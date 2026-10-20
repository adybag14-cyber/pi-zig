//! Actual native execution termination, Promise job hooks and detached queue ownership.
//! These controls use the linked VM. Batch only spells out the caller's explicit
//! continuation save/reset/restore; it is not a Node checkpoint/reporting owner.
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
            c.JS_SetPromiseHook(runtime, null, null);
            c.JS_SetInterruptHandler(runtime, null, null);
            c.JS_SetMemoryLimit(runtime, 0);
            _ = c.JS_PiExchangeJavascriptExecutionAllowed(runtime, true);
        }
        if (self.context) |context| {
            // The probe is disabled before this fallback. Clear a real pending
            // reason, republish any escrowed lease, and cancel before teardown.
            if (c.JS_HasException(context)) c.JS_FreeValue(context, c.JS_GetException(context));
            _ = c.JS_PiCheckExecutionTermination(context);
            c.JS_PiCancelExecutionTermination(self.runtime.?);
            _ = c.JS_PiFinishTerminatedMicrotasks(self.runtime.?);
            if (c.JS_HasException(context)) c.JS_FreeValue(context, c.JS_GetException(context));
            self.context = null;
            c.JS_FreeContext(context);
        }
        if (self.runtime) |runtime| { self.runtime = null; c.JS_FreeRuntime(runtime); }
        if (self.memory) |memory| { self.memory = null; c.pi_js_release_memory_owner(memory); }
    }
    fn checked(self: *Fixture, value: c.JSValue) !c.JSValue {
        if (c.JS_IsException(value) or c.JS_HasException(self.context.?)) {
            c.JS_FreeValue(self.context.?, value);
            return error.ActualTerminationControlSetup;
        }
        return value;
    }
    fn evalRaw(self: *Fixture, source: [:0]const u8) c.JSValue {
        return c.JS_Eval(self.context.?, source.ptr, source.len, "actual-native-termination.js",
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
    fn api(self: *Fixture) !c.JSValue {
        return self.checked(c.JS_NewCFunctionData2(self.context.?, nativeCall,
            "actualNativeTermination", 0, 0, 0, null));
    }
    fn install(self: *Fixture) !void {
        const callback = try self.api(); defer c.JS_FreeValue(self.context.?, callback);
        try self.set("act", callback);
    }
    fn pending(self: *Fixture) !c.JSValue {
        try std.testing.expect(c.JS_HasException(self.context.?));
        return c.JS_GetException(self.context.?);
    }
    fn number(self: *Fixture, value: c.JSValue, expected: i32) !void {
        try std.testing.expect(c.JS_IsNumber(value));
        var actual: i32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(self.context.?, &actual, value));
        try std.testing.expectEqual(expected, actual);
    }
    fn ownBool(self: *Fixture, record: c.JSValue, key: [*:0]const u8, expected: bool) !void {
        // record and this own primitive field were retained before any failure.
        const value = c.JS_GetPropertyStr(self.context.?, record, key);
        defer c.JS_FreeValue(self.context.?, value);
        try std.testing.expect(c.JS_IsBool(value));
        try std.testing.expectEqual(@as(c_int, @intFromBool(expected)), c.JS_ToBool(self.context.?, value));
    }
    fn frame(self: *Fixture, frame_value: i32) void {
        c.JS_PiSetContinuationPreservedEmbedderData(self.runtime.?, c.JS_NewInt32(self.context.?, frame_value));
    }
    fn enqueue(self: *Fixture, callback: *const c.JSJobFunc, args: []const c.JSValue) !void {
        try std.testing.expectEqual(@as(c_int, 0), c.JS_EnqueueJob(self.context.?, callback,
            @intCast(args.len), if (args.len == 0) null else @constCast(args.ptr)));
        try std.testing.expect(!c.JS_HasException(self.context.?));
    }
    fn step(self: *Fixture, expected: c_int) !void {
        var context: ?*c.JSContext = null;
        const status = c.JS_ExecutePendingJob(self.runtime.?, &context);
        try std.testing.expectEqual(expected, status);
        if (status == 0) try std.testing.expect(context == null)
        else try std.testing.expect(context == self.context.?);
    }
};
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
        const previous = self.previous; self.previous = c.pi_js_undefined();
        c.JS_PiSetContinuationPreservedEmbedderData(self.runtime, previous);
        c.JS_FreeValueRT(self.runtime, previous);
    }
};
const Action = enum { none, service, service_request_again, service_finish, reason0, reason1,
    republish_cancel_reason0, finish_enqueue };
