import {writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
const root='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/packages/coding-agent/dist/core/';
const {createAgentSession}=await import(pathToFileURL(root+'sdk.js'));
const {AgentSession}=await import(pathToFileURL(root+'agent-session.js'));
const {SessionManager}=await import(pathToFileURL(root+'session-manager.js'));
const {SettingsManager}=await import(pathToFileURL(root+'settings-manager.js'));
const {createExtensionRuntime,loadExtensionFromFactory}=await import(pathToFileURL(root+'extensions/loader.js'));
const {createEventBus}=await import(pathToFileURL(root+'event-bus.js'));
const usage=()=>({input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}});
const assistant=(stopReason='stop')=>({role:'assistant',api:'openai-completions',provider:'fixture',model:'fixture',content:[{type:'text',text:'answer'}],usage:usage(),stopReason,timestamp:3});
const output=[];
for(const scenario of ['hidden-empty','hidden-tool','forced-string','forced-empty','forced-null','forced-hidden','physical-request','failed-physical-request','finish-no-handler','before-no-handler','before-block','before-error','nested-calls','nested-usage','nested-combine','nested-clear']){
 const trace=[];let session;let streamCalls=0;
 const history=()=>session.sessionManager.getBranch().filter(e=>e.type==='message'||e.type==='custom_message');
 const snapshot=(phase,event)=>trace.push([phase,event.type,history().length,[...session._steeringMessages],[...session._followUpMessages],event.message?.role,event.message?.content,event.willRetry,Object.keys(event).sort()]);
 const runtime=createExtensionRuntime();
 const extension=await loadExtensionFromFactory(pi=>{
  for(const type of ['agent_start','agent_end','turn_start','message_start','message_update','message_end','tool_execution_start','tool_execution_update','tool_execution_end',...(scenario==='before-no-handler'?[]:['tool_call'])])pi.on(type,async event=>{
   snapshot('extension',event);await Promise.resolve();trace.push(['extension-done',event.type]);
   if(event.type==='tool_call'){if(scenario==='before-block')return{block:true,reason:'blocked'};if(scenario==='before-error')throw Error('hookfailure')}
   if(event.type==='message_end'){
    if(scenario==='extension-error')throw Error('extension-failure');
    if(scenario==='message-replacement')return{message:{...event.message,content:[{type:'text',text:'replaced'}],replacement:true}};
    if(scenario==='message-null')return{message:{...event.message,content:null,replacement:true}};
    if(scenario==='message-same-object')return{message:event.message};
    if(scenario==='message-wrong-role')return{message:{role:'custom',content:[]}};
   }
  });
 },'C:/Users/adyba/pi-zig-update-evidence-20261003',createEventBus(),runtime,'<event-fixture>');
 const resources={getExtensions:()=>({extensions:[extension],errors:[],runtime}),getSkills:()=>({skills:[],diagnostics:[]}),getPrompts:()=>({prompts:[],diagnostics:[]}),getThemes:()=>({themes:[],diagnostics:[]}),getAgentsFiles:()=>({agentsFiles:[]}),getSystemPrompt:()=>undefined,getSystemPromptSource:()=>undefined,getAppendSystemPrompt:()=>[],getAppendSystemPromptSources:()=>[],extendResources(){},async reload(){}};
 const model={id:'fixture',name:'fixture',provider:'fixture',api:'openai-completions',baseUrl:'https://fixture.invalid',reasoning:false,input:['text'],cost:{input:0,output:0,cacheRead:0,cacheWrite:0},contextWindow:10000,maxTokens:1000};
 const modelRuntime={getModel:(p,id)=>p==='fixture'&&id==='fixture'?model:undefined,getModels:()=>[model],getAvailableSnapshot:()=>[model],hasConfiguredAuth:()=>true,getError:()=>undefined,streamSimple(){streamCalls++;const message=assistant();return{async *[Symbol.asyncIterator](){yield{type:'start',partial:message};yield{type:'done',reason:'stop',message};},async result(){return message;}};}};
 ({session}=await createAgentSession({cwd:'C:/Users/adyba/pi-zig-update-evidence-20261003',agentDir:'C:/Users/adyba/pi-zig-update-evidence-20261003/owned-session-events-agentdir',sessionManager:SessionManager.inMemory(),settingsManager:SettingsManager.inMemory({retry:{enabled:false},compaction:{enabled:false},cacheWarming:'off'}),resourceLoader:resources,modelRuntime,model,noTools:'all'}));
 if(!(session instanceof AgentSession)||!Object.hasOwn(session,'_handleAgentEvent'))throw Error('Not the real bound Source AgentSession');
 session._extensionRunner.onError(event=>trace.push(['extension-error',event.event,event.error]));
 session.subscribe(event=>{snapshot('public',event);if(scenario==='public-error'&&event.type==='message_end')throw Error('public-failure');});
 session._overflowRecoveryAttempted=true;
 let event={type:'message_end',message:assistant()};
 if(scenario.startsWith('queue-')){
  session._steeringMessages=scenario==='queue-followup'?[]:['queued','queued'];session._followUpMessages=['queued'];
  event={type:'message_start',message:{role:'user',content:scenario==='queue-array-text'?[{type:'text',text:'que'},{type:'image',data:'x'},{type:'text',text:'ued'}]:scenario==='queue-empty'?'':'queued',timestamp:1}};
 }
 if(scenario==='custom-persist')event={type:'message_end',message:{role:'custom',customType:'custom',content:[],display:false,details:{x:1},timestamp:1}};
 if(scenario==='system-persist')event={type:'message_end',message:{role:'system',content:'',sections:{identity:'system'},timestamp:1}};
 if(scenario==='ignored-persist')event={type:'message_end',message:{role:'bashExecution',command:'echo',output:'output',exitCode:0,cancelled:false,truncated:false,timestamp:1}};
 if(scenario.startsWith('retry-')){session._retryAttempt=2;event={type:'message_end',message:assistant(scenario.slice(6)==='success'?'stop':scenario.slice(6))};}
 if(scenario.startsWith('tool-'))event={type:scenario==='tool-start'?'tool_execution_start':scenario==='tool-update'?'tool_execution_update':'tool_execution_end',toolCallId:'call',toolName:'tool',args:{x:1},partialResult:{content:[]},result:{content:[]},isError:false,...(scenario==='tool-end-duration'?{durationMs:7}:{})};
 if(scenario==='turn-start'){session._turnIndex=4;event={type:'turn_start'};}
 if(scenario==='turn-end-flush'){session._pendingCustomMessages=[{role:'custom',customType:'pending',content:'after results',display:true,timestamp:9}];event={type:'turn_end',message:assistant(),toolResults:[]};}
 if(scenario==='agent-start-abort'){session._agentRunAbortRequested=true;session._turnIndex=4;event={type:'agent_start'};}
 if(scenario==='agent-end')event={type:'agent_end',messages:[assistant()]};
 if(scenario==='unknown')event={type:'fixture_unknown'};
 let error=null,hookResult;const nestedTrace=[];
 if(scenario.startsWith('nested-')){const nestedUsage={...usage(),input:2,output:3,totalTokens:5,reasoning:1,cacheWrite1h:4,cost:{...usage().cost,input:0.25,total:0.25}};session._nestedToolCalls={takeRecord(id){nestedTrace.push(['take',id]);return{...(scenario==='nested-calls'?{calls:[{toolName:'nested',toolCallId:'child'}]}:{usage:nestedUsage})}},clear(){nestedTrace.push(['clear'])}};event=scenario==='nested-clear'?{type:'agent_end',messages:[]}:{type:'message_start',message:{role:'toolResult',toolCallId:'parent',toolName:'outer',content:[],...(scenario==='nested-combine'?{usage:{...usage(),input:7,totalTokens:7,reasoning:2,cost:{...usage().cost,input:0.5,total:0.5}}}:{}),timestamp:7}};}
 const hookMessages=[{role:'system',content:'base',toolsAdded:[{name:'keep',description:'keep',parameters:{type:'object'}},{name:'hide',description:'hide',parameters:{type:'object'}}],timestamp:1},{role:'system',content:'append',toolsRemoved:[{name:'remove'}],timestamp:2},{role:'user',content:'question',timestamp:3}];
 if(scenario==='hidden-tool'||scenario==='forced-hidden')session._hiddenDeclarations.add('hide');
 if(scenario.startsWith('forced-'))session._runSystemPromptOptions={forceSystemPrompt:scenario==='forced-null'?null:scenario==='forced-empty'?'':'forced'};
 if(scenario==='failed-physical-request')session._failedResponse=assistant('error');
 try{
  if(scenario.startsWith('nested-'))await session._handleAgentEvent(event);
  else if(scenario.startsWith('hidden-')||scenario.startsWith('forced-'))hookResult=await session.agent.transformContext(hookMessages);
  else if(scenario==='physical-request'||scenario==='failed-physical-request')hookResult=await session.agent.prepareRequest({context:{messages:hookMessages,tools:[{name:'ignored'}]},model:{id:'ignored'},thinkingLevel:'high'});
  else if(scenario==='finish-no-handler')hookResult=await session.agent.finishTurn({message:assistant(),toolResults:[]});
  else hookResult=await session.agent.beforeToolCall({toolCall:{id:'call',name:'tool'},args:{x:1}});
 }catch(cause){error=cause.message;}
 const entries=history();
 output.push({scenario,error,hookResult,nestedTrace,trace,streamCalls,boundOwn:Object.hasOwn(session,'_handleAgentEvent'),history:entries.map(e=>e.type==='message'?{type:e.type,message:e.message}:{type:e.type,customType:e.customType,content:e.content,display:e.display,details:e.details}),mapped:event.message?session._entryIdsByMessage.has(event.message):false,message:event.message,turnIndex:session._turnIndex,retry:session._retryAttempt,overflow:session._overflowRecoveryAttempted,pending:session._pendingCustomMessages.length,lastAssistantSame:session._lastAssistantMessage===event.message,lastToolResultsSame:session._lastAssistantToolResults===event.toolResults});
 session.dispose();
}
writeFileSync(process.argv[2],JSON.stringify({source:'19cb534c3b6e3871458a8fa59e98f0312c50e995',scope:'Real SDK factory-created AgentSession and original installed transform/request/boundary/tool hook callbacks; actual ExtensionRunner and SessionManager; caller messages/fields, user handlers, and an explicit nested recorder collaborator are test inputs; does not certify NestedToolCallRunner itself.',rows:output},(key,value)=>key==='timestamp'?'clock':value,2)+'\n');
