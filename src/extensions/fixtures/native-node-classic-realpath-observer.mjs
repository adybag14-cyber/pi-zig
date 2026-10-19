"use strict";
// Actual Node v24.13 fs.realpathSync observations. The native fixture supplies
// the genuine installed fs/path/Buffer owners; the Source runner uses Node's.
function classicAssert(value, message) { if (!value) throw new Error(message); }
function classicSame(actual, expected, message) { classicAssert(Object.is(actual, expected), message); }
function classicList(actual, expected, message) {
  classicAssert(actual.length === expected.length && actual.every((value, index) => Object.is(value, expected[index])), message);
}
function classicRestore(object, key, descriptor) {
  if (descriptor) Object.defineProperty(object, key, descriptor); else delete object[key];
}
function classicPath(h, suffix) { return h.paths.resolve(h.root, suffix); }
function classicOptions(h, cache, encoding = "utf8") { return {encoding, [h.key]: cache}; }

function observeClassicShape(h) {
  classicSame(h.realpath, h.fs.realpathSync, "same public CJS function");
  classicSame(h.realpath, h.namedRealpath, "initial actual ESM named function");
  classicSame(h.realpath.name, "realpathSync", "classic name");
  classicSame(h.realpath.length, 2, "classic arity");
  classicAssert(Object.hasOwn(h.realpath, "prototype"), "Source ordinary constructor shape");
  const descriptor = Object.getOwnPropertyDescriptor(h.realpath, "native");
  classicAssert(descriptor.writable && descriptor.enumerable && descriptor.configurable, "native descriptor");
  classicSame(descriptor.value, h.nativeOriginal, "original native operation retained");
  classicAssert(h.nativeOriginal !== h.realpath, "separate Source native operation");
  classicSame(typeof h.key, "symbol", "actual private cache key");
}
function observeClassicPlain(h) {
  const file = classicPath(h, "dir/file.txt"), directory = classicPath(h, "dir");
  classicSame(h.realpath(file), file, "actual ordinary file");
  classicSame(h.realpath(directory), directory, "actual directory");
  classicSame(h.realpath(directory + h.paths.sep), directory, "trailing separator");
  classicSame(h.realpath(h.root + "/dir/../dir/file.txt"), file, "initial path resolution");
  classicSame(h.realpath(h.root + "/dir/./nested/../file.txt", null), file, "null default options");
}
function observeClassicFileLinks(h) {
  const file = classicPath(h, "dir/file.txt");
  classicSame(h.realpath(classicPath(h, "relative-file")), file, "relative file link");
  classicSame(h.realpath(classicPath(h, "absolute-file")), file, "absolute file link");
  classicSame(h.realpath(classicPath(h, "chain-file")), file, "link chain");
}
function observeClassicDirectoryLinks(h) {
  const file = classicPath(h, "dir/nested/end.txt");
  classicSame(h.realpath(classicPath(h, "directory-link/nested/end.txt")), file, "linked directory with suffix");
  classicSame(h.realpath(classicPath(h, "second-directory/nested/end.txt")), file, "directory link chain");
}
function observeClassicPathInputs(h) {
  const file = classicPath(h, "dir/file.txt"), trace = [];
  const value = {[Symbol.toPrimitive](hint) { trace.push(hint); return file; }};
  const options = {get encoding() { trace.push("encoding"); return "utf8"; }};
  classicSame(h.realpath(value, options), file, "generic path conversion");
  classicList(trace, ["encoding", "encoding", "default", "encoding", "encoding"], "options then default-hint conversion");
  classicSame(h.realpath(h.Buffer.from(file)), file, "actual Buffer path");
  const href = "file://" + (h.platform === "win32" ? "/" : "") + encodeURI(file.split("\\").join("/"));
  classicSame(h.realpath(new h.URL(href)), file, "actual URL path");
}
function observeClassicOptionFailure(h) {
  const reason = {}, trace = [], descriptor = Object.getOwnPropertyDescriptor(h.paths, "resolve");
  const value = {[Symbol.toPrimitive](hint) { trace.push(hint); return h.root; }};
  try {
    Object.defineProperty(h.paths, "resolve", {configurable:true, get() { trace.push("resolve"); return descriptor.value; }});
    let caught;
    try { h.realpath(value, {get encoding() { trace.push("encoding"); throw reason; }}); } catch (error) { caught = error; }
    classicSame(caught, reason, "ordinary options getter reason");
    classicList(trace, ["encoding"], "option failure stops before path conversion and resolve");
  } finally { classicRestore(h.paths, "resolve", descriptor); }
  let caught;
  try { h.realpath(Symbol("path")); } catch (error) { caught = error; }
  classicAssert(caught instanceof TypeError, "generic addition rejects Symbol");
}
function observeClassicTruthyCache(h) {
  const file = classicPath(h, "uncreated-cache-hit"), value = {}, trace = [];
  const from = Object.getOwnPropertyDescriptor(h.Buffer, "from");
  const cache = {get(path) { classicSame(this, cache, "cache receiver"); trace.push(path); return value; },
    set() { throw new Error("cache-hit set"); }};
  try {
    Object.defineProperty(h.Buffer, "from", {configurable:true, get() { throw new Error("cache-hit encoding"); }});
    classicSame(h.realpath(file, classicOptions(h, cache, "hex")), value, "truthy cached value returned as DATA");
    classicList(trace, [file], "one initial cache lookup with no OS access");
  } finally { classicRestore(h.Buffer, "from", from); }
}
function observeClassicLiveResolve(h) {
  const requested = classicPath(h, "directory-link/nested/end.txt"), expected = classicPath(h, "dir/nested/end.txt");
  const descriptor = Object.getOwnPropertyDescriptor(h.paths, "resolve"), trace = [];
  const hidden = ["dirname", "join", "toNamespacedPath"].map(key => [key, Object.getOwnPropertyDescriptor(h.paths, key)]);
  try {
    Object.defineProperty(h.paths, "resolve", {configurable:true, get() {
      trace.push("get");
      return function(...args) {
        classicSame(this, h.paths, "real path object receiver");
        trace.push(args);
        return Reflect.apply(descriptor.value, this, args);
      };
    }});
    for (const [key] of hidden) Object.defineProperty(h.paths, key, {configurable:true, get() { throw new Error("unselected public path method"); }});
    classicSame(h.realpath(requested), expected, "live public resolve path");
    classicSame(trace.length, 6, "initial resolve and two linked-path resolves");
    classicList(trace.filter((_, index) => index % 2 === 0), ["get","get","get"], "fresh callee at every Source call");
    classicList(trace[1], [requested], "initial argument");
    classicSame(trace[3].length, 2, "link target resolution arguments");
    classicSame(trace[5].length, 2, "suffix resolution arguments");
  } finally {
    classicRestore(h.paths, "resolve", descriptor);
    for (const [key, saved] of hidden) classicRestore(h.paths, key, saved);
  }
}
function observeClassicCacheOrder(h) {
  const file = classicPath(h, "dir/file.txt"), trace = [];
  let reads = 0;
  const cache = {
    get(path) {
      classicSame(this, cache, "cache get receiver");
      if (path === file) {
        reads++;
        trace.push("get" + reads);
        // The initial miss is followed by a separate strict-equality check.
        if (reads === 2) return file;
      }
      return undefined;
    },
    set(path, value) {
      classicSame(this, cache, "cache set receiver");
      if (path === file) { classicSame(value, file, "final cache value"); trace.push("set"); }
    },
  };
  classicSame(h.realpath(file, classicOptions(h, cache)), file, "cache hard-path equality");
  classicList(trace, ["get1", "get2", "set"], "strict-equality hit skips resolved-link lookup");
}
function observeClassicCachedLink(h) {
  const virtual = classicPath(h, "virtual"), request = classicPath(h, "virtual/nested/end.txt");
  const target = classicPath(h, "dir"), expected = classicPath(h, "dir/nested/end.txt"), trace = [];
  const cache = {
    get(path) { if (path === virtual) { trace.push("virtual"); return target; } return undefined; },
    set(path, value) { if (path === request) trace.push(value); },
  };
  classicSame(h.realpath(request, classicOptions(h, cache)), expected, "cached link changes the remaining component walk");
  classicList(trace, ["virtual", "virtual", expected], "equality and actual resolved-link lookup are distinct");
}
function observeClassicEncoding(h) {
  const file = classicPath(h, "dir/file.txt"), trace = [], sentinel = {};
  const original = Object.getOwnPropertyDescriptor(h.Buffer, "from");
  let reads = 0, asBuffer;
  const options = {get encoding() { reads++; trace.push("encoding" + reads); return reads === 6 ? "latin1" : "hex"; }};
  try {
    Object.defineProperty(h.Buffer, "from", {configurable:true, get() {
      trace.push("from");
      return function(result) {
        trace.push("from-call");
        classicSame(this, h.Buffer, "actual Buffer.from receiver");
        classicSame(result, file, "resolved path reaches Buffer.from");
        return asBuffer = {get toString() {
          trace.push("toString");
          return function(encoding) {
            trace.push("toString-call");
            classicSame(this, asBuffer, "actual buffer receiver");
            classicSame(encoding, "latin1", "last live encoding read");
            return sentinel;
          };
        }};
      };
    }});
    classicSame(h.realpath(file, options), sentinel, "arbitrary actual toString result");
    classicList(trace, ["encoding1","encoding2","encoding3","encoding4","from","from-call","encoding5","toString","encoding6","toString-call"], "exact live encoding and callee order");
  } finally { classicRestore(h.Buffer, "from", original); }
}
function observeClassicBuiltinEncoding(h) {
  const file = classicPath(h, "dir/file.txt");
  const bytes = h.realpath(file, "buffer");
  classicAssert(h.Buffer.isBuffer(bytes), "buffer encoding returns actual Buffer");
  classicSame(bytes.toString("utf8"), file, "actual UTF-8 path bytes");
  classicSame(h.realpath(file, "utf8"), file, "UTF-8 fast path");
  classicSame(h.realpath(file, "hex"), h.Buffer.from(file).toString("hex"), "actual Buffer hex encoding");
}
function observeClassicNativeErrors(h) {
  const missing = classicPath(h, "dir/missing.txt"), broken = classicPath(h, "broken-link");
  const ErrorOriginal = Error, descriptor = Object.getOwnPropertyDescriptor(globalThis, "Error");
  try {
    Object.defineProperty(globalThis, "Error", {configurable:true, get() { throw new ErrorOriginal("global Error must not be read"); }});
    for (const [path, syscall] of [[missing, "lstat"], [broken, "stat"]]) {
      let caught;
      try { h.realpath(path); } catch (error) { caught = error; }
      classicSame(Object.getPrototypeOf(caught), ErrorOriginal.prototype, "intrinsic UV Error");
      classicSame(caught.errno, h.platform === "win32" ? -4058 : -2, "actual numeric ENOENT");
      classicSame(caught.code, "ENOENT", "actual symbolic code");
      classicSame(caught.syscall, syscall, "actual failed operation");
      classicSame(caught.path, path, "actual namespace-stripped operation path");
      classicSame(caught.message, "ENOENT: no such file or directory, " + syscall + " '" + path + "'", "actual UV message");
      classicList(Object.keys(caught), ["errno","code","syscall","path"], "actual Set field order");
    }
  } finally { classicRestore(globalThis, "Error", descriptor); }
}
function observeClassicLinkLoop(h) {
  const loop = classicPath(h, "loop-a");
  let caught;
  try { h.realpath(loop); } catch (error) { caught = error; }
  classicSame(caught.code, "ELOOP", "real native link-loop error");
  classicSame(caught.syscall, "stat", "followed stat detects loop");
  classicSame(caught.path, loop, "loop error preserves operation path");
}
function observeClassicCapturedIntrinsics(h) {
  const requested = classicPath(h, "chain-file"), expected = classicPath(h, "dir/file.txt");
  const fields = [[String.prototype,"slice"],[String.prototype,"indexOf"],[String.prototype,"charCodeAt"],[BigInt.prototype,"toString"],
    [globalThis,"Map"],[globalThis,"Set"],[globalThis,"RegExp"],[globalThis,"Number"]];
  const saved = fields.map(([object,key]) => [object,key,Object.getOwnPropertyDescriptor(object,key)]);
  const poisoned = function() { throw new Error("late primordial lookup"); };
  try {
    for (const [object,key] of fields) Object.defineProperty(object,key,{configurable:true,writable:true,value:poisoned});
    classicSame(h.realpath(requested), expected, "bootstrap-captured collections/string/regex primitives");
  } finally {
    for (const [object,key,descriptor] of saved) classicRestore(object,key,descriptor);
  }
}
function observeClassicCacheSetFailure(h) {
  const file = classicPath(h, "dir/file.txt"), reason = {}, trace = [];
  const descriptor = Object.getOwnPropertyDescriptor(h.Buffer, "from");
  let sets = 0;
  const cache = {get() { return undefined; }, set(path) {
    if (path === file && ++sets === 2) { trace.push("set"); throw reason; }
  }};
  try {
    Object.defineProperty(h.Buffer, "from", {configurable:true, get() { trace.push("encode"); throw new Error("late encoding"); }});
    let caught;
    try { h.realpath(file, classicOptions(h, cache, "hex")); } catch (error) { caught = error; }
    classicSame(caught, reason, "cache setter ordinary reason");
    classicList(trace, ["set"], "final cache completion precedes encoding");
  } finally { classicRestore(h.Buffer, "from", descriptor); }
}

