// Oracle-only caller of the immutable latest actual factories and exports.
import * as chord from 'file:///C:/Users/adyba/pi-upstream-source-1692bba-20261014/packages/chord/src/index.ts';
import {ResourceImpl} from 'file:///C:/Users/adyba/pi-upstream-source-1692bba-20261014/packages/chord/src/object.ts';
import {readFileSync,writeFileSync} from 'node:fs';
const [inputPath,outputPath,globalName]=process.argv.slice(2);
await new Function('api','return (async()=>{'+readFileSync(inputPath,'utf8')+'})()')({...chord,ResourceImpl});
const cases=globalThis[globalName];
if(!Array.isArray(cases)||cases.length===0)throw Error('Original factory produced no cases');
writeFileSync(outputPath,JSON.stringify({source:'1692bba6347a287ab0f3cb554a4430fafffc474b',cases},null,2)+'\n');
console.log(JSON.stringify({cases:cases.length,output:outputPath,runtime:process.versions}));
