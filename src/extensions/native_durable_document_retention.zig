//! VM boundary for Source's document-retention setting. Cache ownership, observer
//! pinning and Session-line eviction use the native index in durable/ separately.
const std = @import("std");
const engine_mod = @import("engine.zig");
const retention = @import("../durable/document_retention.zig");
const durable = @import("native_durable.zig");
const docs = @import("native_durable_documents.zig");
const sdk = @import("native_sdk.zig");
const json = @import("../durable/backend/json.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;

/// Session-owned bookkeeping survives explicit tracker-cache unloads. Captures
/// are marked by the Session class; timer callbacks separately root the Session.
pub const Owner = struct {
    index: ?retention.Index = null,
    session: ?c.JSValue = null,
    clock: ?c.JSValue = null,
    custom_clock: bool = false,
    plain_ms: f64 = retention.default_ms,
    timer: ?c.JSValue = null,
    at: ?f64 = null,
    generation: u32 = 0,
    sweeps: u64 = 0,
    timers_unavailable: bool = false,
    pub fn deinit(self: *Owner, runtime: ?*c.JSRuntime) void {
        if (self.index) |*value| value.deinit();
        inline for (.{ "session", "clock", "timer" }) |name| if (@field(self, name)) |value| c.JS_FreeValueRT(runtime, value);
    }
    pub fn mark(self: *Owner, runtime: ?*c.JSRuntime, marker: ?*const c.JS_MarkFunc) void {
        inline for (.{ "session", "clock", "timer" }) |name| if (@field(self, name)) |value| c.JS_MarkValue(runtime, value, marker);
    }
};

pub fn captureClock(engine: *Engine, supplied: c.JSValue) !c.JSValue {
    if (!c.JS_IsUndefined(supplied)) return c.JS_DupValue(engine.context, supplied);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const date = try sdk.get(engine, global, "Date");
    defer engine.freeValue(date);
    return sdk.get(engine, date, "now");
}
fn index(owner: *durable.State) *retention.Index {
    if (owner.cache_policy.index == null) owner.cache_policy.index = retention.Index.init(owner.engine.gpa);
    return &owner.cache_policy.index.?;
}
fn milliseconds(owner: *durable.State) !f64 {
    if (owner.creation_owner) |harness| {
        const state = @import("native_durable_harness.zig").state(owner.engine, harness) catch return retention.default_ms;
        return if (state.host_settings) |captured| readCapturedSettings(owner.engine, captured) else readSettings(owner.engine, state.options);
    }
    return owner.cache_policy.plain_ms;
}
fn now(owner: *durable.State) f64 {
    const engine = owner.engine;
    if (owner.cache_policy.clock) |callback| {
        const value = c.JS_Call(engine.context, callback, c.pi_js_undefined(), 0, null);
        if (!c.JS_IsException(value)) {
            defer engine.freeValue(value);
            var number: f64 = 0;
            if (c.JS_ToFloat64(engine.context, &number, value) == 0) return number;
        }
        engine.freeValue(c.JS_GetException(engine.context));
    }
    return @floatFromInt(std.Io.Clock.real.now(owner.session.?.io).toMilliseconds());
}
fn globalCall(engine: *Engine, name: [:0]const u8, args: []const c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const function = try sdk.get(engine, global, name);
    defer engine.freeValue(function);
    return engine.checked(c.JS_Call(engine.context, function, c.pi_js_undefined(), @intCast(args.len), if (args.len == 0) null else @constCast(args.ptr)));
}
fn clearTimer(owner: *durable.State) void {
    const timer = owner.cache_policy.timer orelse return;
    owner.cache_policy.timer = null;
    defer owner.engine.freeValue(timer);
    const cleared = globalCall(owner.engine, "clearTimeout", &.{timer}) catch return;
    owner.engine.freeValue(cleared);
}
pub fn stop(owner: *durable.State) void {
    clearTimer(owner);
    owner.cache_policy.at = null;
}
pub fn sizes(engine: *Engine, session: c.JSValue) !c.JSValue {
    const owner = try durable.state(engine, session);
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    const cached: usize = if (owner.document_cache) |value| value.items.items.len else 0;
    const idle: usize = if (owner.cache_policy.index) |value| value.idle.items.len else 0;
    const attached: usize = if (owner.cache_policy.index) |value| value.attached.count() else 0;
    inline for (.{ "cached", "idle", "attached", "sweeps" }, .{ cached, idle, attached, owner.cache_policy.sweeps }) |name, count| try sdk.put(engine, result, name, c.JS_NewFloat64(engine.context, @floatFromInt(count)));
    return result;
}
pub fn touch(owner: *durable.State, address: json.Value, record_id: u64) !void {
    if (owner.closing) return;
    const values = index(owner);
    if (values.isPinned(record_id)) return;
    const stamp = now(owner);
    if (values.lastUse(address)) |since| if (stamp - since < @min(1_000, (try milliseconds(owner)) / 10)) return;
    try values.move(address, record_id, stamp);
    if (owner.cache_policy.at == null or owner.cache_policy.at.? > stamp + (try milliseconds(owner))) try schedule(owner);
}
pub fn drop(owner: *durable.State, address: json.Value) void {
    if (owner.cache_policy.index) |*values| values.drop(address);
}
pub fn clearIdle(owner: *durable.State) void {
    if (owner.cache_policy.index) |*values| values.clearIdle();
}
pub fn pin(owner: *durable.State, address: json.Value, record_id: u64) !void {
    try index(owner).pin(address, record_id);
}
pub fn release(owner: *durable.State, record_id: u64) !void {
    if (owner.cache_policy.index) |*values| if (values.unpin(record_id)) try docs.touchRecord(owner, record_id);
}
/// Only callers that actually own the native Session mutation line may evict.
/// No tracker held by a Transaction can leave before settlement releases it.
pub fn sweepOnLine(owner: *durable.State) !void {
    if (std.Thread.getCurrentId() != owner.owner_thread or owner.session.?.ownerThread.load(.acquire) != std.Thread.getCurrentId()) return error.DocumentSweepOutsideSessionLine;
    return sweepReserved(owner);
}
/// Only the generation/thread/epoch-validated owner settlement handler invokes
/// this while its original worker remains blocked and retains the reserved line.
pub fn sweepReserved(owner: *durable.State) !void {
    if (std.Thread.getCurrentId() != owner.owner_thread or owner.session.?.ownerThread.load(.acquire) == 0) return error.DocumentSweepOutsideReservedLine;
    if (owner.closing) return;
    const stamp = now(owner);
    const duration_ms = try milliseconds(owner);
    const values = index(owner);
    while (values.oldestExpired(stamp, duration_ms)) |oldest| {
        docs.dropCached(owner, oldest.address.value);
        values.drop(oldest.address.value);
    }
    try schedule(owner);
}
pub fn sweepOwnerNow(owner: *durable.State) !bool {
    const Call = struct {
        fn run(raw: ?*anyopaque, _: *@import("../durable/session.zig").Transaction, _: @import("../durable/types.zig").Context) !json.Value {
            const current: *durable.State = @ptrCast(@alignCast(raw.?));
            try sweepOnLine(current);
            return .null;
        }
    };
    var completed = (try owner.session.?.tryRead(Call.run, owner, .{}, .{})) orelse return false;
    completed.deinit();
    return true;
}
fn schedule(owner: *durable.State) !void {
    if (owner.closing) return;
    const values = index(owner);
    if (values.idle.items.len == 0) return;
    const at = values.nextDeadline(try milliseconds(owner)) orelse return;
    if (owner.cache_policy.at) |pending| if (pending <= at) return;
    clearTimer(owner);
    owner.cache_policy.generation +%= 1;
    const generation = c.JS_NewUint32(owner.engine.context, owner.cache_policy.generation);
    defer owner.engine.freeValue(generation);
    var data = [_]c.JSValue{ owner.cache_policy.session.?, generation };
    const callback = try owner.engine.checked(c.JS_NewCFunctionData(owner.engine.context, ready, 0, 0, data.len, &data));
    defer owner.engine.freeValue(callback);
    owner.cache_policy.at = at;
    const delay = at - now(owner);
    if (delay <= 0) {
        const queued = try globalCall(owner.engine, "queueMicrotask", &.{callback});
        owner.engine.freeValue(queued);
        return;
    }
    if (owner.cache_policy.timers_unavailable) {
        owner.cache_policy.at = null;
        return;
    }
    const delay_value = c.JS_NewFloat64(owner.engine.context, if (std.math.isNan(delay)) delay else @min(delay, retention.max_timer_delay_ms));
    defer owner.engine.freeValue(delay_value);
    const timer = try globalCall(owner.engine, "setTimeout", &.{ callback, delay_value });
    errdefer owner.engine.freeValue(timer);
    const unref = try sdk.get(owner.engine, timer, "unref");
    defer owner.engine.freeValue(unref);
    if (!c.JS_IsFunction(owner.engine.context, unref)) {
        owner.cache_policy.timer = timer;
        clearTimer(owner);
        owner.cache_policy.timers_unavailable = true;
        owner.cache_policy.at = null;
        return;
    }
    const unreferenced = try owner.engine.checked(c.JS_Call(owner.engine.context, unref, timer, 0, null));
    owner.engine.freeValue(unreferenced);
    owner.cache_policy.timer = timer;
}
fn ready(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const owner = durable.state(engine, data[0]) catch |err| return durable.reject(engine, err);
    owner.cache_policy.sweeps += 1;
    // A microtask already queued before close still runs, but must not turn the
    // normal close into an unhandled admission error or touch disposed trackers.
    if (owner.closing) return c.pi_js_undefined();
    const callback = engine.checked(c.JS_NewCFunctionData(context, queuedSweep, 0, 0, 2, data)) catch |err| return durable.reject(engine, err);
    defer engine.freeValue(callback);
    const pending = durable.enqueueRead(engine, data[0], callback, c.pi_js_undefined()) catch |err| return durable.reject(engine, err);
    defer engine.freeValue(pending);
    const ignored = engine.checked(c.JS_NewCFunction(context, ignore, "document-sweep-error", 0)) catch |err| return durable.reject(engine, err);
    defer engine.freeValue(ignored);
    const observed = sdk.invoke(engine, pending, "then", &.{ ignored, ignored }) catch |err| return durable.reject(engine, err);
    engine.freeValue(observed);
    return c.pi_js_undefined();
}
fn queuedSweep(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const owner = durable.state(engine, data[0]) catch |err| return durable.reject(engine, err);
    var generation: u32 = 0;
    if (c.JS_ToUint32(context, &generation, data[1]) < 0) return engine.throwCaptured();
    if (owner.cache_policy.generation == generation) {
        owner.cache_policy.at = null;
        if (owner.cache_policy.timer) |timer| engine.freeValue(timer);
        owner.cache_policy.timer = null;
    }
    sweepOnLine(owner) catch |err| return durable.reject(engine, err);
    return c.pi_js_undefined();
}
fn ignore(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}

/// Match typeof value === "number" && value >= 0. In particular, neither
/// boxed numbers nor arbitrary ToPrimitive methods are consulted.
pub fn duration(engine: *Engine, value: c.JSValue) f64 {
    if (!c.JS_IsNumber(value)) return retention.default_ms;
    var number: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &number, value) < 0) {
        engine.freeValue(c.JS_GetException(engine.context));
        return retention.default_ms;
    }
    return retention.duration(number);
}

