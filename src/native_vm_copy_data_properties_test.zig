//! Actual linked Object.assign and object spread/rest descriptor timing.
//! The original inspector regression remains unchanged in its own root.
const std = @import("std");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
});

const Fixture = struct {
    runtime: ?*c.JSRuntime = null,
    context: ?*c.JSContext = null,

    fn init(self: *Fixture) !void {
        self.* = .{};
        self.runtime = c.JS_NewRuntime() orelse return error.OutOfMemory;
        errdefer self.deinit();
        c.JS_SetMaxStackSize(self.runtime.?, 1024 * 1024);
        self.context = c.JS_NewContext(self.runtime.?) orelse return error.OutOfMemory;
        try self.run(
            \\function check(value, label) { if (!value) throw new Error(label); }
        );
    }
    fn deinit(self: *Fixture) void {
        if (self.context) |context| {
            if (c.JS_HasException(context)) {
                const reason = c.JS_GetException(context);
                c.JS_FreeValue(context, reason);
            }
            self.context = null;
            c.JS_FreeContext(context);
        }
        if (self.runtime) |runtime| {
            self.runtime = null;
            c.JS_FreeRuntime(runtime);
        }
    }
    fn checked(self: *Fixture, value: c.JSValue) !c.JSValue {
        if (c.JS_IsException(value) or c.JS_HasException(self.context.?)) {
            c.JS_FreeValue(self.context.?, value);
            return error.ActualCopyPropertiesControlException;
        }
        return value;
    }
    fn eval(self: *Fixture, source: [:0]const u8) !c.JSValue {
        return self.checked(c.JS_Eval(self.context.?, source.ptr, source.len,
            "actual-copy-properties.js", c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT));
    }
    fn run(self: *Fixture, source: [:0]const u8) !void {
        const result = try self.eval(source);
        defer c.JS_FreeValue(self.context.?, result);
        try std.testing.expect(!c.JS_HasException(self.context.?));
        try std.testing.expect(!c.JS_IsJobPending(self.runtime.?));
    }
    fn publish(self: *Fixture, name: [*:0]const u8, borrowed: c.JSValue) !void {
        const global_object = try self.checked(c.JS_GetGlobalObject(self.context.?));
        defer c.JS_FreeValue(self.context.?, global_object);
        try std.testing.expectEqual(@as(c_int, 1),
            c.JS_DefinePropertyValueStr(self.context.?, global_object, name,
                c.JS_DupValue(self.context.?, borrowed), c.JS_PROP_C_W_E));
        try std.testing.expect(!c.JS_HasException(self.context.?));
    }
    fn ownBoolean(self: *Fixture, object: c.JSValue, name: [*:0]const u8, expected: bool) !void {
        // The caller retained this exact plain record before the fatal call.
        // Its known own primitive fields are inspected without guest evaluation.
        const value = c.JS_GetPropertyStr(self.context.?, object, name);
        defer c.JS_FreeValue(self.context.?, value);
        try std.testing.expect(c.JS_IsBool(value));
        try std.testing.expectEqual(@as(c_int, @intFromBool(expected)), c.JS_ToBool(self.context.?, value));
    }
};

test "VM copy properties assign skips a deleted own key and preserves the existing target" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    try f.run(
        \\(() => {
        \\    const previous = {depth: 2, colors: false}, trace = [];
        \\    const proto = {};
        \\    Object.defineProperty(proto, "colors", {get() { trace.push("prototype"); return 99; }});
        \\    const input = Object.create(proto);
        \\    Object.defineProperty(input, "depth", {enumerable: true, get() {
        \\        trace.push("depth"); delete input.colors; return 0;
        \\    }});
        \\    Object.defineProperty(input, "colors", {enumerable: true, configurable: true, get() {
        \\        trace.push("colors"); return true;
        \\    }});
        \\    const result = Object.assign(previous, input);
        \\    check(result === previous && previous.depth === 0 && previous.colors === false, "deleted key preserves defaults");
        \\    check(trace.join() === "depth", "no deleted value or inherited fallback read");
        \\})();
    );
}

