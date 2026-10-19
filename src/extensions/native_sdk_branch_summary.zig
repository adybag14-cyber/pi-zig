//! Genuine c268 branch-summary async body over the shared actual completion,
//! entry preparation, conversion, transcript, text and file-operation owners.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const af = v.af;
const Engine = h.Engine;
const Scope = h.Scope;
const frames = @import("native_public_lexical_frame.zig");
const entries_owner = @import("native_sdk_public_branch_entries.zig");
const converter = @import("native_sdk_messages.zig");
const transcript = @import("native_ai_transcript_context.zig");
const serializer = @import("native_sdk_compaction_text.zig");
const content_text = @import("native_ai_content_text.zig");
const files = @import("native_sdk_compaction_file_ops.zig");
const cache_key = "pi-private:sdk-branch-summary-c268";
const BranchFrame = frames.Frame(enum {
    model, api_key, headers, env, signal, custom, replace, reserve, stream, retry, callbacks,
    context_window, token_budget, messages, file_ops, llm_messages, conversation, instructions,
    prompt, summary_messages, context, request_options, response, failure, summary, read_files, modified_files,
});
pub fn exports(engine: *Engine, complete_request: c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached| return h.duplicate(engine, cached);
    const candidate = try h.expression(engine, exportsBody, .{complete_request});
    if (engine.native_module_values.get(cache_key)) |cached| {
        var selected = v.owned.Completion.initValue(engine, h.duplicate(engine, cached));
        selected.release(candidate);
        return selected.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var failed = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        failed.release(candidate);
        return failed.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(cache_key, candidate);
    return h.duplicate(engine, candidate);
}
fn exportsBody(s: *Scope, complete_request: c.JSValue) !c.JSValue {
    const actual_entries = try v.own(s, try entries_owner.create(s.engine));
    const convert = try v.own(s, try converter.create(s.engine));
    const result = try v.object(s);
    inline for (.{ "collectEntriesForBranchSummary", "prepareBranchEntries" }) |name|
        try v.put(s, result, name, try v.get(s, actual_entries, name));
    var boundary: v.guest.Boundary = .{ .engine = s.engine };
    try boundary.begin();
    const generate = try boundary.finishValue(s, af.createResumable(s.engine, "generateBranchSummary", 2, generateBody, &.{ complete_request, convert }));
    try v.put(s, result, "generateBranchSummary", generate);
    return v.duplicate(s, result);
}
pub fn collect(engine: *Engine, session: c.JSValue, old_leaf: c.JSValue, target: c.JSValue) !c.JSValue {
    return entries_owner.collect(engine, session, old_leaf, target);
}
pub fn prepare(engine: *Engine, entries: c.JSValue, supplied_budget: c.JSValue) !c.JSValue {
    return entries_owner.prepare(engine, entries, supplied_budget);
}
fn initialize(s: *Scope, state: *c.JSValue) !*BranchFrame {
    const frame = try BranchFrame.create(s);
    af.replaceState(s.engine, state, v.duplicate(s, frame.owner));
    return frame;
}
fn readOptions(s: *Scope, frame: *BranchFrame, options: c.JSValue) !void {
    const boxed = try v.guest.toObject(s, options);
    inline for (.{
        .{ "model", .model }, .{ "apiKey", .api_key }, .{ "headers", .headers }, .{ "env", .env },
        .{ "signal", .signal }, .{ "customInstructions", .custom }, .{ "replaceInstructions", .replace },
        .{ "reserveTokens", .reserve }, .{ "streamFn", .stream }, .{ "retry", .retry }, .{ "callbacks", .callbacks },
    }) |entry| {
        const value = try v.get(s, boxed, entry[0]);
        try frame.copy(entry[1], if (entry[1] == .reserve and c.JS_IsUndefined(value)) v.number(s, 16384) else value);
    }
}
fn contextWindow(s: *Scope, model: c.JSValue) !c.JSValue {
    const value = try v.get(s, model, "contextWindow");
    return v.duplicate(s, if (v.truthy(s, value)) value else v.number(s, 128000));
}
fn tokenBudget(s: *Scope, window: c.JSValue, reserve: c.JSValue) !c.JSValue {
    return v.duplicate(s, try h.binary(s, .subtract, window, reserve));
}
fn readPrepared(s: *Scope, frame: *BranchFrame, entries: c.JSValue) !void {
    const prepared = try v.own(s, try prepare(s.engine, entries, frame.get(.token_budget)));
    const boxed = try v.guest.toObject(s, prepared);
    try frame.copy(.messages, try v.get(s, boxed, "messages"));
    try frame.copy(.file_ops, try v.get(s, boxed, "fileOps"));
}
fn empty(s: *Scope, messages: c.JSValue) !c.JSValue {
    return v.boolean(s, v.equal(s, try v.get(s, messages, "length"), v.number(s, 0)));
}
fn singleRecord(s: *Scope, name: [*:0]const u8, value: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, name, value);
    return v.duplicate(s, result);
}
fn literalRecord(s: *Scope, name: [*:0]const u8, bytes: []const u8) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, name, try v.text(s, bytes));
    return v.duplicate(s, result);
}
fn convertMessages(s: *Scope, convert: c.JSValue, messages: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, convert, c.pi_js_undefined(), &.{messages}));
}
fn stringValue(s: *Scope, input: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.stringify(s, input));
}
fn focusedInstructions(s: *Scope, custom: c.JSValue) !c.JSValue {
    const prefix = try h.binary(s, .add, try v.text(s, @embedFile("branch_summary_prompt_5ab.txt")), try v.text(s, "\n\nAdditional focus: "));
    const rendered = try v.own(s, try h.expression(s.engine, stringValue, .{custom}));
    return v.duplicate(s, try h.binary(s, .add, prefix, rendered));
}
fn promptText(s: *Scope, conversation: c.JSValue, instructions: c.JSValue) !c.JSValue {
    const first = try v.own(s, try h.expression(s.engine, stringValue, .{conversation}));
    const prefix = try h.binary(s, .add, try v.text(s, "<conversation>\n"), first);
    const middle = try h.binary(s, .add, prefix, try v.text(s, "\n</conversation>\n\n"));
    const last = try v.own(s, try h.expression(s.engine, stringValue, .{instructions}));
    return v.duplicate(s, try h.binary(s, .add, middle, last));
}
fn now(s: *Scope) !c.JSValue {
    const date = try v.global(s, "Date");
    const method = try v.get(s, date, "now");
    return v.duplicate(s, try v.call(s, method, date, &.{}));
}
fn summaryMessages(s: *Scope, prompt: c.JSValue) !c.JSValue {
    const result = try v.array(s);
    const message = try v.object(s);
    try v.put(s, message, "role", try v.text(s, "user"));
    const content = try v.array(s);
    const block = try v.object(s);
    try v.put(s, block, "type", try v.text(s, "text"));
    try v.put(s, block, "text", prompt);
    try v.index(s, content, 0, block);
    try v.put(s, message, "content", content);
    try v.put(s, message, "timestamp", try v.own(s, try h.expression(s.engine, now, .{})));
    try v.index(s, result, 0, message);
    return v.duplicate(s, result);
}
fn contextLiteral(s: *Scope, messages: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "systemPrompt", try v.text(s, @embedFile("compaction_system_prompt_b45.txt")));
    try v.put(s, result, "messages", messages);
    return v.duplicate(s, result);
}
fn contextValue(s: *Scope, messages: c.JSValue) !c.JSValue {
    const input = try v.own(s, try h.expression(s.engine, contextLiteral, .{messages}));
    return transcript.normalize(s.engine, input);
}
fn requestOptions(s: *Scope, frame: *BranchFrame) !c.JSValue {
    const result = try v.object(s);
    inline for (.{ .{ "apiKey", .api_key }, .{ "headers", .headers }, .{ "env", .env }, .{ "signal", .signal } }) |entry|
        try v.put(s, result, entry[0], frame.get(entry[1]));
    return v.duplicate(s, result);
}
fn completeRequest(s: *Scope, frame: *BranchFrame, complete: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, complete, c.pi_js_undefined(), &.{
        frame.get(.model), frame.get(.context), frame.get(.request_options), frame.get(.stream), frame.get(.retry), frame.get(.callbacks),
    }));
}
fn failureValue(s: *Scope, response: c.JSValue) !c.JSValue {
    return serializer.failure(s.engine, response, try v.text(s, "Branch summarization"));
}
fn toolBlock(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.JS_NewBool(engine.context, try h.fieldEqual(engine, v.arg(args, 0), "type", "toolCall"));
}
fn someTool(s: *Scope, response: c.JSValue) !c.JSValue {
    const content = try v.get(s, response, "content");
    const method = try v.get(s, content, "some");
    const predicate = try v.arrow(s, "", 1, toolBlock, &.{});
    return v.boolean(s, v.truthy(s, try v.call(s, method, content, &.{predicate})));
}
fn responseText(s: *Scope, response: c.JSValue) !c.JSValue {
    return content_text.contentText(s.engine, try v.get(s, response, "content"), c.pi_js_undefined());
}
fn prepend(s: *Scope, value: c.JSValue) !c.JSValue {
    const preamble = try v.text(s, @embedFile("branch_summary_preamble_5ab.txt") ++ "\n\n");
    return v.duplicate(s, try h.binary(s, .add, preamble, value));
}
fn readLists(s: *Scope, frame: *BranchFrame) !void {
    const lists = try v.own(s, try files.lists(s.engine, frame.get(.file_ops)));
    const boxed = try v.guest.toObject(s, lists);
    try frame.copy(.read_files, try v.get(s, boxed, "readFiles"));
    try frame.copy(.modified_files, try v.get(s, boxed, "modifiedFiles"));
}
fn appendFiles(s: *Scope, previous: c.JSValue, read_files: c.JSValue, modified_files: c.JSValue) !c.JSValue {
    const formatted = try v.own(s, try files.format(s.engine, read_files, modified_files));
    return v.duplicate(s, try h.binary(s, .add, previous, formatted));
}
fn resultRecord(s: *Scope, frame: *BranchFrame) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "summary", if (v.truthy(s, frame.get(.summary))) frame.get(.summary) else try v.text(s, "No summary generated"));
    try v.put(s, result, "usage", try v.get(s, frame.get(.response), "usage"));
    try v.put(s, result, "readFiles", frame.get(.read_files));
    try v.put(s, result, "modifiedFiles", frame.get(.modified_files));
    return v.duplicate(s, result);
}
fn resumed(engine: *Engine, frame: *BranchFrame, input: c.JSValue) !af.Action {
    try frame.copy(.response, input);
    if (try h.fieldEqual(engine, frame.get(.response), "stopReason", "aborted"))
        return .{ .returned = try h.expression(engine, singleRecord, .{ @as([*:0]const u8, "aborted"), c.JS_NewBool(engine.context, true) }) };
    try frame.take(.failure, h.expression(engine, failureValue, .{frame.get(.response)}));
    if (h.truthy(engine, frame.get(.failure)))
        return .{ .returned = try h.expression(engine, singleRecord, .{ @as([*:0]const u8, "error"), frame.get(.failure) }) };
    if (h.truthy(engine, try h.expression(engine, someTool, .{frame.get(.response)})))
        return .{ .returned = try h.expression(engine, literalRecord, .{ @as([*:0]const u8, "error"), @as([]const u8, "Branch summarization attempted to call a tool") }) };
    try frame.take(.summary, h.expression(engine, responseText, .{frame.get(.response)}));
    try frame.take(.summary, h.expression(engine, prepend, .{frame.get(.summary)}));
    try h.statement(engine, readLists, .{frame});
    try frame.take(.summary, h.expression(engine, appendFiles, .{ frame.get(.summary), frame.get(.read_files), frame.get(.modified_files) }));
    return .{ .returned = try h.expression(engine, resultRecord, .{frame}) };
}
fn generateBody(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) {
        try @import("native_async_body.zig").enterRejectedContinuation(engine);
        return .{ .thrown = h.duplicate(engine, input) };
    }
    var s: Scope = .{ .engine = engine };
    return v.owned.finishAction(&s, advance(&s, args, roots, state, completion, input));
}
fn advance(s: *Scope, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const frame = if (completion == .start) try initialize(s, state) else BranchFrame.from(state.*);
    if (completion != .start) return resumed(s.engine, frame, input);
    try h.statement(s.engine, readOptions, .{ frame, v.arg(args, 1) });
    try frame.take(.context_window, h.expression(s.engine, contextWindow, .{frame.get(.model)}));
    try frame.take(.token_budget, h.expression(s.engine, tokenBudget, .{ frame.get(.context_window), frame.get(.reserve) }));
    try h.statement(s.engine, readPrepared, .{ frame, v.arg(args, 0) });
    if (h.truthy(s.engine, try h.expression(s.engine, empty, .{frame.get(.messages)})))
        return .{ .returned = try h.expression(s.engine, literalRecord, .{ @as([*:0]const u8, "summary"), @as([]const u8, "No content to summarize") }) };
    try frame.take(.llm_messages, h.expression(s.engine, convertMessages, .{ roots[1], frame.get(.messages) }));
    try frame.take(.conversation, serializer.serialize(s.engine, frame.get(.llm_messages)));
    try frame.take(.instructions, if (h.truthy(s.engine, frame.get(.replace)) and h.truthy(s.engine, frame.get(.custom)))
        h.duplicate(s.engine, frame.get(.custom))
    else if (h.truthy(s.engine, frame.get(.custom)))
        h.expression(s.engine, focusedInstructions, .{frame.get(.custom)})
    else h.text(s.engine, @embedFile("branch_summary_prompt_5ab.txt")));
    try frame.take(.prompt, h.expression(s.engine, promptText, .{ frame.get(.conversation), frame.get(.instructions) }));
    try frame.take(.summary_messages, h.expression(s.engine, summaryMessages, .{frame.get(.prompt)}));
    try frame.take(.context, h.expression(s.engine, contextValue, .{frame.get(.summary_messages)}));
    try frame.take(.request_options, h.expression(s.engine, requestOptions, .{frame}));
    return .{ .awaited = try h.expression(s.engine, completeRequest, .{ frame, roots[0] }) };
}
