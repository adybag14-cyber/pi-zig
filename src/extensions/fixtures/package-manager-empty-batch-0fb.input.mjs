// Prepared real-execution supplement. No successful command callback is used.
// The admitted owner must supply a fresh owned physicalRoot and actual pinned
// npmCommand with offline/ignore-scripts/no-audit/no-fund arguments.
import {existsSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
const {DefaultPackageManager,SettingsManager,physicalRoot,npmCommand}=PackageAPI;
if(typeof physicalRoot!=='string'||!Array.isArray(npmCommand)||npmCommand.length===0)throw Error('Actual physical root and pinned offline npm command required');
const installRoot=join(physicalRoot,'npm');
if(existsSync(installRoot))throw Error('Fresh owned empty-batch root required');
const settings=SettingsManager.inMemory({npmCommand}),manager=new DefaultPackageManager({cwd:physicalRoot,agentDir:physicalRoot,settingsManager:settings}),trace=[];
for(const name of ['getNpmInstallRoot','ensureNpmProject','runNpmCommand','getNpmInstallArgs']){
 const original=DefaultPackageManager.prototype[name];
 Object.defineProperty(manager,name,{configurable:true,get(){trace.push(name);return original}});
}
await manager.installNpmBatch([],'user');
globalThis.packageEmptyBatchRows=[{name:'empty-specs-still-create-and-install',trace,rootExists:existsSync(installRoot),packageJson:readFileSync(join(installRoot,'package.json'),'utf8'),gitignore:readFileSync(join(installRoot,'.gitignore'),'utf8'),lockExists:existsSync(join(installRoot,'package-lock.json'))}];
{
 const originalPush=Array.prototype.push,pushes=[];
 try{
  Array.prototype.push=function(...values){if(this[0]==='uninstall'&&values[0]==='--legacy-peer-deps')Reflect.apply(originalPush,pushes,[{name:'legacy-peer-deps-push',lengthBefore:this.length}]);return Reflect.apply(originalPush,this,values)};
  await manager.uninstallNpm({name:'unused-not-installed'},'user');
 }finally{Array.prototype.push=originalPush}
 globalThis.packageEmptyBatchRows.push({name:'uninstall-uses-live-explicit-push',pushes});
}
globalThis.packageEmptyBatchComplete=true;
