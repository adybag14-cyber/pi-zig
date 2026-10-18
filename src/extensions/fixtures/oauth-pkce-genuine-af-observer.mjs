// Differential caller for the preserved c268 PKCE export and native export.
// Replaced globals are explicit guest-observation inputs and always restored.
export async function observePKCE(generate, mode) {
  const hostCrypto = crypto, subtle = hostCrypto.subtle, NativePromise = Promise;
  const randomOwn = Object.getOwnPropertyDescriptor(hostCrypto, "getRandomValues");
  const digestOwn = Object.getOwnPropertyDescriptor(subtle, "digest");
  const savedArray = Object.getOwnPropertyDescriptor(globalThis, "Uint8Array");
  const savedBtoa = Object.getOwnPropertyDescriptor(globalThis, "btoa");
  const savedChar = Object.getOwnPropertyDescriptor(String, "fromCharCode");
  const savedPromise = Object.getOwnPropertyDescriptor(globalThis, "Promise");
  const trace = [], original = {kind:"original"}, closing = {kind:"closing"};
  let expectedError = false;
  const restore = (object, key, descriptor) => descriptor ? Object.defineProperty(object,key,descriptor) : delete object[key];
  try {
    Object.defineProperty(hostCrypto,"getRandomValues",{configurable:true,value(bytes){trace.push("random:"+bytes.length);bytes.fill(0);return bytes}});
    if (mode === "thenable" || mode === "reject") {
      Object.defineProperty(subtle,"digest",{configurable:true,get(){
        trace.push("digest:get");
        return function(name,data){
          trace.push("digest:call:"+name+":"+data.length);
          return {get then(){trace.push("then:get");return function(resolve,reject){trace.push("then:call");if(mode==="reject")reject(original);else resolve(new savedArray.value([1,2,3]).buffer)}}};
        };
      }});
      expectedError = mode === "reject";
    } else if (mode === "iterator-close" || mode === "iterator-close-primitive") {
      Object.defineProperty(hostCrypto,"getRandomValues",{configurable:true,value(){trace.push("random");}});
      Object.defineProperty(globalThis,"Uint8Array",{configurable:true,value:function(){
        return {[Symbol.iterator](){trace.push("iterator");return {
          next(){trace.push("next");return {done:false,value:7}},
          return(){trace.push("return");if(mode==="iterator-close-primitive")return 1;throw closing}
        }}};
      }});
      Object.defineProperty(String,"fromCharCode",{configurable:true,value(){trace.push("body");throw original}});
      expectedError = true;
    } else if (mode === "replace-getter") {
      Object.defineProperty(globalThis,"btoa",{configurable:true,value(){return {get replace(){trace.push("replace:get");throw original}}}});
      expectedError = true;
    } else if (mode === "intrinsic-promise") {
      Object.defineProperty(globalThis,"Promise",{configurable:true,value:function PoisonPromise(){throw original}});
      globalThis.Promise.resolve = () => {throw original};
    }
    let promise;
    try { promise = generate(); trace.push("caller:return"); } catch (error) { return {sync:true,same:error===original,trace}; }
    const intrinsic = promise.constructor === NativePromise;
    NativePromise.resolve().then(()=>trace.push("caller:microtask"));
    try {
      const result = await promise;
      trace.push("caller:fulfilled");
      if (expectedError) throw Error("Required Source rejection missing");
      return {sync:false,intrinsic,result,trace};
    } catch (error) {
      trace.push("caller:rejected");
      if (!expectedError) throw error;
      if (error !== original) throw Error("Source throw or IteratorClose precedence replaced");
      return {sync:false,intrinsic,same:true,trace};
    }
  } finally {
    restore(hostCrypto,"getRandomValues",randomOwn);restore(subtle,"digest",digestOwn);
    restore(globalThis,"Uint8Array",savedArray);restore(globalThis,"btoa",savedBtoa);
    restore(String,"fromCharCode",savedChar);restore(globalThis,"Promise",savedPromise);
  }
}
export async function comparePKCE(native, source, modes) {
  const rows=[];
  for (const mode of modes) {
    const expected=await observePKCE(source,mode), actual=await observePKCE(native,mode);
    if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({mode,expected,actual}));
    rows.push({mode,...actual});
  }
  return rows;
}
