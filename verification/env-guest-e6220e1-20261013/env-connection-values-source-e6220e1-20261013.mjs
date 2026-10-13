import fs from 'node:fs/promises';
import{Connection,isConnectionLost}from'../pi-upstream-env-oracle-e6220e1-20261013/packages/env/src/connection.ts';
const packet={};
const describe=object=>Object.fromEntries(Object.getOwnPropertyNames(object).filter(key=>key!=='constructor').map(key=>{const d=Object.getOwnPropertyDescriptor(object,key);return[key,{enumerable:d.enumerable,writable:d.writable,configurable:d.configurable,length:d.value.length,async:Object.getPrototypeOf(d.value)===Object.getPrototypeOf(async()=>{})}]}));
packet.shape={length:Connection.length,name:Connection.name,methods:describe(Connection.prototype),keys:Object.keys(new Connection({command:[]}))};
const inspect=error=>({name:error.name,message:error.message,code:error.code,lost:isConnectionLost(error),keys:Object.keys(error),fields:error.fields});
async function failure(action){try{await action();return{unexpected:true}}catch(error){return inspect(error)}}
let reads=0;const getter=new Connection({get command(){reads++;throw new Error('command getter')}});const first=getter.info(),second=getter.session();const failures=await Promise.all([first.catch(e=>e),second.catch(e=>e)]);packet.getter={reads,errors:failures.map(inspect),same:failures[0]===failures[1]};packet.retry=await failure(()=>getter.info());packet.retryReads=reads;getter.close();
let calls=0,thisUndefined=false;const call=new Connection({command:async function(){calls++;thisUndefined=this===undefined;throw'plain reason'}});packet.call=await failure(()=>call.info());packet.callContext={calls,thisUndefined};call.close();
const empty=new Connection({command:[]});packet.empty=await failure(()=>empty.info());empty.close();
let closedCalls=0;const closed=new Connection({command:async()=>{closedCalls++;return[]}});closed.close();packet.closed={info:await failure(()=>closed.info()),session:await failure(()=>closed.session()),request:await failure(()=>closed.request('ignored',{})),stale:await failure(()=>closed.request('ignored',{},{session:1})),closedCalls};
let release;const waitCommand=new Connection({command:()=>new Promise(resolve=>{release=resolve})});const pending=waitCommand.info();waitCommand.close();release([]);packet.closeDuringCommand=await failure(()=>pending);
const sharedOptions={command:[]};const mutable=new Connection(sharedOptions);sharedOptions.command=async()=>{throw new Error('mutated')};packet.optionsReference=await failure(()=>mutable.info());mutable.close();
await fs.writeFile(new URL('./env-connection-values-source-data-e6220e1-20261013.json',import.meta.url),JSON.stringify(packet,null,2)+'\n');console.log(JSON.stringify({terminal:'passed',cases:Object.keys(packet).length}));
