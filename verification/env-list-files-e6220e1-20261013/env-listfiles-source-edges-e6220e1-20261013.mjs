import fs from 'node:fs/promises';
import path from 'node:path';
import {Connection} from '../pi-upstream-env-oracle-e6220e1-20261013/packages/env/src/connection.ts';
const evidence=path.dirname(import.meta.filename),root=path.join(evidence,'env-listfiles-source-edges-tree-e6220e1-20261013');
await fs.mkdir(path.join(root,'links/dir'),{recursive:true});await fs.writeFile(path.join(root,'links/dir/inner.txt'),'');
await fs.symlink(path.join(root,'links/dir'),path.join(root,'links/link'),'junction').catch(e=>{if(e.code!=='EEXIST')throw e;});
await fs.symlink(path.join(root,'links'),path.join(root,'links/dir/loop'),'junction').catch(e=>{if(e.code!=='EEXIST')throw e;});
let fileLink=true;try{await fs.symlink('missing',path.join(root,'links/dangling'),'file');}catch(e){if(e.code==='EPERM')fileLink=false;else if(e.code!=='EEXIST')throw e;}
const connection=new Connection({command:[path.join(evidence,'env-listfiles-oracle-target-e6220e1-20261013/debug/pi-env.exe')]});
const cases=[];
try{
 for(const [name,dir,options] of [['links','links',{}],['linked-root','links/link',{}],['names','names',{}],['names-hidden-false','names',{hidden:false}],['unicode-bound','unicode',{maxBytes:3}],['unicode-exact','unicode',{maxBytes:4}]]){
  const result=await connection.request('listFiles',{path:path.join(root,dir),...options});cases.push({name,path:dir,options,json:result.json,payload:Buffer.from(result.payload).toString('base64'),records:Buffer.from(result.payload).toString().split('\0').filter(Boolean)});
 }
 await fs.writeFile(path.join(evidence,'env-listfiles-source-edges-data-e6220e1-20261013.json'),JSON.stringify({fileLink,cases},null,2)+'\n');console.log(JSON.stringify({fileLink,cases}));
}finally{connection.close();}
