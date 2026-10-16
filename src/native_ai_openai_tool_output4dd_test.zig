const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
fn convert(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const config = try scope.object();
    const grammar = try scope.own(try v.js.builtin(engine, "Map", &.{}));
    if (try v.eq(&scope, try scope.get(args[0], "api"), "openai-completions")) return @import("extensions/native_ai_openai_messages.zig").convert(engine, args[0], args[1], config, grammar);
    return c.JS_DupValue(engine.context, try @import("extensions/native_ai_responses_request.zig").messages(&scope, args[0], args[1], config, grammar, c.pi_js_undefined(), .standard));
}
test "native OpenAI4dd tool output whitespace live trim relational length and raw reason identity" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(try scope.own(c.JS_GetGlobalObject(engine.context)), "nativeToolOutput4dd", try scope.own(try @import("extensions/native_node_function.zig").create(engine, "convertToolOutput4dd", 2, convert, &.{})));
    const evaluated = try engine.evalModule(@embedFile("extensions/fixtures/ai-openai-tool-output4dd-native.input.txt"), "native-openai-tool-output4dd-controls.mjs");
    engine.freeValue(evaluated);
}
