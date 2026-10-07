//! SDK credential ownership and provider request preparation. VM values stay
//! on their owning engine; user callbacks are retained as live values.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const engine_mod = @import("engine.zig");
const providers = @import("../ai/providers.zig");
const c = engine_mod.c;

pub fn copy(engine: *engine_mod.Engine, target: c.JSValue, source: c.JSValue) !void {
    if (!c.JS_IsObject(source)) return;
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, source, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    if (count > 65536) return error.NativeSDKPropertyLimit;
    for (0..count) |index| {
        const value = try engine.checked(c.JS_GetProperty(engine.context, source, names[index].atom));
        if (c.JS_DefinePropertyValue(engine.context, target, names[index].atom, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
}
pub fn property(engine: *engine_mod.Engine, target: c.JSValue, key: c.JSValue) !c.JSValue {
    const atom = c.JS_ValueToAtom(engine.context, key);
    if (atom == c.JS_ATOM_NULL) return error.JavaScriptException;
    defer c.JS_FreeAtom(engine.context, atom);
    return engine.checked(c.JS_GetProperty(engine.context, target, atom));
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const input = if (argc > 0) args[0] else c.pi_js_undefined();
    return (switch (magic) {
        0 => readCredential(engine, data[0], input),
        1 => environment(engine, input),
        2 => builtinModels(engine, data[0], false),
        3 => builtinModels(engine, data[0], true),
        4 => builtinAuth(engine, data[0], input, false),
        5 => builtinAuth(engine, data[0], input, true),
        else => error.NativeSDKMethodUnavailable,
    }) catch |err| sdk.fail(engine, err);
}
fn function(engine: *engine_mod.Engine, target: c.JSValue, name: [*:0]const u8, magic: c_int, captured: c.JSValue) !void {
    var data = [_]c.JSValue{captured};
    try sdk.put(engine, target, name, try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, name, 1, magic, 1, &data)));
}
pub fn credentials(engine: *engine_mod.Engine, data: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try function(engine, result, "read", 0, data);
    return result;
}
pub fn readCredential(engine: *engine_mod.Engine, data: c.JSValue, id: c.JSValue) !c.JSValue {
    const keys = try sdk.get(engine, data, "keys");
    defer engine.freeValue(keys);
    const key = try property(engine, keys, id);
    defer engine.freeValue(key);
    if (c.JS_IsString(key)) {
        const value = try sdk.object(engine);
        errdefer engine.freeValue(value);
        try sdk.put(engine, value, "type", try sdk.text(engine, "api_key"));
        try sdk.put(engine, value, "key", c.JS_DupValue(engine.context, key));
        return value;
    }
    const options = try sdk.get(engine, data, "options");
    defer engine.freeValue(options);
    const supplied = try sdk.get(engine, options, "credentials");
    defer engine.freeValue(supplied);
    if (c.JS_IsObject(supplied)) return sdk.invoke(engine, supplied, "read", &.{id});
    const path = try sdk.get(engine, data, "authPath");
    defer engine.freeValue(path);
    if (engine.native_io == null or !c.JS_IsString(path)) return c.pi_js_undefined();
    const filename = try engine.toString(path);
    defer engine.gpa.free(filename);
    const raw = std.Io.Dir.cwd().readFileAlloc(engine.native_io.?, filename, engine.gpa, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return c.pi_js_undefined(),
        else => return err,
    };
    defer engine.gpa.free(raw);
    const stored = try sdk.jsonObject(engine, raw);
    defer engine.freeValue(stored);
    return property(engine, stored, id);
}
fn environment(engine: *engine_mod.Engine, name: c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const process = try sdk.get(engine, global, "process");
    defer engine.freeValue(process);
    if (!c.JS_IsObject(process)) return sdk.promise(engine, c.pi_js_undefined());
    const env = try sdk.get(engine, process, "env");
    defer engine.freeValue(env);
    const result = try property(engine, env, name);
    defer engine.freeValue(result);
    return sdk.promise(engine, result);
}
fn builtinModels(engine: *engine_mod.Engine, rows: c.JSValue, all: bool) !c.JSValue {
    if (all) return c.JS_DupValue(engine.context, rows);
    const result = try sdk.array(engine);
    errdefer engine.freeValue(result);
    for (0..try sdk.length(engine, rows)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        const typ = try sdk.get(engine, row, "type");
        defer engine.freeValue(typ);
        const kind = c.JS_ToCString(engine.context, typ) orelse return error.JavaScriptException;
        defer c.JS_FreeCString(engine.context, kind);
        if (std.mem.eql(u8, std.mem.span(kind), "chat")) try sdk.append(engine, result, c.JS_DupValue(engine.context, row));
    }
    return result;
}
fn builtinAuth(engine: *engine_mod.Engine, id: c.JSValue, options: c.JSValue, resolve: bool) !c.JSValue {
    const credential = try sdk.get(engine, options, "credential");
    defer engine.freeValue(credential);
    const key = if (c.JS_IsObject(credential)) try sdk.get(engine, credential, "key") else c.pi_js_undefined();
    defer engine.freeValue(key);
    const source = try sdk.text(engine, "stored");
    defer engine.freeValue(source);
    if (!c.JS_IsString(key)) {
        const raw = try engine.toString(id);
        defer engine.gpa.free(raw);
        const provider = providers.Provider.fromString(raw) orelse return c.pi_js_undefined();
        const env_name = providers.credentialEnvName(provider) orelse return c.pi_js_undefined();
        const context_value = try sdk.get(engine, options, "ctx");
        defer engine.freeValue(context_value);
        const name = try sdk.text(engine, env_name);
        defer engine.freeValue(name);
        const pending = try sdk.invoke(engine, context_value, "env", &.{name});
        defer engine.freeValue(pending);
        const promise = try sdk.promise(engine, pending);
        defer engine.freeValue(promise);
        var continuation_data = [_]c.JSValue{ name, c.pi_js_bool(engine.context, @intFromBool(resolve)) };
        const continuation = try engine.checked(c.JS_NewCFunctionData2(engine.context, builtinAuthResolved, "builtinAuthResolved", 1, 0, 2, &continuation_data));
        defer engine.freeValue(continuation);
        return sdk.invoke(engine, promise, "then", &.{continuation});
    }
    return builtinAuthResult(engine, key, source, resolve);
}
fn builtinAuthResolved(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return builtinAuthResult(engine, if (argc > 0) args[0] else c.pi_js_undefined(), data[0], c.JS_ToBool(context, data[1]) == 1) catch |err| sdk.fail(engine, err);
}
fn builtinAuthResult(engine: *engine_mod.Engine, key: c.JSValue, source: c.JSValue, resolve: bool) !c.JSValue {
    if (!c.JS_IsString(key)) return c.pi_js_undefined();
    const raw_key = c.JS_ToCString(engine.context, key) orelse return error.JavaScriptException;
    defer c.JS_FreeCString(engine.context, raw_key);
    if (std.mem.span(raw_key).len == 0) return c.pi_js_undefined();
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "source", c.JS_DupValue(engine.context, source));
    if (resolve) {
        const auth = try sdk.object(engine);
        defer engine.freeValue(auth);
        try sdk.put(engine, auth, "apiKey", c.JS_DupValue(engine.context, key));
        try sdk.put(engine, result, "auth", c.JS_DupValue(engine.context, auth));
    } else try sdk.put(engine, result, "type", try sdk.text(engine, "api_key"));
    return result;
}
pub fn seedBuiltins(engine: *engine_mod.Engine, catalog: c.JSValue) !void {
    const document = try sdk.jsonObject(engine, @embedFile("../ai/catalog_source.json"));
    defer engine.freeValue(document);
    const models = try sdk.get(engine, document, "models");
    defer engine.freeValue(models);
    const groups = try sdk.object(engine);
    defer engine.freeValue(groups);
    for (0..try sdk.length(engine, models)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, models, @intCast(index)));
        defer engine.freeValue(row);
        const id = try sdk.get(engine, row, "provider");
        defer engine.freeValue(id);
        const name = c.JS_ToCString(engine.context, id) orelse return error.JavaScriptException;
        defer c.JS_FreeCString(engine.context, name);
        var rows = try sdk.get(engine, groups, name);
        defer engine.freeValue(rows);
        if (!c.JS_IsArray(rows)) {
            const created = try sdk.array(engine);
            engine.freeValue(rows);
            rows = created;
            try sdk.put(engine, groups, name, c.JS_DupValue(engine.context, rows));
        }
        try sdk.append(engine, rows, c.JS_DupValue(engine.context, row));
    }
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, groups, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for (0..count) |index| {
        const id = try engine.checked(c.JS_AtomToValue(engine.context, names[index].atom));
        defer engine.freeValue(id);
        const rows = try engine.checked(c.JS_GetProperty(engine.context, groups, names[index].atom));
        defer engine.freeValue(rows);
        const provider = try sdk.object(engine);
        defer engine.freeValue(provider);
        try sdk.put(engine, provider, "id", c.JS_DupValue(engine.context, id));
        try function(engine, provider, "getModels", 2, rows);
        try function(engine, provider, "getAllModels", 3, rows);
        const auth = try sdk.object(engine);
        defer engine.freeValue(auth);
        const method = try sdk.object(engine);
        defer engine.freeValue(method);
        try function(engine, method, "check", 4, id);
        try function(engine, method, "resolve", 5, id);
        try sdk.put(engine, auth, "apiKey", c.JS_DupValue(engine.context, method));
        try sdk.put(engine, provider, "auth", c.JS_DupValue(engine.context, auth));
        try @import("native_sdk_operations.zig").install(engine, provider);
        const registered = try sdk.invoke(engine, catalog, "setProvider", &.{provider});
        engine.freeValue(registered);
    }
}

