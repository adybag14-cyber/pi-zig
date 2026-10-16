// Genuine oracle only. Run solely in a Root-granted, fully frozen Source owner.
import fs from 'node:fs';
import vm from 'node:vm';
import crypto from 'node:crypto';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
const authority='C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/typebox';
const own=new URL('.',import.meta.url);
const output=process.argv[2];
if(!output||fs.existsSync(output))throw Error('A new explicit output path is required');
const closure=JSON.parse(fs.readFileSync(new URL('reachable-closure.json',own),'utf8'));
const packageBytes=fs.readFileSync(path.join(authority,'package.json'));
const packageJSON=JSON.parse(packageBytes);
if(packageJSON.version!=='1.3.27')throw Error('TypeBox version drift');
for(const entry of closure.modules){const bytes=fs.readFileSync(path.join(authority,'build',entry.file));if(crypto.createHash('sha256').update(bytes).digest('hex')!==entry.sha256)throw Error('TypeBox authority drift: '+entry.file)}
const Type=await import(pathToFileURL(path.join(authority,'build/type/index.mjs')));
const {Memory}=await import(pathToFileURL(path.join(authority,'build/system/memory/index.mjs')));
const {Settings}=await import(pathToFileURL(path.join(authority,'build/system/settings/index.mjs')));
globalThis.TypeBoxOperatorGraph={Type,Memory,Settings};
const fixture=new URL('../../src/extensions/fixtures/typebox-operators-production.input.txt',own);
const input=fs.readFileSync(fixture,'utf8');
vm.runInThisContext(input,{filename:'typebox-operators-production-probes.mjs',timeout:120000});
const result={authority,package:'typebox',version:packageJSON.version,
  packageSha256:crypto.createHash('sha256').update(packageBytes).digest('hex'),
  inputSha256:crypto.createHash('sha256').update(input).digest('hex'),
  closureSha256:crypto.createHash('sha256').update(fs.readFileSync(new URL('reachable-closure.json',own))).digest('hex'),
  cases:globalThis.TypeBoxOperatorRows.length,actualNodeGC:typeof globalThis.gc==='function',
  node:{path:process.execPath,version:process.version,argv:process.execArgv},
  rows:globalThis.TypeBoxOperatorRows};
fs.writeFileSync(output,JSON.stringify(result,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({status:'genuine_source_capture_complete',version:result.version,cases:result.cases,inputSha256:result.inputSha256,output}));
