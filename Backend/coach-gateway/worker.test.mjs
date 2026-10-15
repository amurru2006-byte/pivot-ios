import test from 'node:test';
import assert from 'node:assert/strict';
import { handle, tokenDigest, validRequest, quotaRetrySeconds } from './worker.mjs';

// Synthetic data and fake provider: these tests do not prove model quality.
const token = 'a'.repeat(43);
const now = Date.parse('2026-10-08T12:00:00+02:00');
const clock = () => now;
const fixture = () => ({ version:1, requestID:'12345678-1234-1234-1234-123456789012',
  now:new Date(now).toISOString(), dayKey:'2026-10-08', message:'Pranzo poi palestra',
  events:[{ id:'e0',kind:'meal',category:'lunch',status:'pending',
    start:'2026-10-08T11:00:00+02:00',end:'2026-10-08T11:45:00+02:00',durationMinutes:45,flexibility:'compressible',travelConfirmed:true }],
  history:[{role:'user',text:'Mi sono svegliato a mezzogiorno'}], memories:[] });
const answer = () => ({ version:1,requestID:fixture().requestID,mode:'plan',eventIDs:['e0'],
  reply:'Posso proporti una soluzione per queste attività. Verifichiamo gli spazi disponibili: nessun evento è stato modificato.' });
const environment = async () => ({ GROQ_API_KEY:'synthetic-provider-secret',
  PIVOT_CLIENT_TOKEN_SHA256:await tokenDigest(token),PRIVACY_READY:'zdr-confirmed',
  PIVOT_RATE_LIMITER:{ limit:async () => ({success:true}) } });
function request(body = fixture(), headers = {}, url = 'https://example.test/v1/coach') {
  return new Request(url, {method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json',...headers},
    body: typeof body === 'string' ? body : JSON.stringify(body)});
}
const providerAnswer = () => ({mode:answer().mode,eventIDs:answer().eventIDs,reply:answer().reply});
function upstream(value = providerAnswer(), finish = 'stop') {
  return Response.json({choices:[{finish_reason:finish,message:{content:JSON.stringify(value)}}]});
}
const forbidden = async () => { throw new Error('provider should not be called'); };

test('bounded rejected-request diagnostics return only allowlisted machine classes, never prompts', async () => {
  for (const [code,expected] of [['json_validate_failed','provider_output_schema_rejected'],
                               ['context_length_exceeded','provider_context_rejected'],['private-code-sentinel',null]]) {
    let calls=0;
    const response=await handle(request(),await environment(),{clock,fetchProvider:async()=>{
      calls++; return Response.json({error:{code,message:'private-key-sentinel',failed_generation:'private-prompt-sentinel'}},{status:400});
    }});
    assert.equal(response.status,502); assert.equal(calls,1);
    assert.equal(response.headers.get('X-Pivot-Failure-Class'),expected);
    assert.deepEqual(await response.json(),{error:'provider_request_rejected'});
    assert.equal(JSON.stringify([...response.headers]).includes('sentinel'),false);
  }
});
test('oversized or malformed rejected-request error bodies cannot escape the fixed error response', async () => {
  for (const body of ['x'.repeat(8193),'{malformed']) {
    const response=await handle(request(),await environment(),{clock,fetchProvider:async()=>new Response(body,{status:400})});
    assert.equal(response.status,502); assert.equal(response.headers.get('X-Pivot-Failure-Class'),null);
    assert.deepEqual(await response.json(),{error:'provider_request_rejected'});
  }
});

