import {registerHooks} from 'node:module';
import {readFileSync,realpathSync,existsSync,appendFileSync} from 'node:fs';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {resolve,join,sep} from 'node:path';
import {createHash} from 'node:crypto';
const root=realpathSync(process.env.PI_RENDERER_SOURCE_ROOT),candidate=realpathSync(process.env.PI_RENDERER_CANDIDATE_ROOT),receipts=realpathSync(process.env.PI_RENDERER_RECEIPTS);
const hash=path=>createHash('sha256').update(readFileSync(path)).digest('hex');
const workspaces=JSON.parse(readFileSync(join(candidate,'verification/sdk-read-prompt-original-b45e0eb-20261014/workspaces.json'),'utf8'));
const manifests=['source','dependencies','node-tools','candidate'].map(name=>JSON.parse(readFileSync(join(receipts,name+'-before.json'),'utf8').replace(/^\uFEFF/,'')));
const allowed=new Map(manifests.flat().map(row=>[realpathSync(row.path),row.sha256.toLowerCase()])),seen=new Set();
function record(row){appendFileSync(join(receipts,`modules-${process.pid}.jsonl`),JSON.stringify(row)+'\n');}
function select(value){if(typeof value==='string')return value;if(!value||typeof value!=='object')throw Error('Unsupported official export');for(const key of ['source','import','default'])if(key in value)return select(value[key]);throw Error('No executable official export');}
function workspace(specifier){
 for(const workspace of workspaces){
  if(specifier!==workspace.specifier&&!specifier.startsWith(workspace.specifier+'/'))continue;
  const packagePath=join(root,workspace.path,'package.json');if(hash(packagePath)!==workspace.package_sha256.toLowerCase())throw Error('Official workspace manifest drift');
  const pkg=JSON.parse(readFileSync(packagePath,'utf8')),sub=specifier===workspace.specifier?'.':'./'+specifier.slice(workspace.specifier.length+1);let target;
  const exports=pkg.exports;
  if(typeof exports==='string'||exports&&!Object.keys(exports).some(key=>key.startsWith('.')))target=select(exports);
  else if(exports&&exports[sub])target=select(exports[sub]);
  else if(exports){for(const[key,value]of Object.entries(exports)){const star=key.indexOf('*');if(star<0||!sub.startsWith(key.slice(0,star))||!sub.endsWith(key.slice(star+1)))continue;target=select(value).replaceAll('*',sub.slice(star,sub.length-key.slice(star+1).length));break;}}
  else if(sub==='.')target=pkg.main;
  if(!target)throw Error('Official package export absent '+specifier);const officialTarget=target;
  if(target.startsWith('dist/'))target='./'+target;
  if(target.startsWith('./dist/'))target=target.replace('./dist/','./src/').replace(/\.js$/,'.ts').replace(/\.mjs$/,'.mts');
  const path=resolve(root,workspace.path,target);
  if(!path.startsWith(root+sep)||!existsSync(path))throw Error('Original Source target absent '+specifier+' -> '+path);
  record({kind:'official-workspace-export-map',specifier,packageName:pkg.name,packageVersion:pkg.version,officialTarget,sourceTarget:target,path});
  return{url:pathToFileURL(path).href,shortCircuit:true};
 }
 return null;
}
function observe(url){
 if(!url.startsWith('file:'))return;const path=realpathSync(fileURLToPath(url));
 if(!allowed.has(path))throw Error('Unmanifested original module '+path);
 if(seen.has(path))return;seen.add(path);const sha256=hash(path);
 if(sha256!==allowed.get(path))throw Error('Original module drift '+path);
 record({kind:'observed-module',path,sha256});
}
registerHooks({resolve(specifier,context,next){const result=workspace(specifier)??next(specifier,context);observe(result.url);return result;}});
observe(import.meta.url);
