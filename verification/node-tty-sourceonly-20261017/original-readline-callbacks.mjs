// Actual Node24.14 calls, prepared/unrun. No fd, console, child or expected data.
import readline from 'node:readline';
import tty from 'node:tty';
import util from 'node:util';
const rows=[];
const describe=e=>({name:e.name,code:e.code,message:e.message});
function record(name,body){try{rows.push({name,value:body()})}catch(e){rows.push({name,error:describe(e)})}}
record('four-function-metadata',()=>Object.fromEntries(['cursorTo','moveCursor','clearLine','clearScreenDown'].map(k=>[k,{name:readline[k].name,length:readline[k].length,prototype:Object.hasOwn(readline[k],'prototype')}])));
function writeSubject(trace){const stream={};Object.defineProperty(stream,'write',{get(){trace.push('write getter');return function(...args){trace.push({write:args[0],callback:typeof args[1],same:this===stream,argc:args.length});return false}}});return stream}
for(const [name,args] of [
 ['cursorTo',[0]],['cursorTo',[3,4]],['cursorTo',[Infinity,-Infinity]],
 ['cursorTo',['3',4]],['cursorTo',[NaN,undefined]],['cursorTo',[0,NaN]],
 ['cursorTo',[null,null]],['cursorTo',[3,()=>{}]],
 ['moveCursor',[0,0]],['moveCursor',[-2,3]],['moveCursor',[2n,-3n]],
 ['moveCursor',[NaN,0]],['moveCursor',[Symbol('dx'),0]],
 ['clearLine',[-1]],['clearLine',[1]],['clearLine',[0]],['clearLine',[undefined]],['clearLine',[NaN]],['clearLine',[Symbol('dir')]],
 ['clearScreenDown',[]],
])record(`${name}:${args.map(x=>String(x)).join(',')}`,()=>{const trace=[];const stream=writeSubject(trace);return{returned:readline[name](stream,...args),trace}});
record('positive-relative-direction-preserves-number-then-default-coercion',()=>{
 const trace=[];const stream=writeSubject(trace);const dx={[Symbol.toPrimitive](hint){trace.push(['dx',hint]);return hint==='default'?'different':2}};
 return{returned:readline.moveCursor(stream,dx,0),trace};
});
record('negative-relative-direction-recoerces-for-unary-minus',()=>{
 const trace=[];const stream=writeSubject(trace);let n=0;const dx={[Symbol.toPrimitive](hint){trace.push([hint,++n]);return n===1?-1:-3n}};
 return{returned:readline.moveCursor(stream,dx,0),trace};
});
record('clear-direction-comparisons-reread-coercion',()=>{
 const trace=[];const stream=writeSubject(trace);let n=0;const dir={[Symbol.toPrimitive](hint){trace.push([hint,++n]);return n===1?0:1}};
 return{returned:readline.clearLine(stream,dir),trace};
});
for(const value of [null,false,'bad',1,{},Symbol('callback')]){
 record(`callback:${String(value)}`,()=>readline.cursorTo(null,NaN,()=>{},value));
}
record('cursor-position-error-is-registered-TypeError',()=>{try{readline.cursorTo(writeSubject([]),'x',2)}catch(e){return{...describe(e),base:e instanceof TypeError,ownCode:Object.getOwnPropertyDescriptor(e,'code'),parentConstructor:Object.getPrototypeOf(e).constructor.name}}});
record('TTY-readline-util-share-actual-invalid-argument-class',()=>{
 const errors=[];for(const call of [()=>tty.WriteStream.prototype.hasColors('bad',{FORCE_COLOR:'3'}),()=>readline.clearLine(null,0,'bad'),()=>util.getSystemErrorName('bad')]){try{call()}catch(e){errors.push(e)}}
 return{count:errors.length,same:errors.every(e=>Object.getPrototypeOf(e)===Object.getPrototypeOf(errors[0])),codes:errors.map(e=>e.code)};
});
record('validator-errors-preserve-Hide-subclass-over-registered-base',()=>{
 const errors=[];for(const call of [()=>tty.WriteStream.prototype.hasColors('bad',{FORCE_COLOR:'3'}),()=>readline.clearLine(null,0,'bad'),()=>util.getSystemErrorName('bad')]){try{call()}catch(e){errors.push(e)}}
 return errors.map(e=>{const hidden=Object.getPrototypeOf(e),base=Object.getPrototypeOf(hidden);return{hiddenOwnConstructor:typeof Object.getOwnPropertyDescriptor(hidden,'constructor')?.get,baseOwnConstructor:typeof Object.getOwnPropertyDescriptor(base,'constructor')?.get,typeErrorParent:Object.getPrototypeOf(base)===TypeError.prototype,currentConstructor:e.constructor===TypeError}});
});
record('TTY-validator-range-Hide-versus-util-direct-base-range',()=>{
 let ttyError,utilError;try{tty.WriteStream.prototype.hasColors(1,{FORCE_COLOR:'3'})}catch(e){ttyError=e}try{util.getSystemErrorName(0)}catch(e){utilError=e}
 return{different:Object.getPrototypeOf(ttyError)!==Object.getPrototypeOf(utilError),sameBase:Object.getPrototypeOf(Object.getPrototypeOf(ttyError))===Object.getPrototypeOf(utilError),constructors:[ttyError.constructor===RangeError,utilError.constructor===RangeError]};
});
record('actual-Hide-constructor-live-stack-limit-window',()=>{
 const before=Object.getOwnPropertyDescriptor(Error,'stackTraceLimit');const trace=[];let limit=10;
 Object.defineProperty(Error,'stackTraceLimit',{configurable:true,get(){trace.push(['get',limit]);return limit},set(value){trace.push(['set',value]);limit=value}});
 const callback={get constructor(){trace.push(['callback constructor',limit]);return Object}};
 try{try{readline.clearLine(null,0,callback)}catch(e){return{trace,limit,error:describe(e),hiddenOwnConstructor:typeof Object.getOwnPropertyDescriptor(Object.getPrototypeOf(e),'constructor')?.get}}}
 finally{if(before)Object.defineProperty(Error,'stackTraceLimit',before);else delete Error.stackTraceLimit}
});
record('throwing-Hide-super-does-not-finally-restore-limit',()=>{
 const before=Object.getOwnPropertyDescriptor(Error,'stackTraceLimit');Object.defineProperty(Error,'stackTraceLimit',{configurable:true,writable:true,value:10});const reason={};
 const callback={get constructor(){throw reason}};
 try{try{readline.clearLine(null,0,callback)}catch(e){return{same:e===reason,limit:Error.stackTraceLimit}}}
 finally{if(before)Object.defineProperty(Error,'stackTraceLimit',before);else delete Error.stackTraceLimit}
});
record('write-getter-exact-reason-after-direction-coercion',()=>{
 const trace=[];const reason={};const stream={get write(){trace.push('write');throw reason}};const dx={valueOf(){trace.push('coerce');return 1}};
 try{readline.moveCursor(stream,dx,0)}catch(e){return{same:e===reason,trace}}
});
record('TTY-four-methods-delegate-real-readline',()=>{
 const trace=[];const stream=writeSubject(trace);const p=tty.WriteStream.prototype;
 return {values:[p.cursorTo.call(stream,2,3),p.moveCursor.call(stream,-1,2),p.clearLine.call(stream,1),p.clearScreenDown.call(stream)],trace};
});
record('TTY-cached-module-still-selects-live-export',()=>{
 const p=tty.WriteStream.prototype;const stream=writeSubject([]);p.cursorTo.call(stream,1);
 const descriptor=Object.getOwnPropertyDescriptor(readline,'cursorTo');const trace=[];const reason={};
 Object.defineProperty(readline,'cursorTo',{configurable:true,get(){trace.push('live cursorTo');return function(...args){trace.push({same:this===readline,stream:args[0]===stream,args:args.slice(1)});throw reason}}});
 try{try{p.cursorTo.call(stream,2,3)}catch(e){return{same:e===reason,trace}}}finally{Object.defineProperty(readline,'cursorTo',descriptor)}
});
const ticks=[];const cb=(...args)=>ticks.push({callback:true,args});
ticks.push('before');
const noopReturns=[readline.cursorTo(null,Symbol('x'),undefined,cb),readline.moveCursor(undefined,Symbol('dx'),0,cb),readline.clearLine(null,Symbol('dir'),cb),readline.clearScreenDown(null,cb)];
ticks.push('after');
await new Promise(resolve=>process.nextTick(resolve));
rows.push({name:'actual-nextTick-only-noop-branches',value:{returns:noopReturns,ticks}});
process.stdout.write(JSON.stringify(rows,(_key,value)=>typeof value==='bigint'?`${value}n`:typeof value==='symbol'?String(value):value)+'\n');
