//! Actual linked continuation-data roots and Promise/job propagation.
//! The batch adapter below spells out the native save/reset/restore ABI; it is
//! not a replacement Node Environment or a claim about exception reporting.
const std = @import("std");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
});
const Fixture = struct {
    runtime: ?*c.JSRuntime = null,
    context: ?*c.JSContext = null,
    memory: ?*anyopaque = null,
    fn init(self: *Fixture) !void {
        self.* = .{};
        self.runtime = c.pi_js_new_runtime(64 * 1024 * 1024, &self.memory) orelse return error.OutOfMemory;
        errdefer self.deinit();
        self.context = c.JS_NewContext(self.runtime.?) orelse return error.OutOfMemory;
    }
    fn deinit(self: *Fixture) void {
        if (self.runtime) |runtime| {
            _ = c.JS_PiExchangeJavascriptExecutionAllowed(runtime, true);
            c.JS_SetExecutionContextHook(runtime, null, null);
            c.JS_SetPromiseHook(runtime, null, null);
        }
        if (self.context) |context| { self.context = null; c.JS_FreeContext(context); }
        if (self.runtime) |runtime| { self.runtime = null; c.JS_FreeRuntime(runtime); }
        if (self.memory) |memory| { self.memory = null; c.pi_js_release_memory_owner(memory); }
    }
    fn checked(self: *Fixture, value: c.JSValue) !c.JSValue {
        if (c.JS_IsException(value) or c.JS_HasException(self.context.?)) {
            if (!c.JS_IsException(value)) c.JS_FreeValue(self.context.?, value);
            const reason = c.JS_GetException(self.context.?);
            c.JS_FreeValue(self.context.?, reason);
            return error.ActualContinuationControlException;
        }
        return value;
    }
    fn evalRaw(self: *Fixture, source: [:0]const u8) c.JSValue {
        return c.JS_Eval(self.context.?, source.ptr, source.len, "actual-continuation-data.js",
            c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT);
    }
    fn eval(self: *Fixture, source: [:0]const u8) !c.JSValue { return self.checked(self.evalRaw(source)); }
    fn run(self: *Fixture, source: [:0]const u8) !void {
        const value = try self.eval(source); defer c.JS_FreeValue(self.context.?, value);
    }
    fn set(self: *Fixture, key: [*:0]const u8, value: c.JSValue) !void {
        const global_object = try self.checked(c.JS_GetGlobalObject(self.context.?));
        defer c.JS_FreeValue(self.context.?, global_object);
        try std.testing.expect(c.JS_SetPropertyStr(self.context.?, global_object, key,
            c.JS_DupValue(self.context.?, value)) >= 0);
        try std.testing.expect(!c.JS_HasException(self.context.?));
    }
    fn frame(self: *Fixture, value: c.JSValue) !void {
        c.JS_PiSetContinuationPreservedEmbedderData(self.runtime.?, value);
        try std.testing.expect(!c.JS_HasException(self.context.?));
    }
    fn frameNumber(self: *Fixture, value: i32) !void {
        try self.frame(c.pi_js_int32(self.context.?, value));
    }
    fn frameIs(self: *Fixture, expected: c.JSValue) !void {
        const actual = c.JS_PiGetContinuationPreservedEmbedderData(self.runtime.?);
        defer c.JS_FreeValue(self.context.?, actual);
        try std.testing.expect(c.JS_IsStrictEqual(self.context.?, expected, actual));
    }
    fn frameIsNumber(self: *Fixture, expected: i32) !void {
        const actual = c.JS_PiGetContinuationPreservedEmbedderData(self.runtime.?);
        defer c.JS_FreeValue(self.context.?, actual);
        try self.numberValue(actual, expected);
    }
    fn numberValue(self: *Fixture, value: c.JSValue, expected: i32) !void {
        try std.testing.expect(c.JS_IsNumber(value));
        var actual: i32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(self.context.?, &actual, value));
        try std.testing.expectEqual(expected, actual);
    }
    fn ownBool(self: *Fixture, record: c.JSValue, key: [*:0]const u8, expected: bool) !void {
        // record was retained before any fatal event and has this own data field.
        const value = c.JS_GetPropertyStr(self.context.?, record, key);
        defer c.JS_FreeValue(self.context.?, value);
        try std.testing.expect(c.JS_IsBool(value));
        try std.testing.expectEqual(@as(c_int, @intFromBool(expected)), c.JS_ToBool(self.context.?, value));
    }
    fn pendingReason(self: *Fixture) !c.JSValue {
        try std.testing.expect(c.JS_HasException(self.context.?));
        return c.JS_GetException(self.context.?);
    }
    fn enqueue(self: *Fixture, callback: *const c.JSJobFunc, args: []const c.JSValue) !void {
        try std.testing.expectEqual(@as(c_int, 0), c.JS_EnqueueJob(self.context.?, callback,
            @intCast(args.len), if (args.len == 0) null else @constCast(args.ptr)));
        try std.testing.expect(!c.JS_HasException(self.context.?));
    }
    fn api(self: *Fixture, callback: *const c.JSCFunctionData, name: [*:0]const u8) !c.JSValue {
        const function = try self.checked(c.JS_NewCFunctionData2(self.context.?, callback, name, 1, 0, 0, null));
        errdefer c.JS_FreeValue(self.context.?, function);
        try std.testing.expectEqual(@as(c_int, 0), c.JS_PiMarkNativeApiFunction(self.context.?, function));
        return function;
    }
    fn install(self: *Fixture) !void {
        const get = try self.api(getFrame, "actualFrame"); defer c.JS_FreeValue(self.context.?, get);
        const put = try self.api(setFrame, "actualSetFrame"); defer c.JS_FreeValue(self.context.?, put);
        const note = try self.api(noteFrame, "actualNoteFrame"); defer c.JS_FreeValue(self.context.?, note);
        try self.set("frame", get); try self.set("setFrame", put); try self.set("noteFrame", note);
    }
    fn one(self: *Fixture) !void {
        var context: ?*c.JSContext = null;
        try std.testing.expectEqual(@as(c_int, 1), c.JS_ExecutePendingJob(self.runtime.?, &context));
        try std.testing.expect(context == self.context.?);
        try std.testing.expect(!c.JS_HasException(self.context.?));
    }
    fn failedOne(self: *Fixture) !c.JSValue {
        var context: ?*c.JSContext = null;
        try std.testing.expectEqual(@as(c_int, -1), c.JS_ExecutePendingJob(self.runtime.?, &context));
        try std.testing.expect(context == self.context.?);
        return self.pendingReason();
    }
    fn drain(self: *Fixture) !usize {
        var batch = Batch.enter(self); defer batch.restore();
        try std.testing.expect(!c.JS_HasException(self.context.?));
        var count: usize = 0;
        while (c.JS_IsJobPending(self.runtime.?)) {
            if (count == 64) return error.ActualContinuationJobBudget;
            var context: ?*c.JSContext = null;
            const status = c.JS_ExecutePendingJob(self.runtime.?, &context);
            if (status == 0) return count;
            if (status < 0 or c.JS_HasException(context orelse self.context.?)) {
                const reason = c.JS_GetException(context orelse self.context.?);
                c.JS_FreeValue(context orelse self.context.?, reason);
                return error.ActualContinuationJobFailure;
            }
            try std.testing.expectEqual(@as(c_int, 1), status);
            count += 1;
        }
        c.JS_ClearKeptObjects(self.runtime.?);
        return count;
    }
};
// V8's outer nonempty checkpoint owns the saved value through every job. This
// adapter intentionally does not report exceptions, invoke completed callbacks,
// clear termination queues, or overwrite the independent capability context.
const Batch = struct {
    runtime: *c.JSRuntime,
    previous: c.JSValue,
    active: bool,
    fn enter(f: *Fixture) Batch {
        const runtime = f.runtime.?;
        if (!c.JS_IsJobPending(runtime))
            return .{ .runtime = runtime, .previous = c.pi_js_undefined(), .active = false };
        const previous = c.JS_PiGetContinuationPreservedEmbedderData(runtime);
        c.JS_PiSetContinuationPreservedEmbedderData(runtime, c.pi_js_undefined());
        return .{ .runtime = runtime, .previous = previous, .active = true };
    }
    fn restore(self: *Batch) void {
        if (!self.active) return;
        self.active = false;
        const previous = self.previous;
        self.previous = c.pi_js_undefined();
        c.JS_PiSetContinuationPreservedEmbedderData(self.runtime, previous);
        c.JS_FreeValueRT(self.runtime, previous);
    }
};
const Token = struct { probe: *Probe, index: usize, observe: bool = false, throw_reason: ?usize = null };
const HookObservation = struct { before: bool, capability: i32, continuation: i32 };
const Probe = struct {
    context: ?*c.JSContext = null,
    enabled: bool = false,
    class_id: c.JSClassID = 0,
    counts: [16]usize = .{0} ** 16,
    retired_with: [16]i32 = .{-999} ** 16,
    tokens: [16]Token = undefined,
    reasons: [4]c.JSValue = undefined,
    events: [64]i32 = undefined,
    event_count: usize = 0,
    hook_events: [64]HookObservation = undefined,
    hook_count: usize = 0,
    async_starts: usize = 0,
    async_resumes: usize = 0,
    settlement_promise: c.JSValue = undefined,
    settlement_hooks: usize = 0,
    fn init(self: *Probe, f: *Fixture) !void {
        self.context = f.context.?;
        self.settlement_promise = c.pi_js_undefined();
        for (&self.reasons) |*slot| slot.* = c.pi_js_undefined();
        for (&self.tokens, 0..) |*token, index| token.* = .{ .probe = self, .index = index };
        c.JS_SetContextOpaque(f.context.?, self);
        _ = c.JS_NewClassID(f.runtime.?, &self.class_id);
        const class_definition: c.JSClassDef = .{ .class_name = "Actual continuation holder", .finalizer = retire };
        try std.testing.expectEqual(@as(c_int, 0), c.JS_NewClass(f.runtime.?, self.class_id, &class_definition));
        self.enabled = true;
    }
    fn disable(self: *Probe) void {
        self.enabled = false;
        const context = self.context orelse return;
        self.context = null;
        for (&self.reasons) |*slot| {
            const value = slot.*; slot.* = c.pi_js_undefined();
            c.JS_FreeValue(context, value);
        }
    }
    fn from(context: ?*c.JSContext) ?*Probe {
        const ctx = context orelse return null;
        const raw_owner = c.JS_GetContextOpaque(ctx) orelse return null;
        return @ptrCast(@alignCast(raw_owner));
    }
    fn id(self: *Probe, context: *c.JSContext, value: c.JSValue) i32 {
        if (c.JS_IsUndefined(value)) return -1;
        if (c.JS_IsNumber(value)) {
            var result: i32 = 0;
            if (c.JS_ToInt32(context, &result, value) == 0) return result;
            return -999;
        }
        if (c.JS_IsObject(value)) {
            if (c.JS_GetOpaque(value, self.class_id)) |raw_owner| {
                const token: *Token = @ptrCast(@alignCast(raw_owner));
                return 100 + @as(i32, @intCast(token.index));
            }
        }
        return -2;
    }
    fn current(self: *Probe, context: *c.JSContext) i32 {
        const value = c.JS_PiGetContinuationPreservedEmbedderData(c.JS_GetRuntime(context));
        defer c.JS_FreeValue(context, value);
        return self.id(context, value);
    }
    fn note(self: *Probe, context: *c.JSContext) void {
        if (self.event_count < self.events.len) self.events[self.event_count] = self.current(context);
        self.event_count += 1;
    }
    fn retire(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
        const raw_owner = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return;
        const token: *Token = @ptrCast(@alignCast(raw_owner));
        _ = c.JS_SetOpaque(value, null);
        const probe = token.probe;
        probe.counts[token.index] += 1;
        if (!probe.enabled) return;
        const context = probe.context orelse return;
        if (token.observe) probe.retired_with[token.index] = probe.current(context);
        if (token.throw_reason) |index| {
            token.throw_reason = null;
            _ = c.JS_Throw(context, c.JS_DupValue(context, probe.reasons[index]));
        }
    }
    fn holder(self: *Probe, f: *Fixture, index: usize) !c.JSValue {
        const value = try f.checked(c.JS_NewObjectProtoClass(f.context.?, c.pi_js_null(), self.class_id));
        _ = c.JS_SetOpaque(value, &self.tokens[index]);
        return value;
    }
    fn attach(self: *Probe, f: *Fixture, value: c.JSValue, index: usize) !void {
        const marker = try self.holder(f, index);
        try std.testing.expectEqual(@as(c_int, 1), c.JS_DefinePropertyValueStr(f.context.?, value,
            "actualContinuationHolder", marker, c.JS_PROP_C_W_E));
        try std.testing.expect(!c.JS_HasException(f.context.?));
    }
    fn makeReason(self: *Probe, f: *Fixture, index: usize, uncatchable: bool) !void {
        try std.testing.expect(c.JS_IsUndefined(self.reasons[index]));
        self.reasons[index] = try f.checked(c.JS_NewError(f.context.?));
        if (uncatchable) c.JS_SetUncatchableError(f.context.?, self.reasons[index]);
    }
    fn expectEvents(self: *Probe, expected: []const i32) !void {
        try std.testing.expectEqual(expected.len, self.event_count);
        try std.testing.expectEqualSlices(i32, expected, self.events[0..@min(self.event_count, self.events.len)]);
    }
};
fn getFrame(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue,
    _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const ctx = context orelse return c.pi_js_exception();
    return c.JS_PiGetContinuationPreservedEmbedderData(c.JS_GetRuntime(ctx));
}
fn setFrame(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue,
    _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const ctx = context orelse return c.pi_js_exception();
    c.JS_PiSetContinuationPreservedEmbedderData(c.JS_GetRuntime(ctx), if (argc == 0) c.pi_js_undefined() else argv[0]);
    return if (c.JS_HasException(ctx)) c.pi_js_exception() else c.pi_js_undefined();
}
fn noteFrame(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue,
    _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const ctx = context orelse return c.pi_js_exception();
    const probe = Probe.from(ctx) orelse return c.pi_js_exception();
    probe.note(ctx);
    return c.pi_js_undefined();
}
fn recordJob(context: ?*c.JSContext, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const ctx = context orelse return c.pi_js_exception();
    const probe = Probe.from(ctx) orelse return c.pi_js_exception();
    probe.note(ctx); return c.pi_js_undefined();
}
fn failJob(context: ?*c.JSContext, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const ctx = context orelse return c.pi_js_exception();
    const probe = Probe.from(ctx) orelse return c.pi_js_exception();
    probe.note(ctx);
    if (argc == 0) return c.JS_ThrowTypeError(ctx, "actual job requires its reason");
    return c.JS_Throw(ctx, c.JS_DupValue(ctx, argv[0]));
}
fn returnJob(context: ?*c.JSContext, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const ctx = context orelse return c.pi_js_exception();
    const probe = Probe.from(ctx) orelse return c.pi_js_exception();
    probe.note(ctx);
    return if (argc > 0) c.JS_DupValue(ctx, argv[0]) else c.pi_js_undefined();
}
fn nativeAsync(context: ?*c.JSContext, _: c.JSValue, _: c.JSValue, argc: c_int,
    argv: [*c]c.JSValue, completion: c_int, input: c.JSValue,
    _: [*c]c.JSValue, action: [*c]c_int) callconv(.c) c.JSValue
{
    const ctx = context orelse return c.pi_js_exception();
    const probe = Probe.from(ctx) orelse return c.pi_js_exception();
    probe.note(ctx);
    if (completion == c.JS_PI_AF_START) {
        probe.async_starts += 1;
        if (argc > 0) { action[0] = c.JS_PI_AF_AWAIT; return c.JS_DupValue(ctx, argv[0]); }
        action[0] = c.JS_PI_AF_RETURN; return c.pi_js_undefined();
    }
    probe.async_resumes += 1;
    action[0] = c.JS_PI_AF_RETURN;
    return c.JS_DupValue(ctx, input);
}
fn contextHook(context: ?*c.JSContext, before: bool, value: c.JSValue, raw_owner: ?*anyopaque) callconv(.c) void {
    const ctx = context orelse return;
    const raw = raw_owner orelse return;
    const probe: *Probe = @ptrCast(@alignCast(raw));
    if (probe.hook_count < probe.hook_events.len) probe.hook_events[probe.hook_count] = .{
        .before = before, .capability = probe.id(ctx, value), .continuation = probe.current(ctx),
    };
    probe.hook_count += 1;
}


