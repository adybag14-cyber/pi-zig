//! Public SDK auth resolution remains asynchronous through credential I/O,
//! provider callbacks, OAuth rotation, cancellation, and error wrapping.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const models = @import("native_sdk_models.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const Stage = enum(c_int) { begin, credential, resolved, read_failed, auth_failed, oauth_credential, oauth_auth, oauth_failed };
fn function(engine: *engine_mod.Engine, job: c.JSValue, stage: Stage) !c.JSValue {
    var data = [_]c.JSValue{job};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "sdkAuthResolution", 1, @intFromEnum(stage), 1, &data));
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return advance(engine, data[0], @enumFromInt(magic), if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn then(engine: *engine_mod.Engine, pending: c.JSValue, job: c.JSValue, good: Stage, bad: ?Stage) !c.JSValue {
    const adopted = try sdk.promise(engine, pending);
    defer engine.freeValue(adopted);
    const done = try function(engine, job, good);
    defer engine.freeValue(done);
    const failed = if (bad) |stage| try function(engine, job, stage) else c.pi_js_undefined();
    defer engine.freeValue(failed);
    return sdk.invoke(engine, adopted, "then", &.{ done, failed });
}
fn wrapped(engine: *engine_mod.Engine, job: c.JSValue, code_text: []const u8, prefix: []const u8, cause: c.JSValue) !c.JSValue {
    const id = try sdk.get(engine, job, "id");
    defer engine.freeValue(id);
    const id_text = try engine.toString(id);
    defer engine.gpa.free(id_text);
    const message_text = try std.fmt.allocPrint(engine.gpa, "{s}{s}", .{ prefix, id_text });
    defer engine.gpa.free(message_text);
    const message = try sdk.text(engine, message_text);
    defer engine.freeValue(message);
    const code = try sdk.text(engine, code_text);
    defer engine.freeValue(code);
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    try sdk.put(engine, options, "cause", c.JS_DupValue(engine.context, cause));
    const exports = engine.native_module_values.get("pi-ai") orelse return error.NativeSDKModelModuleUnavailable;
    const constructor = try sdk.get(engine, exports, "ModelsError");
    defer engine.freeValue(constructor);
    var args = [_]c.JSValue{ code, message, options };
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args));
}
pub fn start(engine: *engine_mod.Engine, runtime_data: c.JSValue, input: c.JSValue, options: c.JSValue) !c.JSValue {
    const job = try sdk.object(engine);
    defer engine.freeValue(job);
    try sdk.put(engine, job, "data", c.JS_DupValue(engine.context, runtime_data));
    try sdk.put(engine, job, "input", c.JS_DupValue(engine.context, input));
    const opts = if (c.JS_IsObject(options)) c.JS_DupValue(engine.context, options) else try sdk.object(engine);
    defer engine.freeValue(opts);
    try sdk.put(engine, job, "options", c.JS_DupValue(engine.context, opts));
    var signal = try sdk.get(engine, opts, "signal");
    defer engine.freeValue(signal);
    if (!c.JS_IsObject(signal)) {
        const created = try @import("abort_signal.zig").create(engine);
        engine.freeValue(signal);
        signal = created;
    }
    try sdk.put(engine, job, "signal", c.JS_DupValue(engine.context, signal));
    // Starting in a Promise job preserves the public async rejection boundary.
    const operation = try then(engine, c.pi_js_undefined(), job, .begin, null);
    defer engine.freeValue(operation);
    return @import("native_models_refresh.zig").race(engine, operation, signal, c.pi_js_undefined());
}
fn advance(engine: *engine_mod.Engine, job: c.JSValue, stage: Stage, value: c.JSValue) !c.JSValue {
    if (stage == .read_failed or stage == .auth_failed or stage == .oauth_failed) return c.JS_Throw(engine.context, try wrapped(engine, job, if (stage == .oauth_failed) "oauth" else "auth", if (stage == .read_failed) "Credential store read failed for " else if (stage == .oauth_failed) "OAuth auth derivation failed for " else "API key auth failed for provider ", value));
    const options = try sdk.get(engine, job, "options");
    defer engine.freeValue(options);
    const signal = try sdk.get(engine, job, "signal");
    defer engine.freeValue(signal);
    if (stage == .begin) {
        const checked = try sdk.invoke(engine, signal, "throwIfAborted", &.{});
        engine.freeValue(checked);
        const input = try sdk.get(engine, job, "input");
        defer engine.freeValue(input);
        const id = if (c.JS_IsString(input)) c.JS_DupValue(engine.context, input) else try sdk.get(engine, input, "provider");
        defer engine.freeValue(id);
        try sdk.put(engine, job, "id", c.JS_DupValue(engine.context, id));
        const data = try sdk.get(engine, job, "data");
        defer engine.freeValue(data);
        const catalog = try sdk.get(engine, data, "models");
        defer engine.freeValue(catalog);
        const provider = try sdk.invoke(engine, catalog, "getProvider", &.{id});
        defer engine.freeValue(provider);
        if (!c.JS_IsObject(provider)) return c.pi_js_undefined();
        try sdk.put(engine, job, "provider", c.JS_DupValue(engine.context, provider));
        const authentication = try sdk.get(engine, provider, "auth");
        defer engine.freeValue(authentication);
        const api = try sdk.get(engine, authentication, "apiKey");
        defer engine.freeValue(api);
        const explicit_key = try sdk.get(engine, options, "apiKey");
        defer engine.freeValue(explicit_key);
        if (!c.JS_IsUndefined(explicit_key) and c.JS_IsObject(api)) {
            const credential = try sdk.object(engine);
            defer engine.freeValue(credential);
            try sdk.put(engine, credential, "type", try sdk.text(engine, "api_key"));
            try sdk.put(engine, credential, "key", c.JS_DupValue(engine.context, explicit_key));
            try sdk.put(engine, credential, "env", try sdk.get(engine, options, "env"));
            return advance(engine, job, .credential, credential);
        }
        const read_options = try sdk.object(engine);
        defer engine.freeValue(read_options);
        try sdk.put(engine, read_options, "signal", c.JS_DupValue(engine.context, signal));
        const pending = models.readCredentialOptions(engine, data, id, read_options) catch |err| {
            if (err != error.JavaScriptException) return err;
            return advance(engine, job, .read_failed, engine.captured_exception.?);
        };
        defer engine.freeValue(pending);
        return then(engine, pending, job, .credential, .read_failed);
    }
    const provider = try sdk.get(engine, job, "provider");
    defer engine.freeValue(provider);
    const authentication = try sdk.get(engine, provider, "auth");
    defer engine.freeValue(authentication);
    if (stage == .credential) {
        const type_value = if (c.JS_IsObject(value)) try sdk.get(engine, value, "type") else c.pi_js_undefined();
        defer engine.freeValue(type_value);
        const api_type = try sdk.text(engine, "api_key");
        defer engine.freeValue(api_type);
        const oauth_type = try sdk.text(engine, "oauth");
        defer engine.freeValue(oauth_type);
        if (c.JS_IsObject(value) and c.JS_IsStrictEqual(engine.context, type_value, oauth_type)) {
            const oauth = try sdk.get(engine, authentication, "oauth");
            defer engine.freeValue(oauth);
            if (!c.JS_IsObject(oauth)) return c.pi_js_undefined();
            const data = try sdk.get(engine, job, "data");
            defer engine.freeValue(data);
            const store = try sdk.object(engine);
            defer engine.freeValue(store);
            try sdk.put(engine, store, "credentials", try models.credentials(engine, data));
            const cache = try sdk.object(engine);
            defer engine.freeValue(cache);
            const exports = engine.native_module_values.get("pi-ai") orelse return error.NativeSDKModelModuleUnavailable;
            const constructor = try sdk.get(engine, exports, "ModelsError");
            defer engine.freeValue(constructor);
            try sdk.put(engine, cache, "models_error_prototype", try sdk.get(engine, constructor, "prototype"));
            try sdk.put(engine, store, "cache", c.JS_DupValue(engine.context, cache));
            const minimum_value = try sdk.get(engine, options, "minOAuthValidityMs");
            defer engine.freeValue(minimum_value);
            var minimum: f64 = 300000;
            if (!c.JS_IsUndefined(minimum_value)) {
                var requested: f64 = 0;
                if (c.JS_ToFloat64(engine.context, &requested, minimum_value) < 0) return error.JavaScriptException;
                minimum = if (std.math.isNan(requested)) requested else @max(minimum, requested);
            }
            try sdk.put(engine, job, "oauthRefreshed", c.pi_js_bool(engine.context, @intFromBool(try @import("native_models_oauth_refresh.zig").expiredWithin(engine, value, minimum))));
            try sdk.put(engine, job, "oauthMinimum", c.JS_NewFloat64(engine.context, minimum));
            const pending = try @import("native_models_oauth_refresh.zig").resolveWithMinimum(engine, store, provider, value, signal, minimum);
            defer engine.freeValue(pending);
            return then(engine, pending, job, .oauth_credential, null);
        }
        if (c.JS_IsObject(value) and !c.JS_IsStrictEqual(engine.context, type_value, api_type)) return c.pi_js_undefined();
        const api = try sdk.get(engine, authentication, "apiKey");
        defer engine.freeValue(api);
        if (!c.JS_IsObject(api)) return c.pi_js_undefined();
        const parameters = try sdk.object(engine);
        defer engine.freeValue(parameters);
        const credential = if (c.JS_IsObject(value)) try sdk.object(engine) else c.pi_js_undefined();
        defer engine.freeValue(credential);
        if (c.JS_IsObject(credential)) {
            try models.copy(engine, credential, value);
            const stored_env = try sdk.get(engine, value, "env");
            defer engine.freeValue(stored_env);
            const request_env = try sdk.get(engine, options, "env");
            defer engine.freeValue(request_env);
            if (c.JS_IsObject(request_env)) try sdk.put(engine, credential, "env", try models.mergedHeaders(engine, stored_env, request_env));
        }
        try sdk.put(engine, parameters, "credential", c.JS_DupValue(engine.context, credential));
        try sdk.put(engine, parameters, "ctx", try models.authContext(engine, options));
        try sdk.put(engine, parameters, "signal", c.JS_DupValue(engine.context, signal));
        const pending = sdk.invoke(engine, api, "resolve", &.{parameters}) catch |err| {
            if (err != error.JavaScriptException) return err;
            return advance(engine, job, .auth_failed, engine.captured_exception.?);
        };
        defer engine.freeValue(pending);
        return then(engine, pending, job, .resolved, .auth_failed);
    }
    if (stage == .oauth_credential) {
        if (!c.JS_IsObject(value)) return c.pi_js_undefined();
        const explicit = try sdk.get(engine, options, "minOAuthValidityMs");
        defer engine.freeValue(explicit);
        const refreshed = try sdk.get(engine, job, "oauthRefreshed");
        defer engine.freeValue(refreshed);
        if (!c.JS_IsUndefined(explicit) and c.JS_ToBool(engine.context, refreshed) == 1) {
            const minimum_value = try sdk.get(engine, job, "oauthMinimum");
            defer engine.freeValue(minimum_value);
            var minimum: f64 = 0;
            if (c.JS_ToFloat64(engine.context, &minimum, minimum_value) < 0) return error.JavaScriptException;
            if (try @import("native_models_oauth_refresh.zig").expiredWithin(engine, value, minimum)) return c.JS_Throw(engine.context, try wrapped(engine, job, "oauth", "OAuth refresh returned a token that expires too soon for ", c.pi_js_undefined()));
        }
        const oauth = try sdk.get(engine, authentication, "oauth");
        defer engine.freeValue(oauth);
        const pending = sdk.invoke(engine, oauth, "toAuth", &.{value}) catch |err| {
            if (err != error.JavaScriptException) return err;
            return advance(engine, job, .oauth_failed, engine.captured_exception.?);
        };
        defer engine.freeValue(pending);
        return then(engine, pending, job, .oauth_auth, .oauth_failed);
    }
    if (stage == .oauth_auth) {
        const result = try sdk.object(engine);
        defer engine.freeValue(result);
        try sdk.put(engine, result, "auth", c.JS_DupValue(engine.context, value));
        try sdk.put(engine, result, "source", try sdk.text(engine, "OAuth"));
        return advance(engine, job, .resolved, result);
    }
    return @import("native_sdk_model_headers.zig").finish(engine, job, value);
}
