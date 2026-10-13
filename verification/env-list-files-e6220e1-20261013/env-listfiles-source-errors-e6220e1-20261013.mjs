import fs from 'node:fs/promises';
import path from 'node:path';
import {Connection} from '../pi-upstream-env-oracle-e6220e1-20261013/packages/env/src/connection.ts';
const evidence=path.dirname(import.meta.filename),root=path.join(evidence,'env-listfiles-oracle-tree-e6220e1-20261013/bounds');
const client=new Connection({command:[path.join(evidence,'env-listfiles-oracle-target-e6220e1-20261013/debug/pi-env.exe')]});
const cases=[];
try{for(const [name,input] of [['empty',{path:''}],['wildcard',{path:path.join(root,'?')}],['nul',{path:root+'\0'}],['path-null',{path:null}],['null-options',{path:root,maxEntries:null,maxBytes:null,timeoutMs:null,exclude:null}],['wrong-bools',{path:root,hidden:7,gitignore:'false'}]]){try{const reply=await client.request('listFiles',input);cases.push({name,input,kind:2,json:reply.json,payload:Buffer.from(reply.payload).toString('base64')});}catch(error){cases.push({name,input,kind:3,code:error.code});}}await fs.writeFile(path.join(evidence,'env-listfiles-source-errors-data-e6220e1-20261013.json'),JSON.stringify(cases,null,2)+'\n');console.log(JSON.stringify(cases));}finally{client.close();}
