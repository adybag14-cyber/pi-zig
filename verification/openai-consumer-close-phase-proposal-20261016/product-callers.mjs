// Prepared caller controls only. api must be the actual OpenAI API module.
// No source implementation, expected capture, transport adapter or golden.
export async function observeOpenAIConsumerClose(api) {
 const rows=[],model={id:'fixture-model',name:'fixture',api:'openai-completions',provider:'openai',baseUrl:'http://127.0.0.1:1/v1',reasoning:false,input:['text'],cost:{input:1,output:2,cacheRead:0,cacheWrite:0},contextWindow:32000,maxTokens:4096},context={messages:[{role:'user',content:'fixture',timestamp:1}]};
 const processDescriptor=Object.getOwnPropertyDescriptor(globalThis,'process'),originalProcess=globalThis.process,ownedProcess=Object.create(originalProcess??null);
 Object.defineProperty(ownedProcess,'env',{value:{OPENAI_ADMIN_KEY:'',OPENAI_ORG_ID:'',OPENAI_PROJECT_ID:'',OPENAI_WEBHOOK_SECRET:'',OPENAI_LOG:'',OPENAI_CUSTOM_HEADERS:''}});
 Object.defineProperty(globalThis,'process',{configurable:true,value:ownedProcess});
 try {
  async function run(stepMode,bodyMode,closeMode,held=false) {
   const name=[stepMode,bodyMode,closeMode,held?'held':''].filter(Boolean).join('/'),trace=[],snapshots=[];
   let nextGets=0,nextCalls=0,returnGets=0,returnCalls=0,bodyReads=0,stepReads=0,closeReads=0,release,readyResolve,request,fetchCalls=0,hookCalls=0;
   const ready=held?new Promise(resolve=>readyResolve=resolve):undefined;
   function reason(label,read) {const raw=new Error();Object.defineProperty(raw,'message',{configurable:true,get(){if(this!==raw)throw Error('Raw reason receiver');read();trace.push(label+'.message');return 'fixture-'+label}});return raw}
   const bodyReason=reason('body',()=>bodyReads++),stepReason=reason('step',()=>stepReads++),closeReason=reason('close',()=>closeReads++);
   const chunk={id:'fixture-response',choices:[{index:0,delta:{content:'fixture answer'},finish_reason:'stop'}]};
   if(bodyMode==='decoder')Object.defineProperty(chunk,'choices',{get(){trace.push('chunk.choices');throw bodyReason}});
   const iterator={get next(){nextGets++;trace.push('next.get');if(stepMode==='noncallable')return 1;return function(){
    if(this!==iterator||arguments.length!==0)throw Error('Retained next receiver/arguments');nextCalls++;trace.push('next.call.'+nextCalls);
    if(stepMode==='throw'||stepMode==='late-throw'&&nextCalls===2)throw stepReason;
    if(stepMode==='reject')return Promise.reject(stepReason);
    if(stepMode==='primitive')return 1;
    if(stepMode==='done-throw')return {get done(){trace.push('done.get');throw stepReason},get value(){throw Error('Value after throwing done')}};
    if(stepMode==='value-throw'||stepMode==='late-value-throw'&&nextCalls===2)return {get done(){trace.push('done.get');return false},get value(){trace.push('value.get');throw stepReason}};
    if(nextCalls===1)return {get done(){trace.push('done.get');return false},get value(){trace.push('value.get');return chunk}};
    return {get done(){trace.push('done.get');return true},get value(){throw Error('Done result value must not be read')}};
   }},get return(){returnGets++;trace.push('return.get');if(closeMode==='getter-throw')throw closeReason;if(closeMode==='noncallable')return 1;if(closeMode==='undefined')return undefined;if(closeMode==='null')return null;return function(){
    if(this!==iterator||arguments.length!==0)throw Error('Return receiver/arguments');returnCalls++;trace.push('return.call');
    if(closeMode==='call-throw')throw closeReason;if(closeMode==='reject')return Promise.reject(closeReason);
    if(held){readyResolve();return new Promise(resolve=>release=()=>{trace.push('return.release');resolve({done:true})})}
    return closeMode==='primitive'?1:{done:true};
   }}};
   const iterable={[Symbol.asyncIterator](){if(this!==iterable)throw Error('Iterator receiver');trace.push('iterator.call');return iterator}};
   const options={apiKey:'fixture-key',maxRetries:0,onPayload(payload){trace.push('payload');return {...payload,stream:false}},fetch(url,init){fetchCalls++;trace.push('fetch');request={url,method:init.method,body:init.body,headers:[...init.headers]};if(JSON.parse(init.body).stream!==false)throw Error('Actual SDK nonstream branch');const response=new Response('{}',{status:200,headers:{'content-type':'application/json','x-request-id':'fixture-request'}});Object.defineProperty(response,'json',{value:function(){if(this!==response)throw Error('JSON receiver');trace.push('response.json');return iterable}});return response},onResponse(){trace.push('response')},onProviderStreamEvent(value){hookCalls++;trace.push('hook');if(value!==chunk)throw Error('Actual yielded frame identity');if(stepMode==='captured-next')Object.defineProperty(iterator,'next',{value(){throw Error('Next must be captured once')}});if(bodyMode==='throw')throw bodyReason;if(bodyMode==='reject')return Promise.reject(bodyReason)}};
   const stream=api.stream(model,context,options);trace.push('returned');if(stream instanceof Promise)throw Error('Public stream remains synchronous');
   let terminal=false;const pending=(async()=>{for await(const event of stream)snapshots.push(JSON.parse(JSON.stringify(event)));const result=await stream.result();terminal=true;return result})();
   if(held){await ready;if(terminal||snapshots.some(event=>event.type==='error'))throw Error('Failure applied before close await');release()}
   const result=await pending,bodyFailure=bodyMode!=='none',stepFailure=!['normal','captured-next'].includes(stepMode);
   if(fetchCalls!==1||nextGets!==1)throw Error('Actual fetch route/captured next '+name);
   if(trace.indexOf('response.json')>trace.indexOf('response')||trace.indexOf('response')>trace.indexOf('iterator.call'))throw Error('Parse/response/iterator order '+name);
   if(bodyFailure){if(returnGets!==1||returnCalls!==(['getter-throw','noncallable','undefined','null'].includes(closeMode)?0:1)||bodyReads===0||closeReads!==0||result.errorMessage!=='fixture-body')throw Error('Body completion/close precedence '+name)}
   else if(stepFailure){if(returnGets||returnCalls||result.stopReason!=='error'||!snapshots.some(event=>event.type==='error'))throw Error('Step failure must not close '+name);if(!['noncallable','primitive'].includes(stepMode)&&(stepReads===0||result.errorMessage!=='fixture-step'))throw Error('Step raw reason identity '+name)}
   else if(returnGets||returnCalls||result.stopReason!=='stop'||result.content[0]?.text!=='fixture answer'||snapshots.at(-1)?.type!=='done')throw Error('Normal iteration must not close '+name);
   if(bodyFailure&&hookCalls!==1)throw Error('Hook/decoder body reached once '+name);
   rows.push({name,trace,nextGets,nextCalls,returnGets,returnCalls,bodyReads,stepReads,closeReads,hookCalls,request,snapshots,result});
  }
  for(const step of ['throw','reject','noncallable','primitive','done-throw','value-throw','late-throw','late-value-throw','normal','captured-next'])await run(step,'none','getter-throw');
  for(const body of ['throw','reject','decoder'])for(const close of ['getter-throw','noncallable','call-throw','reject','primitive','object','undefined','null'])await run('normal',body,close);
  await run('normal','reject','object',true);
  if(rows.length!==35)throw Error('Prepared product control count');return rows;
 } finally {if(processDescriptor)Object.defineProperty(globalThis,'process',processDescriptor);else delete globalThis.process}
}
