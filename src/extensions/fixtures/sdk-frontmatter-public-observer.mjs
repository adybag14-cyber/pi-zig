// Real c268 frontend bodies; the selected parser import is the existing native
// C YAML owner in both realms. No full yaml-package comparison is implied.
function fmAssert(value, message) { if (!value) throw new Error(message); }
function fmSame(actual, expected, message) { fmAssert(Object.is(actual, expected), message); }
function fmList(actual, expected, message) {
    fmAssert(actual.length === expected.length && actual.every((value, index) => Object.is(value, expected[index])), message);
}
function fmRestore(object, key, descriptor) {
    if (descriptor) Object.defineProperty(object, key, descriptor); else delete object[key];
}
function fmInput(makeNormalized) {
    return {
        startsWith(prefix) { fmSame(prefix, "\uFEFF", "actual BOM predicate"); return false; },
        replace() { return {replace() { return makeNormalized(); }}; },
    };
}
function observeFrontmatterShapes(subject, text) {
    for (const name of ["parseFrontmatter", "stripFrontmatter"]) {
        const fn = subject[name];
        fmSame(fn.name, name, "actual public arrow name"); fmSame(fn.length, 1, "actual arrow arity");
        fmAssert(!Object.hasOwn(fn, "prototype"), "actual arrow has no constructor prototype");
        let failed = false; try { Reflect.construct(fn, []); } catch (error) { failed = error instanceof TypeError; }
        fmAssert(failed, "actual arrow is not constructible");
    }
    for (const name of ["splitBom", "stripBom"]) {
        fmSame(text[name].name, name, "actual text declaration name");
        fmSame(text[name].length, 1, "actual text declaration arity");
        fmAssert(Object.hasOwn(text[name], "prototype"), "actual ordinary text declaration");
    }
}
function observeFrontmatterBasics(subject, text) {
    for (const [input, body] of [
        ["plain\r\ntext\rnext", "plain\ntext\nnext"],
        ["\uFEFFplain", "plain"], [" \uFEFFplain", " \uFEFFplain"],
        ["---\ntitle: x\n---\n  body \n", "body"],
        ["---\r\ntitle: x\r\n---\r\nbody\r\n", "body"],
        ["---\n---\n body ", "body"], ["---x\n---tail", "tail"],
        ["---\nunclosed", "---\nunclosed"], ["", ""],
    ]) {
        fmSame(subject.parseFrontmatter(input).body, body, "actual normalized/extracted body");
        fmSame(subject.stripFrontmatter(input), body, "strip executes the same parse path");
    }
    fmList(Object.values(text.splitBom("\uFEFFtext")), ["\uFEFF","text"], "actual BOM record");
    fmList(Object.values(text.splitBom("text")), ["","text"], "actual no-BOM record");
    fmSame(text.stripBom("\uFEFF\uFEFFtext"), "\uFEFFtext", "strip removes one BOM");
}
function observeFrontmatterValues(subject) {
    for (const [source, expected] of [["null",null],["false",false],["0",0],["'hello'","hello"]]) {
        const actual = subject.parseFrontmatter("---\n" + source + "\n---\nbody").frontmatter;
        if (expected === null) fmList(Object.keys(actual), [], "parsed null gives a new empty object");
        else fmSame(actual, expected, "all non-null YAML scalars are preserved");
    }
    const result = subject.parseFrontmatter("---\nroot: &root {self: *root, values: [true, 0x2a, null, \"42\"]}\ncopy: *root\n---\nbody");
    fmSame(result.frontmatter.root, result.frontmatter.copy, "real YAML alias graph identity");
    fmSame(result.frontmatter.root.self, result.frontmatter.root, "real recursive YAML graph");
    fmList(result.frontmatter.root.values, [true,42,null,"42"], "real native YAML value types");
    fmSame(subject.parseFrontmatter("---\n\"\\ud800\"\n---\nbody").frontmatter.charCodeAt(0), 0xd800, "isolated UTF16 preserved");
}
function observeFrontmatterLiterals(subject) {
    const descriptor = Object.getOwnPropertyDescriptor(globalThis, "RegExp"), actual = RegExp;
    const seen = [], trace = [];
    const normalized = {startsWith(prefix) { trace.push("fence"); return false; }};
    const input = {
        startsWith() { trace.push("bom"); return false; },
        get replace() {
            trace.push("first:get");
            return function(regexp, replacement) {
                fmAssert(regexp instanceof actual, "actual first intrinsic RegExp");
                fmSame(regexp.source, "\\r\\n", "actual first pattern"); fmSame(regexp.flags, "g", "first flags");
                fmSame(regexp.lastIndex, 0, "fresh first state"); fmSame(replacement, "\n", "first replacement");
                seen.push(regexp); regexp.lastIndex = 17; trace.push("first:call");
                return {get replace() {
                    trace.push("second:get");
                    return function(next, value) {
                        fmAssert(next instanceof actual, "actual second intrinsic RegExp");
                        fmSame(next.source, "\\r", "actual second pattern"); fmSame(next.flags, "g", "second flags");
                        fmSame(next.lastIndex, 0, "fresh second state"); fmSame(value, "\n", "second replacement");
                        seen.push(next); trace.push("second:call"); return normalized;
                    };
                }};
            };
        },
    };
    try {
        Object.defineProperty(globalThis, "RegExp", {configurable:true,value:function() { throw new Error("late global RegExp"); }});
        fmSame(subject.parseFrontmatter(input).body, normalized, "raw normalized result");
        fmSame(subject.parseFrontmatter(input).body, normalized, "fresh second literal evaluation");
        fmAssert(seen[0] !== seen[2] && seen[1] !== seen[3], "each literal creates a fresh actual object");
        fmList(trace, ["bom","first:get","first:call","second:get","second:call","fence","bom","first:get","first:call","second:get","second:call","fence"], "literal/callee sequence");
    } finally { fmRestore(globalThis, "RegExp", descriptor); }
}
function observeFrontmatterNormalizeRetirement(subject, text, hooks) {
    const input = {
        startsWith() { return false; },
        get replace() {
            const first = function() {
                return {holder:hooks.make(1), get replace() {
                    fmSame(hooks.count(0), 1, "first replace callee retires before second getter");
                    const second = function() {
                        return {holder:hooks.make(3), get startsWith() {
                            fmSame(hooks.count(1), 1, "second replace receiver retires before fence getter");
                            fmSame(hooks.count(2), 1, "second replace callee retires before fence getter");
                            return function() { return false; };
                        }};
                    };
                    second.holder = hooks.make(2); return second;
                }};
            };
            first.holder = hooks.make(0); return first;
        },
    };
    let result = subject.parseFrontmatter(input);
    fmSame(hooks.count(3), 0, "normalized local is retained by the actual returned body");
    result = null;
    fmSame(hooks.count(3), 1, "returned body releases its sole real holder");
}
function observeFrontmatterBomPredicate(subject, text, hooks) {
    const input = {
        startsWith() { return hooks.make(0); },
        get slice() {
            fmSame(hooks.count(0), 1, "BOM predicate value retires before slice getter");
            return function(index) { fmSame(index, 1, "actual BOM slice"); return "plain"; };
        },
    };
    fmSame(subject.parseFrontmatter(input).body, "plain", "actual truthy BOM predicate branch");
}
function observeFrontmatterFencePredicate(subject, text, hooks) {
    const input = fmInput(() => ({
        startsWith() { return hooks.make(0); },
        get indexOf() {
            fmSame(hooks.count(0), 1, "fence predicate value retires before indexOf getter");
            return function() { return -1; };
        },
    }));
    fmAssert(typeof subject.parseFrontmatter(input).body === "object", "no-fence result preserves normalized object");
}
function observeFrontmatterFieldOrder(subject) {
    const trace = [], rawBody = {};
    const end = {[Symbol.toPrimitive](hint) { trace.push("end:" + hint); return 5; }};
    const input = fmInput(() => ({
        startsWith() { trace.push("fence"); return true; },
        indexOf(needle, start) { fmSame(needle, "\n---", "actual closing needle"); fmSame(start, 3, "actual search start"); return end; },
        get slice() {
            trace.push("slice:get");
            return function(first, second) {
                if (arguments.length === 2) {
                    fmSame(first, 4, "actual YAML begin"); fmSame(second, end, "raw end operand before delegated slice");
                    trace.push("yaml:call"); return "";
                }
                fmSame(first, 9, "actual generic end + 4"); trace.push("body:call");
                return {get trim() { trace.push("trim:get"); return function() { trace.push("trim:call"); return rawBody; }; }};
            };
        },
    }));
    const result = subject.parseFrontmatter(input);
    fmSame(result.body, rawBody, "raw overridden trim result");
    fmList(trace, ["fence","slice:get","yaml:call","slice:get","end:default","body:call","trim:get","trim:call"], "ordered record fields and callee-before-operand selection");
    fmList(Object.keys(result.frontmatter), [], "empty selected YAML skips the parser");
}
function observeFrontmatterStrictEnd(subject) {
    let coerced = 0, calls = 0;
    const input = fmInput(() => ({
        startsWith() { return true; },
        indexOf() { return {valueOf() { coerced++; return -1; }}; },
        slice(first, second) {
            calls++;
            if (arguments.length === 2) return "";
            return {trim() { return "body"; }};
        },
    }));
    fmSame(subject.parseFrontmatter(input).body, "body", "object end is not strict numeric -1");
    fmSame(calls, 2, "both actual slices still execute"); fmSame(coerced, 1, "only actual addition coerces the end object");
}
function observeFrontmatterExtractRetirement(subject, text, hooks) {
    const date = Object.getOwnPropertyDescriptor(globalThis, "Date"), actual = Date;
    const input = fmInput(() => ({
        holder:hooks.make(4),
        startsWith() { return true; },
        indexOf() { const end = hooks.make(3); end.valueOf = function() { return 40; }; return end; },
        get slice() {
            const fn = function() {
                if (arguments.length === 2) return "!!timestamp 2001-12-15T02:59:43.1Z";
                return {holder:hooks.make(1), get trim() {
                    fmSame(hooks.count(0), 1, "body slice callee retires before trim getter");
                    const method = function() { return "body"; }; method.holder = hooks.make(2); return method;
                }};
            };
            // Only the second, body-producing slice carries this sole holder.
            if (this.sliceCount === undefined) this.sliceCount = 0;
            if (++this.sliceCount === 2) fn.holder = hooks.make(0);
            return fn;
        },
    }));
    try {
        Object.defineProperty(globalThis, "Date", {configurable:true,get() {
            for (let id = 0; id < 5; id++) fmSame(hooks.count(id), 1, "extract expression/local retires before genuine YAML Date " + id);
            return actual;
        }});
        const result = subject.parseFrontmatter(input);
        fmAssert(result.frontmatter instanceof actual, "actual existing YAML timestamp owner");
        fmSame(result.body, "body", "actual text body");
    } finally { fmRestore(globalThis, "Date", date); }
}
function observeFrontmatterRecords(subject, text) {
    const fields = ["bom","text","yamlString","frontmatter","body"];
    const descriptors = fields.map(name => Object.getOwnPropertyDescriptor(Object.prototype, name));
    let writes = 0;
    try {
        for (const field of fields) Object.defineProperty(Object.prototype, field, {configurable:true,set() { writes++; }});
        const bom = text.splitBom("\uFEFFplain");
        const parsed = subject.parseFrontmatter("---\ntitle: x\n---\nbody");
        fmList(Object.keys(bom), ["bom","text"], "actual BOM own-field order");
        fmList(Object.keys(parsed), ["frontmatter","body"], "actual parsed own-field order");
        for (const [record, keys] of [[bom,["bom","text"]],[parsed,["frontmatter","body"]]]) {
            for (const key of keys) {
                const d = Object.getOwnPropertyDescriptor(record, key);
                fmAssert(d && "value" in d && d.configurable && d.enumerable && d.writable, "actual own data descriptor");
            }
        }
        fmSame(writes, 0, "object literals bypass inherited setters");
    } finally { fields.forEach((name, index) => fmRestore(Object.prototype, name, descriptors[index])); }
}
function observeFrontmatterStripValidation(subject) {
    let failed = false;
    try { subject.stripFrontmatter("---\na: [\n---\nbody"); }
    catch (error) { failed = error.name === "YAMLParseError" && typeof error.message === "string"; }
    fmAssert(failed, "stripFrontmatter still invokes the real YAML parser");
}
function observeFrontmatterPrivateData(subject, text, hooks, kind) {
    let reason, caught;
    const fail = function() { reason = hooks.freshPrivateData(); throw reason; };
    const set = Object.getOwnPropertyDescriptor(globalThis, "Set");
    try {
        if (kind === "bom") {
            try { subject.parseFrontmatter({get startsWith() { return fail(); }}); } catch (error) { caught = error; }
        } else if (kind === "replace") {
            try { subject.parseFrontmatter({startsWith() { return false; }, get replace() { return fail(); }}); } catch (error) { caught = error; }
        } else if (kind === "trim") {
            const input = fmInput(() => ({startsWith() { return true; },indexOf() { return 4; },slice() { return arguments.length === 2 ? "" : {get trim() { return fail(); }}; }}));
            try { subject.parseFrontmatter(input); } catch (error) { caught = error; }
        } else {
            Object.defineProperty(globalThis, "Set", {configurable:true,value:function() { return fail(); }});
            try { subject.stripFrontmatter("---\n!!set {a: null}\n---\nbody"); } catch (error) { caught = error; }
        }
        fmSame(caught, reason, "actual frontend/dependency DATA identity");
        fmAssert(hooks.isUnmarkedPrivateData(caught), "private DATA stays ordinary and unmarked");
    } finally { fmRestore(globalThis, "Set", set); }
}
function observeFrontmatterCurrentFatal(subject, text, hooks) {
    const input = fmInput(() => ({
        startsWith() { return true; },
        indexOf() { hooks.freshPrivateData(); return hooks.raiseNativeFatal(); },
        get slice() { hooks.visit(1); return function() { hooks.visit(2); return ""; }; },
    }));
    try { subject.parseFrontmatter(input); hooks.record.guestReached = true; hooks.visit(3); }
    catch (error) { hooks.record.guestReached = true; hooks.visit(3); throw error; }
}
function observeFrontmatterPredicateFatal(subject, text, hooks, cancel) {
    const input = fmInput(() => ({
        startsWith() { return hooks.make(0); },
        get indexOf() { hooks.visit(1); return function() { hooks.visit(2); return -1; }; },
    }));
    if (cancel) hooks.armCancel(0); else hooks.armFatal(0);
    try { subject.parseFrontmatter(input); hooks.record.guestReached = true; hooks.visit(3); }
    catch (error) { hooks.record.guestReached = true; hooks.visit(3); throw error; }
}
function observeFrontmatterTrimFatal(subject, text, hooks) {
    const original = Date;
    Object.defineProperty(globalThis, "Date", {configurable:true,get() { hooks.visit(1); return original; }});
    const input = fmInput(() => ({
        startsWith() { return true; }, indexOf() { return 40; },
        slice() {
            if (arguments.length === 2) return "!!timestamp 2001-12-15";
            const receiver = hooks.make(0); receiver.trim = function() { return "body"; }; return receiver;
        },
    }));
    hooks.armFatal(0);
    try { subject.parseFrontmatter(input); hooks.record.guestReached = true; hooks.visit(2); }
    catch (error) { hooks.record.guestReached = true; hooks.visit(3); throw error; }
}
function observeFrontmatterCalleeFatal(subject, text, hooks) {
    const input = {
        startsWith() { return false; },
        get replace() {
            const fn = function() { return {get replace() { hooks.visit(1); return function() { hooks.visit(2); return ""; }; }}; };
            fn.holder = hooks.make(0); return fn;
        },
    };
    hooks.armFatal(0);
    try { subject.parseFrontmatter(input); hooks.record.guestReached = true; hooks.visit(3); }
    catch (error) { hooks.record.guestReached = true; hooks.visit(3); throw error; }
}
