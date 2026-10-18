//! Prepared binding controls. Requires Root's reviewed C ABI and actual owned
//! module input. No surrogate importer or manually resolved Promise is created.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const c = em.c;
pub fn verifyMetadataAndActualImport(engine: *em.Engine, physical_base: c.JSValue, actual_specifier: c.JSValue) !void {
    const function = try @import("extensions/native_extension_dynamic_import_graph0.zig").create(engine); defer engine.freeValue(function);
    try std.testing.expect(!c.JS_IsAsyncFunction(function));
    try std.testing.expect(!c.JS_IsConstructor(engine.context, function));
    const length = try js.get(engine, function, "length"); defer engine.freeValue(length);
    var count: i32 = 0;
    if (c.JS_ToInt32(engine.context, &count, length) < 0) return js.capture(engine);
    try std.testing.expectEqual(@as(i32, 2), count);
    const pending = try js.call(engine, function, c.pi_js_undefined(), &.{ physical_base, actual_specifier }); defer engine.freeValue(pending);
    try std.testing.expect(c.JS_PromiseState(engine.context, pending) == c.JS_PROMISE_PENDING);
    try std.testing.expect(engine.captured_exception == null);
    const first = try engine.awaitValue(pending); defer engine.freeValue(first);
    const again = try js.call(engine, function, c.pi_js_undefined(), &.{ physical_base, actual_specifier }); defer engine.freeValue(again);
    const second = try engine.awaitValue(again); defer engine.freeValue(second);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, second));
}
pub fn verifyNoBaseCoercion(engine: *em.Engine) !void {
    const function = try @import("extensions/native_extension_dynamic_import_graph0.zig").create(engine); defer engine.freeValue(function);
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try js.define(engine, global, "ActualGraph0Import", c.JS_DupValue(engine.context, function));
    const result = try engine.evalModule(
        \\let calls=0,caught;const base={toString(){calls++;return'C:/unreached.mjs'}};
        \\try{ActualGraph0Import(base,'node:fs')}catch(error){caught=error}
        \\if(calls!==0||!(caught instanceof TypeError))throw Error('Graph0 binding coerced invalid base or wrapped failure');
        \\export const passed=true;
    , "graph0-binding-no-base-coercion.mjs");
    defer engine.freeValue(result);
}
