// The owner supplies ORIGINAL or actual native class and a real owned directory.
// No replacement DefaultPackageManager, SettingsManager or transform is authored.
export async function observePackageProgress({DefaultPackageManager,SettingsManager,physicalRoot}) {
  const make=()=>new DefaultPackageManager({cwd:physicalRoot,agentDir:physicalRoot,settingsManager:SettingsManager.inMemory()});
  const rows=[];
  for(const stage of ['success','operation-sync','operation-await','complete','start','error-callback']){
    const manager=make(),reason={owned:stage,toString(){return stage}},replacement={owned:'error-replacement'},trace=[];
    manager.setProgressCallback(event=>{trace.push([event.type,event.action,event.source,'message'in event?event.message:null]);if(event.type===stage||(stage==='error-callback'&&event.type==='error'))throw event.type==='error'?replacement:reason});
    let caught,thrown=false,returned,operationCalls=0;
    try{returned=await manager.withProgress('update','npm:owned','Preparing',function(){operationCalls++;trace.push(['operation',this===undefined]);if(stage==='operation-sync'||stage==='error-callback')throw reason;if(stage==='operation-await')return Promise.reject(reason);return Promise.resolve('ignored')})}catch(error){caught=error;thrown=true}
    rows.push([stage,thrown,caught===(stage==='error-callback'?replacement:reason),returned===undefined,operationCalls,trace]);
  }
  for(const stage of ['message-getter','string-conversion','instanceof-getter','error-callee']){
    const manager=make(),trace=[],marker={owned:stage},savedError=Object.getOwnPropertyDescriptor(globalThis,'Error');let reason,caught;
    if(stage==='message-getter'){reason=new Error('owned');Object.defineProperty(reason,'message',{get(){trace.push('message');throw marker}})}
    else reason={toString(){trace.push('string');if(stage==='string-conversion')throw marker;return'owned'}};
    if(stage==='instanceof-getter'){function ChangedError(){}Object.defineProperty(ChangedError,Symbol.hasInstance,{get(){trace.push('hasInstance');throw marker}});Object.defineProperty(globalThis,'Error',{configurable:true,writable:true,value:ChangedError})}
    Object.defineProperty(manager,'emitProgress',{configurable:true,get(){trace.push('get-emit');return function(event){trace.push(event.type);if(stage==='error-callee'&&event.type==='error')throw marker}}});
    try{try{await manager.withProgress('update','npm:owned','Preparing',()=>Promise.reject(reason))}catch(error){caught=error}}finally{Object.defineProperty(globalThis,'Error',savedError)}
    rows.push([stage,caught===marker,trace]);
  }
  const manager=make(),trace=[];let resolve;
  const pending=new Promise(r=>resolve=r);manager.setProgressCallback(e=>trace.push(e.type));
  const operation=manager.withProgress('update','npm:owned','Preparing',()=>pending);trace.push('caller');queueMicrotask(()=>trace.push('microtask'));resolve('ignored');const returned=await operation;
  rows.push(['actual-await',returned===undefined,trace]);
  return {authority:'actual-Pi1.3-8efd-package-progress',rows};
}
