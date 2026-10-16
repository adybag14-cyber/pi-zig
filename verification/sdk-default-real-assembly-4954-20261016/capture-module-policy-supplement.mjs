// Prepared genuine jiti39 supplement. Reference/fixture tooling only; run only
// with a separately sealed Root Source slot. No expected fixture is written.
import {readFile,writeFile,mkdir,stat,readdir} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const source='C:/Users/adyba/pi-upstream-source-4954d76-20261015/packages/coding-agent/src/';
const output=process.argv[2],fixtureArg=process.argv[3];if(!output||!fixtureArg)throw Error('Explicit new output and owned physical fixture required');
if(resolve(process.env.PI_PACKAGE_DIR??'')!==resolve(source,'..'))throw Error('Actual Source package required');
const fixture=resolve(fixtureArg);await mkdir(fixture,{recursive:true});
const ownedTemp=join(fixture,'tmp');await mkdir(ownedTemp,{recursive:true});
process.env.TEMP=ownedTemp;process.env.TMP=ownedTemp;process.env.TMPDIR=ownedTemp;process.env.JITI_RESPECT_TMPDIR_ENV='1';
const rows=[],physical=[];const add=(name,value)=>rows.push({name,value});
const portable=value=>typeof value==='string'?value.split(pathToFileURL(fixture).href).join('<fixture-url>').split(fixture).join('<fixture>'):value;
const errorValue=error=>({name:error?.name,message:portable(error?.message),stack:portable(error?.stack)});
async function retain(relative,bytes,label){
  const path=join(fixture,relative);await mkdir(resolve(path,'..'),{recursive:true});
  await writeFile(path,bytes,{flag:label==='created'?'wx':'w'});
  const info=await stat(path,{bigint:true});physical.push({label,path,bytes,sha256:createHash('sha256').update(await readFile(path)).digest('hex'),ino:String(info.ino),size:String(info.size),mtimeNs:String(info.mtimeNs),ctimeNs:String(info.ctimeNs),birthtimeNs:String(info.birthtimeNs)});return path;
}
const {createJiti}=await import(pathToFileURL(source+'core/extensions/jiti-loader.ts').href);
const {VIRTUAL_MODULES}=await import(pathToFileURL(source+'core/extensions/virtual-modules.ts').href);
const loaderUrl=pathToFileURL(source+'core/extensions/loader.ts').href;
const jitiPackage=await readFile('C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/jiti/package.json');
if(JSON.parse(jitiPackage).version!=='2.7.0'||createHash('sha256').update(jitiPackage).digest('hex')!=='aab8aafc42d9aeec14a6e2fe0e15ea1514c0c205a624055a7e776f2ec456283c')throw Error('Pinned jiti metadata drift');
function importer(){return createJiti(loaderUrl,{moduleCache:false,virtualModules:VIRTUAL_MODULES,tsconfigPaths:true})}
globalThis.modulePolicyCounts={};
const countCode=key=>`globalThis.modulePolicyCounts[${JSON.stringify(key)}]=(globalThis.modulePolicyCounts[${JSON.stringify(key)}]??0)+1;`;
const snapshot=()=>({...globalThis.modulePolicyCounts});
async function direct(key,extension,packageType){
  const dir=key;if(packageType!==null)await retain(dir+'/package.json',JSON.stringify(packageType===undefined?{}:{type:packageType})+'\n','created');
  const cjs=extension==='cjs'||packageType==='commonjs'||packageType===undefined;
  const code=version=>countCode(key)+(cjs?`const version=${version},count=globalThis.modulePolicyCounts[${JSON.stringify(key)}];module.exports=()=>({version,count});\n`:`export const version=${version},count=globalThis.modulePolicyCounts[${JSON.stringify(key)}],url=import.meta.url;export default ()=>({version,count,url});\n`);
  const path=await retain(dir+'/root.'+extension,code(1),'created');
  const first=await importer().import(path,{default:true});add(key+'-first',{value:{...first(),url:portable(first().url)},counts:snapshot()});
  const repeated=await importer().import(path,{default:true});add(key+'-repeated',{value:{...repeated(),url:portable(repeated().url)},sameFactory:first===repeated,counts:snapshot()});
  await retain(dir+'/root.'+extension,code(2),'root-edited');const edited=await importer().import(path,{default:true});
  add(key+'-edited',{value:{...edited(),url:portable(edited().url)},old:{...first(),url:portable(first().url)},sameFactory:first===edited,counts:snapshot()});
}
await direct('direct-mjs','mjs',null);
await direct('direct-cjs','cjs',null);
await direct('direct-js-esm','js','module');
await direct('direct-js-commonjs','js','commonjs');
await direct('direct-js-no-type','js',undefined);
await retain('package-transition/package.json','{"type":"commonjs"}\n','created');
const transition=await retain('package-transition/root.js',countCode('transition')+"module.exports=()=>({version:1});\n",'created');
const beforeTransition=await importer().import(transition,{default:true});add('package-type-commonjs-first',{value:beforeTransition(),counts:snapshot()});
await retain('package-transition/package.json','{"type":"module"}\n','type-edited');
await retain('package-transition/root.js',countCode('transition')+"export default ()=>({version:2,url:import.meta.url});\n",'root-edited');
try{const changed=await importer().import(transition,{default:true});add('package-type-commonjs-to-module',{value:{...changed(),url:portable(changed().url)},sameFactory:changed===beforeTransition,counts:snapshot()})}catch(error){add('package-type-commonjs-to-module',{error:errorValue(error),counts:snapshot()})}
await retain('package-transition/package.json','{"type":"commonjs"}\n','type-restored');
await retain('package-transition/root.js',countCode('transition')+"module.exports=()=>({version:3});\n",'root-restored');
try{const changed=await importer().import(transition,{default:true});add('package-type-restored-commonjs',{value:changed(),sameFactory:changed===beforeTransition,counts:snapshot()})}catch(error){add('package-type-restored-commonjs',{error:errorValue(error),counts:snapshot()})}
async function dynamic(kind,extension){
  const dir='dynamic-'+kind;const key='dependency-'+kind;
  const depCode=version=>countCode(key)+(kind==='cjs'?`const value=${version},count=globalThis.modulePolicyCounts[${JSON.stringify(key)}];module.exports={value,count};\n`:`export const value${kind==='ts'?':number':''}=${version},count=globalThis.modulePolicyCounts[${JSON.stringify(key)}];export const url=import.meta.url;\n`);
  await retain(dir+'/dependency.'+extension,depCode(1),'created');
  const rootCode=version=>`export const rootVersion:number=${version};export default async()=>{const namespace=await import('./dependency.${extension}');const dep=namespace.default??namespace;return {rootVersion,value:dep.value,count:dep.count,url:dep.url}};\n`;
  const path=await retain(dir+'/root.ts',rootCode(1),'created');const old=await importer().import(path,{default:true});
  const latePath=await retain(dir+'/late-root.ts',rootCode(1),'created');const lateOld=await importer().import(latePath,{default:true});
  const value1=await old();add(dir+'-first',{value:{...value1,url:portable(value1.url)},counts:snapshot()});
  const value2=await old();add(dir+'-same-live-factory-repeated',{value:{...value2,url:portable(value2.url)},counts:snapshot()});
  await retain(dir+'/dependency.'+extension,depCode(2),'dependency-edited');
  const value3=await old();add(dir+'-same-live-factory-after-edit',{value:{...value3,url:portable(value3.url)},counts:snapshot()});
  await retain(dir+'/root.ts',rootCode(2),'root-edited');const fresh=await importer().import(path,{default:true});
  const value4=await fresh();add(dir+'-reloaded-factory',{value:{...value4,url:portable(value4.url)},counts:snapshot()});
  const value5=await old();add(dir+'-old-closure-after-reload',{value:{...value5,url:portable(value5.url)},counts:snapshot()});
  const value6=await lateOld();add(dir+'-old-closure-first-dynamic-call-after-reload',{value:{...value6,url:portable(value6.url)},counts:snapshot()});
}
await dynamic('ts','ts');await dynamic('cjs','cjs');await dynamic('esm','mjs');
const staticStack=await retain('stack/root.ts',"export default function physicalRootStack(){throw new Error('physical-root-stack')}\n",'created');
try{const call=await importer().import(staticStack,{default:true});call();add('physical-root-stack',null)}catch(error){add('physical-root-stack',errorValue(error))}
await retain('stack/dependency.ts',"export function physicalDependencyStack(){throw new Error('physical-dependency-stack')}\n",'created');
const dynamicStack=await retain('stack/dynamic-root.ts',"export default async function physicalDynamicRootStack(){const dep=await import('./dependency.ts');return dep.physicalDependencyStack()}\n",'created');
try{const call=await importer().import(dynamicStack,{default:true});await call();add('physical-dynamic-stack',null)}catch(error){add('physical-dynamic-stack',errorValue(error))}
await retain('parallel/dependency.ts',countCode('parallel')+"await Promise.resolve();export const value:number=globalThis.modulePolicyCounts.parallel;\n",'created');
const parallel=await retain('parallel/root.ts',"export default async()=>{const dep=await import('./dependency.ts');return dep.value};\n",'created');
const parallelFactory=await importer().import(parallel,{default:true});
const parallelValues=await Promise.allSettled([parallelFactory(),parallelFactory()]);
add('same-live-factory-parallel-dynamic-tla',{values:parallelValues.map(value=>value.status==='fulfilled'?value:{status:value.status,reason:errorValue(value.reason)}),counts:snapshot()});
delete globalThis.modulePolicyCounts;
const physicalFinal=[];async function finalFiles(dir){for(const entry of await readdir(dir,{withFileTypes:true})){const path=join(dir,entry.name);if(entry.isDirectory())await finalFiles(path);else if(entry.isFile()){const info=await stat(path,{bigint:true});physicalFinal.push({path,sha256:createHash('sha256').update(await readFile(path)).digest('hex'),ino:String(info.ino),size:String(info.size),mtimeNs:String(info.mtimeNs),ctimeNs:String(info.ctimeNs),birthtimeNs:String(info.birthtimeNs)})}else throw Error('Unexpected physical fixture entry: '+path)}}await finalFiles(fixture);
if(rows.length!==39)throw Error('Module policy39 corpus incomplete: '+rows.length);
const packageBytes=await readFile(resolve(source,'../package.json'));const typeboxBytes=await readFile('C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/typebox/package.json');
await writeFile(output,JSON.stringify({authority:'4954d760504c11df9b2cbdc040346107b6a8153d',packageRootOverride:resolve(source,'..'),packageVersion:JSON.parse(packageBytes).version,packageSha256:createHash('sha256').update(packageBytes).digest('hex'),typeboxVersion:JSON.parse(typeboxBytes).version,typeboxPackageSha256:createHash('sha256').update(typeboxBytes).digest('hex'),jitiVersion:'2.7.0',jitiPackageSha256:createHash('sha256').update(jitiPackage).digest('hex'),driverSha256:createHash('sha256').update(await readFile(new URL(import.meta.url))).digest('hex'),cases:rows.length,rows,physical,physicalFinal},null,2)+'\n',{flag:'wx'});
