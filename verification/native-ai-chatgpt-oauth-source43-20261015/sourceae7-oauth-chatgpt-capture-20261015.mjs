import { readFileSync, writeFileSync } from 'node:fs';
import { openaiChatGPTOAuth } from 'file:///C:/Users/adyba/pi-upstream-source-ae7b16d-20261015/packages/ai/src/auth/oauth/openai-chatgpt.ts';
globalThis.openaiChatGPTOAuth = openaiChatGPTOAuth;
const ownedListeners=[];
globalThis.__chatGPTOAuthObserveListener=()=>{
  const handles=process._getActiveHandles().filter(handle=>handle.constructor?.name==='Server'&&handle.listening);
  const servers=handles.map(handle=>handle.address());
  if(servers.length!==1||servers[0]?.port!==1455||servers[0]?.address!=='127.0.0.1')throw Error('Source callback listener ownership mismatch');
  ownedListeners.push({pid:process.pid,address:servers[0].address,port:servers[0].port,actualServer:true});
};
const inputPath = 'C:/Users/adyba/pi-zig-native-oauth-chatgpt-20261015/src/extensions/fixtures/ai-oauth-chatgpt-ae7.input.mjs';
const input = readFileSync(inputPath, 'utf8');
await (new Function('return (async()=>{' + input + '\n})()'))();
const observation = globalThis.chatGPTOAuthObservation;
if(ownedListeners.length!==6||process._getActiveHandles().some(handle=>handle.constructor?.name==='Server'&&handle.listening))throw Error('Source did not own and close all six callback listeners');
writeFileSync(process.argv[2], JSON.stringify({runtime:process.version,count:observation.rows.length,sourceHead:'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d',network:'controlled fake fetch; no token endpoint or browser launch',ownedListeners,clock:'controlled Date.now; owner deadline uses wall clock',...observation}, null, 2) + '\n');
console.log(JSON.stringify({rows:observation.rows.length,requests:observation.wire.length,network:'controlled fake fetch only'}));
