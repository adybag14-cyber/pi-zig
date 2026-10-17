// Additive actual pathe2.0.3 / pathe/utils original subject. No expected data.
const {path:p,utils:u}=globalThis.nativePatheSubject;
const rows=[],cwd=globalThis.process?.cwd?.().replaceAll('\\','/');
function clean(value){return typeof value==='string'&&cwd?value.replaceAll(cwd,'<cwd>'):value}
function observe(name,run){try{rows.push({name,value:run()})}catch(error){rows.push({name,error:{name:error?.name??typeof error,message:error?.message??String(error)}})}}
for(const [target,name]of [[p,'resolve'],[u,'filename']])observe('metadata-'+name,()=>({name:target[name].name,length:target[name].length,prototype:Object.hasOwn(target[name],'prototype'),functionPrototype:Object.getPrototypeOf(target[name])===Function.prototype}));
const filenames=['','/','a','a.txt','.a','..','a.','a.tar.gz','a/b.txt','a\\b.txt','/a/.env','c:\\x\\a.d.ts','a/b/','a//b','a\0b.ext','é🌍.ts','a.\ud800','a\n.txt'];
for(let i=0;i<filenames.length;i++)observe('filename-'+i,()=>u.filename(filenames[i]));
const paths=[[],[''],['.'],['a','b'],['a','..','b'],['/a','../../b'],['/','..'],['c:/a','../b'],['c:\\a','..\\b'],['c:','a'],['\\\\server\\share','..','x'],['//.','a'],['../a','../b'],['a',null,false,0,'b'],['a','é🌍','..','\ud800'],['a','/x','y']];
for(let i=0;i<paths.length;i++)observe('resolve-'+i,()=>clean(p.resolve(...paths[i])));
observe('resolve-map-callback',()=>{const original=Array.prototype.map,log=[];Array.prototype.map=function(callback){log.push({name:callback.name,length:callback.length,prototype:Object.hasOwn(callback,'prototype')});return original.call(this,callback)};try{return{value:p.resolve('c:\\a','b'),log}}finally{Array.prototype.map=original}});
observe('resolve-live-cwd',()=>{const descriptor=Object.getOwnPropertyDescriptor(globalThis,'process'),log=[],mock={get cwd(){log.push('cwd');return function(){log.push('call');return'c:\\base\\x'}}};Object.defineProperty(globalThis,'process',{configurable:true,get(){log.push('process');return mock}});try{return{value:p.resolve('a'),log}}finally{if(descriptor)Object.defineProperty(globalThis,'process',descriptor);else delete globalThis.process}});
observe('filename-shared-regex',()=>{const original=String.prototype.split,regexes=[];String.prototype.split=function(regex,...args){regexes.push(regex);return original.call(this,regex,...args)};try{const values=[u.filename('a/b.js'),u.filename('c\\d.ts')];return{values,same:regexes[0]===regexes[1],source:regexes[0].source,flags:regexes[0].flags}}finally{String.prototype.split=original}});
observe('filename-raw-reason',()=>{const reason={original:1};try{u.filename({get split(){throw reason}});return false}catch(error){return error===reason}});
globalThis.nativePatheCacheObservation={count:rows.length,rows};
