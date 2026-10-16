//! Requires constructors from the actual native assembly, not stand-ins.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const c = em.c;
fn brand(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_bool(context, @intFromBool(argc > 0 and c.JS_IsAsyncFunction(argv[0])));
}
pub fn exercise(engine: *em.Engine, actual_classes: c.JSValue, genuine: []const u8) !void {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    const generation = engine.native_allocation_generation;
    const global = try scope.own(try engine.checked(c.JS_GetGlobalObject(engine.context)));
    try scope.put(global, "ActualSdkAsyncClasses", actual_classes);
    try scope.put(global, "ActualSdkIsAsyncFunction", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, brand, "isAsyncFunction", 1))));
    const evaluated = try scope.own(try engine.evalModule(@embedFile("extensions/fixtures/sdk-async-brand-4954.input.mjs"), "sdk-async-brand-4954.input.mjs"));
    _ = try scope.own(try engine.awaitValue(evaluated));
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, genuine.ptr, genuine.len, "genuine-sdk-async-brand.json")));
    const actual = try scope.get(global, "ActualSdkAsyncBrandRows"); const rows = try scope.get(expected, "rows");
    if (try @import("extensions/native_sdk.zig").length(engine, actual) != 15 or try @import("extensions/native_sdk.zig").length(engine, rows) != 15) return error.ActualSdkAsyncBrandUniverseMismatch;
    for (0..15) |index| {
        const value = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, actual, @intCast(index))));
        const oracle = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index))));
        const actual_json = try engine.stringify(value); defer engine.gpa.free(actual_json);
        const expected_json = try engine.stringify(oracle); defer engine.gpa.free(expected_json);
        if (!std.mem.eql(u8, actual_json, expected_json)) { std.debug.print("Genuine SDK async brand row{d} mismatch\nActual:{s}\nSource:{s}\n", .{index,actual_json,expected_json}); return error.ActualSdkAsyncBrandSourceMismatch; }
    }
}
