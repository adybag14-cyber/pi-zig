//! Public ModelRegistry is the actual c268 class. The retained compatibility
//! continuations below serve only the existing internal registry-compat owner.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
pub const createConstructor = @import("native_sdk_model_registry_public.zig").createConstructor;
pub const install = @import("native_sdk_model_registry_public.zig").install;
pub const constructor = @import("native_sdk_model_registry_public.zig").constructor;
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
