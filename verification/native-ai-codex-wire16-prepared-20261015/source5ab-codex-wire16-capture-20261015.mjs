// Actual immutable Source provider and manifested ws8.21 transport, owned loopback only.
import {writeFileSync,readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {zstdDecompressSync} from 'node:zlib';
import WebSocket,{WebSocketServer} from 'file:///C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/ws/wrapper.mjs';
const source='C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015/packages/ai/src/';
const originalSocket=globalThis.WebSocket,originalSetTimeout=globalThis.setTimeout,originalClearTimeout=globalThis.clearTimeout;
const ownedTimers=[],ownedClients=new Map(),ownedPeers=new Map(),capturedStreams=new WeakMap();
let current;
// Exact arguments, receiver, callback, duration and returned Timeout are preserved.
globalThis.setTimeout=function setTimeout(callback,after){const handle=Reflect.apply(originalSetTimeout,this,arguments);ownedTimers.push({handle,scenario:current?.spec.name??'source-import',requestedDelay:arguments[1]});return handle};
const api=await import(pathToFileURL(source+'api/openai-codex-responses.ts'));
const {cleanupSessionResources}=await import(pathToFileURL(source+'session-resources.ts'));
const {AssistantMessageEventStream}=await import(pathToFileURL(source+'utils/event-stream.ts'));
const originalPush=AssistantMessageEventStream.prototype.push;
const snapshot=value=>JSON.parse(JSON.stringify(value,(key,value)=>key==='durationMs'&&typeof value==='number'?0:value));
AssistantMessageEventStream.prototype.push=function(event){capturedStreams.get(this)?.push(snapshot(event));return Reflect.apply(originalPush,this,arguments)};
const specifications=[
 {name:'cached-continuation',turns:2},
 {name:'request-shape-change',turns:2,changeShape:true},
 {name:'busy-session',turns:2,parallel:true},
 {name:'connection-limit-retry',turns:1,connectionLimit:true},
 {name:'missing-previous-retry',turns:2,missingPrevious:true},
 {name:'provider-callback-rejection',turns:1,rejectProvider:true},
 {name:'pre-start-close-fallback-affinity',turns:2,preClose:true},
 {name:'post-start-close-1009',turns:1,postClose:true},
 {name:'idle-remote-close-between-turns',turns:2,idleClose:true},
 {name:'explicit-session-cleanup',turns:2,cleanupBetween:true},
 {name:'binary-buffer',turns:1,binary:true,binaryType:'nodebuffer'},
 {name:'binary-arraybuffer',turns:1,binary:true,binaryType:'arraybuffer'},
 {name:'binary-blob',turns:1,binary:true,binaryType:'blob'},
 {name:'malformed-json',turns:1,malformed:true},
 {name:'idle-read-timeout',turns:1,silent:true},
 {name:'post-start-abnormal-eof',turns:1,abnormal:true},
];
const token='e30.'+Buffer.from(JSON.stringify({'https://api.openai.com/auth':{chatgpt_account_id:'account-fixture'}})).toString('base64')+'.sig';
const modelTemplate={id:'gpt-5.5',api:'openai-codex-responses',provider:'openai-codex',reasoning:true,input:['text','image'],contextWindow:32000,maxTokens:8192,cost:{input:2,output:8,cacheRead:0.5,cacheWrite:1}};
const context={messages:[{role:'system',content:'system',timestamp:0},{role:'user',content:'hello',timestamp:1}]};
const message=text=>({type:'message',id:'msg_fixture',role:'assistant',status:'completed',phase:'final_answer',content:[{type:'output_text',text,annotations:[]}]});
const events=id=>[{type:'response.created',response:{id}},{type:'response.output_item.added',output_index:0,item:message('')},{type:'response.output_text.delta',output_index:0,delta:'answer'},{type:'response.output_item.done',output_index:0,item:message('answer')},{type:'response.done',response:{id,status:'completed',end_turn:true,output:[message('answer')],usage:{input_tokens:8,output_tokens:2,total_tokens:10},service_tier:'default'}}];
const server=createServer(async(req,res)=>{
 const state=current;
 try{
  const chunks=[];for await(const chunk of req)chunks.push(chunk);const wire=Buffer.concat(chunks);
  const decoded=req.headers['content-encoding']==='zstd'?zstdDecompressSync(wire):wire;
  state.http.push({method:req.method,url:origin+req.url,path:req.url,rawHeaders:[...req.rawHeaders],headers:{...req.headers},bodyBase64:wire.toString('base64'),decodedBody:decoded.toString(),body:JSON.parse(decoded.toString())});
  res.writeHead(200,{'content-type':'text/event-stream','x-fixture-response':'owned-loopback'});
  for(const event of events('resp_sse'))res.write('data: '+JSON.stringify(event)+'\n\n');res.end();
 }catch(error){state.peerErrors.push({phase:'http',name:error.name,message:error.message,stack:error.stack});res.destroy(error)}
});
const tcpSockets=new Set();server.on('connection',socket=>{tcpSockets.add(socket);socket.on('close',()=>tcpSockets.delete(socket))});
const wss=new WebSocketServer({noServer:true,perMessageDeflate:false});
server.on('upgrade',(req,socket,head)=>{
 const state=current,record={index:state.handshakes.length,method:req.method,url:origin+req.url,path:req.url,rawHeaders:[...req.rawHeaders],headers:{...req.headers},frames:[],replies:[],controls:[],closes:[]};
 state.handshakes.push(record);
 wss.handleUpgrade(req,socket,head,peer=>{
  ownedPeers.set(peer,{scenario:state.spec.name,index:record.index});state.peers.push(peer);
  peer.on('error',error=>state.peerErrors.push({phase:'websocket',name:error.name,message:error.message,stack:error.stack}));
  peer.on('close',(code,reason)=>record.closes.push({code,reason:reason.toString()}));
  peer.on('pong',data=>record.controls.push({type:'pong',base64:data.toString('base64')}));
  peer.on('message',(bytes,isBinary)=>{
   let body;try{body=JSON.parse(bytes.toString())}catch(error){state.peerErrors.push({phase:'request-json',name:error.name,message:error.message,stack:error.stack});peer.terminate();return}
   record.frames.push({isBinary,base64:bytes.toString('base64'),text:bytes.toString(),body:snapshot(body)});
   const ordinal=++state.sends;let incoming=events('resp_'+ordinal);
   if(state.spec.connectionLimit&&ordinal===1)incoming=[{type:'error',code:'websocket_connection_limit_reached',message:'fixture connection limit'}];
   if(state.spec.missingPrevious&&body.previous_response_id&&!state.missingSent){state.missingSent=true;incoming=[{type:'error',code:'previous_response_not_found',message:'fixture previous missing'}]}
   if(state.spec.silent)return;
   if(state.spec.preClose){peer.close(1011,'fixture pre-start close');return}
   const send=text=>{const reply={text,binary:!!state.spec.binary};record.replies.push(reply);peer.send(text,{binary:reply.binary},error=>{reply.completion=error?{name:error.name,message:error.message,stack:error.stack}:null})};
   if(state.spec.malformed){send('{"type":');return}
   if(state.spec.postClose||state.spec.abnormal)incoming=incoming.slice(0,3);
   peer.ping(Buffer.from('fixture-ping'));
   for(const event of incoming)send(JSON.stringify(event));
   if(state.spec.postClose)peer.close(1009);
   if(state.spec.abnormal)peer._socket.end();
  });
 });
});
await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve)});
const address=server.address(),origin='http://127.0.0.1:'+address.port;
// This is a real caller-supplied global constructor over manifested ws8.21.
// Source's exact constructor URL/options are recorded before the actual super call.
class CallerWebSocket extends WebSocket{
 constructor(url,options){
  const state=current,record={index:state.clients.length,url:String(url),headers:snapshot(options.headers),events:[],sends:[],closes:[]};state.clients.push(record);
  super(url,options);this.binaryType=state.spec.binaryType??'nodebuffer';ownedClients.set(this,{scenario:state.spec.name,index:record.index});state.clientSockets.push(this);
  this.on('open',()=>record.events.push({type:'open',readyState:this.readyState}));
  this.on('message',(data,isBinary)=>record.events.push({type:'message',isBinary,kind:Object.prototype.toString.call(data),byteLength:data.byteLength??data.size??null}));
  this.on('close',(code,reason)=>record.events.push({type:'close',code,reason:reason.toString(),readyState:this.readyState}));
  this.on('error',error=>record.events.push({type:'error',name:error.name,message:error.message,stack:error.stack}));
 }
 send(data,...rest){current.clients[ownedClients.get(this).index].sends.push(String(data));return super.send(data,...rest)}
 close(...args){const owner=ownedClients.get(this);if(owner&&current?.spec.name===owner.scenario)current.clients[owner.index].closes.push(snapshot(args));return super.close(...args)}
}
globalThis.WebSocket=CallerWebSocket;
const rows=[];
try{
 for(const spec of specifications){
  cleanupSessionResources();api.resetOpenAICodexWebSocketDebugStats();
  current={spec,clients:[],clientSockets:[],handshakes:[],peers:[],http:[],peerErrors:[],sends:0,missingSent:false};const state=current;
  const model={...modelTemplate,baseUrl:origin+'/backend-api'};const sessionId='wire-fixture-'+spec.name;const turns=[];
  async function turn(ctx,turnIndex){
   const trace=[],pushEvents=[],consumerEvents=[],aliases=[];let first,providerIndex=0,result,thrown;
   const options={apiKey:token,sessionId,transport:'websocket-cached',headers:{'User-Agent':'pi-fixture'},timeoutMs:spec.silent?75:1000,websocketConnectTimeoutMs:1000,maxRetries:0,reasoningEffort:'high',...(spec.changeShape&&turnIndex===1?{temperature:0.8}:{}),
    onPayload:async(payload,m)=>{trace.push(['payload-enter',m===model,snapshot(payload)]);await Promise.resolve();trace.push(['payload-leave',m===model])},
    onProviderStreamEvent:async(event,m)=>{trace.push(['provider-enter',providerIndex,m===model,snapshot(event)]);await Promise.resolve();trace.push(['provider-leave',providerIndex,m===model]);if(spec.rejectProvider&&providerIndex===0)throw {fixture:'wire-callback-rejection'};providerIndex++},
    onResponse:async(response,m)=>{trace.push(['response-enter',m===model,snapshot(response)]);await Promise.resolve();trace.push(['response-leave',m===model])},
   };
   try{const stream=api.stream(model,ctx,options);capturedStreams.set(stream,pushEvents);for await(const event of stream){const output=event.partial??event.message??event.error;first??=output;aliases.push([event.type,output===first]);consumerEvents.push(snapshot(event))}result=await stream.result();aliases.push(['result',result===first]);capturedStreams.delete(stream)}catch(error){thrown={type:typeof error,name:error?.name,message:error?.message,text:String(error),stack:error?.stack}}
   const row={turnIndex,context:snapshot(ctx),options:{transport:options.transport,sessionId,timeoutMs:options.timeoutMs,websocketConnectTimeoutMs:options.websocketConnectTimeoutMs,maxRetries:options.maxRetries,reasoningEffort:options.reasoningEffort,...(Object.hasOwn(options,'temperature')?{temperature:options.temperature}:{})},trace,pushEvents,consumerEvents,aliases,result:result?snapshot(result):null,...(thrown?{thrown}:{})};turns.push(row);return result;
  }
  if(spec.parallel)await Promise.all([turn(context,0),turn(context,1)]);
  else{
   const result=await turn(context,0);
   if(spec.turns===2){
    if(spec.idleClose){const peer=state.peers[0],client=state.clientSockets[0];const closed=once(client,'close');peer.close(1000,'fixture idle remote close');await closed;state.idleClosedReadyState=client.readyState}
    if(spec.cleanupBetween)cleanupSessionResources(sessionId);
    await turn({messages:[...context.messages,...(result?[result]:[]),{role:'user',content:'next',timestamp:2}]},1);
   }
  }
  const rawStats=api.getOpenAICodexWebSocketDebugStats(sessionId);const stats=rawStats===undefined?undefined:snapshot(rawStats);
  cleanupSessionResources(sessionId);
  // Drain actual close handshakes; already closed peers require no invented wait.
  await Promise.all(state.clientSockets.filter(socket=>socket.readyState===WebSocket.CLOSING).map(socket=>new Promise(resolve=>socket.once('close',resolve))));
  rows.push({name:spec.name,model:snapshot(model),clients:snapshot(state.clients),requests:snapshot(state.handshakes),http:snapshot(state.http),turns,stats,peerErrors:snapshot(state.peerErrors),...(Object.hasOwn(state,'idleClosedReadyState')?{idleClosedReadyState:state.idleClosedReadyState}:{})});
 }
 cleanupSessionResources();
 const sourceLifecycle={unclosedClients:[...ownedClients].filter(([socket])=>socket.readyState!==WebSocket.CLOSED).map(([,record])=>record),unclosedPeers:[...ownedPeers].filter(([socket])=>socket.readyState!==WebSocket.CLOSED).map(([,record])=>record),retainedTimers:ownedTimers.map((record,index)=>({index,scenario:record.scenario,requestedDelay:record.requestedDelay,destroyed:record.handle._destroyed,refed:record.handle.hasRef()})).filter(record=>!record.destroyed)};
 // Only exact job-owned handles/sockets are cleared after all observations.
 for(const record of ownedTimers)Reflect.apply(originalClearTimeout,globalThis,[record.handle]);
 const teardownClosures=[...ownedClients.keys(),...ownedPeers.keys()].filter(socket=>socket.readyState!==WebSocket.CLOSED).map(socket=>new Promise(resolve=>socket.once('close',resolve)));
 for(const [socket] of ownedClients)if(socket.readyState!==WebSocket.CLOSED)socket.terminate();
 for(const [socket] of ownedPeers)if(socket.readyState!==WebSocket.CLOSED)socket.terminate();
 for(const socket of tcpSockets)socket.destroy();
 await Promise.all(teardownClosures);
 await new Promise(resolve=>wss.close(resolve));await new Promise(resolve=>server.close(resolve));
 const testTeardown={listening:server.listening,websocketClients:wss.clients.size,tcpSockets:tcpSockets.size,remainingTimers:ownedTimers.filter(record=>!record.handle._destroyed).length,remainingClients:[...ownedClients].filter(([socket])=>socket.readyState!==WebSocket.CLOSED).length,remainingPeers:[...ownedPeers].filter(([socket])=>socket.readyState!==WebSocket.CLOSED).length};
 const result={sourceHead:'5ab7fe74c400097b386662205cd93900695b8a71',actualNode:{version:process.version,executable:process.execPath},transport:{kind:'actual-caller-global',package:JSON.parse(readFileSync('C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/node_modules/ws/package.json')),origin},cases:specifications.length,context,specifications,rows,protocolSourceCompleted:true,sourceLifecycleQualified:sourceLifecycle.unclosedClients.length===0&&sourceLifecycle.unclosedPeers.length===0&&sourceLifecycle.retainedTimers.length===0,sourceLifecycle,testTeardown};
 writeFileSync(process.argv[2],JSON.stringify(result,null,2)+'\n');
 if(testTeardown.listening||testTeardown.websocketClients||testTeardown.tcpSockets||testTeardown.remainingTimers||testTeardown.remainingClients||testTeardown.remainingPeers)throw Error('Exact owned loopback teardown incomplete');
 console.log(JSON.stringify({cases:rows.length,requests:rows.reduce((n,row)=>n+row.requests.length,0),http:rows.reduce((n,row)=>n+row.http.length,0),turns:rows.reduce((n,row)=>n+row.turns.length,0)}));
}finally{
 globalThis.WebSocket=originalSocket;globalThis.setTimeout=originalSetTimeout;AssistantMessageEventStream.prototype.push=originalPush;
 for(const record of ownedTimers)Reflect.apply(originalClearTimeout,globalThis,[record.handle]);
 for(const [socket] of ownedClients)if(socket.readyState!==WebSocket.CLOSED)socket.terminate();
 for(const [socket] of ownedPeers)if(socket.readyState!==WebSocket.CLOSED)socket.terminate();
 for(const socket of tcpSockets)socket.destroy();wss.close();server.close();
}
