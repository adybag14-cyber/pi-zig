// Genuine Node v24.14 search-path observers. Each entry runs in a fresh Engine
// or pinned Node process with module debug captured disabled. There is no file
// load and no substitute Module/path/process namespace.
function searchAssert(value, message) {
  if (!value) throw new Error("actual Module search paths: " + message);
}
function searchSame(actual, expected, message) {
  searchAssert(actual.length === expected.length, message + " length");
  for (let i = 0; i < expected.length; i++)
    searchAssert(actual[i] === expected[i], message + " item " + i);
}
function searchThrown(callback) {
  try { callback(); } catch (reason) { return reason; }
  throw new Error("actual Module search paths: expected abrupt completion");
}
function searchRestore(object, name, descriptor) {
  if (descriptor === undefined) delete object[name];
  else Object.defineProperty(object, name, descriptor);
}
function searchBaseline(api) {
  return api.Module._resolveLookupPaths("__actual_search_control_missing__");
}
function withSearchInit(api, callback) {
  searchAssert(api.process.platform === "win32", "selected genuine Windows environment branch");
  const fields = [
    [api.process, "env"], [api.process, "execPath"], [api.path, "resolve"],
    [api.path, "delimiter"], [api.Module, "globalPaths"],
  ];
  const saved = fields.map(([target, name]) => [target, name, Object.getOwnPropertyDescriptor(target, name)]);
  try { return callback(); }
  finally {
    for (const [target, name, descriptor] of saved) searchRestore(target, name, descriptor);
    api.Module._initPaths();
  }
}
export function observeSearchPathShapes(api) {
  for (const [name, length] of [["_resolveLookupPaths", 2], ["_initPaths", 0]]) {
    const value = api.Module[name], descriptor = Object.getOwnPropertyDescriptor(api.Module, name);
    searchAssert(value.name === "" && value.length === length && Object.hasOwn(value, "prototype"), "actual ordinary declaration " + name);
    searchAssert(descriptor.writable && descriptor.enumerable && descriptor.configurable, "actual assignment descriptor " + name);
  }
  const first = searchBaseline(api);
  searchAssert(Array.isArray(first) && first.length > 0, "actual initialized private search paths");
  searchAssert(first === searchBaseline(api) && first !== api.Module.globalPaths, "one private binding and separate public clone");
}
export function observeLookupBuiltinCoercion(api) {
  const M = api.Module;
  for (const name of ["fs", "node:fs", "node:test", "node:test/reporters"])
    searchAssert(M._resolveLookupPaths(name) === null, "actual permitted builtin " + name);
  searchAssert(M._resolveLookupPaths("test") === searchBaseline(api), "prefix-only builtin is not permitted without scheme");
  const hints = [];
  const request = { [Symbol.toPrimitive](hint) { hints.push(hint); return hints.length === 1 ? "node:missing" : "node:fs"; } };
  searchAssert(M._resolveLookupPaths(request) === null, "normalizer repeats actual Slice coercion");
  searchSame(hints, ["string", "string"], "prefix coercion order");
  const bareHints = [];
  const bare = { [Symbol.toPrimitive](hint) { bareHints.push(hint); return "fs"; } };
  searchAssert(M._resolveLookupPaths(bare) === searchBaseline(api), "bare membership does not replace the original object with its text");
  searchSame(bareHints, ["string", "string"], "normalizer then original CharAt coercion");
}
export function observeLookupParentArrayLike(api) {
  const base = searchBaseline(api), visits = [];
  let reads = 0;
  const parent = { get paths() {
    visits.push("paths:" + ++reads);
    if (reads === 1) return {get length() { visits.push("predicate:length"); return 1; }};
    return {
      get length() { visits.push("arguments:length"); return 2; },
      get 0() { visits.push("arguments:0"); return "first"; },
      get 1() { visits.push("arguments:1"); return "second"; },
      get [Symbol.iterator]() { throw Error("UnshiftApply must not iterate"); },
    };
  }};
  const result = api.Module._resolveLookupPaths("missing", parent);
  searchSame(visits, ["paths:1", "predicate:length", "paths:2", "arguments:length", "arguments:0", "arguments:1"], "selected optional chain and repeated array-like read");
  searchAssert(result !== base && result.length === base.length + 2, "actual private slice before prepend");
  searchSame(result.slice(0, 2), ["first", "second"], "actual array-like arguments");
  searchSame(result.slice(2), base, "original private suffix");
}
export function observeLookupOptionalPaths(api) {
  const base = searchBaseline(api);
  for (const parent of [undefined, null, false, {paths:null}, {paths:undefined}])
    searchAssert(api.Module._resolveLookupPaths("missing", parent) === base, "nullish optional-chain result");
  for (const length of [0, "", false, undefined, null]) {
    let reads = 0;
    const parent = { get paths() { reads++; return {length}; } };
    searchAssert(api.Module._resolveLookupPaths("missing", parent) === base && reads === 1, "actual falsy raw length");
  }
  let reads = 0, coerced = false;
  const parent = { get paths() {
    reads++;
    return reads === 1 ? {length:{[Symbol.toPrimitive]() { coerced = true; throw Error("predicate coerced"); }}} : [];
  }};
  const result = api.Module._resolveLookupPaths("missing", parent);
  searchAssert(!coerced && reads === 2 && result !== base, "truthy predicate object is not numerically coerced");
  searchSame(result, base, "empty second array-like value");
}
export function observeLookupRelativeOrder(api) {
  const path = api.path, saved = Object.getOwnPropertyDescriptor(path, "dirname"), visits = [];
  const filename = {exact:"second filename"}, result = {exact:"dirname result"};
  let reads = 0;
  const parent = {
    get id() { visits.push("id"); return "parent"; },
    get filename() { visits.push("filename"); return ++reads === 1 ? "first" : filename; },
  };
  try {
    Object.defineProperty(path, "dirname", {configurable:true, get() {
      visits.push("dirname:get");
      return function(value) {
        visits.push("dirname:call");
        searchAssert(this === path && value === filename, "actual dirname receiver and repeated filename");
        return result;
      };
    }});
    const paths = api.Module._resolveLookupPaths("./child", parent);
    searchSame(visits, ["id", "filename", "id", "dirname:get", "filename", "dirname:call"], "disabled debug still evaluates parent id");
    searchAssert(paths.length === 1 && paths[0] === result, "actual raw dirname return in fresh literal");
  } finally { Object.defineProperty(path, "dirname", saved); }
}
export function observeLookupRelativeShortCircuit(api) {
  for (const parent of [undefined, null, false, 0])
    searchSame(api.Module._resolveLookupPaths("./child", parent), ["."], "missing relative context");
  let visits = [];
  const first = {get id() { visits.push("id"); return ""; }, get filename() { throw Error("filename after falsy id"); }};
  searchSame(api.Module._resolveLookupPaths("../child", first), ["."], "falsy id fallback");
  searchSame(visits, ["id"], "id short circuit");
  visits = [];
  const second = {get id() { visits.push("id"); return "parent"; }, get filename() { visits.push("filename"); return ""; }};
  searchSame(api.Module._resolveLookupPaths("..", second), ["."], "falsy filename fallback");
  searchSame(visits, ["id", "filename"], "filename short circuit");
}
export function observeLookupAbruptOrder(api) {
  const reason = {ordinary:"selected getter"};
  searchAssert(searchThrown(() => api.Module._resolveLookupPaths("missing", {get paths() {throw reason;}})) === reason, "first parent path failure");
  searchAssert(searchThrown(() => api.Module._resolveLookupPaths("missing", {paths:{get length() {throw reason;}}})) === reason, "optional length failure");
  const saved = Object.getOwnPropertyDescriptor(api.path, "dirname");
  let ids = 0, filenames = 0, dirnames = 0;
  try {
    Object.defineProperty(api.path, "dirname", {configurable:true, get() {dirnames++; throw Error("dirname should not be selected");}});
    const parent = {get id() { if (++ids === 2) throw reason; return "id"; }, get filename() {filenames++; return "file"; }};
    searchAssert(searchThrown(() => api.Module._resolveLookupPaths("./child", parent)) === reason, "debug operand failure retains reason");
    searchAssert(ids === 2 && filenames === 1 && dirnames === 0, "debug operand precedes dirname");
    ids = 0; filenames = 0; dirnames = 0;
    Object.defineProperty(api.path, "dirname", {configurable:true, get() {dirnames++; throw reason;}});
    const next = {get id() {ids++; return "id";}, get filename() {filenames++; return "file";}};
    searchAssert(searchThrown(() => api.Module._resolveLookupPaths("./child", next)) === reason, "selected dirname getter failure");
    searchAssert(ids === 2 && filenames === 1 && dirnames === 1, "callee failure precedes repeated filename");
  } finally { Object.defineProperty(api.path, "dirname", saved); }
  searchAssert(searchThrown(() => api.Module._resolveLookupPaths(Symbol("request"))) instanceof TypeError, "intrinsic normalizer Symbol conversion");
}
export function observeLookupWindowsSpelling(api) {
  searchAssert(api.process.platform === "win32", "selected Windows lookup branch");
  const base = searchBaseline(api);
  for (const name of [".", "..", "...", "..x", "./child", "../child", ".\\child", "..\\child"])
    searchSame(api.Module._resolveLookupPaths(name), ["."], "relative spelling " + name);
  for (const name of [".name", "package", "C:\\absolute", "/absolute"])
    searchAssert(api.Module._resolveLookupPaths(name) === base, "nonrelative spelling " + name);
}
export function observeInitPathsClone(api) {
  const before = searchBaseline(api), published = api.Module.globalPaths;
  searchAssert(before !== published, "public paths is a clone");
  published.push("__public_only__");
  searchAssert(!before.includes("__public_only__"), "public array mutation does not edit lexical paths");
  api.Module._initPaths();
  const after = searchBaseline(api);
  searchAssert(after !== before && after !== api.Module.globalPaths, "new lexical value and a new clone");
  searchSame(after, api.Module.globalPaths, "clone contents");
}
export function observeInitPathsEvaluation(api) {
  withSearchInit(api, () => {
    const visits = [], M = api.Module, path = api.path;
    let envReads = 0;
    const env = {
      get USERPROFILE() { visits.push("home"); return "H"; },
      get NODE_PATH() { visits.push("node_path"); return {[Symbol.toPrimitive](hint) {visits.push("split:" + hint); return "a;;b;";}}; },
    };
    Object.defineProperty(api.process, "env", {configurable:true, get() {visits.push("env:" + ++envReads); return env;}});
    Object.defineProperty(api.process, "execPath", {configurable:true, get() {visits.push("execPath"); return "E";}});
    Object.defineProperty(path, "resolve", {configurable:true, get() {
      visits.push("resolve:get");
      return function(...args) { searchAssert(this === path, "actual resolve receiver"); visits.push("resolve:" + args.join(",")); return args.join("/"); };
    }});
    Object.defineProperty(path, "delimiter", {configurable:true, get() {visits.push("delimiter"); return ";";}});
    let publication;
    Object.defineProperty(M, "globalPaths", {configurable:true, set(value) {
      visits.push("globalPaths:set"); publication = value;
      const actual = searchBaseline(api);
      searchAssert(actual !== value, "private assignment precedes separate clone publication");
      searchSame(actual, value, "setter observes completed private binding");
    }});
    M._initPaths();
    searchSame(visits, ["env:1","home","env:2","node_path","resolve:get","execPath","resolve:E,..","resolve:get","resolve:E/..,lib,node","resolve:get","resolve:H,.node_libraries","resolve:get","resolve:H,.node_modules","delimiter","split:string","globalPaths:set"], "actual init expression order");
    searchSame(publication, ["a","b","H/.node_modules","H/.node_libraries","E/../lib/node"], "actual prepend/filter order");
  });
}
export function observeInitPathsFailurePublication(api) {
  withSearchInit(api, () => {
    const old = searchBaseline(api), published = api.Module.globalPaths, reason = {actual:"failure"};
    let resolveCalls = 0;
    Object.defineProperty(api.process, "env", {configurable:true, value:{USERPROFILE:"H",get NODE_PATH() {throw reason;}}});
    Object.defineProperty(api.path, "resolve", {configurable:true, value:function() {resolveCalls++; return "path";}});
    searchAssert(searchThrown(() => api.Module._initPaths()) === reason, "environment failure identity");
    searchAssert(resolveCalls === 0 && searchBaseline(api) === old && api.Module.globalPaths === published, "no assignment before environment completion");
    Object.defineProperty(api.process, "env", {configurable:true, value:{USERPROFILE:"",NODE_PATH:""}});
    Object.defineProperty(api.process, "execPath", {configurable:true, value:"executable"});
    let selected;
    Object.defineProperty(api.Module, "globalPaths", {configurable:true, set(copy) {
      selected = searchBaseline(api);
      searchAssert(selected !== old && copy !== selected, "private assignment already committed before public setter");
      searchSame(copy, selected, "actual clone passed to setter"); throw reason;
    }});
    searchAssert(searchThrown(() => api.Module._initPaths()) === reason, "public setter failure identity");
    searchAssert(searchBaseline(api) === selected, "ordinary setter failure retains new private binding");
  });
}
export function observeSearchCapturedPrimordials(api) {
  withSearchInit(api, () => {
    const fields = [
      [Array.prototype,"slice"],[Array.prototype,"unshift"],[Array.prototype,"filter"],
      [String.prototype,"split"],[String.prototype,"startsWith"],[String.prototype,"charAt"],
      [String.prototype,"charCodeAt"],[Reflect,"apply"],[globalThis,"Boolean"],
    ];
    const saved = fields.map(([object,name]) => [object,name,Object.getOwnPropertyDescriptor(object,name)]);
    Object.defineProperty(api.process,"env",{configurable:true,value:{USERPROFILE:"home",NODE_PATH:"a;;b"}});
    Object.defineProperty(api.process,"execPath",{configurable:true,value:"exe"});
    Object.defineProperty(api.path,"resolve",{configurable:true,value:function(first,second) {return first + "/" + second;}});
    Object.defineProperty(api.path,"delimiter",{configurable:true,value:";"});
    try {
      for (const [object,name] of fields)
        Object.defineProperty(object,name,{configurable:true,get() {throw Error("late primordial " + name);}});
      api.Module._initPaths();
      searchAssert(api.Module._resolveLookupPaths("node:fs") === null, "captured normalize methods");
      const value = api.Module._resolveLookupPaths("missing",{paths:{0:"parent",length:1}});
      searchAssert(value[0] === "parent" && value[1] === "a" && value[2] === "b", "captured slice/filter/split/unshift/apply");
    } finally {
      for (const [object,name,descriptor] of saved) Object.defineProperty(object,name,descriptor);
    }
  });
}
