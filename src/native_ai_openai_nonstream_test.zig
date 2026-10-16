const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
fn parse(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(engine.context, try @import("extensions/native_ai_openai_sdk_request.zig").parseResponse(&scope, args[1], args[0]));
}
test "native OpenAI SDK nonstream response raw brands live getters and reader timing" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 20000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/text_encoding.zig").install(engine);
    try @import("extensions/text_decoder.zig").install(engine);
    try @import("extensions/native_headers.zig").install(engine);
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/console.zig").install(engine, std.testing.io);
    try @import("extensions/native_web_fetch.zig").install(engine);
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(try scope.own(c.JS_GetGlobalObject(engine.context)), "nativeSDKParse", try scope.own(try @import("extensions/native_node_function.zig").create(engine, "nativeSDKParse", 2, parse, &.{})));
    const result = try engine.evalModule(@embedFile("extensions/fixtures/ai-openai-nonstream-primary.input.txt") ++ "export const observations=await observeNonstream(nativeSDKParse);if(observations.length!==57)throw Error('All57 authored nonstream controls required');", "native-openai-nonstream-controls.mjs");
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
