//! Request-time model header definitions retain source precedence and resolve
//! templates after provider auth. Configuration rows never expose raw headers.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const models = @import("native_sdk_models.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
fn keys(engine: *engine_mod.Engine, value: c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const object = try sdk.get(engine, global, "Object");
    defer engine.freeValue(object);
    return sdk.invoke(engine, object, "keys", &.{value});
}
pub fn merge(engine: *engine_mod.Engine, base: c.JSValue, changed: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(base) and !c.JS_IsObject(changed)) return c.pi_js_undefined();
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try models.copy(engine, result, base);
    if (!c.JS_IsObject(changed)) return result;
    const names = try keys(engine, changed);
    defer engine.freeValue(names);
    for (0..try sdk.length(engine, names)) |index| {
        const name = try engine.checked(c.JS_GetPropertyUint32(engine.context, names, @intCast(index)));
        defer engine.freeValue(name);
        const text = try engine.toString(name);
        defer engine.gpa.free(text);
        const old_names = try keys(engine, result);
        defer engine.freeValue(old_names);
        for (0..try sdk.length(engine, old_names)) |old_index| {
            const old = try engine.checked(c.JS_GetPropertyUint32(engine.context, old_names, @intCast(old_index)));
            defer engine.freeValue(old);
            const old_text = try engine.toString(old);
            defer engine.gpa.free(old_text);
            if (!std.ascii.eqlIgnoreCase(text, old_text)) continue;
            const atom = c.JS_ValueToAtom(engine.context, old);
            if (atom == c.JS_ATOM_NULL) return error.JavaScriptException;
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DeleteProperty(engine.context, result, atom, 0) < 0) return error.JavaScriptException;
        }
        const value = try models.property(engine, changed, name);
        const atom = c.JS_ValueToAtom(engine.context, name);
        if (atom == c.JS_ATOM_NULL) {
            engine.freeValue(value);
            return error.JavaScriptException;
        }
        defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DefinePropertyValue(engine.context, result, atom, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    return result;
}
fn definition(engine: *engine_mod.Engine, rows: c.JSValue, id: c.JSValue, kind: c.JSValue) !c.JSValue {
    if (!c.JS_IsArray(rows)) return c.pi_js_undefined();
    for (0..try sdk.length(engine, rows)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        const row_id = try sdk.get(engine, row, "id");
        defer engine.freeValue(row_id);
        const row_type = try sdk.get(engine, row, "type");
        defer engine.freeValue(row_type);
        const chat = try sdk.text(engine, "chat");
        defer engine.freeValue(chat);
        if (c.JS_IsStrictEqual(engine.context, row_id, id) and c.JS_IsStrictEqual(engine.context, if (c.JS_IsUndefined(row_type)) chat else row_type, kind)) return sdk.get(engine, row, "headers");
    }
    return c.pi_js_undefined();
}
pub fn finish(engine: *engine_mod.Engine, resolution: c.JSValue, value: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(value)) return c.JS_DupValue(engine.context, value);
    const input = try sdk.get(engine, resolution, "input");
    defer engine.freeValue(input);
    if (c.JS_IsString(input)) return c.JS_DupValue(engine.context, value);
    const result = try models.finishAuth(engine, resolution, value);
    defer engine.freeValue(result);
    const data = try sdk.get(engine, resolution, "data");
    defer engine.freeValue(data);
    const provider_id = try sdk.get(engine, input, "provider");
    defer engine.freeValue(provider_id);
    const model_id = try sdk.get(engine, input, "id");
    defer engine.freeValue(model_id);
    const chat = try sdk.text(engine, "chat");
    defer engine.freeValue(chat);
    const type_value = try sdk.get(engine, input, "type");
    defer engine.freeValue(type_value);
    const kind = if (c.JS_IsUndefined(type_value)) chat else type_value;
    const config = try sdk.get(engine, data, "modelConfig");
    defer engine.freeValue(config);
    const providers = try sdk.get(engine, config, "providers");
    defer engine.freeValue(providers);
    const provider = try models.property(engine, providers, provider_id);
    defer engine.freeValue(provider);
    const raw = try sdk.object(engine);
    defer engine.freeValue(raw);
    if (c.JS_IsObject(provider) and c.JS_IsStrictEqual(engine.context, kind, chat)) {
        const overrides = try sdk.get(engine, provider, "modelOverrides");
        defer engine.freeValue(overrides);
        const overlay = if (c.JS_IsObject(overrides)) try models.property(engine, overrides, model_id) else c.pi_js_undefined();
        defer engine.freeValue(overlay);
        const headers = if (c.JS_IsObject(overlay)) try sdk.get(engine, overlay, "headers") else c.pi_js_undefined();
        defer engine.freeValue(headers);
        try models.copy(engine, raw, headers);
        const rows = try sdk.get(engine, provider, "models");
        defer engine.freeValue(rows);
        const row_headers = try definition(engine, rows, model_id, chat);
        defer engine.freeValue(row_headers);
        try models.copy(engine, raw, row_headers);
    }
    const extensions = try sdk.get(engine, data, "registeredExtensions");
    defer engine.freeValue(extensions);
    const extension = try sdk.invoke(engine, extensions, "get", &.{provider_id});
    defer engine.freeValue(extension);
    if (c.JS_IsObject(extension)) {
        const rows = try sdk.get(engine, extension, "models");
        defer engine.freeValue(rows);
        const headers = try definition(engine, rows, model_id, kind);
        defer engine.freeValue(headers);
        try models.copy(engine, raw, headers);
    }
    const names = try keys(engine, raw);
    defer engine.freeValue(names);
    if (try sdk.length(engine, names) == 0) return c.JS_DupValue(engine.context, result);
    const job = try sdk.object(engine);
    defer engine.freeValue(job);
    try sdk.put(engine, job, "result", c.JS_DupValue(engine.context, result));
    try sdk.put(engine, job, "raw", c.JS_DupValue(engine.context, raw));
    try sdk.put(engine, job, "names", c.JS_DupValue(engine.context, names));
    try sdk.put(engine, job, "index", c.JS_NewInt32(engine.context, 0));
    try sdk.put(engine, job, "headers", try sdk.object(engine));
    const options = try sdk.get(engine, resolution, "options");
    defer engine.freeValue(options);
    const env = try sdk.get(engine, result, "env");
    defer engine.freeValue(env);
    const request_env = try sdk.get(engine, options, "env");
    defer engine.freeValue(request_env);
    try sdk.put(engine, job, "env", try models.mergedHeaders(engine, env, request_env));
    try sdk.put(engine, job, "ctx", try models.authContext(engine, options));
    const provider_text = try engine.toString(provider_id);
    defer engine.gpa.free(provider_text);
    const model_text = try engine.toString(model_id);
    defer engine.gpa.free(model_text);
    const description = try std.fmt.allocPrint(engine.gpa, "model \"{s}/{s}\"", .{ provider_text, model_text });
    defer engine.gpa.free(description);
    try sdk.put(engine, job, "description", try sdk.text(engine, description));
    return next(engine, job);
}
fn completed(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return received(engine, data[0], if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn received(engine: *engine_mod.Engine, job: c.JSValue, value: c.JSValue) !c.JSValue {
    const headers = try sdk.get(engine, job, "headers");
    defer engine.freeValue(headers);
    const key = try sdk.get(engine, job, "current");
    defer engine.freeValue(key);
    const atom = c.JS_ValueToAtom(engine.context, key);
    if (atom == c.JS_ATOM_NULL) return error.JavaScriptException;
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyValue(engine.context, headers, atom, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    return next(engine, job);
}
fn next(engine: *engine_mod.Engine, job: c.JSValue) !c.JSValue {
    const names = try sdk.get(engine, job, "names");
    defer engine.freeValue(names);
    const position = try sdk.get(engine, job, "index");
    defer engine.freeValue(position);
    var index: u32 = 0;
    if (c.JS_ToUint32(engine.context, &index, position) < 0) return error.JavaScriptException;
    if (index < try sdk.length(engine, names)) {
        const key = try engine.checked(c.JS_GetPropertyUint32(engine.context, names, index));
        defer engine.freeValue(key);
        try sdk.put(engine, job, "current", c.JS_DupValue(engine.context, key));
        try sdk.put(engine, job, "index", c.JS_NewUint32(engine.context, index + 1));
        const raw = try sdk.get(engine, job, "raw");
        defer engine.freeValue(raw);
        const text = try models.property(engine, raw, key);
        defer engine.freeValue(text);
        const ctx = try sdk.get(engine, job, "ctx");
        defer engine.freeValue(ctx);
        const env = try sdk.get(engine, job, "env");
        defer engine.freeValue(env);
        const description = try sdk.get(engine, job, "description");
        defer engine.freeValue(description);
        const desc = try engine.toString(description);
        defer engine.gpa.free(desc);
        const key_text = try engine.toString(key);
        defer engine.gpa.free(key_text);
        const full = try std.fmt.allocPrint(engine.gpa, "header \"{s}\" for {s}", .{ key_text, desc });
        defer engine.gpa.free(full);
        const full_value = try sdk.text(engine, full);
        defer engine.freeValue(full_value);
        const pending = try @import("native_sdk_config_value.zig").start(engine, text, ctx, env, false, full_value);
        defer engine.freeValue(pending);
        const adopted = try sdk.promise(engine, pending);
        defer engine.freeValue(adopted);
        var captured = [_]c.JSValue{job};
        const done = try engine.checked(c.JS_NewCFunctionData2(engine.context, completed, "modelHeaderResolved", 1, 0, 1, &captured));
        defer engine.freeValue(done);
        return sdk.invoke(engine, adopted, "then", &.{done});
    }
    const result = try sdk.get(engine, job, "result");
    errdefer engine.freeValue(result);
    const auth = try sdk.get(engine, result, "auth");
    defer engine.freeValue(auth);
    const previous = try sdk.get(engine, auth, "headers");
    defer engine.freeValue(previous);
    const headers = try sdk.get(engine, job, "headers");
    defer engine.freeValue(headers);
    try sdk.put(engine, auth, "headers", try merge(engine, previous, headers));
    return result;
}
