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
    const source = @embedFile("extensions/fixtures/ai-openai-tool-output4dd.expected.json");
    try scope.put(try scope.own(c.JS_GetGlobalObject(engine.context)), "openaiToolOutput4ddSource", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "genuine-openai4dd-Source52.json"))));
    const evaluated = try engine.evalModule(@embedFile("extensions/fixtures/ai-openai-tool-output4dd-native.input.txt") ++
        "\nif(observations.length!==52||openaiToolOutput4ddSource.observations.length!==52)throw Error('all52 required');for(let i=0;i<52;i++)if(JSON.stringify(observations[i])!==JSON.stringify(openaiToolOutput4ddSource.observations[i]))throw Error(JSON.stringify({case:i,actual:observations[i],expected:openaiToolOutput4ddSource.observations[i]}));", "native-openai-tool-output4dd-controls.mjs");
    engine.freeValue(evaluated);
}
