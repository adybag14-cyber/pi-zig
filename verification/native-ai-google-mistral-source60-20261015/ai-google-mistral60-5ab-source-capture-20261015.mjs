import {createServer} from 'node:http';
import {once} from 'node:events';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const root='file:///C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015/packages/ai/src/';
const apis={google:await import(root+'api/google-generative-ai.ts'),vertex:await import(root+'api/google-vertex.ts'),mistral:await import(root+'api/mistral-conversations.ts')};
const tool={name:'read',description:'read file',parameters:{type:'object',properties:{path:{type:'string'}},required:['path']}};
const image={type:'image',mimeType:'image/png',data:'AA=='};
const system={role:'system',content:'system',timestamp:0};
const user={role:'user',content:'hello',timestamp:1};
const baseMessages=[system,user];
const cases=[];
for(const kind of ['google','vertex','mistral']){
 cases.push({name:kind+'-plain',kind},{name:kind+'-thinking-tools',kind,model:{reasoning:true,thinkingLevelMap:{off:'off',low:'low',high:'high'}},options:{reasoning:'low'},context:{messages:[{...system,toolsAdded:[tool]},user]},chunks:kind==='mistral'?[{id:'response-1',choices:[{delta:{content:[{type:'thinking',thinking:[{text:'plan'}]}]}}]},{choices:[{delta:{tool_calls:[{index:0,id:'AbC123xyz',function:{name:'read',arguments:'{"path":'}}]}}]},{choices:[{delta:{tool_calls:[{index:0,function:{arguments:'"x"}'}}]},finish_reason:'tool_calls'}],usage:{prompt_tokens:20,prompt_tokens_details:{cached_tokens:5},completion_tokens:3,total_tokens:23}}]:[{responseId:'response-1',candidates:[{content:{parts:[{thought:true,text:'plan',thoughtSignature:'YWJjZA=='}]}}]},{candidates:[{content:{parts:[{functionCall:{name:'read',id:'call-1',args:{path:'x'}},thoughtSignature:'YWJjZA=='}]},finishReason:'STOP'}],usageMetadata:{promptTokenCount:20,cachedContentTokenCount:5,candidatesTokenCount:3,thoughtsTokenCount:2,totalTokenCount:25}}]},
 {name:kind+'-images',kind,context:{messages:[system,{...user,content:[{type:'text',text:'a\ud800b'},image]}]}},
 {name:kind+'-unknown-stop',kind,chunks:kind==='mistral'?[{choices:[{delta:{content:'partial'},finish_reason:'other'}]}]:[{candidates:[{content:{parts:[{text:'partial'}]},finishReason:'SAFETY'}]}]},
 {name:kind+'-empty',kind,chunks:[]},
 {name:kind+'-http-error',kind,status:403,body:'{"error":{"message":"fixture denied request"}}'},
 {name:kind+'-async-hooks',kind,callback:'async'},
 {name:kind+'-hook-throws',kind,callback:'throw'},
 {name:kind+'-payload-replace',kind,callback:'replace'},
 {name:kind+'-no-key',kind,options:{apiKey:''},noRequest:true});
}
const emptyUsage={input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}};
for(const kind of ['google','vertex','mistral']){
 const provider=kind==='vertex'?'google-vertex':kind,api=kind==='google'?'google-generative-ai':kind==='vertex'?'google-vertex':'mistral-conversations',id=kind==='mistral'?'mistral-fixture':'gemini-3.1-pro-preview';
 const assistant=content=>({role:'assistant',content,api,provider,model:id,usage:emptyUsage,stopReason:'toolUse',timestamp:2});
 const prior=assistant([{type:'thinking',thinking:'prior plan',thinkingSignature:'YWJjZA=='},{type:'text',text:'prior answer',textSignature:'YWJjZA=='},{type:'toolCall',id:'responses_call|item$',name:'read',arguments:{path:'x'},thoughtSignature:'YWJjZA=='}]);
 const toolResult={role:'toolResult',toolCallId:'responses_call|item$',toolName:'read',content:[{type:'text',text:'prior result'},image],isError:false,timestamp:3};
 const replay={messages:[{...system,toolsAdded:[tool]},user,prior,toolResult,{...user,content:'continue',timestamp:4}]};
 cases.push({name:kind+'-replay-signatures-tool-images',kind,context:replay},
 {name:kind+'-cross-provider-replay',kind,context:{messages:[{...system,toolsAdded:[tool]},user,{...prior,provider:'foreign',model:'foreign'},toolResult,{...user,content:'continue',timestamp:4}]}},
 {name:kind+'-nonvision-error-image',kind,model:{input:['text']},context:{messages:[{...system,toolsAdded:[tool]},user,prior,{...toolResult,isError:true,content:[image,image]},{...user,content:'continue',timestamp:4}]}},
 {name:kind+'-late-system-tools',kind,model:{compat:{supportsMidConvoSystemMessages:true}},context:{messages:[{...system,toolsAdded:[tool]},user,{role:'system',content:'updated',toolsRemoved:[{name:'read'}],toolsAdded:[{...tool,description:'updated description'}],timestamp:2},{...user,content:'continue',timestamp:3}]}},
 {name:kind+'-strict-required',kind,context:{messages:[{...system,toolsAdded:[{...tool,parameters:{type:'object',properties:{path:{type:'string'},optional:{type:'integer'}},required:['path']},constrainedSampling:{type:'json_schema',strict:'require'}}]},user]}},
 {name:kind+'-off-map-null',kind,model:{reasoning:true,thinkingLevelMap:{off:null,low:'low',high:'high'}}},
 {name:kind+'-named-tool-choice',kind,context:{messages:[{...system,toolsAdded:[tool]},user]},options:{toolChoice:{type:'function',function:{name:'read',ignored:'extra'},ignored:'extra'}}},
 {name:kind+'-thinking-budget',kind,model:{reasoning:true,...(kind==='mistral'?{}:{id:'gemini-2.5-pro'})},options:{reasoning:'low',thinkingBudgets:{low:4096}}},
 {name:kind+'-cache-none',kind,callback:'metadata',options:{cacheRetention:'none'}},
 {name:kind+'-header-null-overrides',kind,model:{headers:{'X-Affinity':'model-affinity','x-goog-api-key':null}},options:{headers:{'X-Affinity':null,authorization:null}}});
}
// Vertex missing-key mode resolves project/location through an explicit empty env.
const cost={input:1,output:2,cacheRead:.5,cacheWrite:1.5};
const defaultChunks=kind=>kind==='mistral'?[{id:'response-1',choices:[{delta:{content:'answer'},finish_reason:'stop'}],usage:{prompt_tokens:12,completion_tokens:4,total_tokens:16}}]:[{responseId:'response-1',candidates:[{content:{parts:[{text:'answer'}]},finishReason:'STOP'}],usageMetadata:{promptTokenCount:12,candidatesTokenCount:4,totalTokenCount:16}}];
let item,requests;
const server=createServer(async(req,res)=>{try{let raw='';for await(const chunk of req)raw+=chunk;requests.push({path:req.url,body:JSON.parse(raw),headers:Object.fromEntries(['authorization','content-type','x-goog-api-key','x-affinity'].filter(key=>req.headers[key]!==undefined).map(key=>[key,req.headers[key]]))});res.writeHead(item.status??200,{'content-type':item.status?'application/json':'text/event-stream','x-fixture':'source-only'});if(item.status)res.end(item.body);else {for(const chunk of item.chunks??defaultChunks(item.kind)){res.write('data: '+JSON.stringify(chunk)+'\n\n');await new Promise(setImmediate)}res.end()}}catch(error){res.destroy(error)}});
server.listen(0,'127.0.0.1');await once(server,'listening');
function snapshot(value){if(Array.isArray(value))return value.map(snapshot);if(value&&typeof value==='object'){const out={};for(const [key,item]of Object.entries(value)){if(value.role==='assistant'&&key==='timestamp')out[key]='$TIMESTAMP';else if(value.role==='assistant'&&key==='durationMs')out[key]='$DURATION';else out[key]=snapshot(item)}return out}return value}
const rows=[];
try{for(item of cases){requests=[];const callbacks=[],events=[],payloads=[];const apiName=item.kind==='google'?'google-generative-ai':item.kind==='vertex'?'google-vertex':'mistral-conversations';const model={id:item.kind==='mistral'?'mistral-fixture':'gemini-3.1-pro-preview',name:'fixture',provider:item.kind==='vertex'?'google-vertex':item.kind,api:apiName,baseUrl:`http://127.0.0.1:${server.address().port}/v1`,reasoning:false,input:['text','image'],cost,contextWindow:32000,maxTokens:8192,...item.model};const context=structuredClone(item.context??{messages:baseMessages});const options={apiKey:'fixture-placeholder-key',env:{GOOGLE_CLOUD_PROJECT:'',GCLOUD_PROJECT:'',GOOGLE_CLOUD_LOCATION:'',GOOGLE_APPLICATION_CREDENTIALS:''},maxTokens:1000,maxRetries:0,sessionId:'fixture-session',...item.options,onPayload(payload){callbacks.push('payload');payloads.push(snapshot(payload));if(item.callback==='replace')return {...payload,...(item.kind==='mistral'?{temperature:.25}:{config:{...payload.config,temperature:.25}})};if(item.callback==='async')return Promise.resolve()},onResponse(response){callbacks.push('response:'+response.status+':'+response.headers['x-fixture']);if(item.callback==='throw')throw Error('caller response failed');if(item.callback==='async')return Promise.resolve()},onProviderStreamEvent(chunk){callbacks.push('chunk');if(item.callback==='metadata')callbacks.push({constructor:chunk.constructor.name,keys:Object.keys(chunk),text:chunk.text,data:chunk.data,functionCalls:chunk.functionCalls,executableCode:chunk.executableCode,codeExecutionResult:chunk.codeExecutionResult,httpKeys:Object.keys(chunk.sdkHttpResponse?.headers??{}).filter(key=>key==='content-type'||key==='x-fixture')});if(item.callback==='async')return Promise.resolve()}};let result,syncError;try{const stream=apis[item.kind].streamSimple(model,context,options);for await(const event of stream)events.push(snapshot(event));result=snapshot(await stream.result())}catch(error){syncError={name:error.name,message:error.message}}if(item.noRequest?requests.length!==0:requests.length!==1)throw Error('request count '+item.name+' '+requests.length);rows.push({input:item,name:item.name,payloads,requests,callbacks,events,result,...(syncError?{syncError}:{} )})}
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'5ab7fe74c400097b386662205cd93900695b8a71',driverSha256:createHash('sha256').update(readFileSync(import.meta.filename)).digest('hex'),actualNode:{execPath:process.execPath,version:process.version,pid:process.pid},scope:'Actual official5ab Google/Vertex/Mistral APIs, pinned SDK dependencies, owned loopback placeholder credentials; full event snapshots with assistant clocks normalized only.',cases:rows.length,rows},null,2));
}finally{server.closeAllConnections();await new Promise((resolve,reject)=>server.close(error=>error?reject(error):resolve()))}



