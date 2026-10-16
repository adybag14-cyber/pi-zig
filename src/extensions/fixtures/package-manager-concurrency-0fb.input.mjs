const {DefaultPackageManager,SettingsManager}=PackageAPI,rows=[];
const manager=new DefaultPackageManager({cwd:PackageAPI.cwd,agentDir:PackageAPI.agentDir,settingsManager:SettingsManager.inMemory()});
for(const [name,count,limit]of[['empty',0,4],['limit-zero',3,0],['sequential',4,1],['two-workers',5,2],['more-workers-than-tasks',3,64]]){
 const trace=[],tasks=Array.from({length:count},(_,index)=>async function(){trace.push(['start',index,this===tasks]);await Promise.resolve();trace.push(['finish',index]);return index;});
 rows.push({name,result:await manager.runWithConcurrency(tasks,limit),trace});
}
{
 let thirdReached;const thirdReady=new Promise(resolve=>{thirdReached=resolve});
 const trace=[],gates=[],tasks=Array.from({length:3},(_,index)=>function(){trace.push(['start',index,this===tasks]);return new Promise(resolve=>{gates[index]=()=>{trace.push(['release',index]);resolve('value-'+index)};if(index===2)thirdReached()})});
 const work=manager.runWithConcurrency(tasks,2);gates[1]();await thirdReady;gates[2]();gates[0]();rows.push({name:'ordered-results-reversed-settlement',result:await work,trace});
}
{
 const trace=[],reason={original:'failure'};let release,thirdReached;const thirdReady=new Promise(resolve=>{thirdReached=resolve});
 const tasks=[function(){trace.push(['first',this===tasks]);return Promise.reject(reason)},function(){trace.push(['second',this===tasks]);return new Promise(resolve=>{release=()=>{trace.push('release-second');resolve('second')}})},function(){trace.push(['third-after-rejection',this===tasks]);thirdReached();return 'third'}];
 let same=false;try{await manager.runWithConcurrency(tasks,2)}catch(error){same=error===reason;trace.push('outer-rejected')}
 release();await thirdReady;await Promise.resolve();rows.push({name:'failfast-preserves-inflight-worker',same,trace});
}
{
 const trace=[],tasks=[function(){trace.push(['first',this===tasks]);tasks.push(function(){trace.push(['late',this===tasks]);return 2});return 1}];
 rows.push({name:'live-tasks-length-and-growth',result:await manager.runWithConcurrency(tasks,1),trace});
}
const fn=DefaultPackageManager.prototype.runWithConcurrency;rows.push({name:'metadata',functionName:fn.name,length:fn.length,async:PackageAPI.isAsyncFunction(fn),ownPrototype:Object.hasOwn(fn,'prototype')});
globalThis.packageConcurrencyRows=rows;globalThis.packageConcurrencyComplete=true;
