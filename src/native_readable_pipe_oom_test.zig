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
test "native readable pipe host OOM retires pending write and real reader writer capabilities" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try js.Engine.init(failing.allocator(), .{ .host_await_timeout_ms = 10_000 });
    engine.native_io = std.testing.io;
    var result: anyerror!void = undefined;
    {
        defer engine.deinit();
        try @import("extensions/native_readable_stream.zig").install(engine);
        try @import("extensions/native_writable_stream.zig").install(engine);
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const global = try scope.own(c.JS_GetGlobalObject(engine.context));
        var roots = [_]c.JSValue{c.JS_NewFloat64(engine.context, @floatFromInt(@intFromPtr(&failing)))};
        const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, arm, "armNativeHostFailure", 0, 0, roots.len, &roots)));
        try scope.put(global, "armNativeHostFailure", callback);
        result = classifiedOperation(engine);
    }
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectError(error.OutOfMemory, result);
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}
fn classifiedOperation(engine: *js.Engine) !void {
    const generation = engine.native_allocation_generation;
    operation(engine) catch |err| return engine.nativeAllocationError(err, generation);
}
fn operation(engine: *js.Engine) !void {
    const value = try engine.evalModule(
        \\let release;const gate=new Promise(resolve=>{release=resolve});
        \\const source=new ReadableStream({start(controller){controller.enqueue('pending');controller.close()}});
        \\const destination=new WritableStream({write(){Promise.resolve().then(()=>{armNativeHostFailure();release()});return gate}});
        \\await source.pipeTo(destination);throw Error('native host failure must reject the actual pipe capability');
    , "native-readable-pipe-host-oom.mjs");
    engine.freeValue(value);
}
