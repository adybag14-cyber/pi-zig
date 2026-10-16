//! Prepared, unregistered ownership controls; no execution/qualification.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const data = @import("native_sdk_package_data.zig");
const caught = @import("native_sdk_package_catch.zig");
fn prepare(engine: *v.em.Engine) !void {
    const result = try engine.eval(
        \\globalThis.packageDataReason={actual:'define trap'};globalThis.packageDataStale={stale:true};
        \\globalThis.packageDataProxy=new Proxy({},{defineProperty(){throw packageDataReason}});
        \\globalThis.packageDataStaleThrow=()=>{throw packageDataStale};
    , "package-data-pending-prepare.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
}
test "package data definition captures pending reason instead of absent or stale slot" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); engine.native_exception_diagnostics_suppressed += 1;
    try prepare(engine); const proxy = try v.js.global(engine, "packageDataProxy"); defer engine.freeValue(proxy); const reason = try v.js.global(engine, "packageDataReason"); defer engine.freeValue(reason);
    const stale = try v.js.global(engine, "packageDataStaleThrow"); defer engine.freeValue(stale);
    inline for (.{ false, true }) |with_stale| {
        if (with_stale) try std.testing.expectError(error.JavaScriptException, v.js.call(engine, stale, c.pi_js_undefined(), &.{}));
        try std.testing.expectError(error.JavaScriptException, data.put(engine, proxy, "field", c.pi_js_undefined()));
        try std.testing.expect(!c.JS_HasException(engine.context)); try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception orelse return error.MissingActualPendingReason));
        try caught.ignore(engine, error.JavaScriptException, engine.native_allocation_generation); try std.testing.expect(engine.captured_exception == null);
    }
}
fn fail(_: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return error.OutOfMemory; }
test "package data definition preserves exact fresh private native reason" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); engine.native_exception_diagnostics_suppressed += 1;
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global); try v.js.define(engine, global, "packageDataFatal", try @import("native_node_function.zig").createArrow(engine, "packageDataFatal", 0, fail, &.{}));
    const proxy = try engine.eval("new Proxy({},{defineProperty(){packageDataFatal()}})", "package-data-fatal-proxy.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(proxy); const generation = engine.native_allocation_generation;
    try std.testing.expectError(error.JavaScriptException, data.put(engine, proxy, "field", c.pi_js_undefined())); const reason = c.JS_DupValue(engine.context, engine.captured_exception orelse return error.MissingFreshPendingReason); defer engine.freeValue(reason);
    try std.testing.expectError(error.JavaScriptException, caught.ignore(engine, error.JavaScriptException, generation)); try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception.?)); try std.testing.expect(c.JS_IsUncatchableError(engine.captured_exception.?));
}
