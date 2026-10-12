//! Coding-agent message conversion, preserving the original live map/filter
//! calls, message identity, property reads and JavaScript coercion semantics.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;

pub fn create(engine: *em.Engine) !c.JSValue {
    return @import("native_node_function.zig").create(engine, "convertToLlm", 1, convert, &.{});
}
fn convert(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const messages = if (args.len > 0) args[0] else c.pi_js_undefined();
    const mapper = try scope.get(messages, "map");
    const callback = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, mapMessage, "", 1)));
    const mapped = try scope.call(mapper, messages, &.{callback});
    const filter = try scope.get(mapped, "filter");
    const predicate = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, keepMessage, "", 1)));
    return c.JS_DupValue(engine.context, try scope.call(filter, mapped, &.{predicate}));
}
fn keepMessage(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_bool(context, @intFromBool(argc > 0 and !c.JS_IsUndefined(args[0])));
}
fn mapMessage(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return map(engine, if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn textContent(scope: *Scope, text: c.JSValue) !c.JSValue {
    const content = try scope.array();
    const block = try scope.object();
    try scope.put(block, "type", try scope.text("text"));
    try scope.put(block, "text", text);
    try scope.index(content, 0, block);
    return content;
}
fn userMessage(scope: *Scope, source: c.JSValue, content: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "role", try scope.text("user"));
    try scope.put(result, "content", content);
    try scope.put(result, "timestamp", try scope.get(source, "timestamp"));
    return result;
}
fn map(engine: *em.Engine, message: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const role = try scope.get(message, "role");
    inline for (.{ "system", "user", "assistant", "toolResult" }) |kind| {
        if (scope.equal(role, try scope.text(kind))) return c.JS_DupValue(engine.context, message);
    }
    const result = if (scope.equal(role, try scope.text("bashExecution"))) result: {
        if (scope.truthy(try scope.get(message, "excludeFromContext"))) return c.pi_js_undefined();
        break :result try userMessage(&scope, message, try textContent(&scope, try bashText(&scope, message)));
    } else if (scope.equal(role, try scope.text("custom"))) result: {
        const initial = try scope.get(message, "content");
        const content = if (c.JS_IsString(initial)) try textContent(&scope, try scope.get(message, "content")) else try scope.get(message, "content");
        break :result try userMessage(&scope, message, content);
    } else if (scope.equal(role, try scope.text("branchSummary"))) result: {
        const prefix = try scope.text("The following is a summary of a branch that this conversation came back from:\n\n<summary>\n");
        const text = try scope.concat(try scope.concat(prefix, try scope.get(message, "summary")), try scope.text("</summary>"));
        break :result try userMessage(&scope, message, try textContent(&scope, text));
    } else if (scope.equal(role, try scope.text("compactionSummary"))) result: {
        const prefix = try scope.text("The conversation history before this point was compacted into the following summary:\n\n<summary>\n");
        const text = try scope.concat(try scope.concat(prefix, try scope.get(message, "summary")), try scope.text("\n</summary>"));
        break :result try userMessage(&scope, message, try textContent(&scope, text));
    } else return c.pi_js_undefined();
    return c.JS_DupValue(engine.context, result);
}
fn bashText(scope: *Scope, message: c.JSValue) !c.JSValue {
    var text = try scope.concat(try scope.concat(try scope.text("Ran `"), try scope.stringify(try scope.get(message, "command"))), try scope.text("`\n"));
    const output = if (scope.truthy(try scope.get(message, "output"))) output: {
        break :output try scope.concat(try scope.concat(try scope.text("```\n"), try scope.stringify(try scope.get(message, "output"))), try scope.text("\n```"));
    } else try scope.text("(no output)");
    text = try scope.concat(text, output);
    if (scope.truthy(try scope.get(message, "cancelled"))) {
        text = try scope.concat(text, try scope.text("\n\n(command cancelled)"));
    } else if (!c.JS_IsNull(try scope.get(message, "exitCode")) and !c.JS_IsUndefined(try scope.get(message, "exitCode")) and !scope.equal(try scope.get(message, "exitCode"), c.JS_NewInt32(scope.engine.context, 0))) {
        text = try scope.concat(text, try scope.concat(try scope.text("\n\nCommand exited with code "), try scope.stringify(try scope.get(message, "exitCode"))));
    }
    if (scope.truthy(try scope.get(message, "truncated")) and scope.truthy(try scope.get(message, "fullOutputPath"))) {
        text = try scope.concat(text, try scope.concat(try scope.concat(try scope.text("\n\n[Output truncated. Full output: "), try scope.stringify(try scope.get(message, "fullOutputPath"))), try scope.text("]")));
    }
    return text;
}
