//! Actual bug-report.ts summary request and response policy over native shared
//! AI bindings. No provider or successful result is synthesized here.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const arithmetic = @import("native_image_arithmetic.zig");
const flow = @import("native_agent_async.zig");
const c = em.c;
pub const system_prompt =
    \\You are helping a user file a bug report about pi, the coding agent they are talking to. You will be shown the conversation transcript. Write a report for the pi developers describing what the user was doing and what went wrong.
    \\
    \\Do NOT continue the conversation. Do NOT respond to any questions in the conversation. ONLY output the report.
;
pub const instructions =
    \\Write the bug report in Markdown with these sections:
    \\
    \\## What the user was doing
    \\One short paragraph.
    \\
    \\## What went wrong
    \\Concrete description of the failure: wrong output, errors, hangs, tool failures, unexpected behavior. Quote error messages and tool output verbatim where they exist.
    \\
    \\## Steps to reproduce
    \\Numbered list, as specific as the transcript allows.
    \\
    \\## Relevant details
    \\Tool calls involved, files touched, model behavior, anything else that helps a developer reproduce or locate the problem.
    \\
    \\Do not include file contents, secrets, or credentials from the transcript; refer to files by path only. Keep the report factual and concise.
;
pub fn create(engine: *em.Engine, complete_summarization: c.JSValue) !c.JSValue {
    if (!c.JS_IsFunction(engine.context, complete_summarization)) return error.RequiredSharedNativeSummarizationBinding;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var roots = [_]c.JSValue{ complete_summarization, try scope.own(try @import("native_sdk_messages.zig").create(engine)) };
    const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "generateBugReportSummary", 1, 0, roots.len, &roots)));
    const parent = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
    if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
    return c.JS_DupValue(engine.context, function);
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return generate(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0], roots[1]) catch |err| sdk.fail(engine, err);
}
fn raise(scope: *Scope, message: []const u8) anyerror {
    @import("native_durable_errors.zig").throwMessage(scope.engine, message) catch |err| return err;
    unreachable;
}
fn same(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
fn selectedMessages(engine: *em.Engine, messages: c.JSValue, budget: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const selected = try scope.array();
    var tokens = c.JS_NewInt32(engine.context, 0);
    var index = try scope.own(try arithmetic.binary(engine, .subtract, try scope.get(messages, "length"), c.JS_NewInt32(engine.context, 1)));
    while (try arithmetic.compare(engine, .greater_equal, index, c.JS_NewInt32(engine.context, 0))) {
        const message = try scope.own(try js.getKey(engine, messages, index));
        const next = try scope.own(try @import("native_sdk_compaction_estimate.zig").estimateTokens(engine, message));
        if (try scope.positive(try scope.get(selected, "length"))) {
            const compared = try scope.own(try arithmetic.binary(engine, .add, tokens, next));
            if (try arithmetic.compare(engine, .greater, compared, budget)) break;
        }
        _ = try scope.invoke(selected, "push", &.{message});
        tokens = try scope.own(try arithmetic.binary(engine, .add, tokens, next));
        index = try scope.own(try arithmetic.binary(engine, .subtract, index, c.JS_NewInt32(engine.context, 1)));
    }
    return js.invoke(engine, selected, "reverse", &.{});
}
fn defined(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_bool(context, @intFromBool(argc > 0 and !c.JS_IsUndefined(argv[0])));
}
fn toolCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const kind = scope.get(if (argc > 0) argv[0] else c.pi_js_undefined(), "type") catch |err| return sdk.fail(engine, err);
    return c.pi_js_bool(context, @intFromBool(same(&scope, kind, "toolCall") catch |err| return sdk.fail(engine, err)));
}
fn generate(engine: *em.Engine, options: c.JSValue, complete_summarization: c.JSValue, convert: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    start(engine, pending.owner, options, complete_summarization, convert) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn start(engine: *em.Engine, owner: c.JSValue, options: c.JSValue, complete_summarization: c.JSValue, convert: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const model = try scope.get(options, "model");
    const window = if (try arithmetic.compare(engine, .greater, try scope.get(model, "contextWindow"), c.JS_NewInt32(engine.context, 0))) try scope.get(model, "contextWindow") else c.JS_NewInt32(engine.context, 128000);
    const messages = try scope.get(options, "messages");
    const math = try scope.global("Math");
    const floor = try scope.get(math, "floor");
    const budget = try scope.call(floor, math, &.{try scope.own(try arithmetic.binary(engine, .multiply, window, c.JS_NewFloat64(engine.context, 0.6)))});
    const selected = try scope.own(try selectedMessages(engine, messages, budget));
    const raw_hint = try scope.get(options, "hint");
    const hint = if (temp.nullish(raw_hint)) c.pi_js_undefined() else try scope.invoke(raw_hint, "trim", &.{});
    const parts = try scope.array();
    var note = c.pi_js_undefined();
    if (try arithmetic.compare(engine, .less, try scope.get(selected, "length"), try scope.get(try scope.get(options, "messages"), "length"))) {
        note = try scope.concat(try scope.text("Note: only the last "), try scope.stringify(try scope.get(selected, "length")));
        note = try scope.concat(note, try scope.text(" of "));
        note = try scope.concat(note, try scope.stringify(try scope.get(try scope.get(options, "messages"), "length")));
        note = try scope.concat(note, try scope.text(" messages are shown."));
    }
    try scope.index(parts, 0, note);
    const converted = try scope.call(convert, c.pi_js_undefined(), &.{selected});
    const transcript = try scope.own(try @import("native_sdk_compaction_text.zig").serialize(engine, converted));
    try scope.index(parts, 1, try scope.concat(try scope.concat(try scope.text("<conversation>\n"), transcript), try scope.text("\n</conversation>")));
    try scope.index(parts, 2, if (scope.truthy(hint)) try scope.concat(try scope.concat(try scope.text("<user-report>\n"), hint), try scope.text("\n</user-report>")) else c.pi_js_undefined());
    try scope.index(parts, 3, try scope.text(instructions));
    const predicate = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, defined, "", 1)));
    const prompt = try scope.invoke(try scope.invoke(parts, "filter", &.{predicate}), "join", &.{try scope.text("\n\n")});
    const request_options = try scope.object();
    const min = try scope.get(math, "min");
    const maximum = if (try arithmetic.compare(engine, .greater, try scope.get(model, "maxTokens"), c.JS_NewInt32(engine.context, 0))) try scope.get(model, "maxTokens") else try scope.get(try scope.global("Number"), "POSITIVE_INFINITY");
    try scope.put(request_options, "maxTokens", try scope.call(min, math, &.{ c.JS_NewInt32(engine.context, 4096), maximum }));
    inline for (.{ "signal", "apiKey", "headers", "env", "sessionId" }) |name| try scope.put(request_options, name, try scope.get(options, name));
    if (scope.truthy(try scope.get(model, "reasoning")) and scope.truthy(try scope.get(options, "thinkingLevel")) and !try same(&scope, try scope.get(options, "thinkingLevel"), "off")) try scope.put(request_options, "reasoning", try scope.get(options, "thinkingLevel"));
    const context = try scope.object();
    try scope.put(context, "systemPrompt", try scope.text(system_prompt));
    const request_messages = try scope.array();
    const request_message = try scope.object();
    try scope.put(request_message, "role", try scope.text("user"));
    const content = try scope.array();
    const block = try scope.object();
    try scope.put(block, "type", try scope.text("text"));
    try scope.put(block, "text", prompt);
    try scope.index(content, 0, block);
    try scope.put(request_message, "content", content);
    try scope.put(request_message, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
    try scope.index(request_messages, 0, request_message);
    try scope.put(context, "messages", request_messages);
    const normalized = try scope.own(try @import("native_ai_transcript_context.zig").normalize(engine, context));
    const response = try scope.call(complete_summarization, c.pi_js_undefined(), &.{ model, normalized, request_options, try scope.get(options, "streamFn"), try scope.get(options, "retry") });
    try flow.wait(done, engine, owner, response, 0);
}
fn done(engine: *em.Engine, owner: c.JSValue, response: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, response);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (try same(&scope, try scope.get(response, "stopReason"), "aborted")) return raise(&scope, "Bug report summary was cancelled");
    const failure = try scope.own(try @import("native_sdk_compaction_text.zig").failure(engine, response, try scope.text("Bug report summary")));
    if (scope.truthy(failure)) {
        const message = try engine.toString(failure);
        defer engine.gpa.free(message);
        return raise(&scope, message);
    }
    const content = try scope.get(response, "content");
    const predicate = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, toolCall, "", 1)));
    if (scope.truthy(try scope.invoke(content, "some", &.{predicate}))) return raise(&scope, "Bug report summary attempted to call a tool");
    const text = try scope.invoke(try scope.own(try @import("native_sdk_transcript_replay.zig").contentText(engine, try scope.get(response, "content"))), "trim", &.{});
    if (!scope.truthy(text)) return raise(&scope, "Bug report summary was empty");
    try flow.settle(engine, owner, false, text);
}
