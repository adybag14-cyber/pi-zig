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


function observeInspectTypedValues(inspect) {
    const rows = [
        [new Uint8Array([0]), "Uint8Array(1) [ 0 ]"],
        [new Uint8ClampedArray([1, 255]), "Uint8ClampedArray(2) [ 1, 255 ]"],
        [new Int8Array([-2]), "Int8Array(1) [ -2 ]"],
        [new Uint16Array([65535]), "Uint16Array(1) [ 65535 ]"],
        [new Int16Array([-32768]), "Int16Array(1) [ -32768 ]"],
        [new Uint32Array([4294967295]), "Uint32Array(1) [ 4294967295 ]"],
        [new Int32Array([-2147483648]), "Int32Array(1) [ -2147483648 ]"],
        [new Float32Array([1.5]), "Float32Array(1) [ 1.5 ]"],
        [new Float64Array([-0, NaN, Infinity]), "Float64Array(3) [ -0, NaN, Infinity ]"],
        [new BigInt64Array([-4294967297n]), "BigInt64Array(1) [ -4294967297n ]"],
        [new BigUint64Array([18446744073709551615n]), "BigUint64Array(1) [ 18446744073709551615n ]"],
    ];
    for (const [input, expected] of rows) inspectAssert(inspect(input) === expected, expected);
    inspectAssert(inspect(new Int32Array([1234567]), {numericSeparator:true}) === "Int32Array(1) [ 1_234_567 ]", "typed numeric separators");
    inspectAssert(inspect(new BigInt64Array([-1234567n]), {numericSeparator:true}) === "BigInt64Array(1) [ -1_234_567n ]", "typed BigInt separators");
    const extra = new Uint8Array([7]); extra.label = "ok";
    inspectAssert(inspect(extra) === "Uint8Array(1) [ 7, label: 'ok' ]", "typed non-index own properties");
}
function observeInspectTypedLimits(inspect) {
    inspectAssert(inspect(new Uint8Array(0), {depth:-1}) === "Uint8Array(0) []", "empty typed return precedes depth");
    inspectAssert(inspect(new Uint8Array([1]), {depth:-1}) === "[Uint8Array]", "typed depth label has no element size");
    inspectAssert(inspect(new Uint8Array([1,2]), {maxArrayLength:0}) === "Uint8Array(2) [ ... 2 more items ]", "typed zero limit");
    inspectAssert(inspect(new Uint8Array([1,2,3]), {maxArrayLength:1}) === "Uint8Array(3) [ 1, ... 2 more items ]", "typed remaining count");
    inspectAssert(inspect(new Uint8Array([1,2]), {compact:false}) === "Uint8Array(2) [\n  1,\n  2\n]", "typed separate lines");
    inspectAssert(inspect(new Uint8Array([1,2]), {compact:true}) === "Uint8Array(2) [ 1, 2 ]", "typed compact true");
    inspectAssert(inspect(new Uint8Array([1,2]), {colors:true,breakLength:32}) === "Uint8Array(2) [ \u001b[33m1\u001b[39m, \u001b[33m2\u001b[39m ]", "typed color removal controls break-length measurement");
    let caught;
    try { inspect(new Uint8Array([1,2]), {maxArrayLength:1.5}); } catch (reason) { caught = reason; }
    inspectAssert(caught instanceof RangeError, "actual Array rejects fractional maximum");
}
function observeInspectTypedCaptured(inspect) {
    const input = new Uint8Array([3,5]); Object.setPrototypeOf(input, null);
    const oldUint8 = globalThis.Uint8Array, oldArray = globalThis.Array;
    const oldMin = Math.min, oldMax = Math.max;
    const fail = function(){ throw new Error("late typed primordial"); };
    let result;
    try {
        globalThis.Uint8Array = fail; globalThis.Array = fail;
        Math.min = fail; Math.max = fail;
        result = inspect(input);
    } finally {
        globalThis.Uint8Array = oldUint8; globalThis.Array = oldArray;
        Math.min = oldMin; Math.max = oldMax;
    }
    inspectAssert(result === "[Uint8Array(2): null prototype] [ 3, 5 ]", "captured typed reconstruction and Array/Math imports");
}
function observeInspectTypedLengthReads(inspect) {
    const input = new Uint8Array([4]);
    let reads = 0;
    Object.defineProperty(input, "length", {get(){
        reads++;
        return reads === 2 ? 3 : 1;
    }});
    const result = inspect(input);
    inspectAssert(reads === 3, "three selected live length reads");
    inspectAssert(result === "Uint8Array(1) [ 4, ... 2 more items ]", "intrinsic size differs from repeated live length");
}
function observeInspectTypedPrefix(inspect) {
    const original = Object.getOwnPropertyDescriptor(String.prototype, "indexOf");
    const marker = {prefix:true};
    let selected = 0, caught;
    try {
        Object.defineProperty(String.prototype, "indexOf", {configurable:true,get(){selected++;throw marker;}});
        try { inspect(new Uint8Array([7])); } catch (reason) { caught = reason; }
    } finally {
        Object.defineProperty(String.prototype, "indexOf", original);
    }
    inspectAssert(selected === 1 && caught === marker, "actual prefix live method getter and ordinary reason");
}
function observeInspectTypedOutputSet(inspect) {
    const input = new Uint8Array([9]);
    const prior = Object.getOwnPropertyDescriptor(Array.prototype, "0");
    const define = Object.defineProperty;
    let writes = 0, output, result;
    try {
        define(Array.prototype, "0", {configurable:true,set(value){
            if (value === "9") { writes++; output = this; value = "first"; }
            define(this, "0", {value,writable:true,enumerable:true,configurable:true});
        }});
        result = inspect(input);
    } finally {
        if (prior) define(Array.prototype, "0", prior); else delete Array.prototype[0];
    }
    inspectAssert(writes === 1 && Array.isArray(output) && output.length === 1, "formatter writes actual output Array");
    inspectAssert(result === "Uint8Array(1) [ first ]", "output setter result reaches actual reduction");
}
