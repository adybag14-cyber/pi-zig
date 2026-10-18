// Inert genuine original input. Root owns the accepted full-source/Node fence.
const moduleUrl=process.argv[2];
if(typeof moduleUrl!=='string'||!moduleUrl.startsWith('file:'))throw new TypeError('actual original package-manager module URL required');
const {DefaultPackageManager}=await import(moduleUrl);
const trace=[],reason={input:'actual-constructor-options'};
const options={get cwd(){trace.push('cwd');return process.cwd()},
  get agentDir(){trace.push('agentDir');return process.cwd()},
  get settingsManager(){trace.push('settingsManager');return {}},
  get builtinExtensions(){trace.push('builtinExtensions');throw reason}};
let actual;
try{new DefaultPackageManager(options)}catch(error){actual=error}
process.stdout.write(JSON.stringify({trace,rawReason:actual===reason,
  name:DefaultPackageManager.name,length:DefaultPackageManager.length,
  functionText:Function.prototype.toString.call(DefaultPackageManager)})+'\n');