test "VM continuation native get and set preserve arbitrary identity across real contexts without observation" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try f.frameIs(c.pi_js_undefined());
    const foreign = c.JS_NewContext(f.runtime.?) orelse return error.OutOfMemory;
    defer c.JS_FreeContext(foreign);
    const value = try f.eval(
        \\globalThis.progress={traps:false};
        \\new Proxy({}, {get(){progress.traps=true;throw 1;},getPrototypeOf(){progress.traps=true;throw 2;}})
    ); defer c.JS_FreeValue(f.context.?, value);
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    c.JS_PiSetContinuationPreservedEmbedderData(c.JS_GetRuntime(foreign), value);
    const owned = c.JS_PiGetContinuationPreservedEmbedderData(f.runtime.?);
    c.JS_PiSetContinuationPreservedEmbedderData(f.runtime.?, c.pi_js_undefined());
    c.JS_SetMemoryLimit(f.runtime.?, 0);
    defer c.JS_FreeValue(f.context.?, owned);
    try std.testing.expect(!c.JS_HasException(f.context.?));
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, value, owned));
    try f.frameIs(c.pi_js_undefined());
    try f.run("if(progress.traps)throw Error('continuation observed a guest property');");
}

test "VM continuation publication precedes old finalization and the owned getter is an independent root" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    probe.tokens[0].observe = true;
    {
        const old = try probe.holder(&f, 0); defer c.JS_FreeValue(f.context.?, old);
        try f.frame(old);
    }
    try f.frameNumber(44);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try std.testing.expectEqual(@as(i32, 44), probe.retired_with[0]);
    {
        const value = try probe.holder(&f, 1); defer c.JS_FreeValue(f.context.?, value);
        try f.frame(value);
        try f.frame(value);
    }
    try std.testing.expectEqual(@as(usize, 0), probe.counts[1]);
    const owned = c.JS_PiGetContinuationPreservedEmbedderData(f.runtime.?);
    try f.frame(c.pi_js_undefined());
    try std.testing.expectEqual(@as(usize, 0), probe.counts[1]);
    c.JS_FreeValue(f.context.?, owned);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[1]);
}