test('authenticated request uses fixed provider/model, strict schema and no-store', async () => {
  let calls=0;
  const env = await environment();
  const response = await handle(request(),env,{clock, fetchProvider:async (url,init) => {
    calls++;
    assert.equal(url,'https://api.groq.com/openai/v1/chat/completions');
    assert.equal(init.headers.Authorization,`Bearer ${env.GROQ_API_KEY}`);
    const sent = JSON.parse(init.body);
    assert.equal(sent.model,'openai/gpt-oss-120b');
    assert.equal(sent.stream,false);
    assert.equal(sent.temperature,0);
    assert.equal(init.redirect,'manual');
    assert.equal(sent.response_format.json_schema.strict,true);
    assert.equal(sent.response_format.json_schema.schema.additionalProperties,false);
    assert.deepEqual(sent.response_format.json_schema.schema.required,['mode','eventIDs','reply']);
    assert.equal(Object.hasOwn(JSON.parse(sent.messages[1].content),'requestID'),false);
    assert.equal(JSON.parse(sent.messages[1].content).history[0].text,fixture().history[0].text);
    assert.equal(Object.hasOwn(sent,'tools'),false);
    return upstream();
  }});
  assert.equal(response.status,200);
  assert.deepEqual(await response.json(),answer());
  assert.equal(response.headers.get('Cache-Control'),'no-store');
  assert.equal(calls,1);
});
test('authentication and verified privacy configuration are required before provider access', async () => {
  for (const [change,headers,status] of [
    [{PRIVACY_READY:undefined},{},503], [{GROQ_API_KEY:undefined},{},503],
    [{PIVOT_CLIENT_TOKEN_SHA256:undefined},{},503], [{PIVOT_RATE_LIMITER:undefined},{},503],
    [{},{Authorization:'Bearer invalid'},401], [{},{Authorization:`Bearer ${'b'.repeat(43)}`},401]
  ]) {
    const response = await handle(request(fixture(),headers),{...await environment(),...change},{clock,fetchProvider:forbidden});
    assert.equal(response.status,status);
  }
});
test('forbidden fields, metadata leaks, stale contexts and malformed requests are rejected', async () => {
  const modifications = [
    x => x.providerURL='https://untrusted.test', x => x.model='paid-model', x => x.health={sleep:8},
    x => x.events[0].title='private title', x => x.events[0].notes='private notes',
    x => x.history[0].role='system', x => x.events.push({...x.events[0]}),
    x => x.events[0].durationMinutes=999, x => x.dayKey='2026-10-07',
    x => x.now=new Date(now-121_000).toISOString(), x => x.events[0].category='gym',
    x => x.message=' ', x => x.version=true, x => x.memories=Array(5).fill('memory')
  ];
  for (const modify of modifications) {
    const value = fixture(); modify(value);
    const response = await handle(request(value),await environment(),{clock,fetchProvider:forbidden});
    assert.equal(response.status,400,JSON.stringify(value));
  }
  assert.equal((await handle(request('{bad'),await environment(),{clock,fetchProvider:forbidden})).status,400);
});
test('actual body size is bounded even without Content-Length', async () => {
  const response = await handle(request('x'.repeat(24_001)),await environment(),{clock,fetchProvider:forbidden});
  assert.equal(response.status,413);
  assert.equal((await handle(request(fixture(),{'Content-Type':'text/plain'}),await environment(),{clock,fetchProvider:forbidden})).status,415);
});
test('rate limit exhaustion and binding outage cannot contact provider', async () => {
  for (const [limit,status] of [[async () => ({success:false}),429],[async () => {throw new Error('unavailable');},503]]) {
    const env = await environment(); env.PIVOT_RATE_LIMITER.limit=limit;
    assert.equal((await handle(request(),env,{clock,fetchProvider:forbidden})).status,status);
  }
});
test('quota, upstream failure and exceptions never echo secrets or retry', async () => {
  for (const status of [429,500,401]) {
    let calls=0;
    const response = await handle(request(),await environment(),{clock,fetchProvider:async () => {
      calls++; return new Response('private prompt synthetic-provider-secret',{status});
    }});
    assert.equal(response.status,status === 429 ? 429 : 502);
    assert.equal((await response.text()).includes('private'),false);
    assert.equal(calls,1);
  }
  const response = await handle(request(),await environment(),{clock,fetchProvider:async () => {throw new Error('secret');}});
  assert.equal(response.status,502);
  assert.equal((await response.text()).includes('secret'),false);
});
test('unknown IDs, duplicate IDs, extra fields, wrong request ID and truncated responses fail closed', async () => {
  for (const change of [
    {eventIDs:['e99']},{eventIDs:['e0','e0']},{mode:'conversation'},{requestID:'old'},
    {version:true},{reply:' '},{proposedStart:'18:00'}
  ]) {
    const response = await handle(request(),await environment(),{clock,fetchProvider:async () => upstream({...providerAnswer(),...change})});
    assert.equal(response.status,502);
  }
  assert.equal((await handle(request(),await environment(),{clock,fetchProvider:async () => upstream(providerAnswer(),'length')})).status,502);
  assert.equal((await handle(request(),await environment(),{clock,fetchProvider:async () => new Response('x'.repeat(32_001))})).status,502);
});
test('non-eligible event cannot become a plan; conversation needs no activity', async () => {
  const body = fixture(); body.events[0].category='other';
  assert.equal((await handle(request(body),await environment(),{clock,fetchProvider:async () => upstream()})).status,502);
  body.events=[];
  const value = {...providerAnswer(),mode:'conversation',eventIDs:[]};
  const response = await handle(request(body),await environment(),{clock,fetchProvider:async () => upstream(value)});
  assert.equal(response.status,200);
});
test('endpoint rejects unapproved paths, insecure transport and non-POST methods', async () => {
  for (const url of ['https://example.test/','https://example.test/v1/coach?model=x','http://example.test/v1/coach']) {
    assert.equal((await handle(request(fixture(),{},url),await environment(),{clock,fetchProvider:forbidden})).status,404);
  }
  assert.equal((await handle(new Request('https://example.test/v1/coach'),await environment(),{clock,fetchProvider:forbidden})).status,405);
});
test('Rome day key handles midnight and daylight saving independently of server timezone', () => {
  const body=fixture(); body.now='2026-10-07T22:30:00Z';
  assert.equal(validRequest(body,Date.parse(body.now)),true);
  body.dayKey='2026-10-07';
  assert.equal(validRequest(body,Date.parse(body.now)),false);
});

