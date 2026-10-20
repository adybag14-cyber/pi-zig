function helperAssert(value, message) {
  if (!value) throw new Error("Actual CommonJS helpers: " + message);
}
function helperEqual(actual, expected, message) {
  helperAssert(actual.length === expected.length, message + " length");
  for (let i = 0; i < expected.length; i++)
    helperAssert(Object.is(actual[i], expected[i]), message + " index " + i);
}
function helperRestore(object, key, descriptor) {
  if (descriptor) Object.defineProperty(object, key, descriptor);
  else delete object[key];
}
function helperOptions(view, user = [], noAddons = false, moduleSync = false) {
  const names = ["--conditions", "--no-addons", "--experimental-require-module"];
  const values = [user, noAddons, moduleSync];
  const descriptors = names.map(name => Object.getOwnPropertyDescriptor(view.cache, name));
  for (let i = 0; i < names.length; i++)
    Object.defineProperty(view.cache, names[i], {value:values[i], writable:true, enumerable:true, configurable:true});
  return () => {
    for (let i = 0; i < names.length; i++) helperRestore(view.cache, names[i], descriptors[i]);
  };
}
function helperGetter(object, key, get) {
  Object.defineProperty(object, key, {get, enumerable:true, configurable:true});
}
function observeHelpersShape(h, v) {
  const restore = helperOptions(v);
  try {
    for (const [name, length] of [["toRealPath",1],["initializeCjsConditions",0],["getCjsConditions",0],["getCjsConditionsArray",0]]) {
      const fn = h[name];
      helperAssert(typeof fn === "function" && fn.name === name && fn.length === length, "original function " + name);
      helperAssert(Object.hasOwn(fn, "prototype") && typeof fn.prototype === "object", "ordinary constructor " + name);
      const lengthDescriptor = Object.getOwnPropertyDescriptor(fn, "length");
      helperAssert(!lengthDescriptor.writable && !lengthDescriptor.enumerable && lengthDescriptor.configurable, "length descriptor " + name);
    }
    const initialized = new h.initializeCjsConditions();
    helperAssert(Object.getPrototypeOf(initialized) === h.initializeCjsConditions.prototype, "real ordinary initialize construction");
    helperAssert(h.initializeCjsConditions() === undefined, "initialize returns undefined");
  } finally { restore(); }
}
function observeHelpersConditions(h, v) {
  const object = {}, symbol = Symbol("condition");
  const user = ["x","x",NaN,NaN,-0,0,object,symbol];
  const restore = helperOptions(v,user,true,true);
  try {
    const array = h.getCjsConditionsArray(), set = h.getCjsConditions();
    helperEqual(array, ["require","node",...user,"module-sync"], "ordered raw conditions");
    helperAssert(Object.isFrozen(array), "actual array frozen");
    helperAssert(set instanceof v.SafeSet && Object.getPrototypeOf(set) === v.SafeSet.prototype, "genuine SafeSet instance");
    helperAssert(set.size === 8 && set.has(NaN) && set.has(0) && set.has(object) && set.has(symbol), "SameValueZero and original identities");
    helperAssert(!set.has("node-addons"), "truthy no-addons omits addon condition");
  } finally { restore(); }
}
function observeHelpersLazyAndReinitialize(h, v) {
  const restore = helperOptions(v,["first"],false,false);
  try {
    const first = h.getCjsConditions(), array = h.getCjsConditionsArray();
    helperAssert(first === h.getCjsConditions() && array === h.getCjsConditionsArray(), "both lazy identities");
    v.cache["--conditions"] = ["second"];
    helperAssert(h.getCjsConditions() === first && h.getCjsConditionsArray() === array, "cached values survive option mutation");
    helperAssert(h.initializeCjsConditions() === undefined, "explicit initialization");
    const next = h.getCjsConditions(), nextArray = h.getCjsConditionsArray();
    helperAssert(next !== first && nextArray !== array, "explicit reinitialization replaces both");
    helperEqual(array,["require","node","node-addons","first"],"old frozen snapshot");
    helperEqual(nextArray,["require","node","node-addons","second"],"new frozen snapshot");
  } finally { restore(); }
}
function observeHelpersOrder(h, v) {
  const restore = helperOptions(v), trace = [];
  const iterator = Object.getOwnPropertyDescriptor(Array.prototype, Symbol.iterator);
  try {
    helperGetter(v.cache,"--conditions",() => { trace.push("conditions"); return {
      [Symbol.iterator]() {
        trace.push("user.iterator"); let index = 0;
        return {next(){ trace.push("user.next" + index); return index++ === 0 ? {value:"user",done:false} : {done:true}; }};
      }
    }; });
    helperGetter(v.cache,"--no-addons",() => { trace.push("no-addons"); return false; });
    helperGetter(v.cache,"--experimental-require-module",() => { trace.push("module-sync"); return true; });
    Object.defineProperty(Array.prototype,Symbol.iterator,{...iterator,value:function(){
      if (Object.isFrozen(this) && this[0] === "require") trace.push("set.iterator");
      return Reflect.apply(iterator.value,this,[]);
    }});
    h.initializeCjsConditions();
  } finally { Object.defineProperty(Array.prototype,Symbol.iterator,iterator); restore(); }
  helperEqual(trace,["conditions","no-addons","user.iterator","user.next0","user.next1","module-sync","set.iterator"],"actual initialization order");
  helperEqual(h.getCjsConditionsArray(),["require","node","node-addons","user","module-sync"],"ordered result");
}
function observeHelpersSpreadFailure(h, v) {
  const restore = helperOptions(v), reason = {}, trace = [];
  let fail = true;
  try {
    helperGetter(v.cache,"--conditions",() => { trace.push("conditions"); return {
      [Symbol.iterator]() { trace.push("iterator"); if (fail) throw reason; return [][Symbol.iterator](); }
    }; });
    helperGetter(v.cache,"--no-addons",() => { trace.push("no-addons"); return true; });
    helperGetter(v.cache,"--experimental-require-module",() => { trace.push("module-sync"); return false; });
    let caught;
    try { h.getCjsConditions(); } catch (error) { caught = error; }
    helperAssert(caught === reason, "original spread failure");
    helperEqual(trace,["conditions","no-addons","iterator"],"failure before later flag");
    fail = false;
    helperEqual(h.getCjsConditionsArray(),["require","node"],"undefined array retries original initializer");
    helperEqual(trace,["conditions","no-addons","iterator","conditions","no-addons","iterator","module-sync"],"real retry reads");
  } finally { restore(); }
}
function observeHelpersFlagFailure(h, v) {
  const restore = helperOptions(v,["user"],true,false), reason = {};
  let reads = 0;
  try {
    helperGetter(v.cache,"--experimental-require-module",() => { reads++; throw reason; });
    let caught;
    try { h.getCjsConditionsArray(); } catch (error) { caught = error; }
    helperAssert(caught === reason && reads === 1,"flag throws after assignment");
    const partial = h.getCjsConditionsArray();
    helperEqual(partial,["require","node","user"],"published array before flag");
    helperAssert(!Object.isFrozen(partial) && reads === 1,"array lazy getter returns partial without retry");
    Object.defineProperty(v.cache,"--experimental-require-module",{value:false,writable:true,configurable:true});
    const set = h.getCjsConditions();
    helperAssert(set.has("user") && h.getCjsConditionsArray() !== partial && Object.isFrozen(h.getCjsConditionsArray()),"undefined Set getter retries");
  } finally { restore(); }
}
function observeHelpersPushFailure(h, v) {
  const restore = helperOptions(v,[],true,true), reason = {};
  const push = Object.getOwnPropertyDescriptor(Array.prototype,"push");
  let caught, reads = 0;
  try {
    Object.defineProperty(Array.prototype,"push",{configurable:true,get(){
      if (this[0] === "require") { reads++; throw reason; }
      return push.value;
    }});
    try { h.initializeCjsConditions(); } catch (error) { caught = error; }
  } finally { Object.defineProperty(Array.prototype,"push",push); }
  try {
    helperAssert(caught === reason && reads === 1,"live array push getter");
    const partial = h.getCjsConditionsArray();
    helperEqual(partial,["require","node"],"partial array without module-sync");
    helperAssert(!Object.isFrozen(partial),"push failure precedes freeze");
    v.cache["--experimental-require-module"] = false;
    helperAssert(h.getCjsConditions().has("require") && h.getCjsConditionsArray() !== partial,"real retry after push failure");
  } finally { restore(); }
}
function observeHelpersSetFailure(h, v) {
  const restore = helperOptions(v,["user"],true,false), reason = {};
  const iterator = Object.getOwnPropertyDescriptor(Array.prototype,Symbol.iterator);
  let caught, reads = 0;
  try {
    Object.defineProperty(Array.prototype,Symbol.iterator,{...iterator,value:function(){
      if (Object.isFrozen(this) && this[0] === "require") { reads++; throw reason; }
      return Reflect.apply(iterator.value,this,[]);
    }});
    try { h.initializeCjsConditions(); } catch (error) { caught = error; }
  } finally { Object.defineProperty(Array.prototype,Symbol.iterator,iterator); }
  try {
    helperAssert(caught === reason && reads === 1,"actual SafeSet consumes frozen array iterable");
    const partial = h.getCjsConditionsArray();
    helperAssert(Object.isFrozen(partial),"freeze completed before Set failure");
    helperAssert(h.getCjsConditions().has("user") && h.getCjsConditionsArray() !== partial,"Set remains undefined and retries");
  } finally { restore(); }
}
function observeHelpersRealpath(h, v) {
  const fs = Object.getOwnPropertyDescriptor(v.fs,"realpathSync");
  const keyDescriptor = Object.getOwnPropertyDescriptor(v.internalFS,"realpathCacheKey");
  const key = keyDescriptor.value, request = {}, returned = {}, trace = [];
  let selectedCache;
  try {
    helperGetter(v.fs,"realpathSync",() => { trace.push("callee"); return function(path, options) {
      trace.push("call");
      helperAssert(this === v.fs && path === request,"actual fs receiver and raw request");
      const keys = Reflect.ownKeys(options);
      helperAssert(keys.length === 1 && keys[0] === key,"real computed cache key");
      const descriptor = Object.getOwnPropertyDescriptor(options,key);
      helperAssert(descriptor.writable && descriptor.enumerable && descriptor.configurable,"object literal own cache field");
      const cache = descriptor.value;
      helperAssert(cache instanceof v.SafeMap,"real primordial cache");
      if (selectedCache) helperAssert(cache === selectedCache && cache.get("prior") === returned,"same cache across invocations");
      else { selectedCache = cache; cache.set("prior",returned); }
      return returned;
    }; });
    helperGetter(v.internalFS,"realpathCacheKey",() => { trace.push("key"); return {
      [Symbol.toPrimitive](hint) { trace.push(hint); return key; }
    }; });
    helperAssert(h.toRealPath(request) === returned && h.toRealPath(request) === returned,"real returned value");
    helperEqual(trace,["callee","key","string","call","callee","key","string","call"],"callee before computed options");
  } finally { Object.defineProperty(v.fs,"realpathSync",fs); Object.defineProperty(v.internalFS,"realpathCacheKey",keyDescriptor); }
}
function observeHelpersKeyFailure(h, v) {
  const fs = Object.getOwnPropertyDescriptor(v.fs,"realpathSync");
  const descriptor = Object.getOwnPropertyDescriptor(v.internalFS,"realpathCacheKey");
  const reason = {};
  let calls = 0, reads = 0;
  try {
    helperGetter(v.fs,"realpathSync",() => { reads++; return () => { calls++; }; });
    for (const conversion of [false,true]) {
      helperGetter(v.internalFS,"realpathCacheKey",() => {
        if (!conversion) throw reason;
        return {[Symbol.toPrimitive](){throw reason;}};
      });
      let caught;
      try { h.toRealPath("request"); } catch (error) { caught = error; }
      helperAssert(caught === reason,"computed key error identity");
    }
    helperAssert(reads === 2 && calls === 0,"selected callee is never called after key failure");
  } finally { Object.defineProperty(v.fs,"realpathSync",fs); Object.defineProperty(v.internalFS,"realpathCacheKey",descriptor); }
}
function installHelpersPrimordialPoison() {
  const map = Object.getOwnPropertyDescriptor(globalThis,"Map");
  const set = Object.getOwnPropertyDescriptor(globalThis,"Set");
  const freeze = Object.getOwnPropertyDescriptor(Object,"freeze");
  const define = Object.defineProperty;
  const reason = {};
  define(globalThis,"Map",{...map,value:function(){throw reason;}});
  define(globalThis,"Set",{...set,value:function(){throw reason;}});
  define(Object,"freeze",{...freeze,value:function(){throw reason;}});
  globalThis.restoreHelperPrimordials = () => {
    define(globalThis,"Map",map); define(globalThis,"Set",set); define(Object,"freeze",freeze);
  };
}
function observeHelpersPoisonedImports(h, v) {
  const restore = helperOptions(v,["captured"],true,false);
  try {
    h.initializeCjsConditions();
    helperAssert(Object.isFrozen(h.getCjsConditionsArray()) && h.getCjsConditions().has("captured"),"original freeze and SafeSet after first late acquire");
    const fs = Object.getOwnPropertyDescriptor(v.fs,"realpathSync");
    try {
      Object.defineProperty(v.fs,"realpathSync",{...fs,value:function(path,options){
        helperAssert(options[v.internalFS.realpathCacheKey] instanceof v.SafeMap,"original SafeMap after first late acquire");
        return path;
      }});
      helperAssert(h.toRealPath("captured") === "captured","actual helper still calls real fs field");
    } finally { Object.defineProperty(v.fs,"realpathSync",fs); }
  } finally { restore(); restoreHelperPrimordials(); }
}
function observeHelpersPrivateData(h, v, route) {
  const restore = helperOptions(v), reason = actualHelpersPrivateData();
  const fs = Object.getOwnPropertyDescriptor(v.fs,"realpathSync");
  const key = Object.getOwnPropertyDescriptor(v.internalFS,"realpathCacheKey");
  let caught;
  try {
    if (route === 0) helperGetter(v.cache,"--conditions",() => { throw reason; });
    if (route === 1) helperGetter(v.cache,"--no-addons",() => { throw reason; });
    if (route === 2) v.cache["--conditions"] = {[Symbol.iterator](){return {next(){throw reason;}};}};
    if (route === 3) helperGetter(v.cache,"--experimental-require-module",() => { throw reason; });
    if (route === 4) helperGetter(v.internalFS,"realpathCacheKey",() => { throw reason; });
    if (route === 5) Object.defineProperty(v.fs,"realpathSync",{...fs,value(){throw reason;}});
    try { if (route < 4) h.initializeCjsConditions(); else h.toRealPath("data"); }
    catch (error) { caught = error; }
    helperAssert(caught === reason,"ordinary private DATA stays exact at route " + route);
  } finally { restore(); Object.defineProperty(v.fs,"realpathSync",fs); Object.defineProperty(v.internalFS,"realpathCacheKey",key); }
}
function observeHelpersFlaggedReturn(h, v) {
  const fs = Object.getOwnPropertyDescriptor(v.fs,"realpathSync");
  const reason = actualHelpersFlaggedData();
  globalThis.actualHelpersSelectedData = reason;
  try {
    Object.defineProperty(v.fs,"realpathSync",{...fs,value(){return reason;}});
    helperAssert(h.toRealPath("flagged") === reason,"flagged successful return remains DATA");
  } finally { Object.defineProperty(v.fs,"realpathSync",fs); }
}
function observeHelpersLocalRetention(h, v) {
  const restore = helperOptions(v), iterator = Object.getOwnPropertyDescriptor(Array.prototype,Symbol.iterator);
  try {
    helperGetter(v.cache,"--conditions",() => {
      const holder = actualHelpersHolder(0);
      holder[Symbol.iterator] = function(){
        let done = false;
        return {next(){
          helperAssert(actualHelpersFreedCount(0) === 0 && actualHelpersFreedCount(1) === 0,"both original locals survive user iteration");
          if (done) return {done:true}; done = true; return {value:"held",done:false};
        }};
      };
      return holder;
    });
    helperGetter(v.cache,"--no-addons",() => actualHelpersHolder(1));
    Object.defineProperty(Array.prototype,Symbol.iterator,{...iterator,value:function(){
      if (Object.isFrozen(this) && this[0] === "require")
        helperAssert(actualHelpersFreedCount(0) === 0 && actualHelpersFreedCount(1) === 0,"locals survive final SafeSet iterable");
      return Reflect.apply(iterator.value,this,[]);
    }});
    h.initializeCjsConditions();
    helperAssert(actualHelpersFreedCount(0) === 1 && actualHelpersFreedCount(1) === 1,"original locals retire at function terminal");
  } finally { Object.defineProperty(Array.prototype,Symbol.iterator,iterator); restore(); }
}
function observeHelpersFlagRetirement(h, v) {
  const restore = helperOptions(v,[],true,false), push = Object.getOwnPropertyDescriptor(Array.prototype,"push");
  let read = 0;
  try {
    helperGetter(v.cache,"--experimental-require-module",() => actualHelpersHolder(2));
    Object.defineProperty(Array.prototype,"push",{configurable:true,get(){
      if (this[0] === "require") {
        read++;
        helperAssert(actualHelpersFreedCount(2) === 1,"truthy flag operand retires before push getter");
      }
      return push.value;
    }});
    h.initializeCjsConditions();
  } finally { Object.defineProperty(Array.prototype,"push",push); restore(); }
  helperAssert(read === 1 && h.getCjsConditions().has("module-sync"),"flag selected real branch");
}
function observeHelpersKeyRetirement(h, v) {
  const fs = Object.getOwnPropertyDescriptor(v.fs,"realpathSync");
  const descriptor = Object.getOwnPropertyDescriptor(v.internalFS,"realpathCacheKey"), key = descriptor.value;
  try {
    helperGetter(v.internalFS,"realpathCacheKey",() => {
      const holder = actualHelpersHolder(0);
      holder[Symbol.toPrimitive] = function(hint) { helperAssert(hint === "string","actual computed key hint"); return key; };
      return holder;
    });
    Object.defineProperty(v.fs,"realpathSync",{...fs,value(path){
      helperAssert(actualHelpersFreedCount(0) === 1,"raw key holder retires before actual fs body");
      return path;
    }});
    helperAssert(h.toRealPath("key") === "key","normal key result");
  } finally { Object.defineProperty(v.fs,"realpathSync",fs); Object.defineProperty(v.internalFS,"realpathCacheKey",descriptor); }
}
function observeHelpersCalleeRetirement(h, v) {
  const fs = Object.getOwnPropertyDescriptor(v.fs,"realpathSync");
  try {
    helperGetter(v.fs,"realpathSync",() => {
      const holder = actualHelpersHolder(0);
      return function(path) { void holder; return path; };
    });
    helperAssert(h.toRealPath("callee") === "callee" && actualHelpersFreedCount(0) === 1,"selected fs callee retires before caller continuation");
  } finally { Object.defineProperty(v.fs,"realpathSync",fs); }
}
function observeHelpersFailedReinitialize(h, v) {
  const restore = helperOptions(v,["old"],true,false), reason = {};
  try {
    h.initializeCjsConditions();
    const prior = h.getCjsConditions(), priorArray = h.getCjsConditionsArray();
    v.cache["--conditions"] = ["next"];
    helperGetter(v.cache,"--experimental-require-module",() => {throw reason;});
    let caught;
    try { h.initializeCjsConditions(); } catch (error) { caught = error; }
    const partial = h.getCjsConditionsArray();
    helperAssert(caught === reason && h.getCjsConditions() === prior,"prior Set survives failed later initialization");
    helperAssert(partial !== priorArray && !Object.isFrozen(partial) && prior.has("old"),"new partial array and prior Set remain distinct");
    Object.defineProperty(v.cache,"--experimental-require-module",{value:false,writable:true,configurable:true});
    h.initializeCjsConditions();
    helperAssert(h.getCjsConditions() !== prior && h.getCjsConditions().has("next"),"later explicit success replaces old Set");
  } finally { restore(); }
}
function observeHelpersRefresh(h, v) {
  const restore = helperOptions(v,["ephemeral"],true,false);
  try {
    h.initializeCjsConditions();
    helperAssert(h.getCjsConditions().has("ephemeral"),"actual initial options dictionary");
    v.options.refreshOptions();
    h.initializeCjsConditions();
    helperEqual(h.getCjsConditionsArray(),["require","node","node-addons","native-condition","module-sync"],"same retained getter reads genuine refreshed native options");
  } finally { restore(); }
}
function installHelpersFatal(v, route) {
  helperOptions(v,[],true,false);
  if (route === 0) helperGetter(v.cache,"--conditions",() => {
    actualHelpersProgress.selected++;
    return actualHelpersFatal();
  });
  if (route === 1) {
    helperGetter(v.cache,"--experimental-require-module",() => {
      actualHelpersProgress.selected++;
      return actualHelpersHolder(2);
    });
    const push = Object.getOwnPropertyDescriptor(Array.prototype,"push");
    Object.defineProperty(Array.prototype,"push",{configurable:true,get(){
      actualHelpersProgress.later++;
      return push.value;
    }});
  }
  if (route === 2) {
    const key = v.internalFS.realpathCacheKey;
    helperGetter(v.internalFS,"realpathCacheKey",() => {
      actualHelpersProgress.selected++;
      const holder = actualHelpersHolder(0);
      holder[Symbol.toPrimitive] = function(){return key;};
      return holder;
    });
    Object.defineProperty(v.fs,"realpathSync",{configurable:true,writable:true,value(){
      actualHelpersProgress.later++;
      return "unreachable";
    }});
  }
}
