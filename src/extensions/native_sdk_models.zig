//! SDK credential ownership and provider request preparation. VM values stay
//! on their owning engine; user callbacks are retained as live values.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const engine_mod = @import("engine.zig");
const providers = @import("../ai/providers.zig");
const c = engine_mod.c;

// A direct native allocator outcome is a producer before deferred JS roots
// can publish a later cleanup event. Other typed failures retain their class.
fn nativeAllocation(engine: anytype, result: anytype) @TypeOf(result) {
    return result catch |err| {
        if (@as(anyerror, err) == error.OutOfMemory) _ = engine.throwNativeOutOfMemoryFatal();
        return err;
    };
}
fn nativeText(engine: anytype, value: c.JSValue) anyerror![]u8 {
    try engine.checkNativeEntry();
    return nativeAllocation(engine, engine.toString(value));
}

pub fn copy(engine: *engine_mod.Engine, target: c.JSValue, source: c.JSValue) !void {
    if (!c.JS_IsObject(source)) return;
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    try engine.checkNativeEntry();
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, source, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    if (count > 65536) return error.NativeSDKPropertyLimit;
    for (0..count) |index| {
        try engine.checkNativeEntry();
        const value = try engine.checked(c.JS_GetProperty(engine.context, source, names[index].atom));
        if (c.JS_DefinePropertyValue(engine.context, target, names[index].atom, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
}
pub fn property(engine: *engine_mod.Engine, target: c.JSValue, key: c.JSValue) !c.JSValue {
    const atom = c.JS_ValueToAtom(engine.context, key);
    if (atom == c.JS_ATOM_NULL) return error.JavaScriptException;
    defer c.JS_FreeAtom(engine.context, atom);
    try engine.checkNativeEntry();
    return engine.checked(c.JS_GetProperty(engine.context, target, atom));
}
fn callback(context: ?*c.JSContext, ignored0: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    var frame = @import("native_pending_owner.zig").Frame.init(engine);
    frame.enter() catch return frame.finishCallback(c.pi_js_exception());
    return frame.finishCallback(callbackOwnedBody(context, ignored0, argc, args, magic, data));
}
fn callbackOwnedBody(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) c.JSValue {
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
        const failure = @import("native_agent_async.zig").reason(engine, err) catch |fatal| return sdk.fail(engine, fatal);
        defer engine.releaseNativeValue(failure);
        const global = c.JS_GetGlobalObject(context);
        defer engine.releaseNativeValue(global);
        const promise = sdk.get(engine, global, "Promise") catch |get_error| return sdk.fail(engine, get_error);
        defer engine.releaseNativeValue(promise);
        return sdk.invoke(engine, promise, "reject", &.{failure}) catch |reject_error| sdk.fail(engine, reject_error);
    };
    if (magic == 0 or magic == 7) {
        defer engine.releaseNativeValue(result);
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
    errdefer engine.releaseNativeValue(result);
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
    defer engine.releaseNativeValue(options);
    const supplied = try sdk.get(engine, options, "credentials");
    defer engine.releaseNativeValue(supplied);
    if (!c.JS_IsObject(supplied)) return error.NativeSDKCredentialModifyUnavailable;
    return sdk.invoke(engine, supplied, "modify", args);
}
pub fn readCredentialOptions(engine: *engine_mod.Engine, data: c.JSValue, id: c.JSValue, operation_options: c.JSValue) !c.JSValue {
    if (c.JS_IsObject(operation_options)) {
        const signal = try sdk.get(engine, operation_options, "signal");
        defer engine.releaseNativeValue(signal);
        if (c.JS_IsObject(signal)) {
            const checked = try sdk.invoke(engine, signal, "throwIfAborted", &.{});
            engine.releaseNativeValue(checked);
        }
    }
    const keys = try sdk.get(engine, data, "keys");
    defer engine.releaseNativeValue(keys);
    const key = try property(engine, keys, id);
    defer engine.releaseNativeValue(key);
    if (c.JS_IsString(key) and c.JS_ToBool(engine.context, key) == 1) {
        const value = try sdk.object(engine);
        errdefer engine.releaseNativeValue(value);
        try sdk.put(engine, value, "type", try sdk.text(engine, "api_key"));
        try sdk.put(engine, value, "key", c.JS_DupValue(engine.context, key));
        return value;
    }
    const options = try sdk.get(engine, data, "options");
    defer engine.releaseNativeValue(options);
    const supplied = try sdk.get(engine, options, "credentials");
    defer engine.releaseNativeValue(supplied);
    if (c.JS_IsObject(supplied)) return sdk.invoke(engine, supplied, "read", &.{ id, operation_options });
    const path = try sdk.get(engine, data, "authPath");
    defer engine.releaseNativeValue(path);
    if (engine.native_io == null or !c.JS_IsString(path)) return c.pi_js_undefined();
    const filename = try nativeText(engine, path);
    defer engine.gpa.free(filename);
    const raw = nativeAllocation(engine, std.Io.Dir.cwd().readFileAlloc(engine.native_io.?, filename, engine.gpa, .limited(1024 * 1024))) catch |err| switch (err) {
        error.FileNotFound => return c.pi_js_undefined(),
        else => return err,
    };
    defer engine.gpa.free(raw);
    const stored = try sdk.jsonObject(engine, raw);
    defer engine.releaseNativeValue(stored);
    return property(engine, stored, id);
}
pub fn listCredentials(engine: *engine_mod.Engine, data: c.JSValue, options: c.JSValue) !c.JSValue {
    const configured = try sdk.get(engine, data, "options");
    defer engine.releaseNativeValue(configured);
    const supplied = try sdk.get(engine, configured, "credentials");
    defer engine.releaseNativeValue(supplied);
    const pending = if (c.JS_IsObject(supplied)) try sdk.invoke(engine, supplied, "list", &.{options}) else try defaultCredentialList(engine, data);
    defer engine.releaseNativeValue(pending);
    const adopted = try sdk.promise(engine, pending);
    defer engine.releaseNativeValue(adopted);
    var captured = [_]c.JSValue{ data, options };
    const done = try engine.checked(c.JS_NewCFunctionData2(engine.context, listCompleted, "runtimeCredentialList", 1, 0, 2, &captured));
    defer engine.releaseNativeValue(done);
    return sdk.invoke(engine, adopted, "then", &.{done});
}
fn defaultCredentialList(engine: *engine_mod.Engine, data: c.JSValue) !c.JSValue {
    const output = try sdk.array(engine);
    errdefer engine.releaseNativeValue(output);
    const path = try sdk.get(engine, data, "authPath");
    defer engine.releaseNativeValue(path);
    if (engine.native_io == null or !c.JS_IsString(path)) return output;
    const filename = try nativeText(engine, path);
    defer engine.gpa.free(filename);
    const raw = nativeAllocation(engine, std.Io.Dir.cwd().readFileAlloc(engine.native_io.?, filename, engine.gpa, .limited(1024 * 1024))) catch |err| switch (err) {
        error.FileNotFound => return output,
        else => return err,
    };
    defer engine.gpa.free(raw);
    const stored = try sdk.jsonObject(engine, raw);
    defer engine.releaseNativeValue(stored);
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    try engine.checkNativeEntry();
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, stored, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for (0..count) |index| {
        try engine.checkNativeEntry();
        const credential = try engine.checked(c.JS_GetProperty(engine.context, stored, names[index].atom));
        defer engine.releaseNativeValue(credential);
        const entry = try sdk.object(engine);
        defer engine.releaseNativeValue(entry);
        try sdk.put(engine, entry, "providerId", try engine.checked(c.JS_AtomToString(engine.context, names[index].atom)));
        try sdk.put(engine, entry, "type", try sdk.get(engine, credential, "type"));
        try sdk.append(engine, output, c.JS_DupValue(engine.context, entry));
    }
    return output;
}
fn listCompleted(context: ?*c.JSContext, ignored0: c.JSValue, argc: c_int, args: [*c]c.JSValue, ignored1: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    var frame = @import("native_pending_owner.zig").Frame.init(engine);
    frame.enter() catch return frame.finishCallback(c.pi_js_exception());
    return frame.finishCallback(listCompletedOwnedBody(context, ignored0, argc, args, ignored1, data));
}
fn listCompletedOwnedBody(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return mergeCredentialList(engine, data[0], data[1], if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn mergeCredentialList(engine: *engine_mod.Engine, data: c.JSValue, options: c.JSValue, entries: c.JSValue) !c.JSValue {
    if (c.JS_IsObject(options)) {
        const signal = try sdk.get(engine, options, "signal");
        defer engine.releaseNativeValue(signal);
        if (c.JS_IsObject(signal)) {
            const checked = try sdk.invoke(engine, signal, "throwIfAborted", &.{});
            engine.releaseNativeValue(checked);
        }
    }
    const map = try @import("native_sdk_auth_snapshot.zig").collection(engine, "Map");
    defer engine.releaseNativeValue(map);
    for (0..try sdk.length(engine, entries)) |index| {
        try engine.checkNativeEntry();
        const entry = try engine.checked(c.JS_GetPropertyUint32(engine.context, entries, @intCast(index)));
        defer engine.releaseNativeValue(entry);
        const id = try sdk.get(engine, entry, "providerId");
        defer engine.releaseNativeValue(id);
        const ignored = try sdk.invoke(engine, map, "set", &.{ id, entry });
        engine.releaseNativeValue(ignored);
    }
    const keys = try sdk.get(engine, data, "keys");
    defer engine.releaseNativeValue(keys);
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    try engine.checkNativeEntry();
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, keys, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for (0..count) |index| {
        try engine.checkNativeEntry();
        const key = try engine.checked(c.JS_GetProperty(engine.context, keys, names[index].atom));
        defer engine.releaseNativeValue(key);
        if (c.JS_IsUndefined(key)) continue;
        const id = try engine.checked(c.JS_AtomToString(engine.context, names[index].atom));
        defer engine.releaseNativeValue(id);
        const entry = try sdk.object(engine);
        defer engine.releaseNativeValue(entry);
        try sdk.put(engine, entry, "providerId", c.JS_DupValue(engine.context, id));
        try sdk.put(engine, entry, "type", try sdk.text(engine, "api_key"));
        const ignored = try sdk.invoke(engine, map, "set", &.{ id, entry });
        engine.releaseNativeValue(ignored);
    }
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.releaseNativeValue(global);
    const array = try sdk.get(engine, global, "Array");
    defer engine.releaseNativeValue(array);
    const values = try sdk.invoke(engine, map, "values", &.{});
    defer engine.releaseNativeValue(values);
    return sdk.invoke(engine, array, "from", &.{values});
}
fn environment(engine: *engine_mod.Engine, options: c.JSValue, name: c.JSValue) !c.JSValue {
    const overlay = if (c.JS_IsObject(options)) try sdk.get(engine, options, "env") else c.pi_js_undefined();
    defer engine.releaseNativeValue(overlay);
    if (c.JS_IsObject(overlay)) {
        const value = try property(engine, overlay, name);
        defer engine.releaseNativeValue(value);
        if (c.JS_ToBool(engine.context, value) == 1) return sdk.promise(engine, value);
    }
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.releaseNativeValue(global);
    const process = try sdk.get(engine, global, "process");
    defer engine.releaseNativeValue(process);
    if (!c.JS_IsObject(process)) return sdk.promise(engine, c.pi_js_undefined());
    const env = try sdk.get(engine, process, "env");
    defer engine.releaseNativeValue(env);
    const result = try property(engine, env, name);
    defer engine.releaseNativeValue(result);
    return sdk.promise(engine, result);
}
fn builtinModels(engine: *engine_mod.Engine, rows: c.JSValue, all: bool) !c.JSValue {
    if (all) return c.JS_DupValue(engine.context, rows);
    const result = try sdk.array(engine);
    errdefer engine.releaseNativeValue(result);
    for (0..try sdk.length(engine, rows)) |index| {
        try engine.checkNativeEntry();
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.releaseNativeValue(row);
        const typ = try sdk.get(engine, row, "type");
        defer engine.releaseNativeValue(typ);
        try engine.checkNativeEntry();
        const kind = c.JS_ToCString(engine.context, typ) orelse return error.JavaScriptException;
        defer c.JS_FreeCString(engine.context, kind);
        if (std.mem.eql(u8, std.mem.span(kind), "chat")) try sdk.append(engine, result, c.JS_DupValue(engine.context, row));
    }
    return result;
}
fn builtinAuth(engine: *engine_mod.Engine, id: c.JSValue, options: c.JSValue, resolve: bool) !c.JSValue {
    const credential = try sdk.get(engine, options, "credential");
    defer engine.releaseNativeValue(credential);
    const key = if (c.JS_IsObject(credential)) try sdk.get(engine, credential, "key") else c.pi_js_undefined();
    defer engine.releaseNativeValue(key);
    const source = try sdk.text(engine, "stored");
    defer engine.releaseNativeValue(source);
    if (!c.JS_IsString(key)) {
        const raw = try nativeText(engine, id);
        defer engine.gpa.free(raw);
        const provider = providers.Provider.fromString(raw) orelse return c.pi_js_undefined();
        const env_name = providers.credentialEnvName(provider) orelse return c.pi_js_undefined();
        const context_value = try sdk.get(engine, options, "ctx");
        defer engine.releaseNativeValue(context_value);
        const name = try sdk.text(engine, env_name);
        defer engine.releaseNativeValue(name);
        const pending = try sdk.invoke(engine, context_value, "env", &.{name});
        defer engine.releaseNativeValue(pending);
        const promise = try sdk.promise(engine, pending);
        defer engine.releaseNativeValue(promise);
        var continuation_data = [_]c.JSValue{ name, c.pi_js_bool(engine.context, @intFromBool(resolve)) };
        const continuation = try engine.checked(c.JS_NewCFunctionData2(engine.context, builtinAuthResolved, "builtinAuthResolved", 1, 0, 2, &continuation_data));
        defer engine.releaseNativeValue(continuation);
        return sdk.invoke(engine, promise, "then", &.{continuation});
    }
    return builtinAuthResult(engine, key, source, resolve);
}
fn builtinAuthResolved(context: ?*c.JSContext, ignored0: c.JSValue, argc: c_int, args: [*c]c.JSValue, ignored1: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    var frame = @import("native_pending_owner.zig").Frame.init(engine);
    frame.enter() catch return frame.finishCallback(c.pi_js_exception());
    return frame.finishCallback(builtinAuthResolvedOwnedBody(context, ignored0, argc, args, ignored1, data));
}
fn builtinAuthResolvedOwnedBody(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return builtinAuthResult(engine, if (argc > 0) args[0] else c.pi_js_undefined(), data[0], c.JS_ToBool(context, data[1]) == 1) catch |err| sdk.fail(engine, err);
}
fn builtinAuthResult(engine: *engine_mod.Engine, key: c.JSValue, source: c.JSValue, resolve: bool) !c.JSValue {
    if (!c.JS_IsString(key)) return c.pi_js_undefined();
    const raw_key = c.JS_ToCString(engine.context, key) orelse return error.JavaScriptException;
    defer c.JS_FreeCString(engine.context, raw_key);
    if (std.mem.span(raw_key).len == 0) return c.pi_js_undefined();
    const result = try sdk.object(engine);
    errdefer engine.releaseNativeValue(result);
    try sdk.put(engine, result, "source", c.JS_DupValue(engine.context, source));
    if (resolve) {
        const auth = try sdk.object(engine);
        defer engine.releaseNativeValue(auth);
        try sdk.put(engine, auth, "apiKey", c.JS_DupValue(engine.context, key));
        try sdk.put(engine, result, "auth", c.JS_DupValue(engine.context, auth));
    } else try sdk.put(engine, result, "type", try sdk.text(engine, "api_key"));
    return result;
}
pub fn seedBuiltins(engine: *engine_mod.Engine, catalog: c.JSValue) !void {
    const document = try sdk.jsonObject(engine, @embedFile("../ai/catalog_source.json"));
    defer engine.releaseNativeValue(document);
    const models = try sdk.get(engine, document, "models");
    defer engine.releaseNativeValue(models);
    const groups = try sdk.object(engine);
    defer engine.releaseNativeValue(groups);
    for (0..try sdk.length(engine, models)) |index| {
        try engine.checkNativeEntry();
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, models, @intCast(index)));
        defer engine.releaseNativeValue(row);
        const id = try sdk.get(engine, row, "provider");
        defer engine.releaseNativeValue(id);
        try engine.checkNativeEntry();
        const name = c.JS_ToCString(engine.context, id) orelse return error.JavaScriptException;
        defer c.JS_FreeCString(engine.context, name);
        var rows = try sdk.get(engine, groups, name);
        defer engine.releaseNativeValue(rows);
        if (!c.JS_IsArray(rows)) {
            const created = try sdk.array(engine);
            engine.releaseNativeValue(rows);
            rows = created;
            try sdk.put(engine, groups, name, c.JS_DupValue(engine.context, rows));
        }
        try sdk.append(engine, rows, c.JS_DupValue(engine.context, row));
    }
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    try engine.checkNativeEntry();
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, groups, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for (0..count) |index| {
        const id = try engine.checked(c.JS_AtomToValue(engine.context, names[index].atom));
        defer engine.releaseNativeValue(id);
        try engine.checkNativeEntry();
        const rows = try engine.checked(c.JS_GetProperty(engine.context, groups, names[index].atom));
        defer engine.releaseNativeValue(rows);
        const provider = try sdk.object(engine);
        defer engine.releaseNativeValue(provider);
        try sdk.put(engine, provider, "id", c.JS_DupValue(engine.context, id));
        try function(engine, provider, "getModels", 2, rows);
        try function(engine, provider, "getAllModels", 3, rows);
        const auth = try sdk.object(engine);
        defer engine.releaseNativeValue(auth);
        const method = try sdk.object(engine);
        defer engine.releaseNativeValue(method);
        try function(engine, method, "check", 4, id);
        try function(engine, method, "resolve", 5, id);
        try sdk.put(engine, auth, "apiKey", c.JS_DupValue(engine.context, method));
        try sdk.put(engine, provider, "auth", c.JS_DupValue(engine.context, auth));
        try @import("native_sdk_operations.zig").install(engine, provider);
        try @import("native_sdk_chat_transport.zig").install(engine, provider);
        const registered = try sdk.invoke(engine, catalog, "setProvider", &.{provider});
        engine.releaseNativeValue(registered);
    }
}

pub fn authContext(engine: *engine_mod.Engine, options: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.releaseNativeValue(result);
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
    errdefer engine.releaseNativeValue(result);
    try copy(engine, result, value);
    const original_auth = try sdk.get(engine, value, "auth");
    defer engine.releaseNativeValue(original_auth);
    const auth = try sdk.object(engine);
    defer engine.releaseNativeValue(auth);
    try copy(engine, auth, original_auth);
    try sdk.put(engine, result, "auth", c.JS_DupValue(engine.context, auth));
    const input = try sdk.get(engine, job, "input");
    defer engine.releaseNativeValue(input);
    if (c.JS_IsObject(input)) {
        const headers = try sdk.get(engine, input, "headers");
        defer engine.releaseNativeValue(headers);
        const previous = try sdk.get(engine, auth, "headers");
        defer engine.releaseNativeValue(previous);
        if (c.JS_IsObject(headers) or c.JS_IsObject(previous)) try sdk.put(engine, auth, "headers", try @import("native_sdk_model_headers.zig").merge(engine, previous, headers));
    }
    return result;
}
fn fileExists(engine: *engine_mod.Engine, input: c.JSValue) !c.JSValue {
    const path = try nativeText(engine, input);
    defer engine.gpa.free(path);
    var exists = true;
    std.Io.Dir.cwd().access(engine.native_io orelse return error.NativeSDKRequiresIO, path, .{}) catch {
        exists = false;
    };
    return sdk.promise(engine, c.pi_js_bool(engine.context, @intFromBool(exists)));
}
pub fn mergedHeaders(engine: *engine_mod.Engine, base: c.JSValue, updates: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.releaseNativeValue(result);
    try copy(engine, result, base);
    try copy(engine, result, updates);
    return result;
}

pub fn operationError(engine: *engine_mod.Engine, model: c.JSValue, images: bool, message: []const u8, aborted: bool) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.releaseNativeValue(result);
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
    defer engine.releaseNativeValue(kind);
    const expected = try sdk.text(engine, if (images) "image" else "classifier");
    defer engine.releaseNativeValue(expected);
    var invalid = !c.JS_IsStrictEqual(engine.context, kind, expected);
    var has_images = false;
    if (!images and !invalid) {
        const attachments = try sdk.get(engine, context, "images");
        defer engine.releaseNativeValue(attachments);
        if (c.JS_IsArray(attachments) and try sdk.length(engine, attachments) > 0) {
            const input = try sdk.get(engine, model, "input");
            defer engine.releaseNativeValue(input);
            const image_kind = try sdk.text(engine, "image");
            defer engine.releaseNativeValue(image_kind);
            var allowed = false;
            if (c.JS_IsArray(input)) for (0..try sdk.length(engine, input)) |index| {
                try engine.checkNativeEntry();
                const item = try engine.checked(c.JS_GetPropertyUint32(engine.context, input, @intCast(index)));
                defer engine.releaseNativeValue(item);
                if (c.JS_IsStrictEqual(engine.context, item, image_kind)) allowed = true;
            };
            invalid = !allowed;
            has_images = invalid;
        }
    }
    if (invalid) {
        const provider = try sdk.get(engine, model, "provider");
        defer engine.releaseNativeValue(provider);
        const id = try sdk.get(engine, model, "id");
        defer engine.releaseNativeValue(id);
        const provider_name = try nativeText(engine, provider);
        defer engine.gpa.free(provider_name);
        const model_name = try nativeText(engine, id);
        defer engine.gpa.free(model_name);
        const message = try nativeAllocation(engine, std.fmt.allocPrint(engine.gpa, "Model {s}/{s} {s}", .{ provider_name, model_name, if (has_images) "does not accept image input" else if (images) "is not an image model" else "is not a classifier model" }));
        defer engine.gpa.free(message);
        return operationError(engine, model, images, message, false);
    }
    return typedRequest(engine, data, model, context, options, images) catch |err| {
        try @import("native_pending_owner.zig").catchFailure(engine, err);
        var diagnostic = if (err == error.JavaScriptException and engine.captured_exception != null and c.JS_IsError(engine.captured_exception.?)) try sdk.get(engine, engine.captured_exception.?, "message") else if (err == error.JavaScriptException and engine.captured_exception != null) c.JS_DupValue(engine.context, engine.captured_exception.?) else c.pi_js_undefined();
        defer engine.releaseNativeValue(diagnostic);
        if (c.JS_IsUndefined(diagnostic)) {
            engine.releaseNativeValue(diagnostic);
            diagnostic = try sdk.text(engine, @errorName(err));
        }
        const message = try nativeText(engine, diagnostic);
        defer engine.gpa.free(message);
        const signal = if (c.JS_IsObject(options)) try sdk.get(engine, options, "signal") else c.pi_js_undefined();
        defer engine.releaseNativeValue(signal);
        const aborted = if (c.JS_IsObject(signal)) try sdk.get(engine, signal, "aborted") else c.pi_js_undefined();
        defer engine.releaseNativeValue(aborted);
        return operationError(engine, model, images, message, c.JS_ToBool(engine.context, aborted) == 1);
    };
}
fn typedRequest(engine: *engine_mod.Engine, data: c.JSValue, model: c.JSValue, context: c.JSValue, options: c.JSValue, images: bool) !c.JSValue {
    const pending = try request(engine, data, model, context, options, if (images) "generateImages" else "classify");
    defer engine.releaseNativeValue(pending);
    return engine.awaitValue(pending);
}

pub fn throwError(engine: *engine_mod.Engine, code_text: []const u8, message_text: []const u8) !c.JSValue {
    const exports = engine.native_module_values.get("pi-ai") orelse return error.NativeSDKModelModuleUnavailable;
    const constructor = try sdk.get(engine, exports, "ModelsError");
    defer engine.releaseNativeValue(constructor);
    const code = try sdk.text(engine, code_text);
    defer engine.releaseNativeValue(code);
    const message = try sdk.text(engine, message_text);
    defer engine.releaseNativeValue(message);
    var arguments = [_]c.JSValue{ code, message };
    try engine.checkNativeEntry();
    const failure = try engine.checked(c.JS_CallConstructor(engine.context, constructor, arguments.len, &arguments));
    defer engine.releaseNativeValue(failure);
    return engine.checked(c.JS_PiThrowExceptionData(engine.context, c.JS_DupValue(engine.context, failure)));
}
pub fn assertChat(engine: *engine_mod.Engine, model: c.JSValue) !void {
    const kind = try sdk.get(engine, model, "type");
    defer engine.releaseNativeValue(kind);
    const chat = try sdk.text(engine, "chat");
    defer engine.releaseNativeValue(chat);
    if (c.JS_IsUndefined(kind) or c.JS_IsStrictEqual(engine.context, kind, chat)) return;
    const provider = try sdk.get(engine, model, "provider");
    defer engine.releaseNativeValue(provider);
    const id = try sdk.get(engine, model, "id");
    defer engine.releaseNativeValue(id);
    const p = try nativeText(engine, provider);
    defer engine.gpa.free(p);
    const m = try nativeText(engine, id);
    defer engine.gpa.free(m);
    const message = try nativeAllocation(engine, std.fmt.allocPrint(engine.gpa, "Model {s}/{s} is not a chat model", .{ p, m }));
    defer engine.gpa.free(message);
    const ignored = try throwError(engine, "provider", message);
    engine.releaseNativeValue(ignored);
}
pub fn request(engine: *engine_mod.Engine, data: c.JSValue, model: c.JSValue, context: c.JSValue, input_options: c.JSValue, method: [*:0]const u8) !c.JSValue {
    const pending_auth = try resolveAuth(engine, data, model, input_options);
    defer engine.releaseNativeValue(pending_auth);
    const resolved = try engine.awaitValue(pending_auth);
    defer engine.releaseNativeValue(resolved);
    if (!c.JS_IsObject(resolved)) return error.NativeSDKProviderNotConfigured;
    const authentication = try sdk.get(engine, resolved, "auth");
    defer engine.releaseNativeValue(authentication);
    const options = try sdk.object(engine);
    defer engine.releaseNativeValue(options);
    try copy(engine, options, input_options);
    const explicit_key = if (c.JS_IsObject(input_options)) try sdk.get(engine, input_options, "apiKey") else c.pi_js_undefined();
    defer engine.releaseNativeValue(explicit_key);
    try sdk.put(engine, options, "apiKey", if (c.JS_IsUndefined(explicit_key) or c.JS_IsNull(explicit_key)) try sdk.get(engine, authentication, "apiKey") else c.JS_DupValue(engine.context, explicit_key));
    const initial_headers = try sdk.get(engine, authentication, "headers");
    defer engine.releaseNativeValue(initial_headers);
    const added_headers = if (c.JS_IsObject(input_options)) try sdk.get(engine, input_options, "headers") else c.pi_js_undefined();
    defer engine.releaseNativeValue(added_headers);
    var headers = try @import("native_sdk_model_headers.zig").merge(engine, initial_headers, added_headers);
    defer engine.releaseNativeValue(headers);
    const transform = try sdk.get(engine, options, "transformHeaders");
    defer engine.releaseNativeValue(transform);
    if (c.JS_IsFunction(engine.context, transform)) {
        const transform_input = if (c.JS_IsUndefined(headers) or c.JS_IsNull(headers)) try sdk.object(engine) else c.JS_DupValue(engine.context, headers);
        defer engine.releaseNativeValue(transform_input);
        var values = [_]c.JSValue{transform_input};
        try engine.checkNativeEntry();
        const pending = try engine.checked(c.JS_Call(engine.context, transform, c.pi_js_undefined(), 1, &values));
        defer engine.releaseNativeValue(pending);
        const transformed = try engine.awaitValue(pending);
        engine.releaseNativeValue(headers);
        headers = transformed;
    }
    try sdk.put(engine, options, "headers", c.JS_DupValue(engine.context, headers));
    const auth_env = try sdk.get(engine, resolved, "env");
    defer engine.releaseNativeValue(auth_env);
    const input_env = if (c.JS_IsObject(input_options)) try sdk.get(engine, input_options, "env") else c.pi_js_undefined();
    defer engine.releaseNativeValue(input_env);
    const env = if (c.JS_ToBool(engine.context, auth_env) == 1 or c.JS_ToBool(engine.context, input_env) == 1) try sdk.object(engine) else c.pi_js_undefined();
    defer engine.releaseNativeValue(env);
    if (c.JS_IsObject(env)) {
        try copy(engine, env, auth_env);
        try copy(engine, env, input_env);
    }
    try sdk.put(engine, options, "env", c.JS_DupValue(engine.context, env));
    const atom = c.JS_NewAtom(engine.context, "transformHeaders");
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DeleteProperty(engine.context, options, atom, 0) < 0) return error.JavaScriptException;
    const base = try sdk.get(engine, authentication, "baseUrl");
    defer engine.releaseNativeValue(base);
    const request_model = if (c.JS_ToBool(engine.context, base) == 1) try sdk.object(engine) else c.JS_DupValue(engine.context, model);
    defer engine.releaseNativeValue(request_model);
    if (c.JS_ToBool(engine.context, base) == 1) {
        try copy(engine, request_model, model);
        try sdk.put(engine, request_model, "baseUrl", c.JS_DupValue(engine.context, base));
    }
    const id = try sdk.get(engine, model, "provider");
    defer engine.releaseNativeValue(id);
    const catalog = try sdk.get(engine, data, "models");
    defer engine.releaseNativeValue(catalog);
    const provider = try sdk.invoke(engine, catalog, "getProvider", &.{id});
    defer engine.releaseNativeValue(provider);
    if (std.mem.eql(u8, std.mem.span(method), "fetchDeferred") or std.mem.eql(u8, std.mem.span(method), "cancelDeferred")) {
        const implementation = try sdk.get(engine, provider, method);
        defer engine.releaseNativeValue(implementation);
        if (c.JS_ToBool(engine.context, implementation) != 1) {
            const name = try nativeText(engine, id);
            defer engine.gpa.free(name);
            const message = try nativeAllocation(engine, std.fmt.allocPrint(engine.gpa, "Provider {s} does not support deferred responses", .{name}));
            defer engine.gpa.free(message);
            return throwError(engine, "provider", message);
        }
    }
    return sdk.invoke(engine, provider, method, &.{ request_model, context, options });
}
