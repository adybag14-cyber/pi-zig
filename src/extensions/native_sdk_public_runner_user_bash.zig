//! Actual Source isUserBashEventResult, including repeated reads and `in`.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const c = em.c;
fn ordinaryObject(engine: *em.Engine, value: c.JSValue) bool {
    // JavaScript typeof excludes callable objects, including callable proxies.
    return c.JS_IsObject(value) and !c.JS_IsFunction(engine.context, value);
}
fn notUndefined(engine: *em.Engine, receiver: c.JSValue, name: [*:0]const u8) !bool {
    const value = try sdk.get(engine, receiver, name);
    defer engine.freeValue(value);
    return !c.JS_IsUndefined(value);
}
pub fn valid(engine: *em.Engine, value: c.JSValue) !bool {
    if (!ordinaryObject(engine, value)) return false;
    const has_operations = try notUndefined(engine, value, "operations");
    const has_result = try notUndefined(engine, value, "result");
    if (has_operations == has_result) return false;
    if (has_operations) {
        const operations = try sdk.get(engine, value, "operations");
        defer engine.freeValue(operations);
        if (!ordinaryObject(engine, operations)) return false;
        const exec = try sdk.get(engine, operations, "exec");
        defer engine.freeValue(exec);
        return c.JS_IsFunction(engine.context, exec);
    }
    const result = try sdk.get(engine, value, "result");
    defer engine.freeValue(result);
    if (!ordinaryObject(engine, result)) return false;
    const output = try sdk.get(engine, result, "output");
    defer engine.freeValue(output);
    if (!c.JS_IsString(output)) return false;
    const exit_key = try sdk.text(engine, "exitCode");
    defer engine.freeValue(exit_key);
    if (!try js.hasKey(engine, result, exit_key)) return false;
    if (try notUndefined(engine, result, "exitCode")) {
        const exit_code = try sdk.get(engine, result, "exitCode");
        defer engine.freeValue(exit_code);
        if (!c.JS_IsNumber(exit_code)) return false;
    }
    const cancelled = try sdk.get(engine, result, "cancelled");
    defer engine.freeValue(cancelled);
    if (!c.JS_IsBool(cancelled)) return false;
    const truncated = try sdk.get(engine, result, "truncated");
    defer engine.freeValue(truncated);
    if (!c.JS_IsBool(truncated)) return false;
    if (try notUndefined(engine, result, "fullOutputPath")) {
        const path = try sdk.get(engine, result, "fullOutputPath");
        defer engine.freeValue(path);
        if (!c.JS_IsString(path)) return false;
    }
    return true;
}
