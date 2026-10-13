// Source-only oracle resolver. Product execution never imports this file.
import {registerHooks} from 'node:module';
import {readFileSync,realpathSync,existsSync,readdirSync,appendFileSync} from 'node:fs';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {resolve,join,sep,dirname} from 'node:path';
import {createHash} from 'node:crypto';
const root=realpathSync(process.env.PI_LOADOUT_SOURCE_ROOT);
const log=process.env.PI_LOADOUT_MODULE_LOG;
if(!log||existsSync(log))throw Error('Fresh module log required');
const helperRoot=realpathSync(dirname(fileURLToPath(import.meta.url)));
const deps=process.env.PI_LOADOUT_DEPS_ROOT?realpathSync(process.env.PI_LOADOUT_DEPS_ROOT):root;
const packageJson=JSON.parse(readFileSync(join(root,'package.json')));
const workspaces=[];
for(const pattern of packageJson.workspaces){
 const star=pattern.indexOf('*');
 if(star<0){if(existsSync(join(root,pattern,'package.json')))workspaces.push(pattern);continue;}
 if(star!==pattern.length-1)throw Error('Unsupported workspace pattern '+pattern);
 const parent=pattern.slice(0,-1);
 for(const entry of readdirSync(join(root,parent),{withFileTypes:true}))if(entry.isDirectory()&&existsSync(join(root,parent,entry.name,'package.json')))workspaces.push(join(parent,entry.name));
}
const packages=workspaces.map(path=>({path,manifest:JSON.parse(readFileSync(join(root,path,'package.json')))}));
if(packages.length!==16||packages.some(p=>p.manifest.version!=='1.2.0'))throw Error('Latest16 workspace contracts changed');
const hash=path=>createHash('sha256').update(readFileSync(path)).digest('hex');
const record=row=>appendFileSync(log,JSON.stringify(row)+'\n');
function select(value){if(typeof value==='string')return value;if(!value||typeof value!=='object')throw Error('Unsupported official export');for(const key of ['source','import','default'])if(key in value)return select(value[key]);throw Error('No executable official export');}
function workspace(specifier){
 for(const {path,manifest:pkg}of packages){
  if(specifier!==pkg.name&&!specifier.startsWith(pkg.name+'/'))continue;
  const sub=specifier===pkg.name?'.':'./'+specifier.slice(pkg.name.length+1),exp=pkg.exports;
  let target;
  if(typeof exp==='string'||exp&&!Object.keys(exp).some(k=>k.startsWith('.')))target=select(exp);
  else if(exp?.[sub])target=select(exp[sub]);
  else if(exp){for(const[key,value]of Object.entries(exp)){const star=key.indexOf('*');if(star<0||!sub.startsWith(key.slice(0,star))||!sub.endsWith(key.slice(star+1)))continue;target=select(value).replaceAll('*',sub.slice(star,sub.length-key.slice(star+1).length));break;}}
  else if(sub==='.')target=pkg.main;
  if(!target)throw Error('Official export absent '+specifier);
  const official=target;
  if(target.startsWith('dist/'))target='./'+target;
  if(target.startsWith('./dist/'))target=target.replace('./dist/','./src/').replace(/\.js$/,'.ts').replace(/\.mjs$/,'.mts');
  const selected=resolve(root,path,target);
  if(!selected.startsWith(root+sep)||!existsSync(selected))throw Error('Original Source target absent '+specifier);
  record({kind:'official-workspace-export-map',specifier,packageName:pkg.name,packageVersion:pkg.version,manifest:join(root,path,'package.json'),manifestSha256:hash(join(root,path,'package.json')),officialTarget:official,sourceTarget:target,path:selected});
  return{url:pathToFileURL(selected).href,shortCircuit:true};
 }
}
const seen=new Set();
function observe(url){
 if(!url.startsWith('file:'))return;
 const path=realpathSync(fileURLToPath(url));
 const allowed=path.startsWith(root+sep)||path.startsWith(helperRoot+sep)||(path.startsWith(deps+sep)&&path.includes(sep+'node_modules'+sep));
 if(!allowed)throw Error('Unmanifested Source dependency '+path);
 if(seen.has(path))return;seen.add(path);record({kind:'observed-module',path,sha256:hash(path)});
}
registerHooks({resolve(specifier,context,next){const result=workspace(specifier)??next(specifier,context);observe(result.url);return result;}});
observe(import.meta.url);
