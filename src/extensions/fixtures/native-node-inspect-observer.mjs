// The same observers accept the actual pinned Node inspect function or this
// port's actual captured native inspector. No replacement inspector is defined.
function inspectAssert(value, message) { if (!value) throw new Error(message); }
function observeInspectShape(inspect) {
    inspectAssert(inspect.name === "inspect" && inspect.length === 2 && Object.hasOwn(inspect, "prototype"), "ordinary inspect shape");
    inspectAssert(inspect.custom === Symbol.for("nodejs.util.inspect.custom"), "actual custom symbol identity");
    const descriptor = Object.getOwnPropertyDescriptor(inspect, "defaultOptions");
    inspectAssert(descriptor.get.name === "get" && descriptor.set.name === "set" && descriptor.set.length === 1, "original accessor method shapes");
    inspectAssert(inspect.defaultOptions === inspect.defaultOptions && !Object.isExtensible(inspect.defaultOptions), "same sealed default record");
}
function observeInspectPrimitives(inspect) {
    const rows = [[undefined,"undefined"],[null,"null"],[true,"true"],[false,"false"],[0,"0"],[-0,"-0"],[NaN,"NaN"],[Infinity,"Infinity"],[-Infinity,"-Infinity"],[17n,"17n"],["alpha","'alpha'"],["a'b",'"a\'b"'],["x\n","'x\\n'"],["\ud800","'\\ud800'"],[Symbol("marker"),"Symbol(marker)"]];
    for (const [value, expected] of rows) inspectAssert(inspect(value) === expected, "primitive inspect " + expected);
}
function observeInspectNumeric(inspect) {
    inspectAssert(inspect(1234567, {numericSeparator:true}) === "1_234_567", "number separator");
    inspectAssert(inspect(-1234567n, {numericSeparator:true}) === "-1_234_567n", "BigInt separator");
    inspectAssert(inspect("abcdef", {maxStringLength:3}) === "'abc'... 3 more characters", "string truncation");
}
function observeInspectCapturedPrimordials(inspect) {
    const original = globalThis.String, assign = Object.assign, depth = inspect.defaultOptions.depth;
    globalThis.String = function() { throw new Error("late global String"); };
    Object.assign = function() { throw new Error("late Object.assign"); };
    try {
        inspectAssert(inspect(Symbol("captured")) === "Symbol(captured)" && inspect(12) === "12", "retained actual primordial");
        inspect.defaultOptions = {depth:1};
        inspectAssert(inspect.defaultOptions.depth === 1, "actual retained ObjectAssign");
    } finally { globalThis.String = original; Object.assign = assign; inspect.defaultOptions = {depth}; }
}
function observeInspectCustomArguments(inspect) {
    let called = 0;
    const input = {[inspect.custom](depth, options, actual) {
        called++;
        inspectAssert(this === input && depth === 2 && actual === inspect, "custom inspect actual receiver and imports");
        inspectAssert(options.depth === 2 && options.customInspect === true && options.colors === false, "actual options snapshot");
        return "custom result";
    }};
    inspectAssert(inspect(input) === "custom result" && called === 1, "custom result dispatch");
}
function observeInspectOrdinaryCustomThrow(inspect) {
    const reason = {ordinary:"custom"};
    let caught;
    try { inspect({[inspect.custom]() { throw reason; }}); } catch (error) { caught = error; }
    inspectAssert(caught === reason, "custom inspection exact ordinary throw identity");
}
function observeInspectTagCatch(inspect) {
    let calls = 0;
    const input = {};
    Object.defineProperty(input, Symbol.toStringTag, {get() { calls++; throw {ordinary:"tag"}; }});
    inspectAssert(inspect(input) === "{}" && calls === 1, "actual tag getter ordinary catch");
}
function observeInspectInstanceCatch(inspect) {
    let calls = 0;
    function Constructor() {}
    Object.defineProperty(Constructor, Symbol.hasInstance, {value() { calls++; throw {ordinary:"instance"}; }});
    const input = {};
    Object.defineProperty(input, "constructor", {value:Constructor});
    inspectAssert(inspect(input) === "{}" && calls === 1, "actual instanceof ordinary catch");
}
function observeInspectProxyDetails(inspect) {
    const target = {answer:42};
    const handler = new Proxy({}, {get() { throw new Error("proxy trap must not be consulted"); }});
    inspectAssert(inspect(new Proxy(target, handler)) === "{ answer: 42 }", "actual trap-free proxy details");
    const revoked = Proxy.revocable({}, {}); revoked.revoke();
    inspectAssert(inspect(revoked.proxy) === "<Revoked Proxy>", "actual revoked proxy");
}
function observeInspectDefaultAssignment(inspect) {
    const previous = {...inspect.defaultOptions}, trace = [];
    const input = {};
    Object.defineProperty(input, "depth", {enumerable:true, get() { trace.push("depth"); delete input.colors; return 0; }});
    Object.defineProperty(input, "colors", {enumerable:true, configurable:true, get() { trace.push("colors"); return true; }});
    try {
        inspect.defaultOptions = input;
        inspectAssert(trace.join() === "depth" && inspect.defaultOptions.depth === 0 && inspect.defaultOptions.colors === previous.colors, "descriptor then live Get per assign key");
        const proxy = new Proxy({depth:1}, {
            ownKeys(target) { trace.push("keys"); return Reflect.ownKeys(target); },
            getOwnPropertyDescriptor(target, name) { trace.push("descriptor:" + name); return Reflect.getOwnPropertyDescriptor(target, name); },
            get(target, name, receiver) { trace.push("get:" + name); return Reflect.get(target, name, receiver); },
        });
        inspect.defaultOptions = proxy;
        inspectAssert(trace.slice(1).join() === "keys,descriptor:depth,get:depth" && inspect.defaultOptions.depth === 1, "actual proxy assign operations");
    } finally { inspect.defaultOptions = previous; }
}
