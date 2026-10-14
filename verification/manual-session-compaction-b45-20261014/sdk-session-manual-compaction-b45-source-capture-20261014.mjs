import{readFileSync,writeFileSync}from'node:fs';import{createHash}from'node:crypto';
const{AgentSession}=await import('file:///C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/packages/coding-agent/src/core/agent-session.ts');
const{createFileOps}=await import('file:///C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/packages/coding-agent/src/core/compaction/utils.ts');
const p=AgentSession.prototype;globalThis.manualCompactionAPI={compact:p.compact,clear:p._clearManualCompactionState,failed:p._emitSessionCompactFailed,refresh:p._refreshFinalizedContext,defaultSummary:p._runDefaultCompaction,createFileOps};
const input=readFileSync(process.argv[3]);await import('data:text/javascript,'+encodeURIComponent(input.toString('utf8')));
if(manualCompactionRows.length!==44)throw Error('All44 genuine manual compaction cases required');
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb',inputSha256:createHash('sha256').update(input).digest('hex'),cases:44,scope:'Actual upstream ordinary manual32 plus actual default summary8 and finalized projection4 on caller-owned collaborators; actual summary generation included; full factory remains separate',rows:manualCompactionRows},null,2));
