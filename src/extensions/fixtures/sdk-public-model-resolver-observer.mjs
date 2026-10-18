// Public caller observers. Runtime objects are explicit mutable public inputs;
// dependency functions come from real retained native owners in both realms.
function assertModel(value, message) { if (!value) throw new Error(message); }
function runtimeFor(models, usable = () => false) {
    const runtime = {
        getModels() { assertModel(this === runtime && arguments.length === 0, "getModels receiver and arity"); return models; },
        getAvailable(_unused, _options) { assertModel(this === runtime, "getAvailable receiver"); return Promise.resolve(models); },
        hasConfiguredAuth(provider) { assertModel(this === runtime && arguments.length === 1, "auth receiver and arity"); return usable(provider); },
    };
    return runtime;
}
function observeModelChoices(api) {
    const named = { provider: "named", id: "item", name: "Named item" };
    const raw = { provider: "other", id: "named/item", name: "Gateway item" };
    let auth = [];
    let runtime = runtimeFor([named, raw], provider => { auth.push(provider); return provider === "other"; });
    assertModel(api.resolveCliModel({ cliModel: "named/item", modelRuntime: runtime }).model === raw, "sole usable raw provider beats unusable named match");
    runtime = runtimeFor([raw, named], () => false);
    assertModel(api.resolveCliModel({ cliModel: "named/item", modelRuntime: runtime }).model === named, "named match wins when no provider is usable");
    runtime = runtimeFor([raw, named], () => true);
    assertModel(api.resolveCliModel({ cliModel: "named/item", modelRuntime: runtime }).model === named, "usable named provider wins independent of catalog order");
    auth = [];
    runtime = runtimeFor([raw, named], provider => { auth.push(provider); return true; });
    assertModel(api.resolveCliModel({ cliModel: "named/item", inlineApiKey: true, modelRuntime: runtime }).model === named && auth.length === 0, "inline key suppresses stored-auth selection");
    const a = { provider: "zeta", id: "shared", name: "Shared" }, b = { provider: "alpha", id: "shared", name: "Shared" };
    const result = api.resolveCliModel({ cliModel: "shared", modelRuntime: runtimeFor([a, b]) });
    assertModel(result.model === undefined && result.error === 'Model "shared" is ambiguous across providers: alpha/shared, zeta/shared. No matching provider is authenticated. Use --provider or provider/model.', "deterministic ambiguity diagnostic");
    const aliases = [{ provider: "p", id: "base-20260101" }, { provider: "p", id: "base-latest" }, { provider: "p", id: "base" }];
    assertModel(api.resolveCliModel({ cliModel: "bas", modelRuntime: runtimeFor(aliases) }).model === aliases[1], "alias preference then descending id order");
}
function observeModelThinking(api) {
    const base = { provider: "p", id: "foo", name: "Foo" };
    const runtime = runtimeFor([base]);
    let result = api.resolveCliModel({ cliModel: "foo:high:low", modelRuntime: runtime });
    assertModel(result.model === base && result.thinkingLevel === "low" && result.warning === undefined, "recursive valid thinking suffix");
    result = api.resolveCliModel({ cliModel: "foo:invalid", modelRuntime: runtime });
    assertModel(result.model === undefined && result.error.includes("not found"), "strict invalid suffix stays part of id");
    const literal = { provider: "p", id: "foo:high", name: "Literal" };
    result = api.resolveCliModel({ cliModel: "foo:high", modelRuntime: runtimeFor([base, literal]) });
    assertModel(result.model === literal && result.thinkingLevel === undefined, "literal colon id precedes thinking suffix");
}
function observeModelFallback(api, _hooks, defaults) {
    const first = { provider: "openai", id: "other", name: "Other", reasoning: false, marker: "first" };
    const preferred = { provider: "openai", id: "gpt-5.5", name: "Default", reasoning: false, marker: "default" };
    const runtime = runtimeFor([first, preferred]);
    let result = api.resolveCliModel({ cliProvider: "OPENAI", cliModel: "custom:high", modelRuntime: runtime });
    assertModel(result.model.id === "custom" && result.model.name === "custom" && result.model.marker === "default" && result.model.reasoning === true && result.thinkingLevel === "high", "actual default template and parsed fallback thinking");
    result = api.resolveCliModel({ cliProvider: "openai", cliModel: "custom:high", cliThinking: "off", modelRuntime: runtime });
    assertModel(result.model.id === "custom:high" && result.model.reasoning === false && result.thinkingLevel === undefined, "explicit thinking retains custom suffix");
    const previous = defaults.openai;
    defaults.openai = "other";
    try {
        result = api.resolveCliModel({ cliProvider: "openai", cliModel: "custom", modelRuntime: runtime });
        assertModel(result.model.marker === "first" && result.warning === 'Model "custom" not found for provider "openai". Using custom model id.', "shared mutable actual default-map owner");
    } finally { defaults.openai = previous; }
}
function observeModelInputOrder(api) {
    const names = [], options = {};
    const runtime = runtimeFor([]);
    for (const [name, value] of [["cliProvider", undefined], ["cliModel", ""], ["cliThinking", "low"], ["inlineApiKey", true], ["modelRuntime", runtime]]) {
        Object.defineProperty(options, name, { get() { names.push(name); return value; } });
    }
    const result = api.resolveCliModel(options);
    assertModel(names.join() === "cliProvider,cliModel,cliThinking,inlineApiKey,modelRuntime", "complete destructuring precedes empty-model return");
    assertModel(Object.keys(result).join() === "model,warning,error" && result.model === undefined && result.error === undefined, "empty result field shape");
    const bad = { provider: "p", id: "zzz", name: { toLowerCase() { return undefined; } } };
    let caught;
    try { api.resolveCliModel({ cliModel: "target", modelRuntime: runtimeFor([bad]) }); } catch (error) { caught = error; }
    assertModel(caught instanceof TypeError, "name optional chain does not swallow undefined method return");
}
function observeModelOptionsBinding(api, hooks) {
    const keys = ["cliProvider", "cliModel", "cliThinking", "inlineApiKey", "modelRuntime"];
    const previous = keys.map(name => Object.getOwnPropertyDescriptor(Number.prototype, name));
    const marker = Symbol("one options BindingPattern receiver");
    const reads = [];
    const runtime = { getModels() {
        assertModel(hooks.count(0) === 1, "boxed options receiver retires before getModels");
        return [];
    } };
    const values = [undefined, "alpha", undefined, undefined, runtime];
    try {
        keys.forEach((name, index) => Object.defineProperty(Number.prototype, name, {
            configurable: true,
            get() {
                assertModel(typeof this === "object", "BindingPattern boxes a primitive options receiver");
                if (index === 0) Object.defineProperty(this, marker, { value: hooks.make(0) });
                else assertModel(Object.hasOwn(this, marker), "all options getters use one boxed receiver");
                reads.push(name);
                return values[index];
            },
        }));
        const result = api.resolveCliModel(41);
        assertModel(reads.join() === keys.join() && result.error.startsWith("No models available."), "boxed options keep declaration order and actual body");
        assertModel(hooks.count(0) === 1, "one BindingPattern temporary is retired");
        for (const value of [null, undefined]) {
            let caught;
            try { api.resolveCliModel(value); } catch (error) { caught = error; }
            assertModel(caught instanceof TypeError, "nullish options fail ToObject");
        }
    } finally {
        keys.forEach((name, index) => {
            if (previous[index]) Object.defineProperty(Number.prototype, name, previous[index]);
            else delete Number.prototype[name];
        });
    }
}
async function observeModelScopeAwait(api) {
    const model = { provider: "p", id: "alpha" }, options = { signal: { real: true } };
    const events = [], patterns = {};
    let returned = false;
    Object.defineProperty(patterns, Symbol.iterator, { get() {
        assertModel(returned, "patterns iterator starts after actual Await"); events.push("iterator");
        return function () { return ["alpha"][Symbol.iterator](); };
    } });
    const runtime = { get getAvailable() { events.push("getter"); return function (kind, received) {
        events.push("call"); assertModel(this === runtime && arguments.length === 2 && kind === undefined && received === options, "actual getAvailable arguments");
        return Promise.resolve([model]);
    }; } };
    const pending = api.resolveModelScopeWithDiagnostics(patterns, runtime, options);
    returned = true;
    assertModel(pending instanceof Promise && events.join() === "getter,call", "genuine immediate Promise and single Source Await");
    const result = await pending;
    assertModel(result.scopedModels[0].model === model && result.diagnostics.length === 0 && events.join() === "getter,call,iterator", "post-Await actual scope body");
}
async function observeModelScopeResults(api) {
    const alpha = { provider: "p", id: "alpha", name: "Alpha" };
    const bracket = { provider: "p", id: "bracketed[1m]", name: "Bracket" };
    let result = await api.resolveModelScopeWithDiagnostics(["alpha:high", "*alp*", "bracketed[1m]", "none"], runtimeFor([alpha, bracket]));
    assertModel(result.scopedModels.length === 2 && result.scopedModels[0].model === alpha && result.scopedModels[0].thinkingLevel === "high" && result.scopedModels[1].model === bracket, "actual matching and first-wins deduplication");
    assertModel(result.diagnostics.length === 1 && result.diagnostics[0].code === "no-match" && result.diagnostics[0].pattern === "none", "no-match warning");
    result = await api.resolveModelScopeWithDiagnostics(["alpha:bad:high"], runtimeFor([alpha]));
    assertModel(result.scopedModels[0].model === alpha && result.scopedModels[0].thinkingLevel === undefined && result.diagnostics[0].code === "invalid-thinking-level" && result.diagnostics[0].message === 'Invalid thinking level "bad" in pattern "alpha:bad". Using default instead.', "inner recursive warning suppresses outer thinking");
    const other = { provider: "a", id: "alpha" };
    result = await api.resolveModelScopeWithDiagnostics(["alpha"], runtimeFor([alpha, other]));
    assertModel(result.scopedModels.length === 2 && result.diagnostics[0].message === 'Pattern "alpha" matches several providers: a, p. Use provider/id to choose one.', "scope keeps every provider and warns deterministically");
}
async function observeModelScopeData(api, hooks, _defaults, rejected) {
    let data;
    const runtime = { get getAvailable() { return function () {
        data = hooks.freshPrivateData();
        if (rejected) return Promise.reject(data);
        throw data;
    }; } };
    let caught;
    try { await api.resolveModelScopeWithDiagnostics([], runtime); } catch (error) { caught = error; }
    assertModel(caught === data && hooks.isUnmarkedPrivateData(data), "ordinary same-call or Await rejection DATA identity");
}
async function observeModelScopeClose(api, _hooks, _defaults, nextThrows) {
    const original = { original: true }, replacement = { replacement: true };
    let closes = 0, nexts = 0;
    const pattern = { get includes() { throw original; } };
    const patterns = { [Symbol.iterator]() { return { next() {
        nexts++; if (nextThrows) throw original; return { done: false, value: pattern };
    }, get return() { closes++; return function () { throw replacement; }; } }; } };
    let caught;
    try { await api.resolveModelScopeWithDiagnostics(patterns, runtimeFor([])); } catch (error) { caught = error; }
    assertModel(caught === original && nexts === 1 && closes === (nextThrows ? 0 : 1), "actual outer IteratorClose and original Throw precedence");
}
async function observeModelScopeHeads(api, hooks) {
    const model = { provider: "p", id: "alpha" }; let nexts = 0;
    const patterns = { [Symbol.iterator]() { return { next() {
        nexts++;
        if (nexts === 2) assertModel(hooks.count(0) === 0, "previous pattern head survives next");
        if (nexts === 3) { assertModel(hooks.count(1) === 0, "last pattern head survives done"); return { done: true }; }
        const id = nexts;
        return { done: false, value: {
            holder: hooks.make(id - 1),
            includes() { if (id === 2) assertModel(hooks.count(0) === 1, "new head assignment precedes body"); return false; },
            trim() { return "alpha"; },
        } };
    } }; } };
    const result = await api.resolveModelScopeWithDiagnostics(patterns, runtimeFor([model]));
    assertModel(result.scopedModels.length === 1 && hooks.count(0) === 1 && hooks.count(1) === 1, "final uncaptured head retires at Source function exit");
}
function observeModelReceiver(api, hooks) {
    let made = 0, providers = 0;
    const model = {
        get id() { made++; return { holder: hooks.make(0), toLowerCase() { return "alpha"; } }; },
        get provider() { providers++; assertModel(hooks.count(0) === made, "id call receiver retires before provider getter"); return "p"; },
    };
    const result = api.resolveCliModel({ cliModel: "alpha", modelRuntime: runtimeFor([model]) });
    assertModel(result.model === model && made === 1 && providers === 1 && hooks.count(0) === 1, "actual nested id method producer boundary");
}
function observeModelReceiverFatal(api, hooks) {
    const model = {
        get id() { return { holder: hooks.make(0), toLowerCase() { return "alpha"; } }; },
        get provider() { hooks.visit(2); return "p"; },
    };
    hooks.armFatal(0);
    try { api.resolveCliModel({ cliModel: "alpha", modelRuntime: runtimeFor([model]) }); } catch (error) { hooks.visit(3); }
}
async function observeModelCurrentFatal(api, hooks) {
    const runtime = { get getAvailable() {
        const data = hooks.freshPrivateData();
        hooks.raiseNativeFatal();
        throw data;
    } };
    try { await api.resolveModelScopeWithDiagnostics([], runtime); } catch (error) { hooks.visit(3); }
}
async function observeModelCancellation(api, hooks) {
    let nexts = 0;
    const model = { provider: "p", id: "alpha" };
    const patterns = { [Symbol.iterator]() { return { next() {
        nexts++; if (nexts > 2) hooks.visit(1);
        return { done: false, value: {
            holder: hooks.make(nexts - 1),
            includes() { if (nexts === 2) hooks.visit(1); return false; },
            trim() { return "alpha"; },
        } };
    }, return() { hooks.visit(2); return { done: true }; } }; } };
    hooks.armCancel(0);
    await api.resolveModelScopeWithDiagnostics(patterns, runtimeFor([model]));
}

function observeModelSetSize(api, hooks) {
    const NativeSet = Set; let constructions = 0, coerced = false;
    const model = { provider: "p", id: "alpha" };
    globalThis.Set = function (values) {
        assertModel(new.target !== undefined && Array.isArray(values), "actual Set constructor and mapped argument");
        constructions++;
        const current = constructions;
        return { holder: hooks.make(0), get size() {
            return current === 1 ? { valueOf() { coerced = true; assertModel(hooks.count(0) === 1, "Set receiver retires before size coercion"); return 1; } } : 1;
        } };
    };
    try {
        const result = api.resolveCliModel({ cliModel: "alp", modelRuntime: runtimeFor([model]) });
        assertModel(result.model === model && coerced && constructions === 2 && hooks.count(0) === 2, "actual fuzzy provider count boundaries");
    } finally { globalThis.Set = NativeSet; }
}
