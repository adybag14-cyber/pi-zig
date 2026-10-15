const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;

test "native Claude5ab extended actual Source14 seven supplied SDK client traces with identical whole-byte reader and awaited cleanup" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try @import("extensions/text_encoding.zig").install(engine);
    try @import("extensions/text_decoder.zig").install(engine);
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/native_headers.zig").install(engine);
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "sdkBoundaryStreams", try scope.own(try @import("extensions/native_ai_anthropic_factory.zig").create(engine)));
    const bytes = @embedFile("extensions/fixtures/ai-anthropic5ab-sdk-boundaries.json");
    try scope.put(global, "sdkBoundarySource", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "actual-anthropic-sdk-boundary-source14.json"))));
    const guest = @embedFile("extensions/fixtures/ai-anthropic5ab-sdk-boundaries-native.mjs");
    const result = engine.evalModule(guest ++ "\nexport const compared=await runSupplied(sdkBoundarySource,sdkBoundaryStreams);", "native-anthropic-sdk-supplied-source14.mjs") catch |err| {
        std.debug.print("Anthropic supplied SDK Source14: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
