const std = @import("std");
const builtin = @import("builtin");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = js.c;
test "native Env ArrayBufferView actual compiled intrinsic inventory" {
    const names = try std.testing.allocator.alloc([]const u8, builtin.test_functions.len);
    defer std.testing.allocator.free(names);
    for (builtin.test_functions, names) |function, *name| name.* = function.name;
    const text = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(text);
    std.debug.print("\nENV_ARRAYBUFFERVIEW_TEST_INVENTORY={s}\n", .{text});
}
fn spanValue(scope: *Scope, value: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    var offset: usize = undefined;
    var length: usize = undefined;
    var element: usize = undefined;
    const backing = try scope.own(try engine.checked(c.JS_PiGetArrayBufferViewBuffer(engine.context, value, &offset, &length, &element)));
    const result = try scope.object();
    try scope.put(result, "offset", c.JS_NewFloat64(engine.context, @floatFromInt(offset)));
    try scope.put(result, "length", c.JS_NewFloat64(engine.context, @floatFromInt(length)));
    try scope.put(result, "elementBytes", c.JS_NewFloat64(engine.context, @floatFromInt(element)));
    try scope.put(result, "buffer", backing);
    return result;
}
fn span(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    // These intrinsic errors are still inside the guest's try/catch. Preserve
    // their identity without diagnostic ToString or swallowed formatter OOM.
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = spanValue(&scope, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| return @import("extensions/native_durable.zig").reject(engine, err);
    return c.JS_DupValue(engine.context, value);
}
fn collect(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(js.Engine.fromContext(context.?).runtime);
    return c.pi_js_undefined();
}
fn replay(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "spanOf", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, span, "spanOf", 1))));
    try scope.put(global, "nativeCollect", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, collect, "nativeCollect", 0))));
    const source = @embedFile("extensions/fixtures/env-node-view-span-source-24.json");
    try scope.put(global, "viewSpanSource", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "actual-node24-view-span.json"))));
    const generation = engine.native_allocation_generation;
    const output = engine.evalModule(@embedFile("extensions/fixtures/env-node-view-span-source-24.input.txt") ++
        "\nif(JSON.stringify(packet)!==JSON.stringify(viewSpanSource))throw Error(JSON.stringify({actual:packet,expected:viewSpanSource}));export const proof=true;", "native-env-arraybufferview-source.mjs") catch |err| {
        const classified = engine.nativeAllocationError(err, generation);
        if (classified != error.OutOfMemory) std.debug.print("ArrayBufferView Source failure: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return classified;
    };
    engine.freeValue(output);
    c.JS_RunGC(engine.runtime);
}
test "native Env ArrayBufferView intrinsic spans match actual Node24 brand shadowed getters resizable detach and retained backing GC" {
    try replay(std.testing.allocator);
}
test "native Env ArrayBufferView intrinsic result roots release at every host allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, replay, .{});
}
