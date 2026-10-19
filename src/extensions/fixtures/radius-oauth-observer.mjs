// Actual c268 Radius declarations are selected through controlled lexical
// imports. These observers never replace a production network/module owner.
function roCheck(condition,message){if(!condition)throw new Error("Radius OAuth control: "+message);}
function roAmbient(trace,control={}){
 class ObservedURL{
  constructor(path,base){
   trace.push("URL:new");
   if(control.urlThrow)throw control.marker;
   this.path=String(path);this.base=base===undefined?undefined:String(base);this._search="";
   trace.push(["URL:args",this.path,this.base]);
  }
  set search(value){trace.push("URL:search:set");this._search=value;}
  get search(){return this._search;}
  toString(){trace.push("URL:toString");if(control.urlTextThrow)throw control.marker;return this.path+(this._search?"?"+String(this._search):"");}
 }
 class ObservedParams{
  constructor(fields){
   trace.push(["params:new",Object.keys(fields)]);
   if(control.paramsThrow)throw control.marker;
   this.entries=Object.keys(fields).map(key=>[key,String(fields[key])]);
  }
  toString(){trace.push("params:toString");if(control.paramsTextThrow)throw control.marker;return this.entries.map(([k,v])=>k+"="+v).join("&");}
 }
 Object.defineProperty(globalThis,"URL",{value:ObservedURL,writable:true,configurable:true});
 Object.defineProperty(globalThis,"URLSearchParams",{value:ObservedParams,writable:true,configurable:true});
 Object.defineProperty(globalThis,"crypto",{value:{randomUUID(){trace.push("crypto:uuid");if(control.uuidThrow)throw control.marker;return "state-value";}},writable:true,configurable:true});
 Object.defineProperty(Date,"now",{configurable:true,writable:true,value(){trace.push("Date:now");if(control.nowThrow)throw control.marker;return control.nowValue===undefined?500000:control.nowValue;}});
}
function roImports(trace,control={}){
 return {
  normalizeRadiusGatewayUrl(value){trace.push(["normalize",value]);if(control.normalizeThrow)throw control.marker;return value;},
  generatePKCE(){trace.push("pkce:call");if(control.pkceThrow)throw control.marker;if(control.pkceReject)return Promise.reject(control.marker);
   return control.pair===undefined?{verifier:"verifier-value",challenge:"challenge-value"}:control.pair;},
  startOAuthCallbackServer(options){
   trace.push(["callback:start",Object.keys(options),options.providerName,options.host,options.port,options.path,options.state,options.signal===control.signal]);
   roCheck(options.complete.name==="complete"&&options.complete.length===1&&!roIsAsync(options.complete)&&!Object.hasOwn(options.complete,"prototype"),"ordinary complete arrow");
   if(control.captureComplete)control.captureComplete(options.complete);
   if(control.startThrow)throw control.marker;
   if(control.startReject)return Promise.reject(control.marker);
   return {
    wait(){trace.push("callback:wait");if(control.waitThrow)throw control.marker;if(control.waitReject)return Promise.reject(control.marker);return control.credential===undefined?{access:"browser-access"}:control.credential;},
    close(){trace.push("callback:close");if(control.closeThrow)throw control.closeMarker;}
   };
  },
  pollOAuthDeviceCodeFlow(options){
   trace.push(["poll:start",Object.keys(options),options.intervalSeconds,options.expiresInSeconds,options.signal===control.signal]);
   roCheck(options.poll.name==="poll"&&options.poll.length===0&&roIsAsync(options.poll)&&!Object.hasOwn(options.poll,"prototype"),"actual async poll arrow");
   if(control.capturePoll)control.capturePoll(options.poll);
   if(control.pollThrow)throw control.marker;
   return options.poll();
  }
 };
}
function roReason(reason,marker){
 if(reason===marker)return {identity:"marker"};
 if(reason===undefined)return {kind:"undefined"};
 if(reason===null||typeof reason!=="object")return {kind:typeof reason,value:String(reason)};
 return {name:reason.name,message:reason.message,status:reason.status,oauthError:reason.oauthError};
}
async function roSettle(trace,call,marker){
 try{
  const pending=call();trace.push("caller:after-call");
  roCheck(Object.getPrototypeOf(pending)===Promise.prototype,"genuine outer Promise");
  const value=await pending;trace.push("caller:fulfilled");
  return {trace,value};
 }catch(reason){trace.push("caller:rejected");return {trace,error:roReason(reason,marker)};}
}
function roData(trace,kind,route,marker){
 const defaults=kind==="token"?{access_token:"access",refresh_token:"refresh",expires_in:120,scope:"gateway"}:
  kind==="device"?{device_code:"device",user_code:"USER",verification_uri:"https://verify.example",expires_in:600,interval:5}:
  {authorizationEndpoint:"https://authorize.example"};
 const data={};let endpointReads=0;
 for(const [name,initial]of Object.entries(defaults))Object.defineProperty(data,name,{enumerable:true,configurable:true,get(){
  trace.push("data:"+name);
  if(route==="data-"+name+"-throw")throw marker;
  if(route==="missing-"+name)return undefined;
  if(name==="authorizationEndpoint"){
   endpointReads++;
   if(route==="invalid-endpoint")return 17;
   if(route==="changing-endpoint")return endpointReads===1?"https://first.example":"https://second.example";
  }
  if(name==="expires_in"&&route==="expiry-coerce")return {[Symbol.toPrimitive](hint){trace.push(["expiry:primitive",hint]);return 120;}};
  if(name==="expires_in"&&route==="expiry-throw")return {[Symbol.toPrimitive](hint){trace.push(["expiry:primitive",hint]);throw marker;}};
  return initial;
 }});
 return data;
}
async function observeRadiusOAuthHttp(kind,route){
 const trace=[],marker={tag:"http"},control={marker};
 if(route==="url-throw")control.urlThrow=true;
 if(route==="params-throw")control.paramsThrow=true;
 if(route==="date-throw")control.nowThrow=true;
 if(route==="date-object")control.nowValue={[Symbol.toPrimitive](hint){trace.push(["now:primitive",hint]);return "500000";}};
 roAmbient(trace,control);
 const imports=roImports(trace),s=roMake(imports);
 const signal={get aborted(){trace.push("signal:aborted");if(route==="aborted-throw")throw marker;return route==="cancelled";}};
 const data=roData(trace,kind,route,marker);
 const bad=route==="http-error"||route==="text-throw"||route==="text-reject"||route==="text-get-throw"||route==="status-throw";
 const response={
  get ok(){trace.push("response:ok");if(route==="ok-throw")throw marker;return !bad;},
  get status(){trace.push("response:status");if(route==="status-throw")throw marker;return 401;},
  get text(){trace.push("response:text:get");if(route==="text-get-throw")throw marker;return function(){
   roCheck(this===response,"text receiver");trace.push("response:text:call");
   if(route==="text-throw")throw marker;if(route==="text-reject")return Promise.reject(marker);
   return Promise.resolve('{"error":"access_denied","error_description":"reason"}');
  };},
  get json(){trace.push("response:json:get");if(route==="json-get-throw")throw marker;return function(){
   roCheck(this===response,"json receiver");trace.push("response:json:call");
   if(route==="json-throw")throw marker;if(route==="json-reject")return Promise.reject(marker);
   return data;
  };}
 };
 globalThis.fetch=function(url,init){
  trace.push(["fetch",url.path,url.base,Object.keys(init),Object.keys(init.headers),init.method,init.signal===signal,init.body?.entries??init.body]);
  if(route==="fetch-throw"||route==="cancelled"||route==="aborted-throw")throw marker;
  if(route==="fetch-reject")return Promise.reject(marker);
  return response;
 };
 const call=kind==="discovery"?()=>s.loadRadiusOAuthDiscovery("https://gateway.example",signal):
  kind==="token"?()=>s.requestOAuthToken("https://gateway.example","body-value",signal):
  ()=>s.requestDeviceAuthorization("https://gateway.example",signal);
 return roSettle(trace,call,marker);
}
async function observeRadiusOAuthReadError(route){
 const trace=[],marker={tag:"read"},control={marker};roAmbient(trace,control);
 const s=roMake(roImports(trace));
 let parsedReads=0;
 const data={
  get error(){trace.push("parsed:error");parsedReads++;if(route==="field-throw")throw marker;return route==="changing-error"&&parsedReads>1?17:route==="wrong-types"?17:"access_denied";},
  get error_description(){trace.push("parsed:description");return route==="wrong-types"?false:"explanation";}
 };
 const originalParse=JSON.parse;
 JSON.parse=function(text){trace.push(["JSON:parse",text]);if(route==="parse-throw")throw marker;return data;};
 const text=route==="empty"?"":"body text";
 const response={
  get status(){trace.push("response:status");if(route==="status-throw")throw marker;return 403;},
  get text(){trace.push("response:text:get");if(route==="text-get-throw")throw marker;return function(){
   trace.push("response:text:call");roCheck(this===response,"text receiver");
   if(route==="text-call-throw")throw marker;
   if(route==="text-reject")return Promise.reject(marker);
   if(route==="catch-get-throw")return {get catch(){trace.push("catch:get");throw marker;}};
   if(route==="catch-call-throw")return {catch(){trace.push("catch:call");throw marker;}};
   return Promise.resolve(text);
  };}
 };
 try{
  const observation=await roSettle(trace,()=>s.readOAuthResponseError(response,"Prefix"),marker);
  if(observation.value){const e=observation.value;observation.value={message:e.message,status:e.status,oauthError:e.oauthError,instance:e instanceof s.OAuthResponseError,fields:Object.keys(e)};}
  return observation;
 }finally{JSON.parse=originalParse;}
}
function observeRadiusOAuthClass(route){
 const trace=[],marker={tag:"class"};roAmbient(trace);
 const s=roMake(roImports(trace));let reason;
 let status=401,oauth="access_denied",description="description";
 if(route==="no-description")description="";
 if(route==="description-only")oauth="";
 if(route==="status-only"){oauth="";description="";}
 if(route==="detail-object"){description={[Symbol.toPrimitive](hint){trace.push(["description",hint]);return "object detail";}};}
 if(route==="detail-throw"){description={[Symbol.toPrimitive](hint){trace.push(["description",hint]);throw marker;}};}
 if(route==="status-object"){oauth="";description="";status={[Symbol.toPrimitive](hint){trace.push(["status",hint]);return 407;}};}
 try{const value=new s.OAuthResponseError(status,oauth,description,"Prefix");return {trace,value:{message:value.message,status:value.status===status,oauthError:value.oauthError,keys:Object.keys(value),extendsError:value instanceof Error}};}
 catch(e){reason=roReason(e,marker);}
 return {trace,error:reason};
}
async function observeRadiusOAuthBrowser(route){
 const trace=[],marker={tag:"browser"},closeMarker=new Error("close failure"),signal={aborted:false};
 const control={marker,closeMarker,signal};
 const flags={"pkce-throw":"pkceThrow","pkce-reject":"pkceReject","uuid-throw":"uuidThrow","url-throw":"urlThrow","params-throw":"paramsThrow","params-text-throw":"paramsTextThrow","start-throw":"startThrow","start-reject":"startReject","wait-throw":"waitThrow","wait-reject":"waitReject","close-throw":"closeThrow"};
 if(flags[route])control[flags[route]]=true;
 if(route==="falsy")control.credential=null;
 if(route==="wait-and-close"){control.waitReject=true;control.closeThrow=true;}
 if(route==="falsy-and-close"){control.credential=false;control.closeThrow=true;}
 if(route==="pkce-null")control.pair=null;
 if(route==="verifier-get-throw")control.pair={get verifier(){trace.push("pkce:verifier");throw marker;},get challenge(){trace.push("pkce:challenge");return "unused";}};
 roAmbient(trace,control);
 const interaction={
  get signal(){trace.push("interaction:signal");return signal;},
  get notify(){trace.push("notify:get");return function(input){
   roCheck(this===interaction,"notify receiver");trace.push(["notify",input.type,Object.keys(input),input.url??input.message]);
   if(route==="progress-throw"&&input.type==="progress")throw marker;
   if(route==="auth-notice-throw"&&input.type==="auth_url")throw marker;
  };}
 };
 const s=roMake(roImports(trace,control));
 return roSettle(trace,()=>s.loginWithBrowser("https://gateway.example","https://authorize.example",interaction),marker);
}
async function observeRadiusOAuthDevice(route){
 const trace=[],marker={tag:"device-flow"},signal={aborted:false},control={marker,signal};
 roAmbient(trace,control);
 const s=roMake(roImports(trace,control));
 const errorCode={"pending":"authorization_pending","slow":"slow_down","expired":"expired_token","denied":"access_denied","unknown":"invalid_request"}[route];
 let requests=0;
 globalThis.fetch=function(url,init){
  trace.push(["fetch",url.path,init.body.entries,init.signal===signal]);requests++;
  if(requests===1)return {ok:true,json(){trace.push("device:json");return {device_code:"device-value",user_code:"USER",verification_uri:"https://verify.example",expires_in:600,interval:5};}};
  if(route==="token-reject")return Promise.reject(marker);
  if(route==="token-throw")throw marker;
  if(errorCode)return {ok:false,status:400,text(){return Promise.resolve(JSON.stringify({error:errorCode}));}};
  return {ok:true,json(){trace.push("token:json");return {access_token:"access",refresh_token:"refresh",expires_in:120,scope:"scope"};}};
 };
 const interaction={get signal(){trace.push("interaction:signal");return signal;},get notify(){trace.push("notify:get");return function(input){
  roCheck(this===interaction,"notify receiver");trace.push(["notify",input.type,Object.keys(input),input.userCode,input.verificationUri,input.intervalSeconds,input.expiresInSeconds]);
  if(route==="notify-throw")throw marker;
 };}};
 return roSettle(trace,()=>s.loginWithDeviceCode("https://gateway.example",interaction),marker);
}
async function observeRadiusOAuthPublic(route){
 const trace=[],marker={tag:"public"},signal={aborted:false},control={marker,signal};roAmbient(trace,control);
 const imports=roImports(trace,control),s=roMake(imports);
 let names=0;
 const options={get gateway(){trace.push("options:gateway");if(route==="gateway-throw")throw marker;return "https://gateway.example";},get name(){trace.push("options:name");names++;if(route==="name-throw")throw marker;return route==="changing-name"?"Name"+names:"Radius";}};
 if(route==="normalize-throw")control.normalizeThrow=true;
 let oauth;
 try{oauth=s.createRadiusOAuth(options);trace.push("factory:returned");}
 catch(e){return {trace,error:roReason(e,marker)};}
 const interaction={
  get signal(){trace.push("interaction:signal");return signal;},
  prompt(input){trace.push(["prompt",input.type,input.message,input.options]);roCheck(this===interaction,"prompt receiver");
   if(route==="prompt-throw")throw marker;if(route==="prompt-reject")return Promise.reject(marker);
   if(route==="method-object")return {[Symbol.toPrimitive](hint){trace.push(["method",hint]);return "object-method";}};
   return route==="device"?"device-code":route==="browser"?"browser":"unknown";
  },
  notify(input){trace.push(["notify",input.type]);}
 };
 globalThis.fetch=function(url,init){
  trace.push(["fetch",url.path,init.body?.entries,init.signal===signal]);
  if(url.path==="/v1/oauth")return {ok:true,json(){return {authorizationEndpoint:"https://authorize.example"};}};
  if(url.path==="/v1/oauth/device")return {ok:true,json(){return {device_code:"d",user_code:"u",verification_uri:"v",expires_in:10,interval:1};}};
  return {ok:true,json(){return {access_token:"a",refresh_token:"r",expires_in:100,scope:"s"};}};
 };
 if(route==="refresh")return roSettle(trace,()=>oauth.refresh({get refresh(){trace.push("credential:refresh");return "refresh-secret";}},signal),marker);
 if(route==="to-auth"||route==="to-auth-throw")return roSettle(trace,()=>oauth.toAuth({get access(){trace.push("credential:access");if(route==="to-auth-throw")throw marker;return "access-secret";}}),marker);
 return roSettle(trace,()=>oauth.login(interaction),marker);
}
async function observeRadiusOAuthComplete(){
 const trace=[],marker={tag:"complete"},signal={aborted:false},control={marker,signal};roAmbient(trace,control);
 let complete;control.captureComplete=call=>{complete=call;};
 globalThis.fetch=function(url,init){trace.push(["fetch",url.path,init.body.entries,init.signal===signal]);return {ok:true,json(){return {access_token:"a",refresh_token:"r",expires_in:100};}};};
 const s=roMake(roImports(trace,control));
 await s.loginWithBrowser("https://gateway.example","https://authorize.example",{signal,notify(input){trace.push(["notify",input.type]);}});
 roCheck(typeof complete==="function","escaped complete arrow exists");
 return roSettle(trace,()=>complete("actual-code"),marker);
}
async function observeRadiusOAuthActualFatal(){
 const h=roHooks,trace=[];roAmbient(trace);
 const prior=h.freshPrivateData();roCheck(h.isUnmarkedPrivateData(prior),"prior successful private DATA");
 const s=roMake(roImports(trace));
 globalThis.fetch=()=>h.raiseNativeFatal();
 const signal={get aborted(){h.record.guestReached=true;h.visit(3);return false;}};
 try{await s.requestOAuthToken("https://gateway.example","body",signal);}
 catch(reason){h.record.guestReached=true;h.visit(3);throw reason;}
 h.record.guestReached=true;h.visit(3);
}

