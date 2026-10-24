const trAssert = (value, message) => { if (!value) throw Error(message); };
const trSame = (a, b, message) => trAssert(JSON.stringify(a) === JSON.stringify(b), message + ": " + JSON.stringify(a));
const trContext = () => ({ hasUI: false, ui: { select() { throw Error("unexpected UI"); } } });
const trOptions = extra => Object.assign({ cwd: __trCwd, trustStore: __trStore, projectTrustContext: trContext() }, extra);
const trExtension = (path, handlers) => ({ path, handlers: new Map([["project_trust", handlers]]) });
const trExtensions = handlers => ({ extensions: [trExtension("/extension", handlers)] });
async function trRejected(value) {
  try { await value; } catch (reason) { return reason; }
  throw Error("Expected an actual rejected Promise");
}
async function observeResolutionShape(subject) {
  trAssert(__trIsAsync(subject) && subject.name === "resolveProjectTrusted" && subject.length === 1, "actual async shape");
  trAssert(!Object.hasOwn(subject, "prototype"), "no constructor prototype");
  let rejected = false;
  try { Reflect.construct(subject, []); } catch (e) { rejected = e instanceof TypeError; }
  trAssert(rejected, "actual nonconstructor");
  trAssert(__trManager.hasTrustRequiringProjectResources(__trCwd), "real physical resource exists");
  trAssert(await subject(trOptions()) === false, "original ask policy without UI");
  trAssert(!__trFS.existsSync(__trFile) && !__trFS.existsSync(__trFile + ".lock"), "read does not create trust data and releases actual lock");
}
async function observeResolutionOverride(subject) {
  let gets = 0;
  const result = await subject({
    get trustOverride() { return ++gets === 1 ? null : "exact-second-value"; },
    get cwd() { throw Error("override must precede cwd/resources"); },
    get trustStore() { throw Error("override must precede Store"); }
  });
  trAssert(result === "exact-second-value" && gets === 2, "defined override is reread and not coerced");
}
async function observeResolutionMissingOverride(subject) {
  const log = [];
  const options = trOptions({ defaultProjectTrust: "always" });
  Object.defineProperty(options, "trustOverride", { get() { log.push("override"); return undefined; } });
  trAssert(await subject(options) === true, "missing override follows actual Store then policy");
  trSame(log, ["override"], "absent override read exactly once");
}
async function observeResolutionNoResources(subject) {
  let cwdReads = 0;
  trAssert(await subject({
    get cwd() { cwdReads++; return __trCwd; },
    get extensionsResult() { throw Error("no resources precedes extensions"); },
    get trustStore() { throw Error("no resources precedes Store"); },
    get projectTrustContext() { throw Error("no resources precedes UI"); }
  }) === true, "no resources is trusted");
  trAssert(cwdReads === 1 && __trNoResourceCalls === 1, "single captured resource call");
}
async function observeResolutionExtensionOrder(subject) {
  const log = [], context = trContext(), winning = { trusted: "yes" };
  const extensions = trExtensions([function(event, ctx) { "use strict";
    log.push("handler");
    trAssert(this === undefined && event.type === "project_trust" && event.cwd === __trCwd && ctx === context, "exact extension inputs");
    trSame(Object.keys(event), ["type","cwd"], "event literal order"); return winning;
  }]);
  const options = {
    get cwd() { log.push("cwd"); return __trCwd; },
    get extensionsResult() { log.push("extensions"); return extensions; },
    get projectTrustContext() { log.push("context"); return context; },
    get trustStore() { throw Error("extension decision precedes Store"); }
  };
  trAssert(await subject(options) === true, "extension decides");
  trSame(log, ["cwd","extensions","extensions","cwd","context","handler"], "repeated extension/cwd/context order");
}
async function observeResolutionReportsBeforeDecision(subject) {
  const log = [];
  const winner = {
    get trusted() { log.push("trusted"); return "yes"; },
    get remember() { log.push("remember"); return false; }
  };
  const options = trOptions({
    extensionsResult: trExtensions([() => { throw Error("first"); }, () => winner]),
    onExtensionError(message) { "use strict";
      trAssert(this === options, "optional method retains options receiver");
      log.push("report:" + message);
    }
  });
  trAssert(await subject(options) === true, "winner after reporting");
  trSame(log, ["trusted",'report:Extension "/extension" project_trust error: first',"trusted","remember"], "reporting precedes resolver decision");
}
async function observeResolutionRemember(subject, trusted) {
  const result = { trusted: trusted ? "yes" : "arbitrary-non-undecided", remember: true };
  trAssert(await subject(trOptions({ extensionsResult: trExtensions([() => result]) })) === trusted, "strict yes conversion");
  trAssert(__trStore.get(__trCwd) === trusted, "actual Store remembers boolean decision");
  trAssert(__trFS.existsSync(__trFile) && !__trFS.existsSync(__trFile + ".lock"), "real trust file and released lock");
}
async function observeResolutionRememberStrict(subject) {
  trAssert(await subject(trOptions({ extensionsResult: trExtensions([() => ({ trusted: "yes", remember: 1 })]) })) === true, "extension yes");
  trAssert(!__trFS.existsSync(__trFile), "truthy remember is not strict true");
}
async function observeResolutionEmptyExtensionAwait(subject, present) {
  const log = [], get = __trStore.get;
  __trStore.get = function(cwd) { log.push("get"); return Reflect.apply(get, this, [cwd]); };
  const options = trOptions({ defaultProjectTrust: "always", extensionsResult: present ? { extensions: [] } : 0 });
  const pending = subject(options); log.push("caller");
  trAssert(await pending === true, "event exhaustion reaches Store/policy");
  trSame(log, present ? ["caller","get"] : ["get","caller"], "only actual extension branch introduces Await");
}
async function observeResolutionOptionalReport(subject) {
  const path = { toString() { throw Error("skipped template must not coerce"); } };
  const options = trOptions({ defaultProjectTrust: "always", extensionsResult: {
    extensions: [trExtension(path, [() => { throw "ordinary"; }])]
  }, onExtensionError: null });
  trAssert(await subject(options) === true, "nullish optional reporter skips entire template");
}
async function observeResolutionNoncallableReport(subject) {
  const log = [];
  const path = { toString() { log.push("path"); return "P"; } };
  const options = trOptions({ extensionsResult: {
    extensions: [trExtension(path, [() => { throw "ordinary"; }])]
  }, onExtensionError: 17 });
  trAssert(await trRejected(subject(options)) instanceof TypeError, "noncallable reporter rejects");
  trSame(log, ["path"], "optional noncallable check happens after arguments");
  trAssert(!__trFS.existsSync(__trFile), "report failure precedes Store");
}
async function observeResolutionReportClose(subject) {
  const prototype = Object.getPrototypeOf([][Symbol.iterator]());
  const saved = Object.getOwnPropertyDescriptor(prototype, "return");
  const marker = {}, later = {};
  let closed = 0;
  Object.defineProperty(prototype, "return", { configurable: true, value() { closed++; throw later; } });
  try {
    const options = trOptions({ extensionsResult: trExtensions([() => { throw "ordinary"; }]) });
    Object.defineProperty(options, "onExtensionError", { get() { throw marker; } });
    trAssert(await trRejected(subject(options)) === marker, "original body throw survives close failure");
    trAssert(closed === 1, "only error-loop iterator closes on report failure");
  } finally {
    if (saved) Object.defineProperty(prototype, "return", saved); else delete prototype.return;
  }
}
async function observeResolutionErrorStep(subject, valueFailure) {
  const saved = Object.getOwnPropertyDescriptor(Array.prototype, Symbol.iterator);
  const marker = {}; let closed = 0;
  const extensions = trExtensions([() => {
    Object.defineProperty(Array.prototype, Symbol.iterator, { configurable: true, value() {
      return { next() {
        if (!valueFailure) throw marker;
        return { done: false, get value() { throw marker; } };
      }, return() { closed++; return {}; } };
    }});
    throw "recorded first";
  }]);
  let reason;
  try { reason = await trRejected(subject(trOptions({ extensionsResult: extensions }))); }
  finally { Object.defineProperty(Array.prototype, Symbol.iterator, saved); }
  trAssert(reason === marker && closed === 0, "failed error next/value never closes its own iterator");
}
async function observeResolutionStorePriority(subject, trusted) {
  __trStore.set(__trCwd, trusted);
  const options = trOptions();
  Object.defineProperty(options, "defaultProjectTrust", { get() { throw Error("Store decision precedes defaults"); } });
  Object.defineProperty(options, "projectTrustContext", { get() { throw Error("Store decision precedes UI"); } });
  trAssert(await subject(options) === trusted, "real persisted Store decision takes priority");
}
async function observeResolutionStoreUndefined(subject) {
  __trStore.get = function() { return undefined; };
  const options = trOptions();
  Object.defineProperty(options, "defaultProjectTrust", { get() { throw Error("only null falls through"); } });
  trAssert(await subject(options) === undefined, "non-null Store value is returned without boolean conversion");
}
async function observeResolutionStoreGetOrder(subject) {
  const log = [], get = __trStore.get;
  Object.defineProperty(__trStore, "get", { configurable: true, get() {
    log.push("get-method"); return function(cwd) {
      trAssert(this === __trStore && cwd === __trCwd, "actual Store receiver and cwd");
      log.push("get-call"); return Reflect.apply(get, this, [cwd]);
    };
  }});
  const options = { defaultProjectTrust: "always",
    get cwd() { log.push("cwd"); return __trCwd; },
    get trustStore() { log.push("store"); return __trStore; }
  };
  trAssert(await subject(options) === true, "policy after null Store");
  trSame(log, ["cwd","store","get-method","cwd","get-call"], "read Store receiver/callee before second cwd");
}
async function observeResolutionDefaultLive(subject) {
  let reads = 0;
  Object.defineProperty(__trDefaults, "defaultProjectTrust", { configurable: true,
    get() { reads++; return reads === 1 ? "always" : "never"; } });
  trAssert(await subject(trOptions({ defaultProjectTrust: null })) === true, "null uses live shared default");
  trAssert(await subject(trOptions({ defaultProjectTrust: "always" })) === true && reads === 1, "nonnull option skips shared default");
  trAssert(await subject(trOptions()) === false && reads === 2, "later calls reread same default object");
}
async function observeResolutionUnknownPolicy(subject) {
  let hasUiReads = 0;
  const context = { get hasUI() { hasUiReads++; return false; } };
  const policy = { toString() { throw Error("Source switch never coerces policy"); } };
  trAssert(await subject(trOptions({ defaultProjectTrust: policy, projectTrustContext: context })) === false, "unknown policy falls to UI availability");
  trAssert(hasUiReads === 1, "one hasUI read");
}
async function observeResolutionSessionChoices(subject) {
  for (const trusted of [true, false]) {
    const label = trusted ? "Trust (this session only)" : "Do not trust (this session only)";
    const context = { hasUI: true, ui: { select(prompt, labels) {
      trAssert(labels.includes(label), "includeSessionOnly original option");
      trAssert(prompt === "Trust project folder?\n" + __trCwd + "\n\nThis allows " + __trConfig.APP_NAME +
        " to load " + __trConfig.CONFIG_DIR_NAME + " settings and resources, install missing project packages, and execute project extensions.", "exact original prompt");
      return label;
    }}};
    trAssert(await subject(trOptions({ projectTrustContext: context })) === trusted, "session decision");
    trAssert(!__trFS.existsSync(__trFile), "empty updates do not write Store");
  }
}
async function observeResolutionPhysicalSave(subject, parent) {
  const parentPath = __trManager.getProjectTrustParentPath(__trCwd);
  const context = { hasUI: true, ui: { select(_, labels) {
    const label = parent ? "Trust parent folder (" + parentPath + ")" : "Trust";
    trAssert(labels.includes(label), "actual option label"); return label;
  }}};
  trAssert(await subject(trOptions({ projectTrustContext: context })) === true, "selected physical trust");
  const entry = __trStore.getEntry(__trCwd);
  trAssert(entry !== null && entry.decision === true, "actual persisted trust entry");
  if (parent) trAssert(entry.path === parentPath, "actual parent update and child deletion");
  trAssert(__trFS.existsSync(__trFile) && !__trFS.existsSync(__trFile + ".lock"), "Store saved and lock released");
}
async function observeResolutionCancel(subject, missing) {
  const context = { hasUI: true, ui: { select() { return missing ? "no matching label" : undefined; } } };
  trAssert(await subject(trOptions({ projectTrustContext: context })) === false, "cancel or unmatched selection denies");
  trAssert(!__trFS.existsSync(__trFile), "no selected option performs no save");
}
async function observeResolutionUiRejection(subject) {
  const marker = {};
  const context = { hasUI: true, ui: { select() { return Promise.reject(marker); } } };
  trAssert(await trRejected(subject(trOptions({ projectTrustContext: context }))) === marker, "same rejection crosses both genuine async helpers");
  trAssert(!__trFS.existsSync(__trFile), "rejected selection never writes");
}
function prepareResolutionPromptOrder() {
  globalThis.__trTrace = [];
  const original = __trManager.getProjectTrustOptions;
  __trManager.getProjectTrustOptions = function(cwd, options) {
    __trTrace.push("getOptions");
    trAssert(options.includeSessionOnly === true && Object.keys(options).join() === "includeSessionOnly", "fresh original helper options");
    const rows = Reflect.apply(original, undefined, [cwd, options]);
    const map = rows.map, find = rows.find;
    Object.defineProperty(rows, "map", { get() { __trTrace.push("map"); return map; } });
    Object.defineProperty(rows, "find", { get() { __trTrace.push("find"); return find; } });
    return rows;
  };
  __trConfig.APP_NAME = { toString() { __trTrace.push("APP"); return "ActualName"; } };
  __trConfig.CONFIG_DIR_NAME = { toString() { __trTrace.push("CONFIG"); return ".actual-config"; } };
}
async function observeResolutionPromptOrder(subject) {
  const ui = { get select() { __trTrace.push("select"); return function(prompt, labels) {
    __trTrace.push("select-call"); trAssert(this === ui, "UI select receiver");
    trAssert(prompt.includes("ActualName to load .actual-config"), "captured imports use intrinsic template conversion");
    return labels[0];
  }; }};
  const context = { hasUI: true, get ui() { __trTrace.push("ui"); return ui; } };
  trAssert(await subject(trOptions({ projectTrustContext: context })) === true, "actual choice");
  trSame(__trTrace, ["getOptions","ui","select","APP","CONFIG","map","select-call","find"], "original select argument evaluation order");
}
function prepareResolutionLayers() {
  globalThis.__trTrace = [];
  const getOptions = __trManager.getProjectTrustOptions, setMany = __trStore.setMany;
  __trManager.getProjectTrustOptions = function(cwd, options) {
    const rows = Reflect.apply(getOptions, undefined, [cwd, options]), find = rows.find;
    rows.find = function(callback) { __trTrace.push("find"); return Reflect.apply(find, this, [callback]); };
    return rows;
  };
  __trStore.setMany = function(updates) { __trTrace.push("save"); return Reflect.apply(setMany, this, [updates]); };
}
async function observeResolutionLayers(subject) {
  const context = { hasUI: true, ui: { select(_, labels) { __trTrace.push("select"); return labels[0]; } } };
  const pending = subject(trOptions({ projectTrustContext: context }));
  __trTrace.push("caller");
  Promise.resolve().then(() => __trTrace.push("tick"));
  trAssert(await pending === true, "separate helper result");
  __trTrace.push("returned");
  trSame(__trTrace, ["select","caller","find","tick","save","returned"], "both original AsyncFunction Await layers retained");
}
function prepareResolutionSaveOrder() {
  globalThis.__trTrace = [];
  const getOptions = __trManager.getProjectTrustOptions, setMany = __trStore.setMany;
  __trManager.getProjectTrustOptions = function(cwd, options) {
    const rows = Reflect.apply(getOptions, undefined, [cwd, options]);
    const updates = rows[0].updates;
    let gets = 0;
    Object.defineProperty(rows[0], "updates", { get() { __trTrace.push("updates:" + ++gets); return updates; } });
    Object.defineProperty(rows[0], "trusted", { get() { __trTrace.push("trusted"); return true; } });
    return rows;
  };
  Object.defineProperty(__trStore, "setMany", { get() {
    __trTrace.push("setMany-get"); return function(updates) {
      __trTrace.push("setMany-call"); return Reflect.apply(setMany, this, [updates]);
    };
  }});
}
async function observeResolutionSaveOrder(subject) {
  const context = { hasUI: true, ui: { select(_, labels) { return labels[0]; } } };
  trAssert(await subject(trOptions({ projectTrustContext: context })) === true, "saved choice");
  trSame(__trTrace, ["updates:1","setMany-get","updates:2","setMany-call","trusted"], "length check precedes live setMany/second updates and trusted read");
}
function prepareResolutionEscapedFind() {
  const original = __trManager.getProjectTrustOptions;
  __trManager.getProjectTrustOptions = function(cwd, options) {
    const rows = Reflect.apply(original, undefined, [cwd, options]);
    rows.find = function(callback) {
      globalThis.__trEscapedFind = callback;
      trAssert(callback.length === 1 && !Object.hasOwn(callback, "prototype"), "original anonymous arrow");
      return rows[0];
    };
    return rows;
  };
}
async function observeResolutionEscapedFind(subject, hooks) {
  const context = { hasUI: true, ui: { select() { return hooks.make(0); } } };
  trAssert(await subject(trOptions({ projectTrustContext: context })) === true, "live find may choose original first option");
  __trGC();
  trAssert(hooks.count(0) === 0 && __trEscapedFind({ label: null }) === false, "escaped selected binding retained after both async calls");
  __trEscapedFind = null;
  __trGC();
  trAssert(hooks.count(0) === 1, "actual closed lexical binding retires once");
}
function prepareResolutionNamedCaptures() {
  globalThis.__trNamedReads = [];
  globalThis.__trCapturedName = __trConfig.APP_NAME;
  globalThis.__trCapturedDir = __trConfig.CONFIG_DIR_NAME;
  const options = __trManager.getProjectTrustOptions, resources = __trManager.hasTrustRequiringProjectResources;
  Object.defineProperty(__trConfig, "APP_NAME", { configurable: true, get() { __trNamedReads.push("APP_NAME"); return __trCapturedName; } });
  Object.defineProperty(__trConfig, "CONFIG_DIR_NAME", { configurable: true, get() { __trNamedReads.push("CONFIG_DIR_NAME"); return __trCapturedDir; } });
  Object.defineProperty(__trManager, "getProjectTrustOptions", { configurable: true, get() { __trNamedReads.push("getProjectTrustOptions"); return options; } });
  Object.defineProperty(__trManager, "hasTrustRequiringProjectResources", { configurable: true, get() { __trNamedReads.push("hasTrustRequiringProjectResources"); return resources; } });
}
async function observeResolutionNamedCaptures(subject) {
  trSame(__trNamedReads, ["APP_NAME","CONFIG_DIR_NAME","getProjectTrustOptions","hasTrustRequiringProjectResources"], "original named import order");
  for (const [object, keys] of [[__trConfig, ["APP_NAME","CONFIG_DIR_NAME"]],
    [__trManager, ["getProjectTrustOptions","hasTrustRequiringProjectResources"]]]) {
    for (const key of keys) Object.defineProperty(object, key, { configurable: true, get() { throw Error("must retain original named capture"); } });
  }
  const context = { hasUI: true, ui: { select(prompt, labels) {
    trAssert(prompt.includes("This allows " + __trCapturedName + " to load " + __trCapturedDir), "original primitive import captures");
    trAssert(labels.includes("Trust (this session only)"), "captured getOptions"); return "Trust (this session only)";
  }}};
  trAssert(await subject(trOptions({ projectTrustContext: context })) === true, "captured module bindings survive public mutations");
}
async function observeResolutionPrivateRejection(subject, hooks) {
  const data = hooks.freshPrivateData();
  const context = { hasUI: true, ui: { select() { return Promise.reject(data); } } };
  trAssert(await trRejected(subject(trOptions({ projectTrustContext: context }))) === data &&
    hooks.isUnmarkedPrivateData(data), "ordinary private rejection crosses both Await layers unchanged");
}
async function observeResolutionReentry(subject) {
  const log = [];
  const context = { hasUI: true, ui: { async select(_, labels) {
    log.push("select");
    trAssert(await subject({ trustOverride: true }) === true, "nested independent resolver");
    log.push("nested"); return labels[0];
  }}};
  trAssert(await subject(trOptions({ projectTrustContext: context })) === true, "outer selection remains live");
  trSame(log, ["select","nested"], "nested async execution");
}
async function observeResolutionAbandoned(subject, hooks) {
  globalThis.__trGate = new Promise(() => {});
  const context = Object.assign(hooks.make(1), { hasUI: true, ui: { select() { return globalThis.__trGate; } } });
  const options = Object.assign(hooks.make(0), { cwd: __trCwd, trustStore: __trStore, projectTrustContext: context });
  // This caller releases its own two holder references before dropping the
  // gate, so the actual async frames are their sole remaining owners.
  const pending = (() => Reflect.apply(subject, hooks.make(3), [options, hooks.make(2)]))();
  globalThis.__trPending = pending;
  return { release: () => { delete globalThis.__trGate; }, pending };
}
async function observeResolutionPendingNormal(subject) {
  const marker = new Error("actual pending selection");
  globalThis.__trPendingReason = marker;
  const context = { hasUI: true, ui: { select: __trPendingNative } };
  trAssert(await trRejected(subject(trOptions({ projectTrustContext: context }))) === marker, "actual pending wins successful native selection return");
  delete globalThis.__trPendingReason;
}
async function observeResolutionFatal(subject, hooks, reporter) {
  hooks.freshPrivateData();
  const prototype = Object.getPrototypeOf([][Symbol.iterator]());
  Object.defineProperty(prototype, "return", { configurable: true, value() { hooks.visit(2); return {}; } });
  const options = trOptions();
  if (reporter) {
    options.extensionsResult = trExtensions([() => { throw "ordinary report"; }]);
    options.onExtensionError = () => hooks.raiseNativeFatal();
  } else {
    options.projectTrustContext = { hasUI: true, ui: { select() { hooks.raiseNativeFatal(); } } };
  }
  try { await subject(options); } catch (_) { hooks.visit(3); }
  hooks.record.guestReached = true;
}
async function observeResolutionAbandonedControl(subject, hooks) {
  const handle = await observeResolutionAbandoned(subject, hooks);
  __trGC();
  for (let slot = 0; slot < 4; slot++) trAssert(hooks.count(slot) === 0, "both suspended helpers retain actual inputs");
  handle.release();
  __trGC();
  for (let slot = 0; slot < 4; slot++) trAssert(hooks.count(slot) === 1, "abandoned genuine async chain releases each argument once");
  trAssert(__trPromisePending(handle.pending), "outer Promise remains unsettled");
  delete globalThis.__trPending;
}

