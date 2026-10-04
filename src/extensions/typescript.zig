//! Transform user-authored extension input using a C syntax tree and Zig edits.
//! Host logic is Zig; no TypeScript compiler or JavaScript transformer is used.
const std = @import("std");
const c = @cImport({
    @cInclude("tree_sitter/api.h");
});
extern fn tree_sitter_typescript() ?*const c.TSLanguage;

pub const TransformError = error{
    OutOfMemory,
    WriteFailed,
    TypeScriptNestingLimit,
    UnsupportedTypeScriptEnumName,
    TypeScriptRuntimeSyntaxRequiresLowering,
    ExtensionSourceTooLarge,
    TypeScriptParserAbiMismatch,
    TypeScriptParseFailed,
    InvalidTypeScriptInput,
    OverlappingTypeScriptReplacement,
    UnsupportedTypeScriptParameterProperty,
};

const Range = struct { start: usize, end: usize };
const Replacement = struct { range: Range, text: []u8 };

const Transformer = struct {
    gpa: std.mem.Allocator,
    source: []const u8,
    output: []u8,
    replacements: std.ArrayList(Replacement) = .empty,

    fn deinit(self: *Transformer) void {
        for (self.replacements.items) |replacement| self.gpa.free(replacement.text);
        self.replacements.deinit(self.gpa);
    }

    fn lowerEnum(self: *Transformer, node: c.TSNode) !void {
        const name_node = c.ts_node_child_by_field_name(node, "name", 4);
        const name_range = nodeRange(name_node);
        const name = self.source[name_range.start..name_range.end];
        const body = c.ts_node_child_by_field_name(node, "body", 4);
        var generated: std.Io.Writer.Allocating = .init(self.gpa);
        defer generated.deinit();
        const writer = &generated.writer;
        const temporary = try std.fmt.allocPrint(self.gpa, "__pi_enum_{x}", .{std.hash.Wyhash.hash(nodeRange(node).start, self.source)});
        defer self.gpa.free(temporary);
        try writer.print("var {s}; (function ({s}) {{ let {s}_next = 0; let {s}_value;", .{ name, name, temporary, temporary });
        var index: u32 = 0;
        while (index < c.ts_node_named_child_count(body)) : (index += 1) {
            const member = c.ts_node_named_child(body, index);
            if (std.mem.eql(u8, nodeKind(member), "comment")) continue;
            const assignment = std.mem.eql(u8, nodeKind(member), "enum_assignment");
            const member_name = if (assignment) c.ts_node_child_by_field_name(member, "name", 4) else member;
            const member_range = nodeRange(member_name);
            const member_text = self.source[member_range.start..member_range.end];
            var key: std.Io.Writer.Allocating = .init(self.gpa);
            defer key.deinit();
            if (std.mem.eql(u8, nodeKind(member_name), "string")) {
                try key.writer.writeAll(member_text);
            } else if (std.mem.eql(u8, nodeKind(member_name), "property_identifier")) {
                try std.json.Stringify.value(member_text, .{}, &key.writer);
            } else return error.UnsupportedTypeScriptEnumName;
            if (assignment) {
                const value_node = c.ts_node_child_by_field_name(member, "value", 5);
                const value_range = nodeRange(value_node);
                const value = try transform(self.gpa, self.source[value_range.start..value_range.end]);
                defer self.gpa.free(value);
                try writer.print("{s}_value = ({s});", .{ temporary, value });
            } else {
                try writer.print("{s}_value = {s}_next;", .{ temporary, temporary });
            }
            try writer.print("{s}[{s}] = {s}_value; if (typeof {s}_value === 'number') {{ {s}[{s}_value] = {s}; {s}_next = {s}_value + 1; }} else {{ {s}_next = undefined; }}", .{ name, key.written(), temporary, temporary, name, temporary, key.written(), temporary, temporary, temporary });
            // Lexical member aliases retain references to earlier enum members
            // in ordinary initializers (for example B = A + 1).
            if (std.mem.eql(u8, nodeKind(member_name), "property_identifier") and !isAny(member_text, &.{ "default", "class", "function", "var", "let", "const", "new", "return", "case", "delete", "typeof", "void", "yield", "await", "enum", "export", "import", "null", "true", "false" })) {
                try writer.print("const {s} = {s}_value;", .{ member_text, temporary });
            }
        }
        try writer.print("}})({s} || ({s} = {{}}));", .{ name, name });
        const text = try generated.toOwnedSlice();
        errdefer self.gpa.free(text);
        try self.replacements.append(self.gpa, .{ .range = nodeRange(node), .text = text });
    }

    fn lowerParameterProperties(self: *Transformer, constructor: c.TSNode) !void {
        const parameters = c.ts_node_child_by_field_name(constructor, "parameters", 10);
        const body = c.ts_node_child_by_field_name(constructor, "body", 4);
        if (c.ts_node_is_null(parameters) or c.ts_node_is_null(body)) return;
        var assignments: std.Io.Writer.Allocating = .init(self.gpa);
        defer assignments.deinit();
        var index: u32 = 0;
        while (index < c.ts_node_named_child_count(parameters)) : (index += 1) {
            const parameter = c.ts_node_named_child(parameters, index);
            var property = false;
            var child_index: u32 = 0;
            while (child_index < c.ts_node_child_count(parameter)) : (child_index += 1) {
                const child = c.ts_node_child(parameter, child_index);
                if (isAny(nodeKind(child), &.{ "accessibility_modifier", "readonly", "override_modifier" })) property = true;
            }
            if (!property) continue;
            const name_node = c.ts_node_child_by_field_name(parameter, "pattern", 7);
            if (!std.mem.eql(u8, nodeKind(name_node), "identifier")) return error.UnsupportedTypeScriptParameterProperty;
            const name_range = nodeRange(name_node);
            const name = self.source[name_range.start..name_range.end];
            try assignments.writer.writeAll("this[");
            try std.json.Stringify.value(name, .{}, &assignments.writer);
            try assignments.writer.print("] = {s};", .{name});
        }
        if (assignments.written().len == 0) return;
        var insertion = nodeRange(body).start + 1;
        const class_node = c.ts_node_parent(c.ts_node_parent(constructor));
        var derived = false;
        index = 0;
        while (index < c.ts_node_named_child_count(class_node)) : (index += 1) {
            if (std.mem.eql(u8, nodeKind(c.ts_node_named_child(class_node, index)), "class_heritage")) derived = true;
        }
        if (derived) {
            var found_super = false;
            index = 0;
            while (index < c.ts_node_named_child_count(body)) : (index += 1) {
                const statement = c.ts_node_named_child(body, index);
                if (!std.mem.eql(u8, nodeKind(statement), "expression_statement")) continue;
                const expression = c.ts_node_named_child(statement, 0);
                const function = c.ts_node_child_by_field_name(expression, "function", 8);
                if (std.mem.eql(u8, nodeKind(expression), "call_expression") and std.mem.eql(u8, nodeKind(function), "super")) {
                    insertion = nodeRange(statement).end;
                    found_super = true;
                    break;
                }
            }
            if (!found_super) return error.UnsupportedTypeScriptParameterProperty;
        }
        const text = try assignments.toOwnedSlice();
        errdefer self.gpa.free(text);
        try self.replacements.append(self.gpa, .{ .range = .{ .start = insertion, .end = insertion }, .text = text });
    }

    fn erase(self: *Transformer, range: Range) void {
        for (self.output[range.start..range.end]) |*byte| {
            if (byte.* != '\r' and byte.* != '\n') byte.* = ' ';
        }
    }

    fn eraseItem(self: *Transformer, node: c.TSNode) void {
        var range = nodeRange(node);
        var next = range.end;
        while (next < self.source.len and std.ascii.isWhitespace(self.source[next])) : (next += 1) {}
        if (next < self.source.len and self.source[next] == ',') {
            range.end = next + 1;
        } else {
            var previous = range.start;
            while (previous > 0 and std.ascii.isWhitespace(self.source[previous - 1])) : (previous -= 1) {}
            if (previous > 0 and self.source[previous - 1] == ',') range.start = previous - 1;
        }
        self.erase(range);
    }

    fn walk(self: *Transformer, node: c.TSNode, depth: usize) !void {
        if (depth > 512) return error.TypeScriptNestingLimit;
        const kind = nodeKind(node);
        const range = nodeRange(node);
        const text = self.source[range.start..range.end];
        if (std.mem.eql(u8, kind, "method_definition")) {
            const name_node = c.ts_node_child_by_field_name(node, "name", 4);
            const name_range = nodeRange(name_node);
            if (std.mem.eql(u8, self.source[name_range.start..name_range.end], "constructor")) try self.lowerParameterProperties(node);
        }
        if (isAny(kind, &.{ "type_annotation", "type_arguments", "type_parameters", "accessibility_modifier", "override_modifier", "implements_clause" })) {
            self.erase(range);
            return;
        }
        if (isAny(kind, &.{ "interface_declaration", "type_alias_declaration", "ambient_declaration", "function_signature", "abstract_method_signature" })) {
            const parent = c.ts_node_parent(node);
            self.erase(if (std.mem.eql(u8, nodeKind(parent), "export_statement")) nodeRange(parent) else range);
            return;
        }
        if ((std.mem.eql(u8, kind, "import_statement") and startsWithWords(text, "import", "type")) or
            (std.mem.eql(u8, kind, "export_statement") and startsWithWords(text, "export", "type")))
        {
            self.erase(range);
            return;
        }
        if (std.mem.eql(u8, kind, "import_specifier") and startsWithWord(text, "type")) {
            self.eraseItem(node);
            return;
        }
        if (isAny(kind, &.{ "as_expression", "satisfies_expression" })) {
            const expression = c.ts_node_named_child(node, 0);
            self.erase(.{ .start = nodeRange(expression).end, .end = range.end });
            try self.walk(expression, depth + 1);
            return;
        }
        if (std.mem.eql(u8, kind, "non_null_expression")) {
            self.erase(.{ .start = range.end - 1, .end = range.end });
        }
        if (std.mem.eql(u8, kind, "enum_declaration")) {
            try self.lowerEnum(node);
            return;
        }
        if (isAny(kind, &.{ "internal_module", "import_alias", "export_assignment", "decorator" })) {
            // These emit runtime code, so never pretend type erasure is enough.
            return error.TypeScriptRuntimeSyntaxRequiresLowering;
        }
        if (isAny(kind, &.{ "required_parameter", "optional_parameter" })) {
            var modifier_index: u32 = 0;
            while (modifier_index < c.ts_node_child_count(node)) : (modifier_index += 1) {
                const child = c.ts_node_child(node, modifier_index);
                if (isAny(nodeKind(child), &.{ "accessibility_modifier", "readonly", "override_modifier" })) {
                    const constructor = c.ts_node_parent(c.ts_node_parent(node));
                    const name = c.ts_node_child_by_field_name(constructor, "name", 4);
                    const name_range = nodeRange(name);
                    if (!std.mem.eql(u8, nodeKind(constructor), "method_definition") or
                        !std.mem.eql(u8, self.source[name_range.start..name_range.end], "constructor")) return error.UnsupportedTypeScriptParameterProperty;
                    self.erase(nodeRange(child));
                }
            }
            const pattern = c.ts_node_child_by_field_name(node, "pattern", 7);
            if (!c.ts_node_is_null(pattern) and std.mem.eql(u8, nodeKind(pattern), "this")) {
                self.eraseItem(node);
                return;
            }
            var index: u32 = 0;
            while (index < c.ts_node_child_count(node)) : (index += 1) {
                const child = c.ts_node_child(node, index);
                if (std.mem.eql(u8, nodeKind(child), "?")) self.erase(nodeRange(child));
            }
        }
        if (std.mem.eql(u8, kind, "public_field_definition")) {
            var index: u32 = 0;
            while (index < c.ts_node_child_count(node)) : (index += 1) {
                const child = c.ts_node_child(node, index);
                if (isAny(nodeKind(child), &.{ "?", "!", "readonly", "declare", "abstract" })) self.erase(nodeRange(child));
            }
        }
        if (std.mem.eql(u8, kind, "abstract")) {
            self.erase(range);
            return;
        }
        var index: u32 = 0;
        while (index < c.ts_node_named_child_count(node)) : (index += 1) {
            try self.walk(c.ts_node_named_child(node, index), depth + 1);
        }
    }
};

