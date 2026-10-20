//! Genuine simple Error stack state and raw native Script projection.
//! Detailed stacks, ThrowAt metadata, Message construction/reporting and normal
//! Engine installation are deliberately outside this explicit owner fixture.
const std = @import("std");
const em = @import("extensions/engine.zig");
const stack = @import("extensions/native_error_stack.zig");
const c = em.c;

const Retirement = enum { count, ordinary, fatal, terminate };
const Token = struct { probe: *Probe, index: usize, action: Retirement };
const Probe = struct {
    engine: *em.Engine,
    installed_owner: c.JSValue,
    holder_class: c.JSClassID = 0,
    enabled: bool = true,
    tokens: [4]Token = undefined,
    retired: [4]usize = @splat(0),
    observed: c.JSValue,
    stored_absent: bool = false,
    stored_start: c_int = 0,
    stored_end: c_int = 0,
    observe_calls: usize = 0,
    fallback: ?c.JSValue = null,
    fallback_calls: usize = 0,
    reasons: [2]c.JSValue,
    termination_status: c_int = 0,
    termination_active: bool = false,

    fn holder(self: *Probe, index: usize, action: Retirement) !c.JSValue {
        self.tokens[index] = .{ .probe = self, .index = index, .action = action };
        const value = c.JS_NewObjectClass(self.engine.context, @intCast(self.holder_class));
        if (c.JS_IsException(value) or c.JS_HasException(self.engine.context)) {
            self.engine.freeValue(value);
            return error.ActualHolderAllocationFailure;
        }
        _ = c.JS_SetOpaque(value, &self.tokens[index]);
        return value;
    }
    fn observe(self: *Probe, receiver: c.JSValue) void {
        self.stored_start = 731;
        self.stored_end = 947;
        const source = stack.readSimpleStackLocation(self.installed_owner, receiver,
            &self.stored_start, &self.stored_end);
        self.stored_absent = source == null;
        c.JS_PiFreeScript(source);
        self.observe_calls += 1;
    }
};
fn retire(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const token: *Token = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    _ = c.JS_SetOpaque(value, null);
    const p = token.probe;
    p.retired[token.index] += 1;
    if (!p.enabled) return;
    if (c.JS_IsObject(p.observed)) p.observe(p.observed);
    switch (token.action) {
        .count => {},
        .ordinary, .fatal => {
            if (token.action == .fatal) c.JS_SetUncatchableError(p.engine.context, p.reasons[1]);
            _ = c.JS_Throw(p.engine.context, c.JS_DupValue(p.engine.context, p.reasons[1]));
        },
        .terminate => {
            c.JS_PiRequestExecutionTermination(p.engine.runtime);
            p.termination_status = c.JS_PiCheckExecutionTermination(p.engine.context);
            p.termination_active = c.JS_PiIsExecutionTerminating(p.engine.runtime);
        },
    }
}
fn probeOf(values: [*c]c.JSValue) *Probe {
    return @ptrCast(@alignCast(c.JS_GetOpaque(values[0], c.JS_GetClassID(values[0])).?));
}
fn countRetired(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue,
    _: c_int, values: [*c]c.JSValue) callconv(.c) c.JSValue
{
    return c.JS_NewInt32(context, @intCast(probeOf(values).retired[0]));
}
fn observeStored(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue,
    _: c_int, values: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const p = probeOf(values);
    p.observe(if (argc > 0) argv[0] else c.pi_js_undefined());
    return c.JS_NewBool(context, p.stored_absent);
}
fn throwFirst(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue,
    _: c_int, values: [*c]c.JSValue) callconv(.c) c.JSValue
{
    return c.JS_Throw(context, c.JS_DupValue(context, probeOf(values).reasons[0]));
}
fn cancelAndReturnNative(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue,
    _: c_int, values: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const p = probeOf(values);
    c.JS_PiRequestExecutionTermination(p.engine.runtime);
    p.termination_status = c.JS_PiCheckExecutionTermination(context);
    p.termination_active = c.JS_PiIsExecutionTerminating(p.engine.runtime);
    c.JS_PiCancelExecutionTermination(p.engine.runtime);
    return c.JS_PiNativeTerminationResult();
}
fn captureAll(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_CaptureCurrentStackFrames(context, 16, c.pi_js_undefined(), null, 0, 0, 0);
}
fn recursiveCapture(context: ?*c.JSContext, _: c.JSValue, phase: c_int,
    _: c.JSValue, _: [*c]const u8, _: c_int, _: c_int, _: c_int,
    raw_owner: ?*anyopaque) callconv(.c) c_int
{
    const p: *Probe = @ptrCast(@alignCast(raw_owner orelse return -1));
    if (context != p.engine.context) return -1;
    if (phase == c.JS_ERROR_STACK_PREPARE or p.fallback != null) return 0;
    p.fallback_calls += 1;
    // This real recursive creation enters the linked C hook-active fallback.
    const nested = c.JS_NewError(context);
    if (c.JS_IsException(nested) or c.JS_HasException(context)) {
        c.JS_FreeValue(context, nested);
        return -1;
    }
    p.fallback = nested;
    return 0;
}
const Location = struct {
    script: ?*c.JSNativeScript = null,
    start: c_int = 731,
    end: c_int = 947,
    fn deinit(self: *Location) void {
        const owner = self.script;
        self.script = null;
        c.JS_PiFreeScript(owner);
    }
};
const Fixture = struct {
    engine: *em.Engine,
    installed_owner: c.JSValue,
    carrier: c.JSValue,
    probe: Probe,

    fn init(self: *Fixture) !void {
        const engine = try em.Engine.init(std.testing.allocator, .{ .memory_limit = 64 * 1024 * 1024 });
        self.* = .{
            .engine = engine, .installed_owner = c.pi_js_undefined(), .carrier = c.pi_js_undefined(),
            .probe = .{ .engine = engine, .installed_owner = c.pi_js_undefined(),
                .observed = c.pi_js_undefined(),
                .reasons = .{ c.pi_js_undefined(), c.pi_js_undefined() } },
        };
        errdefer self.deinit();
        self.installed_owner = try stack.install(engine);
        self.probe.installed_owner = self.installed_owner;
        var carrier_class: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &carrier_class);
        const carrier_definition: c.JSClassDef = .{ .class_name = "Simple stack control probe" };
        if (c.JS_NewClass(engine.runtime, carrier_class, &carrier_definition) < 0) return error.OutOfMemory;
        _ = c.JS_NewClassID(engine.runtime, &self.probe.holder_class);
        const holder_definition: c.JSClassDef = .{ .class_name = "Simple stack sole holder", .finalizer = retire };
        if (c.JS_NewClass(engine.runtime, self.probe.holder_class, &holder_definition) < 0) return error.OutOfMemory;
        self.carrier = try self.checked(c.JS_NewObjectClass(engine.context, @intCast(carrier_class)));
        _ = c.JS_SetOpaque(self.carrier, &self.probe);
        for (&self.probe.reasons) |*reason| reason.* = try self.checked(c.JS_NewError(engine.context));
        var roots = [_]c.JSValue{self.carrier};
        inline for (.{
            .{ "retiredCount", countRetired }, .{ "observeStored", observeStored },
            .{ "throwFirst", throwFirst }, .{ "cancelAndReturnNative", cancelAndReturnNative },
        }) |entry| {
            const function_value = try self.checked(c.JS_NewCFunctionData2(engine.context, entry[1], entry[0], 1, 0, 1, &roots));
            defer engine.freeValue(function_value);
            try self.publish(entry[0], function_value);
        }
        const capture_function = try self.checked(c.JS_NewCFunction(engine.context, captureAll, "captureAll", 0));
        defer engine.freeValue(capture_function);
        try self.publish("captureAll", capture_function);
    }
    fn deinit(self: *Fixture) void {
        self.probe.enabled = false;
        self.probe.observed = c.pi_js_undefined();
        c.JS_SetMemoryLimit(self.engine.runtime, 0);
        _ = c.JS_PiExchangeJavascriptExecutionAllowed(self.engine.runtime, true);
        c.JS_PiCancelExecutionTermination(self.engine.runtime);
        _ = c.JS_PiCheckExecutionTermination(self.engine.context);
        c.JS_PiCancelExecutionTermination(self.engine.runtime);
        while (c.JS_HasException(self.engine.context)) self.engine.freeValue(c.JS_GetException(self.engine.context));
        stack.uninstall(self.engine);
        if (self.probe.fallback) |value| {
            self.probe.fallback = null;
            self.engine.freeValue(value);
        }
        self.engine.freeValue(self.carrier);
        for (self.probe.reasons) |reason| self.engine.freeValue(reason);
        self.engine.freeValue(self.installed_owner);
        self.engine.deinit();
    }
    fn checked(self: *Fixture, result: c.JSValue) !c.JSValue {
        if (c.JS_IsException(result) or c.JS_HasException(self.engine.context)) {
            self.engine.freeValue(result);
            return error.ActualSimpleStackControlException;
        }
        return result;
    }
    fn eval(self: *Fixture, program: [:0]const u8) !c.JSValue {
        return self.checked(self.rawEval(program));
    }
    fn rawEval(self: *Fixture, program: [:0]const u8) c.JSValue {
        return c.JS_Eval(self.engine.context, program.ptr, program.len,
            "actual-simple-stack.js", c.JS_EVAL_TYPE_GLOBAL);
    }
    fn run(self: *Fixture, program: [:0]const u8) !void {
        const value = try self.eval(program);
        defer self.engine.freeValue(value);
    }
    fn publish(self: *Fixture, name: [*:0]const u8, borrowed: c.JSValue) !void {
        const global_object = try self.checked(c.JS_GetGlobalObject(self.engine.context));
        defer self.engine.freeValue(global_object);
        try std.testing.expectEqual(@as(c_int, 1), c.JS_DefinePropertyValueStr(self.engine.context,
            global_object, name, c.JS_DupValue(self.engine.context, borrowed), c.JS_PROP_C_W_E));
        try std.testing.expect(!c.JS_HasException(self.engine.context));
    }
    fn get(self: *Fixture, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
        return self.checked(c.JS_GetPropertyStr(self.engine.context, object, name));
    }
    fn global(self: *Fixture, name: [*:0]const u8) !c.JSValue {
        const global_object = try self.checked(c.JS_GetGlobalObject(self.engine.context));
        defer self.engine.freeValue(global_object);
        return self.get(global_object, name);
    }
    fn setStack(self: *Fixture, receiver: c.JSValue, borrowed: c.JSValue) c_int {
        return c.JS_SetPropertyStr(self.engine.context, receiver, "stack",
            c.JS_DupValue(self.engine.context, borrowed));
    }
    fn read(self: *Fixture, receiver: c.JSValue) Location {
        var found: Location = .{};
        found.script = stack.readSimpleStackLocation(self.installed_owner, receiver, &found.start, &found.end);
        return found;
    }
    fn expectMissing(self: *Fixture, receiver: c.JSValue) !void {
        var found = self.read(receiver); defer found.deinit();
        try std.testing.expect(found.script == null);
        try std.testing.expectEqual(@as(c_int, 731), found.start);
        try std.testing.expectEqual(@as(c_int, 947), found.end);
    }
    fn string(self: *Fixture, value: c.JSValue, expected: []const u8) !void {
        try std.testing.expect(c.JS_IsString(value));
        var length: usize = 0;
        const bytes = c.JS_ToCStringLen(self.engine.context, &length, value) orelse return error.OutOfMemory;
        defer c.JS_FreeCString(self.engine.context, bytes);
        try std.testing.expectEqualStrings(expected, bytes[0..length]);
    }
    fn source(self: *Fixture, owner: ?*c.JSNativeScript, expected: []const u8) !void {
        try std.testing.expect(owner != null);
        const text = c.JS_PiScriptGetSource(owner); defer self.engine.freeValue(text);
        try self.string(text, expected);
    }
    fn expectPending(self: *Fixture, expected: c.JSValue, fatal: bool) !void {
        try std.testing.expect(c.JS_HasException(self.engine.context));
        const reason = c.JS_GetException(self.engine.context); defer self.engine.freeValue(reason);
        try std.testing.expect(c.JS_IsSameValue(self.engine.context, expected, reason));
        try std.testing.expectEqual(fatal, c.JS_IsUncatchableError(reason));
    }
    fn expectNative(self: *Fixture, result: c.JSValue, active: bool) !void {
        try std.testing.expect(c.JS_IsException(result));
        try std.testing.expect(c.JS_HasException(self.engine.context));
        try std.testing.expectEqual(active, c.JS_PiIsExecutionTerminating(self.engine.runtime));
        const reason = c.JS_GetException(self.engine.context); defer self.engine.freeValue(reason);
        try std.testing.expect(c.JS_PiIsExecutionTermination(reason));
        try std.testing.expectEqual(@as(c_int, if (active) 1 else -1),
            c.JS_PiNativePendingPriority(self.engine.runtime, reason));
        if (active) {
            _ = c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, reason));
            c.JS_PiCancelExecutionTermination(self.engine.runtime);
        }
    }
    fn ownBool(self: *Fixture, object: c.JSValue, name: [*:0]const u8, expected: bool) !void {
        // All callers retain a known plain own Boolean record before failure.
        const value = try self.get(object, name); defer self.engine.freeValue(value);
        try std.testing.expect(c.JS_IsBool(value));
        try std.testing.expectEqual(expected, c.JS_ToBool(self.engine.context, value) != 0);
    }
    fn weakSet(self: *Fixture, map: c.JSValue, key: c.JSValue, value: c.JSValue) !void {
        const function_value = try self.get(map, "set"); defer self.engine.freeValue(function_value);
        var args = [_]c.JSValue{ key, value };
        const result = try self.checked(c.JS_Call(self.engine.context, function_value, map, 2, &args));
        defer self.engine.freeValue(result);
    }
    fn heldError(self: *Fixture, action: Retirement) !c.JSValue {
        try self.run("Error.stackTraceLimit=1;");
        const receiver = try self.probe.holder(0, action); defer self.engine.freeValue(receiver);
        const function_value = try self.eval("(function heldSource(){return new Error('held');})");
        defer self.engine.freeValue(function_value);
        const result = try self.checked(c.JS_Call(self.engine.context, function_value, receiver, 0, null));
        errdefer self.engine.freeValue(result);
        try std.testing.expectEqual(@as(usize, 0), self.probe.retired[0]);
        return result;
    }
    fn fallbackError(self: *Fixture, enabled: bool) !c.JSValue {
        try self.run(if (enabled) "Error.stackTraceLimit=4;" else "Error.stackTraceLimit='disabled';");
        c.JS_SetNativeErrorStackHook(self.engine.runtime, recursiveCapture, &self.probe);
        const outer = try self.eval("new Error('outer recursive capture')");
        defer self.engine.freeValue(outer);
        const nested = self.probe.fallback orelse return error.MissingActualRecursiveCapture;
        try std.testing.expectEqual(@as(usize, 1), self.probe.fallback_calls);
        try std.testing.expect(c.JS_PiHasPendingNativeErrorStack(nested));
        return c.JS_DupValue(self.engine.context, nested);
    }
};