test "VM continuation runtime root keeps a real cyclic graph live until clearing and collection" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    {
        const value = try f.checked(c.JS_NewObject(f.context.?)); defer c.JS_FreeValue(f.context.?, value);
        try probe.attach(&f, value, 0);
        try std.testing.expectEqual(@as(c_int, 1), c.JS_DefinePropertyValueStr(f.context.?, value,
            "self", c.JS_DupValue(f.context.?, value), c.JS_PROP_C_W_E));
        try f.frame(value);
    }
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual(@as(usize, 0), probe.counts[0]);
    try f.frame(c.pi_js_undefined());
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
}

test "VM continuation native restoration preserves ordinary or fatal pending and flagged stored DATA" {
    inline for (.{ false, true }) |uncatchable| {
        var probe: Probe = .{};
        var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
        try probe.makeReason(&f, 0, uncatchable);
        try probe.makeReason(&f, 1, true);
        try f.frame(probe.reasons[1]);
        try std.testing.expect(!c.JS_HasException(f.context.?));
        _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, probe.reasons[0]));
        const allowed = c.JS_PiExchangeJavascriptExecutionAllowed(f.runtime.?, false);
        defer _ = c.JS_PiExchangeJavascriptExecutionAllowed(f.runtime.?, allowed);
        c.JS_SetMemoryLimit(f.runtime.?, 1);
        const owned = c.JS_PiGetContinuationPreservedEmbedderData(f.runtime.?);
        c.JS_PiSetContinuationPreservedEmbedderData(f.runtime.?, c.pi_js_int32(f.context.?, 71));
        c.JS_SetMemoryLimit(f.runtime.?, 0);
        defer c.JS_FreeValue(f.context.?, owned);
        const reason = try f.pendingReason(); defer c.JS_FreeValue(f.context.?, reason);
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?, probe.reasons[0], reason));
        try std.testing.expect(c.JS_IsUncatchableError(reason) == uncatchable);
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?, probe.reasons[1], owned));
        try f.frameIsNumber(71);
        try std.testing.expect(!c.JS_HasException(f.context.?));
    }
}

