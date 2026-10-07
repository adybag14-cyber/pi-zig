//! OAuth model refresh uses the credential store's lock. Once the lock callback
//! starts, caller cancellation cannot discard a rotated refresh credential.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const engine_mod = @import("engine.zig");
const signals = @import("abort_signal.zig");
const models = @import("native_models.zig");
const c = engine_mod.c;
const Stage = enum(c_int) { cancel_wait, modify, refreshed, refresh_failed, modified, modify_failed };
fn function(engine: *engine_mod.Engine, job: c.JSValue, stage: Stage) !c.JSValue {
    var captured = [_]c.JSValue{job};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "oauthModelRefresh", 1, @intFromEnum(stage), 1, &captured));
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, stage: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return advance(engine, data[0], @enumFromInt(stage), if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn then(engine: *engine_mod.Engine, pending: c.JSValue, job: c.JSValue, good: Stage, bad: Stage) !c.JSValue {
    const adopted = try sdk.promise(engine, pending);
    defer engine.freeValue(adopted);
    const fulfilled = try function(engine, job, good);
    defer engine.freeValue(fulfilled);
    const rejected = try function(engine, job, bad);
    defer engine.freeValue(rejected);
    return sdk.invoke(engine, adopted, "then", &.{ fulfilled, rejected });
}
fn typeIsOAuth(engine: *engine_mod.Engine, value: c.JSValue) !bool {
    if (!c.JS_IsObject(value)) return false;
    const kind = try sdk.get(engine, value, "type");
    defer engine.freeValue(kind);
    const expected = try sdk.text(engine, "oauth");
    defer engine.freeValue(expected);
    return c.JS_IsStrictEqual(engine.context, kind, expected);
}
fn expired(engine: *engine_mod.Engine, value: c.JSValue) !bool {
    const expiry = try sdk.get(engine, value, "expires");
    defer engine.freeValue(expiry);
    var deadline: f64 = undefined;
    if (c.JS_ToFloat64(engine.context, &deadline, expiry) < 0) return error.JavaScriptException;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const date = try sdk.get(engine, global, "Date");
    defer engine.freeValue(date);
    const time = try sdk.invoke(engine, date, "now", &.{});
    defer engine.freeValue(time);
    var now: f64 = undefined;
    if (c.JS_ToFloat64(engine.context, &now, time) < 0) return error.JavaScriptException;
    return now >= deadline;
}
fn cleanup(engine: *engine_mod.Engine, job: c.JSValue) !void {
    const listener = try sdk.get(engine, job, "listener");
    defer engine.freeValue(listener);
    if (!c.JS_IsFunction(engine.context, listener)) return;
    const signal = try sdk.get(engine, job, "signal");
    defer engine.freeValue(signal);
    const event = try sdk.text(engine, "abort");
    defer engine.freeValue(event);
    const ignored = try sdk.invoke(engine, signal, "removeEventListener", &.{ event, listener });
    engine.freeValue(ignored);
    try sdk.put(engine, job, "listener", c.pi_js_undefined());
}
pub fn resolve(engine: *engine_mod.Engine, store: c.JSValue, provider: c.JSValue, credential: c.JSValue, signal: c.JSValue) !c.JSValue {
    const auth = try sdk.get(engine, provider, "auth");
    defer engine.freeValue(auth);
    const oauth = try sdk.get(engine, auth, "oauth");
    defer engine.freeValue(oauth);
    if (!c.JS_IsObject(oauth)) return sdk.promise(engine, c.pi_js_undefined());
    if (!try expired(engine, credential)) return sdk.promise(engine, credential);
    const aborted = try sdk.get(engine, signal, "aborted");
    defer engine.freeValue(aborted);
    if (c.JS_ToBool(engine.context, aborted) == 1) return sdk.promise(engine, c.pi_js_undefined());
    const job = try sdk.object(engine);
    defer engine.freeValue(job);
    try sdk.put(engine, job, "store", c.JS_DupValue(engine.context, store));
    try sdk.put(engine, job, "id", try sdk.get(engine, provider, "id"));
    try sdk.put(engine, job, "oauth", c.JS_DupValue(engine.context, oauth));
    try sdk.put(engine, job, "signal", c.JS_DupValue(engine.context, signal));
    const wait = try signals.create(engine);
    defer engine.freeValue(wait);
    try sdk.put(engine, job, "wait", c.JS_DupValue(engine.context, wait));
    const listener = try function(engine, job, .cancel_wait);
    defer engine.freeValue(listener);
    try sdk.put(engine, job, "listener", c.JS_DupValue(engine.context, listener));
    const event = try sdk.text(engine, "abort");
    defer engine.freeValue(event);
    const added = try sdk.invoke(engine, signal, "addEventListener", &.{ event, listener });
    engine.freeValue(added);
    const credentials = try sdk.get(engine, store, "credentials");
    defer engine.freeValue(credentials);
    const id = try sdk.get(engine, job, "id");
    defer engine.freeValue(id);
    const modify = try function(engine, job, .modify);
    defer engine.freeValue(modify);
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    try sdk.put(engine, options, "signal", c.JS_DupValue(engine.context, wait));
    const pending = sdk.invoke(engine, credentials, "modify", &.{ id, modify, options }) catch |err| {
        try cleanup(engine, job);
        return err;
    };
    defer engine.freeValue(pending);
    return then(engine, pending, job, .modified, .modify_failed);
}
fn wrap(engine: *engine_mod.Engine, job: c.JSValue, code: []const u8, prefix: []const u8, cause: c.JSValue) !c.JSValue {
    const store = try sdk.get(engine, job, "store");
    defer engine.freeValue(store);
    const id = try sdk.get(engine, job, "id");
    defer engine.freeValue(id);
    const text = try engine.toString(id);
    defer engine.gpa.free(text);
    const message = try std.fmt.allocPrint(engine.gpa, "{s}{s}", .{ prefix, text });
    defer engine.gpa.free(message);
    return models.fromCause(engine, store, code, message, cause);
}
fn advance(engine: *engine_mod.Engine, job: c.JSValue, stage: Stage, value: c.JSValue) !c.JSValue {
    if (stage == .cancel_wait) {
        const wait = try sdk.get(engine, job, "wait");
        defer engine.freeValue(wait);
        const signal = try sdk.get(engine, job, "signal");
        defer engine.freeValue(signal);
        const reason = try sdk.get(engine, signal, "reason");
        defer engine.freeValue(reason);
        try signals.abort(engine, wait, reason);
        return c.pi_js_undefined();
    }
    if (stage == .modify) {
        try cleanup(engine, job);
        const signal = try sdk.get(engine, job, "signal");
        defer engine.freeValue(signal);
        const checked = try sdk.invoke(engine, signal, "throwIfAborted", &.{});
        engine.freeValue(checked);
        if (!try typeIsOAuth(engine, value) or !try expired(engine, value)) return c.pi_js_undefined();
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const constructor = try sdk.get(engine, global, "AbortSignal");
        defer engine.freeValue(constructor);
        const timeout = try sdk.invoke(engine, constructor, "timeout", &.{c.JS_NewInt32(engine.context, 15000)});
        defer engine.freeValue(timeout);
        const oauth = try sdk.get(engine, job, "oauth");
        defer engine.freeValue(oauth);
        const pending = sdk.invoke(engine, oauth, "refresh", &.{ value, timeout }) catch |err| {
            if (err != error.JavaScriptException) return err;
            return advance(engine, job, .refresh_failed, engine.captured_exception.?);
        };
        defer engine.freeValue(pending);
        return then(engine, pending, job, .refreshed, .refresh_failed);
    }
    if (stage == .refreshed) return c.JS_DupValue(engine.context, value);
    if (stage == .refresh_failed) return c.JS_Throw(engine.context, try wrap(engine, job, "oauth", "OAuth refresh failed for ", value));
    try cleanup(engine, job);
    if (stage == .modified) return if (try typeIsOAuth(engine, value)) c.JS_DupValue(engine.context, value) else c.pi_js_undefined();
    const store = try sdk.get(engine, job, "store");
    defer engine.freeValue(store);
    const cache = try sdk.get(engine, store, "cache");
    defer engine.freeValue(cache);
    const prototype = try sdk.get(engine, cache, "models_error_prototype");
    defer engine.freeValue(prototype);
    const constructor = try sdk.get(engine, prototype, "constructor");
    defer engine.freeValue(constructor);
    // The provider's wrapped OAuth failure already carries its original cause.
    const wrapped = c.JS_IsInstanceOf(engine.context, value, constructor);
    if (wrapped < 0) return error.JavaScriptException;
    if (wrapped == 1) return c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value));
    const signal = try sdk.get(engine, job, "signal");
    defer engine.freeValue(signal);
    const checked = try sdk.invoke(engine, signal, "throwIfAborted", &.{});
    engine.freeValue(checked);
    return c.JS_Throw(engine.context, try wrap(engine, job, "auth", "Credential store modify failed for ", value));
}
