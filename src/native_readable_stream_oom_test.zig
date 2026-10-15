const std = @import("std");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = js.c;
fn arm(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    var address: u64 = 0;
    if (c.JS_ToIndex(context, &address, roots[0]) < 0) return c.JS_Throw(context, c.JS_GetException(context));
    const failing: *std.testing.FailingAllocator = @ptrFromInt(@as(usize, @intCast(address)));
    failing.fail_index = failing.alloc_index;
    return c.pi_js_undefined();
}
test "native readable host OOM rejects actual tee consumers without another host root" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try js.Engine.init(failing.allocator(), .{ .host_await_timeout_ms = 10_000 });
    engine.native_io = std.testing.io;
    var result: anyerror!void = undefined;
    {
        defer engine.deinit();
        try @import("extensions/native_readable_stream.zig").install(engine);
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const global = try scope.own(c.JS_GetGlobalObject(engine.context));
        var roots = [_]c.JSValue{c.JS_NewFloat64(engine.context, @floatFromInt(@intFromPtr(&failing)))};
        const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, arm, "armNativeHostFailure", 0, 0, roots.len, &roots)));
        try scope.put(global, "armNativeHostFailure", callback);
        const generation = engine.native_allocation_generation;
        result = operation(engine) catch |err| engine.nativeAllocationError(err, generation);
    }
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectError(error.OutOfMemory, result);
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}
fn operation(engine: *js.Engine) !void {
    const value = try engine.evalModule(
        \\const source=new ReadableStream({type:'bytes',pull(controller){controller.enqueue(new Uint8Array([65,66]));controller.close();armNativeHostFailure()}});
        \\const branches=source.tee(),first=branches[0].getReader(),second=branches[1].getReader();
        \\await Promise.all([first.read(),second.read()]);throw Error('native host failure must reject the actual consumers');
    , "native-readable-tee-host-oom.mjs");
    engine.freeValue(value);
}
