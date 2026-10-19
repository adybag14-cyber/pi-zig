function radiusConfigCheck(ok,message){if(!ok)throw new Error(message);}
function radiusCapture(action,marker){try{return {value:action()};}catch(error){return {thrown:error===marker?"marker":error?.name??typeof error,message:error===marker?null:error?.message??null};}}
function radiusModel(){return {id:"model-a",name:"Model A",reasoning:true,input:["text"],cost:{input:1,output:2},contextWindow:32768,maxTokens:4096};}
function observeRadiusNormalize(s,route){
 const trace=[],marker={failure:route},RealRegExp=RegExp,descriptor=Object.getOwnPropertyDescriptor(RealRegExp.prototype,"test");
 let input;
 try{
  if(route==="values")return ["host///","HTTP://Host///","https://host/x/","",undefined,null,7].map(value=>radiusCapture(()=>s.normalizeRadiusGatewayUrl(value),marker));
  if(route==="symbol")return radiusCapture(()=>s.normalizeRadiusGatewayUrl(Symbol("gateway")),marker);
  input={[Symbol.toPrimitive](hint){trace.push("hint:"+hint);if(route==="stringify-throw")throw marker;return route==="replace-get-throw"?"https://host/":"host/";}};
  if(route==="coercion")return {trace,result:radiusCapture(()=>s.normalizeRadiusGatewayUrl(input),marker)};
  globalThis.RegExp=function(){throw new Error("Global RegExp must not construct a literal");};
  if(route==="test-get-throw")Object.defineProperty(RealRegExp.prototype,"test",{configurable:true,get(){trace.push("test-get");throw marker;}});
  else Object.defineProperty(RealRegExp.prototype,"test",{configurable:true,get(){trace.push("test-get:"+this.source+":"+this.flags);return function(value){trace.push("test-call:"+(value===input));return route==="replace-get-throw"||route==="live-methods";};}});
  if(route==="replace-get-throw"||route==="live-methods")Object.defineProperty(input,"replace",{get(){trace.push("replace-get");if(route==="replace-get-throw")throw marker;return function(regex,replacement){trace.push("replace-call:"+(this===input)+":"+regex.source+":"+regex.flags+":"+replacement);return "replaced";};}});
  return {trace,result:radiusCapture(()=>s.normalizeRadiusGatewayUrl(input),marker)};
 }finally{globalThis.RegExp=RealRegExp;Object.defineProperty(RealRegExp.prototype,"test",descriptor);}
}
function observeRadiusModel(s,route){
 const trace=[],marker={failure:route},RealArray=Array,arrayDescriptor=Object.getOwnPropertyDescriptor(globalThis,"Array");
 if(route==="invalid-values")return [undefined,null,7,"x",false,()=>{},[],{},Object.assign(radiusModel(),{reasoning:1}),Object.assign(radiusModel(),{cost:[]})].map(value=>s.isRadiusGatewayModel(value));
 const original=radiusModel(),model={};let costReads=0;
 for(const name of Object.keys(original))Object.defineProperty(model,name,{enumerable:true,get(){trace.push(name);if(route===name+"-throw")throw marker;if(name==="cost"&&route==="changing-cost")return ++costReads===1?null:{};return original[name];}});
 try{
  if(route==="array-order")Object.defineProperty(globalThis,"Array",{configurable:true,get(){trace.push("Array");const receiver={get isArray(){trace.push("isArray-get");return function(value){trace.push("isArray-call:"+(this===receiver));return RealArray.isArray(value);};}};return receiver;}});
  return {trace,result:radiusCapture(()=>s.isRadiusGatewayModel(model),marker)};
 }finally{Object.defineProperty(globalThis,"Array",arrayDescriptor);}
}
function observeRadiusSanitize(s,route){
 const trace=[],marker={failure:route};
 if(route==="invalid")return [undefined,null,[],()=>{},1,{}, {baseUrl:7,models:[]},{baseUrl:"x",models:{}}].map(value=>s.sanitizeRadiusGatewayConfig(value));
 const model=radiusModel(),models=[model],config={};
 Object.defineProperty(config,"baseUrl",{get(){trace.push("baseUrl");if(route==="base-throw")throw marker;return "https://gateway";}});
 Object.defineProperty(config,"models",{get(){trace.push("models");if(route==="models-throw")throw marker;return models;}});
 if(route==="identity")s.isRadiusGatewayModel=()=>{throw marker;};
 if(route==="spread"){
  const symbol=Symbol("extra");Object.setPrototypeOf(model,{inherited:1});
  Object.defineProperty(model,"hidden",{value:2});Object.defineProperty(model,symbol,{enumerable:true,get(){trace.push("symbol");return 3;}});
  Object.defineProperty(model,"__proto__",{enumerable:true,value:"own"});
  const result=s.sanitizeRadiusGatewayConfig(config),copy=result.models[0];
  return {trace,base:result.baseUrl,copy:copy!==model,cost:copy.cost===model.cost,input:copy.input===model.input,keys:Reflect.ownKeys(copy).map(key=>typeof key==="symbol"?"symbol":key),symbol:copy[symbol],normalPrototype:Object.getPrototypeOf(copy)===Object.prototype,ownProto:copy.__proto__,hidden:Object.hasOwn(copy,"hidden")};
 }
 Object.defineProperty(models,"filter",{get(){trace.push("filter-get");if(route==="filter-throw")throw marker;return function(predicate){trace.push("filter-call:"+(this===models)+":"+predicate.name+":"+Object.hasOwn(predicate,"prototype"));const selected=predicate(model);trace.push("selected:"+selected);return {get map(){trace.push("map-get");if(route==="map-throw")throw marker;return function(copy){trace.push("map-call:"+copy.name+":"+copy.length+":"+Object.hasOwn(copy,"prototype"));return selected?[copy(model)]:[];};}};};}});
 return {trace,result:radiusCapture(()=>s.sanitizeRadiusGatewayConfig(config),marker)};
}
function observeRadiusModels(s,route){
 const trace=[],marker={failure:route},provider={id:"provider-id"};
 if(route==="credential")return [undefined,null,{}, {gatewayConfig:{baseUrl:"g",models:[radiusModel()]}}].map(value=>s.getRadiusCredentialConfig(value));
 if(route==="legacy")return [undefined,null,{}, {gatewayConfig:{baseUrl:"g",models:[radiusModel()]}}].map(value=>s.getRadiusModels("provider",value));
 if(route==="credential-throw")return radiusCapture(()=>s.getRadiusModels(provider,{get gatewayConfig(){trace.push("gatewayConfig");throw marker;}}),marker);
 const first=radiusModel(),second=Object.assign(radiusModel(),{id:"model-b"}),models=[first,second],config={};let reads=0,saved;
 Object.defineProperty(config,"baseUrl",{get(){trace.push("baseUrl:"+ ++reads);if(route==="base-throw")throw marker;return "gateway-"+reads;}});
 Object.defineProperty(config,"models",{get(){trace.push("models");return models;}});
 if(route==="spread-throw")Object.defineProperty(first,"extra",{enumerable:true,get(){trace.push("extra");throw marker;}});
 if(route==="escaped-map")Object.defineProperty(models,"map",{get(){trace.push("map-get");return function(callback){trace.push("map-call:"+(this===models));saved=callback;return "retained";};}});
 const result=radiusCapture(()=>s.getRadiusModelsFromConfig(provider,config),marker);
 if(route==="escaped-map"){
  radiusConfigCheck(result.value==="retained","real live map return");
  const mapped=saved(first);return {trace,result:result.value,providerSame:mapped.provider===provider,base:mapped.baseUrl,id:mapped.id,prototype:Object.getPrototypeOf(mapped)===Object.prototype};
 }
 return {trace,result};
}
function observeRadiusTruncate(s,route){
 const trace=[],marker={failure:route};
 if(route==="strings")return ["","  small\n","\t"+"x".repeat(513)+"  "].map(value=>s.truncateHttpBody(value));
 if(route==="unicode")return ["x"+"😀".repeat(256),"\u2003"+"é".repeat(513)+"\u2003"].map(value=>s.truncateHttpBody(value));
 if(route==="exact-limit")return [511,512,513].map(length=>s.truncateHttpBody(" "+ "x".repeat(length)+" "));
 const sliceResult={[Symbol.toPrimitive](hint){trace.push("hint:"+hint);if(route==="hint-throw")throw marker;return "cut";}};
 const trimmed={get length(){trace.push("length");if(route==="length-throw")throw marker;return {[Symbol.toPrimitive](hint){trace.push("length-hint:"+hint);return 513;}};},
  get slice(){trace.push("slice-get");if(route==="slice-throw")throw marker;return function(begin,end){trace.push("slice-call:"+(this===trimmed)+":"+begin+":"+end);return sliceResult;};}};
 const body={get trim(){trace.push("trim-get");return function(){trace.push("trim-call:"+(this===body));return trimmed;};}};
 const originalString=String;globalThis.String=function(){throw new Error("Intrinsic conversion must not call global String");};
 try{return {trace,result:radiusCapture(()=>s.truncateHttpBody(body),marker)};}finally{globalThis.String=originalString;}
}

