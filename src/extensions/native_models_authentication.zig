//! Models login/logout using actual Provider auth and credential-store callbacks.
//! Cancellation before a mutation starts releases the caller; in-flight mutation
//! remains observed and owns its credential until the store settles.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const awaiting = @import("native_durable_await.zig");
const models = @import("native_models.zig");
const c = em.c;
const Action = enum(c_int) { login, logout };
const Stage = enum(c_int) { login_ready, mutation_ready, started_ready, logout_ready };
fn nullish(value: c.JSValue) bool {
    return c.JS_IsUndefined(value) or c.JS_IsNull(value);
}
fn intrinsic(scope: *Scope, state: c.JSValue) !awaiting.Intrinsics {
    const cache = try scope.get(try scope.get(state, "store"), "cache");
    return .{ .constructor = try scope.get(cache, "promise_constructor"), .resolve = try scope.get(cache, "promise_resolve"), .then_function = try scope.get(cache, "promise_then") };
}
fn wait(scope: *Scope, state: c.JSValue, value: c.JSValue, stage: Stage) !c.JSValue {
    var captured = try intrinsic(scope, state);
    return scope.own(try awaiting.continueWith(advance, scope.engine, &captured, state, value, @intFromEnum(stage)));
}
pub fn install(engine: *em.Engine, instance: c.JSValue, store: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var data = [_]c.JSValue{store};
    inline for (std.meta.fields(Action)) |field| try scope.put(instance, field.name, try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, if (field.value == 0) 4 else 1, field.value, data.len, &data))));
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, raw: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return invoke(engine, data[0], @enumFromInt(raw), args[0..@intCast(argc)]) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn wrapped(scope: *Scope, state: c.JSValue, message: c.JSValue, original: c.JSValue) !c.JSValue {
    const text = try scope.engine.toString(message);
    defer scope.engine.gpa.free(text);
    return scope.own(try models.fromCause(scope.engine, try scope.get(state, "store"), "auth", text, original));
}
fn raise(scope: *Scope, state: c.JSValue, code: []const u8, message: c.JSValue) anyerror {
    const text = scope.engine.toString(message) catch |err| return err;
    defer scope.engine.gpa.free(text);
    const reason = scope.own(models.fromCause(scope.engine, scope.get(state, "store") catch |err| return err, code, text, c.pi_js_undefined()) catch |err| return err) catch |err| return err;
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason))) catch |err| return err;
    unreachable;
}
fn invoke(engine: *em.Engine, store: c.JSValue, action: Action, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const id = if (args.len > 0) args[0] else c.pi_js_undefined();
    const input = if (args.len > (if (action == .login) @as(usize, 2) else 1)) args[if (action == .login) 2 else 1] else c.pi_js_undefined();
    const supplied = if (nullish(input)) c.pi_js_undefined() else try scope.get(input, "signal");
    const signal = if (nullish(supplied)) try scope.own(try @import("abort_signal.zig").create(engine)) else supplied;
    _ = try scope.invoke(signal, "throwIfAborted", &.{});
    const state = try scope.object();
    try scope.put(state, "store", store);
    try scope.put(state, "id", id);
    try scope.put(state, "signal", signal);
    const options = try scope.object();
    try scope.put(options, "signal", signal);
    if (action == .logout) {
        const pending = scope.invoke(try scope.get(store, "credentials"), "delete", &.{ id, options }) catch |err| {
            if (err != error.JavaScriptException or engine.captured_exception == null) return err;
            const reason = try storeFailure(&scope, state, engine.captured_exception.?, "delete");
            return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
        };
        return c.JS_DupValue(engine.context, try wait(&scope, state, pending, .logout_ready));
    }
    const provider = try scope.own(try models.query(engine, store, .getProvider, &.{id}));
    if (c.JS_IsUndefined(provider)) return raise(&scope, state, "provider", try scope.concat(try scope.text("Unknown provider: "), id));
    const kind = if (args.len > 1) args[1] else c.pi_js_undefined();
    const method = try scope.get(try scope.get(provider, "auth"), if (scope.equal(kind, try scope.text("oauth"))) "oauth" else "apiKey");
    if (nullish(method) or !scope.truthy(try scope.get(method, "login"))) return raise(&scope, state, "auth", try scope.concat(try scope.concat(try scope.concat(try scope.get(provider, "name"), try scope.text(" does not support ")), kind), try scope.text(" login")));
    const interaction = try scope.own(try js.spread(engine, input));
    try scope.put(interaction, "signal", signal);
    const pending = try scope.invoke(method, "login", &.{ interaction, if (args.len > 3) args[3] else c.pi_js_undefined() });
    const raced = try scope.own(try @import("native_models_refresh.zig").race(engine, pending, signal, c.pi_js_undefined()));
    return c.JS_DupValue(engine.context, try wait(&scope, state, raced, .login_ready));
}
fn storeFailure(scope: *Scope, state: c.JSValue, reason: c.JSValue, operation: []const u8) !c.JSValue {
    const signal = try scope.get(state, "signal");
    if (scope.truthy(try scope.get(signal, "aborted"))) return scope.get(signal, "reason");
    return wrapped(scope, state, try scope.concat(try scope.concat(try scope.text("Credential store "), try scope.text(operation)), try scope.concat(try scope.text(" failed for "), try scope.get(state, "id"))), reason);
}
fn removeListener(scope: *Scope, state: c.JSValue) !void {
    const listener = try scope.get(state, "listener");
    if (!c.JS_IsFunction(scope.engine.context, listener)) return;
    _ = try scope.invoke(try scope.get(state, "signal"), "removeEventListener", &.{ try scope.text("abort"), listener });
    try scope.put(state, "listener", c.pi_js_undefined());
}
fn settle(scope: *Scope, state: c.JSValue, value: c.JSValue, rejected: bool) !c.JSValue {
    if (scope.truthy(try scope.get(state, "closed"))) return c.pi_js_undefined();
    try removeListener(scope, state);
    try scope.put(state, "closed", c.pi_js_bool(scope.engine.context, 1));
    _ = try scope.call(try scope.get(state, if (rejected) "reject" else "resolve"), c.pi_js_undefined(), &.{value});
    return c.pi_js_undefined();
}
fn callback(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return callbackInner(engine, data[0], magic == 0) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn callbackInner(engine: *em.Engine, state: c.JSValue, mutation: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!mutation) {
        if (scope.truthy(try scope.get(state, "started"))) return c.pi_js_undefined();
        return settle(&scope, state, try scope.get(try scope.get(state, "signal"), "reason"), true);
    }
    try scope.put(state, "started", c.pi_js_bool(engine.context, 1));
    _ = try wait(&scope, state, c.pi_js_undefined(), .started_ready);
    return @import("native_durable.zig").resolvedPromise(engine, try scope.get(state, "credential"));
}
fn advance(engine: *em.Engine, state: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    return advanceInner(engine, state, value, rejected, raw) catch |err| {
        // A host failure formatting a mutation error must still retire the
        // separately-owned login capability. The mutation remains observed.
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const reject = scope.get(state, "reject") catch return err;
        if (c.JS_IsFunction(engine.context, reject)) {
            _ = @import("native_durable.zig").reject(engine, err);
            const reason = c.JS_GetException(engine.context);
            defer engine.freeValue(reason);
            _ = settle(&scope, state, reason, true) catch {};
        }
        return err;
    };
}
fn advanceInner(engine: *em.Engine, state: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(raw);
    if (stage == .logout_ready) {
        if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, try storeFailure(&scope, state, value, "delete"))));
        return c.pi_js_undefined();
    }
    if (stage == .login_ready) {
        if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
        try scope.put(state, "credential", value);
        try scope.put(state, "started", c.pi_js_bool(engine.context, 0));
        try scope.put(state, "closed", c.pi_js_bool(engine.context, 0));
        var functions: [2]c.JSValue = undefined;
        const result = try scope.own(try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions)));
        defer for (functions) |function| engine.freeValue(function);
        try scope.put(state, "resolve", functions[0]);
        try scope.put(state, "reject", functions[1]);
        var data = [_]c.JSValue{state};
        const mutate = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "", 1, 0, data.len, &data)));
        const options = try scope.object();
        try scope.put(options, "signal", try scope.get(state, "signal"));
        const pending = try scope.invoke(try scope.get(try scope.get(state, "store"), "credentials"), "modify", &.{ try scope.get(state, "id"), mutate, options });
        _ = try wait(&scope, state, pending, .mutation_ready);
        const listener = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "", 0, 1, data.len, &data)));
        try scope.put(state, "listener", listener);
        const listener_options = try scope.object();
        try scope.put(listener_options, "once", c.pi_js_bool(engine.context, 1));
        _ = try scope.invoke(try scope.get(state, "signal"), "addEventListener", &.{ try scope.text("abort"), listener, listener_options });
        if (scope.truthy(try scope.get(try scope.get(state, "signal"), "aborted"))) _ = try callbackInner(engine, state, false);
        return c.JS_DupValue(engine.context, result);
    }
    if (stage == .started_ready) {
        try removeListener(&scope, state);
        return c.pi_js_undefined();
    }
    if (rejected) return settle(&scope, state, try storeFailure(&scope, state, value, "modify"), true);
    return settle(&scope, state, try scope.get(state, "credential"), false);
}
