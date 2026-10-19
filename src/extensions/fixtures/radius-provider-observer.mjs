// Actual c268 Radius provider observations. All import doubles are test inputs;
// production obtains the real config/auth/catalog/API/OAuth module owners.
function radiusProviderCheck(value,message){if(!value)throw new Error(message);}
function radiusProviderSummary(models){
 if(Array.isArray(models))return models.map(model=>({id:model.id,provider:model.provider,nested:model.nested?.value}));
 return models===undefined?"undefined":models===null?"null":{kind:models.kind};
}
function radiusProviderHarness(route){
 const trace=[],marker={kind:"exact-marker"},nested={value:7};
 const catalog={one:{id:"one",provider:"original",nested},two:{id:"two",provider:"original",nested}};
 const h={trace,marker,catalog,updates:[],normalizeCalls:0,config:{kind:"config"},legacy:[{id:"legacy",provider:"chosen"}],refreshed:[{id:"fresh",provider:"chosen"}]};
 const streams={
  get stream(){trace.push("stream:get");if(route==="stream-get-throw")throw marker;return function(...args){trace.push("stream:call:"+(this===streams)+":"+args.length);if(route==="stream-call-throw")throw marker;h.streamArgs=args;return args[2];};},
  get streamSimple(){trace.push("simple:get");if(route==="simple-get-throw")throw marker;return function(...args){trace.push("simple:call:"+(this===streams)+":"+args.length);if(route==="simple-call-throw")throw marker;h.streamArgs=args;return args[2];};}
 };
 h.imports={
  piMessagesApi(){trace.push("api:create:"+(this===undefined));if(route==="api-throw")throw marker;return streams;},
  envApiKeyAuth(label,names){trace.push("auth:key:"+label+":"+names.join(",")+":"+(this===undefined));if(route==="auth-key-throw")throw marker;return {kind:"apiKey",label,names};},
  lazyOAuth(options){trace.push("auth:lazy:"+Object.keys(options).join(",")+":"+options.name+":"+(this===undefined));if(route==="auth-lazy-throw")throw marker;h.oauthOptions=options;return options;},
  loadRadiusOAuth(options){trace.push("oauth:load:"+Object.keys(options).join(",")+":"+options.name+":"+options.gateway+":"+(this===undefined));if(route==="oauth-load-throw")throw marker;h.loaded=options;return h.oauthResult;},
  RADIUS_MODELS:catalog,
  DEFAULT_RADIUS_GATEWAY:"https://radius.pi.dev",
  getRadiusModels(id,credential){trace.push("legacy:call:"+id+":"+(credential===h.currentCredential)+":"+(this===undefined));if(route==="legacy-get-throw")throw marker;return h.legacy;},
  getRadiusModelsFromConfig(id,config){trace.push("refreshed:call:"+id+":"+(config===h.config)+":"+(this===undefined));if(route==="config-map-throw")throw marker;return h.refreshed;},
  loadRadiusGatewayConfig(gateway,key,signal){trace.push("config:load:"+gateway+":"+String(key)+":"+(signal===h.signal)+":"+(this===undefined));if(route==="config-load-throw")throw marker;return {get then(){trace.push("config:then-get");if(route==="config-then-throw")throw marker;return function(resolve,reject){trace.push("config:adopt");if(route==="late-abort")h.signal.aborted=true;(route==="config-reject"?reject:resolve)(route==="config-reject"?marker:h.config);};}};},
  normalizeRadiusGatewayUrl(value){h.normalizeCalls++;trace.push("normalize:"+h.normalizeCalls+":"+(value===h.rawGateway?"raw":String(value))+":"+(this===undefined));if(route==="normalize-first-throw"&&h.normalizeCalls===1||route==="normalize-second-throw"&&h.normalizeCalls===2)throw marker;return value===h.rawGateway?"https://radius.pi.dev":value;}
 };
 return h;
}
async function observeRadiusProviderOrdinary(route){
 const h=radiusProviderHarness(route),trace=h.trace,marker=h.marker;
 const factory=radiusProviderMake(h.imports),oldValues=Object.getOwnPropertyDescriptor(Object,"values");
 const id={kind:"raw-id"},name={kind:"raw-name"},rawGateway={kind:"raw-gateway"};
 h.rawGateway=rawGateway;
 let options={id:"chosen",name:"Chosen",gateway:"https://radius.pi.dev"},result;
 if(route==="default"||route==="undefined")options=undefined;
 if(route==="null")options=null;
 if(route==="nullish")options={id:null,name:undefined,gateway:null};
 if(route==="raw")options={id,name,gateway:rawGateway};
 if(route==="custom-gateway")options={id:"chosen",name:"Chosen",gateway:"https://custom.test"};
 if(route.startsWith("option-")){
  options={};
  for(const key of ["id","name","gateway"])Object.defineProperty(options,key,{get(){trace.push("option:"+key);if(route==="option-"+key+"-throw")throw marker;return key==="id"?"chosen":key==="name"?"Chosen":"https://radius.pi.dev";}});
 }
 const liveValues=route.startsWith("values-")||route.startsWith("map-")||route==="escaped-map";
 if(liveValues)Object.defineProperty(Object,"values",{configurable:true,get(){
  trace.push("values:get");if(route==="values-get-throw")throw marker;
  return function(value){
   trace.push("values:call:"+(this===Object)+":"+(value===h.catalog));if(route==="values-call-throw")throw marker;
   const receiver={get map(){trace.push("map:get");if(route==="map-get-throw")throw marker;return function(callback){
    trace.push("map:call:"+(this===receiver)+":"+callback.name+":"+callback.length+":"+Object.hasOwn(callback,"prototype"));
    h.escapedMap=callback;if(route==="map-call-throw")throw marker;
    return [callback(h.catalog.one),callback(h.catalog.two)];
   };}};
   return receiver;
  };
 }});
 try{
  try{
   const provider=route==="default"?factory():factory(options);
   h.provider=provider;
   const models=provider.getModels();
   result={keys:Object.keys(provider),id:provider.id===id?"raw-id":provider.id,name:provider.name===name?"raw-name":provider.name,
    models:radiusProviderSummary(models),sameModels:models===provider.getModels(),
    copied:models.length?models[0]!==h.catalog.one&&models[0].nested===h.catalog.one.nested:null,
    refreshAsync:radiusProviderIsAsync(provider.refreshModels),
    functions:["getModels","refreshModels","stream","streamSimple"].map(key=>({key,name:provider[key].name,length:provider[key].length,prototype:Object.hasOwn(provider[key],"prototype")}))};
   if(route==="escaped-map"){const later=h.escapedMap({id:"later",provider:"wrong"});result.escaped={id:later.id,provider:later.provider};}
  }catch(error){result={thrown:error===marker?"marker":error?.name??typeof error};}
  return {trace,result};
 }finally{Object.defineProperty(Object,"values",oldValues);}
}
async function observeRadiusProviderStreams(route){
 const h=radiusProviderHarness(route),factory=radiusProviderMake(h.imports);
 h.oauthResult={kind:"loaded-result"};
 const provider=factory({id:"chosen",name:"Chosen",gateway:"https://custom.test"}),model={},context={},options={};
 let result;
 try{
  if(route.startsWith("oauth")){
   const load=provider.auth.oauth.load,returned=load.call({wrong:true});
   result={identity:returned===h.oauthResult,loadName:load.name,loadLength:load.length,loadPrototype:Object.hasOwn(load,"prototype"),loaded:h.loaded};
  }else{
   const method=route.startsWith("simple")?"streamSimple":"stream";
   const callable=provider[method],returned=callable.call({wrong:true},model,context,options,"extra");
   result={identity:returned===options,model:h.streamArgs[0]===model,context:h.streamArgs[1]===context,length:h.streamArgs.length};
  }
 }catch(error){result={thrown:error===h.marker?"marker":error?.name??typeof error};}
 return {trace:h.trace,result};
}
async function observeRadiusProviderRefresh(route){
 const h=radiusProviderHarness(route),trace=h.trace,marker=h.marker;
 const factory=radiusProviderMake(h.imports),provider=factory({id:"chosen",name:"Chosen",gateway:"https://radius.pi.dev"});
 h.provider=provider;trace.length=0;h.signal={aborted:route==="already-aborted"};
 const originalNow=Object.getOwnPropertyDescriptor(Date,"now");
 Object.defineProperty(Date,"now",{configurable:true,get(){trace.push("date:now-get");if(route==="date-get-throw")throw marker;return function(){trace.push("date:now-call:"+(this===Date));if(route==="date-call-throw")throw marker;return 123456;};}});
 let credentialReads=0,publishes=0,result,stored;
 const oauthRoutes=route.startsWith("legacy")||route==="date-get-throw"||route==="date-call-throw";
 h.currentCredential=oauthRoutes?{type:"oauth",access:"access-token"}:{type:"api_key",key:"api-token"};
 if(route==="missing-credential")h.currentCredential=undefined;
 if(route==="null-credential")h.currentCredential=null;
 if(route==="oauth-access")h.currentCredential={type:"oauth",access:"token",key:"wrong"};
 if(route==="legacy-empty")h.legacy=[];
 if(route==="legacy-length-throw")h.legacy={get length(){trace.push("legacy:length");throw marker;}};
 if(route==="legacy-length-coercion")h.legacy={kind:"legacy",get length(){trace.push("legacy:length");return {[Symbol.toPrimitive](hint){trace.push("legacy:coerce:"+hint);return 1;}};}};
 const storedRoutes=route.startsWith("stored")||route.startsWith("filter")||route==="delayed-update";
 const restored=route==="stored-no-map"?{kind:"restored",get map(){trace.push("wrong:restored-map");throw marker;}}:[{id:"stored",provider:"chosen"}];
 if(storedRoutes){
  const models={get filter(){trace.push("filter:get");if(route==="filter-get-throw")throw marker;return function(callback){
   trace.push("filter:call:"+(this===models)+":"+callback.name+":"+callback.length);
   h.filterCallback=callback;
   trace.push("filter:matches:"+callback({provider:"chosen"})+":"+callback({provider:"other"}));
   if(route==="filter-call-throw")throw marker;return restored;
  };}};
  stored={get models(){trace.push("stored:models");if(route==="stored-models-throw")throw marker;return models;}};
 }
 const context={
  get stored(){trace.push("context:stored");if(route==="stored-get-throw")throw marker;return stored;},
  get credential(){
   credentialReads++;trace.push("context:credential:"+credentialReads);
   if(route==="credential-get-throw")throw marker;
   if(route==="changing-credential"){
    if(credentialReads===1)return {get type(){trace.push("credential:first-type");return "api_key";}};
    if(credentialReads===2)return {get type(){trace.push("credential:second-type");return "oauth";}};
    return {get access(){trace.push("credential:third-access");return "changed-access";}};
   }
   if(route==="credential-type-throw")return {get type(){trace.push("credential:type");throw marker;}};
   if(route==="credential-key-throw")return {type:"api_key",get key(){trace.push("credential:key");throw marker;}};
   if(route==="credential-access-throw")return {type:"oauth",get access(){trace.push("credential:access");throw marker;}};
   return h.currentCredential;
  },
  get allowNetwork(){trace.push("context:allowNetwork");if(route==="allow-throw")throw marker;return route!=="offline"&&route!=="stored-offline"&&route!=="legacy-offline";},
  get signal(){trace.push("context:signal");if(route==="signal-get-throw")throw marker;return h.signal;},
  get publish(){
   trace.push("publish:get");if(route==="publish-get-throw")throw marker;
   return function(input){
    publishes++;trace.push("publish:call:"+publishes+":"+(this===context)+":"+Object.keys(input).join(","));
    const update=input.update;h.updates.push(update);
    trace.push("update:shape:"+update.name+":"+update.length+":"+Object.hasOwn(update,"prototype"));
    if(input.persist)trace.push("persist:"+Object.keys(input.persist).join(",")+":"+(input.persist.models===h.legacy?"legacy":input.persist.models===h.refreshed?"refreshed":"unknown")+":"+input.persist.checkedAt);
    if(route==="publish-call-throw")throw marker;
    if(route!=="delayed-update"){update.call({wrong:true});trace.push("models:"+JSON.stringify(radiusProviderSummary(provider.getModels())));}
    return {get then(){
     trace.push("publish:then-get:"+publishes);if(route==="publish-then-throw")throw marker;
     return function(resolve,reject){trace.push("publish:adopt:"+publishes);
      if(route==="publish-reject"){reject(marker);return;}
      const stop=route==="stored-false"||route==="legacy-false"||route==="final-false";
      resolve(!stop);
     };
    }};
   };
  }
 };
 if(route==="aborted-get-throw")Object.defineProperty(h.signal,"aborted",{get(){trace.push("signal:aborted");throw marker;}});
 else if(route==="signal-aborted-order")Object.defineProperty(h.signal,"aborted",{get(){trace.push("signal:aborted");return false;}});
 try{
  try{
   const pending=provider.refreshModels.call({wrong:true},context);
   trace.push("caller:after-call");
   radiusProviderCheck(Object.getPrototypeOf(pending)===Promise.prototype,"genuine outer Promise");
   const returned=await pending;trace.push("caller:fulfilled");
   result={returnedUndefined:returned===undefined,models:radiusProviderSummary(provider.getModels()),publishes};
   if(route==="delayed-update"){
    result.delayed=[];
    for(let index=h.updates.length-1;index>=0;index--){h.updates[index]();result.delayed.push(radiusProviderSummary(provider.getModels()));}
   }
   if(h.filterCallback)result.escapedFilter=[h.filterCallback({provider:"chosen"}),h.filterCallback({provider:"other"})];
  }catch(error){trace.push("caller:rejected");result={thrown:error===marker?"marker":error?.name??typeof error,publishes,models:radiusProviderSummary(provider.getModels())};}
  return {trace,result};
 }finally{Object.defineProperty(Date,"now",originalNow);}
}

