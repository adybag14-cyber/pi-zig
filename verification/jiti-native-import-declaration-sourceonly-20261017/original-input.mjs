// Original direct callers of the genuine nativeImportOrRequire export loaded
// from unchanged jiti2.7 require.ts (reference), or canonical real native export.
// Actual createRequire/queued-or-guest-dynamic-import capabilities and physical
// module names are supplied by the owned driver. No stub namespace/importer.
export function contextProbe(actualRequire, actualImport, kind, reason) {
  const trace = [];
  const counters = {importReads:0,requireReads:0,diagnosticReads:0};
  Object.defineProperty(reason,"toString",{configurable:true,get(){counters.diagnosticReads++;return function(){return "actual user reason";};}});
  const marker = {actualUserThenReturn:true};
  const realCompletions = [];
  let context;
  const importing = new Proxy(actualImport,{apply(target,receiver,args){
    trace.push(["import-call",receiver === context,args[0]]);
    const promise = Reflect.apply(target,receiver,args);
    const then = promise.then;
    Object.defineProperty(promise,"then",{configurable:true,get(){
      trace.push("then-get");
      if(kind === "then-get-throw") throw reason;
      if(kind === "then-get-oom") return globalThis.ActualNativeImportFreshOOM();
      return function(...args){
        trace.push(["then-call",this === promise,args[0].name,args[0].length,Object.hasOwn(args[0],"prototype")]);
        const completion = Reflect.apply(then,this,args);
        realCompletions.push(completion);
        if(kind === "success-pending-event") globalThis.ActualNativeImportPendingEvent(reason);
        return kind === "raw-then" ? marker : completion;
      };
    }});
    return promise;
  }});
  const requiring = new Proxy(actualRequire,{apply(target,receiver,args){
    trace.push(["require-call",receiver === context,args[0]]);
    return Reflect.apply(target,receiver,args);
  }});
  context = {opts:{interopDefault:false}};
  Object.defineProperty(context,"nativeImport",{get(){
    counters.importReads++;
    trace.push(["import-get",counters.importReads]);
    if(kind === "import-get-throw" || kind === "sync-must-not-read-import") throw reason;
    if(kind === "import-get-oom") return globalThis.ActualNativeImportFreshOOM();
    if(kind === "falsy-import") return undefined;
    if(kind === "second-import-noncallable" && counters.importReads === 2) return {};
    return importing;
  }});
  Object.defineProperty(context,"nativeRequire",{get(){
    counters.requireReads++;
    trace.push("require-get");
    return requiring;
  }});
  return {context,counters,trace,marker,realCompletions};
}
export function callOrdinary(actualDeclaration, context, id, asynchronous) {
  try { return {returned:true,value:actualDeclaration(context,id,asynchronous)}; }
  catch(reason) { return {returned:false,reason}; }
}
// Driver records the raw result/receiver/getter trace BEFORE awaiting any real
// completion. It drains only its owned real imports afterward. Native pending/
// OOM probes are native-only fault controls, not a fabricated Node baseline.
