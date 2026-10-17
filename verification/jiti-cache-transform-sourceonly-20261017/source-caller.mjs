// PREPARED ONLY. Exact admitted official jiti2.7 dist factory; Node builtins;
// owned custom transform USER options. No default Babel substitute or packages.
import { createRequire } from 'node:module';
import * as fs from 'node:fs';
import { join,resolve,relative,isAbsolute } from 'node:path';
import { tmpdir } from 'node:os';
const originalProcess=globalThis.process;
const root=resolve(originalProcess.argv[3]),nonce=originalProcess.argv[4];
const within=path=>{const rel=relative(root,resolve(path));return rel===''||(!rel.startsWith('..')&&!isAbsolute(rel))};
if(!nonce||originalProcess.env.PI_JITI_CACHE_CAPTURE_OWNED!==nonce||!within(originalProcess.cwd())||!within(tmpdir()))throw Error('separate owned start/dummy-temp fence required');
const require=createRequire(import.meta.url);
const createJiti=require(resolve(originalProcess.argv[2]));
const parent={createRequire,onError(reason){throw reason},nativeImport(id){return import(id)}};
const rows=[];
const rawReason=Object.freeze({owned:'raw-cache-transform-reason'});
function errorRecord(reason){return{type:typeof reason,sameRaw:reason===rawReason,name:reason?.name,message:reason?.message,code:reason?.code,errno:reason?.errno,path:reason?.path,syscall:reason?.syscall,stack:reason?.stack}}
function observe(id,run){try{rows.push({id,status:'returned',value:run()})}catch(reason){rows.push({id,status:'thrown',reason:errorRecord(reason)})}}
function fixture(name){const directory=join(root,name);fs.mkdirSync(directory,{recursive:true});const entry=join(directory,'entry.ts');fs.writeFileSync(entry,'export const original=1;');return{directory,entry,cache:join(directory,'cache')}}
function files(path){if(!path||typeof path!=='string'||!fs.existsSync(path)||!fs.statSync(path).isDirectory())return[];return fs.readdirSync(path).sort().map(name=>({name,bytes:fs.readFileSync(join(path,name),'utf8')}))}
function make(name,extra={}){
  const paths=fixture(name),trace=[],state={code:'module.exports = 42;',calls:0,result:undefined};let instance;
  function hook(options){state.calls++;trace.push({event:'user-transform',sameThis:this===instance.options,keys:Reflect.ownKeys(options).map(String),options});if(state.throw)throw state.throw;return state.result??{code:state.code}}
  instance=createJiti(paths.entry,{tsconfigPaths:false,debug:false,fsCache:paths.cache,transform:hook,...extra},parent);
  return{paths,trace,state,instance,options:{source:'owned source',filename:paths.entry,ts:true,async:false},snapshot(){return{calls:state.calls,trace,cache:files(instance.options.fsCache),fsCache:instance.options.fsCache}}};
}
observe('cache-disabled',()=>{const c=make('disabled',{fsCache:false});return{code:c.instance.transform(c.options),...c.snapshot()}});
observe('filename-absent',()=>{const c=make('filename-absent');delete c.options.filename;return{code:c.instance.transform(c.options),...c.snapshot()}});
observe('miss-hit-stored-suffix',()=>{const c=make('hit');const first=c.instance.transform(c.options),afterFirst=c.snapshot(),second=c.instance.transform(c.options);return{first,afterFirst,second,...c.snapshot()}});
observe('stale-source-hash-overwrites',()=>{const c=make('stale');c.instance.transform(c.options);const name=fs.readdirSync(c.paths.cache)[0];fs.writeFileSync(join(c.paths.cache,name),'owned stale without suffix');return{code:c.instance.transform(c.options),...c.snapshot()}});
observe('source-change-invalidates-same-filename',()=>{const c=make('changed');c.instance.transform(c.options);c.options.source='owned changed source';return{code:c.instance.transform(c.options),...c.snapshot()}});
observe('rebuild-bypasses-existing-hit',()=>{const c=make('rebuild');c.instance.transform(c.options);c.instance.options.rebuildFsCache=true;return{code:c.instance.transform(c.options),...c.snapshot()}});
observe('maps-interop-async-jsx-cache-name',()=>{const c=make('flags',{sourceMaps:true,interopDefault:true,transformOptions:{babel:{sourceFileName:'owned override',sourceMaps:false,extra:1},customBase:'owned'}});Object.assign(c.options,{filename:join(c.paths.directory,'view.tsx'),async:true,interopDefault:true,jsx:true});return{code:c.instance.transform(c.options),...c.snapshot()}});
observe('top-babel-overrides-constructed-object',()=>{const c=make('top-babel',{sourceMaps:true,transformOptions:{babel:{first:'owned'},other:'base'}});c.options.babel={last:'owned top-level'};return{code:c.instance.transform(c.options),...c.snapshot()}});
observe('cache-flags-read-source-fields-exactly',()=>{const c=make('flag-origin',{sourceMaps:true,interopDefault:true});Object.assign(c.options,{sourceMaps:false,interopDefault:false});return{code:c.instance.transform(c.options),...c.snapshot()}});
observe('marker-output-never-stored',()=>{const c=make('marker');c.state.result={error:{owned:'reported transform error'},code:'exports.__JITI_ERROR__ = { owned: true };'};const first=c.instance.transform(c.options),second=c.instance.transform(c.options);return{first,second,...c.snapshot()}});
observe('shebang-prefix-after-cache',()=>{const c=make('shebang');c.state.code='#!/usr/bin/env node\nmodule.exports=42;';const first=c.instance.transform(c.options),afterFirst=c.snapshot(),second=c.instance.transform(c.options);return{first,afterFirst,second,...c.snapshot()}});
observe('raw-code-identity',()=>{const c=make('raw-code',{fsCache:false});const code={startsWith(prefix){c.trace.push({event:'startsWith',sameThis:this===code,prefix});return false}};c.state.result={code};return{same:c.instance.transform(c.options)===code,...c.snapshot()}});
observe('raw-transform-hook-throw',()=>{const c=make('hook-throw',{fsCache:false});c.state.throw=rawReason;return c.instance.transform(c.options)});
observe('raw-code-getter-throw',()=>{const c=make('code-getter',{fsCache:false});c.state.result={get code(){throw rawReason}};return c.instance.transform(c.options)});
observe('raw-startsWith-getter-throw',()=>{const c=make('startsWith-getter',{fsCache:false});c.state.result={code:{get startsWith(){throw rawReason}}};return c.instance.transform(c.options)});
observe('callee-before-option-spreads',()=>{const c=make('callee',{fsCache:false});const fn=c.instance.options.transform;Object.defineProperty(c.instance.options,'transform',{configurable:true,get(){c.trace.push('get transform');return fn}});Object.defineProperty(c.instance.options,'transformOptions',{configurable:true,get(){c.trace.push('get transformOptions');return{get custom(){c.trace.push('get custom');return 1},babel:{owned:true}}}});return{code:c.instance.transform(c.options),...c.snapshot()}});
observe('error-debug-double-read-before-code',()=>{const c=make('debug-error',{fsCache:false});c.instance.options.debug=true;let count=0;c.state.result={get error(){c.trace.push('get error');return{owned:++count}},get code(){c.trace.push('get code');return c.state.code}};const owner=console,descriptor=Object.getOwnPropertyDescriptor(owner,'log'),logs=[];try{Object.defineProperty(owner,'log',{configurable:true,writable:true,value:function(...args){logs.push({sameThis:this===owner,args})}});const code=c.instance.transform(c.options);return{code,logs,...c.snapshot()}}finally{Object.defineProperty(owner,'log',descriptor)}});
observe('debug-throw-precedes-code-getter',()=>{const c=make('debug-throw',{fsCache:false});c.instance.options.debug=true;c.state.result={error:{owned:true},get code(){c.trace.push('get code');return c.state.code}};const owner=console,descriptor=Object.getOwnPropertyDescriptor(owner,'log');try{Object.defineProperty(owner,'log',{configurable:true,writable:true,value(){throw rawReason}});return c.instance.transform(c.options)}finally{Object.defineProperty(owner,'log',descriptor)}});
observe('prepare-real-mkdir-failure-disables-cache',()=>{const p=fixture('mkdir-error');const notDirectory=join(p.directory,'not-directory');fs.writeFileSync(notDirectory,'owned regular file');const c=make('mkdir-consumer',{fsCache:notDirectory});return{code:c.instance.transform(c.options),...c.snapshot()}});
observe('real-write-failure-remains-throw',()=>{const c=make('write-error',{fsCache:false});const notDirectory=join(c.paths.directory,'not-directory');fs.writeFileSync(notDirectory,'owned regular file');c.instance.options.fsCache=notDirectory;return c.instance.transform(c.options)});
observe('default-nearby-node-modules-directory',()=>{const p=fixture('nearby');fs.mkdirSync(join(p.directory,'node_modules'));const instance=createJiti(p.entry,{tsconfigPaths:false,fsCache:true,transform(){return{code:'module.exports=42;'}}},parent);return{fsCache:instance.options.fsCache,exists:fs.existsSync(instance.options.fsCache)}});
observe('default-owned-temp-directory',()=>{const p=fixture('temp');const before=originalProcess.env.TMPDIR;const instance=createJiti(p.entry,{tsconfigPaths:false,fsCache:true,transform(){return{code:'module.exports=42;'}}},parent);return{fsCache:instance.options.fsCache,tmpdirRestored:originalProcess.env.TMPDIR===before,withinOwned:within(instance.options.fsCache)}});
observe('respect-tmpdir-environment',()=>{const p=fixture('respect');const descriptor=Object.getOwnPropertyDescriptor(originalProcess.env,'JITI_RESPECT_TMPDIR_ENV');try{originalProcess.env.JITI_RESPECT_TMPDIR_ENV='owned';const before=originalProcess.env.TMPDIR;const instance=createJiti(p.entry,{tsconfigPaths:false,fsCache:true,transform(){return{code:'module.exports=42;'}}},parent);return{fsCache:instance.options.fsCache,tmpdirUnchanged:originalProcess.env.TMPDIR===before,withinOwned:within(instance.options.fsCache)}}finally{if(descriptor)Object.defineProperty(originalProcess.env,'JITI_RESPECT_TMPDIR_ENV',descriptor);else delete originalProcess.env.JITI_RESPECT_TMPDIR_ENV}});
originalProcess.stdout.write(JSON.stringify({authority:'actual-jiti2.7-public-custom-transform-user-option',rows})+'\n');
