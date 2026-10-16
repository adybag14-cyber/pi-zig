// Unexecuted genuine ECMAScript language observer. No hand-built async-from-
// sync adapter or production host implementation is used.
import {existsSync,readFileSync,writeFileSync} from 'node:fs';
import {dirname,join,resolve,relative,isAbsolute} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {consume} from './language-consumer.mjs';
import {observeForAwait} from './for-await-callers.mjs';
if(process.version!=='v24.14.0'||!process.argv[2])throw Error('Pinned Node and owned output required');
let container=dirname(fileURLToPath(import.meta.url));while(!existsSync(join(container,'.pi-zig-workspace.json'))){const parent=dirname(container);if(parent===container)throw Error('Container metadata missing');container=parent}
const layout=JSON.parse(readFileSync(join(container,'.pi-zig-workspace.json'),'utf8'));if(layout.schema!==1||layout.all_agent_jobs_held_for_revalidation)throw Error('Reference jobs remain held');
const output=resolve(process.argv[2]),under=relative(resolve(container,layout.evidence),output);if(under==='..'||under.startsWith('..\\')||under.startsWith('../')||isAbsolute(under))throw Error('Owned output must remain under contained evidence');
const rows=await observeForAwait(consume);if(rows.length!==56)throw Error('All56 genuine language caller observations required');
const files=['language-consumer.mjs','for-await-callers.mjs','capture-language-reference.mjs'].map(name=>({name,sha256:createHash('sha256').update(readFileSync(new URL(name,import.meta.url))).digest('hex')}));
writeFileSync(output,JSON.stringify({authority:'Actual pinned Node language for-await and async-generator yield*; no adapter implementation',actualNode:{pid:process.pid,execPath:process.execPath,version:process.version,v8:process.versions.v8},cases:rows.length,rows,files,nativeQualified:false,network:false,sdkRuntimeDependency:false},null,2));
