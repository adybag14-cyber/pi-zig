const std = @import("std");
const builtin = @import("builtin");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = js.c;
test "native readable byte Source actual compiled inventory" {
    const names = try std.testing.allocator.alloc([]const u8, builtin.test_functions.len);
    defer std.testing.allocator.free(names);
    for (builtin.test_functions, names) |item, *name| name.* = item.name;
    const text = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(text);
    std.debug.print("\nREADABLE_BYTE_SOURCE_TEST_INVENTORY={s}\n", .{text});
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
    const bindings = try scope.object();
    try @import("extensions/native_readable_byte_stream.zig").prepare(&scope, bindings);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    // Supply the real private native constructor to the unchanged reference
    // body. This does not install the unqualified public global/module graph.
    try scope.put(global, "ReadableStream", try scope.get(bindings, "fileHandleReadableStream"));
    try scope.put(global, "caseName", try scope.text(case_name));
    try scope.put(global, "nativeCollect", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, collect, "nativeCollect", 0))));
    const source = @embedFile("extensions/fixtures/env-readable-byte-stream-source-24.json");
    try scope.put(global, "byteStreamSource", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "actual-node24-byte-Source12.json"))));
    const body = @embedFile("extensions/fixtures/env-readable-byte-stream-source-24.input.txt");
    const generation = engine.native_allocation_generation;
    const result = engine.evalModule(body ++ "\nif(JSON.stringify(packet)!==JSON.stringify(byteStreamSource[caseName]))throw Error(JSON.stringify({case:caseName,actual:packet,expected:byteStreamSource[caseName]}));export const proof=true;", "native-readable-byte-actual-Source12.mjs") catch |err| {
        const classified = engine.nativeAllocationError(err, generation);
        if (classified != error.OutOfMemory) std.debug.print("Native readable byte actual Source case {s}: {s}\n", .{ case_name, engine.last_error orelse "no diagnostic" });
        return classified;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native readable byte Source enqueue detaches storage" {
    try replay("enqueue-detach");
}
test "native readable byte Source BYOB nonzero offset" {
    try replay("byob-offset");
}
test "native readable byte Source minimum elements" {
    try replay("byob-min-elements");
}
test "native readable byte Source zero response" {
    try replay("respond-zero");
}
test "native readable byte Source partial element close" {
    try replay("close-partial-element");
}
test "native readable byte Source cancel identity and pending close" {
    try replay("cancel-identity");
}
test "native readable byte Source release retains BYOB request" {
    try replay("release-pending");
}
test "native readable byte Source serial pull" {
    try replay("pull-serialization");
}
test "native readable byte Source empty view validation" {
    try replay("empty-byob-invalid");
}
test "native readable byte Source replacement view" {
    try replay("respond-new-view");
}
test "native readable byte Source desired size" {
    try replay("desired-size");
}
test "native readable byte Source error identity" {
    try replay("error-identity");
}
