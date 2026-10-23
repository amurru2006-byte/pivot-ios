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

test('v2 creates only a bounded draft and replaces claims of applied changes', async () => {
  const body={...fixture(),version:2,purpose:'conversation',message:'Crea una chiamata di prova dalle22 a mezzanotte oggi'};
  const generated={mode:'create',eventIDs:[],reply:'Ho creato tutto',rewrittenMessage:null,
    draft:{title:'Chiamata di prova',start:'2026-10-08T22:00:00+02:00',end:'2026-10-09T00:00:00+02:00',calendarHint:'Personale',notes:'',endEstimated:false}};
  const response=await handle(request(body),await environment(),{clock,fetchProvider:async(url,init)=>{
    const sent=JSON.parse(init.body);
    assert.equal(sent.response_format.json_schema.name,'pivot_coach_v2');
    assert.equal(sent.response_format.json_schema.strict,true);
    return upstream(generated);
  }});
  assert.equal(response.status,200);
  const value=await response.json();
  assert.equal(value.version,2); assert.equal(value.draft.title,'Chiamata di prova');
  assert.match(value.reply,/nessun evento è stato creato/);
  assert.equal(Date.parse(value.draft.end)-Date.parse(value.draft.start),7200000);
});

test('v2 rewrite accepts long text but cannot create calendar actions', async () => {
  const body={...fixture(),version:2,purpose:'rewrite',message:'Devo studiare e cucinare. '.repeat(200),events:[],history:[]};
  assert.equal(validRequest(body,now),true);
  const generated={mode:'rewrite',eventIDs:[],reply:'Controlla il testo',draft:null,rewrittenMessage:body.message};
  const response=await handle(request(body),await environment(),{clock,fetchProvider:async()=>upstream(generated)});
  assert.equal(response.status,200); assert.equal((await response.json()).rewrittenMessage,body.message);
  for(const change of [{mode:'conversation'},{eventIDs:['e0']},{draft:{}},{rewrittenMessage:null}]) {
    const failed=await handle(request(body),await environment(),{clock,fetchProvider:async()=>upstream({...generated,...change})});
    assert.equal(failed.status,502);
  }
});

const fixtureV3 = () => ({...fixture(),version:3,purpose:'conversation',draftContext:[],references:[],historyOmittedCount:0});
const deletion = (eventID='e0') => ({kind:'delete',eventID,title:null,start:null,end:null,notes:null});
const responseV3 = () => ({mode:'actions',eventIDs:[],reply:'Ho cancellato tutto',draft:null,rewrittenMessage:null,actions:[deletion()]});

const fixtureV4 = () => ({...fixtureV3(),version:4,planningContext:[]});
const planningV4 = () => ({eventIDs:['e0'],allowedDayOffsets:[1],excludedDayOffsets:[2],band:'afternoon',earliestMinute:null,latestMinute:null,afterEventID:null});
const contextV4 = (intent=planningV4()) => ({anchor:fixture().now,intent});
const responseV4 = () => ({mode:'recover',eventIDs:[],reply:'Ho già spostato tutto alle18',draft:null,rewrittenMessage:null,actions:[],planning:planningV4()});

test('v4 interprets only bounded planning constraints with one call and no new provider tools', async () => {
  const body=fixtureV4(); body.planningContext=[contextV4()]; let calls=0;
  const response=await handle(request(body),await environment(),{clock,fetchProvider:async(url,init)=>{
    calls++; const sent=JSON.parse(init.body), dto=JSON.parse(sent.messages[1].content);
    assert.equal(sent.response_format.json_schema.name,'pivot_coach_v4');
    assert.equal(sent.response_format.json_schema.strict,true); assert.equal(Object.hasOwn(sent,'tools'),false);
    assert.equal(sent.model,'openai/gpt-oss-120b'); assert.equal(sent.max_completion_tokens,2400);
    assert.deepEqual(sent.response_format.json_schema.schema.required,['mode','eventIDs','reply','draft','rewrittenMessage','actions','planning']);
    assert.deepEqual(dto.planningContext,body.planningContext);
    assert.deepEqual(Object.keys(dto.planningContext[0]).sort(),['anchor','intent']);
    assert.deepEqual(Object.keys(dto.planningContext[0].intent).sort(),Object.keys(planningV4()).sort());
    assert.equal(Object.hasOwn(dto,'requestID'),false);
    return upstream(responseV4());
  }});
  assert.equal(response.status,200); assert.equal(calls,1);
  const result=await response.json(); assert.equal(result.version,4); assert.equal(result.requestID,body.requestID);
  assert.deepEqual(result.planning,planningV4()); assert.deepEqual(result.eventIDs,[]); assert.deepEqual(result.actions,[]);
  assert.equal(result.reply.includes('alle18'),false); assert.equal(result.reply.includes('nessun evento è stato spostato'),true);
});

