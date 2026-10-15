import { writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { EventStream, AssistantMessageEventStream } from 'file:///C:/Users/adyba/pi-upstream-source-5ab7fe7-20261015/packages/ai/src/utils/event-stream.ts';

const rows=[];
const snapshot=value=>JSON.parse(JSON.stringify(value));
async function observe(name,run){const trace=[];await run(trace);rows.push({name,trace});}
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b});return {promise,resolve,reject};};
const result=(trace,label,promise)=>promise.then(value=>{trace.push([label,snapshot(value)]);return value},error=>{trace.push([label,'rejected',error?.message??String(error)]);throw error});

await observe('actual-generator-brand-and-method-metadata',async trace=>{
 const fn=async function* body(){yield 1};const it=fn();const p=Object.getPrototypeOf(it),intrinsic=Object.getPrototypeOf(p);
 trace.push({brand:Object.prototype.toString.call(it),functionBrand:Object.prototype.toString.call(fn),ownPrototype:Object.hasOwn(fn,'prototype'),ownPrototypeKeys:Reflect.ownKeys(p).map(String),intrinsicKeys:Reflect.ownKeys(intrinsic).map(String),nextName:intrinsic.next.name,nextLength:intrinsic.next.length,methodName:EventStream.prototype[Symbol.asyncIterator].name,methodLength:EventStream.prototype[Symbol.asyncIterator].length,methodOwnPrototype:Object.hasOwn(EventStream.prototype[Symbol.asyncIterator],'prototype'),self:it[Symbol.asyncIterator]()===it});
 let seen;try{await intrinsic.next.call({})}catch(error){seen=error}trace.push({invalidBrand:seen instanceof TypeError});
 assert.equal((await intrinsic.next.call(it)).value,1);
});
await observe('raw-yield-and-return-identity',async trace=>{
 const root={},final={};const it=(async function*(){yield root;return Promise.resolve(final)})();const a=await it.next(),b=await it.next();trace.push({yieldRaw:a.value===root,yieldDone:a.done,returnRaw:b.value===final,returnDone:b.done});
});
await observe('cross-realm-body-result-and-completed-result',async trace=>{
 const a=vm.createContext({}),b=vm.createContext({});vm.runInContext('globalThis.root={};globalThis.it=(async function*(){yield root})()',a);const next=vm.runInContext('Object.getPrototypeOf(Object.getPrototypeOf((async function*(){})())).next',b),promisePrototypeB=vm.runInContext('Promise.prototype',b),objectPrototypeA=vm.runInContext('Object.prototype',a),objectPrototypeB=vm.runInContext('Object.prototype',b);const pending=next.call(a.it);const first=await pending,returned=await next.call(a.it),completed=await next.call(a.it);trace.push({promiseB:Object.getPrototypeOf(pending)===promisePrototypeB,rawA:first.value===a.root,yieldResultA:Object.getPrototypeOf(first)===objectPrototypeA,returnResultA:Object.getPrototypeOf(returned)===objectPrototypeA,completedResultB:Object.getPrototypeOf(completed)===objectPrototypeB});
});
await observe('queued-next-yield-await',async trace=>{
 const gate=deferred();const it=(async function*(){trace.push('start');yield gate.promise;trace.push('resumed');return 'final'})();const a=result(trace,'first',it.next()),b=result(trace,'second',it.next());trace.push('queued');queueMicrotask(()=>trace.push('producer-before-release'));gate.resolve('root');trace.push('released');await Promise.all([a,b]);
});
await observe('active-yield-queued-return-await',async trace=>{
 const gate=deferred();const it=(async function*(){try{yield gate.promise}finally{trace.push('finally')}})();const a=result(trace,'first',it.next()),b=result(trace,'returned',it.return({then(resolve){trace.push('return-then');resolve('final')}}));trace.push('queued-return');gate.resolve('root');await Promise.all([a,b]);
});
await observe('completed-return-drains-queued-next-and-throw',async trace=>{
 const gate=deferred(),reason={tag:'raw'};const it=(async function*(){trace.push('body-must-not-run')})();const a=result(trace,'return',it.return(gate.promise)),b=result(trace,'next-one',it.next()),c=result(trace,'next-two',it.next()),d=it.throw(reason).then(()=>trace.push('unexpected'),error=>trace.push(['throwRaw',error===reason]));trace.push('queued');gate.resolve('final');await Promise.all([a,b,c,d]);
});
await observe('suspended-start-abrupt-does-not-enter-body',async trace=>{
 const calls=[],root={},reason={};const one=(async function*(){calls.push('body');yield 1})();const a=await one.return(root);const two=(async function*(){calls.push('body');yield 1})();let seen;try{await two.throw(reason)}catch(error){seen=error}trace.push({calls,returned:a.value===root,done:a.done,throwRaw:seen===reason,terminal:(await two.next()).done});
});
await observe('yield-throwing-then-getter-caught-at-suspension',async trace=>{
 const reason={};const poison={get then(){trace.push('get-then');throw reason}};const it=(async function*(){try{yield poison}catch(error){trace.push(['caughtRaw',error===reason]);yield 'caught'}finally{trace.push('finally')}})();await result(trace,'first',it.next());await result(trace,'second',it.next());
});
await observe('explicit-await-throwing-then-getter',async trace=>{
 const reason={},poison={get then(){trace.push('get-then');throw reason}};const it=(async function*(){try{await poison}catch(error){trace.push(['caughtRaw',error===reason]);yield 'caught'}})();await result(trace,'first',it.next());await result(trace,'second',it.next());
});
await observe('poisoned-promise-constructor-raw-rejection',async trace=>{
 const reason={},promise=Promise.resolve('value');Object.defineProperty(promise,'constructor',{get(){trace.push('get-constructor');throw reason}});const it=(async function*(){await promise;yield 'unexpected'})();try{await it.next()}catch(error){trace.push(['raw',error===reason])}trace.push(await it.next());
});
await observe('return-expression-await-precedes-finally',async trace=>{
 const gate=deferred();const it=(async function*(){try{yield 'first';return gate.promise}finally{trace.push('finally')}})();await result(trace,'first',it.next());const second=result(trace,'second',it.next());trace.push('return-pending');gate.resolve('final');await second;
});
await observe('external-return-input-await-precedes-finally',async trace=>{
 const gate=deferred();const it=(async function*(){try{yield 'first'}finally{trace.push('finally')}})();await result(trace,'first',it.next());const returned=result(trace,'returned',it.return(gate.promise));trace.push('return-pending');gate.resolve('final');await returned;
});
await observe('throw-after-yield-closes-raw',async trace=>{
 const reason={};const it=(async function*(){try{yield 'first'}finally{trace.push('finally')}})();await result(trace,'first',it.next());try{await it.throw(reason)}catch(error){trace.push(['raw',error===reason])}await result(trace,'terminal',it.next());
});
await observe('nested-async-generator-await-and-yield-boundaries',async trace=>{
 const shared={stage:'initial'};async function* inner(){trace.push('inner-start');yield shared;shared.stage='inner-final';trace.push('inner-final')};async function* outer(){for await(const value of inner()){trace.push(['outer',snapshot(value)]);yield value;trace.push('outer-resume')}};const it=outer();const first=result(trace,'consumer',it.next());queueMicrotask(()=>{shared.stage='producer-microtask';trace.push('producer-microtask')});await first;await result(trace,'terminal',it.next());
});
await observe('eventstream-queued-mutated-object-retains-identity',async trace=>{
 const stream=new EventStream(()=>false,x=>x),shared={stage:'push'};stream.push(shared);const it=stream[Symbol.asyncIterator](),pending=it.next().then(value=>{trace.push(['consumer',snapshot(value),value.value===shared]);return value});shared.stage='after-next';queueMicrotask(()=>{shared.stage='producer-microtask';trace.push('producer-microtask')});await pending;stream.end('final');await result(trace,'terminal',it.next());trace.push(['result',await stream.result()]);
});
await observe('eventstream-waiter-mutated-object-retains-identity',async trace=>{
 const stream=new EventStream(()=>false,x=>x),shared={stage:'push'},it=stream[Symbol.asyncIterator]();const pending=it.next().then(value=>{trace.push(['consumer',snapshot(value),value.value===shared]);return value});stream.push(shared);shared.stage='after-push';queueMicrotask(()=>{shared.stage='producer-microtask';trace.push('producer-microtask')});await pending;stream.end();await result(trace,'terminal',it.next());
});
await observe('eventstream-pending-return-queues-until-producer-close',async trace=>{
 const stream=new EventStream(()=>false,x=>x),it=stream[Symbol.asyncIterator]();const a=result(trace,'next',it.next()),b=result(trace,'return',it.return('return-value'));trace.push('queued-return');stream.end('final');trace.push('producer-closed');await Promise.all([a,b]);trace.push(['result',await stream.result()]);
});
await observe('eventstream-pending-throw-queues-until-producer-push',async trace=>{
 const reason={},stream=new EventStream(()=>false,x=>x),it=stream[Symbol.asyncIterator]();const a=result(trace,'next',it.next()),b=it.throw(reason).then(()=>trace.push('unexpected'),error=>trace.push(['throwRaw',error===reason]));trace.push('queued-throw');stream.push('value');await Promise.all([a,b]);stream.end();await result(trace,'terminal',it.next());
});
await observe('eventstream-two-iterators-compete-in-fifo-order',async trace=>{
 const stream=new EventStream(()=>false,x=>x),a=stream[Symbol.asyncIterator](),b=stream[Symbol.asyncIterator]();const first=result(trace,'first',a.next()),second=result(trace,'second',b.next());stream.push('a');stream.push('b');await Promise.all([first,second]);stream.end();await Promise.all([result(trace,'end-a',a.next()),result(trace,'end-b',b.next())]);
});
await observe('assistant-shared-partial-duration-and-callback-boundaries',async trace=>{
 const stream=new AssistantMessageEventStream(),message={role:'assistant',content:[],timestamp:5000000000000},it=stream[Symbol.asyncIterator]();const snapshotEvent=event=>{const copy=snapshot(event);if(copy.value?.partial?.durationMs!==undefined)copy.value.partial.durationMs='<measured>';if(copy.value?.message?.durationMs!==undefined)copy.value.message.durationMs='<measured>';return copy};
 const consumer=(async()=>{for await(const event of {[Symbol.asyncIterator]:()=>it})trace.push(['consumer',snapshotEvent({value:event,done:false}),event.partial===message||event.message===message])})();
 stream.push({type:'text_start',partial:message});trace.push(['after-push',Object.hasOwn(message,'durationMs')]);await Promise.resolve();message.content.push({type:'text',text:'one'});stream.push({type:'text_delta',delta:'one',partial:message});await Promise.resolve();stream.push({type:'text_end',partial:message});await Promise.resolve();stream.push({type:'done',message});await consumer;trace.push(['resultRaw',await stream.result()===message]);
});
const output={sourceHead:'5ab7fe74c400097b386662205cd93900695b8a71',runtime:process.version,count:rows.length,rows};
assert.equal(rows.length,20);
writeFileSync(process.argv[2],JSON.stringify(output,null,2)+'\n');
console.log(JSON.stringify({status:'passed',count:rows.length,output:process.argv[2]}));