async function observeRadiusOAuthExplicitThrow(route,reason,progress){
 const trace=[];roAmbient(trace);
 const OriginalError=Error;
 function ReturnedError(){progress.constructed++;return reason;}
 ReturnedError.prototype=OriginalError.prototype;
 // HTTP's lexical class captures this actual superclass. A successful Error
 // return is still DATA; only the selected Source throw makes it pending.
 if(route==="http-error")globalThis.Error=ReturnedError;
 const imports=roImports(trace);imports.startOAuthCallbackServer=()=>({wait(){return null;},close(){progress.closed=true;}});
 const s=roMake(imports);
 globalThis.Error=ReturnedError;
 const marker={tag:"ordinary"};
 const signal={aborted:route==="cancelled"};
 globalThis.fetch=()=>{
  if(route==="cancelled")throw marker;
  if(route==="device-required")return {ok:true,json(){return {};}};
  return {ok:false,status:401,text(){return Promise.resolve('{"error":"denied"}');}};
 };
 const call=route==="discovery"?()=>s.loadRadiusOAuthDiscovery("g",signal):
  route==="cancelled"?()=>s.requestOAuthToken("g","body",signal):
  route==="device-required"?()=>s.requestDeviceAuthorization("g",signal):
  route==="http-error"?()=>s.requestOAuthToken("g","body",signal):
  route==="browser-falsy"?()=>s.loginWithBrowser("g","a",{signal,notify(){}}):
  ()=>s.createRadiusOAuth({name:"Radius",gateway:"g"}).login({prompt(){return "unknown";}});
 try{await call();}
 catch(error){progress.guestReached=true;throw error;}
 progress.guestReached=true;
}