/// The Harness reads only settings.documentRetentionMs at each cache use.
/// Getter failures select the default without entering Engine.checked, which
/// would replace the operation's captured exception/diagnostic with a cache
/// bookkeeping failure. Call on the VM owner after capturing any original cause.
pub fn readSettings(engine: *Engine, options: c.JSValue) f64 {
    const settings = c.JS_GetPropertyStr(engine.context, options, "settings");
    if (c.JS_IsException(settings)) {
        engine.freeValue(c.JS_GetException(engine.context));
        return retention.default_ms;
    }
    defer engine.freeValue(settings);
    if (c.JS_IsUndefined(settings) or c.JS_IsNull(settings)) return retention.default_ms;
    const selected = c.JS_GetPropertyStr(engine.context, settings, "documentRetentionMs");
    if (c.JS_IsException(selected)) {
        engine.freeValue(c.JS_GetException(engine.context));
        return retention.default_ms;
    }
    defer engine.freeValue(selected);
    return duration(engine, selected);
}
pub fn readCapturedSettings(engine: *Engine, captured: c.JSValue) !f64 {
    // Ordinary bookkeeping failures preserve the operation's captured cause.
    // Trusted fatal reasons are rethrown exactly through the fallible callers.
    // A supplier can reenter native callbacks and replace Engine's capture even
    // though this guard itself uses raw C operations. Detach the prior ownership
    // before running any guest code; ordinary completion restores it by value.
    const previous = engine.captured_exception;
    const previous_message = engine.last_error;
    engine.captured_exception = null;
    engine.last_error = null;
    var restore_previous = true;
    defer {
        if (restore_previous) {
            if (engine.captured_exception) |value| engine.freeValue(value);
            if (engine.last_error) |message| engine.gpa.free(message);
            engine.captured_exception = previous;
            engine.last_error = previous_message;
        } else {
            if (previous) |value| engine.freeValue(value);
            if (previous_message) |message| engine.gpa.free(message);
        }
    }
    errdefer restore_previous = false;
    const call_generation = engine.native_allocation_generation;
    const settings = if (c.JS_IsFunction(engine.context, captured)) c.JS_Call(engine.context, captured, c.pi_js_undefined(), 0, null) else c.JS_DupValue(engine.context, captured);
    if (c.JS_IsException(settings)) {
        try discardOrdinarySettingFailure(engine, call_generation);
        return retention.default_ms;
    }
    defer engine.freeValue(settings);
    if (c.JS_IsUndefined(settings) or c.JS_IsNull(settings)) return retention.default_ms;
    const get_generation = engine.native_allocation_generation;
    const selected = c.JS_GetPropertyStr(engine.context, settings, "documentRetentionMs");
    if (c.JS_IsException(selected)) {
        try discardOrdinarySettingFailure(engine, get_generation);
        return retention.default_ms;
    }
    defer engine.freeValue(selected);
    return duration(engine, selected);
}
fn discardOrdinarySettingFailure(engine: *Engine, generation: u64) !void {
    const reason = c.JS_GetException(engine.context);
    defer engine.freeValue(reason);
    try @import("native_async_body.zig").rethrowRecognizedAllocation(engine, reason, generation);
    if (c.JS_IsUncatchableError(reason)) {
        engine.native_exception_diagnostics_suppressed += 1;
        defer engine.native_exception_diagnostics_suppressed -= 1;
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
        unreachable;
    }
}