const Mode = enum { value, request_value, terminate, cancel_abrupt, cancel_success, throw_reason0 };
const Token = struct { probe: *Probe, index: usize, action: Action = .none };
const HookRecord = struct {
    kind: c.JSPromiseHookType,
    promise: c.JSValue, // Borrowed identity only; never dereferenced after retirement.
    frame: i32,
    calls: usize,
    first_retired: usize,
    second_retired: usize,
    terminating: bool,
    queued: bool,
    state: c.JSPromiseStateEnum,
    matched_expected: bool,
};
const Probe = struct {
    context: ?*c.JSContext = null,
    enabled: bool = false,
    class_id: c.JSClassID = 0,
    tokens: [16]Token = undefined,
    counts: [16]usize = .{0} ** 16,
    actions: [16]Action = .{.none} ** 16,
    mode: Mode = .value,
    calls: usize = 0,
    jobs: usize = 0,
    async_starts: usize = 0,
    interrupt_calls: usize = 0,
    return_value: c.JSValue = undefined,
    reasons: [2]c.JSValue = undefined,
    init_promise: c.JSValue = undefined,
    retain_init: bool = false,
    expected_hook_promise: c.JSValue = undefined,
    before_action: Action = .none,
    after_action: Action = .none,
    hook_count: usize = 0,
    hooks: [16]HookRecord = undefined,
    overflow: bool = false,
    nested_finish: c_int = -99,
    queued_before_enqueue: bool = true,
    enqueue_status: c_int = -99,
    current_at_job: i32 = -999,
    fn init(self: *Probe, f: *Fixture) !void {
        self.context = f.context.?;
        const nothing = c.pi_js_undefined();
        self.return_value = nothing; self.init_promise = nothing; self.expected_hook_promise = nothing;
        for (&self.reasons) |*slot| slot.* = nothing;
        for (&self.tokens, 0..) |*token, index| token.* = .{ .probe = self, .index = index };
        _ = c.JS_NewClassID(f.runtime.?, &self.class_id);
        const definition: c.JSClassDef = .{ .class_name = "Actual termination holder", .finalizer = retire };
        try std.testing.expectEqual(@as(c_int, 0), c.JS_NewClass(f.runtime.?, self.class_id, &definition));
        c.JS_SetContextOpaque(f.context.?, self);
        self.enabled = true;
    }
    fn disable(self: *Probe) void {
        self.enabled = false;
        const context = self.context orelse return;
        self.context = null; self.expected_hook_promise = c.pi_js_undefined();
        c.JS_SetPromiseHook(c.JS_GetRuntime(context), null, null);
        c.JS_SetContextOpaque(context, null);
        for (&self.reasons) |*slot| {
            const old = slot.*; slot.* = c.pi_js_undefined(); c.JS_FreeValue(context, old);
        }
        const returned = self.return_value; self.return_value = c.pi_js_undefined();
        const init_promise = self.init_promise; self.init_promise = c.pi_js_undefined();
        c.JS_FreeValue(context, returned); c.JS_FreeValue(context, init_promise);
    }
    fn from(context: *c.JSContext) ?*Probe {
        const raw_owner = c.JS_GetContextOpaque(context) orelse return null;
        return @ptrCast(@alignCast(raw_owner));
    }
    fn reason(self: *Probe, f: *Fixture, index: usize, fatal: bool) !void {
        self.reasons[index] = try f.checked(c.JS_NewError(f.context.?));
        if (fatal) c.JS_SetUncatchableError(f.context.?, self.reasons[index]);
    }
    fn holder(self: *Probe, f: *Fixture, index: usize, action: Action) !c.JSValue {
        const value = try f.checked(c.JS_NewObjectProtoClass(f.context.?, c.pi_js_null(), self.class_id));
        self.tokens[index].action = action;
        _ = c.JS_SetOpaque(value, &self.tokens[index]);
        return value;
    }
    fn id(context: *c.JSContext) i32 {
        const value = c.JS_PiGetContinuationPreservedEmbedderData(c.JS_GetRuntime(context));
        defer c.JS_FreeValue(context, value);
        if (c.JS_IsUndefined(value)) return -1;
        if (!c.JS_IsNumber(value)) return -2;
        var result: i32 = 0;
        if (c.JS_ToInt32(context, &result, value) < 0) return -3;
        return result;
    }
    fn perform(self: *Probe, context: *c.JSContext, action: Action) void {
        const runtime = c.JS_GetRuntime(context);
        switch (action) {
            .none => {},
            .service, .service_request_again, .service_finish => {
                c.JS_PiRequestExecutionTermination(runtime);
                _ = c.JS_PiCheckExecutionTermination(context);
                if (action == .service_request_again) c.JS_PiRequestExecutionTermination(runtime);
                if (action == .service_finish) self.nested_finish = c.JS_PiFinishTerminatedMicrotasks(runtime);
            },
            .reason0, .reason1 => {
                const index: usize = if (action == .reason0) 0 else 1;
                _ = c.JS_Throw(context, c.JS_DupValue(context, self.reasons[index]));
            },
            .republish_cancel_reason0 => {
                _ = c.JS_PiCheckExecutionTermination(context);
                c.JS_PiCancelExecutionTermination(runtime);
                _ = c.JS_Throw(context, c.JS_DupValue(context, self.reasons[0]));
            },
            .finish_enqueue => {
                self.nested_finish = c.JS_PiFinishTerminatedMicrotasks(runtime);
                self.queued_before_enqueue = c.JS_IsJobPending(runtime);
                self.enqueue_status = c.JS_EnqueueJob(context, recordJob, 0, null);
            },
        }
    }
    fn retire(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
        const raw_owner = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return;
        const token: *Token = @ptrCast(@alignCast(raw_owner));
        const self = token.probe;
        const action = token.action; token.action = .none;
        _ = c.JS_SetOpaque(value, null);
        self.counts[token.index] += 1;
        if (!self.enabled) return;
        self.perform(self.context orelse return, action);
    }
    fn installHook(self: *Probe, f: *Fixture) void { c.JS_SetPromiseHook(f.runtime.?, hook, self); }
    fn hook(context: ?*c.JSContext, kind: c.JSPromiseHookType, promise: c.JSValue,
        _: c.JSValue, raw_owner: ?*anyopaque) callconv(.c) void
    {
        const ctx = context orelse return;
        const self: *Probe = @ptrCast(@alignCast(raw_owner orelse return));
        if (!self.enabled) return;
        if (kind == c.JS_PROMISE_HOOK_INIT and self.retain_init and c.JS_IsUndefined(self.init_promise))
            self.init_promise = c.JS_DupValue(ctx, promise);
        if (kind != c.JS_PROMISE_HOOK_BEFORE and kind != c.JS_PROMISE_HOOK_AFTER) return;
        if (self.hook_count == self.hooks.len) { self.overflow = true; return; }
        self.hooks[self.hook_count] = .{
            .kind = kind, .promise = promise, .frame = id(ctx), .calls = self.calls,
            .first_retired = self.counts[0], .second_retired = self.counts[1],
            .terminating = c.JS_PiIsExecutionTerminating(c.JS_GetRuntime(ctx)),
            .queued = c.JS_IsJobPending(c.JS_GetRuntime(ctx)), .state = c.JS_PromiseState(ctx, promise),
            .matched_expected = !c.JS_IsUndefined(self.expected_hook_promise) and c.JS_IsStrictEqual(ctx, self.expected_hook_promise, promise),
        };
        self.hook_count += 1;
        const action = if (kind == c.JS_PROMISE_HOOK_BEFORE) self.before_action else self.after_action;
        if (kind == c.JS_PROMISE_HOOK_BEFORE) self.before_action = .none else self.after_action = .none;
        self.perform(ctx, action);
    }
    fn hooksAre(self: *Probe, f: *Fixture, promise: c.JSValue, before_calls: usize, after_calls: usize) !void {
        try std.testing.expect(!self.overflow);
        try std.testing.expectEqual(@as(usize, 2), self.hook_count);
        try std.testing.expectEqual(@as(c.JSPromiseHookType, c.JS_PROMISE_HOOK_BEFORE), self.hooks[0].kind);
        try std.testing.expectEqual(@as(c.JSPromiseHookType, c.JS_PROMISE_HOOK_AFTER), self.hooks[1].kind);
        for (self.hooks[0..2]) |event|
            try std.testing.expect(c.JS_IsStrictEqual(f.context.?, promise, event.promise));
        try std.testing.expectEqual(before_calls, self.hooks[0].calls);
        try std.testing.expectEqual(after_calls, self.hooks[1].calls);
    }
};
fn nativeCall(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue,
    _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const ctx = context orelse return c.pi_js_exception();
    const probe = Probe.from(ctx) orelse return c.pi_js_exception();
    const runtime = c.JS_GetRuntime(ctx);
    probe.calls += 1;
    switch (probe.mode) {
        .terminate => { c.JS_PiRequestExecutionTermination(runtime); _ = c.JS_PiCheckExecutionTermination(ctx); return c.pi_js_exception(); },
        .cancel_abrupt, .cancel_success => {
            c.JS_PiRequestExecutionTermination(runtime); _ = c.JS_PiCheckExecutionTermination(ctx);
            c.JS_PiCancelExecutionTermination(runtime);
            if (probe.mode == .cancel_abrupt) return c.JS_PiNativeTerminationResult();
            return c.JS_NewInt32(ctx, 41);
        },
        .throw_reason0 => return c.JS_Throw(ctx, c.JS_DupValue(ctx, probe.reasons[0])),
        .request_value => c.JS_PiRequestExecutionTermination(runtime),
        .value => {},
    }
    if (!c.JS_IsUndefined(probe.return_value)) {
        const value = probe.return_value; probe.return_value = c.pi_js_undefined(); return value;
    }
    return c.JS_NewInt32(ctx, 41);
}
fn recordJob(context: ?*c.JSContext, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const ctx = context orelse return c.pi_js_exception();
    const probe = Probe.from(ctx) orelse return c.pi_js_exception();
    probe.jobs += 1; probe.current_at_job = Probe.id(ctx);
    return c.pi_js_undefined();
}
fn terminateJob(context: ?*c.JSContext, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const ctx = context orelse return c.pi_js_exception();
    const probe = Probe.from(ctx) orelse return c.pi_js_exception();
    probe.jobs += 1; probe.current_at_job = Probe.id(ctx);
    c.JS_PiRequestExecutionTermination(c.JS_GetRuntime(ctx));
    _ = c.JS_PiCheckExecutionTermination(ctx);
    return c.pi_js_exception();
}
fn failJob(context: ?*c.JSContext, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const ctx = context orelse return c.pi_js_exception();
    const probe = Probe.from(ctx) orelse return c.pi_js_exception();
    probe.jobs += 1;
    return c.JS_Throw(ctx, c.JS_DupValue(ctx, probe.reasons[0]));
}
fn asyncTerminate(context: ?*c.JSContext, _: c.JSValue, _: c.JSValue, _: c_int,
    _: [*c]c.JSValue, _: c_int, _: c.JSValue, _: [*c]c.JSValue,
    action: [*c]c_int) callconv(.c) c.JSValue
{
    const ctx = context orelse return c.pi_js_exception();
    const probe = Probe.from(ctx) orelse return c.pi_js_exception();
    probe.async_starts += 1; action[0] = c.JS_PI_AF_RETURN;
    c.JS_PiRequestExecutionTermination(c.JS_GetRuntime(ctx));
    _ = c.JS_PiCheckExecutionTermination(ctx);
    return c.pi_js_exception();
}
fn interrupt(_: ?*c.JSRuntime, raw_owner: ?*anyopaque) callconv(.c) c_int {
    const probe: *Probe = @ptrCast(@alignCast(raw_owner orelse return 1));
    probe.interrupt_calls += 1; return 1;
}
fn requestWorker(runtime: *c.JSRuntime) void { c.JS_PiRequestExecutionTermination(runtime); }
fn attachMarker(f: *Fixture, probe: *Probe, promise: c.JSValue, index: usize) !void {
    const marker = try probe.holder(f, index, .none);
    try std.testing.expect(c.JS_DefinePropertyValueStr(f.context.?, promise, "actualMarker",
        marker, c.JS_PROP_C_W_E) >= 0);
}
fn setupReaction(f: *Fixture, probe: *Probe, mode: Mode) !c.JSValue {
    try f.install(); probe.mode = mode;
    return f.eval("Promise.resolve(1).then(act)");
}

