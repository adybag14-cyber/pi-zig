//! Actual bytecode property-result and receiver-retirement boundaries.
//! Original inspector/Helpers controls remain in their independent roots.
const std = @import("std");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
});
const Fixture = struct {
    runtime: ?*c.JSRuntime = null,
    context: ?*c.JSContext = null,
    progress: c.JSValue = undefined,
    fn init(self: *Fixture) !void {
        self.* = .{ .progress = c.pi_js_undefined() };
        self.runtime = c.JS_NewRuntime() orelse return error.OutOfMemory;
        errdefer self.deinit();
        c.JS_SetMaxStackSize(self.runtime.?, 1024 * 1024);
        self.context = c.JS_NewContext(self.runtime.?) orelse return error.OutOfMemory;
        self.progress = try self.eval(
            \\globalThis.progress = {after:false, caught:false, finalized:false};
            \\progress
        );
        const take_function = try self.checked(c.JS_NewCFunction(self.context.?, take, "take", 0));
        defer c.JS_FreeValue(self.context.?, take_function);
        try self.publish("take", take_function);
        const key = try self.checked(c.JS_NewString(self.context.?, "x"));
        defer c.JS_FreeValue(self.context.?, key);
        try self.publish("key", key);
    }
    fn deinit(self: *Fixture) void {
        if (self.runtime) |runtime| c.JS_SetMemoryLimit(runtime, 0);
        if (self.context) |context| {
            if (c.JS_HasException(context)) c.JS_FreeValue(context, c.JS_GetException(context));
            _ = c.JS_PiCheckExecutionTermination(context);
            c.JS_PiCancelExecutionTermination(self.runtime.?);
            if (c.JS_HasException(context)) c.JS_FreeValue(context, c.JS_GetException(context));
            const progress = self.progress; self.progress = c.pi_js_undefined();
            c.JS_FreeValue(context, progress);
            self.context = null;
            c.JS_FreeContext(context);
        }
        if (self.runtime) |runtime| { self.runtime = null; c.JS_FreeRuntime(runtime); }
    }
    fn checked(self: *Fixture, value: c.JSValue) !c.JSValue {
        if (c.JS_IsException(value) or c.JS_HasException(self.context.?)) {
            c.JS_FreeValue(self.context.?, value);
            return error.ActualPropertyRetirementSetupFailed;
        }
        return value;
    }
    fn eval(self: *Fixture, source: [:0]const u8) !c.JSValue {
        return self.checked(c.JS_Eval(self.context.?, source.ptr, source.len,
            "actual-property-retirement.js", c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT));
    }
    fn compile(self: *Fixture, comptime expression: []const u8) !c.JSValue {
        return self.eval("(function(){try{const value=" ++ expression ++
            ";progress.after=true;return value;}catch(reason){progress.caught=true;return reason;}" ++
            "finally{progress.finalized=true;}})");
    }
    fn publish(self: *Fixture, name: [*:0]const u8, value: c.JSValue) !void {
        const global_object = try self.checked(c.JS_GetGlobalObject(self.context.?));
        defer c.JS_FreeValue(self.context.?, global_object);
        try self.defineOwned(global_object, name, c.JS_DupValue(self.context.?, value));
    }
    fn defineOwned(self: *Fixture, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
        // The actual C definition consumes value even on failure.
        try std.testing.expectEqual(@as(c_int, 1),
            c.JS_DefinePropertyValueStr(self.context.?, object, name, value, c.JS_PROP_C_W_E));
        try std.testing.expect(!c.JS_HasException(self.context.?));
    }
    fn ownBool(self: *Fixture, name: [*:0]const u8, expected: bool) !void {
        // This exact plain record and its primitive own fields predate the call.
        const value = c.JS_GetPropertyStr(self.context.?, self.progress, name);
        defer c.JS_FreeValue(self.context.?, value);
        try std.testing.expect(c.JS_IsBool(value));
        try std.testing.expectEqual(@as(c_int, @intFromBool(expected)), c.JS_ToBool(self.context.?, value));
    }
    fn expectProgress(self: *Fixture, after: bool, caught: bool, finalized: bool) !void {
        try self.ownBool("after", after);
        try self.ownBool("caught", caught);
        try self.ownBool("finalized", finalized);
    }
    fn number(self: *Fixture, value: c.JSValue, expected: i32) !void {
        try std.testing.expect(c.JS_IsNumber(value));
        var actual: i32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(self.context.?, &actual, value));
        try std.testing.expectEqual(expected, actual);
    }
};
const Action = enum { none, first, second, terminate };
const Shape = enum { data, getter, inherited_getter, array, typed, arguments };
const GetterMode = enum { value, throw_first };
const Token = struct { probe: *Probe, index: usize };
const Probe = struct {
    context: ?*c.JSContext = null,
    enabled: bool = false,
    class_id: c.JSClassID = 0,
    tokens: [2]Token = undefined,
    counts: [2]usize = .{0, 0},
    actions: [2]Action = .{.none, .none},
    reasons: [2]c.JSValue = undefined,
    next: c.JSValue = undefined,
    getter_result: c.JSValue = undefined,
    getter_mode: GetterMode = .value,
    taken: usize = 0,
    getter_calls: usize = 0,
    getter_receiver: bool = false,
    result_retired_at_receiver: usize = 999,
    events: [8]usize = undefined,
    event_count: usize = 0,
    overflow: bool = false,
    fn init(self: *Probe, f: *Fixture) !void {
        self.* = .{ .context = f.context.?, .next = c.pi_js_undefined(), .getter_result = c.pi_js_undefined(),
            .reasons = .{c.pi_js_undefined(), c.pi_js_undefined()} };
        for (&self.tokens, 0..) |*token, index| token.* = .{ .probe = self, .index = index };
        errdefer self.disable();
        _ = c.JS_NewClassID(f.runtime.?, &self.class_id);
        const definition: c.JSClassDef = .{ .class_name = "Actual property operand", .finalizer = retire };
        try std.testing.expectEqual(@as(c_int, 0), c.JS_NewClass(f.runtime.?, self.class_id, &definition));
        for (&self.reasons) |*slot| slot.* = try f.checked(c.JS_NewError(f.context.?));
        c.JS_SetContextOpaque(f.context.?, self);
        self.enabled = true;
    }
    fn disable(self: *Probe) void {
        self.enabled = false;
        const context = self.context orelse return;
        self.context = null;
        c.JS_SetContextOpaque(context, null);
        const next = self.next; self.next = c.pi_js_undefined();
        const result = self.getter_result; self.getter_result = c.pi_js_undefined();
        c.JS_FreeValue(context, next);
        c.JS_FreeValue(context, result);
        for (&self.reasons) |*slot| {
            const reason = slot.*; slot.* = c.pi_js_undefined(); c.JS_FreeValue(context, reason);
        }
    }
    fn from(context: *c.JSContext) ?*Probe {
        const raw_owner = c.JS_GetContextOpaque(context) orelse return null;
        return @ptrCast(@alignCast(raw_owner));
    }
    fn makeHolder(self: *Probe, f: *Fixture, index: usize) !c.JSValue {
        const value = try f.checked(c.JS_NewObjectProtoClass(f.context.?, c.pi_js_null(), self.class_id));
        _ = c.JS_SetOpaque(value, &self.tokens[index]);
        return value;
    }
    fn fatal(self: *Probe, index: usize) void {
        c.JS_SetUncatchableError(self.context.?, self.reasons[index]);
    }
    fn getter(self: *Probe, f: *Fixture, object: c.JSValue) !void {
        _ = self;
        const atom = c.JS_NewAtom(f.context.?, "x");
        if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
        defer c.JS_FreeAtom(f.context.?, atom);
        const function = try f.checked(c.JS_NewCFunction(f.context.?, getValue, "actualPropertyGetter", 0));
        try std.testing.expectEqual(@as(c_int, 1),
            c.JS_DefinePropertyGetSet(f.context.?, object, atom, function, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE));
        try std.testing.expect(!c.JS_HasException(f.context.?));
    }
    fn prepare(self: *Probe, f: *Fixture, shape: Shape, value: c.JSValue) !void {
        // This staging owner is transferred by take() before the actual read.
        self.getter_result = value;
        switch (shape) {
            .data, .getter, .inherited_getter => self.next = try self.makeHolder(f, 0),
            .array => self.next = try f.eval("[7]"),
            .typed => self.next = try f.eval("new Uint8Array([7])"),
            .arguments => self.next = try f.eval("(function(value){return arguments;})(7)"),
        }
        switch (shape) {
            .data => {
                const result = self.getter_result; self.getter_result = c.pi_js_undefined();
                try f.defineOwned(self.next, "x", result);
            },
            .getter => try self.getter(f, self.next),
            .inherited_getter => {
                const prototype = try f.checked(c.JS_NewObject(f.context.?));
                defer c.JS_FreeValue(f.context.?, prototype);
                try self.getter(f, prototype);
                try std.testing.expectEqual(@as(c_int, 1), c.JS_SetPrototype(f.context.?, self.next, prototype));
            },
            .array, .typed, .arguments => {
                const marker = try self.makeHolder(f, 0);
                try f.defineOwned(self.next, "owner", marker);
                const unused = self.getter_result; self.getter_result = c.pi_js_undefined();
                c.JS_FreeValue(f.context.?, unused);
            },
        }
    }
};
fn start(f: *Fixture, p: *Probe) !void {
    try f.init();
    errdefer f.deinit();
    try p.init(f);
}
fn retire(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const raw_owner = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return;
    const token: *Token = @ptrCast(@alignCast(raw_owner));
    _ = c.JS_SetOpaque(value, null);
    const p = token.probe;
    if (token.index == 0) p.result_retired_at_receiver = p.counts[1];
    p.counts[token.index] += 1;
    if (p.event_count < p.events.len) { p.events[p.event_count] = token.index; p.event_count += 1; }
    else p.overflow = true;
    const action = p.actions[token.index]; p.actions[token.index] = .none;
    if (!p.enabled) return;
    const context = p.context orelse return;
    switch (action) {
        .none => {},
        .first => _ = c.JS_Throw(context, c.JS_DupValue(context, p.reasons[0])),
        .second => _ = c.JS_Throw(context, c.JS_DupValue(context, p.reasons[1])),
        .terminate => {
            c.JS_PiRequestExecutionTermination(c.JS_GetRuntime(context));
            _ = c.JS_PiCheckExecutionTermination(context);
        },
    }
}
fn take(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const p = Probe.from(context.?) orelse return c.JS_ThrowInternalError(context, "missing property probe");
    p.taken += 1;
    const value = p.next; p.next = c.pi_js_undefined();
    return value;
}
fn getValue(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const p = Probe.from(context.?) orelse return c.JS_ThrowInternalError(context, "missing property probe");
    p.getter_calls += 1;
    p.getter_receiver = c.JS_GetClassID(receiver) == p.class_id;
    if (p.getter_mode == .throw_first) return c.JS_Throw(context, c.JS_DupValue(context, p.reasons[0]));
    const value = p.getter_result; p.getter_result = c.pi_js_undefined();
    return value;
}
fn expectFatal(f: *Fixture, p: *Probe, function: c.JSValue, reason_index: usize) !void {
    const result = c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null);
    defer c.JS_FreeValue(f.context.?, result);
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expect(c.JS_HasException(f.context.?));
    const reason = c.JS_GetException(f.context.?);
    defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, p.reasons[reason_index]));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try f.expectProgress(false, false, false);
    try std.testing.expectEqual(@as(usize, 1), p.taken);
    try std.testing.expectEqual(@as(usize, 1), p.counts[0]);
    try std.testing.expect(!p.overflow);
}
fn expectOrdinary(f: *Fixture, p: *Probe, function: c.JSValue, reason_index: usize) !void {
    const result = c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null);
    defer c.JS_FreeValue(f.context.?, result);
    try std.testing.expect(!c.JS_IsException(result));
    try std.testing.expect(!c.JS_HasException(f.context.?));
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, result, p.reasons[reason_index]));
    try f.expectProgress(false, true, true);
    try std.testing.expectEqual(@as(usize, 1), p.taken);
    try std.testing.expectEqual(@as(usize, 1), p.counts[0]);
}