test "native document retention reads exact numeric types without coercion" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const values = try engine.eval("globalThis.coercions=0;[undefined,NaN,-1,'0',0,1,Infinity,-Infinity,null,new Number(0),{valueOf(){coercions++;return 0}}]", "retention-values.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(values);
    const expected = [_]f64{ 600_000, 600_000, 600_000, 600_000, 0, 1, std.math.inf(f64), 600_000, 600_000, 600_000, 600_000 };
    for (expected, 0..) |want, item_offset| {
        const value = try engine.checked(c.JS_GetPropertyUint32(engine.context, values, @intCast(item_offset)));
        defer engine.freeValue(value);
        try std.testing.expectEqual(want, duration(engine, value));
    }
    const result = try engine.eval("if(coercions!==0)throw Error('retention coerced user value')", "retention-coercions.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
}

test "native document retention reads current settings and contains getter failures" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const options = try engine.eval("globalThis.retentionValues={value:Infinity,reads:0,failOptions:false,failField:false};({get settings(){retentionValues.reads++;if(retentionValues.failOptions)throw {options:true};return {get documentRetentionMs(){if(retentionValues.failField)throw {field:true};return retentionValues.value}}}})", "retention-settings.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(options);
    try std.testing.expectEqual(std.math.inf(f64), readSettings(engine, options));
    engine.freeValue(try engine.eval("retentionValues.value=0", "retention-change.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expectEqual(@as(f64, 0), readSettings(engine, options));
    engine.freeValue(try engine.eval("retentionValues.failOptions=true", "retention-options-throw.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expectEqual(retention.default_ms, readSettings(engine, options));
    engine.freeValue(try engine.eval("retentionValues.failOptions=false;retentionValues.failField=true", "retention-field-throw.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expectEqual(retention.default_ms, readSettings(engine, options));
    engine.freeValue(try engine.eval("if(retentionValues.reads!==4)throw Error('settings not read once at each use')", "retention-settings-count.js", c.JS_EVAL_TYPE_GLOBAL));
}
