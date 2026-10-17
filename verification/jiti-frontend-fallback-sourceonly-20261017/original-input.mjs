// Original user observations around the completed ACTUAL jiti frontend. Before
// this call the real actualJiti, namespaces and owned physical valid module
// already exist. evalOptions: async=true, forceTranspile=false, real filename.
// Actual nativeImportOrRequire/queued import is required, never a fake result.
export function captureActualFallback(actualJiti, originalSource, evalOptions, counters) {
  const descriptor = Object.getOwnPropertyDescriptor(Promise.prototype,"catch");
  const originalCatch = Promise.prototype.catch;
  let callback;
  Object.defineProperty(Promise.prototype,"catch",{configurable:true,writable:true,value:function(handler){
    callback = handler;
    return Reflect.apply(originalCatch,this,[handler]);
  }});
  let entryPromise;
  try { entryPromise = actualJiti.evalModule(originalSource,evalOptions); }
  finally { Object.defineProperty(Promise.prototype,"catch",descriptor); }
  if (typeof callback !== "function") throw new Error("actual frontend callback was not observed");
  // Driver awaits the real successful native-import entryPromise BEFORE direct
  // causal callback calls. This avoids an earlier C2 .then propagation path
  // fatalizing marked data before the target actual callback is reached.
  return {callback,entryPromise,originalOptions:evalOptions,counters};
}
export function ordinaryData(counters, reason = new Error("original frontend rejection data")) {
  Object.defineProperty(reason,"toString",{get(){counters.diagnosticReads++;return function(){return "original frontend rejection data";};}});
  return reason;
}
export function counters() { return {diagnosticReads:0,extraReads:0}; }
export function addOriginalOptionGetter(options, counter, kind, sameReason) {
  Object.defineProperty(options,"extra",{enumerable:true,configurable:true,get(){
    counter.extraReads++;
    if (kind === "ordinary") throw sameReason;
    if (kind === "oom") return globalThis.ActualJitiFallbackFreshOOM();
    if (kind === "interrupt") { globalThis.ActualJitiFallbackCancelBudget(); for (;;) {} }
    return 1;
  }});
}
export function observeRawSourceTailReturn() {
  const descriptor = Object.getOwnPropertyDescriptor(Promise.prototype,"then");
  const originalThen = Promise.prototype.then;
  const marker = {originalUserRawReturn:true};
  const realCompletions = [];
  Object.defineProperty(Promise.prototype,"then",{configurable:true,writable:true,value:function(...args){
    realCompletions.push(Reflect.apply(originalThen,this,args));
    return marker;
  }});
  return {marker,realCompletions,restore(){Object.defineProperty(Promise.prototype,"then",descriptor);}};
}
// This file observes the original Source callbacks/callees and supplies legal
// user options. It never clones their implementations, swaps the real self/
// require/importer with a fake, manufactures an expected trace or runs Node.