pub fn resolveAuth(engine: *engine_mod.Engine, data: c.JSValue, input: c.JSValue, overrides: c.JSValue) !c.JSValue {
    const opts = if (c.JS_IsObject(overrides)) c.JS_DupValue(engine.context, overrides) else try sdk.object(engine);
    defer engine.freeValue(opts);
    const initial_signal = try sdk.get(engine, opts, "signal");
    defer engine.freeValue(initial_signal);
    if (c.JS_IsObject(initial_signal)) {
        const checked = try sdk.invoke(engine, initial_signal, "throwIfAborted", &.{});
        engine.freeValue(checked);
    }
    const id = if (c.JS_IsString(input)) c.JS_DupValue(engine.context, input) else try sdk.get(engine, input, "provider");
    defer engine.freeValue(id);
    const catalog = try sdk.get(engine, data, "models");
    defer engine.freeValue(catalog);
    const provider = try sdk.invoke(engine, catalog, "getProvider", &.{id});
    defer engine.freeValue(provider);
    if (!c.JS_IsObject(provider)) return c.pi_js_undefined();
    const authentication = try sdk.get(engine, provider, "auth");
    defer engine.freeValue(authentication);
    const api = try sdk.get(engine, authentication, "apiKey");
    defer engine.freeValue(api);
    const requested = try sdk.get(engine, opts, "apiKey");
    defer engine.freeValue(requested);
    const credential = if (!c.JS_IsUndefined(requested)) explicit: {
        const value = try sdk.object(engine);
        errdefer engine.freeValue(value);
        try sdk.put(engine, value, "type", try sdk.text(engine, "api_key"));
        try sdk.put(engine, value, "key", c.JS_DupValue(engine.context, requested));
        break :explicit value;
    } else loaded: {
        const pending = try readCredential(engine, data, id);
        defer engine.freeValue(pending);
        break :loaded try engine.awaitValue(pending);
    };
    defer engine.freeValue(credential);
    if (c.JS_IsObject(credential)) {
        const kind = try sdk.get(engine, credential, "type");
        defer engine.freeValue(kind);
        const expected = try sdk.text(engine, "api_key");
        defer engine.freeValue(expected);
        if (!c.JS_IsStrictEqual(engine.context, kind, expected)) return c.pi_js_undefined();
    }
    if (!c.JS_IsObject(api)) return c.pi_js_undefined();
    const parameters = try sdk.object(engine);
    defer engine.freeValue(parameters);
    try sdk.put(engine, parameters, "credential", c.JS_DupValue(engine.context, credential));
    const ctx = try sdk.object(engine);
    defer engine.freeValue(ctx);
    try function(engine, ctx, "env", 1, data);
    try sdk.put(engine, parameters, "ctx", c.JS_DupValue(engine.context, ctx));
    const signal = try sdk.get(engine, opts, "signal");
    defer engine.freeValue(signal);
    if (c.JS_IsObject(signal)) {
        const checked = try sdk.invoke(engine, signal, "throwIfAborted", &.{});
        engine.freeValue(checked);
        try sdk.put(engine, parameters, "signal", c.JS_DupValue(engine.context, signal));
    } else {
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const ctor = try sdk.get(engine, global, "AbortController");
        defer engine.freeValue(ctor);
        const controller = try engine.checked(c.JS_CallConstructor(engine.context, ctor, 0, null));
        defer engine.freeValue(controller);
        try sdk.put(engine, parameters, "signal", try sdk.get(engine, controller, "signal"));
    }
    const pending = try sdk.invoke(engine, api, "resolve", &.{parameters});
    defer engine.freeValue(pending);
    const result = try engine.awaitValue(pending);
    errdefer engine.freeValue(result);
    if (c.JS_IsObject(result) and c.JS_IsObject(input)) {
        const resolved = try sdk.get(engine, result, "auth");
        defer engine.freeValue(resolved);
        const headers = try sdk.get(engine, input, "headers");
        defer engine.freeValue(headers);
        const previous = try sdk.get(engine, resolved, "headers");
        defer engine.freeValue(previous);
        if (c.JS_IsObject(headers) or c.JS_IsObject(previous)) try sdk.put(engine, resolved, "headers", try mergedHeaders(engine, previous, headers));
    }
    return result;
}
pub fn mergedHeaders(engine: *engine_mod.Engine, base: c.JSValue, updates: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try copy(engine, result, base);
    try copy(engine, result, updates);
    return result;
}

