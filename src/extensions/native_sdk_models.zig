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
    const result = (switch (magic) {
        0 => readCredentialOptions(engine, data[0], input, if (argc > 1) args[1] else c.pi_js_undefined()),
        1 => environment(engine, data[0], input),
        2 => builtinModels(engine, data[0], false),
        3 => builtinModels(engine, data[0], true),
        4 => builtinAuth(engine, data[0], input, false),
        5 => builtinAuth(engine, data[0], input, true),
        6 => modifyCredential(engine, data[0], if (argc > 0) args[0..@intCast(argc)] else &.{}),
        7 => listCredentials(engine, data[0], input),
        8 => fileExists(engine, input),
        else => error.NativeSDKMethodUnavailable,
    }) catch |err| {
        if (magic != 0 and magic != 7) return sdk.fail(engine, err);
        _ = sdk.fail(engine, err);
        const failure = c.JS_GetException(context);
        defer engine.freeValue(failure);
        const global = c.JS_GetGlobalObject(context);
        defer engine.freeValue(global);
        const promise = sdk.get(engine, global, "Promise") catch |get_error| return sdk.fail(engine, get_error);
        defer engine.freeValue(promise);
        return sdk.invoke(engine, promise, "reject", &.{failure}) catch |reject_error| sdk.fail(engine, reject_error);
    };
    if (magic == 0 or magic == 7) {
        defer engine.freeValue(result);
        return sdk.promise(engine, result) catch |err| sdk.fail(engine, err);
    }
    return result;
}
fn function(engine: *engine_mod.Engine, target: c.JSValue, name: [*:0]const u8, magic: c_int, captured: c.JSValue) !void {
    var data = [_]c.JSValue{captured};
    try sdk.put(engine, target, name, try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, name, 1, magic, 1, &data)));
}
pub fn credentials(engine: *engine_mod.Engine, data: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try function(engine, result, "read", 0, data);
    try function(engine, result, "modify", 6, data);
    try function(engine, result, "list", 7, data);
    return result;
}
pub fn readCredential(engine: *engine_mod.Engine, data: c.JSValue, id: c.JSValue) !c.JSValue {
    return readCredentialOptions(engine, data, id, c.pi_js_undefined());
}
fn modifyCredential(engine: *engine_mod.Engine, data: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const options = try sdk.get(engine, data, "options");
    defer engine.freeValue(options);
    const supplied = try sdk.get(engine, options, "credentials");
    defer engine.freeValue(supplied);
    if (!c.JS_IsObject(supplied)) return error.NativeSDKCredentialModifyUnavailable;
    return sdk.invoke(engine, supplied, "modify", args);
}
pub fn readCredentialOptions(engine: *engine_mod.Engine, data: c.JSValue, id: c.JSValue, operation_options: c.JSValue) !c.JSValue {
    if (c.JS_IsObject(operation_options)) {
        const signal = try sdk.get(engine, operation_options, "signal");
        defer engine.freeValue(signal);
        if (c.JS_IsObject(signal)) {
            const checked = try sdk.invoke(engine, signal, "throwIfAborted", &.{});
            engine.freeValue(checked);
        }
    }
    const keys = try sdk.get(engine, data, "keys");
    defer engine.freeValue(keys);
    const key = try property(engine, keys, id);
    defer engine.freeValue(key);
    if (c.JS_IsString(key) and c.JS_ToBool(engine.context, key) == 1) {
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
    if (c.JS_IsObject(supplied)) return sdk.invoke(engine, supplied, "read", &.{ id, operation_options });
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
pub fn listCredentials(engine: *engine_mod.Engine, data: c.JSValue, options: c.JSValue) !c.JSValue {
    const configured = try sdk.get(engine, data, "options");
    defer engine.freeValue(configured);
    const supplied = try sdk.get(engine, configured, "credentials");
    defer engine.freeValue(supplied);
    const pending = if (c.JS_IsObject(supplied)) try sdk.invoke(engine, supplied, "list", &.{options}) else try defaultCredentialList(engine, data);
    defer engine.freeValue(pending);
    const adopted = try sdk.promise(engine, pending);
    defer engine.freeValue(adopted);
    var captured = [_]c.JSValue{ data, options };
    const done = try engine.checked(c.JS_NewCFunctionData2(engine.context, listCompleted, "runtimeCredentialList", 1, 0, 2, &captured));
    defer engine.freeValue(done);
    return sdk.invoke(engine, adopted, "then", &.{done});
}
fn defaultCredentialList(engine: *engine_mod.Engine, data: c.JSValue) !c.JSValue {
    const output = try sdk.array(engine);
    errdefer engine.freeValue(output);
    const path = try sdk.get(engine, data, "authPath");
    defer engine.freeValue(path);
    if (engine.native_io == null or !c.JS_IsString(path)) return output;
    const filename = try engine.toString(path);
    defer engine.gpa.free(filename);
    const raw = std.Io.Dir.cwd().readFileAlloc(engine.native_io.?, filename, engine.gpa, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return output,
        else => return err,
    };
    defer engine.gpa.free(raw);
    const stored = try sdk.jsonObject(engine, raw);
    defer engine.freeValue(stored);
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, stored, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for (0..count) |index| {
        const credential = try engine.checked(c.JS_GetProperty(engine.context, stored, names[index].atom));
        defer engine.freeValue(credential);
        const entry = try sdk.object(engine);
        defer engine.freeValue(entry);
        try sdk.put(engine, entry, "providerId", try engine.checked(c.JS_AtomToString(engine.context, names[index].atom)));
        try sdk.put(engine, entry, "type", try sdk.get(engine, credential, "type"));
        try sdk.append(engine, output, c.JS_DupValue(engine.context, entry));
    }
    return output;
}
fn listCompleted(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return mergeCredentialList(engine, data[0], data[1], if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn mergeCredentialList(engine: *engine_mod.Engine, data: c.JSValue, options: c.JSValue, entries: c.JSValue) !c.JSValue {
    if (c.JS_IsObject(options)) {
        const signal = try sdk.get(engine, options, "signal");
        defer engine.freeValue(signal);
        if (c.JS_IsObject(signal)) {
            const checked = try sdk.invoke(engine, signal, "throwIfAborted", &.{});
            engine.freeValue(checked);
        }
    }
    const map = try @import("native_sdk_auth_snapshot.zig").collection(engine, "Map");
    defer engine.freeValue(map);
    for (0..try sdk.length(engine, entries)) |index| {
        const entry = try engine.checked(c.JS_GetPropertyUint32(engine.context, entries, @intCast(index)));
        defer engine.freeValue(entry);
        const id = try sdk.get(engine, entry, "providerId");
        defer engine.freeValue(id);
        const ignored = try sdk.invoke(engine, map, "set", &.{ id, entry });
        engine.freeValue(ignored);
    }
    const keys = try sdk.get(engine, data, "keys");
    defer engine.freeValue(keys);
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, keys, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for (0..count) |index| {
        const key = try engine.checked(c.JS_GetProperty(engine.context, keys, names[index].atom));
        defer engine.freeValue(key);
        if (c.JS_IsUndefined(key)) continue;
        const id = try engine.checked(c.JS_AtomToString(engine.context, names[index].atom));
        defer engine.freeValue(id);
        const entry = try sdk.object(engine);
        defer engine.freeValue(entry);
        try sdk.put(engine, entry, "providerId", c.JS_DupValue(engine.context, id));
        try sdk.put(engine, entry, "type", try sdk.text(engine, "api_key"));
        const ignored = try sdk.invoke(engine, map, "set", &.{ id, entry });
        engine.freeValue(ignored);
    }
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const array = try sdk.get(engine, global, "Array");
    defer engine.freeValue(array);
    const values = try sdk.invoke(engine, map, "values", &.{});
    defer engine.freeValue(values);
    return sdk.invoke(engine, array, "from", &.{values});
}
fn environment(engine: *engine_mod.Engine, options: c.JSValue, name: c.JSValue) !c.JSValue {
    const overlay = if (c.JS_IsObject(options)) try sdk.get(engine, options, "env") else c.pi_js_undefined();
    defer engine.freeValue(overlay);
    if (c.JS_IsObject(overlay)) {
        const value = try property(engine, overlay, name);
        defer engine.freeValue(value);
        if (c.JS_ToBool(engine.context, value) == 1) return sdk.promise(engine, value);
    }
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
        try @import("native_sdk_chat_transport.zig").install(engine, provider);
        const registered = try sdk.invoke(engine, catalog, "setProvider", &.{provider});
        engine.freeValue(registered);
    }
}

pub fn authContext(engine: *engine_mod.Engine, options: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try function(engine, result, "env", 1, options);
    try function(engine, result, "fileExists", 8, options);
    return result;
}
pub fn resolveAuth(engine: *engine_mod.Engine, data: c.JSValue, input: c.JSValue, overrides: c.JSValue) !c.JSValue {
    return @import("native_sdk_auth_resolution.zig").start(engine, data, input, overrides);
}
pub fn finishAuth(engine: *engine_mod.Engine, job: c.JSValue, value: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(value)) return c.JS_DupValue(engine.context, value);
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try copy(engine, result, value);
    const original_auth = try sdk.get(engine, value, "auth");
    defer engine.freeValue(original_auth);
    const auth = try sdk.object(engine);
    defer engine.freeValue(auth);
    try copy(engine, auth, original_auth);
    try sdk.put(engine, result, "auth", c.JS_DupValue(engine.context, auth));
    const input = try sdk.get(engine, job, "input");
    defer engine.freeValue(input);
    if (c.JS_IsObject(input)) {
        const headers = try sdk.get(engine, input, "headers");
        defer engine.freeValue(headers);
        const previous = try sdk.get(engine, auth, "headers");
        defer engine.freeValue(previous);
        if (c.JS_IsObject(headers) or c.JS_IsObject(previous)) try sdk.put(engine, auth, "headers", try @import("native_sdk_model_headers.zig").merge(engine, previous, headers));
    }
    return result;
}
fn fileExists(engine: *engine_mod.Engine, input: c.JSValue) !c.JSValue {
    const path = try engine.toString(input);
    defer engine.gpa.free(path);
    var exists = true;
    std.Io.Dir.cwd().access(engine.native_io orelse return error.NativeSDKRequiresIO, path, .{}) catch {
        exists = false;
    };
    return sdk.promise(engine, c.pi_js_bool(engine.context, @intFromBool(exists)));
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
    const pending_auth = try resolveAuth(engine, data, model, input_options);
    defer engine.freeValue(pending_auth);
    const resolved = try engine.awaitValue(pending_auth);
    defer engine.freeValue(resolved);
    if (!c.JS_IsObject(resolved)) return error.NativeSDKProviderNotConfigured;
    const authentication = try sdk.get(engine, resolved, "auth");
    defer engine.freeValue(authentication);
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    try copy(engine, options, input_options);
    const explicit_key = if (c.JS_IsObject(input_options)) try sdk.get(engine, input_options, "apiKey") else c.pi_js_undefined();
    defer engine.freeValue(explicit_key);
    try sdk.put(engine, options, "apiKey", if (c.JS_IsUndefined(explicit_key) or c.JS_IsNull(explicit_key)) try sdk.get(engine, authentication, "apiKey") else c.JS_DupValue(engine.context, explicit_key));
    const initial_headers = try sdk.get(engine, authentication, "headers");
    defer engine.freeValue(initial_headers);
    const added_headers = if (c.JS_IsObject(input_options)) try sdk.get(engine, input_options, "headers") else c.pi_js_undefined();
    defer engine.freeValue(added_headers);
    var headers = try @import("native_sdk_model_headers.zig").merge(engine, initial_headers, added_headers);
    defer engine.freeValue(headers);
    const transform = try sdk.get(engine, options, "transformHeaders");
    defer engine.freeValue(transform);
    if (c.JS_IsFunction(engine.context, transform)) {
        const transform_input = if (c.JS_IsUndefined(headers) or c.JS_IsNull(headers)) try sdk.object(engine) else c.JS_DupValue(engine.context, headers);
        defer engine.freeValue(transform_input);
        var values = [_]c.JSValue{transform_input};
        const pending = try engine.checked(c.JS_Call(engine.context, transform, c.pi_js_undefined(), 1, &values));
        defer engine.freeValue(pending);
        const transformed = try engine.awaitValue(pending);
        engine.freeValue(headers);
        headers = transformed;
    }
    try sdk.put(engine, options, "headers", c.JS_DupValue(engine.context, headers));
    const auth_env = try sdk.get(engine, resolved, "env");
    defer engine.freeValue(auth_env);
    const input_env = if (c.JS_IsObject(input_options)) try sdk.get(engine, input_options, "env") else c.pi_js_undefined();
    defer engine.freeValue(input_env);
    const env = if (c.JS_ToBool(engine.context, auth_env) == 1 or c.JS_ToBool(engine.context, input_env) == 1) try sdk.object(engine) else c.pi_js_undefined();
    defer engine.freeValue(env);
    if (c.JS_IsObject(env)) {
        try copy(engine, env, auth_env);
        try copy(engine, env, input_env);
    }
    try sdk.put(engine, options, "env", c.JS_DupValue(engine.context, env));
    const atom = c.JS_NewAtom(engine.context, "transformHeaders");
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DeleteProperty(engine.context, options, atom, 0) < 0) return error.JavaScriptException;
    const base = try sdk.get(engine, authentication, "baseUrl");
    defer engine.freeValue(base);
    const request_model = if (c.JS_ToBool(engine.context, base) == 1) try sdk.object(engine) else c.JS_DupValue(engine.context, model);
    defer engine.freeValue(request_model);
    if (c.JS_ToBool(engine.context, base) == 1) {
        try copy(engine, request_model, model);
        try sdk.put(engine, request_model, "baseUrl", c.JS_DupValue(engine.context, base));
    }
    const id = try sdk.get(engine, model, "provider");
    defer engine.freeValue(id);
    const catalog = try sdk.get(engine, data, "models");
    defer engine.freeValue(catalog);
    const provider = try sdk.invoke(engine, catalog, "getProvider", &.{id});
    defer engine.freeValue(provider);
    return sdk.invoke(engine, provider, method, &.{ request_model, context, options });
}
