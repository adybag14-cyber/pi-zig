import { RelayHold,RelayCall } from 'file:///C:/Users/adyba/pi-sdk-loadout-source-e6220e1-20261013/packages/chord/src/connection.ts';
import { ChordError } from 'file:///C:/Users/adyba/pi-sdk-loadout-source-e6220e1-20261013/packages/chord/src/errors.ts';
import {readFileSync,writeFileSync} from 'node:fs';
const input=readFileSync('C:/Users/adyba/pi-zig-update-evidence-20261003/chord-relay-original-e622.input.txt','utf8');
await new Function('api','return(async()=>{'+input+'})()')({RelayHold,RelayCall,ChordError});
const cases=globalThis.chordRelayCases;
writeFileSync('C:/Users/adyba/pi-zig-update-evidence-20261003/chord-relay-original-e622-20261013.json',JSON.stringify({source:'e6220e1316f86af818a0ccbfe1c09d7e918b41cf',cases},null,2)+'\n');
console.log(JSON.stringify({cases:cases.length,negative:cases.filter(row=>Object.hasOwn(row,'error')||JSON.stringify(row).includes('"error":')).length}));
