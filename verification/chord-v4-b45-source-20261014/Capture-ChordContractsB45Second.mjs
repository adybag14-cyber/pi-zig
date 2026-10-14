// Oracle caller only: actual immutable b45 exports and internal placement factories.
import * as chord from 'file:///C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/packages/chord/src/index.ts';
import {contractFromDescription,resolveHost,placedOn,placementText} from 'file:///C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/packages/chord/src/contract.ts';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
const sourceRequire=createRequire('file:///C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/packages/chord/src/contract.ts');
const {Type}=await import(pathToFileURL(sourceRequire.resolve('typebox')).href);
import {readFileSync,writeFileSync} from 'node:fs';
const [inputPath,outputPath,globalName]=process.argv.slice(2);
await new Function('api','return (async()=>{'+readFileSync(inputPath,'utf8')+'})()')({...chord,Type,contractFromDescription,resolveHost,placedOn,placementText});
const cases=globalThis[globalName];
if(!Array.isArray(cases)||cases.length!==28)throw Error('Actual b45 contract case count');
writeFileSync(outputPath,JSON.stringify({source:'b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb',cases},null,2)+'\n');
console.log(JSON.stringify({cases:cases.length,output:outputPath,runtime:process.versions}));