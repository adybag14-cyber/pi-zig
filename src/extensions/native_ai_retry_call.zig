//! Original retryAssistantCall with intrinsic async continuations and the
//! original private abort-error class. Private until differential qualification.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
const Stage = enum(c_int) { produced, finished, scheduled, slept, started, sleepFinished };
pub fn create(engine: *em.Engine) !c.JSValue {
    _ = try @import("native_ai_error_classification.zig").initialize(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const base = try scope.global("Error");
    const prototype = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, try scope.get(base, "prototype"))));
    const box = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    const abort_error = try scope.own(try @import("native_class.zig").constructor(engine, "RetrySleepAbortError", 0, prototype, constructAbort, &.{box}));
    if (c.JS_SetPrototype(engine.context, abort_error, base) < 0) return js.capture(engine);
    try scope.put(box, "constructor", abort_error);
    var roots = [_]c.JSValue{abort_error};
    const result = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "retryAssistantCall", 4, 0, roots.len, &roots)));
    const async_prototype = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
    if (c.JS_SetPrototype(engine.context, result, async_prototype) < 0) return js.capture(engine);
    return c.JS_DupValue(engine.context, result);
}
fn constructAbort(engine: *em.Engine, target: c.JSValue, _: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const constructor = try scope.get(values[0], "constructor");
    const base = try scope.own(try engine.checked(c.JS_GetPrototype(engine.context, constructor)));
    var args = [_]c.JSValue{try scope.text("Aborted")};
    return engine.checked(c.JS_CallConstructor2(engine.context, base, target, args.len, &args));
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var args = [_]c.JSValue{c.pi_js_undefined()} ** 4;
    if (argc > 0) for (argv[0..@min(@as(usize, @intCast(argc)), args.len)], 0..) |value, index| {
        args[index] = value;
    };
    return retry(engine, &args, roots[0]) catch |err| sdk.fail(engine, err);
}
pub fn retry(engine: *em.Engine, args: []const c.JSValue, abort_error: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, args[0]);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    initialize(engine, pending.owner, args, abort_error) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn initialize(engine: *em.Engine, owner: c.JSValue, args: []const c.JSValue, abort_error: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ "policy", "signal", "callbacks" }, 1..) |name, index| try scope.put(owner, name, args[index]);
    try scope.put(owner, "abortErrorConstructor", abort_error);
    try scope.put(owner, "generation", try scope.own(try engine.checked(c.JS_NewBigUint64(engine.context, engine.native_allocation_generation))));
    const enabled = if (temp.nullish(args[1])) c.pi_js_undefined() else try scope.get(args[1], "enabled");
    try scope.put(owner, "maxAttempts", if (scope.truthy(enabled)) try scope.get(args[1], "maxRetries") else c.JS_NewInt32(engine.context, 0));
    try scope.put(owner, "attempt", c.JS_NewInt32(engine.context, 0));
    try scope.put(owner, "lastRetry", c.pi_js_undefined());
    return produce(engine, owner);
}
fn wait(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    return flow.wait(continued, engine, owner, value, @intFromEnum(stage));
}
fn produce(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const produced = try scope.call(try scope.get(owner, "agent"), c.pi_js_undefined(), &.{});
    try wait(engine, owner, produced, .produced);
}
fn optional(scope: *Scope, owner: c.JSValue, name: [*:0]const u8) !struct { receiver: c.JSValue, function: c.JSValue } {
    const receiver = try scope.get(owner, "callbacks");
    return .{ .receiver = receiver, .function = if (temp.nullish(receiver)) c.pi_js_undefined() else try scope.get(receiver, name) };
}
fn finish(engine: *em.Engine, owner: c.JSValue, success: bool, final_error: bool) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const last = try scope.get(owner, "lastRetry");
    if (!scope.truthy(last)) return flow.settle(engine, owner, false, try scope.get(owner, "response"));
    const call = try optional(&scope, owner, "onRetryFinished");
    var result = c.pi_js_undefined();
    if (!temp.nullish(call.function)) {
        const count = try scope.get(last, "attempt");
        const flag = c.pi_js_bool(engine.context, @intFromBool(success));
        result = if (final_error)
            try scope.call(call.function, call.receiver, &.{ flag, count, try scope.get(try scope.get(owner, "response"), "errorMessage") })
        else
            try scope.call(call.function, call.receiver, &.{ flag, count });
    }
    try wait(engine, owner, result, .finished);
}
fn continued(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, failed: bool, raw_stage: c_int) !void {
    const stage: Stage = @enumFromInt(raw_stage);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (failed and stage != .slept) return flow.settle(engine, owner, true, value);
    switch (stage) {
        .produced => {
            try scope.put(owner, "response", value);
            if (try is(&scope, try scope.get(value, "stopReason"), "aborted")) return finish(engine, owner, false, false);
            if (!try is(&scope, try scope.get(value, "stopReason"), "error")) return finish(engine, owner, true, false);
            const attempt = try scope.get(owner, "attempt");
            if (try arithmetic.compare(engine, .greater_equal, attempt, try scope.get(owner, "maxAttempts")) or !try @import("native_ai_error_classification.zig").retryable(engine, value)) return finish(engine, owner, false, true);
            const next = try scope.own(try engine.checked(c.JS_PiIncrement(engine.context, attempt)));
            try scope.put(owner, "attempt", next);
            const last = try scope.object();
            try scope.put(last, "attempt", next);
            const message = try scope.get(value, "errorMessage");
            try scope.put(last, "errorMessage", if (scope.truthy(message)) message else try scope.text("Unknown error"));
            try scope.put(owner, "lastRetry", last);
            const delay = try scope.own(try @import("native_durable_retry.zig").delay(engine, try scope.get(owner, "policy"), next));
            try scope.put(owner, "delay", delay);
            const call = try optional(&scope, owner, "onRetryScheduled");
            const result = if (temp.nullish(call.function)) c.pi_js_undefined() else try scope.call(call.function, call.receiver, &.{ next, try scope.get(owner, "maxAttempts"), delay, try scope.get(last, "errorMessage") });
            try wait(engine, owner, result, .scheduled);
        },
        .finished => try flow.settle(engine, owner, false, try scope.get(owner, "response")),
        .scheduled => {
            const slept = sleep(engine, try scope.get(owner, "delay"), try scope.get(owner, "signal"), try scope.get(owner, "abortErrorConstructor")) catch |err| {
                const reason = flow.reason(engine, err);
                defer engine.freeValue(reason);
                return continued(engine, owner, reason, true, @intFromEnum(Stage.slept));
            };
            defer engine.freeValue(slept);
            try wait(engine, owner, slept, .slept);
        },
        .slept => {
            if (failed) {
                var generation: u64 = 0;
                if (c.JS_ToBigUint64(engine.context, &generation, try scope.get(owner, "generation")) < 0) return js.capture(engine);
                const tagged = c.pi_js_native_allocation_error_generation(value);
                const distance = tagged -% generation;
                if (tagged != 0 and distance != 0 and distance <= engine.native_allocation_generation -% generation) return flow.settle(engine, owner, true, value);
                try scope.put(owner, "sleepError", value);
                const call = try optional(&scope, owner, "onRetryFinished");
                var result = c.pi_js_undefined();
                if (!temp.nullish(call.function)) result = try scope.call(call.function, call.receiver, &.{ c.pi_js_bool(engine.context, 0), try scope.get(owner, "attempt"), try scope.get(try scope.get(owner, "lastRetry"), "errorMessage") });
                return wait(engine, owner, result, .sleepFinished);
            }
            const call = try optional(&scope, owner, "onRetryAttemptStart");
            const result = if (temp.nullish(call.function)) c.pi_js_undefined() else try scope.call(call.function, call.receiver, &.{});
            try wait(engine, owner, result, .started);
        },
        .started => try produce(engine, owner),
        .sleepFinished => {
            const reason = try scope.get(owner, "sleepError");
            const instance = c.JS_IsInstanceOf(engine.context, reason, try scope.get(owner, "abortErrorConstructor"));
            if (instance < 0) return js.capture(engine);
            if (instance == 0) return flow.settle(engine, owner, true, reason);
            const response = try scope.get(owner, "response");
            _ = try scope.get(response, "errorMessage");
            const rest = try scope.own(try withoutErrorMessage(engine, response));
            const result = try scope.own(try js.spread(engine, rest));
            try scope.put(result, "stopReason", try scope.text("aborted"));
            try flow.settle(engine, owner, false, result);
        },
    }
}
fn is(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
fn withoutErrorMessage(engine: *em.Engine, response: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    const boxed = try engine.checked(c.JS_ToObject(engine.context, response));
    defer engine.freeValue(boxed);
    const excluded = c.JS_NewAtom(engine.context, "errorMessage");
    if (excluded == c.JS_ATOM_NULL) return js.capture(engine);
    defer c.JS_FreeAtom(engine.context, excluded);
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, boxed, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK) < 0) return js.capture(engine);
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for (names[0..count]) |entry| {
        if (entry.atom == excluded) continue;
        var descriptor: c.JSPropertyDescriptor = undefined;
        const present = c.JS_GetOwnProperty(engine.context, &descriptor, boxed, entry.atom);
        if (present < 0) return js.capture(engine);
        if (present == 0) continue;
        defer engine.freeValue(descriptor.value);
        defer engine.freeValue(descriptor.getter);
        defer engine.freeValue(descriptor.setter);
        if (descriptor.flags & c.JS_PROP_ENUMERABLE == 0) continue;
        const value = try engine.checked(c.JS_GetProperty(engine.context, boxed, entry.atom));
        if (c.JS_DefinePropertyValue(engine.context, result, entry.atom, value, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    }
    return result;
}
fn sleep(engine: *em.Engine, milliseconds: c.JSValue, signal: c.JSValue, constructor: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const promise = try scope.global("Promise");
    var roots = [_]c.JSValue{ milliseconds, signal, constructor };
    const executor = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, executeSleep, "", 2, 0, roots.len, &roots)));
    return engine.checked(c.JS_CallConstructor(engine.context, promise, 1, @constCast(&[_]c.JSValue{executor})));
}
fn rejectAbort(scope: *Scope, reject: c.JSValue, constructor: c.JSValue) !void {
    const reason = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, 0, null)));
    _ = try scope.call(reject, c.pi_js_undefined(), &.{reason});
}
fn executeSleep(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    initializeSleep(engine, roots, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn initializeSleep(engine: *em.Engine, roots: [*c]c.JSValue, resolve: c.JSValue, reject: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!temp.nullish(roots[1]) and scope.truthy(try scope.get(roots[1], "aborted"))) return rejectAbort(&scope, reject, roots[2]);
    const timeout = try scope.call(try scope.global("setTimeout"), c.pi_js_undefined(), &.{ resolve, roots[0] });
    if (!temp.nullish(roots[1])) {
        const add = try scope.get(roots[1], "addEventListener");
        var saved = [_]c.JSValue{ timeout, reject, roots[2] };
        const listener = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, abortSleep, "", 0, 0, saved.len, &saved)));
        const options = try scope.object();
        try scope.put(options, "once", c.pi_js_bool(engine.context, 1));
        _ = try scope.call(add, roots[1], &.{ try scope.text("abort"), listener, options });
    }
}
fn abortSleep(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    _ = scope.call(scope.global("clearTimeout") catch |err| return sdk.fail(engine, err), c.pi_js_undefined(), &.{roots[0]}) catch |err| return sdk.fail(engine, err);
    rejectAbort(&scope, roots[1], roots[2]) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
