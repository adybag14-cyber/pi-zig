import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const {AgentSession}=await import('file:///C:/Users/adyba/pi-upstream-source-1692bba-20261014/packages/coding-agent/src/core/agent-session.ts');
globalThis.sessionRestoreMethod=AgentSession.prototype._restoreToolsFromTranscript;
const input=readFileSync(process.argv[3]);
await import('data:text/javascript,'+encodeURIComponent(input.toString('utf8')));
if(sessionRestoreRows.length!==22)throw Error('All22 original restore observations required');
writeFileSync(process.argv[2],JSON.stringify({sourceHead:'1692bba6347a287ab0f3cb554a4430fafffc474b',inputSha256:createHash('sha256').update(input).digest('hex'),scope:'Actual unchanged original AgentSession.prototype._restoreToolsFromTranscript on caller-owned receivers; original current-system and settings-manager helper dependencies; this is method qualification, not complete factory qualification',cases:22,rows:sessionRestoreRows},null,2));
