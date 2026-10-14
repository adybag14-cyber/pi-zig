import{readFileSync,writeFileSync}from'node:fs';import{createHash}from'node:crypto';
const base='file:///C:/Users/adyba/pi-upstream-source-b45e0eb-20261014/packages/';
const{AgentSession}=await import(base+'coding-agent/src/core/agent-session.ts');
const{registerApiProvider,getApiProvider}=await import(base+'ai/src/compat.ts');
globalThis.reloadAPI={reload:AgentSession.prototype.reload,registerApiProvider,getApiProvider};
const input=readFileSync(process.argv[3]);await import('data:text/javascript,'+encodeURIComponent(input.toString('utf8')));
if(reloadRows.length!==24)throw Error('All24 actual reload cases required');
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'b45e0ebcc5ae2fc42a6f2f23104d10e656e6bedb',inputSha256:createHash('sha256').update(input).digest('hex'),cases:24,scope:'Actual AgentSession.prototype.reload and actual compat registry reset on caller-owned receiver; full factory and builtin transport execution are outside this corpus',rows:reloadRows},null,2));