test('v4 request context rejects private fields unknown aliases duplicate targets and contradictory days before provider', async () => {
  const changes=[x=>x.planningContext=[{...contextV4(),nativeID:'private'}],
    x=>x.planningContext=[contextV4({...planningV4(),eventIDs:['e99']})],x=>x.planningContext=[contextV4(),contextV4()],
    x=>x.planningContext=[contextV4({...planningV4(),eventIDs:['e0','e0']})],
    x=>x.planningContext=[contextV4({...planningV4(),excludedDayOffsets:[1]})],x=>x.planningContext=[contextV4({...planningV4(),allowedDayOffsets:[7]})],
    x=>x.planningContext=[contextV4({...planningV4(),allowedDayOffsets:[]})],x=>x.planningContext=[contextV4({...planningV4(),earliestMinute:true})],
    x=>x.planningContext=[contextV4({...planningV4(),latestMinute:600})],x=>x.planningContext=[contextV4({...planningV4(),afterEventID:'e0'})],
    x=>x.planningContext=[{...contextV4(),anchor:new Date(now+1000).toISOString()}],
    x=>x.planningContext=[{...contextV4(),anchor:new Date(now-9*86400_000).toISOString()}],
    x=>x.planningContext=[{...contextV4(),anchor:'2026-10-08'}],
    x=>x.events[0].id='e48',x=>x.purpose='rewrite',x=>delete x.planningContext];
  for(const change of changes) {
    const body=fixtureV4(); change(body);
    assert.equal(validRequest(body,now),false);
    assert.equal((await handle(request(body),await environment(),{clock,fetchProvider:forbidden})).status,400);
  }
});

test('v4 original request bytes reject duplicate fields even with Unicode escaping inside context arrays', async () => {
  const body=fixtureV4();body.planningContext=[contextV4()];const raw=JSON.stringify(body);
  for(const value of [raw.replace('"version":4','"version":4,"version":4'),
    raw.replace('"allowedDayOffsets":[1]','"allowedDayOffsets":[1],"allowedDayOff\\u0073ets":[1]')]) {
    assert.notEqual(value,raw);
    assert.equal((await handle(request(value),await environment(),{clock,fetchProvider:forbidden})).status,400);
  }
});

test('v4 provider output rejects duplicate original keys instead of accepting collapsed planner fields', async () => {
  const raw=JSON.stringify(responseV4());
  for(const value of [raw.replace('"mode":"recover"','"mode":"conversation","mode":"recover"'),
    raw.replace('"eventIDs":["e0"]','"eventIDs":["e0"],"event\\u0049Ds":["e0"]'),
    raw.replace('"planning":','"planning":null,"planning":')]) {
    assert.notEqual(value,raw);
    const response=await handle(request(fixtureV4()),await environment(),{clock,fetchProvider:async()=>Response.json({choices:[{finish_reason:'stop',message:{content:value}}]})});
    assert.equal(response.status,502);assert.deepEqual(await response.json(),{error:'invalid_response'});
  }
});

test('v4 response rejects unsupported metadata invalid intent and hidden actions across modes', async () => {
  const values=[{...responseV4(),planning:{...planningV4(),location:'private'}},
    {...responseV4(),planning:{...planningV4(),eventIDs:['e99']}},{...responseV4(),planning:null},
    {...responseV4(),planning:{...planningV4(),allowedDayOffsets:[true]}},
    {...responseV4(),planning:{...planningV4(),earliestMinute:Number.MAX_SAFE_INTEGER}},
    {...responseV4(),planning:{...planningV4(),afterEventID:'e0'}},
    {...responseV4(),actions:[deletion()]},{...responseV4(),eventIDs:['e0']},
    {...responseV4(),mode:'conversation'},{...responseV4(),mode:'plan',eventIDs:['e0']},
    {...responseV4(),draft:{title:'hidden',start:null,end:null,calendarHint:null,notes:'',endEstimated:false}}];
  for(const value of values) {
    const response=await handle(request(fixtureV4()),await environment(),{clock,fetchProvider:async()=>upstream(value)});
    assert.equal(response.status,502,JSON.stringify(value));
  }
});

