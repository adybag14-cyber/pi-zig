// Genuine Node reference only. Never installed as a native product worker.
import * as web from 'node:stream/web';
import fs from 'node:fs/promises';
import crypto from 'node:crypto';
const [caseName,inputPath,outputPath,proofPath]=process.argv.slice(2);
const cases=['namespace-metadata','queue-basic','queue-conversion','queue-errors','queue-brand','queue-size-getters','encoder-carry','encoder-empty-eof','encoder-conversion','encoder-error','decoder-utf8-bom','decoder-utf16','decoder-options','decoder-fatal','decoder-undefined','decoder-gc'];
if(process.versions.node!=='24.14.0'||typeof globalThis.gc!=='function'||!cases.includes(caseName)||!process.env.PI_SOURCE_ORACLE_CONTROL_MANIFEST)throw Error('Actual Node stream/control mismatch');
const digest=bytes=>crypto.createHash('sha256').update(bytes).digest('hex').toUpperCase();
const input=await fs.readFile(inputPath),inputHash=digest(input);
const packet=await new Function('web','caseName','nativeCollect','return(async()=>{'+input.toString('utf8')+';return packet})()')(web,caseName,globalThis.gc);
globalThis.gc();
if(digest(await fs.readFile(inputPath))!==inputHash)throw Error('Stream observer input drift');
await fs.writeFile(outputPath,JSON.stringify(packet,null,2)+'\n');
const proof={case:caseName,node:process.versions.node,platform:process.platform,input_sha256:inputHash,output_sha256:digest(await fs.readFile(outputPath)),actualBundledNodeStream:true,real_gc:true,source_head:'4954d760504c11df9b2cbdc040346107b6a8153d',native_qualified:false,public_activation:false};
await fs.writeFile(proofPath,JSON.stringify(proof,null,2)+'\n');console.log(JSON.stringify({status:'captured',...proof}));
