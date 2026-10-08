//! Native rendering of the script-visible JSON Schema declarations.
const std = @import("std");
const Value = std.json.Value;
const discovery = @import("codemode_discovery.zig");
pub const mcp_typescript_preamble = @embedFile("fixtures/codemode-mcp-preamble-6fb.txt");
pub const Declaration = struct { name: []const u8, description: []const u8 = "", input: Value = .null, output: ?Value = null, signature: ?[]const u8 = null };
fn docComment(a: std.mem.Allocator, text: []const u8, indent: []const u8) ![]const u8 {
    const trimmed = trimJs(text);
    if (trimmed.len == 0) return "";
    const escaped = try std.mem.replaceOwned(u8, a, trimmed, "*/", "*\\/");
    if (std.mem.indexOfScalar(u8, escaped, '\n') == null) return std.fmt.allocPrint(a, "{s}/** {s} */\n", .{ indent, escaped });
    var lines: std.ArrayList([]const u8) = .empty;
    try lines.append(a, try std.fmt.allocPrint(a, "{s}/**", .{indent}));
    var split = std.mem.splitScalar(u8, escaped, '\n');
    while (split.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        try lines.append(a, try std.fmt.allocPrint(a, "{s} *{s}{s}", .{ indent, if (line.len > 0) " " else "", line }));
    }
    try lines.append(a, try std.fmt.allocPrint(a, "{s} */\n", .{indent}));
    return std.mem.join(a, "\n", lines.items);
}
fn globalDeclaration(a: std.mem.Allocator, head: []const u8, item: Declaration, indent: []const u8) ![]const u8 {
    const signature = item.signature orelse try std.fmt.allocPrint(a, "(args: {s}): Promise<{s}>", .{ try schemaToType(a, item.input, null), try schemaToType(a, item.output orelse .null, null) });
    return std.fmt.allocPrint(a, "{s}{s}{s}{s};", .{ try docComment(a, item.description, indent), indent, head, signature });
}
pub fn renderDeclarations(gpa: std.mem.Allocator, tools: []const Declaration, globals: []const Declaration) ![]u8 {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var sections: std.ArrayList([]const u8) = .empty;
    if (tools.len > 0) {
        var members: std.ArrayList([]const u8) = .empty;
        for (tools) |tool| try members.append(a, try std.fmt.allocPrint(a, "{s}  {s}(args: {s}): Promise<{s}>;", .{ try docComment(a, tool.description, "  "), try discovery.identifier(a, tool.name), try schemaToType(a, tool.input, 16_000), try outputType(a, tool.output) }));
        try sections.append(a, try std.fmt.allocPrint(a, "declare const tools: {{\n{s}\n}};", .{try std.mem.join(a, "\n", members.items)}));
    }
    var namespaces: std.StringArrayHashMapUnmanaged(std.ArrayList([]const u8)) = .empty;
    for (globals) |global| {
        if (std.mem.indexOfScalar(u8, global.name, '.')) |dot| {
            const entry = try namespaces.getOrPut(a, global.name[0..dot]);
            if (!entry.found_existing) entry.value_ptr.* = .empty;
            try entry.value_ptr.append(a, try globalDeclaration(a, global.name[dot + 1 ..], global, "  "));
        } else try sections.append(a, try globalDeclaration(a, try std.fmt.allocPrint(a, "declare function {s}", .{global.name}), global, ""));
    }
    for (namespaces.keys(), namespaces.values()) |name, members| try sections.append(a, try std.fmt.allocPrint(a, "declare const {s}: {{\n{s}\n}};", .{ name, try std.mem.join(a, "\n", members.items) }));
    return std.mem.join(gpa, "\n\n", sections.items);
}
const OrderedName = struct { name: []const u8, units: []const u16 };
const Context = struct {
    a: std.mem.Allocator,
    root: Value,
    resolving: std.StringHashMapUnmanaged(void) = .empty,
    expansions: usize = 0,
    fn join(self: *Context, values: []const []const u8, separator: []const u8) ![]const u8 {
        return std.mem.join(self.a, separator, values);
    }
    fn unionTypes(self: *Context, values: []const []const u8) ![]const u8 {
        var unique: std.ArrayList([]const u8) = .empty;
        for (values) |value| {
            if (std.mem.eql(u8, value, "unknown")) return "unknown";
            var found = false;
            for (unique.items) |previous| found = found or std.mem.eql(u8, previous, value);
            if (!found) try unique.append(self.a, value);
        }
        return if (unique.items.len == 0) "never" else self.join(unique.items, " | ");
    }
    fn reference(self: *Context, name: []const u8) !?Value {
        if (!std.mem.eql(u8, name, "#") and !std.mem.startsWith(u8, name, "#/")) return null;
        var result = self.root;
        if (name.len == 1) return result;
        var segments = std.mem.splitScalar(u8, name[2..], '/');
        while (segments.next()) |segment| {
            if (segment.len == 0) continue;
            const decoded = try self.a.dupe(u8, segment);
            var cursor: usize = 0;
            while (cursor < decoded.len) : (cursor += 1) if (decoded[cursor] == '%') {
                if (cursor + 2 >= decoded.len or !std.ascii.isHex(decoded[cursor + 1]) or !std.ascii.isHex(decoded[cursor + 2])) return error.MalformedSchemaReferenceUri;
                cursor += 2;
            };
            const uri = std.Uri.percentDecodeInPlace(decoded);
            if (!std.unicode.utf8ValidateSlice(uri)) return error.MalformedSchemaReferenceUri;
            var key: std.ArrayList(u8) = .empty;
            var index: usize = 0;
            while (index < uri.len) : (index += 1) {
                if (uri[index] == '~' and index + 1 < uri.len and (uri[index + 1] == '0' or uri[index + 1] == '1')) {
                    try key.append(self.a, if (uri[index + 1] == '0') '~' else '/');
                    index += 1;
                } else try key.append(self.a, uri[index]);
            }
            if (result != .object) return null;
            result = result.object.get(key.items) orelse return null;
        }
        return if (result == .object or result == .bool) result else null;
    }
    fn render(self: *Context, schema: Value, depth: usize) anyerror![]const u8 {
        if (depth > 256) return "unknown";
        if (schema == .bool) return if (schema.bool) "unknown" else "never";
        if (schema != .object) return "unknown";
        const object = schema.object;
        if (object.get("$ref")) |value| if (value == .string) {
            if (self.expansions >= 32 or self.resolving.contains(value.string)) return "unknown";
            const target = try self.reference(value.string) orelse return "unknown";
            self.expansions += 1;
            try self.resolving.put(self.a, value.string, {});
            defer _ = self.resolving.remove(value.string);
            return self.render(target, depth + 1);
        };
        if (object.get("const")) |value| return std.json.Stringify.valueAlloc(self.a, value, .{});
        if (object.get("enum")) |values| if (values == .array) {
            const variants = try self.a.alloc([]const u8, values.array.items.len);
            for (values.array.items, variants) |value, *variant| variant.* = try std.json.Stringify.valueAlloc(self.a, value, .{});
            return self.unionTypes(variants);
        };
        for ([_][]const u8{ "anyOf", "oneOf", "allOf" }) |name| if (object.get(name)) |values| if (values == .array) {
            var variants: std.ArrayList([]const u8) = .empty;
            for (values.array.items) |value| {
                const text = try self.render(value, depth + 1);
                if (std.mem.eql(u8, name, "allOf")) {
                    if (!std.mem.eql(u8, text, "unknown")) try variants.append(self.a, if (std.mem.indexOf(u8, text, " | ") != null) try std.fmt.allocPrint(self.a, "({s})", .{text}) else text);
                } else try variants.append(self.a, text);
            }
            return if (std.mem.eql(u8, name, "allOf")) if (variants.items.len == 0) "unknown" else self.join(variants.items, " & ") else self.unionTypes(variants.items);
        };
        const kind = object.get("type");
        if (kind) |value| if (value == .array) {
            const variants = try self.a.alloc([]const u8, value.array.items.len);
            for (value.array.items, variants) |item, *variant| {
                var copy = object;
                // Arena ownership isolates the shallow map before replacing its type.
                copy = try object.clone(self.a);
                try copy.put(self.a, "type", item);
                variant.* = try self.render(.{ .object = copy }, depth + 1);
            }
            return self.unionTypes(variants);
        };
        const name = if (kind) |value| if (value == .string) value.string else "unknown" else "";
        if (std.mem.eql(u8, name, "string")) return "string";
        if (std.mem.eql(u8, name, "number") or std.mem.eql(u8, name, "integer")) return "number";
        if (std.mem.eql(u8, name, "boolean")) return "boolean";
        if (std.mem.eql(u8, name, "null")) return "null";
        if (std.mem.eql(u8, name, "array") or (name.len == 0 and (object.contains("items") or object.contains("prefixItems")))) {
            if (object.get("items")) |items| if (items != .array) return std.fmt.allocPrint(self.a, "Array<{s}>", .{try self.render(items, depth + 1)});
            const prefix = object.get("prefixItems");
            const tuple = if (prefix != null and prefix.? == .array) prefix.? else object.get("items") orelse Value{ .null = {} };
            if (tuple == .array and tuple.array.items.len > 0) {
                const parts = try self.a.alloc([]const u8, tuple.array.items.len);
                for (tuple.array.items, parts) |item, *part| part.* = try self.render(item, depth + 1);
                return std.fmt.allocPrint(self.a, "[{s}]", .{try self.join(parts, ", ")});
            }
            return "unknown[]";
        }
        if (!std.mem.eql(u8, name, "object") and !(name.len == 0 and (object.contains("properties") or object.contains("additionalProperties") or object.contains("required")))) return "unknown";
        const properties = if (object.get("properties")) |value| if (value == .object) value.object else std.json.ObjectMap{} else std.json.ObjectMap{};
        const ordered = try self.a.alloc(OrderedName, properties.count());
        for (properties.keys(), ordered) |key, *entry| entry.* = .{ .name = key, .units = try std.unicode.wtf8ToWtf16LeAlloc(self.a, key) };
        std.mem.sort(OrderedName, ordered, {}, struct {
            fn lessThan(_: void, left: OrderedName, right: OrderedName) bool {
                return std.mem.order(u16, left.units, right.units) == .lt;
            }
        }.lessThan);
        const names = try self.a.alloc([]const u8, ordered.len);
        for (ordered, names) |entry, *name_| name_.* = entry.name;
        var members: std.ArrayList([]const u8) = .empty;
        var commented = false;
        for (names) |key| {
            const value = properties.get(key).?;
            var required = false;
            if (object.get("required")) |list| if (list == .array) for (list.array.items) |entry| {
                if (entry == .string and std.mem.eql(u8, entry.string, key)) required = true;
            };
            const key_text = if (validIdentifier(key)) key else try std.json.Stringify.valueAlloc(self.a, key, .{});
            try members.append(self.a, try std.fmt.allocPrint(self.a, "{s}{s}: {s};", .{ key_text, if (required) "" else "?", try self.render(value, depth + 1) }));
            commented = commented or description(value).len > 0;
        }
        if (object.get("additionalProperties")) |additional| {
            if (additional != .bool or additional.bool) try members.append(self.a, try std.fmt.allocPrint(self.a, "[key: string]: {s};", .{if (additional == .bool) "unknown" else try self.render(additional, depth + 1)}));
        } else if (names.len == 0) try members.append(self.a, "[key: string]: unknown;");
        if (members.items.len == 0) return "{}";
        if (!commented) return std.fmt.allocPrint(self.a, "{{ {s} }}", .{try self.join(members.items, " ")});
        var lines: std.ArrayList([]const u8) = .empty;
        try lines.append(self.a, "{");
        for (names, 0..) |key, index| {
            var comments = std.mem.splitScalar(u8, description(properties.get(key).?), '\n');
            while (comments.next()) |line| {
                const trimmed = trimJs(line);
                if (trimmed.len > 0) try lines.append(self.a, try std.fmt.allocPrint(self.a, "  // {s}", .{trimmed}));
            }
            const indented = try std.mem.replaceOwned(u8, self.a, members.items[index], "\n", "\n  ");
            try lines.append(self.a, try std.fmt.allocPrint(self.a, "  {s}", .{indented}));
        }
        for (members.items[names.len..]) |member| try lines.append(self.a, try std.fmt.allocPrint(self.a, "  {s}", .{member}));
        try lines.append(self.a, "}");
        return self.join(lines.items, "\n");
    }
};
fn validIdentifier(value: []const u8) bool {
    if (value.len == 0 or (!std.ascii.isAlphabetic(value[0]) and value[0] != '_' and value[0] != '$')) return false;
    for (value[1..]) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '$') return false;
    return true;
}
fn description(value: Value) []const u8 {
    if (value != .object) return "";
    const text = value.object.get("description") orelse return "";
    return if (text == .string) trimJs(text.string) else "";
}
pub fn trimJs(text: []const u8) []const u8 {
    var iterator = (std.unicode.Wtf8View.init(text) catch return text).iterator();
    var begin: usize = 0;
    var end: usize = 0;
    var leading = true;
    while (iterator.nextCodepoint()) |point| {
        const whitespace = (point >= 9 and point <= 13) or point == 0x20 or point == 0xa0 or point == 0x1680 or (point >= 0x2000 and point <= 0x200a) or point == 0x2028 or point == 0x2029 or point == 0x202f or point == 0x205f or point == 0x3000 or point == 0xfeff;
        if (leading and whitespace) begin = iterator.i else if (!whitespace) { leading = false; end = iterator.i; }
    }
    return text[begin..@max(begin, end)];
}
pub fn schemaToType(gpa: std.mem.Allocator, schema: Value, max_chars: ?usize) ![]u8 {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var context: Context = .{ .a = arena.allocator(), .root = schema };
    const result = try context.render(schema, 0);
    var characters: usize = 0;
    var iterator = (try std.unicode.Wtf8View.init(result)).iterator();
    while (iterator.nextCodepoint()) |point| characters += if (point > 0xffff) @as(usize, 2) else 1;
    return gpa.dupe(u8, if (max_chars) |limit| if (characters > limit) "unknown" else result else result);
}
pub fn sample(gpa: std.mem.Allocator, name: []const u8, text: []const u8, input: Value, output: ?Value) ![]u8 {
    const id = try discovery.identifier(gpa, name);
    defer gpa.free(id);
    const input_type = try schemaToType(gpa, input, 16_000);
    defer gpa.free(input_type);
    const output_type = try outputType(gpa, output);
    defer gpa.free(output_type);
    return std.fmt.allocPrint(gpa, "{s}\n\ncodemode tool declaration:\n```ts\ndeclare const tools: {{ {s}(args: {s}): Promise<{s}>; }};\n```", .{ trimJs(text), id, input_type, output_type });
}
pub fn outputType(gpa: std.mem.Allocator, schema: ?Value) ![]u8 {
    if (schema) |value| if (value == .object) if (value.object.get("properties")) |properties| if (properties == .object) {
        const content = properties.object.get("content");
        const is_error = properties.object.get("isError");
        const meta = properties.object.get("_meta");
        if (content != null and content.? == .object and is_error != null and is_error.? == .object and meta != null and meta.? == .object) {
            const content_type = content.?.object.get("type");
            const items = content.?.object.get("items");
            const error_type = is_error.?.object.get("type");
            const meta_type = meta.?.object.get("type");
            if (content_type != null and content_type.? == .string and std.mem.eql(u8, content_type.?.string, "array") and items != null and items.? == .object and error_type != null and error_type.? == .string and std.mem.eql(u8, error_type.?.string, "boolean") and meta_type != null and meta_type.? == .string and std.mem.eql(u8, meta_type.?.string, "object")) {
                const item_type = items.?.object.get("type");
                if (item_type != null and item_type.? == .string and std.mem.eql(u8, item_type.?.string, "object")) {
                    const structured = properties.object.get("structuredContent") orelse Value{ .bool = true };
                    const actual = if (structured == .object or structured == .bool) structured else Value{ .bool = true };
                    const result = try schemaToType(gpa, actual, null);
                    defer gpa.free(result);
                    return if (std.mem.eql(u8, result, "unknown")) gpa.dupe(u8, "CallToolResult") else std.fmt.allocPrint(gpa, "CallToolResult<{s}>", .{result});
                }
            }
        }
    };
    return schemaToType(gpa, schema orelse .null, null);
}
test "native codemode declaration schema and samples replay current original renderer" {
    const gpa = std.testing.allocator;
    const captured = try std.json.parseFromSlice(Value, gpa, @embedFile("fixtures/codemode-declarations-original-6fb.json"), .{});
    defer captured.deinit();
    for (captured.value.object.get("rows").?.array.items) |row| {
        const schema = row.object.get("schema").?;
        const actual = try schemaToType(gpa, schema, null);
        defer gpa.free(actual);
        try std.testing.expectEqualStrings(row.object.get("type").?.string, actual);
        const output = try std.json.parseFromSlice(Value, gpa, "{\"type\":\"string\"}", .{});
        defer output.deinit();
        const rendered = try sample(gpa, "sample-tool", " Sample description ", schema, output.value);
        defer gpa.free(rendered);
        try std.testing.expectEqualStrings(row.object.get("sample").?.string, rendered);
    }
}
test "native codemode declaration MCP outputs replay actual source result schemas" {
    const gpa = std.testing.allocator;
    const captured = try std.json.parseFromSlice(Value, gpa, @embedFile("fixtures/codemode-mcp-declarations-original-6fb.json"), .{});
    defer captured.deinit();
    const input = try std.json.parseFromSlice(Value, gpa, "{\"type\":\"object\",\"properties\":{}}", .{});
    defer input.deinit();
    for (captured.value.object.get("rows").?.array.items) |row| {
        const actual = try outputType(gpa, row.object.get("outputSchema"));
        defer gpa.free(actual);
        try std.testing.expectEqualStrings(row.object.get("type").?.string, actual);
        const rendered = try sample(gpa, "mcp__dev_radius__lookup", "Find records", input.value, row.object.get("outputSchema"));
        defer gpa.free(rendered);
        try std.testing.expectEqualStrings(row.object.get("sample").?.string, rendered);
    }
}
test "native codemode declaration Unicode limits property order comments and references replay source" {
    const gpa = std.testing.allocator;
    const captured = try std.json.parseFromSlice(Value, gpa, @embedFile("fixtures/codemode-schema-edges-original-6fb.json"), .{});
    defer captured.deinit();
    for (captured.value.object.get("rows").?.array.items) |row| {
        const schema = row.object.get("schema").?;
        if (row.object.contains("error")) {
            try std.testing.expectError(error.MalformedSchemaReferenceUri, schemaToType(gpa, schema, null));
            continue;
        }
        const actual = try schemaToType(gpa, schema, null);
        defer gpa.free(actual);
        try std.testing.expectEqualStrings(row.object.get("type").?.string, actual);
        const bounded = try schemaToType(gpa, schema, @intCast(row.object.get("maxChars").?.integer));
        defer gpa.free(bounded);
        try std.testing.expectEqualStrings(row.object.get("bounded").?.string, bounded);
        const rendered = try sample(gpa, "unicode", "\xc2\xa0 Trim me \xef\xbb\xbf", schema, null);
        defer gpa.free(rendered);
        try std.testing.expectEqualStrings(row.object.get("sample").?.string, rendered);
    }
}
test "native codemode declaration complete tools globals and ordered namespaces replay source" {
    const gpa = std.testing.allocator;
    const captured = try std.json.parseFromSlice(Value, gpa, @embedFile("fixtures/codemode-full-declarations-original-6fb.json"), .{});
    defer captured.deinit();
    for (captured.value.object.get("rows").?.array.items) |row| {
        const input = row.object.get("input").?.object;
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        const a = arena.allocator();
        var lists: [2]std.ArrayList(Declaration) = .{ .empty, .empty };
        for ([_][]const u8{ "tools", "globals" }, 0..) |key, index| if (input.get(key)) |items| for (items.array.items) |item| {
            try lists[index].append(a, .{ .name = item.object.get("name").?.string, .description = if (item.object.get("description")) |value| value.string else "", .input = item.object.get("inputSchema") orelse .null, .output = item.object.get("outputSchema"), .signature = if (item.object.get("signature")) |value| value.string else null });
        };
        const actual = try renderDeclarations(gpa, lists[0].items, lists[1].items);
        defer gpa.free(actual);
        try std.testing.expectEqualStrings(row.object.get("result").?.string, actual);
    }
}
test "native codemode declaration allocation failures release nested rendering and namespace buffers" {
    const Check = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const schema = try std.json.parseFromSlice(Value, gpa, "{\"type\":\"object\",\"properties\":{\"😀\":{\"$ref\":\"#/$defs/value\",\"description\":\"First\\nsecond\"}},\"$defs\":{\"value\":{\"type\":\"array\",\"items\":{\"enum\":[\"a\",\"b\"]}}}}", .{});
            defer schema.deinit();
            const result = try renderDeclarations(gpa, &.{.{ .name = "lookup-record", .description = "Find\nrecords */", .input = schema.value, .output = schema.value }}, &.{ .{ .name = "models.list", .input = schema.value }, .{ .name = "models.get", .signature = "(id: string): unknown" } });
            defer gpa.free(result);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Check.run, .{});
}
