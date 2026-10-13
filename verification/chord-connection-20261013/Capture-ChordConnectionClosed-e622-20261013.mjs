import { Connection } from 'file:///C:/Users/adyba/pi-sdk-loadout-source-e6220e1-20261013/packages/chord/src/connection.ts';
import { memoryLinkPair } from 'file:///C:/Users/adyba/pi-sdk-loadout-source-e6220e1-20261013/packages/chord/src/link.ts';
import {readFileSync,writeFileSync} from 'node:fs';
const input=readFileSync('C:/Users/adyba/pi-zig-update-evidence-20261003/chord-connection-closed-original-e622.input.txt','utf8');
await new Function('api','return(async()=>{'+input+'})()')({Connection,memoryLinkPair});
const cases=globalThis.chordConnectionClosedCases;
writeFileSync('C:/Users/adyba/pi-zig-update-evidence-20261003/chord-connection-closed-original-e622-20261013.json',JSON.stringify({source:'e6220e1316f86af818a0ccbfe1c09d7e918b41cf',cases},null,2)+'\n');
console.log(JSON.stringify({cases:cases.length,allClosed:cases.every(row=>row.beforeClosed&&!row.open&&row.timers===0)}));
