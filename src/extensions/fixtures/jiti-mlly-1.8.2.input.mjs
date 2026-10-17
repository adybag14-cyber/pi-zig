// Prepared ORIGINAL subject: actual pinned mlly1.8.2 + real Node bindings.
// fixtureRootURL points to the byte-sealed jiti-mlly-tree directory.
// No fixture body is imported/evaluated: resolution and package JSON reads only.
const {mlly,fixtureRootURL,nodeURL,fs,process:subjectProcess}=globalThis.nativeMllySubject;
const base=new URL('entry.mjs',fixtureRootURL),rootPath=nodeURL.fileURLToPath(fixtureRootURL);
const rows=[];
function clean(value){if(typeof value==='string')return value.replaceAll(String(fixtureRootURL),'<fixture>/').replaceAll(rootPath,'<fixture>/').replaceAll(rootPath.replaceAll('\\','/'),'<fixture>/');if(Array.isArray(value))return value.map(clean);if(value&&typeof value==='object')return Object.fromEntries(Object.entries(value).map(([key,value])=>[key,clean(value)]));return value}
function observe(name,run){try{rows.push({name,value:clean(run())})}catch(error){rows.push({name,error:clean({name:error?.name??typeof error,code:error?.code,message:error?.message??String(error),url:error?.url,causeName:error?.cause?.name})})}}
for(const name of ['fileURLToPath','pathToFileURL','resolveSync','resolvePathSync'])observe('metadata-'+name,()=>({name:mlly[name].name,length:mlly[name].length,prototype:Object.hasOwn(mlly[name],'prototype'),functionPrototype:Object.getPrototypeOf(mlly[name])===Function.prototype}));
const cases=[
 ['relative-direct','./src/local.js'],['relative-extension','./src/local'],['relative-index','./src/folder'],
 ['absolute-file',nodeURL.fileURLToPath(new URL('src/local.js',fixtureRootURL))],['file-url',String(new URL('src/local.js',fixtureRootURL))],['url-object',new URL('src/local.js',fixtureRootURL)],
 ['bare-default','conditional'],['bare-custom','conditional',{conditions:['custom','import']}],['bare-unknown-conditions','conditional',{conditions:['unknown']}],
 ['package-pattern','conditional/feature/a'],['package-blocked','conditional/blocked'],['package-array','conditional/array'],['package-empty','conditional/empty'],['package-numeric','conditional/numeric'],['package-escape','conditional/escape'],['package-query','conditional/query'],
 ['self','fixture-root'],['local-import','#local'],['wild-import','#wild/local'],['trailer-import','#tail/local.js'],['external-import','#external'],
 ['legacy-main','legacy'],['unknown-package','not-installed-here'],['missing-file','./src/missing'],['encoded-separator','./src%2flocal.js'],['directory','./src'],['invalid-package','bad%name'],['invalid-import','#'],['mixed-export','mixed'],['bad-config','bad-config'],
];
for(const [name,id,options]of cases)observe('resolve-'+name,()=>({url:mlly.resolveSync(id,{url:base,...options}),path:mlly.resolvePathSync(id,{url:base,...options})}));
for(const [name,id]of [['plain','relative/path'],['backslash','c:\\a\\b'],['uppercase','FILE:///a'],['url',String(new URL('src/local.js',fixtureRootURL))],['object',new URL('src/local.js',fixtureRootURL)]])observe('file-'+name,()=>mlly.fileURLToPath(id));
for(const [name,id]of [['path',rootPath],['file',new URL('src/local.js',fixtureRootURL)],['http','https://example.invalid/a']])observe('url-'+name,()=>mlly.pathToFileURL(id));
for(const id of ['node:test','fs','https://example.invalid/a'])observe('protocol-'+id,()=>mlly.resolveSync(id,{get url(){throw Error('bypass must skip options')}}));
observe('conditions-live-read',()=>{const log=[],options={url:base,get conditions(){log.push('conditions');return['custom','import']}};return{value:mlly.resolveSync('conditional',options),log}});
observe('url-live-read',()=>{const log=[],options={get url(){log.push('url');return base}};return{value:mlly.resolveSync('./src/local.js',options),log}});
observe('conditions-raw-reason',()=>{const reason={original:1},options={url:base,conditions:{[Symbol.iterator](){throw reason}}};try{mlly.resolveSync('conditional',options);return false}catch(error){return error===reason}});
observe('extensions-entered-close',()=>{const log=[],extensions={[Symbol.iterator](){let i=0;return{next(){log.push('next');return i++===0?{value:'.bad',done:false}:i===2?{value:'.js',done:false}:{done:true}},return(){log.push('return');return{done:true}}}}};return{value:mlly.resolveSync('./src/local',{url:base,extensions}),log}});
observe('legacy-module-warning',()=>{const original=subjectProcess.emitWarning,log=[];subjectProcess.emitWarning=function(...args){log.push(args)};try{return{value:mlly.resolveSync('legacy-module',{url:base}),log}}finally{subjectProcess.emitWarning=original}});
observe('same-module-package-cache',()=>{const original=fs.readFileSync,log=[];fs.readFileSync=function(path,...args){log.push(String(path));return original.call(this,path,...args)};try{return{first:mlly.resolveSync('conditional',{url:base}),second:mlly.resolveSync('conditional',{url:base}),log}}finally{fs.readFileSync=original}});
globalThis.nativeMllyObservation={count:rows.length,rows};
