// Guest inputs/observations only. The implementation is actual Source or Zig/C.
export async function run(api, ownedPath) {
  const rows = [];
  const metadata = fn => ({ name: fn.name, length: fn.length, ownPrototype: Object.hasOwn(fn, "prototype"), asyncPrototype: Object.getPrototypeOf(fn) === Object.getPrototypeOf(async () => {}) });
  const auth = api.envApiKeyAuth("Owned API key", ["OWNED_FIRST", "OWNED_SECOND"]);
  rows.push({ case: "metadata", factory: metadata(api.envApiKeyAuth), lazyFactory: metadata(api.lazyOAuth), login: metadata(auth.login), resolve: metadata(auth.resolve), keys: Object.keys(auth) });

  {
    const log = [], env = { OWNED_CONFIG: "owned-config" };
    const credential = { get key() { log.push("credential.key"); return "owned-stored-key"; }, get env() { log.push("credential.env"); return env; } };
    const signal = { throwIfAborted() { log.push("signal.check"); } };
    const ctx = { env() { throw Error("stored credential consulted environment"); } };
    const input = { get ctx() { log.push("input.ctx"); return ctx; }, get credential() { log.push("input.credential"); return credential; }, get signal() { log.push("input.signal"); return signal; } };
    const result = await auth.resolve(input);
    rows.push({ case: "stored-getters", log, result, sameEnv: result.env === env });
  }
  {
    const log = [];
    const names = { [Symbol.iterator]() { log.push("iterator"); let index = 0; return { next() { log.push(`next:${index}`); return index < 3 ? { done: false, value: ["ONE", "TWO", "THREE"][index++] } : { done: true }; }, return() { log.push("return"); return {}; } }; } };
    const ctx = { async env(name) { log.push(`env:${name}:${this === ctx}`); return name === "TWO" ? "owned-env-key" : ""; } };
    const result = await api.envApiKeyAuth("Owned", names).resolve({ ctx, credential: { key: "" }, signal: { throwIfAborted() { log.push("check"); } } });
    rows.push({ case: "env-iterator", log, result });
  }
  {
    const log = [], reason = { owned: "abort-reason" };
    let aborted = false;
    const names = { [Symbol.iterator]() { return { next() { return { value: "ONE", done: false }; }, return() { log.push("return"); throw Error("owned close failure"); } }; } };
    const signal = { throwIfAborted() { if (aborted) throw reason; } };
    let sameReason = false;
    try { await api.envApiKeyAuth("Owned", names).resolve({ ctx: { async env() { aborted = true; return "owned-must-not-return"; } }, signal }); }
    catch (error) { sameReason = error === reason; }
    rows.push({ case: "abort-closes-preserving", log, sameReason });
  }
  {
    const log = [];
    const name = { [Symbol.toPrimitive](hint) { log.push(`name:${hint}`); return "Owned key"; } };
    const signal = { throwIfAborted() { log.push("check"); } };
    const interaction = { get signal() { log.push("signal"); return signal; }, get prompt() { log.push("prompt-get"); return async function(prompt) { log.push(`prompt-call:${this === interaction}`); rows.push({ case: "prompt-input", prompt }); return "owned-entered-key"; }; } };
    const result = await api.envApiKeyAuth(name, []).login(interaction);
    rows.push({ case: "login-getter-order", log, result });
  }
  {
    const reason = { owned: "prompt-failure" };
    let syncThrow = false, sameReason = false, promise;
    try { promise = auth.login({ signal: { throwIfAborted() {} }, prompt() { throw reason; } }); } catch { syncThrow = true; }
    try { await promise; } catch (error) { sameReason = error === reason; }
    rows.push({ case: "login-sync-failure-is-async", syncThrow, sameReason });
  }
  {
    const log = [], credential = { access: "owned-access" }, options = { owned: "options" };
    let loads = 0, release;
    const flow = { get login() { log.push("login-get"); return function(a, b) { log.push(`login:${this === flow}:${a === credential}:${b === options}:${arguments.length}`); return credential; }; }, refresh(a, b) { log.push(`refresh:${this === flow}:${a === credential}:${b === undefined}:${arguments.length}`); return options; }, async toAuth(a) { log.push(`toAuth:${this === flow}:${a === credential}:${arguments.length}`); return { apiKey: a.access }; } };
    const input = { get name() { log.push("name"); return "Owned OAuth"; }, get isSubscription() { log.push("isSubscription"); return true; }, get loginLabel() { log.push("loginLabel"); return "Owned sign in"; }, load() { loads++; log.push(`load:${this === input}`); return new Promise(resolve => { release = resolve; }); } };
    const lazy = api.lazyOAuth(input);
    const initialLog = [...log];
    const a = lazy.login(credential, options), b = lazy.refresh(credential);
    release(flow);
    const values = await Promise.all([a, b]);
    const request = await lazy.toAuth(credential);
    rows.push({ case: "lazy-load-delegation", initialLog, log, loads, identity: values[0] === credential && values[1] === options, request, metadata: [metadata(lazy.login), metadata(lazy.refresh), metadata(lazy.toAuth)], keys: Object.keys(lazy) });
  }
  {
    const reason = { owned: "load-failure" };
    let loads = 0, matches = 0;
    const lazy = api.lazyOAuth({ name: "Owned", load() { loads++; return Promise.reject(reason); } });
    for (let n = 0; n < 2; n++) try { await lazy.toAuth({}); } catch (error) { if (error === reason) matches++; }
    rows.push({ case: "lazy-rejection-cached", loads, matches });
  }
  {
    const reason = { owned: "sync-load-failure" };
    let loads = 0, matches = 0;
    const lazy = api.lazyOAuth({ name: "Owned", load() { loads++; throw reason; } });
    for (let n = 0; n < 2; n++) try { await lazy.toAuth({}); } catch (error) { if (error === reason) matches++; }
    rows.push({ case: "lazy-sync-throw-retries", loads, matches });
  }
  {
    let loads = 0, errors = 0;
    const lazy = api.lazyOAuth({ name: "Owned", load() { loads++; return undefined; } });
    for (let n = 0; n < 2; n++) try { await lazy.toAuth({}); } catch (error) { if (error instanceof TypeError) errors++; }
    rows.push({ case: "lazy-nullish-retries", loads, errors });
  }
  {
    const oldProcess = globalThis.process;
    const holder = oldProcess ?? {};
    const oldEnv = holder.env;
    holder.env = { OWNED_SPACE: "  owned value  ", OWNED_EMPTY: " \t ", OWNED_NUMBER: 12 };
    globalThis.process = holder;
    try {
      const context = api.defaultProviderAuthContext();
      rows.push({ case: "default-context-env", value: await context.env("OWNED_SPACE"), empty: (await context.env("OWNED_EMPTY")) === undefined, number: (await context.env("OWNED_NUMBER")) === undefined, missing: (await context.env("OWNED_MISSING")) === undefined });
      rows.push({ case: "default-context-owned-file", exists: await context.fileExists(ownedPath), missing: await context.fileExists(ownedPath + ".missing"), invalid: await context.fileExists({ startsWith() { throw Error("owned invalid path"); } }) });
    } finally { holder.env = oldEnv; globalThis.process = oldProcess; }
  }
  {
    const originalNow = Date.now, originalSet = globalThis.setTimeout, originalClear = globalThis.clearTimeout;
    const durations = [], subscriptions = [];
    let clock = 10000, timerId = 0;
    Date.now = () => clock;
    globalThis.setTimeout = (fn, ms) => { durations.push(ms); clock += Number(ms); Promise.resolve().then(fn); return ++timerId; };
    globalThis.clearTimeout = id => subscriptions.push(`clear:${id}`);
    const signal = { aborted: false, addEventListener(type, fn, opts) { subscriptions.push(`add:${type}:${opts.once}`); }, removeEventListener(type) { subscriptions.push(`remove:${type}`); } };
    try {
      const results = [{ status: "pending" }, { status: "slow_down", intervalSeconds: 2 }, { status: "complete", value: "owned-device-result" }];
      const options = { intervalSeconds: 0.25, expiresInSeconds: 10, waitBeforeFirstPoll: true, signal, async poll() { subscriptions.push(`poll:${this === options}`); return results.shift(); } };
      const value = await api.pollOAuthDeviceCodeFlow(options);
      rows.push({ case: "device-poll-intervals", durations, subscriptions, value, clock });
      signal.aborted = true;
      let message;
      try { await api.abortableSleep(1, signal, "Owned cancel"); } catch (error) { message = error.message; }
      rows.push({ case: "device-sleep-preabort", message });
      signal.aborted = false;
      try { await api.pollOAuthDeviceCodeFlow({ signal, expiresInSeconds: 0, poll() { throw Error("expired flow polled"); } }); } catch (error) { rows.push({ case: "device-expired-no-poll", message: error.message }); }
    } finally { Date.now = originalNow; globalThis.setTimeout = originalSet; globalThis.clearTimeout = originalClear; }
  }
  return rows;
}