fn nodeKind(node: c.TSNode) []const u8 {
    if (c.ts_node_is_null(node)) return "";
    return std.mem.span(c.ts_node_type(node));
}

fn nodeRange(node: c.TSNode) Range {
    return .{ .start = c.ts_node_start_byte(node), .end = c.ts_node_end_byte(node) };
}

fn isAny(value: []const u8, options: []const []const u8) bool {
    for (options) |option| if (std.mem.eql(u8, value, option)) return true;
    return false;
}

fn startsWithWord(text: []const u8, word: []const u8) bool {
    if (!std.mem.startsWith(u8, text, word)) return false;
    return text.len == word.len or std.ascii.isWhitespace(text[word.len]) or text[word.len] == '{';
}

fn startsWithWords(text: []const u8, first: []const u8, second: []const u8) bool {
    if (!startsWithWord(text, first)) return false;
    return startsWithWord(std.mem.trimStart(u8, text[first.len..], " \t\r\n"), second);
}

pub fn transform(gpa: std.mem.Allocator, source: []const u8) TransformError![]u8 {
    if (source.len > 16 * 1024 * 1024) return error.ExtensionSourceTooLarge;
    const parser = c.ts_parser_new() orelse return error.OutOfMemory;
    defer c.ts_parser_delete(parser);
    if (!c.ts_parser_set_language(parser, tree_sitter_typescript())) return error.TypeScriptParserAbiMismatch;
    const tree = c.ts_parser_parse_string(parser, null, source.ptr, @intCast(source.len)) orelse return error.TypeScriptParseFailed;
    defer c.ts_tree_delete(tree);
    const root = c.ts_tree_root_node(tree);
    if (c.ts_node_has_error(root)) return error.InvalidTypeScriptInput;
    const output = try gpa.dupe(u8, source);
    errdefer gpa.free(output);
    var transformer: Transformer = .{ .gpa = gpa, .source = source, .output = output };
    defer transformer.deinit();
    try transformer.walk(root, 0);
    if (transformer.replacements.items.len > 0) {
        std.mem.sort(Replacement, transformer.replacements.items, {}, struct {
            fn lessThan(_: void, a: Replacement, b: Replacement) bool {
                return a.range.start < b.range.start;
            }
        }.lessThan);
        var generated: std.ArrayList(u8) = .empty;
        errdefer generated.deinit(gpa);
        var offset: usize = 0;
        for (transformer.replacements.items) |replacement| {
            if (replacement.range.start < offset) return error.OverlappingTypeScriptReplacement;
            try generated.appendSlice(gpa, output[offset..replacement.range.start]);
            try generated.appendSlice(gpa, replacement.text);
            offset = replacement.range.end;
        }
        try generated.appendSlice(gpa, output[offset..]);
        const complete = try generated.toOwnedSlice(gpa);
        gpa.free(output);
        return complete;
    }
    return output;
}

