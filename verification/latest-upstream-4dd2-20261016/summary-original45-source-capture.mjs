import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const base='file:///C:/Users/adyba/pi-upstream-source-4dd2b149-20261016/packages/coding-agent/src/core/compaction/';
const packageVersion=JSON.parse(readFileSync(new URL('../../../package.json',base))).version;
if(process.version!=='v24.14.0'||packageVersion!=='1.3.0'||process.env.PI_PACKAGE_DIR)throw Error('Pinned actual latest Source/Node authority mismatch');
const {generateSummaryWithUsage,generateSummary,compact}=await import(base+'compaction.ts');
const {createFileOps}=await import(base+'utils.ts');
globalThis.summaryGenerationAPI={generateSummaryWithUsage,generateSummary,compact};
globalThis.createSummaryFileOps=createFileOps;
const input=readFileSync(process.argv[3]);
const inputSha256=createHash('sha256').update(input).digest('hex');
if(inputSha256!=='891ff13852540cade5aba7726488caae59c9e38bddf124be80b948b6bd966b38')throw Error('Original summary45 caller bytes changed');
let timer;
try{await Promise.race([import('data:text/javascript,'+encodeURIComponent(input.toString('utf8'))),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Original summary45 caller exceeded10s')),10000);})]);}finally{clearTimeout(timer);}
if(summaryGenerationRows.length!==45)throw Error('All45 unchanged original summary caller cases required');
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'4dd2b149d155d7369de16ea4dc77c84e9f5ffb24',packageVersion,actualNode:{version:process.version,execPath:process.execPath,pid:process.pid},inputSha256,cases:45,scope:'Actual latest4dd exports with exact unchanged original45 caller input. Separate latest capture; original b45 expected and proof are immutable.',rows:summaryGenerationRows},null,2));
