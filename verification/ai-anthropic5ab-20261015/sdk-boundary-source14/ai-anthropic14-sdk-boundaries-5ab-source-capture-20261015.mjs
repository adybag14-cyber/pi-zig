import {readFileSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const api = await import('file:///C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015/packages/ai/src/api/anthropic-messages.ts');
const cases = [
  {name:'supplied-status403',supplied:true,status:403},
  {name:'supplied-no-response-hook-getters',supplied:true,noResponseHook:true,forbidMetadata:true},
  {name:'supplied-response-hook-getter-capture',supplied:true,captureHook:true},
  {name:'supplied-output-format-conflict',supplied:true,formatConflict:true},
  {name:'supplied-release-throws',supplied:true,releaseThrows:true},
  {name:'supplied-hook-and-release-throw',supplied:true,releaseThrows:true,hookThrows:true},
  {name:'default-fetch304',status:304},
  {name:'default-fetch-error-text-reject',status:403,textReject:true},
  {name:'default-fetch-network-reject',networkReject:true},
  {name:'default-fetch-timeout',timeout:true},
  {name:'preaborted-request',preabort:true},
  {name:'supplied-abort-in-payload',supplied:true,abortPayload:true},
  {name:'default-abort-in-payload',abortPayload:true},
  {name:'default-fresh-fetch-signal'},
];
const baseUrl='https://fixture.invalid';
const model={id:'claude-sonnet-4-6',name:'Claude Sonnet 4.6',provider:'anthropic',api:'anthropic-messages',baseUrl,input:['text'],reasoning:true,cost:{input:1,output:2,cacheRead:.5,cacheWrite:1.5},contextWindow:32000,maxTokens:8192,compat:{forceAdaptiveThinking:true}};
const context={messages:[{role:'user',content:'hello',timestamp:1}]};
const chunks=[{type:'message_start',message:{id:'owned-sdk-message',model:model.id,usage:{input_tokens:10,output_tokens:0}}},{type:'content_block_start',index:0,content_block:{type:'text',text:''}},{type:'content_block_delta',index:0,delta:{type:'text_delta',text:'answer'}},{type:'content_block_stop',index:0},{type:'message_delta',delta:{stop_reason:'end_turn'},usage:{output_tokens:2}},{type:'message_stop'}];
const wire=chunks.map(chunk=>'event: '+chunk.type+'\ndata: '+JSON.stringify(chunk)+'\n\n').join('');
function snapshot(value){if(ArrayBuffer.isView(value))return{$bytes:[...value]};if(Array.isArray(value))return value.map(snapshot);if(value&&typeof value==='object'){const result={};for(const[key,item]of Object.entries(value)){if(value.role==='assistant'&&key==='timestamp')result[key]='$TIMESTAMP';else if(value.role==='assistant'&&key==='durationMs')result[key]='$DURATION';else result[key]=snapshot(item)}return result}return value}
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
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'5ab7fe74c400097b386662205cd93900695b8a71',driverSha256:createHash('sha256').update(readFileSync(import.meta.filename)).digest('hex'),actualNode:{execPath:process.execPath,version:process.version,pid:process.pid},cases:rows.length,fundedProviderRequests:0,scope:'Actual public Source5ab stream + pinnedSDK; caller-supplied SDK protocols, genuine Headers/Response/AbortSignal, controlled custom fetch only; no network or real credentials. Original SDK runtime diagnostic request headers retained. Trace is copied at result boundary; deferred GC signal cleanup is a separate unqualified surface.',model,context,chunks,wire,rows},null,2));