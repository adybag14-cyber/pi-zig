import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {join} from 'node:path';
const [sourceRoot,,,closurePath,inputPath,goldenPath,outputPath]=process.argv.slice(2);
readFileSync(0); // Retained owner handle and live argv snapshot precede observation.
if(process.version!=='v24.14.0'||process.platform!=='linux')throw Error('Actual Linux Node24.14 required');
process.env.PI_PACKAGE_DIR=join(sourceRoot,'packages/coding-agent');
const {AgentSession}=await import(pathToFileURL(join(sourceRoot,'packages/coding-agent/src/core/agent-session.ts')).href);
const p=AgentSession.prototype;
globalThis.customAPI={send:p.sendCustomMessage,append:p._appendCustomMessage,flush:p._flushPendingCustomMessages};
const input=readFileSync(inputPath),golden=JSON.parse(readFileSync(goldenPath));
await import('data:text/javascript;base64,'+input.toString('base64'));
const descriptors=['sendCustomMessage','_appendCustomMessage','_flushPendingCustomMessages'].map(name=>{const d=Object.getOwnPropertyDescriptor(p,name),f=d.value;return{name,length:f.length,enumerable:d.enumerable,configurable:d.configurable,writable:d.writable,ownPrototype:Object.hasOwn(f,'prototype'),async:Object.getPrototypeOf(f)===Object.getPrototypeOf(async()=>{})};});
const stringify=JSON.stringify,hash=x=>createHash('sha256').update(x).digest('hex'),rows=globalThis.customMessageRows;
if(rows.length!==40||golden.sourceHead!=='5ab7fe74c400097b386662205cd93900695b8a71'||stringify(rows)!==stringify(golden.rows)||stringify(descriptors)!==stringify(golden.descriptors)||hash(input)!==golden.inputSha256)throw Error('Genuine Linux Source40/descriptors differ from original Windows fixture');
const raw=stringify({descriptors,rows});writeFileSync(outputPath+'.rows.bin',raw);
writeFileSync(outputPath,stringify({sourceHead:golden.sourceHead,actualNode:{version:process.version,executable:process.execPath,pid:process.pid,platform:process.platform,arch:process.arch},inputSha256:hash(input),cases:40,matchedOriginal:true,rawSha256:hash(raw),closurePath,descriptors,rows},null,2));
