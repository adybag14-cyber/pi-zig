import{readFileSync,writeFileSync,readdirSync}from'node:fs';import{createHash}from'node:crypto';import{join}from'node:path';import{pathToFileURL}from'node:url';
const evidence='C:/Users/adyba/pi-zig-update-evidence-20261003/',root='C:/Users/adyba/pi-upstream-source-1692bba-20261014';
const hash=path=>createHash('sha256').update(readFileSync(path)).digest('hex');
const frozen=JSON.parse(readFileSync(process.argv[4],'utf8'));
const verify=()=>frozen.map(manifest=>{if(hash(manifest.path)!==manifest.sha256.toLowerCase())throw Error('Manifest drift '+manifest.path);const rows=JSON.parse(readFileSync(manifest.path,'utf8'));for(const row of rows)if(hash(row.path)!==row.sha256.toLowerCase())throw Error('Frozen '+manifest.name+' drift '+row.path);return{name:manifest.name,count:rows.length,drift:0}});
const before=verify();
const{default:core}=await import(pathToFileURL(join(root,'node_modules/highlight.js/lib/core.js')).href);
const constructors=new Map();
for(const insensitive of[false,true]){const name='pi-original-multi-regex-'+insensitive;core.registerLanguage(name,()=>({case_insensitive:insensitive,contains:[{begin:/a/,end:/b/}]}));core.highlight('ab',{language:name,ignoreIllegals:true});const language=core.getLanguage(name);constructors.set(insensitive,language.matcher.getMatcher(0).constructor);}
let instances=0;globalThis.makeMultiRegex=options=>{instances++;return new(constructors.get(Boolean(options.case_insensitive)))()};
const input=readFileSync(process.argv[3],'utf8');await import('data:text/javascript,'+encodeURIComponent(input));
if(sdkMultiRegexRows.length!==30||instances!==30)throw Error('Original MultiRegex30 inventory mismatch '+sdkMultiRegexRows.length+'/'+instances);
const observedModules=readdirSync(evidence).filter(name=>name.startsWith(`sdk-source-1692-modules-${process.pid}-`)).flatMap(name=>readFileSync(evidence+name,'utf8').trim().split('\n').filter(Boolean).map(JSON.parse));
for(const row of observedModules.filter(row=>row.kind==='observed-module'))if(hash(row.path)!==row.sha256)throw Error('Observed original module drift');
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'1692bba6347a287ab0f3cb554a4430fafffc474b',inputSha256:createHash('sha256').update(input).digest('hex'),platform:process.platform,arch:process.arch,cases:sdkMultiRegexRows.length,instances,node:{version:process.version,path:process.execPath,sha256:hash(process.execPath),execArgv:process.execArgv},before,after:verify(),scope:'Original actual highlight.js10.7.3 MultiRegex constructors from real compiled caller grammars; unchanged caller input, no Source body rewrite; private algorithms and observed class metadata only',rows:sdkMultiRegexRows,observedModules},null,2));
