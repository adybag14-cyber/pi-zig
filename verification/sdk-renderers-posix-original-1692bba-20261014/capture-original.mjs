import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
const source=process.env.PI_RENDERER_SOURCE_ROOT,receipts=process.env.PI_RENDERER_RECEIPTS,family=process.argv[2],output=process.argv[3],input=process.argv[4];
if(!['listing','shell'].includes(family))throw Error('Unknown renderer family');
const hash=path=>createHash('sha256').update(readFileSync(path)).digest('hex');
const verify=()=>['source','dependencies','node-tools','candidate'].map(name=>{const rows=JSON.parse(readFileSync(join(receipts,name+'-before.json'),'utf8').replace(/^\uFEFF/,''));for(const row of rows)if(hash(row.path)!==row.sha256.toLowerCase())throw Error('Frozen '+name+' drift '+row.path);return{name,count:rows.length,drift:0};});
const before=verify(),root=pathToFileURL(join(source,'packages/coding-agent/src/')).href;
const theme=await import(root+'modes/interactive/theme/theme.ts'),tui=await import('@earendil-works/pi-tui');
tui.setCapabilityOverrides({images:null,hyperlinks:false});
globalThis.actualRendererTheme=theme.loadThemeFromPath(join(source,'packages/coding-agent/src/modes/interactive/theme/dark.json'),'truecolor');
theme.setThemeInstance(actualRendererTheme);
if(family==='listing')globalThis.listingRenderers={find:(await import(root+'core/tools/renderers/find.ts')).findRenderers,ls:(await import(root+'core/tools/renderers/ls.ts')).lsRenderers,grep:(await import(root+'core/tools/renderers/grep.ts')).grepRenderers};
else{
 globalThis.createShellRenderers=(await import(root+'core/tools/renderers/bash.ts')).createShellRenderers;
 globalThis.formatToolDuration=(await import(root+'core/tools/render-utils.ts')).formatToolDuration;
 globalThis.ignoredRendererTheme=new Proxy(actualRendererTheme,{get(){throw Error('shell renderers accessed ignored Theme argument');}});
}
await import('data:text/javascript,'+encodeURIComponent(readFileSync(input,'utf8')));
const raw=JSON.parse(JSON.stringify(family==='listing'?sdkListingRendererRows:sdkShellRendererRows));
if(raw.length!==(family==='listing'?59:53))throw Error('Original complete renderer inventory mismatch');
const observed=readFileSync(join(receipts,`modules-${process.pid}.jsonl`),'utf8').trim().split('\n').map(JSON.parse);
for(const row of observed.filter(row=>row.kind==='observed-module'))if(hash(row.path)!==row.sha256)throw Error('Observed original module drift '+row.path);
writeFileSync(output,JSON.stringify({source:'1692bba6347a287ab0f3cb554a4430fafffc474b',scope:'Unchanged original renderer bodies and genuine Theme/TUI/helpers on the actual recorded platform; caller input unchanged, no TypeError normalization or Source body rewrite',family,platform:process.platform,arch:process.arch,cases:raw.length,node:{version:process.version,path:process.execPath,sha256:hash(process.execPath),execArgv:process.execArgv},input:{path:input,sha256:hash(input)},before,after:verify(),raw,observedModules:observed},null,2));
