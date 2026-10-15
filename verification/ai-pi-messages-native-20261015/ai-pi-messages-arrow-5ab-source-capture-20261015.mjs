import { writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { once } from 'node:events';
import * as api from 'file:///C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015/packages/ai/src/api/pi-messages.ts';
const rows=[];
for(const name of ['stream','streamSimple']){
  const value=api[name];
  let construction;
  try {new value();construction='constructed';}catch(error){construction={name:error.name,message:error.message};}
  const descriptors={};
  for(const key of Reflect.ownKeys(value)){const d=Object.getOwnPropertyDescriptor(value,key);descriptors[String(key)]={...(Object.hasOwn(d,'value')?{value:d.value}:{}),writable:d.writable,enumerable:d.enumerable,configurable:d.configurable};}
  rows.push({name,prototypeIsFunctionPrototype:Object.getPrototypeOf(value)===Function.prototype,ownKeys:Reflect.ownKeys(value).map(String),descriptors,construction});
}
const usage={input:2,output:3,cacheRead:0,cacheWrite:0,totalTokens:5,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}};
const terminal={type:'done',reason:'stop',usage,responseId:'wire-response'};
const cases=[
 {name:'wire-default-success',status:200,statusText:'OK',body:'data: {"type":"start"}\r\n\r\ndata: {"type":"text_start","contentIndex":0}\n\ndata: {"type":"text_delta","contentIndex":0,"delta":"wire"}\n\ndata: '+JSON.stringify(terminal)+'\n\n'},
 {name:'wire-http-structured',status:403,statusText:'Fixture Denied',body:'{"error":{"message":"denied","code":"fixture"}}'},
 {name:'wire-eof-terminal',status:200,statusText:'OK',body:'data: '+JSON.stringify(terminal)},
 {name:'wire-no-body204',status:204,statusText:'No Content',body:''}
];
const snapshot=value=>JSON.parse(JSON.stringify(value,(key,item)=>key==='stack'&&typeof item==='string'?'<stack>':key==='durationMs'&&typeof item==='number'?'<duration>':item));
let current,requests,origin;
const server=createServer(async(req,res)=>{try{let rawBody='';for await(const part of req)rawBody+=part;requests.push({url:new URL(req.url,origin).href,path:req.url,method:req.method,rawBody,body:JSON.parse(rawBody),headers:Object.fromEntries(['authorization','accept','content-type','x-test'].map(key=>[key,req.headers[key]])),rawHeaders:req.headers});res.writeHead(current.status,current.statusText,{'content-type':'text/event-stream','x-fixture':'source-only','connection':'close'});res.end(current.body);}catch(error){res.destroy(error)}});
server.listen(0,'127.0.0.1');await once(server,'listening');origin=`http://127.0.0.1:${server.address().port}`;
const savedNow=Date.now;Date.now=()=>123456789;
try{for(current of cases){requests=[];const model={id:'wire-model',api:'pi-messages',provider:'test-pi',baseUrl:origin+'/v1///'},context={messages:[{role:'user',content:'wire request',timestamp:9}]},options={apiKey:'fixture-key',headers:{'x-test':'yes'},maxTokens:0,cacheRetention:'none'},events=[],order=[];const stream=api.stream(model,context,{...options,onPayload(payload,seen){if(payload.context!==context||seen!==model)throw Error('literal identity');order.push('payload')},onResponse(response){order.push('response:'+response.status+':'+response.headers['x-fixture'])},onProviderStreamEvent(event){order.push('provider:'+event.type)}});let partial;for await(const event of stream){if(event.partial){if(partial&&partial!==event.partial)throw Error('partial alias');partial=event.partial}events.push(snapshot(event));}const result=await stream.result();if(partial&&partial!==result)throw Error('terminal alias');if(requests.length!==1)throw Error('one genuine request required');rows.push(snapshot({name:current.name,input:{model,context,options},requests,events,result,order}));}}
finally{Date.now=savedNow;server.closeAllConnections();await new Promise((resolve,reject)=>server.close(error=>error?reject(error):resolve()));}
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'5ab7fe74c400097b386662205cd93900695b8a71',actualNode:{execPath:process.execPath,version:process.version,pid:process.pid},cases:rows.length,scope:'Two original arrow descriptor controls and four supplemental genuine default-wire controls with original method/full URL/path/query/raw body retained. Original Source22 data is unchanged.',rows},null,2));
