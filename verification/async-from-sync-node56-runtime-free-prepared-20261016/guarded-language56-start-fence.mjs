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
import {resolve,join,dirname,sep} from 'node:path';
import {fileURLToPath} from 'node:url';
const configPath=process.env.PI_LANGUAGE56_CAPTURE_CONFIG;
if(!configPath)throw Error('Exact owned Language56 config required');
const config=JSON.parse(fs.readFileSync(configPath));
const run=fs.realpathSync(config.run);
// Avoid granting recursive read permission to the container merely to realpath it.
// The controller already rejects project reparse paths before the child starts.
const container=resolve(config.container);
if(!run.startsWith(resolve(container,'evidence')+sep)||process.version!=='v24.14.0')throw Error('Pinned contained Node reference required');
const runtime=resolve(config.forbidden_runtime),attempts=[],observed=[],resolutions=[],loaded=[];
const subjectBuiltins=new Set(['node:fs','node:path','node:url','node:crypto']);
if(config.scope!=='runtime-free-language56-only'||config.expected_cases!==56||config.module_files.length!==4)throw Error('Exact separately granted Language56 profile required');
const environmentNames=Object.keys(process.env);
const environmentAllowlist=new Set(['SystemRoot','WINDIR','ComSpec','PATH','PATHEXT','TEMP','TMP','HOME','USERPROFILE','HOMEDRIVE','HOMEPATH','APPDATA','LOCALAPPDATA','PI_CODING_AGENT_DIR','NO_COLOR','POWERSHELL_TELEMETRY_OPTOUT','POWERSHELL_UPDATECHECK','PSModulePath','PI_LANGUAGE56_CAPTURE_CONFIG'].map(name=>name.toUpperCase()));
if(environmentNames.some(name=>!environmentAllowlist.has(name.toUpperCase())))throw Error('Unexpected inherited capture environment name');
for(const name of ['HOME','USERPROFILE','TEMP','TMP','APPDATA','LOCALAPPDATA','PI_CODING_AGENT_DIR'])if(!resolve(process.env[name]??'').startsWith(run+sep))throw Error('Owned fixture environment paths required');
const allowed=new Map(config.module_files.map(row=>[fs.realpathSync(row.path),row.sha256.toUpperCase()]));
if(allowed.size!==4)throw Error('Four distinct sealed Language56 modules required');
const sha=path=>createHash('sha256').update(fs.readFileSync(path)).digest('hex').toUpperCase();
if(!process.permission||process.permission.has('child')||process.permission.has('worker')||process.permission.has('addons')||!process.permission.has('fs.write',run))throw Error('Expected restricted runtime-free Node permissions');
const forbiddenReadGrants=[container,runtime,join(dirname(process.execPath),'node_modules')];
if(forbiddenReadGrants.some(path=>process.permission.has('fs.read',path)))throw Error('No container/runtime/npm directory read grant allowed');
function deny(name){return function(){attempts.push({kind:'network',api:name});throw Error('Language56NetworkForbidden:'+name);};}
for(const [object,names,prefix] of [[http,['request','get','createServer'],'http'],[https,['request','get','createServer'],'https'],[net,['connect','createConnection','createServer'],'net'],[tls,['connect','createServer'],'tls'],[dgram,['createSocket'],'dgram']])for(const name of names)object[name]=deny(prefix+'.'+name);
net.Socket.prototype.connect=deny('net.Socket.connect');
for(const name of Object.keys(dns))if(name==='lookup'||name==='lookupService'||name==='reverse'||name.startsWith('resolve'))dns[name]=deny('dns.'+name);
for(const name of Object.keys(dns.promises))if(name==='lookup'||name==='lookupService'||name==='reverse'||name.startsWith('resolve'))dns.promises[name]=deny('dns.promises.'+name);
for(const [Resolver,prefix] of [[dns.Resolver,'dns.Resolver'],[dns.promises.Resolver,'dns.promises.Resolver']])
 for(const name of Object.getOwnPropertyNames(Resolver.prototype))if(name.startsWith('resolve')||name==='reverse')Resolver.prototype[name]=deny(prefix+'.'+name);
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
 if(!allowed.has(path)||sha(path)!==allowed.get(path)){attempts.push({kind:'unapproved-file-module',path});throw Error('Unsealed Language56 module');}
 if(!observed.includes(path))observed.push(path);
}
registerHooks({resolve(specifier,context,next){
 resolutions.push({specifier,parentURL:context.parentURL});
 if(specifier.startsWith('node:')&&!subjectBuiltins.has(specifier)){attempts.push({kind:'unapproved-subject-builtin',specifier});throw Error('Language56 builtin outside exact subject closure');}
 if(!specifier.startsWith('node:')&&!specifier.startsWith('file:')&&!specifier.startsWith('./')&&!specifier.startsWith('../')){attempts.push({kind:'package-import',specifier});throw Error('No npm/dependency import permitted');}
 if(specifier==='../types.ts'||specifier.includes('node_modules')){attempts.push({kind:'erased-or-dependency-import-request',specifier});throw Error('Unexpected type/dependency runtime resolution');}
 if(specifier.startsWith('node:'))return {url:specifier,shortCircuit:true};
 const url=new URL(specifier,context.parentURL);
 if(url.search||url.hash){attempts.push({kind:'unapproved-module-variation',specifier});throw Error('Exact canonical file module required');}
 observe(url.href);return {url:url.href,shortCircuit:true};
},load(url,context,next){
 if(url.startsWith('node:'))return next(url,context);
 observe(url);
 const path=fs.realpathSync(fileURLToPath(url)),bytes=fs.readFileSync(path),digest=createHash('sha256').update(bytes).digest('hex').toUpperCase();
 if(digest!==allowed.get(path)){attempts.push({kind:'loaded-byte-drift',path});throw Error('Exact loaded Language56 bytes required');}
 if(!loaded.some(row=>row.path===path))loaded.push({path,sha256:digest});
 return {format:'module',source:bytes,shortCircuit:true};
}});
observe(import.meta.url);
const ready=join(run,'start-fence-ready.json'),release=join(run,'start-fence-release.json');
fs.writeFileSync(ready,JSON.stringify({pid:process.pid,execPath:process.execPath,version:process.version,argv:process.argv,execArgv:process.execArgv,nonce:config.nonce,sourceImported:false},null,2),{flag:'wx'});
const deadline=Date.now()+10000;
while(!fs.existsSync(release)){if(Date.now()>=deadline)throw Error('Owned start-fence release deadline10s');await new Promise(resolve=>setTimeout(resolve,25));}
const permit=JSON.parse(fs.readFileSync(release));
if(permit.nonce!==config.nonce||permit.node_pid!==process.pid||permit.live_identity_verified!==true)throw Error('Exact live owned start-fence release required');
process.once('beforeExit',()=>{
 const subject=fs.realpathSync(config.subject);
 const required=config.module_files.map(row=>fs.realpathSync(row.path));
 const self=fs.realpathSync(fileURLToPath(import.meta.url));
 const success=observed.includes(subject)&&required.every(path=>observed.includes(path)&&(path===self||loaded.some(row=>row.path===path&&row.sha256===allowed.get(path)))))&&attempts.length===0;
 fs.writeFileSync(join(run,'runtime-free-closure.json'),JSON.stringify({scope:config.scope,pid:process.pid,sourceHead:config.source_head,observed,loaded,preloadSelf:{path:self,sha256:sha(self)},resolutions,attempts,forbiddenDirectoryReadGrants:false,runtimeDependenciesLoaded:0,npmImports:0,networkRequests:0,environmentNames:environmentNames.sort(),environmentAllowlistMatched:true,credentialValuesRecorded:false,allRequiredModulesObserved:success,startFenceNonce:config.nonce},null,2),{flag:'wx'});
 if(!success)process.exitCode=1;
});
