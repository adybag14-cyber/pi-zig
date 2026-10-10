//! YAML grammar comes from the statically linked full C parser. Core schema,
//! duplicate keys, graph identity and yaml2.9.0 alias accounting remain native.
const std = @import("std");
const c = @cImport({
    @cInclude("pi_yaml.h");
});
pub const Pair = struct { key: *Value, value: *Value };
pub const Value = struct {
    data: union(enum) { null, boolean: bool, number: f64, string: []const u8, sequence: []*Value, mapping: []Pair } = .null,
    references: usize = 1,
    alias_weight: usize = 0,
};
pub const Diagnostic = struct { name: []const u8 = "YAMLParseError", code: ?[]const u8, message: []const u8, offset: usize = 0, end: usize = 0 };
pub const Owned = struct {
    arena: std.heap.ArenaAllocator,
    root: ?*Value = null,
    diagnostic: ?Diagnostic = null,
    pub fn deinit(self: *Owned) void {
        self.arena.deinit();
        self.* = undefined;
    }
};
fn text(value: c.pi_yaml_text) []const u8 {
    return if (value.bytes == null) "" else value.bytes[0..value.length];
}
const Node = c.pi_yaml_node;
const Decoder = struct {
    allocator: std.mem.Allocator,
    input: []const u8,
    parse_input: []const u8,
    anchors: std.StringHashMapUnmanaged(*Node) = .empty,
    values: std.AutoHashMapUnmanaged(*Node, *Value) = .empty,
    diagnostic: ?Diagnostic = null,
    fn report(self: *Decoder, node: ?*Node, name: []const u8, code: ?[]const u8, message: []const u8) anyerror {
        const offset = if (node) |present| c.pi_yaml_offset(present) else 0;
        self.diagnostic = .{ .name = name, .code = code, .message = message, .offset = offset, .end = offset + 1 };
        return error.InvalidYaml;
    }
    fn scalarValue(self: *Decoder, node: *Node) !@FieldType(Value, "data") {
        var content = text(c.pi_yaml_scalar(node));
        if (c.pi_yaml_double_quoted(node) != 0) {
            const start = c.pi_yaml_offset(node);
            const end = c.pi_yaml_end(node);
            if (start <= end and end <= self.input.len and !std.mem.eql(u8, self.input[start..end], self.parse_input[start..end])) {
                const original = self.input[start..end];
                const units = try std.unicode.wtf8ToWtf16LeAlloc(self.allocator, original);
                defer self.allocator.free(units);
                var decoded = try @import("yaml_quoted.zig").decode(self.allocator, units);
                defer decoded.deinit();
                if (decoded.failure) |failure| {
                    const offset = start + bytePosition(original, failure.offset);
                    self.diagnostic = .{ .code = failure.code, .message = try std.unicode.wtf16LeToWtf8Alloc(self.allocator, failure.message), .offset = offset, .end = offset + 1 };
                    return error.InvalidYaml;
                }
                content = try std.unicode.wtf16LeToWtf8Alloc(self.allocator, decoded.value);
            }
        }
        return scalar(self.allocator, content, c.pi_yaml_plain(node) != 0, text(c.pi_yaml_tag(node)));
    }
    fn weight(self: *Decoder, node: *Node) usize {
        if (c.pi_yaml_kind(node) == 3) {
            const source = self.anchors.get(text(c.pi_yaml_scalar(node))) orelse return 0;
            const value = self.values.get(source) orelse return 0;
            return value.references *| value.alias_weight;
        }
        var result: usize = 0;
        var iterator: ?*anyopaque = null;
        if (c.pi_yaml_kind(node) == 1) {
            while (c.pi_yaml_sequence_next(node, &iterator)) |child| result = @max(result, self.weight(child));
        } else if (c.pi_yaml_kind(node) == 2) {
            var key: ?*Node = null;
            var value: ?*Node = null;
            while (c.pi_yaml_mapping_next(node, &iterator, &key, &value) != 0) {
                if (key) |present| result = @max(result, self.weight(present));
                if (value) |present| result = @max(result, self.weight(present));
            }
        } else result = 1;
        return result;
    }
    fn decode(self: *Decoder, maybe: ?*Node) anyerror!*Value {
        const node = maybe orelse {
            const empty = try self.allocator.create(Value);
            empty.* = .{};
            return empty;
        };
        if (c.pi_yaml_kind(node) == 3) {
            const name = text(c.pi_yaml_scalar(node));
            const source = self.anchors.get(name) orelse return self.report(node, "ReferenceError", null, try std.fmt.allocPrint(self.allocator, "Unresolved alias (the anchor must be set before the alias): {s}", .{name}));
            const result = self.values.get(source) orelse return self.report(node, "ReferenceError", null, "This should not happen: Alias anchor was not resolved?");
            result.references +|= 1;
            if (result.alias_weight == 0) result.alias_weight = self.weight(source);
            if (result.references *| result.alias_weight > 100) return self.report(node, "ReferenceError", null, "Excessive alias count indicates a resource exhaustion attack");
            return result;
        }
        if (self.values.get(node)) |existing| return existing;
        const result = try self.allocator.create(Value);
        result.* = .{};
        try self.values.put(self.allocator, node, result);
        const anchor = text(c.pi_yaml_anchor(node));
        if (anchor.len != 0) try self.anchors.put(self.allocator, anchor, node);
        switch (c.pi_yaml_kind(node)) {
            0 => result.data = try self.scalarValue(node),
            1 => {
                var children: std.ArrayList(*Value) = .empty;
                var iterator: ?*anyopaque = null;
                while (c.pi_yaml_sequence_next(node, &iterator)) |child| try children.append(self.allocator, try self.decode(child));
                result.data = .{ .sequence = try children.toOwnedSlice(self.allocator) };
            },
            2 => {
                var pairs: std.ArrayList(Pair) = .empty;
                var key_nodes: std.ArrayList(?*Node) = .empty;
                var iterator: ?*anyopaque = null;
                var key_node: ?*Node = null;
                var value_node: ?*Node = null;
                while (c.pi_yaml_mapping_next(node, &iterator, &key_node, &value_node) != 0) {
                    const key = try self.decode(key_node);
                    for (pairs.items, key_nodes.items) |previous, previous_node| {
                        const same = key_node == previous_node or (key_node != null and previous_node != null and c.pi_yaml_kind(key_node) == 0 and c.pi_yaml_kind(previous_node) == 0 and equalScalar(key, previous.key));
                        if (same) return self.report(key_node, "YAMLParseError", "DUPLICATE_KEY", "Map keys must be unique");
                    }
                    try pairs.append(self.allocator, .{ .key = key, .value = try self.decode(value_node) });
                    try key_nodes.append(self.allocator, key_node);
                }
                result.data = .{ .mapping = try pairs.toOwnedSlice(self.allocator) };
            },
            else => return error.InvalidYamlNode,
        }
        return result;
    }
};
fn equalScalar(a: *Value, b: *Value) bool {
    if (std.meta.activeTag(a.data) != std.meta.activeTag(b.data)) return false;
    return switch (a.data) {
        .null => true,
        .boolean => |value| value == b.data.boolean,
        .number => |value| value == b.data.number,
        .string => |value| std.mem.eql(u8, value, b.data.string),
        else => false,
    };
}
fn integer(input: []const u8, base: u8, offset: usize) ?f64 {
    var bytes = input[offset..];
    var negative = false;
    if (base == 10 and bytes.len > 0 and (bytes[0] == '-' or bytes[0] == '+')) {
        negative = bytes[0] == '-';
        bytes = bytes[1..];
    }
    if (bytes.len == 0) return null;
    var result: f64 = 0;
    for (bytes) |byte| {
        const number = std.fmt.charToDigit(byte, base) catch return null;
        result = result * @as(f64, @floatFromInt(base)) + @as(f64, @floatFromInt(number));
    }
    return if (negative) -result else result;
}
fn decimal(input: []const u8) bool {
    var index: usize = 0;
    if (input.len > 0 and (input[0] == '+' or input[0] == '-')) index += 1;
    var before: usize = 0;
    while (index < input.len and std.ascii.isDigit(input[index])) : (index += 1) before += 1;
    var after: usize = 0;
    var dot = false;
    if (index < input.len and input[index] == '.') {
        dot = true;
        index += 1;
        while (index < input.len and std.ascii.isDigit(input[index])) : (index += 1) after += 1;
    }
    if (before + after == 0) return false;
    var exponent = false;
    if (index < input.len and (input[index] == 'e' or input[index] == 'E')) {
        exponent = true;
        index += 1;
        if (index < input.len and (input[index] == '+' or input[index] == '-')) index += 1;
        const start = index;
        while (index < input.len and std.ascii.isDigit(input[index])) : (index += 1) {}
        if (index == start) return false;
    }
    return index == input.len and (dot or exponent);
}
fn oneOf(input: []const u8, variants: []const []const u8) bool {
    for (variants) |variant| if (std.mem.eql(u8, input, variant)) return true;
    return false;
}
fn scalar(allocator: std.mem.Allocator, input: []const u8, plain: bool, tag: []const u8) !@FieldType(Value, "data") {
    const forced_string = std.mem.eql(u8, tag, "tag:yaml.org,2002:str");
    if ((plain or tag.len != 0) and !forced_string) {
        const automatic = tag.len == 0 or !std.mem.startsWith(u8, tag, "tag:yaml.org,2002:");
        if ((automatic or std.mem.endsWith(u8, tag, ":null")) and oneOf(input, &.{ "", "~", "null", "Null", "NULL" })) return .null;
        if (automatic or std.mem.endsWith(u8, tag, ":bool")) {
            if (oneOf(input, &.{ "true", "True", "TRUE" })) return .{ .boolean = true };
            if (oneOf(input, &.{ "false", "False", "FALSE" })) return .{ .boolean = false };
        }
        if (automatic or std.mem.endsWith(u8, tag, ":int")) {
            const parsed = if (std.mem.startsWith(u8, input, "0o")) integer(input, 8, 2) else if (std.mem.startsWith(u8, input, "0x")) integer(input, 16, 2) else integer(input, 10, 0);
            if (parsed) |number| return .{ .number = number };
        }
        if (automatic or std.mem.endsWith(u8, tag, ":float")) {
            if (oneOf(input, &.{ ".nan", ".NaN", ".NAN" })) return .{ .number = std.math.nan(f64) };
            if (oneOf(input, &.{ ".inf", ".Inf", ".INF", "+.inf", "+.Inf", "+.INF" })) return .{ .number = std.math.inf(f64) };
            if (oneOf(input, &.{ "-.inf", "-.Inf", "-.INF" })) return .{ .number = -std.math.inf(f64) };
            if (decimal(input)) return .{ .number = try std.fmt.parseFloat(f64, input) };
        }
    }
    return .{ .string = try allocator.dupe(u8, input) };
}
pub fn parse(allocator: std.mem.Allocator, input: []const u8) !Owned {
    var result: Owned = .{ .arena = .init(allocator) };
    errdefer result.deinit();
    const arena = result.arena.allocator();
    const prepared = try @import("native_yaml_compat.zig").prepare(c, arena, input);
    const document = prepared.document;
    defer c.pi_yaml_destroy(document);
    var diagnostic: c.pi_yaml_error = undefined;
    const status = c.pi_yaml_error_get(document, &diagnostic);
    if (status < 0) return error.OutOfMemory;
    if (status > 0) {
        result.diagnostic = try classify(arena, input, std.mem.span(diagnostic.message), diagnostic.offset, status);
        return result;
    }
    var decoder: Decoder = .{ .allocator = arena, .input = input, .parse_input = prepared.parse_input };
    result.root = decoder.decode(c.pi_yaml_root(document)) catch |err| {
        if (err != error.InvalidYaml) return err;
        result.diagnostic = decoder.diagnostic;
        return result;
    };
    return result;
}

