import {writeFileSync} from 'node:fs';
import {openaiCodexOAuth} from 'file:///C:/Users/adyba/pi-upstream-source-ae7b16d-20261015/packages/ai/src/auth/oauth/openai-codex.ts';
import {createRadiusOAuth} from 'file:///C:/Users/adyba/pi-upstream-source-ae7b16d-20261015/packages/ai/src/auth/oauth/radius.ts';
import {runOAuthCases,caseIds} from './oauth-codex-radius-ae7-cases-20261015.mjs';
const timeout=setTimeout(()=>{console.error('Owned OAuth Source deadline exceeded');process.exit(124)},20000);
try {
  const result=await runOAuthCases(openaiCodexOAuth,createRadiusOAuth);
  if(result.length!==35 || caseIds.length!==35)throw Error('Strict Source case inventory mismatch');
  if(!process.argv[2])throw Error('Owned output path required');
  writeFileSync(process.argv[2],JSON.stringify({sourceHead:'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d',runtime:process.version,count:result.length,caseIds,rows:result},null,2)+'\n');
  console.log(JSON.stringify({status:'source-complete',caseCount:result.length,sourceHead:'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d'}));
} finally {clearTimeout(timeout)}
