import { createServer } from 'node:http';
import { once } from 'node:events';
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import * as api from 'file:///C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015/packages/ai/src/api/pi-messages.ts';

const inputPath='C:/Users/adyba/pi-zig-ai-pi-messages-20261015/src/extensions/fixtures/ai-pi-messages-5ab.input.txt';
const input=readFileSync(inputPath,'utf8');
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
await new AsyncFunction('piMessagesAPI',input)(api);
const rows=globalThis.piMessagesRows;
if(rows.length!==18)throw Error('18 original supplied-fetch controls required');
const originalNow=Date.now;
const snapshot=value=>JSON.parse(JSON.stringify(value,(key,item)=>key==='stack'&&typeof item==='string'?'<stack>':key==='durationMs'&&typeof item==='number'?'<duration>':item));
let active;
let requests;
const usage={input:2,output:3,cacheRead:0,cacheWrite:0,totalTokens:5,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}};
const terminal={type:'done',reason:'stop',usage,responseId:'wire-response'};
const server=createServer(async(req,res)=>{
  try {
    let body='';for await(const part of req)body+=part;
    requests.push({path:req.url,body:JSON.parse(body),headers:Object.fromEntries(['authorization','accept','content-type','x-test'].map(key=>[key,req.headers[key]]))});
    res.writeHead(active.status,active.statusText,{'content-type':'text/event-stream','x-fixture':'source-only','connection':'close'});
    res.end(active.body);
  } catch(error) {res.destroy(error);}
});
server.listen(0,'127.0.0.1');await once(server,'listening');
try {
  Date.now=()=>123456789;
  const cases=[
    {name:'wire-default-success',status:200,statusText:'OK',body:'data: {"type":"start"}\r\n\r\ndata: {"type":"text_start","contentIndex":0}\n\ndata: {"type":"text_delta","contentIndex":0,"delta":"wire"}\n\ndata: '+JSON.stringify(terminal)+'\n\n'},
    {name:'wire-http-structured',status:403,statusText:'Fixture Denied',body:'{"error":{"message":"denied","code":"fixture"}}'},
    {name:'wire-eof-terminal',status:200,statusText:'OK',body:'data: '+JSON.stringify(terminal)},
    {name:'wire-no-body204',status:204,statusText:'No Content',body:''}
  ];
  for(active of cases){
    requests=[];const order=[],events=[];
    const model={id:'wire-model',api:'pi-messages',provider:'test-pi',baseUrl:`http://127.0.0.1:${server.address().port}/v1///`};
    const context={messages:[{role:'user',content:'wire request',timestamp:9}]};
    const stream=api.stream(model,context,{apiKey:'fixture-key',headers:{'x-test':'yes'},maxTokens:0,cacheRetention:'none',onPayload(payload,seen){if(payload.context!==context||seen!==model)throw Error('literal identity');order.push('payload');},onResponse(response){order.push('response:'+response.status+':'+response.headers['x-fixture']);},onProviderStreamEvent(event){order.push('provider:'+event.type);}});
    let partial;for await(const event of stream){if(event.partial){if(partial&&partial!==event.partial)throw Error('partial alias');partial=event.partial;}events.push(snapshot(event));}
    const result=await stream.result();if(partial&&result!==partial)throw Error('terminal alias');
    if(requests.length!==1)throw Error('owned loopback request count');
    rows.push(snapshot({name:active.name,requests,events,result,order}));
  }
}finally{
  Date.now=originalNow;server.closeAllConnections();await new Promise((resolve,reject)=>server.close(error=>error?reject(error):resolve()));
}
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'5ab7fe74c400097b386662205cd93900695b8a71',actualNode:{execPath:process.execPath,version:process.version,pid:process.pid},driverSha256:createHash('sha256').update(readFileSync(import.meta.filename)).digest('hex'),inputSha256:createHash('sha256').update(input).digest('hex'),scope:'Actual original Pi messages module: 18 supplied-fetch controls plus 4 owned-loopback default-fetch controls. Stack and numeric duration values normalized with property presence preserved; mutable partial and terminal aliases checked live.',cases:rows.length,rows},null,2));
