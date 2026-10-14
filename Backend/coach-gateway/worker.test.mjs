import test from 'node:test';
import assert from 'node:assert/strict';
import { handle, tokenDigest, validRequest } from './worker.mjs';

// Synthetic data and fake provider: these tests do not prove model quality.
const token = 'a'.repeat(43);
const now = Date.parse('2026-10-08T12:00:00+02:00');
const clock = () => now;
const fixture = () => ({ version:1, requestID:'12345678-1234-1234-1234-123456789012',
  now:new Date(now).toISOString(), dayKey:'2026-10-08', message:'Pranzo poi palestra',
  events:[{ id:'e0',kind:'meal',category:'lunch',status:'pending',
    start:'2026-10-08T11:00:00+02:00',end:'2026-10-08T11:45:00+02:00',durationMinutes:45,flexibility:'compressible',travelConfirmed:true }],
  history:[{role:'user',text:'Mi sono svegliato a mezzogiorno'}], memories:[] });
const answer = () => ({ version:1,requestID:fixture().requestID,mode:'plan',eventIDs:['e0'],reply:'Prepariamo il pranzo' });
const environment = async () => ({ GROQ_API_KEY:'synthetic-provider-secret',
  PIVOT_CLIENT_TOKEN_SHA256:await tokenDigest(token),PRIVACY_READY:'zdr-confirmed',
  PIVOT_RATE_LIMITER:{ limit:async () => ({success:true}) } });
function request(body = fixture(), headers = {}, url = 'https://example.test/v1/coach') {
  return new Request(url, {method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json',...headers},
    body: typeof body === 'string' ? body : JSON.stringify(body)});
}
function upstream(value = answer(), finish = 'stop') {
  return Response.json({choices:[{finish_reason:finish,message:{content:JSON.stringify(value)}}]});
}
const forbidden = async () => { throw new Error('provider should not be called'); };

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
    assert.equal(sent.response_format.json_schema.strict,true);
    assert.equal(sent.response_format.json_schema.schema.additionalProperties,false);
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
    const response = await handle(request(),await environment(),{clock,fetchProvider:async () => upstream({...answer(),...change})});
    assert.equal(response.status,502);
  }
  assert.equal((await handle(request(),await environment(),{clock,fetchProvider:async () => upstream(answer(),'length')})).status,502);
  assert.equal((await handle(request(),await environment(),{clock,fetchProvider:async () => new Response('x'.repeat(32_001))})).status,502);
});
test('non-eligible event cannot become a plan; conversation needs no activity', async () => {
  const body = fixture(); body.events[0].category='other';
  assert.equal((await handle(request(body),await environment(),{clock,fetchProvider:async () => upstream()})).status,502);
  body.events=[];
  const value = {...answer(),mode:'conversation',eventIDs:[]};
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
