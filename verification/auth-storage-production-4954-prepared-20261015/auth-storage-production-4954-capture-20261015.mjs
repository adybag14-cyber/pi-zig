import fs from 'node:fs';
import path from 'node:path';
import {tmpdir} from 'node:os';
import {pathToFileURL} from 'node:url';
import {syncBuiltinESMExports} from 'node:module';
import {createHash} from 'node:crypto';
import {runAuthStorageCases,authStorageCaseIds} from './auth-storage-production-4954-cases-20261015.mjs';
const source='C:/Users/adyba/pi-upstream-source-4954d76-20261015/';
const tree='C:/Users/adyba/pi-zig-native-auth-storage-production-20261015/';
const root=fs.mkdtempSync(path.join(tmpdir(),'pi-auth-storage-production-4954-'));
const realRoot=fs.realpathSync(root),originalFs={},rawEffects=[],rawErrors=[],rawRevisions=[],previousEnv=new Map();
let output;
const timeout=setTimeout(()=>{console.error('Actual AuthStorage Source47 internal deadline');process.exit(124)},60000);
function owned(input){const value=path.resolve(String(input));if(value!==realRoot&&!value.startsWith(realRoot+path.sep))throw Error('Fixture path escaped owned root');return value}
function rememberEnv(name){if(!previousEnv.has(name))previousEnv.set(name,process.env[name])}
rememberEnv('PI_CODING_AGENT_DIR');process.env.PI_CODING_AGENT_DIR=realRoot;
globalThis.__authStorageRawError=(id,error)=>rawErrors.push({id,name:error?.name,message:error?.message,stack:error?.stack,constructor:error?.constructor?.name});
globalThis.__authStorageRawRevision=value=>rawRevisions.push(value);
try{
 for(const method of ['existsSync','mkdirSync','readFileSync','writeFileSync','statSync']){
  const original=fs[method];originalFs[method]=original;
  fs[method]=function(...args){
   const first=args[0],address=typeof first==='string'?path.resolve(first):undefined;
   if(address===realRoot||address?.startsWith(realRoot+path.sep))rawEffects.push({method,path:address,args:args.slice(1).map(value=>typeof value==='string'?value:value===undefined?null:value)});
   return Reflect.apply(original,this,args);
  };
 }
 syncBuiltinESMExports();
 const classes=await import(pathToFileURL(source+'packages/coding-agent/src/core/auth-storage.ts'));
 const fixture={root:realRoot,file:name=>owned(path.join(realRoot,name)),display:value=>String(value).replaceAll(realRoot,'<ROOT>'),toFileUrl:value=>String(pathToFileURL(owned(value))),read:value=>fs.readFileSync(owned(value),'utf-8'),write:(file,value)=>fs.writeFileSync(owned(file),value),setEnv(name,value){if(!name.startsWith('PI_AUTH_STORAGE_FIXTURE_'))throw Error('Fixture environment name escaped scope');rememberEnv(name);process.env[name]=value}};
 const observed=await runAuthStorageCases(classes,fixture);
 if(authStorageCaseIds.length!==47||observed.rows.length!==47||observed.rows.some((row,index)=>row.id!==authStorageCaseIds[index]))throw Error('Strict original AuthStorage47 inventory mismatch');
 const input=fs.readFileSync(tree+'src/extensions/fixtures/auth-storage-production-4954-cases.input.txt','utf8');
 const files=fs.readdirSync(realRoot,{recursive:true}).sort();
 if(files.some(file=>file.endsWith('.lock')))throw Error('Actual Source file backend left owned lock directories');
 output={sourceHead:'4954d760504c11df9b2cbdc040346107b6a8153d',runtime:process.version,count:47,inputSha256:createHash('sha256').update(input).digest('hex'),caseIds:authStorageCaseIds,rows:observed.rows,rawEffects,rawErrors,rawRevisions,ownedTempRoot:realRoot,ownedFiles:files};
}finally{
 for(const [method,original]of Object.entries(originalFs))fs[method]=original;
 syncBuiltinESMExports();
 for(const [name,value]of previousEnv)if(value===undefined)delete process.env[name];else process.env[name]=value;
 clearTimeout(timeout);
 const parent=path.resolve(tmpdir());
 if(path.dirname(realRoot)!==parent||!path.basename(realRoot).startsWith('pi-auth-storage-production-4954-')||fs.lstatSync(realRoot).isSymbolicLink()||fs.realpathSync(realRoot)!==realRoot)throw Error('Owned Source temporary root identity changed');
 for(const entry of fs.readdirSync(realRoot,{recursive:true,withFileTypes:true}))if(entry.isSymbolicLink())throw Error('Owned Source temporary root contains a link');
 fs.rmSync(realRoot,{recursive:true,force:false});
 if(fs.existsSync(realRoot))throw Error('Owned Source temporary root still exists after cleanup');
}
output.ownedTemporaryRemovedAndAbsenceVerified=true;
if(!process.argv[2])throw Error('Owned output path required');
fs.writeFileSync(process.argv[2],JSON.stringify(output,null,2)+'\n');
console.log(JSON.stringify({count:output.count,rawEffects:rawEffects.length,rawErrors:rawErrors.length,ownedTemporaryRemovedAndAbsenceVerified:true}));
