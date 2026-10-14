import{readFileSync,writeFileSync}from'node:fs';import{createHash}from'node:crypto';
const base='file:///C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/packages/coding-agent/src/core/compaction/';
const{generateSummaryWithUsage,generateSummary,compact}=await import(base+'compaction.ts'),{createFileOps}=await import(base+'utils.ts');
globalThis.summaryGenerationAPI={generateSummaryWithUsage,generateSummary,compact};globalThis.createSummaryFileOps=createFileOps;
const input=readFileSync(process.argv[3]);await import('data:text/javascript,'+encodeURIComponent(input.toString('utf8')));
if(summaryGenerationRows.length!==45)throw Error('All45 original generation cases required');
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb',inputSha256:createHash('sha256').update(input).digest('hex'),cases:45,scope:'Actual unchanged generateSummaryWithUsage/generateSummary/compact with supplied stream, actual conversion/retry/file tracking/usage dependencies, deterministic clock, caller-owned getter and numeric cases',rows:summaryGenerationRows},null,2));