test('provider quota preserves a five-hour timer without returning its private error body', async () => {
  let calls = 0;
  const response = await handle(request(),await environment(),{clock,fetchProvider:async () => {
    calls++; return new Response('private calendar and secret key',{status:429,headers:{'Retry-After':'18000'}});
  }});
  assert.equal(response.status,429);
  assert.deepEqual(await response.json(),{error:'quota_unavailable',retryAfterSeconds:18000,retryAt:new Date(now+18_000_000).toISOString()});
  assert.equal(response.headers.get('Retry-After'),'18000'); assert.equal(calls,1);
});
test('only exhausted buckets affect the reported wait and compound reset values are supported', () => {
  assert.equal(quotaRetrySeconds(new Headers({'x-ratelimit-remaining-requests':'100','x-ratelimit-reset-requests':'23h',
    'x-ratelimit-remaining-tokens':'0','x-ratelimit-reset-tokens':'7m6.5s'}),now),427);
  assert.equal(quotaRetrySeconds(new Headers({'retry-after':'5','x-ratelimit-remaining-requests':'0','x-ratelimit-reset-requests':'2h30m',
    'x-ratelimit-remaining-tokens':'0','x-ratelimit-reset-tokens':'45s'}),now),9000);
});
test('missing or malformed timing stays unknown rather than inventing a reset time', async () => {
  for(const headers of [{},{'retry-after':'later'},{'retry-after':'Infinity'},{'retry-after':'-10'},
    {'retry-after':'9999999999'},{'x-ratelimit-reset-requests':'24h'},
    {'x-ratelimit-remaining-tokens':'0','x-ratelimit-reset-tokens':'10minutes'}]) {
    assert.equal(quotaRetrySeconds(new Headers(headers),now),null);
  }
  const response = await handle(request(),await environment(),{clock,fetchProvider:async () => new Response('secret',{status:429})});
  assert.deepEqual(await response.json(),{error:'quota_unavailable',retryAfterSeconds:null,retryAt:null});
  assert.equal(response.headers.has('Retry-After'),false);
});
test('HTTP date Retry-After is bounded and expired dates are not new credits', () => {
  assert.equal(quotaRetrySeconds(new Headers({'retry-after':new Date(now+60_000).toUTCString()}),now),60);
  assert.equal(quotaRetrySeconds(new Headers({'retry-after':new Date(now-60_000).toUTCString()}),now),null);
});
test('local limiter provides its own retry window without calling the AI provider', async () => {
  const env=await environment(); env.PIVOT_RATE_LIMITER.limit=async () => ({success:false});
  const response=await handle(request(),env,{clock,fetchProvider:forbidden});
  assert.deepEqual(await response.json(),{error:'rate_limited',retryAfterSeconds:60,retryAt:new Date(now+60_000).toISOString()});
});
test('response and request diagnostics never expose provider secrets or raw exceptions', async () => {
  const response=await handle(request(),await environment(),{clock,fetchProvider:async () => {
    throw new Error('provider-secret-private-input');
  }});
  assert.deepEqual(await response.json(),{error:'provider_unavailable'});
  assert.equal(response.headers.get('Cache-Control'),'no-store');
});

