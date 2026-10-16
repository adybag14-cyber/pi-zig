// Genuine jiti reference controls, prepared only. Physical bodies/metadata stay
// retained; run under Root's full sealed Source slot and original module import.
import {readFile,writeFile,mkdir,stat,readdir} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const source='C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/coding-agent/src/';
const output=process.argv[2],fixtureArg=process.argv[3];if(!output||!fixtureArg)throw Error('Explicit new output and owned physical fixture required');
if(resolve(process.env.PI_PACKAGE_DIR??'')!==resolve(source,'..'))throw Error('Actual Source package required');
const fixture=resolve(fixtureArg);await mkdir(fixture,{recursive:true});
// Keep genuine jiti's default fsCache effects in the owned retained directory.
// This selects actual process environment, without replacing Source options.
const ownedTemp=join(fixture,'tmp');await mkdir(ownedTemp,{recursive:true});
process.env.TEMP=ownedTemp;process.env.TMP=ownedTemp;process.env.TMPDIR=ownedTemp;process.env.JITI_RESPECT_TMPDIR_ENV='1';
const rows=[],physical=[];const add=(name,value)=>rows.push({name,value});
const portable=value=>typeof value==='string'?value.split(pathToFileURL(fixture).href).join('<fixture-url>').split(fixture).join('<fixture>'):value;
async function retain(name,bytes,label){
  const path=join(fixture,name);await writeFile(path,bytes,{flag:label==='created'?'wx':'w'});
  const info=await stat(path,{bigint:true});
  physical.push({label,path,bytes,sha256:createHash('sha256').update(await readFile(path)).digest('hex'),ino:String(info.ino),size:String(info.size),mtimeNs:String(info.mtimeNs),ctimeNs:String(info.ctimeNs),birthtimeNs:String(info.birthtimeNs)});
  return path;
}
const jitiModule=await import(pathToFileURL(source+'core/extensions/jiti-loader.ts').href);
const virtualModule=await import(pathToFileURL(source+'core/extensions/virtual-modules.ts').href);
const loaderUrl=pathToFileURL(source+'core/extensions/loader.ts').href;
const jitiPackage=await readFile('C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/jiti/package.json');
if(JSON.parse(jitiPackage).version!=='2.7.0')throw Error('Pinned jiti version drift');
function importer(){return jitiModule.createJiti(loaderUrl,{moduleCache:false,virtualModules:virtualModule.VIRTUAL_MODULES,tsconfigPaths:true})}
globalThis.freshRootCounts={root:0,dependency:0,cjs:0,cycleRoot:0,cycleDependency:0};
const dep=await retain('dependency.ts',"globalThis.freshRootCounts.dependency++; export const value:number=1; export const count=globalThis.freshRootCounts.dependency;\n",'created');
const root=await retain('root.ts',"import {value,count} from './dependency.ts'; globalThis.freshRootCounts.root++; export const version:number=1; export const rootCount=globalThis.freshRootCounts.root; export const dependency=value; export const dependencyCount=count; export const url=import.meta.url; export const read=()=>({version,dependency,rootCount,dependencyCount}); export default read;\n",'created');
const first=await importer().import(root);add('first-transformed-root',{...first.read(),url:portable(first.url),counts:{...globalThis.freshRootCounts}});
const second=await importer().import(root);add('repeated-transformed-root',{...second.read(),sameNamespace:first===second,sameDefault:first.default===second.default,counts:{...globalThis.freshRootCounts}});
await retain('root.ts',"import {value,count} from './dependency.ts'; globalThis.freshRootCounts.root++; export const version:number=2; export const rootCount=globalThis.freshRootCounts.root; export const dependency=value; export const dependencyCount=count; export const url=import.meta.url; export const read=()=>({version,dependency,rootCount,dependencyCount}); export default read;\n",'root-edited');
const edited=await importer().import(root);add('same-file-root-edit',{...edited.read(),old:first.read(),url:portable(edited.url),counts:{...globalThis.freshRootCounts}});
await retain('dependency.ts',"globalThis.freshRootCounts.dependency++; export const value:number=2; export const count=globalThis.freshRootCounts.dependency;\n",'dependency-edited');
const dependencyEdited=await importer().import(root);add('same-file-transformed-dependency-edit',{...dependencyEdited.read(),old:first.read(),previous:edited.read(),counts:{...globalThis.freshRootCounts}});
const direct=await retain('direct-self.ts',"import {read as selfRead} from './direct-self.ts'; export const version:number=1; export function read(){return version}; export const same=()=>selfRead===read; export default ()=>({version:read(),same:same(),url:import.meta.url});\n",'created');
try{const value=await importer().import(direct,{default:true});add('direct-self-cycle',{...value(),url:portable(value().url)})}catch(error){add('direct-self-cycle',{name:error.name,message:portable(error.message)})}
const cycleDep=await retain('cycle-dependency.ts',"import {version} from './cycle-root.ts'; globalThis.freshRootCounts.cycleDependency++; export const peek=()=>version;\n",'created');
void dep;void cycleDep;
const cycleRoot=await retain('cycle-root.ts',"import {peek} from './cycle-dependency.ts'; globalThis.freshRootCounts.cycleRoot++; export const version:number=1; export default ()=>({version,peek:peek()});\n",'created');
let oldCycle;
try{oldCycle=await importer().import(cycleRoot,{default:true});add('indirect-cycle-first',{value:oldCycle(),counts:{...globalThis.freshRootCounts}})}catch(error){add('indirect-cycle-first',{name:error.name,message:portable(error.message)})}
await retain('cycle-root.ts',"import {peek} from './cycle-dependency.ts'; globalThis.freshRootCounts.cycleRoot++; export const version:number=2; export default ()=>({version,peek:peek()});\n",'cycle-root-edited');
try{const value=await importer().import(cycleRoot,{default:true});add('indirect-cycle-reload',{value:value(),old:oldCycle?.(),counts:{...globalThis.freshRootCounts}})}catch(error){add('indirect-cycle-reload',{name:error.name,message:portable(error.message)})}
const cjs=await retain('dependency.cjs',"globalThis.freshRootCounts.cjs++;module.exports={value:1,count:globalThis.freshRootCounts.cjs};\n",'created');
void cjs;
const cjsRoot=await retain('cjs-root.ts',"import value from './dependency.cjs'; export default ()=>value;\n",'created');
const firstCjs=await importer().import(cjsRoot,{default:true});add('cjs-dependency-first',{value:firstCjs(),counts:{...globalThis.freshRootCounts}});
await retain('dependency.cjs',"globalThis.freshRootCounts.cjs++;module.exports={value:2,count:globalThis.freshRootCounts.cjs};\n",'cjs-dependency-edited');
const secondCjs=await importer().import(cjsRoot,{default:true});add('cjs-dependency-edit',{value:secondCjs(),old:firstCjs(),counts:{...globalThis.freshRootCounts}});
const shared=await retain('shared-root.ts',"import {value,count} from './dependency.ts';export default ()=>({value,count});\n",'created');
const sharedFirst=await importer().import(shared,{default:true});
await retain('dependency.ts',"globalThis.freshRootCounts.dependency++;export const value:number=3;export const count=globalThis.freshRootCounts.dependency;\n",'shared-dependency-edited');
const sharedSecond=await importer().import(shared,{default:true});const sharedOther=await importer().import(root);
add('shared-dependency-two-roots',{first:sharedFirst(),second:sharedSecond(),other:sharedOther.read(),old:first.read(),counts:{...globalThis.freshRootCounts}});
await retain('data.json','{"value":1}\n','created');
const jsonRoot=await retain('json-root.ts',"import data from './data.json';export default ()=>data;\n",'created');
const firstJson=await importer().import(jsonRoot,{default:true});await retain('data.json','{"value":2}\n','json-edited');
const secondJson=await importer().import(jsonRoot,{default:true});add('json-dependency-edit',{first:firstJson(),second:secondJson(),same:firstJson()===secondJson()});
await retain('native-dependency.mjs',"export const value=1;export const url=import.meta.url;\n",'created');
const nativeRoot=await retain('native-root.ts',"import {value,url} from './native-dependency.mjs';export default ()=>({value,url});\n",'created');
const firstNative=await importer().import(nativeRoot,{default:true});await retain('native-dependency.mjs',"export const value=2;export const url=import.meta.url;\n",'native-dependency-edited');
const secondNative=await importer().import(nativeRoot,{default:true});add('native-esm-dependency-edit',{first:{...firstNative(),url:portable(firstNative().url)},second:{...secondNative(),url:portable(secondNative().url)}});
const tla=await retain('tla-root.ts',"export const before:number=1;await Promise.resolve();export const after:number=2;export const url=import.meta.url;export default ()=>({before,after,url});\n",'created');
try{const value=await importer().import(tla,{default:true});add('top-level-await-root',{...value(),url:portable(value().url)})}catch(error){add('top-level-await-root',{name:error.name,message:portable(error.message)})}
const loader=await import(loaderUrl);loader.clearExtensionCache();
let release,started;globalThis.freshRootGate=new Promise(resolve=>{release=resolve});const reached=new Promise(resolve=>{started=resolve});globalThis.freshRootStarted=started;
globalThis.freshStaleRuns=[];
const stale=await retain('stale-extension.ts',"globalThis.freshStaleRuns.push(1);globalThis.freshRootStarted();await globalThis.freshRootGate;export default pi=>pi.registerCommand('stale',{handler:()=>1});\n",'created');
const inflight=loader.loadExtensionsCached([stale],fixture);
await Promise.race([reached,inflight.then(result=>{throw Error('Inflight control completed before gate: '+JSON.stringify(result.errors))})]);
loader.clearExtensionCache();
await retain('stale-extension.ts',"globalThis.freshStaleRuns.push(2);export default pi=>pi.registerCommand('stale',{handler:()=>2});\n",'stale-root-edited');
const replacement=await loader.loadExtensionsCached([stale],fixture);release();const original=await inflight;const cached=await loader.loadExtensionsCached([stale],fixture);
const staleResult=value=>({errors:value.errors,commands:value.extensions.map(extension=>extension.commands.get('stale')?.handler())});
add('clear-cache-stale-inflight-token',{original:staleResult(original),replacement:staleResult(replacement),cached:staleResult(cached),runs:globalThis.freshStaleRuns});
delete globalThis.freshRootGate;delete globalThis.freshRootStarted;delete globalThis.freshStaleRuns;
delete globalThis.freshRootCounts;
const physicalFinal=[];
async function finalFiles(dir){for(const entry of await readdir(dir,{withFileTypes:true})){const path=join(dir,entry.name);if(entry.isDirectory())await finalFiles(path);else if(entry.isFile()){const info=await stat(path,{bigint:true});physicalFinal.push({path,sha256:createHash('sha256').update(await readFile(path)).digest('hex'),ino:String(info.ino),size:String(info.size),mtimeNs:String(info.mtimeNs),ctimeNs:String(info.ctimeNs),birthtimeNs:String(info.birthtimeNs)})}else throw Error('Unexpected physical fixture entry: '+path)}}
await finalFiles(fixture);
if(rows.length!==14)throw Error('Fresh root14 corpus incomplete');
await writeFile(output,JSON.stringify({authority:'4954d760504c11df9b2cbdc040346107b6a8153d',reference:'actual pinned jiti-loader/virtual-modules with exact Source resolution options',jitiVersion:'2.7.0',jitiPackageSha256:createHash('sha256').update(jitiPackage).digest('hex'),cases:rows.length,rows,physical,physicalFinal},null,2)+'\n',{flag:'wx'});
