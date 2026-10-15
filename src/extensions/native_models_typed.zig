//! Actual typed Models requests and auth resolution. Provider callbacks execute
//! on their owning realm; no blocking await or cross-thread JSValue is used.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const vm = @import("native_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const awaiting = @import("native_durable_await.zig");
const models = @import("native_models.zig");
const signals = @import("abort_signal.zig");
const c = em.c;
const Action = enum(c_int) { getAuth, classify, generateImages };
const Stage = enum(c_int) { credential, api_key, oauth_refreshed, oauth_auth, auth_ready, transformed, finished };
fn item(scope: *Scope, array: c.JSValue, index: usize) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, array, @intCast(index))));
}
fn is(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
fn concat(scope: *Scope, parts: []const c.JSValue) !c.JSValue {
    var value = try scope.text("");
    for (parts) |part| value = try scope.concat(value, part);
    return value;
}
fn optional(scope: anytype, value: c.JSValue, key: [*:0]const u8) !c.JSValue {
    return if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) c.pi_js_undefined() else scope.get(value, key);
}
fn intrinsic(scope: *Scope, state: c.JSValue) !awaiting.Intrinsics {
    const cache = try scope.get(try scope.get(state, "store"), "cache");
    return .{ .constructor = try scope.get(cache, "promise_constructor"), .resolve = try scope.get(cache, "promise_resolve"), .then_function = try scope.get(cache, "promise_then") };
}
fn wait(scope: *Scope, state: c.JSValue, value: c.JSValue, stage: Stage) !c.JSValue {
    var captured = try intrinsic(scope, state);
    return scope.own(try awaiting.continueWith(advance, scope.engine, &captured, state, value, @intFromEnum(stage)));
}
fn capability(engine: *em.Engine, value: c.JSValue, rejected: bool) !c.JSValue {
    var functions: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    errdefer engine.freeValue(promise);
    defer engine.freeValue(functions[0]);
    defer engine.freeValue(functions[1]);
    var args = [_]c.JSValue{value};
    const ignored = try engine.checked(c.JS_Call(engine.context, functions[@intFromBool(rejected)], c.pi_js_undefined(), 1, &args));
    engine.freeValue(ignored);
    return promise;
}
fn cause(scope: *Scope, state: c.JSValue, code: []const u8, message: c.JSValue, original: c.JSValue) !c.JSValue {
    const text = try scope.engine.toString(message);
    defer scope.engine.gpa.free(text);
    return scope.own(try models.fromCause(scope.engine, try scope.get(state, "store"), code, text, original));
}
fn raise(scope: *Scope, state: c.JSValue, code: []const u8, message: c.JSValue) anyerror {
    const reason = cause(scope, state, code, message, c.pi_js_undefined()) catch |err| return err;
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason))) catch |err| return err;
    unreachable;
}
fn mergeHeaders(scope: *Scope, base: c.JSValue, override: c.JSValue) !c.JSValue {
    if (!scope.truthy(base) and !scope.truthy(override)) return c.pi_js_undefined();
    const merged = try scope.own(try js.spread(scope.engine, base));
    const object = try scope.global("Object");
    const entries = try scope.invoke(object, "entries", &.{if (c.JS_IsNull(override) or c.JS_IsUndefined(override)) try scope.object() else override});
    for (0..try vm.length(scope.engine, entries)) |i| {
        const pair = try item(scope, entries, i);
        const name = try item(scope, pair, 0);
        const lowered = try scope.invoke(name, "toLowerCase", &.{});
        const keys = try scope.invoke(object, "keys", &.{merged});
        for (0..try vm.length(scope.engine, keys)) |j| {
            const old = try item(scope, keys, j);
            if (!scope.equal(try scope.invoke(old, "toLowerCase", &.{}), lowered)) continue;
            const atom = c.JS_ValueToAtom(scope.engine.context, old);
            if (atom == c.JS_ATOM_NULL) return js.capture(scope.engine);
            defer c.JS_FreeAtom(scope.engine.context, atom);
            if (c.JS_DeleteProperty(scope.engine.context, merged, atom, c.JS_PROP_THROW) < 0) return js.capture(scope.engine);
        }
        try js.setKey(scope.engine, merged, name, try item(scope, pair, 1));
    }
    return merged;
}
pub fn install(engine: *em.Engine, instance: c.JSValue, store: c.JSValue) !void {
    if (engine.abort_signal_class == 0) try signals.install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var captures = [_]c.JSValue{store};
    inline for (std.meta.fields(Action)) |field| try scope.put(instance, field.name, try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, if (field.value == 0) 2 else 3, field.value, captures.len, &captures))));
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, raw: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return invoke(engine, captures[0], @enumFromInt(raw), args[0..@intCast(argc)]) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn overlay(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return overlayCall(engine, captures[0], if (argc > 0) args[0] else c.pi_js_undefined(), magic == 0) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn overlayCall(engine: *em.Engine, state: c.JSValue, name: c.JSValue, environment: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const base = try scope.get(try scope.get(state, "store"), "authContext");
    if (!environment) return c.JS_DupValue(engine.context, try scope.invoke(base, "fileExists", &.{name}));
    const supplied = try scope.own(try js.getKey(engine, try scope.get(try scope.get(state, "overrides"), "env"), name));
    return if (scope.truthy(supplied)) capability(engine, supplied, false) else c.JS_DupValue(engine.context, try scope.invoke(base, "env", &.{name}));
}
fn requestContext(scope: *Scope, state: c.JSValue) !c.JSValue {
    const base = try scope.get(try scope.get(state, "store"), "authContext");
    const env = try optional(scope, try scope.get(state, "overrides"), "env");
    if (!scope.truthy(env)) return base;
    const result = try scope.object();
    var captures = [_]c.JSValue{state};
    inline for (.{ "env", "fileExists" }, 0..) |key, i| try scope.put(result, key, try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, overlay, key, 1, @intCast(i), captures.len, &captures))));
    return result;
}
pub fn getAuth(engine: *em.Engine, store: c.JSValue, selected: c.JSValue, overrides: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const signal_arg = try optional(&scope, overrides, "signal");
    const signal = if (c.JS_IsUndefined(signal_arg) or c.JS_IsNull(signal_arg)) try scope.own(try signals.create(engine)) else signal_arg;
    const id = if (c.JS_IsString(selected)) selected else try scope.get(selected, "provider");
    const provider = try scope.own(try models.query(engine, store, .getProvider, &.{id}));
    if (c.JS_IsUndefined(provider)) return capability(engine, c.pi_js_undefined(), false);
    return resolveWithProvider(engine, store, provider, selected, id, overrides, signal);
}
/// Availability already owns a provider snapshot. Resolve its credentials again
/// through the same actual resolver without reselecting a replacement provider.
pub fn resolveProviderAuth(engine: *em.Engine, store: c.JSValue, provider: c.JSValue, overrides: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const supplied = try optional(&scope, overrides, "signal");
    const signal = if (c.JS_IsUndefined(supplied) or c.JS_IsNull(supplied)) try scope.own(try signals.create(engine)) else supplied;
    const id = try scope.get(provider, "id");
    return resolveWithProvider(engine, store, provider, id, id, overrides, signal);
}
fn resolveWithProvider(engine: *em.Engine, store: c.JSValue, provider: c.JSValue, selected: c.JSValue, id: c.JSValue, overrides: c.JSValue, signal: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.object();
    inline for (.{ .{ "store", store }, .{ "selected", selected }, .{ "overrides", overrides }, .{ "signal", signal }, .{ "provider", provider }, .{ "id", id } }) |field| try scope.put(state, field[0], field[1]);
    const pending = startAuth(&scope, state) catch |err| pending: {
        const reason = if (err == error.JavaScriptException and engine.captured_exception != null) engine.captured_exception.? else return err;
        break :pending try scope.own(try capability(engine, reason, true));
    };
    return @import("native_models_refresh.zig").race(engine, pending, signal, c.pi_js_undefined());
}
fn startAuth(scope: *Scope, state: c.JSValue) !c.JSValue {
    _ = try scope.invoke(try scope.get(state, "signal"), "throwIfAborted", &.{});
    try scope.put(state, "requestAuthContext", try requestContext(scope, state));
    const overrides = try scope.get(state, "overrides");
    const explicit = try optional(scope, overrides, "apiKey");
    const api_key = if (c.JS_IsUndefined(explicit)) c.pi_js_undefined() else try scope.get(try scope.get(try scope.get(state, "provider"), "auth"), "apiKey");
    if (!c.JS_IsUndefined(explicit) and scope.truthy(api_key)) {
        const credential = try scope.object();
        try scope.put(credential, "type", try scope.text("api_key"));
        try scope.put(credential, "key", try optional(scope, overrides, "apiKey"));
        try scope.put(credential, "env", try optional(scope, overrides, "env"));
        return apiKey(scope, state, api_key, credential);
    }
    const credentials = try scope.get(try scope.get(state, "store"), "credentials");
    const options = try scope.object();
    try scope.put(options, "signal", try scope.get(state, "signal"));
    const pending = if (c.JS_IsUndefined(credentials) or c.JS_IsNull(credentials)) c.pi_js_undefined() else scope.invoke(credentials, "read", &.{ try scope.get(state, "id"), options }) catch |err| {
        if (err != error.JavaScriptException or scope.engine.captured_exception == null) return err;
        return scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, try cause(scope, state, "auth", try scope.concat(try scope.text("Credential store read failed for "), try scope.get(state, "id")), scope.engine.captured_exception.?))));
    };
    return wait(scope, state, pending, .credential);
}
fn apiKey(scope: *Scope, state: c.JSValue, implementation: c.JSValue, credential: c.JSValue) !c.JSValue {
    const input = try scope.object();
    try scope.put(input, "ctx", try scope.get(state, "requestAuthContext"));
    try scope.put(input, "credential", credential);
    try scope.put(input, "signal", try scope.get(state, "signal"));
    const pending = scope.invoke(implementation, "resolve", &.{input}) catch |err| {
        if (err != error.JavaScriptException or scope.engine.captured_exception == null) return err;
        return scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, try cause(scope, state, "auth", try scope.concat(try scope.text("API key auth failed for provider "), try scope.get(state, "id")), scope.engine.captured_exception.?))));
    };
    return wait(scope, state, pending, .api_key);
}
fn authValue(scope: *Scope, state: c.JSValue, value: c.JSValue) !c.JSValue {
    const selected = try scope.get(state, "selected");
    if (!scope.truthy(value) or c.JS_IsString(selected)) return c.JS_DupValue(scope.engine.context, value);
    const headers = try scope.get(selected, "headers");
    if (!scope.truthy(headers)) return c.JS_DupValue(scope.engine.context, value);
    const result = try scope.own(try js.spread(scope.engine, value));
    const auth = try scope.get(value, "auth");
    const copied = try scope.own(try js.spread(scope.engine, auth));
    try scope.put(copied, "headers", try mergeHeaders(scope, try scope.get(auth, "headers"), headers));
    try scope.put(result, "auth", copied);
    return c.JS_DupValue(scope.engine.context, result);
}
pub fn errorResult(scope: anytype, state: c.JSValue, reason: c.JSValue) !c.JSValue {
    if (scope.truthy(try scope.get(state, "requestOnly"))) return scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason)));
    const model = try scope.get(state, "model");
    const result = try scope.object();
    inline for (.{ "api", "provider" }) |key| try scope.put(result, key, try scope.get(model, key));
    try scope.put(result, "model", try scope.get(model, "id"));
    try scope.put(result, if (scope.truthy(try scope.get(state, "images"))) "output" else "answers", if (scope.truthy(try scope.get(state, "images"))) try scope.array() else try scope.object());
    const signal = try optional(scope, try scope.get(state, "options"), "signal");
    const aborted = !c.JS_IsUndefined(signal) and !c.JS_IsNull(signal) and scope.truthy(try scope.get(signal, "aborted"));
    try scope.put(result, "stopReason", try scope.text(if (aborted) "aborted" else "error"));
    const constructor = try scope.global("Error");
    const instance = c.JS_IsInstanceOf(scope.engine.context, reason, constructor);
    if (instance < 0) return js.capture(scope.engine);
    try scope.put(result, "errorMessage", if (instance == 1) try scope.get(reason, "message") else try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{reason}));
    try scope.put(result, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
    return c.JS_DupValue(scope.engine.context, result);
}
fn invoke(engine: *em.Engine, store: c.JSValue, action: Action, args: []const c.JSValue) !c.JSValue {
    if (action == .getAuth) return getAuth(engine, store, if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined());
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.object();
    try scope.put(state, "store", store);
    try scope.put(state, "images", c.pi_js_bool(engine.context, @intFromBool(action == .generateImages)));
    try scope.put(state, "model", if (args.len > 0) args[0] else c.pi_js_undefined());
    try scope.put(state, "context", if (args.len > 1) args[1] else c.pi_js_undefined());
    try scope.put(state, "options", if (args.len > 2) args[2] else c.pi_js_undefined());
    return startTyped(&scope, state) catch |err| {
        if (err != error.JavaScriptException or engine.captured_exception == null) return err;
        const failed = try scope.own(try errorResult(&scope, state, engine.captured_exception.?));
        return capability(engine, failed, false);
    };
}
fn startTyped(scope: *Scope, state: c.JSValue) !c.JSValue {
    const model = try scope.get(state, "model");
    const images = scope.truthy(try scope.get(state, "images"));
    var kind = try scope.get(model, "type");
    if (c.JS_IsUndefined(kind) or c.JS_IsNull(kind)) kind = try scope.text("chat");
    const id = try scope.get(model, "id");
    const provider_id = try scope.get(model, "provider");
    if (!try is(scope, kind, if (images) "image" else "classifier")) return raise(scope, state, "provider", try concat(scope, &.{ try scope.text("Model "), provider_id, try scope.text("/"), id, try scope.text(if (images) " is not an image model" else " is not a classifier model") }));
    if (!images) {
        const pictures = try optional(scope, try scope.get(state, "context"), "images");
        if (!c.JS_IsUndefined(pictures) and !c.JS_IsNull(pictures) and scope.truthy(try scope.get(pictures, "length")) and !scope.truthy(try scope.invoke(try scope.get(model, "input"), "includes", &.{try scope.text("image")}))) return raise(scope, state, "provider", try concat(scope, &.{ try scope.text("Model "), provider_id, try scope.text("/"), id, try scope.text(" does not accept image input") }));
    }
    const provider = try scope.own(try models.query(scope.engine, try scope.get(state, "store"), .getProvider, &.{provider_id}));
    if (c.JS_IsUndefined(provider)) return raise(scope, state, "provider", try scope.concat(try scope.text("Unknown provider: "), provider_id));
    try scope.put(state, "provider", provider);
    const method = try scope.get(provider, if (images) "generateImages" else "classify");
    if (!scope.truthy(method)) return raise(scope, state, "provider", try concat(scope, &.{ try scope.text("Provider "), provider_id, try scope.text(if (images) " does not support image generation" else " does not support classification") }));
    const options = try scope.get(state, "options");
    const overrides = try scope.object();
    inline for (.{ "apiKey", "env", "signal" }) |key| try scope.put(overrides, key, try optional(scope, options, key));
    const pending = try scope.own(try getAuth(scope.engine, try scope.get(state, "store"), model, overrides));
    return c.JS_DupValue(scope.engine.context, try wait(scope, state, pending, .auth_ready));
}
fn request(scope: *Scope, state: c.JSValue, headers: c.JSValue) !c.JSValue {
    const options = try scope.get(state, "options");
    const resolution = try scope.get(state, "resolution");
    const auth = try scope.get(resolution, "auth");
    const model = try scope.get(state, "model");
    const base_url = try scope.get(auth, "baseUrl");
    const selected = if (scope.truthy(base_url)) selected: {
        const copy = try scope.own(try js.spread(scope.engine, model));
        try scope.put(copy, "baseUrl", base_url);
        break :selected copy;
    } else model;
    _ = try optional(scope, options, "transformHeaders");
    const outgoing = try scope.object();
    if (!c.JS_IsUndefined(options) and !c.JS_IsNull(options)) {
        var properties: [*c]c.JSPropertyEnum = null;
        var count: u32 = 0;
        if (c.JS_GetOwnPropertyNames(scope.engine.context, &properties, &count, options, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK | c.JS_GPN_ENUM_ONLY) < 0) return js.capture(scope.engine);
        defer c.JS_FreePropertyEnum(scope.engine.context, properties, count);
        const excluded = c.JS_NewAtom(scope.engine.context, "transformHeaders");
        defer c.JS_FreeAtom(scope.engine.context, excluded);
        for (properties[0..count]) |property| {
            if (property.atom == excluded) continue;
            const value = try scope.engine.checked(c.JS_GetProperty(scope.engine.context, options, property.atom));
            if (c.JS_DefinePropertyValue(scope.engine.context, outgoing, property.atom, value, c.JS_PROP_C_W_E) < 0) return js.capture(scope.engine);
        }
    }
    var key = try optional(scope, options, "apiKey");
    if (c.JS_IsUndefined(key) or c.JS_IsNull(key)) key = try scope.get(auth, "apiKey");
    try scope.put(outgoing, "apiKey", key);
    try scope.put(outgoing, "headers", headers);
    const resolved_env = try scope.get(resolution, "env");
    const caller_env = try optional(scope, options, "env");
    var env = c.pi_js_undefined();
    if (scope.truthy(resolved_env) or scope.truthy(caller_env)) {
        env = try scope.own(try js.spread(scope.engine, resolved_env));
        try js.spreadInto(scope.engine, env, caller_env);
    }
    try scope.put(outgoing, "env", env);
    if (scope.truthy(try scope.get(state, "requestOnly"))) {
        const result = try scope.object();
        try scope.put(result, "requestModel", selected);
        try scope.put(result, "requestOptions", outgoing);
        return c.JS_DupValue(scope.engine.context, result);
    }
    const pending = try scope.invoke(try scope.get(state, "provider"), if (scope.truthy(try scope.get(state, "images"))) "generateImages" else "classify", &.{ selected, try scope.get(state, "context"), outgoing });
    return c.JS_DupValue(scope.engine.context, try wait(scope, state, pending, .finished));
}
fn advance(engine: *em.Engine, state: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    return advanceInner(engine, state, value, rejected, raw) catch |err| {
        const stage: Stage = @enumFromInt(raw);
        if (err != error.JavaScriptException or engine.captured_exception == null or (stage != .auth_ready and stage != .transformed and stage != .finished)) return err;
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        return errorResult(&scope, state, engine.captured_exception.?);
    };
}
fn advanceInner(engine: *em.Engine, state: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(raw);
    if (rejected) {
        if (stage == .auth_ready or stage == .transformed or stage == .finished) return errorResult(&scope, state, value);
        const message = try scope.concat(try scope.text(switch (stage) {
            .credential => "Credential store read failed for ",
            .api_key => "API key auth failed for provider ",
            .oauth_auth => "OAuth auth derivation failed for ",
            else => "",
        }), try scope.get(state, "id"));
        const wrapped = if (stage == .oauth_refreshed) value else try cause(&scope, state, if (stage == .oauth_auth) "oauth" else "auth", message, value);
        return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, wrapped)));
    }
    switch (stage) {
        .credential => {
            const auth = try scope.get(try scope.get(state, "provider"), "auth");
            const api_key = try scope.get(auth, "apiKey");
            if (scope.truthy(value)) {
                const kind = try scope.get(value, "type");
                if (try is(&scope, kind, "oauth") and scope.truthy(try scope.get(auth, "oauth"))) {
                    const explicit = try optional(&scope, try scope.get(state, "overrides"), "minOAuthValidityMs");
                    var minimum: f64 = 0;
                    if (!c.JS_IsUndefined(explicit) and !c.JS_IsNull(explicit)) if (c.JS_ToFloat64(engine.context, &minimum, explicit) < 0) return js.capture(engine);
                    minimum = @max(300000, minimum);
                    try scope.put(state, "minimum", c.JS_NewFloat64(engine.context, minimum));
                    try scope.put(state, "explicitMinimum", c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsUndefined(explicit))));
                    try scope.put(state, "refreshNeeded", c.pi_js_bool(engine.context, @intFromBool(try @import("native_models_oauth_refresh.zig").expiredWithin(engine, value, minimum))));
                    const pending = try scope.own(try @import("native_models_oauth_refresh.zig").resolveWithMinimum(engine, try scope.get(state, "store"), try scope.get(state, "provider"), value, try scope.get(state, "signal"), minimum));
                    return c.JS_DupValue(engine.context, try wait(&scope, state, pending, .oauth_refreshed));
                }
                if (try is(&scope, kind, "api_key") and scope.truthy(api_key)) {
                    const env = try optional(&scope, try scope.get(state, "overrides"), "env");
                    var credential = value;
                    if (scope.truthy(env)) {
                        credential = try scope.own(try js.spread(engine, value));
                        const merged = try scope.own(try js.spread(engine, try scope.get(value, "env")));
                        try js.spreadInto(engine, merged, env);
                        try scope.put(credential, "env", merged);
                    }
                    return c.JS_DupValue(engine.context, try apiKey(&scope, state, api_key, credential));
                }
                return c.pi_js_undefined();
            }
            return if (scope.truthy(api_key)) c.JS_DupValue(engine.context, try apiKey(&scope, state, api_key, c.pi_js_undefined())) else c.pi_js_undefined();
        },
        .api_key => return authValue(&scope, state, value),
        .oauth_refreshed => {
            if (c.JS_IsUndefined(value)) return c.pi_js_undefined();
            var minimum: f64 = 0;
            if (c.JS_ToFloat64(engine.context, &minimum, try scope.get(state, "minimum")) < 0) return js.capture(engine);
            if (scope.truthy(try scope.get(state, "explicitMinimum")) and scope.truthy(try scope.get(state, "refreshNeeded")) and try @import("native_models_oauth_refresh.zig").expiredWithin(engine, value, minimum)) return raise(&scope, state, "oauth", try scope.concat(try scope.text("OAuth refresh returned a token that expires too soon for "), try scope.get(state, "id")));
            const pending = scope.invoke(try scope.get(try scope.get(try scope.get(state, "provider"), "auth"), "oauth"), "toAuth", &.{value}) catch |err| {
                if (err != error.JavaScriptException or engine.captured_exception == null) return err;
                return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, try cause(&scope, state, "oauth", try scope.concat(try scope.text("OAuth auth derivation failed for "), try scope.get(state, "id")), engine.captured_exception.?))));
            };
            return c.JS_DupValue(engine.context, try wait(&scope, state, pending, .oauth_auth));
        },
        .oauth_auth => {
            const result = try scope.object();
            try scope.put(result, "auth", value);
            try scope.put(result, "source", try scope.text("OAuth"));
            return authValue(&scope, state, result);
        },
        .auth_ready => {
            if (!scope.truthy(value)) return errorResult(&scope, state, try cause(&scope, state, "auth", try scope.concat(try scope.text("Provider is not configured: "), try scope.get(try scope.get(state, "model"), "provider")), c.pi_js_undefined()));
            try scope.put(state, "resolution", value);
            const options = try scope.get(state, "options");
            const headers = try mergeHeaders(&scope, try scope.get(try scope.get(value, "auth"), "headers"), try optional(&scope, options, "headers"));
            if (scope.truthy(try optional(&scope, options, "transformHeaders"))) return c.JS_DupValue(engine.context, try wait(&scope, state, try scope.call(try scope.get(options, "transformHeaders"), options, &.{if (c.JS_IsUndefined(headers) or c.JS_IsNull(headers)) try scope.object() else headers}), .transformed));
            return request(&scope, state, headers) catch |err| {
                if (err != error.JavaScriptException or engine.captured_exception == null) return err;
                return errorResult(&scope, state, engine.captured_exception.?);
            };
        },
        .transformed => return request(&scope, state, value) catch |err| {
            if (err != error.JavaScriptException or engine.captured_exception == null) return err;
            return errorResult(&scope, state, engine.captured_exception.?);
        },
        .finished => return c.JS_DupValue(engine.context, value),
    }
}

/// Shared auth application for native chat/deferred service dispatch. Returns a
/// Promise for the exact request model/options pair; failures remain rejections.
pub fn applyAuth(engine: *em.Engine, store: c.JSValue, model: c.JSValue, options: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.object();
    try scope.put(state, "store", store);
    try scope.put(state, "model", model);
    try scope.put(state, "options", options);
    try scope.put(state, "requestOnly", c.pi_js_bool(engine.context, 1));
    const overrides = try scope.object();
    inline for (.{ "apiKey", "env", "signal" }) |key| try scope.put(overrides, key, try optional(&scope, options, key));
    const pending = try scope.own(try getAuth(engine, store, model, overrides));
    return c.JS_DupValue(engine.context, try wait(&scope, state, pending, .auth_ready));
}