fn issue(code: []const u8, message: []const u8, offset: usize) Diagnostic {
    return .{ .code = code, .message = message, .offset = offset, .end = offset + 1 };
}
/// Native grammar failures remain errors. Match the public yaml2.9.0 token
/// categories without substituting a delimiter-only acceptance check.
fn classify(allocator: std.mem.Allocator, input: []const u8, message: []const u8, offset: usize, status: c_int) !Diagnostic {
    if (status == 2) {
        var result = issue("MULTIPLE_DOCS", message, offset);
        result.end = input.len;
        return result;
    }
    if (std.mem.indexOf(u8, message, "document start") != null or std.mem.indexOf(u8, message, "with directives without content") != null)
        return issue("MISSING_CHAR", "Missing directives-end indicator line", input.len);
    var quote: ?u8 = null;
    var comment = false;
    var line_start: usize = 0;
    var stack: std.ArrayList(struct { delimiter: u8, offset: usize }) = .empty;
    defer stack.deinit(allocator);
    var last_comma = false;
    var first_value: ?usize = null;
    var index: usize = 0;
    while (index < input.len) : (index += 1) {
        const byte = input[index];
        if (byte == '\n') {
            comment = false;
            line_start = index + 1;
        }
        if (comment) continue;
        if (quote) |active| {
            if (active == '"' and byte == '\\' and index + 1 < input.len) {
                const next = input[index + 1];
                if (std.mem.indexOfScalar(u8, "0abtnvfre N_LP\"/\\xuU\n\r", next) == null)
                    return issue("BAD_DQ_ESCAPE", try std.fmt.allocPrint(allocator, "Invalid escape sequence \\{c}", .{next}), index);
                index += 1;
            } else if (byte == active) {
                if (active == '\'' and index + 1 < input.len and input[index + 1] == '\'') index += 1 else quote = null;
            }
            continue;
        }
        if (byte == '#' and (index == 0 or std.ascii.isWhitespace(input[index - 1]))) {
            comment = true;
            continue;
        }
        if (byte == '\t' and std.mem.trim(u8, input[line_start..index], " ").len == 0)
            return issue("TAB_AS_INDENT", "Tabs are not allowed as indentation", index);
        if (byte == '"' or byte == '\'') {
            quote = byte;
            last_comma = false;
            continue;
        }
        if (byte == ':' and first_value == null and stack.items.len == 0) {
            var value_start = index + 1;
            while (value_start < input.len and input[value_start] == ' ') value_start += 1;
            if (value_start < input.len and input[value_start] != '\n') first_value = value_start;
        }
        if ((byte == '|' or byte == '>') and (index == 0 or std.ascii.isWhitespace(input[index - 1]))) {
            var end = index + 1;
            while (end < input.len and !std.ascii.isWhitespace(input[end]) and input[end] != '#') end += 1;
            var indent = false;
            var chomp = false;
            for (input[index + 1 .. end], index + 1..) |character, position| {
                if (!chomp and (character == '+' or character == '-')) chomp = true else if (!indent and character >= '1' and character <= '9') indent = true else return issue("UNEXPECTED_TOKEN", try std.fmt.allocPrint(allocator, "Block scalar header includes extra characters: {s}", .{input[index..end]}), position);
            }
        }
        if (byte == '[' or byte == '{') {
            try stack.append(allocator, .{ .delimiter = byte, .offset = index });
            last_comma = false;
        } else if (byte == ']' or byte == '}') {
            if (stack.items.len != 0) _ = stack.pop();
            last_comma = false;
        } else if (byte == ',' and stack.items.len != 0) {
            if (last_comma) return issue("UNEXPECTED_TOKEN", if (stack.items[stack.items.len - 1].delimiter == '[') "Unexpected , in flow sequence" else "Unexpected , in flow map", index);
            last_comma = true;
        } else if (!std.ascii.isWhitespace(byte)) last_comma = false;
    }
    if (quote) |active| return issue("MISSING_CHAR", if (active == '"') "Missing closing \"quote" else "Missing closing 'quote", input.len);
    if (stack.items.len != 0) {
        const collection = stack.items[stack.items.len - 1];
        const root = std.mem.trim(u8, input[0..collection.offset], " \t\n\r").len == 0;
        const description = if (collection.delimiter == '[') "Flow sequence" else "Flow map";
        return issue(if (root) "MISSING_CHAR" else "BAD_INDENT", try std.fmt.allocPrint(allocator, "{s}{s}{c}", .{ description, if (root) " must end with a " else " in block collection must be sufficiently indented and end with a ", @as(u8, if (collection.delimiter == '[') ']' else '}') }), input.len);
    }
    if (first_value != null and (std.mem.indexOf(u8, message, "mapping") != null or std.mem.indexOf(u8, message, "value") != null or std.mem.indexOf(u8, message, "multiline plain key") != null))
        return issue("BLOCK_AS_IMPLICIT_KEY", "Nested mappings are not allowed in compact mappings", first_value.?);
    return issue("YAML_SYNTAX_ERROR", try allocator.dupe(u8, message), offset);
}
fn bytePosition(input: []const u8, requested: usize) usize {
    var index: usize = 0;
    var units: usize = 0;
    while (index < input.len and units < requested) {
        const length = std.unicode.utf8ByteSequenceLength(input[index]) catch 1;
        const end = @min(input.len, index + length);
        const point = std.unicode.utf8Decode(input[index..end]) catch input[index];
        units += if (point > 0xffff) @as(usize, 2) else 1;
        index = end;
    }
    return index;
}
