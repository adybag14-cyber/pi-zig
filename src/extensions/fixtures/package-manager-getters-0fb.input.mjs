// Prepared transparent getter/owned-file controls. All observed methods remain
// the actual class functions; physicalRoot is a fresh owner-created directory.
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {join} from 'node:path';
const {DefaultPackageManager,SettingsManager,physicalRoot}=PackageAPI,rows=[];
if(typeof physicalRoot!=='string')throw Error('Actual owned physical root required');
const make=()=>new DefaultPackageManager({cwd:physicalRoot,agentDir:physicalRoot,settingsManager:SettingsManager.inMemory()});
{
 const manager=make(),trace=[];
 for(const name of ['getSourceMatchKeyForSettings','getPackageSourceString']){const original=DefaultPackageManager.prototype[name];Object.defineProperty(manager,name,{configurable:true,get(){trace.push(name);return original}})}
 const existing={get source(){trace.push('existing.source');return 'npm:pkg@1.0.0'}};
 rows.push({name:'settings-outer-callee-before-inner-source',match:manager.packageSourcesMatch(existing,'npm:pkg@2.0.0','user'),trace});
}
{
 const manager=make(),trace=[],original=DefaultPackageManager.prototype.resolveManagedPath;
 Object.defineProperty(manager,'resolveManagedPath',{configurable:true,get(){trace.push('resolveManagedPath');return original}});
 manager.getGitInstallPath({get host(){trace.push('source.host');return 'github.com'},get path(){trace.push('source.path');return 'owner/repo'}},'user');
 rows.push({name:'git-outer-callee-before-source-getters',trace});
}
const descriptor=Object.getOwnPropertyDescriptor(globalThis,'JSON'),originalJSON=JSON;
{
 const manager=make(),trace=[],root=join(physicalRoot,'version');mkdirSync(root,{recursive:true});const path=join(root,'package.json');writeFileSync(path,'{"version":"before"}');
 try{Object.defineProperty(globalThis,'JSON',{configurable:true,get(){trace.push('JSON');writeFileSync(path,'{"version":"after"}');return originalJSON}});const version=manager.getInstalledNpmVersion(root);rows.push({name:'installed-version-read-before-JSON-getter',version,trace,after:readFileSync(path,'utf8')});}finally{Object.defineProperty(globalThis,'JSON',descriptor)}
}
{
 const manager=make(),trace=[],root=join(physicalRoot,'dependencies');mkdirSync(root,{recursive:true});const path=join(root,'package.json');writeFileSync(path,'{"dependencies":{"missing":"1"}}');
 try{Object.defineProperty(globalThis,'JSON',{configurable:true,get(){trace.push('JSON');writeFileSync(path,'{"dependencies":{}}');return originalJSON}});const missing=manager.hasMissingGitDependencies(root);rows.push({name:'missing-dependencies-JSON-getter-before-read',missing,trace,after:readFileSync(path,'utf8')});}finally{Object.defineProperty(globalThis,'JSON',descriptor)}
}
globalThis.packageGetterRows=rows;globalThis.packageGetterComplete=true;
