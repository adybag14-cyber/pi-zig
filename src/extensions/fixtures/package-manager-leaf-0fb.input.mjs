// Prepared controls only. PackageAPI must contain the actual original or actual
// complete native classes; the observer supplies the real async-brand authority.
const {DefaultPackageManager,SettingsManager}=PackageAPI,rows=[];
const configurations=[undefined,[],['npm'],['npm.cmd'],['pnpm.exe'],['bun'],['wrapper','npm'],['wrapper','--','pnpm.cmd'],['wrapper','npm','bun'],['wrapper','--'],['wrapper','--','bun.exe','--','npm'],['']];
for(let index=0;index<configurations.length;index++){
 const settings=SettingsManager.inMemory({npmCommand:configurations[index]});
 const manager=new DefaultPackageManager({cwd:PackageAPI.cwd,agentDir:PackageAPI.agentDir,settingsManager:settings});
 try{rows.push({name:'command:'+index,command:manager.getNpmCommand(),manager:manager.getPackageManagerName(),dependencies:manager.getGitDependencyInstallArgs(),install:manager.getNpmInstallArgs(['pkg@^1','@scope/pkg@latest'],'/install-root')});}
 catch(error){rows.push({name:'command:'+index,error:{name:error.name,message:error.message}});}
}
for(const name of ['getNpmCommand','getPackageManagerName','getGitDependencyInstallArgs','runNpmCommandSync','getNpmInstallArgs','runNpmCommand','installNpm','uninstallNpm','installNpmBatch']){
 const fn=DefaultPackageManager.prototype[name],descriptor=Object.getOwnPropertyDescriptor(DefaultPackageManager.prototype,name);
 rows.push({name:'metadata:'+name,functionName:fn.name,length:fn.length,async:PackageAPI.isAsyncFunction(fn),ownPrototype:Object.hasOwn(fn,'prototype'),enumerable:descriptor.enumerable,configurable:descriptor.configurable,writable:descriptor.writable});
}
for(const mode of ['resolve','reject','throw','start-throws','complete-throws','error-throws']){
 const trace=[],operationReason={original:'operation'},callbackReason={original:'callback'};
 const manager=new DefaultPackageManager({cwd:PackageAPI.cwd,agentDir:PackageAPI.agentDir,settingsManager:SettingsManager.inMemory()});
 manager.setProgressCallback(function(event){trace.push({receiver:this===manager,event});if((mode==='start-throws'&&event.type==='start')||(mode==='complete-throws'&&event.type==='complete')||(mode==='error-throws'&&event.type==='error'))throw callbackReason;});
 let rejected;
 try{await manager.withProgress('install','npm:pkg','Installing npm:pkg...',()=>{trace.push('operation');if(mode==='throw')throw operationReason;if(mode==='reject'||mode==='error-throws')return Promise.reject(operationReason);return Promise.resolve();});}
 catch(error){rejected=error===operationReason?'operation':error===callbackReason?'callback':'unexpected';}
 rows.push({name:'progress:'+mode,trace,rejected});
}
for(const scenario of ['add','unchanged','change-version','preserve-filter','remove','remove-missing','version-match-remove']){
 const initial=scenario==='add'?[]:scenario==='preserve-filter'?[{source:'npm:pkg@1.0.0',extensions:['index.ts'],autoload:false}]:['npm:pkg@1.0.0'];
 const settings=SettingsManager.inMemory({packages:initial});
 const manager=new DefaultPackageManager({cwd:PackageAPI.cwd,agentDir:PackageAPI.agentDir,settingsManager:settings});
 const changed=scenario==='remove'||scenario==='version-match-remove'?manager.removeSourceFromSettings(scenario==='remove'?'npm:pkg@1.0.0':'npm:pkg@2.0.0'):scenario==='remove-missing'?manager.removeSourceFromSettings('npm:absent'):manager.addSourceToSettings(scenario==='unchanged'?'npm:pkg@1.0.0':'npm:pkg@2.0.0');
 rows.push({name:'settings:'+scenario,changed,packages:settings.getGlobalSettings().packages});
}
globalThis.packageLeafRows=rows;
globalThis.packageLeafComplete=true;
