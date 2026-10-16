//! Bounded native lowering of the selected jiti2.7 Babel module profile.
//! Tree-sitter supplies syntax; Zig performs validation and code generation.
//! Unsupported forms fail before a wrapper or dependency can execute.
const std = @import("std");
const ts = @import("typescript.zig");
const c = @cImport({ @cInclude("tree_sitter/api.h"); });
extern fn tree_sitter_typescript() ?*const c.TSLanguage;
pub const Options = struct { typescript: bool = true, async_mode: bool = false };
pub const Error = ts.TransformError || error{
    UnsupportedModuleForm, UnsupportedModuleIdentifier, UnsupportedModuleBinding,
    UnsupportedModuleBindingShadow, UnsupportedModuleWrite, UnsupportedModuleImport,
    UnsupportedModuleRuntimeSyntax, UnsupportedModuleEvaluation, DuplicateModuleExport,
    MissingModuleExportBinding, OverlappingModuleEdit,
};
const Range = struct { start: usize, end: usize };
const Edit = struct { range: Range, text: []u8 };
const Kind = enum { constant, function, class, mutable };
const Decl = struct { name: []const u8, kind: Kind, name_range: Range, statement: Range, value: ?Range, late_init: bool = false };
const Export = struct { name: []const u8, local: []const u8, kind: Kind };
const Source = struct { literal: []const u8, name: []const u8, active_start: usize = std.math.maxInt(usize), named: bool = false };
const Import = struct { local: []const u8, name: []const u8, source: usize, statement: Range, used: bool = false };
const ImportStatement = struct { source: usize, range: Range, side_effect: bool };
fn kind(n: c.TSNode) []const u8 { return if (c.ts_node_is_null(n)) "" else std.mem.span(c.ts_node_type(n)); }
fn range(n: c.TSNode) Range { return .{ .start = c.ts_node_start_byte(n), .end = c.ts_node_end_byte(n) }; }
fn field(n: c.TSNode, comptime name: [:0]const u8) c.TSNode { return c.ts_node_child_by_field_name(n, name, name.len); }
fn is(n: c.TSNode, expected: []const u8) bool { return std.mem.eql(u8, kind(n), expected); }
fn any(n: c.TSNode, names: []const []const u8) bool { for (names) |name| if (is(n, name)) return true; return false; }
fn identifier(text: []const u8) bool {
    if (text.len == 0 or !(std.ascii.isAlphabetic(text[0]) or text[0] == '_' or text[0] == '$')) return false;
    for (text[1..]) |byte| if (!(std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '$')) return false;
    return true;
}
fn reserved(text: []const u8) bool {
    inline for (.{ "exports", "require", "module", "__filename", "__dirname", "jitiImport", "jitiESMResolve", "undefined", "arguments", "eval", "await", "yield", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for", "function", "if", "import", "in", "instanceof", "new", "null", "return", "super", "switch", "this", "throw", "true", "try", "typeof", "var", "void", "while", "with", "let", "static", "implements", "interface", "package", "private", "protected", "public" }) |name| if (std.mem.eql(u8, text, name)) return true;
    return std.mem.startsWith(u8, text, "__pi_cjs_") or std.mem.eql(u8, text, "_default");
}
const Plan = struct {
    gpa: std.mem.Allocator, source: []const u8, original: []const u8, original_root: c.TSNode, options: Options,
    declarations: std.ArrayList(Decl) = .empty,
    exports: std.ArrayList(Export) = .empty,
    sources: std.ArrayList(Source) = .empty,
    imports: std.ArrayList(Import) = .empty,
    import_statements: std.ArrayList(ImportStatement) = .empty,
    edits: std.ArrayList(Edit) = .empty,
    fn deinit(p: *Plan) void {
        for (p.edits.items) |e| p.gpa.free(e.text);
        p.edits.deinit(p.gpa); p.import_statements.deinit(p.gpa); p.imports.deinit(p.gpa);
        p.sources.deinit(p.gpa); p.exports.deinit(p.gpa); p.declarations.deinit(p.gpa);
    }
    fn text(p: *Plan, n: c.TSNode) []const u8 { const r = range(n); return p.source[r.start..r.end]; }
    fn edit(p: *Plan, r: Range, text: []const u8) Error!void {
        const copy = try p.gpa.dupe(u8, text); errdefer p.gpa.free(copy);
        try p.edits.append(p.gpa, .{ .range = r, .text = copy });
    }
    fn erase(p: *Plan, r: Range) Error!void {
        const blank = try p.gpa.dupe(u8, p.source[r.start..r.end]); defer p.gpa.free(blank);
        for (blank) |*byte| if (byte.* != '\n' and byte.* != '\r') { byte.* = ' '; };
        try p.edit(r, blank);
    }
    fn declaration(p: *Plan, name: []const u8) ?Decl { for (p.declarations.items) |d| if (std.mem.eql(u8, d.name, name)) return d; return null; }
    fn imported(p: *Plan, name: []const u8) ?usize { for (p.imports.items, 0..) |i, index| if (std.mem.eql(u8, i.local, name)) return index; return null; }
    fn exported(p: *Plan, name: []const u8) bool { for (p.exports.items) |e| if (std.mem.eql(u8, e.local, name)) return true; return false; }
    fn addDecl(p: *Plan, n: c.TSNode) Error!void {
        if (any(n, &.{ "function_declaration", "generator_function_declaration", "class_declaration" })) {
            const name = field(n, "name"); if (c.ts_node_is_null(name)) return;
            try p.declarations.append(p.gpa, .{ .name = p.text(name), .kind = if (is(n, "class_declaration")) .class else .function, .name_range = range(name), .statement = range(n), .value = null });
        } else if (any(n, &.{ "lexical_declaration", "variable_declaration" })) {
            const declaration_kind: Kind = if (is(n, "lexical_declaration") and std.mem.eql(u8, p.text(field(n, "kind")), "const")) .constant else .mutable;
            for (0..c.ts_node_named_child_count(n)) |index| {
                const child = c.ts_node_named_child(n, @intCast(index)); if (!is(child, "variable_declarator")) continue;
                const name = field(child, "name"); if (!is(name, "identifier")) continue;
                const value = field(child, "value");
                try p.declarations.append(p.gpa, .{ .name = p.text(name), .kind = declaration_kind, .name_range = range(name), .statement = range(n), .value = if (c.ts_node_is_null(value)) null else range(value), .late_init = anonymousInitializer(value) });
            }
        }
    }
    fn addExport(p: *Plan, name: []const u8, local: []const u8, declaration_kind: Kind) Error!void {
        if (!identifier(name) or std.mem.eql(u8, name, "__esModule") or std.mem.eql(u8, name, "__proto__") or std.mem.eql(u8, local, "undefined")) return error.UnsupportedModuleIdentifier;
        for (p.exports.items) |e| if (std.mem.eql(u8, e.name, name)) return error.DuplicateModuleExport;
        if (declaration_kind == .mutable) return error.UnsupportedModuleWrite;
        try p.exports.append(p.gpa, .{ .name = name, .local = local, .kind = declaration_kind });
    }
    fn sourceIndex(p: *Plan, literal: []const u8) Error!usize {
        if (literal.len < 2 or (literal[0] != '\'' and literal[0] != '"')) return error.UnsupportedModuleImport;
        const name = literal[1..literal.len - 1];
        for (name) |byte| if (byte == '\\' or byte >= 128 or byte < 32) return error.UnsupportedModuleImport;
        for (p.sources.items, 0..) |s, index| if (std.mem.eql(u8, s.name, name)) return index;
        try p.sources.append(p.gpa, .{ .literal = literal, .name = name }); return p.sources.items.len - 1;
    }
    fn importStatement(p: *Plan, n: c.TSNode) Error!void {
        if (p.options.typescript) for (0..c.ts_node_named_child_count(p.original_root)) |index| {
            const original = c.ts_node_named_child(p.original_root, @intCast(index));
            if (is(original, "import_statement") and range(original).start == range(n).start and (hasToken(original, "type") or typeOnlySpecifiers(original, p.original))) return p.erase(range(n));
        };
        const src = field(n, "source"); if (c.ts_node_is_null(src)) return error.UnsupportedModuleImport;
        const source_index = try p.sourceIndex(p.text(src)); var has_clause = false;
        const before = p.imports.items.len;
        for (0..c.ts_node_named_child_count(n)) |index| {
            const child = c.ts_node_named_child(n, @intCast(index)); if (is(child, "comment") or is(child, "string")) continue;
            if (!is(child, "import_clause")) return error.UnsupportedModuleImport; has_clause = true;
            for (0..c.ts_node_named_child_count(child)) |part_index| {
                const part = c.ts_node_named_child(child, @intCast(part_index)); if (is(part, "comment")) continue;
                if (!is(part, "named_imports")) return error.UnsupportedModuleImport;
                for (0..c.ts_node_named_child_count(part)) |specifier_index| {
                    const specifier = c.ts_node_named_child(part, @intCast(specifier_index)); if (is(specifier, "comment")) continue;
                    if (!is(specifier, "import_specifier")) return error.UnsupportedModuleImport;
                    if (p.options.typescript and hasToken(specifier, "type")) continue;
                    const name = field(specifier, "name"); const alias = field(specifier, "alias");
                    const local = if (c.ts_node_is_null(alias)) name else alias;
                    if (!is(name, "identifier") or !identifier(p.text(name)) or !identifier(p.text(local)) or std.mem.eql(u8, p.text(name), "default")) return error.UnsupportedModuleImport;
                    if (reserved(p.text(local)) or p.imported(p.text(local)) != null) return error.UnsupportedModuleBinding;
                    try p.imports.append(p.gpa, .{ .local = p.text(local), .name = p.text(name), .source = source_index, .statement = range(n) });
                }
            }
        }
        try p.import_statements.append(p.gpa, .{ .source = source_index, .range = range(n), .side_effect = !has_clause or p.imports.items.len == before });
        try p.erase(range(n));
    }
    fn exportStatement(p: *Plan, n: c.TSNode) Error!void {
        if (!c.ts_node_is_null(field(n, "source"))) return error.UnsupportedModuleImport;
        var value = field(n, "declaration"); if (c.ts_node_is_null(value)) value = field(n, "value");
        const default_export = hasToken(n, "default");
        if (default_export) {
            if (c.ts_node_is_null(value)) return error.UnsupportedModuleForm;
            if (any(value, &.{ "function_declaration", "function_expression", "generator_function", "generator_function_declaration" })) {
                const name = field(value, "name"); const local = if (c.ts_node_is_null(name)) "_default" else p.text(name);
                try p.addExport("default", local, .function);
                try p.erase(.{ .start = range(n).start, .end = range(value).start });
                if (c.ts_node_is_null(name)) {
                    const parameters = field(value, "parameters"); if (c.ts_node_is_null(parameters)) return error.UnsupportedModuleForm;
                    try p.edit(.{ .start = range(parameters).start, .end = range(parameters).start }, " _default");
                } else if (p.declaration(local) == null) {
                    try p.declarations.append(p.gpa, .{ .name = local, .kind = .function, .name_range = range(name), .statement = range(value), .value = null });
                }
                return;
            }
            if (any(value, &.{ "class", "class_declaration" })) {
                const name = field(value, "name"); if (c.ts_node_is_null(name)) return error.UnsupportedModuleForm;
                if (p.declaration(p.text(name)) == null) try p.declarations.append(p.gpa, .{ .name = p.text(name), .kind = .class, .name_range = range(name), .statement = range(value), .value = null });
                try p.addExport("default", p.text(name), .class);
                try p.erase(.{ .start = range(n).start, .end = range(value).start }); return;
            }
            const expression = unwrapped(value);
            if (any(expression, &.{ "arrow_function", "function_expression", "class" })) return error.UnsupportedModuleForm;
            try p.addExport("default", "_default", .constant);
            try p.edit(.{ .start = range(n).start, .end = range(value).start }, "var _default = exports[\"default\"] = (");
            try p.edit(.{ .start = range(value).end, .end = range(value).end }, ");"); return;
        }
        if (!c.ts_node_is_null(value)) {
            if (any(value, &.{ "lexical_declaration", "variable_declaration" })) for (0..c.ts_node_named_child_count(value)) |index| {
                const child = c.ts_node_named_child(value, @intCast(index));
                if (is(child, "variable_declarator") and !is(field(child, "name"), "identifier")) return error.UnsupportedModuleBinding;
            };
            var found = false;
            for (p.declarations.items) |d| if (d.statement.start == range(value).start and d.statement.end == range(value).end) {
                try p.addExport(d.name, d.name, d.kind); found = true;
            };
            if (!found) return error.UnsupportedModuleForm;
            try p.erase(.{ .start = range(n).start, .end = range(value).start }); return;
        }
        var clause: ?c.TSNode = null;
        for (0..c.ts_node_named_child_count(n)) |index| { const child = c.ts_node_named_child(n, @intCast(index)); if (is(child, "export_clause")) clause = child; }
        const list = clause orelse return error.UnsupportedModuleForm;
        for (0..c.ts_node_named_child_count(list)) |index| {
            const spec = c.ts_node_named_child(list, @intCast(index)); if (is(spec, "comment")) continue;
            if (!is(spec, "export_specifier") or std.mem.startsWith(u8, p.text(spec), "type ")) return error.UnsupportedModuleForm;
            const name = field(spec, "name"); const alias = field(spec, "alias");
            if (!is(name, "identifier") or (!c.ts_node_is_null(alias) and !is(alias, "identifier"))) return error.UnsupportedModuleIdentifier;
            const d = p.declaration(p.text(name)) orelse return error.MissingModuleExportBinding;
            try p.addExport(if (c.ts_node_is_null(alias)) d.name else p.text(alias), d.name, d.kind);
        }
        try p.erase(range(n));
    }
    fn binding(p: *Plan, n: c.TSNode, depth: usize) Error!void {
        if (depth > 256) return error.TypeScriptNestingLimit;
        if (any(n, &.{ "identifier", "type_identifier", "shorthand_property_identifier_pattern" })) {
            const name = p.text(n); if (!identifier(name) or reserved(name)) return error.UnsupportedModuleBinding;
            if (p.imported(name) != null) return error.UnsupportedModuleBindingShadow;
            if (p.exported(name)) {
                const d = p.declaration(name) orelse return error.UnsupportedModuleBindingShadow;
                const r = range(n); if (r.start != d.name_range.start or r.end != d.name_range.end) return error.UnsupportedModuleBindingShadow;
            }
            return;
        }
        if (any(n, &.{ "required_parameter", "optional_parameter", "rest_pattern" })) { var pattern = field(n, "pattern"); if (c.ts_node_is_null(pattern)) pattern = field(n, "name"); if (!c.ts_node_is_null(pattern)) return p.binding(pattern, depth + 1); }
        if (any(n, &.{ "assignment_pattern", "object_assignment_pattern" })) { return p.binding(field(n, "left"), depth + 1); }
        if (is(n, "pair_pattern")) return p.binding(field(n, "value"), depth + 1);
        for (0..c.ts_node_named_child_count(n)) |index| try p.binding(c.ts_node_named_child(n, @intCast(index)), depth + 1);
    }
    fn writeTarget(p: *Plan, n: c.TSNode, depth: usize) Error!void {
        if (depth > 256) return error.TypeScriptNestingLimit;
        if (any(n, &.{ "member_expression", "subscript_expression" })) return;
        if (any(n, &.{ "identifier", "shorthand_property_identifier_pattern" })) {
            if (p.imported(p.text(n)) != null or p.exported(p.text(n))) return error.UnsupportedModuleWrite;
            return;
        }
        if (is(n, "pair_pattern")) return p.writeTarget(field(n, "value"), depth + 1);
        if (any(n, &.{ "assignment_pattern", "object_assignment_pattern" })) return p.writeTarget(field(n, "left"), depth + 1);
        for (0..c.ts_node_named_child_count(n)) |index| try p.writeTarget(c.ts_node_named_child(n, @intCast(index)), depth + 1);
    }
    fn reference(p: *Plan, n: c.TSNode) Error!void {
        const index = p.imported(p.text(n)) orelse return;
        p.imports.items[index].used = true;
        const imported = p.imports.items[index];
        const replacement = if (is(n, "shorthand_property_identifier"))
            try std.fmt.allocPrint(p.gpa, "{s}: (0, __pi_cjs_import_{d}[\"{s}\"])", .{ imported.local, imported.source, imported.name })
        else try std.fmt.allocPrint(p.gpa, "(0, __pi_cjs_import_{d}[\"{s}\"])", .{ imported.source, imported.name });
        defer p.gpa.free(replacement); try p.edit(range(n), replacement);
    }
    fn walk(p: *Plan, n: c.TSNode, depth: usize, function_depth: usize) Error!void {
        if (depth > 256) return error.TypeScriptNestingLimit;
        if (is(n, "import_statement") or is(n, "export_clause")) return;
        if (is(n, "export_statement")) {
            var value = field(n, "declaration"); if (c.ts_node_is_null(value)) value = field(n, "value");
            if (!c.ts_node_is_null(value)) try p.walk(value, depth + 1, function_depth); return;
        }
        if (any(n, &.{ "identifier", "type_identifier" }) and (!identifier(p.text(n)) or std.mem.startsWith(u8, p.text(n), "__pi_cjs_") or std.mem.eql(u8, p.text(n), "_default"))) return error.UnsupportedModuleIdentifier;
        if (is(n, "meta_property") or is(n, "with_statement")) return error.UnsupportedModuleEvaluation;
        if (function_depth == 0 and is(n, "return_statement")) return error.UnsupportedModuleEvaluation;
        if (function_depth == 0 and is(n, "await_expression") and !p.options.async_mode) return error.UnsupportedModuleEvaluation;
        if (is(n, "call_expression")) {
            const callee = unwrapped(field(n, "function"));
            if (is(callee, "import") or (is(callee, "identifier") and std.mem.eql(u8, p.text(callee), "eval"))) return error.UnsupportedModuleEvaluation;
        }
        if (any(n, &.{ "assignment_expression", "augmented_assignment_expression" })) try p.writeTarget(field(n, "left"), 0);
        if (is(n, "unary_expression") and hasToken(n, "delete")) {
            const argument = unwrapped(field(n, "argument"));
            if (is(argument, "identifier")) return error.UnsupportedModuleEvaluation;
        }
        if (is(n, "update_expression")) try p.writeTarget(field(n, "argument"), 0);
        if (is(n, "for_in_statement")) try p.writeTarget(field(n, "left"), 0);
        if (is(n, "variable_declarator")) try p.binding(field(n, "name"), 0);
        if (any(n, &.{ "function_declaration", "generator_function_declaration", "function_expression", "generator_function", "class", "class_declaration" })) {
            const name = field(n, "name"); if (!c.ts_node_is_null(name)) try p.binding(name, 0);
        }
        if (is(n, "formal_parameters")) try p.binding(n, 0);
        if (is(n, "arrow_function")) { const parameter = field(n, "parameter"); if (!c.ts_node_is_null(parameter)) try p.binding(parameter, 0); }
        if (is(n, "catch_clause")) { const parameter = field(n, "parameter"); if (!c.ts_node_is_null(parameter)) try p.binding(parameter, 0); }
        if (is(n, "identifier")) {
            const parent = c.ts_node_parent(n);
            // Binding identifiers were checked above and are never rewritten.
            if (!isBindingIdentifier(n, parent)) try p.reference(n);
        } else if (is(n, "shorthand_property_identifier")) try p.reference(n);
        const function_node = any(n, &.{ "function_declaration", "generator_function_declaration", "function_expression", "generator_function", "arrow_function" });
        for (0..c.ts_node_named_child_count(n)) |index| {
            const child = c.ts_node_named_child(n, @intCast(index));
            // Computed method names run in the surrounding evaluation scope.
            const method_body = is(n, "method_definition") and (same(child, field(n, "parameters")) or same(child, field(n, "body")));
            try p.walk(child, depth + 1, function_depth + @as(usize, @intFromBool(function_node or method_body)));
        }
    }
    fn initializeExports(p: *Plan) Error!void {
        for (p.declarations.items) |d| {
            if (!p.exported(d.name) or d.kind == .function) continue;
            var prefix: std.Io.Writer.Allocating = .init(p.gpa); defer prefix.deinit();
            // Source buildInitStatement reduces aliases into outer assignments.
            var index = p.exports.items.len;
            while (index > 0) { index -= 1; const e = p.exports.items[index]; if (std.mem.eql(u8, e.local, d.name)) try prefix.writer.print("exports[\"{s}\"] = ", .{e.name}); }
            if (d.kind == .constant and d.late_init) {
                for (p.declarations.items) |other| if (other.name_range.start != d.name_range.start and other.statement.start == d.statement.start and other.late_init and p.exported(other.name)) return error.UnsupportedModuleForm;
                const statement = try std.fmt.allocPrint(p.gpa, ";{s}{s};", .{ prefix.written(), d.name }); defer p.gpa.free(statement);
                try p.edit(.{ .start = d.statement.end, .end = d.statement.end }, statement);
            } else if (d.kind == .constant) {
                const value = d.value orelse return error.UnsupportedModuleForm;
                try prefix.writer.writeByte('('); try p.edit(.{ .start = value.start, .end = value.start }, prefix.written());
                try p.edit(.{ .start = value.end, .end = value.end }, ")");
            } else if (d.kind == .class) {
                const statement = try std.fmt.allocPrint(p.gpa, ";{s}{s};", .{ prefix.written(), d.name }); defer p.gpa.free(statement);
                try p.edit(.{ .start = d.statement.end, .end = d.statement.end }, statement);
            }
        }
    }
    fn emit(p: *Plan) Error![]u8 {
        var output: std.Io.Writer.Allocating = .init(p.gpa); defer output.deinit();
        try output.writer.writeAll("\"use strict\";Object.defineProperty(exports,\"__esModule\",{value:true});");
        var header_entries: std.ArrayList(Export) = .empty; defer header_entries.deinit(p.gpa);
        for (p.exports.items, 0..) |e, index| {
            if (e.kind == .function) {
                var repeated = false;
                for (p.exports.items[0..index]) |previous| if (std.mem.eql(u8, previous.local, e.local)) { repeated = true; break; };
                if (repeated) continue;
            }
            try header_entries.append(p.gpa, e);
        }
        std.mem.sort(Export, header_entries.items, {}, struct { fn less(_: void, a: Export, b: Export) bool { return std.mem.order(u8, a.name, b.name) == .lt; } }.less);
        var pending: std.ArrayList([]const u8) = .empty; defer pending.deinit(p.gpa);
        for (header_entries.items, 0..) |e, entry_index| {
            if (e.kind == .function) {
                try flush(&output.writer, pending.items); pending.clearRetainingCapacity();
                var alias_index = p.exports.items.len;
                while (alias_index > 0) { alias_index -= 1; const alias = p.exports.items[alias_index]; if (std.mem.eql(u8, alias.local, e.local)) try output.writer.print("exports[\"{s}\"]=", .{alias.name}); }
                try output.writer.print("{s};", .{e.local});
            } else try pending.append(p.gpa, e.name);
            if ((entry_index + 1) % 100 == 0) { try flush(&output.writer, pending.items); pending.clearRetainingCapacity(); }
        }
        try flush(&output.writer, pending.items);
        for (p.import_statements.items) |statement| {
            var active = statement.side_effect; var named = false;
            for (p.imports.items) |i| if (i.statement.start == statement.range.start and (!p.options.typescript or i.used)) { active = true; named = true; };
            if (active) { const src = &p.sources.items[statement.source]; src.active_start = @min(src.active_start, statement.range.start); src.named = src.named or named; }
        }
        const ordering = try p.gpa.alloc(usize, p.sources.items.len); defer p.gpa.free(ordering);
        for (ordering, 0..) |*entry, index| entry.* = index;
        std.mem.sort(usize, ordering, p.sources.items, struct { fn less(sources: []Source, a: usize, b: usize) bool { return sources[a].active_start < sources[b].active_start; } }.less);
        for (ordering) |index| { const src = p.sources.items[index]; if (src.active_start == std.math.maxInt(usize)) continue;
            if (src.named) try output.writer.print("var __pi_cjs_import_{d}=", .{index});
            try output.writer.print("{s}({s});", .{ if (p.options.async_mode) "await jitiImport" else "require", src.literal });
        }
        std.mem.sort(Edit, p.edits.items, {}, struct { fn less(_: void, a: Edit, b: Edit) bool { return a.range.start < b.range.start or (a.range.start == b.range.start and a.range.end < b.range.end); } }.less);
        var offset: usize = 0;
        for (p.edits.items) |e| { if (e.range.start < offset) return error.OverlappingModuleEdit; try output.writer.writeAll(p.source[offset..e.range.start]); try output.writer.writeAll(e.text); offset = e.range.end; }
        try output.writer.writeAll(p.source[offset..]); return output.toOwnedSlice();
    }
};
fn flush(writer: *std.Io.Writer, names: []const []const u8) Error!void {
    if (names.len == 0) return; var index = names.len;
    while (index > 0) { index -= 1; try writer.print("exports[\"{s}\"]=", .{names[index]}); }
    try writer.writeAll("void 0;");
}
fn hasToken(n: c.TSNode, token: []const u8) bool { for (0..c.ts_node_child_count(n)) |index| if (is(c.ts_node_child(n, @intCast(index)), token)) return true; return false; }
fn anonymousInitializer(input: c.TSNode) bool {
    const n = unwrapped(input);
    return is(n, "arrow_function") or (any(n, &.{ "function_expression", "generator_function", "class" }) and c.ts_node_is_null(field(n, "name")));
}
fn unwrapped(input: c.TSNode) c.TSNode {
    var n = input;
    while (is(n, "parenthesized_expression")) {
        var only: ?c.TSNode = null;
        for (0..c.ts_node_named_child_count(n)) |index| {
            const child = c.ts_node_named_child(n, @intCast(index));
            if (is(child, "comment")) continue;
            if (only != null) return n;
            only = child;
        }
        n = only orelse return n;
    }
    return n;
}
fn same(a: c.TSNode, b: c.TSNode) bool { return !c.ts_node_is_null(a) and !c.ts_node_is_null(b) and range(a).start == range(b).start and range(a).end == range(b).end; }
fn isBindingIdentifier(n: c.TSNode, parent: c.TSNode) bool {
    if (any(parent, &.{ "variable_declarator", "function_declaration", "generator_function_declaration", "function_expression", "generator_function", "class", "class_declaration" }) and same(n, field(parent, "name"))) return true;
    if (any(parent, &.{ "required_parameter", "optional_parameter", "rest_pattern" }) and (same(n, field(parent, "pattern")) or same(n, field(parent, "name")))) return true;
    if (is(parent, "arrow_function") and same(n, field(parent, "parameter"))) return true;
    if (is(parent, "catch_clause") and same(n, field(parent, "parameter"))) return true;
    if (any(parent, &.{ "assignment_pattern", "object_assignment_pattern" })) return same(n, field(parent, "left"));
    if (is(parent, "pair_pattern")) return same(n, field(parent, "value"));
    return any(parent, &.{ "array_pattern", "object_pattern" });
}
fn originalPreflight(n: c.TSNode, source: []const u8, options: Options, depth: usize) Error!void {
    if (depth > 256) return error.TypeScriptNestingLimit;
    if (any(n, &.{ "identifier", "type_identifier", "statement_identifier" })) {
        const r = range(n); const text = source[r.start..r.end];
        if (!identifier(text) or std.mem.eql(u8, text, "_default") or std.mem.startsWith(u8, text, "__pi_cjs_")) return error.UnsupportedModuleIdentifier;
    }
    if (any(n, &.{ "enum_declaration", "internal_module", "import_alias", "export_assignment", "decorator", "using_declaration", "jsx_element", "jsx_self_closing_element", "jsx_fragment" })) return error.UnsupportedModuleRuntimeSyntax;
    if (any(n, &.{ "type_assertion", "asserts_annotation", "type_predicate_annotation" })) return error.UnsupportedModuleRuntimeSyntax;
    if (!options.typescript and any(n, &.{ "type_annotation", "type_arguments", "type_parameters", "interface_declaration", "type_alias_declaration", "ambient_declaration", "as_expression", "satisfies_expression", "non_null_expression", "optional_parameter", "accessibility_modifier", "override_modifier", "implements_clause", "function_signature", "abstract_method_signature" })) return error.UnsupportedModuleRuntimeSyntax;
    if (!options.typescript and any(n, &.{ "import_statement", "import_specifier", "export_statement", "export_specifier" }) and hasToken(n, "type")) return error.UnsupportedModuleRuntimeSyntax;
    if (!options.typescript and any(n, &.{ "class", "class_declaration", "method_definition", "public_field_definition" }) and (hasToken(n, "abstract") or hasToken(n, "readonly") or hasToken(n, "?") or hasToken(n, "!"))) return error.UnsupportedModuleRuntimeSyntax;
    if (options.typescript and is(n, "import_specifier")) {
        const name = range(field(n, "name"));
        if (std.mem.eql(u8, source[name.start..name.end], "type")) return error.UnsupportedModuleImport;
    }
    if (any(n, &.{ "required_parameter", "optional_parameter" }) and (hasToken(n, "readonly") or hasToken(n, "override_modifier"))) return error.UnsupportedModuleRuntimeSyntax;
    if (any(n, &.{ "required_parameter", "optional_parameter" })) for (0..c.ts_node_named_child_count(n)) |index| if (is(c.ts_node_named_child(n, @intCast(index)), "accessibility_modifier")) return error.UnsupportedModuleRuntimeSyntax;
    if (is(n, "public_field_definition") and (hasToken(n, "declare") or hasToken(n, "abstract"))) return error.UnsupportedModuleRuntimeSyntax;
    for (0..c.ts_node_named_child_count(n)) |index| try originalPreflight(c.ts_node_named_child(n, @intCast(index)), source, options, depth + 1);
}
fn typeOnlySpecifiers(n: c.TSNode, source: []const u8) bool {
    if (is(n, "import_specifier")) {
        return hasToken(n, "type");
    }
    var found = false;
    for (0..c.ts_node_named_child_count(n)) |index| {
        const child = c.ts_node_named_child(n, @intCast(index));
        if (is(child, "comment") or is(child, "string")) continue;
        if (any(child, &.{ "identifier", "namespace_import", "import_require_clause" })) return false;
        if (is(child, "import_specifier")) { if (!typeOnlySpecifiers(child, source)) return false; found = true; }
        else if (any(child, &.{ "import_clause", "named_imports" })) { if (!typeOnlySpecifiers(child, source)) return false; found = true; }
    }
    return found;
}
pub fn lower(gpa: std.mem.Allocator, input: []const u8, options: Options) Error![]u8 {
    // Every writer in this lowering path is memory-backed Allocating; its
    // WriteFailed is allocator failure, never an ordinary user/module error.
    return lowerValue(gpa, input, options) catch |err| return if (err == error.WriteFailed) error.OutOfMemory else err;
}
fn lowerValue(gpa: std.mem.Allocator, input: []const u8, options: Options) Error![]u8 {
    if (input.len > 16 * 1024 * 1024) return error.ExtensionSourceTooLarge;
    const parser = c.ts_parser_new() orelse return error.OutOfMemory; defer c.ts_parser_delete(parser);
    if (!c.ts_parser_set_language(parser, tree_sitter_typescript())) return error.TypeScriptParserAbiMismatch;
    const original = c.ts_parser_parse_string(parser, null, input.ptr, @intCast(input.len)) orelse return error.TypeScriptParseFailed; defer c.ts_tree_delete(original);
    if (c.ts_node_has_error(c.ts_tree_root_node(original))) return error.InvalidTypeScriptInput;
    try originalPreflight(c.ts_tree_root_node(original), input, options, 0);
    const source = if (options.typescript) try ts.transform(gpa, input) else try gpa.dupe(u8, input); defer gpa.free(source);
    if (source.len != input.len) return error.UnsupportedModuleRuntimeSyntax;
    const tree = c.ts_parser_parse_string(parser, null, source.ptr, @intCast(source.len)) orelse return error.TypeScriptParseFailed; defer c.ts_tree_delete(tree);
    const root = c.ts_tree_root_node(tree); if (c.ts_node_has_error(root)) return error.InvalidTypeScriptInput;
    var plan: Plan = .{ .gpa = gpa, .source = source, .original = input, .original_root = c.ts_tree_root_node(original), .options = options }; defer plan.deinit();
    if (std.mem.startsWith(u8, source, "#!")) try plan.edit(.{ .start = 0, .end = 0 }, "// ");
    for (0..c.ts_node_named_child_count(root)) |index| { const n = c.ts_node_named_child(root, @intCast(index)); const d = if (is(n, "export_statement")) field(n, "declaration") else n; if (!c.ts_node_is_null(d)) try plan.addDecl(d); }
    for (0..c.ts_node_named_child_count(root)) |index| { const n = c.ts_node_named_child(root, @intCast(index)); if (is(n, "import_statement")) try plan.importStatement(n); }
    for (0..c.ts_node_named_child_count(root)) |index| { const n = c.ts_node_named_child(root, @intCast(index)); if (is(n, "export_statement")) try plan.exportStatement(n); }
    if (plan.exports.items.len == 0) return error.UnsupportedModuleForm;
    try plan.walk(root, 0, 0); try plan.initializeExports(); return plan.emit();
}
