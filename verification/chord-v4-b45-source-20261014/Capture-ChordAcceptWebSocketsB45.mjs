// Caller-only oracle: actual immutable b45 public exports, no Source body replacement.
import * as chord from 'file:///C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/packages/chord/src/index.ts';
import {readFileSync,writeFileSync} from 'node:fs';
const [inputPath,outputPath,globalName]=process.argv.slice(2);
await new Function('api','return (async()=>{'+readFileSync(inputPath,'utf8')+'})()')(chord);
const cases=globalThis[globalName];
if(!Array.isArray(cases)||cases.length!==13)throw Error('Actual b45 acceptWebSockets case count');
writeFileSync(outputPath,JSON.stringify({source:'b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb',cases},null,2)+'\n');
console.log(JSON.stringify({cases:cases.length,output:outputPath,runtime:process.versions}));