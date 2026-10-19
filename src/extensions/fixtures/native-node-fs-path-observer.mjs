// Shared actual internal/fs/utils observers. The caller supplies its genuine
// private exports and Buffer owner; this file contains no implementation.
function fsPathAssert(value, label) { if (!value) throw new Error(label); }
function fsPathThrown(callback) { try { callback(); } catch (reason) { return reason; } throw new Error("missing expected throw"); }
function fsPathSame(actual, expected, label) { fsPathAssert(JSON.stringify(actual) === JSON.stringify(expected), label + ": " + JSON.stringify(actual)); }
function observeFsPathDefaults(h) {
  const empty = h.kEmptyObject;
  fsPathAssert(Object.getPrototypeOf(empty) === null && Object.isFrozen(empty), "actual empty owner shape");
  for (const value of [undefined, null, function options() {}]) fsPathAssert(h.getOptions(value) === empty, "same default owner");
  const supplied = {chosen:true};
  fsPathAssert(h.getOptions(null, supplied) === supplied && h.getOptions(undefined, false) === false, "explicit default identity");
  const options = {encoding:"utf8"};
  fsPathAssert(h.getOptions(options) === options, "object options unchanged");
  const callable = Object.defineProperty(function() {}, "encoding", {get() { throw new Error("function encoding read"); }});
  fsPathAssert(h.getOptions(callable) === empty, "function options short circuit");
}
function observeFsPathStringSpread(h) {
  const symbol = Symbol("copy");
  const trace = [];
  const proto = {fromCopiedProto:true};
  const source = Object.create(null);
  Object.defineProperty(source, "a", {enumerable:true, get() { trace.push("get:a"); return 7; }});
  Object.defineProperty(source, "__proto__", {enumerable:true, value:proto});
  Object.defineProperty(source, "hidden", {enumerable:false, value:99});
  source[symbol] = 8;
  const proxy = new Proxy(source, {
    ownKeys(target) { trace.push("keys"); return Reflect.ownKeys(target); },
    getOwnPropertyDescriptor(target, key) { trace.push("desc:" + String(key)); return Reflect.getOwnPropertyDescriptor(target,key); },
    get(target, key, receiver) { trace.push("read:" + String(key)); return Reflect.get(target,key,receiver); },
  });
  const result = h.getOptions("utf8", proxy);
  fsPathAssert(Object.getPrototypeOf(result) === Object.prototype && result.a === 7 && result[symbol] === 8 && !Object.hasOwn(result,"hidden"), "spread data");
  fsPathAssert(Object.hasOwn(result,"__proto__") && result.__proto__ === proto && result.encoding === "utf8", "copy then ordinary assignment");
  fsPathSame(trace, ["keys","desc:a","read:a","get:a","desc:__proto__","read:__proto__","desc:hidden","desc:Symbol(copy)","read:Symbol(copy)"], "spread interleave");
  fsPathAssert(!Object.hasOwn(source,"encoding"), "default source preserved");
  const prior = Object.getOwnPropertyDescriptor(Object.prototype, "encoding");
  let receiver;
  Object.defineProperty(Object.prototype, "encoding", {configurable:true, set(value) {
    receiver = this;
    Object.defineProperty(this,"encoding",{value,configurable:true,writable:true,enumerable:true});
  }});
  try { const assigned = h.getOptions("utf8", null); fsPathAssert(receiver === assigned && assigned.encoding === "utf8", "live ordinary assignment setter"); }
  finally { if (prior) Object.defineProperty(Object.prototype,"encoding",prior); else delete Object.prototype.encoding; }
}
function observeFsPathOptionTypes(h) {
  for (const value of [0, true, 2n, Symbol("options")]) {
    const reason = fsPathThrown(() => h.getOptions(value));
    fsPathAssert(reason instanceof TypeError && reason.code === "ERR_INVALID_ARG_TYPE" && reason.message.includes('"options" argument'), "actual options type error");
  }
  fsPathAssert(h.getOptions("buffer").encoding === "buffer", "buffer string accepted");
  const reason = fsPathThrown(() => h.getOptions("BUFFER"));
  fsPathAssert(reason.code === "ERR_INVALID_ARG_VALUE" && reason.message.includes("encoding"), "buffer sentinel exact case");
}
function observeFsPathEncodingReads(h) {
  const trace = [];
  const actual = h.Buffer.isEncoding;
  const signal = new Proxy({}, {has(target, key) { trace.push("has:" + key); return key === "aborted"; }});
  const options = {get encoding() { trace.push("encoding"); return "utf8"; }, get signal() { trace.push("signal"); return signal; }};
  h.Buffer.isEncoding = function(value) { fsPathAssert(this === h.Buffer, "Buffer receiver"); trace.push("is:" + value); return true; };
  try { fsPathAssert(h.getOptions(options) === options, "same read options"); }
  finally { h.Buffer.isEncoding = actual; }
  fsPathSame(trace, ["encoding","encoding","is:utf8","signal","signal","has:aborted"], "actual read order");
}
function observeFsPathBufferSentinel(h) {
  const trace = [];
  const actual = h.Buffer.isEncoding;
  h.Buffer.isEncoding = function() { throw new Error("buffer sentinel predicate"); };
  try {
    const options = {get encoding() { trace.push("encoding"); return "buffer"; }, get signal() { trace.push("signal"); return undefined; }};
    fsPathAssert(h.getOptions(options) === options, "sentinel returns actual options");
    fsPathSame(trace, ["encoding","signal"], "sentinel single reads");
    let reads = 0;
    const empty = {get encoding() { reads++; return ""; }};
    fsPathAssert(h.getOptions(empty) === empty && reads === 2, "falsy encoding still reads twice");
  } finally { h.Buffer.isEncoding = actual; }
}
function observeFsPathLiveBuffer(h) {
  const actual = h.Buffer.isEncoding;
  const trace = [];
  h.Buffer.isEncoding = function(value) { trace.push(value); return value === "invented"; };
  try {
    const options = {encoding:"invented"};
    fsPathAssert(h.getOptions(options) === options, "live Buffer predicate accepted");
    const reason = fsPathThrown(() => h.getOptions({encoding:"rejected"}));
    fsPathAssert(reason.code === "ERR_INVALID_ARG_VALUE" && reason.message.includes("is invalid encoding"), "actual encoding value error");
  } finally { h.Buffer.isEncoding = actual; }
  fsPathSame(trace, ["invented","rejected"], "predicate actual arguments");
}
function observeFsPathSignalReads(h) {
  let reads = 0;
  const changing = {get signal() { reads++; return reads === 1 ? {} : {aborted: false}; }};
  fsPathAssert(h.getOptions(changing) === changing && reads === 2, "second signal value is validated");
  const first = {get signal() { reads++; return undefined; }};
  reads = 0; h.getOptions(first); fsPathAssert(reads === 1, "undefined signal single read");
  reads = 0;
  const second = {get signal() { reads++; return reads === 1 ? {aborted:false} : {}; }};
  const reason = fsPathThrown(() => h.getOptions(second));
  fsPathAssert(reads === 2 && reason.code === "ERR_INVALID_ARG_TYPE" && reason.message.includes("options.signal"), "second invalid signal source name");
}
function observeFsPathOrdinaryFailures(h) {
  const reason = {};
  for (const options of [
    {get encoding() { throw reason; }},
    {get signal() { throw reason; }},
  ]) fsPathAssert(fsPathThrown(() => h.getOptions(options)) === reason, "ordinary option getter identity");
  const actual = h.Buffer.isEncoding;
  h.Buffer.isEncoding = function() { throw reason; };
  try { fsPathAssert(fsPathThrown(() => h.getOptions({encoding:"utf8"})) === reason, "ordinary Buffer callback identity"); }
  finally { h.Buffer.isEncoding = actual; }
  const defaults = Object.defineProperty({}, "value", {enumerable:true, get() { throw reason; }});
  fsPathAssert(fsPathThrown(() => h.getOptions("utf8", defaults)) === reason, "ordinary spread getter identity");
}
function observeFsPathValidateShape(h) {
  fsPathAssert(h.getOptions.name === "getOptions" && h.getOptions.length === 1 && Object.hasOwn(h.getOptions,"prototype"), "getOptions function shape");
  fsPathAssert(h.validatePath.name === "wrappedFn" && h.validatePath.length === 0 && Object.hasOwn(h.validatePath,"prototype"), "hidden wrapper shape");
  const raw = h.validatePath.withoutStackTrace;
  fsPathAssert(typeof raw === "function" && raw.length === 1 && !Object.hasOwn(raw,"prototype"), "raw default-parameter arrow");
  for (const input of ["", ".", "/path", h.Buffer.from([1,2]), new Uint8Array([3,4])]) {
    fsPathAssert(h.validatePath(input) === undefined && raw(input,"chosen") === undefined, "valid string or actual Uint8Array");
  }
}
function fsPathObserveLiveHidden(h, field, input, isType) {
  const base = h[field];
  const descriptor = Object.getOwnPropertyDescriptor(base, "HideStackFramesError");
  fsPathAssert(descriptor && descriptor.configurable, "real mutable hidden constructor member");
  const trace = [];
  const selected = {};
  const lookupReason = {};
  const replacement = function(name, second, third) {
    trace.push("construct");
    fsPathAssert(new.target === replacement && name === "chosen", "actual selected constructor and arguments");
    if (isType) {
      fsPathSame(second, ["string", "Buffer", "URL"], "actual expected argument array");
      fsPathAssert(third === input, "invalid-type input identity");
    } else {
      fsPathAssert(second === input && third === "must be a string, Uint8Array, or URL without null bytes", "invalid-value arguments");
    }
    return selected;
  };
  try {
    Object.defineProperty(base, "HideStackFramesError", {configurable:true, get() {
      trace.push("get"); return replacement;
    }});
    const reason = fsPathThrown(() => h.validatePath.withoutStackTrace(input, "chosen"));
    fsPathAssert(reason === selected, "live selected hidden constructor return identity");
    fsPathSame(trace, ["get", "construct"], "hidden constructor selected at the throw");
    Object.defineProperty(base, "HideStackFramesError", {configurable:true, get() {
      trace.push("get-throw"); throw lookupReason;
    }});
    fsPathAssert(fsPathThrown(() => h.validatePath.withoutStackTrace(input, "chosen")) === lookupReason, "hidden member getter ordinary throw identity");
    fsPathSame(trace, ["get", "construct", "get-throw"], "later invocation rereads the live hidden member");
  } finally { Object.defineProperty(base, "HideStackFramesError", descriptor); }
}
function observeFsPathValidateInvalid(h) {
  for (const input of [undefined,null,1,[],{},new Uint16Array([1]),new Uint8ClampedArray([1]),new DataView(new ArrayBuffer(2))]) {
    const reason = fsPathThrown(() => h.validatePath(input,"file"));
    fsPathAssert(reason instanceof TypeError && reason.code === "ERR_INVALID_ARG_TYPE" && reason.message.includes('"file" argument'), "hidden invalid path type");
  }
  fsPathObserveLiveHidden(h, "invalid_arg_type", new Uint16Array([1]), true);
}
function observeFsPathValidateNul(h) {
  for (const input of ["a\0b",h.Buffer.from([1,0,2]),new Uint8Array([0])]) {
    const reason = fsPathThrown(() => h.validatePath(input));
    fsPathAssert(reason instanceof TypeError && reason.code === "ERR_INVALID_ARG_VALUE" && reason.message.includes("without null bytes"), "hidden null-byte value error");
  }
  fsPathObserveLiveHidden(h, "invalid_arg_value", "a\0b", false);
}
function observeFsPathCapturedIncludes(h) {
  const strings = String.prototype;
  const typed = Object.getPrototypeOf(Uint8Array.prototype);
  const stringIncludes = strings.includes, typedIncludes = typed.includes;
  strings.includes = function() { throw new Error("late string includes"); };
  typed.includes = function() { throw new Error("late typed includes"); };
  try {
    fsPathAssert(h.validatePath("okay") === undefined && h.validatePath(new Uint8Array([1])) === undefined, "captured actual includes");
    fsPathAssert(fsPathThrown(() => h.validatePath("a\0b")).code === "ERR_INVALID_ARG_VALUE", "captured string null check");
    fsPathAssert(fsPathThrown(() => h.validatePath(new Uint8Array([0]))).code === "ERR_INVALID_ARG_VALUE", "captured typed null check");
  } finally { strings.includes = stringIncludes; typed.includes = typedIncludes; }
}