async function observeResolutionLiveExtension(subject) {
  const log = [];
  const changedCwd = __trPath.join(__trRoot, "after-extension");
  const changedStore = new __trManager.ProjectTrustStore(__trPath.join(__trRoot, "after-extension-agent"));
  const originalContext = trContext();
  let finish;
  const options = trOptions({ projectTrustContext: originalContext,
    extensionsResult: trExtensions([() => { throw Error("before wait"); }, (event, context) => {
      trAssert(event.cwd === __trCwd && context === originalContext, "event captures original call inputs");
      return new Promise(resolve => { finish = resolve; });
    }]),
    onExtensionError() { throw Error("old reporter must not be captured across Await"); }
  });
  const pending = subject(options);
  trAssert(typeof finish === "function", "actual handler reached its awaited Promise");
  options.cwd = changedCwd;
  options.trustStore = changedStore;
  options.onExtensionError = function(message) {
    trAssert(this === options, "live reporter receiver after Await"); log.push(message);
  };
  finish({ trusted: "yes", remember: true });
  trAssert(await pending === true && changedStore.get(changedCwd) === true, "post-Await cwd and genuine Store are live");
  trSame(log, ['Extension "/extension" project_trust error: before wait'], "live reporter selected after Await");
  trAssert(__trStore.get(__trCwd) === null && !__trFS.existsSync(__trFile), "original Store never receives remembered decision");
}
async function observeResolutionLiveSelection(subject) {
  const changedCwd = __trPath.join(__trRoot, "after-selection");
  const changedStore = new __trManager.ProjectTrustStore(__trPath.join(__trRoot, "after-selection-agent"));
  let finish;
  const context = { hasUI: true, ui: { select(_, labels) {
    trAssert(labels[0] === "Trust", "real selected option"); return new Promise(resolve => { finish = resolve; });
  }}};
  const options = trOptions({ projectTrustContext: context });
  const pending = subject(options);
  trAssert(typeof finish === "function", "actual UI Await reached");
  options.cwd = changedCwd;
  options.trustStore = changedStore;
  Object.defineProperty(options, "projectTrustContext", { get() { throw Error("context is not reread after selection"); } });
  finish("Trust");
  trAssert(await pending === true, "selected option succeeds");
  trAssert(changedStore.get(__trCwd) === true && changedStore.get(changedCwd) === null,
    "option updates retain pre-Await cwd while save uses live post-Await Store");
  trAssert(!__trFS.existsSync(__trFile), "original Store not used for selected save");
}
