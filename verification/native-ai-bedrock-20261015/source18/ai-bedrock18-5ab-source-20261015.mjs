import { createServer } from 'node:http';
import { readFileSync, writeFileSync } from 'node:fs';
import { stream, streamSimple } from 'file:///C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015/packages/ai/src/api/bedrock-converse-stream.ts';
const [outputPath,inputPath]=process.argv.slice(2);
const inputs=JSON.parse(readFileSync(inputPath,'utf8'));
const normalize=value=>JSON.parse(JSON.stringify(value,(key,item)=>key==='timestamp'?0:item instanceof Uint8Array?Array.from(item):item));
function crc32(bytes){let crc=0xffffffff;for(const byte of bytes){crc^=byte;for(let i=0;i<8;i++)crc=(crc>>>1)^((crc&1)?0xedb88320:0)}return (crc^0xffffffff)>>>0}
function header(name,value){const n=Buffer.from(name),v=Buffer.from(value),length=Buffer.alloc(2);length.writeUInt16BE(v.length);return Buffer.concat([Buffer.from([n.length]),n,Buffer.from([7]),length,v])}
function frame(event){const [type,payload]=Object.entries(event)[0];const exception=type.endsWith('Exception');const headers=Buffer.concat([header(':message-type',exception?'exception':'event'),header(exception?':exception-type':':event-type',type),header(':content-type','application/json')]);const data=Buffer.from(JSON.stringify(payload));const prelude=Buffer.alloc(12);prelude.writeUInt32BE(16+headers.length+data.length);prelude.writeUInt32BE(headers.length,4);prelude.writeUInt32BE(crc32(prelude.subarray(0,8)),8);const content=Buffer.concat([prelude,headers,data]);const end=Buffer.alloc(4);end.writeUInt32BE(crc32(content));return Buffer.concat([content,end])}
const rows=[];
for(const input of inputs){
 let request;const requests=[];
 const wire=input.httpError?Buffer.from(input.httpError.body):Buffer.concat(input.events.map(frame));
 const server=createServer(async(req,res)=>{try{const body=[];for await(const chunk of req)body.push(chunk);request={method:req.method,url:`http://${req.headers.host}${req.url}`,path:req.url,body:JSON.parse(Buffer.concat(body).toString('utf8')),headers:Object.fromEntries(Object.entries(req.headers).filter(([key])=>['content-type','accept','x-fixture','authorization'].includes(key)).map(([key,value])=>[key,value]))};requests.push(request);res.writeHead(input.httpError?.status??200,{'content-type':input.httpError?'application/json':'application/vnd.amazon.eventstream','x-amzn-requestid':'fixture-request-id','x-fixture-response':'raw-gateway'});if(input.splitWire){for(let i=0;i<wire.length;i+=7)res.write(wire.subarray(i,i+7));res.end()}else res.end(wire)}catch(error){res.destroy(error)}});
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const endpoint=`http://127.0.0.1:${server.address().port}`;
 const model={id:input.modelId??'anthropic.claude-sonnet-4-6',name:input.modelName??'Claude Sonnet 4.6',api:'bedrock-converse-stream',provider:'amazon-bedrock',baseUrl:endpoint,reasoning:true,input:['text','image'],contextWindow:200000,maxTokens:8192,cost:{input:3,output:15,cacheRead:0.3,cacheWrite:3.75}};
 const context=input.context??{messages:[{role:'user',content:'Hello',timestamp:1}]};
 const callbacks=[];
 const controller=new AbortController();
 const options={region:'eu-west-2',bearerToken:'fixture-placeholder-bearer',env:{AWS_BEDROCK_SKIP_AUTH:'0',AWS_BEDROCK_FORCE_HTTP1:'1',AWS_EC2_METADATA_DISABLED:'true'},maxRetries:0,...input.options,signal:controller.signal,
  async onPayload(payload,m){callbacks.push({type:'payload',model:m.id,value:normalize(payload)});await Promise.resolve();if(input.payloadReplacement)return {...payload,requestMetadata:{fixture:'replacement'}};},
  async onResponse(value,m){callbacks.push({type:'response',model:m.id,value:{status:value.status,headers:Object.fromEntries(Object.entries(value.headers).filter(([key])=>['x-amzn-requestid','x-fixture-response','content-type'].includes(key)))}});await Promise.resolve();if(input.responseThrow)throw new RangeError('fixture response failure');},
  async onProviderStreamEvent(value,m){callbacks.push({type:'provider',model:m.id,value:normalize(value)});await Promise.resolve();if(input.eventMutate&&value.contentBlockDelta?.delta?.text!==undefined)value.contentBlockDelta.delta.text+=' changed';if(input.eventThrow&&value.contentBlockDelta)throw {fixture:'event rejection'};if(input.abortOnEvent&&value.contentBlockDelta)controller.abort({fixture:'abort'});}
 };
 const events=[];let result,thrown;
 try{const output=(input.simple?streamSimple:stream)(model,context,options);for await(const event of output)events.push(normalize(event));result=normalize(await output.result());}catch(error){thrown={name:error?.name,message:error?.message,value:normalize(error)}}
 finally{server.closeAllConnections();await new Promise(resolve=>server.close(resolve))}
 rows.push({name:input.name,request,requests,callbacks,events,result,thrown});
}
writeFileSync(outputPath,JSON.stringify({sourceHead:'5ab7fe74c400097b386662205cd93900695b8a71',actualNode:{version:process.version,executable:process.execPath},cases:rows.length,rows},null,2)+'\n');





