import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const base='file:///C:/Users/adyba/pi-upstream-source-4dd2b149-20261016/packages/coding-agent/src/core/';
const packageVersion=JSON.parse(readFileSync(new URL('../../package.json',base))).version;
if(process.version!=='v24.14.0'||packageVersion!=='1.3.0'||process.env.PI_PACKAGE_DIR)throw Error('Pinned actual latest Source/Node authority mismatch');
const compaction=await import(base+'compaction/compaction.ts');
const {generateBranchSummary}=await import(base+'compaction/branch-summarization.ts');
const {createFileOps}=await import(base+'compaction/utils.ts');
const {defaultModelPerProvider}=await import(base+'model-resolver.ts');
globalThis.latestSummaryAPI={generateSummary:compaction.generateSummary,generateSummaryWithUsage:compaction.generateSummaryWithUsage,compact:compaction.compact,generateBranchSummary,createFileOps,defaultModelPerProvider};
const input=readFileSync(process.argv[3]);
let timer;
try{await Promise.race([import('data:text/javascript,'+encodeURIComponent(input.toString('utf8'))),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Original latest summary caller exceeded10s')),10000);})]);}finally{clearTimeout(timer);}
if(latestSummaryRows.length!==30)throw Error('All30 latest summary/default controls are required');
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'4dd2b149d155d7369de16ea4dc77c84e9f5ffb24',packageVersion,actualNode:{version:process.version,execPath:process.execPath,pid:process.pid},inputSha256:createHash('sha256').update(input).digest('hex'),cases:30,scope:'Unmodified official latest summary/default exports; caller-owned stream only. No expected values before terminal capture and full post validation.',rows:latestSummaryRows},null,2));
