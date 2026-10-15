import { createRequire } from 'node:module';
import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
const require=createRequire(import.meta.url);
const installed='C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/node_modules/highlight.js/lib/';
globalThis.highlightCoreAPI=require(installed+'core.js');
for(const name of ['python','java','go','javascript','json','cpp','typescript','php','ruby','c','csharp','nix','bash','rust','scala','kotlin','swift','dart','groovy','perl','lua'])highlightCoreAPI.registerLanguage(name,require(installed+'languages/'+name+'.js'));
await import('data:text/javascript;charset=utf-8,'+encodeURIComponent(readFileSync(process.argv[3],'utf8')));
highlightLazyBatch2Hooks.beforeLoad();
try{globalThis.highlightLazyFactories=Object.fromEntries(['xml','css','markdown','powershell','sql','yaml'].map(name=>[name,require(installed+'languages/'+name+'.js')]))}finally{highlightLazyBatch2Hooks.afterLoad()}
highlightLazyBatch2Hooks.run();
if(!Array.isArray(globalThis.sdkHighlightLazyBatch2Rows)||sdkHighlightLazyBatch2Rows.length!==45)throw Error('Genuine Source45 rows absent');
writeFileSync(process.argv[2],JSON.stringify({source:'highlight.js@10.7.3 actual installed modules',input:pathToFileURL(process.argv[3]).href,cases:45,rows:sdkHighlightLazyBatch2Rows},null,2)+'\n');
