//! Native bounded jiti2.7 import-meta-paths/env/resolve passes over user syntax.
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
    engine: *v.em.Engine, source: []const u8, edits: std.ArrayList(Edit) = .empty, original_process_identifier: bool = false,
    fn deinit(self: *Plan) void { for (self.edits.items) |edit| if (edit.replacement) |text| self.engine.gpa.free(text); self.edits.deinit(self.engine.gpa); }
};
fn kind(node: c.TSNode) []const u8 { return if (c.ts_node_is_null(node)) "" else std.mem.span(c.ts_node_type(node)); }
fn is(node: c.TSNode, name: []const u8) bool { return std.mem.eql(u8, kind(node), name); }
fn field(node: c.TSNode, comptime name: [:0]const u8) c.TSNode { return c.ts_node_child_by_field_name(node, name, name.len); }
fn text(source: []const u8, node: c.TSNode) []const u8 { return source[c.ts_node_start_byte(node)..c.ts_node_end_byte(node)]; }
fn same(a: c.TSNode, b: c.TSNode) bool { return !c.ts_node_is_null(a) and !c.ts_node_is_null(b) and c.ts_node_start_byte(a) == c.ts_node_start_byte(b) and c.ts_node_end_byte(a) == c.ts_node_end_byte(b); }
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
fn writing(node: c.TSNode, source: []const u8) bool {
    var child = node; var parent = c.ts_node_parent(child);
    while (!c.ts_node_is_null(parent)) {
        // Follow only target edges. A computed pattern key or a default's
        // initializer evaluates a read even when its containing pattern is a
        // target; an outer member's object/index likewise reads this value.
        if (is(parent, "parenthesized_expression") or is(parent, "non_null_expression") or
            is(parent, "array_pattern") or is(parent, "object_pattern") or is(parent, "rest_pattern"))
        {
            child = parent; parent = c.ts_node_parent(parent); continue;
        }
        if (is(parent, "pair_pattern")) {
            if (!same(child, field(parent, "value"))) return false;
            child = parent; parent = c.ts_node_parent(parent); continue;
        }
        if (is(parent, "assignment_pattern") or is(parent, "object_assignment_pattern")) {
            if (!same(child, field(parent, "left"))) return false;
            child = parent; parent = c.ts_node_parent(parent); continue;
        }
        if (is(parent, "assignment_expression") or is(parent, "augmented_assignment_expression") or is(parent, "for_in_statement"))
            return same(child, field(parent, "left"));
        if (is(parent, "update_expression")) return same(child, field(parent, "argument"));
        return is(parent, "unary_expression") and same(child, field(parent, "argument")) and std.mem.eql(u8, text(source, field(parent, "operator")), "delete");
    }
    return false;
}
fn collect(plan: *Plan, node: c.TSNode, depth: usize) !void {
    if (depth > 256) return error.UnsupportedJitiMetaNesting;
    if (is(node, "identifier") and std.mem.eql(u8, text(plan.source, node), "process")) plan.original_process_identifier = true;
    if (is(node, "member_expression") or is(node, "subscript_expression")) {
        const object = unwrap(field(node, "object"));
        if (is(object, "meta_property") and hasToken(object, "import")) {
            // Babel's computed-identifier quirks and TS import-elision visitor
            // interaction need a separate profile. Do not guess them here.
            if (!is(node, "member_expression") or !c.ts_node_is_null(field(node, "optional_chain")) or writing(node, plan.source)) return error.UnsupportedJitiMetaForm;
            const property = field(node, "property");
            if (!is(property, "property_identifier")) return error.UnsupportedJitiMetaForm;
            const tag = std.meta.stringToEnum(Kind, text(plan.source, property)) orelse return error.UnsupportedJitiMetaProperty;
            try plan.edits.append(plan.engine.gpa, .{ .node = node, .kind = tag });
            return;
        }
    }
    if (is(node, "meta_property")) return error.UnsupportedJitiMetaProperty;
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
    if (plan.original_process_identifier) for (plan.edits.items) |edit| if (edit.kind == .env) return error.UnsupportedJitiMetaProcessBinding;
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
    const json = try s.global("JSON"); const stringify = try s.get(json, "stringify");
    var path = try s.call(imports.path_to_file_url, v.c.pi_js_undefined(), &.{filename});
    if (tag != .url) path = try s.call(imports.file_url_to_path, v.c.pi_js_undefined(), &.{path});
    if (tag == .dirname) path = try s.call(imports.dirname, v.c.pi_js_undefined(), &.{path});
    const encoded = try s.call(stringify, json, &.{path});
    if (!v.c.JS_IsString(encoded)) return error.UnsupportedJitiMetaLiteral;
    const bytes = try engine.toString(encoded); errdefer engine.gpa.free(bytes);
    const terminated = try engine.gpa.dupeZ(u8, bytes); defer engine.gpa.free(terminated);
    const literal = try s.own(try engine.checked(v.c.JS_ParseJSON(engine.context, terminated.ptr, bytes.len, "native-jiti-meta-literal.json")));
    if (!v.c.JS_IsString(literal)) return error.UnsupportedJitiMetaLiteral;
    return bytes;
}
