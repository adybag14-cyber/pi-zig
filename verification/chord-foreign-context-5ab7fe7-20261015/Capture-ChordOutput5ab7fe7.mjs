import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
const sourceRoot=process.argv[2],callerPath=process.argv[3];
if(!sourceRoot||!callerPath)throw Error('Source root and unchanged caller are required');
const outputUrl=pathToFileURL(path.join(sourceRoot,'packages/chord/src/output.ts')).href;
const originalBuffer=globalThis.Buffer;
let apiFallback,apiBuffer;
try{
 globalThis.Buffer=undefined;
 apiFallback=await import(outputUrl+'?chord-output-buffer-absent');
 globalThis.Buffer=originalBuffer;
 apiBuffer=await import(outputUrl+'?chord-output-buffer-present');
}finally{globalThis.Buffer=originalBuffer}
const caller=fs.readFileSync(callerPath,'utf8');
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
await new AsyncFunction('apiFallback','apiBuffer',caller)(apiFallback,apiBuffer);
if(!Array.isArray(globalThis.chordOutputCases)||globalThis.chordOutputCases.length!==14)throw Error('Output14 caller inventory changed');
process.stdout.write(JSON.stringify({source_scope:'actual chord/output module with independently captured optional Buffer branches',cases:globalThis.chordOutputCases})+'\n');
