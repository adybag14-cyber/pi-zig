'use strict';
// Authored observers of the selected genuine internal/options declarations.
function optionsAssert(value, message) {
  if (!value) throw new Error(message);
}
function optionsRestore(object, key, descriptor) {
  if (descriptor) Object.defineProperty(object, key, descriptor);
  else delete object[key];
}
function observeOptionsShapes(api) {
  const expected = [
    ["getOptionValue", 1], ["getEmbedderOptions", 0],
    ["refreshOptions", 0], ["getAllowUnauthorized", 0],
  ];
  for (const [name, length] of expected) {
    const fn = api[name];
    optionsAssert(typeof fn === "function" && fn.name === name && fn.length === length, "original ordinary function name/length " + name);
    optionsAssert(Object.getPrototypeOf(fn) === Function.prototype, "original function prototype " + name);
    const descriptor = Object.getOwnPropertyDescriptor(fn, "prototype");
    optionsAssert(descriptor && descriptor.writable && !descriptor.enumerable && !descriptor.configurable, "ordinary constructible function " + name);
    optionsAssert(descriptor.value.constructor === fn, "actual prototype constructor " + name);
  }
  optionsAssert(Array.isArray(new api.getOptionValue("--conditions")), "ordinary constructor keeps actual object return");
  const refreshed = new api.refreshOptions();
  optionsAssert(Object.getPrototypeOf(refreshed) === api.refreshOptions.prototype, "ordinary constructor keeps allocated receiver after undefined return");
}
function observeOptionsValues(api) {
  const conditions = api.getOptionValue("--conditions");
  optionsAssert(JSON.stringify(conditions) === '["base","environment","command"]', "native startup list order");
  optionsAssert(api.getOptionValue("--addons") === false && api.getOptionValue("--no-addons") === true, "actual native negative Boolean pair");
  optionsAssert(api.getOptionValue("--preserve-symlinks") === true && api.getOptionValue("--preserve-symlinks-main") === false, "actual native environment then exec options");
  optionsAssert(api.getOptionValue("--pending-deprecation") === true, "actual native environment startup selection");
  optionsAssert(api.getOptionValue("--strip-types") === true && api.getOptionValue("--experimental-quic") === undefined, "explicit native build inputs");
  optionsAssert(api.getOptionValue("unselected-name") === undefined, "absent selected dictionary property");
  const embedder = api.getEmbedderOptions();
  optionsAssert(Object.getPrototypeOf(embedder) === null, "actual native embedder record");
  optionsAssert(embedder.shouldNotRegisterESMLoader === false && embedder.noGlobalSearchPaths === false && embedder.noBrowserGlobals === false && embedder.hasEmbedderPreload === true, "actual native embedder fields");
}
function observeOptionsCache(api) {
  const first = api.getOptionValue("--conditions");
  optionsAssert(api.getOptionValue("--conditions") === first, "same original lazy dictionary");
  first.push("guest mutation");
  const embedder = api.getEmbedderOptions();
  embedder.hasEmbedderPreload = false;
  const env = process.env;
  const nodeOptions = Object.getOwnPropertyDescriptor(env, "NODE_OPTIONS");
  try {
    Object.defineProperty(env, "NODE_OPTIONS", {value:"--conditions=late", writable:true, configurable:true});
    optionsAssert(api.refreshOptions() === undefined, "refresh returns undefined");
    const second = api.getOptionValue("--conditions");
    optionsAssert(second !== first && JSON.stringify(second) === '["base","environment","command"]', "refresh serializes retained startup configuration");
    optionsAssert(api.getEmbedderOptions() === embedder && embedder.hasEmbedderPreload === false, "refresh only clears the original optionsDict binding");
  } finally { optionsRestore(env, "NODE_OPTIONS", nodeOptions); }
}
function observeOptionsKeyRefresh(api) {
  const original = api.getOptionValue("--conditions");
  let inside, count = 0;
  const selected = api.getOptionValue({
    [Symbol.toPrimitive](hint) {
      optionsAssert(hint === "string", "computed option key string hint");
      count++;
      api.refreshOptions();
      inside = api.getOptionValue("--conditions");
      return "--conditions";
    },
  });
  optionsAssert(count === 1 && selected === original && inside !== original && api.getOptionValue("--conditions") === inside, "computed key retains selected dictionary across refresh and reentry");
}
function observeOptionsWarningPredicate(api) {
  const actual = process;
  const env = actual.env;
  const valueDescriptor = Object.getOwnPropertyDescriptor(env, "NODE_TLS_REJECT_UNAUTHORIZED");
  const emitDescriptor = Object.getOwnPropertyDescriptor(actual, "emitWarning");
  const calls = [];
  Object.defineProperty(actual, "emitWarning", {configurable:true, value:function(message) {
    optionsAssert(this === actual && arguments.length === 1, "warning actual receiver and one argument");
    calls.push(message);
  }});
  try {
    for (const value of [0, false, null, undefined, { [Symbol.toPrimitive]() { throw Error("unexpected coercion"); } }]) {
      Object.defineProperty(env, "NODE_TLS_REJECT_UNAUTHORIZED", {configurable:true, value});
      optionsAssert(api.getAllowUnauthorized() === false, "strict string-only predicate");
    }
    Object.defineProperty(env, "NODE_TLS_REJECT_UNAUTHORIZED", {configurable:true, value:"0"});
    optionsAssert(api.getAllowUnauthorized() === true && api.getAllowUnauthorized() === true, "true predicate is still returned after first warning");
    const expected = "Setting the NODE_TLS_REJECT_UNAUTHORIZED environment variable to '0' makes TLS connections and HTTPS requests insecure by disabling certificate verification.";
    optionsAssert(calls.length === 1 && calls[0] === expected, "one exact original warning");
    Object.defineProperty(env, "NODE_TLS_REJECT_UNAUTHORIZED", {configurable:true, value:"1"});
    optionsAssert(api.getAllowUnauthorized() === false, "environment is reread after warning");
  } finally {
    optionsRestore(env, "NODE_TLS_REJECT_UNAUTHORIZED", valueDescriptor);
    optionsRestore(actual, "emitWarning", emitDescriptor);
  }
}
function observeOptionsWarningFailure(api) {
  const actual = process, env = actual.env;
  const valueDescriptor = Object.getOwnPropertyDescriptor(env, "NODE_TLS_REJECT_UNAUTHORIZED");
  const emitDescriptor = Object.getOwnPropertyDescriptor(actual, "emitWarning");
  const reason = new Error("ordinary warning getter");
  let visits = 0, caught = 0;
  Object.defineProperty(env, "NODE_TLS_REJECT_UNAUTHORIZED", {configurable:true, value:"0"});
  Object.defineProperty(actual, "emitWarning", {configurable:true, get() { visits++; throw reason; }});
  try {
    try { api.getAllowUnauthorized(); } catch (error) { optionsAssert(error === reason, "exact warning getter reason"); caught++; }
    optionsAssert(caught === 1 && visits === 1, "first warning getter throws");
    optionsAssert(api.getAllowUnauthorized() === true && visits === 1, "warn flag was stored before getter and stays cleared after throw");
  } finally {
    optionsRestore(env, "NODE_TLS_REJECT_UNAUTHORIZED", valueDescriptor);
    optionsRestore(actual, "emitWarning", emitDescriptor);
  }
}
function observeOptionsChainRetirement(api) {
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, "process");
  const original = process;
  const emit = Object.getOwnPropertyDescriptor(original, "emitWarning");
  let processReads = 0, warningCalls = 0;
  Object.defineProperty(original, "emitWarning", {configurable:true, get() {
    const holder = actualOptionsHolder(2);
    return function() { void holder; warningCalls++; optionsAssert(this === original, "selected warning receiver"); };
  }});
  Object.defineProperty(globalThis, "process", {configurable:true, get() {
    if (++processReads === 2) {
      optionsAssert(actualOptionsFreedCount(1) === 1, "env receiver retired before second process lookup");
      return original;
    }
    const holder = actualOptionsHolder(0);
    Object.defineProperty(holder, "env", {get() {
      const environment = actualOptionsHolder(1);
      Object.defineProperty(environment, "NODE_TLS_REJECT_UNAUTHORIZED", {get() {
        optionsAssert(actualOptionsFreedCount(0) === 1, "process receiver retired before environment field getter");
        return "0";
      }});
      return environment;
    }});
    return holder;
  }});
  try {
    optionsAssert(api.getAllowUnauthorized() === true, "ordinary chain completes");
    optionsAssert(processReads === 2 && warningCalls === 1 && actualOptionsFreedCount(2) === 1, "warning callee retires before next statement");
  } finally {
    optionsRestore(globalThis, "process", descriptor);
    optionsRestore(original, "emitWarning", emit);
  }
}
function observeOptionsPrivateData(api, route) {
  const reason = actualOptionsPrivateData();
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, "process");
  let caught = 0;
  try {
    if (route === 0) {
      try { api.getOptionValue({ [Symbol.toPrimitive]() { throw reason; } }); }
      catch (error) { optionsAssert(error === reason, "computed-key DATA identity"); caught++; }
    } else {
      const original = process;
      if (route === 1) {
        Object.defineProperty(globalThis, "process", {configurable:true, get() { throw reason; }});
      } else {
        Object.defineProperty(globalThis, "process", {configurable:true, value:{
          env: {NODE_TLS_REJECT_UNAUTHORIZED:"0"},
          get emitWarning() { if (route === 2) throw reason; return function() { throw reason; }; },
        }});
      }
      try { api.getAllowUnauthorized(); }
      catch (error) { optionsAssert(error === reason, "warning/process DATA identity"); caught++; }
      void original;
    }
    optionsAssert(caught === 1, "ordinary private DATA reaches one guest catch");
  } finally { optionsRestore(globalThis, "process", descriptor); }
}
function observeOptionsFlaggedReturn(api) {
  const reason = actualOptionsFlaggedData();
  globalThis.actualOptionsSelectedData = reason;
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, "process");
  let caught = 0;
  Object.defineProperty(globalThis, "process", {configurable:true, value:{
    env:{NODE_TLS_REJECT_UNAUTHORIZED:"0"},
    emitWarning() { return reason; },
  }});
  try {
    let returned;
    try { returned = api.getAllowUnauthorized(); } catch { caught++; }
    optionsAssert(returned === true && caught === 0, "successful flagged warning result remains discarded DATA");
  } finally { optionsRestore(globalThis, "process", descriptor); }
}
function installOptionsFatalRoute(retireProcess) {
  Object.defineProperty(globalThis, "process", {configurable:true, get() {
    actualOptionsProgress.process++;
    if (!retireProcess) {
      return {
        env:{NODE_TLS_REJECT_UNAUTHORIZED:"0"},
        get emitWarning() {
          actualOptionsProgress.warning++;
          return actualOptionsFatal();
        },
      };
    }
    const receiver = actualOptionsHolder(0);
    Object.defineProperty(receiver, "env", {get() {
      actualOptionsProgress.environment++;
      return {get NODE_TLS_REJECT_UNAUTHORIZED() {actualOptionsProgress.value++; return "0";}};
    }});
    return receiver;
  }});
}
