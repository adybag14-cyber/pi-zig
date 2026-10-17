// PREPARED ONLY: genuine Node24 builtins, new owned root, no dependencies/network.
import * as fs from 'node:fs';
import { join,resolve } from 'node:path';
const root=resolve(process.argv[2]),file=join(root,'file.txt'),dir=join(root,'directory');
fs.writeFileSync(file,'owned-metadata-followup');fs.mkdirSync(dir);
const rows=[];
const original=Object.getOwnPropertyDescriptor(globalThis,'BigInt');
const rawReason=Object.freeze({owned:'global-BigInt-getter'});
function pick(stats){return{modeType:typeof stats.mode,mode:String(stats.mode),dev:String(stats.dev),ino:String(stats.ino),size:String(stats.size),mtimeMs:String(stats.mtimeMs),isDirectory:stats.isDirectory(),isFile:stats.isFile(),isSymbolicLink:stats.isSymbolicLink()}};
function record(id,run){try{rows.push({id,status:'returned',value:run()})}catch(reason){rows.push({id,status:'thrown',sameRaw:reason===rawReason,name:reason?.name,message:reason?.message})}}
record('stat-file-mode',()=>pick(fs.statSync(file)));
record('stat-directory-mode',()=>pick(fs.statSync(dir)));
record('lstat-file-mode',()=>pick(fs.lstatSync(file)));
record('lstat-directory-mode',()=>pick(fs.lstatSync(dir)));
for(const [id,path]of [['file',file],['directory',dir]]){
  const permissions=fs.statSync(path).mode&0o777;
  try{fs.chmodSync(path,0o444);record('readonly-'+id+'-modes',()=>({stat:pick(fs.statSync(path)),lstat:pick(fs.lstatSync(path))}));}
  finally{fs.chmodSync(path,permissions)}
}
const before=fs.statSync(dir,{bigint:true});
const trace=[];
try{
  Object.defineProperty(globalThis,'BigInt',{configurable:true,get(){trace.push('global BigInt');throw rawReason}});
  record('stat-bigint-under-throwing-global-getter',()=>pick(fs.statSync(dir,{bigint:true})));
  record('lstat-bigint-under-throwing-global-getter',()=>pick(fs.lstatSync(dir,{bigint:true})));
  record('existing-big-stats-method-under-global-getter',()=>({dir:before.isDirectory(),file:before.isFile()}));
  record('big-mode-property-coercion-and-receiver-order',()=>{
    const receiver={get mode(){trace.push('get mode');return before.mode}};
    const property={[Symbol.toPrimitive](hint){trace.push('property '+hint);return 0o040000}};
    const result=before._checkModeProperty.call(receiver,property);
    return{result,trace:[...trace]};
  });
  record('big-mode-property-raw-reason',()=>before._checkModeProperty.call(before,{[Symbol.toPrimitive](){throw rawReason}}));
  record('global-getter-trace',()=>[...trace]);
}finally{Object.defineProperty(globalThis,'BigInt',original)}
const calls=[];
try{
  Object.defineProperty(globalThis,'BigInt',{configurable:true,writable:true,value(value){calls.push(String(value));return 999n}});
  record('stat-bigint-under-replaced-function',()=>pick(fs.statSync(file,{bigint:true})));
  record('lstat-bigint-under-replaced-function',()=>pick(fs.lstatSync(dir,{bigint:true})));
  record('replaced-function-call-trace',()=>[...calls]);
}finally{Object.defineProperty(globalThis,'BigInt',original)}
process.stdout.write(JSON.stringify({node:process.version,platform:process.platform,rows})+'\n');
