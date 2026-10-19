//! Actual c268 tool_search definition and zero-Await AsyncFunction executor.
const t = @import("native_sdk_tool_search_values.zig");
const h = t.h;
const v = t.v;
const c = t.c;
const Engine = t.Engine;
const Scope = t.Scope;
const Arguments = t.Arguments;
const af = v.af;
const load_tools = @import("native_sdk_tool_search_load.zig");
const ExecuteFrame = t.Frame(enum { query, limit, max, tools, text });

pub fn create(s: *Scope, search: c.JSValue, schema: c.JSValue, description_value: c.JSValue) !c.JSValue {
    return v.duplicate(s, try t.function(s, "createToolSearchToolDefinition", 0,
        .{ .formal_count = 1, .callback = definitionCall }, &.{search, schema, description_value}));
}
fn reachesCall(engine: *Engine, _: c.JSValue, _: *Arguments, _: []const c.JSValue) !c.JSValue {
    return h.text(engine, "all");
}
fn definitionBody(s: *Scope, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    if (c.JS_IsUndefined(args.get(0))) try args.take(0, h.expression(s.engine, emptyObject, .{}));
    const result = try v.object(s);
    try v.put(s, result, "name", try v.text(s, "tool_search"));
    try v.put(s, result, "label", try v.text(s, "tool_search"));
    try v.put(s, result, "description", roots[2]);
    try v.put(s, result, "promptSnippet", try v.text(s, "Search for tools that are not loaded yet and load the matches"));
    try v.put(s, result, "parameters", roots[1]);
    try v.put(s, result, "exposure", try v.text(s, "model-only"));
    try v.put(s, result, "reachesTools", try t.arrow(s, "reachesTools", 0,
        .{ .formal_count = 0, .callback = reachesCall }, &.{}));
    const options_cell = try args.capture(s, 0);
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const execute = try boundary.finishValue(s, af.createResumableWithClose(
        s.engine, "execute", 2, executeBody, &.{options_cell, roots[0]}, ExecuteFrame.closeAtAsyncTerminal));
    try v.put(s, result, "execute", execute);
    return v.duplicate(s, result);
}
fn definitionCall(engine: *Engine, _: c.JSValue, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, definitionBody, .{args, roots});
}
fn emptyObject(s: *Scope) !c.JSValue { return v.duplicate(s, try v.object(s)); }
fn bindInput(s: *Scope, frame: *ExecuteFrame, input: c.JSValue) !void {
    // One parameter BindingPattern conversion precedes its ordered getters.
    const receiver = try v.guest.toObject(s, input);
    try frame.copy(.query, try v.get(s, receiver, "query"));
    try frame.copy(.limit, try v.get(s, receiver, "limit"));
}
fn emptyQuery(s: *Scope, query: c.JSValue) !c.JSValue {
    const result = try t.invoke(s, query, "trim", &.{});
    return v.boolean(s, try v.eq(s, result, ""));
}
fn integer(s: *Scope, value: c.JSValue) !c.JSValue {
    const receiver = try v.global(s, "Number");
    const callee = try v.get(s, receiver, "isInteger");
    return v.boolean(s, v.truthy(s, try v.call(s, callee, receiver, &.{value})));
}
fn newError(s: *Scope, message: []const u8) !c.JSValue {
    const constructor = try v.global(s, "Error");
    return v.duplicate(s, try v.construct(s, constructor, &.{try v.text(s, message)}));
}
fn raise(s: *Scope, reason: c.JSValue) !c.JSValue {
    // This is Source OP_throw, distinct from forwarding a caught/Await reason.
    // JS_Throw consumes the owned operand and normalizes an explicitly thrown
    // uncatchable-tagged Error before C435 captures the pending completion.
    return s.engine.checked(c.JS_Throw(s.engine.context, reason));
}
fn optionsPresent(s: *Scope, cell: c.JSValue) !c.JSValue {
    const options = try t.sync.read(s, cell);
    return v.boolean(s, v.truthy(s, try v.get(s, options, "tools")));
}
fn searched(s: *Scope, cell: c.JSValue, search: c.JSValue, query: c.JSValue, maximum: c.JSValue) !c.JSValue {
    const options = try t.sync.read(s, cell);
    const tools = try v.get(s, options, "tools");
    return v.duplicate(s, try v.call(s, search, c.pi_js_undefined(), &.{tools, query, maximum}));
}
fn toolsValue(s: *Scope, cell: c.JSValue, search: c.JSValue, query: c.JSValue, maximum: c.JSValue) !c.JSValue {
    if (h.truthy(s.engine, try h.expression(s.engine, optionsPresent, .{cell})))
        return h.expression(s.engine, searched, .{cell, search, query, maximum});
    return v.duplicate(s, try v.array(s));
}
fn fieldString(s: *Scope, value: c.JSValue, field: [*:0]const u8) !c.JSValue {
    return v.duplicate(s, try v.stringify(s, try v.get(s, value, field)));
}
fn descriptionTrim(s: *Scope, tool: c.JSValue) !c.JSValue {
    const receiver = try v.get(s, tool, "description");
    const callee = try v.get(s, receiver, "trim");
    return v.duplicate(s, try v.call(s, callee, receiver, &.{}));
}
fn descriptionSplit(s: *Scope, tool: c.JSValue) !c.JSValue {
    const receiver = try v.own(s, try h.expression(s.engine, descriptionTrim, .{tool}));
    const callee = try v.get(s, receiver, "split");
    const separator = try t.literalRegex(s, "\\r?\\n", "");
    return v.duplicate(s, try v.call(s, callee, receiver, &.{separator}));
}
fn firstDescriptionLine(s: *Scope, tool: c.JSValue) !c.JSValue {
    const receiver = try v.own(s, try h.expression(s.engine, descriptionSplit, .{tool}));
    return v.duplicate(s, try v.key(s, receiver, v.number(s, 0)));
}
fn firstLineString(s: *Scope, tool: c.JSValue) !c.JSValue {
    const value = try v.own(s, try h.expression(s.engine, firstDescriptionLine, .{tool}));
    return v.duplicate(s, try v.stringify(s, value));
}
fn lineBody(s: *Scope, tool: c.JSValue) !c.JSValue {
    const prefix = try v.text(s, "- ");
    const name = try v.own(s, try h.expression(s.engine, fieldString, .{tool, @as([*:0]const u8, "name")}));
    const named = try h.binary(s, .add, prefix, name);
    const before_description = try h.binary(s, .add, named, try v.text(s, ": "));
    const line = try v.own(s, try h.expression(s.engine, firstLineString, .{tool}));
    return v.duplicate(s, try h.binary(s, .add, before_description, line));
}
fn lineCall(engine: *Engine, _: c.JSValue, args: *Arguments, _: []const c.JSValue) !c.JSValue {
    return h.expression(engine, lineBody, .{args.get(0)});
}
fn lines(s: *Scope, tools: c.JSValue) !c.JSValue {
    const callee = try v.get(s, tools, "map");
    const callback = try t.arrow(s, "", 1, .{ .formal_count = 1, .callback = lineCall }, &.{});
    return v.duplicate(s, try v.call(s, callee, tools, &.{callback}));
}
fn joinedLines(s: *Scope, tools: c.JSValue) !c.JSValue {
    const receiver = try v.own(s, try h.expression(s.engine, lines, .{tools}));
    const callee = try v.get(s, receiver, "join");
    return v.duplicate(s, try v.call(s, callee, receiver, &.{try v.text(s, "\n")}));
}
fn joinedString(s: *Scope, tools: c.JSValue) !c.JSValue {
    const value = try v.own(s, try h.expression(s.engine, joinedLines, .{tools}));
    return v.duplicate(s, try v.stringify(s, value));
}
fn loadedText(s: *Scope, tools: c.JSValue) !c.JSValue {
    const prefix = try v.text(s, "Loaded ");
    const count = try v.own(s, try h.expression(s.engine, fieldString, .{tools, @as([*:0]const u8, "length")}));
    const counted = try h.binary(s, .add, prefix, count);
    const tool_prefix = try h.binary(s, .add, counted, try v.text(s, " tool"));
    const singular = h.truthy(s.engine, try h.expression(s.engine, t.fieldStrict,
        .{tools, @as([*:0]const u8, "length"), v.number(s, 1)}));
    const pluralized = try h.binary(s, .add, tool_prefix, try v.text(s, if (singular) "" else "s"));
    const before_lines = try h.binary(s, .add, pluralized, try v.text(s, ". They are available from your next call:\n"));
    const rendered = try v.own(s, try h.expression(s.engine, joinedString, .{tools}));
    return v.duplicate(s, try h.binary(s, .add, before_lines, rendered));
}
fn responseText(s: *Scope, tools: c.JSValue) !c.JSValue {
    if (h.truthy(s.engine, try h.expression(s.engine, t.fieldStrict,
        .{tools, @as([*:0]const u8, "length"), v.number(s, 0)})))
        return v.duplicate(s, try v.text(s, "No matching tools found."));
    return h.expression(s.engine, loadedText, .{tools});
}
fn responseBody(s: *Scope, frame: *ExecuteFrame) !c.JSValue {
    const result = try v.object(s);
    const content = try v.array(s);
    const block = try v.object(s);
    try v.put(s, block, "type", try v.text(s, "text"));
    try v.put(s, block, "text", frame.get(.text));
    try v.index(s, content, 0, block);
    try v.put(s, result, "content", content);
    const details = try v.object(s);
    try v.put(s, details, "loaded", try v.own(s, try h.expression(s.engine, load_tools.names, .{frame.get(.tools)})));
    try v.put(s, result, "details", details);
    return v.duplicate(s, result);
}
fn executeAdvance(s: *Scope, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue) !af.Action {
    const frame = try ExecuteFrame.createAsync(s);
    af.replaceState(s.engine, state, v.duplicate(s, frame.owner));
    try h.statement(s.engine, bindInput, .{frame, v.arg(args, 1)});
    if (h.truthy(s.engine, try h.expression(s.engine, emptyQuery, .{frame.get(.query)})))
        return .{ .thrown = try raise(s, try h.expression(s.engine, newError, .{@as([]const u8, "query must not be empty")})) };
    try frame.copy(.max, if (v.nullish(frame.get(.limit))) v.number(s, 8) else frame.get(.limit));
    if (!h.truthy(s.engine, try h.expression(s.engine, integer, .{frame.get(.max)})) or
        try h.compare(s.engine, .less_equal, frame.get(.max), v.number(s, 0)))
        return .{ .thrown = try raise(s, try h.expression(s.engine, newError, .{@as([]const u8, "limit must be a positive integer")})) };
    try frame.take(.tools, h.expression(s.engine, toolsValue, .{roots[0], roots[1], frame.get(.query), frame.get(.max)}));
    try frame.take(.text, h.expression(s.engine, responseText, .{frame.get(.tools)}));
    return .{ .returned = try h.expression(s.engine, responseBody, .{frame}) };
}
fn executeBody(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, _: c.JSValue) !af.Action {
    if (completion != .start) return error.ToolSearchExecutorHasNoAwait;
    var s: Scope = .{ .engine = engine };
    return v.owned.finishAction(&s, executeAdvance(&s, args, roots, state));
}
