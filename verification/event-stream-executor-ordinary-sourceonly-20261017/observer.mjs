// Additive original observation; original13 observer/reference stay immutable.
export async function observeWaitingExecutorReturn(EventStream){
 const original=globalThis.Promise,marker={owned:'enqueue-return'},trace=[];
 const stream=new EventStream(()=>false,value=>value);
 stream.waiting={enqueue(resolve){trace.push('enqueue:'+String(this===stream.waiting));resolve({value:'owned',done:false});return marker}};
 try{
  globalThis.Promise=class extends original{constructor(executor){super(resolve=>{const value=executor(resolve);trace.push('executor-return:'+String(value===marker))})}};
  const value=await stream[Symbol.asyncIterator]().next();
  return{authority:'actual-Pi1.3-8efd-waiting-executor-return',trace,value};
 }finally{globalThis.Promise=original}
}
