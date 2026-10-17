// Genuine Node24 builtin caller. PREPARED ONLY; no expected observations exist.
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
const rows=[];
const key=process.platform==='win32'?'USERPROFILE':'HOME';
const present=Object.hasOwn(process.env,key),previous=process.env[key];
function observe(id,body){try{rows.push({id,value:body()})}catch(error){rows.push({id,error:{name:error.name,code:error.code,errno:error.errno,syscall:error.syscall,message:error.message,info:error.info}})}}
try{
  delete process.env[key];
  observe('missing-native-account',()=>{const value=os.homedir();return{value,type:typeof value,absolute:path.isAbsolute(value),nonempty:value.length>0}});
  for(const[id,value]of[['empty',''],['one','a'],['two','ab'],['three','abc'],['relative','owned/home'],['unicode','λowned'],['trailing','C:\\owned\\'],['nul','C:\\owned\u0000suffix'],['boundary-259','x'.repeat(259)],['boundary-260','x'.repeat(260)]]){
    process.env[key]=value;
    observe('home-'+id,()=>os.homedir());
  }
  observe('release-native-cached',()=>({value:os.release(),again:os.release(),primitive:String(os.release)}));
  observe('platform-live',()=>({actual:os.platform(),process:process.platform,primitive:String(os.platform)}));
  observe('arch-live',()=>({actual:os.arch(),process:process.arch,primitive:String(os.arch)}));
  observe('tmpdir-existing-real-body',()=>{const value=os.tmpdir();return{value,type:typeof value,nonempty:value.length>0}});
  observe('type-version-native-cached',()=>({type:os.type(),typePrimitive:String(os.type),version:os.version(),versionPrimitive:String(os.version)}));
  observe('consumed-signal-constants',()=>({signals:Object.entries(os.constants.signals),frozen:Object.isFrozen(os.constants.signals)}));
  observe('constant-descriptors',()=>Object.fromEntries(['constants','EOL','devNull'].map(key=>{const d=Object.getOwnPropertyDescriptor(os,key);return[key,{writable:d.writable,enumerable:d.enumerable,configurable:d.configurable}]})));
  observe('consumed-function-metadata',()=>Object.fromEntries(['homedir','release','type','version','platform','arch','tmpdir'].map(key=>[key,{name:os[key].name,length:os[key].length,primitive:typeof os[key][Symbol.toPrimitive]}])));
}finally{
  if(present)process.env[key]=previous;else delete process.env[key];
}
globalThis.nativeOsConsumedRows={authority:'Node24.14.0-builtin-os-Pi1.3-consumed',rows};
export default globalThis.nativeOsConsumedRows;
