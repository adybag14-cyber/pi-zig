// Exact-source differential observers. Clock and timer functions are explicit
// guest inputs; neither observer supplies a production implementation.
export async function observeDevicePoll(poll, mode) {
  const NativePromise=Promise, NativeError=Error, NativeNumber=Number, NativeMath=Math;
  const keys=["Date","Math","Number","Error","Promise","setTimeout","clearTimeout"];
  const saved=keys.map(key=>[key,Object.getOwnPropertyDescriptor(globalThis,key)]);
  const trace=[], timers=[], original={kind:"poll rejection"}, value={kind:"completed"};
  let now=0, calls=0, settled=false, result, failure, statusReads=0;
  const signal={
    get aborted(){trace.push("signal.aborted");return mode==="aborted"},
    addEventListener(name,handler,options){trace.push("signal.add:"+name+":"+options.once);this.handler=handler},
    removeEventListener(name,handler){trace.push("signal.remove:"+name+":"+(handler===this.handler));this.handler=undefined}
  };
  const math={};
  for(const name of ["max","min","floor"])Object.defineProperty(math,name,{get(){
    trace.push("Math."+name+":get");
    return function(...args){trace.push("Math."+name+":call:"+args.join(","));return Reflect.apply(NativeMath[name],NativeMath,args)};
  }});
  const date={get now(){trace.push("Date.now:get");return function(){trace.push("Date.now:call:"+now);return now}}};
  const number={get POSITIVE_INFINITY(){trace.push("Number.infinity");return Infinity},get isFinite(){
    trace.push("Number.isFinite:get");return function(value){trace.push("Number.isFinite:call:"+value);return NativeNumber.isFinite(value)};
  }};
  const define=(key,value)=>Object.defineProperty(globalThis,key,{configurable:true,writable:true,value});
  const response=(status,extra={})=>Object.defineProperties(extra,{status:{get(){trace.push("result.status:"+status);return status}}});
  function nextResponse(){
    if(mode==="reject")return NativePromise.reject(original);
    if(mode==="poll-thenable")return {get then(){trace.push("poll.then:get");return function(resolve){trace.push("poll.then:call");resolve(response("complete",{value}))}}};
    if(mode==="failed")return response("failed",Object.defineProperty({},"message",{get(){trace.push("result.message");return "server rejected"}}));
    if(mode==="status-sequence")return Object.defineProperties({message:"sequence rejected"},{status:{get(){const status=["other","failed"][statusReads++];trace.push("result.status:"+status);return status}}});
    if(calls===1&&["pending","wait-first","slow-increment","slow-server","slow-infinite","slow-timeout"].includes(mode)){
      const status=mode.startsWith("slow-")?"slow_down":"pending";
      const out=response(status);
      if(status==="slow_down")Object.defineProperty(out,"intervalSeconds",{get(){trace.push("result.interval");return mode==="slow-server"?2.75:mode==="slow-infinite"?Infinity:undefined}});
      if(mode==="slow-timeout")now=5000;
      return out;
    }
    return response("complete",Object.defineProperty({},"value",{get(){
      trace.push("result.value");
      if(mode==="tail-thenable")return {get then(){trace.push("tail.then:get");return function(resolve){trace.push("tail.then:call");resolve(value)}}};
      return value;
    }}));
  }
  const options={
    get expiresInSeconds(){trace.push("options.expires");return mode==="timeout"?0:mode==="slow-timeout"?1:mode==="finite"?3:undefined},
    get intervalSeconds(){trace.push("options.interval");return mode==="pending"?.2:undefined},
    get waitBeforeFirstPoll(){trace.push("options.wait");return mode==="wait-first"},
    get signal(){trace.push("options.signal");return signal},
    get poll(){trace.push("options.poll:get");return function(){trace.push("options.poll:call:"+(this===options));calls++;return nextResponse()}}
  };
  try {
    define("Date",date);define("Math",math);define("Number",number);
    define("Error",function ObservedError(message){trace.push("Error:construct:"+message);return new NativeError(message)});
    define("setTimeout",function(callback,delay){trace.push("timer:set:"+delay);const timer={callback,delay};timers.push(timer);return timer});
    define("clearTimeout",function(timer){trace.push("timer:clear");const index=timers.indexOf(timer);if(index>=0)timers.splice(index,1)});
    if(mode==="intrinsic-promise")define("Promise",function(){throw original});
    let promise;
    try{promise=poll(options);trace.push("caller:return")}catch(error){return {synchronous:true,same:error===original,trace}}
    const intrinsic=promise.constructor===NativePromise;
    promise.then(v=>{result=v;settled=true;trace.push("caller:fulfilled")},e=>{failure=e;settled=true;trace.push("caller:rejected")});
    NativePromise.resolve().then(()=>trace.push("caller:microtask"));
    for(let index=0;!settled&&index<100;index++){
      await NativePromise.resolve();
      if(timers.length){const timer=timers.shift();now+=timer.delay;trace.push("timer:fire:"+now);timer.callback()}
    }
    if(!settled)throw new NativeError("Device poll did not settle under bounded actual timer inputs");
    return {synchronous:false,intrinsic,calls,outcome:failure?{kind:"rejected",same:failure===original,message:failure===original?null:failure.message}:{kind:"fulfilled",same:result===value},trace};
  } finally {
    for(const [key,descriptor]of saved)descriptor?Object.defineProperty(globalThis,key,descriptor):delete globalThis[key];
  }
}
export async function compareDevicePoll(native,source,modes){
  const rows=[];
  for(const mode of modes){
    const expected=await observeDevicePoll(source,mode),actual=await observeDevicePoll(native,mode);
    if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({mode,expected,actual}));
    rows.push({mode,...actual});
  }
  return rows;
}
export async function observeDeviceSleep(sleep,mode){
  const NativePromise=Promise,NativeError=Error;
  const keys=["Promise","Error","setTimeout","clearTimeout"];
  const saved=keys.map(key=>[key,Object.getOwnPropertyDescriptor(globalThis,key)]);
  const trace=[],token={},handle={},original={kind:"original"};
  let elapsed,onAbort,result,failed,executor;
  const signal={
    get aborted(){trace.push("aborted");return mode==="already-aborted"},
    get addEventListener(){trace.push("add:get");return function(name,callback,options){
      trace.push("add:call:"+name+":"+options.once+":"+(this===signal));onAbort=callback;
      if(mode==="abort-register")callback();
    }},
    get removeEventListener(){trace.push("remove:get");return function(name,callback){
      trace.push("remove:call:"+name+":"+(callback===onAbort)+":"+(this===signal));
      if(mode==="tdz")callback();
    }}
  };
  const define=(key,value)=>Object.defineProperty(globalThis,key,{configurable:true,writable:true,value});
  try{
    define("Error",function(message){trace.push("Error:"+message);return new NativeError(message)});
    Object.defineProperty(globalThis,"clearTimeout",{configurable:true,get(){trace.push("clear:get");return function(value){trace.push("clear:call:"+(value===handle))}}});
    define("setTimeout",function(callback,delay){
      trace.push("timer:set:"+delay);elapsed=callback;
      if(mode==="tdz")callback();
      return handle;
    });
    if(mode==="live-constructor")define("Promise",function(callback){
      trace.push("Promise:construct");executor=callback;
      callback(v=>trace.push("resolve:"+v),e=>trace.push("reject:"+e.message));
      return token;
    });
    else if(mode==="constructor-throws")define("Promise",function(){throw original});
    try{result=mode==="constructible"?new sleep(7,signal,"cancel selected"):sleep(7,signal,"cancel selected");trace.push("caller:return")}
    catch(error){failed=error;trace.push("caller:throw")}
    if(mode==="live-constructor"){
      trace.push("executor:"+executor.name+":"+executor.length+":"+("prototype"in executor));
      elapsed();
      return {token:result===token,trace};
    }
    if(failed)return {synchronous:true,same:failed===original,trace};
    if(mode==="elapsed"||mode==="constructible")elapsed();
    try{await result;trace.push("fulfilled");return {synchronous:false,trace}}
    catch(error){trace.push("rejected");return {synchronous:false,message:error.message,trace}}
  }finally{
    for(const [key,descriptor]of saved)descriptor?Object.defineProperty(globalThis,key,descriptor):delete globalThis[key];
  }
}
export async function compareDeviceSleep(native,source,modes){
  const rows=[];
  for(const mode of modes){
    const expected=await observeDeviceSleep(source,mode),actual=await observeDeviceSleep(native,mode);
    if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({mode,expected,actual}));
    rows.push({mode,...actual});
  }
  return rows;
}
