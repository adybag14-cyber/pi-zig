//! Unconfigured ModelRegistry authentication still resolves configured headers.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const models = @import("native_sdk_models.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
pub fn start(engine: *engine_mod.Engine, auth_job: c.JSValue) !c.JSValue {
    const runtime = try sdk.get(engine, auth_job, "runtime");
    defer engine.freeValue(runtime);
    if (c.JS_GetOpaque(runtime, engine.native_sdk_class) == null) {
        const input = try sdk.get(engine, auth_job, "input");
        defer engine.freeValue(input);
        const compatibility = try sdk.invoke(engine, runtime, "getCompatibilityRequestConfig", &.{input});
        defer engine.freeValue(compatibility);
        const flag = try sdk.get(engine, compatibility, "authHeader");
        defer engine.freeValue(flag);
        if (c.JS_ToBool(engine.context, flag) == 1) return @import("native_sdk_model_registry.zig").missingKey(engine, auth_job);
        const result = try sdk.object(engine);
        errdefer engine.freeValue(result);
        try sdk.put(engine, result, "ok", c.pi_js_bool(engine.context, 1));
        try sdk.put(engine, result, "headers", try sdk.get(engine, compatibility, "headers"));
        return result;
    }
    const data = (try sdk.state(engine, runtime)).data;
    const model = try sdk.get(engine, auth_job, "input");
    defer engine.freeValue(model);
    const id = try sdk.get(engine, model, "provider");
    defer engine.freeValue(id);
    const model_id = try sdk.get(engine, model, "id");
    defer engine.freeValue(model_id);
    const config = try sdk.get(engine, data, "modelConfig");
    defer engine.freeValue(config);
    const providers = try sdk.get(engine, config, "providers");
    defer engine.freeValue(providers);
    const provider = try models.property(engine, providers, id);
    defer engine.freeValue(provider);
    const extensions = try sdk.get(engine, data, "registeredExtensions");
    defer engine.freeValue(extensions);
    const extension = try sdk.invoke(engine, extensions, "get", &.{id});
    defer engine.freeValue(extension);
    const job = try sdk.object(engine);
    defer engine.freeValue(job);
    try sdk.put(engine, job, "authJob", c.JS_DupValue(engine.context, auth_job));
    var flag = if (c.JS_IsObject(extension)) try sdk.get(engine, extension, "authHeader") else c.pi_js_undefined();
    defer engine.freeValue(flag);
    if (c.JS_IsUndefined(flag) or c.JS_IsNull(flag)) {
        engine.freeValue(flag);
        flag = if (c.JS_IsObject(provider)) try sdk.get(engine, provider, "authHeader") else c.pi_js_undefined();
    }
    try sdk.put(engine, job, "authHeader", c.JS_DupValue(engine.context, flag));
    const raw = try sdk.object(engine);
    defer engine.freeValue(raw);
    for ([_]c.JSValue{ provider, extension }) |source| if (c.JS_IsObject(source)) {
        const headers = try sdk.get(engine, source, "headers");
        defer engine.freeValue(headers);
        try models.copy(engine, raw, headers);
    };
    const typ = try sdk.get(engine, model, "type");
    defer engine.freeValue(typ);
    const chat = try sdk.text(engine, "chat");
    defer engine.freeValue(chat);
    const kind = if (c.JS_IsUndefined(typ)) chat else typ;
    if (c.JS_IsObject(provider) and c.JS_IsStrictEqual(engine.context, kind, chat)) {
        const overrides = try sdk.get(engine, provider, "modelOverrides");
        defer engine.freeValue(overrides);
        const override = if (c.JS_IsObject(overrides)) try models.property(engine, overrides, model_id) else c.pi_js_undefined();
        defer engine.freeValue(override);
        if (c.JS_IsObject(override)) {
            const headers = try sdk.get(engine, override, "headers");
            defer engine.freeValue(headers);
            try models.copy(engine, raw, headers);
        }
    }
    for ([_]c.JSValue{ provider, extension }, 0..) |source, index| if (c.JS_IsObject(source) and (index == 1 or c.JS_IsStrictEqual(engine.context, kind, chat))) {
        const rows = try sdk.get(engine, source, "models");
        defer engine.freeValue(rows);
        const headers = try @import("native_sdk_model_headers.zig").definition(engine, rows, model_id, kind);
        defer engine.freeValue(headers);
        try models.copy(engine, raw, headers);
    };
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const object = try sdk.get(engine, global, "Object");
    defer engine.freeValue(object);
    try sdk.put(engine, job, "names", try sdk.invoke(engine, object, "keys", &.{raw}));
    try sdk.put(engine, job, "raw", c.JS_DupValue(engine.context, raw));
    try sdk.put(engine, job, "index", c.JS_NewInt32(engine.context, 0));
    try sdk.put(engine, job, "ctx", try models.authContext(engine, c.pi_js_undefined()));
    const headers = try sdk.object(engine);
    defer engine.freeValue(headers);
    const original = try sdk.get(engine, model, "headers");
    defer engine.freeValue(original);
    try models.copy(engine, headers, original);
    try sdk.put(engine, job, "headers", c.JS_DupValue(engine.context, headers));
    try sdk.put(engine, job, "hasHeaders", c.pi_js_bool(engine.context, @intFromBool(c.JS_ToBool(engine.context, original) == 1)));
    return next(engine, job);
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return received(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined(), magic == 1) catch |err| sdk.fail(engine, err);
}
fn received(engine: *engine_mod.Engine, job: c.JSValue, value: c.JSValue, failed: bool) !c.JSValue {
    if (failed) {
        const parent = try sdk.get(engine, job, "authJob");
        defer engine.freeValue(parent);
        return @import("native_sdk_model_registry.zig").finishAuth(engine, parent, value, 1);
    }
    const headers = try sdk.get(engine, job, "headers");
    defer engine.freeValue(headers);
    const name = try sdk.get(engine, job, "current");
    defer engine.freeValue(name);
    const atom = c.JS_ValueToAtom(engine.context, name);
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
        const name = try engine.checked(c.JS_GetPropertyUint32(engine.context, names, index));
        defer engine.freeValue(name);
        try sdk.put(engine, job, "current", c.JS_DupValue(engine.context, name));
        try sdk.put(engine, job, "index", c.JS_NewUint32(engine.context, index + 1));
        const raw = try sdk.get(engine, job, "raw");
        defer engine.freeValue(raw);
        const value = try models.property(engine, raw, name);
        defer engine.freeValue(value);
        const ctx = try sdk.get(engine, job, "ctx");
        defer engine.freeValue(ctx);
        const description = try sdk.text(engine, "configured model header");
        defer engine.freeValue(description);
        const pending = try @import("native_sdk_config_value.zig").start(engine, value, ctx, c.pi_js_undefined(), false, description);
        defer engine.freeValue(pending);
        const adopted = try sdk.promise(engine, pending);
        defer engine.freeValue(adopted);
        var data = [_]c.JSValue{job};
        const good = try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "registryHeader", 1, 0, 1, &data));
        defer engine.freeValue(good);
        const bad = try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "registryHeaderFailure", 1, 1, 1, &data));
        defer engine.freeValue(bad);
        return sdk.invoke(engine, adopted, "then", &.{ good, bad });
    }
    const flag = try sdk.get(engine, job, "authHeader");
    defer engine.freeValue(flag);
    if (c.JS_ToBool(engine.context, flag) == 1) {
        const parent = try sdk.get(engine, job, "authJob");
        defer engine.freeValue(parent);
        return @import("native_sdk_model_registry.zig").missingKey(engine, parent);
    }
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "ok", c.pi_js_bool(engine.context, 1));
    const has_headers = try sdk.get(engine, job, "hasHeaders");
    defer engine.freeValue(has_headers);
    try sdk.put(engine, result, "headers", if (try sdk.length(engine, names) > 0 or c.JS_ToBool(engine.context, has_headers) == 1) try sdk.get(engine, job, "headers") else c.pi_js_undefined());
    return result;
}
