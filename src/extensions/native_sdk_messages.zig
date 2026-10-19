//! Actual c268 message conversion. The real public map/filter calls and arrow
//! callbacks preserve live fields, generic addition, and Source expression slots.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const Engine = h.Engine;
const Scope = h.Scope;
const cache_key = "\x00sdk-convert-to-llm";
const BashFrame = h.Frame(enum { value });
const MapFrame = h.Frame(enum { content, exhaustive });
const Kind = enum(i32) { other, bash, custom, branch, compaction, system, user, assistant, tool };
const branch_prefix = "The following is a summary of a branch that this conversation came back from:\n\n<summary>\n";
const compaction_prefix = "The conversation history before this point was compacted into the following summary:\n\n<summary>\n";

pub fn create(engine: *Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(cache_key)) |cached| return h.duplicate(engine, cached);
    const candidate = try h.expression(engine, createBody, .{});
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
fn createBody(s: *Scope) !c.JSValue {
    return v.duplicate(s, try v.ordinary(s, "convertToLlm", 1, convertCall, &.{}));
}
fn convertCall(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return convert(engine, v.arg(args, 0));
}
pub fn convert(engine: *Engine, messages: c.JSValue) !c.JSValue {
    return h.expression(engine, convertBody, .{messages});
}
fn mappedMessages(s: *Scope, messages: c.JSValue) !c.JSValue {
    const method = try v.get(s, messages, "map");
    const callback = try v.arrow(s, "", 1, mapMessage, &.{});
    return v.duplicate(s, try v.call(s, method, messages, &.{callback}));
}
fn convertBody(s: *Scope, messages: c.JSValue) !c.JSValue {
    const mapped = try v.own(s, try h.expression(s.engine, mappedMessages, .{messages}));
    const method = try v.get(s, mapped, "filter");
    const callback = try v.arrow(s, "", 1, keepMessage, &.{});
    // The temporary map result is owned before the selected filter function.
    return v.duplicate(s, try v.call(s, method, mapped, &.{callback}));
}
fn keepMessage(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.JS_NewBool(engine.context, !c.JS_IsUndefined(v.arg(args, 0)));
}
fn messageKind(s: *Scope, message: c.JSValue) !c.JSValue {
    const role = try v.get(s, message, "role");
    inline for (.{
        .{ "bashExecution", Kind.bash }, .{ "custom", Kind.custom },
        .{ "branchSummary", Kind.branch }, .{ "compactionSummary", Kind.compaction },
        .{ "system", Kind.system }, .{ "user", Kind.user },
        .{ "assistant", Kind.assistant }, .{ "toolResult", Kind.tool },
    }) |entry| {
        if (try v.eq(s, role, entry[0])) return c.JS_NewInt32(s.engine.context, @intFromEnum(entry[1]));
    }
    return c.JS_NewInt32(s.engine.context, @intFromEnum(Kind.other));
}
fn mapMessage(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var locals = MapFrame.init(engine);
    return locals.finish(mapBody(engine, &locals, v.arg(args, 0)));
}
fn mapBody(engine: *Engine, locals: *MapFrame, message: c.JSValue) !c.JSValue {
    const encoded = try h.expression(engine, messageKind, .{message});
    const kind: Kind = @enumFromInt(c.JS_VALUE_GET_INT(encoded));
    switch (kind) {
        .bash => {
            if (try h.fieldTest(engine, message, "excludeFromContext", .truthy)) return c.pi_js_undefined();
            return h.expression(engine, userRecord, .{ message, kind, c.pi_js_undefined() });
        },
        .custom => {
            try locals.set(.content, if (try h.fieldTest(engine, message, "content", .string))
                h.expression(engine, customTextContent, .{message})
            else
                h.get(engine, message, "content"));
            return h.expression(engine, userRecord, .{ message, kind, locals.get(.content) });
        },
        .branch, .compaction => return h.expression(engine, userRecord, .{ message, kind, c.pi_js_undefined() }),
        .system, .user, .assistant, .tool => return h.duplicate(engine, message),
        .other => {
            try locals.set(.exhaustive, h.duplicate(engine, message));
            return c.pi_js_undefined();
        },
    }
}
fn customTextContent(s: *Scope, message: c.JSValue) !c.JSValue {
    const result = try v.array(s);
    const block = try v.object(s);
    try v.put(s, block, "type", try v.text(s, "text"));
    try v.put(s, block, "text", try v.get(s, message, "content"));
    try v.index(s, result, 0, block);
    return v.duplicate(s, result);
}
fn prefixSummary(s: *Scope, message: c.JSValue, comptime kind: Kind) !c.JSValue {
    const prefix = try v.text(s, if (kind == .branch) branch_prefix else compaction_prefix);
    return v.duplicate(s, try h.binary(s, .add, prefix, try v.get(s, message, "summary")));
}
fn summaryText(s: *Scope, message: c.JSValue, comptime kind: Kind) !c.JSValue {
    const initial = try v.own(s, try h.expression(s.engine, prefixSummary, .{ message, kind }));
    return v.duplicate(s, try h.binary(s, .add, initial, try v.text(s, if (kind == .branch) "</summary>" else "\n</summary>")));
}
fn transformedContent(s: *Scope, message: c.JSValue, kind: Kind) !c.JSValue {
    const result = try v.array(s);
    const block = try v.object(s);
    try v.put(s, block, "type", try v.text(s, "text"));
    const rendered = try v.own(s, switch (kind) {
        .bash => try bashExecutionToText(s.engine, message),
        .branch => try h.expression(s.engine, summaryText, .{ message, Kind.branch }),
        .compaction => try h.expression(s.engine, summaryText, .{ message, Kind.compaction }),
        else => unreachable,
    });
    try v.put(s, block, "text", rendered);
    try v.index(s, result, 0, block);
    return v.duplicate(s, result);
}
fn userRecord(s: *Scope, message: c.JSValue, kind: Kind, custom: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "role", try v.text(s, "user"));
    const content = if (kind == .custom) custom else
        try v.own(s, try h.expression(s.engine, transformedContent, .{ message, kind }));
    try v.put(s, result, "content", content);
    try v.put(s, result, "timestamp", try v.get(s, message, "timestamp"));
    return v.duplicate(s, result);
}