function radiusProviderMinimalImports(){
 return {
  piMessagesApi(){return {stream(){},streamSimple(){}};},
  envApiKeyAuth(){return {};},
  lazyOAuth(options){return options;},
  loadRadiusOAuth(){return {};},
  RADIUS_MODELS:{one:{id:"one",provider:"original"}},
  DEFAULT_RADIUS_GATEWAY:"https://radius.pi.dev",
  getRadiusModels(){return [];},
  getRadiusModelsFromConfig(id,config){return config.models;},
  loadRadiusGatewayConfig(){return {models:[]};},
  normalizeRadiusGatewayUrl(value){return value;}
 };
}
function radiusProviderPrepareAbandonedBlock(route){
 const h=radiusProviderHooks,imports=radiusProviderMinimalImports();
 imports.loadRadiusGatewayConfig=()=>{globalThis.radiusProviderLoadReached=true;return new Promise(()=>{});};
 if(route==="legacy")imports.getRadiusModels=()=>[{holder:h.make(1)}];
 const factory=radiusProviderMake(imports);
 const provider=factory();
 const context={
  holder:h.make(2),
  stored:route==="stored"?{holder:h.make(0),models:{filter(){return [{holder:h.make(1)}];}}}:undefined,
  credential:route==="legacy"?{type:"oauth",access:"key",holder:h.make(0)}:{type:"api_key",key:"key"},
  allowNetwork:true,signal:{aborted:false},
  publish(input){globalThis.radiusProviderRetainedUpdate=input.update;return Promise.resolve(true);}
 };
 // Neither the caller nor a test-owned queue retains the outer Promise.
 provider.refreshModels(context);
}
function radiusProviderPrepareAbandonedFinalPublish(){
 const h=radiusProviderHooks,imports=radiusProviderMinimalImports();
 imports.loadRadiusGatewayConfig=()=>({holder:h.make(0)});
 imports.getRadiusModelsFromConfig=()=>[{holder:h.make(1)}];
 const provider=radiusProviderMake(imports)();
 provider.refreshModels({
  holder:h.make(2),credential:{type:"api_key",key:"key"},allowNetwork:true,signal:{aborted:false},
  publish(input){globalThis.radiusProviderRetainedUpdate=input.update;globalThis.radiusProviderPublishReached=true;return new Promise(()=>{});}
 });
}
async function observeRadiusProviderActualFatal(){
 const h=radiusProviderHooks,imports=radiusProviderMinimalImports();
 const prior=h.freshPrivateData();
 radiusProviderCheck(h.isUnmarkedPrivateData(prior),"successful prior private DATA");
 imports.loadRadiusGatewayConfig=()=>h.raiseNativeFatal();
 const provider=radiusProviderMake(imports)();
 try{await provider.refreshModels({allowNetwork:true,signal:{aborted:false}});}
 catch(error){h.record.guestReached=true;h.visit(3);throw error;}
 h.record.guestReached=true;h.visit(3);
}
