// External transport controls only. Whole provider and SDK functions are immutable Source.
import {writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {zstdDecompressSync} from 'node:zlib';
const source='C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015/packages/ai/src/';
const modules={standard:await import(pathToFileURL(source+'api/openai-responses.ts')),azure:await import(pathToFileURL(source+'api/azure-openai-responses.ts')),codex:await import(pathToFileURL(source+'api/openai-codex-responses.ts'))};
const {AssistantMessageEventStream}=await import(pathToFileURL(source+'utils/event-stream.ts'));
const fixedTime=1792080000123;Date.now=()=>fixedTime;
const token='e30.'+Buffer.from(JSON.stringify({'https://api.openai.com/auth':{chatgpt_account_id:'account-fixture'}})).toString('base64')+'.sig';
const model={id:'gpt-5.5',api:'openai-responses',provider:'openai',baseUrl:'https://api.openai.com/v1',reasoning:true,input:['text','image'],contextWindow:32000,maxTokens:8192,cost:{input:2,output:8,cacheRead:0.5,cacheWrite:1}};
const context={messages:[{role:'system',content:'system',timestamp:0},{role:'user',content:'hello',timestamp:1}]};
const item={type:'message',id:'msg_fixture',role:'assistant',status:'completed',phase:'final_answer',content:[{type:'output_text',text:'answer',annotations:[]}]};
const chunks=[{type:'response.created',response:{id:'resp_fixture'}},{type:'response.output_item.added',output_index:0,item:{...item,content:[]}},{type:'response.output_text.delta',output_index:0,delta:'answer'},{type:'response.output_item.done',output_index:0,item}];
const completed={type:'response.completed',response:{id:'resp_fixture',status:'completed',output:[item],usage:{input_tokens:8,output_tokens:2,total_tokens:10},service_tier:'default'}};
const specs=[
 {name:'standard-http-retry-zero',mode:'standard',maxRetries:1,plans:[{status:429,body:{error:{message:'busy',type:'rate_limit_error'}},headers:{'retry-after-ms':'0'}},{}]},
 {name:'azure-http-retry-zero',mode:'azure',maxRetries:1,plans:[{status:503,body:{error:{message:'busy',type:'server_error'}},headers:{'retry-after-ms':'0'}},{}]},
 {name:'codex-http-retry-zero',mode:'codex',maxRetries:1,plans:[{status:429,body:{error:{message:'busy',type:'rate_limit_error'}},headers:{'retry-after-ms':'0'}},{}]},
 {name:'codex-terminal-usage-limit',mode:'codex',maxRetries:1,plans:[{status:429,body:{error:{message:'usage limit reached',type:'usage_limit_reached',code:'insufficient_quota'}}}]},
 {name:'codex-terminal-quota-catch',mode:'codex',maxRetries:1,plans:[{status:429,body:{error:{message:'quota exceeded',type:'quota_exceeded',code:'insufficient_quota'}}},{}]},
 {name:'codex-network-raw-object-retry',mode:'codex',maxRetries:1,plans:[{reject:{fixture:'network-object'}},{}]},
 {name:'codex-response-hook-retry',mode:'codex',maxRetries:1,rejectResponseAt:0,plans:[{},{}]},
 {name:'codex-retry-hint-invalid-number',mode:'codex',maxRetries:1,plans:[{status:503,body:{error:{message:'busy'}},headers:{'retry-after-ms':'0junk'}},{}]},
 {name:'codex-retry-delay-exceeded',mode:'codex',maxRetries:1,maxRetryDelayMs:1,plans:[{status:503,body:{error:{message:'busy'}},headers:{'retry-after-ms':'5000'}}]},
 {name:'standard-entered-reader-raw-object',mode:'standard',plans:[{readerReject:{fixture:'reader-object'}}]},
 {name:'codex-entered-reader-raw-object',mode:'codex',plans:[{readerReject:{fixture:'reader-object'}}]},
 {name:'standard-pre-aborted',mode:'standard',preAborted:true,plans:[]},
 {name:'codex-pre-aborted',mode:'codex',preAborted:true,plans:[]},
 {name:'codex-invalid-timeout',mode:'codex',invalidTimeout:true,plans:[]},
];
// Only numeric duration magnitude is standardized when that property exists.
const snapshot=value=>JSON.parse(JSON.stringify(value,(key,value)=>key==='durationMs'&&typeof value==='number'?0:value));
const originalPush=AssistantMessageEventStream.prototype.push;let currentEvents;
AssistantMessageEventStream.prototype.push=function(event){currentEvents?.push(snapshot(event));return Reflect.apply(originalPush,this,arguments)};
const rows=[];
try{for(const spec of specs){
 const selected={...model};
 if(spec.mode==='azure'){selected.api='azure-openai-responses';selected.provider='azure';selected.baseUrl='https://resource.openai.azure.com/openai/v1'}
 if(spec.mode==='codex'){selected.api='openai-codex-responses';selected.provider='openai-codex';selected.baseUrl='https://chatgpt.com/backend-api'}
 const trace=[],requests=[],events=[],consumerEvents=[],consumerAliases=[];let providerIndex=0,responseIndex=0,firstOutput;
 const controller=new AbortController();if(spec.preAborted)controller.abort();
 const options={apiKey:spec.mode==='codex'?token:'sk-fixture',transport:'sse',sessionId:'retry-fixture-session',maxRetries:spec.maxRetries??0,headers:{'user-agent':'pi-fixture','x-fixture':'retry-caller'},signal:controller.signal,
  ...(spec.mode==='azure'?{env:{AZURE_OPENAI_BASE_URL:selected.baseUrl,AZURE_OPENAI_API_VERSION:'2026-01-01'}}:{}),...(spec.maxRetryDelayMs!==undefined?{maxRetryDelayMs:spec.maxRetryDelayMs}:{}),...(spec.invalidTimeout?{timeoutMs:NaN}:{}),
  onPayload:async(payload,m)=>{trace.push(['payload-enter',m===selected]);await Promise.resolve();trace.push(['payload-leave',m===selected])},
  onResponse:async(response,m)=>{const index=responseIndex++;trace.push(['response-enter',index,m===selected,snapshot(response)]);await Promise.resolve();trace.push(['response-leave',index,m===selected]);if(index===spec.rejectResponseAt)throw {fixture:'response-hook-object'}},
  onProviderStreamEvent:async(event,m)=>{const index=providerIndex++;trace.push(['provider-enter',index,m===selected,snapshot(event)]);await Promise.resolve();trace.push(['provider-leave',index,m===selected])},
  fetch:async(url,init)=>{
   let body=init.body;const headers=new Headers(init.headers);if(headers.get('content-encoding')==='zstd')body=zstdDecompressSync(body).toString();
   const index=requests.length;const plan=spec.plans[index];requests.push({url:String(url),method:init.method,headers:Object.fromEntries(headers),body:JSON.parse(body)});trace.push(['fetch',index,Boolean(init.signal?.aborted)]);
   if(!plan)throw new Error('Unexpected extra fixture request '+index);
   if(plan.reject)throw plan.reject;
   const status=plan.status??200;
   if(status!==200)return new Response(JSON.stringify(plan.body),{status,statusText:status===429?'Too Many Requests':'Service Unavailable',headers:{'content-type':'application/json','x-fixture-response':'source',...plan.headers}});
   const end=spec.mode==='codex'?{...completed,type:'response.done',response:{...completed.response,end_turn:true}}:completed;
   const values=plan.readerReject?chunks:[...chunks,end];const bytes=new TextEncoder().encode(values.map(event=>'data: '+JSON.stringify(event)+'\n\n').join(''));let offset=0;
   return new Response(new ReadableStream({pull(stream){if(offset===bytes.length){if(plan.readerReject)stream.error(plan.readerReject);else stream.close();return}const next=Math.min(offset+17,bytes.length);stream.enqueue(bytes.slice(offset,next));offset=next}}),{status,headers:{'content-type':'text/event-stream','x-fixture-response':'source'}});
  },
 };
 let result,thrown;currentEvents=events;
 try{const stream=modules[spec.mode].stream(selected,context,options);for await(const event of stream){const output=event.partial??event.message??event.error;firstOutput??=output;consumerAliases.push([event.type,output===firstOutput]);consumerEvents.push(snapshot(event))}result=await stream.result();consumerAliases.push(['result',result===firstOutput])}catch(error){thrown={string:String(error),...(error?.stack?{stack:error.stack}:{})}}
 currentEvents=undefined;rows.push({name:spec.name,requests,trace,events,consumerEvents,consumerAliases,result:result?snapshot(result):null,...(thrown?{thrown}:{})});
}}finally{AssistantMessageEventStream.prototype.push=originalPush}
const output={sourceHead:'5ab7fe74c400097b386662205cd93900695b8a71',sourceModule:'packages/ai/src/api/openai-responses.ts + azure-openai-responses.ts + openai-codex-responses.ts',actualNode:{version:process.version,executable:process.execPath},cases:specs.length,fixedTime,inputs:{model,context,specs},rows};
writeFileSync(process.argv[2],JSON.stringify(output,null,2)+'\n');
console.log(JSON.stringify({rows:rows.length,requests:rows.reduce((count,row)=>count+row.requests.length,0),events:rows.reduce((count,row)=>count+row.events.length,0),errors:rows.filter(row=>row.result?.stopReason==='error'||row.result?.stopReason==='aborted').length}));
