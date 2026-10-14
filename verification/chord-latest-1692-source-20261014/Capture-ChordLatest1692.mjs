// Oracle-only caller. Every API below is the unmodified pinned original Source export.
import {createHost,defineFacet} from 'file:///C:/Users/adyba/pi-upstream-source-1692bba-20261014/packages/chord/src/host.ts';
import {Cell} from 'file:///C:/Users/adyba/pi-upstream-source-1692bba-20261014/packages/chord/src/cell.ts';
import {remote,local,method,opaque} from 'file:///C:/Users/adyba/pi-upstream-source-1692bba-20261014/packages/chord/src/contract.ts';
import {memoryLinkPair,webSocketLink,ipcLink,Packed,unpack,inflateMessage} from 'file:///C:/Users/adyba/pi-upstream-source-1692bba-20261014/packages/chord/src/link.ts';
import {isFrame} from 'file:///C:/Users/adyba/pi-upstream-source-1692bba-20261014/packages/chord/src/wire.ts';
import {defineRegistry} from 'file:///C:/Users/adyba/pi-upstream-source-1692bba-20261014/packages/chord/src/registry.ts';
import {readFileSync,writeFileSync} from 'node:fs';
const [inputPath,outputPath,globalName]=process.argv.slice(2);
const input=readFileSync(inputPath,'utf8');
await new Function('api','return (async()=>{'+input+'})()')({createHost,defineFacet,Cell,remote,local,method,opaque,memoryLinkPair,webSocketLink,ipcLink,Packed,unpack,inflateMessage,isFrame,defineRegistry});
const cases=globalThis[globalName];
if(!Array.isArray(cases)||cases.length===0)throw Error('Oracle did not return actual cases');
writeFileSync(outputPath,JSON.stringify({source:'1692bba6347a287ab0f3cb554a4430fafffc474b',cases},null,2)+'\n');
console.log(JSON.stringify({cases:cases.length,output:outputPath,runtime:process.versions}));
