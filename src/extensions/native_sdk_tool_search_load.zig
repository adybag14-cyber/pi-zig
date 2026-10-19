//! Actual c268 searchAndLoad declaration, retaining its lexical callback cells.
const t = @import("native_sdk_tool_search_values.zig");
const h = t.h;
const v = t.v;
const c = t.c;
const Engine = t.Engine;
const Scope = t.Scope;
const Arguments = t.Arguments;
const SearchFrame = t.Frame(enum { active, candidates, documents, matches });

pub fn create(s: *Scope, document_function: c.JSValue, ranker_constructor: c.JSValue) !c.JSValue {
    const searchable = try t.function(s, "isSearchable", 1,
        .{ .formal_count = 1, .callback = searchableCall }, &.{});
    return v.duplicate(s, try t.function(s, "searchAndLoad", 3,
        .{ .formal_count = 3, .callback = searchCall, .hooks = t.sync.frameHooks(SearchFrame) },
        &.{searchable, document_function, ranker_constructor}));
}
fn searchableBody(s: *Scope, exposure: c.JSValue) !c.JSValue {
    return v.boolean(s, try v.eq(s, exposure, "codemode") or try v.eq(s, exposure, "deferred"));
}
fn searchableCall(engine: *Engine, _: c.JSValue, args: *Arguments, _: []const c.JSValue) !c.JSValue {
    return h.expression(engine, searchableBody, .{args.get(0)});
}
fn callSearchable(s: *Scope, callable: c.JSValue, tool: c.JSValue) !c.JSValue {
    const result = try v.call(s, callable, c.pi_js_undefined(), &.{try v.get(s, tool, "exposure")});
    return v.boolean(s, v.truthy(s, result));
}
fn activeIncludes(s: *Scope, active_cell: c.JSValue, tool: c.JSValue) !c.JSValue {
    const receiver = try SearchFrame.read(s, active_cell);
    const callee = try v.get(s, receiver, "includes");
    const result = try v.call(s, callee, receiver, &.{try v.get(s, tool, "name")});
    return v.boolean(s, !v.truthy(s, result));
}
fn candidateBody(s: *Scope, tool: c.JSValue, searchable: c.JSValue, active_cell: c.JSValue) !c.JSValue {
    if (!h.truthy(s.engine, try h.expression(s.engine, callSearchable, .{searchable, tool})))
        return v.boolean(s, false);
    return h.expression(s.engine, activeIncludes, .{active_cell, tool});
}
fn candidateCall(engine: *Engine, _: c.JSValue, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, candidateBody, .{args.get(0), roots[0], roots[1]});
}
fn activeTools(s: *Scope, tools: c.JSValue) !c.JSValue {
    return v.duplicate(s, try t.invoke(s, tools, "getActiveTools", &.{}));
}
fn allTools(s: *Scope, tools: c.JSValue) !c.JSValue {
    return v.duplicate(s, try t.invoke(s, tools, "getAllTools", &.{}));
}
fn candidatesValue(s: *Scope, tools: c.JSValue, frame: *SearchFrame, searchable: c.JSValue) !c.JSValue {
    const receiver = try v.own(s, try h.expression(s.engine, allTools, .{tools}));
    const callee = try v.get(s, receiver, "filter");
    const active_cell = try frame.capture(s, .active, "active");
    const callback = try t.arrow(s, "", 1,
        .{ .formal_count = 1, .callback = candidateCall }, &.{searchable, active_cell});
    return v.duplicate(s, try v.call(s, callee, receiver, &.{callback}));
}
fn documentBody(s: *Scope, tool: c.JSValue, callable: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), &.{tool, try v.get(s, tool, "namespace")}));
}
fn documentCall(engine: *Engine, _: c.JSValue, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, documentBody, .{args.get(0), roots[0]});
}
fn documentsValue(s: *Scope, candidates: c.JSValue, callable: c.JSValue) !c.JSValue {
    const callee = try v.get(s, candidates, "map");
    const callback = try t.arrow(s, "", 1,
        .{ .formal_count = 1, .callback = documentCall }, &.{callable});
    return v.duplicate(s, try v.call(s, callee, candidates, &.{callback}));
}
fn instance(s: *Scope, constructor: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.construct(s, constructor, &.{}));
}
fn matchesValue(s: *Scope, constructor: c.JSValue, query: c.JSValue, documents: c.JSValue, limit: c.JSValue) !c.JSValue {
    const receiver = try v.own(s, try h.expression(s.engine, instance, .{constructor}));
    const callee = try v.get(s, receiver, "rank");
    return v.duplicate(s, try v.call(s, callee, receiver, &.{query, documents, limit}));
}
fn nameBody(s: *Scope, value: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.get(s, value, "name"));
}
pub fn nameCall(engine: *Engine, _: c.JSValue, args: *Arguments, _: []const c.JSValue) !c.JSValue {
    return h.expression(engine, nameBody, .{args.get(0)});
}
pub fn names(s: *Scope, matches: c.JSValue) !c.JSValue {
    const callee = try v.get(s, matches, "map");
    const callback = try t.arrow(s, "", 1, .{ .formal_count = 1, .callback = nameCall }, &.{});
    return v.duplicate(s, try v.call(s, callee, matches, &.{callback}));
}
fn activated(s: *Scope, active: c.JSValue, matches: c.JSValue) !c.JSValue {
    const result = try v.array(s);
    var position: u32 = 0;
    try t.append(s, result, &position, active);
    const found_names = try v.own(s, try h.expression(s.engine, names, .{matches}));
    try t.append(s, result, &position, found_names);
    return v.duplicate(s, result);
}
fn activate(s: *Scope, tools: c.JSValue, frame: *SearchFrame) !void {
    const callee = try v.get(s, tools, "setActiveTools");
    const value = try v.own(s, try h.expression(s.engine, activated, .{frame.get(.active), frame.get(.matches)}));
    _ = try v.call(s, callee, tools, &.{value});
}
fn sameName(s: *Scope, tool: c.JSValue, match_cell: c.JSValue) !c.JSValue {
    const left = try v.get(s, tool, "name");
    const match = try t.sync.read(s, match_cell);
    return v.boolean(s, c.JS_IsStrictEqual(s.engine.context, left, try v.get(s, match, "name")));
}
fn sameNameCall(engine: *Engine, _: c.JSValue, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, sameName, .{args.get(0), roots[0]});
}
fn findCandidate(s: *Scope, args: *Arguments, candidates_cell: c.JSValue) !c.JSValue {
    const receiver = try SearchFrame.read(s, candidates_cell);
    const callee = try v.get(s, receiver, "find");
    const match_cell = try args.capture(s, 0);
    const callback = try t.arrow(s, "", 1, .{ .formal_count = 1, .callback = sameNameCall }, &.{match_cell});
    return v.duplicate(s, try v.call(s, callee, receiver, &.{callback}));
}
fn descriptionLookup(s: *Scope, args: *Arguments, candidates_cell: c.JSValue) !c.JSValue {
    const receiver = try v.own(s, try h.expression(s.engine, findCandidate, .{args, candidates_cell}));
    return v.duplicate(s, if (v.nullish(receiver)) c.pi_js_undefined() else try v.get(s, receiver, "description"));
}
fn description(s: *Scope, args: *Arguments, candidates_cell: c.JSValue) !c.JSValue {
    const value = try v.own(s, try h.expression(s.engine, descriptionLookup, .{args, candidates_cell}));
    return v.duplicate(s, if (v.nullish(value)) try v.text(s, "") else value);
}
fn resultBody(s: *Scope, args: *Arguments, candidates_cell: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "name", try v.get(s, args.get(0), "name"));
    try v.put(s, result, "description", try v.own(s, try h.expression(s.engine, description, .{args, candidates_cell})));
    return v.duplicate(s, result);
}
fn resultCall(engine: *Engine, _: c.JSValue, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, resultBody, .{args, roots[0]});
}
fn results(s: *Scope, frame: *SearchFrame) !c.JSValue {
    const receiver = frame.get(.matches);
    const callee = try v.get(s, receiver, "map");
    const candidates_cell = try frame.capture(s, .candidates, "candidates");
    const callback = try t.arrow(s, "", 1, .{ .formal_count = 1, .callback = resultCall }, &.{candidates_cell});
    return v.duplicate(s, try v.call(s, callee, receiver, &.{callback}));
}
fn searchBody(s: *Scope, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    const frame = try args.createFrame(s, SearchFrame);
    try frame.take(.active, h.expression(s.engine, activeTools, .{args.get(0)}));
    try frame.take(.candidates, h.expression(s.engine, candidatesValue, .{args.get(0), frame, roots[0]}));
    try frame.take(.documents, h.expression(s.engine, documentsValue, .{frame.get(.candidates), roots[1]}));
    try frame.take(.matches, h.expression(s.engine, matchesValue,
        .{roots[2], args.get(1), frame.get(.documents), args.get(2)}));
    if (h.truthy(s.engine, try h.expression(s.engine, t.fieldCompare,
        .{frame.get(.matches), @as([*:0]const u8, "length"), h.math.Operation.greater, v.number(s, 0)})))
        try h.statement(s.engine, activate, .{args.get(0), frame});
    return h.expression(s.engine, results, .{frame});
}
fn searchCall(engine: *Engine, _: c.JSValue, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, searchBody, .{args, roots});
}
