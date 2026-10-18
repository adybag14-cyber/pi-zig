// Shared observations over the actual Source internal/errors + validators, or
// the native bootstrap's actual selected exports. No error implementation lives
// in this observer.
function argumentAssert(value, message) { if (!value) throw new Error(message); }
function argumentThrown(body) {
    try { body(); } catch (reason) { return reason; }
    throw new Error("Expected the actual operation to throw");
}
function argumentSame(actual, expected, message) {
    argumentAssert(JSON.stringify(actual) === JSON.stringify(expected), message);
}
function observeArgumentShape(actual) {
    const Type = actual.codes.ERR_INVALID_ARG_TYPE;
    const Value = actual.codes.ERR_INVALID_ARG_VALUE;
    const error = new Type("path", "string", 42);
    const code = Object.getOwnPropertyDescriptor(error, "code");
    const message = Object.getOwnPropertyDescriptor(error, "message");
    const constructor = Object.getOwnPropertyDescriptor(Type.prototype, "constructor");
    argumentAssert(Type.name === "NodeError" && Type.length === 0, "actual class shape");
    argumentAssert(Object.getPrototypeOf(Type) === TypeError && Object.getPrototypeOf(Type.prototype) === TypeError.prototype, "genuine TypeError superclass");
    argumentAssert(code.value === "ERR_INVALID_ARG_TYPE" && code.writable && code.enumerable && code.configurable, "public code initializer");
    argumentAssert(message.writable && !message.enumerable && message.configurable, "actual message descriptor");
    argumentAssert(constructor.get.name === "get constructor" && constructor.get.length === 0 && !constructor.enumerable && constructor.configurable, "actual constructor getter");
    argumentAssert(error.constructor === TypeError && error instanceof TypeError, "base constructor identity");
    const marker = Object.getOwnPropertySymbols(Type.prototype).find(symbol => symbol.description === "kIsNodeError");
    argumentAssert(typeof marker === "symbol" && error[marker] === true, "actual shared Node marker");
    argumentAssert(Type.HideStackFramesError.name === "HideStackFramesError" && Type.HideStackFramesError.length === 0, "hidden class shape");
    argumentAssert(Value.RangeError.prototype.constructor === RangeError, "actual RangeError specialization");
    argumentAssert(argumentThrown(() => Type("path", "string", 42)) instanceof TypeError, "class without new rejects");
    argumentAssert(error.toString() === "TypeError [ERR_INVALID_ARG_TYPE]: " + error.message, "actual class stringifier");
}
function observeArgumentPrimitiveMessages(actual) {
    const Type = actual.codes.ERR_INVALID_ARG_TYPE;
    const rows = [
        [undefined, "undefined"], [null, "null"], [-0, "type number (-0)"],
        [17n, "type bigint (17n)"], [true, "type boolean (true)"],
        [Symbol("x"), "type symbol (Symbol(x))"], ["a'b", 'type string ("a\'b")'],
        ["abcdefghijklmnopqrstuvwxyz0123456789", "type string ('abcdefghijklmnopqrstuvwxy...')"],
    ];
    for (const [value, received] of rows) {
        const result = new Type("path", "string", value);
        argumentAssert(result.message === 'The "path" argument must be of type string. Received ' + received, "specific type " + received);
    }
    function namedFunction() {}
    argumentAssert(new Type("path", "string", namedFunction).message.endsWith("Received function namedFunction"), "function specific type");
}
function observeArgumentExpectedLists(actual) {
    const Type = actual.codes.ERR_INVALID_ARG_TYPE;
    argumentAssert(new Type("first argument", ["string", "number"], null).message ===
        "The first argument must be one of type string or number. Received null", "primitive type list");
    argumentAssert(new Type("options.value", ["Object", "Widget"], undefined).message ===
        'The "options.value" property must be an instance of Widget or Object. Received undefined', "Object specialization list");
    argumentAssert(new Type("x", ["fast", "Slow-mode"], null).message ===
        'The "x" argument must be one of fast or Slow-mode. Received null', "literal expected list");
}
function observeArgumentValueRange(actual) {
    const Value = actual.codes.ERR_INVALID_ARG_VALUE;
    const result = new Value("options.mode", "r");
    argumentAssert(result.message === "The property 'options.mode' is invalid. Received 'r'", "actual invalid value message");
    const range = new Value.RangeError("count", 7, "must be even");
    argumentAssert(range instanceof RangeError && range.code === "ERR_INVALID_ARG_VALUE", "range owner and code");
    argumentAssert(range.message === "The argument 'count' must be even. Received 7", "range function-message path");
    argumentAssert(Value.HideStackFramesError.prototype.constructor === TypeError &&
        Value.RangeError.HideStackFramesError.prototype.constructor === RangeError, "both hidden specializations");
}
function observeArgumentInternalAssert(actual) {
    argumentAssert(actual.assert.name === "assert" && actual.assert.length === 2 &&
        actual.assert.fail.name === "fail" && actual.assert.fail.length === 1, "actual assert functions");
    argumentAssert(actual.assert(true, "unused") === undefined, "true assertion returns");
    const result = argumentThrown(() => actual.assert(false, "failure"));
    argumentAssert(result instanceof Error && result.code === "ERR_INTERNAL_ASSERTION", "lazy genuine assertion class");
    argumentAssert(result.message.startsWith("failure\nThis is caused by either a bug in Node.js "), "actual assertion message");
    const absent = argumentThrown(() => actual.assert.fail());
    argumentAssert(absent.message.startsWith("This is caused by either a bug in Node.js "), "undefined assertion message");
}
function observeArgumentValidators(actual) {
    const validate = actual.validateString;
    argumentAssert(validate.name === "wrappedFn" && validate.length === 0 && Object.hasOwn(validate, "prototype"), "actual normal wrapper");
    argumentAssert(validate.withoutStackTrace.name === "" && validate.withoutStackTrace.length === 2 &&
        !Object.hasOwn(validate.withoutStackTrace, "prototype"), "actual raw validator arrow");
    argumentAssert(validate("ok", "path") === undefined && validate.withoutStackTrace("ok", "path") === undefined, "actual validator success");
    const result = argumentThrown(() => validate(42, "path"));
    argumentAssert(result.code === "ERR_INVALID_ARG_TYPE" && result.message.endsWith("Received type number (42)"), "actual validator failure");
}
function observeArgumentAbortSignal(actual) {
    argumentAssert(actual.validateAbortSignal(undefined, "signal") === undefined, "undefined signal");
    argumentAssert(actual.validateAbortSignal({aborted:false}, "signal") === undefined, "structural signal");
    const events = [];
    const signal = new Proxy({}, {has(target, key) { events.push(String(key)); return key === "aborted"; }});
    argumentAssert(actual.validateAbortSignal(signal, "signal") === undefined, "actual has operation");
    argumentSame(events, ["aborted"], "signal has order");
    for (const value of [null, 7, function invalidSignal() {}]) {
        const error = argumentThrown(() => actual.validateAbortSignal(value, "signal"));
        argumentAssert(error.code === "ERR_INVALID_ARG_TYPE", "invalid signal class");
    }
}
function observeArgumentConstructorReads(actual) {
    const events = [];
    let reads = 0;
    const input = {};
    Object.defineProperty(input, "constructor", {get() {
        events.push("constructor" + ++reads);
        if (reads === 1) return {};
        if (reads === 2) return {name:"ignored"};
        return {get name() { events.push("name"); return {toString() { events.push("name-string"); return "Selected"; }}; }};
    }});
    const error = new actual.codes.ERR_INVALID_ARG_TYPE("x", "string", input);
    argumentAssert(error.message.endsWith("Received an instance of Selected"), "third constructor result");
    argumentSame(events, ["constructor1","constructor2","constructor3","name","name-string"], "repeated constructor reads");
}
function observeArgumentPrimitiveInOperand(actual) {
    let reads = 0;
    const input = Object.defineProperty({}, "constructor", {get() { return ++reads === 1 ? {} : 1; }});
    const error = argumentThrown(() => new actual.codes.ERR_INVALID_ARG_TYPE("x", "string", input));
    argumentAssert(error instanceof TypeError && reads === 2, "primitive second constructor rejects at in");
}
function argumentWithLimit(body) {
    const descriptor = Object.getOwnPropertyDescriptor(Error, "stackTraceLimit");
    try { return body(); }
    finally {
        if (descriptor) Object.defineProperty(Error, "stackTraceLimit", descriptor);
        else delete Error.stackTraceLimit;
    }
}
function observeArgumentHiddenRest(actual) {
    argumentWithLimit(() => {
        Object.defineProperty(Error, "stackTraceLimit", {value:9,writable:true,configurable:true});
        const iterator = Array.prototype[Symbol.iterator];
        let intercepted = 0;
        Array.prototype[Symbol.iterator] = function() {
            if (this.length === 3 && this[0] === "path" && this[1] === "string" && this[2] === 42) {
                intercepted++;
                let position = 0;
                const selected = ["count", "number", 7];
                return {next() { return position < 3 ? {done:false,value:selected[position++]} : {done:true}; }};
            }
            return Reflect.apply(iterator, this, []);
        };
        let result;
        try { result = new actual.codes.ERR_INVALID_ARG_TYPE.HideStackFramesError("path", "string", 42); }
        finally { Array.prototype[Symbol.iterator] = iterator; }
        argumentAssert(intercepted === 1 && result.message === 'The "count" argument must be of type number. Received type number (7)', "hidden super spreads the actual rest array");
        argumentAssert(Error.stackTraceLimit === 9, "successful hidden constructor restores limit");
    });
}
function observeArgumentHiddenSuperTarget(actual) {
    argumentWithLimit(() => {
        Object.defineProperty(Error, "stackTraceLimit", {value:8,writable:true,configurable:true});
        const Hidden = actual.codes.ERR_INVALID_ARG_TYPE.HideStackFramesError;
        const previous = Object.getPrototypeOf(Hidden);
        const iterator = Array.prototype[Symbol.iterator];
        let called = 0;
        let decoy = 0;
        let target;
        function Base(value) { called++; target = new.target; this.value = value; }
        function Decoy() { decoy++; }
        function Target() {}
        Object.setPrototypeOf(Hidden, Base);
        Array.prototype[Symbol.iterator] = function() {
            if (this.length === 1 && this[0] === "super-token") {
                Object.setPrototypeOf(Hidden, Decoy);
                let done = false;
                return {next() { if (done) return {done:true}; done=true; return {done:false,value:"selected"}; }};
            }
            return Reflect.apply(iterator, this, []);
        };
        let result;
        try { result = Reflect.construct(Hidden, ["super-token"], Target); }
        finally { Array.prototype[Symbol.iterator] = iterator; Object.setPrototypeOf(Hidden, previous); }
        argumentAssert(called === 1 && decoy === 0 && target === Target && Object.getPrototypeOf(result) === Target.prototype &&
            result.value === "selected", "resolved lexical superclass and actual new.target");
    });
}
function observeArgumentHiddenLimits(actual) {
    argumentWithLimit(() => {
        const events = [];
        let limit = 7;
        Object.defineProperty(Error, "stackTraceLimit", {
            configurable:true,
            get() { events.push("get:" + limit); return limit; },
            set(value) { events.push("set:" + value); limit=value; },
        });
        const result = new actual.codes.ERR_INVALID_ARG_TYPE.HideStackFramesError("x","string",7);
        argumentAssert(result.code === "ERR_INVALID_ARG_TYPE" && limit === 7, "accessor limit restores");
        argumentSame(events, ["get:7","set:0","set:7"], "limit getter and setter order");
        Object.defineProperty(Error, "stackTraceLimit", {value:5,writable:false,configurable:true});
        const again = new actual.codes.ERR_INVALID_ARG_TYPE.HideStackFramesError("x","string",7);
        argumentAssert(again.code === "ERR_INVALID_ARG_TYPE" && Error.stackTraceLimit === 5, "nonwritable limit branch");
    });
}
function observeArgumentHiddenThrow(actual) {
    argumentWithLimit(() => {
        const Hidden = actual.codes.ERR_INVALID_ARG_TYPE.HideStackFramesError;
        const previous = Object.getPrototypeOf(Hidden);
        const reason = {};
        Object.defineProperty(Error, "stackTraceLimit", {value:13,writable:true,configurable:true});
        Object.setPrototypeOf(Hidden, function ThrowingBase() { throw reason; });
        let caught;
        try { caught = argumentThrown(() => new Hidden("x","string",7)); }
        finally { Object.setPrototypeOf(Hidden, previous); }
        argumentAssert(caught === reason && Error.stackTraceLimit === 0, "throwing super leaves zero without finally");
    });
}
function observeArgumentCapturedApplyAndRest(actual) {
    const OriginalArray = Array;
    const prototype = OriginalArray.prototype;
    const iterator = prototype[Symbol.iterator];
    const apply = Reflect.apply;
    let iteratorReads = 0;
    prototype[Symbol.iterator] = function() {
        if ((this.length === 3 && this[0] === "rest-token") || (this.length === 2 && this[0] === "valid-token")) {
            iteratorReads++;
            throw new Error("A plain rest parameter must not iterate");
        }
        return apply(iterator, this, []);
    };
    Reflect.apply = function lateApply() { throw new Error("late Reflect.apply"); };
    globalThis.Array = function lateArray() { throw new Error("late Array constructor"); };
    try {
        const result = new actual.codes.ERR_INVALID_ARG_TYPE("rest-token","string",7);
        argumentAssert(result.code === "ERR_INVALID_ARG_TYPE", "function-message constructor retained apply");
        argumentAssert(actual.validateString("valid-token","path") === undefined, "wrapper retained apply");
        argumentAssert(iteratorReads === 0, "real rest producers ignore iterator");
    } finally {
        globalThis.Array = OriginalArray;
        Reflect.apply = apply;
        prototype[Symbol.iterator] = iterator;
    }
}
function observeArgumentExpectedIteratorClose(actual) {
    let closed = 0;
    const expected = [];
    expected[Symbol.iterator] = function() {
        return {next() { return {done:false,value:17}; }, return() { closed++; return {}; }};
    };
    const reason = argumentThrown(() => new actual.codes.ERR_INVALID_ARG_TYPE("x",expected,null));
    argumentAssert(reason.code === "ERR_INTERNAL_ASSERTION" && closed === 1, "actual invalid expected entry closes its iterator");
}
function observeArgumentInspectThrow(actual) {
    const reason = {};
    const input = {[Symbol.for("nodejs.util.inspect.custom")]() { throw reason; }};
    const caught = argumentThrown(() => new actual.codes.ERR_INVALID_ARG_VALUE("x", input));
    argumentAssert(caught === reason, "actual lazy inspector ordinary throw identity");
}