test "VM continuation old-root cleanup reduces actual pending while preserving the published replacement" {
    inline for (.{ false, true }) |prior_fatal| {
        var probe: Probe = .{};
        var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
        try probe.makeReason(&f, 0, prior_fatal);
        try probe.makeReason(&f, 1, true);
        probe.tokens[0].observe = true;
        probe.tokens[0].throw_reason = 1;
        {
            const old = try probe.holder(&f, 0); defer c.JS_FreeValue(f.context.?, old);
            try f.frame(old);
        }
        _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, probe.reasons[0]));
        c.JS_PiSetContinuationPreservedEmbedderData(f.runtime.?, c.pi_js_int32(f.context.?, 72));
        const reason = try f.pendingReason(); defer c.JS_FreeValue(f.context.?, reason);
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?,
            probe.reasons[if (prior_fatal) 0 else 1], reason));
        try std.testing.expect(c.JS_IsUncatchableError(reason));
        try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
        try std.testing.expectEqual(@as(i32, 72), probe.retired_with[0]);
        try f.frameIsNumber(72);
    }
}

test "VM continuation native jobs capture enqueue data and a nonempty batch restores its outer root" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    try f.frameNumber(11); try f.enqueue(recordJob, &.{});
    try f.frameNumber(99);
    try std.testing.expectEqual(@as(usize, 1), try f.drain());
    try probe.expectEvents(&.{11});
    try f.frameIsNumber(99);
    try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
}

