//! Pure native value/error differential against all immutable Source481 rows.
//! The owned JSON parser preserves isolated escaped UTF16 units as WTF8.
const std = @import("std");
const fm = @import("coding_agent/frontmatter.zig");
const json = @import("durable/backend/json.zig");
const Value = fm.yaml.Value;
fn field(value: json.Value, name: []const u8) json.Value {
    return value.object.get(name).?;
}
fn string(value: json.Value, name: []const u8) []const u8 {
    return field(value, name).string;
}
const Graph = struct {
    gpa: std.mem.Allocator,
    nodes: []const json.Value,
    matched: []?*Value,
    seen: std.AutoHashMapUnmanaged(*Value, usize) = .empty,
    fn match(self: *Graph, actual: *Value, expected: json.Value) anyerror!bool {
        if (expected.object.get("ref")) |reference| {
            const id: usize = @intCast(try json.asInteger(reference));
            if (id >= self.nodes.len) return error.InvalidSourceGraphReference;
            if (self.matched[id]) |previous| return actual == previous;
            if (self.seen.contains(actual)) return false;
            self.matched[id] = actual;
            try self.seen.put(self.gpa, actual, id);
            return self.node(actual, self.nodes[id]);
        }
        const kind = string(expected, "type");
        if (std.mem.eql(u8, kind, "null")) return actual.data == .null;
        if (std.mem.eql(u8, kind, "string")) return actual.data == .string and std.mem.eql(u8, actual.data.string, string(expected, "value"));
        if (std.mem.eql(u8, kind, "boolean")) return actual.data == .boolean and actual.data.boolean == std.mem.eql(u8, string(expected, "value"), "true");
        if (std.mem.eql(u8, kind, "number")) {
            if (actual.data != .number) return false;
            const value = actual.data.number;
            const raw = string(expected, "value");
            if (std.mem.eql(u8, raw, "NaN")) return std.math.isNan(value);
            if (std.mem.eql(u8, raw, "Infinity")) return std.math.isPositiveInf(value);
            if (std.mem.eql(u8, raw, "-Infinity")) return std.math.isNegativeInf(value);
            if (std.mem.eql(u8, raw, "-0")) return value == 0 and std.math.signbit(value);
            return value == try std.fmt.parseFloat(f64, raw) and !(value == 0 and std.math.signbit(value));
        }
        return false;
    }
    fn node(self: *Graph, actual: *Value, expected: json.Value) anyerror!bool {
        const kind = string(expected, "type");
        if (std.mem.eql(u8, kind, "timestamp")) return actual.data == .timestamp and actual.data.timestamp == try std.fmt.parseFloat(f64, string(expected, "milliseconds"));
        if (std.mem.eql(u8, kind, "binary")) {
            if (actual.data != .binary) return false;
            const bytes = try @import("extensions/binary_encoding.zig").encode(self.gpa, string(expected, "base64"), .base64);
            defer self.gpa.free(bytes);
            return std.mem.eql(u8, bytes, actual.data.binary);
        }
        if (std.mem.eql(u8, kind, "sequence") or std.mem.eql(u8, kind, "set")) {
            const items = if (std.mem.eql(u8, kind, "sequence")) switch (actual.data) {
                .sequence => |items| items,
                else => return false,
            } else switch (actual.data) {
                .set => |items| items,
                else => return false,
            };
            const expected_items = field(expected, "items").array.items;
            if (items.len != expected_items.len) return false;
            for (items, expected_items) |item, observed| if (!try self.match(item, observed)) return false;
            return true;
        }
        if (std.mem.eql(u8, kind, "object") or std.mem.eql(u8, kind, "map")) {
            const object = std.mem.eql(u8, kind, "object");
            const entries = if (object) switch (actual.data) {
                .mapping => |entries| entries,
                else => return false,
            } else switch (actual.data) {
                .ordered_mapping => |entries| entries,
                else => return false,
            };
            const expected_entries = field(expected, "entries").array.items;
            if (entries.len != expected_entries.len) return false;
            for (entries, expected_entries) |entry, observed| {
                const pair = observed.array.items;
                if (object) {
                    // Scalar property keys are already native values. Do not
                    // invent Source collection-key rendering in the observer.
                    const key = switch (entry.key.data) {
                        .string => |key| key,
                        .null => "",
                        else => return false,
                    };
                    if (!std.mem.eql(u8, key, pair[0].string)) return false;
                } else if (!try self.match(entry.key, pair[0])) return false;
                if (!try self.match(entry.value, pair[1])) return false;
            }
            return true;
        }
        return false;
    }
};
fn utf16Offset(gpa: std.mem.Allocator, input: []const u8, offset: usize) !usize {
    const units = try std.unicode.wtf8ToWtf16LeAlloc(gpa, input[0..@min(input.len, offset)]);
    defer gpa.free(units);
    return units.len;
}
pub fn exercise(gpa: std.mem.Allocator) !void {
    try exerciseSource(gpa, "481", @embedFile("extensions/fixtures/sdk-yaml-values-source-481.json"), 21, 11, 10);
}
pub fn exerciseEdges(gpa: std.mem.Allocator) !void {
    try exerciseSource(gpa, "489", @embedFile("extensions/fixtures/sdk-yaml-edges-source-489.json"), 24, 20, 4);
}
fn exerciseSource(gpa: std.mem.Allocator, comptime capture: []const u8, fixture: []const u8, count: usize, expected_accepted: usize, expected_rejected: usize) !void {
    var source = try json.Owned.parse(gpa, fixture);
    defer source.deinit();
    const rows = field(source.value, "rows").array.items;
    try std.testing.expectEqual(count, rows.len);
    var failed: usize = 0;
    var accepted: usize = 0;
    var rejected: usize = 0;
    for (rows) |row| {
        const label = string(row, "id");
        const expected_graph = row.object.get("graph");
        if (expected_graph != null) accepted += 1 else rejected += 1;
        const content = try std.fmt.allocPrint(gpa, "---\n{s}\n---\n body ", .{string(row, "yaml")});
        defer gpa.free(content);
        var parsed = fm.parse(gpa, content) catch |err| {
            std.debug.print("Source{s} {s} native error {s}\n", .{ capture, label, @errorName(err) });
            failed += 1;
            continue;
        };
        defer parsed.deinit();
        var matches = false;
        if (expected_graph) |expected| {
            if (parsed.frontmatter.diagnostic == null and parsed.frontmatter.root != null) {
                const nodes = field(expected, "nodes").array.items;
                const matched = try gpa.alloc(?*Value, nodes.len);
                defer gpa.free(matched);
                @memset(matched, null);
                var graph: Graph = .{ .gpa = gpa, .nodes = nodes, .matched = matched };
                defer graph.seen.deinit(gpa);
                matches = try graph.match(parsed.frontmatter.root.?, field(expected, "root"));
                for (matched) |value| if (value == null) { matches = false; };
                matches = matches and std.mem.eql(u8, parsed.body, string(row, "body"));
            }
        } else if (parsed.frontmatter.diagnostic) |diagnostic| {
            const expected = field(row, "error");
            const message = try fm.pretty(gpa, parsed.yaml_source.?, diagnostic);
            defer gpa.free(message);
            const code = field(expected, "code");
            const pos = field(expected, "pos");
            const code_matches = if (code == .null) diagnostic.code == null else diagnostic.code != null and std.mem.eql(u8, code.string, diagnostic.code.?);
            const pos_matches = pos == .null or (try utf16Offset(gpa, parsed.yaml_source.?, diagnostic.offset) == try json.asInteger(pos.array.items[0]) and try utf16Offset(gpa, parsed.yaml_source.?, diagnostic.end) == try json.asInteger(pos.array.items[1]));
            matches = code_matches and pos_matches and std.mem.eql(u8, diagnostic.name, string(expected, "name")) and std.mem.eql(u8, message, string(expected, "message"));
        }
        if (!matches) {
            if (parsed.frontmatter.diagnostic) |diagnostic| std.debug.print("Source{s} {s} mismatch name={s} code={s} pos{d},{d} message={s}\n", .{ capture, label, diagnostic.name, diagnostic.code orelse "<null>", diagnostic.offset, diagnostic.end, diagnostic.message }) else std.debug.print("Source{s} {s} value/acceptance mismatch\n", .{ capture, label });
            failed += 1;
        }
    }
    std.debug.print("Source{s} complete values/errors accepted{d} rejected{d} total{d} mismatches{d}\n", .{ capture, accepted, rejected, rows.len, failed });
    try std.testing.expectEqual(expected_accepted, accepted);
    try std.testing.expectEqual(expected_rejected, rejected);
    try std.testing.expectEqual(@as(usize, 0), failed);
}
