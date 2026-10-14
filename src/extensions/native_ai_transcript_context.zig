//! Original transcript context normalization over live guest values.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
pub fn exports(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    inline for (.{ "createInitialSystemMessage", "normalizeContext" }, 0..) |name, kind| {
        const Adapter = struct {
            fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
                host.native_exception_diagnostics_suppressed += 1;
                defer host.native_exception_diagnostics_suppressed -= 1;
                const first = if (args.len > 0) args[0] else c.pi_js_undefined();
                return if (kind == 0) initial(host, first, if (args.len > 1) args[1] else c.pi_js_undefined()) else normalize(host, first);
            }
        };
        try scope.put(result, name, try scope.own(try @import("native_node_function.zig").create(engine, name, if (kind == 0) 2 else 1, Adapter.call, &.{})));
    }
    return c.JS_DupValue(engine.context, result);
}
pub fn initial(engine: *em.Engine, prompt: c.JSValue, tools: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const has_prompt = !c.JS_IsUndefined(prompt) and try arithmetic.compare(engine, .greater, try scope.get(prompt, "length"), c.JS_NewInt32(engine.context, 0));
    const has_tools = !c.JS_IsUndefined(tools) and try arithmetic.compare(engine, .greater, try scope.get(tools, "length"), c.JS_NewInt32(engine.context, 0));
    if (!has_prompt and !has_tools) return c.pi_js_undefined();
    const result = try scope.object();
    try scope.put(result, "role", try scope.text("system"));
    try scope.put(result, "content", if (c.JS_IsNull(prompt) or c.JS_IsUndefined(prompt)) try scope.text("") else prompt);
    if (has_tools) try scope.put(result, "toolsAdded", tools);
    try scope.put(result, "timestamp", c.JS_NewInt32(engine.context, 0));
    return c.JS_DupValue(engine.context, result);
}
pub fn normalize(engine: *em.Engine, context: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prompt = try scope.get(context, "systemPrompt");
    const tools = try scope.get(context, "tools");
    const first = try scope.own(try initial(engine, prompt, tools));
    const messages = try scope.get(context, "messages");
    const output = if (scope.truthy(first)) try scope.own(try @import("native_sdk_transcript_replay.zig").arraySpread(engine, messages, first)) else messages;
    const result = try scope.object();
    try scope.put(result, "messages", output);
    return c.JS_DupValue(engine.context, result);
}