test "VM termination request service cancel and generation are distinct allocation-free native operations" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const before = c.JS_PiExecutionTerminationGeneration(f.runtime.?);
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    c.JS_PiRequestExecutionTermination(f.runtime.?);
    const requested_pending = c.JS_HasException(f.context.?);
    const requested_active = c.JS_PiIsExecutionTerminating(f.runtime.?);
    const status = c.JS_PiCheckExecutionTermination(f.context.?);
    const active = c.JS_PiIsExecutionTerminating(f.runtime.?);
    const serviced = c.JS_PiExecutionTerminationGeneration(f.runtime.?);
    const token = c.JS_GetException(f.context.?);
    const detached_active = c.JS_PiIsExecutionTerminating(f.runtime.?);
    const token_priority = c.JS_PiNativePendingPriority(f.runtime.?, token);
    _ = c.JS_Throw(f.context.?, token);
    c.JS_PiCancelExecutionTermination(f.runtime.?);
    const after_cancel = c.JS_PiCheckExecutionTermination(f.context.?);
    c.JS_SetMemoryLimit(f.runtime.?, 0);
    try std.testing.expect(!requested_pending and !requested_active);
    try std.testing.expectEqual(@as(c_int, -1), status);
    try std.testing.expect(active and !detached_active);
    try std.testing.expectEqual(before + 1, serviced);
    try std.testing.expect(c.JS_PiIsExecutionTermination(token));
    try std.testing.expect(!c.JS_IsError(token) and !c.JS_IsUncatchableError(token));
    try std.testing.expectEqual(@as(c_int, 1), token_priority);
    try std.testing.expectEqual(@as(c_int, 0), after_cancel);
    try std.testing.expect(!c.JS_HasException(f.context.?));
}

test "VM termination request-only cancellation and empty job observation do not create an event" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    c.JS_PiRequestExecutionTermination(f.runtime.?);
    try f.step(0);
    try std.testing.expect(!c.JS_HasException(f.context.?));
    try std.testing.expect(!c.JS_PiIsExecutionTerminating(f.runtime.?));
    c.JS_PiCancelExecutionTermination(f.runtime.?);
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiCheckExecutionTermination(f.context.?));
    try std.testing.expectEqual(@as(u64, 0), c.JS_PiExecutionTerminationGeneration(f.runtime.?));
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiFinishTerminatedMicrotasks(f.runtime.?));
}

test "VM termination servicing preserves an earlier actual ordinary or generic fatal reason and its later request" {
    for ([_]bool{ false, true }) |fatal| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        const reason = try f.checked(c.JS_NewError(f.context.?)); defer c.JS_FreeValue(f.context.?, reason);
        if (fatal) c.JS_SetUncatchableError(f.context.?, reason);
        _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
        c.JS_PiRequestExecutionTermination(f.runtime.?);
        try std.testing.expectEqual(@as(c_int, -1), c.JS_PiCheckExecutionTermination(f.context.?));
        try std.testing.expectEqual(@as(u64, 0), c.JS_PiExecutionTerminationGeneration(f.runtime.?));
        try std.testing.expect(!c.JS_PiIsExecutionTerminating(f.runtime.?));
        {
            const actual = try f.pending(); defer c.JS_FreeValue(f.context.?, actual);
            try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, actual));
            try std.testing.expectEqual(fatal, c.JS_IsUncatchableError(actual));
        }
        try std.testing.expectEqual(@as(c_int, -1), c.JS_PiCheckExecutionTermination(f.context.?));
        try std.testing.expect(c.JS_PiIsExecutionTerminating(f.runtime.?));
        try std.testing.expectEqual(@as(u64, 1), c.JS_PiExecutionTerminationGeneration(f.runtime.?));
        c.JS_PiCancelExecutionTermination(f.runtime.?);
    }
}

test "VM termination a detached event lease blocks reentry but is not the actual pending query or cancel condition" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    c.JS_PiRequestExecutionTermination(f.runtime.?);
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiCheckExecutionTermination(f.context.?));
    const token = try f.pending(); defer c.JS_FreeValue(f.context.?, token);
    try std.testing.expect(!c.JS_PiIsExecutionTerminating(f.runtime.?));
    c.JS_PiCancelExecutionTermination(f.runtime.?);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_PiNativePendingPriority(f.runtime.?, token));
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiCheckExecutionTermination(f.context.?));
    try std.testing.expect(c.JS_PiIsExecutionTerminating(f.runtime.?));
    try std.testing.expectEqual(@as(u64, 1), c.JS_PiExecutionTerminationGeneration(f.runtime.?));
    c.JS_PiCancelExecutionTermination(f.runtime.?);
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiNativePendingPriority(f.runtime.?, token));
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiCheckExecutionTermination(f.context.?));
}

