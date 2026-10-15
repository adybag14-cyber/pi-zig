// Prepared only. Run solely through a granted, frozen, bounded Source owner.
import fs from 'node:fs';
import path from 'node:path';
import util from 'node:util';
import crypto from 'node:crypto';
import {fileURLToPath,pathToFileURL} from 'node:url';
import net from 'node:net';
import http from 'node:http';
import https from 'node:https';
const [output,root]=process.argv.slice(2);
if(!output||!root||!path.basename(root).startsWith('sdk-exec-owned-')) throw Error('Explicit owned capture output/root required');
if(fs.existsSync(output)) throw Error('Refuse expected-output replay');
const deny=()=>{throw Error('SDK exec Source fixture forbids network');};
net.connect=net.createConnection=http.request=http.get=https.request=https.get=deny;
globalThis.fetch=deny;
const {execCommand}=await import(pathToFileURL('C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/coding-agent/src/core/exec.ts'));
const fixture=fileURLToPath(new URL('./owned-child.mjs',import.meta.url));
const nonce=crypto.randomUUID();
const rows=[];
const rawError=(e)=>({name:e?.name,message:e?.message,code:e?.code,inspect:util.inspect(e,{depth:8,showHidden:true}),ownKeys:Reflect.ownKeys(Object(e)).map(String)});
const args=(id,mode,...extra)=>[fixture,mode,root,id,nonce,...extra];
const delay=(ms)=>new Promise(resolve=>setTimeout(resolve,ms));
async function run(id,operation,trace=[]){
  const before=performance.now();
  let value;
  try{value={result:await operation()};}catch(error){value={error:rawError(error)};}
  rows.push({id,...value,trace,elapsedMs:performance.now()-before});
}
await run('argv-literal',()=>execCommand(process.execPath,args('argv-literal','argv','a b','&|><^%$`','€','"quoted"',''),root));
await run('separate-channels-controls',()=>execCommand(process.execPath,args('separate-channels-controls','channels'),root));
await run('nonzero',()=>execCommand(process.execPath,args('nonzero','nonzero'),root));
await run('invalid-utf8',()=>execCommand(process.execPath,args('invalid-utf8','bytes'),root));
await run('split-utf8',()=>execCommand(process.execPath,args('split-utf8','split'),root));
await run('above-execfile-default-maxbuffer',()=>execCommand(process.execPath,args('above-execfile-default-maxbuffer','large'),root));
{
  const trace=[];const options={};
  for(const key of ['cwd','env','shell','maxBuffer','onData']) Object.defineProperty(options,key,{get(){trace.push(key);throw Error(`Unused option ${key} read`);}});
  await run('ignored-options',()=>execCommand(process.execPath,args('ignored-options','cwd'),root,options),trace);
}
await run('timeout-ms',()=>execCommand(process.execPath,args('timeout-ms','sleep'),root,{timeout:60}));
await run('timeout-string',()=>execCommand(process.execPath,args('timeout-string','sleep'),root,{timeout:'60'}));
await run('timeout-zero',()=>execCommand(process.execPath,args('timeout-zero','sleep'),root,{timeout:0}));
{
  const controller=new AbortController();controller.abort(new Error('owned caller reason'));
  await run('preaborted-spawn',()=>execCommand(process.execPath,args('preaborted-spawn','sleep'),root,{signal:controller.signal}));
}
{
  const id='active-abort';const controller=new AbortController();
  const watcher=fs.watch(root,()=>{if(fs.existsSync(path.join(root,`${id}.ready`))) controller.abort();});
  try{await run(id,()=>execCommand(process.execPath,args(id,'ready'),root,{signal:controller.signal}));}finally{watcher.close();}
}
await run('self-signal',()=>execCommand(process.execPath,args('self-signal','self-term'),root));
await run('missing-executable',()=>execCommand(path.join(root,'fixture-not-an-executable'),[],root));
await run('missing-cwd',()=>execCommand(process.execPath,[],path.join(root,'missing-cwd')));
await run('nonstring-command',()=>execCommand(1,[],root));
await run('empty-command',()=>execCommand('',[],root));
await run('nonarray-args',()=>execCommand(process.execPath,{},root));
await run('null-byte-command',()=>execCommand('fixture\0invalid',[],root));
await run('null-byte-argument',()=>execCommand(process.execPath,['fixture\0invalid'],root));
await run('argument-coercion',()=>execCommand(process.execPath,args('argument-coercion','argv',1,null,undefined,{toString(){return 'object-arg';}}),root));
for(const kind of ['signal','timeout','addEventListener']){
  const trace=[];const original=new Error(`Owned ${kind} getter/callback`);const options={};
  if(kind==='addEventListener') options.signal={aborted:false,addEventListener(){trace.push('addEventListener');throw original;}};
  else Object.defineProperty(options,kind,{get(){trace.push(kind);throw original;}});
  await run(`throw-${kind}`,()=>execCommand(process.execPath,args(`throw-${kind}`,'sleep'),root,options),trace);
}
{
  const trace=[];let removals=0;
  const signal={aborted:false,addEventListener(name,callback,options){trace.push({method:'add',name,once:options.once,length:callback.length});},removeEventListener(name){trace.push({method:'remove',name,attempt:++removals});if(removals===1)throw Error('Owned first cleanup failure');}};
  await run('cleanup-catch-reresolve',()=>execCommand(process.execPath,args('cleanup-catch-reresolve','channels'),root,{signal}),trace);
}
for(const mode of ['descendant-quiet','descendant-active']) await run(mode,()=>execCommand(process.execPath,args(mode,mode),root));
if(process.platform!=='win32') await run('ignored-successful-sigterm',()=>execCommand(process.execPath,args('ignored-successful-sigterm','ignore-term'),root,{timeout:120}));
// Every fixture descendant has a natural bound below400ms. Retire those owned
// inputs naturally; this observer does not introduce a broad process killer.
await delay(750);
const identities=fs.readdirSync(root).filter(name=>name.endsWith('.identity.json')).sort().map(name=>JSON.parse(fs.readFileSync(path.join(root,name))));
if(identities.some(row=>row.nonce!==nonce||row.executable!==process.execPath))throw Error('Owned child identity mismatch');
const functionShape={name:execCommand.name,length:execCommand.length,tag:Object.prototype.toString.call(execCommand),ownKeys:Reflect.ownKeys(execCommand).map(String),asyncPrototype:Object.getPrototypeOf(execCommand)===Object.getPrototypeOf(async function(){})};
const observation={authority:'actual4954 core/exec.ts and child-process.ts; real owned Node24 children; no spawn mock',sourceHead:'4954d760504c11df9b2cbdc040346107b6a8153d',platform:process.platform,functionShape,rows,identities};
fs.writeFileSync(output,JSON.stringify(observation,null,2));
