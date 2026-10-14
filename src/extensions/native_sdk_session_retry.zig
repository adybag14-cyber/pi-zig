//! Ordinary session recovery omission, retry events and abortable backoff.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const flow = @import("native_agent_async.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
const Method = enum(c_int) { _summarizationRetryCallbacks, _finishCancelledRetry, _prepareRetry, _omitRecoveryAttempt };
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    inline for (std.meta.fields(Method)) |field| {
        const function = try engine.checked(c.pi_js_function_magic(engine.context, dispatch, field.name, if (field.value == 1) 0 else 1, field.value));
        defer engine.freeValue(function);
        if (field.value == 2) {
            const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
            defer engine.freeValue(parent);
            if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
        }
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
fn dispatch(context: ?*c.JSContext, session: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const first = if (argc > 0) argv[0] else c.pi_js_undefined();
    const second = if (argc > 1) argv[1] else c.pi_js_undefined();
    return run(engine, session, @enumFromInt(magic), first, second) catch |err| sdk.fail(engine, err);
}
fn run(engine: *em.Engine, session: c.JSValue, method: Method, first: c.JSValue, second: c.JSValue) !c.JSValue {
    switch (method) {
        ._prepareRetry => return prepare(engine, session, first),
        ._summarizationRetryCallbacks => return callbacks(engine, session, first),
        ._finishCancelledRetry => try finishCancelled(engine, session),
        ._omitRecoveryAttempt => try omit(engine, session, first, second),
    }
    return c.pi_js_undefined();
}
fn callbacks(engine: *em.Engine, session: c.JSValue, source: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    var roots = [_]c.JSValue{ session, source };
    inline for (.{ "onRetryScheduled", "onRetryAttemptStart", "onRetryFinished" }, 0..) |name, index| try scope.put(result, name, try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, emitCallback, name, if (index == 0) 4 else 0, index, roots.len, &roots))));
    return c.JS_DupValue(engine.context, result);
}
fn emitCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    emitCallbackValue(engine, roots[0], roots[1], magic, if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn emitCallbackValue(engine: *em.Engine, session: c.JSValue, source: c.JSValue, magic: c_int, args: []const c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const emit = try scope.get(session, "_emit");
    const event = try scope.object();
    try scope.put(event, "type", try scope.text(switch (magic) {
        0 => "summarization_retry_scheduled",
        1 => "summarization_retry_attempt_start",
        else => "summarization_retry_finished",
    }));
    if (magic == 0) {
        inline for (.{ "attempt", "maxAttempts", "delayMs", "errorMessage" }, 0..) |name, index| try scope.put(event, name, if (args.len > index) args[index] else c.pi_js_undefined());
    } else if (magic == 1) try js.spreadInto(engine, event, source);
    _ = try scope.call(emit, session, &.{event});
}
fn finishCancelled(engine: *em.Engine, session: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.equal(try scope.get(session, "_retryAttempt"), c.JS_NewInt32(engine.context, 0))) return;
    const attempt = try scope.get(session, "_retryAttempt");
    try scope.set(session, "_retryAttempt", c.JS_NewInt32(engine.context, 0));
    const emit = try scope.get(session, "_emit");
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("auto_retry_end"));
    try scope.put(event, "success", c.pi_js_bool(engine.context, 0));
    try scope.put(event, "attempt", attempt);
    try scope.put(event, "finalError", try scope.text("Retry cancelled"));
    _ = try scope.call(emit, session, &.{event});
}
fn prepare(engine: *em.Engine, session: c.JSValue, message: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, session);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    initial(engine, pending.owner, message) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn initial(engine: *em.Engine, owner: c.JSValue, message: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "generation", try scope.own(try engine.checked(c.JS_NewBigUint64(engine.context, engine.native_allocation_generation))));
    const session = try scope.get(owner, "agent");
    const settings = try scope.invoke(try scope.get(session, "settingsManager"), "getRetrySettings", &.{});
    if (!scope.truthy(try scope.get(settings, "enabled"))) return flow.settle(engine, owner, false, c.pi_js_bool(engine.context, 0));
    const count = try scope.get(session, "_retryAttempt");
    try scope.set(session, "_retryAttempt", try scope.own(try engine.checked(c.JS_PiIncrement(engine.context, count))));
    if (try arithmetic.compare(engine, .greater, try scope.get(session, "_retryAttempt"), try scope.get(settings, "maxRetries"))) {
        try scope.set(session, "_retryAttempt", try scope.own(try engine.checked(c.JS_PiDecrement(engine.context, try scope.get(session, "_retryAttempt")))));
        return flow.settle(engine, owner, false, c.pi_js_bool(engine.context, 0));
    }
    const delay = try scope.own(try @import("native_durable_retry.zig").delay(engine, settings, try scope.get(session, "_retryAttempt")));
    const emit = try scope.get(session, "_emit");
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("auto_retry_start"));
    try scope.put(event, "attempt", try scope.get(session, "_retryAttempt"));
    try scope.put(event, "maxAttempts", try scope.get(settings, "maxRetries"));
    try scope.put(event, "delayMs", delay);
    const error_message = try scope.get(message, "errorMessage");
    try scope.put(event, "errorMessage", if (scope.truthy(error_message)) error_message else try scope.text("Unknown error"));
    _ = try scope.call(emit, session, &.{event});
    _ = try scope.invoke(session, "_omitRecoveryAttempt", &.{message});
    try scope.set(session, "_retryAbortController", try scope.own(try js.builtin(engine, "AbortController", &.{})));
    beginSleep(engine, owner, delay) catch |err| {
        const raw = flow.reason(engine, err);
        defer engine.freeValue(raw);
        return slept(engine, owner, raw, true, 0);
    };
}
fn beginSleep(engine: *em.Engine, owner: c.JSValue, delay: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    const signal = try scope.get(try scope.get(session, "_retryAbortController"), "signal");
    const pending = try scope.own(try @import("native_sdk_sleep.zig").sleep(engine, delay, signal));
    try flow.wait(slept, engine, owner, pending, 0);
}
fn slept(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, failed: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const session = try scope.get(owner, "agent");
    if (failed) {
        var generation: u64 = 0;
        if (c.JS_ToBigUint64(engine.context, &generation, try scope.get(owner, "generation")) < 0) return js.capture(engine);
        const tagged = c.pi_js_native_allocation_error_generation(value);
        const distance = tagged -% generation;
        if (tagged != 0 and distance != 0 and distance <= engine.native_allocation_generation -% generation) {
            try scope.set(session, "_retryAbortController", c.pi_js_undefined());
            return flow.settle(engine, owner, true, value);
        }
        _ = scope.invoke(session, "_finishCancelledRetry", &.{}) catch |err| {
            const raw = flow.reason(engine, err);
            defer engine.freeValue(raw);
            try scope.set(session, "_retryAbortController", c.pi_js_undefined());
            return flow.settle(engine, owner, true, raw);
        };
    }
    try scope.set(session, "_retryAbortController", c.pi_js_undefined());
    try flow.settle(engine, owner, false, c.pi_js_bool(engine.context, @intFromBool(!failed)));
}
fn omit(engine: *em.Engine, session: c.JSValue, message: c.JSValue, raw_results: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const results = if (c.JS_IsUndefined(raw_results)) try scope.array() else raw_results;
    const targets = try scope.array();
    try scope.index(targets, 0, message);
    const symbol = try scope.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context)));
    var result_iterator = try js.Iterator.init(engine, results, symbol);
    defer result_iterator.deinit();
    errdefer result_iterator.closePreserving();
    var index: u32 = 1;
    while (try result_iterator.next()) |item| {
        defer engine.freeValue(item);
        try scope.index(targets, index, item);
        index += 1;
    }
    var map_roots = [_]c.JSValue{session};
    const mapper = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, targetId, "", 1, 0, map_roots.len, &map_roots)));
    const ids = try scope.invoke(targets, "map", &.{mapper});
    var check_roots = [_]c.JSValue{ session, ids };
    const predicate = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, unresolvedTarget, "", 2, 0, check_roots.len, &check_roots)));
    if (scope.truthy(try scope.invoke(targets, "some", &.{predicate}))) {
        const constructor = try scope.global("Error");
        const reason = try scope.text("Cannot persist recovery omission because a projected message has no source entry");
        const error_value = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, @constCast(&[_]c.JSValue{reason}))));
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, error_value)));
    }
    var id_iterator = try js.Iterator.init(engine, ids, symbol);
    defer id_iterator.deinit();
    errdefer id_iterator.closePreserving();
    while (try id_iterator.next()) |id| {
        defer engine.freeValue(id);
        if (!scope.truthy(id)) continue;
        var iteration: Scope = .{ .engine = engine };
        defer iteration.deinit();
        const edit = try iteration.invoke(try iteration.get(session, "sessionManager"), "appendContextEdit", &.{ id, c.pi_js_null() });
        const entry = try iteration.invoke(try iteration.get(session, "sessionManager"), "getEntry", &.{edit});
        if (iteration.truthy(entry)) {
            const emit = try iteration.get(session, "_emit");
            const event = try iteration.object();
            try iteration.put(event, "type", try iteration.text("entry_appended"));
            try iteration.put(event, "entry", entry);
            _ = try iteration.call(emit, session, &.{event});
        }
    }
    _ = try scope.invoke(session, "_refreshFinalizedContext", &.{});
}
fn targetId(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return js.invoke(engine, roots[0], "_findPersistedMessageEntryId", &.{if (argc > 0) argv[0] else c.pi_js_undefined()}) catch |err| sdk.fail(engine, err);
}
fn unresolvedTarget(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return unresolved(engine, roots[0], roots[1], if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn unresolved(engine: *em.Engine, session: c.JSValue, ids: c.JSValue, target: c.JSValue, index: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!c.JS_IsUndefined(try scope.own(try js.getKey(engine, ids, index)))) return c.pi_js_bool(engine.context, 0);
    const messages = try scope.get(try scope.get(try scope.get(session, "agent"), "state"), "messages");
    return js.invoke(engine, messages, "includes", &.{target});
}
