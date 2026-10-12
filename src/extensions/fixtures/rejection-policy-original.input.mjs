// Shared caller input for genuine Node and native C ABI replay. No replacement
// promise, event-loop, emitter or default fatal policy implementation is here.
export async function startCase(id, log) {
  let reason=new Error('original-rejection-'+id),promise,second,primitiveCalls=0,stackReads=0,ownChecks=0;
  const other=new Error('listener-original-throw');
  if(id==='raw-string')reason='plain-original-rejection';
  if(id==='raw-symbol')reason=Symbol('original-symbol-rejection');
  if(id==='raw-object')reason={original:true};
  if(id==='own-stack-object')reason=Object.defineProperty({},'stack',{get(){stackReads++;return'owned-stack'}});
  if(id==='function-own-stack')reason=Object.assign(function namedReason(){},{stack:'function-stack'});
  if(id==='proxy-own-stack')reason=new Proxy({stack:'proxy-stack'},{getOwnPropertyDescriptor(target,key){if(key==='stack')ownChecks++;return Reflect.getOwnPropertyDescriptor(target,key)}});
  if(id==='object-no-coercion')reason={[Symbol.toPrimitive](){primitiveCalls++;throw Error('guest coercion forbidden')}};
  process.on('uncaughtExceptionMonitor',(error,origin)=>log({phase:'fatal',origin,original:error===reason,other:error===other,name:error?.name,code:error?.code,message:error?.message,primitiveCalls,stackReads,ownChecks}));
  process.on('rejectionHandled',p=>log({phase:'handled',first:p===promise,second:p===second}));
  if(id==='dynamic-emit'){const emit=process.emit;process.emit=function(name,...args){if(name==='unhandledRejection')log({phase:'emit',receiver:this===process,original:args[0]===reason,promise:args[1]===promise});return Reflect.apply(emit,this,[name,...args])}}
  if(['listener-handles','listener-late-catch','listener-microtask-catch','listener-throws','listener-catches-sibling'].includes(id))process.on('unhandledRejection',(value,p)=>{log({phase:'unhandled',original:value===reason,first:p===promise,second:p===second});if(id==='listener-late-catch')p.catch(()=>log({phase:'catch'}));if(id==='listener-microtask-catch')queueMicrotask(()=>p.catch(()=>log({phase:'catch'})));if(id==='listener-throws')throw other;if(id==='listener-catches-sibling'&&p===promise)second.catch(()=>log({phase:'second-catch'}))});
  log({phase:'start',id,unhandledListeners:process.listenerCount('unhandledRejection'),uncaughtListeners:process.listenerCount('uncaughtException')});
  promise=Promise.reject(reason);
  switch(id){
    case'same-turn-catch':promise.catch(value=>log({phase:'caught',original:value===reason}));break;
    case'microtask-catch':queueMicrotask(()=>promise.catch(value=>log({phase:'caught',original:value===reason})));break;
    case'later-timer-catch':setTimeout(()=>{log({phase:'attach-late-handler'});promise.catch(value=>log({phase:'caught',original:value===reason}))},10);break;
    case'same-reason-distinct-promises':second=Promise.reject(reason);break;
    case'handled-parent-unhandled-child':promise.then();break;
    case'await-consumes-rejection':try{await promise}catch(value){log({phase:'caught',original:value===reason})}break;
    case'listener-catches-sibling':second=Promise.reject(reason);break;
  }
  setTimeout(()=>log({phase:'completed-turn',primitiveCalls,stackReads,ownChecks}),20);
}