fn esmSyntax(node: c.TSNode, source: []const u8, top_level: bool, depth: usize) TransformError!bool {
    if (depth > 128) return error.TypeScriptNestingLimit;
    const kind = nodeKind(node);
    if (isAny(kind, &.{ "import_statement", "export_statement" })) return true;
    if (std.mem.eql(u8, kind, "meta_property")) {
        const range = nodeRange(node);
        if (std.mem.eql(u8, source[range.start..range.end], "import.meta")) return true;
    }
    if (top_level and std.mem.eql(u8, kind, "await_expression")) return true;
    const children_top_level = top_level and !isAny(kind, &.{ "function_declaration", "function_expression", "generator_function_declaration", "generator_function", "arrow_function", "method_definition" });
    var index: u32 = 0;
    while (index < c.ts_node_named_child_count(node)) : (index += 1) {
        if (try esmSyntax(c.ts_node_named_child(node, index), source, children_top_level, depth + 1)) return true;
    }
    return false;
}

pub fn hasModuleSyntax(source: []const u8) TransformError!bool {
    if (source.len > 16 * 1024 * 1024) return error.ExtensionSourceTooLarge;
    const parser = c.ts_parser_new() orelse return error.OutOfMemory;
    defer c.ts_parser_delete(parser);
    if (!c.ts_parser_set_language(parser, tree_sitter_typescript())) return error.TypeScriptParserAbiMismatch;
    const tree = c.ts_parser_parse_string(parser, null, source.ptr, @intCast(source.len)) orelse return error.TypeScriptParseFailed;
    defer c.ts_tree_delete(tree);
    const root = c.ts_tree_root_node(tree);
    if (c.ts_node_has_error(root)) return error.InvalidTypeScriptInput;
    return esmSyntax(root, source, true, 0);
}

