//! Original summary generation and prepared compaction over native module bindings.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const math = @import("native_image_arithmetic.zig");
const flow = @import("native_agent_async.zig");
const c = em.c;
const Operation = enum(c_int) { generateSummaryWithUsage, generateSummary, compact };
pub fn exports(engine: *em.Engine, complete_request: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try scope.put(bindings, "request", complete_request);
    try scope.put(bindings, "convert", try scope.own(try @import("native_sdk_messages.zig").create(engine)));
    const result = try scope.object();
    inline for (@import("std").meta.fields(Operation)) |field| {
        var roots = [_]c.JSValue{bindings};
        const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, if (field.value == 2) 12 else 14, field.value, roots.len, &roots)));
        if (c.JS_SetPrototype(engine.context, function, try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)))) < 0) return js.capture(engine);
        try scope.put(result, field.name, function);
    }
    return c.JS_DupValue(engine.context, result);
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, kind: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var args = [_]c.JSValue{c.pi_js_undefined()} ** 14;
    if (argc > 0) for (argv[0..@min(args.len, @as(usize, @intCast(argc)))], 0..) |value, index| {
        args[index] = value;
    };
    return (switch (@as(Operation, @enumFromInt(kind))) {
        .generateSummaryWithUsage => generateUsage(engine, roots[0], &args, false),
        .generateSummary => generateText(engine, roots[0], &args),
        .compact => compact(engine, roots[0], args[0..12]),
    }) catch |err| sdk.fail(engine, err);
}
fn keepArgs(scope: *Scope, owner: c.JSValue, args: []const c.JSValue) !void {
    const values = try scope.array();
    for (args, 0..) |value, index| try scope.index(values, @intCast(index), value);
    try scope.put(owner, "args", values);
}
fn arg(scope: *Scope, owner: c.JSValue, index: u32) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, try scope.get(owner, "args"), index)));
}
fn raise(scope: *Scope, message: c.JSValue) anyerror {
    const constructor = scope.global("Error") catch |err| return err;
    var args = [_]c.JSValue{message};
    const reason = scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, &args)) catch |err| return err;
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, reason)) catch |err| return err;
    unreachable;
}
fn completionOptions(scope: *Scope, owner: c.JSValue) !c.JSValue {
    const options = try scope.object();
    inline for (.{ "signal", "apiKey", "headers", "env", "sessionId" }, .{ try arg(scope, owner, 5), try arg(scope, owner, 3), try arg(scope, owner, 4), try arg(scope, owner, 10), try arg(scope, owner, 13) }) |name, value| try scope.put(options, name, value);
    const thinking = try arg(scope, owner, 8);
    if (scope.truthy(try scope.get(try arg(scope, owner, 1), "reasoning")) and scope.truthy(thinking) and !scope.equal(thinking, try scope.text("off"))) try scope.put(options, "reasoning", thinking);
    return options;
}
fn buildContext(scope: *Scope, prompt: c.JSValue) !c.JSValue {
    const context = try scope.object();
    try scope.put(context, "systemPrompt", try scope.text(@embedFile("compaction_system_prompt_b45.txt")));
    const messages = try scope.array();
    const message = try scope.object();
    try scope.put(message, "role", try scope.text("user"));
    const content = try scope.array();
    const block = try scope.object();
    try scope.put(block, "type", try scope.text("text"));
    try scope.put(block, "text", prompt);
    try scope.index(content, 0, block);
    try scope.put(message, "content", content);
    try scope.put(message, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
    try scope.index(messages, 0, message);
    try scope.put(context, "messages", messages);
    return scope.own(try @import("native_ai_transcript_context.zig").normalize(scope.engine, context));
}
fn generateUsage(engine: *em.Engine, bindings: c.JSValue, args: []const c.JSValue, prefix: bool) !c.JSValue {
    const pending = try flow.create(engine, bindings);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    generationStart(engine, pending.owner, args, prefix) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn generationStart(engine: *em.Engine, owner: c.JSValue, args: []const c.JSValue, prefix: bool) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try keepArgs(&scope, owner, args);
    try scope.put(owner, "prefix", c.pi_js_bool(engine.context, @intFromBool(prefix)));
    var base_prompt = if (prefix) c.pi_js_undefined() else try scope.text(if (scope.truthy(args[7])) @embedFile("compaction_update_prompt_b45.txt") else @embedFile("compaction_initial_prompt_b45.txt"));
    if (!prefix and scope.truthy(args[6])) base_prompt = try scope.concat(try scope.concat(base_prompt, try scope.text("\n\nAdditional focus: ")), try scope.stringify(args[6]));
    const bindings = try scope.get(owner, "agent");
    const messages = try scope.call(try scope.get(bindings, "convert"), c.pi_js_undefined(), &.{args[0]});
    const conversation = try scope.own(try @import("native_sdk_compaction_text.zig").serialize(engine, messages));
    var prompt = try scope.concat(try scope.text(if (prefix) "# Conversation\n" else "<conversation>\n"), try scope.stringify(conversation));
    if (prefix) {
        prompt = try scope.concat(prompt, try scope.text("\n\n# Instructions\n"));
        prompt = try scope.concat(prompt, try scope.text(@embedFile("compaction_turnprefix_prompt_b45.txt")));
    } else {
        prompt = try scope.concat(prompt, try scope.text("\n</conversation>\n\n"));
        if (scope.truthy(args[7])) {
            prompt = try scope.concat(prompt, try scope.text("<previous-summary>\n"));
            prompt = try scope.concat(prompt, try scope.stringify(args[7]));
            prompt = try scope.concat(prompt, try scope.text("\n</previous-summary>\n\n"));
        }
        prompt = try scope.concat(prompt, base_prompt);
    }
    var options = c.pi_js_undefined();
    var context = c.pi_js_undefined();
    if (prefix) {
        context = try buildContext(&scope, prompt);
        options = try completionOptions(&scope, owner);
    } else {
        options = try completionOptions(&scope, owner);
        context = try buildContext(&scope, prompt);
    }
    const completion = try scope.call(try scope.get(bindings, "request"), c.pi_js_undefined(), &.{ args[1], context, options, args[9], args[11], args[12] });
    return flow.wait(generationReady, engine, owner, completion, 0);
}
fn isToolCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const value = sdk.get(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), "type") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(value);
    const expected = sdk.text(engine, "toolCall") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(expected);
    return c.pi_js_bool(context, @intFromBool(c.JS_IsStrictEqual(context, value, expected)));
}
fn generationReady(engine: *em.Engine, owner: c.JSValue, response: c.JSValue, failed: bool, _: c_int) !void {
    if (failed) return flow.settle(engine, owner, true, response);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prefix = scope.truthy(try scope.get(owner, "prefix"));
    const failure = try scope.own(try @import("native_sdk_compaction_text.zig").failure(engine, response, try scope.text(if (prefix) "Turn prefix summarization" else "Summarization")));
    if (scope.truthy(failure)) return raise(&scope, failure);
    const content = try scope.get(response, "content");
    const some = try scope.get(content, "some");
    const callback = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, isToolCall, "", 1)));
    if (scope.truthy(try scope.call(some, content, &.{callback}))) return raise(&scope, try scope.text(if (prefix) "Turn prefix summarization attempted to call a tool" else "Summarization attempted to call a tool"));
    const result = try scope.object();
    try scope.put(result, "text", try scope.own(try @import("native_sdk_transcript_replay.zig").contentText(engine, try scope.get(response, "content"))));
    try scope.put(result, "usage", try scope.get(response, "usage"));
    return flow.settle(engine, owner, false, result);
}
fn generateText(engine: *em.Engine, bindings: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, bindings);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    const value = generateUsage(engine, bindings, args, false) catch |err| {
        try flow.rejectError(engine, pending.owner, err);
        return pending.promise;
    };
    defer engine.freeValue(value);
    flow.wait(textReady, engine, pending.owner, value, 0) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn textReady(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, failed: bool, _: c_int) !void {
    if (failed) return flow.settle(engine, owner, true, value);
    const text = try sdk.get(engine, value, "text");
    defer engine.freeValue(text);
    return flow.settle(engine, owner, false, text);
}
fn compact(engine: *em.Engine, bindings: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, bindings);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    compactStart(engine, pending.owner, args) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn compactStart(engine: *em.Engine, owner: c.JSValue, args: []const c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try keepArgs(&scope, owner, args);
    inline for (.{ "firstKeptEntryId", "messagesToSummarize", "turnPrefixMessages", "isSplitTurn", "tokensBefore", "previousSummary", "fileOps" }) |name| try scope.put(owner, name, try scope.get(args[0], name));
    const split = scope.truthy(try scope.get(owner, "isSplitTurn")) and try math.compare(engine, .greater, try scope.get(try scope.get(owner, "turnPrefixMessages"), "length"), c.JS_NewInt32(engine.context, 0));
    try scope.put(owner, "split", c.pi_js_bool(engine.context, @intFromBool(split)));
    if (split) {
        const previous = try scope.get(owner, "previousSummary");
        try scope.put(owner, "historyText", if (c.JS_IsNull(previous) or c.JS_IsUndefined(previous)) try scope.text("No prior history.") else previous);
        try scope.put(owner, "historyUsage", c.pi_js_undefined());
        if (!try math.compare(engine, .greater, try scope.get(try scope.get(owner, "messagesToSummarize"), "length"), c.JS_NewInt32(engine.context, 0))) return requestPart(&scope, owner, true);
    }
    return requestPart(&scope, owner, false);
}
fn requestPart(scope: *Scope, owner: c.JSValue, prefix: bool) !void {
    const args = [_]c.JSValue{
        try scope.get(owner, if (prefix) "turnPrefixMessages" else "messagesToSummarize"),
        try arg(scope, owner, 1),
        c.pi_js_undefined(),
        try arg(scope, owner, 2),
        try arg(scope, owner, 3),
        try arg(scope, owner, 5),
        if (prefix) c.pi_js_undefined() else try arg(scope, owner, 4),
        if (prefix) c.pi_js_undefined() else try scope.get(owner, "previousSummary"),
        try arg(scope, owner, 6),
        try arg(scope, owner, 7),
        try arg(scope, owner, 8),
        try arg(scope, owner, 9),
        try arg(scope, owner, 10),
        try arg(scope, owner, 11),
    };
    const value = try scope.own(try generateUsage(scope.engine, try scope.get(owner, "agent"), &args, prefix));
    return flow.wait(compactReady, scope.engine, owner, value, if (prefix) 1 else 0);
}
fn compactReady(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, failed: bool, stage: c_int) !void {
    if (failed) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (stage == 0 and scope.truthy(try scope.get(owner, "split"))) {
        try scope.put(owner, "historyText", try scope.get(value, "text"));
        try scope.put(owner, "historyUsage", try scope.get(value, "usage"));
        return requestPart(&scope, owner, true);
    }
    var summary = c.pi_js_undefined();
    var usage = c.pi_js_undefined();
    if (stage == 1) {
        summary = try scope.concat(try scope.stringify(try scope.get(owner, "historyText")), try scope.text("\n\n---\n\n**Turn Context (split turn):**\n\n"));
        summary = try scope.concat(summary, try scope.stringify(try scope.get(value, "text")));
        const history_usage = try scope.get(owner, "historyUsage");
        usage = if (scope.truthy(history_usage)) try scope.own(try @import("native_sdk_session_hooks.zig").combineUsage(engine, history_usage, try scope.get(value, "usage"))) else try scope.get(value, "usage");
    } else {
        summary = try scope.get(value, "text");
        usage = try scope.get(value, "usage");
    }
    const lists = try scope.own(try @import("native_sdk_compaction_files.zig").lists(engine, try scope.get(owner, "fileOps")));
    const read_files = try scope.get(lists, "readFiles");
    const modified_files = try scope.get(lists, "modifiedFiles");
    summary = try scope.concat(summary, try scope.own(try @import("native_sdk_compaction_files.zig").format(engine, read_files, modified_files)));
    if (!scope.truthy(try scope.get(owner, "firstKeptEntryId"))) return raise(&scope, try scope.text("First kept entry has no UUID - session may need migration"));
    const result = try scope.object();
    try scope.put(result, "summary", summary);
    try scope.put(result, "firstKeptEntryId", try scope.get(owner, "firstKeptEntryId"));
    try scope.put(result, "tokensBefore", try scope.get(owner, "tokensBefore"));
    try scope.put(result, "usage", usage);
    const details = try scope.object();
    try scope.put(details, "readFiles", read_files);
    try scope.put(details, "modifiedFiles", modified_files);
    try scope.put(result, "details", details);
    return flow.settle(engine, owner, false, result);
}