test('provider rejection diagnostics are closed HTTP-status codes, not error bodies', async () => {
  for(const [status,code] of [[400,'provider_request_rejected'],[422,'provider_request_rejected'],
    [401,'provider_credentials_rejected'],[403,'provider_access_denied'],
    [404,'provider_endpoint_unavailable'],[500,'provider_internal_error'],[503,'provider_capacity_unavailable']]) {
    let calls=0;
    const response=await handle(request(),await environment(),{clock,fetchProvider:async () => {
      calls++; return new Response('private-calendar provider-secret invented-status',{status});
    }});
    assert.equal(response.status,502);
    assert.deepEqual(await response.json(),{error:code});
    assert.equal(response.headers.get('Cache-Control'),'no-store');
    assert.equal(calls,1);
  }
});

test('transport and JSON failures expose only closed categories, never exception messages', async () => {
  for(const [error,code] of [[new TypeError('private-secret'),'provider_transport_failed'],
    [new SyntaxError('private-secret'),'invalid_response'],[new Error('private-secret'),'provider_unavailable']]) {
    const response=await handle(request(),await environment(),{clock,fetchProvider:async()=>{throw error;}});
    assert.equal(response.status,502);
    assert.deepEqual(await response.json(),{error:code});
  }
});

test('default provider fetch preserves its native global receiver', async () => {
  const original=globalThis.fetch;
  let calls=0;
  globalThis.fetch=async function(url,init) {
    assert.equal(this,globalThis);
    assert.equal(url,'https://api.groq.com/openai/v1/chat/completions');
    assert.equal(init.redirect,'manual');
    calls++;
    return upstream();
  };
  try {
    const response=await handle(request(),await environment(),{clock});
    assert.equal(response.status,200);
    assert.deepEqual(await response.json(),answer());
    assert.equal(calls,1);
  } finally { globalThis.fetch=original; }
});

test('provider redirects never forward authorization or prompt to their destination', async () => {
  for(const status of [301,302,303,307,308]) {
    let calls=0;
    const response=await handle(request(),await environment(),{clock,fetchProvider:async(url,init)=>{
      calls++; assert.equal(url,'https://api.groq.com/openai/v1/chat/completions');
      assert.equal(init.redirect,'manual');
      return new Response('private-secret',{status,headers:{Location:'https://untrusted.test/secret'}});
    }});
    assert.equal(response.status,502);
    assert.deepEqual(await response.json(),{error:'provider_redirect_rejected'});
    assert.equal(response.headers.has('Location'),false);
    assert.equal(calls,1);
  }
});

test('a valid model plan cannot claim Calendar changes or present unverified times', async () => {
  const response=await handle(request(),await environment(),{clock,fetchProvider:async()=>upstream({
    ...providerAnswer(),reply:'Ho spostato e salvato tutto nel Calendario alle 18:00.'
  })});
  assert.equal(response.status,200);
  assert.deepEqual(await response.json(),answer());
});

test('provider key whitespace is normalized and invalid header characters fail before provider calls', async () => {
  const env=await environment(); env.GROQ_API_KEY=`  ${env.GROQ_API_KEY}\n`;
  const response=await handle(request(),env,{clock,fetchProvider:async(_,init)=>{
    assert.equal(init.headers.Authorization,'Bearer synthetic-provider-secret'); return upstream();
  }});
  assert.equal(response.status,200);
  for(const key of ['short','synthetic secret with spaces','private\r\nsecret-value-rejected']) {
    env.GROQ_API_KEY=key;
    const rejected=await handle(request(),env,{clock,fetchProvider:forbidden});
    assert.equal(rejected.status,503);
    assert.deepEqual(await rejected.json(),{error:'provider_key_format_invalid'});
  }
});

test('server binds each response identity and rejects provider-authored identity fields', async () => {
  const body=fixture(); body.requestID='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const response=await handle(request(body),await environment(),{clock,fetchProvider:async()=>upstream()});
  assert.equal(response.status,200); assert.equal((await response.json()).requestID,body.requestID);
  for(const extra of [{requestID:body.requestID},{version:1}]) {
    const rejected=await handle(request(body),await environment(),{clock,fetchProvider:async()=>upstream({...providerAnswer(),...extra})});
    assert.equal(rejected.status,502); assert.equal(rejected.headers.get('X-Pivot-Failure-Class'),'response_fields');
  }
});
