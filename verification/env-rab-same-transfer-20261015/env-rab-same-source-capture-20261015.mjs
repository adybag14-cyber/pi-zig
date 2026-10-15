// Reference-only genuine Node FileHandle capture; not an application runtime.
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
const [bodyPath,outputPath,proofPath]=process.argv.slice(2);
if(process.versions.node!=='24.14.0'||process.env.UV_THREADPOOL_SIZE!=='1'||typeof globalThis.gc!=='function')throw Error('Pinned Node reference/control mismatch');
const digest=bytes=>crypto.createHash('sha256').update(bytes).digest('hex').toUpperCase();
const body=await fs.readFile(bodyPath),bodyHash=digest(body);
const directory=await fs.mkdtemp(path.join(os.tmpdir(),'pi-env-rab-same-reference-'));
const filename=path.join(directory,'file');await fs.writeFile(filename,new Uint8Array([0,1,2,3,4,5,6,7,8,9]));
const file=await fs.open(filename,'r+');let blockers=0;
const queueBlocker=()=>{blockers++;return new Promise((resolve,reject)=>crypto.pbkdf2('owned-rab-same','reference-only',1000000,16,'sha256',(error,value)=>error?reject(error):resolve(value)))};
const releaseBlocker=blocker=>blocker;
let packet;
try{packet=await new Function('file','queueBlocker','releaseBlocker','nativeCollect','return(async()=>{'+body.toString('utf8')+';return packet})()')(file,queueBlocker,releaseBlocker,globalThis.gc)}finally{if(file.fd!==-1)await file.close()}
if(digest(await fs.readFile(bodyPath))!==bodyHash)throw Error('Source body drift');
await fs.writeFile(outputPath,JSON.stringify(packet,null,2)+'\n');
const proof={node:process.versions.node,platform:process.platform,fields:Object.keys(packet),input_sha256:bodyHash,output_sha256:digest(await fs.readFile(outputPath)),pool_size:process.env.UV_THREADPOOL_SIZE,blockers,iterations_per_blocker:1000000,real_gc:true,native_qualified:false,public_activation:false};
await fs.writeFile(proofPath,JSON.stringify(proof,null,2)+'\n');
console.log(JSON.stringify({status:'captured',...proof}));
