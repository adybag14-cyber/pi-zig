import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {Connection,nodePlatform} from '../pi-upstream-env-oracle-e6220e1-20261013/packages/env/src/connection.ts';
import {LocalExecutionEnv,listFilesOver} from '../pi-upstream-env-oracle-e6220e1-20261013/packages/env/src/list-files.ts';
import {RemoteExecutionEnv} from '../pi-upstream-env-oracle-e6220e1-20261013/packages/env/src/remote-env.ts';
const evidence=path.dirname(import.meta.filename);
const root=path.join(evidence,'env-listfiles-oracle-tree-e6220e1-20261013');
const binary=path.join(evidence,'env-listfiles-oracle-target-e6220e1-20261013/debug/pi-env.exe');
const connection=new Connection({command:[binary]});
const oldConnection=new Connection({command:[process.execPath,path.join(evidence,'../pi-upstream-env-oracle-e6220e1-20261013/packages/env/test/old-daemon.ts')]});
const context={};
const results={};
try {
 const remote=new RemoteExecutionEnv({connection,id:'source-oracle',cwd:path.join(root,'bounds')});
 const local=new LocalExecutionEnv({connection,cwd:path.join(root,'bounds')});
 const listed=await remote.listFiles('.',{maxEntries:2},context);
 assert.deepEqual(listed,{ok:true,value:{entries:[{path:'a',kind:'file'},{path:'b',kind:'file'}],truncated:true}});
 assert.deepEqual(await local.listFiles('.',{maxEntries:2},context),listed);
 results.localRemote=listed;
 results.invalid=[];
 for(const options of [{maxEntries:-1},{maxBytes:1.5},{timeoutMs:NaN},{maxEntries:Number.MAX_SAFE_INTEGER+1}]){
  const result=await remote.listFiles('.',options,context);assert(!result.ok);assert.equal(result.error.code,'invalid');results.invalid.push({code:result.error.code,message:result.error.message});
 }
 const controller=new AbortController();controller.abort();
 const aborted=await remote.listFiles('.',undefined,{abortSignal:controller.signal});assert.equal(aborted.error.code,'aborted');results.preAbort=aborted.error.code;
 const old=new RemoteExecutionEnv({connection:oldConnection,id:'old',cwd:'/'});
 const unsupported=await old.listFiles('.',undefined,context);assert.equal(unsupported.error.code,'not_supported');results.oldDaemon={code:unsupported.error.code,message:unsupported.error.message};
 results.platforms=[];
 for(const input of [{os:'windows',arch:'aarch64'},{os:'macos',arch:'x86_64'},{os:'linux',arch:'x86'},{os:'android',arch:'riscv64'}])results.platforms.push({input,output:nodePlatform(input)});
 const helloOnly={info:async()=>({features:[]}),request:async()=>{throw Error('old daemon must never receive listFiles');}};
 assert.equal((await listFilesOver(helloOnly,'/',undefined,context)).error.code,'not_supported');results.noUnsupportedRequest=true;
 const invalidBeforeAbort=await listFilesOver(helloOnly,'/',{maxEntries:-1},{abortSignal:controller.signal});assert.equal(invalidBeforeAbort.error.code,'invalid');results.invalidBeforeAbort=true;
 await fs.writeFile(path.join(evidence,'env-listfiles-source-client-e6220e1-20261013.json'),JSON.stringify(results,null,2)+'\n');
 console.log(JSON.stringify({terminal:'passed',invalid:results.invalid.length,nodePlatform:results.platforms.length,oldDaemon:results.oldDaemon.code,localRemote:true}));
}finally{connection.close();oldConnection.close();}
