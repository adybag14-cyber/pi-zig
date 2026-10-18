//! Actual c268 session-manager projection over live guest values.
//! SessionManager and the public exports use these same native bodies.
const std = @import("std");
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const copy = @import("native_sdk_catalog_copy.zig");
const x = @import("native_sdk_catalog_values.zig");
const c = h.c;
const Engine = h.Engine;
const Scope = h.Scope;
const Public = enum { buildContextEntries, buildSessionProjection, buildSessionContext, sessionEntryToContextMessages };
const Operation = enum { path, context, projection, messages, context_result };
const Callback = enum { same_compaction, edit, project, flatten };
pub fn exports(engine: *Engine) !c.JSValue { return h.expression(engine, exportsBody, .{}); }
fn exportsBody(s: *Scope) !c.JSValue {
    const result = try v.object(s);
    inline for (std.meta.fields(Public)) |field| {
        const Adapter = struct {
            fn call(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
                return dispatch(engine, switch (@as(Public, @enumFromInt(field.value))) {
                    .buildContextEntries => .context, .buildSessionProjection => .projection,
                    .buildSessionContext => .context_result, .sessionEntryToContextMessages => .messages,
                }, v.arg(args, 0), v.arg(args, 1), v.arg(args, 2));
            }
        };
        try v.put(s, result, field.name, try v.ordinary(s, field.name, if (field.value == 3) 1 else 3, Adapter.call, &.{}));
    }
    return v.duplicate(s, result);
}
pub fn path(engine: *Engine, entries: c.JSValue, leaf_id: c.JSValue, by_id: c.JSValue) !c.JSValue {
    return dispatch(engine, .path, entries, leaf_id, by_id);
}
pub fn contextEntries(engine: *Engine, entries: c.JSValue, leaf_id: c.JSValue, by_id: c.JSValue) !c.JSValue {
    return dispatch(engine, .context, entries, leaf_id, by_id);
}
pub fn projection(engine: *Engine, entries: c.JSValue, leaf_id: c.JSValue, by_id: c.JSValue) !c.JSValue {
    return dispatch(engine, .projection, entries, leaf_id, by_id);
}
pub fn entryMessages(engine: *Engine, entry: c.JSValue) !c.JSValue {
    return dispatch(engine, .messages, entry, c.pi_js_undefined(), c.pi_js_undefined());
}
fn dispatch(engine: *Engine, operation: Operation, first: c.JSValue, second: c.JSValue, third: c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    var invocation: Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    const outcome = (switch (operation) {
        .path => sessionPath(engine, first, second, third),
        .context => contextValue(engine, first, second, third),
        .projection => projectionValue(engine, first, second, third),
        .messages => messagesValue(engine, first),
        .context_result => contextResult(engine, first, second, third),
    }) catch |err| @import("native_sdk.zig").fail(engine, err);
    return engine.checked(engine.leaveNativeInvocation(&invocation, outcome));
}
fn arrow(s: *Scope, comptime kind: Callback, roots: []const c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *Engine, _: c.JSValue, args: []const c.JSValue, saved: []const c.JSValue) !c.JSValue {
            return h.expression(engine, callbackBody, .{ kind, args, saved });
        }
    };
    return v.arrow(s, "", if (kind == .project) 2 else 1, Adapter.call, roots);
}
const IndexFrame = h.Frame(enum { index, entry });
fn buildIndex(engine: *Engine, entries: c.JSValue, supplied: c.JSValue) !c.JSValue {
    if (h.truthy(engine, supplied)) return h.duplicate(engine, supplied);
    var f = IndexFrame.init(engine);
    return f.finish(indexBody(&f, entries));
}
fn indexBody(f: *IndexFrame, entries: c.JSValue) !c.JSValue {
    try f.set(.index, h.construct(f.engine, "Map", &.{}));
    var iterator = try v.Iterator.init(f.engine, entries);
    try iterator.finish(indexRows(f, &iterator));
    return h.duplicate(f.engine, f.get(.index));
}
fn indexRows(f: *IndexFrame, iterator: *v.Iterator) !void {
    while (try iterator.next()) |incoming| {
        try f.set(.entry, incoming);
        try h.statement(f.engine, indexRow, .{ f.get(.index), f.get(.entry) });
    }
}
fn indexRow(s: *Scope, index: c.JSValue, entry: c.JSValue) !void {
    const callable = try v.get(s, index, "set");
    _ = try v.call(s, callable, index, &.{ try v.get(s, entry, "id"), entry });
}
const PathFrame = h.Frame(enum { index, leaf, selected, current });
fn sessionPath(engine: *Engine, entries: c.JSValue, leaf_id: c.JSValue, by_id: c.JSValue) !c.JSValue {
    var f = PathFrame.init(engine);
    return f.finish(pathBody(&f, entries, leaf_id, by_id));
}
fn pathBody(f: *PathFrame, entries: c.JSValue, leaf_id: c.JSValue, by_id: c.JSValue) !c.JSValue {
    const engine = f.engine;
    try f.set(.index, buildIndex(engine, entries, by_id));
    if (c.JS_IsNull(leaf_id)) return h.array(engine);
    if (h.truthy(engine, leaf_id)) try f.set(.leaf, v.invokeOwned(engine, f.get(.index), "get", &.{leaf_id}));
    if (v.nullish(f.get(.leaf))) try f.set(.leaf, h.expression(engine, lastEntry, .{entries}));
    if (!h.truthy(engine, f.get(.leaf))) return h.array(engine);
    try f.set(.selected, h.array(engine));
    try f.set(.current, h.duplicate(engine, f.get(.leaf)));
    var steps: usize = 0;
    while (h.truthy(engine, f.get(.current))) {
        try v.poll(engine, &steps);
        try h.discard(engine, f.get(.selected), "push", &.{f.get(.current)});
        const next = if (try h.fieldTest(engine, f.get(.current), "parentId", .truthy))
            h.expression(engine, nextParent, .{ f.get(.index), f.get(.current) })
        else @as(anyerror!c.JSValue, c.pi_js_undefined());
        try f.set(.current, next);
    }
    try h.discard(engine, f.get(.selected), "reverse", &.{});
    return h.duplicate(engine, f.get(.selected));
}
fn lastEntry(s: *Scope, entries: c.JSValue) !c.JSValue {
    const position = try v.own(s, try h.expression(s.engine, lastPosition, .{entries}));
    return v.duplicate(s, try v.key(s, entries, position));
}
fn lastPosition(s: *Scope, entries: c.JSValue) !c.JSValue {
    return v.duplicate(s, try h.binary(s, .subtract, try v.get(s, entries, "length"), v.number(s, 1)));
}
fn nextParent(s: *Scope, index: c.JSValue, current: c.JSValue) !c.JSValue {
    const callable = try v.get(s, index, "get");
    return v.duplicate(s, try v.call(s, callable, index, &.{try v.get(s, current, "parentId")}));
}
const ContextFrame = h.Frame(enum { selected, compaction, scanned_entry, cut, result, cursor, kept_entry });
fn contextValue(engine: *Engine, entries: c.JSValue, leaf_id: c.JSValue, by_id: c.JSValue) !c.JSValue {
    var f = ContextFrame.init(engine);
    return f.finish(contextBody(&f, entries, leaf_id, by_id));
}
fn contextBody(f: *ContextFrame, entries: c.JSValue, leaf_id: c.JSValue, by_id: c.JSValue) !c.JSValue {
    const engine = f.engine;
    try f.set(.selected, sessionPath(engine, entries, leaf_id, by_id));
    try f.set(.compaction, c.pi_js_null());
    var iterator = try v.Iterator.init(engine, f.get(.selected));
    try iterator.finish(compactionRows(f, &iterator));
    if (!h.truthy(engine, f.get(.compaction))) return h.duplicate(engine, f.get(.selected));
    try f.set(.cut, h.expression(engine, findCompaction, .{ f.get(.selected), f.get(.compaction) }));
    if (try h.compare(engine, .less, f.get(.cut), h.number(engine, 0))) return h.duplicate(engine, f.get(.selected));
    try f.set(.result, h.expression(engine, singleton, .{f.get(.compaction)}));
    try f.set(.cursor, h.number(engine, 0));
    var found = false; var steps: usize = 0;
    while (try h.compare(engine, .less, f.get(.cursor), f.get(.cut))) {
        try v.poll(engine, &steps);
        // BCDF enters the body after the condition and before path[i].
        // A false condition retains the final entry through the following push.
        try f.clear(.kept_entry);
        try f.set(.kept_entry, h.key(engine, f.get(.selected), f.get(.cursor)));
        if (h.truthy(engine, try h.expression(engine, keptEntry, .{ f.get(.kept_entry), f.get(.compaction) }))) found = true;
        if (found and !(try h.fieldEqual(engine, f.get(.kept_entry), "type", "message") and
            try h.nestedEqual(engine, f.get(.kept_entry), "message", "role", "system")))
            try h.discard(engine, f.get(.result), "push", &.{f.get(.kept_entry)});
        try f.set(.cursor, h.increment(engine, f.get(.cursor)));
    }
    try spreadTail(engine, f.get(.result), f.get(.selected), f.get(.cut));
    return h.duplicate(engine, f.get(.result));
}
fn compactionRows(f: *ContextFrame, iterator: *v.Iterator) !void {
    while (try iterator.next()) |incoming| {
        try f.set(.scanned_entry, incoming);
        if (try h.fieldEqual(f.engine, f.get(.scanned_entry), "type", "compaction"))
            try f.set(.compaction, h.duplicate(f.engine, f.get(.scanned_entry)));
    }
}
fn findCompaction(s: *Scope, selected: c.JSValue, compaction: c.JSValue) !c.JSValue {
    const callable = try v.get(s, selected, "findIndex");
    const predicate = try arrow(s, .same_compaction, &.{compaction});
    return v.duplicate(s, try v.call(s, callable, selected, &.{predicate}));
}
fn keptEntry(s: *Scope, entry: c.JSValue, compaction: c.JSValue) !c.JSValue {
    return v.boolean(s, v.equal(s, try v.get(s, entry, "id"), try v.get(s, compaction, "firstKeptEntryId")));
}
fn singleton(s: *Scope, value: c.JSValue) !c.JSValue {
    const result = try v.array(s); try v.index(s, result, 0, value);
    return v.duplicate(s, result);
}
fn spreadTail(engine: *Engine, result: c.JSValue, selected: c.JSValue, cut: c.JSValue) !void {
    var s: Scope = .{ .engine = engine }; var arguments: std.ArrayList(c.JSValue) = .empty;
    var completion = v.owned.Completion.initVoid(engine, spreadTailBody(&s, result, selected, cut, &arguments));
    completion.releaseScope(&s);
    for (arguments.items) |value| completion.release(value);
    arguments.deinit(engine.gpa);
    return completion.finishVoid();
}
fn spreadTailBody(s: *Scope, result: c.JSValue, selected: c.JSValue, cut: c.JSValue, arguments: *std.ArrayList(c.JSValue)) !void {
    const push = try v.get(s, result, "push");
    const tail = try h.expression(s.engine, slicedTail, .{ selected, cut });
    var iterator = try v.Iterator.initOwned(s.engine, tail);
    try iterator.finish(collectArguments(s.engine, &iterator, arguments));
    _ = try v.call(s, push, result, arguments.items);
}
fn slicedTail(s: *Scope, selected: c.JSValue, cut: c.JSValue) !c.JSValue {
    const slice = try v.get(s, selected, "slice");
    return v.duplicate(s, try v.call(s, slice, selected, &.{try h.binary(s, .add, cut, v.number(s, 1))}));
}
fn collectArguments(engine: *Engine, iterator: *v.Iterator, arguments: *std.ArrayList(c.JSValue)) !void {
    while (try iterator.next()) |incoming| {
        arguments.append(engine.gpa, incoming) catch |err| {
            var completion = v.owned.Completion.initVoid(engine, err); completion.release(incoming);
            try completion.finishVoid(); unreachable;
        };
    }
}
const SettingsFrame = h.Frame(enum { thinking_level, model, entry });
fn settings(engine: *Engine, selected: c.JSValue) !c.JSValue {
    var f = SettingsFrame.init(engine);
    return f.finish(settingsBody(&f, selected));
}
fn settingsBody(f: *SettingsFrame, selected: c.JSValue) !c.JSValue {
    try f.set(.thinking_level, h.text(f.engine, "off"));
    try f.set(.model, c.pi_js_null());
    var iterator = try v.Iterator.init(f.engine, selected);
    try iterator.finish(settingsRows(f, &iterator));
    return h.expression(f.engine, settingsResult, .{ f.get(.thinking_level), f.get(.model) });
}
fn settingsRows(f: *SettingsFrame, iterator: *v.Iterator) !void {
    const engine = f.engine;
    while (try iterator.next()) |incoming| {
        try f.set(.entry, incoming);
        const entry = f.get(.entry);
        if (try h.fieldEqual(engine, entry, "type", "thinking_level_change"))
            try f.set(.thinking_level, h.get(engine, entry, "thinkingLevel"))
        else if (try h.fieldEqual(engine, entry, "type", "model_change"))
            try f.set(.model, h.expression(engine, modelRecord, .{ entry, false }))
        else if (try h.fieldEqual(engine, entry, "type", "message") and try h.nestedEqual(engine, entry, "message", "role", "assistant"))
            try f.set(.model, h.expression(engine, modelRecord, .{ entry, true }));
    }
}
fn modelRecord(s: *Scope, entry: c.JSValue, nested_message: bool) !c.JSValue {
    const result = try v.object(s);
    const provider = try v.own(s, if (nested_message) try h.nested(s.engine, entry, "message", "provider") else try h.get(s.engine, entry, "provider"));
    try v.put(s, result, "provider", provider);
    const model_id = try v.own(s, if (nested_message) try h.nested(s.engine, entry, "message", "model") else try h.get(s.engine, entry, "modelId"));
    try v.put(s, result, "modelId", model_id);
    return v.duplicate(s, result);
}
fn settingsResult(s: *Scope, thinking_level: c.JSValue, model: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "thinkingLevel", thinking_level); try v.put(s, result, "model", model);
    return v.duplicate(s, result);
}
const MessagesFrame = h.Frame(enum { message, summary });
fn messagesValue(engine: *Engine, entry: c.JSValue) !c.JSValue {
    var f = MessagesFrame.init(engine);
    return f.finish(messagesBody(&f, entry));
}
fn messagesBody(f: *MessagesFrame, entry: c.JSValue) !c.JSValue {
    const engine = f.engine;
    if (try h.fieldEqual(engine, entry, "type", "message")) {
        try f.set(.message, h.get(engine, entry, "message"));
        const message = f.get(.message);
        if (try h.fieldEqual(engine, message, "role", "system") and try h.fieldTest(engine, message, "content", .nullish))
            return h.expression(engine, repairedMessage, .{ message, false });
        if ((try h.fieldEqual(engine, message, "role", "user") or try h.fieldEqual(engine, message, "role", "assistant") or
            try h.fieldEqual(engine, message, "role", "toolResult")) and try h.fieldTest(engine, message, "content", .nullish))
            return h.expression(engine, repairedMessage, .{ message, true });
        return h.expression(engine, singleton, .{message});
    }
    if (try h.fieldEqual(engine, entry, "type", "custom_message")) return h.expression(engine, customArray, .{entry});
    if (try h.fieldEqual(engine, entry, "type", "branch_summary") and try h.fieldTest(engine, entry, "summary", .truthy))
        return h.expression(engine, branchArray, .{entry});
    if (try h.fieldEqual(engine, entry, "type", "compaction")) {
        try f.set(.summary, h.expression(engine, compactionMessage, .{entry}));
        return if (try h.fieldTest(engine, entry, "systemMessage", .truthy))
            h.expression(engine, systemAndSummary, .{ entry, f.get(.summary) })
        else h.expression(engine, singleton, .{f.get(.summary)});
    }
    return h.array(engine);
}
fn repairedMessage(s: *Scope, message: c.JSValue, empty_array: bool) !c.JSValue {
    const result = try v.array(s); var ops: x.Ops = .{ .s = s };
    const repaired = try copy.object(&ops, message);
    try v.put(s, repaired, "content", if (empty_array) try v.array(s) else try v.text(s, ""));
    try v.index(s, result, 0, repaired); return v.duplicate(s, result);
}
fn dateTime(engine: *Engine, timestamp: c.JSValue) !c.JSValue {
    return h.expression(engine, dateTimeBody, .{timestamp});
}
fn dateTimeBody(s: *Scope, timestamp: c.JSValue) !c.JSValue {
    const date = try v.own(s, try h.construct(s.engine, "Date", &.{timestamp}));
    const method = try v.get(s, date, "getTime");
    return v.duplicate(s, try v.call(s, method, date, &.{}));
}
fn customArray(s: *Scope, entry: c.JSValue) !c.JSValue {
    const result = try v.array(s);
    const message = try v.own(s, try h.expression(s.engine, customFromEntry, .{entry}));
    try v.index(s, result, 0, message); return v.duplicate(s, result);
}
fn customFromEntry(s: *Scope, entry: c.JSValue) !c.JSValue {
    const custom_type = try v.get(s, entry, "customType");
    var content = try v.get(s, entry, "content");
    if (v.nullish(content)) content = try v.array(s);
    const display = try v.get(s, entry, "display");
    const details = try v.get(s, entry, "details");
    const timestamp = try v.get(s, entry, "timestamp");
    return h.expression(s.engine, customMessage, .{ custom_type, content, display, details, timestamp });
}
pub fn customMessage(s: *Scope, custom_type: c.JSValue, content: c.JSValue, display: c.JSValue, details: c.JSValue, timestamp: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "role", try v.text(s, "custom")); try v.put(s, result, "customType", custom_type);
    try v.put(s, result, "content", content); try v.put(s, result, "display", display); try v.put(s, result, "details", details);
    try v.put(s, result, "timestamp", try v.own(s, try dateTime(s.engine, timestamp)));
    return v.duplicate(s, result);
}
fn branchArray(s: *Scope, entry: c.JSValue) !c.JSValue {
    const result = try v.array(s);
    const message = try v.own(s, try h.expression(s.engine, branchFromEntry, .{entry}));
    try v.index(s, result, 0, message); return v.duplicate(s, result);
}
fn branchFromEntry(s: *Scope, entry: c.JSValue) !c.JSValue {
    const summary = try v.get(s, entry, "summary"); const from_id = try v.get(s, entry, "fromId");
    const timestamp = try v.get(s, entry, "timestamp");
    return h.expression(s.engine, branchMessage, .{ summary, from_id, timestamp });
}
pub fn branchMessage(s: *Scope, summary: c.JSValue, from_id: c.JSValue, timestamp: c.JSValue) !c.JSValue {
    const result = try v.object(s); try v.put(s, result, "role", try v.text(s, "branchSummary"));
    try v.put(s, result, "summary", summary); try v.put(s, result, "fromId", from_id);
    try v.put(s, result, "timestamp", try v.own(s, try dateTime(s.engine, timestamp)));
    return v.duplicate(s, result);
}
fn compactionMessage(s: *Scope, entry: c.JSValue) !c.JSValue {
    const summary = try v.get(s, entry, "summary"); const tokens_before = try v.get(s, entry, "tokensBefore");
    const timestamp = try v.get(s, entry, "timestamp");
    return h.expression(s.engine, compactionRecord, .{ summary, tokens_before, timestamp });
}
pub fn compactionRecord(s: *Scope, summary: c.JSValue, tokens_before: c.JSValue, timestamp: c.JSValue) !c.JSValue {
    const result = try v.object(s); try v.put(s, result, "role", try v.text(s, "compactionSummary"));
    try v.put(s, result, "summary", summary); try v.put(s, result, "tokensBefore", tokens_before);
    try v.put(s, result, "timestamp", try v.own(s, try dateTime(s.engine, timestamp)));
    return v.duplicate(s, result);
}
fn systemAndSummary(s: *Scope, entry: c.JSValue, summary: c.JSValue) !c.JSValue {
    const result = try v.array(s); try v.index(s, result, 0, try v.get(s, entry, "systemMessage"));
    try v.index(s, result, 1, summary); return v.duplicate(s, result);
}
const EditFrame = h.Frame(enum { messages, replacement });
fn projectEntry(engine: *Engine, entry: c.JSValue, edit: c.JSValue) !c.JSValue {
    var f = EditFrame.init(engine);
    return f.finish(projectEntryBody(&f, entry, edit));
}
fn projectEntryBody(f: *EditFrame, entry: c.JSValue, edit: c.JSValue) !c.JSValue {
    try f.set(.messages, messagesValue(f.engine, entry));
    if (!h.truthy(f.engine, edit)) return h.duplicate(f.engine, f.get(.messages));
    try f.set(.replacement, h.get(f.engine, edit, "replacement"));
    if (c.JS_IsNull(f.get(.replacement))) return h.array(f.engine);
    return h.expression(f.engine, editMap, .{ f.get(.messages), f.get(.replacement) });
}
fn editMap(s: *Scope, messages: c.JSValue, replacement: c.JSValue) !c.JSValue {
    const map = try v.get(s, messages, "map"); const callback = try arrow(s, .edit, &.{replacement});
    return v.duplicate(s, try v.call(s, map, messages, &.{callback}));
}
fn editedMessage(s: *Scope, message: c.JSValue, replacement: c.JSValue) !c.JSValue {
    const engine = s.engine;
    if (!try h.fieldEqual(engine, message, "role", "user") and !try h.fieldEqual(engine, message, "role", "assistant") and
        !try h.fieldEqual(engine, message, "role", "toolResult") and !try h.fieldEqual(engine, message, "role", "custom"))
        return v.duplicate(s, message);
    const as_text = (try h.fieldEqual(engine, message, "role", "assistant") or try h.fieldEqual(engine, message, "role", "toolResult")) and
        try h.fieldTest(engine, replacement, "content", .string);
    const content = try v.own(s, if (as_text) try h.expression(engine, textContent, .{replacement}) else try h.get(engine, replacement, "content"));
    var ops: x.Ops = .{ .s = s }; const result = try copy.object(&ops, message);
    try v.put(s, result, "content", content); return v.duplicate(s, result);
}
fn textContent(s: *Scope, replacement: c.JSValue) !c.JSValue {
    const result = try v.array(s); const block = try v.object(s);
    try v.put(s, block, "type", try v.text(s, "text")); try v.put(s, block, "text", try v.get(s, replacement, "content"));
    try v.index(s, result, 0, block); return v.duplicate(s, result);
}
const ProjectionFrame = h.Frame(enum { selected, thinking_level, model, context, edits, entry, projected });
fn projectionValue(engine: *Engine, entries: c.JSValue, leaf_id: c.JSValue, by_id: c.JSValue) !c.JSValue {
    var f = ProjectionFrame.init(engine);
    return f.finish(projectionBody(&f, entries, leaf_id, by_id));
}
fn projectionBody(f: *ProjectionFrame, entries: c.JSValue, leaf_id: c.JSValue, by_id: c.JSValue) !c.JSValue {
    const engine = f.engine;
    try f.set(.selected, sessionPath(engine, entries, leaf_id, by_id));
    try h.statement(engine, captureSettings, .{f});
    try f.set(.context, contextValue(engine, entries, leaf_id, by_id));
    try f.set(.edits, h.construct(engine, "Map", &.{}));
    var iterator = try v.Iterator.init(engine, f.get(.context));
    try iterator.finish(editRows(f, &iterator));
    try f.set(.projected, h.expression(engine, projectionMap, .{ f.get(.context), f.get(.edits) }));
    return h.expression(engine, projectionResult, .{ f.get(.projected), f.get(.thinking_level), f.get(.model) });
}
fn captureSettings(s: *Scope, f: *ProjectionFrame) !void {
    const result = try v.own(s, try settings(s.engine, f.get(.selected)));
    try f.set(.thinking_level, h.get(s.engine, result, "thinkingLevel"));
    try f.set(.model, h.get(s.engine, result, "model"));
}
fn editRows(f: *ProjectionFrame, iterator: *v.Iterator) !void {
    while (try iterator.next()) |incoming| {
        try f.set(.entry, incoming);
        if (try h.fieldEqual(f.engine, f.get(.entry), "type", "context_edit"))
            try h.statement(f.engine, editRow, .{ f.get(.edits), f.get(.entry) });
    }
}
fn editRow(s: *Scope, edits: c.JSValue, entry: c.JSValue) !void {
    const callable = try v.get(s, edits, "set");
    _ = try v.call(s, callable, edits, &.{ try v.get(s, entry, "targetId"), entry });
}
fn projectionMap(s: *Scope, context: c.JSValue, edits: c.JSValue) !c.JSValue {
    const map = try v.get(s, context, "map"); const callback = try arrow(s, .project, &.{edits});
    return v.duplicate(s, try v.call(s, map, context, &.{callback}));
}
fn projectionResult(s: *Scope, projected: c.JSValue, thinking_level: c.JSValue, model: c.JSValue) !c.JSValue {
    const result = try v.object(s); try v.put(s, result, "entries", projected);
    const messages = try v.own(s, try h.expression(s.engine, flattened, .{projected}));
    try v.put(s, result, "messages", messages); try v.put(s, result, "thinkingLevel", thinking_level); try v.put(s, result, "model", model);
    return v.duplicate(s, result);
}
fn flattened(s: *Scope, projected: c.JSValue) !c.JSValue {
    const callable = try v.get(s, projected, "flatMap"); const callback = try arrow(s, .flatten, &.{});
    return v.duplicate(s, try v.call(s, callable, projected, &.{callback}));
}
const ResultFrame = h.Frame(enum { messages, thinking_level, model });
fn contextResult(engine: *Engine, entries: c.JSValue, leaf_id: c.JSValue, by_id: c.JSValue) !c.JSValue {
    var f = ResultFrame.init(engine);
    return f.finish(contextResultBody(&f, entries, leaf_id, by_id));
}
fn contextResultBody(f: *ResultFrame, entries: c.JSValue, leaf_id: c.JSValue, by_id: c.JSValue) !c.JSValue {
    try h.statement(f.engine, captureProjection, .{ f, entries, leaf_id, by_id });
    return h.expression(f.engine, contextRecord, .{ f.get(.messages), f.get(.thinking_level), f.get(.model) });
}
fn captureProjection(s: *Scope, f: *ResultFrame, entries: c.JSValue, leaf_id: c.JSValue, by_id: c.JSValue) !void {
    const result = try v.own(s, try projectionValue(s.engine, entries, leaf_id, by_id));
    try f.set(.messages, h.get(s.engine, result, "messages"));
    try f.set(.thinking_level, h.get(s.engine, result, "thinkingLevel"));
    try f.set(.model, h.get(s.engine, result, "model"));
}
fn contextRecord(s: *Scope, messages: c.JSValue, thinking_level: c.JSValue, model: c.JSValue) !c.JSValue {
    const result = try v.object(s); try v.put(s, result, "messages", messages);
    try v.put(s, result, "thinkingLevel", thinking_level); try v.put(s, result, "model", model);
    return v.duplicate(s, result);
}
fn callbackBody(s: *Scope, comptime kind: Callback, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const entry = v.arg(args, 0);
    return switch (kind) {
        .same_compaction => v.boolean(s, v.equal(s, try v.get(s, entry, "id"), try v.get(s, roots[0], "id"))),
        .flatten => v.duplicate(s, try v.get(s, entry, "messages")),
        .edit => editedMessage(s, entry, roots[0]),
        .project => projectedEntry(s, entry, v.arg(args, 1), roots[0]),
    };
}
fn projectedEntry(s: *Scope, entry: c.JSValue, position: c.JSValue, edits: c.JSValue) !c.JSValue {
    const result = try v.object(s); try v.put(s, result, "sourceEntry", entry);
    const skip = try h.fieldEqual(s.engine, entry, "type", "compaction") and try h.compare(s.engine, .greater, position, v.number(s, 0));
    const messages = try v.own(s, if (skip) try h.array(s.engine) else try h.expression(s.engine, editedProjection, .{ entry, edits }));
    try v.put(s, result, "messages", messages); return v.duplicate(s, result);
}
fn editedProjection(s: *Scope, entry: c.JSValue, edits: c.JSValue) !c.JSValue {
    const edit = try v.own(s, try h.expression(s.engine, lookupEdit, .{ entry, edits }));
    return projectEntry(s.engine, entry, edit);
}
fn lookupEdit(s: *Scope, entry: c.JSValue, edits: c.JSValue) !c.JSValue {
    const callable = try v.get(s, edits, "get");
    return v.duplicate(s, try v.call(s, callable, edits, &.{try v.get(s, entry, "id")}));
}
