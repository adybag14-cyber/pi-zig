// PREPARED ONLY. A separately granted controller pins Node24.14 and supplies
// one newly owned root; no runtime/dependency imports or network are used.
import * as fs from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
const root = resolve(process.argv[2]);
const rows=[];
const rawReason=Object.freeze({owned:'raw-getter-failure'});
const file=join(root,'file.txt'),dir=join(root,'directory'),missing=join(root,'missing');
fs.writeFileSync(file,'owned-lstat'); fs.mkdirSync(dir);
fs.writeFileSync(join(root,'unicode-🌍.txt'),'owned');
const links=[
  ['file-link','file.txt','file'],['directory-link','directory','dir'],
  ['broken-file-link','missing','file'],['broken-dir-link','missing-dir','dir'],
  ['unicode-link','unicode-🌍.txt','file'],['self-link','self-link','file'],
];
if(process.platform==='win32')links.push(['directory-junction',dir,'junction'],['broken-junction',join(root,'missing-dir'),'junction']);
const created=[];
for(const [name,target,type]of links){
  try{fs.symlinkSync(target,join(root,name),type);created.push(name);rows.push({id:'create-'+name,status:'returned'});}
  catch(error){rows.push({id:'create-'+name,status:'thrown',error:errorRecord(error)});}
}
function scalar(value){
  if(typeof value==='bigint')return{type:'bigint',decimal:value.toString()};
  if(value instanceof Date)return{type:'Date',milliseconds:value.getTime(),iso:value.toISOString()};
  return{type:typeof value,value};
}
function errorRecord(error){
  return{type:typeof error,name:error?.name,message:error?.message,own:Reflect.ownKeys(Object(error)).map(key=>({key:String(key),value:scalar(error[key]),descriptor:Object.getOwnPropertyDescriptor(error,key)})),sameRaw:error===rawReason};
}
function statsRecord(value){
  if(value===undefined)return{type:'undefined'};
  return{type:typeof value,constructor:value.constructor.name,own:Reflect.ownKeys(value).map(key=>({key:String(key),value:scalar(value[key]),enumerable:Object.prototype.propertyIsEnumerable.call(value,key)})),isDirectory:value.isDirectory(),isFile:value.isFile(),isSymbolicLink:value.isSymbolicLink(),isBlockDevice:value.isBlockDevice(),isCharacterDevice:value.isCharacterDevice(),isFIFO:value.isFIFO(),isSocket:value.isSocket(),statsPrototype:Object.getPrototypeOf(value)===fs.Stats.prototype};
}
function capture(id,operation){try{rows.push({id,status:'returned',value:operation()});}catch(error){rows.push({id,status:'thrown',error:errorRecord(error)});}}
for(const [id,path]of [['file',file],['dir',dir],...created.map(name=>[name,join(root,name)])]){
  capture('lstat-'+id,()=>statsRecord(fs.lstatSync(path)));
  capture('stat-'+id,()=>statsRecord(fs.statSync(path)));
  capture('bigint-'+id,()=>statsRecord(fs.lstatSync(path,{bigint:true})));
}
capture('missing-throws',()=>statsRecord(fs.lstatSync(missing)));
capture('missing-suppressed',()=>statsRecord(fs.lstatSync(missing,{throwIfNoEntry:false})));
capture('notdir-not-suppressed',()=>statsRecord(fs.lstatSync(join(file,'child'),{throwIfNoEntry:false})));
capture('url-path',()=>statsRecord(fs.lstatSync(pathToFileURL(file))));
capture('buffer-path',()=>statsRecord(fs.lstatSync(Buffer.from(file))));
capture('uint8-path',()=>statsRecord(fs.lstatSync(new Uint8Array(Buffer.from(file)))));
capture('nul-path-before-options',()=>fs.lstatSync(file+'\0owned',{get bigint(){throw rawReason}}));
capture('raw-bigint-getter',()=>fs.lstatSync(file,{get bigint(){throw rawReason}}));
capture('raw-missing-getter',()=>fs.lstatSync(file,{get throwIfNoEntry(){throw rawReason}}));
capture('null-options',()=>fs.lstatSync(file,null));
capture('strict-bigint-and-throwIfNoEntry',()=>statsRecord(fs.lstatSync(file,{bigint:1,throwIfNoEntry:0})));
capture('options-order',()=>{const trace=[];const stats=fs.lstatSync(file,{get bigint(){trace.push('bigint');return false},get throwIfNoEntry(){trace.push('throwIfNoEntry');return false}});return{trace,stats:statsRecord(stats)}});
capture('function-metadata',()=>({name:fs.lstatSync.name,length:fs.lstatSync.length,own:Reflect.ownKeys(fs.lstatSync),descriptor:Object.getOwnPropertyDescriptor(fs,'lstatSync')}));
process.stdout.write(JSON.stringify({node:process.version,platform:process.platform,rows})+'\n');
