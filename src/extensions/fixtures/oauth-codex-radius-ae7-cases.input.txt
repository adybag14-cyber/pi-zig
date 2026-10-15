// Identical owned input for immutable ae7 Source and native QuickJS façades.
// Every HTTP effect is an explicit fake; no provider endpoint can be reached.
export const caseIds = [
  'metadata','codex-toAuth-identity','radius-toAuth-identity','codex-refresh-getter-sync',
  'radius-refresh-getter-async','codex-unknown-method','radius-name-is-live',
  'codex-refresh-success','codex-refresh-missing-fields','codex-refresh-null',
  'codex-refresh-account-missing','codex-refresh-malformed-jwt','codex-refresh-http',
  'codex-refresh-text-reject','codex-refresh-fetch-error','codex-refresh-fetch-value',
  'radius-refresh-success','radius-refresh-unvalidated-fields','radius-refresh-json-null',
  'radius-refresh-json-error','radius-refresh-text-error','radius-refresh-null-error',
  'radius-refresh-fetch-identity','radius-refresh-cancellation','codex-device-success',
  'codex-device-not-enabled','codex-device-invalid-interval','codex-device-poll-error',
  'radius-device-success','radius-device-invalid','radius-device-expired','radius-device-denied',
  'radius-device-error-brand','radius-discovery-invalid','radius-discovery-http',
];
export async function runOAuthCases(codex, createRadius) {
  const output = [], requests = [], notices = [];
  const previousFetch = globalThis.fetch, originalNow = Date.now;
  const now = 1700000000000;
  Date.now = () => now;
  const jwt = 'e30.' + btoa(JSON.stringify({'https://api.openai.com/auth':{chatgpt_account_id:'account-1'}})) + '.sig';
  const valid = {access_token:jwt,refresh_token:'refresh-2',expires_in:120};
  const abort = new AbortController();
  let queue = [];
  const response = (json, status=200, text) => ({
    ok:status>=200&&status<300,status,statusText:status===401?'Unauthorized':'Fixture',
    async json(){if(json instanceof Error)throw json;return json},
    async text(){if(text instanceof Error)throw text;return text===undefined?JSON.stringify(json):text},
  });
  const error = e => ({name:e?.name,message:e?.message,constructor:e?.constructor?.name,
    ...(e && Object.hasOwn(e,'status')?{status:e.status}:{}),
    ...(e && Object.hasOwn(e,'oauthError')?{oauthError:e.oauthError??null}:{})});
  const describe = fn => ({name:fn.name,length:fn.length,prototypeName:Object.getPrototypeOf(fn).constructor.name,
    ownPrototype:Object.hasOwn(fn,'prototype'),constructible:(()=>{try{Reflect.construct(function(){},[],fn);return true}catch{return false}})()});
  const snapshot = value => JSON.parse(JSON.stringify(value));
  globalThis.fetch = async (input, init={}) => {
    requests.push({url:String(input),inputKind:typeof input==='string'?'string':input.constructor.name,
      method:init.method??'GET',headers:Object.entries(init.headers??{}),body:init.body===undefined?null:String(init.body),
      bodyKind:init.body?.constructor?.name??null,signalSame:init.signal===abort.signal});
    if(!queue.length)throw Error('Owned HTTP fixture exhausted');
    const next=queue.shift();if(next.throw!==undefined)throw next.throw;
    return next;
  };
  async function record(id, fn) {
    const start=requests.length, noticeStart=notices.length;
    let value;
    try{value={ok:true,value:await fn()}}catch(e){value={ok:false,error:error(e)}}
    output.push({id,...value,requests:requests.slice(start),notices:notices.slice(noticeStart)});
  }
  const radius=createRadius({name:'Radius test',gateway:'gateway.example/base///'});
  const interaction=method=>({signal:abort.signal,prompt:async()=>method,notify:value=>notices.push(snapshot(value))});
  try {
    await record('metadata',()=>({codexKeys:Object.keys(codex),radiusKeys:Object.keys(radius),
      codexName:codex.name,subscription:codex.isSubscription,radiusName:radius.name,
      codex:Object.fromEntries(['login','refresh','toAuth'].map(k=>[k,describe(codex[k])])),
      radius:Object.fromEntries(['login','refresh','toAuth'].map(k=>[k,describe(radius[k])]))}));
    const access={owned:'access'};
    await record('codex-toAuth-identity',async()=>({same:(await codex.toAuth({access})).apiKey===access}));
    await record('radius-toAuth-identity',async()=>({same:(await radius.toAuth({access})).apiKey===access}));
    const sentinel=new Error('credential getter');
    const credential={get refresh(){throw sentinel}};
    await record('codex-refresh-getter-sync',()=>{try{const result=codex.refresh(credential,abort.signal);return{sync:false,promise:result instanceof Promise}}catch(e){return{sync:true,same:e===sentinel}}});
    await record('radius-refresh-getter-async',async()=>{let result;try{result=radius.refresh(credential,abort.signal)}catch(e){return{sync:true,same:e===sentinel}}try{await result;return{unexpected:true}}catch(e){return{sync:false,same:e===sentinel,promise:result instanceof Promise}}});
    await record('codex-unknown-method',()=>codex.login(interaction('bad')));
    const options={name:'First',gateway:'https://gateway.example/'};
    const live=createRadius(options);options.name='Second';
    await record('radius-name-is-live',()=>live.login({signal:abort.signal,notify(){},async prompt(value){notices.push(snapshot(value));return 'bad'}}));
    queue=[response(valid)];await record('codex-refresh-success',()=>codex.refresh({refresh:'r +/=x',unknown:access},abort.signal));
    queue=[response({access_token:'a',expires_in:120})];await record('codex-refresh-missing-fields',()=>codex.refresh({refresh:'r'},abort.signal));
    queue=[response(null)];await record('codex-refresh-null',()=>codex.refresh({refresh:'r'},abort.signal));
    queue=[response({...valid,access_token:'e30.e30.sig'})];await record('codex-refresh-account-missing',()=>codex.refresh({refresh:'r'},abort.signal));
    queue=[response({...valid,access_token:'not-a-jwt'})];await record('codex-refresh-malformed-jwt',()=>codex.refresh({refresh:'r'},abort.signal));
    queue=[response({},401,'raw failure')];await record('codex-refresh-http',()=>codex.refresh({refresh:'r'},abort.signal));
    queue=[response({},401,new Error('body read'))];await record('codex-refresh-text-reject',()=>codex.refresh({refresh:'r'},abort.signal));
    queue=[{throw:new Error('network failure')}];await record('codex-refresh-fetch-error',()=>codex.refresh({refresh:'r'},abort.signal));
    queue=[{throw:'network value'}];await record('codex-refresh-fetch-value',()=>codex.refresh({refresh:'r'},abort.signal));
    queue=[response({access_token:'a',refresh_token:'r',expires_in:120,scope:'gateway offline_access'})];await record('radius-refresh-success',()=>radius.refresh({refresh:'r +/=x',unknown:access},abort.signal));
    queue=[response({access_token:7,expires_in:'2'})];await record('radius-refresh-unvalidated-fields',()=>radius.refresh({refresh:undefined},abort.signal));
    queue=[response(null)];await record('radius-refresh-json-null',()=>radius.refresh({refresh:'r'},abort.signal));
    queue=[response({error:'invalid_client',error_description:'bad'},400)];await record('radius-refresh-json-error',()=>radius.refresh({refresh:'r'},abort.signal));
    queue=[response({},503,'unavailable')];await record('radius-refresh-text-error',()=>radius.refresh({refresh:'r'},abort.signal));
    queue=[response(null,400,'null')];await record('radius-refresh-null-error',()=>radius.refresh({refresh:'r'},abort.signal));
    queue=[{throw:sentinel}];await record('radius-refresh-fetch-identity',async()=>{try{await radius.refresh({refresh:'r'},abort.signal)}catch(e){return{same:e===sentinel}}});
    const cancelled=new AbortController();cancelled.abort();queue=[{throw:sentinel}];await record('radius-refresh-cancellation',()=>radius.refresh({refresh:'r'},cancelled.signal));
    queue=[response({device_auth_id:'device-id',user_code:'CODE',interval:' 0.25 '}),response({authorization_code:'code',code_verifier:'verifier'}),response(valid)];await record('codex-device-success',()=>codex.login(interaction('device_code')));
    queue=[response({},404,'missing')];await record('codex-device-not-enabled',()=>codex.login(interaction('device_code')));
    queue=[response({device_auth_id:'device-id',user_code:'CODE',interval:-1})];await record('codex-device-invalid-interval',()=>codex.login(interaction('device_code')));
    queue=[response({device_auth_id:'device-id',user_code:'CODE',interval:0}),response({error:'bad'},500)];await record('codex-device-poll-error',()=>codex.login(interaction('device_code')));
    queue=[response({device_code:'device-id',user_code:'CODE',verification_uri:'https://owned.example/device',expires_in:900,interval:0}),response({access_token:'a',refresh_token:'r',expires_in:120})];await record('radius-device-success',()=>radius.login(interaction('device-code')));
    queue=[response({device_code:'device-id'})];await record('radius-device-invalid',()=>radius.login(interaction('device-code')));
    queue=[response({device_code:'d',user_code:'CODE',verification_uri:'https://owned.example/device',expires_in:900}),response({error:'expired_token'},400)];await record('radius-device-expired',()=>radius.login(interaction('device-code')));
    queue=[response({device_code:'d',user_code:'CODE',verification_uri:'https://owned.example/device',expires_in:900}),response({error:'access_denied'},400)];await record('radius-device-denied',()=>radius.login(interaction('device-code')));
    const spoof=Object.assign(new Error('spoof'),{oauthError:'authorization_pending',status:400});queue=[response({device_code:'d',user_code:'CODE',verification_uri:'https://owned.example/device',expires_in:900}),{throw:spoof}];await record('radius-device-error-brand',async()=>{try{await radius.login(interaction('device-code'))}catch(e){return{same:e===spoof}}});
    queue=[response({authorizationEndpoint:7})];await record('radius-discovery-invalid',()=>radius.login(interaction('browser')));
    queue=[response({},500,'config failure')];await record('radius-discovery-http',()=>radius.login(interaction('browser')));
    if(output.length!==caseIds.length || output.some((row,i)=>row.id!==caseIds[i]))throw Error('Case inventory drift');
    return output;
  } finally { globalThis.fetch=previousFetch;Date.now=originalNow; }
}
