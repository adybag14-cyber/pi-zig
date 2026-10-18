// Controls over the complete c268 print body. Each Source/native selection gets
// a fresh Engine and the same genuine platform, child, shell and stdout owners.
// RuntimeHost objects below are explicit guest protocol observers.
const assertPrint = (value, message) => { if (!value) throw new Error(message); };
const settlePrint = async (predicate) => {
    for (let turn = 0; turn < 64 && !predicate(); turn++) await Promise.resolve();
    assertPrint(predicate(), "bounded print continuation did not reach its observer");
};
function printHost() {
    const row = { trace: [], prompts: [], disposals: 0, unsubscriptions: 0, backpressureUnsubscriptions: 0, binding: undefined, event: undefined, backpressure: undefined, rebind: undefined };
    const session = {
        sessionManager: { getHeader() { row.trace.push("header"); return { type: "session", id: "actual-print" }; } },
        state: { messages: [{ role: "assistant", stopReason: "stop", content: [{ type: "text", text: "answer" }, { type: "image", data: "ignored" }] }] },
        async bindExtensions(options) { assertPrint(this === session, "bind receiver"); row.trace.push("bind"); row.binding = options; },
        subscribe(callback) { assertPrint(this === session, "subscribe receiver"); row.trace.push("subscribe"); row.event = callback; return () => { row.trace.push("unsubscribe"); row.unsubscriptions++; }; },
        agent: { subscribe(callback) { assertPrint(this === session.agent, "agent receiver"); row.trace.push("agent-subscribe"); row.backpressure = callback; return () => { row.trace.push("backpressure-unsubscribe"); row.backpressureUnsubscriptions++; }; } },
        async prompt(message, options) { assertPrint(this === session, "prompt receiver"); row.trace.push("prompt"); row.prompts.push({ message, options, argc: arguments.length }); },
        waitForIdle() { assertPrint(this === session, "idle receiver"); return "idle"; },
        async navigateTree(target, options) { assertPrint(this === session, "navigate receiver"); row.navigation = [target, options]; return { cancelled: false, other: "excluded" }; },
        async reload() { assertPrint(this === session, "reload receiver"); row.trace.push("reload"); return "discarded"; },
    };
    const host = {
        session,
        setRebindSession(callback) { assertPrint(this === host, "setRebind receiver"); row.trace.push("set-rebind"); row.rebind = callback; },
        async dispose() { assertPrint(this === host, "dispose receiver"); row.trace.push("dispose"); row.disposals++; },
        newSession(options) { assertPrint(this === host, "newSession receiver"); row.newOptions = options; return { then(resolve) { row.trace.push("adopt-new"); resolve("new-result"); } }; },
        async fork(entry, options) { assertPrint(this === host, "fork receiver"); row.fork = [entry, options]; return { cancelled: true, other: "excluded" }; },
        switchSession(path, options) { assertPrint(this === host, "switch receiver"); row.switch = [path, options]; return { then(resolve) { row.trace.push("adopt-switch"); resolve("switch-result"); } }; },
    };
    row.host = host; return row;
}
function observeSignalCalls() {
    const originalOn = process.on, originalOff = process.off;
    const rows = [];
    process.on = function (signal, handler) { assertPrint(this === process, "on receiver"); rows.push(["on", signal, handler]); return Reflect.apply(originalOn, this, [signal, handler]); };
    process.off = function (signal, handler) { assertPrint(this === process, "off receiver"); rows.push(["off", signal, handler]); return Reflect.apply(originalOff, this, [signal, handler]); };
    return { rows, restore() { process.on = originalOn; process.off = originalOff; } };
}
async function observePrintText() {
    const row = printHost(), signals = observeSignalCalls(), images = [{ type: "image", data: "original" }];
    try {
        const result = await selectedPrint.runPrintMode(row.host, { mode: "text", initialMessage: "initial", initialImages: images, messages: ["one", "two"] });
        assertPrint(result === 0, "text exit status");
        assertPrint(row.prompts.length === 3 && row.prompts[0].options.images === images && row.prompts[0].argc === 2, "initial images and argument count");
        assertPrint(row.prompts[1].message === "one" && row.prompts[2].message === "two" && row.prompts[1].argc === 1, "serial additional prompts");
        assertPrint(printWrites.join("") === "answer\n" && printErrors.length === 0, "actual raw text output");
        assertPrint(row.binding.mode === "print" && row.disposals === 1 && row.unsubscriptions === 1 && row.backpressureUnsubscriptions === 0, "print disposal");
        const ons = signals.rows.filter(x => x[0] === "on"), offs = signals.rows.filter(x => x[0] === "off");
        assertPrint(ons.length === (process.platform === "win32" ? 1 : 2) && offs.length === ons.length, "actual signal cleanup count");
        for (let index = 0; index < ons.length; index++) assertPrint(ons[index][1] === offs[index][1] && ons[index][2] === offs[index][2], "same signal handler cleanup");
    } finally { signals.restore(); }
}
async function observePrintJson() {
    const row = printHost();
    row.host.session.prompt = async function (message) {
        row.prompts.push(message);
        row.event({ type: "message_update", message: { role: "assistant", usage: { tokens: 7 } }, assistantMessageEvent: { type: "toolcall_start", partial: { content: [{ type: "toolCall", id: "call-1", name: "read" }] }, contentIndex: 0, extra: true } });
        assertPrint(Object.prototype.toString.call(row.backpressure) === "[object AsyncFunction]", "actual agent backpressure arrow");
        await row.backpressure();
    };
    assertPrint(await selectedPrint.runPrintMode(row.host, { mode: "json", messages: ["question"] }) === 0, "json exit");
    const lines = printWrites.join("").trim().split("\n").map(line => JSON.parse(line));
    assertPrint(lines.length === 2 && lines[0].type === "session" && lines[0].id === "actual-print", "actual header before events");
    const projected = lines[1];
    assertPrint(projected.type === "message_update" && projected.usage.tokens === 7, "event usage");
    assertPrint(projected.assistantMessageEvent.id === "call-1" && projected.assistantMessageEvent.toolName === "read" && !("partial" in projected.assistantMessageEvent), "actual JSON projection");
    assertPrint(row.trace.indexOf("header") < row.trace.indexOf("bind") && row.binding.mode === "json", "json header and bind order");
    assertPrint(row.disposals === 1 && row.unsubscriptions === 1 && row.backpressureUnsubscriptions === 1, "json unsubscribe and dispose");
}
async function observePrintActions() {
    const row = printHost(); let releasePrompt;
    row.host.session.prompt = () => new Promise(resolve => { releasePrompt = resolve; });
    const running = selectedPrint.runPrintMode(row.host, { mode: "control", messages: ["wait"] });
    await settlePrint(() => releasePrompt !== undefined);
    const actions = row.binding.commandContextActions;
    assertPrint(Object.keys(actions).join() === "waitForIdle,newSession,fork,navigateTree,switchSession,reload", "actual action order");
    for (const [name, length] of [["newSession", 1], ["fork", 2], ["navigateTree", 2], ["switchSession", 2], ["reload", 0]]) {
        const fn = actions[name];
        assertPrint(fn.name === name && fn.length === length && Object.prototype.toString.call(fn) === "[object AsyncFunction]" && !Object.hasOwn(fn, "prototype"), "genuine action shape " + name);
    }
    assertPrint(actions.waitForIdle() === "idle" && !Object.hasOwn(actions.waitForIdle, "prototype"), "ordinary idle arrow");
    const options = { real: true };
    assertPrint(await actions.newSession(options) === "new-result" && row.newOptions === options, "actual return adoption");
    assertPrint(await actions.switchSession("saved", options) === "switch-result" && row.switch[1] === options, "switch return adoption");
    assertPrint(JSON.stringify(await actions.fork("entry", options)) === '{"cancelled":true}' && row.fork[1] === options, "fork Await projection");
    const reads = [], navigation = {};
    for (const name of ["summarize", "customInstructions", "replaceInstructions", "label"]) Object.defineProperty(navigation, name, { get() { reads.push(name); return name; } });
    assertPrint(JSON.stringify(await actions.navigateTree("target", navigation)) === '{"cancelled":false}', "navigate Await projection");
    assertPrint(reads.join() === "summarize,customInstructions,replaceInstructions,label" && row.navigation[1].label === "label", "live navigation arguments");
    assertPrint(await actions.reload() === undefined, "reload Await discards result");
    const next = printHost(); next.host.session.waitForIdle = () => "new-idle"; row.host.session = next.host.session;
    await row.rebind();
    assertPrint(actions.waitForIdle() === "new-idle" && next.binding.mode === "print" && row.unsubscriptions === 1, "old closures read the reassigned actual session binding");
    releasePrompt();
    assertPrint(await running === 0 && next.unsubscriptions === 1 && row.disposals === 1, "rebound disposal");
}
async function observePrintTdz() {
    const row = printHost(); let early;
    row.host.setRebindSession = callback => { row.rebind = callback; early = callback().catch(error => error); };
    assertPrint(await selectedPrint.runPrintMode(row.host, { mode: "control" }) === 0, "TDZ does not replace later rebind");
    const failure = await early;
    assertPrint(failure instanceof ReferenceError && failure.message === "rebindSession is not initialized", "actual captured uninitialized lexical cell");
    await row.rebind();
    assertPrint(row.disposals === 1, "escaped closed rebind callback remains callable");
}
async function observePrintSetupFailure(which) {
    const row = printHost(), signals = observeSignalCalls(), reason = { kind: which };
    if (which === "session") Object.defineProperty(row.host, "session", { get() { throw reason; } });
    else row.host.setRebindSession = () => { throw reason; };
    let thrown;
    try { await selectedPrint.runPrintMode(row.host, { mode: "control" }); } catch (error) { thrown = error; }
    assertPrint(thrown === reason && row.disposals === 0 && printErrors.length === 0, "setup remains outside Source try");
    assertPrint(signals.rows.filter(x => x[0] === "off").length === 0, "setup failure does not invent finally");
    assertPrint((signals.rows.length === 0) === (which === "session"), "setup registration boundary");
    signals.restore();
}
async function observePrintPromptClose(nextThrows) {
    const row = printHost(), first = new Error("first prompt reason"), close = new Error("close replacement");
    let nexts = 0, closes = 0;
    const messages = { [Symbol.iterator]() { return { next() { nexts++; if (nextThrows) throw first; return { done: false, value: "one" }; }, get return() { closes++; return function () { throw close; }; } }; } };
    row.host.session.prompt = async () => { throw first; };
    assertPrint(await selectedPrint.runPrintMode(row.host, { mode: "control", messages }) === 1, "ordinary catch exit");
    assertPrint(nexts === 1 && closes === (nextThrows ? 0 : 1), "actual for-of IteratorClose boundary");
    assertPrint(printErrors.length === 1 && printErrors[0][0] === "first prompt reason" && row.disposals === 1, "first DATA before close and finally");
}
async function observePrintFinalFailure(which) {
    const row = printHost(), first = new Error(which), originalOff = process.off;
    if (which === "cleanup") process.off = () => { throw first; };
    else if (which === "dispose") row.host.dispose = async () => { row.disposals++; throw first; };
    else {
        first.code = "EPIPE"; globalThis.printWriteFailure = first;
        process.exit = code => { assertPrint(code === 1, "raw output exit code"); };
    }
    let thrown;
    try { await selectedPrint.runPrintMode(row.host, { mode: which === "flush" ? "text" : "control" }); } catch (error) { thrown = error; }
    assertPrint(thrown === first, "finally failure overrides return");
    assertPrint(row.disposals === (which === "cleanup" ? 0 : 1), "cleanup before dispose before flush");
    assertPrint(printErrors.length === 0, "Source catch does not catch its finally");
    process.off = originalOff;
}
async function observePrintStatus(reason) {
    const row = printHost();
    row.host.session.state.messages[0].stopReason = reason;
    if (reason === "error") row.host.session.state.messages[0].errorMessage = "provider detail";
    assertPrint(await selectedPrint.runPrintMode(row.host, { mode: "text" }) === 1, "assistant failure exit");
    const expected = reason === "error" ? "provider detail" : reason === "aborted" ? "Request aborted" : "Response was truncated: the model reached its output token limit.";
    assertPrint(printErrors.length === 1 && printErrors[0][0] === expected, "Source diagnostic");
    assertPrint(printWrites.join("") === (reason === "length" ? "answer\n" : ""), "failure output boundary");
}
async function observePrintMessageLocals() {
    const row = printHost(); let nexts = 0, prompts = 0;
    const messages = { [Symbol.iterator]() { return { next() {
        nexts++;
        if (nexts === 2) assertPrint(printHooks.count(0) === 0, "previous head survives next");
        if (nexts === 3) { assertPrint(printHooks.count(1) === 0, "last head survives done"); return { done: true }; }
        return { done: false, value: { id: nexts, holder: printHooks.make(nexts - 1) } };
    } }; } };
    row.host.session.prompt = async message => { prompts++; if (message.id === 2) assertPrint(printHooks.count(0) === 1, "new head stored before previous retirement"); };
    row.host.dispose = async () => { row.disposals++; assertPrint(printHooks.count(1) === 0, "final head survives dispose Await"); };
    assertPrint(await selectedPrint.runPrintMode(row.host, { mode: "control", messages }) === 0 && prompts === 2, "actual loop complete");
    assertPrint(printHooks.count(0) === 1 && printHooks.count(1) === 1, "terminal activation retires uncaptured heads");
}
async function observePrintSignalLocals() {
    const row = printHost(), processDescriptor = Object.getOwnPropertyDescriptor(globalThis, "process");
    const iterator = Array.prototype[Symbol.iterator], push = Array.prototype.push;
    let nexts = 0, registered = 0, dropped = 0, restored = false;
    function restore() { if (restored) return; restored = true; Array.prototype[Symbol.iterator] = iterator; Array.prototype.push = push; Object.defineProperty(globalThis, "process", processDescriptor); }
    Object.defineProperty(globalThis, "process", { configurable: true, value: {
        platform: "win32",
        on(signal, handler) { registered++; handler.holder = printHooks.make(1); assertPrint(signal.marker === "signal", "actual overridden iterator head"); },
        off() { throw Error("dropped cleanup must not run"); },
    } });
    Array.prototype[Symbol.iterator] = function () {
        if (this.length !== 1 || this[0] !== "SIGTERM") return Reflect.apply(iterator, this, []);
        return { next() {
            nexts++;
            if (nexts === 1) return { done: false, value: { marker: "signal", holder: printHooks.make(0) } };
            assertPrint(printHooks.count(0) === 0 && printHooks.count(1) === 0, "closed captures do not clear the original frame slots before next");
            return { done: true };
        } };
    };
    Array.prototype.push = function (value) {
        if (this.length === 0 && typeof value === "function" && value.name === "") { dropped++; return 0; }
        return Reflect.apply(push, this, [value]);
    };
    row.host.setRebindSession = callback => {
        assertPrint(printHooks.count(0) === 1 && printHooks.count(1) === 1, "register function exit retires dropped handler and signal");
        row.rebind = callback; restore();
    };
    try {
        assertPrint(await selectedPrint.runPrintMode(row.host, { mode: "control" }) === 0, "dropped registration mode");
        assertPrint(nexts === 2 && registered === 1 && dropped === 1, "causal registration path");
    } finally { restore(); }
}
async function observePrintSignalExit() {
    const row = printHost(), actualExit = process.exit, handlers = [], actualOn = process.on, actualOff = process.off;
    let promptRelease; const exited = [];
    process.on = function (signal, handler) { handlers.push([signal, handler]); return Reflect.apply(actualOn, this, [signal, handler]); };
    process.exit = code => { exited.push(code); };
    row.host.session.prompt = () => new Promise(resolve => { promptRelease = resolve; });
    const running = selectedPrint.runPrintMode(row.host, { mode: "control", messages: ["pending"] });
    await settlePrint(() => promptRelease !== undefined);
    try {
        for (const [signal, handler] of handlers) { handler(); await settlePrint(() => exited.length > 0); assertPrint(exited.shift() === (signal === "SIGHUP" ? 129 : 143), "signal captured actual code"); }
        promptRelease();
        assertPrint(await running === 0 && row.disposals === 1 && row.unsubscriptions === 1, "dispose is idempotent across signals and finally");
    } finally { process.exit = actualExit; process.on = actualOn; process.off = actualOff; }
}
async function observePrintPrivateData() {
    const row = printHost(); let data;
    Object.defineProperty(row.host.session, "prompt", { get() { data = printHooks.freshPrivateData(); throw data; } });
    assertPrint(await selectedPrint.runPrintMode(row.host, { mode: "control", messages: ["ordinary"] }) === 1, "private DATA remains catchable");
    assertPrint(printHooks.isUnmarkedPrivateData(data) && printErrors.length === 1 && printErrors[0][0] === data.message && row.disposals === 1, "same-operation private DATA goes through Source catch and finally");
}
async function observePrintCurrentFatal() {
    const row = printHost();
    Object.defineProperty(row.host.session, "prompt", { get() { const data = printHooks.freshPrivateData(); printHooks.raiseNativeFatal(); throw data; } });
    row.host.dispose = async () => { printHooks.record.guestReached = true; printHooks.visit(3); };
    try { await selectedPrint.runPrintMode(row.host, { mode: "control", messages: ["fatal"] }); }
    catch (error) { printHooks.record.guestReached = true; printHooks.visit(3); }
}
function observeJsonProjection() {
    const json = selectedJson.toJsonEvent, event = { type: "other" };
    assertPrint(json(event) === event && json.name === "toJsonEvent" && json.length === 1 && Object.hasOwn(json, "prototype"), "ordinary event identity");
    const delta = { type: "text_delta", delta: "piece", partial: { ignored: true } };
    const usage = { tokens: 3 };
    const result = json({ type: "message_update", message: { role: "assistant", usage }, assistantMessageEvent: delta });
    assertPrint(result.usage === usage && result.assistantMessageEvent.delta === "piece" && !("partial" in result.assistantMessageEvent) && result.assistantMessageEvent !== delta, "actual partial exclusion");
    const without = { type: "text_delta", delta: "same" };
    assertPrint(json({ type: "message_update", message: { role: "assistant", usage }, assistantMessageEvent: without }).assistantMessageEvent === without, "no partial preserves delta identity");
    let error;
    try { json({ type: "message_update", message: { role: "user" } }); } catch (reason) { error = reason; }
    assertPrint(error.message === "message_update message is not an assistant message", "wrong role diagnostic");
}
function observeJsonLiveOrder() {
    const log = [], symbol = Symbol("included");
    const tool = { get type() { log.push("tool:type"); return "toolCall"; }, get id() { log.push("tool:id"); return "call"; }, get name() { log.push("tool:name"); return "read"; } };
    const delta = new Proxy({
        get type() { log.push("delta:type"); return "toolcall_start"; },
        get partial() { log.push("delta:partial"); return { content: [tool] }; },
        get contentIndex() { log.push("delta:index"); return { [Symbol.toPrimitive]() { log.push("index:coerce"); return 0; } }; },
        get extra() { log.push("delta:extra"); return 9; }, [symbol]: 7,
    }, {
        ownKeys(target) { log.push("delta:keys"); return Reflect.ownKeys(target); },
        getOwnPropertyDescriptor(target, key) { log.push("descriptor:" + (typeof key === "symbol" ? "symbol" : key)); return Reflect.getOwnPropertyDescriptor(target, key); },
    });
    let messages = 0;
    const result = selectedJson.toJsonEvent({
        get type() { log.push("outer:type"); return "message_update"; },
        get message() { messages++; log.push("outer:message"); return { get role() { log.push("message:role"); return "assistant"; }, get usage() { log.push("message:usage"); return { input: 1 }; } }; },
        get assistantMessageEvent() { log.push("outer:delta"); return delta; },
    });
    assertPrint(messages === 2 && result.assistantMessageEvent.id === "call" && result.assistantMessageEvent.toolName === "read" && result.assistantMessageEvent[symbol] === 7, "live JSON result");
    assertPrint(log.slice(0, 9).join() === "outer:type,outer:message,message:role,outer:message,message:usage,outer:delta,delta:type,delta:partial,delta:index", "outer and tool expression order");
    assertPrint(log.indexOf("index:coerce") < log.indexOf("tool:type") && log.indexOf("delta:keys") < log.indexOf("tool:id") && log.indexOf("tool:id") < log.indexOf("tool:name"), "ToPropertyKey rest then final tool properties");
    assertPrint(log.filter(x => x === "delta:partial").length === 2 && !("partial" in result.assistantMessageEvent), "destructuring still reads excluded partial once");
}

async function observePrintProcessRetirement() {
    const row = printHost(), descriptor = Object.getOwnPropertyDescriptor(globalThis, "process"); let made = 0, calls = 0;
    Object.defineProperty(globalThis, "process", { configurable: true, get() {
        made++;
        return { holder: printHooks.make(0), platform: "win32",
            get on() { assertPrint(printHooks.count(0) === made - 1, "previous process receiver retires before next on getter"); return function () { calls++; assertPrint(printHooks.count(0) === made - 1, "current process receiver remains through on"); }; },
            get off() { assertPrint(printHooks.count(0) === made - 1, "previous process receiver retires before off getter"); return function () { calls++; }; },
        };
    } });
    Object.defineProperty(row.host, "setRebindSession", { get() {
        assertPrint(printHooks.count(0) === made, "discarded process on result and receiver retire before setRebind getter");
        return callback => { row.rebind = callback; };
    } });
    try {
        assertPrint(await selectedPrint.runPrintMode(row.host, { mode: "control" }) === 0, "observed process mode");
        assertPrint(calls === 2 && printHooks.count(0) === made, "all actual process temporaries retire");
    } finally { Object.defineProperty(globalThis, "process", descriptor); }
}
