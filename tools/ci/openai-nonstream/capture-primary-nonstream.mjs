// Prepared genuine primary observer. Root's separately admitted owner must
// resolve argv[2] through Resolve-PiZigWorkspace.ps1 and seal the complete
// recovered runtime/candidate/controls before any execution.
import {existsSync,readFileSync,writeFileSync} from 'node:fs';
import {dirname,join,resolve,relative,isAbsolute} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {observeNonstream} from './primary-nonstream-callers.mjs';
const runtime=process.argv[2],output=process.argv[3];
if(!runtime||!output||process.version!=='v24.14.0')throw Error('Resolved pinned runtime/output/Node required');
let container=dirname(fileURLToPath(import.meta.url));while(!existsSync(join(container,'.pi-zig-workspace.json'))){const parent=dirname(container);if(parent===container)throw Error('Workspace container metadata required');container=parent}
const layout=JSON.parse(readFileSync(join(container,'.pi-zig-workspace.json'),'utf8'));
if(layout.schema!==1||layout.runtime_status==='recovery_pending'||layout.all_agent_jobs_held_for_revalidation)throw Error('Runtime recovery/revalidation still held');
if(resolve(runtime).toLowerCase()!==resolve(container,layout.runtime).toLowerCase())throw Error('Runtime must come from workspace resolver');
const outputRelative=relative(resolve(container,layout.evidence),resolve(output));if(outputRelative==='..'||outputRelative.startsWith('..\\')||outputRelative.startsWith('../')||isAbsolute(outputRelative))throw Error('Owned output must remain under contained evidence');
const primary=join(runtime,'node_modules','openai','internal','parse.mjs'),digest=createHash('sha256').update(readFileSync(primary)).digest('hex').toUpperCase();
if(digest!=='A79745D365C6C0D258C0793BF44B23ECE19A6DFE0AB0C82AA565175F06A359B8')throw Error('Primary parse bytes differ from immutable earlier authority');
const packageFile=join(runtime,'node_modules','openai','package.json');if(JSON.parse(readFileSync(packageFile,'utf8')).version!=='6.40.0')throw Error('Pinned actual SDK required');
const {defaultParseResponse}=await import(pathToFileURL(primary).href);
const rows=await observeNonstream((props,client)=>defaultParseResponse(client,props));
if(rows.length!==57)throw Error('All57 shared primary caller observations required');
writeFileSync(output,JSON.stringify({authority:'Actual pinned SDK defaultParseResponse; shared owned caller controls only',node:{pid:process.pid,version:process.version,execPath:process.execPath},primary,primarySha256:digest,cases:rows.length,rows,nativeQualified:false,network:false},null,2));