test "VM termination cancelled native result adds no event and cannot replace a subsequent real cleanup reason" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const reason = try f.checked(c.JS_NewError(f.context.?)); defer c.JS_FreeValue(f.context.?, reason);
    c.JS_PiRequestExecutionTermination(f.runtime.?);
    _ = c.JS_PiCheckExecutionTermination(f.context.?);
    const token = c.JS_GetException(f.context.?);
    _ = c.JS_Throw(f.context.?, token);
    c.JS_PiCancelExecutionTermination(f.runtime.?);
    const generation = c.JS_PiExecutionTerminationGeneration(f.runtime.?);
    const abrupt = c.JS_PiNativeTerminationResult();
    try std.testing.expect(c.JS_PiIsExecutionTermination(abrupt));
    try std.testing.expect(!c.JS_HasException(f.context.?));
    try std.testing.expect(!c.JS_PiIsExecutionTerminating(f.runtime.?));
    _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, reason));
    _ = c.JS_Throw(f.context.?, abrupt);
    const actual = try f.pending(); defer c.JS_FreeValue(f.context.?, actual);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, reason, actual));
    try std.testing.expectEqual(generation, c.JS_PiExecutionTerminationGeneration(f.runtime.?));
    try std.testing.expect(!c.JS_PiIsExecutionTerminating(f.runtime.?));
}

test "VM termination an earlier generic fatal retires a losing cleanup event lease without erasing a later request" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try probe.init(&f); defer probe.disable();
    try probe.reason(&f, 0, true);
    const holder = try probe.holder(&f, 0, .service_request_again);
    c.JS_PiSetContinuationPreservedEmbedderData(f.runtime.?, holder);
    c.JS_FreeValue(f.context.?, holder);
    _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, probe.reasons[0]));
    // This actual runtime owner escrows the earlier fatal while the replaced
    // slot's finalizer services termination and leaves another request.
    c.JS_PiSetContinuationPreservedEmbedderData(f.runtime.?, c.pi_js_undefined());
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try std.testing.expect(!c.JS_PiIsExecutionTerminating(f.runtime.?));
    {
        const actual = try f.pending(); defer c.JS_FreeValue(f.context.?, actual);
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?, probe.reasons[0], actual));
    }
    try std.testing.expectEqual(@as(u64, 1), c.JS_PiExecutionTerminationGeneration(f.runtime.?));
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiCheckExecutionTermination(f.context.?));
    try std.testing.expectEqual(@as(u64, 2), c.JS_PiExecutionTerminationGeneration(f.runtime.?));
    try std.testing.expect(c.JS_PiIsExecutionTerminating(f.runtime.?));
    c.JS_PiCancelExecutionTermination(f.runtime.?);
}

test "VM termination classified actual owners retain cached generic authority without mutating public Error flags" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const first = try f.checked(c.JS_NewError(f.context.?)); defer c.JS_FreeValue(f.context.?, first);
    const second = try f.checked(c.JS_NewError(f.context.?)); defer c.JS_FreeValue(f.context.?, second);
    _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, first));
    const owned_first = try f.pending(); defer c.JS_FreeValue(f.context.?, owned_first);
    _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, second));
    const owned_second = try f.pending(); defer c.JS_FreeValue(f.context.?, owned_second);
    c.JS_SetUncatchableError(f.context.?, first);
    try std.testing.expect(!c.JS_PiNativePendingReplaceClassified(f.runtime.?,
        owned_first, false, owned_second, false));
    try std.testing.expect(c.JS_IsUncatchableError(first));
    c.JS_SetUncatchableError(f.context.?, second);
    _ = c.JS_Throw(f.context.?, c.JS_DupValue(f.context.?, second));
    const owned_second_fatal = try f.pending(); defer c.JS_FreeValue(f.context.?, owned_second_fatal);
    try std.testing.expect(c.JS_IsUncatchableError(owned_second_fatal));
    c.JS_ClearUncatchableError(f.context.?, second);
    try std.testing.expect(c.JS_PiNativePendingReplaceClassified(f.runtime.?,
        owned_first, false, owned_second_fatal, true));
    try std.testing.expect(!c.JS_IsUncatchableError(second));
    try std.testing.expect(!c.JS_HasException(f.context.?));
}

test "VM termination the real script call skips catch finally and later own-data progress after a native event" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try probe.init(&f); defer probe.disable(); try f.install();
    const function = try f.eval(
        \\globalThis.progress={caught:false,finalized:false,after:false};
        \\(function(){try{act();progress.after=true}catch(e){progress.caught=true}finally{progress.finalized=true}})
    ); defer c.JS_FreeValue(f.context.?, function);
    const progress = try f.eval("progress"); defer c.JS_FreeValue(f.context.?, progress);
    probe.mode = .terminate;
    const raw = c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null);
    defer c.JS_FreeValue(f.context.?, raw);
    try std.testing.expect(c.JS_IsException(raw));
    try std.testing.expect(c.JS_PiIsExecutionTerminating(f.runtime.?));
    try std.testing.expectEqual(@as(usize, 1), probe.calls);
    try f.ownBool(progress, "caught", false); try f.ownBool(progress, "finalized", false);
    try f.ownBool(progress, "after", false);
    c.JS_PiCancelExecutionTermination(f.runtime.?);
}

test "VM termination requested entry blocks direct ordinary and explicitly admitted native API callbacks" {
    for ([_]bool{ false, true }) |marked| {
        var probe: Probe = .{};
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        try probe.init(&f); defer probe.disable();
        const callback = try f.api(); defer c.JS_FreeValue(f.context.?, callback);
        if (marked) try std.testing.expectEqual(@as(c_int, 0), c.JS_PiMarkNativeApiFunction(f.context.?, callback));
        c.JS_PiRequestExecutionTermination(f.runtime.?);
        const raw = c.JS_Call(f.context.?, callback, c.pi_js_undefined(), 0, null);
        defer c.JS_FreeValue(f.context.?, raw);
        try std.testing.expect(c.JS_IsException(raw));
        try std.testing.expect(c.JS_PiIsExecutionTerminating(f.runtime.?));
        try std.testing.expectEqual(@as(usize, 0), probe.calls);
        c.JS_PiCancelExecutionTermination(f.runtime.?);
    }
}

test "VM termination native return services a request and retires the actual returned sole holder exactly once" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try probe.init(&f); defer probe.disable();
    const callback = try f.api(); defer c.JS_FreeValue(f.context.?, callback);
    probe.return_value = try probe.holder(&f, 0, .none);
    probe.mode = .request_value;
    const raw = c.JS_Call(f.context.?, callback, c.pi_js_undefined(), 0, null);
    defer c.JS_FreeValue(f.context.?, raw);
    try std.testing.expect(c.JS_IsException(raw));
    try std.testing.expect(c.JS_PiIsExecutionTerminating(f.runtime.?));
    try std.testing.expectEqual(@as(usize, 1), probe.calls);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    c.JS_PiCancelExecutionTermination(f.runtime.?);
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
}