test "VM continuation failed task data reaches an undefined-capture successor until a successful task clears it" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    try probe.makeReason(&f, 0, false);
    try f.frameNumber(11); try f.enqueue(failJob, &.{probe.reasons[0]});
    try f.frame(c.pi_js_undefined()); try f.enqueue(recordJob, &.{}); try f.enqueue(recordJob, &.{});
    try f.frameNumber(99);
    var batch = Batch.enter(&f); defer batch.restore();
    const reason = try f.failedOne(); defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, probe.reasons[0]));
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    // Consuming/reporting the ordinary reason does not itself reset this slot.
    try f.frameIsNumber(11);
    try f.one(); try f.frameIs(c.pi_js_undefined());
    try f.one(); try f.frameIs(c.pi_js_undefined());
    try probe.expectEvents(&.{11, 11, -1});
    batch.restore();
    try f.frameIsNumber(99);
}

test "VM continuation a later explicit capture replaces failed data and reporting may select a new value" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    try probe.makeReason(&f, 0, false);
    try f.frameNumber(11); try f.enqueue(failJob, &.{probe.reasons[0]});
    try f.frame(c.pi_js_undefined()); try f.enqueue(recordJob, &.{});
    try f.frameNumber(22); try f.enqueue(recordJob, &.{});
    try f.frameNumber(99);
    var batch = Batch.enter(&f); defer batch.restore();
    const reason = try f.failedOne(); defer c.JS_FreeValue(f.context.?, reason);
    try f.frameIsNumber(11);
    // A native message listener is allowed to change current continuation data.
    try f.frameNumber(33);
    try f.one(); try f.one();
    try probe.expectEvents(&.{11, 33, 22});
    try f.frameIs(c.pi_js_undefined());
    batch.restore(); try f.frameIsNumber(99);
}

test "VM continuation pending Promise reactions capture registration rather than resolution context" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable(); try f.install();
    try f.frameNumber(11);
    try f.run(
        \\globalThis.release=undefined;
        \\globalThis.pending=new Promise(resolve=>{release=resolve;});
        \\globalThis.result=pending.then(()=>{noteFrame();return 7;});
    );
    try f.frameNumber(22); try f.run("release(5);");
    try f.frameNumber(99);
    try std.testing.expectEqual(@as(usize, 1), try f.drain());
    try probe.expectEvents(&.{11}); try f.frameIsNumber(99);
    const result = try f.eval("result"); defer c.JS_FreeValue(f.context.?, result);
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(f.context.?, result));
    const value = c.JS_PromiseResult(f.context.?, result); defer c.JS_FreeValue(f.context.?, value);
    try f.numberValue(value, 7);
}

test "VM continuation already settled Promise reactions also retain registration context" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable(); try f.install();
    try f.run("globalThis.settled=Promise.resolve(5);");
    try f.frameNumber(21); try f.run("globalThis.result=settled.then(()=>noteFrame());");
    try f.frameNumber(31);
    try std.testing.expectEqual(@as(usize, 1), try f.drain());
    try probe.expectEvents(&.{21}); try f.frameIsNumber(31);
}

test "VM continuation thenable job captures after the live then getter while reactions keep their own registration" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable(); try f.install();
    try f.frameNumber(11);
    try f.run(
        \\globalThis.result=Promise.resolve({get then(){
        \\ noteFrame();setFrame(22);
        \\ return function(resolve){noteFrame();resolve(9);};
        \\}});
    );
    try f.frameIsNumber(22);
    try f.frameNumber(33); try f.run("globalThis.observed=result.then(()=>noteFrame());");
    try f.frameNumber(99);
    try std.testing.expectEqual(@as(usize, 2), try f.drain());
    try probe.expectEvents(&.{11, 22, 33}); try f.frameIsNumber(99);
}

test "VM continuation actual Source Await captures again after a resumed body changes current data" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable(); try f.install();
    try f.frameNumber(11);
    try f.run(
        \\globalThis.releaseOne=undefined;globalThis.releaseTwo=undefined;
        \\globalThis.gateOne=new Promise(resolve=>{releaseOne=resolve;});
        \\globalThis.gateTwo=new Promise(resolve=>{releaseTwo=resolve;});
        \\globalThis.result=(async function(){
        \\ noteFrame();await gateOne;noteFrame();setFrame(22);
        \\ await gateTwo;noteFrame();return frame();
        \\})();
    );
    try f.frameNumber(31); try f.run("releaseOne(1);"); try f.frameNumber(99);
    try std.testing.expect((try f.drain()) >= 1);
    try probe.expectEvents(&.{11, 11}); try f.frameIsNumber(99);
    const result = try f.eval("result"); defer c.JS_FreeValue(f.context.?, result);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.context.?, result));
    try f.frameNumber(44); try f.run("releaseTwo(2);"); try f.frameNumber(88);
    try std.testing.expect((try f.drain()) >= 1);
    try probe.expectEvents(&.{11, 11, 22}); try f.frameIsNumber(88);
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(f.context.?, result));
    const value = c.JS_PromiseResult(f.context.?, result); defer c.JS_FreeValue(f.context.?, value);
    try f.numberValue(value, 22);
}

test "VM continuation genuine native AsyncFunction Await uses the same independent registration root" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable(); try f.install();
    const function = try f.checked(c.JS_PiNewNativeAsyncFunction(f.context.?, nativeAsync,
        c.pi_js_undefined(), c.pi_js_undefined(), 0, "ActualContinuationAsync", 1));
    defer c.JS_FreeValue(f.context.?, function); try f.set("actualAsync", function);
    try f.frameNumber(11);
    try f.run(
        \\globalThis.release=undefined;
        \\globalThis.gate=new Promise(resolve=>{release=resolve;});
        \\globalThis.result=actualAsync(gate);
    );
    try f.frameNumber(33); try f.run("globalThis.observed=result.then(()=>noteFrame());");
    try f.frameNumber(44); try f.run("release(5);"); try f.frameNumber(99);
    try std.testing.expect((try f.drain()) >= 2);
    try probe.expectEvents(&.{11, 11, 33}); try f.frameIsNumber(99);
    try std.testing.expectEqual(@as(usize, 1), probe.async_starts);
    try std.testing.expectEqual(@as(usize, 1), probe.async_resumes);
    const result = try f.eval("result"); defer c.JS_FreeValue(f.context.?, result);
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(f.context.?, result));
    const value = c.JS_PromiseResult(f.context.?, result); defer c.JS_FreeValue(f.context.?, value);
    try f.numberValue(value, 5);
}