test "VM copy properties includes an initially hidden key made enumerable by a prior getter" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    try f.run(
        \\(() => {
        \\    const copies = [s => Object.assign({}, s), s => ({...s}), s => { const {...r} = s; return r; }];
        \\    for (const copy of copies) {
        \\        const trace = [], source = {};
        \\        Object.defineProperty(source, "first", {enumerable: true, get() {
        \\            trace.push("first"); Object.defineProperty(source, "later", {enumerable: true}); return 1;
        \\        }});
        \\        Object.defineProperty(source, "later", {configurable: true, enumerable: false, get() {
        \\            trace.push("later"); check(this === source, "actual receiver"); return 2;
        \\        }});
        \\        const result = copy(source);
        \\        check(Object.keys(result).join() === "first,later" && result.later === 2, "all own keys snapshotted");
        \\        check(trace.join() === "first,later", "later descriptor observed after first Get");
        \\    }
        \\})();
    );
}

test "VM copy properties skips a key made nonenumerable before its value read" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    try f.run(
        \\(() => {
        \\    const copies = [s => Object.assign({}, s), s => ({...s}), s => { const {...r} = s; return r; }];
        \\    for (const copy of copies) {
        \\        const trace = [], source = {};
        \\        Object.defineProperty(source, "first", {enumerable: true, get() {
        \\            trace.push("first"); Object.defineProperty(source, "later", {enumerable: false}); return 1;
        \\        }});
        \\        Object.defineProperty(source, "later", {configurable: true, enumerable: true, get() {
        \\            trace.push("later"); return 2;
        \\        }});
        \\        const result = copy(source);
        \\        check(Object.keys(result).join() === "first" && !Object.hasOwn(result, "later"), "newly hidden key skipped");
        \\        check(trace.join() === "first", "hidden value getter not entered");
        \\    }
        \\})();
    );
}

test "VM copy properties spread and rest skip deleted slots without inherited fallback" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    try f.run(
        \\(() => {
        \\    const copies = [s => ({...s}), s => { const {...r} = s; return r; }];
        \\    for (const copy of copies) {
        \\        const trace = [], proto = {};
        \\        Object.defineProperty(proto, "later", {get() { trace.push("inherited"); return 9; }});
        \\        const source = Object.create(proto);
        \\        Object.defineProperty(source, "first", {enumerable: true, get() {
        \\            trace.push("first"); delete source.later; return 1;
        \\        }});
        \\        Object.defineProperty(source, "later", {enumerable: true, configurable: true, value: 2});
        \\        const result = copy(source);
        \\        check(result.first === 1 && !Object.hasOwn(result, "later"), "rest or spread preserves absence");
        \\        check(trace.join() === "first", "prototype lookup skipped");
        \\    }
        \\})();
    );
}

test "VM copy properties reads replacement values but never adds keys created after the snapshot" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    try f.run(
        \\(() => {
        \\    const copies = [s => Object.assign({}, s), s => ({...s}), s => { const {...r} = s; return r; }];
        \\    for (const copy of copies) {
        \\        const trace = [], source = {};
        \\        Object.defineProperty(source, "first", {enumerable: true, get() {
        \\            trace.push("first");
        \\            Object.defineProperty(source, "later", {enumerable: true, configurable: true, get() {
        \\                check(this === source, "replacement receiver"); trace.push("replacement"); return 7;
        \\            }});
        \\            source.added = 8;
        \\            return 1;
        \\        }});
        \\        Object.defineProperty(source, "later", {enumerable: true, configurable: true, value: 2});
        \\        const result = copy(source);
        \\        check(result.later === 7 && !Object.hasOwn(result, "added"), "live value and fixed key list");
        \\        check(trace.join() === "first,replacement", "replacement getter chosen");
        \\    }
        \\})();
    );
}

