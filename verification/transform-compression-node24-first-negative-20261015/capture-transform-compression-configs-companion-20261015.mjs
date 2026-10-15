// External reference control only. The sealed b2b2 caller/input are unchanged.
import { writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
const natives=process.binding('natives');
const keys=Object.keys(natives);
const observed={pid:process.pid,nodeVersion:process.version,totalEntries:keys.length,sourceBodies:keys.filter(name=>typeof natives[name]==='string').length,configs:{own:Object.hasOwn(natives,'configs'),type:typeof natives.configs,undefined:natives.configs===undefined}};
writeFileSync(process.argv[2]+'.configs.json',JSON.stringify(observed,null,2)+'\n');
if(observed.totalEntries!==369||observed.sourceBodies!==368||!observed.configs.own||!observed.configs.undefined||observed.configs.type!=='undefined')throw Error('Actual Node369/368/configs authority inventory changed');
await import(pathToFileURL('C:/Users/adyba/pi-zig-native-transform-compression-20261015/tools/capture-web-transform-compression-node24.mjs').href);