test "VM continuation job and Promise captures leave application capability tokens and hooks independent" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable(); try f.install();
    try f.frameNumber(11); c.JS_SetExecutionContext(f.runtime.?, c.pi_js_int32(f.context.?, 71));
    try f.enqueue(recordJob, &.{});
    try f.frameNumber(22); c.JS_SetExecutionContext(f.runtime.?, c.pi_js_int32(f.context.?, 72));
    try f.enqueue(recordJob, &.{});
    try f.frameNumber(33); c.JS_SetExecutionContext(f.runtime.?, c.pi_js_int32(f.context.?, 73));
    try f.run("globalThis.observed=Promise.resolve().then(()=>noteFrame());");
    try f.frameNumber(99); c.JS_SetExecutionContext(f.runtime.?, c.pi_js_int32(f.context.?, 79));
    c.JS_SetExecutionContextHook(f.runtime.?, contextHook, &probe);
    try std.testing.expectEqual(@as(usize, 3), try f.drain());
    try probe.expectEvents(&.{11, 22, 33}); try f.frameIsNumber(99);
    try std.testing.expectEqual(@as(usize, 6), probe.hook_count);
    for (0..3) |index| {
        const expected_capability: i32 = 71 + @as(i32, @intCast(index));
        const expected_data: i32 = 11 * (1 + @as(i32, @intCast(index)));
        for (0..2) |phase| {
            const event = probe.hook_events[index * 2 + phase];
            try std.testing.expectEqual(phase == 0, event.before);
            try std.testing.expectEqual(expected_capability, event.capability);
            try std.testing.expectEqual(expected_data, event.continuation);
        }
    }
    // Enqueue now still captures the caller's capability, not the last job's.
    try f.enqueue(recordJob, &.{});
    try std.testing.expectEqual(@as(usize, 1), try f.drain());
    try std.testing.expectEqual(@as(usize, 8), probe.hook_count);
    try std.testing.expectEqual(@as(i32, 79), probe.hook_events[6].capability);
    try std.testing.expectEqual(@as(i32, 99), probe.hook_events[6].continuation);
}

test "VM continuation disallowed checkpoints retain independent job roots through GC and make no progress" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    {
        const data = try probe.holder(&f, 0); defer c.JS_FreeValue(f.context.?, data);
        const capability = try probe.holder(&f, 1); defer c.JS_FreeValue(f.context.?, capability);
        try f.frame(data); c.JS_SetExecutionContext(f.runtime.?, capability);
        try f.enqueue(recordJob, &.{});
    }
    try f.frameNumber(99); c.JS_SetExecutionContext(f.runtime.?, c.pi_js_undefined());
    c.JS_SetExecutionContextHook(f.runtime.?, contextHook, &probe);
    const allowed = c.JS_PiExchangeJavascriptExecutionAllowed(f.runtime.?, false);
    {
        defer _ = c.JS_PiExchangeJavascriptExecutionAllowed(f.runtime.?, allowed);
        try std.testing.expectEqual(@as(usize, 0), try f.drain());
        try f.frameIsNumber(99);
        c.JS_RunGC(f.runtime.?);
        try std.testing.expectEqual(@as(usize, 0), probe.counts[0]);
        try std.testing.expectEqual(@as(usize, 0), probe.counts[1]);
        try std.testing.expectEqual(@as(usize, 0), probe.event_count);
        try std.testing.expectEqual(@as(usize, 0), probe.hook_count);
        try std.testing.expect(c.JS_IsJobPending(f.runtime.?));
    }
    try std.testing.expectEqual(@as(usize, 1), try f.drain());
    try probe.expectEvents(&.{100}); try f.frameIsNumber(99);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[1]);
    try std.testing.expectEqual(@as(usize, 2), probe.hook_count);
    try std.testing.expectEqual(@as(i32, 101), probe.hook_events[0].capability);
    try std.testing.expectEqual(@as(i32, 100), probe.hook_events[0].continuation);
}

test "VM continuation empty checkpoints neither replace current data nor acquire an extra root" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    {
        const data = try probe.holder(&f, 0); defer c.JS_FreeValue(f.context.?, data);
        try f.frame(data);
    }
    var batch = Batch.enter(&f); defer batch.restore();
    try std.testing.expect(!batch.active);
    var context: ?*c.JSContext = f.context.?;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ExecutePendingJob(f.runtime.?, &context));
    try std.testing.expect(context == null);
    try std.testing.expectEqual(@as(i32, 100), probe.current(f.context.?));
    try std.testing.expectEqual(@as(usize, 0), try f.drain());
    try std.testing.expectEqual(@as(usize, 0), probe.counts[0]);
    try f.frame(c.pi_js_undefined());
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
}

