import { createRequire } from 'node:module';
import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
const require=createRequire(import.meta.url);
const installed='C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/node_modules/highlight.js/lib/';
globalThis.highlightCoreAPI=require(installed+'core.js');
// Independent baseline, exactly matching native createEager followed by XML.
const baseline=['python','java','go','javascript','json','cpp','typescript','php','ruby','c','csharp','nix','bash','rust','scala','kotlin','swift','dart','groovy','perl','lua','xml'];
for(const name of baseline)highlightCoreAPI.registerLanguage(name,require(installed+'languages/'+name+'.js'));
const names=['livecodeserver','livescript','lsl','mathematica','maxima','mel','nsis','pgsql','reasonml','scss','sqf','sql_more','stan','stata','stylus','vbnet','verilog','vim','x86asm','xquery'];
globalThis.highlightLazyFactories=Object.fromEntries(names.map(name=>[name,require(installed+'languages/'+name+'.js')]));
await import('data:text/javascript;charset=utf-8,'+encodeURIComponent(readFileSync(process.argv[3],'utf8')));
if(!Array.isArray(globalThis.sdkHighlightLazyBatch10Rows)||sdkHighlightLazyBatch10Rows.length!==113)throw Error('Genuine Source113 batch10 rows absent');
writeFileSync(process.argv[2],JSON.stringify({source:'highlight.js@10.7.3 actual installed modules',input:pathToFileURL(process.argv[3]).href,cases:113,rows:sdkHighlightLazyBatch10Rows},null,2)+'\n');