pub fn operationError(engine: *engine_mod.Engine, model: c.JSValue, images: bool, message: []const u8, aborted: bool) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "api", try sdk.get(engine, model, "api"));
    try sdk.put(engine, result, "provider", try sdk.get(engine, model, "provider"));
    try sdk.put(engine, result, "model", try sdk.get(engine, model, "id"));
    try sdk.put(engine, result, if (images) "output" else "answers", if (images) try sdk.array(engine) else try sdk.object(engine));
    try sdk.put(engine, result, "stopReason", try sdk.text(engine, if (aborted) "aborted" else "error"));
    try sdk.put(engine, result, "errorMessage", try sdk.text(engine, message));
    try sdk.put(engine, result, "timestamp", c.JS_NewInt64(engine.context, if (engine.native_io) |io| std.Io.Clock.real.now(io).toMilliseconds() else 0));
    return result;
}

pub fn typedOperation(engine: *engine_mod.Engine, data: c.JSValue, model: c.JSValue, context: c.JSValue, options: c.JSValue, images: bool) !c.JSValue {
    const kind = try sdk.get(engine, model, "type");
    defer engine.freeValue(kind);
    const expected = try sdk.text(engine, if (images) "image" else "classifier");
    defer engine.freeValue(expected);
    var invalid = !c.JS_IsStrictEqual(engine.context, kind, expected);
    var has_images = false;
    if (!images and !invalid) {
        const attachments = try sdk.get(engine, context, "images");
        defer engine.freeValue(attachments);
        if (c.JS_IsArray(attachments) and try sdk.length(engine, attachments) > 0) {
            const input = try sdk.get(engine, model, "input");
            defer engine.freeValue(input);
            const image_kind = try sdk.text(engine, "image");
            defer engine.freeValue(image_kind);
            var allowed = false;
            if (c.JS_IsArray(input)) for (0..try sdk.length(engine, input)) |index| {
                const item = try engine.checked(c.JS_GetPropertyUint32(engine.context, input, @intCast(index)));
                defer engine.freeValue(item);
                if (c.JS_IsStrictEqual(engine.context, item, image_kind)) allowed = true;
            };
            invalid = !allowed;
            has_images = invalid;
        }
    }
    if (invalid) {
        const provider = try sdk.get(engine, model, "provider");
        defer engine.freeValue(provider);
        const id = try sdk.get(engine, model, "id");
        defer engine.freeValue(id);
        const provider_name = try engine.toString(provider);
        defer engine.gpa.free(provider_name);
        const model_name = try engine.toString(id);
        defer engine.gpa.free(model_name);
        const message = try std.fmt.allocPrint(engine.gpa, "Model {s}/{s} {s}", .{ provider_name, model_name, if (has_images) "does not accept image input" else if (images) "is not an image model" else "is not a classifier model" });
        defer engine.gpa.free(message);
        return operationError(engine, model, images, message, false);
    }
    return typedRequest(engine, data, model, context, options, images) catch |err| {
        if (err == error.OutOfMemory) return err;
        var diagnostic = if (err == error.JavaScriptException and engine.captured_exception != null and c.JS_IsError(engine.captured_exception.?)) try sdk.get(engine, engine.captured_exception.?, "message") else if (err == error.JavaScriptException and engine.captured_exception != null) c.JS_DupValue(engine.context, engine.captured_exception.?) else c.pi_js_undefined();
        defer engine.freeValue(diagnostic);
        if (c.JS_IsUndefined(diagnostic)) {
            engine.freeValue(diagnostic);
            diagnostic = try sdk.text(engine, @errorName(err));
        }
        const message = try engine.toString(diagnostic);
        defer engine.gpa.free(message);
        const signal = if (c.JS_IsObject(options)) try sdk.get(engine, options, "signal") else c.pi_js_undefined();
        defer engine.freeValue(signal);
        const aborted = if (c.JS_IsObject(signal)) try sdk.get(engine, signal, "aborted") else c.pi_js_undefined();
        defer engine.freeValue(aborted);
        return operationError(engine, model, images, message, c.JS_ToBool(engine.context, aborted) == 1);
    };
}
fn typedRequest(engine: *engine_mod.Engine, data: c.JSValue, model: c.JSValue, context: c.JSValue, options: c.JSValue, images: bool) !c.JSValue {
    const pending = try request(engine, data, model, context, options, if (images) "generateImages" else "classify");
    defer engine.freeValue(pending);
    return engine.awaitValue(pending);
}

