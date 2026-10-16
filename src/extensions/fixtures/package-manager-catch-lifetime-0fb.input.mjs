// Prepared genuine class controls; no expected output and no GC substitute.
// The owner must supply an actual fresh physicalRoot, then perform real GC and
// job-boundary retirement before calling finishPackageCatchLifetimeControl().
import {mkdirSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
const {DefaultPackageManager,SettingsManager,physicalRoot}=PackageAPI;
if(typeof physicalRoot!=='string')throw Error('Actual owned physical root required');
const make=()=>new DefaultPackageManager({cwd:physicalRoot,agentDir:physicalRoot,settingsManager:SettingsManager.inMemory()});
const rows=[];
for(const stage of ['operation','complete']){
 const manager=make(),reason={stage,toString(){return stage}},trace=[];
 manager.setProgressCallback(event=>{trace.push(event.type);if(event.type==='complete'&&stage==='complete')throw reason;if(event.type==='error')throw reason});
 let observed;
 try{await manager.withProgress('update','npm:fixture','fixture',()=>{if(stage==='operation')throw reason;return Promise.resolve()})}catch(error){observed=error}
 rows.push({name:`same-object-rethrow-from-${stage}-catch-callback`,same:observed===reason,trace});
}
const manager=make(),root=join(physicalRoot,'caught-manifest');
mkdirSync(root,{recursive:true});writeFileSync(join(root,'package.json'),'{}');
const descriptor=Object.getOwnPropertyDescriptor(globalThis,'JSON');
const finalized=[],registry=new FinalizationRegistry(token=>finalized.push(token));
let weak;
(()=>{
 const reason={ordinary:true};weak=new WeakRef(reason);registry.register(reason,'manifest-ordinary');
 try{Object.defineProperty(globalThis,'JSON',{configurable:true,get(){throw reason}});rows.push({name:'ordinary-manifest-catch',version:manager.getInstalledNpmVersion(root)})}
 finally{Object.defineProperty(globalThis,'JSON',descriptor)}
})();
globalThis.packageCatchLifetimeRows=rows;
globalThis.packageCatchLifetimePrepared=true;
globalThis.finishPackageCatchLifetimeControl=()=>{
 rows.push({name:'ordinary-manifest-weak-after-real-GC',released:weak.deref()===undefined,finalized:finalized.slice()});
 globalThis.packageCatchLifetimeComplete=true;
 // Do not assert FinalizationRegistry callback timing.
 return rows;
};