test "VM copy properties keeps numeric string and symbol key order with live symbol descriptors" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    try f.run(
        \\(() => {
        \\    const copies = [s => Object.assign({}, s), s => ({...s}), s => { const {...r} = s; return r; }];
        \\    for (const copy of copies) {
        \\        const hidden = Symbol("hidden"), removed = Symbol("removed"), added = Symbol("added");
        \\        const source = {}, trace = [];
        \\        Object.defineProperty(source, "2", {enumerable: true, get() { trace.push("2"); return 2; }});
        \\        Object.defineProperty(source, "0", {enumerable: true, get() {
        \\            trace.push("0"); Object.defineProperty(source, hidden, {enumerable: true});
        \\            delete source[removed]; source[added] = 8; return 0;
        \\        }});
        \\        Object.defineProperty(source, "name", {enumerable: true, get() { trace.push("name"); return 3; }});
        \\        Object.defineProperty(source, hidden, {enumerable: false, configurable: true, get() { trace.push("symbol"); return 4; }});
        \\        Object.defineProperty(source, removed, {enumerable: true, configurable: true, get() { trace.push("removed"); return 5; }});
        \\        const result = copy(source), keys = Reflect.ownKeys(result);
        \\        check(keys.length === 4 && keys[0] === "0" && keys[1] === "2" && keys[2] === "name" && keys[3] === hidden, "snapshot ordering");
        \\        check(result[hidden] === 4 && !Object.hasOwn(result, removed) && !Object.hasOwn(result, added), "symbol descriptor timing");
        \\        check(trace.join() === "0,2,name,symbol", "symbol values after strings");
        \\    }
        \\})();
    );
}

test "VM copy properties preserves actual proxy descriptor Get and target Set order" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    try f.run(
        \\(() => {
        \\    const trace = [], symbol = Symbol("selected"), source = {};
        \\    let from, to;
        \\    const label = key => key === symbol ? "symbol" : key;
        \\    Object.defineProperty(source, "first", {enumerable: true, configurable: true, get() {
        \\        check(this === from, "source proxy receiver");
        \\        Object.defineProperty(source, "hidden", {enumerable: true}); delete source.gone; return 1;
        \\    }});
        \\    Object.defineProperty(source, "hidden", {enumerable: false, configurable: true, value: 2});
        \\    source.gone = 3; source.last = 4; source[symbol] = 5;
        \\    from = new Proxy(source, {
        \\        ownKeys(target) { check(target === source, "ownKeys target"); trace.push("keys"); return ["first", "hidden", "gone", "last", symbol]; },
        \\        getOwnPropertyDescriptor(target, key) { trace.push("desc:" + label(key)); return Reflect.getOwnPropertyDescriptor(target, key); },
        \\        get(target, key, receiver) { check(receiver === from, "Get receiver"); trace.push("get:" + label(key)); return Reflect.get(target, key, receiver); }
        \\    });
        \\    const target = {};
        \\    to = new Proxy(target, {set(object, key, value, receiver) {
        \\        check(object === target && receiver === to, "Set target and receiver");
        \\        trace.push("set:" + label(key)); return Reflect.set(object, key, value, object);
        \\    }});
        \\    check(Object.assign(to, from) === to, "returned target");
        \\    check(trace.join() === "keys,desc:first,get:first,set:first,desc:hidden,get:hidden,set:hidden,desc:gone,desc:last,get:last,set:last,desc:symbol,get:symbol,set:symbol", "per-key operations");
        \\    check(target.hidden === 2 && target[symbol] === 5 && !Object.hasOwn(target, "gone"), "actual copied target");
        \\})();
    );
}

