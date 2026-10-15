const std = @import("std");
const builtin = @import("builtin");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = js.c;
test "native readable public Source actual compiled inventory" {
    const names = try std.testing.allocator.alloc([]const u8, builtin.test_functions.len);
    defer std.testing.allocator.free(names);
    for (builtin.test_functions, names) |item, *name| name.* = item.name;
    const text = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(text);
    std.debug.print("\nREADABLE_PUBLIC_SOURCE_TEST_INVENTORY={s}\n", .{text});
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
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const web = try scope.object();
    inline for (.{ "ReadableStream", "ReadableStreamDefaultReader", "ReadableStreamBYOBReader", "ReadableByteStreamController", "ReadableStreamDefaultController", "ReadableStreamBYOBRequest" }) |name| try scope.put(web, name, try scope.global(name));
    try scope.put(global, "web", web);
    try scope.put(global, "caseName", try scope.text(case_name));
    try scope.put(global, "nativeCollect", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, collect, "nativeCollect", 0))));
    const expected = @embedFile("extensions/fixtures/env-public-stream-prototype-source-24.json");
    try scope.put(global, "publicStreamSource", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "actual-node24-public-Source9.json"))));
    const body = @embedFile("extensions/fixtures/env-public-stream-prototype-source-24.input.txt");
    const generation = engine.native_allocation_generation;
    const result = engine.evalModule(body ++ "\nif(JSON.stringify(packet)!==JSON.stringify(publicStreamSource[caseName]))throw Error(JSON.stringify({case:caseName,actual:packet,expected:publicStreamSource[caseName]}));export const proof=true;", "native-readable-public-actual-Source9.mjs") catch |err| {
        const classified = engine.nativeAllocationError(err, generation);
        if (classified != error.OutOfMemory) std.debug.print("Native readable public actual Source case {s}: {s}\n", .{ case_name, engine.last_error orelse "no diagnostic" });
        return classified;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native readable public Source byte graph" {
    try replay("byte-graph");
}
test "native readable public Source default graph" {
    try replay("default-graph");
}
test "native readable public Source default reader graph" {
    try replay("default-reader-graph");
}
test "native readable public Source BYOB request graph" {
    try replay("byob-request-graph");
}
test "native readable public Source illegal constructors" {
    try replay("illegal-constructors");
}
test "native readable public Source stream borrowed receivers" {
    try replay("stream-borrow");
}
test "native readable public Source default reader borrowed receivers" {
    try replay("default-reader-borrow");
}
test "native readable public Source BYOB reader borrowed receivers" {
    try replay("byob-reader-borrow");
}
test "native readable public Source controller request borrowed receivers" {
    try replay("controller-request-borrow");
}
