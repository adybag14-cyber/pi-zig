import {createHash} from 'node:crypto';
import {writeFileSync} from 'node:fs';
const natives=process.binding('natives');
const keys=Object.keys(natives),strings=keys.filter(name=>typeof natives[name]==='string');
const actualBodiesSha256=createHash('sha256').update(JSON.stringify(natives)).digest('hex');
const observation={pid:process.pid,nodeVersion:process.version,keys:keys.length,stringBodies:strings.length,configsOwn:Object.hasOwn(natives,'configs'),configsUndefined:natives.configs===undefined,undefinedKeys:keys.filter(name=>natives[name]===undefined),actualBodiesSha256};
if(observation.keys!==369||observation.stringBodies!==368||!observation.configsOwn||!observation.configsUndefined||actualBodiesSha256!=='0cd86676bb2a46a4e772d1fd8bb3d00fca658383bc388846dcc796547dc79263')throw Error('Actual original Node24 builtin authority changed');
writeFileSync(process.env.WRITABLE_BUILTIN_OBSERVATION,JSON.stringify(observation,null,2)+'\n');
