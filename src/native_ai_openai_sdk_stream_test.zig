const std = @import("std");
const em = @import("extensions/engine.zig");
const v = @import("extensions/native_ai_provider_values.zig");
const Scope = v.Scope;
const c = em.c;
fn subject(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return @import("extensions/native_ai_openai_sdk_stream.zig").fromBodyIterator(engine, args[0], .{
        .codec = try scope.own(try @import("extensions/native_ai_openai_sdk_chunks.zig").codec(engine)),
        .controller = args[1],
        .error_factory = try scope.own(try @import("extensions/native_ai_openai_sdk_error.zig").factory(engine, args[2])),
        .logger = try scope.global("console"),
    });
}
fn install(engine: *em.Engine) !void {
    try @import("extensions/text_encoding.zig").install(engine);
    try @import("extensions/text_decoder.zig").install(engine);
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/native_headers.zig").install(engine);
    try @import("extensions/console.zig").install(engine, std.testing.io);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try @import("extensions/native_sdk.zig").put(engine, global, "nativeSdkSubject", try @import("extensions/native_node_function.zig").create(engine, "nativeSdkSubject", 3, subject, &.{}));
}
fn exercise(engine: *em.Engine) !void {
    const source = @embedFile("extensions/fixtures/ai-openai-sdk-producer16-ae7.json");
    const original = try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "genuine-openai-sdk16.json"));
    defer engine.freeValue(original);
    const expected_rows = try v.js.get(engine, original, "rows");
    defer engine.freeValue(expected_rows);
    const module = engine.evalModule(@embedFile("extensions/fixtures/ai-openai-sdk-producer16-ae7.input.txt"), "native-openai-sdk-producer16.mjs") catch |err| {
        std.debug.print("SDKProducer16: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    defer engine.freeValue(module);
    const rows = try v.js.get(engine, module, "default");
    defer engine.freeValue(rows);
    const actual = try engine.stringify(rows);
    defer engine.gpa.free(actual);
    const expected = try engine.stringify(expected_rows);
    defer engine.gpa.free(expected);
    try std.testing.expectEqualStrings(expected, actual);
}
test "native OpenAI SDK three producer generators match genuine Source16 complete framing and ownership traces" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    try exercise(engine);
    c.JS_RunGC(engine.runtime);
}
test "native OpenAI SDK producer traces survive forced GC with cached codec roots" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const Adapter = struct {
        fn collect(host: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            c.JS_RunGC(host.runtime);
            return c.pi_js_undefined();
        }
    };
    try @import("extensions/native_sdk.zig").put(engine, global, "collectSdkRoots", try @import("extensions/native_node_function.zig").create(engine, "", 0, Adapter.collect, &.{}));
    const installed = try engine.evalModule("const parse=JSON.parse;JSON.parse=function(...args){collectSdkRoots();return Reflect.apply(parse,this,args)};export const done=true;", "native-sdk-gc-parse-hook.mjs");
    engine.freeValue(installed);
    try exercise(engine);
    c.JS_RunGC(engine.runtime);
}
