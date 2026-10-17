//! Actual jiti2.7 Babel import-meta passes, including compiler-only contexts.
//! Derived from pinned jiti contributors' passes and Ernest's import-meta-env;
//! exact jiti/Babel/MIT and predecessor BSD notices are retained with this unit.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = @cImport({ @cInclude("tree_sitter/api.h"); });
extern fn tree_sitter_typescript() ?*const c.TSLanguage;
pub const Imports = struct { path_to_file_url: v.c.JSValue, file_url_to_path: v.c.JSValue, dirname: v.c.JSValue };
const Kind = enum { url, dirname, filename, resolve, env };
const Edit = struct { node: c.TSNode, kind: Kind, replacement: ?[]u8 = null };
const Plan = struct {
    engine: *v.em.Engine, source: []const u8, edits: std.ArrayList(Edit) = .empty,
    fn deinit(self: *Plan) void { for (self.edits.items) |edit| if (edit.replacement) |replacement_text| self.engine.gpa.free(replacement_text); self.edits.deinit(self.engine.gpa); }
};
fn kind(node: c.TSNode) []const u8 { return if (c.ts_node_is_null(node)) "" else std.mem.span(c.ts_node_type(node)); }
fn is(node: c.TSNode, name: []const u8) bool { return std.mem.eql(u8, kind(node), name); }
fn field(node: c.TSNode, comptime name: [:0]const u8) c.TSNode { return c.ts_node_child_by_field_name(node, name, name.len); }
fn text(source: []const u8, node: c.TSNode) []const u8 { return source[c.ts_node_start_byte(node)..c.ts_node_end_byte(node)]; }
fn hasToken(node: c.TSNode, name: []const u8) bool { for (0..c.ts_node_child_count(node)) |i| if (is(c.ts_node_child(node, @intCast(i)), name)) return true; return false; }
fn unwrap(input: c.TSNode) c.TSNode {
    var node = input;
    while (is(node, "parenthesized_expression")) {
        var only: ?c.TSNode = null;
        for (0..c.ts_node_named_child_count(node)) |i| { const child = c.ts_node_named_child(node, @intCast(i)); if (is(child, "comment")) continue; if (only != null) return node; only = child; }
        node = only orelse return node;
    }
    return node;
}
fn collect(plan: *Plan, node: c.TSNode, depth: usize) !void {
    if (depth > 256) return error.UnsupportedJitiMetaNesting;
    if (is(node, "member_expression") or is(node, "subscript_expression")) {
        const object = unwrap(field(node, "object"));
        if (is(object, "meta_property") and hasToken(object, "import")) {
            // Primary plugins visit MemberExpression with Identifier property,
            // irrespective of computed/write/delete position. OptionalMember-
            // Expression and literal-index members are deliberately untouched.
            // Output is compiler text, not a promise of valid CJS evaluation.
            if (!c.ts_node_is_null(field(node, "optional_chain"))) return;
            const property = if (is(node,"subscript_expression")) field(node,"index") else field(node, "property");
            if (!is(property, "property_identifier") and !is(property,"identifier")) return;
            const tag = std.meta.stringToEnum(Kind, text(plan.source, property)) orelse return;
            try plan.edits.append(plan.engine.gpa, .{ .node = node, .kind = tag });
            return;
        }
    }
    if (is(node, "meta_property")) return;
    for (0..c.ts_node_named_child_count(node)) |i| try collect(plan, c.ts_node_named_child(node, @intCast(i)), depth + 1);
}
/// Owned rewritten source. Does not execute user code or create a Module/cache
/// record. Imported path functions are actual mlly/pathe operations.
pub fn rewrite(engine: *v.em.Engine, imports: Imports, input: []const u8, filename: v.c.JSValue) anyerror![]u8 {
    if (input.len > 16 * 1024 * 1024) return error.UnsupportedJitiMetaSourceSize;
    const parser = c.ts_parser_new() orelse return error.OutOfMemory; defer c.ts_parser_delete(parser);
    if (!c.ts_parser_set_language(parser, tree_sitter_typescript())) return error.TypeScriptParserAbiMismatch;
    const tree = c.ts_parser_parse_string(parser, null, input.ptr, @intCast(input.len)) orelse return error.OutOfMemory; defer c.ts_tree_delete(tree);
    const root = c.ts_tree_root_node(tree); if (c.ts_node_has_error(root)) return error.UnsupportedJitiBabelDiagnostic;
    var plan: Plan = .{ .engine = engine, .source = input }; defer plan.deinit();
    try collect(&plan, root, 0);
    // Source Program visitor groups all URL replacements, then dirname, then
    // filename. Actual path calls happen in this order, not occurrence order.
    for ([_]Kind{ .url, .dirname, .filename, .resolve, .env }) |tag| {
        for (plan.edits.items) |*edit| if (edit.kind == tag) { edit.replacement = try replacement(engine, imports, tag, filename); };
    }
    std.mem.sort(Edit, plan.edits.items, {}, struct { fn less(_: void, a: Edit, b: Edit) bool { return c.ts_node_start_byte(a.node) < c.ts_node_start_byte(b.node); } }.less);
    var output: std.Io.Writer.Allocating = .init(engine.gpa); defer output.deinit();
    var offset: usize = 0;
    for (plan.edits.items) |edit| {
        const start = c.ts_node_start_byte(edit.node); const end = c.ts_node_end_byte(edit.node);
        if (start < offset) return error.UnsupportedJitiMetaOverlap;
        try output.writer.writeAll(input[offset..start]); try output.writer.writeAll(edit.replacement.?); offset = end;
    }
    try output.writer.writeAll(input[offset..]); return output.toOwnedSlice();
}
fn replacement(engine: *v.em.Engine, imports: Imports, tag: Kind, filename: v.c.JSValue) ![]u8 {
    if (tag == .env) return engine.gpa.dupe(u8, "process.env");
    if (tag == .resolve) return engine.gpa.dupe(u8, "jitiESMResolve");
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    if (!s.truthy(filename)) return engine.gpa.dupe(u8, switch (tag) { .url => "require('url').pathToFileURL(__filename).toString()", .dirname => "__dirname", .filename => "__filename", else => unreachable });
    // Source acquires JSON.stringify before evaluating its path argument.
    const json = try s.global("JSON"); try current(engine);
    const stringify = try s.get(json, "stringify"); try current(engine);
    var path = try s.call(imports.path_to_file_url, v.c.pi_js_undefined(), &.{filename});
    try current(engine);
    if (tag != .url) { path = try s.call(imports.file_url_to_path, v.c.pi_js_undefined(), &.{path}); try current(engine); }
    if (tag == .dirname) { path = try s.call(imports.dirname, v.c.pi_js_undefined(), &.{path}); try current(engine); }
    const encoded = try s.call(stringify, json, &.{path}); try current(engine);
    if (!v.c.JS_IsString(encoded)) return error.UnsupportedJitiMetaLiteral;
    const bytes = try engine.toString(encoded); errdefer engine.gpa.free(bytes);
    const terminated = try engine.gpa.dupeZ(u8, bytes); defer engine.gpa.free(terminated);
    const literal = try s.own(try engine.checked(v.c.JS_ParseJSON(engine.context, terminated.ptr, bytes.len, "native-jiti-meta-literal.json")));
    if (!v.c.JS_IsString(literal)) return error.UnsupportedJitiMetaLiteral;
    return bytes;
}
fn current(engine:*v.em.Engine)!void{if(v.c.JS_HasException(engine.context))return v.js.capture(engine);}
