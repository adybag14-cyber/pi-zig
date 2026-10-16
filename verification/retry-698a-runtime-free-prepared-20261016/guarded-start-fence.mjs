// Capture-only guard/fence. No provider or Source function is substituted.
import fs from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import tls from 'node:tls';
import dgram from 'node:dgram';
import dns from 'node:dns';
import {registerHooks,syncBuiltinESMExports} from 'node:module';
import {createHash} from 'node:crypto';
import {resolve,join,sep} from 'node:path';
import {fileURLToPath} from 'node:url';
const configPath=process.env.PI_RETRY698_CAPTURE_CONFIG;
if(!configPath)throw Error('Exact owned Source160 config required');
const config=JSON.parse(fs.readFileSync(configPath));
const run=fs.realpathSync(config.run);
const container=fs.realpathSync(config.container);
if(!run.startsWith(resolve(container,'evidence')+sep)||process.version!=='v24.14.0')throw Error('Pinned contained Node reference required');
const runtime=resolve(config.forbidden_runtime),attempts=[],observed=[],resolutions=[];
const environmentNames=Object.keys(process.env);
const environmentAllowlist=new Set(['SystemRoot','WINDIR','ComSpec','PATH','PATHEXT','TEMP','TMP','HOME','USERPROFILE','HOMEDRIVE','HOMEPATH','APPDATA','LOCALAPPDATA','PI_CODING_AGENT_DIR','NO_COLOR','POWERSHELL_TELEMETRY_OPTOUT','POWERSHELL_UPDATECHECK','PSModulePath','PI_RETRY698_CAPTURE_CONFIG'].map(name=>name.toUpperCase()));
if(environmentNames.some(name=>!environmentAllowlist.has(name.toUpperCase())))throw Error('Unexpected inherited capture environment name');
for(const name of ['HOME','USERPROFILE','TEMP','TMP','APPDATA','LOCALAPPDATA','PI_CODING_AGENT_DIR'])if(!resolve(process.env[name]??'').startsWith(run+sep))throw Error('Owned fixture environment paths required');
const allowed=new Map(config.module_files.map(row=>[fs.realpathSync(row.path),row.sha256.toUpperCase()]));
const sha=path=>createHash('sha256').update(fs.readFileSync(path)).digest('hex').toUpperCase();
if(!process.permission||process.permission.has('child')||process.permission.has('worker')||process.permission.has('addons')||!process.permission.has('fs.write',run))throw Error('Expected restricted runtime-free Node permissions');
function deny(name){return function(){attempts.push({kind:'network',api:name});throw Error('Source160NetworkForbidden:'+name);};}
for(const [object,names,prefix] of [[http,['request','get','createServer'],'http'],[https,['request','get','createServer'],'https'],[net,['connect','createConnection','createServer'],'net'],[tls,['connect','createServer'],'tls'],[dgram,['createSocket'],'dgram']])for(const name of names)object[name]=deny(prefix+'.'+name);
net.Socket.prototype.connect=deny('net.Socket.connect');
for(const name of Object.keys(dns))if(name==='lookup'||name==='lookupService'||name.startsWith('resolve'))dns[name]=deny('dns.'+name);
for(const name of Object.keys(dns.promises))if(name==='lookup'||name==='lookupService'||name.startsWith('resolve'))dns.promises[name]=deny('dns.promises.'+name);
globalThis.fetch=deny('fetch');globalThis.WebSocket=deny('WebSocket');
for(const object of [fs,fs.promises])for(const name of ['readFile','readFileSync','open','openSync','realpath','realpathSync','access','accessSync','stat','statSync','lstat','lstatSync'])if(typeof object[name]==='function'){
 const original=object[name];object[name]=function(path,...args){
  if(typeof path!=='number'){
   const resolved=resolve(path instanceof URL?fileURLToPath(path):String(path));
   if(resolved===runtime||resolved.startsWith(runtime+sep)){attempts.push({kind:'runtime-access',api:name});throw Error('DeletedRuntimeAccessForbidden');}
  }
  return Reflect.apply(original,this,[path,...args]);
 };
}
syncBuiltinESMExports();
function observe(url){
 if(url.startsWith('node:'))return;
 if(!url.startsWith('file:')){attempts.push({kind:'unapproved-module-scheme'});throw Error('Only exact file and Node builtins allowed');}
 const path=fs.realpathSync(fileURLToPath(url));
 if(!allowed.has(path)||sha(path)!==allowed.get(path)){attempts.push({kind:'unapproved-file-module',path});throw Error('Unsealed Source160 module');}
 if(!observed.includes(path))observed.push(path);
}
registerHooks({resolve(specifier,context,next){
 resolutions.push({specifier,parentURL:context.parentURL});
 if(!specifier.startsWith('node:')&&!specifier.startsWith('file:')&&!specifier.startsWith('./')&&!specifier.startsWith('../')){attempts.push({kind:'package-import',specifier});throw Error('No npm/dependency import permitted');}
 if(specifier==='../types.ts'||specifier.includes('node_modules')){attempts.push({kind:'erased-or-dependency-import-request',specifier});throw Error('Unexpected type/dependency runtime resolution');}
 const result=next(specifier,context);observe(result.url);return result;
}});
observe(import.meta.url);
const ready=join(run,'start-fence-ready.json'),release=join(run,'start-fence-release.json');
fs.writeFileSync(ready,JSON.stringify({pid:process.pid,execPath:process.execPath,version:process.version,argv:process.argv,execArgv:process.execArgv,nonce:config.nonce,sourceImported:false},null,2),{flag:'wx'});
const deadline=Date.now()+10000;
while(!fs.existsSync(release)){if(Date.now()>=deadline)throw Error('Owned start-fence release deadline10s');await new Promise(resolve=>setTimeout(resolve,25));}
const permit=JSON.parse(fs.readFileSync(release));
if(permit.nonce!==config.nonce||permit.node_pid!==process.pid||permit.live_identity_verified!==true)throw Error('Exact live owned start-fence release required');
process.once('beforeExit',()=>{
 const classifier=fs.realpathSync(config.classifier);
 const required=config.module_files.map(row=>fs.realpathSync(row.path));
 const success=observed.includes(classifier)&&required.every(path=>observed.includes(path))&&attempts.length===0;
 fs.writeFileSync(join(run,'runtime-free-closure.json'),JSON.stringify({pid:process.pid,sourceHead:config.source_head,observed,resolutions,attempts,runtimeDependenciesLoaded:0,npmImports:0,networkRequests:0,environmentNames:environmentNames.sort(),environmentAllowlistMatched:true,credentialValuesRecorded:false,allRequiredModulesObserved:success,startFenceNonce:config.nonce},null,2),{flag:'wx'});
 if(!success)process.exitCode=1;
});
