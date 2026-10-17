// Shared ORIGINAL/native observer. These are controlled caller inputs, not
// substitute SDK modules, a copied implementation, or an authored golden.
const insist = (condition, label) => { if (!condition) throw new Error(label); };
const deferred = () => { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; };
const credential = () => ({ type: "oauth", access: "owned-fixture", refresh: "owned-refresh", expires: 1 });
const rejection = async promise => { try { await promise; } catch (reason) { return reason; } throw new Error("expected rejection"); };
export const authAsyncNames = ["reloadFromStorageAsync", "readLatestData", "read", "modify", "delete", "list"];
export async function observeAuthStorage(AuthStorage) {
  const rows = [];
  const prototype = AuthStorage.prototype;
  rows.push({ case: "auth-method-shapes", methods: authAsyncNames.map(name => {
    const fn = prototype[name];
    insist(Object.getPrototypeOf(fn) === Object.getPrototypeOf(async function () {}), "real async prototype");
    insist(!Object.hasOwn(fn, "prototype"), "async method is nonconstructible");
    return { name: fn.name, length: fn.length, tag: Object.prototype.toString.call(fn) };
  }) });
  {
    const store = AuthStorage.inMemory({ fixture: credential() });
    const before = await store.read("fixture");
    const updated = await store.modify("fixture", async current => ({ ...current, access: "updated-fixture" }));
    const listed = await store.list();
    const after = await store.read("fixture");
    insist(before.access === "owned-fixture" && updated.access === "updated-fixture" && after.access === "updated-fixture", "real memory backend roundtrip");
    insist(listed.length === 1 && listed[0].providerId === "fixture" && listed[0].type === "oauth", "real metadata list");
    await store.delete("fixture");
    insist(await store.read("fixture") === undefined, "real delete");
    rows.push({ case: "real-memory-roundtrip", before, updated, listed, after, deleted: true });
  }
  {
    const store = AuthStorage.inMemory({ fixture: credential() });
    const calls = [], gate = deferred();
    Object.defineProperty(store, "readLatestData", { get() { calls.push("latest-get"); return function () { calls.push(this === store ? "latest-call-self" : "wrong-self"); return gate.promise; }; } });
    calls.push("before-call"); const promise = prototype.read.call(store, "fixture"); calls.push("after-call");
    let settled = false; promise.then(() => { settled = true; }); await Promise.resolve();
    insist(!settled, "read really awaits held data"); gate.resolve({ fixture: credential() });
    const value = await promise; insist(value.access === "owned-fixture", "held result");
    rows.push({ case: "read-await-and-live-getter", calls, value });
  }
  {
    const store = AuthStorage.inMemory(); let coerced = 0;
    const reason = { toString() { coerced++; return "must not format"; } };
    Object.defineProperty(store, "readLatestData", { get() { throw reason; } });
    let sync = false, promise; try { promise = prototype.read.call(store, "fixture"); } catch { sync = true; }
    insist(!sync && await rejection(promise) === reason && coerced === 0, "getter throw is raw asynchronous rejection");
    rows.push({ case: "getter-throw-rejects-not-sync", sync, exact: true, coerced });
  }
  {
    const store = AuthStorage.inMemory({ fixture: credential() }); const callbacks = [];
    const lock = store.storage.withLockAsync;
    store.storage.withLockAsync = function (fn, options) { callbacks.push(fn); return lock.call(this, fn, options); };
    await store.reloadFromStorageAsync(); await store.modify("fixture", async current => current); await store.delete("fixture");
    for (const fn of callbacks) insist(Object.getPrototypeOf(fn) === Object.getPrototypeOf(async () => {}) && !Object.hasOwn(fn, "prototype"), "real async storage callback");
    globalThis.__observedAuthAsyncCallbacks = callbacks;
    rows.push({ case: "storage-callback-shapes", callbacks: callbacks.map(fn => ({ name: fn.name, length: fn.length, tag: Object.prototype.toString.call(fn) })) });
  }
  {
    const store = AuthStorage.inMemory({ fixture: credential() }); const reason = { fixture: "rejection-data" };
    store.storage.withLockAsync = () => Promise.reject(reason);
    const snapshot = await store.readLatestData(); insist(snapshot.fixture.access === "owned-fixture", "ordinary rejection fallback");
    insist(await rejection(store.readLatestData({ signal: new AbortController().signal })) === reason, "signal preserves rejected data");
    rows.push({ case: "no-signal-fallback-and-signalled-rejection", snapshot, exact: true });
  }
  {
    const store = AuthStorage.inMemory(); const events = [];
    store.storage.withLockAsync = function () { events.push("lock-call"); return { get then() { events.push("then-get"); return resolve => { events.push("then-call"); resolve({ fixture: credential() }); }; } }; };
    events.push("before-call"); const promise = store.reloadFromStorageAsync(); events.push("after-call"); await promise;
    rows.push({ case: "direct-return-thenable-observation", events });
  }
  {
    let sync = false, promise; try { promise = prototype.read.call(null, "fixture"); } catch { sync = true; }
    const reason = await rejection(promise); insist(!sync && reason instanceof TypeError, "invalid receiver rejects asynchronously");
    rows.push({ case: "invalid-receiver-rejection", sync, errorName: reason.name });
  }
  return rows;
}
function reloadReceiver(events, settingsResult = Promise.resolve()) {
  const resources = () => ({ extensions: [], skills: [], prompts: [], themes: [] });
  return {
    loaded: false, settingsManager: { reload() { events.push("settings"); return settingsResult; }, setProjectTrusted(value) { events.push("trusted:" + value); } },
    packageManager: { resolve() { events.push("packages"); return Promise.resolve(resources()); }, resolveExtensionSources() { events.push("cli"); return Promise.resolve(resources()); } },
    additionalExtensionPaths: [], additionalSkillPaths: [], additionalPromptTemplatePaths: [], additionalThemePaths: [], disabledBuiltinExtensions: new Set(),
    noExtensions: true, noSkills: true, noPromptTemplates: true, noThemes: true, noContextFiles: true,
    systemPromptSource: "", appendSystemPromptSource: [], skillDiagnostics: [], promptDiagnostics: [], themeDiagnostics: [],
    mergePaths(first, second) { return [...first, ...second]; },
    loadFinalExtensionSet() { events.push("extensions"); return Promise.resolve({ extensions: [], errors: [], diagnostics: [] }); },
    applyExtensionSourceInfo() { events.push("source-info"); }, updateSkillsFromPaths() { events.push("skills"); }, updatePromptsFromPaths() { events.push("prompts"); }, updateThemesFromPaths() { events.push("themes"); },
    discoverAppendSystemPromptFile() { return undefined; }, discoverSystemPromptFile() { return undefined; },
  };
}
export async function observeResourceReload(DefaultResourceLoader) {
  const rows = [], reload = DefaultResourceLoader.prototype.reload;
  insist(Object.getPrototypeOf(reload) === Object.getPrototypeOf(async () => {}) && !Object.hasOwn(reload, "prototype"), "real reload AF shape");
  rows.push({ case: "reload-shape", name: reload.name, length: reload.length, tag: Object.prototype.toString.call(reload) });
  {
    const events = [], gate = deferred(), receiver = reloadReceiver(events, gate.promise);
    events.push("before-call"); const promise = reload.call(receiver); events.push("after-call");
    let settled = false; promise.then(() => { settled = true; }); await Promise.resolve();
    insist(!settled && !receiver.loaded && !events.includes("packages"), "reload held at Source settings Await");
    gate.resolve(); await promise; insist(receiver.loaded === true, "reload completes after real awaits");
    rows.push({ case: "reload-real-await-order", events, loaded: receiver.loaded });
  }
  {
    let coerced = 0; const reason = { toString() { coerced++; return "must not format"; } }, events = [];
    const receiver = reloadReceiver(events, Promise.reject(reason));
    insist(await rejection(reload.call(receiver)) === reason && !events.includes("packages") && coerced === 0, "raw rejection stops later phases");
    rows.push({ case: "reload-rejected-data", events, exact: true, coerced, loaded: receiver.loaded });
  }
  {
    const events = [], gate = deferred(), receiver = reloadReceiver(events); let gets = 0;
    receiver.loadProjectTrustExtensions = () => { events.push("trust-load"); return gate.promise; };
    const options = { get resolveProjectTrust() { gets++; events.push("resolve-get:" + gets); return function () { events.push(this === options ? "resolve-self" : "wrong-self"); return Promise.resolve(true); }; } };
    const promise = reload.call(receiver, options); gate.resolve({ extensions: [], errors: [] }); await promise;
    insist(gets === 2 && events.includes("resolve-self") && events.includes("trusted:true"), "Source rereads live resolver after Await");
    rows.push({ case: "reload-live-trust-getter", events, gets });
  }
  {
    const reason = { fixture: "options-getter" }, receiver = reloadReceiver([]);
    const options = { get resolveProjectTrust() { throw reason; } }; let sync = false, promise;
    try { promise = reload.call(receiver, options); } catch { sync = true; }
    insist(!sync && await rejection(promise) === reason, "options getter failure rejects asynchronously");
    rows.push({ case: "reload-start-getter-throw", sync, exact: true });
  }
  return rows;
}
export async function verifyNativeRejectedData(AuthStorage, DefaultResourceLoader, makeDataReason) {
  const reason = makeDataReason(); const store = AuthStorage.inMemory({ fixture: credential() });
  store.storage.withLockAsync = () => Promise.resolve().then(() => Promise.reject(makeDataReason()));
  const fallback = await store.readLatestData(); insist(fallback.fixture.access === "owned-fixture", "fresh tagged rejected DATA still takes Source fallback");
  store.storage.withLockAsync = () => Promise.reject(reason);
  insist(await rejection(store.readLatestData({ signal: new AbortController().signal })) === reason, "old flagged rejected DATA exact identity");
  const events = [], receiver = reloadReceiver(events, Promise.reject(reason));
  insist(await rejection(DefaultResourceLoader.prototype.reload.call(receiver)) === reason && !events.includes("packages"), "reload returns raw flagged rejection DATA");
  return { fallback: true, signalledExact: true, reloadExact: true };
}