test "VM simple stack source WeakMap intrinsic distinguishes absent and stored undefined" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const map = try f.eval("new WeakMap()"); defer f.engine.freeValue(map);
    const key = try f.checked(c.JS_NewObject(f.engine.context)); defer f.engine.freeValue(key);
    var result = c.JS_NewInt32(f.engine.context, 713);
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiReadWeakMapEntry(f.engine.context, map, key, &result));
    defer f.engine.freeValue(result);
    try std.testing.expect(c.JS_IsUndefined(result));
    try f.weakSet(map, key, c.pi_js_undefined());
    try std.testing.expectEqual(@as(c_int, 1), c.JS_PiReadWeakMapEntry(f.engine.context, map, key, &result));
    try std.testing.expect(c.JS_IsUndefined(result));
    try std.testing.expect(!c.JS_HasException(f.engine.context));
}
test "VM simple stack source WeakMap invalid brands and Proxy leave output untouched" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const map = try f.eval("new WeakMap()"); defer f.engine.freeValue(map);
    const plain = try f.checked(c.JS_NewObject(f.engine.context)); defer f.engine.freeValue(plain);
    try f.publish("actualMap", map);
    const proxy = try f.eval("new Proxy(actualMap,{get(){throw 9;},getPrototypeOf(){throw 10;}})");
    defer f.engine.freeValue(proxy);
    for ([_]c.JSValue{ plain, proxy, c.pi_js_undefined() }) |invalid| {
        var result = c.JS_NewInt32(f.engine.context, 713);
        try std.testing.expectEqual(@as(c_int, -1), c.JS_PiReadWeakMapEntry(f.engine.context, invalid, plain, &result));
        try std.testing.expect(c.JS_IsSameValue(f.engine.context, result, c.JS_NewInt32(f.engine.context, 713)));
    }
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiReadWeakMapEntry(f.engine.context, map, plain, null));
    try std.testing.expect(!c.JS_HasException(f.engine.context));
}
test "VM simple stack source WeakMap read bypasses poisoned methods and heap and execution gates" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const map = try f.eval("new WeakMap()"); defer f.engine.freeValue(map);
    const key = try f.checked(c.JS_NewObject(f.engine.context)); defer f.engine.freeValue(key);
    try f.weakSet(map, key, f.probe.reasons[0]);
    try f.run("WeakMap.prototype.get=function(){throw 11;};WeakMap.prototype.has=function(){throw 12;};");
    const occurrence = c.JS_PiOutOfMemoryOccurrence(f.engine.runtime);
    c.JS_SetMemoryLimit(f.engine.runtime, 1);
    const previous = c.JS_PiExchangeJavascriptExecutionAllowed(f.engine.runtime, false);
    var result = c.pi_js_undefined();
    const status = c.JS_PiReadWeakMapEntry(f.engine.context, map, key, &result);
    _ = c.JS_PiExchangeJavascriptExecutionAllowed(f.engine.runtime, previous);
    c.JS_SetMemoryLimit(f.engine.runtime, 0);
    defer f.engine.freeValue(result);
    try std.testing.expectEqual(@as(c_int, 1), status);
    try std.testing.expect(c.JS_IsSameValue(f.engine.context, f.probe.reasons[0], result));
    try std.testing.expectEqual(occurrence, c.JS_PiOutOfMemoryOccurrence(f.engine.runtime));
    try std.testing.expect(!c.JS_HasException(f.engine.context));
}
test "VM simple stack source WeakMap raw read preserves actual ordinary fatal and private pending" {
    for (0..3) |mode| {
        var f: Fixture = undefined; try f.init(); defer f.deinit();
        const map = try f.eval("new WeakMap()"); defer f.engine.freeValue(map);
        const key = try f.checked(c.JS_NewObject(f.engine.context)); defer f.engine.freeValue(key);
        try f.weakSet(map, key, c.JS_NewInt32(f.engine.context, 37));
        if (mode == 2) {
            c.JS_PiRequestExecutionTermination(f.engine.runtime);
            try std.testing.expectEqual(@as(c_int, -1), c.JS_PiCheckExecutionTermination(f.engine.context));
        } else {
            if (mode == 1) c.JS_SetUncatchableError(f.engine.context, f.probe.reasons[0]);
            _ = c.JS_Throw(f.engine.context, c.JS_DupValue(f.engine.context, f.probe.reasons[0]));
        }
        var result = c.pi_js_undefined();
        const status = c.JS_PiReadWeakMapEntry(f.engine.context, map, key, &result);
        defer f.engine.freeValue(result);
        try std.testing.expectEqual(@as(c_int, 1), status);
        try std.testing.expect(c.JS_IsSameValue(f.engine.context, result, c.JS_NewInt32(f.engine.context, 37)));
        if (mode == 2) try f.expectNative(c.JS_PiNativeTerminationResult(), true)
        else try f.expectPending(f.probe.reasons[0], mode == 1);
    }
}
test "VM simple stack source WeakMap returned value owns one root without keeping the key alive" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var map = try f.eval("new WeakMap()"); defer f.engine.freeValue(map);
    var key = try f.checked(c.JS_NewObject(f.engine.context)); defer f.engine.freeValue(key);
    var holder = try f.probe.holder(0, .count); defer f.engine.freeValue(holder);
    try f.weakSet(map, key, holder);
    f.engine.freeValue(holder); holder = c.pi_js_undefined();
    var result = c.pi_js_undefined(); defer f.engine.freeValue(result);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_PiReadWeakMapEntry(f.engine.context, map, key, &result));
    f.engine.freeValue(key); key = c.pi_js_undefined();
    f.engine.freeValue(map); map = c.pi_js_undefined();
    c.JS_RunGC(f.engine.runtime);
    try std.testing.expectEqual(@as(usize, 0), f.probe.retired[0]);
    f.engine.freeValue(result); result = c.pi_js_undefined();
    try std.testing.expectEqual(@as(usize, 1), f.probe.retired[0]);
}
test "VM simple stack source real Error selects its original complete Script and source position" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const program = "(function actualSource(){return new Error('location');})";
    const function_value = try f.eval(program); defer f.engine.freeValue(function_value);
    const compiled = c.JS_PiGetCompiledScript(function_value) orelse return error.MissingCompiledSource;
    defer c.JS_PiFreeScript(compiled);
    const error_value = try f.checked(c.JS_Call(f.engine.context, function_value, c.pi_js_undefined(), 0, null));
    defer f.engine.freeValue(error_value);
    var found = f.read(error_value); defer found.deinit();
    try std.testing.expect(found.script == compiled);
    try std.testing.expect(found.start >= 0 and @as(usize, @intCast(found.start)) < program.len);
    try std.testing.expectEqual(found.start + 1, found.end);
    try f.source(found.script, program);
    try std.testing.expect(!c.JS_PiHasPendingNativeErrorStack(error_value));
}
test "VM simple stack source inherited holder remains visible through a never-captured native Error" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const parent = try f.eval("new Error('parent')"); defer f.engine.freeValue(parent);
    const bare = try f.checked(c.JS_NewObjectClass(f.engine.context, @intCast(c.JS_GetClassID(parent))));
    defer f.engine.freeValue(bare);
    try std.testing.expect(c.JS_IsError(bare));
    try std.testing.expect(!c.JS_PiHasPendingNativeErrorStack(bare));
    var legacy = c.pi_js_undefined(); defer f.engine.freeValue(legacy);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_ReadPendingNativeErrorStack(f.engine.context, bare, &legacy));
    try std.testing.expect(c.JS_IsUndefined(legacy));
    try std.testing.expectEqual(@as(c_int, 1), c.JS_SetPrototype(f.engine.context, bare, parent));
    var first = f.read(parent); defer first.deinit();
    var inherited = f.read(bare); defer inherited.deinit();
    try std.testing.expect(first.script != null and inherited.script == first.script);
    try std.testing.expectEqual(first.start, inherited.start);
    try std.testing.expectEqual(first.end, inherited.end);
}
test "VM simple stack source captured-disabled state blocks an inherited raw stack" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const parent = try f.eval("new Error('parent')"); defer f.engine.freeValue(parent);
    try f.run("Error.stackTraceLimit='disabled';");
    const child = try f.eval("new Error('child')"); defer f.engine.freeValue(child);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_SetPrototype(f.engine.context, child, parent));
    var inherited = f.read(parent); defer inherited.deinit();
    try std.testing.expect(inherited.script != null);
    try f.expectMissing(child);
}
test "VM simple stack source formatted undefined and other DATA block inheritance" {
    for ([_]bool{ false, true }) |undefined_value| {
        var f: Fixture = undefined; try f.init(); defer f.deinit();
        const parent = try f.eval("new Error('parent')"); defer f.engine.freeValue(parent);
        const child = try f.eval("new Error('child')"); defer f.engine.freeValue(child);
        try std.testing.expectEqual(@as(c_int, 1), c.JS_SetPrototype(f.engine.context, child, parent));
        try std.testing.expectEqual(@as(c_int, 1), f.setStack(child,
            if (undefined_value) c.pi_js_undefined() else f.probe.reasons[0]));
        try f.expectMissing(child);
        var inherited = f.read(parent); defer inherited.deinit();
        try std.testing.expect(inherited.script != null);
    }
}
test "VM simple stack source raw lookup stops at Proxy without invoking its traps" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const parent = try f.eval("new Error('parent')"); defer f.engine.freeValue(parent);
    try f.publish("parentError", parent);
    const proxy = try f.eval("new Proxy(parentError,{get(){throw 31;},getPrototypeOf(){throw 32;},getOwnPropertyDescriptor(){throw 33;}})");
    defer f.engine.freeValue(proxy);
    const child = try f.checked(c.JS_NewObjectProto(f.engine.context, proxy)); defer f.engine.freeValue(child);
    try f.expectMissing(proxy);
    try f.expectMissing(child);
    try std.testing.expect(!c.JS_HasException(f.engine.context));
}
test "VM simple stack source raw lookup ignores guest fields and preserves actual pending at heap limit one" {
    for (0..3) |mode| {
        var f: Fixture = undefined; try f.init(); defer f.deinit();
        const error_value = try f.eval("new Error('raw')"); defer f.engine.freeValue(error_value);
        try f.publish("rawError", error_value);
        try f.run("for(const name of ['stack','name','message'])Object.defineProperty(rawError,name,{get(){throw 41;},configurable:true});WeakMap.prototype.get=function(){throw 42;};");
        var before = f.read(error_value); defer before.deinit();
        try std.testing.expect(before.script != null);
        if (mode == 2) {
            c.JS_PiRequestExecutionTermination(f.engine.runtime);
            try std.testing.expectEqual(@as(c_int, -1), c.JS_PiCheckExecutionTermination(f.engine.context));
        } else {
            if (mode == 1) c.JS_SetUncatchableError(f.engine.context, f.probe.reasons[0]);
            _ = c.JS_Throw(f.engine.context, c.JS_DupValue(f.engine.context, f.probe.reasons[0]));
        }
        const occurrence = c.JS_PiOutOfMemoryOccurrence(f.engine.runtime);
        c.JS_SetMemoryLimit(f.engine.runtime, 1);
        const previous = c.JS_PiExchangeJavascriptExecutionAllowed(f.engine.runtime, false);
        var after = f.read(error_value);
        _ = c.JS_PiExchangeJavascriptExecutionAllowed(f.engine.runtime, previous);
        c.JS_SetMemoryLimit(f.engine.runtime, 0);
        defer after.deinit();
        try std.testing.expect(after.script == before.script);
        try std.testing.expectEqual(before.start, after.start); try std.testing.expectEqual(before.end, after.end);
        try std.testing.expectEqual(occurrence, c.JS_PiOutOfMemoryOccurrence(f.engine.runtime));
        if (mode == 2) try f.expectNative(c.JS_PiNativeTerminationResult(), true)
        else try f.expectPending(f.probe.reasons[0], mode == 1);
    }
}
test "VM simple stack source native Script result retains no captured receiver graph" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var error_value = try f.heldError(.count); defer f.engine.freeValue(error_value);
    var found = f.read(error_value); defer found.deinit();
    try std.testing.expect(found.script != null);
    f.engine.freeValue(error_value); error_value = c.pi_js_undefined();
    c.JS_RunGC(f.engine.runtime);
    try std.testing.expectEqual(@as(usize, 1), f.probe.retired[0]);
    try f.source(found.script, "(function heldSource(){return new Error('held');})");
}
test "VM simple stack source raw projection skips native and synthetic records before a real Script" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const frames = try f.eval("captureAll()"); defer f.engine.freeValue(frames);
    const native_frame = try f.checked(c.JS_GetPropertyUint32(f.engine.context, frames, 0)); defer f.engine.freeValue(native_frame);
    var absent_position: c_int = 919;
    const absent = c.JS_PiGetCapturedStackFrameScript(native_frame, &absent_position); defer c.JS_PiFreeScript(absent);
    try std.testing.expect(absent == null and absent_position == 919);
    const actual_frame = try f.checked(c.JS_GetPropertyUint32(f.engine.context, frames, 1)); defer f.engine.freeValue(actual_frame);
    var position: c_int = -2;
    const actual = c.JS_PiGetCapturedStackFrameScript(actual_frame, &position) orelse return error.MissingActualFrame;
    defer c.JS_PiFreeScript(actual);
    const synthetic = try f.checked(c.JS_CaptureCurrentStackFrames(f.engine.context, 8,
        c.pi_js_undefined(), "not-a-Script.js", 7, 8, c.JS_ERROR_STACK_SINGLE_LEVEL));
    defer f.engine.freeValue(synthetic);
    const fake_frame = try f.checked(c.JS_GetPropertyUint32(f.engine.context, synthetic, 0)); defer f.engine.freeValue(fake_frame);
    const mixed = try f.checked(c.JS_NewArray(f.engine.context)); defer f.engine.freeValue(mixed);
    for ([_]c.JSValue{ fake_frame, native_frame, actual_frame }, 0..) |frame, index|
        try std.testing.expectEqual(@as(c_int, 1), c.JS_DefinePropertyValueUint32(f.engine.context,
            mixed, @intCast(index), c.JS_DupValue(f.engine.context, frame), c.JS_PROP_C_W_E));
    var start: c_int = 731; var end: c_int = 947;
    const selected = c.JS_PiFindCapturedStackScriptLocation(mixed, &start, &end); defer c.JS_PiFreeScript(selected);
    try std.testing.expect(selected == actual);
    try std.testing.expectEqual(position, start); try std.testing.expectEqual(position + 1, end);
    start = 731; end = 947;
    const no_source = c.JS_PiFindCapturedStackScriptLocation(synthetic, &start, &end); defer c.JS_PiFreeScript(no_source);
    try std.testing.expect(no_source == null and start == 731 and end == 947);
}
test "VM simple stack source raw projection rejects Proxy and accessor arrays without guest entry" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const frames = try f.eval("captureAll()"); defer f.engine.freeValue(frames);
    try f.publish("capturedFrames", frames);
    const proxy = try f.eval("new Proxy(capturedFrames,{get(){throw 51;}})"); defer f.engine.freeValue(proxy);
    const accessor = try f.eval("Object.defineProperty([],0,{get(){throw 52;},configurable:true})"); defer f.engine.freeValue(accessor);
    for ([_]c.JSValue{ proxy, accessor, c.pi_js_undefined() }) |unsupported| {
        var start: c_int = 731; var end: c_int = 947;
        const unexpected = c.JS_PiFindCapturedStackScriptLocation(unsupported, &start, &end);
        defer c.JS_PiFreeScript(unexpected);
        try std.testing.expect(unexpected == null and start == 731 and end == 947);
    }
    var end: c_int = 947;
    const unexpected = c.JS_PiFindCapturedStackScriptLocation(frames, null, &end); defer c.JS_PiFreeScript(unexpected);
    try std.testing.expect(unexpected == null and end == 947);
    try std.testing.expect(!c.JS_HasException(f.engine.context));
}

