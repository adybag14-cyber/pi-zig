import {readFileSync,writeFileSync,readdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
const evidence='C:/Users/adyba/pi-zig-update-evidence-20261003/';
const hash=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
const names=['sdk-loadout-e622-full-source-runtime-manifest-20261013.json','durable-19cb534-reference-20261012-all-built-runtime.json','root-current8a-npm-tools-before.json'];
const inventories=names.map(name=>{const parsed=JSON.parse(readFileSync(evidence+name,'utf8').replace(/^\uFEFF/,''));return {name,manifestSha256:hash(evidence+name),rows:Array.isArray(parsed)?parsed:parsed.inputs};});
function verify(){return inventories.map(({name,manifestSha256,rows})=>{const drift=rows.filter(row=>hash(row.path)!==row.sha256.toLowerCase()).map(row=>row.path);if(drift.length)throw Error('Immutable Source runtime drift '+name+' '+drift[0]);return {manifest:name,manifestSha256,count:rows.length,drift:0};});}
const before=verify(),began=Date.now();
const original=await import('file:///C:/Users/adyba/pi-sdk-loadout-source-e6220e1-20261013/packages/coding-agent/src/modes/interactive/components/visual-truncate.ts');
globalThis.VisualLinePreview=original.VisualLinePreview;globalThis.truncateToVisualLines=original.truncateToVisualLines;
await import('data:text/javascript,'+encodeURIComponent(readFileSync(process.argv[3],'utf8')));
const raw=JSON.parse(JSON.stringify(globalThis.sdkVisualPreviewRows)),ended=Date.now();
const observedModules=readdirSync(evidence).filter(name=>name.startsWith(`sdk-loadout-e622-modules-${process.pid}-`)).flatMap(name=>readFileSync(evidence+name,'utf8').trim().split('\n').filter(Boolean).map(JSON.parse));
for(const module of observedModules.filter(x=>x.kind==='observed-module'))if(hash(module.path)!==module.sha256)throw Error('Observed module drift '+module.path);
writeFileSync(process.argv[2],JSON.stringify({source:'e6220e1316f86af818a0ccbfe1c09d7e918b41cf',scope:'Unchanged original VisualLinePreview and truncateToVisualLines with actual latest TUI Text; no Source body rewrites',node:{version:process.version,executable:process.execPath,executableSha256:hash(process.execPath),execArgv:process.execArgv},before,after:verify(),input:{path:process.argv[3],sha256:hash(process.argv[3])},timeBounds:{began,ended},raw,observedModules},null,2));
