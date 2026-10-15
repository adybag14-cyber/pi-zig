import { readFileSync, writeFileSync } from 'node:fs';
import { githubCopilotOAuth } from 'file:///C:/Users/adyba/pi-upstream-source-ae7b16d-20261015/packages/ai/src/auth/oauth/github-copilot.ts';
import { kimiCodingOAuth } from 'file:///C:/Users/adyba/pi-upstream-source-ae7b16d-20261015/packages/ai/src/auth/oauth/kimi-coding.ts';
import { xaiOAuth } from 'file:///C:/Users/adyba/pi-upstream-source-ae7b16d-20261015/packages/ai/src/auth/oauth/xai.ts';
Object.assign(globalThis,{githubCopilotOAuth,kimiCodingOAuth,xaiOAuth});
const inputPath='C:/Users/adyba/pi-zig-native-oauth-copilot-kimi-xai-20261015/src/extensions/fixtures/ai-oauth-subscriptions-ae7.input.txt';
await new Function('return(async()=>{'+readFileSync(inputPath,'utf8')+'\n})()')();
const result={runtime:process.version,count:globalThis.subscriptionOAuthRows.length,sourceHead:'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d',clock:'controlled Date.now/microtask sleep; owner uses real wall time',rawDiagnostics:globalThis.subscriptionOAuthDiagnostics,rows:globalThis.subscriptionOAuthRows};
writeFileSync(process.argv[2],JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({rows:result.count,network:'fake fetch only'}));

