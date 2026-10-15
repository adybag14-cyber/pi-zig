// Genuine Node24 global fetch/Request/Response loopback observations. New phase;
// no expected packet exists until the bounded authority capture has passed.
import {createServer} from 'node:http';
const rows=[],requests=[],sockets=new Set(),gates=new Map();
const descriptor=(object,key)=>{const d=Object.getOwnPropertyDescriptor(object,key);return{key:typeof key==='symbol'?String(key):key,enumerable:d.enumerable,configurable:d.configurable,...('value'in d?{writable:d.writable,value:typeof d.value==='function'?{type:'function',name:d.value.name,length:d.value.length}:typeof d.value==='symbol'?String(d.value):d.value!==null&&typeof d.value==='object'?{type:'object',tag:Object.prototype.toString.call(d.value)}:d.value}:{get:d.get?{name:d.get.name,length:d.get.length}:undefined,set:d.set?{name:d.set.name,length:d.set.length}:undefined})}};
const errorShape=e=>({name:e?.name,message:e?.message,code:e?.code,typeError:e instanceof TypeError,cause:e?.cause?{name:e.cause.name,message:e.cause.message,code:e.cause.code}:undefined});
const record=async(name,operation)=>{try{rows.push({name,value:await operation()})}catch(error){rows.push({name,error:errorShape(error)})}};
const server=createServer(async(req,res)=>{
  const chunks=[];for await(const chunk of req)chunks.push(chunk);
  const bytes=Buffer.concat(chunks),url=new URL(req.url,'http://localhost');
  requests.push({path:req.url,method:req.method,headers:req.headers,rawHeaders:req.rawHeaders,bytes:[...bytes]});
  if(url.pathname==='/echo'){res.setHeader('content-type','application/json');res.end(JSON.stringify({method:req.method,path:req.url,authorization:req.headers.authorization,custom:req.headers['x-custom'],contentType:req.headers['content-type']?.startsWith('multipart/form-data; boundary=')?'multipart/form-data':req.headers['content-type'],bytes:[...bytes]}));return}
  if(url.pathname==='/json'){res.setHeader('Content-Type','application/json');res.end('{"native":true,"text":"é😀"}');return}
  if(url.pathname==='/binary'){res.setHeader('Content-Type','application/octet-stream');res.end(Buffer.from([0,65,128,255,13,10]));return}
  if(url.pathname==='/error'){res.writeHead(403,{'Content-Type':'application/json'});res.end('{"error":{"type":"permission","message":"denied"}}');return}
  if(url.pathname==='/cookies'){res.setHeader('Set-Cookie',['one=1; Expires=Wed, 21 Oct 2026 07:28:00 GMT','two=2']);res.setHeader('X-Duplicate',['one','two']);res.end('cookies');return}
  if(url.pathname==='/latin1'){res.setHeader('__proto__','own');res.writeHead(201,'Cr\xe9\xe9',{'X-Latin1':'caf\xe9','constructor':'wire'});res.end('latin1');return}
  if(url.pathname==='/redirect'){res.writeHead(302,{Location:'/json'});res.end();return}
  if(url.pathname==='/null204'){res.writeHead(204);res.end();return}
  if(url.pathname==='/empty'){res.writeHead(200);res.end();return}
  if(url.pathname==='/gate'){
    const gate=gates.get(url.searchParams.get('id'));res.writeHead(gate.status,{'Content-Type':'application/json'});res.flushHeaders();gate.sent=true;await gate.release;gate.finished=true;res.end('{"headBeforeBody":true}');return
  }
  if(url.pathname==='/abort-head'){const gate=gates.get(url.searchParams.get('id'));gate.seen=true;await gate.release;res.end('late');return}
  if(url.pathname==='/abort-body'){res.writeHead(200);res.flushHeaders();res.write('first');const gate=gates.get(url.searchParams.get('id'));gate.seen=true;await gate.release;res.end('last');return}
  res.writeHead(404);res.end('missing');
});
server.on('connection',socket=>{sockets.add(socket);socket.on('close',()=>sockets.delete(socket))});
await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve)});
const origin='http://127.0.0.1:'+server.address().port;
const shape=r=>({status:r.status,statusText:r.statusText,ok:r.ok,type:r.type,url:r.url.replace(origin,'<origin>'),redirected:r.redirected,headers:[...r.headers].filter(([name])=>!['date','connection','keep-alive','transfer-encoding','content-length'].includes(name)),actualHeaders:r.headers instanceof Headers,body:r.body===null?null:{actualStream:r.body instanceof ReadableStream,locked:r.body.locked},bodyUsed:r.bodyUsed,actualResponse:r instanceof Response,tag:Object.prototype.toString.call(r)});
const gate=(id,status=200)=>{let unblock;const value={status,sent:false,seen:false,finished:false,release:new Promise(resolve=>unblock=resolve),unblock:()=>unblock()};gates.set(id,value);return value};
try{
  await record('fetch global descriptor',()=>descriptor(globalThis,'fetch'));
  await record('fetch function descriptors',()=>Reflect.ownKeys(fetch).map(key=>descriptor(fetch,key)));
  await record('fetch actual async return',async()=>{const value=fetch(origin+'/json');return{promise:value instanceof Promise,response:(await value) instanceof Response}});
  await record('fetch constructible ordinary wrapper',async()=>{const value=new fetch(origin+'/empty');return{promise:value instanceof Promise,text:await(await value).text()}});
  await record('fetch HTTP JSON metadata and consumption',async()=>{const r=await fetch(origin+'/json#fragment'),before=shape(r),value=await r.json();return{before,value,after:shape(r)}});
  for(const mode of ['text','bytes','arrayBuffer','blob'])await record('fetch binary '+mode,async()=>{const r=await fetch(origin+'/binary'),value=await r[mode]();return{shape:shape(r),value:mode==='text'?value:mode==='blob'?{type:value.type,size:value.size,bytes:[...new Uint8Array(await value.arrayBuffer())]}:[...new Uint8Array(value instanceof ArrayBuffer?value:value.buffer,value.byteOffset??0,value.byteLength)]}});
  await record('fetch 403 full JSON error body',async()=>{const r=await fetch(origin+'/error'),before=shape(r);return{before,value:await r.json(),after:shape(r)}});
  await record('fetch duplicate cookie ownership',async()=>{const r=await fetch(origin+'/cookies');return{shape:shape(r),cookies:r.headers.getSetCookie(),text:await r.text()}});
  await record('fetch immutable response headers',async()=>{const r=await fetch(origin+'/empty');let error;try{r.headers.append('x','blocked')}catch(e){error=errorShape(e)}return{error,text:await r.text()}});
  await record('fetch Latin1 raw headers and statusText',async()=>{const r=await fetch(origin+'/latin1');return{shape:shape(r),ownConstructor:r.headers.get('constructor'),text:await r.text()}});
  await record('fetch clone independent real body',async()=>{const a=await fetch(origin+'/json'),b=a.clone();return{before:[shape(a),shape(b)],value:await Promise.all([a.json(),b.text()]),after:[shape(a),shape(b)]}});
  const uploads=[['string','é😀'],['uint8',new Uint8Array([0,128,255])],['offset-view',new DataView(new Uint8Array([90,65,66,90]).buffer,1,2)],['params',new URLSearchParams([['a','hello world'],['a','é']])],['blob',new Blob(['owned'],{type:'text/custom'})],['empty','']];
  for(const[name,value]of uploads)await record('fetch upload '+name,async()=>{const r=await fetch(origin+'/echo?query=a%20b',{method:'POST',body:value,headers:{Authorization:'Bearer fixture','X-Custom':'owned'}});return{shape:shape(r),value:await r.json()}});
  await record('fetch genuine Request upload',async()=>{const request=new Request(origin+'/echo',{method:'POST',body:'request',headers:new Headers({'X-Custom':'request'})}),r=await fetch(request);return{requestUsed:request.bodyUsed,value:await r.json()}});
  await record('fetch supplied Headers ownership',async()=>{const headers=new Headers({'X-Custom':'before'}),promise=fetch(origin+'/echo',{headers});headers.set('X-Custom','after');return(await promise).json()});
  await record('fetch HEAD null body',async()=>{const r=await fetch(origin+'/binary',{method:'HEAD'});return{before:shape(r),text:await r.text(),after:shape(r)}});
  await record('fetch 204 null body',async()=>{const r=await fetch(origin+'/null204');return{before:shape(r),text:await r.text(),after:shape(r)}});
  await record('fetch empty 200 real body',async()=>{const r=await fetch(origin+'/empty');return{before:shape(r),text:await r.text(),after:shape(r)}});
  for(const status of [200,403])await record('fetch header before EOF '+status,async()=>{const g=gate('head'+status,status),r=await fetch(origin+'/gate?id=head'+status),atHead={sent:g.sent,finished:g.finished,shape:shape(r)};g.unblock();return{atHead,value:await r.json(),finished:g.finished}});
  await record('fetch original pre-abort reason',async()=>{const controller=new AbortController(),reason={owned:'pre'};controller.abort(reason);let caught;try{await fetch(origin+'/json',{signal:controller.signal})}catch(e){caught=e}return{sameReason:caught===reason,reason:caught}});
  await record('fetch abort before headers original reason',async()=>{const g=gate('abort-head'),controller=new AbortController(),reason={owned:'head'},promise=fetch(origin+'/abort-head?id=abort-head',{signal:controller.signal});while(!g.seen)await new Promise(resolve=>setTimeout(resolve,1));controller.abort(reason);let caught;try{await promise}catch(e){caught=e}g.unblock();return{sameReason:caught===reason,reason:caught}});
  await record('fetch abort after headers original reason',async()=>{const g=gate('abort-body'),controller=new AbortController(),reason={owned:'body'},r=await fetch(origin+'/abort-body?id=abort-body',{signal:controller.signal});controller.abort(reason);let caught;try{await r.text()}catch(e){caught=e}g.unblock();return{sameReason:caught===reason,reason:caught,shape:shape(r)}});
  for(const redirect of ['follow','manual','error'])await record('fetch redirect '+redirect,async()=>{const r=await fetch(origin+'/redirect',{redirect});return{shape:shape(r),text:await r.text()}});
  await record('fetch invalid URL',()=>fetch('/relative'));
  await record('fetch no arguments',()=>fetch());
  await record('fetch invalid GET body',()=>fetch(origin+'/json',{method:'GET',body:'invalid'}));
  await record('fetch invalid header ByteString',()=>fetch(origin+'/json',{headers:{'x':'Ā'}}));
  await record('fetch stream requires duplex',()=>fetch(origin+'/echo',{method:'POST',body:new ReadableStream({start(c){c.close()}})}));
  await record('fetch genuine duplex stream upload',async()=>{const r=await fetch(origin+'/echo',{method:'POST',duplex:'half',body:new ReadableStream({start(c){c.enqueue(new Uint8Array([65,66]));c.close()}})});return r.json()});
}finally{
  for(const value of gates.values())value.unblock();
  server.close();for(const socket of sockets)socket.destroy();await new Promise(resolve=>server.close(resolve));
}
globalThis.webFetchRows=rows;
// Keep actual Node defaults as separately observed diagnostics, never invent a
// Zig/QuickJS identity matching Node's User-Agent or peer header ordering.
globalThis.webFetchActualRequests=requests;
