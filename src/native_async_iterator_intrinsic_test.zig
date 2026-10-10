const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const c = engine_mod.c;
test "native async iterator intrinsic matches actual guest generator and survives owned reference GC" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const first = try engine.checked(c.JS_GetAsyncIteratorPrototype(engine.context));
    defer engine.freeValue(first);
    const second = try engine.checked(c.JS_GetAsyncIteratorPrototype(engine.context));
    defer engine.freeValue(second);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, second));
    const generator = try engine.eval("(async function* userFixture(){yield 1;})()", "async-iterator-guest-fixture.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(generator);
    const one = try engine.checked(c.JS_GetPrototype(engine.context, generator));
    defer engine.freeValue(one);
    const two = try engine.checked(c.JS_GetPrototype(engine.context, one));
    defer engine.freeValue(two);
    const three = try engine.checked(c.JS_GetPrototype(engine.context, two));
    defer engine.freeValue(three);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, three));
    c.JS_RunGC(engine.runtime);
    const after = try engine.checked(c.JS_GetAsyncIteratorPrototype(engine.context));
    defer engine.freeValue(after);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, after));
}
test "native async iterator intrinsic is context owned within one runtime" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const other_context = c.JS_NewContext(engine.runtime) orelse return error.OutOfMemory;
    defer c.JS_FreeContext(other_context);
    const first = c.JS_GetAsyncIteratorPrototype(engine.context);
    defer c.JS_FreeValue(engine.context, first);
    const other = c.JS_GetAsyncIteratorPrototype(other_context);
    defer c.JS_FreeValue(other_context, other);
    try std.testing.expect(!c.JS_IsException(first) and !c.JS_IsException(other));
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, first, other));
}
fn allocationCase(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    const first = try engine.checked(c.JS_GetAsyncIteratorPrototype(engine.context));
    defer engine.freeValue(first);
    // The accessor is allocation-free. Repeated duplication/freeing and GC do
    // not consume a C heap allocation or change the context's intrinsic root.
    for (0..32) |_| {
        const next = try engine.checked(c.JS_GetAsyncIteratorPrototype(engine.context));
        defer engine.freeValue(next);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, next));
        c.JS_RunGC(engine.runtime);
    }
}
test "native async iterator intrinsic host allocation failure cleanup and reuse" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
    try allocationCase(std.testing.allocator);
}
