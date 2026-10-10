const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const c = engine_mod.c;
test "native async function intrinsic equals actual guest prototype and survives GC" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const first = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(first);
    const guest = try engine.eval("async function userFixture(){};userFixture", "async-function-guest-fixture.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(guest);
    const actual = try engine.checked(c.JS_GetPrototype(engine.context, guest));
    defer engine.freeValue(actual);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, actual));
    c.JS_RunGC(engine.runtime);
    const after = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(after);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, after));
}
test "native async function intrinsic is owned by each context" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const other = c.JS_NewContext(engine.runtime) orelse return error.OutOfMemory;
    defer c.JS_FreeContext(other);
    const first = c.JS_GetAsyncFunctionPrototype(engine.context);
    defer c.JS_FreeValue(engine.context, first);
    const second = c.JS_GetAsyncFunctionPrototype(other);
    defer c.JS_FreeValue(other, second);
    try std.testing.expect(!c.JS_IsException(first) and !c.JS_IsException(second));
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, first, second));
}
fn allocationCase(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    const first = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(first);
    for (0..32) |_| {
        const next = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
        defer engine.freeValue(next);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, next));
        c.JS_RunGC(engine.runtime);
    }
}
test "native async function intrinsic allocator cleanup and reuse" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
    try allocationCase(std.testing.allocator);
}