test "VM copy properties rest excludes string and symbol keys before descriptor lookup" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    try f.run(
        \\(() => {
        \\    const symbol = Symbol("skip"), target = {skip: 1, keep: 3, [symbol]: 2}, trace = [];
        \\    const source = new Proxy(target, {
        \\        ownKeys() { trace.push("keys"); return ["skip", symbol, "keep"]; },
        \\        getOwnPropertyDescriptor(object, key) {
        \\            check(key === "keep", "excluded descriptor not observed");
        \\            trace.push("desc:keep"); return Reflect.getOwnPropertyDescriptor(object, key);
        \\        },
        \\        get(object, key, receiver) {
        \\            trace.push(key === symbol ? "get:symbol" : "get:" + key);
        \\            return Reflect.get(object, key, receiver);
        \\        }
        \\    });
        \\    const {skip, [symbol]: skippedSymbol, ...rest} = source;
        \\    check(skip === 1 && skippedSymbol === 2 && rest.keep === 3 && Reflect.ownKeys(rest).join() === "keep", "actual rest exclusions");
        \\    check(trace.join() === "get:skip,get:symbol,keys,desc:keep,get:keep", "binding then excluded copy order");
        \\})();
    );
}

test "VM copy properties target setters can change later source descriptors" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    try f.run(
        \\(() => {
        \\    const trace = [], source = {first: 1};
        \\    Object.defineProperty(source, "later", {enumerable: true, configurable: true, get() { trace.push("later"); return 2; }});
        \\    Object.defineProperty(source, "hidden", {enumerable: false, configurable: true, get() { trace.push("hidden"); return 3; }});
        \\    const target = {};
        \\    Object.defineProperty(target, "first", {set(value) {
        \\        check(this === target && value === 1, "actual target setter");
        \\        trace.push("set:first"); delete source.later;
        \\        Object.defineProperty(source, "hidden", {enumerable: true});
        \\    }});
        \\    check(Object.assign(target, source) === target, "target identity");
        \\    check(target.hidden === 3 && !Object.hasOwn(target, "later"), "descriptor after prior Set");
        \\    check(trace.join() === "set:first,hidden", "setter effects precede later descriptor");
        \\})();
    );
}

test "VM copy properties spread and rest create own data slots without prototype setters" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    try f.run(
        \\(() => {
        \\    const copies = [s => ({...s}), s => { const {...r} = s; return r; }];
        \\    const name = "actualCopySlot", original = Object.getOwnPropertyDescriptor(Object.prototype, name);
        \\    let sets = 0;
        \\    Object.defineProperty(Object.prototype, name, {configurable: true, set() { sets++; throw 99; }});
        \\    try {
        \\        for (const copy of copies) {
        \\            const source = {};
        \\            Object.defineProperty(source, name, {enumerable: true, get() { return 7; }});
        \\            const result = copy(source), desc = Object.getOwnPropertyDescriptor(result, name);
        \\            check(desc.value === 7 && desc.writable && desc.enumerable && desc.configurable, "own data definition");
        \\        }
        \\        check(sets === 0, "no inherited Set");
        \\    } finally {
        \\        if (original) Object.defineProperty(Object.prototype, name, original);
        \\        else delete Object.prototype[name];
        \\    }
        \\})();
    );
}

test "VM copy properties ordinary descriptor and getter failures keep identity and stop later copies" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    try f.run(
        \\(() => {
        \\    for (const phase of ["descriptor", "get"]) {
        \\        const reason = {phase}, trace = [], target = {};
        \\        const plain = {first: 1, second: 2, later: 3};
        \\        const source = new Proxy(plain, {
        \\            ownKeys(object) { trace.push("keys"); return Reflect.ownKeys(object); },
        \\            getOwnPropertyDescriptor(object, key) {
        \\                trace.push("desc:" + key); if (phase === "descriptor" && key === "second") throw reason;
        \\                return Reflect.getOwnPropertyDescriptor(object, key);
        \\            },
        \\            get(object, key, receiver) {
        \\                trace.push("get:" + key); if (phase === "get" && key === "second") throw reason;
        \\                return Reflect.get(object, key, receiver);
        \\            }
        \\        });
        \\        let caught = false;
        \\        try { Object.assign(target, source); } catch (actual) { check(actual === reason, "ordinary reason identity"); caught = true; }
        \\        check(caught && target.first === 1 && Reflect.ownKeys(target).join() === "first", "partial target retained");
        \\        check(trace.join() === (phase === "descriptor" ? "keys,desc:first,get:first,desc:second" : "keys,desc:first,get:first,desc:second,get:second"), "no later Get or Set");
        \\    }
        \\})();
    );
}

