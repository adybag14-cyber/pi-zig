import * as api from 'file:///C:/Users/adyba/pi-sdk-loadout-source-e6220e1-20261013/packages/chord/src/delta/index.ts';
import {readFileSync,writeFileSync} from 'node:fs';
const input=readFileSync('C:/Users/adyba/pi-zig-chord-full-composition-e6220e1-20261013/src/extensions/fixtures/chord-apply-original-e622.input.txt','utf8');
await new Function('api','return(async()=>{'+input+'})()')(api);
const cases=globalThis.chordApplyCases;
writeFileSync('C:/Users/adyba/pi-zig-update-evidence-20261003/chord-apply-original-e622-20261013.json',JSON.stringify({source:'e6220e1316f86af818a0ccbfe1c09d7e918b41cf',cases},null,2)+'\n');
console.log(JSON.stringify({cases:cases.length,negative:cases.filter(row=>JSON.stringify(row).includes('"error":')).length}));