test "VM termination Cancel during native unwind preserves an explicit abrupt result but permits an actual normal return" {
    for ([_]Mode{ .cancel_abrupt, .cancel_success }) |mode| {
        var probe: Probe = .{};
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        try probe.init(&f); defer probe.disable(); try f.install();
        const function = try f.eval(
            \\globalThis.progress={caught:false,finalized:false,after:false};
            \\(function(){try{act();progress.after=true}catch(e){progress.caught=true}finally{progress.finalized=true}})
        ); defer c.JS_FreeValue(f.context.?, function);
        const progress = try f.eval("progress"); defer c.JS_FreeValue(f.context.?, progress);
        probe.mode = mode;
        const raw = c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null);
        defer c.JS_FreeValue(f.context.?, raw);
        try std.testing.expect(!c.JS_PiIsExecutionTerminating(f.runtime.?));
        try std.testing.expectEqual(@as(u64, 1), c.JS_PiExecutionTerminationGeneration(f.runtime.?));
        if (mode == .cancel_abrupt) {
            try std.testing.expect(c.JS_IsException(raw));
            const pending = try f.pending(); defer c.JS_FreeValue(f.context.?, pending);
            try std.testing.expect(c.JS_PiIsExecutionTermination(pending));
            try std.testing.expectEqual(@as(c_int, -1), c.JS_PiNativePendingPriority(f.runtime.?, pending));
            try f.ownBool(progress, "caught", false); try f.ownBool(progress, "finalized", false);
            try f.ownBool(progress, "after", false);
        } else {
            try std.testing.expect(!c.JS_IsException(raw) and !c.JS_HasException(f.context.?));
            try f.ownBool(progress, "caught", false); try f.ownBool(progress, "finalized", true);
            try f.ownBool(progress, "after", true);
        }
    }
}

test "VM termination source and native async initial failures do not reject their real Promise with the private token" {
    for ([_]bool{ false, true }) |native| {
        var probe: Probe = .{};
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        try probe.init(&f); defer probe.disable(); try f.install();
        const function = if (native)
            try f.checked(c.JS_PiNewNativeAsyncFunction(f.context.?, asyncTerminate,
                c.pi_js_undefined(), c.pi_js_undefined(), 0, "actualTerminationAsync", 0))
        else try f.eval("(async function(){act();return 9})");
        defer c.JS_FreeValue(f.context.?, function);
        probe.mode = .terminate; probe.retain_init = true; probe.installHook(&f);
        const raw = c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null);
        defer c.JS_FreeValue(f.context.?, raw);
        try std.testing.expect(c.JS_IsException(raw));
        try std.testing.expect(c.JS_PiIsExecutionTerminating(f.runtime.?));
        try std.testing.expect(c.JS_IsPromise(probe.init_promise));
        try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.context.?, probe.init_promise));
        try std.testing.expectEqual(@as(usize, if (native) 1 else 0), probe.async_starts);
        try std.testing.expectEqual(@as(usize, if (native) 0 else 1), probe.calls);
        c.JS_PiCancelExecutionTermination(f.runtime.?);
    }
}

test "VM termination the direct existing-Promise operation never accepts an actual private completion as fulfillment or rejection DATA" {
    for ([_]bool{ false, true }) |reject| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        const promise = try f.checked(c.JS_PiNewPendingPromise(f.context.?));
        defer c.JS_FreeValue(f.context.?, promise);
        c.JS_PiRequestExecutionTermination(f.runtime.?); _ = c.JS_PiCheckExecutionTermination(f.context.?);
        const token = try f.pending(); defer c.JS_FreeValue(f.context.?, token);
        const raw = c.JS_PiSettlePromise(f.context.?, promise, token, reject);
        defer c.JS_FreeValue(f.context.?, raw);
        try std.testing.expect(c.JS_IsException(raw));
        try std.testing.expect(c.JS_PiIsExecutionTerminating(f.runtime.?));
        try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.context.?, promise));
        c.JS_PiCancelExecutionTermination(f.runtime.?);
    }
}

test "VM termination flagged returned Error DATA and the unchanged generic interrupt remain distinct from the private event" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try probe.init(&f); defer probe.disable(); try probe.reason(&f, 0, true);
    const callback = try f.api(); defer c.JS_FreeValue(f.context.?, callback);
    probe.return_value = c.JS_DupValue(f.context.?, probe.reasons[0]);
    const data = c.JS_Call(f.context.?, callback, c.pi_js_undefined(), 0, null);
    defer c.JS_FreeValue(f.context.?, data);
    try std.testing.expect(c.JS_IsStrictEqual(f.context.?, probe.reasons[0], data));
    try std.testing.expect(!c.JS_HasException(f.context.?) and !c.JS_PiIsExecutionTerminating(f.runtime.?));
    c.JS_SetInterruptHandler(f.runtime.?, interrupt, &probe);
    const raw = f.evalRaw("for(let i=0;i<100000;i++){let j=i+1;}");
    defer c.JS_FreeValue(f.context.?, raw);
    c.JS_SetInterruptHandler(f.runtime.?, null, null);
    try std.testing.expect(c.JS_IsException(raw));
    try std.testing.expect(probe.interrupt_calls > 0);
    const pending = try f.pending(); defer c.JS_FreeValue(f.context.?, pending);
    try std.testing.expect(c.JS_IsError(pending) and c.JS_IsUncatchableError(pending));
    try std.testing.expect(!c.JS_PiIsExecutionTermination(pending));
    try std.testing.expectEqual(@as(u64, 0), c.JS_PiExecutionTerminationGeneration(f.runtime.?));
}

test "VM termination runtime event is shared across genuine contexts and can be requested by a native worker" {
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    const foreign = c.JS_NewContext(f.runtime.?) orelse return error.OutOfMemory;
    defer c.JS_FreeContext(foreign);
    const worker = try std.Thread.spawn(.{}, requestWorker, .{f.runtime.?});
    worker.join();
    try std.testing.expect(!c.JS_HasException(foreign));
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiCheckExecutionTermination(foreign));
    try std.testing.expect(c.JS_HasException(f.context.?) and c.JS_PiIsExecutionTerminating(f.runtime.?));
    const token = c.JS_GetException(f.context.?);
    try std.testing.expect(c.JS_PiIsExecutionTermination(token));
    _ = c.JS_Throw(foreign, token);
    c.JS_PiCancelExecutionTermination(c.JS_GetRuntime(foreign));
    try std.testing.expect(!c.JS_HasException(f.context.?));
}

