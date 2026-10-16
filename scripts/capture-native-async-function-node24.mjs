import {readFileSync,writeFileSync} from 'node:fs';
import {isAsyncFunction} from 'node:util/types';
import vm from 'node:vm';
if(process.version!=='v24.14.0'||typeof globalThis.gc!=='function')throw Error('Pinned Node24 with exposed GC required');
if(!process.argv[2]||!process.argv[3])throw Error('Output and exact shared caller input required');
globalThis.asyncFixtureLexical={tag:'lexical'};
globalThis.asyncFixtures={
 echo:async function echo(value,trace){trace?.push('body');return value},
 thrower:async function thrower(value){throw value},
 reflect:async function reflect(...args){return{thisValue:this,args}},
 arrow:(function(){return async(value)=>({thisValue:this,value})}).call(asyncFixtureLexical),
 awaiter:async function awaiter(value,trace){trace?.push('start');const result=await value;trace?.push('resumed');return result},
 catcher:async function catcher(value,trace){trace?.push('start');try{const result=await value;trace?.push('resumed');return result}catch(error){trace?.push('caught');return{caught:error}}},
 stateful:async function stateful(value){const state={tag:'private-local'};await value;return state},
};
Object.defineProperty(asyncFixtures.arrow,'name',{value:'arrow',configurable:true});
globalThis.isAsyncFunction=isAsyncFunction;
globalThis.runGC=()=>globalThis.gc();
const other=vm.runInNewContext('({fn:async function otherAsync(){return globalThis.realmMarker},prototype:Promise.prototype})',{realmMarker:42});
globalThis.otherAsync=other.fn;globalThis.otherPromisePrototype=other.prototype;
const input=readFileSync(process.argv[3],'utf8');
await(new Function('return(async()=>{'+input+'\n})()'))();
if(asyncBodyRows.length!==42||new Set(asyncBodyRows.map(row=>row.name)).size!==42)throw Error('Exactly42 distinct complete Source observations required');
if(asyncBodyRows.some(row=>'error'in row))throw Error('Unexpected Source caller failure: '+JSON.stringify(asyncBodyRows.filter(row=>'error'in row)));
writeFileSync(process.argv[2],JSON.stringify({runtime:process.version,source:'actual Node24 syntax and intrinsic util/types/Promise/vm; no native proposal substituted',count:asyncBodyRows.length,rows:asyncBodyRows},null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({runtime:process.version,count:asyncBodyRows.length}));
