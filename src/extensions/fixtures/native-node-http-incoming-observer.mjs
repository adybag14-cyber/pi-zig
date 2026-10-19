// Shared actual Node IncomingMessage body controls. The production owner and
// unchanged pinned Source consume the same real Stream and explicit import seam.
function incomingAssert(value,message){if(!value)throw new Error(message);}
function incomingEqual(a,b,message){incomingAssert(JSON.stringify(a)===JSON.stringify(b),message+": "+JSON.stringify(a));}
function incomingThrown(call){try{call();}catch(error){return error;}throw new Error("expected ordinary throw");}
function incomingSymbol(value,name){const key=Object.getOwnPropertySymbols(value).find(x=>x.description===name);incomingAssert(key,"missing actual private "+name);return key;}
function incomingTicks(run){
  const process=globalThis.process, descriptor=Object.getOwnPropertyDescriptor(process,"nextTick"), calls=[];
  Object.defineProperty(process,"nextTick",{configurable:true,writable:true,value:function(...args){incomingAssert(this===process,"actual nextTick receiver");calls.push(args);}});
  try{return run(calls);}finally{Object.defineProperty(process,"nextTick",descriptor);}
}
function observeIncomingShape(api,streams){
  const C=api.IncomingMessage, proto=C.prototype, value=new C(null);
  incomingAssert(C.name==="IncomingMessage"&&C.length===1,"actual constructor metadata");
  incomingAssert(Object.getPrototypeOf(C)===streams.Readable&&Object.getPrototypeOf(proto)===streams.Readable.prototype,"same genuine Readable inheritance");
  incomingAssert(value instanceof C&&value instanceof streams.Readable,"actual stream receiver");
  for(const name of ["connection","headers","headersDistinct","trailers","trailersDistinct"]){
    const d=Object.getOwnPropertyDescriptor(proto,name);
    incomingAssert(!d.enumerable&&!d.configurable&&d.get.length===0&&d.set.length===1,"actual accessor flags "+name);
    incomingAssert(Object.hasOwn(d.get,"prototype")&&Object.hasOwn(d.set,"prototype"),"ordinary accessor function expressions "+name);
  }
  for(const [name,arity] of [["setTimeout",2],["_read",1],["_destroy",2],["_addHeaderLines",2],["_addHeaderLine",3],["_addHeaderLineDistinct",3],["_dumpAndCloseReadable",0],["_dump",0]]){
    const d=Object.getOwnPropertyDescriptor(proto,name);
    incomingAssert(d.enumerable&&d.writable&&d.configurable&&d.value.name===name&&d.value.length===arity&&Object.hasOwn(d.value,"prototype"),"ordinary assigned method "+name);
  }
  incomingAssert(value.socket===null&&value.client===null&&value.httpVersion===null&&value.httpVersionMajor===null&&value.httpVersionMinor===null,"socket and version fields");
  incomingAssert(value.complete===false&&value.aborted===false&&value.upgrade===null&&value.url===""&&value.method===null&&value.statusCode===null&&value.statusMessage===null,"request/response fields");
  incomingAssert(value._consuming===false&&value._dumped===false&&value.joinDuplicateHeaders===false,"initial source flags");
  const incomingNames=["kHeaders","kHeadersDistinct","kHeadersCount","kTrailers","kTrailersDistinct","kTrailersCount"];
  incomingEqual(Object.getOwnPropertySymbols(value).map(s=>s.description).filter(name=>incomingNames.includes(name)),["kHeaders","kHeadersCount","kTrailers","kTrailersCount"],"actual four initial Incoming slots alongside genuine Stream symbols");
  incomingAssert(api.readStart.length===1&&api.readStop.length===1,"actual read helper arities");
}
function observeIncomingConstructor(api,streams){
  const trace=[], readable=streams.Readable, own=Object.getOwnPropertyDescriptor(readable,"call");
  Object.defineProperty(readable,"call",{configurable:true,get(){trace.push("get:call");return function(self,options){incomingAssert(this===readable,"Readable.call receiver");trace.push(["call",options.highWaterMark]);self._readableState={};};}});
  try{
    const socket={get readableHighWaterMark(){trace.push("hwm");return 37;}};
    const value=new api.IncomingMessage(socket);
    incomingEqual(trace,["hwm","get:call",["call",37]],"options before live Readable.call");
    incomingAssert(value.socket===socket&&value.client===socket&&value._readableState.readingMore===true,"real constructor assignments");
  }finally{if(own)Object.defineProperty(readable,"call",own);else delete readable.call;}
}
function observeIncomingHeaders(api){
  const value=new api.IncomingMessage(null);
  const raw=["Host","first","host","second","Cookie","a","cookie","b","Set-Cookie","one","set-cookie","two","X-One","a","x-one","b","Connection","keep-alive"];
  value._addHeaderLines(raw,raw.length);
  const headers=value.headers;
  incomingEqual(headers,{host:"first",cookie:"a; b","set-cookie":["one","two"],"x-one":"a, b",connection:"keep-alive"},"real known and duplicate headers");
  incomingAssert(value.rawHeaders===raw&&value.headers===headers,"lazy same header owner");
  value.joinDuplicateHeaders=true;
  value._addHeaderLine("HOST","third",headers);
  incomingAssert(headers.host==="first, third","actual joinDuplicateHeaders branch");
  value.headers={custom:"assigned"};
  incomingEqual(value.headers,{custom:"assigned"},"public setter uses same private slot");
}
function observeIncomingDistinct(api){
  const value=new api.IncomingMessage(null);
  value._addHeaderLines(["Host","a","host","b","Set-Cookie","c"],6);
  incomingEqual(value.headersDistinct,{host:["a","b"],"set-cookie":["c"]},"actual distinct arrays");
  value.complete=true;
  const raw=["X-Trailer","one","x-trailer","two"];
  value._addHeaderLines(raw,4);
  incomingAssert(value.rawTrailers===raw,"real trailer array retained");
  incomingEqual(value.trailers,{"x-trailer":"one, two"},"actual lazy trailers");
  incomingEqual(value.trailersDistinct,{"x-trailer":["one","two"]},"actual distinct trailers");
}
function observeIncomingKnownFields(api){
  const proto=String.prototype, saved=Object.getOwnPropertyDescriptor(proto,"toLowerCase"), trace=[];
  Object.defineProperty(proto,"toLowerCase",{configurable:true,get(){trace.push(["lower:get",String(this)]);return function(){trace.push(["lower:call",String(this)]);return Reflect.apply(saved.value,this,[]);};}});
  try{
    const dst={}, fn=api.IncomingMessage.prototype._addHeaderLine;
    fn.call({}, "Content-Type","a",dst);
    incomingEqual(trace,[],"traditional casing skips lower method");
    fn.call({}, "CONTENT-TYPE","b",dst);
    incomingEqual(trace,[["lower:get","CONTENT-TYPE"],["lower:call","CONTENT-TYPE"]],"one genuine lowercase recursion");
    incomingAssert(dst["content-type"]==="a","no duplicate singleton");
    fn.call({}, "X-Custom","c",dst);
    incomingAssert(dst["x-custom"]==="c","unknown field real fallback");
  }finally{Object.defineProperty(proto,"toLowerCase",saved);}
}
function observeIncomingDynamicKeys(api){
  const trace=[], key={ [Symbol.toPrimitive](hint){trace.push("key:"+hint);return "selected";} };
  const field={get toLowerCase(){trace.push("get:lower");return function(){trace.push("call:lower");return key;};}};
  const dest=new Proxy({}, {get(target,name){trace.push("get:"+String(name));return target[name];},set(target,name,value){trace.push("set:"+String(name));target[name]=value;return true;}});
  api.IncomingMessage.prototype._addHeaderLineDistinct(field,"value",dest);
  incomingEqual(trace,["get:lower","call:lower","key:string","get:selected","key:string","set:selected"],"repeated Source property references");
  incomingEqual(dest.selected,["value"],"actual distinct append result");
}
function observeIncomingCompound(api){
  const saved=Object.getOwnPropertyDescriptor(String.prototype,"slice"), trace=[];
  const key={ [Symbol.toPrimitive](hint){trace.push("key:"+hint);return "x-value";} };
  Object.defineProperty(String.prototype,"slice",{configurable:true,writable:true,value:function(n){if(String(this)==="\0x-value"&&n===1)return key;return Reflect.apply(saved.value,this,[n]);}});
  try{
    const dest=new Proxy({"x-value":"old"}, {get(target,name){trace.push("get:"+String(name));return target[name];},set(target,name,value){trace.push("set:"+String(name));target[name]=value;return true;}});
    const incoming={ [Symbol.toPrimitive](hint){trace.push("incoming:"+hint);return "new";} };
    api.IncomingMessage.prototype._addHeaderLine("X-Value",incoming,dest);
    incomingEqual(trace,["key:string","get:x-value","key:string","get:x-value","incoming:default","set:x-value"],"compound one converted key and actual generic plus");
    incomingAssert(dest["x-value"]==="old, new","actual compound output");
  }finally{Object.defineProperty(String.prototype,"slice",saved);}
}
function observeIncomingHeaderLoop(api){
  const value=new api.IncomingMessage(null), trace=[];
  const count=incomingSymbol(value,"kHeadersCount"), header=incomingSymbol(value,"kHeaders");
  const src=new Proxy(["A","1","B","2"],{get(target,key){trace.push("raw:"+String(key));return target[key];}});
  value.rawHeaders=src;value[header]=null;
  Object.defineProperty(value,count,{configurable:true,get(){trace.push("count");return {valueOf(){trace.push("count:valueOf");return 4;}};}});
  Object.defineProperty(value,"_addHeaderLine",{configurable:true,get(){trace.push("method");return function(field,data,dest){incomingAssert(this===value,"actual header receiver");trace.push(["call",field,data]);dest[field]=data;};}});
  incomingEqual(value.headers,{A:"1",B:"2"},"actual lazy getter loop result");
  incomingEqual(trace,["count","count:valueOf","method","raw:0","raw:1",["call","A","1"],"count","count:valueOf","method","raw:2","raw:3",["call","B","2"],"count","count:valueOf"],"live count and callee-before-indices");
}
function observeIncomingLineOrder(api){
  const value=new api.IncomingMessage(null), trace=[], raw=["A","1"];
  const count=incomingSymbol(value,"kHeadersCount"), header=incomingSymbol(value,"kHeaders");
  Object.defineProperty(value,"complete",{get(){trace.push("complete");return false;}});
  Object.defineProperty(value,"rawHeaders",{set(v){incomingAssert(v===raw,"actual raw assignment");trace.push("raw");}});
  Object.defineProperty(value,count,{set(v){incomingAssert(v===2,"actual count assignment");trace.push("count");}});
  Object.defineProperty(value,header,{get(){trace.push("destination");return {};}});
  Object.defineProperty(value,"_addHeaderLine",{get(){trace.push("method");return function(a,b,d){trace.push(["call",a,b]);};}});
  value._addHeaderLines(raw,2);
  incomingEqual(trace,["complete","raw","count","destination","method",["call","A","1"]],"raw/count/destination ordered assignments");
  trace.length=0;value._addHeaderLines(null,2);incomingEqual(trace,[],"optional null header list");
}
function observeIncomingTimeoutConnection(api,hooks){
  const trace=[], socket={setTimeout(n){incomingAssert(this===socket,"socket timeout receiver");trace.push(["timeout",n]);}};
  const receiver={on(event,fn){trace.push(["on",event]);return hooks.make(0);},get socket(){incomingAssert(hooks.count(0)===1,"on result retired before socket getter");trace.push("socket");return socket;}};
  incomingAssert(api.IncomingMessage.prototype.setTimeout.call(receiver,19,()=>{})===receiver,"setTimeout returns same this");
  incomingEqual(trace,[["on","timeout"],"socket",["timeout",19]],"actual timeout call order");
  const descriptor=Object.getOwnPropertyDescriptor(api.IncomingMessage.prototype,"connection"), own={socket};
  incomingAssert(descriptor.get.call(own)===socket,"connection getter");
  descriptor.set.call(own,23);incomingAssert(own.socket===23,"connection setter");
}
function observeIncomingReadPredicates(api,hooks){
  const trace=[];
  const socket={get _paused(){trace.push("paused");return false;},get readable(){trace.push("readable");return hooks.make(0);},get resume(){incomingAssert(hooks.count(0)===1,"readable predicate retired before resume");trace.push("resume");return function(){trace.push("call");};}};
  api.readStart(socket);incomingEqual(trace,["paused","readable","resume","call"],"readStart predicate order");
  let reads=0;
  const receiver={_consuming:true,get socket(){reads++;if(reads===1)return {get readable(){return hooks.make(1);}};incomingAssert(hooks.count(1)===1,"_read predicate retired before second socket read");return {_paused:true};}};
  api.IncomingMessage.prototype._read.call(receiver,99);incomingAssert(reads===2,"Source repeated socket read");
  let paused=0;api.readStop({pause(){paused++;}});api.readStop(null);incomingAssert(paused===1,"real readStop guard");
}
function observeIncomingDump(api){
  const trace=[], receiver={_dumped:false,removeAllListeners(name){trace.push(["remove",name]);},resume(){trace.push("resume");}};
  api.IncomingMessage.prototype._dump.call(receiver);
  api.IncomingMessage.prototype._dump.call(receiver);
  incomingEqual(trace,[["remove","data"],"resume"],"single actual dump body");
  let reads=0;const state={}, closed={set _dumped(v){incomingAssert(v===true,"dump flag");},get _readableState(){reads++;return state;}};
  api.IncomingMessage.prototype._dumpAndCloseReadable.call(closed);
  incomingAssert(reads===5,"five distinct live state receivers");
  incomingEqual(state,{ended:true,endEmitted:true,destroyed:true,closed:true,closeEmitted:true},"actual closed state assignments");
}
function observeIncomingDestroyElse(api){
  incomingTicks(calls=>{
    const error={selected:true}, callbackArgs=[];
    const receiver={readableEnded:true,complete:true,socket:null,listenerCount(name){incomingAssert(name==="error","actual listenerCount name");return 0;}};
    api.IncomingMessage.prototype._destroy.call(receiver,error,(...args)=>callbackArgs.push(args));
    incomingAssert(calls.length===1&&calls[0][1]===receiver&&calls[0][2]===error,"actual nextTick arguments");
    Reflect.apply(calls[0][0],undefined,calls[0].slice(1));
    incomingEqual(callbackArgs,[[]],"no error listener callback has no arguments");
    receiver.listenerCount=()=>1;calls.length=0;
    api.IncomingMessage.prototype._destroy.call(receiver,error,(...args)=>callbackArgs.push(args));
    Reflect.apply(calls[0][0],undefined,calls[0].slice(1));
    incomingAssert(callbackArgs[1].length===1&&callbackArgs[1][0]===error,"error listener receives exact reason");
  });
}
function observeIncomingDestroyFinished(api,control){
  const trace=[], error={original:true}, callbackArgs=[];let deferred;
  incomingTicks(calls=>{
    const socket={destroyed:false,destroy(e){incomingAssert(e===error,"exact destroy reason");trace.push("destroy");}};
    const receiver={readableEnded:false,complete:false,socket,emit(name){trace.push("emit:"+name);},listenerCount(){return 1;}};
    control.finished=function(actual,cb){incomingAssert(actual===socket,"actual finished socket");trace.push("finished");deferred=cb;return function(){incomingAssert(this===undefined,"ordinary cleanup receiver");trace.push("cleanup");};};
    try{
      api.IncomingMessage.prototype._destroy.call(receiver,error,(...args)=>callbackArgs.push(args));
      incomingAssert(receiver.aborted===true&&calls.length===0,"aborted before deferred completion");
      deferred({code:"ERR_STREAM_PREMATURE_CLOSE"});
      incomingEqual(trace,["emit:aborted","destroy","finished","cleanup"],"actual completion then cleanup");
      incomingAssert(calls.length===1&&calls[0][2]===error,"premature close falls back to original error");
      Reflect.apply(calls[0][0],undefined,calls[0].slice(1));
      incomingAssert(callbackArgs[0][0]===error,"real onError body through nextTick");
    }finally{control.finished=null;}
  });
}
function observeIncomingCleanupTDZ(api,control){
  const receiver={readableEnded:true,complete:true,aborted:true,socket:{destroyed:false,destroy(){}}};let escaped;
  control.finished=function(socket,cb){escaped=cb;cb(null);};
  try{
    const first=incomingThrown(()=>api.IncomingMessage.prototype._destroy.call(receiver,null,()=>{}));
    incomingAssert(first instanceof ReferenceError,"synchronous callback sees actual cleanup TDZ");
    const second=incomingThrown(()=>escaped(null));
    incomingAssert(second instanceof ReferenceError,"escaped failed activation retains uninitialized binding");
  }finally{control.finished=null;}
}
function observeIncomingDestroyOrder(api,control){
  const trace=[], socket={get destroyed(){trace.push("destroyed");return true;}};
  incomingTicks(calls=>{
    const receiver={get readableEnded(){trace.push("ended");return false;},get complete(){trace.push("complete");return false;},set aborted(v){trace.push("aborted:set");},emit(name){trace.push("emit:"+name);},get socket(){trace.push("socket");return socket;}};
    api.IncomingMessage.prototype._destroy.call(receiver,7,()=>{});
    incomingEqual(trace,["ended","aborted:set","emit:aborted","socket","socket","destroyed"],"actual destroy short circuits and repeated socket");
    incomingAssert(calls.length===1,"already destroyed socket uses direct tick");
  });
}
function observeIncomingPrivateData(api,hooks){
  let saved;
  const receiver={get readableEnded(){saved=hooks.freshPrivateData();throw saved;}};
  incomingAssert(incomingThrown(()=>api.IncomingMessage.prototype._destroy.call(receiver,null,()=>{}))===saved,"same getter private DATA identity");
  incomingAssert(hooks.isUnmarkedPrivateData(saved),"ordinary DATA tag remains unmarked");
}
function observeIncomingCurrentFatal(api,hooks){
  const old=hooks.freshPrivateData();incomingAssert(hooks.isUnmarkedPrivateData(old),"successful prior DATA");
  const receiver={get readableEnded(){hooks.raiseNativeFatal();return true;},get complete(){hooks.visit(1);return true;}};
  try{api.IncomingMessage.prototype._destroy.call(receiver,null,()=>{});}catch(error){hooks.record.guestReached=true;hooks.visit(2);throw error;}
}
function observeIncomingPredicateFatal(api,hooks){
  hooks.armFatal(0);
  const socket={_paused:false,get readable(){return hooks.make(0);},get resume(){hooks.visit(1);return function(){};}};
  try{api.readStart(socket);}catch(error){hooks.record.guestReached=true;hooks.visit(2);throw error;}
}
async function observeIncomingRealReadable(api,streams){
  const value=new api.IncomingMessage(null), chunks=[];
  value.push("ab");value.push("cd");value.complete=true;value.push(null);
  value.on("data",chunk=>chunks.push(chunk.toString()));
  const finished=new Promise((resolve,reject)=>streams.finished(value,{readable:true,writable:false},error=>error?reject(error):resolve()));
  await finished;
  incomingEqual(chunks,["ab","cd"],"actual Readable flow through incoming prototype");
  incomingAssert(value.readableEnded===true,"genuine readable terminal state");
}

function observeIncomingCompoundRetirement(api,hooks){
  let reads=0;
  const dest={get "x-value"(){
    if(++reads===1)return "probe";
    const holder=hooks.make(0);
    Object.defineProperty(holder,"valueOf",{value(){return "old";}});
    return holder;
  },set "x-value"(value){
    incomingAssert(hooks.count(0)===1,"binary old operand retired before actual PutValue");
    incomingAssert(value==="old, new","completed actual compound result");
  }};
  api.IncomingMessage.prototype._addHeaderLine("X-Value","new",dest);
  incomingAssert(reads===2,"typeof and compound Source references are distinct");
}
