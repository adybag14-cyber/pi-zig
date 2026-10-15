// Browser OAuth witnesses use only owned loopback callbacks and fake token HTTP.
export const browserCaseIds=['codex-manual-code','codex-manual-query','codex-manual-url','codex-manual-state-mismatch','codex-manual-missing','radius-callback-success','radius-callback-exchange-failure'];
export async function runOAuthBrowserCases(codex,createRadius,ownedCallbackFetch) {
  const output=[],requests=[],notifications=[];
  const previousFetch=globalThis.fetch,previousCrypto=globalThis.crypto,previousNow=Date.now;
  const now=1700000000000,controller=new AbortController();
  const fixedCrypto={
    getRandomValues(bytes){for(let i=0;i<bytes.length;i++)bytes[i]=i;return bytes},
    subtle:previousCrypto.subtle,
    randomUUID(){return '00112233-4455-4677-8899-aabbccddeeff'},
  };
  Object.defineProperty(globalThis,'crypto',{value:fixedCrypto,writable:true,configurable:true});
  Date.now=()=>now;
  const access='e30.'+btoa(JSON.stringify({'https://api.openai.com/auth':{chatgpt_account_id:'browser-account'}}))+'.sig';
  let tokenStatus=200;
  globalThis.fetch=async(input,init={})=>{
    const url=String(input);
    requests.push({url,inputKind:typeof input==='string'?'string':input.constructor.name,method:init.method??'GET',headers:Object.entries(init.headers??{}),body:init.body===undefined?null:String(init.body),bodyKind:init.body?.constructor?.name??null,signalSame:init.signal===controller.signal});
    if(url==='https://gateway.example/v1/oauth')return{ok:true,async json(){return{authorizationEndpoint:'https://owned.example/authorize?discard=1#fragment'}}};
    if(url!=='https://auth.openai.com/oauth/token'&&url!=='https://gateway.example/v1/oauth/token')throw Error('Unexpected owned browser HTTP '+url);
    return {ok:tokenStatus===200,status:tokenStatus,statusText:'Fixture',async json(){return{access_token:access,refresh_token:'browser-refresh',expires_in:120,scope:'gateway offline_access'}},async text(){return JSON.stringify({error:'invalid_grant',error_description:'expired code'})}};
  };
  function eventSnapshot(event){
    if(event.type!=='auth_url')return event;
    const url=new URL(event.url);url.searchParams.set('state','<STATE>');
    return{...event,url:String(url)};
  }
  function error(e){return{name:e.name,message:e.message,constructor:e.constructor.name,...(Object.hasOwn(e,'status')?{status:e.status}:{}),...(Object.hasOwn(e,'oauthError')?{oauthError:e.oauthError??null}:{})}}
  async function record(id,fn){const requestStart=requests.length,eventStart=notifications.length;let result;try{result={ok:true,value:await fn()}}catch(e){globalThis.__observeOAuthError?.(id,e);result={ok:false,error:error(e)}}output.push({id,...result,requests:requests.slice(requestStart),notices:notifications.slice(eventStart)})}
  async function manual(mode){
    let auth;
    return codex.login({signal:controller.signal,notify(event){globalThis.__observeOAuthEvent?.(event);if(event.type==='auth_url'){globalThis.__observeOAuthListener?.(1455);auth=new URL(event.url)}notifications.push(eventSnapshot(event))},async prompt(prompt){
      if(prompt.type==='select')return'browser';
      notifications.push({type:prompt.type,message:prompt.message,placeholder:prompt.placeholder,signalAborted:prompt.signal.aborted});
      const state=auth.searchParams.get('state');
      if(mode==='raw')return' browser-code ';
      if(mode==='query')return'code=browser-code&state='+state;
      if(mode==='url')return'http://localhost:1455/auth/callback?code=browser-code&state='+state;
      if(mode==='mismatch')return'browser-code#wrong-state';
      return'   ';
    }},{agentName:'owned fixture'});
  }
  try{
    await record('codex-manual-code',()=>manual('raw'));
    await record('codex-manual-query',()=>manual('query'));
    await record('codex-manual-url',()=>manual('url'));
    await record('codex-manual-state-mismatch',()=>manual('mismatch'));
    await record('codex-manual-missing',()=>manual('missing'));
    async function radiusBrowser(status){
      tokenStatus=status;let callbackResponse;
      const auth=createRadius({name:'Owned Radius',gateway:'https://gateway.example/base/'});
      let credential,failure;
      try{credential=await auth.login({signal:controller.signal,async prompt(){return'browser'},notify(event){
        globalThis.__observeOAuthEvent?.(event);notifications.push(eventSnapshot(event));
        if(event.type==='auth_url'){
          globalThis.__observeOAuthListener?.(1456);
          const authorize=new URL(event.url),target=new URL(authorize.searchParams.get('redirect_uri'));
          target.searchParams.set('state',authorize.searchParams.get('state'));target.searchParams.set('code','browser-code');
          callbackResponse=ownedCallbackFetch(String(target)).then(async response=>({status:response.status,contentType:response.headers.get('content-type'),cacheControl:response.headers.get('cache-control'),body:await response.text()}));
        }
      }})}catch(e){globalThis.__observeOAuthError?.('radius-callback-'+status,e);failure=e}
      const page=await callbackResponse;
      return{...(failure?{error:error(failure)}:{credential}),page};
    }
    await record('radius-callback-success',()=>radiusBrowser(200));
    await record('radius-callback-exchange-failure',()=>radiusBrowser(400));
    if(output.length!==browserCaseIds.length||output.some((r,i)=>r.id!==browserCaseIds[i]))throw Error('Browser case inventory drift');
    return output;
  }finally{globalThis.fetch=previousFetch;Object.defineProperty(globalThis,'crypto',{value:previousCrypto,writable:true,configurable:true});Date.now=previousNow}
}