// Native-only finalizer controls. The actual C holder is created by the
// second full-path cache read and must retire before the third read.
function observeClassicCacheRetirement(h) {
  const file = classicPath(h, "dir/file.txt");
  let reads = 0;
  const cache = {get(path) {
    if (path === file) {
      reads++;
      if (reads === 2) { actualClassicVisit(0); return actualClassicHolder(); }
      if (reads === 3) { actualClassicVisit(1); classicSame(actualClassicFreed(), 1, "strict equality operand retired before resolved lookup"); }
    }
    return undefined;
  }, set() {}};
  try { return h.realpath(file, classicOptions(h, cache)); }
  catch (error) { actualClassicVisit(2); throw error; }
}
function observeClassicPrivateThrow(h) {
  const descriptor = Object.getOwnPropertyDescriptor(h.paths, "resolve");
  let reason, caught;
  try {
    Object.defineProperty(h.paths, "resolve", {configurable:true, get() {
      reason = actualClassicPrivateData();
      throw reason;
    }});
    try { h.realpath(h.root); } catch (error) { caught = error; }
    classicSame(caught, reason, "same-operation private DATA stays ordinary");
  } finally { classicRestore(h.paths, "resolve", descriptor); }
}
function observeClassicFlaggedCache(h) {
  const reason = actualClassicFlaggedData();
  const cache = {get() { return reason; }};
  const result = h.realpath(h.root, classicOptions(h, cache));
  classicSame(result, reason, "successful flagged cached DATA retains identity");
  return result;
}
function observeClassicSharedStatBuffers(h, numeric, bigint) {
  const file = classicPath(h, "dir/file.txt");
  const first = h.fs.statSync(file);
  classicSame(numeric[8], first.size, "public stat fills shared numeric size");
  classicSame(numeric[7], first.ino, "public stat fills shared numeric inode");
  const priorSize = numeric[8], second = h.fs.lstatSync(classicPath(h, "relative-file"), {bigint:true});
  classicSame(bigint[8], second.size, "public bigint lstat fills the shared bigint array");
  classicSame(bigint[7], second.ino, "public bigint lstat fills shared inode");
  classicSame(numeric[8], priorSize, "BigInt update keeps the numeric record");
}
