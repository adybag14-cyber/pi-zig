import {writeFileSync} from 'node:fs';
import {openaiCodexOAuth} from 'file:///C:/Users/adyba/pi-upstream-source-ae7b16d-20261015/packages/ai/src/auth/oauth/openai-codex.ts';
import {createRadiusOAuth} from 'file:///C:/Users/adyba/pi-upstream-source-ae7b16d-20261015/packages/ai/src/auth/oauth/radius.ts';
import {runOAuthBrowserCases,browserCaseIds} from './oauth-codex-radius-browser-ae7-cases-20261015.mjs';
const timeout=setTimeout(()=>{console.error('Owned OAuth browser Source deadline exceeded');process.exit(124)},30000);
const listeners=[];
const ownedServers=new Set(),acceptedSockets=new Set(),rawEvents=[],rawDiagnostics=[];
let acceptedSocketCount=0,closedSocketCount=0;
globalThis.__observeOAuthEvent=event=>rawEvents.push(JSON.parse(JSON.stringify(event)));
globalThis.__observeOAuthError=(id,error)=>rawDiagnostics.push({id,name:error?.name,message:error?.message,stack:error?.stack,constructor:error?.constructor?.name,...(Object.hasOwn(error,'status')?{status:error.status}:{}),...(Object.hasOwn(error,'oauthError')?{oauthError:error.oauthError??null}:{})});
globalThis.__observeOAuthListener=port=>{
  const handles=process._getActiveHandles().filter(handle=>handle.constructor?.name==='Server'&&handle.listening);
  const servers=handles.map(handle=>handle.address());
  if(servers.length!==1||servers[0]?.port!==port||servers[0]?.address!=='127.0.0.1')throw Error('Source callback listener ownership mismatch');
  listeners.push({pid:process.pid,address:servers[0].address,port:servers[0].port,actualServer:true});
  const server=handles[0];
  if(!ownedServers.has(server)){
    ownedServers.add(server);
    server.on('connection',socket=>{acceptedSockets.add(socket);acceptedSocketCount++;socket.once('close',()=>{acceptedSockets.delete(socket);closedSocketCount++})});
  }
};
try{
  await new Promise(resolve=>setTimeout(resolve,25));
  const nativeFetch=globalThis.fetch;
  const result=await runOAuthBrowserCases(openaiCodexOAuth,createRadiusOAuth,(input,init)=>{
    const url=new URL(input);
    if(url.hostname!=='127.0.0.1'||url.port!=='1456'||url.pathname!=='/oauth/callback')throw Error('Owned loopback callback origin required');
    return nativeFetch(input,init);
  });
  if(result.length!==7||browserCaseIds.length!==7)throw Error('Strict browser Source case inventory mismatch');
  if(listeners.length!==7||process._getActiveHandles().some(handle=>handle.constructor?.name==='Server'&&handle.listening))throw Error('Owned browser callback listener lifecycle mismatch');
  const settleDeadline=performance.now()+10000;
  while(acceptedSockets.size){if(performance.now()>=settleDeadline)throw Error('Owned Source callback sockets did not close');await new Promise(resolve=>setTimeout(resolve,25))}
  if(acceptedSocketCount!==2||closedSocketCount!==2||rawEvents.filter(event=>event.type==='auth_url').length!==7||rawDiagnostics.length!==3)throw Error('Owned Source browser effect inventory mismatch');
  if(!process.argv[2])throw Error('Owned output path required');
  writeFileSync(process.argv[2],JSON.stringify({sourceHead:'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d',runtime:process.version,count:result.length,caseIds:browserCaseIds,listeners,ownedSockets:{accepted:acceptedSocketCount,closed:closedSocketCount,remaining:acceptedSockets.size},rawEvents,rawDiagnostics,rows:result},null,2)+'\n');
  console.log(JSON.stringify({status:'source-complete',caseCount:result.length,sourceHead:'ae7b16d43b7c78c5b6fa3213fdd1215bb339729d'}));
}finally{clearTimeout(timeout)}
