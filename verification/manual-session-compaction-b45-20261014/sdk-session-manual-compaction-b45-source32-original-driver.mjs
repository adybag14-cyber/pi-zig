import{readFileSync,writeFileSync}from'node:fs';import{createHash}from'node:crypto';
const{AgentSession}=await import('file:///C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/packages/coding-agent/src/core/agent-session.ts');
const p=AgentSession.prototype;globalThis.manualCompactionAPI={compact:p.compact,clear:p._clearManualCompactionState,failed:p._emitSessionCompactFailed,refresh:p._refreshFinalizedContext};
const input=readFileSync(process.argv[3]);await import('data:text/javascript,'+encodeURIComponent(input.toString('utf8')));
if(manualCompactionRows.length!==32)throw Error('All32 genuine manual compaction cases required');
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb',inputSha256:createHash('sha256').update(input).digest('hex'),cases:32,scope:'Actual upstream ordinary manual compact/clear/failure/refresh bodies on caller-owned collaborators; default summary request and full factory are separate',rows:manualCompactionRows},null,2));
