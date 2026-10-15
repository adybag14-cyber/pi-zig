import {registerHooks,isBuiltin} from 'node:module';
import {readFileSync,writeFileSync,realpathSync} from 'node:fs';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {resolve,join,sep} from 'node:path';
import {createHash} from 'node:crypto';
const [sourceRoot,manifestPath,contractPath,closurePath,inputPath]=process.argv.slice(2);
const root=realpathSync(sourceRoot),hash=x=>createHash('sha256').update(x).digest('hex').toUpperCase();
const contract=JSON.parse(readFileSync(contractPath)),rows=JSON.parse(readFileSync(manifestPath));
if(contract.source_head!=='5ab7fe74c400097b386662205cd93900695b8a71'||contract.workspaces.length!==16)throw Error('Latest official workspace contract mismatch');
const frozen=new Map(rows.map(row=>[realpathSync(row.path),row.sha256]));
if(frozen.size!==rows.length)throw Error('Duplicate canonical frozen module path');
const caller=readFileSync(inputPath),callerURL='data:text/javascript;base64,'+caller.toString('base64');
const loaded=new Map(),builtins=new Set(),workspaceMappings=[];
function select(value){
 if(typeof value==='string')return value;
 if(!value||typeof value!=='object')throw Error('Unsupported official export');
 for(const key of ['source','import','default'])if(key in value)return select(value[key]);
 throw Error('No executable official export');
}
function workspace(specifier){
 for(const workspace of contract.workspaces){
  if(specifier!==workspace.specifier&&!specifier.startsWith(workspace.specifier+'/'))continue;
  const subpath=specifier===workspace.specifier?'.':'./'+specifier.slice(workspace.specifier.length+1);
  const pkg=JSON.parse(readFileSync(join(root,workspace.path,'package.json')));
  if(pkg.name!==workspace.packageName||pkg.version!==workspace.version)throw Error('Official workspace metadata changed');
  const exports=pkg.exports;let target;
  if(typeof exports==='string'||exports&&!Object.keys(exports).some(key=>key.startsWith('.')))target=select(exports);
  else if(exports&&exports[subpath])target=select(exports[subpath]);
  else if(exports){for(const [key,value] of Object.entries(exports)){
   const star=key.indexOf('*');
   if(star<0||!subpath.startsWith(key.slice(0,star))||!subpath.endsWith(key.slice(star+1)))continue;
   target=select(value).replaceAll('*',subpath.slice(star,subpath.length-key.slice(star+1).length));break;
  }}else if(subpath==='.')target=pkg.main;
  if(!target)throw Error('Official package export absent '+specifier);
  const officialTarget=target;
  if(target.startsWith('dist/'))target='./'+target;
  if(target.startsWith('./dist/'))target=target.replace('./dist/','./src/').replace(/\.js$/,'.ts').replace(/\.mjs$/,'.mts');
  const path=realpathSync(resolve(root,workspace.path,target));
  if(!path.startsWith(root+sep)||!frozen.has(path))throw Error('Latest Source workspace resolution escape '+path);
  workspaceMappings.push({specifier,officialTarget,sourceTarget:target,path});
  return {url:pathToFileURL(path).href,shortCircuit:true};
 }
 return null;
}
function observe(url){
 if(!url.startsWith('file:'))throw Error('Unpinned file module '+url);
 const path=realpathSync(fileURLToPath(url)),pin=frozen.get(path);
 if(!pin||hash(readFileSync(path))!==pin)throw Error('Unmanifested or drifted module '+path);
 return {path,pin};
}
registerHooks({
 resolve(specifier,context,next){return workspace(specifier)??next(specifier,context);},
 load(url,context,next){
  if(isBuiltin(url)){builtins.add(url);return next(url,context);}
  if(url===callerURL){const result=next(url,context);loaded.set(url,{kind:'unchanged-original-caller',sha256:hash(caller)});return result;}
  const {path,pin}=observe(url),result=next(url,context);
  if(hash(readFileSync(path))!==pin)throw Error('Executed module changed during load '+path);
  loaded.set(path,{kind:'unchanged-default-module',url,path,file_sha256:pin,format:result.format,loader_source_sha256:result.source==null?null:hash(typeof result.source==='string'?result.source:Buffer.from(result.source))});
  return result;
 }
});
observe(import.meta.url);
process.on('exit',code=>{
 const records=[...loaded.values()];
 const drift=records.filter(row=>row.path&&hash(readFileSync(row.path))!==row.file_sha256);
 writeFileSync(closurePath,JSON.stringify({source_head:contract.source_head,node:{version:process.version,executable:process.execPath,pid:process.pid},exit_code:code,unchanged_default_loader:true,manifest_sha256:hash(readFileSync(manifestPath)),observer_sha256:hash(readFileSync(fileURLToPath(import.meta.url))),records,workspace_mappings:workspaceMappings,builtins:[...builtins].sort(),post_drift:drift},null,2));
});
