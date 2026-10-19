//! Complete genuine c268 tool-search module and extension factory.
//! The private lexical graph is retained once; public export records cannot
//! replace the actual bindings captured by its declarations.
const t = @import("native_sdk_tool_search_values.zig");
const h = t.h;
const v = t.v;
const c = t.c;
const Engine = t.Engine;
const Scope = t.Scope;
const Arguments = t.Arguments;
const copy = @import("native_sdk_catalog_copy.zig");
const catalog = @import("native_sdk_catalog_values.zig");
const key = "\x00sdk-tool-search-module-c268";

pub fn create(engine: *Engine) !c.JSValue {
    try engine.checkNativeEntry();
    return h.expression(engine, selectedExports, .{});
}
fn selectedExports(s: *Scope) !c.JSValue {
    const owner = try v.own(s, try moduleOwner(s.engine));
    return v.duplicate(s, try v.get(s, owner, "exports"));
}
fn moduleOwner(engine: *Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(key)) |cached| return h.duplicate(engine, cached);
    const candidate = try h.expression(engine, moduleBody, .{});
    if (engine.native_module_values.get(key)) |cached| {
        var selected = v.owned.Completion.initValue(engine, h.duplicate(engine, cached));
        selected.release(candidate);
        return selected.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var failed = v.owned.Completion.initValue(engine, @as(anyerror!c.JSValue, err));
        failed.release(candidate);
        return failed.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(key, candidate);
    return h.duplicate(engine, candidate);
}
fn queryOptions(s: *Scope) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "description", try v.text(s, "Search query for deferred tools."));
    return v.duplicate(s, result);
}
fn querySchema(s: *Scope, types: c.JSValue) !c.JSValue {
    const callee = try v.get(s, types, "String");
    const options = try v.own(s, try h.expression(s.engine, queryOptions, .{}));
    return v.duplicate(s, try v.call(s, callee, types, &.{options}));
}
fn maximumDescription(s: *Scope) !c.JSValue {
    const prefix = try v.text(s, "Maximum number of tools to return. Defaults to ");
    const rendered = try v.own(s, try h.expression(s.engine, t.stringBody, .{v.number(s, 8)}));
    const before_end = try h.binary(s, .add, prefix, rendered);
    return v.duplicate(s, try h.binary(s, .add, before_end, try v.text(s, ".")));
}
fn limitOptions(s: *Scope) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "description", try v.own(s, try h.expression(s.engine, maximumDescription, .{})));
    return v.duplicate(s, result);
}
fn numberSchema(s: *Scope, types: c.JSValue) !c.JSValue {
    const callee = try v.get(s, types, "Number");
    const options = try v.own(s, try h.expression(s.engine, limitOptions, .{}));
    return v.duplicate(s, try v.call(s, callee, types, &.{options}));
}
fn limitSchema(s: *Scope, types: c.JSValue) !c.JSValue {
    const callee = try v.get(s, types, "Optional");
    const argument = try v.own(s, try h.expression(s.engine, numberSchema, .{types}));
    return v.duplicate(s, try v.call(s, callee, types, &.{argument}));
}
fn schemaFields(s: *Scope, types: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "query", try v.own(s, try h.expression(s.engine, querySchema, .{types})));
    try v.put(s, result, "limit", try v.own(s, try h.expression(s.engine, limitSchema, .{types})));
    return v.duplicate(s, result);
}
fn schemaBody(s: *Scope, types: c.JSValue) !c.JSValue {
    const callee = try v.get(s, types, "Object");
    const fields = try v.own(s, try h.expression(s.engine, schemaFields, .{types}));
    return v.duplicate(s, try v.call(s, callee, types, &.{fields}));
}
fn descriptionBody(s: *Scope) !c.JSValue {
    const first = try v.text(s, "# Tool discovery\n\nSearches over deferred tool metadata with BM25 and exposes matching tools for the next model call.\n\nSome of the tools, such as tools of MCP servers, may not have been provided to you upfront, and you should use this tool (`");
    const name = try v.text(s, "tool_search");
    const named = try h.binary(s, .add, first, name);
    const second = try h.binary(s, .add, named, try v.text(s, "`) to search for the required tools. For MCP tool discovery, always use `"));
    const repeated = try h.binary(s, .add, second, name);
    return v.duplicate(s, try h.binary(s, .add, repeated, try v.text(s, "`.")));
}
fn optionsForPi(s: *Scope, pi: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "tools", pi);
    return v.duplicate(s, result);
}
fn definitionForPi(s: *Scope, callable: c.JSValue, pi: c.JSValue) !c.JSValue {
    const options = try v.own(s, try h.expression(s.engine, optionsForPi, .{pi}));
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), &.{options}));
}
fn registration(s: *Scope, callable: c.JSValue, pi: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    const definition = try v.own(s, try h.expression(s.engine, definitionForPi, .{callable, pi}));
    var ops: catalog.Ops = .{ .s = s };
    try copy.into(&ops, result, definition);
    try v.put(s, result, "defaultActive", v.boolean(s, false));
    return v.duplicate(s, result);
}
fn register(s: *Scope, pi: c.JSValue, callable: c.JSValue) !void {
    const callee = try v.get(s, pi, "registerTool");
    const definition = try v.own(s, try h.expression(s.engine, registration, .{callable, pi}));
    _ = try v.call(s, callee, pi, &.{definition});
}
fn extensionCall(engine: *Engine, _: c.JSValue, args: *Arguments, roots: []const c.JSValue) !c.JSValue {
    try h.statement(engine, register, .{args.get(0), roots[0]});
    return c.pi_js_undefined();
}
fn extensionBody(s: *Scope, definition: c.JSValue) !c.JSValue {
    return v.duplicate(s, try t.arrow(s, "", 1, .{ .formal_count = 1, .callback = extensionCall }, &.{definition}));
}
fn extensionFactoryCall(engine: *Engine, _: c.JSValue, _: *Arguments, roots: []const c.JSValue) !c.JSValue {
    return h.expression(engine, extensionBody, .{roots[0]});
}
fn defaultExtension(s: *Scope, callable: c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), &.{}));
}
fn moduleBody(s: *Scope) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const typebox = try boundary.finishValue(s, @import("native_typebox_production_graph.zig").create(s.engine));
    const types = try v.get(s, typebox, "Type");
    const text_module = try v.own(s, try @import("native_sdk_tool_search_text.zig").create(s));
    const ranker = try v.own(s, try @import("native_sdk_tool_search_ranker.zig").create(s, text_module));
    const document = try v.get(s, text_module, "createToolSearchDocument");
    const search = try v.own(s, try @import("native_sdk_tool_search_load.zig").create(s, document, ranker));
    const schema = try v.own(s, try h.expression(s.engine, schemaBody, .{types}));
    const description = try v.own(s, try h.expression(s.engine, descriptionBody, .{}));
    const definition = try v.own(s, try @import("native_sdk_tool_search_execute.zig").create(s, search, schema, description));
    const extension_factory = try t.function(s, "createToolSearchExtension", 0,
        .{ .formal_count = 0, .callback = extensionFactoryCall }, &.{definition});
    const default_extension = try v.own(s, try h.expression(s.engine, defaultExtension, .{extension_factory}));

    const exports = try v.object(s);
    try v.put(s, exports, "TOOL_SEARCH_TOOL_NAME", try v.text(s, "tool_search"));
    try v.put(s, exports, "DEFAULT_TOOL_SEARCH_LIMIT", v.number(s, 8));
    try v.put(s, exports, "tokenize", try v.get(s, text_module, "tokenize"));
    try v.put(s, exports, "createToolSearchDocument", document);
    try v.put(s, exports, "Bm25Ranker", ranker);
    try v.put(s, exports, "toolSearchSchema", schema);
    try v.put(s, exports, "TOOL_SEARCH_DESCRIPTION", description);
    try v.put(s, exports, "createToolSearchToolDefinition", definition);
    try v.put(s, exports, "createToolSearchExtension", extension_factory);
    try v.put(s, exports, "default", default_extension);

    const owner = try v.stateObject(s);
    try v.put(s, owner, "typebox", typebox);
    try v.put(s, owner, "text", text_module);
    try v.put(s, owner, "ranker", ranker);
    try v.put(s, owner, "search", search);
    try v.put(s, owner, "schema", schema);
    try v.put(s, owner, "description", description);
    try v.put(s, owner, "definition", definition);
    try v.put(s, owner, "extension", extension_factory);
    try v.put(s, owner, "default", default_extension);
    try v.put(s, owner, "exports", exports);
    return v.duplicate(s, owner);
}