test('v4 keeps conversation and explicit edits while v3 still rejects recovery and planning fields', async () => {
  for(const value of [{...responseV4(),mode:'conversation',planning:null}, {...responseV3(),planning:null}]) {
    assert.equal((await handle(request(fixtureV4()),await environment(),{clock,fetchProvider:async()=>upstream(value)})).status,200);
  }
  assert.equal((await handle(request(fixtureV3()),await environment(),{clock,fetchProvider:async()=>upstream(responseV4())})).status,502);
  const old={...fixtureV3(),planningContext:[]};
  assert.equal((await handle(request(old),await environment(),{clock,fetchProvider:forbidden})).status,400);
});

test('v4 integrity bound rejects excessive nested response depth without exposing raw output', async () => {
  const raw='{"a":'+ '['.repeat(33)+'0'+']'.repeat(33)+'}';
  const response=await handle(request(fixtureV4()),await environment(),{clock,fetchProvider:async()=>Response.json({choices:[{finish_reason:'stop',message:{content:raw}}]})});
  assert.equal(response.status,502); assert.deepEqual(await response.json(),{error:'invalid_response'});
});

test('v4 preserves the original context date anchor instead of rebasing yesterday constraints to today', async () => {
  const body=fixtureV4(), anchor=new Date(now-86400_000).toISOString();
  body.planningContext=[{anchor,intent:planningV4()}];
  const response=await handle(request(body),await environment(),{clock,fetchProvider:async(url,init)=>{
    const sent=JSON.parse(init.body), dto=JSON.parse(sent.messages[1].content);
    assert.equal(dto.planningContext[0].anchor,anchor);
    assert.deepEqual(dto.planningContext[0].intent.allowedDayOffsets,[1]);
    assert.equal(dto.now,body.now); assert.notEqual(dto.now,anchor);
    return upstream(responseV4());
  }});
  assert.equal(response.status,200);
});

test('v3 passes whole earlier turns and partial draft facts without calendar metadata', async () => {
  const body=fixtureV3();
  body.history=[{role:'user',text:'Dettagli già forniti. '.repeat(30)+'dalle11:50 alle19:35'}];
  body.draftContext=[{title:'Attività di prova',start:'2026-10-08T11:50:00+02:00',end:null,calendarHint:null,notes:'',endEstimated:false}];
  body.message='La fine è alle19:35, come ti dicevo'; body.historyOmittedCount=2;
  assert.equal(validRequest(body,now),true);
  const generated={...responseV3(),mode:'create',actions:[],draft:{...body.draftContext[0],end:'2026-10-08T19:35:00+02:00'}};
  const response=await handle(request(body),await environment(),{clock,fetchProvider:async(_,init)=>{
    const sent=JSON.parse(init.body), context=JSON.parse(sent.messages[1].content);
    assert.equal(sent.response_format.json_schema.name,'pivot_coach_v3');
    assert.deepEqual(context.draftContext,body.draftContext); assert.deepEqual(context.history,body.history);
    assert.equal(context.historyOmittedCount,2); assert.equal(Object.hasOwn(context.events[0],'title'),false);
    assert.match(sent.messages[0].content,/Non richiedere tutto da capo|non richiedere tutto da capo/);
    return upstream(generated);
  }});
  assert.equal(response.status,200); assert.equal((await response.json()).draft.end,generated.draft.end);
});

test('v3 deletion is only an alias-bound proposal and provider claims are replaced', async () => {
  const response=await handle(request(fixtureV3()),await environment(),{clock,fetchProvider:async()=>upstream(responseV3())});
  assert.equal(response.status,200); const value=await response.json();
  assert.equal(value.version,3); assert.deepEqual(value.actions,[deletion()]);
  assert.match(value.reply,/non è ancora cambiato/); assert.doesNotMatch(value.reply,/Ho cancellato/);
});

test('v3 rejects unknown aliases duplicate targets malformed deletes and no-op patches', async () => {
  const malformed=[ [deletion('external-calendar-id')], [deletion(),deletion()], [{...deletion(),title:'non-null'}],
    [{...deletion(),kind:'update'}], [null], Array(11).fill(deletion()), [{...deletion(),calendarID:'private'}] ];
  for(const actions of malformed) {
    const response=await handle(request(fixtureV3()),await environment(),{clock,fetchProvider:async()=>upstream({...responseV3(),actions})});
    assert.equal(response.status,502); assert.deepEqual(await response.json(),{error:'invalid_response'});
  }
});

