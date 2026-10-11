//! YAML grammar comes from the statically linked full C parser. Core schema,
//! duplicate keys, graph identity and yaml2.9.0 alias accounting remain native.
const std = @import("std");
const c = @cImport({
    @cInclude("pi_yaml.h");
});
pub const Pair = struct { key: *Value, value: *Value };
pub const Value = struct {
    data: union(enum) { null, boolean: bool, number: f64, string: []const u8, binary: []const u8, timestamp: f64, merge, sequence: []*Value, mapping: []Pair, set: []*Value, ordered_mapping: []Pair } = .null,
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
    scalars: std.AutoHashMapUnmanaged(*Node, @FieldType(Value, "data")) = .empty,
    diagnostic: ?Diagnostic = null,
    fn report(self: *Decoder, node: ?*Node, name: []const u8, code: ?[]const u8, message: []const u8) anyerror {
        const offset = if (node) |present| c.pi_yaml_offset(present) else 0;
        self.diagnostic = .{ .name = name, .code = code, .message = message, .offset = offset, .end = offset + 1 };
        return error.InvalidYaml;
    }
    fn reportTag(self: *Decoder, node: *Node, message: []const u8) anyerror {
        const offset = c.pi_yaml_tag_offset(node);
        self.diagnostic = .{ .code = "TAG_RESOLVE_FAILED", .message = message, .offset = offset, .end = @max(offset + 1, c.pi_yaml_tag_end(node)) };
        return error.InvalidYaml;
    }
    fn scalarValue(self: *Decoder, node: *Node) !@FieldType(Value, "data") {
        if (self.scalars.get(node)) |value| return value;
        const value = try self.resolveScalar(node);
        try self.scalars.put(self.allocator, node, value);
        return value;
    }
    fn resolveScalar(self: *Decoder, node: *Node) !@FieldType(Value, "data") {
        var content = text(c.pi_yaml_scalar(node));
        if (c.pi_yaml_double_quoted(node) != 0) {
            const start = c.pi_yaml_offset(node);
            const end = c.pi_yaml_end(node);
            if (start <= end and end <= self.input.len) {
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
    // yaml.parse first composes the document and throws composition errors;
    // Alias.toJSON only runs afterward. Source481's duplicate-before-alias
    // therefore reports DUPLICATE_KEY even when an earlier value is *missing.
    // This pass never resolves aliases or counts them as graph references.
    fn validate(self: *Decoder, maybe: ?*Node) anyerror!void {
        const node = maybe orelse return;
        if (c.pi_yaml_kind(node) == 0) {
            _ = self.scalarValue(node) catch |err| {
                if (err == error.InvalidYamlTimestamp) return self.reportTag(node, "!!timestamp expects a date, starting with yyyy-mm-dd");
                return err;
            };
        } else if (c.pi_yaml_kind(node) == 1) {
            var iterator: ?*anyopaque = null;
            while (c.pi_yaml_sequence_next(node, &iterator)) |child| try self.validate(child);
        } else if (c.pi_yaml_kind(node) == 2) {
            var keys: std.ArrayList(?*Node) = .empty;
            var iterator: ?*anyopaque = null;
            var key: ?*Node = null;
            var value: ?*Node = null;
            while (c.pi_yaml_mapping_next(node, &iterator, &key, &value) != 0) {
                try self.validate(key);
                // Flow maps compose the value before checking this key;
                // block maps check it before composing the value.
                if (c.pi_yaml_flow(node) != 0) try self.validate(value);
                for (keys.items) |previous| {
                    const same = key == previous or (key != null and previous != null and c.pi_yaml_kind(key) == 0 and c.pi_yaml_kind(previous) == 0 and equalScalarData(try self.scalarValue(key.?), try self.scalarValue(previous.?)));
                    if (same) return self.report(key, "YAMLParseError", "DUPLICATE_KEY", "Map keys must be unique");
                }
                try keys.append(self.allocator, key);
                if (c.pi_yaml_flow(node) == 0) try self.validate(value);
            }
        }
        try self.validateCollection(node);
    }
    fn validateCollection(self: *Decoder, node: *Node) !void {
        const tag = text(c.pi_yaml_tag(node));
        if (c.pi_yaml_kind(node) == 2 and std.mem.eql(u8, tag, "tag:yaml.org,2002:set")) {
            var iterator: ?*anyopaque = null;
            var key: ?*Node = null;
            var value: ?*Node = null;
            while (c.pi_yaml_mapping_next(node, &iterator, &key, &value) != 0) {
                if (value) |present| {
                    if (c.pi_yaml_kind(present) != 0 or (try self.scalarValue(present)) != .null or text(c.pi_yaml_tag(present)).len != 0 or c.pi_yaml_commented(present) != 0)
                        return self.reportTag(node, "Set items must all have null values");
                }
            }
        } else if (c.pi_yaml_kind(node) == 1 and (std.mem.eql(u8, tag, "tag:yaml.org,2002:pairs") or std.mem.eql(u8, tag, "tag:yaml.org,2002:omap"))) {
            const ordered = std.mem.eql(u8, tag, "tag:yaml.org,2002:omap");
            var keys: std.ArrayList(@FieldType(Value, "data")) = .empty;
            var iterator: ?*anyopaque = null;
            while (c.pi_yaml_sequence_next(node, &iterator)) |child| {
                var key: ?*Node = child;
                if (c.pi_yaml_kind(child) == 2) {
                    key = null;
                    var pair_iterator: ?*anyopaque = null;
                    var value: ?*Node = null;
                    _ = c.pi_yaml_mapping_next(child, &pair_iterator, &key, &value);
                    var extra_key: ?*Node = null;
                    if (c.pi_yaml_mapping_next(child, &pair_iterator, &extra_key, &value) != 0)
                        return self.reportTag(node, "Each pair must have its own sequence indicator");
                }
                if (ordered and (key == null or c.pi_yaml_kind(key.?) == 0)) {
                    const data = if (key) |present| try self.scalarValue(present) else @as(@FieldType(Value, "data"), .null);
                    for (keys.items) |previous| {
                        // Array.includes uses SameValueZero, unlike mapping
                        // composition's strict scalar comparison.
                        if (equalScalarData(previous, data) or (previous == .number and data == .number and std.math.isNan(previous.number) and std.math.isNan(data.number)))
                            return self.reportTag(node, try std.fmt.allocPrint(self.allocator, "Ordered maps must not include duplicate keys: {s}", .{try self.scalarText(data)}));
                    }
                    try keys.append(self.allocator, data);
                }
            }
        }
    }
    fn scalarText(self: *Decoder, data: @FieldType(Value, "data")) ![]const u8 {
        return switch (data) {
            .null => "null",
            .boolean => |value| if (value) "true" else "false",
            .string => |value| value,
            .number => |value| if (std.math.isNan(value)) "NaN" else if (std.math.isPositiveInf(value)) "Infinity" else if (std.math.isNegativeInf(value)) "-Infinity" else if (value == 0) "0" else try std.fmt.allocPrint(self.allocator, "{d}", .{value}),
            else => "[object Object]",
        };
    }
    fn nullValue(self: *Decoder) !*Value {
        const result = try self.allocator.create(Value);
        result.* = .{};
        return result;
    }
    fn decodePairs(self: *Decoder, node: *Node, ordered: bool) !@FieldType(Value, "data") {
        var pairs: std.ArrayList(Pair) = .empty;
        var sequence: std.ArrayList(*Value) = .empty;
        var iterator: ?*anyopaque = null;
        while (c.pi_yaml_sequence_next(node, &iterator)) |child| {
            var key: ?*Node = child;
            var value: ?*Node = null;
            if (c.pi_yaml_kind(child) == 2) {
                key = null;
                var pair_iterator: ?*anyopaque = null;
                _ = c.pi_yaml_mapping_next(child, &pair_iterator, &key, &value);
            }
            const decoded_key = try self.decode(key);
            const pair: Pair = .{ .key = if (ordered) decoded_key else try self.objectKey(key, decoded_key), .value = if (value) |present| try self.decode(present) else try self.nullValue() };
            if (ordered) {
                for (pairs.items) |previous| if (previous.key == pair.key or equalScalarData(previous.key.data, pair.key.data))
                    return self.report(node, "Error", null, "Ordered maps must not include duplicate keys");
                try pairs.append(self.allocator, pair);
            } else {
                const entry = try self.allocator.create(Value);
                const singleton = try self.allocator.alloc(Pair, 1);
                singleton[0] = pair;
                entry.* = .{ .data = .{ .mapping = singleton } };
                try sequence.append(self.allocator, entry);
            }
        }
        return if (ordered) .{ .ordered_mapping = try pairs.toOwnedSlice(self.allocator) } else .{ .sequence = try sequence.toOwnedSlice(self.allocator) };
    }
    fn mergeSource(self: *Decoder, node: *Node) !*Node {
        if (c.pi_yaml_kind(node) != 3) return node;
        // The merge tag calls Alias.resolve, rather than Alias.toJSON. This
        // lookup does not increment the ordinary alias reference counter.
        return self.anchors.get(text(c.pi_yaml_scalar(node))) orelse return self.report(node, "Error", null, "Merge sources must be maps or map aliases");
    }
    fn objectKey(self: *Decoder, maybe: ?*Node, value: *Value) !*Value {
        const primitive: ?[]const u8 = switch (value.data) {
            .string => return value,
            .null => "",
            .boolean, .number => try self.scalarText(value.data),
            else => null,
        };
        if (primitive) |content| {
            const key = try self.allocator.create(Value);
            key.* = .{ .data = .{ .string = content } };
            return key;
        }
        const node = maybe orelse return value;
        if (value.data != .sequence and value.data != .mapping and value.data != .ordered_mapping and value.data != .set) return value;
        // addPairToJSMap.stringifyKey renders collection keys as YAML in a
        // flow context before assigning an ordinary JS object property. The
        // original node/value remains cached for subsequent alias values.
        var output: std.ArrayList(u8) = .empty;
        try self.flowKey(&output, node, 0, false);
        const key = try self.allocator.create(Value);
        key.* = .{ .data = .{ .string = try output.toOwnedSlice(self.allocator) } };
        return key;
    }
    fn flowKey(self: *Decoder, output: *std.ArrayList(u8), maybe: ?*Node, depth: usize, include_properties: bool) anyerror!void {
        const node = maybe orelse return output.appendSlice(self.allocator, "null");
        if (depth > 512) return error.YamlKeyNestingLimit;
        const kind = c.pi_yaml_kind(node);
        if (kind == 3) {
            try output.append(self.allocator, '*');
            return output.appendSlice(self.allocator, text(c.pi_yaml_scalar(node)));
        }
        const tag = text(c.pi_yaml_tag(node));
        if (include_properties and tag.len != 0) {
            const prefix = "tag:yaml.org,2002:";
            if (std.mem.startsWith(u8, tag, prefix)) {
                try output.appendSlice(self.allocator, "!!");
                try output.appendSlice(self.allocator, tag[prefix.len..]);
            } else {
                try output.appendSlice(self.allocator, "!<");
                try output.appendSlice(self.allocator, tag);
                try output.append(self.allocator, '>');
            }
            try output.append(self.allocator, ' ');
        }
        const anchor = text(c.pi_yaml_anchor(node));
        if (include_properties and anchor.len != 0) {
            try output.append(self.allocator, '&');
            try output.appendSlice(self.allocator, anchor);
            try output.append(self.allocator, ' ');
        }
        if (kind == 0) {
            const data = try self.scalarValue(node);
            if (data == .string) {
                const content = data.string;
                const plain = c.pi_yaml_plain(node) != 0 and content.len != 0 and std.mem.indexOfAny(u8, content, "[]{},\n\r") == null and std.mem.indexOf(u8, content, ": ") == null;
                if (plain) return output.appendSlice(self.allocator, content);
                if (c.pi_yaml_single_quoted(node) != 0 and std.mem.indexOfAny(u8, content, "\n\r") == null) {
                    try output.append(self.allocator, '\'');
                    for (content) |byte| {
                        try output.append(self.allocator, byte);
                        if (byte == '\'') try output.append(self.allocator, byte);
                    }
                    return output.append(self.allocator, '\'');
                }
                const quoted = try @import("../durable/backend/json.zig").stringify(self.allocator, .{ .string = content });
                defer self.allocator.free(quoted);
                return self.quotedKey(output, quoted);
            }
            if (data == .number and std.math.isNan(data.number)) return output.appendSlice(self.allocator, ".nan");
            if (data == .number and std.math.isPositiveInf(data.number)) return output.appendSlice(self.allocator, ".inf");
            if (data == .number and std.math.isNegativeInf(data.number)) return output.appendSlice(self.allocator, "-.inf");
            if (data == .number and data.number == 0 and std.math.signbit(data.number)) return output.appendSlice(self.allocator, "-0");
            return output.appendSlice(self.allocator, try self.scalarText(data));
        }
        var lines: std.ArrayList([]const u8) = .empty;
        defer lines.deinit(self.allocator);
        var iterator: ?*anyopaque = null;
        if (kind == 1) {
            const pairs = std.mem.eql(u8, tag, "tag:yaml.org,2002:omap") or std.mem.eql(u8, tag, "tag:yaml.org,2002:pairs");
            while (c.pi_yaml_sequence_next(node, &iterator)) |child| {
                var item: std.ArrayList(u8) = .empty;
                if (pairs) {
                    var key: ?*Node = child;
                    var value: ?*Node = null;
                    if (c.pi_yaml_kind(child) == 2) {
                        key = null;
                        var pair_iterator: ?*anyopaque = null;
                        _ = c.pi_yaml_mapping_next(child, &pair_iterator, &key, &value);
                    }
                    try self.flowPair(&item, key, value, depth + 1, false);
                } else try self.flowKey(&item, child, depth + 1, true);
                try lines.append(self.allocator, try item.toOwnedSlice(self.allocator));
            }
        } else if (kind == 2) {
            const all_null = std.mem.eql(u8, tag, "tag:yaml.org,2002:set");
            var key: ?*Node = null;
            var value: ?*Node = null;
            while (c.pi_yaml_mapping_next(node, &iterator, &key, &value) != 0) {
                var item: std.ArrayList(u8) = .empty;
                try self.flowPair(&item, key, value, depth + 1, all_null);
                try lines.append(self.allocator, try item.toOwnedSlice(self.allocator));
            }
        }
        try output.append(self.allocator, if (kind == 1) '[' else '{');
        var width: usize = 2;
        var multiline = false;
        for (lines.items, 0..) |line, index| {
            const units = try std.unicode.wtf8ToWtf16LeAlloc(self.allocator, line);
            defer self.allocator.free(units);
            width += units.len + 2 + @intFromBool(index + 1 < lines.items.len);
            multiline = multiline or std.mem.indexOfScalar(u8, line, '\n') != null;
        }
        multiline = multiline or width > 80;
        for (lines.items, 0..) |line, index| {
            if (multiline) {
                try output.append(self.allocator, '\n');
                try output.appendNTimes(self.allocator, ' ', (depth + 1) * 2);
            } else try output.append(self.allocator, ' ');
            try output.appendSlice(self.allocator, line);
            if (index + 1 < lines.items.len) try output.append(self.allocator, ',');
        }
        if (lines.items.len != 0) {
            if (multiline) {
                try output.append(self.allocator, '\n');
                try output.appendNTimes(self.allocator, ' ', depth * 2);
            } else try output.append(self.allocator, ' ');
        }
        try output.append(self.allocator, if (kind == 1) ']' else '}');
    }
    fn flowPair(self: *Decoder, output: *std.ArrayList(u8), key: ?*Node, value: ?*Node, depth: usize, all_null: bool) !void {
        const explicit = key != null and (c.pi_yaml_kind(key.?) != 0 or (c.pi_yaml_plain(key.?) == 0 and c.pi_yaml_double_quoted(key.?) == 0 and c.pi_yaml_single_quoted(key.?) == 0));
        if (explicit) try output.appendSlice(self.allocator, "? ");
        try self.flowKey(output, key, depth, true);
        if (!all_null and value != null) {
            try output.appendSlice(self.allocator, if (explicit) "\n: " else ": ");
            try self.flowKey(output, value, depth, true);
        }
    }
    fn quotedKey(self: *Decoder, output: *std.ArrayList(u8), quoted: []const u8) !void {
        var index: usize = 0;
        while (index < quoted.len) : (index += 1) {
            if (quoted[index] == '\\' and index + 1 < quoted.len) {
                if (quoted[index + 1] == 'u' and index + 6 <= quoted.len) {
                    const code = quoted[index + 2 .. index + 6];
                    const short: ?u8 = if (std.mem.eql(u8, code, "0000")) '0' else if (std.mem.eql(u8, code, "0007")) 'a' else if (std.mem.eql(u8, code, "0008")) 'b' else if (std.mem.eql(u8, code, "0009")) 't' else if (std.mem.eql(u8, code, "000a")) 'n' else if (std.mem.eql(u8, code, "000b")) 'v' else if (std.mem.eql(u8, code, "000c")) 'f' else if (std.mem.eql(u8, code, "000d")) 'r' else if (std.mem.eql(u8, code, "001b")) 'e' else null;
                    if (short) |character| {
                        try output.appendSlice(self.allocator, &.{ '\\', character });
                        index += 5;
                        continue;
                    }
                    if (std.mem.startsWith(u8, code, "00")) {
                        try output.appendSlice(self.allocator, "\\x");
                        try output.appendSlice(self.allocator, code[2..]);
                        index += 5;
                        continue;
                    }
                }
                try output.appendSlice(self.allocator, quoted[index .. index + 2]);
                index += 1;
            } else try output.append(self.allocator, quoted[index]);
        }
    }
    fn mergeMap(self: *Decoder, pairs: *std.ArrayList(Pair), node: *Node) anyerror!void {
        const source = try self.mergeSource(node);
        if (c.pi_yaml_kind(source) != 2) return self.report(node, "Error", null, "Merge sources must be maps or map aliases");
        const decoded = try self.decode(source);
        // The source's YAML mapping is converted to a fresh Map by upstream;
        // this keeps its keys before ordinary-object key coercion.
        const entries = switch (decoded.data) {
            .mapping => |entries| entries,
            else => return self.report(node, "Error", null, "Merge sources must be maps or map aliases"),
        };
        for (entries) |entry| {
            var found = false;
            for (pairs.items) |present| if (try self.sameObjectKey(present.key, entry.key)) {
                found = true;
                break;
            };
            if (!found) try pairs.append(self.allocator, entry);
        }
    }
    fn sameObjectKey(self: *Decoder, a: *Value, b: *Value) !bool {
        if (a == b or equalScalarData(a.data, b.data)) return true;
        // Ordinary JS object property keys coerce scalar numbers/bools/null.
        // Collection-key YAML rendering is retained as a separate gap.
        const a_scalar = a.data == .null or a.data == .boolean or a.data == .number or a.data == .string;
        const b_scalar = b.data == .null or b.data == .boolean or b.data == .number or b.data == .string;
        if (!a_scalar or !b_scalar) return false;
        const left = if (a.data == .null) "" else try self.scalarText(a.data);
        const right = if (b.data == .null) "" else try self.scalarText(b.data);
        return std.mem.eql(u8, left, right);
    }
    fn merge(self: *Decoder, pairs: *std.ArrayList(Pair), maybe: ?*Node) anyerror!void {
        const node = maybe orelse return self.report(null, "Error", null, "Merge sources must be maps or map aliases");
        const source = try self.mergeSource(node);
        if (c.pi_yaml_kind(source) == 1) {
            var iterator: ?*anyopaque = null;
            while (c.pi_yaml_sequence_next(source, &iterator)) |child| try self.mergeMap(pairs, child);
        } else try self.mergeMap(pairs, source);
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
            0 => result.data = self.scalarValue(node) catch |err| {
                if (err == error.InvalidYamlTimestamp) return self.reportTag(node, "!!timestamp expects a date, starting with yyyy-mm-dd");
                return err;
            },
            1 => {
                const tag = text(c.pi_yaml_tag(node));
                if (std.mem.eql(u8, tag, "tag:yaml.org,2002:pairs") or std.mem.eql(u8, tag, "tag:yaml.org,2002:omap")) {
                    result.data = try self.decodePairs(node, std.mem.eql(u8, tag, "tag:yaml.org,2002:omap"));
                    return result;
                }
                var children: std.ArrayList(*Value) = .empty;
                var iterator: ?*anyopaque = null;
                while (c.pi_yaml_sequence_next(node, &iterator)) |child| try children.append(self.allocator, try self.decode(child));
                result.data = .{ .sequence = try children.toOwnedSlice(self.allocator) };
            },
            2 => {
                const is_set = std.mem.eql(u8, text(c.pi_yaml_tag(node)), "tag:yaml.org,2002:set");
                var pairs: std.ArrayList(Pair) = .empty;
                var iterator: ?*anyopaque = null;
                var key_node: ?*Node = null;
                var value_node: ?*Node = null;
                while (c.pi_yaml_mapping_next(node, &iterator, &key_node, &value_node) != 0) {
                    if (key_node != null and std.mem.eql(u8, text(c.pi_yaml_tag(key_node.?)), "tag:yaml.org,2002:merge")) {
                        try self.merge(&pairs, value_node);
                        continue;
                    }
                    const decoded_key = try self.decode(key_node);
                    const key = if (is_set) decoded_key else try self.objectKey(key_node, decoded_key);
                    // Original scalar/node duplicate checks ran during
                    // composition. Property-key coercion may now collide
                    // (e.g. 1 and "1"); Source overwrites that object value.
                    const value = try self.decode(value_node);
                    var replaced = false;
                    for (pairs.items) |*previous| if (if (is_set) previous.key == key or equalScalar(previous.key, key) or (previous.key.data == .number and key.data == .number and std.math.isNan(previous.key.data.number) and std.math.isNan(key.data.number)) else try self.sameObjectKey(previous.key, key)) {
                        previous.value = value;
                        replaced = true;
                        break;
                    };
                    if (!replaced) {
                        try pairs.append(self.allocator, .{ .key = key, .value = value });
                    }
                }
                if (is_set) {
                    const items = try self.allocator.alloc(*Value, pairs.items.len);
                    for (pairs.items, items) |pair, *item| item.* = pair.key;
                    result.data = .{ .set = items };
                } else {
                    const entries = try pairs.toOwnedSlice(self.allocator);
                    objectPropertyOrder(entries);
                    result.data = .{ .mapping = entries };
                }
            },
            else => return error.InvalidYamlNode,
        }
        return result;
    }
};
fn arrayIndex(value: *Value) ?u32 {
    if (value.data != .string) return null;
    const key = value.data.string;
    if (key.len == 0 or (key.len > 1 and key[0] == '0')) return null;
    for (key) |byte| if (!std.ascii.isDigit(byte)) return null;
    const index = std.fmt.parseInt(u32, key, 10) catch return null;
    return if (index == std.math.maxInt(u32)) null else index;
}
fn objectPropertyOrder(entries: []Pair) void {
    // Ordinary JS object enumeration puts array-index names first in numeric
    // order, retaining insertion order for all remaining string properties.
    for (entries, 0..) |entry, from| {
        const index = arrayIndex(entry.key) orelse continue;
        var to = from;
        while (to > 0) : (to -= 1) {
            if (arrayIndex(entries[to - 1].key)) |previous| if (previous <= index) break;
            entries[to] = entries[to - 1];
        }
        entries[to] = entry;
    }
}
fn equalScalar(a: *Value, b: *Value) bool {
    return equalScalarData(a.data, b.data);
}
fn equalScalarData(a: @FieldType(Value, "data"), b: @FieldType(Value, "data")) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .null => true,
        .boolean => |value| value == b.boolean,
        .number => |value| value == b.number,
        .string => |value| std.mem.eql(u8, value, b.string),
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
    const forced_string = std.mem.eql(u8, tag, "tag:yaml.org,2002:str") or std.mem.eql(u8, tag, "!");
    if (std.mem.eql(u8, tag, "tag:yaml.org,2002:binary")) return .{ .binary = try @import("../extensions/binary_encoding.zig").encode(allocator, input, .base64) };
    if (std.mem.eql(u8, tag, "tag:yaml.org,2002:timestamp")) return .{ .timestamp = @import("yaml_timestamp.zig").resolve(input) orelse return error.InvalidYamlTimestamp };
    // Each explicit merge resolver creates a distinct Symbol, so two such
    // keys do not count as duplicate scalar keys during composition.
    if (std.mem.eql(u8, tag, "tag:yaml.org,2002:merge")) return .merge;
    if ((plain or tag.len != 0) and !forced_string) {
        // compose-scalar.findScalarTagByName falls back to the string tag for
        // unknown names. It does not apply implicit number/bool resolution.
        const automatic = tag.len == 0;
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
    decoder.validate(c.pi_yaml_root(document)) catch |err| {
        if (err != error.InvalidYaml) return err;
        result.diagnostic = decoder.diagnostic;
        return result;
    };
    result.root = decoder.decode(c.pi_yaml_root(document)) catch |err| {
        if (err != error.InvalidYaml) return err;
        result.diagnostic = decoder.diagnostic;
        return result;
    };
    return result;
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
    if (std.mem.indexOf(u8, message, "wrongly indented double-quoted scalar") != null) {
        if (std.mem.indexOfPos(u8, input, @min(offset, input.len), "\n\"")) |boundary|
            return issue("MISSING_CHAR", "Missing closing \"quote", boundary);
    }
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
                if (next == 'x' or next == 'u' or next == 'U') {
                    const count: usize = if (next == 'x') 2 else if (next == 'u') 4 else 8;
                    const stop = @min(input.len, index + count + 2);
                    const digits = input[index + 2 .. stop];
                    const point: ?u32 = std.fmt.parseInt(u32, digits, 16) catch null;
                    if (digits.len != count or point == null or point.? > 0x10ffff)
                        return issue("BAD_DQ_ESCAPE", try std.fmt.allocPrint(allocator, "Invalid escape sequence {s}", .{input[index..stop]}), index);
                }
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
        if (byte == '*' and stack.items.len != 0 and stack.items[stack.items.len - 1].delimiter == '{') {
            // yaml2.9 includes a trailing colon in the flow alias token. A
            // following value consequently lacks its map separator. This
            // classifies an actual grammar failure; it never accepts input.
            var alias_end = index + 1;
            while (alias_end < input.len and !std.ascii.isWhitespace(input[alias_end]) and std.mem.indexOfScalar(u8, ",[]{}", input[alias_end]) == null) alias_end += 1;
            if (alias_end > index + 1 and input[alias_end - 1] == ':') {
                var value_start = alias_end;
                while (value_start < input.len and std.ascii.isWhitespace(input[value_start])) value_start += 1;
                if (value_start < input.len and input[value_start] != '}' and input[value_start] != ',')
                    return issue("MISSING_CHAR", "Missing , or : between flow map items", value_start);
            }
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
