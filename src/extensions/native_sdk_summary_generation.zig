//! Actual c268 summary generation and prepared compaction. QuickJS owns the
//! genuine async capabilities, Await stages, and terminal adoption. Source
//! locals remain in marked activation owners until the VM retires native_state.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const af = v.af;
const Engine = h.Engine;
const Scope = h.Scope;
const frames = @import("native_public_lexical_frame.zig");
const serializer = @import("native_sdk_compaction_text.zig");
const content_text = @import("native_sdk_transcript_replay.zig");
const transcript = @import("native_ai_transcript_context.zig");
const files = @import("native_sdk_compaction_file_ops.zig");
const usage = @import("native_sdk_usage_combine.zig");
const module_cache_key = "pi-private:sdk-summary-generation-c268";
const UsageFrame = frames.Frame(enum {
    base_prompt, llm_messages, conversation_text, prompt_text, completion_options, response, failure, text_content,
});
const PrefixFrame = frames.Frame(enum { llm_messages, conversation_text, prompt_text, response, failure });
const CompactFrame = frames.Frame(enum {
    first_kept, messages, turn_prefix, split, tokens_before, previous_summary, file_ops,
    summary, summary_usage, history_text, history_usage, history_result, turn_result,
    result, read_files, modified_files, stage,
});
const CompactStage = enum(i32) { history, prefix, whole };

