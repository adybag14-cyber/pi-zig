// Prepared genuine Source options.ts input; no execution grant is implied.
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import readline from 'node:readline';
const [jitiEntry, originalOptions] = process.argv.slice(2);
if(process.version!=='v24.14.0'||!path.isAbsolute(jitiEntry||'')||!path.isAbsolute(originalOptions||''))throw Error('exact Node and sealed absolute primary inputs required');
const fence=readline.createInterface({input:process.stdin,crlfDelay:Infinity});const line=await new Promise(resolve=>fence.once('line',resolve));fence.close();
if(line!=='ADMIT-JITI-OPTIONS-SOURCE-ONLY')throw Error('explicit admission required');
const {createJiti}=await import(pathToFileURL(jitiEntry).href);
const jiti=createJiti(jitiEntry,{fsCache:false,moduleCache:false,tryNative:false,interopDefault:false});
const {resolveJitiOptions:subject}=await jiti.import(originalOptions);
if(typeof subject!=='function'||subject.name!=='resolveJitiOptions')throw Error('actual original Source declaration required');
const rows=[],error=e=>({name:e?.name,message:e?.message});
const environment=Object.getOwnPropertyDescriptor(process,'env'),bun=Object.getOwnPropertyDescriptor(globalThis,'Bun');
async function observe(id,run){try{rows.push({id,value:await run()})}catch(e){rows.push({id,error:error(e)})}}
function withEnv(value,run){Object.defineProperty(process,'env',{configurable:true,writable:true,value});try{return run()}finally{Object.defineProperty(process,'env',environment)}}
try{
  delete globalThis.Bun;
  await observe('ordinary-callable',()=>({name:subject.name,length:subject.length,prototype:Object.hasOwn(subject,'prototype')}));
  await observe('default-values-order',()=>withEnv({},()=>{const v=subject({});return {keys:Object.keys(v),value:v}}));
  await observe('deprecated-overrides',()=>withEnv({},()=>subject({cache:false,requireCache:false})));
  await observe('explicit-overrides-win',()=>withEnv({},()=>subject({cache:false,requireCache:false,fsCache:'explicit',moduleCache:'explicit-module'})));
  await observe('nested-env-fallbacks',()=>withEnv({JITI_CACHE:'false',JITI_FS_CACHE:'true',JITI_REQUIRE_CACHE:'false'},()=>subject({})));
  await observe('raw-tsconfig-json-fallback',()=>withEnv({JITI_TSCONFIG_PATHS:'config-path'},()=>subject({}).tsconfigPaths));
  await observe('parsed-tsconfig-string',()=>withEnv({JITI_TSCONFIG_PATHS:'"config-path"'},()=>subject({}).tsconfigPaths));
  await observe('jsx-keeps-duplicate-tsx',()=>withEnv({JITI_JSX:'true'},()=>subject({}).extensions));
  await observe('env-present-undefined',()=>withEnv({JITI_DEBUG:undefined},()=>subject({}).debug));
  await observe('env-get-before-has-false',()=>{const trace=[];return withEnv(new Proxy({},{get(t,k){trace.push(['get',String(k)]);return 'true'},has(t,k){trace.push(['has',String(k)]);return false}}),()=>({value:subject({}),trace}))});
  await observe('env-get-throw-is-outside-catch',()=>withEnv(new Proxy({},{get(){throw new RangeError('owned env getter')}}),()=>subject({})));
  await observe('malformed-json-defaults',()=>withEnv({JITI_DEBUG:'bad',JITI_EXTENSIONS:'bad',JITI_ALIAS:'bad'},()=>subject({})));
  await observe('jsx-nonarray-fails-before-user-override',()=>withEnv({JITI_JSX:'true',JITI_EXTENSIONS:'null'},()=>subject({jsx:false,extensions:[]})));
  await observe('symbol-spread-identity',()=>withEnv({},()=>{const key=Symbol('user'),identity={},actual=subject({[key]:identity});return {same:actual[key]===identity,symbols:Object.getOwnPropertySymbols(actual).map(String)}}));
  await observe('inherited-deprecated-setter',()=>withEnv({},()=>{const old=Object.getOwnPropertyDescriptor(Object.prototype,'fsCache');let calls=0;Object.defineProperty(Object.prototype,'fsCache',{configurable:true,set(){calls++}});try{const v=subject({cache:false});return {calls,value:v.fsCache,own:Object.hasOwn(v,'fsCache')}}finally{if(old)Object.defineProperty(Object.prototype,'fsCache',old);else delete Object.prototype.fsCache}}));
  await observe('getter-json-catch-boolean-trace',()=>{
    const parse=Object.getOwnPropertyDescriptor(JSON,'parse'),boolean=Object.getOwnPropertyDescriptor(globalThis,'Boolean'),trace=[],marker={get toString(){throw Error('caught reason formatted')}},originalParse=JSON.parse,originalBoolean=Boolean,target={JITI_CACHE:'false',JITI_TSCONFIG_PATHS:'bad'};
    const view=new Proxy(target,{get(t,k,r){trace.push(['get',String(k)]);return Reflect.get(t,k,r)},has(t,k){trace.push(['has',String(k)]);return Reflect.has(t,k)}});
    try{Object.defineProperty(process,'env',{configurable:true,get(){trace.push(['env']);return view}});Object.defineProperty(JSON,'parse',{configurable:true,writable:true,value:function(value){'use strict';trace.push(['parse',this===JSON,value]);if(value==='bad')throw marker;return originalParse(value)}});Object.defineProperty(globalThis,'Boolean',{configurable:true,writable:true,value:function(value){'use strict';trace.push(['Boolean',this===undefined,value]);return originalBoolean(value)}});
      let reads=0;const user={get cache(){trace.push(['cache',++reads]);return false},get requireCache(){trace.push(['requireCache']);return undefined}},actual=subject(user);trace.push(['result',actual.fsCache,actual.tsconfigPaths]);return trace;
    }finally{Object.defineProperty(process,'env',environment);Object.defineProperty(JSON,'parse',parse);Object.defineProperty(globalThis,'Boolean',boolean)}
  });
  await observe('constructible-return-object',()=>withEnv({},()=>{const v=new subject({debug:true});return {debug:v.debug,instance:v instanceof subject}}));
  await observe('null-user-options',()=>withEnv({},()=>subject(null)));
  await observe('undefined-user-options',()=>withEnv({},()=>subject(undefined)));
}finally{Object.defineProperty(process,'env',environment);if(bun)Object.defineProperty(globalThis,'Bun',bun);else delete globalThis.Bun}
process.stdout.write(JSON.stringify({metadata:{node:process.version,execPath:process.execPath,jitiEntry,originalOptions,sourceBytes:fs.statSync(originalOptions).size,fsCache:false,physicalWrites:[]},rows})+'\n');
