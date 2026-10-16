const std = @import("std");
const builtin = @import("builtin");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = js.c;
test "native readable pipe Source actual compiled inventory" {
    const names = try std.testing.allocator.alloc([]const u8, builtin.test_functions.len);
    defer std.testing.allocator.free(names);
    for (builtin.test_functions, names) |item, *name| name.* = item.name;
    const text = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(text);
    std.debug.print("\nREADABLE_PIPE_SOURCE_TEST_INVENTORY={s}\n", .{text});
}
fn collect(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(js.Engine.fromContext(context.?).runtime);
    return c.pi_js_undefined();
}
fn replay(case_name: []const u8) !void {
    const engine = try js.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try @import("extensions/native_readable_stream.zig").install(engine);
    try @import("extensions/native_writable_stream.zig").install(engine);
    try @import("extensions/native_transform_stream.zig").install(engine);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const web = try scope.object();
    inline for (.{ "ReadableStream", "ReadableStreamDefaultReader", "ReadableStreamBYOBReader", "ReadableByteStreamController", "ReadableStreamDefaultController", "ReadableStreamBYOBRequest", "WritableStream", "TransformStream" }) |name| try scope.put(web, name, try scope.global(name));
    try scope.put(global, "web", web);
    try scope.put(global, "caseName", try scope.text(case_name));
    try scope.put(global, "nativeCollect", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, collect, "nativeCollect", 0))));
    const expected = @embedFile("extensions/fixtures/env-readable-pipe-source-24.json");
    try scope.put(global, "pipeStreamSource", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "actual-node24-pipe-Source20.json"))));
    const body = @embedFile("extensions/fixtures/env-readable-pipe-source-24.input.txt");
    const generation = engine.native_allocation_generation;
    const result = engine.evalModule(body ++ "\nif(JSON.stringify(packet)!==JSON.stringify(pipeStreamSource[caseName]))throw Error(JSON.stringify({case:caseName,actual:packet,expected:pipeStreamSource[caseName]}));export const proof=true;", "native-readable-pipe-actual-Source20.mjs") catch |err| {
        const classified = engine.nativeAllocationError(err, generation);
        if (classified != error.OutOfMemory) std.debug.print("Native readable pipe actual Source case {s}: {s}\n", .{ case_name, engine.last_error orelse "no diagnostic" });
        return classified;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native readable pipe Source pipe-values" {
    try replay("pipe-values");
}
test "native readable pipe Source pipe-final-chunk" {
    try replay("pipe-final-chunk");
}
test "native readable pipe Source pipe-closed-source-hwm-zero" {
    try replay("pipe-closed-source-hwm-zero");
}
test "native readable pipe Source pipe-source-error" {
    try replay("pipe-source-error");
}
test "native readable pipe Source pipe-destination-error" {
    try replay("pipe-destination-error");
}
test "native readable pipe Source pipe-write-error" {
    try replay("pipe-write-error");
}
test "native readable pipe Source pipe-prevent-close" {
    try replay("pipe-prevent-close");
}
test "native readable pipe Source pipe-prevent-abort" {
    try replay("pipe-prevent-abort");
}
test "native readable pipe Source pipe-prevent-cancel" {
    try replay("pipe-prevent-cancel");
}
test "native readable pipe Source pipe-pre-abort" {
    try replay("pipe-pre-abort");
}
test "native readable pipe Source pipe-abort-pending-write" {
    try replay("pipe-abort-pending-write");
}
test "native readable pipe Source pipe-abort-actions-reject" {
    try replay("pipe-abort-actions-reject");
}
test "native readable pipe Source pipe-through-identity" {
    try replay("pipe-through-identity");
}
test "native readable pipe Source pipe-through-error" {
    try replay("pipe-through-error");
}
test "native readable pipe Source pipe-through-getter-order" {
    try replay("pipe-through-getter-order");
}
test "native readable pipe Source pipe-borrowed-receivers" {
    try replay("pipe-borrowed-receivers");
}
test "native readable pipe Source pipe-locked-source-order" {
    try replay("pipe-locked-source-order");
}
test "native readable pipe Source pipe-locked-destination" {
    try replay("pipe-locked-destination");
}
test "native readable pipe Source pipe-closed-destination" {
    try replay("pipe-closed-destination");
}
test "native readable pipe Source pipe-close-error" {
    try replay("pipe-close-error");
}