test "VM simple stack source fallback presence distinguishes untouched Error and consuming transfer" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fallback = try f.fallbackError(true); defer f.engine.freeValue(fallback);
    const bare = try f.checked(c.JS_NewObjectClass(f.engine.context, @intCast(c.JS_GetClassID(fallback))));
    defer f.engine.freeValue(bare);
    try std.testing.expect(!c.JS_PiHasPendingNativeErrorStack(bare));
    var untouched = c.JS_NewInt32(f.engine.context, 713);
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiTakePendingNativeErrorStack(bare, &untouched));
    try std.testing.expect(c.JS_IsSameValue(f.engine.context, untouched, c.JS_NewInt32(f.engine.context, 713)));
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiTakePendingNativeErrorStack(fallback, null));
    try std.testing.expect(c.JS_PiHasPendingNativeErrorStack(fallback));
    var transferred = c.pi_js_undefined(); defer f.engine.freeValue(transferred);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_PiTakePendingNativeErrorStack(fallback, &transferred));
    try std.testing.expect(c.JS_IsArray(transferred));
    try std.testing.expect(!c.JS_PiHasPendingNativeErrorStack(fallback));
    untouched = c.JS_NewInt32(f.engine.context, 713);
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiTakePendingNativeErrorStack(fallback, &untouched));
    try std.testing.expect(c.JS_IsSameValue(f.engine.context, untouched, c.JS_NewInt32(f.engine.context, 713)));
    var start: c_int = 731; var end: c_int = 947;
    const actual = c.JS_PiFindCapturedStackScriptLocation(transferred, &start, &end);
    defer c.JS_PiFreeScript(actual);
    try std.testing.expect(actual != null and start >= 0 and end == start + 1);
    try f.expectMissing(fallback);
}
test "VM simple stack source raw fallback read neither allocates nor adopts its C owner" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fallback = try f.fallbackError(true); defer f.engine.freeValue(fallback);
    var frames = c.pi_js_undefined(); defer f.engine.freeValue(frames);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_ReadPendingNativeErrorStack(f.engine.context, fallback, &frames));
    var start: c_int = 731; var end: c_int = 947;
    const actual = c.JS_PiFindCapturedStackScriptLocation(frames, &start, &end); defer c.JS_PiFreeScript(actual);
    try std.testing.expect(actual != null);
    const occurrence = c.JS_PiOutOfMemoryOccurrence(f.engine.runtime);
    c.JS_SetMemoryLimit(f.engine.runtime, 1);
    const previous = c.JS_PiExchangeJavascriptExecutionAllowed(f.engine.runtime, false);
    var found = f.read(fallback);
    _ = c.JS_PiExchangeJavascriptExecutionAllowed(f.engine.runtime, previous);
    c.JS_SetMemoryLimit(f.engine.runtime, 0);
    defer found.deinit();
    try std.testing.expect(found.script == actual);
    try std.testing.expectEqual(start, found.start); try std.testing.expectEqual(end, found.end);
    try std.testing.expect(c.JS_PiHasPendingNativeErrorStack(fallback));
    try std.testing.expectEqual(occurrence, c.JS_PiOutOfMemoryOccurrence(f.engine.runtime));
    try std.testing.expect(!c.JS_HasException(f.engine.context));
}
test "VM simple stack source successful map adoption consumes fallback before formatter failure" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fallback = try f.fallbackError(true); defer f.engine.freeValue(fallback);
    var before = f.read(fallback); defer before.deinit();
    try std.testing.expect(before.script != null);
    try f.publish("expectedReason", f.probe.reasons[0]);
    try f.run("Error.prepareStackTrace=function(){throw expectedReason;};");
    const raw = c.JS_GetPropertyStr(f.engine.context, fallback, "stack"); defer f.engine.freeValue(raw);
    try std.testing.expect(c.JS_IsException(raw));
    try f.expectPending(f.probe.reasons[0], false);
    try std.testing.expect(!c.JS_PiHasPendingNativeErrorStack(fallback));
    var after = f.read(fallback); defer after.deinit();
    try std.testing.expect(after.script == before.script);
    try std.testing.expectEqual(before.start, after.start);
    try std.testing.expectEqual(before.end, after.end);
    var untouched = c.JS_NewInt32(f.engine.context, 713);
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiTakePendingNativeErrorStack(fallback, &untouched));
    try std.testing.expect(c.JS_IsSameValue(f.engine.context, untouched, c.JS_NewInt32(f.engine.context, 713)));
}
test "VM simple stack source failed map adoption leaves the original C fallback intact" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fallback = try f.fallbackError(true); defer f.engine.freeValue(fallback);
    var before = f.read(fallback); defer before.deinit();
    try std.testing.expect(before.script != null);
    const occurrence = c.JS_PiOutOfMemoryOccurrence(f.engine.runtime);
    c.JS_SetMemoryLimit(f.engine.runtime, 1);
    const raw = c.JS_GetPropertyStr(f.engine.context, fallback, "stack");
    c.JS_SetMemoryLimit(f.engine.runtime, 0);
    defer f.engine.freeValue(raw);
    try std.testing.expect(c.JS_IsException(raw));
    try std.testing.expect(c.JS_HasException(f.engine.context));
    const reason = c.JS_GetException(f.engine.context); defer f.engine.freeValue(reason);
    try std.testing.expect(c.JS_IsNull(reason));
    try std.testing.expect(c.JS_PiOutOfMemoryOccurrence(f.engine.runtime) > occurrence);
    try std.testing.expect(c.JS_PiHasPendingNativeErrorStack(fallback));
    var after = f.read(fallback); defer after.deinit();
    try std.testing.expect(after.script == before.script);
    try std.testing.expectEqual(before.start, after.start); try std.testing.expectEqual(before.end, after.end);
}
test "VM simple stack source present undefined fallback blocks inherited provenance and transfers once" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const parent = try f.eval("new Error('parent')"); defer f.engine.freeValue(parent);
    var parent_location = f.read(parent); defer parent_location.deinit();
    try std.testing.expect(parent_location.script != null);
    const fallback = try f.fallbackError(false); defer f.engine.freeValue(fallback);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_SetPrototype(f.engine.context, fallback, parent));
    try f.expectMissing(fallback);
    var transferred = c.JS_NewInt32(f.engine.context, 713); defer f.engine.freeValue(transferred);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_PiTakePendingNativeErrorStack(fallback, &transferred));
    try std.testing.expect(c.JS_IsUndefined(transferred));
    try std.testing.expect(!c.JS_PiHasPendingNativeErrorStack(fallback));
    var inherited = f.read(fallback); defer inherited.deinit();
    try std.testing.expect(inherited.script == parent_location.script);
    try std.testing.expectEqual(parent_location.start, inherited.start);
}
test "VM simple stack source consuming fallback transfer preserves actual pending without allocation" {
    for (0..3) |mode| {
        var f: Fixture = undefined; try f.init(); defer f.deinit();
        const fallback = try f.fallbackError(mode != 1); defer f.engine.freeValue(fallback);
        if (mode == 2) {
            c.JS_PiRequestExecutionTermination(f.engine.runtime);
            try std.testing.expectEqual(@as(c_int, -1), c.JS_PiCheckExecutionTermination(f.engine.context));
        } else {
            if (mode == 1) c.JS_SetUncatchableError(f.engine.context, f.probe.reasons[0]);
            _ = c.JS_Throw(f.engine.context, c.JS_DupValue(f.engine.context, f.probe.reasons[0]));
        }
        const occurrence = c.JS_PiOutOfMemoryOccurrence(f.engine.runtime);
        c.JS_SetMemoryLimit(f.engine.runtime, 1);
        var transferred = c.pi_js_undefined();
        const status = c.JS_PiTakePendingNativeErrorStack(fallback, &transferred);
        const present_after = c.JS_PiHasPendingNativeErrorStack(fallback);
        c.JS_SetMemoryLimit(f.engine.runtime, 0);
        defer f.engine.freeValue(transferred);
        try std.testing.expectEqual(@as(c_int, 1), status);
        try std.testing.expect(!present_after);
        try std.testing.expect(if (mode == 1) c.JS_IsUndefined(transferred) else c.JS_IsArray(transferred));
        try std.testing.expectEqual(occurrence, c.JS_PiOutOfMemoryOccurrence(f.engine.runtime));
        if (mode == 2) try f.expectNative(c.JS_PiNativeTerminationResult(), true)
        else try f.expectPending(f.probe.reasons[0], mode == 1);
    }
}
test "VM simple stack source setter publishes formatted state before retiring captured receiver" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const error_value = try f.heldError(.count); defer f.engine.freeValue(error_value);
    f.probe.observed = error_value; defer f.probe.observed = c.pi_js_undefined();
    try std.testing.expectEqual(@as(c_int, 1), f.setStack(error_value, c.JS_NewInt32(f.engine.context, 37)));
    try std.testing.expectEqual(@as(usize, 1), f.probe.retired[0]);
    try std.testing.expectEqual(@as(usize, 1), f.probe.observe_calls);
    try std.testing.expect(f.probe.stored_absent);
    try std.testing.expectEqual(@as(c_int, 731), f.probe.stored_start);
    try std.testing.expectEqual(@as(c_int, 947), f.probe.stored_end);
    const formatted = try f.get(error_value, "stack"); defer f.engine.freeValue(formatted);
    try std.testing.expect(c.JS_IsSameValue(f.engine.context, formatted, c.JS_NewInt32(f.engine.context, 37)));
    try f.expectMissing(error_value);
}
test "VM simple stack source successful formatting retires simple frames after actual formatter returns" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const error_value = try f.heldError(.count); defer f.engine.freeValue(error_value);
    f.probe.observed = error_value; defer f.probe.observed = c.pi_js_undefined();
    try f.run("globalThis.during=-1;Error.prepareStackTrace=function(error,frames){frames.length=0;during=retiredCount();return 71;};");
    const formatted = try f.get(error_value, "stack"); defer f.engine.freeValue(formatted);
    try std.testing.expect(c.JS_IsSameValue(f.engine.context, formatted, c.JS_NewInt32(f.engine.context, 71)));
    try std.testing.expectEqual(@as(usize, 1), f.probe.retired[0]);
    try std.testing.expect(f.probe.stored_absent);
    const during = try f.global("during"); defer f.engine.freeValue(during);
    try std.testing.expect(c.JS_IsSameValue(f.engine.context, during, c.JS_NewInt32(f.engine.context, 0)));
    try f.expectMissing(error_value);
}
test "VM simple stack source formatter-local raw owner survives setter and success overwrites its DATA" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const error_value = try f.heldError(.count); defer f.engine.freeValue(error_value);
    try f.run("globalThis.during=-1;globalThis.sawAbsent=false;Error.prepareStackTrace=function(error,frames){frames.length=0;error.stack=61;sawAbsent=observeStored(error);during=retiredCount();return 73;};");
    const formatted = try f.get(error_value, "stack"); defer f.engine.freeValue(formatted);
    try std.testing.expect(c.JS_IsSameValue(f.engine.context, formatted, c.JS_NewInt32(f.engine.context, 73)));
    const during = try f.global("during"); defer f.engine.freeValue(during);
    const absent = try f.global("sawAbsent"); defer f.engine.freeValue(absent);
    try std.testing.expect(c.JS_IsSameValue(f.engine.context, during, c.JS_NewInt32(f.engine.context, 0)));
    try std.testing.expect(c.JS_IsBool(absent) and c.JS_ToBool(f.engine.context, absent) != 0);
    try std.testing.expectEqual(@as(usize, 1), f.probe.retired[0]);
    const cached = try f.get(error_value, "stack"); defer f.engine.freeValue(cached);
    try std.testing.expect(c.JS_IsSameValue(f.engine.context, cached, formatted));
    try f.expectMissing(error_value);
}
test "VM simple stack source formatter throw preserves a reentrant setter and retires local frames" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const error_value = try f.heldError(.count); defer f.engine.freeValue(error_value);
    try f.publish("expectedReason", f.probe.reasons[0]);
    try f.run("globalThis.during=-1;Error.prepareStackTrace=function(error,frames){frames.length=0;error.stack=83;during=retiredCount();throw expectedReason;};");
    const raw = c.JS_GetPropertyStr(f.engine.context, error_value, "stack"); defer f.engine.freeValue(raw);
    try std.testing.expect(c.JS_IsException(raw));
    try f.expectPending(f.probe.reasons[0], false);
    try std.testing.expectEqual(@as(usize, 1), f.probe.retired[0]);
    const during = try f.global("during"); defer f.engine.freeValue(during);
    try std.testing.expect(c.JS_IsSameValue(f.engine.context, during, c.JS_NewInt32(f.engine.context, 0)));
    const cached = try f.get(error_value, "stack"); defer f.engine.freeValue(cached);
    try std.testing.expect(c.JS_IsSameValue(f.engine.context, cached, c.JS_NewInt32(f.engine.context, 83)));
    try f.expectMissing(error_value);
}
test "VM simple stack source FixedArray success replaces a record recaptured during formatting" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const error_value = try f.heldError(.count); defer f.engine.freeValue(error_value);
    try f.run("Error.prepareStackTrace=function(error,frames){frames.length=0;Error.captureStackTrace(error);return 89;};");
    const formatted = try f.get(error_value, "stack"); defer f.engine.freeValue(formatted);
    try std.testing.expect(c.JS_IsSameValue(f.engine.context, formatted, c.JS_NewInt32(f.engine.context, 89)));
    try std.testing.expectEqual(@as(usize, 1), f.probe.retired[0]);
    try f.expectMissing(error_value);
    const cached = try f.get(error_value, "stack"); defer f.engine.freeValue(cached);
    try std.testing.expect(c.JS_IsSameValue(f.engine.context, cached, formatted));
}
test "VM simple stack source formatter failure preserves the new record and its actual recapture Script" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const error_value = try f.heldError(.count); defer f.engine.freeValue(error_value);
    try f.publish("expectedReason", f.probe.reasons[0]);
    const program = "Error.prepareStackTrace=function recaptured(error,frames){frames.length=0;Error.captureStackTrace(error);throw expectedReason;};";
    try f.run(program);
    const raw = c.JS_GetPropertyStr(f.engine.context, error_value, "stack"); defer f.engine.freeValue(raw);
    try std.testing.expect(c.JS_IsException(raw));
    try f.expectPending(f.probe.reasons[0], false);
    try std.testing.expectEqual(@as(usize, 1), f.probe.retired[0]);
    var recaptured = f.read(error_value); defer recaptured.deinit();
    try std.testing.expect(recaptured.script != null and recaptured.start >= 0);
    try f.source(recaptured.script, program);
}
test "VM simple stack source inherited formatting writes the selected holder without creating child state" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const parent = try f.eval("new Error('parent')"); defer f.engine.freeValue(parent);
    const child = try f.checked(c.JS_NewObjectProto(f.engine.context, parent)); defer f.engine.freeValue(child);
    try f.publish("parentError", parent); try f.publish("childError", child);
    try f.run("globalThis.sawParent=false;Error.prepareStackTrace=function(error){sawParent=error===parentError;return 97;};");
    const formatted = try f.get(child, "stack"); defer f.engine.freeValue(formatted);
    try std.testing.expect(c.JS_IsSameValue(f.engine.context, formatted, c.JS_NewInt32(f.engine.context, 97)));
    try f.expectMissing(parent); try f.expectMissing(child);
    try f.run("if(!sawParent||Object.hasOwn(childError,'stack')||parentError.stack!==97)throw 98;");
}
test "VM simple stack source flagged formatter DATA remains a successful formatted value" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const error_value = try f.heldError(.count); defer f.engine.freeValue(error_value);
    c.JS_SetUncatchableError(f.engine.context, f.probe.reasons[0]);
    try f.publish("formattedData", f.probe.reasons[0]);
    try f.run("Error.prepareStackTrace=function(){return formattedData;};");
    const formatted = try f.get(error_value, "stack"); defer f.engine.freeValue(formatted);
    try std.testing.expect(c.JS_IsSameValue(f.engine.context, formatted, f.probe.reasons[0]));
    try std.testing.expect(c.JS_IsUncatchableError(formatted));
    try std.testing.expect(!c.JS_HasException(f.engine.context));
    try std.testing.expectEqual(@as(usize, 1), f.probe.retired[0]);
    try f.expectMissing(error_value);
}
test "VM simple stack source setter retirement preserves the actual ordinary cleanup reason" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const error_value = try f.heldError(.ordinary); defer f.engine.freeValue(error_value);
    f.probe.observed = error_value; defer f.probe.observed = c.pi_js_undefined();
    const status = f.setStack(error_value, c.JS_NewInt32(f.engine.context, 101));
    try std.testing.expectEqual(@as(c_int, -1), status);
    try f.expectPending(f.probe.reasons[1], false);
    try std.testing.expectEqual(@as(usize, 1), f.probe.retired[0]);
    try std.testing.expect(f.probe.stored_absent);
    const formatted = try f.get(error_value, "stack"); defer f.engine.freeValue(formatted);
    try std.testing.expect(c.JS_IsSameValue(f.engine.context, formatted, c.JS_NewInt32(f.engine.context, 101)));
}
test "VM simple stack source actual fatal receiver retirement stops later guest catch and finally" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const error_value = try f.heldError(.fatal); defer f.engine.freeValue(error_value);
    try f.publish("selectedError", error_value);
    try f.run("globalThis.progress={later:false,caught:false,finally:false};");
    const progress = try f.global("progress"); defer f.engine.freeValue(progress);
    f.probe.observed = error_value; defer f.probe.observed = c.pi_js_undefined();
    const raw = f.rawEval("try{selectedError.stack=103;progress.later=true;}catch(e){progress.caught=true;}finally{progress.finally=true;}");
    defer f.engine.freeValue(raw);
    try std.testing.expect(c.JS_IsException(raw));
    try f.expectPending(f.probe.reasons[1], true);
    try std.testing.expectEqual(@as(usize, 1), f.probe.retired[0]);
    try std.testing.expect(f.probe.stored_absent);
    try f.ownBool(progress, "later", false); try f.ownBool(progress, "caught", false); try f.ownBool(progress, "finally", false);
}
test "VM simple stack source actual private receiver retirement keeps its native completion" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const error_value = try f.heldError(.terminate); defer f.engine.freeValue(error_value);
    try f.publish("selectedError", error_value);
    try f.run("globalThis.progress={later:false,caught:false,finally:false};");
    const progress = try f.global("progress"); defer f.engine.freeValue(progress);
    f.probe.observed = error_value; defer f.probe.observed = c.pi_js_undefined();
    const raw = f.rawEval("try{selectedError.stack=107;progress.later=true;}catch(e){progress.caught=true;}finally{progress.finally=true;}");
    defer f.engine.freeValue(raw);
    try f.expectNative(raw, true);
    try std.testing.expectEqual(@as(c_int, -1), f.probe.termination_status);
    try std.testing.expect(f.probe.termination_active and f.probe.stored_absent);
    try std.testing.expectEqual(@as(usize, 1), f.probe.retired[0]);
    try f.ownBool(progress, "later", false); try f.ownBool(progress, "caught", false); try f.ownBool(progress, "finally", false);
}
test "VM simple stack source cancelled formatter unwind stays native and preserves unformatted state" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const error_value = try f.eval("new Error('cancelled')"); defer f.engine.freeValue(error_value);
    var before = f.read(error_value); defer before.deinit();
    try std.testing.expect(before.script != null);
    try f.publish("selectedError", error_value);
    try f.run("globalThis.progress={inner:false,later:false,caught:false,finally:false};Error.prepareStackTrace=function(){cancelAndReturnNative();progress.inner=true;};");
    const progress = try f.global("progress"); defer f.engine.freeValue(progress);
    const raw = f.rawEval("try{void selectedError.stack;progress.later=true;}catch(e){progress.caught=true;}finally{progress.finally=true;}");
    defer f.engine.freeValue(raw);
    try f.expectNative(raw, false);
    try std.testing.expectEqual(@as(c_int, -1), f.probe.termination_status);
    try std.testing.expect(f.probe.termination_active);
    try std.testing.expectEqual(@as(u64, 1), c.JS_PiExecutionTerminationGeneration(f.engine.runtime));
    try f.ownBool(progress, "inner", false); try f.ownBool(progress, "later", false);
    try f.ownBool(progress, "caught", false); try f.ownBool(progress, "finally", false);
    var after = f.read(error_value); defer after.deinit();
    try std.testing.expect(after.script == before.script);
    try std.testing.expectEqual(before.start, after.start); try std.testing.expectEqual(before.end, after.end);
}
test "VM simple stack source formatter failure and final raw retirement reduce actual fatal owners" {
    for ([_]bool{ false, true }) |first_fatal| {
        var f: Fixture = undefined; try f.init(); defer f.deinit();
        const error_value = try f.heldError(.fatal); defer f.engine.freeValue(error_value);
        f.probe.observed = error_value; defer f.probe.observed = c.pi_js_undefined();
        if (first_fatal) c.JS_SetUncatchableError(f.engine.context, f.probe.reasons[0]);
        try f.run("Error.prepareStackTrace=function(error,frames){frames.length=0;error.stack=109;throwFirst();};");
        const raw = c.JS_GetPropertyStr(f.engine.context, error_value, "stack"); defer f.engine.freeValue(raw);
        try std.testing.expect(c.JS_IsException(raw));
        try f.expectPending(f.probe.reasons[if (first_fatal) 0 else 1], true);
        try std.testing.expectEqual(@as(usize, 1), f.probe.retired[0]);
        try std.testing.expect(f.probe.stored_absent);
        try f.expectMissing(error_value);
    }
}
