const oauth=globalThis.openaiChatGPTOAuth,rows=[],wire=[],trace=[];
const originalFetch=globalThis.fetch,originalNow=Date.now;
const token={access_token:' access ',refresh_token:' refresh ',scope:'openid\tchatgpt.tokens.use.direct  custom',expires_in:3600};
Date.now=()=>1700000000123;
let response=token,status=200,body='',statusText='OK',rejectText=false;
globalThis.fetch=async(url,init)=>{
  wire.push({url,method:init.method,headers:init.headers,body:init.body.toString(),signal:init.signal===signal});
  return {ok:status>=200&&status<300,status,statusText,async json(){return response},async text(){if(rejectText)throw 'read failed';return body}};
};
const signal=new AbortController().signal;
async function observe(name,work){try{rows.push({name,value:await work()})}catch(error){rows.push({name,error:{name:error?.name??typeof error,message:error?.message??String(error)}})}}
try{
  rows.push({name:'metadata',value:{keys:Object.keys(oauth),name:oauth.name,isSubscription:oauth.isSubscription,loginLabel:oauth.loginLabel,methods:['login','refresh','toAuth'].map(key=>({key,name:oauth[key].name,length:oauth[key].length,async:Object.getPrototypeOf(oauth[key])===Object.getPrototypeOf(async()=>{}),prototype:Object.hasOwn(oauth[key],'prototype')}))}});
  await observe('refresh-success',()=>oauth.refresh({clientId:' issued client ',refresh:'r +/='},signal));
  const rich={get clientId(){trace.push('clientId');return 'client-rich'},get refresh(){trace.push('refresh');return {toString(){trace.push('refresh.toString');return 'rich +'},toJSON(){throw Error('credential stringify')}}},get unknown(){throw Error('unknown credential read')}};
  await observe('refresh-getters',()=>oauth.refresh(rich,signal));
  rows.push({name:'refresh-getter-order',value:trace.splice(0)});
  for(const clientId of [undefined,null,'',' \t ',3,{},false])await observe('invalid-client-'+String(clientId),()=>oauth.refresh({clientId,get refresh(){throw Error('refresh should stay unread')}},signal));
  await observe('toAuth-live',async()=>{const access={marker:'live'},credential={get access(){trace.push('access');return access},get unknown(){throw Error('unknown read')},toJSON(){throw Error('credential stringify')}};const pending=oauth.toAuth(credential);trace.push('returned');const value=await pending;return {promise:pending instanceof Promise,keys:Object.keys(value),same:value.apiKey===access,trace:trace.splice(0)}});
  const marker={getter:'identity'};await observe('toAuth-getter-error',async()=>{const p=oauth.toAuth({get access(){throw marker}});try{await p}catch(e){return {promise:p instanceof Promise,same:e===marker}}});
  await observe('toAuth-null',()=>oauth.toAuth(null));
  for(const [name,value] of [['null',null],['array',[]],['number',4],['missing-access',{}],['blank-access',{...token,access_token:' '}],['missing-refresh',{...token,refresh_token:undefined}],['blank-scope',{...token,scope:' '}],['missing-direct-scope',{...token,scope:'openid offline_access'}],['expires-zero',{...token,expires_in:0}],['expires-string',{...token,expires_in:'3600'}],['expires-infinity',{...token,expires_in:Infinity}],['expires-negative',{...token,expires_in:-1}],['expires-fractional',{...token,expires_in:0.5}]]){
    response=value;await observe('response-'+name,()=>oauth.refresh({clientId:'issued',refresh:'r'},signal));
  }
  response=token;status=401;statusText='Unauthorized';body='fake denied';await observe('http-body',()=>oauth.refresh({clientId:'issued',refresh:'r'},signal));
  body='';await observe('http-empty',()=>oauth.refresh({clientId:'issued',refresh:'r'},signal));
  rejectText=true;await observe('http-read-error',()=>oauth.refresh({clientId:'issued',refresh:'r'},signal));
  status=200;rejectText=false;
  for(const options of [undefined,{}, {getDeviceId:()=>undefined},{getDeviceId:()=>''},{getDeviceId:()=> 'bad-uuid'}])await observe('login-invalid-device',()=>oauth.login({get notify(){throw Error('unexpected notify')}},options));
  const optionMarker={option:'identity'};await observe('login-device-getter',async()=>{const p=oauth.login({}, {get getDeviceId(){throw optionMarker}});try{await p}catch(error){return {promise:p instanceof Promise,same:error===optionMarker}}});
  const loginEvents=[];
  for(const mode of ['success','missing-id-token','wrong-state','missing-issued-id','authorization-error','cancelled']){
    response={...token,id_token:'present'};if(mode==='missing-id-token')delete response.id_token;
    const controller=new AbortController();let currentState,manualSignal;
    await observe('login-'+mode,async()=>{
      const interaction={signal:controller.signal,notify(value){loginEvents.push(mode+':'+value.type);if(value.type==='auth_url'){globalThis.__chatGPTOAuthObserveListener?.();const url=new URL(value.url);currentState=url.searchParams.get('state');const fields=Object.fromEntries(url.searchParams);fields.state='<random32>';fields.nonce='<random32>';fields.code_challenge='<S256>';loginEvents.push({mode,url:url.origin+url.pathname,fields,stateBytes:currentState.length,nonceBytes:url.searchParams.get('nonce').length,challengeBytes:url.searchParams.get('code_challenge').length})}},prompt(value){manualSignal=value.signal;loginEvents.push({mode,type:value.type,message:value.message,placeholder:value.placeholder,initialAborted:value.signal.aborted});if(mode==='cancelled'){controller.abort('owned cancellation');return Promise.reject('owned cancellation')}const url=new URL('http://127.0.0.1:1455/auth/callback');url.searchParams.set('code','issued code+/=');url.searchParams.set('state',mode==='wrong-state'?'wrong':currentState);if(mode!=='missing-issued-id')url.searchParams.set('client_id',' issued + client ');if(mode==='authorization-error')url.searchParams.set('error','access_denied');return Promise.resolve(url.toString())}};
      const credential=await oauth.login(interaction,{getDeviceId(){return 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'},agentName:'Fixture Agent'});
      return {credential,manualAborted:manualSignal.aborted};
    });
    loginEvents.push({mode,finallyAborted:manualSignal?.aborted??null});
  }
  rows.push({name:'login-interactions',value:loginEvents});
  for(const request of wire){const form=new URLSearchParams(request.body);if(form.has('code_verifier')){form.set('code_verifier','<PKCE>');request.body=form.toString()}if(form.get('grant_type')==='authorization_code')request.signal='interaction'}
  globalThis.chatGPTOAuthObservation={rows,wire};
}finally{Date.now=originalNow;globalThis.fetch=originalFetch}