test "VM property retirement publishes the owned data result before its sole receiver retires" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    const value = try p.makeHolder(&f, 1);
    try p.prepare(&f, .data, value);
    const function = try f.compile("take().x"); defer c.JS_FreeValue(f.context.?, function);
    {
        const result = c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null);
        defer c.JS_FreeValue(f.context.?, result);
        try std.testing.expect(!c.JS_IsException(result));
        try std.testing.expect(!c.JS_HasException(f.context.?));
        try std.testing.expectEqual(p.class_id, c.JS_GetClassID(result));
        try std.testing.expectEqual(@as(usize, 1), p.counts[0]);
        try std.testing.expectEqual(@as(usize, 0), p.counts[1]);
        try std.testing.expectEqual(@as(usize, 0), p.result_retired_at_receiver);
        try f.expectProgress(true, false, true);
    }
    try std.testing.expectEqual(@as(usize, 1), p.counts[1]);
    try std.testing.expectEqualSlices(usize, &.{0, 1}, p.events[0..p.event_count]);
}
test "VM property retirement getter uses the original receiver and returns its selected value once" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    try p.prepare(&f, .getter, c.JS_NewInt32(f.context.?, 7));
    const function = try f.compile("take().x"); defer c.JS_FreeValue(f.context.?, function);
    const result = c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null);
    defer c.JS_FreeValue(f.context.?, result);
    try f.number(result, 7);
    try std.testing.expectEqual(@as(usize, 1), p.getter_calls);
    try std.testing.expect(p.getter_receiver);
    try std.testing.expectEqual(@as(usize, 1), p.counts[0]);
    try f.expectProgress(true, false, true);
}
test "VM property retirement inherited accessor keeps the actual receiver through its call" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    try p.prepare(&f, .inherited_getter, c.JS_NewInt32(f.context.?, 7));
    const function = try f.compile("take().x"); defer c.JS_FreeValue(f.context.?, function);
    const result = c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null);
    defer c.JS_FreeValue(f.context.?, result);
    try f.number(result, 7);
    try std.testing.expectEqual(@as(usize, 1), p.getter_calls);
    try std.testing.expect(p.getter_receiver);
    try std.testing.expectEqual(@as(usize, 1), p.counts[0]);
    try f.expectProgress(true, false, true);
}
test "VM property retirement computed string lookup consumes its key and retains the result" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    try p.prepare(&f, .getter, try p.makeHolder(&f, 1));
    const function = try f.compile("take()[key]"); defer c.JS_FreeValue(f.context.?, function);
    {
        const result = c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null);
        defer c.JS_FreeValue(f.context.?, result);
        try std.testing.expect(!c.JS_IsException(result));
        try std.testing.expectEqual(p.class_id, c.JS_GetClassID(result));
        try std.testing.expectEqual(@as(usize, 1), p.getter_calls);
        try std.testing.expectEqualSlices(usize, &.{1, 0}, &p.counts);
        try f.expectProgress(true, false, true);
    }
    try std.testing.expectEqual(@as(usize, 1), p.counts[1]);
}
test "VM property retirement own data receiver fatal stops later work catch and finally" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.fatal(0); p.actions[0] = .first;
    try p.prepare(&f, .data, c.JS_NewInt32(f.context.?, 7));
    const function = try f.compile("take().x"); defer c.JS_FreeValue(f.context.?, function);
    try expectFatal(&f, &p, function, 0);
}
test "VM property retirement successful getter fatal releases its selected result exactly once" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.fatal(0); p.actions[0] = .first;
    try p.prepare(&f, .getter, try p.makeHolder(&f, 1));
    const function = try f.compile("take().x"); defer c.JS_FreeValue(f.context.?, function);
    try expectFatal(&f, &p, function, 0);
    try std.testing.expectEqualSlices(usize, &.{1, 1}, &p.counts);
    try std.testing.expectEqual(@as(usize, 0), p.result_retired_at_receiver);
    try std.testing.expectEqualSlices(usize, &.{0, 1}, p.events[0..p.event_count]);
}
test "VM property retirement failed field lookup selects a later actual receiver fatal" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.getter_mode = .throw_first; p.fatal(1); p.actions[0] = .second;
    try p.prepare(&f, .getter, c.pi_js_undefined());
    const function = try f.compile("take().x"); defer c.JS_FreeValue(f.context.?, function);
    try expectFatal(&f, &p, function, 1);
    try std.testing.expectEqual(@as(usize, 1), p.getter_calls);
}
test "VM property retirement first actual field fatal survives a second receiver fatal" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.getter_mode = .throw_first; p.fatal(0); p.fatal(1); p.actions[0] = .second;
    try p.prepare(&f, .getter, c.pi_js_undefined());
    const function = try f.compile("take().x"); defer c.JS_FreeValue(f.context.?, function);
    try expectFatal(&f, &p, function, 0);
    try std.testing.expectEqual(@as(usize, 1), p.getter_calls);
}
test "VM property retirement ordinary field lookup reason survives ordinary receiver cleanup" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.getter_mode = .throw_first; p.actions[0] = .second;
    try p.prepare(&f, .getter, c.pi_js_undefined());
    const function = try f.compile("take().x"); defer c.JS_FreeValue(f.context.?, function);
    try expectOrdinary(&f, &p, function, 0);
}
test "VM property retirement computed lookup receiver fatal blocks the next guest statement" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.fatal(0); p.actions[0] = .first;
    try p.prepare(&f, .data, c.JS_NewInt32(f.context.?, 7));
    const function = try f.compile("take()[key]"); defer c.JS_FreeValue(f.context.?, function);
    try expectFatal(&f, &p, function, 0);
}
test "VM property retirement computed lookup preserves its first actual fatal through receiver cleanup" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.getter_mode = .throw_first; p.fatal(0); p.fatal(1); p.actions[0] = .second;
    try p.prepare(&f, .getter, c.pi_js_undefined());
    const function = try f.compile("take()[key]"); defer c.JS_FreeValue(f.context.?, function);
    try expectFatal(&f, &p, function, 0);
}
test "VM property retirement fast array receiver fatal is checked before dispatch" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.fatal(0); p.actions[0] = .first;
    try p.prepare(&f, .array, c.JS_NewInt32(f.context.?, 7));
    const function = try f.compile("take()[0]"); defer c.JS_FreeValue(f.context.?, function);
    try expectFatal(&f, &p, function, 0);
}
test "VM property retirement fast typed array receiver fatal is checked before dispatch" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.fatal(0); p.actions[0] = .first;
    try p.prepare(&f, .typed, c.JS_NewInt32(f.context.?, 7));
    const function = try f.compile("take()[0]"); defer c.JS_FreeValue(f.context.?, function);
    try expectFatal(&f, &p, function, 0);
}
test "VM property retirement actual arguments element receiver fatal is checked before dispatch" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.fatal(0); p.actions[0] = .first;
    try p.prepare(&f, .arguments, c.JS_NewInt32(f.context.?, 7));
    const function = try f.compile("take()[0]"); defer c.JS_FreeValue(f.context.?, function);
    try expectFatal(&f, &p, function, 0);
}
test "VM property retirement result cleanup fatal preempts the receiver ordinary completion" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.actions[0] = .first; p.actions[1] = .second; p.fatal(1);
    try p.prepare(&f, .data, try p.makeHolder(&f, 1));
    const function = try f.compile("take().x"); defer c.JS_FreeValue(f.context.?, function);
    try expectFatal(&f, &p, function, 1);
    try std.testing.expectEqualSlices(usize, &.{0, 1}, p.events[0..p.event_count]);
    try std.testing.expectEqualSlices(usize, &.{1, 1}, &p.counts);
}
test "VM property retirement receiver fatal survives the selected result cleanup fatal" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.actions[0] = .first; p.actions[1] = .second; p.fatal(0); p.fatal(1);
    try p.prepare(&f, .getter, try p.makeHolder(&f, 1));
    const function = try f.compile("take()[key]"); defer c.JS_FreeValue(f.context.?, function);
    try expectFatal(&f, &p, function, 0);
    try std.testing.expectEqualSlices(usize, &.{0, 1}, p.events[0..p.event_count]);
    try std.testing.expectEqualSlices(usize, &.{1, 1}, &p.counts);
}
test "VM property retirement returned flagged Error remains successful DATA" {
    inline for (.{ "take().x", "take()[key]" }) |expression| {
        var f: Fixture = .{}; var p: Probe = .{};
        try start(&f, &p); defer { p.disable(); f.deinit(); }
        p.fatal(0);
        try p.prepare(&f, .getter, c.JS_DupValue(f.context.?, p.reasons[0]));
        const function = try f.compile(expression); defer c.JS_FreeValue(f.context.?, function);
        const result = c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null);
        defer c.JS_FreeValue(f.context.?, result);
        try std.testing.expect(!c.JS_IsException(result));
        try std.testing.expect(!c.JS_HasException(f.context.?));
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?, result, p.reasons[0]));
        try std.testing.expect(c.JS_IsUncatchableError(result));
        try std.testing.expectEqual(@as(usize, 1), p.counts[0]);
        try f.expectProgress(true, false, true);
    }
}
test "VM property retirement actual private termination skips catch and finally without DATA projection" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.actions[0] = .terminate;
    try p.prepare(&f, .data, c.JS_NewInt32(f.context.?, 7));
    const function = try f.compile("take().x"); defer c.JS_FreeValue(f.context.?, function);
    const result = c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null);
    defer c.JS_FreeValue(f.context.?, result);
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expect(c.JS_HasException(f.context.?));
    try std.testing.expect(c.JS_PiIsExecutionTerminating(f.runtime.?));
    const reason = c.JS_GetException(f.context.?); defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_PiIsExecutionTermination(reason));
    try std.testing.expectEqual(@as(u64, 1), c.JS_PiExecutionTerminationGeneration(f.runtime.?));
    try f.expectProgress(false, false, false);
    try std.testing.expectEqual(@as(usize, 1), p.counts[0]);
    _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
    c.JS_PiCancelExecutionTermination(f.runtime.?);
    try std.testing.expect(!c.JS_HasException(f.context.?));
}
test "VM property retirement ordinary receiver throw enters the original guest catch once" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    p.actions[0] = .first;
    try p.prepare(&f, .data, c.JS_NewInt32(f.context.?, 7));
    const function = try f.compile("take().x"); defer c.JS_FreeValue(f.context.?, function);
    try expectOrdinary(&f, &p, function, 0);
}
test "VM property retirement successful scalar read and receiver release need no allocation" {
    var f: Fixture = .{}; var p: Probe = .{};
    try start(&f, &p); defer { p.disable(); f.deinit(); }
    try p.prepare(&f, .data, c.JS_NewInt32(f.context.?, 7));
    const function = try f.compile("take().x"); defer c.JS_FreeValue(f.context.?, function);
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    const result = c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null);
    defer c.JS_FreeValue(f.context.?, result);
    c.JS_SetMemoryLimit(f.runtime.?, 0);
    try f.number(result, 7);
    try std.testing.expect(!c.JS_HasException(f.context.?));
    try std.testing.expectEqual(@as(usize, 1), p.counts[0]);
    try f.expectProgress(true, false, true);
}