fn stringField(s: *Scope, message: c.JSValue, field: [*:0]const u8) !c.JSValue {
    return v.duplicate(s, try v.stringify(s, try v.get(s, message, field)));
}
fn fieldTemplate(s: *Scope, prefix: []const u8, message: c.JSValue, field: [*:0]const u8, suffix: []const u8) !c.JSValue {
    const first = try v.text(s, prefix);
    const rendered = try v.own(s, try h.expression(s.engine, stringField, .{ message, field }));
    const joined = try h.binary(s, .add, first, rendered);
    return v.duplicate(s, if (suffix.len == 0) joined else try h.binary(s, .add, joined, try v.text(s, suffix)));
}
fn appendLiteral(s: *Scope, previous: c.JSValue, bytes: []const u8) !c.JSValue {
    return v.duplicate(s, try h.binary(s, .add, previous, try v.text(s, bytes)));
}
fn appendField(s: *Scope, previous: c.JSValue, prefix: []const u8, message: c.JSValue, field: [*:0]const u8, suffix: []const u8) !c.JSValue {
    const right = try v.own(s, try h.expression(s.engine, fieldTemplate, .{ prefix, message, field, suffix }));
    return v.duplicate(s, try h.binary(s, .add, previous, right));
}
fn fieldSame(s: *Scope, message: c.JSValue, field: [*:0]const u8, expected: c.JSValue) !c.JSValue {
    return v.boolean(s, v.equal(s, try v.get(s, message, field), expected));
}
fn sameField(engine: *Engine, message: c.JSValue, field: [*:0]const u8, expected: c.JSValue) !bool {
    return h.truthy(engine, try h.expression(engine, fieldSame, .{ message, field, expected }));
}
pub fn bashExecutionToText(engine: *Engine, message: c.JSValue) !c.JSValue {
    var locals = BashFrame.init(engine);
    return locals.finish(bashBody(engine, &locals, message));
}
fn bashBody(engine: *Engine, locals: *BashFrame, message: c.JSValue) !c.JSValue {
    try locals.set(.value, h.expression(engine, fieldTemplate, .{ "Ran `", message, "command", "`\n" }));
    if (try h.fieldTest(engine, message, "output", .truthy)) {
        try locals.set(.value, h.expression(engine, appendField, .{ locals.get(.value), "```\n", message, "output", "\n```" }));
    } else {
        try locals.set(.value, h.expression(engine, appendLiteral, .{ locals.get(.value), "(no output)" }));
    }
    if (try h.fieldTest(engine, message, "cancelled", .truthy)) {
        try locals.set(.value, h.expression(engine, appendLiteral, .{ locals.get(.value), "\n\n(command cancelled)" }));
    } else if (!try sameField(engine, message, "exitCode", c.pi_js_null()) and
        !try sameField(engine, message, "exitCode", c.pi_js_undefined()) and
        !try sameField(engine, message, "exitCode", h.number(engine, 0)))
    {
        try locals.set(.value, h.expression(engine, appendField, .{ locals.get(.value), "\n\nCommand exited with code ", message, "exitCode", "" }));
    }
    if (try h.fieldTest(engine, message, "truncated", .truthy) and try h.fieldTest(engine, message, "fullOutputPath", .truthy)) {
        try locals.set(.value, h.expression(engine, appendField, .{ locals.get(.value), "\n\n[Output truncated. Full output: ", message, "fullOutputPath", "]" }));
    }
    return h.duplicate(engine, locals.get(.value));
}
