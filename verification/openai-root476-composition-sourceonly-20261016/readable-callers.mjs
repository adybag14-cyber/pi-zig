// Caller controls for the actual SDK shim/native leaf, not an implementation.
export async function observeReadableCompletion(create) {
 const rows=[];
 for(const mode of ['done-getter','done-getter-cleanup','done','done-release','done-release-twice','pending','null','undefined','read-throw','read-reject','read-throw-cleanup','read-reject-cleanup']) {
  const trace=[],first=new Error('fixture-first'),second=new Error('fixture-second');let releases=0;
  const input=mode==='null'?null:mode==='undefined'?undefined:{get done(){trace.push('done');if(this!==input)throw Error('Done receiver');if(mode.startsWith('done-getter'))throw first;return mode.startsWith('done')},get value(){throw Error('Shim next must not access value')}};
  const reader={read(){trace.push('read');if(this!==reader)throw Error('Read receiver');if(mode.startsWith('read-throw'))throw first;if(mode.startsWith('read-reject'))return Promise.reject(first);return input},releaseLock(){trace.push('release.'+(++releases));if(this!==reader)throw Error('Release receiver');if(mode==='done-release'&&releases===1||mode==='done-release-twice'&&releases===1)throw first;if(mode==='done-release-twice'&&releases===2||mode.endsWith('cleanup'))throw second},cancel(){throw Error('Next does not cancel')}};
  const stream={getReader(){trace.push('getReader');return reader}},iterator=create(stream);let result,failure;
  try{result=await iterator.next()}catch(error){failure=error}
  const expectedRelease=mode==='done-release'||mode==='done-release-twice'?2:mode==='pending'||mode==='null'||mode==='undefined'?0:1;
  const expectedFailure=mode.endsWith('cleanup')||mode==='done-release-twice'?second:mode==='done-getter'||mode==='done-release'||mode.startsWith('read-')?first:undefined;
  if(releases!==expectedRelease||failure!==expectedFailure||!expectedFailure&&result!==input)throw Error('Actual shim completion '+mode);
  rows.push({mode,trace,releases,firstSame:failure===first,secondSame:failure===second,resultSame:result===input});
 }
 return rows;
}

// Full actual public API -> SDK -> custom fetch -> reader route. No network.
export async function observeReadablePublicRoute(api) {
 const rows=[],model={id:'fixture-model',name:'fixture',api:'openai-completions',provider:'openai',baseUrl:'http://127.0.0.1:1/v1',reasoning:false,input:['text'],cost:{input:1,output:2,cacheRead:0,cacheWrite:0},contextWindow:32000,maxTokens:4096},context={messages:[{role:'user',content:'fixture',timestamp:1}]};
 const descriptor=Object.getOwnPropertyDescriptor(globalThis,'process'),ownedProcess=Object.create(globalThis.process??null);Object.defineProperty(ownedProcess,'env',{value:{OPENAI_ADMIN_KEY:'',OPENAI_ORG_ID:'',OPENAI_PROJECT_ID:'',OPENAI_WEBHOOK_SECRET:'',OPENAI_LOG:'',OPENAI_CUSTOM_HEADERS:''}});Object.defineProperty(globalThis,'process',{configurable:true,value:ownedProcess});
 try {
  for(const mode of ['done-getter','done-release','done-release-twice']) {
   const trace=[],snapshots=[],first=new Error('fixture-reader-first'),second=new Error('fixture-reader-second');let reads=0,releases=0,fetches=0;
   const bytes=new TextEncoder().encode('data: '+JSON.stringify({id:'fixture-response',choices:[{index:0,delta:{content:'fixture answer'},finish_reason:'stop'}]})+'\n\n');
   const reader={read(){trace.push('read.'+(++reads));if(this!==reader)throw Error('Read receiver');if(reads===1)return {done:false,value:bytes};return {get done(){trace.push('done');if(mode==='done-getter')throw first;return true}}},releaseLock(){trace.push('release.'+(++releases));if(this!==reader)throw Error('Release receiver');if(mode!=='done-getter'&&releases===1)throw first;if(mode==='done-release-twice'&&releases===2)throw second},cancel(){trace.push('cancel');return Promise.resolve()}};
   const body={getReader(){trace.push('getReader');return reader}};
   const stream=api.stream(model,context,{apiKey:'fixture-key',maxRetries:0,fetch(){fetches++;trace.push('fetch');const response=new Response(null,{status:200,headers:{'content-type':'text/event-stream'}});Object.defineProperty(response,'body',{value:body});return response},onResponse(){trace.push('response')},onProviderStreamEvent(){trace.push('chunk')}});
   for await(const event of stream)snapshots.push(JSON.parse(JSON.stringify(event)));const result=await stream.result();
   const expected=mode==='done-release-twice'?second:first;if(fetches!==1||result.stopReason!=='error'||result.errorMessage!==expected.message||trace.indexOf('getReader')<trace.indexOf('response'))throw Error('Actual public reader catch '+mode);
   rows.push({mode,trace,reads,releases,snapshots,result});
  }
  return rows;
 }finally{if(descriptor)Object.defineProperty(globalThis,'process',descriptor);else delete globalThis.process}
}