pub fn request(engine: *engine_mod.Engine, data: c.JSValue, model: c.JSValue, context: c.JSValue, input_options: c.JSValue, method: [*:0]const u8) !c.JSValue {
    const resolved = try resolveAuth(engine, data, model, input_options);
    defer engine.freeValue(resolved);
    if (!c.JS_IsObject(resolved)) return error.NativeSDKProviderNotConfigured;
    const authentication = try sdk.get(engine, resolved, "auth");
    defer engine.freeValue(authentication);
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    try copy(engine, options, authentication);
    try copy(engine, options, input_options);
    const initial_headers = try sdk.get(engine, authentication, "headers");
    defer engine.freeValue(initial_headers);
    const added_headers = if (c.JS_IsObject(input_options)) try sdk.get(engine, input_options, "headers") else c.pi_js_undefined();
    defer engine.freeValue(added_headers);
    var headers = try mergedHeaders(engine, initial_headers, added_headers);
    defer engine.freeValue(headers);
    const transform = try sdk.get(engine, options, "transformHeaders");
    defer engine.freeValue(transform);
    if (c.JS_IsFunction(engine.context, transform)) {
        var values = [_]c.JSValue{headers};
        const pending = try engine.checked(c.JS_Call(engine.context, transform, c.pi_js_undefined(), 1, &values));
        defer engine.freeValue(pending);
        const transformed = try engine.awaitValue(pending);
        engine.freeValue(headers);
        headers = transformed;
    }
    try sdk.put(engine, options, "headers", c.JS_DupValue(engine.context, headers));
    const atom = c.JS_NewAtom(engine.context, "transformHeaders");
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DeleteProperty(engine.context, options, atom, 0) < 0) return error.JavaScriptException;
    const request_model = try sdk.object(engine);
    defer engine.freeValue(request_model);
    try copy(engine, request_model, model);
    const base = try sdk.get(engine, authentication, "baseUrl");
    defer engine.freeValue(base);
    if (c.JS_IsString(base)) try sdk.put(engine, request_model, "baseUrl", c.JS_DupValue(engine.context, base));
    const id = try sdk.get(engine, model, "provider");
    defer engine.freeValue(id);
    const catalog = try sdk.get(engine, data, "models");
    defer engine.freeValue(catalog);
    const provider = try sdk.invoke(engine, catalog, "getProvider", &.{id});
    defer engine.freeValue(provider);
    return sdk.invoke(engine, provider, method, &.{ request_model, context, options });
}
