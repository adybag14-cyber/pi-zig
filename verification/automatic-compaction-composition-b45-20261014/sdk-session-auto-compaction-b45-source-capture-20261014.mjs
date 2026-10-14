import{readFileSync,writeFileSync}from'node:fs';import{createHash}from'node:crypto';
const{AgentSession}=await import('file:///C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/packages/coding-agent/src/core/agent-session.ts');
const p=AgentSession.prototype;globalThis.autoCompactionAPI={run:p._runAutoCompaction,failed:p._emitSessionCompactFailed,refresh:p._refreshFinalizedContext};
const input=readFileSync(process.argv[3]);await import('data:text/javascript,'+encodeURIComponent(input.toString('utf8')));
if(autoCompactionRows.length!==40)throw Error('All40 genuine automatic compaction cases required');
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb',inputSha256:createHash('sha256').update(input).digest('hex'),cases:40,scope:'Actual upstream automatic compaction body with genuine failed/refresh helpers and preparation on caller-owned dependencies; no full factory qualification',rows:autoCompactionRows},null,2));
