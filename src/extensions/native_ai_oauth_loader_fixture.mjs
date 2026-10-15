// Guest input shared verbatim by genuine Source and the native loader graph.
// This fixture never invokes login or refresh and fails every network request.
export async function run(api, lazyOAuth) {
  const rows = [];
  const oldFetch = globalThis.fetch;
  globalThis.fetch = () => { throw Error('OAuth loader fixture forbids network'); };
  const names = ['loadAnthropicOAuth','loadOpenAICodexOAuth','loadOpenAIChatGPTOAuth','loadGitHubCopilotOAuth','loadOpenRouterOAuth','loadKimiCodingOAuth','loadMetaOAuth','loadXaiOAuth'];
  const shape = value => ({keys:Object.keys(value),name:value.name,isSubscription:value.isSubscription??null,loginLabel:value.loginLabel??null,methods:['login','refresh','toAuth'].map(key=>({key,name:value[key].name,length:value[key].length,tag:Object.prototype.toString.call(value[key]),constructible:(()=>{try{Reflect.construct(function(){},[],value[key]);return true}catch{return false}})()}))});
  try {
    api.registerBundledOAuthFlowLoaders(undefined);
    rows.push({case:'loader-export-metadata',functions:[...names,'loadRadiusOAuth','registerBundledOAuthFlowLoaders'].map(key=>({key,name:api[key].name,length:api[key].length,tag:Object.prototype.toString.call(api[key]),constructible:(()=>{try{Reflect.construct(function(){},[],api[key]);return true}catch{return false}})()}))});
    for (const name of names) {
      const [first,second]=await Promise.all([api[name](),api[name]()]);
      rows.push({case:name,same:first===second,shape:shape(first)});
    }
    const options={name:'Owned Radius graph',gateway:'owned.invalid/'};
    const [radius,other]=await Promise.all([api.loadRadiusOAuth(options),api.loadRadiusOAuth(options)]);
    const access={owned:true};
    rows.push({case:'radius-fresh-factory',fresh:radius!==other,shape:shape(radius),accessIdentity:(await radius.toAuth({access})).apiKey===access});
    let trace=[];const marker={owned:'bundled'};
    const bundled={get anthropic(){trace.push('get');return function(){trace.push(this===bundled?'receiver':'bad-receiver');trace.push(arguments.length);return marker}}};
    api.registerBundledOAuthFlowLoaders(bundled);
    const first=api.loadAnthropicOAuth();trace.push('returned');
    rows.push({case:'bundled-receiver-and-getter',identity:(await first)===marker,trace});
    const reason={owned:'raw-error'};let sync=false,promise;
    api.registerBundledOAuthFlowLoaders({get anthropic(){throw reason}});
    try{promise=api.loadAnthropicOAuth()}catch{sync=true}
    let rejection;try{await promise}catch(error){rejection=error}
    rows.push({case:'bundled-getter-rejection',sync,sameReason:rejection===reason});
    let count=0;const thenable={then(resolve){count++;resolve(marker)}};
    api.registerBundledOAuthFlowLoaders({anthropic(){return thenable}});
    rows.push({case:'bundled-thenable',identity:(await api.loadAnthropicOAuth())===marker,count});
    let received,receiver,args;const untouched={get name(){throw Error('options must remain raw')}};
    const radiusLoaders={radius(input){received=input;receiver=this;args=arguments.length;return marker}};
    api.registerBundledOAuthFlowLoaders(radiusLoaders);
    rows.push({case:'bundled-radius-options',identity:(await api.loadRadiusOAuth(untouched))===marker,sameOptions:received===untouched,sameReceiver:receiver===radiusLoaders,args});
    let gets=0;const changing={get anthropic(){gets++;return ()=>marker}};
    api.registerBundledOAuthFlowLoaders(changing);
    await api.loadAnthropicOAuth();await api.loadAnthropicOAuth();
    rows.push({case:'bundled-getter-not-cached',gets});
    let loads=0;const credential={owned:'credential'};
    api.registerBundledOAuthFlowLoaders({anthropic(){loads++;return {name:'Owned delegated',toAuth(value){return {apiKey:value}},refresh(value){return value},login(){return credential}}}});
    const lazy=lazyOAuth({name:'Owned graph lazy',load:api.loadAnthropicOAuth});
    const [one,two]=await Promise.all([lazy.toAuth(credential),lazy.toAuth(credential)]);
    rows.push({case:'lazy-loader-coalesces',loads,identity:one.apiKey===credential&&two.apiKey===credential});
    api.registerBundledOAuthFlowLoaders(undefined);
    const restored=await api.loadAnthropicOAuth();
    rows.push({case:'default-module-restored',same:restored===await api.loadAnthropicOAuth(),name:restored.name});
    api.registerBundledOAuthFlowLoaders({});
    let failure;try{await api.loadMetaOAuth()}catch(error){failure=error}
    rows.push({case:'missing-bundled-method',typeError:failure instanceof TypeError});
  } finally {
    api.registerBundledOAuthFlowLoaders(undefined);
    globalThis.fetch=oldFetch;
  }
  return rows;
}
