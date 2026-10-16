//! Strict full-packet Source16 gate; expected intentionally absent until capture acceptance.
const std = @import("std");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const c = js.c;
fn collect(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(js.Engine.fromContext(context.?).runtime);
    return c.pi_js_undefined();
}
fn replay(case_name: []const u8) !void {
    const engine = try js.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/native_node_stream_web.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "caseName", try scope.text(case_name));
    try scope.put(global, "nativeCollect", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, collect, "nativeCollect", 0))));
    const expected = @embedFile("extensions/fixtures/stream-web-queue-text-node24.json");
    try scope.put(global, "streamWebSource", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "actual-node24-stream-web-Source16.json"))));
    const value = engine.evalModule("import * as web from 'node:stream/web';\n" ++ @embedFile("extensions/fixtures/stream-web-queue-text-node24.input.txt") ++ "\nif(JSON.stringify(packet)!==JSON.stringify(streamWebSource[caseName]))throw Error(JSON.stringify({case:caseName,actual:packet,expected:streamWebSource[caseName]}));export const proof=true;", "native-stream-web-source16.mjs") catch |err| {
        std.debug.print("Native stream web Source16 {s}: {s}\n", .{ case_name, engine.last_error orelse "no diagnostic" });
        return err;
    };
    engine.freeValue(value);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
test "native stream web Source16 namespace-metadata" {
    try replay("namespace-metadata");
}
test "native stream web Source16 queue-basic" {
    try replay("queue-basic");
}
test "native stream web Source16 queue-conversion" {
    try replay("queue-conversion");
}
test "native stream web Source16 queue-errors" {
    try replay("queue-errors");
}
test "native stream web Source16 queue-brand" {
    try replay("queue-brand");
}
test "native stream web Source16 queue-size-getters" {
    try replay("queue-size-getters");
}
test "native stream web Source16 encoder-carry" {
    try replay("encoder-carry");
}
test "native stream web Source16 encoder-empty-eof" {
    try replay("encoder-empty-eof");
}
test "native stream web Source16 encoder-conversion" {
    try replay("encoder-conversion");
}
test "native stream web Source16 encoder-error" {
    try replay("encoder-error");
}
test "native stream web Source16 decoder-utf8-bom" {
    try replay("decoder-utf8-bom");
}
test "native stream web Source16 decoder-utf16" {
    try replay("decoder-utf16");
}
test "native stream web Source16 decoder-options" {
    try replay("decoder-options");
}
test "native stream web Source16 decoder-fatal" {
    try replay("decoder-fatal");
}
test "native stream web Source16 decoder-undefined" {
    try replay("decoder-undefined");
}
test "native stream web Source16 decoder-gc" {
    try replay("decoder-gc");
}
