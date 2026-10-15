import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
const [sourceRoot,callerPath,guestPath,outputPath,observerPath]=process.argv.slice(2);
if(!sourceRoot||!callerPath||!guestPath||!outputPath)throw Error('Actual Source root caller guest and output paths are required');
const originalNodeOptions=process.env.NODE_OPTIONS;
try{
 // Original forkDriver deliberately clears execArgv. The bounded oracle's
 // transparent observer is inherited as Node startup configuration instead;
 // every actual child module must satisfy the same pinned Source closure.
 if(observerPath)process.env.NODE_OPTIONS=[originalNodeOptions??'','--import '+pathToFileURL(observerPath).href].filter(Boolean).join(' ');
 const nodeUrl=pathToFileURL(path.join(sourceRoot,'packages/chord/src/node.ts')).href;
 const api=await import(nodeUrl);
 const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
 await new AsyncFunction('api','guestPath','guestNodeSpecifier',fs.readFileSync(callerPath,'utf8'))(api,guestPath,nodeUrl);
 if(!Array.isArray(globalThis.chordForkDriverCases)||globalThis.chordForkDriverCases.length!==2)throw Error('Fork2 caller inventory changed');
 fs.writeFileSync(outputPath,JSON.stringify({source_scope:'actual latest forkDriver childControl processLock manager and guest entry',cases:globalThis.chordForkDriverCases},null,2)+'\n');
 process.stdout.write(JSON.stringify({cases:2,output:outputPath})+'\n');
}finally{if(originalNodeOptions===undefined)delete process.env.NODE_OPTIONS;else process.env.NODE_OPTIONS=originalNodeOptions}