pub fn exports(engine: *Engine, complete_request: c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(module_cache_key)) |cached| return h.duplicate(engine, cached);
    const candidate = try h.expression(engine, exportsBody, .{complete_request});
    if (engine.native_module_values.get(module_cache_key)) |cached| {
        var selected = v.owned.Completion.initValue(engine, h.duplicate(engine, cached));
        selected.release(candidate);
        return selected.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var failed = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        failed.release(candidate);
        return failed.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(module_cache_key, candidate);
    return h.duplicate(engine, candidate);
}
fn asyncFunction(s: *Scope, name: [*:0]const u8, length: c_int, callback: af.Body, roots: []const c.JSValue) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    return boundary.finishValue(s, af.createResumable(s.engine, name, length, callback, roots));
}
fn updatePrompt(s: *Scope) !c.JSValue {
    return v.duplicate(s, try v.text(s, @embedFile("compaction_update_prompt_b45.txt")));
}
fn exportsBody(s: *Scope, complete_request: c.JSValue) !c.JSValue {
    const convert = try v.own(s, try @import("native_sdk_messages.zig").create(s.engine));
    const updated_prompt = try v.own(s, try h.expression(s.engine, updatePrompt, .{}));
    const with_usage = try asyncFunction(s, "generateSummaryWithUsage", 14, usageBody, &.{ complete_request, convert, updated_prompt });
    const prefix = try asyncFunction(s, "generateTurnPrefixSummary", 11, prefixBody, &.{ complete_request, convert });
    const result = try v.object(s);
    try v.put(s, result, "generateSummaryWithUsage", with_usage);
    try v.put(s, result, "generateSummary", try asyncFunction(s, "generateSummary", 14, textBody, &.{with_usage}));
    try v.put(s, result, "compact", try asyncFunction(s, "compact", 12, compactBody, &.{ with_usage, prefix }));
    return v.duplicate(s, result);
}
fn initialize(s: *Scope, state: *c.JSValue, comptime Frame: type) !*Frame {
    const frame = try Frame.create(s);
    af.replaceState(s.engine, state, v.duplicate(s, frame.owner));
    return frame;
}
fn rejected(engine: *Engine, input: c.JSValue) !af.Action {
    try @import("native_async_body.zig").enterRejectedContinuation(engine);
    return .{ .thrown = h.duplicate(engine, input) };
}
fn returnedField(s: *Scope, input: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const temporary = try v.own(s, h.duplicate(s.engine, input));
    return v.duplicate(s, try v.get(s, temporary, name));
}
fn callSummary(s: *Scope, function: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const actual = [_]c.JSValue{
        v.arg(args, 0), v.arg(args, 1), v.arg(args, 2), v.arg(args, 3),
        v.arg(args, 4), v.arg(args, 5), v.arg(args, 6), v.arg(args, 7),
        v.arg(args, 8), v.arg(args, 9), v.arg(args, 10), v.arg(args, 11),
        v.arg(args, 12), v.arg(args, 13),
    };
    return v.duplicate(s, try v.call(s, function, c.pi_js_undefined(), &actual));
}
fn textBody(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, _: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return rejected(engine, input);
    if (completion == .start) return .{ .awaited = try h.expression(engine, callSummary, .{ roots[0], args }) };
    return .{ .returned = try h.expression(engine, returnedField, .{ input, @as([*:0]const u8, "text") }) };
}
pub fn options(engine: *Engine, model: c.JSValue, api_key: c.JSValue, headers: c.JSValue, env: c.JSValue, signal: c.JSValue, thinking: c.JSValue, session_id: c.JSValue) !c.JSValue {
    return h.expression(engine, optionsBody, .{ model, api_key, headers, env, signal, thinking, session_id });
}
fn optionsBody(s: *Scope, model: c.JSValue, api_key: c.JSValue, headers: c.JSValue, env: c.JSValue, signal: c.JSValue, thinking: c.JSValue, session_id: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    inline for (.{ "signal", "apiKey", "headers", "env", "sessionId" }, .{ signal, api_key, headers, env, session_id }) |name, value|
        try v.put(s, result, name, value);
    if (try h.fieldTest(s.engine, model, "reasoning", .truthy) and v.truthy(s, thinking) and !try v.eq(s, thinking, "off"))
        try h.assign(s.engine, result, "reasoning", thinking);
    return v.duplicate(s, result);
}
fn now(s: *Scope) !c.JSValue {
    const date = try v.global(s, "Date");
    const method = try v.get(s, date, "now");
    return v.duplicate(s, try v.call(s, method, date, &.{}));
}
pub fn context(engine: *Engine, prompt: c.JSValue) !c.JSValue {
    return h.expression(engine, contextBody, .{prompt});
}
fn contextBody(s: *Scope, prompt: c.JSValue) !c.JSValue {
    const initial = try v.own(s, try h.expression(s.engine, contextLiteral, .{prompt}));
    return transcript.normalize(s.engine, initial);
}
fn contextLiteral(s: *Scope, prompt: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "systemPrompt", try v.text(s, @embedFile("compaction_system_prompt_b45.txt")));
    const messages = try v.array(s);
    const message = try v.object(s);
    try v.put(s, message, "role", try v.text(s, "user"));
    const content = try v.array(s);
    const block = try v.object(s);
    try v.put(s, block, "type", try v.text(s, "text"));
    try v.put(s, block, "text", prompt);
    try v.index(s, content, 0, block);
    try v.put(s, message, "content", content);
    try v.put(s, message, "timestamp", try v.own(s, try h.expression(s.engine, now, .{})));
    try v.index(s, messages, 0, message);
    try v.put(s, result, "messages", messages);
    return v.duplicate(s, result);
}
fn stringValue(s: *Scope, input: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.stringify(s, input));
}
fn fieldString(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return v.duplicate(s, try v.stringify(s, try v.get(s, receiver, name)));
}
fn template(s: *Scope, prefix: []const u8, input: c.JSValue, suffix: []const u8) !c.JSValue {
    const first = try v.text(s, prefix);
    const rendered = try v.own(s, try h.expression(s.engine, stringValue, .{input}));
    const joined = try h.binary(s, .add, first, rendered);
    return v.duplicate(s, if (suffix.len == 0) joined else try h.binary(s, .add, joined, try v.text(s, suffix)));
}
fn focusedPrompt(s: *Scope, base: c.JSValue, instructions: c.JSValue) !c.JSValue {
    const first = try v.own(s, try h.expression(s.engine, stringValue, .{base}));
    const joined = try h.binary(s, .add, first, try v.text(s, "\n\nAdditional focus: "));
    const last = try v.own(s, try h.expression(s.engine, stringValue, .{instructions}));
    return v.duplicate(s, try h.binary(s, .add, joined, last));
}
fn appendTemplate(s: *Scope, previous: c.JSValue, prefix: []const u8, value: c.JSValue, suffix: []const u8) !c.JSValue {
    const right = try v.own(s, try h.expression(s.engine, template, .{ prefix, value, suffix }));
    return v.duplicate(s, try h.binary(s, .add, previous, right));
}
fn addition(s: *Scope, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return v.duplicate(s, try h.binary(s, .add, left, right));
}
fn convertMessages(s: *Scope, function: c.JSValue, messages: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, function, c.pi_js_undefined(), &.{messages}));
}
fn prefixPrompt(s: *Scope, conversation: c.JSValue) !c.JSValue {
    const first = try v.own(s, try h.expression(s.engine, template, .{ "# Conversation\n", conversation, "\n\n# Instructions\n" }));
    return v.duplicate(s, try h.binary(s, .add, first, try v.text(s, @embedFile("compaction_turnprefix_prompt_b45.txt"))));
}
fn usageRequest(s: *Scope, frame: *UsageFrame, args: []const c.JSValue, request: c.JSValue) !c.JSValue {
    const actual_context = try v.own(s, try context(s.engine, frame.get(.prompt_text)));
    return v.duplicate(s, try v.call(s, request, c.pi_js_undefined(), &.{
        v.arg(args, 1), actual_context, frame.get(.completion_options),
        v.arg(args, 9), v.arg(args, 11), v.arg(args, 12),
    }));
}
fn prefixRequest(s: *Scope, frame: *PrefixFrame, args: []const c.JSValue, request: c.JSValue) !c.JSValue {
    const actual_context = try v.own(s, try context(s.engine, frame.get(.prompt_text)));
    const actual_options = try v.own(s, try options(s.engine,
        v.arg(args, 1), v.arg(args, 2), v.arg(args, 3), v.arg(args, 4),
        v.arg(args, 5), v.arg(args, 6), v.arg(args, 10)));
    return v.duplicate(s, try v.call(s, request, c.pi_js_undefined(), &.{
        v.arg(args, 1), actual_context, actual_options, v.arg(args, 7), v.arg(args, 8), v.arg(args, 9),
    }));
}
fn failureValue(s: *Scope, response: c.JSValue, label: []const u8) !c.JSValue {
    return serializer.failure(s.engine, response, try v.text(s, label));
}
fn toolBlock(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.JS_NewBool(engine.context, try h.fieldEqual(engine, v.arg(args, 0), "type", "toolCall"));
}
fn someTool(s: *Scope, response: c.JSValue) !c.JSValue {
    const content = try v.get(s, response, "content");
    const method = try v.get(s, content, "some");
    const callback = try v.arrow(s, "", 1, toolBlock, &.{});
    return v.boolean(s, v.truthy(s, try v.call(s, method, content, &.{callback})));
}
fn hasTool(engine: *Engine, response: c.JSValue) !bool {
    return h.truthy(engine, try h.expression(engine, someTool, .{response}));
}
fn responseText(s: *Scope, response: c.JSValue) !c.JSValue {
    return content_text.contentText(s.engine, try v.get(s, response, "content"));
}
fn textUsageRecord(s: *Scope, rendered: c.JSValue, response: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "text", rendered);
    try v.put(s, result, "usage", try v.get(s, response, "usage"));
    return v.duplicate(s, result);
}
fn prefixRecord(s: *Scope, response: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "text", try v.own(s, try h.expression(s.engine, responseText, .{response})));
    try v.put(s, result, "usage", try v.get(s, response, "usage"));
    return v.duplicate(s, result);
}
fn newError(s: *Scope, message: c.JSValue) !c.JSValue {
    const constructor = try v.global(s, "Error");
    return v.duplicate(s, try v.construct(s, constructor, &.{message}));
}
fn newLiteralError(s: *Scope, bytes: []const u8) !c.JSValue {
    const constructor = try v.global(s, "Error");
    return v.duplicate(s, try v.construct(s, constructor, &.{try v.text(s, bytes)}));
}
fn generationReady(engine: *Engine, frame: anytype, input: c.JSValue, comptime prefix: bool) !af.Action {
    try frame.copy(.response, input);
    try frame.take(.failure, h.expression(engine, failureValue, .{
        frame.get(.response), @as([]const u8, if (prefix) "Turn prefix summarization" else "Summarization"),
    }));
    if (h.truthy(engine, frame.get(.failure)))
        return .{ .thrown = try h.expression(engine, newError, .{frame.get(.failure)}) };
    if (try hasTool(engine, frame.get(.response)))
        return .{ .thrown = try h.expression(engine, newLiteralError, .{
            @as([]const u8, if (prefix) "Turn prefix summarization attempted to call a tool" else "Summarization attempted to call a tool"),
        }) };
    if (prefix) {
        return .{ .returned = try h.expression(engine, prefixRecord, .{frame.get(.response)}) };
    } else {
        try frame.take(.text_content, h.expression(engine, responseText, .{frame.get(.response)}));
        return .{ .returned = try h.expression(engine, textUsageRecord, .{ frame.get(.text_content), frame.get(.response) }) };
    }
}
fn usageBody(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return rejected(engine, input);
    var s: Scope = .{ .engine = engine };
    return v.owned.finishAction(&s, usageAdvance(&s, args, roots, state, completion, input));
}
fn usageAdvance(s: *Scope, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const frame = if (completion == .start) try initialize(s, state, UsageFrame) else UsageFrame.from(state.*);
    if (completion != .start) return generationReady(s.engine, frame, input, false);
    try frame.take(.base_prompt, if (h.truthy(s.engine, v.arg(args, 7)))
        h.duplicate(s.engine, roots[2]) else h.text(s.engine, @embedFile("compaction_initial_prompt_b45.txt")));
    if (h.truthy(s.engine, v.arg(args, 6)))
        try frame.take(.base_prompt, h.expression(s.engine, focusedPrompt, .{ frame.get(.base_prompt), v.arg(args, 6) }));
    try frame.take(.llm_messages, h.expression(s.engine, convertMessages, .{ roots[1], v.arg(args, 0) }));
    try frame.take(.conversation_text, serializer.serialize(s.engine, frame.get(.llm_messages)));
    try frame.take(.prompt_text, h.expression(s.engine, template, .{
        "<conversation>\n", frame.get(.conversation_text), "\n</conversation>\n\n",
    }));
    if (h.truthy(s.engine, v.arg(args, 7)))
        try frame.take(.prompt_text, h.expression(s.engine, appendTemplate, .{
            frame.get(.prompt_text), "<previous-summary>\n", v.arg(args, 7), "\n</previous-summary>\n\n",
        }));
    try frame.take(.prompt_text, h.expression(s.engine, addition, .{ frame.get(.prompt_text), frame.get(.base_prompt) }));
    try frame.take(.completion_options, options(s.engine,
        v.arg(args, 1), v.arg(args, 3), v.arg(args, 4), v.arg(args, 10),
        v.arg(args, 5), v.arg(args, 8), v.arg(args, 13)));
    return .{ .awaited = try h.expression(s.engine, usageRequest, .{ frame, args, roots[0] }) };
}
fn prefixBody(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return rejected(engine, input);
    var s: Scope = .{ .engine = engine };
    return v.owned.finishAction(&s, prefixAdvance(&s, args, roots, state, completion, input));
}
fn prefixAdvance(s: *Scope, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const frame = if (completion == .start) try initialize(s, state, PrefixFrame) else PrefixFrame.from(state.*);
    if (completion != .start) return generationReady(s.engine, frame, input, true);
    try frame.take(.llm_messages, h.expression(s.engine, convertMessages, .{ roots[1], v.arg(args, 0) }));
    try frame.take(.conversation_text, serializer.serialize(s.engine, frame.get(.llm_messages)));
    try frame.take(.prompt_text, h.expression(s.engine, prefixPrompt, .{frame.get(.conversation_text)}));
    return .{ .awaited = try h.expression(s.engine, prefixRequest, .{ frame, args, roots[0] }) };
}
fn readPreparation(s: *Scope, frame: *CompactFrame, preparation: c.JSValue) !void {
    const boxed = try v.guest.toObject(s, preparation);
    inline for (.{
        .{ "firstKeptEntryId", .first_kept }, .{ "messagesToSummarize", .messages },
        .{ "turnPrefixMessages", .turn_prefix }, .{ "isSplitTurn", .split },
        .{ "tokensBefore", .tokens_before }, .{ "previousSummary", .previous_summary }, .{ "fileOps", .file_ops },
    }) |entry| try frame.copy(entry[1], try v.get(s, boxed, entry[0]));
}
fn nonempty(s: *Scope, messages: c.JSValue) !c.JSValue {
    return v.boolean(s, v.truthy(s, try h.binary(s, .greater, try v.get(s, messages, "length"), v.number(s, 0))));
}
fn hasMessages(engine: *Engine, messages: c.JSValue) !bool {
    return h.truthy(engine, try h.expression(engine, nonempty, .{messages}));
}
fn previousHistory(s: *Scope, previous: c.JSValue) !c.JSValue {
    return v.duplicate(s, if (v.nullish(previous)) try v.text(s, "No prior history.") else previous);
}
fn historyRequest(s: *Scope, frame: *CompactFrame, args: []const c.JSValue, function: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, function, c.pi_js_undefined(), &.{
        frame.get(.messages), v.arg(args, 1), c.pi_js_undefined(), v.arg(args, 2),
        v.arg(args, 3), v.arg(args, 5), v.arg(args, 4), frame.get(.previous_summary),
        v.arg(args, 6), v.arg(args, 7), v.arg(args, 8), v.arg(args, 9), v.arg(args, 10), v.arg(args, 11),
    }));
}
fn turnRequest(s: *Scope, frame: *CompactFrame, args: []const c.JSValue, function: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, function, c.pi_js_undefined(), &.{
        frame.get(.turn_prefix), v.arg(args, 1), v.arg(args, 2), v.arg(args, 3),
        v.arg(args, 8), v.arg(args, 5), v.arg(args, 6), v.arg(args, 7),
        v.arg(args, 9), v.arg(args, 10), v.arg(args, 11),
    }));
}
fn requestHistory(engine: *Engine, frame: *CompactFrame, args: []const c.JSValue, function: c.JSValue, stage: CompactStage) !af.Action {
    try frame.take(.stage, c.JS_NewInt32(engine.context, @intFromEnum(stage)));
    return .{ .awaited = try h.expression(engine, historyRequest, .{ frame, args, function }) };
}
fn requestTurn(engine: *Engine, frame: *CompactFrame, args: []const c.JSValue, function: c.JSValue) !af.Action {
    try frame.take(.stage, c.JS_NewInt32(engine.context, @intFromEnum(CompactStage.prefix)));
    return .{ .awaited = try h.expression(engine, turnRequest, .{ frame, args, function }) };
}
fn mergeTurnText(s: *Scope, history: c.JSValue, result: c.JSValue) !c.JSValue {
    const first = try v.own(s, try h.expression(s.engine, stringValue, .{history}));
    const joined = try h.binary(s, .add, first, try v.text(s, "\n\n---\n\n**Turn Context (split turn):**\n\n"));
    const last = try v.own(s, try h.expression(s.engine, fieldString, .{ result, @as([*:0]const u8, "text") }));
    return v.duplicate(s, try h.binary(s, .add, joined, last));
}
fn mergeTurnUsage(s: *Scope, history: c.JSValue, result: c.JSValue) !c.JSValue {
    const current = try v.get(s, result, "usage");
    return usage.combine(s.engine, history, current);
}
fn readFileLists(s: *Scope, frame: *CompactFrame) !void {
    const lists = try v.own(s, try files.lists(s.engine, frame.get(.file_ops)));
    const boxed = try v.guest.toObject(s, lists);
    try frame.copy(.read_files, try v.get(s, boxed, "readFiles"));
    try frame.copy(.modified_files, try v.get(s, boxed, "modifiedFiles"));
}
fn appendFiles(s: *Scope, previous: c.JSValue, read_files: c.JSValue, modified_files: c.JSValue) !c.JSValue {
    const formatted = try v.own(s, try files.format(s.engine, read_files, modified_files));
    return v.duplicate(s, try h.binary(s, .add, previous, formatted));
}
fn compactRecord(s: *Scope, frame: *CompactFrame) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "summary", frame.get(.summary));
    try v.put(s, result, "firstKeptEntryId", frame.get(.first_kept));
    try v.put(s, result, "tokensBefore", frame.get(.tokens_before));
    try v.put(s, result, "usage", frame.get(.summary_usage));
    const details = try v.object(s);
    try v.put(s, details, "readFiles", frame.get(.read_files));
    try v.put(s, details, "modifiedFiles", frame.get(.modified_files));
    try v.put(s, result, "details", details);
    return v.duplicate(s, result);
}
fn compactFinish(engine: *Engine, frame: *CompactFrame) !af.Action {
    try h.statement(engine, readFileLists, .{frame});
    try frame.take(.summary, h.expression(engine, appendFiles, .{ frame.get(.summary), frame.get(.read_files), frame.get(.modified_files) }));
    if (!h.truthy(engine, frame.get(.first_kept)))
        return .{ .thrown = try h.expression(engine, newLiteralError, .{@as([]const u8, "First kept entry has no UUID - session may need migration")}) };
    return .{ .returned = try h.expression(engine, compactRecord, .{frame}) };
}
fn compactBody(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) return rejected(engine, input);
    var s: Scope = .{ .engine = engine };
    return v.owned.finishAction(&s, compactAdvance(&s, args, roots, state, completion, input));
}
fn compactAdvance(s: *Scope, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const engine = s.engine;
    const frame = if (completion == .start) try initialize(s, state, CompactFrame) else CompactFrame.from(state.*);
    if (completion == .start) {
        try h.statement(engine, readPreparation, .{ frame, v.arg(args, 0) });
        if (h.truthy(engine, frame.get(.split)) and try hasMessages(engine, frame.get(.turn_prefix))) {
            try frame.take(.history_text, h.expression(engine, previousHistory, .{frame.get(.previous_summary)}));
            try frame.take(.history_usage, c.pi_js_undefined());
            if (try hasMessages(engine, frame.get(.messages))) return requestHistory(engine, frame, args, roots[0], .history);
            return requestTurn(engine, frame, args, roots[1]);
        }
        return requestHistory(engine, frame, args, roots[0], .whole);
    }
    switch (@as(CompactStage, @enumFromInt(c.JS_VALUE_GET_INT(frame.get(.stage))))) {
        .history => {
            try frame.copy(.history_result, input);
            try frame.take(.history_text, h.get(engine, frame.get(.history_result), "text"));
            try frame.take(.history_usage, h.get(engine, frame.get(.history_result), "usage"));
            return requestTurn(engine, frame, args, roots[1]);
        },
        .prefix => {
            try frame.copy(.turn_result, input);
            try frame.take(.summary, h.expression(engine, mergeTurnText, .{ frame.get(.history_text), frame.get(.turn_result) }));
            try frame.take(.summary_usage, if (h.truthy(engine, frame.get(.history_usage)))
                h.expression(engine, mergeTurnUsage, .{ frame.get(.history_usage), frame.get(.turn_result) })
            else
                h.get(engine, frame.get(.turn_result), "usage"));
        },
        .whole => {
            try frame.copy(.result, input);
            try frame.take(.summary, h.get(engine, frame.get(.result), "text"));
            try frame.take(.summary_usage, h.get(engine, frame.get(.result), "usage"));
        },
    }
    return compactFinish(engine, frame);
}