test('v3 update preserves omitted patch values and rejects invalid time pairs', async () => {
  const action={kind:'update',eventID:'e0',title:'Titolo nuovo',start:'2026-10-08T09:00:00+02:00',end:'2026-10-08T10:00:00+02:00',notes:null};
  const body=fixtureV3();
  const valid=await handle(request(body),await environment(),{clock,fetchProvider:async()=>upstream({...responseV3(),actions:[action]})});
  assert.equal(valid.status,200); assert.equal((await valid.json()).actions[0].notes,null);
  for(const patch of [{end:null},{end:action.start},{end:'2026-10-10T10:00:00+02:00'},{kind:'replace'}]) {
    const response=await handle(request(body),await environment(),{clock,fetchProvider:async()=>upstream({...responseV3(),actions:[{...action,...patch}]})});
    assert.equal(response.status,502);
  }
});

test('v3 clarification may retain incomplete draft but cannot carry hidden actions', async () => {
  const draft={title:'',start:'2026-10-08T10:00:00+02:00',end:null,calendarHint:null,notes:'lista di prova',endEstimated:false};
  const generated={...responseV3(),mode:'clarify',reply:'Quale titolo vuoi usare?',actions:[],draft};
  const response=await handle(request(fixtureV3()),await environment(),{clock,fetchProvider:async()=>upstream(generated)});
  assert.equal(response.status,200); assert.deepEqual((await response.json()).draft,draft);
  const rejected=await handle(request(fixtureV3()),await environment(),{clock,fetchProvider:async()=>upstream({...generated,actions:[deletion()]})});
  assert.equal(rejected.status,502);
});

test('v3 expanded context is still strict bounded and cannot carry raw calendar fields', async () => {
  const changes=[x=>x.draftContext.push({title:'bad'}), x=>x.history=Array(21).fill({role:'user',text:'test'}),
    x=>x.history[0].text='x'.repeat(12001), x=>x.references=['e99'], x=>x.references=['e0','e0'],
    x=>x.historyOmittedCount=-1, x=>x.events[0].title='private', x=>x.draftContext.push(null)];
  for(const change of changes) { const body=fixtureV3(); change(body); assert.equal(validRequest(body,now),false); }
  const oversized=fixtureV3(); oversized.history=Array(20).fill({role:'user',text:'x'.repeat(2000)});
  const response=await handle(request(oversized),await environment(),{clock,fetchProvider:forbidden});
  assert.equal(response.status,413);
});

test('v3 opt-in preferences stay bounded user data and cannot introduce provider tools or identities', async () => {
  const body = fixtureV3();
  body.memories = ['Preferisco la sera', 'Evita due appuntamenti senza margine'];
  let calls = 0;
  const response = await handle(request(body), await environment(), {clock, fetchProvider:async (_url, init) => {
    calls++;
    const payload = JSON.parse(init.body);
    assert.deepEqual(JSON.parse(payload.messages[1].content).memories, body.memories);
    assert.equal(payload.messages[1].role, 'user');
    assert.equal(payload.messages.length, 2);
    assert.equal(Object.hasOwn(payload, 'tools'), false);
    assert.equal(Object.hasOwn(payload, 'tool_choice'), false);
    return upstream({...responseV3(),mode:'conversation',actions:[],eventIDs:[],draft:null});
  }});
  assert.equal(response.status,200); assert.equal(calls,1);
  for (const memories of [Array(5).fill('QA'), ['x'.repeat(241)], ['😀'.repeat(121)], [{text:'QA',calendarID:'private-id'}]]) {
    const rejected = await handle(request({...body,memories}), await environment(), {clock,fetchProvider:forbidden});
    assert.equal(rejected.status,400);
  }
});

test('v2 rejects malformed drafts, extra capabilities and mixed protocol identities', async () => {
  const body={...fixture(),version:2,purpose:'conversation'};
  const generated={mode:'create',eventIDs:[],reply:'Bozza',rewrittenMessage:null,
    draft:{title:'Prova',start:null,end:null,calendarHint:null,notes:'',endEstimated:false}};
  for(const draft of [{...generated.draft,execute:true},{...generated.draft,start:'not a date'},
    {...generated.draft,notes:'x'.repeat(3001)},{...generated.draft,calendarHint:77}]) {
    const response=await handle(request(body),await environment(),{clock,fetchProvider:async()=>upstream({...generated,draft})});
    assert.equal(response.status,502);
  }
  assert.equal(validRequest({...body,purpose:'execute'},now),false);
  assert.equal(validRequest({...fixture(),purpose:'conversation'},now),false);
  assert.equal(validRequest({...body,message:'x'.repeat(12001)},now),false);
});
