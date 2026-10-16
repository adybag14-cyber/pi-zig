const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
fn convert(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return @import("extensions/native_ai_google_messages.zig").convert(engine, args[0], args[1]);
}
test "native Google4dd tool output whitespace live trim relational length and raw reason identity" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(try scope.own(c.JS_GetGlobalObject(engine.context)), "nativeGoogleToolOutput4dd", try scope.own(try @import("extensions/native_node_function.zig").create(engine, "convertGoogleToolOutput4dd", 2, convert, &.{})));
    const evaluated = try engine.evalModule(@embedFile("extensions/fixtures/ai-google-tool-output4dd-native.input.txt"), "native-google-tool-output4dd-controls.mjs");
    engine.freeValue(evaluated);
}