test "VM termination native reaction BEFORE and AFTER select the actual derived Promise for pending and settled registration" {
    for ([_]bool{ false, true }) |settled_first| {
        var probe: Probe = .{};
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        try probe.init(&f); defer probe.disable(); try f.install();
        const source = try f.checked(c.JS_PiNewPendingPromise(f.context.?));
        defer c.JS_FreeValue(f.context.?, source);
        try f.set("source", source);
        if (settled_first) {
            const status = try f.checked(c.JS_PiSettlePromise(f.context.?, source, c.JS_NewInt32(f.context.?, 7), false));
            c.JS_FreeValue(f.context.?, status);
        }
        f.frame(42);
        const derived = try f.eval("source.then(act)"); defer c.JS_FreeValue(f.context.?, derived);
        if (!settled_first) {
            const status = try f.checked(c.JS_PiSettlePromise(f.context.?, source, c.JS_NewInt32(f.context.?, 7), false));
            c.JS_FreeValue(f.context.?, status);
        }
        probe.installHook(&f);
        try f.step(1);
        try probe.hooksAre(&f, derived, 0, 1);
        try std.testing.expectEqual(@as(i32, 42), probe.hooks[0].frame);
        try std.testing.expectEqual(@as(i32, 42), probe.hooks[1].frame);
        try std.testing.expectEqual(c.JS_PROMISE_PENDING, probe.hooks[0].state);
        try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, probe.hooks[1].state);
        try std.testing.expectEqual(@as(i32, -1), Probe.id(f.context.?));
        try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
    }
}

test "VM termination thenable native hooks surround the actual resolve or rejection builtin and its full cleanup" {
    for ([_]bool{ false, true }) |throws| {
        var probe: Probe = .{};
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        try probe.init(&f); defer probe.disable(); try f.install();
        const promise = try f.eval(if (throws)
            "Promise.resolve({then(){act();throw Error('ordinary thenable')}})"
        else "Promise.resolve({then(resolve){act();resolve(9)}})");
        defer c.JS_FreeValue(f.context.?, promise);
        probe.installHook(&f);
        try f.step(1);
        try probe.hooksAre(&f, promise, 0, 1);
        try std.testing.expectEqual(if (throws) c.JS_PROMISE_REJECTED else c.JS_PROMISE_FULFILLED,
            probe.hooks[1].state);
        try std.testing.expect(!c.JS_HasException(f.context.?));
        try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
    }
}

test "VM termination ignored Await and actual non-Promise species capabilities do not invent native Promise hooks" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try probe.init(&f); defer probe.disable();
    const awaited = try f.eval("(async()=>{await 1;return 2})()");
    defer c.JS_FreeValue(f.context.?, awaited);
    probe.installHook(&f);
    try f.step(1);
    try std.testing.expectEqual(@as(usize, 0), probe.hook_count);
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(f.context.?, awaited));
    const custom = try f.eval(
        \\globalThis.progress={resolved:false,rejected:false};
        \\function Foreign(executor){executor(()=>{progress.resolved=true},()=>{progress.rejected=true});return {}}
        \\let base=Promise.resolve(3);base.constructor={[Symbol.species]:Foreign};base.then(v=>v+1)
    ); defer c.JS_FreeValue(f.context.?, custom);
    try std.testing.expect(!c.JS_IsPromise(custom));
    try f.step(1);
    try std.testing.expectEqual(@as(usize, 0), probe.hook_count);
    try f.run("if(!progress.resolved||progress.rejected)throw Error('actual custom capability')");
    try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
}

test "VM termination ordinary failed jobs retire their own roots and retain continuation until a later successful job clears it" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try probe.init(&f); defer probe.disable(); try probe.reason(&f, 0, false);
    f.frame(11);
    const marker = try probe.holder(&f, 0, .none);
    try f.enqueue(failJob, &.{marker}); c.JS_FreeValue(f.context.?, marker);
    c.JS_PiSetContinuationPreservedEmbedderData(f.runtime.?, c.pi_js_undefined());
    try f.enqueue(recordJob, &.{});
    f.frame(77);
    var batch = Batch.enter(&f); defer batch.restore();
    try f.step(-1);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try std.testing.expectEqual(@as(i32, 11), Probe.id(f.context.?));
    try std.testing.expect(!c.JS_PiIsExecutionTerminating(f.runtime.?));
    {
        const reason = try f.pending(); defer c.JS_FreeValue(f.context.?, reason);
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?, probe.reasons[0], reason));
    }
    try f.step(1);
    try std.testing.expectEqual(@as(i32, 11), probe.current_at_job);
    try std.testing.expectEqual(@as(i32, -1), Probe.id(f.context.?));
    batch.restore();
    try std.testing.expectEqual(@as(i32, 77), Probe.id(f.context.?));
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiFinishTerminatedMicrotasks(f.runtime.?));
}

test "VM termination reaction holds its real Promise until outer restore queue detachment and one deferred native AFTER" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try probe.init(&f); defer probe.disable();
    f.frame(33);
    var promise = try setupReaction(&f, &probe, .terminate);
    defer c.JS_FreeValue(f.context.?, promise);
    try attachMarker(&f, &probe, promise, 0);
    probe.expected_hook_promise = promise; // Hook compares only while the selected job owns this target.
    const queued = try probe.holder(&f, 1, .finish_enqueue);
    try f.enqueue(recordJob, &.{queued}); c.JS_FreeValue(f.context.?, queued);
    probe.installHook(&f);
    f.frame(77);
    var batch = Batch.enter(&f); defer batch.restore();
    c.JS_FreeValue(f.context.?, promise); promise = c.pi_js_undefined();
    try f.step(c.JS_PI_JOB_TERMINATED);
    try std.testing.expectEqual(@as(usize, 1), probe.hook_count);
    try std.testing.expectEqual(@as(usize, 1), probe.calls);
    try std.testing.expectEqual(@as(i32, 33), Probe.id(f.context.?));
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual(@as(usize, 0), probe.counts[0]);
    try std.testing.expectEqual(@as(usize, 0), probe.counts[1]);
    batch.restore();
    try std.testing.expect(c.JS_PiIsExecutionTerminating(f.runtime.?));
    try std.testing.expectEqual(@as(c_int, 1), c.JS_PiFinishTerminatedMicrotasks(f.runtime.?));
    probe.expected_hook_promise = c.pi_js_undefined();
    try std.testing.expectEqual(@as(usize, 2), probe.hook_count);
    try std.testing.expect(probe.hooks[0].matched_expected and probe.hooks[1].matched_expected);
    try std.testing.expectEqual(@as(c.JSPromiseHookType, c.JS_PROMISE_HOOK_BEFORE), probe.hooks[0].kind);
    try std.testing.expectEqual(@as(c.JSPromiseHookType, c.JS_PROMISE_HOOK_AFTER), probe.hooks[1].kind);
    try std.testing.expectEqual(@as(usize, 0), probe.hooks[0].calls);
    try std.testing.expectEqual(@as(usize, 1), probe.hooks[1].calls);
    try std.testing.expectEqual(@as(i32, 77), probe.hooks[1].frame);
    try std.testing.expect(probe.hooks[1].terminating);
    try std.testing.expectEqual(@as(usize, 1), probe.hooks[1].second_retired);
    try std.testing.expectEqual(@as(usize, 0), probe.hooks[1].first_retired);
    try std.testing.expect(probe.hooks[1].queued);
    try std.testing.expectEqual(@as(c_int, 0), probe.nested_finish);
    try std.testing.expect(!probe.queued_before_enqueue);
    try std.testing.expectEqual(@as(c_int, 0), probe.enqueue_status);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[1]);
    try std.testing.expectEqual(@as(usize, 0), probe.jobs);
    c.JS_PiCancelExecutionTermination(f.runtime.?);
    try f.step(1); // Only the new cleanup enqueue survives the detached old list.
    try std.testing.expectEqual(@as(usize, 1), probe.jobs);
    try std.testing.expectEqual(@as(i32, 77), probe.current_at_job);
    try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
}