test "VM copy properties returned flagged DATA remains a copied value" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    const reason = try f.checked(c.JS_NewError(f.context.?));
    defer c.JS_FreeValue(f.context.?, reason);
    c.JS_SetUncatchableError(f.context.?, reason);
    try f.publish("flaggedData", reason);
    try f.run(
        \\(() => {
        \\    const copies = [s => Object.assign({}, s), s => ({...s}), s => { const {...r} = s; return r; }];
        \\    for (const copy of copies) {
        \\        let calls = 0;
        \\        const source = {get value() { calls++; return flaggedData; }};
        \\        const result = copy(source);
        \\        check(calls === 1 && result.value === flaggedData && Object.keys(result).join() === "value", "returned DATA identity");
        \\    }
        \\})();
    );
    try std.testing.expect(!c.JS_HasException(f.context.?));
}

test "VM copy properties actual fatal getter skips later value catch and finally" {
    const operations = [_][:0]const u8{
        \\try { Object.assign(actualTarget, actualSource); progress.after = true; }
        \\catch (error) { progress.caught = true; }
        \\finally { progress.closed = true; }
        ,
        \\try { ({...actualSource}); progress.after = true; }
        \\catch (error) { progress.caught = true; }
        \\finally { progress.closed = true; }
        ,
        \\try { const {...result} = actualSource; progress.after = true; }
        \\catch (error) { progress.caught = true; }
        \\finally { progress.closed = true; }
        ,
    };
    for (operations) |operation| {
        var f: Fixture = .{};
        try f.init();
        defer f.deinit();
        const reason = try f.checked(c.JS_NewError(f.context.?));
        defer c.JS_FreeValue(f.context.?, reason);
        c.JS_SetUncatchableError(f.context.?, reason);
        try f.publish("flaggedData", reason);
        try f.run(
            \\var progress = {first: false, second: false, later: false, caught: false, closed: false, after: false};
            \\var actualTarget = {}, actualSource = {};
            \\Object.defineProperties(actualSource, {
            \\    first: {enumerable: true, get() { progress.first = true; return 1; }},
            \\    second: {enumerable: true, get() { progress.second = true; throw flaggedData; }},
            \\    later: {enumerable: true, get() { progress.later = true; return 3; }}
            \\});
        );
        const progress = try f.eval("progress");
        defer c.JS_FreeValue(f.context.?, progress);
        const raw = c.JS_Eval(f.context.?, operation.ptr, operation.len,
            "actual-copy-properties-fatal.js", c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT);
        defer c.JS_FreeValue(f.context.?, raw);
        try std.testing.expect(c.JS_IsException(raw));
        try std.testing.expect(c.JS_HasException(f.context.?));
        const actual = c.JS_GetException(f.context.?);
        defer c.JS_FreeValue(f.context.?, actual);
        try std.testing.expect(c.JS_IsSameValue(f.context.?, reason, actual));
        try f.ownBoolean(progress, "first", true);
        try f.ownBoolean(progress, "second", true);
        try f.ownBoolean(progress, "later", false);
        try f.ownBoolean(progress, "caught", false);
        try f.ownBoolean(progress, "closed", false);
        try f.ownBoolean(progress, "after", false);
        try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
    }
}
