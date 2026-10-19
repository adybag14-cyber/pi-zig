// The subject is the complete c268 factory or the actual native EventBus.
// Both receive the same genuine installed EventEmitter import.
function eventAssert(value, message) { if (!value) throw new Error(message); }
function eventSame(actual, expected, message) { eventAssert(Object.is(actual, expected), message); }
function eventList(actual, expected, message) {
    eventAssert(actual.length === expected.length && actual.every((value, index) => Object.is(value, expected[index])), message);
}
function eventRestore(object, key, descriptor) {
    if (descriptor) Object.defineProperty(object, key, descriptor); else delete object[key];
}
function eventCapture(create, E, channel, handler) {
    const descriptor = Object.getOwnPropertyDescriptor(E.prototype, "on"), original = E.prototype.on;
    let captured;
    Object.defineProperty(E.prototype, "on", {configurable:true, writable:true, value:function(key, callback) {
        captured = {emitter:this, channel:key, safe:callback};
        return Reflect.apply(original, this, [key, callback]);
    }});
    try {
        const bus = create();
        const off = bus.on(channel, handler);
        eventAssert(captured && captured.channel === channel, "actual EventEmitter.on retained the real safeHandler");
        return {bus, off, ...captured};
    } finally { eventRestore(E.prototype, "on", descriptor); }
}
function observeEventBusShapes(create, E) {
    eventSame(create.name, "createEventBus", "actual ordinary factory name");
    eventSame(create.length, 0, "actual ordinary factory arity");
    eventAssert(Object.hasOwn(create, "prototype"), "ordinary factory is constructible");
    for (const bus of [create(), new create()]) {
        eventList(Reflect.ownKeys(bus), ["emit","on","clear"], "actual object literal order");
        for (const [name, length] of [["emit",2],["on",2],["clear",0]]) {
            const descriptor = Object.getOwnPropertyDescriptor(bus, name), fn = descriptor.value;
            eventAssert(descriptor.writable && descriptor.enumerable && descriptor.configurable, "literal method descriptor " + name);
            eventSame(fn.name, name, "arrow name"); eventSame(fn.length, length, "arrow length");
            eventAssert(!Object.hasOwn(fn, "prototype"), "actual arrow has no constructor prototype");
        }
    }
    const captured = eventCapture(create, E, "shape", () => {});
    eventAssert(captured.emitter instanceof E, "one genuine EventEmitter instance");
    eventSame(captured.safe.name, "safeHandler", "actual local async arrow name");
    eventSame(captured.safe.length, 1, "actual local async arrow length");
    eventAssert(eventBusIsAsync(captured.safe), "real VM async brand");
    eventSame(Object.getPrototypeOf(captured.safe), Object.getPrototypeOf(async () => {}), "intrinsic async prototype");
    eventAssert(!Object.hasOwn(captured.safe, "prototype") && !Object.hasOwn(captured.off, "prototype"), "actual captured arrow shapes");
    eventSame(captured.off.name, "", "unsubscribe arrow name"); eventSame(captured.off.length, 0, "unsubscribe arrow length");
    eventSame(captured.off(), captured.emitter, "expression unsubscribe returns actual EventEmitter.off result");
}
async function observeEventBusDispatch(create, E) {
    const bus = create(), first = [], second = [], key = Symbol("topic"), data = {};
    const unsubscribe = bus.on("topic", function(value) { first.push([this, value]); });
    const unsubscribeSymbol = bus.on(key, value => second.push(value));
    eventSame(bus.emit("topic", data), undefined, "emit discards the actual emitter result");
    eventSame(bus.emit(key, data), undefined, "symbol channel dispatch");
    eventSame(first.length, 1, "actual synchronous dispatch before Await");
    eventSame(first[0][0], undefined, "plain strict handler call");
    eventSame(first[0][1], data, "same user data");
    eventList(second, [data], "independent symbol channel");
    await Promise.resolve();
    eventAssert(unsubscribe() instanceof E, "real unsubscribe return");
    bus.emit("topic", 2); eventSame(first.length, 1, "actual listener removed");
    eventSame(bus.clear(), undefined, "clear discards actual removeAllListeners result");
    bus.emit(key, 3); eventSame(second.length, 1, "clear removes symbol listeners");
    eventAssert(unsubscribeSymbol() instanceof E, "off remains real after clear");
}
function observeEventBusLiveMethods(create, E, hooks) {
    const captured = eventCapture(create, E, "method", () => {}), trace = [];
    Object.defineProperty(captured.emitter, "emit", {configurable:true, get() {
        trace.push("emit:get");
        const method = function(key, data) {
            eventSame(this, captured.emitter, "actual emit receiver");
            eventList([key,data], ["selected",7], "actual emit arguments");
            trace.push("emit:call"); return hooks.make(1);
        };
        method.holder = hooks.make(0);
        return method;
    }});
    eventSame(captured.bus.emit("selected", 7), undefined, "void emit result");
    eventSame(hooks.count(0), 1, "temporary emit callee retired at statement");
    eventSame(hooks.count(1), 1, "discarded emit result retired at statement");
    Object.defineProperty(captured.emitter, "off", {configurable:true, get() {
        trace.push("off:get");
        return function(key, callback) {
            eventSame(this, captured.emitter, "actual off receiver");
            eventList([key,callback], ["method",captured.safe], "captured unsubscribe arguments");
            trace.push("off:call"); return hooks.make(2);
        };
    }});
    let returned = captured.off();
    eventSame(hooks.count(2), 0, "unsubscribe transfers its result owner");
    returned = null;
    eventSame(hooks.count(2), 1, "caller owns the off result");
    Object.defineProperty(captured.emitter, "removeAllListeners", {configurable:true, get() {
        trace.push("clear:get");
        return function(...args) {
            eventSame(this, captured.emitter, "actual clear receiver"); eventSame(args.length, 0, "clear forwards no arguments");
            trace.push("clear:call"); return hooks.make(3);
        };
    }});
    eventSame(captured.bus.clear(), undefined, "void clear result");
    eventSame(hooks.count(3), 1, "discarded clear result retired");
    eventList(trace, ["emit:get","emit:call","off:get","off:call","clear:get","clear:call"], "live actual methods");
}
async function observeEventBusAwait(create, E, hooks) {
    const OriginalPromise = Promise, descriptor = Object.getOwnPropertyDescriptor(globalThis, "Promise");
    let resolve, calls = 0;
    const gate = new OriginalPromise(done => { resolve = done; });
    const captured = eventCapture(create, E, "await", function() { calls++; return gate; });
    let pending;
    try {
        Object.defineProperty(globalThis, "Promise", {configurable:true, writable:true, value:function() { throw new Error("global Promise constructor used"); }});
        pending = captured.safe(hooks.make(0));
        eventAssert(pending instanceof OriginalPromise, "intrinsic async capability");
    } finally { eventRestore(globalThis, "Promise", descriptor); }
    eventSame(calls, 1, "body starts synchronously");
    eventSame(hooks.count(0), 0, "unused actual argument retained across suspension");
    let settled = false; pending.then(() => { settled = true; });
    await OriginalPromise.resolve();
    eventAssert(!settled && hooks.count(0) === 0, "real unresolved Await");
    resolve(19);
    eventSame(await pending, undefined, "fulfilled handler result is discarded");
    eventSame(hooks.count(0), 1, "actual argument retires at native or Source AF terminal");
}
async function observeEventBusCatch(create, E, hooks, afterAwait) {
    const trace = [], reason = {}, descriptor = Object.getOwnPropertyDescriptor(globalThis, "console");
    let active = false;
    const channel = {[Symbol.toPrimitive](hint) { if (active) trace.push("channel:" + hint); return "topic"; }};
    const captured = eventCapture(create, E, channel, function() {
        trace.push("handler");
        if (afterAwait) return Promise.reject(reason);
        throw reason;
    });
    active = true;
    try {
        Object.defineProperty(globalThis, "console", {configurable:true, get() {
            trace.push("console");
            return {marker:true, get error() {
                trace.push("error");
                return function(message, error) {
                    eventAssert(this.marker, "actual console receiver");
                    eventSame(message, "Event handler error (topic):", "actual template literal");
                    eventSame(error, reason, "same ordinary caught reason");
                    trace.push("log");
                };
            }};
        }});
        const pending = captured.safe(3);
        eventList(trace, afterAwait ? ["handler"] : ["handler","console","error","channel:string","log"], "actual pre-Await path");
        eventSame(await pending, undefined, "ordinary catch resolves undefined");
        eventList(trace, ["handler","console","error","channel:string","log"], "live logging selection before string conversion");
    } finally { eventRestore(globalThis, "console", descriptor); }
}
async function observeEventBusLogFailure(create, E, hooks, afterAwait) {
    const originalReason = {}, logReason = {}, descriptor = Object.getOwnPropertyDescriptor(globalThis, "console");
    const captured = eventCapture(create, E, "log", () => {
        if (afterAwait) return Promise.reject(originalReason);
        throw originalReason;
    });
    try {
        Object.defineProperty(globalThis, "console", {configurable:true, value:{error(message, error) {
            eventSame(error, originalReason, "actual body reason reaches logger");
            throw logReason;
        }}});
        let caught;
        try { await captured.safe(); } catch (error) { caught = error; }
        eventSame(caught, logReason, "logging abrupt completion becomes the async rejection");
    } finally { eventRestore(globalThis, "console", descriptor); }
}
async function observeEventBusTemplates(create, E) {
    const concat = Object.getOwnPropertyDescriptor(String.prototype, "concat"), consoleDescriptor = Object.getOwnPropertyDescriptor(globalThis, "console");
    const trace = [], reason = {}, conversion = {};
    let active = false, mode = "normal";
    const channel = {[Symbol.toPrimitive](hint) {
        if (active) { trace.push(hint); if (mode === "throw") throw conversion; }
        return "channel";
    }};
    const captured = eventCapture(create, E, channel, () => { throw reason; });
    const symbolCaptured = eventCapture(create, E, Symbol("symbol"), () => { throw reason; });
    active = true;
    try {
        Object.defineProperty(String.prototype, "concat", {configurable:true, writable:true, value:function() { throw new Error("live concat must not be used"); }});
        Object.defineProperty(globalThis, "console", {configurable:true, value:{get error() {
            trace.push("error");
            return function(message, error) { trace.push("call"); eventSame(message, "Event handler error (channel):", "intrinsic literal result"); eventSame(error, reason, "unchanged reason"); };
        }}});
        await captured.safe();
        eventList(trace, ["error","string","call"], "intrinsic ToString after live logger selection");
        trace.length = 0; mode = "throw";
        let caught;
        try { await captured.safe(); } catch (error) { caught = error; }
        eventSame(caught, conversion, "template conversion abrupt identity");
        eventList(trace, ["error","string"], "conversion failure prevents logger call");
        trace.length = 0; caught = undefined;
        try { await symbolCaptured.safe(); } catch (error) { caught = error; }
        eventAssert(caught instanceof TypeError, "template ToString rejects Symbol");
        eventList(trace, ["error"], "Symbol fails after selecting logger and before call");
    } finally { eventRestore(String.prototype, "concat", concat); eventRestore(globalThis, "console", consoleDescriptor); }
}
async function observeEventBusPrivateData(create, E, hooks, afterAwait) {
    let reason, logs = 0;
    const descriptor = Object.getOwnPropertyDescriptor(globalThis, "console");
    const captured = eventCapture(create, E, "data", () => {
        reason = hooks.freshPrivateData();
        if (afterAwait) return Promise.reject(reason);
        throw reason;
    });
    try {
        Object.defineProperty(globalThis, "console", {configurable:true, value:{error(message, error) {
            logs++; eventSame(error, reason, "same private DATA reason"); eventAssert(hooks.isUnmarkedPrivateData(error), "ordinary unmarked private DATA");
        }}});
        eventSame(await captured.safe(), undefined, "ordinary DATA catch completes normally");
        eventSame(logs, 1, "actual ordinary catch logging");
    } finally { eventRestore(globalThis, "console", descriptor); }
}
async function observeEventBusCurrentFatal(create, E, hooks) {
    const captured = eventCapture(create, E, "fatal", () => { hooks.freshPrivateData(); return hooks.raiseNativeFatal(); });
    Object.defineProperty(globalThis, "console", {configurable:true, get() { hooks.visit(1); return {get error() { hooks.visit(2); return () => {}; }}; }});
    try { await captured.safe(); hooks.record.guestReached = true; hooks.visit(3); }
    catch (error) { hooks.record.guestReached = true; hooks.visit(3); throw error; }
}
async function observeEventBusAfterAwaitFatal(create, E, hooks) {
    const reason = hooks.freshPrivateData();
    let active = false;
    const channel = {[Symbol.toPrimitive]() { if (active) hooks.visit(1); return "fatal"; }};
    const captured = eventCapture(create, E, channel, () => Promise.reject(reason));
    active = true;
    Object.defineProperty(globalThis, "console", {configurable:true, get() {
        return {get error() { hooks.raiseNativeFatal(); return function() { hooks.visit(2); }; }};
    }});
    try { await captured.safe(); hooks.record.guestReached = true; hooks.visit(3); }
    catch (error) { hooks.record.guestReached = true; hooks.visit(3); throw error; }
}
async function observeEventBusCleanupFailure(create, E, hooks, cancel) {
    const reason = {}, captured = eventCapture(create, E, "cleanup", () => { throw reason; });
    Object.defineProperty(globalThis, "console", {configurable:true, get() {
        return {holder:hooks.make(0), error() {}};
    }});
    if (cancel) hooks.armCancel(0); else hooks.armFatal(0);
    try { await captured.safe(); hooks.visit(1); hooks.record.guestReached = true; }
    catch (error) { hooks.visit(2); hooks.record.guestReached = true; throw error; }
}