test "VM termination thenable failure retains its target as pending and defers exactly its native AFTER" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try probe.init(&f); defer probe.disable(); try f.install();
    probe.mode = .terminate;
    const promise = try f.eval("Promise.resolve({then(){act()}})");
    defer c.JS_FreeValue(f.context.?, promise);
    probe.installHook(&f);
    try f.step(c.JS_PI_JOB_TERMINATED);
    try std.testing.expectEqual(@as(usize, 1), probe.hook_count);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.context.?, promise));
    try std.testing.expectEqual(@as(c_int, 1), c.JS_PiFinishTerminatedMicrotasks(f.runtime.?));
    try probe.hooksAre(&f, promise, 0, 1);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(f.context.?, promise));
    try std.testing.expect(c.JS_PiIsExecutionTerminating(f.runtime.?));
    c.JS_PiCancelExecutionTermination(f.runtime.?);
}

test "VM termination a payload finalizer cannot finish its active job before Execute returns" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try probe.init(&f); defer probe.disable(); probe.installHook(&f);
    const current = try probe.holder(&f, 0, .service_finish);
    try f.enqueue(recordJob, &.{current}); c.JS_FreeValue(f.context.?, current);
    const queued = try probe.holder(&f, 1, .none);
    try f.enqueue(recordJob, &.{queued}); c.JS_FreeValue(f.context.?, queued);
    f.frame(87);
    var batch = Batch.enter(&f); defer batch.restore();
    try f.step(c.JS_PI_JOB_TERMINATED);
    try std.testing.expectEqual(@as(c_int, 0), probe.nested_finish);
    try std.testing.expectEqual(@as(usize, 1), probe.jobs);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try std.testing.expectEqual(@as(usize, 0), probe.counts[1]);
    try std.testing.expectEqual(@as(usize, 0), probe.hook_count);
    batch.restore();
    try std.testing.expectEqual(@as(c_int, 1), c.JS_PiFinishTerminatedMicrotasks(f.runtime.?));
    try std.testing.expectEqual(@as(usize, 1), probe.counts[1]);
    try std.testing.expectEqual(@as(usize, 0), probe.hook_count);
    try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
    c.JS_PiCancelExecutionTermination(f.runtime.?);
}

test "VM termination Cancel before the checkpoint finish releases held job owners but preserves the live queue and skips deferred AFTER" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try probe.init(&f); defer probe.disable();
    var promise = try setupReaction(&f, &probe, .terminate);
    defer c.JS_FreeValue(f.context.?, promise);
    try attachMarker(&f, &probe, promise, 0);
    const queued = try probe.holder(&f, 1, .none);
    try f.enqueue(recordJob, &.{queued}); c.JS_FreeValue(f.context.?, queued);
    probe.installHook(&f);
    c.JS_FreeValue(f.context.?, promise); promise = c.pi_js_undefined();
    try f.step(c.JS_PI_JOB_TERMINATED);
    c.JS_PiCancelExecutionTermination(f.runtime.?);
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiFinishTerminatedMicrotasks(f.runtime.?));
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try std.testing.expectEqual(@as(usize, 0), probe.counts[1]);
    try std.testing.expectEqual(@as(usize, 1), probe.hook_count);
    try std.testing.expect(c.JS_IsJobPending(f.runtime.?));
    try f.step(1);
    try std.testing.expectEqual(@as(usize, 1), probe.jobs);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[1]);
    try std.testing.expect(!c.JS_HasException(f.context.?));
}

test "VM termination real cancellation during detached queue retirement permits a later actual ordinary or fatal reason" {
    for ([_]bool{ false, true }) |fatal| {
        var probe: Probe = .{};
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        try probe.init(&f); defer probe.disable(); try probe.reason(&f, 0, fatal);
        try f.enqueue(terminateJob, &.{});
        const queued = try probe.holder(&f, 0, .republish_cancel_reason0);
        try f.enqueue(recordJob, &.{queued}); c.JS_FreeValue(f.context.?, queued);
        try f.step(c.JS_PI_JOB_TERMINATED);
        try std.testing.expectEqual(@as(c_int, 1), c.JS_PiFinishTerminatedMicrotasks(f.runtime.?));
        try std.testing.expect(!c.JS_PiIsExecutionTerminating(f.runtime.?));
        const reason = try f.pending(); defer c.JS_FreeValue(f.context.?, reason);
        try std.testing.expect(c.JS_IsStrictEqual(f.context.?, probe.reasons[0], reason));
        try std.testing.expectEqual(fatal, c.JS_IsUncatchableError(reason));
        try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
        try std.testing.expectEqual(@as(usize, 1), probe.jobs);
        try std.testing.expect(!c.JS_IsJobPending(f.runtime.?));
        try std.testing.expectEqual(@as(u64, 1), c.JS_PiExecutionTerminationGeneration(f.runtime.?));
    }
}

test "VM termination BEFORE or AFTER producers retain one matching native AFTER without rerunning the reaction" {
    for ([_]bool{ true, false }) |at_before| {
        var probe: Probe = .{};
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        try probe.init(&f); defer probe.disable();
        const promise = try setupReaction(&f, &probe, .value);
        defer c.JS_FreeValue(f.context.?, promise);
        if (at_before) probe.before_action = .service else probe.after_action = .service;
        probe.installHook(&f);
        try f.step(c.JS_PI_JOB_TERMINATED);
        try std.testing.expectEqual(@as(usize, if (at_before) 1 else 2), probe.hook_count);
        try std.testing.expectEqual(@as(usize, if (at_before) 0 else 1), probe.calls);
        try std.testing.expectEqual(@as(c_int, 1), c.JS_PiFinishTerminatedMicrotasks(f.runtime.?));
        try probe.hooksAre(&f, promise, 0, if (at_before) 0 else 1);
        try std.testing.expectEqual(if (at_before) c.JS_PROMISE_PENDING else c.JS_PROMISE_FULFILLED,
            c.JS_PromiseState(f.context.?, promise));
        c.JS_PiCancelExecutionTermination(f.runtime.?);
    }
}

test "VM termination Disallow leaves a nonempty queue intact while a real request blocks it before any job or hook" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try probe.init(&f); defer probe.disable(); probe.installHook(&f);
    const queued = try probe.holder(&f, 0, .none);
    try f.enqueue(recordJob, &.{queued}); c.JS_FreeValue(f.context.?, queued);
    const allowed = c.JS_PiExchangeJavascriptExecutionAllowed(f.runtime.?, false);
    defer _ = c.JS_PiExchangeJavascriptExecutionAllowed(f.runtime.?, allowed);
    try f.step(0);
    try std.testing.expect(c.JS_IsJobPending(f.runtime.?));
    try std.testing.expectEqual(@as(usize, 0), probe.counts[0]);
    try std.testing.expect(!c.JS_HasException(f.context.?));
    c.JS_PiRequestExecutionTermination(f.runtime.?);
    try f.step(c.JS_PI_JOB_TERMINATED);
    try std.testing.expectEqual(@as(usize, 0), probe.jobs);
    try std.testing.expectEqual(@as(usize, 0), probe.hook_count);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_PiFinishTerminatedMicrotasks(f.runtime.?));
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try std.testing.expectEqual(@as(usize, 0), probe.hook_count);
    c.JS_PiCancelExecutionTermination(f.runtime.?);
}

