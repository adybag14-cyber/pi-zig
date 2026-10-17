//! Prepared controls; the original data authority is the accepted C8 output.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const catalog = @import("native_node_builtin_catalog.zig");
fn check(engine: *v.em.Engine, function: c.JSValue, id: []const u8, expected: bool) !void {
    const text = try engine.checked(c.JS_NewStringLen(engine.context, id.ptr, id.len));
    defer engine.freeValue(text);
    const result = try v.js.call(engine, function, c.pi_js_undefined(), &.{text});
    defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, result, c.pi_js_bool(engine.context, @intFromBool(expected))));
}
test "Node24 original builtin catalog preserves frozen publication and callable shape" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const graph = try catalog.createOriginalNode24(engine);
    defer engine.freeValue(graph.builtin_modules);
    defer engine.freeValue(graph.is_builtin);
    const global = try engine.checked(c.JS_GetGlobalObject(engine.context));
    defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, "ownedBuiltinModules", c.JS_DupValue(engine.context, graph.builtin_modules)) < 0) return v.js.capture(engine);
    if (c.JS_SetPropertyStr(engine.context, global, "ownedIsBuiltin", c.JS_DupValue(engine.context, graph.is_builtin)) < 0) return v.js.capture(engine);
    const observed = try engine.eval(
        "Object.isFrozen(ownedBuiltinModules)&&ownedBuiltinModules.length===72&&ownedBuiltinModules[0]==='_http_agent'&&ownedBuiltinModules[71]==='node:test/reporters'&&ownedIsBuiltin.name==='isBuiltin'&&ownedIsBuiltin.length===1&&!Object.hasOwn(ownedIsBuiltin,'prototype')&&Reflect.set(ownedBuiltinModules,'0','changed')===false&&ownedBuiltinModules[0]==='_http_agent'",
        "owned-node24-builtin-publication.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(observed);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, observed, c.pi_js_bool(engine.context, 1)));
}
test "Node24 original builtin classifier keeps bare and prefix-only identities distinct" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const graph = try catalog.createOriginalNode24(engine);
    defer engine.freeValue(graph.builtin_modules);
    defer engine.freeValue(graph.is_builtin);
    try check(engine, graph.is_builtin, "fs", true);
    try check(engine, graph.is_builtin, "node:fs", true);
    try check(engine, graph.is_builtin, "test", false);
    try check(engine, graph.is_builtin, "node:test", true);
    try check(engine, graph.is_builtin, "node:node:test", false);
    try check(engine, graph.is_builtin, "sqlite", false);
    try check(engine, graph.is_builtin, "node:sqlite", true);
    try check(engine, graph.is_builtin, "sea", false);
    try check(engine, graph.is_builtin, "node:sea", true);
    try check(engine, graph.is_builtin, "not-an-owned-builtin", false);
    try check(engine, graph.is_builtin, "node:not-an-owned-builtin", false);
    const result = try v.js.call(engine, graph.is_builtin, c.pi_js_undefined(), &.{c.JS_NewInt32(engine.context, 1)});
    defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, result, c.pi_js_bool(engine.context, 0)));
}
test "Node24 original builtin authority refuses silent Node version replacement" {
    try catalog.requireOriginalNodeVersion("v24.14.0");
    try std.testing.expectError(error.OriginalNodeBuiltinVersionMismatch, catalog.requireOriginalNodeVersion("v24.14.1"));
    try std.testing.expectError(error.OriginalNodeBuiltinVersionMismatch, catalog.requireOriginalNodeVersion("24.14.0"));
}
