// Prepared genuine utils/paths.ts observations. The future reference harness
// loads the full pinned original module with an explicit process/import seam.
// No expected answers or replacement function body are supplied here.
const {markPathIgnoredByCloudSync:mark,process:subjectProcess,spawnCalls,caseId}=PathsAPI;
if(!['darwin','linux','win32','changing-platform','live-iterator','spawn-throw','iterator-close'].includes(caseId))throw Error('Explicit cloud-sync case required');
const trace=[];
let reads=0,callCount=0;
const path={toString(){trace.push('path-coercion');return '/uncoerced/cloud path'}};
Object.defineProperty(subjectProcess,'platform',{configurable:true,get(){
 reads++;trace.push(['platform',reads]);
 if(caseId==='changing-platform')return reads===1?'darwin':'linux';
 return caseId==='linux'?'linux':caseId==='win32'?'win32':'darwin';
}});
const reason={source:'spawn'},closeReason={source:'close'};
spawnCalls.observe=(command,args,options,receiver)=>{
 trace.push(['spawn',command,args.map(x=>x===path?'same-path':x),Object.keys(options),options.encoding,options.stdio,receiver===undefined]);
 callCount++;
 if(caseId==='spawn-throw'||caseId==='iterator-close')throw reason;
 return {ignoredResult:callCount};
};
const descriptor=Object.getOwnPropertyDescriptor(Array.prototype,Symbol.iterator);
let iterators=0;
if(caseId==='live-iterator'||caseId==='iterator-close'){
 Object.defineProperty(Array.prototype,Symbol.iterator,{...descriptor,value:function(){
  if(this[0]!=='com.dropbox.ignored')return Reflect.apply(descriptor.value,this,arguments);
  iterators++;trace.push(['attrs-iterator',this.length]);
  let step=0;
  return {next(){trace.push(['next',step]);return step++===0?{value:'custom.attribute',done:false}:{done:true}},return(){trace.push('return');if(caseId==='iterator-close')throw closeReason;return {done:true}}};
 }});
}
let result,error;
try{result=mark(path)}catch(caught){error=caught}
finally{Object.defineProperty(Array.prototype,Symbol.iterator,descriptor)}
globalThis.pathCloudSyncRows=[{caseId,trace,reads,callCount,iterators,resultUndefined:result===undefined,error:error===reason?'same-spawn':error===closeReason?'same-close':error?String(error):null}];
globalThis.pathCloudSyncComplete=true;
