//! Actual c268 compaction utils serializer and summarization failure strings.
//! Source lexical values use Frame; expression temporaries retire through
//! AF33/C435 before the next observable getter, call or coercion.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const Engine = v.em.Engine;
const Scope = v.Scope;
const content_text = @import("native_ai_content_text.zig");
const cache_key = "\x00sdk-compaction-text";
const SerialFrame = h.Frame(enum {
    parts, message, user_content, tool_calls, block, arguments, arguments_text, tool_content,
});
const PairFrame = h.Frame(enum { key, value });
const TruncateFrame = h.Frame(enum { truncated_chars });

pub fn exports(engine: *Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached| return h.duplicate(engine, cached);
    const candidate = try h.expression(engine, exportsBody, .{});
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
fn exportsBody(s: *Scope) !c.JSValue {
    const result = try v.object(s);
    const text = try v.own(s, try content_text.create(s.engine));
    try v.put(s, result, "serializeConversation", try v.ordinary(s, "serializeConversation", 1, serializeCall, &.{text}));
    try v.put(s, result, "getSummarizationFailure", try v.ordinary(s, "getSummarizationFailure", 2, failureCall, &.{}));
    return v.duplicate(s, result);
}
fn serializeCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return serializeWith(engine, v.arg(args, 0), roots[0]);
}
fn failureCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return failure(engine, v.arg(args, 0), v.arg(args, 1));
}
fn stringifyValue(s: *Scope, value: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.stringify(s, value));
}
fn stringifyIncoming(s: *Scope, incoming: anyerror!c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.stringify(s, try v.own(s, try incoming)));
}
fn stringField(s: *Scope, receiver: c.JSValue, field: [*:0]const u8) !c.JSValue {
    return v.duplicate(s, try v.stringify(s, try v.get(s, receiver, field)));
}
fn errorMessage(s: *Scope, response: c.JSValue) !c.JSValue {
    const value = try v.get(s, response, "errorMessage");
    return v.duplicate(s, if (v.truthy(s, value)) value else try v.text(s, "Unknown error"));
}
fn failureBody(s: *Scope, response: c.JSValue, label: c.JSValue, error_stop: bool) !c.JSValue {
    const label_text = try v.own(s, try h.expression(s.engine, stringifyValue, .{label}));
    if (!error_stop) return v.duplicate(s, try h.binary(s, .add, label_text, try v.text(s, " failed: generation hit the token cap and the summary is incomplete")));
    const prefix = try h.binary(s, .add, label_text, try v.text(s, " failed: "));
    const reason = try v.own(s, try h.expression(s.engine, stringifyIncoming, .{
        h.expression(s.engine, errorMessage, .{response}),
    }));
    return v.duplicate(s, try h.binary(s, .add, prefix, reason));
}
pub fn failure(engine: *Engine, response: c.JSValue, label: c.JSValue) !c.JSValue {
    if (try h.fieldEqual(engine, response, "stopReason", "error"))
        return h.expression(engine, failureBody, .{ response, label, true });
    if (try h.fieldEqual(engine, response, "stopReason", "length"))
        return h.expression(engine, failureBody, .{ response, label, false });
    return c.pi_js_undefined();
}
fn lengthRelation(s: *Scope, value: c.JSValue, expected: c.JSValue, operation: h.math.Operation) !c.JSValue {
    return v.duplicate(s, try h.binary(s, operation, try v.get(s, value, "length"), expected));
}
fn remainingChars(s: *Scope, value: c.JSValue, maximum: c.JSValue) !c.JSValue {
    return v.duplicate(s, try h.binary(s, .subtract, try v.get(s, value, "length"), maximum));
}
fn sliceText(s: *Scope, value: c.JSValue, maximum: c.JSValue) !c.JSValue {
    const sliced = try v.invoke(s, value, "slice", &.{v.number(s, 0), maximum});
    return v.duplicate(s, try v.stringify(s, sliced));
}
fn truncateTemplate(s: *Scope, f: *TruncateFrame, value: c.JSValue, maximum: c.JSValue) !c.JSValue {
    const sliced = try v.own(s, try h.expression(s.engine, sliceText, .{ value, maximum }));
    const prefix = try h.binary(s, .add, sliced, try v.text(s, "\n\n[... "));
    const remaining = try v.own(s, try h.expression(s.engine, stringifyValue, .{f.get(.truncated_chars)}));
    const joined = try h.binary(s, .add, prefix, remaining);
    return v.duplicate(s, try h.binary(s, .add, joined, try v.text(s, " more characters truncated]")));
}
fn truncateSource(f: *TruncateFrame, value: c.JSValue, maximum: c.JSValue) !c.JSValue {
    if (h.truthy(f.engine, try h.expression(f.engine, lengthRelation, .{ value, maximum, @as(h.math.Operation, .less_equal) })))
        return h.duplicate(f.engine, value);
    try f.set(.truncated_chars, h.expression(f.engine, remainingChars, .{ value, maximum }));
    return h.expression(f.engine, truncateTemplate, .{ f, value, maximum });
}
fn truncate(engine: *Engine, value: c.JSValue) !c.JSValue {
    var f = TruncateFrame.init(engine);
    return f.finish(truncateSource(&f, value, h.number(engine, 2000)));
}
fn callPairReturn(s: *Scope, receiver: c.JSValue, called: *bool) !c.JSValue {
    const method = try v.get(s, receiver, "return");
    if (v.nullish(method)) return c.pi_js_undefined();
    called.* = true;
    return v.duplicate(s, try v.call(s, method, receiver, &.{}));
}
fn closePair(s: *Scope, receiver: c.JSValue) !void {
    var called = false;
    // BCDF JS_IteratorClose uses JS_CallFree: retire the selected method
    // before checking whether its normal return value is an object.
    const result = try v.own(s, try h.expression(s.engine, callPairReturn, .{ receiver, &called }));
    if (called and !c.JS_IsObject(result)) return v.typeError(s, "not an object");
}
fn pairBindings(f: *PairFrame, iterator: *v.Iterator) !void {
    try f.set(.key, (try iterator.next()) orelse c.pi_js_undefined());
    try f.set(.value, if (iterator.closed) c.pi_js_undefined() else (try iterator.next()) orelse c.pi_js_undefined());
    if (!iterator.closed) {
        iterator.closed = true;
        try h.statement(f.engine, closePair, .{iterator.receiver});
    }
}
fn jsonValue(s: *Scope, value: c.JSValue) !c.JSValue {
    const json = try v.global(s, "JSON");
    const method = try v.get(s, json, "stringify");
    return v.duplicate(s, try v.call(s, method, json, &.{value}));
}
fn pairTemplate(s: *Scope, f: *PairFrame) !c.JSValue {
    const key = try v.own(s, try h.expression(s.engine, stringifyValue, .{f.get(.key)}));
    const prefix = try h.binary(s, .add, key, try v.text(s, "="));
    const value = try v.own(s, try h.expression(s.engine, stringifyIncoming, .{
        h.expression(s.engine, jsonValue, .{f.get(.value)}),
    }));
    return v.duplicate(s, try h.binary(s, .add, prefix, value));
}
fn pairSource(f: *PairFrame, pair: c.JSValue) !c.JSValue {
    var iterator = try v.Iterator.init(f.engine, pair);
    try iterator.finish(pairBindings(f, &iterator));
    return h.expression(f.engine, pairTemplate, .{f});
}
fn argumentEntry(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var f = PairFrame.init(engine);
    return f.finish(pairSource(&f, v.arg(args, 0)));
}
fn textBlock(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.JS_NewBool(engine.context, try h.fieldEqual(engine, v.arg(args, 0), "type", "text"));
}
fn objectEntries(s: *Scope, arguments: c.JSValue) !c.JSValue {
    const object = try v.global(s, "Object");
    const method = try v.get(s, object, "entries");
    return v.duplicate(s, try v.call(s, method, object, &.{arguments}));
}
fn mappedArguments(s: *Scope, incoming: anyerror!c.JSValue) !c.JSValue {
    const entries = try v.own(s, try incoming);
    const map = try v.get(s, entries, "map");
    const callback = try v.arrow(s, "", 1, argumentEntry, &.{});
    return v.duplicate(s, try v.call(s, map, entries, &.{callback}));
}
fn joinIncoming(s: *Scope, incoming: anyerror!c.JSValue, separator: []const u8) !c.JSValue {
    const values = try v.own(s, try incoming);
    const method = try v.get(s, values, "join");
    return v.duplicate(s, try v.call(s, method, values, &.{try v.text(s, separator)}));
}
fn argumentsText(engine: *Engine, arguments: c.JSValue) !c.JSValue {
    return h.expression(engine, joinIncoming, .{
        h.expression(engine, mappedArguments, .{h.expression(engine, objectEntries, .{arguments})}),
        @as([]const u8, ", "),
    });
}
fn toolCallText(s: *Scope, f: *SerialFrame) !c.JSValue {
    const name = try v.own(s, try h.expression(s.engine, stringField, .{ f.get(.block), @as([*:0]const u8, "name") }));
    const prefix = try h.binary(s, .add, name, try v.text(s, "("));
    const arguments = try v.own(s, try h.expression(s.engine, stringifyValue, .{f.get(.arguments_text)}));
    const call_text = try h.binary(s, .add, prefix, arguments);
    return v.duplicate(s, try h.binary(s, .add, call_text, try v.text(s, ")")));
}
fn appendToolCall(s: *Scope, f: *SerialFrame) !void {
    const calls = f.get(.tool_calls);
    const push = try v.get(s, calls, "push");
    const text = try v.own(s, try h.expression(s.engine, toolCallText, .{f}));
    _ = try v.call(s, push, calls, &.{text});
}
fn blocksSource(f: *SerialFrame, iterator: *v.Iterator) !void {
    while (try iterator.next()) |block| {
        try f.set(.block, block);
        if (try h.fieldEqual(f.engine, f.get(.block), "type", "toolCall")) {
            try f.clear(.arguments_text);
            try f.clear(.arguments);
            try f.set(.arguments, h.get(f.engine, f.get(.block), "arguments"));
            try f.set(.arguments_text, argumentsText(f.engine, f.get(.arguments)));
            try h.statement(f.engine, appendToolCall, .{f});
        }
    }
}
fn contentCall(s: *Scope, message: c.JSValue, callable: c.JSValue, empty_separator: bool) !c.JSValue {
    const content = try v.get(s, message, "content");
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(),
        if (empty_separator) &.{ content, try v.text(s, "") } else &.{content}));
}
fn prefixedText(s: *Scope, prefix: []const u8, value: c.JSValue) !c.JSValue {
    const text = try v.own(s, try h.expression(s.engine, stringifyValue, .{value}));
    return v.duplicate(s, try h.binary(s, .add, try v.text(s, prefix), text));
}
fn appendKnownContent(s: *Scope, parts: c.JSValue, prefix: []const u8, content: c.JSValue) !void {
    const push = try v.get(s, parts, "push");
    const text = try v.own(s, try h.expression(s.engine, prefixedText, .{ prefix, content }));
    _ = try v.call(s, push, parts, &.{text});
}
fn someText(s: *Scope, incoming: anyerror!c.JSValue) !c.JSValue {
    const content = try v.own(s, try incoming);
    const some = try v.get(s, content, "some");
    const predicate = try v.arrow(s, "", 1, textBlock, &.{});
    return v.boolean(s, v.truthy(s, try v.call(s, some, content, &.{predicate})));
}
fn assistantText(s: *Scope, f: *SerialFrame, callable: c.JSValue) !c.JSValue {
    const text = try v.own(s, try h.expression(s.engine, stringifyIncoming, .{
        h.expression(s.engine, contentCall, .{ f.get(.message), callable, false }),
    }));
    return v.duplicate(s, try h.binary(s, .add, try v.text(s, "[Assistant]: "), text));
}
fn appendAssistant(s: *Scope, f: *SerialFrame, callable: c.JSValue) !void {
    const parts = f.get(.parts);
    const push = try v.get(s, parts, "push");
    const text = try v.own(s, try h.expression(s.engine, assistantText, .{ f, callable }));
    _ = try v.call(s, push, parts, &.{text});
}
fn joinedText(s: *Scope, values: c.JSValue, separator: []const u8) !c.JSValue {
    return v.duplicate(s, try v.stringify(s, try v.invoke(s, values, "join", &.{try v.text(s, separator)})));
}
fn toolCallsText(s: *Scope, calls: c.JSValue) !c.JSValue {
    const joined = try v.own(s, try h.expression(s.engine, joinedText, .{ calls, @as([]const u8, "; ") }));
    return v.duplicate(s, try h.binary(s, .add, try v.text(s, "[Assistant tool calls]: "), joined));
}
fn appendToolCalls(s: *Scope, f: *SerialFrame) !void {
    const parts = f.get(.parts);
    const push = try v.get(s, parts, "push");
    const text = try v.own(s, try h.expression(s.engine, toolCallsText, .{f.get(.tool_calls)}));
    _ = try v.call(s, push, parts, &.{text});
}
fn toolResultText(s: *Scope, content: c.JSValue) !c.JSValue {
    const text = try v.own(s, try h.expression(s.engine, stringifyIncoming, .{truncate(s.engine, content)}));
    return v.duplicate(s, try h.binary(s, .add, try v.text(s, "[Tool result]: "), text));
}
fn appendToolResult(s: *Scope, f: *SerialFrame) !void {
    const parts = f.get(.parts);
    const push = try v.get(s, parts, "push");
    const text = try v.own(s, try h.expression(s.engine, toolResultText, .{f.get(.tool_content)}));
    _ = try v.call(s, push, parts, &.{text});
}
fn messagesSource(f: *SerialFrame, iterator: *v.Iterator, callable: c.JSValue) !void {
    const engine = f.engine;
    while (try iterator.next()) |message| {
        try f.set(.message, message);
        if (try h.fieldEqual(engine, f.get(.message), "role", "user")) {
            try f.clear(.user_content);
            try f.set(.user_content, h.expression(engine, contentCall, .{ f.get(.message), callable, true }));
            if (h.truthy(engine, f.get(.user_content)))
                try h.statement(engine, appendKnownContent, .{ f.get(.parts), @as([]const u8, "[User]: "), f.get(.user_content) });
        } else if (try h.fieldEqual(engine, f.get(.message), "role", "assistant")) {
            try f.clear(.tool_calls);
            try f.set(.tool_calls, h.array(engine));
            // BCDF enters the nested enumeration scope before evaluating RHS.
            try f.clear(.block);
            var blocks = try v.Iterator.initOwned(engine, try h.get(engine, f.get(.message), "content"));
            try blocks.finish(blocksSource(f, &blocks));
            if (h.truthy(engine, try h.expression(engine, someText, .{h.get(engine, f.get(.message), "content")})))
                try h.statement(engine, appendAssistant, .{ f, callable });
            if (h.truthy(engine, try h.expression(engine, lengthRelation, .{ f.get(.tool_calls), h.number(engine, 0), @as(h.math.Operation, .greater) })))
                try h.statement(engine, appendToolCalls, .{f});
        } else if (try h.fieldEqual(engine, f.get(.message), "role", "toolResult")) {
            try f.clear(.tool_content);
            try f.set(.tool_content, h.expression(engine, contentCall, .{ f.get(.message), callable, true }));
            if (h.truthy(engine, f.get(.tool_content))) try h.statement(engine, appendToolResult, .{f});
        }
    }
}
fn serializeSource(f: *SerialFrame, messages: c.JSValue, callable: c.JSValue) !c.JSValue {
    try f.set(.parts, h.array(f.engine));
    var iterator = try v.Iterator.init(f.engine, messages);
    try iterator.finish(messagesSource(f, &iterator, callable));
    return h.expression(f.engine, partsJoin, .{f.get(.parts)});
}
fn partsJoin(s: *Scope, parts: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.invoke(s, parts, "join", &.{try v.text(s, "\n\n")}));
}
fn serializeWith(engine: *Engine, messages: c.JSValue, callable: c.JSValue) !c.JSValue {
    var f = SerialFrame.init(engine);
    return f.finish(serializeSource(&f, messages, callable));
}
fn serializeEntry(s: *Scope, messages: c.JSValue) !c.JSValue {
    const callable = try v.own(s, try content_text.create(s.engine));
    return serializeWith(s.engine, messages, callable);
}
pub fn serialize(engine: *Engine, messages: c.JSValue) !c.JSValue {
    return h.expression(engine, serializeEntry, .{messages});
}
