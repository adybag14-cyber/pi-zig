// Test guest only: actual Source14 supplied-client protocol replay with the same whole-byte reader input.
function snapshot(value){if(ArrayBuffer.isView(value))return{$bytes:[...value]};if(Array.isArray(value))return value.map(snapshot);if(value&&typeof value==='object'){const result={};for(const[key,item]of Object.entries(value)){if(value.role==='assistant'&&key==='timestamp')result[key]='$TIMESTAMP';else if(value.role==='assistant'&&key==='durationMs')result[key]='$DURATION';else result[key]=snapshot(item)}return result}return value}

export async function runSupplied(source,api){
if(source.cases!==14||source.sourceHead!=='5ab7fe74c400097b386662205cd93900695b8a71')throw Error('actual Source14 required');
const {model,context,wire}=source;const expected=source.rows.filter(row=>row.input.supplied);const cases=expected.map(row=>row.input);
const rows=[];
for(const item of cases){
  const trace=[],events=[],payloads=[],responses=[],sdkCalls=[],fetchCalls=[];
  const controller=new AbortController();
  const sourceSignal=controller.signal;
  const add=sourceSignal.addEventListener,remove=sourceSignal.removeEventListener;
  sourceSignal.addEventListener=function(type,callback,options){trace.push('signal:add:'+type+':'+options?.once);return add.call(this,type,callback,options)};
  sourceSignal.removeEventListener=function(type,callback){trace.push('signal:remove:'+type);return remove.call(this,type,callback)};
  if(item.preabort)controller.abort(new Error('owned preabort'));
  const headers=new Headers([['x-owned','sdk'],['constructor','owned-constructor'],['__proto__','owned-proto']]);
  let consumed=false;
  const reader={read(){trace.push('reader:read');if(consumed)return Promise.resolve({value:undefined,done:true});consumed=true;return Promise.resolve({value:new TextEncoder().encode(wire),done:false})},releaseLock(){trace.push('reader:release');if(item.releaseThrows)throw Error('owned release failed')}};
  const response={get status(){trace.push('response:status');if(item.forbidMetadata)throw Error('status must not be read without hook');return item.status??200},get headers(){trace.push('response:headers');if(item.forbidMetadata)throw Error('headers must not be read without hook');return headers},body:{getReader(){trace.push('body:getReader');return reader}}};
  const client={beta:{messages:{create(params,options){sdkCalls.push({params:snapshot(params),requestOptions:{keys:Object.keys(options),maxRetries:options.maxRetries,signalSame:options.signal===sourceSignal,...(options.timeout!==undefined?{timeout:options.timeout}:{})}});trace.push('sdk:create');return {asResponse(){trace.push('sdk:asResponse');return Promise.resolve(response)}}}}}};
  const options={apiKey:'fixture-placeholder-key',env:{},maxTokens:1000,maxRetries:0,signal:sourceSignal,...(item.timeout?{timeoutMs:5}:{}),
    onPayload(params){trace.push('payload');payloads.push(snapshot(params));if(item.abortPayload)controller.abort(new Error('owned payload abort'));if(item.formatConflict)return{...params,output_format:{type:'json_schema',schema:{}},output_config:{format:{type:'json_schema',schema:{}}}}},
    onProviderStreamEvent(chunk){trace.push('chunk:'+chunk.type);if(item.hookThrows)throw Error('owned hook failed')},
  };
  const responseCallback=function(metadata){trace.push('response:callback');responses.push(snapshot(metadata));if(this!==options)throw Error('response callback receiver')};
  if(!item.noResponseHook){if(item.captureHook)Object.defineProperty(options,'onResponse',{configurable:true,get(){trace.push('response:hook-get');Object.defineProperty(options,'onResponse',{value(){throw Error('second hook must not run')},writable:true,configurable:true});return responseCallback}});else options.onResponse=responseCallback}
  if(item.supplied)options.client=client;
  else options.fetch=function(url,init){fetchCalls.push({url,keys:Object.keys(init),method:init.method,body:init.body,headers:Object.fromEntries(init.headers.entries()),headersBrand:init.headers instanceof Headers,signalBrand:init.signal instanceof AbortSignal,signalFresh:init.signal!==sourceSignal,receiverUndefined:this===undefined,signalAborted:init.signal.aborted});trace.push('fetch');if(item.networkReject)return Promise.reject(Error('owned network failure'));if(item.timeout)return new Promise((_,reject)=>init.signal.addEventListener('abort',()=>reject(new DOMException('owned timeout','AbortError')),{once:true}));const value=new Response(item.status===304?null:item.status===403?'owned denied':wire,{status:item.status??200,headers});if(item.textReject)value.text=()=>Promise.reject(Error('owned body read failed'));return Promise.resolve(value)};
  const stream=api.stream(model,context,options);
  for await(const event of stream)events.push(snapshot(event));
  const result=snapshot(await stream.result());
  if(item.preabort&&payloads.length)throw Error('preabort reached payload');
  if((item.preabort||(!item.supplied&&item.abortPayload))&&fetchCalls.length)throw Error('aborted request reached fetch');
  rows.push({name:item.name,input:item,trace:[...trace],payloads,responses,sdkCalls,fetchCalls,events,result});
}

if(rows.length!==7)throw Error('all seven supplied-client Source cases required');
for(let index=0;index<rows.length;index++){const actual=rows[index],wanted=expected[index];for(const key of ['name','trace','payloads','responses','sdkCalls','fetchCalls','events','result'])if(JSON.stringify(actual[key])!==JSON.stringify(wanted[key]))throw Error(JSON.stringify({name:actual.name,key,actual:actual[key],expected:wanted[key]}));}return true;}