test "native module syntax detection distinguishes imports meta and top-level await from CommonJS" {
    try std.testing.expect(try hasModuleSyntax("export const answer=42;"));
    try std.testing.expect(try hasModuleSyntax("const url=import.meta.url;"));
    try std.testing.expect(try hasModuleSyntax("await Promise.resolve();"));
    try std.testing.expect(try hasModuleSyntax("function nested(){return import.meta.url;}"));
    try std.testing.expect(!try hasModuleSyntax("module.exports=async function(){await Promise.resolve();return 'export default';};"));
    try std.testing.expect(!try hasModuleSyntax("const input=require('./data.json'); exports.value=input.value;"));
}

test "native input transform erases types without changing strings or object fields" {
    const source = "interface Message { value: number }\r\ntype Id = string;\r\nconst message: Message = {value: 42}; const text = 'as Message: number'; const obj = {as: text}; message.value satisfies number;\r\n";
    const output = try transform(std.testing.allocator, source);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqual(source.len, output.len);
    try std.testing.expect(std.mem.indexOf(u8, output, "'as Message: number'") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "{as: text}") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "interface") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "satisfies") == null);
}

test "native transformed extension module executes typed generic factory" {
    const engine_mod = @import("engine.zig");
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const source = "export type Message = { value: number }; function identity<T>(value: T): T { return value; } export default (value: number): number => identity<number>(value!) + 1;";
    const output = try transform(std.testing.allocator, source);
    defer std.testing.allocator.free(output);
    const namespace = try engine.evalModule(output, "typed-extension.ts");
    defer engine.freeValue(namespace);
    const factory = engine_mod.c.JS_GetPropertyStr(engine.context, namespace, "default");
    defer engine.freeValue(factory);
    var arguments = [_]engine_mod.c.JSValue{engine_mod.c.pi_js_int32(engine.context, 41)};
    defer engine.freeValue(arguments[0]);
    const result = try engine.checked(engine_mod.c.JS_Call(engine.context, factory, engine_mod.c.pi_js_undefined(), 1, &arguments));
    defer engine.freeValue(result);
    const encoded = try engine.stringify(result);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings("42", encoded);
}

