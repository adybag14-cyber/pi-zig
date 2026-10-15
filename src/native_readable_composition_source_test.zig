const std = @import("std");
const builtin = @import("builtin");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = js.c;
test "native readable composition Source actual compiled inventory" {
    const names = try std.testing.allocator.alloc([]const u8, builtin.test_functions.len);
    defer std.testing.allocator.free(names);
    for (builtin.test_functions, names) |item, *name| name.* = item.name;
    const text = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(text);
    std.debug.print("\nREADABLE_COMPOSITION_SOURCE_TEST_INVENTORY={s}\n", .{text});
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
    const expected = @embedFile("extensions/fixtures/env-readable-composition-source-24.json");
    try scope.put(global, "compositionStreamSource", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "actual-node24-composition-Source12.json"))));
    const body = @embedFile("extensions/fixtures/env-readable-composition-source-24.input.txt");
    const generation = engine.native_allocation_generation;
    const result = engine.evalModule(body ++ "\nif(JSON.stringify(packet)!==JSON.stringify(compositionStreamSource[caseName]))throw Error(JSON.stringify({case:caseName,actual:packet,expected:compositionStreamSource[caseName]}));export const proof=true;", "native-readable-composition-actual-Source12.mjs") catch |err| {
        const classified = engine.nativeAllocationError(err, generation);
        if (classified != error.OutOfMemory) std.debug.print("Native readable composition actual Source case {s}: {s}\n", .{ case_name, engine.last_error orelse "no diagnostic" });
        return classified;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native readable composition Source default-size-direct" {
    try replay("default-size-direct");
}
test "native readable composition Source default-zero-size-close" {
    try replay("default-zero-size-close");
}
test "native readable composition Source default-size-throw" {
    try replay("default-size-throw");
}
test "native readable composition Source constructor-order" {
    try replay("constructor-order");
}
test "native readable composition Source tee-default-identity" {
    try replay("tee-default-identity");
}
test "native readable composition Source tee-byob-first" {
    try replay("tee-byob-first");
}
test "native readable composition Source tee-reader-switch" {
    try replay("tee-reader-switch");
}
test "native readable composition Source tee-cancel-reasons" {
    try replay("tee-cancel-reasons");
}
test "native readable composition Source iterator-queue-values" {
    try replay("iterator-queue-values");
}
test "native readable composition Source iterator-prevent-cancel" {
    try replay("iterator-prevent-cancel");
}
test "native readable composition Source iterator-error-identity" {
    try replay("iterator-error-identity");
}
test "native readable composition Source iterator-return-cancel-reject" {
    try replay("iterator-return-cancel-reject");
}