test "VM termination the held active context survives caller release and GC until native checkpoint retirement" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try probe.init(&f); defer probe.disable();
    var foreign: ?*c.JSContext = c.JS_NewContext(f.runtime.?) orelse return error.OutOfMemory;
    defer if (foreign) |context| c.JS_FreeContext(context);
    c.JS_SetContextOpaque(foreign.?, &probe);
    const global_object = try f.checked(c.JS_GetGlobalObject(foreign.?));
    const marker = try probe.holder(&f, 0, .none);
    const status = c.JS_DefinePropertyValueStr(foreign.?, global_object, "actualContextMarker",
        marker, c.JS_PROP_C_W_E);
    c.JS_FreeValue(foreign.?, global_object);
    try std.testing.expect(status >= 0);
    try std.testing.expectEqual(@as(c_int, 0), c.JS_EnqueueJob(foreign.?, terminateJob, 0, null));
    var actual_context: ?*c.JSContext = null;
    try std.testing.expectEqual(@as(c_int, c.JS_PI_JOB_TERMINATED),
        c.JS_ExecutePendingJob(f.runtime.?, &actual_context));
    try std.testing.expect(actual_context == foreign.?);
    c.JS_FreeContext(foreign.?); foreign = null;
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual(@as(usize, 0), probe.counts[0]);
    try std.testing.expectEqual(@as(c_int, 1), c.JS_PiFinishTerminatedMicrotasks(f.runtime.?));
    c.JS_RunGC(f.runtime.?);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    c.JS_PiCancelExecutionTermination(f.runtime.?);
}

test "VM termination constructor and suspended generator entries are blocked before their real bodies and resume after cancellation" {
    for ([_]bool{ false, true }) |generator| {
        var f: Fixture = .{}; try f.init(); defer f.deinit();
        const function = try f.eval(if (generator)
            "globalThis.progress={entered:false};(function*(){progress.entered=true;yield 3})"
        else "globalThis.progress={entered:false};(function Actual(){progress.entered=true})");
        defer c.JS_FreeValue(f.context.?, function);
        const progress = try f.eval("progress"); defer c.JS_FreeValue(f.context.?, progress);
        var iterator = c.pi_js_undefined(); defer c.JS_FreeValue(f.context.?, iterator);
        var next = c.pi_js_undefined(); defer c.JS_FreeValue(f.context.?, next);
        if (generator) {
            iterator = try f.checked(c.JS_Call(f.context.?, function, c.pi_js_undefined(), 0, null));
            next = try f.checked(c.JS_GetPropertyStr(f.context.?, iterator, "next"));
        }
        c.JS_PiRequestExecutionTermination(f.runtime.?);
        const raw = if (generator) c.JS_Call(f.context.?, next, iterator, 0, null)
            else c.JS_CallConstructor(f.context.?, function, 0, null);
        defer c.JS_FreeValue(f.context.?, raw);
        try std.testing.expect(c.JS_IsException(raw));
        try f.ownBool(progress, "entered", false);
        try std.testing.expect(c.JS_PiIsExecutionTerminating(f.runtime.?));
        c.JS_PiCancelExecutionTermination(f.runtime.?);
        const resumed = try f.checked(if (generator) c.JS_Call(f.context.?, next, iterator, 0, null)
            else c.JS_CallConstructor(f.context.?, function, 0, null));
        defer c.JS_FreeValue(f.context.?, resumed);
        try f.ownBool(progress, "entered", true);
    }
}

test "VM termination runtime teardown retires held and queued native owners without deferred Promise hooks" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try probe.init(&f); defer probe.disable();
    var promise = try setupReaction(&f, &probe, .terminate);
    defer if (f.context) |context| c.JS_FreeValue(context, promise);
    try attachMarker(&f, &probe, promise, 0);
    const queued = try probe.holder(&f, 1, .none);
    try f.enqueue(recordJob, &.{queued}); c.JS_FreeValue(f.context.?, queued);
    probe.installHook(&f);
    c.JS_FreeValue(f.context.?, promise); promise = c.pi_js_undefined();
    try f.step(c.JS_PI_JOB_TERMINATED);
    try std.testing.expectEqual(@as(usize, 1), probe.hook_count);
    // Exercise actual JS_FreeRuntime's separate no-hook drain, not Finish.
    probe.enabled = false;
    c.JS_SetPromiseHook(f.runtime.?, null, null);
    c.JS_SetContextOpaque(f.context.?, null);
    probe.context = null;
    const context = f.context.?; f.context = null; c.JS_FreeContext(context);
    const runtime = f.runtime.?; f.runtime = null; c.JS_FreeRuntime(runtime);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[0]);
    try std.testing.expectEqual(@as(usize, 1), probe.counts[1]);
    try std.testing.expectEqual(@as(usize, 1), probe.hook_count);
}

fn cancelledJob(context: ?*c.JSContext, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const ctx = context orelse return c.pi_js_exception();
    const probe = Probe.from(ctx) orelse return c.pi_js_exception();
    probe.jobs += 1;
    c.JS_PiRequestExecutionTermination(c.JS_GetRuntime(ctx));
    _ = c.JS_PiCheckExecutionTermination(ctx);
    c.JS_PiCancelExecutionTermination(c.JS_GetRuntime(ctx));
    return c.JS_PiNativeTerminationResult();
}
test "VM termination a cancelled job returns native abrupt status until the genuine checkpoint acknowledges its inactive completion" {
    var probe: Probe = .{};
    var f: Fixture = .{}; try f.init(); defer f.deinit();
    try probe.init(&f); defer probe.disable(); probe.installHook(&f);
    try f.enqueue(cancelledJob, &.{});
    try f.enqueue(recordJob, &.{});
    try f.step(c.JS_PI_JOB_TERMINATED);
    try std.testing.expect(!c.JS_PiIsExecutionTerminating(f.runtime.?));
    const first = try f.pending();
    try std.testing.expect(c.JS_PiIsExecutionTermination(first));
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiNativePendingPriority(f.runtime.?, first));
    _ = c.JS_Throw(f.context.?, first);
    try std.testing.expectEqual(@as(c_int, 0), c.JS_PiFinishTerminatedMicrotasks(f.runtime.?));
    try std.testing.expect(c.JS_IsJobPending(f.runtime.?));
    // The actual caller's TryRunMicrotasks boundary acknowledges only this
    // inactive private completion. A real ordinary/fatal replacement is not DATA
    // and would have to remain published for its original reporting owner.
    const acknowledged = try f.pending();
    try std.testing.expect(c.JS_PiIsExecutionTermination(acknowledged));
    c.JS_FreeValue(f.context.?, acknowledged);
    try std.testing.expect(!c.JS_HasException(f.context.?));
    try f.step(1);
    try std.testing.expectEqual(@as(usize, 2), probe.jobs);
    try std.testing.expectEqual(@as(usize, 0), probe.hook_count);
}
