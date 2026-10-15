// Controlled guest inputs shared with original immutable Source bodies.
// No real environment credential, file lookup, login flow or endpoint is used.
export async function run(api) {
  const rows=[], rawFunctions=[];
  const savedFetch=globalThis.fetch;
  globalThis.fetch=()=>{throw Error('Provider factory fixture forbids network')};
  const functionShape=fn=>({name:fn.name,length:fn.length,tag:Object.prototype.toString.call(fn),prototype:Object.hasOwn(fn,'prototype'),constructible:(()=>{try{Reflect.construct(function(){},[],fn);return true}catch{return false}})()});
  const summarizeAuth=value=>value?{keys:Object.keys(value),name:value.name,isSubscription:value.isSubscription??null,loginLabel:value.loginLabel??null,methods:Object.fromEntries(Object.entries(value).filter(([,x])=>typeof x==='function').map(([key,fn])=>[key,functionShape(fn)]))}:null;
  const errorShape=error=>({name:error?.name??typeof error,message:error?.message??String(error),code:error?.code??null});
  const observe=async(name,callback)=>{try{rows.push({case:name,value:await callback()})}catch(error){rows.push({case:name,error:errorShape(error)})}};
  const controlledContext=log=>({async env(name){log.push(['env',name]);return {CLOUDFLARE_ACCOUNT_ID:'owned-account',CLOUDFLARE_GATEWAY_ID:'owned-gateway'}[name]},async fileExists(path){log.push(['fileExists',path]);return false}});
  try {
    await observe('actual export metadata',()=>({models:Object.keys(api.models),all:Object.keys(api.all),factories:Object.entries(api.factories).map(([key,fn])=>({key,...functionShape(fn)}))}));
    for(const [exportName,constructor] of Object.entries(api.factories)) {
      await observe('factory '+exportName,()=>{
        const provider=constructor(),second=constructor();
        const chat=provider.getModels(),all=provider.getAllModels?.()??chat;
        const first=chat[0];
        rawFunctions.push({exportName,source:Function.prototype.toString.call(constructor)});
        return {factory:functionShape(constructor),id:provider.id,name:provider.name,baseUrl:provider.baseUrl??null,keys:Object.keys(provider),fresh:provider!==second,authKeys:Object.keys(provider.auth),apiKey:summarizeAuth(provider.auth.apiKey),oauth:summarizeAuth(provider.auth.oauth),sameApiKey:provider.auth.apiKey===second.auth.apiKey,sameOAuth:provider.auth.oauth===second.auth.oauth,methods:Object.fromEntries(Object.entries(provider).filter(([,value])=>typeof value==='function').map(([key,fn])=>[key,functionShape(fn)])),chat:chat.map(model=>model.id),all:all.map(model=>[model.type??'chat',model.id]),canonicalFirst:first?first===api.all.getBuiltinModel(provider.id,first.id):null};
      });
    }
    await observe('builtin order and freshness',()=>{const one=api.all.builtinProviders(),two=api.all.builtinProviders();return {ids:one.map(p=>p.id),allFresh:one.every((p,i)=>p!==two[i]),sameBedrock:one[0].auth.apiKey===two[0].auth.apiKey};});
    await observe('Models constructor getters and actual class',()=>{
      const trace=[],credentialStore={async read(){return undefined}},modelsStore={async read(){return undefined}},authContext=controlledContext(trace);
      const input={get credentials(){trace.push('credentials');return credentialStore},get modelsStore(){trace.push('modelsStore');return modelsStore},get authContext(){trace.push('authContext');return authContext}};
      const models=api.models.createModels(input),proto=Object.getPrototypeOf(models);
      return {trace,keys:Object.keys(models),prototype:Object.getOwnPropertyNames(proto),constructor:proto.constructor.name,methods:Object.fromEntries(Object.getOwnPropertyNames(proto).filter(key=>key!=='constructor'&&typeof proto[key]==='function').map(key=>[key,functionShape(proto[key])])),emptyProviders:models.getProviders().length};
    });
    await observe('builtin Models registers every real provider',()=>{const trace=[];const models=api.all.builtinModels({authContext:controlledContext(trace)});return {ids:models.getProviders().map(p=>p.id),anthropic:models.getModel('anthropic',api.all.getBuiltinModels('anthropic')[0]?.id)===api.all.getBuiltinModels('anthropic')[0],trace};});
    await observe('ModelsError cause getters and class fields',()=>{
      const trace=[],cause={toString(){trace.push('cause.toString');return ' owned cause '}};
      const options={get cause(){trace.push('options.cause');return cause}};
      const error=new api.models.ModelsError('auth','Owned operation',options);
      return {trace,name:error.name,message:error.message,code:error.code,sameCause:error.cause===cause,keys:Object.keys(error),own:Object.getOwnPropertyNames(error).filter(key=>key!=='stack'),errorBrand:error instanceof Error,constructor:error.constructor===api.models.ModelsError};
    });
    await observe('availability resolves stored credentials twice',async()=>{
      const trace=[],store={async read(id){trace.push(['read',id]);return {type:'api_key',key:'owned-stored-key'}}};
      const models=api.models.createModels({credentials:store,authContext:controlledContext(trace)});
      models.setProvider(api.factories.openaiProvider());
      const check=await models.checkAuth('openai');
      return {trace,check};
    });
    await observe('stored unsupported credential never falls back',async()=>{
      const trace=[],store={async read(id){trace.push(['read',id]);return {type:'owned-unsupported'}}};
      const ctx={async env(name){trace.push(['forbidden ambient',name]);return 'owned-ambient-key'},async fileExists(){throw Error('Forbidden real file probe')}};
      const models=api.models.createModels({credentials:store,authContext:ctx});models.setProvider(api.factories.openaiProvider());
      const check=await models.checkAuth('openai');return {trace,check:check??null};
    });
    for(const exportName of ['anthropicProvider','amazonBedrockProvider','googleVertexProvider','cloudflareWorkersAIProvider','cloudflareAIGatewayProvider']) {
      await observe('owned stored auth '+exportName,async()=>{const trace=[],auth=api.factories[exportName]().auth.apiKey,credential={type:'api_key',key:'owned-auth-key',env:{CLOUDFLARE_ACCOUNT_ID:'owned-stored-account'}};return {result:await auth.resolve({ctx:controlledContext(trace),credential,signal:new AbortController().signal}),trace};});
      await observe('owned missing auth '+exportName,async()=>{const trace=[],auth=api.factories[exportName]().auth.apiKey;return {result:(await auth.resolve({ctx:controlledContext(trace),credential:undefined,signal:new AbortController().signal}))??null,trace};});
      await observe('raw getter error '+exportName,async()=>{const marker={owned:'raw getter'},auth=api.factories[exportName]().auth.apiKey;let promise,sync=false,error;try{promise=auth.resolve({get ctx(){throw marker}})}catch(value){sync=true;error=value}try{await promise}catch(value){error=value}return {sync,sameError:error===marker};});
    }
    await observe('Anthropic actual federation config resolution',async()=>{const trace=[],values={ANTHROPIC_FEDERATION_RULE_ID:'owned-rule',ANTHROPIC_ORGANIZATION_ID:'owned-org',ANTHROPIC_IDENTITY_TOKEN_FILE:'owned-unused-file',ANTHROPIC_WORKSPACE_ID:'owned-workspace'};const result=await api.factories.anthropicProvider().auth.apiKey.resolve({ctx:{async env(name){trace.push(name);return values[name]}},signal:new AbortController().signal});return {trace,result};});
    await observe('Bedrock selected profile precedes ambient access keys',async()=>{const trace=[];const result=await api.factories.amazonBedrockProvider().auth.apiKey.resolve({ctx:controlledContext(trace),credential:{type:'api_key',env:{AWS_PROFILE:'owned-profile'}},signal:new AbortController().signal});return {trace,result};});
    await observe('Vertex owned file callback and project aliases',async()=>{const trace=[],values={GCLOUD_PROJECT:'owned-project',GOOGLE_CLOUD_LOCATION:'owned-location'};const result=await api.factories.googleVertexProvider().auth.apiKey.resolve({ctx:{async env(name){trace.push(['env',name]);return values[name]},async fileExists(path){trace.push(['fileExists',path]);return true}},signal:new AbortController().signal});return {trace,result};});
    await observe('Cloudflare missing key still resolves each configured field',async()=>{const trace=[];const result=await api.factories.cloudflareAIGatewayProvider().auth.apiKey.resolve({ctx:controlledContext(trace),signal:new AbortController().signal});return {trace,result:result??null};});
    await observe('OpenAI OAuth classifier filter',()=>{const provider=api.factories.openaiProvider(),models=[{id:'chat'},{id:'image',type:'image'},{id:'classifier',type:'classifier'}];const oauth=provider.filterAllModels(models,{type:'oauth'});return {oauth:oauth.map(m=>m.id),unchanged:provider.filterAllModels(models,{type:'api_key'})===models};});
    await observe('Copilot exact model availability policy',()=>{const provider=api.factories.githubCopilotProvider(),models=[{id:'a'},{id:'b'}];return {selected:provider.filterModels(models,{type:'oauth',availableModelIds:['b']}).map(m=>m.id),invalidPreserves:provider.filterModels(models,{type:'oauth',availableModelIds:[1]})===models};});
    await observe('OpenCode session wrapper getter and callback context',()=>{
      const trace=[],marker={},streams={extra:'retained',stream(model,context,options){trace.push(['call',this===streams,options.headers]);return marker},streamSimple(){}};
      const wrapper=api.wrappers.withOpenCodeSessionHeader(streams),options={get sessionId(){trace.push('sessionId');return 'owned-session'},get headers(){trace.push('headers');return {X:'owned'}}};
      return {trace,identity:wrapper.stream({}, {}, options)===marker,extra:wrapper.extra};
    });
    await observe('Cloudflare endpoint wrapper getter and callback context',()=>{
      const trace=[],marker={},streams={stream(model,context,options){trace.push(['call',this===streams,model.baseUrl,options.env]);return marker},streamSimple(){}};
      const wrapper=api.wrappers.cloudflareStreams(streams),model={get baseUrl(){trace.push('baseUrl');return 'https://owned.invalid/{CLOUDFLARE_ACCOUNT_ID}/{CLOUDFLARE_GATEWAY_ID}'}};
      return {trace,identity:wrapper.stream(model,{}, {env:{CLOUDFLARE_ACCOUNT_ID:'owned-account',CLOUDFLARE_GATEWAY_ID:'owned-gateway'}})===marker};
    });
    await observe('Radius options getters and custom gateway baseline',()=>{const trace=[],options={get id(){trace.push('id');return 'owned-radius'},get name(){trace.push('name');return 'Owned Radius'},get gateway(){trace.push('gateway');return 'owned.invalid/gateway///'}};const provider=api.factories.radiusProvider(options);return {trace,id:provider.id,name:provider.name,models:provider.getModels(),keys:Object.keys(provider)};});
    await observe('Radius offline restore replaces catalog through publication',async()=>{const provider=api.factories.radiusProvider({id:'owned-radius',gateway:'owned.invalid'}),trace=[];const stored={models:[{id:'owned-one',provider:'owned-radius'},{id:'other',provider:'different'}]};await provider.refreshModels({stored,allowNetwork:false,signal:new AbortController().signal,async publish(value){trace.push(Object.keys(value));value.update?.();return true}});return {trace,models:provider.getModels(),same:provider.getModels()[0]===stored.models[0]};});
  } finally {globalThis.fetch=savedFetch}
  return {rows,rawFunctions};
}
