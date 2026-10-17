// Negative control observation of the actual imported platform function. The
// Proxy delegates its real receiver/arguments/result, never a stub output.
// No fake core/frontend/require callback or namespace supplies this Subject.
export function observeActualPlatform(actualPlatform) {
  const counter = {calls:0,diagnosticReads:0};
  const platform = new Proxy(actualPlatform,{apply(target,receiver,args){
    counter.calls++;
    return Reflect.apply(target,receiver,args);
  }});
  const pendingReason = new Error("actual current host event");
  Object.defineProperty(pendingReason,"toString",{get(){
    counter.diagnosticReads++;
    return function(){return "actual current host event";};
  }});
  return {platform,counter,pendingReason};
}
