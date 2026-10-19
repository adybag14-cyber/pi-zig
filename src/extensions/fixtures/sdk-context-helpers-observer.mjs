// Actual c268 helper bodies run in separate fresh Source/native Engines.
// Hooks are the existing real C holder recorder, never a GC simulation.
function contextAssert(value, message) { if (!value) throw new Error(message); }
function contextSame(actual, expected, message) { contextAssert(Object.is(actual, expected), message); }
function contextList(actual, expected, message) {
    contextAssert(actual.length === expected.length && actual.every((value, index) => Object.is(value, expected[index])), message);
}
function contextRestore(object, key, descriptor) {
    if (descriptor) Object.defineProperty(object, key, descriptor); else delete object[key];
}
function observeContextShapes(subject, info) {
    for (const [name, length] of [["parseSkillBlock",1],["formatReadLineRange",2],["createSyntheticSourceInfo",2]]) {
        const fn = subject[name];
        contextSame(fn.name, name, "actual public function name");
        contextSame(fn.length, length, "actual public function arity");
        contextAssert(Object.hasOwn(fn, "prototype"), "actual ordinary function declaration");
        const descriptor = Object.getOwnPropertyDescriptor(subject, name);
        contextAssert(descriptor.writable && descriptor.enumerable && descriptor.configurable, "actual public binding");
    }
    for (const [name, length] of [["getSyntheticPathSource",1],["isSyntheticPath",1],["createSourceInfo",2],["createSyntheticSourceInfo",2]]) {
        contextSame(info[name].name, name, "actual shared source-info function name");
        contextSame(info[name].length, length, "actual shared source-info function arity");
    }
    contextSame(subject.createSyntheticSourceInfo, info.createSyntheticSourceInfo, "public binding is the same source-info owner");
    contextSame(info.BUILTIN_PATH_PREFIX, "builtin:", "actual retained prefix");
}
function observeSkillBasics(subject) {
    const parse = subject.parseSkillBlock;
    const text = '<skill name="coding" location="/skills/coding.md">\nfirst\nsecond\n</skill>\n\n  Please use it.  ';
    const result = parse(text);
    contextList(Reflect.ownKeys(result), ["name","location","content","userMessage"], "actual skill record order");
    contextList(Object.values(result), ["coding","/skills/coding.md","first\nsecond","Please use it."], "actual regex captures and trimmed tail");
    const empty = parse('<skill name="x" location="p">\n\n</skill>');
    contextSame(empty.content, "", "empty content capture");
    contextSame(empty.userMessage, undefined, "missing optional user message");
    contextSame(parse('<skill name="x" location="p">\nbody\n</skill>\n\n   ').userMessage, undefined, "empty trimmed tail");
    for (const invalid of [
        "", "ordinary text", '<skill name="" location="p">\nx\n</skill>',
        '<skill name="x" location="">\nx\n</skill>',
        '<skill name="x" location="p">\rx\r</skill>',
        '<skill name="x" location="p">\nx\n</skill>\n\n',
        '<skill name="x" location="p">\nx\n</skill>\ntrailing',
    ]) contextSame(parse(invalid), null, "actual invalid framing");
}
function observeSkillLiteral(subject, info, hooks) {
    const original = Object.getOwnPropertyDescriptor(globalThis, "RegExp"), seen = [], trace = [];
    const intrinsic = RegExp;
    try {
        Object.defineProperty(globalThis, "RegExp", {configurable:true, value:function() { throw new Error("live global RegExp"); }});
        const input = {get match() {
            trace.push("get");
            const method = function(regexp) {
                contextSame(this, input, "actual match receiver");
                contextAssert(regexp instanceof intrinsic, "fresh real intrinsic RegExp");
                contextSame(regexp.flags, "", "actual literal has no flags");
                contextSame(regexp.source, /^<skill name="([^"]+)" location="([^"]+)">\n([\s\S]*?)\n<\/skill>(?:\n\n([\s\S]+))?$/.source, "exact literal pattern");
                contextSame(regexp.lastIndex, 0, "fresh RegExp state");
                seen.push(regexp); regexp.lastIndex = 13;
                trace.push("call");
                return null;
            };
            method.holder = hooks.make(seen.length);
            return method;
        }};
        contextSame(subject.parseSkillBlock(input), null, "actual overridden match result");
        contextSame(hooks.count(0), 1, "first temporary match callee retired");
        contextSame(subject.parseSkillBlock(input), null, "second actual overridden match result");
        contextSame(hooks.count(1), 1, "second temporary match callee retired");
        contextAssert(seen[0] !== seen[1], "each literal expression creates a different actual RegExp");
        contextList(trace, ["get","call","get","call"], "callee selected before each literal invocation");
    } finally { contextRestore(globalThis, "RegExp", original); }
}
function observeSkillFields(subject) {
    const trace = [], name = {}, location = Symbol("location"), content = 17, message = {};
    const matched = {
        get 1() { trace.push("name"); return name; },
        get 2() { trace.push("location"); return location; },
        get 3() { trace.push("content"); return content; },
        get 4() { trace.push("tail"); return {get trim() {
            trace.push("trim:get");
            return function() { trace.push("trim:call"); return message; };
        }}; },
    };
    const result = subject.parseSkillBlock({match() { trace.push("match"); return matched; }});
    contextList(trace, ["match","name","location","content","tail","trim:get","trim:call"], "ordered repeated Source field operations");
    contextList(Object.values(result), [name,location,content,message], "actual values are forwarded without string coercion");
}
function observeSkillRetirement(subject, info, hooks) {
    const input = {get match() {
        const method = function() {
            return {
                holder: hooks.make(0),
                get 1() { contextSame(hooks.count(1), 1, "match callee retired before first capture getter"); return "name"; },
                2: "path", 3: "body",
                get 4() {
                    return {
                        holder: hooks.make(2),
                        get trim() {
                            const method = function() { return hooks.make(4); };
                            method.holder = hooks.make(3);
                            return method;
                        },
                    };
                },
            };
        };
        method.holder = hooks.make(1);
        return method;
    }};
    let result = subject.parseSkillBlock(input);
    contextSame(hooks.count(0), 1, "actual match lexical local retired at function return");
    contextSame(hooks.count(2), 1, "optional trim receiver retired before return");
    contextSame(hooks.count(3), 1, "optional trim callee retired before return");
    contextSame(hooks.count(4), 0, "raw truthy trim result belongs to returned record");
    contextAssert(typeof result.userMessage === "object", "raw trim result survives");
    result = null;
    contextSame(hooks.count(4), 1, "result ownership transfers exactly once");
}
function observeSkillOptional(subject) {
    for (const missing of [undefined, null]) {
        const result = subject.parseSkillBlock({match() { return {1:"n",2:"p",3:"b",4:missing}; }});
        contextSame(result.userMessage, undefined, "actual nullish optional chain");
    }
    for (const selected of [undefined, null, false, 0, -0, NaN, ""]) {
        const result = subject.parseSkillBlock({match() { return {1:"n",2:"p",3:"b",4:{trim() { return selected; }}}; }});
        contextSame(result.userMessage, undefined, "actual logical-or fallback");
    }
    for (const result of [undefined, null, false, 0, NaN, ""])
        contextSame(subject.parseSkillBlock({match() { return result; }}), null, "actual match truthiness");
    let caught;
    try { subject.parseSkillBlock({match() { return {4:17}; }}); } catch (error) { caught = error; }
    contextAssert(caught instanceof TypeError, "nonnull optional receiver still calls its live trim method");
}
function observeRangeBasics(subject) {
    for (const [offset, limit, expected] of [
        [undefined,undefined,""], [null,null,""], [undefined,3,":1-3"],
        [null,0,":1"], [0,1,":0"], [5,0,":5-4"], [2,-1,":2"],
        [4,undefined,":4"], [" 2 ","3",":2-4"], ["0x10",2,":16-17"],
        ["",1,""], ["   ",1,""], [NaN,1,""], [Infinity,2,""],
        [1,"Infinity",""], [false,2,""], [{},2,""], [1,{}, ""],
    ]) contextSame(subject.formatReadLineRange(offset, limit), expected, "actual Source numeric/default branch");
}
function observeRangeLiveNumber(subject) {
    const descriptor = Object.getOwnPropertyDescriptor(globalThis, "Number"), trace = [];
    function NumberReplacement(value) { trace.push("Number:"+value); return value === "start" ? 4 : 2; }
    Object.defineProperty(NumberReplacement, "isFinite", {configurable:true, get() {
        trace.push("finite:get");
        return function(value) { contextSame(this, NumberReplacement, "actual Number receiver"); trace.push("finite:"+value); return true; };
    }});
    try {
        Object.defineProperty(globalThis, "Number", {configurable:true, get() { trace.push("global"); return NumberReplacement; }});
        contextSame(subject.formatReadLineRange("start", "count"), ":4-5", "live Number and finite calls");
        contextList(trace, ["global","Number:start","global","finite:get","finite:4","global","Number:count","global","finite:get","finite:2"], "each Source global/member lookup remains live");
    } finally { contextRestore(globalThis, "Number", descriptor); }
}
function observeRangeTrimRetirement(subject, info, hooks) {
    const trim = Object.getOwnPropertyDescriptor(String.prototype, "trim");
    const number = Object.getOwnPropertyDescriptor(globalThis, "Number"), actualNumber = Number;
    let reads = 0;
    try {
        Object.defineProperty(String.prototype, "trim", {configurable:true, get() {
            const fn = function() { return hooks.make(1); };
            fn.holder = hooks.make(0); return fn;
        }});
        Object.defineProperty(globalThis, "Number", {configurable:true, get() {
            reads++;
            contextSame(hooks.count(0), 1, "trim callee retired before Number getter");
            contextSame(hooks.count(1), 1, "strict comparison result retired before Number getter");
            return actualNumber;
        }});
        contextSame(subject.formatReadLineRange("2", null), ":2", "object trim result is tested by strict comparison");
        contextSame(reads, 2, "conversion and finite receiver are independent reads");
    } finally { contextRestore(String.prototype, "trim", trim); contextRestore(globalThis, "Number", number); }
}
function observeRangeFiniteRetirement(subject, info, hooks) {
    const number = Object.getOwnPropertyDescriptor(globalThis, "Number"), actualNumber = Number;
    const finite = Object.getOwnPropertyDescriptor(actualNumber, "isFinite");
    let globals = 0, calls = 0;
    try {
        Object.defineProperty(actualNumber, "isFinite", {configurable:true, get() {
            const fn = function() { calls++; return calls === 1 ? hooks.make(0) : true; };
            if (calls === 0) fn.holder = hooks.make(1);
            return fn;
        }});
        Object.defineProperty(globalThis, "Number", {configurable:true, get() {
            if (++globals === 2) {
                contextSame(hooks.count(0), 1, "finite predicate result retired before count conversion");
                contextSame(hooks.count(1), 1, "finite callee retired before count conversion");
            }
            return actualNumber;
        }});
        contextSame(subject.formatReadLineRange(7, "2"), ":7-8", "actual finite truthiness result");
        contextSame(globals, 3, "actual global receiver reads"); contextSame(calls, 2, "actual predicates");
    } finally { contextRestore(actualNumber, "isFinite", finite); contextRestore(globalThis, "Number", number); }
}
function observeRangeTemplates(subject) {
    const concat = Object.getOwnPropertyDescriptor(String.prototype, "concat");
    const numberString = Object.getOwnPropertyDescriptor(Number.prototype, "toString");
    const finite = Object.getOwnPropertyDescriptor(Number, "isFinite");
    try {
        String.prototype.concat = function() { throw new Error("live concat"); };
        Number.prototype.toString = function() { throw new Error("boxed numeric toString"); };
        Number.isFinite = function() { return true; };
        contextSame(subject.formatReadLineRange(3, 2), ":3-4", "intrinsic template concatenation");
        contextSame(subject.formatReadLineRange(Infinity, 1), ":Infinity-Infinity", "live finite predicate permits actual Infinity");
        contextSame(subject.formatReadLineRange(-Infinity, Infinity), ":-Infinity", "actual NaN end is falsy");
    } finally {
        contextRestore(String.prototype, "concat", concat);
        contextRestore(Number.prototype, "toString", numberString);
        contextRestore(Number, "isFinite", finite);
    }
}
function observeSourceInfoRecords(subject, info) {
    const trace = [], path = {}, source = {}, baseDir = Symbol("base");
    const options = {
        get source() { trace.push("source"); return source; },
        get scope() { trace.push("scope"); return null; },
        get origin() { trace.push("origin"); return undefined; },
        get baseDir() { trace.push("baseDir"); return baseDir; },
    };
    const result = subject.createSyntheticSourceInfo(path, options);
    contextList(trace, ["source","scope","origin","baseDir"], "one ordered lookup per actual literal field");
    contextList(Reflect.ownKeys(result), ["path","source","scope","origin","baseDir"], "actual metadata literal order");
    contextList(Object.values(result), [path,source,"temporary","top-level",baseDir], "actual nullish defaults");
    contextSame(info.createSyntheticSourceInfo(path, {source,scope:false,origin:0}).scope, false, "false scope is preserved");
    contextSame(info.createSyntheticSourceInfo(path, {source,scope:false,origin:0}).origin, 0, "zero origin is preserved");
    const ordinary = info.createSourceInfo(path, {source,scope:null,origin:undefined});
    contextSame(ordinary.scope, null, "ordinary source info has no synthetic default");
    contextSame(ordinary.origin, undefined, "ordinary source info forwards undefined");
    const fields = ["path","source","scope","origin","baseDir"], writes = [];
    const descriptors = fields.map(name => Object.getOwnPropertyDescriptor(Object.prototype, name));
    try {
        for (const name of fields) Object.defineProperty(Object.prototype, name, {
            configurable:true, set() { writes.push(name); },
        });
        for (const constructed of [
            subject.createSyntheticSourceInfo("actual-path", {source:"actual-source"}),
            info.createSourceInfo("actual-path", {source:"actual-source"}),
        ]) {
            contextList(Reflect.ownKeys(constructed), fields, "actual literal defines all own fields");
            contextSame(constructed.path, "actual-path", "literal path bypasses inherited setter");
            contextSame(constructed.source, "actual-source", "literal source bypasses inherited setter");
            for (const name of fields) {
                const descriptor = Object.getOwnPropertyDescriptor(constructed, name);
                contextAssert(descriptor.writable && descriptor.enumerable && descriptor.configurable && "value" in descriptor,
                    "actual own data descriptor " + name);
            }
        }
        contextSame(writes.length, 0, "Source object-literal definitions never invoke inherited setters");
    } finally { fields.forEach((name, index) => contextRestore(Object.prototype, name, descriptors[index])); }
}
function observeSourcePaths(subject, info) {
    for (const [path, source, synthetic] of [
        ["builtin:read","builtin",true], ["<inline:name>","inline",true], ["<:name>","temporary",true],
        ["<>","temporary",true], ["<incomplete",undefined,true], ["file.ts",undefined,false],
    ]) {
        contextSame(info.getSyntheticPathSource(path), source, "actual path source branch");
        contextSame(info.isSyntheticPath(path), synthetic, "actual ordinary string synthetic predicate");
    }
    const returned = {}, calls = [];
    const path = {startsWith(prefix) { calls.push(prefix); return returned; }};
    contextSame(info.isSyntheticPath(path), returned, "logical-or returns first raw truthy method result");
    contextList(calls, ["builtin:"], "truthy result short-circuits second method call");
    let index = 0;
    contextSame(info.isSyntheticPath({startsWith() { return index++ === 0 ? 0 : "raw"; }}), "raw", "logical-or returns second raw result");
}
function observeSourceChainRetirement(subject, info, hooks) {
    const path = {
        startsWith(prefix) { return prefix === "<"; }, endsWith() { return true; },
        get slice() {
            const fn = function() {
                return {holder:hooks.make(1), get split() {
                    contextSame(hooks.count(0), 1, "slice callee retired before split getter");
                    const split = function() {
                        return {holder:hooks.make(3), get 0() {
                            contextSame(hooks.count(1), 1, "temporary split receiver retired before index");
                            contextSame(hooks.count(2), 1, "split callee retired before index");
                            return hooks.make(4);
                        }};
                    };
                    split.holder = hooks.make(2); return split;
                }};
            };
            fn.holder = hooks.make(0); return fn;
        },
    };
    let result = info.getSyntheticPathSource(path);
    contextSame(hooks.count(3), 1, "indexed temporary receiver retired before return");
    contextSame(hooks.count(4), 0, "raw selected field owner is returned");
    result = null;
    contextSame(hooks.count(4), 1, "actual final result ownership");
}
function observeContextPrivateData(subject, info, hooks, kind) {
    let reason, caught;
    const fail = function() { reason = hooks.freshPrivateData(); throw reason; };
    const trim = Object.getOwnPropertyDescriptor(String.prototype, "trim");
    try {
        if (kind === "match") {
            try { subject.parseSkillBlock({get match() { return fail(); }}); } catch (error) { caught = error; }
        } else if (kind === "trim") {
            try { subject.parseSkillBlock({match() { return {4:{get trim() { return fail(); }}}; }}); } catch (error) { caught = error; }
        } else if (kind === "range") {
            Object.defineProperty(String.prototype, "trim", {configurable:true,get:fail});
            try { subject.formatReadLineRange("2", 3); } catch (error) { caught = error; }
        } else {
            try { info.createSyntheticSourceInfo("p", {get source() { return fail(); }}); } catch (error) { caught = error; }
        }
        contextSame(caught, reason, "same actual getter private DATA identity");
        contextAssert(hooks.isUnmarkedPrivateData(caught), "ordinary private DATA remains unmarked");
    } finally { contextRestore(String.prototype, "trim", trim); }
}
function observeSkillCurrentFatal(subject, info, hooks) {
    const input = {match() { return {
        get 1() { hooks.freshPrivateData(); return hooks.raiseNativeFatal(); },
        get 2() { hooks.visit(1); return "p"; },
        get 4() { hooks.visit(2); return undefined; },
    }; }};
    try { subject.parseSkillBlock(input); hooks.record.guestReached = true; hooks.visit(3); }
    catch (error) { hooks.record.guestReached = true; hooks.visit(3); throw error; }
}
function observeSkillTrimFatal(subject, info, hooks) {
    const input = {match() { return {get 4() {
        const receiver = hooks.make(0); receiver.trim = function() { return "tail"; }; return receiver;
    }}; }};
    hooks.armFatal(0);
    try { subject.parseSkillBlock(input); hooks.record.guestReached = true; hooks.visit(1); }
    catch (error) { hooks.record.guestReached = true; hooks.visit(2); throw error; }
}
function observeRangeTrimFailure(subject, info, hooks, cancel) {
    const actualNumber = Number;
    Object.defineProperty(String.prototype, "trim", {configurable:true, value:function() { return hooks.make(0); }});
    Object.defineProperty(globalThis, "Number", {configurable:true, get() { hooks.visit(1); return actualNumber; }});
    if (cancel) hooks.armCancel(0); else hooks.armFatal(0);
    try { subject.formatReadLineRange("2", null); hooks.record.guestReached = true; hooks.visit(2); }
    catch (error) { hooks.record.guestReached = true; hooks.visit(2); throw error; }
}
function observeSourceInfoCurrentFatal(subject, info, hooks) {
    const options = {
        source: "actual", scope: "user",
        get origin() { hooks.freshPrivateData(); return hooks.raiseNativeFatal(); },
        get baseDir() { hooks.visit(1); return "never"; },
    };
    try { subject.createSyntheticSourceInfo("p", options); hooks.record.guestReached = true; hooks.visit(2); }
    catch (error) { hooks.record.guestReached = true; hooks.visit(2); throw error; }
}