test "VM continuation failed real enqueue allocation leaves borrowed data capability and arguments unretained" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    {
        const data = try probe.holder(&f, 0); defer c.JS_FreeValue(f.context.?, data);
        const capability = try probe.holder(&f, 1); defer c.JS_FreeValue(f.context.?, capability);
        const argument = try probe.holder(&f, 2); defer c.JS_FreeValue(f.context.?, argument);
        try f.frame(data); c.JS_SetExecutionContext(f.runtime.?, capability);
        var args = [_]c.JSValue{argument};
        c.JS_SetMemoryLimit(f.runtime.?, 1);
        const status = c.JS_EnqueueJob(f.context.?, recordJob, 1, &args);
        c.JS_SetMemoryLimit(f.runtime.?, 0);
        try std.testing.expectEqual(@as(c_int, -1), status);
        const reason = try f.pendingReason(); defer c.JS_FreeValue(f.context.?, reason);
        try std.testing.expect(c.JS_IsNull(reason));
        try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
        try std.testing.expectEqual(@as(usize, 0), probe.event_count);
        try f.frame(c.pi_js_undefined()); c.JS_SetExecutionContext(f.runtime.?, c.pi_js_undefined());
    }
    try std.testing.expectEqualSlices(usize, &.{1, 1, 1}, probe.counts[0..3]);
}

test "VM continuation Promise reaction data is a real GC edge in both reachable and unreachable cycles" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    {
        const data = try f.checked(c.JS_NewObject(f.context.?)); defer c.JS_FreeValue(f.context.?, data);
        try probe.attach(&f, data, 0); try f.set("data", data); try f.frame(data);
        try f.run(
            \\globalThis.pending=new Promise(()=>{});
            \\data.pending=pending;pending.then(()=>{});
            \\delete globalThis.pending;delete globalThis.data;
        );
    }
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual(@as(usize, 0), probe.counts[0]);
    try f.frame(c.pi_js_undefined());
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
}

test "VM continuation runtime teardown releases current and unexecuted queued native roots exactly once" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    {
        const queued = try probe.holder(&f, 0); defer c.JS_FreeValue(f.context.?, queued);
        const capability = try probe.holder(&f, 1); defer c.JS_FreeValue(f.context.?, capability);
        const argument = try probe.holder(&f, 2); defer c.JS_FreeValue(f.context.?, argument);
        const current = try probe.holder(&f, 3); defer c.JS_FreeValue(f.context.?, current);
        try f.frame(queued); c.JS_SetExecutionContext(f.runtime.?, capability);
        try f.enqueue(recordJob, &.{argument});
        try f.frame(current); c.JS_SetExecutionContext(f.runtime.?, c.pi_js_undefined());
    }
    try std.testing.expectEqualSlices(usize, &.{0, 0, 0, 0}, probe.counts[0..4]);
    probe.disable(); f.deinit();
    try std.testing.expectEqualSlices(usize, &.{1, 1, 1, 1}, probe.counts[0..4]);
    try std.testing.expectEqual(@as(usize, 0), probe.event_count);
}

test "VM continuation job and batch cleanup retain the first actual fatal and release every independent owner" {
    inline for (.{ false, true }) |body_fatal| {
        var probe: Probe = .{};
        var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
        try probe.makeReason(&f, 0, body_fatal);
        try probe.makeReason(&f, 1, true); try probe.makeReason(&f, 2, true); try probe.makeReason(&f, 3, true);
        probe.tokens[0].throw_reason = 1; probe.tokens[0].observe = true;
        probe.tokens[1].throw_reason = 2; probe.tokens[1].observe = true;
        probe.tokens[2].throw_reason = 3; probe.tokens[2].observe = true;
        {
            const data = try probe.holder(&f, 0); defer c.JS_FreeValue(f.context.?, data);
            const capability = try probe.holder(&f, 1); defer c.JS_FreeValue(f.context.?, capability);
            const argument = try probe.holder(&f, 2); defer c.JS_FreeValue(f.context.?, argument);
            try f.frame(data); c.JS_SetExecutionContext(f.runtime.?, capability);
            try f.enqueue(failJob, &.{probe.reasons[0], argument});
            try f.frameNumber(99); c.JS_SetExecutionContext(f.runtime.?, c.pi_js_undefined());
        }
        var batch = Batch.enter(&f); defer batch.restore();
        var context: ?*c.JSContext = null;
        try std.testing.expectEqual(@as(c_int, -1), c.JS_ExecutePendingJob(f.runtime.?, &context));
        try std.testing.expect(context == f.context.?);
        try std.testing.expect(c.JS_HasException(f.context.?));
        try std.testing.expectEqualSlices(usize, &.{0, 1, 1}, probe.counts[0..3]);
        try std.testing.expectEqual(@as(i32, 100), probe.retired_with[1]);
        try std.testing.expectEqual(@as(i32, 100), probe.retired_with[2]);
        // Preserve the still-pending body/cleanup completion through outer restore.
        batch.restore();
        const reason = try f.pendingReason(); defer c.JS_FreeValue(f.context.?, reason);
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?,
            probe.reasons[if (body_fatal) 0 else 2], reason));
        try std.testing.expect(c.JS_IsUncatchableError(reason));
        try std.testing.expectEqualSlices(usize, &.{1, 1, 1}, probe.counts[0..3]);
        try std.testing.expectEqual(@as(i32, 99), probe.retired_with[0]);
        try probe.expectEvents(&.{100}); try f.frameIsNumber(99);
    }
}