async function observeRadiusLoad(s,route){
 const trace=[],marker={failure:route},errorData={kind:"returned-error-data"};
 const RealError=Error,RealPromise=Promise;
 const globals={};for(const name of ["fetch","URL","Error"])globals[name]=Object.getOwnPropertyDescriptor(globalThis,name);
 const authorization=Object.getOwnPropertyDescriptor(Object.prototype,"authorization");
 const signal={kind:"signal"};
 let gateway=route==="gateway-hint"?{[Symbol.toPrimitive](hint){trace.push("gateway:hint:"+hint);return "https://gateway.test";}}:"https://gateway.test";
 let apiKey=route==="no-key"?undefined:{[Symbol.toPrimitive](hint){trace.push("key:hint:"+hint);return "key-token";}};
 const httpRoutes=new Set(["http-failure","error-rebound","gateway-hint","status-hint","long-body","text-get-throw","text-throw","text-reject","trim-throw","status-throw","error-data","error-constructor-throw"]);
 const failed=httpRoutes.has(route);
 let payload={baseUrl:"https://api.test/v1",models:[radiusModel(),null]};
 if(route==="invalid-config")payload=null;
 if(route==="invalid-models")payload={baseUrl:"https://api.test",models:{}};
 if(route==="invalid-base"||route==="invalid-error-data")payload={baseUrl:7,models:[]};
 if(route==="sanitize-throw")payload={get baseUrl(){trace.push("sanitize:baseUrl");throw marker;},models:[]};
 const body=route==="long-body"?"  "+"x".repeat(520)+"  ":route==="trim-throw"?{get trim(){trace.push("body:trim-get");throw marker;}}:"  failure body  ";
 const status=route==="status-hint"?{[Symbol.toPrimitive](hint){trace.push("status:hint:"+hint);return "429";}}:503;
 const thenable=(kind,value,reject)=>({get then(){trace.push(kind+":then-get");return function(resolve,fail){trace.push(kind+":adopt");(reject?fail:resolve)(reject?marker:value);};}});
 function SelectedError(message){
  trace.push("error:construct:"+message);
  if(route==="error-constructor-throw")throw marker;
  if(route==="error-data"||route==="invalid-error-data")return errorData;
  return new RealError(message);
 }
 const response={
  get ok(){trace.push("response:ok");if(route==="ok-throw")throw marker;return !failed;},
  get status(){trace.push("response:status");if(route==="status-throw")throw marker;return status;},
  get json(){
   trace.push("response:json-get");if(route==="json-get-throw")throw marker;
   return function(){trace.push("response:json-call:"+(this===response));if(route==="json-throw")throw marker;return thenable("json",payload,route==="json-reject");};
  },
  get text(){
   trace.push("response:text-get");if(route==="text-get-throw")throw marker;
   return function(){
    trace.push("response:text-call:"+(this===response));
    if(route==="text-throw")throw marker;
    if(route==="error-rebound")Object.defineProperty(globalThis,"Error",{configurable:true,value:function ReboundError(){trace.push("wrong:rebound-error");return marker;}});
    return thenable("text",body,route==="text-reject");
   };
  }
 };
 function URL(path,base){trace.push("url:construct:"+path+":"+(base===gateway));if(route==="url-throw")throw marker;this.path=path;this.base=base;}
 function fetch(url,init){
  trace.push("fetch:call:"+(this===undefined));
  trace.push("request:"+url.path+":"+Object.keys(init).join(",")+":"+Object.keys(init.headers).join(",")+":"+init.headers.accept+":"+(init.signal===signal));
  if(Object.hasOwn(init.headers,"authorization"))trace.push("authorization:"+init.headers.authorization);
  if(route==="fetch-throw")throw marker;
  return thenable("fetch",response,route==="fetch-reject");
 }
 try{
  Object.defineProperty(globalThis,"fetch",{configurable:true,get(){trace.push("fetch:get");if(route==="fetch-get-throw")throw marker;return fetch;}});
  Object.defineProperty(globalThis,"URL",{configurable:true,get(){trace.push("url:get");if(route==="url-get-throw")throw marker;return URL;}});
  Object.defineProperty(globalThis,"Error",{configurable:true,get(){trace.push("error:get");return SelectedError;}});
  if(route==="authorization-setter")Object.defineProperty(Object.prototype,"authorization",{configurable:true,set(value){trace.push("authorization:set:"+value+":"+this.accept);}});
  let result;
  try{
   const pending=s.loadRadiusGatewayConfig(gateway,apiKey,signal);
   trace.push("caller:after-call");
   radiusConfigCheck(Object.getPrototypeOf(pending)===RealPromise.prototype,"load must return its intrinsic async Promise");
   const value=await pending;
   trace.push("caller:fulfilled");
   result={value};
  }catch(error){
   trace.push("caller:rejected");
   result={thrown:error===marker?"marker":error===errorData?"data":error?.name??typeof error,message:error===marker||error===errorData?null:error?.message??null};
  }
  return {trace,result};
 }finally{
  for(const name of ["fetch","URL","Error"]){if(globals[name])Object.defineProperty(globalThis,name,globals[name]);else delete globalThis[name];}
  if(authorization)Object.defineProperty(Object.prototype,"authorization",authorization);else delete Object.prototype.authorization;
 }
}

async function observeRadiusActualFatal(s,hooks){
 const progress=hooks.record;
 globalThis.URL=function(){return {};};
 globalThis.fetch=()=>{const data=hooks.freshPrivateData();try{hooks.raiseNativeFatal();}catch{progress.guestReached=true;}throw data;};
 try{await s.loadRadiusGatewayConfig("gateway");}catch{progress.guestReached=true;hooks.visit(3);}
}
async function observeRadiusExplicitErrorThrow(s,route,reason,progress){
 globalThis.URL=function(){return {};};
 globalThis.fetch=()=>Promise.resolve(route==="http"?{ok:false,status:503,text(){return Promise.resolve("body");}}:{ok:true,json(){return Promise.resolve(null);}});
 globalThis.Error=function(message){progress.constructed++;progress.message=message;return reason;};
 try{await s.loadRadiusGatewayConfig("gateway");progress.guestReached=true;}catch{progress.guestReached=true;}
}
