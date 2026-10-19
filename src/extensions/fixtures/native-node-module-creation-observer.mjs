// Node v24.14 observers over the actual constructor/createRequire component.
// Each exported observer runs in a fresh native Engine or a fresh pinned Node
// process. No observer loads a file or supplies a substitute Module namespace.
function moduleAssert(value, message) {
  if (!value) throw new Error("actual Module: " + message);
}
function moduleThrown(fn) {
  try { fn(); } catch (reason) { return reason; }
  throw new Error("actual Module: expected abrupt completion");
}
function moduleSame(actual, expected, message) {
  moduleAssert(actual.length === expected.length, message + " length");
  for (let i = 0; i < expected.length; i++)
    moduleAssert(actual[i] === expected[i], message + " item " + i);
}
function moduleRestore(object, name, descriptor) {
  if (descriptor === undefined) delete object[name];
  else Object.defineProperty(object, name, descriptor);
}
function moduleFilename(api, suffix = "unit.js") {
  return api.process.platform === "win32" ? "C:\\module-core\\" + suffix : "/module-core/" + suffix;
}
function moduleCapture(api, callback) {
  const descriptor = Object.getOwnPropertyDescriptor(api.Module.prototype, "filename");
  let created;
  Object.defineProperty(api.Module.prototype, "filename", {
    configurable: true,
    set(value) {
      created = this;
      Object.defineProperty(this, "filename", {value, writable:true, enumerable:true, configurable:true});
    }
  });
  try { return {value: callback(), module: () => created}; }
  finally { moduleRestore(api.Module.prototype, "filename", descriptor); }
}
export function observeModuleConstructor(api) {
  const M = api.Module;
  moduleAssert(M.name === "Module" && M.length === 0, "actual defaulted constructor shape");
  moduleAssert(M.Module === M && typeof M.createRequire === "function", "one declaration identity");
  moduleAssert(Object.getPrototypeOf(M._cache) === null && Object.getPrototypeOf(M._pathCache) === null, "actual null prototype caches");
  const first = new M();
  const second = new M("id");
  moduleSame(Object.keys(first), ["id","path","exports","filename","loaded","children"], "public initialization order");
  moduleAssert(first.id === "" && first.path === "." && first.filename === null && first.loaded === false, "default fields");
  moduleAssert(Array.isArray(first.children) && first.children.length === 0, "fresh child list");
  moduleAssert(first.exports !== second.exports && first.children !== second.children, "fresh instance owners");
  moduleAssert(first.constructor === M && first instanceof M, "same constructor prototype");
}
export function observeModuleAssignments(api) {
  const M = api.Module, prototype = M.prototype, path = api.path;
  const fields = ["id","path","filename","loaded","children","exports"];
  const saved = fields.map(name => [name, Object.getOwnPropertyDescriptor(prototype, name)]);
  const dirname = Object.getOwnPropertyDescriptor(path, "dirname");
  const visits = [];
  const pathValue = {exact:"dirname result"};
  let receiver, result;
  try {
    for (const name of fields) {
      Object.defineProperty(prototype, name, {configurable:true, set(value) {
        visits.push("set:" + name);
        if (name === "exports") throw Error("inherited exports setter must not run");
        Object.defineProperty(this, name, {value,writable:true,enumerable:true,configurable:true});
      }});
    }
    Object.defineProperty(path, "dirname", {configurable:true, get() {
      visits.push("get:dirname");
      return function(id) {
        visits.push("call:dirname");
        moduleAssert(this === path && id === "selected", "live dirname receiver and argument");
        return pathValue;
      };
    }});
    receiver = Object.create(prototype);
    result = M.call(receiver, "selected");
  } finally {
    Object.defineProperty(path, "dirname", dirname);
    for (const [name, descriptor] of saved) moduleRestore(prototype, name, descriptor);
  }
  moduleSame(visits, ["set:id","get:dirname","call:dirname","set:path","set:filename","set:loaded","set:children"], "constructor statements");
  moduleAssert(result === undefined && receiver.path === pathValue, "ordinary Module call retains raw dirname result");
  const descriptor = Object.getOwnPropertyDescriptor(receiver, "exports");
  moduleAssert(descriptor.writable && descriptor.enumerable && descriptor.configurable && typeof descriptor.value === "object", "exports uses own data definition");
}
export function observeModuleParent(api) {
  const M = api.Module;
  const parent = new M("parent"), first = new M("first", parent), next = new M("next", parent);
  moduleSame(parent.children, [first,next], "actual parent children append");
  moduleAssert(first.parent === parent && next.parent === parent, "actual first parent");
  const replacement = {replacement:true};
  first.parent = replacement;
  moduleAssert(first.parent === replacement && next.parent === parent, "separate parent slots");
  moduleSame(parent.children, [first,next], "parent setter does not append children");
}
export function observeModuleDescriptors(api) {
  const M = api.Module;
  const preload = Object.getOwnPropertyDescriptor(M.prototype, "isPreloading");
  const parent = Object.getOwnPropertyDescriptor(M.prototype, "parent");
  const constructor = Object.getOwnPropertyDescriptor(M.prototype, "constructor");
  for (const value of [preload,parent,constructor])
    moduleAssert(value.enumerable === false && value.configurable === false, "actual accessor flags");
  moduleAssert(preload.get.length === 0 && !Object.hasOwn(preload.get, "prototype"), "shorthand preload getter");
  moduleAssert(parent.get.length === 0 && parent.set.length === 1, "actual parent wrappers arities");
  moduleAssert(Object.hasOwn(parent.get, "prototype") && Object.hasOwn(parent.set, "prototype"), "ordinary pending-deprecation wrappers");
  moduleAssert(Object.hasOwn(constructor.get, "prototype") && constructor.get.call(null) === M, "ordinary constructor getter and lexical Module");
  moduleAssert(new M().isPreloading === false, "current actual preload state");
}
export function observeModulePaths(api) {
  const windows = api.process.platform === "win32";
  const input = windows ? "C:\\alpha\\node_modules\\beta" : "/alpha/node_modules/beta";
  const expected = windows
    ? ["C:\\alpha\\node_modules\\beta\\node_modules","C:\\alpha\\node_modules","C:\\node_modules"]
    : ["/alpha/node_modules/beta/node_modules","/alpha/node_modules","/node_modules"];
  moduleSame(api.Module._nodeModulePaths(input), expected, "reverse path scan");
  moduleSame(api.Module._nodeModulePaths(windows ? "D:\\" : "/"), windows ? ["D:\\node_modules"] : ["/node_modules"], "root branch");
  const unicode = windows ? "C:\\alpha\\😀\\leaf" : "/alpha/😀/leaf";
  moduleAssert(api.Module._nodeModulePaths(unicode)[0] === unicode + (windows ? "\\node_modules" : "/node_modules"), "UTF16 scan and sliced path");
}
function moduleIsNmChars(receiver) {
  return Array.isArray(receiver) && receiver.length === 12 && Object.hasOwn(receiver, "0") &&
    receiver[0] === 115 && receiver[11] === 110;
}
export function observeModulePathIndexedPrototype(api) {
  const saved = Object.getOwnPropertyDescriptor(Array.prototype, "12");
  let visits = 0, seen, result;
  Object.defineProperty(Array.prototype, "12", {configurable:true, get() {
    if (moduleIsNmChars(this)) { visits++; seen = this; return 120; }
    return undefined;
  }});
  try { result = api.Module._nodeModulePaths(moduleFilename(api, "xnode_modules")); }
  finally { moduleRestore(Array.prototype, "12", saved); }
  moduleAssert(visits === 1 && seen.length === 12 && !Object.hasOwn(seen, "12"), "real private nmChars inherited index");
  moduleAssert(result[0] === moduleFilename(api, "xnode_modules") + (api.process.platform === "win32" ? "\\node_modules" : "/node_modules"), "p beyond twelve still takes nonmatching separator branch");
}
export function observeModulePathIndexedThrow(api) {
  const saved = Object.getOwnPropertyDescriptor(Array.prototype, "12");
  const marker = {indexed:"ordinary throw"};
  let visits = 0, reason;
  Object.defineProperty(Array.prototype, "12", {configurable:true, get() {
    if (moduleIsNmChars(this)) { visits++; throw marker; }
    return undefined;
  }});
  try { reason = moduleThrown(() => api.Module._nodeModulePaths(moduleFilename(api, "xnode_modules"))); }
  finally { moduleRestore(Array.prototype, "12", saved); }
  moduleAssert(reason === marker && visits === 1, "actual indexed getter throw is propagated");
}
export function observeModulePathsPrimordials(api) {
  const targets = [[String.prototype,"charCodeAt"],[String.prototype,"slice"],[Array.prototype,"push"]];
  const saved = targets.map(([object,name]) => [object,name,Object.getOwnPropertyDescriptor(object,name)]);
  let result;
  try {
    for (const [object,name] of targets)
      Object.defineProperty(object,name,{configurable:true,get(){throw Error("late " + name);}});
    result = api.Module._nodeModulePaths(moduleFilename(api, "leaf"));
  } finally {
    for (const [object,name,descriptor] of saved) Object.defineProperty(object,name,descriptor);
  }
  moduleAssert(result[0] === moduleFilename(api, "leaf") + (api.process.platform === "win32" ? "\\node_modules" : "/node_modules"), "captured UTF16 and Array push primordials");
}
export function observeCreateRequireContexts(api) {
  const filename = moduleFilename(api);
  const capture = moduleCapture(api, () => api.Module.createRequire(filename));
  const require = capture.value, instance = capture.module();
  moduleAssert(instance instanceof api.Module && instance.filename === filename && instance.id === filename, "real createRequire Module");
  moduleAssert(instance.path === api.path.dirname(filename) && instance.loaded === false, "real constructor context");
  moduleSame(instance.paths, api.Module._nodeModulePaths(instance.path), "actual module path context");
  moduleAssert(typeof require === "function" && require.name === "require" && require.length === 1, "actual require shape");
  moduleAssert(require.resolve.name === "resolve" && require.resolve.length === 2 && require.resolve.paths.name === "paths" && require.resolve.paths.length === 1, "actual resolver declaration shapes");
  const main = Object.getOwnPropertyDescriptor(require,"main");
  moduleAssert(main.writable && main.enumerable && main.configurable && main.value === api.process.mainModule, "own main definition");
  const directory = moduleFilename(api, "");
  const next = moduleCapture(api, () => api.Module.createRequire(directory));
  moduleAssert(next.module().filename === api.path.join(directory,"noop.js"), "directory uses actual noop proxy path");
}
export function observeCreateRequireURL(api) {
  const href = api.process.platform === "win32" ? "file:///C:/module-core/url.js?selected=1#hash" : "file:///module-core/url.js?selected=1#hash";
  const capture = moduleCapture(api, () => api.Module.createRequire(href));
  const instance = capture.module();
  moduleAssert(instance.filename === moduleFilename(api,"url.js"), "actual URL conversion ignores search/hash for file path");
  moduleAssert(Object.getOwnPropertySymbols(instance).some(key => instance[key] === href), "Node24.14 Module retains actual URL href");
  const original = new URL(href);
  const again = moduleCapture(api, () => api.Module.createRequire(original));
  moduleAssert(again.module().filename === instance.filename, "actual URL object conversion");
}
export function observeCreateRequirePathCallees(api) {
  const M = api.Module, prototype = M.prototype, path = api.path;
  const oldPath = Object.getOwnPropertyDescriptor(prototype,"path");
  const oldPaths = Object.getOwnPropertyDescriptor(M,"_nodeModulePaths");
  const oldJoin = Object.getOwnPropertyDescriptor(path,"join");
  const visits = [], marker = {paths:true};
  let capture;
  try {
    Object.defineProperty(path,"join",{configurable:true,get(){
      visits.push("get:join");
      return function(dirname, leaf) {
        visits.push("call:join");
        moduleAssert(this === path && leaf === "noop.js", "selected join callee and receiver");
        return oldJoin.value.call(path,dirname,leaf);
      };
    }});
    Object.defineProperty(prototype,"path",{configurable:true,set(value){
      Object.defineProperty(this,"path",{configurable:true,get(){visits.push("get:module.path"); return value;}});
    }});
    Object.defineProperty(M,"_nodeModulePaths",{configurable:true,get(){
      visits.push("get:Module._nodeModulePaths");
      return function(value) {
        visits.push("call:Module._nodeModulePaths");
        moduleAssert(this === M && value === api.path.dirname(moduleFilename(api,"noop.js")), "actual paths call receiver and argument");
        return marker;
      };
    }});
    capture = moduleCapture(api, () => M.createRequire(moduleFilename(api,"")));
  } finally {
    Object.defineProperty(path,"join",oldJoin);
    Object.defineProperty(M,"_nodeModulePaths",oldPaths);
    moduleRestore(prototype,"path",oldPath);
  }
  moduleSame(visits, ["get:join","call:join","get:Module._nodeModulePaths","get:module.path","call:Module._nodeModulePaths"], "createRequire callee/reference order");
  moduleAssert(capture.module().paths === marker, "raw paths result assigned");
}
export function observeCreateRequireFailures(api) {
  for (const input of [undefined,null,1,{},Symbol("filename"),"relative.js","https://example.invalid/module.js"]) {
    const reason = moduleThrown(() => api.Module.createRequire(input));
    moduleAssert(reason instanceof TypeError && reason.code === "ERR_INVALID_ARG_VALUE", "actual invalid filename class");
    moduleAssert(reason.message.includes("'filename'") && reason.message.includes("must be a file URL object, file URL string, or absolute path string"), "actual filename message");
  }
  const saved = Object.getOwnPropertyDescriptor(api.path,"isAbsolute");
  const marker = {outside:"URL try"};
  let visits = 0, reason;
  Object.defineProperty(api.path,"isAbsolute",{configurable:true,get(){visits++; throw marker;}});
  try { reason = moduleThrown(() => api.Module.createRequire(moduleFilename(api))); }
  finally { Object.defineProperty(api.path,"isAbsolute",saved); }
  moduleAssert(reason === marker && visits === 1, "isAbsolute getter remains outside URL catch");
}
export function observeCreateRequireCapturedURL(api) {
  const url = Object.getOwnPropertyDescriptor(globalThis,"URL");
  const ends = Object.getOwnPropertyDescriptor(String.prototype,"endsWith");
  const href = api.process.platform === "win32" ? "file:///C:/module-core/captured.js" : "file:///module-core/captured.js";
  let capture;
  try {
    Object.defineProperty(globalThis,"URL",{configurable:true,get(){throw Error("late URL constructor");}});
    Object.defineProperty(String.prototype,"endsWith",{configurable:true,get(){throw Error("late endsWith");}});
    capture = moduleCapture(api, () => api.Module.createRequire(href));
  } finally {
    Object.defineProperty(globalThis,"URL",url);
    Object.defineProperty(String.prototype,"endsWith",ends);
  }
  moduleAssert(capture.module().filename === moduleFilename(api,"captured.js"), "retained URL and suffix primordials");
}
export function observeRequireCopiedFields(api) {
  const M = api.Module, process = api.process;
  const targets = [[process,"mainModule"],[M,"_extensions"],[M,"_cache"],
    [Function.prototype,"main"],[Function.prototype,"extensions"],[Function.prototype,"cache"]];
  const saved = targets.map(([object,name]) => [object,name,Object.getOwnPropertyDescriptor(object,name)]);
  const main = {main:true}, extensions = {extensions:true}, cache = {cache:true};
  const visits = [];
  let require, extensionsReceiver, cacheReceiver;
  try {
    Object.defineProperty(process,"mainModule",{configurable:true,get(){visits.push("get:main");return main;}});
    Object.defineProperty(M,"_extensions",{configurable:true,get(){visits.push("get:extensions");return extensions;}});
    Object.defineProperty(M,"_cache",{configurable:true,get(){visits.push("get:cache");return cache;}});
    Object.defineProperty(Function.prototype,"main",{configurable:true,set(){throw Error("main inherited setter");}});
    Object.defineProperty(Function.prototype,"extensions",{configurable:true,set(value){
      visits.push("set:extensions"); extensionsReceiver = this; moduleAssert(value === extensions,"extensions raw value");
    }});
    Object.defineProperty(Function.prototype,"cache",{configurable:true,set(value){
      visits.push("set:cache"); cacheReceiver = this; moduleAssert(value === cache,"cache raw value");
    }});
    require = M.createRequire(moduleFilename(api));
  } finally {
    for (const [object,name,descriptor] of saved) moduleRestore(object,name,descriptor);
  }
  moduleSame(visits,["get:main","get:extensions","set:extensions","get:cache","set:cache"],"makeRequire separate assignments");
  moduleAssert(require.main === main && extensionsReceiver === require && cacheReceiver === require, "actual require owns main and receives assignments");
}
export function observeRequireLiveDispatch(api) {
  const M = api.Module;
  const capture = moduleCapture(api, () => M.createRequire(moduleFilename(api)));
  const require = capture.value, instance = capture.module();
  const oldResolve = Object.getOwnPropertyDescriptor(M,"_resolveFilename");
  const oldPaths = Object.getOwnPropertyDescriptor(M,"_resolveLookupPaths");
  const rawRequire = {require:true}, rawResolve = {resolve:true}, rawPaths = {paths:true}, options = {};
  let requireCalls = 0, resolveReads = 0, pathsReads = 0;
  try {
    instance.require = function(request) {
      requireCalls++; moduleAssert(this === instance && request === "selected", "captured Module require receiver"); return rawRequire;
    };
    Object.defineProperty(M,"_resolveFilename",{configurable:true,get(){
      resolveReads++;
      return function(request,parent,isMain,receivedOptions) {
        moduleAssert(this === M && request === "selected" && parent === instance && isMain === false && receivedOptions === options,"resolve actual arguments");
        return rawResolve;
      };
    }});
    Object.defineProperty(M,"_resolveLookupPaths",{configurable:true,get(){
      pathsReads++;
      return function(request,parent) {
        moduleAssert(this === M && request === "selected" && parent === instance,"lookup actual arguments"); return rawPaths;
      };
    }});
    moduleAssert(require.call(null,"selected","ignored") === rawRequire && requireCalls === 1, "raw require completion");
    moduleAssert(require.resolve.call(null,"selected",options) === rawResolve && resolveReads === 1,"raw resolve completion");
    moduleAssert(require.resolve.paths.call(null,"selected") === rawPaths && pathsReads === 1,"raw paths completion");
    const first = moduleThrown(() => require.resolve({}));
    const second = moduleThrown(() => require.resolve.paths({}));
    moduleAssert(first.code === "ERR_INVALID_ARG_TYPE" && second.code === "ERR_INVALID_ARG_TYPE","real validateString");
    moduleAssert(resolveReads === 1 && pathsReads === 1,"validation retires before Module getter");
  } finally {
    moduleRestore(M,"_resolveFilename",oldResolve);
    moduleRestore(M,"_resolveLookupPaths",oldPaths);
  }
}
export function observeModuleWarnings(api) {
  const M = api.Module, process = api.process;
  const emit = Object.getOwnPropertyDescriptor(process,"emitWarning");
  const calls = [];
  const descriptor = Object.getOwnPropertyDescriptor(M.prototype,"parent");
  let first, parent, replacement;
  try {
    Object.defineProperty(process,"emitWarning",{configurable:true,writable:true,value:function(...args){calls.push([this,args]);}});
    parent = new M("parent"); first = new M("child",parent); replacement = {};
    moduleAssert(first.parent === parent && first.parent === parent,"warned getter body");
    first.parent = replacement;
    moduleAssert(first.parent === replacement,"warned setter body");
  } finally { Object.defineProperty(process,"emitWarning",emit); }
  moduleAssert(calls.length === 1 && calls[0][0] === undefined,"one code-deduplicated raw warning call");
  moduleSame(calls[0][1].slice(0,3),[
    "module.parent is deprecated due to accuracy issues. Please use require.main to find program entry point instead.",
    "DeprecationWarning","DEP0144"],"warning arguments");
  moduleAssert(calls[0][1][3] === descriptor.get,"actual deprecated callback passed");
}
export function observeModuleWarningFailure(api) {
  const M = api.Module, process = api.process;
  const emit = Object.getOwnPropertyDescriptor(process,"emitWarning");
  const marker = {warning:"ordinary throw"};
  let visits = 0, first, second, parent;
  try {
    Object.defineProperty(process,"emitWarning",{configurable:true,writable:true,value:function(){visits++;throw marker;}});
    parent = new M("parent");
    const child = new M("child",parent);
    first = moduleThrown(() => child.parent);
    second = child.parent;
  } finally { Object.defineProperty(process,"emitWarning",emit); }
  moduleAssert(first === marker && second === parent && visits === 1,"warned flag publishes before failed emit; later getter proceeds");
}
