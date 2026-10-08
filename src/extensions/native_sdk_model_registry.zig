//! Source ModelRegistry compatibility facade. Synchronous catalog snapshots
//! retain their exact runtime independently of any AgentSession context guard.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const Method = enum(c_int) { refresh, getError, getAll, getAvailable, find, findOfType, hasConfiguredAuth, getApiKeyAndHeaders, getProviderAuthStatus, getProvider, stream, streamSimple, complete, getModelsOfType, getAvailableOfType, getModelOfType, classify, generateImages, getProviderDisplayName, getProviderAuth, getApiKeyForProvider, isUsingOAuth, registerProvider, unregisterProvider, registerVirtualModel, unregisterVirtualModel, getRegisteredProviderConfig, getRegisteredNativeProvider, getRegisteredProviderIds };
fn arity(method: Method) c_int {
    return switch (method) {
        .getError, .getAll, .getAvailable, .getRegisteredProviderIds => 0,
        .find, .getModelsOfType, .registerProvider, .unregisterVirtualModel => 2,
        .findOfType, .stream, .streamSimple, .complete, .getAvailableOfType, .getModelOfType, .classify, .generateImages => 3,
        else => 1,
    };
}
pub fn install(engine: *engine_mod.Engine, proto: c.JSValue) !void {
    inline for (std.meta.fields(Method)) |field| {
        const function = try engine.checked(c.pi_js_function_magic(engine.context, callback, field.name, arity(@enumFromInt(field.value)), @intCast(field.value)));
        if (c.JS_DefinePropertyValueStr(engine.context, proto, field.name, function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
    }
}
fn callback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const method: Method = @enumFromInt(magic);
    var args = [_]c.JSValue{c.pi_js_undefined()} ** 3;
    const count: usize = @intCast(arity(method));
    for (0..@min(count, @as(usize, @intCast(@max(argc, 0))))) |index| args[index] = argv[index];
    return dispatch(engine, receiver, method, args[0..count]) catch |err| sdk.fail(engine, err);
}
fn dispatch(engine: *engine_mod.Engine, receiver: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    const runtime = try sdk.get(engine, receiver, "runtime");
    defer engine.freeValue(runtime);
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    switch (method) {
        .getAll, .getAvailable => {
            const rows = try sdk.invoke(engine, runtime, if (method == .getAll) "getModels" else "getAvailableSnapshot", &.{});
            defer engine.freeValue(rows);
            const global = c.JS_GetGlobalObject(engine.context);
            defer engine.freeValue(global);
            const array = try sdk.get(engine, global, "Array");
            defer engine.freeValue(array);
            return sdk.invoke(engine, array, "from", &.{rows});
        },
        .find => return sdk.invoke(engine, runtime, "getModel", args),
        .findOfType => return sdk.invoke(engine, runtime, "getModelOfType", args),
        .hasConfiguredAuth, .isUsingOAuth => {
            const provider = try sdk.get(engine, first, "provider");
            defer engine.freeValue(provider);
            return sdk.invoke(engine, runtime, @tagName(method), &.{provider});
        },
        .getProviderAuth => return sdk.invoke(engine, runtime, "getAuth", args),
        .getProviderDisplayName => {
            const provider = try sdk.invoke(engine, runtime, "getProvider", &.{first});
            defer engine.freeValue(provider);
            const name = if (c.JS_IsObject(provider)) try sdk.get(engine, provider, "name") else c.pi_js_undefined();
            if (!c.JS_IsNull(name) and !c.JS_IsUndefined(name)) return name;
            engine.freeValue(name);
            return c.JS_DupValue(engine.context, first);
        },
        .registerProvider => {
            if (!c.JS_IsString(first)) {
                const result = try sdk.invoke(engine, runtime, "registerNativeProvider", &.{first});
                engine.freeValue(result);
                return c.pi_js_undefined();
            }
            if (args.len < 2 or c.JS_ToBool(engine.context, args[1]) != 1) {
                const failure = try engine.checked(c.JS_NewError(engine.context));
                defer engine.freeValue(failure);
                try sdk.put(engine, failure, "message", try sdk.text(engine, "Provider config is required when registering by name"));
                _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, failure));
                return error.JavaScriptException;
            }
            const result = try sdk.invoke(engine, runtime, "registerProvider", args);
            engine.freeValue(result);
            return c.pi_js_undefined();
        },
        .unregisterProvider, .registerVirtualModel, .unregisterVirtualModel => {
            const result = try sdk.invoke(engine, runtime, @tagName(method), args);
            engine.freeValue(result);
            return c.pi_js_undefined();
        },
        .getRegisteredProviderConfig => {
            return sdk.invoke(engine, runtime, "getRegisteredProviderConfig", &.{first});
        },
        .getApiKeyForProvider, .getApiKeyAndHeaders => return auth(engine, runtime, first, method == .getApiKeyAndHeaders),
        else => return sdk.invoke(engine, runtime, @tagName(method), args),
    }
}
fn auth(engine: *engine_mod.Engine, runtime: c.JSValue, input: c.JSValue, headers: bool) !c.JSValue {
    const job = try sdk.object(engine);
    defer engine.freeValue(job);
    try sdk.put(engine, job, "runtime", c.JS_DupValue(engine.context, runtime));
    try sdk.put(engine, job, "input", c.JS_DupValue(engine.context, input));
    var data = [_]c.JSValue{job};
    const good = try engine.checked(c.JS_NewCFunctionData2(engine.context, authCallback, "registryAuth", 1, if (headers) 0 else 2, 1, &data));
    defer engine.freeValue(good);
    const bad = try engine.checked(c.JS_NewCFunctionData2(engine.context, authCallback, "registryAuthFailure", 1, if (headers) 1 else 3, 1, &data));
    defer engine.freeValue(bad);
    const pending = sdk.invoke(engine, runtime, "getAuth", &.{input}) catch |err| {
        if (err != error.JavaScriptException) return err;
        const caught = c.JS_DupValue(engine.context, engine.captured_exception orelse return err);
        defer engine.freeValue(caught);
        const result = try finishAuth(engine, job, caught, if (headers) 1 else 3);
        defer engine.freeValue(result);
        return sdk.promise(engine, result);
    };
    defer engine.freeValue(pending);
    return sdk.invoke(engine, pending, "then", &.{ good, bad });
}
fn authCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, stage: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return finishAuth(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined(), stage) catch |err| {
        if (err == error.JavaScriptException and stage == 0) {
            const caught = c.JS_DupValue(engine.context, engine.captured_exception orelse return sdk.fail(engine, err));
            defer engine.freeValue(caught);
            return finishAuth(engine, data[0], caught, 1) catch |failure| sdk.fail(engine, failure);
        }
        return sdk.fail(engine, err);
    };
}
fn isError(engine: *engine_mod.Engine, value: c.JSValue) bool {
    _ = engine;
    return c.JS_IsError(value);
}
pub fn finishAuth(engine: *engine_mod.Engine, job: c.JSValue, value: c.JSValue, stage: c_int) !c.JSValue {
    if (stage == 3) return c.pi_js_undefined();
    const result = try sdk.object(engine);
    var result_owned = true;
    errdefer if (result_owned) engine.freeValue(result);
    if (stage == 1) {
        const cause = if (isError(engine, value)) try sdk.get(engine, value, "cause") else c.pi_js_undefined();
        defer engine.freeValue(cause);
        const source = if (isError(engine, cause)) cause else value;
        const message = if (isError(engine, source)) try sdk.get(engine, source, "message") else try engine.checked(c.JS_ToString(engine.context, source));
        defer engine.freeValue(message);
        const raw = try engine.toString(message);
        defer engine.gpa.free(raw);
        if (std.mem.eql(u8, raw, "authHeader requires a resolved API key")) {
            engine.freeValue(result);
            result_owned = false;
            return missingKey(engine, job);
        }
        try sdk.put(engine, result, "ok", c.pi_js_bool(engine.context, 0));
        try sdk.put(engine, result, "error", c.JS_DupValue(engine.context, message));
        return result;
    }
    if (!c.JS_IsUndefined(value) and !c.JS_IsNull(value)) {
        const resolved = try sdk.get(engine, value, "auth");
        defer engine.freeValue(resolved);
        if (stage == 2) {
            engine.freeValue(result);
            result_owned = false;
            return sdk.get(engine, resolved, "apiKey");
        }
        try sdk.put(engine, result, "ok", c.pi_js_bool(engine.context, 1));
        inline for (.{ "apiKey", "headers" }) |field| try sdk.put(engine, result, field, try sdk.get(engine, resolved, field));
        const url = try sdk.get(engine, resolved, "baseUrl");
        defer engine.freeValue(url);
        if (c.JS_ToBool(engine.context, url) == 1) try sdk.put(engine, result, "baseUrl", c.JS_DupValue(engine.context, url));
        try sdk.put(engine, result, "env", try sdk.get(engine, value, "env"));
        return result;
    }
    if (stage == 2) {
        engine.freeValue(result);
        result_owned = false;
        return c.pi_js_undefined();
    }
    // Source's unconfigured-auth compatibility path is asynchronous only by
    // virtue of the surrounding auth call; configured headers resolve here.
    engine.freeValue(result);
    result_owned = false;
    return @import("native_sdk_registry_compat.zig").start(engine, job);
}
pub fn missingKey(engine: *engine_mod.Engine, job: c.JSValue) !c.JSValue {
    const model = try sdk.get(engine, job, "input");
    defer engine.freeValue(model);
    const provider = try sdk.get(engine, model, "provider");
    defer engine.freeValue(provider);
    const name = try engine.toString(provider);
    defer engine.gpa.free(name);
    const message = try std.fmt.allocPrint(engine.gpa, "No API key found for \"{s}\"", .{name});
    defer engine.gpa.free(message);
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "ok", c.pi_js_bool(engine.context, 0));
    try sdk.put(engine, result, "error", try sdk.text(engine, message));
    return result;
}