test "native input transform handles this optional parameters and mixed type imports" {
    const source = "import type { Context } from 'types'; import { type Item, useful } from 'runtime'; function f(this: Context, value?: number): number { return value ?? 42; }";
    const output = try transform(std.testing.allocator, source);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "import type") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "useful") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "this:") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "value?") == null);
}

test "native input transform rejects malformed and non erasable runtime syntax" {
    try std.testing.expectError(error.InvalidTypeScriptInput, transform(std.testing.allocator, "const value: = ;"));
    try std.testing.expectError(error.TypeScriptRuntimeSyntaxRequiresLowering, transform(std.testing.allocator, "namespace Value { export const number = 1; }"));
}

test "native TypeScript lowering initializes parameter properties before constructor body" {
    const engine_mod = @import("engine.zig");
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const source = "class Base { constructor() {} } class Value extends Base { observed: number; constructor(public value: number, private readonly label: string = 'pi') { super(); this.observed = this.value; } read() { return [this.value, this.label, this.observed]; } } export default () => new Value(42).read();";
    const output = try transform(std.testing.allocator, source);
    defer std.testing.allocator.free(output);
    const namespace = try engine.evalModule(output, "parameter-properties.ts");
    defer engine.freeValue(namespace);
    const factory = engine_mod.c.JS_GetPropertyStr(engine.context, namespace, "default");
    defer engine.freeValue(factory);
    const result = try engine.checked(engine_mod.c.JS_Call(engine.context, factory, engine_mod.c.pi_js_undefined(), 0, null));
    defer engine.freeValue(result);
    const encoded = try engine.stringify(result);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings("[42,\"pi\",42]", encoded);
}

test "native TypeScript lowering retains numeric string and exported enum behavior" {
    const engine_mod = @import("engine.zig");
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const source = "export enum Numeric { Zero, Two = 2, Three, Four = Three + 1 } enum Text { Value = 'node-modules-ts-ok' } export default () => [Numeric.Zero, Numeric.Two, Numeric.Three, Numeric.Four, Numeric[4], Text.Value];";
    const output = try transform(std.testing.allocator, source);
    defer std.testing.allocator.free(output);
    const namespace = try engine.evalModule(output, "enum-extension.ts");
    defer engine.freeValue(namespace);
    const factory = engine_mod.c.JS_GetPropertyStr(engine.context, namespace, "default");
    defer engine.freeValue(factory);
    const result = try engine.checked(engine_mod.c.JS_Call(engine.context, factory, engine_mod.c.pi_js_undefined(), 0, null));
    defer engine.freeValue(result);
    const encoded = try engine.stringify(result);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings("[0,2,3,4,\"Four\",\"node-modules-ts-ok\"]", encoded);
}