test "VM continuation returned flagged DATA and contained ordinary Promise rejection complete tasks normally" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable(); try f.install();
    try probe.makeReason(&f, 0, true);
    try f.frameNumber(11); try f.enqueue(returnJob, &.{probe.reasons[0]}); try f.frameNumber(99);
    try std.testing.expectEqual(@as(usize, 1), try f.drain());
    try std.testing.expect(!c.JS_HasException(f.context.?));
    try std.testing.expect(c.JS_IsUncatchableError(probe.reasons[0])); try f.frameIsNumber(99);
    try f.frameNumber(21);
    try f.run(
        \\globalThis.rejected=Promise.resolve().then(()=>{
        \\ noteFrame();setFrame(22);throw 13;
        \\});
    );
    try f.frameNumber(98);
    var batch = Batch.enter(&f); defer batch.restore();
    try f.one(); try f.frameIs(c.pi_js_undefined());
    try probe.expectEvents(&.{11, 21});
    const rejected = try f.eval("rejected"); defer c.JS_FreeValue(f.context.?, rejected);
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(f.context.?, rejected));
    const reason = c.JS_PromiseResult(f.context.?, rejected); defer c.JS_FreeValue(f.context.?, reason);
    try f.numberValue(reason, 13);
    batch.restore(); try f.frameIsNumber(98);
}

test "VM continuation setup retirement fatal stops the real job and hooks while consuming queued owners" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    try probe.makeReason(&f, 0, true);
    probe.tokens[1].throw_reason = 0; probe.tokens[1].observe = true;
    {
        const captured = try probe.holder(&f, 0); defer c.JS_FreeValue(f.context.?, captured);
        const displaced = try probe.holder(&f, 1); defer c.JS_FreeValue(f.context.?, displaced);
        const argument = try probe.holder(&f, 2); defer c.JS_FreeValue(f.context.?, argument);
        const capability = try probe.holder(&f, 3); defer c.JS_FreeValue(f.context.?, capability);
        try f.frame(captured); c.JS_SetExecutionContext(f.runtime.?, capability);
        try f.enqueue(recordJob, &.{argument});
        try f.frame(displaced); c.JS_SetExecutionContext(f.runtime.?, c.pi_js_undefined());
    }
    c.JS_SetExecutionContextHook(f.runtime.?, contextHook, &probe);
    // This directly exercises per-job setup, with the current old root still
    // live. The separate outer batch adapter would reset it before this point.
    const reason = try f.failedOne(); defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, probe.reasons[0]));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(@as(usize, 0), probe.event_count);
    try std.testing.expectEqual(@as(usize, 0), probe.hook_count);
    try std.testing.expectEqualSlices(usize, &.{0, 1, 1, 1}, probe.counts[0..4]);
    try std.testing.expectEqual(@as(i32, 100), probe.retired_with[1]);
    try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
    try f.frame(c.pi_js_undefined());
    try std.testing.expectEqualSlices(usize, &.{1, 1, 1, 1}, probe.counts[0..4]);
}

fn failReactionEnqueue(context: ?*c.JSContext, kind: c.JSPromiseHookType, promise: c.JSValue,
    _: c.JSValue, raw_owner: ?*anyopaque) callconv(.c) void
{
    const ctx = context orelse return;
    const raw = raw_owner orelse return;
    const probe: *Probe = @ptrCast(@alignCast(raw));
    if (!probe.enabled or kind != c.JS_PROMISE_HOOK_RESOLVE or
        !c.JS_IsStrictEqual(ctx, promise, probe.settlement_promise)) return;
    probe.settlement_hooks += 1;
    const runtime = c.JS_GetRuntime(ctx);
    c.JS_SetPromiseHook(runtime, null, null);
    // This actual hook runs after the fulfilled state is stored and before
    // the real reaction job allocation. The two reaction records already exist.
    c.JS_SetMemoryLimit(runtime, 1);
}
test "VM continuation reaction retirement preserves earlier fatal when actual enqueue allocation fails" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit(); try probe.init(&f); defer probe.disable();
    try probe.makeReason(&f, 0, true); try probe.makeReason(&f, 1, true);
    var resolving = [_]c.JSValue{c.pi_js_undefined(), c.pi_js_undefined()};
    const promise = try f.checked(c.JS_NewPromiseCapability(f.context.?, &resolving));
    defer c.JS_FreeValue(f.context.?, promise);
    defer { for (resolving) |value| c.JS_FreeValue(f.context.?, value); }
    var derived = c.pi_js_undefined(); defer c.JS_FreeValue(f.context.?, derived);
    {
        const data = try probe.holder(&f, 0); defer c.JS_FreeValue(f.context.?, data);
        const capability = try probe.holder(&f, 1); defer c.JS_FreeValue(f.context.?, capability);
        probe.tokens[1].throw_reason = 0;
        probe.tokens[0].throw_reason = 1;
        try f.frame(data); c.JS_SetExecutionContext(f.runtime.?, capability);
        derived = try f.checked(c.JS_PromiseThen(f.context.?, promise, c.pi_js_undefined(), c.pi_js_undefined()));
        try f.frame(c.pi_js_undefined()); c.JS_SetExecutionContext(f.runtime.?, c.pi_js_undefined());
    }
    try std.testing.expectEqualSlices(usize, &.{0, 0}, probe.counts[0..2]);
    probe.settlement_promise = promise; // Borrowed from the retained actual Promise.
    c.JS_SetPromiseHook(f.runtime.?, failReactionEnqueue, &probe);
    const result = c.JS_PiSettlePromise(f.context.?, promise, c.pi_js_int32(f.context.?, 7), false);
    c.JS_SetMemoryLimit(f.runtime.?, 0);
    c.JS_SetPromiseHook(f.runtime.?, null, null);
    probe.settlement_promise = c.pi_js_undefined();
    defer c.JS_FreeValue(f.context.?, result);
    try std.testing.expect(c.JS_IsException(result));
    const reason = try f.pendingReason(); defer c.JS_FreeValue(f.context.?, reason);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, probe.reasons[0]));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(@as(usize, 1), probe.settlement_hooks);
    try std.testing.expectEqualSlices(usize, &.{1, 1}, probe.counts[0..2]);
    try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(f.context.?, promise));
}
