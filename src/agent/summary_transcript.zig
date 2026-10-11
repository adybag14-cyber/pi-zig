//! Latest coding-agent transcript material shared by compaction and branch summaries.
const std = @import("std");
const session = @import("session.zig");

fn label(writer: *std.Io.Writer, first: *bool, prefix: []const u8, text: []const u8) !void {
    if (!first.*) try writer.writeAll("\n\n");
    first.* = false;
    try writer.writeAll(prefix);
    try writer.writeAll(text);
}
fn calls(gpa: std.mem.Allocator, raw: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return error.InvalidSummaryToolCalls;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    var first = true;
    for (parsed.value.array.items) |item| {
        if (item != .object) return error.InvalidSummaryToolCall;
        const function = item.object.get("function") orelse item;
        if (function != .object) return error.InvalidSummaryToolCall;
        const name = function.object.get("name") orelse return error.InvalidSummaryToolCall;
        const arguments = function.object.get("arguments") orelse return error.InvalidSummaryToolCall;
        if (name != .string) return error.InvalidSummaryToolCall;
        var decoded: ?std.json.Parsed(std.json.Value) = null;
        defer if (decoded) |*value| value.deinit();
        const fields = if (arguments == .string) args: {
            decoded = try std.json.parseFromSlice(std.json.Value, gpa, arguments.string, .{});
            break :args decoded.?.value;
        } else arguments;
        if (fields != .object) return error.InvalidSummaryToolArguments;
        if (!first) try out.writer.writeAll("; ");
        first = false;
        try out.writer.print("{s}(", .{name.string});
        const keys = try @import("../ai/json_property_order.zig").keys(gpa, fields.object);
        defer gpa.free(keys);
        var ordered: std.heap.ArenaAllocator = .init(gpa);
        defer ordered.deinit();
        var first_argument = true;
        for (keys) |key| {
            if (!first_argument) try out.writer.writeAll(", ");
            first_argument = false;
            try out.writer.print("{s}=", .{key});
            try std.json.Stringify.value(try @import("../ai/json_property_order.zig").copy(ordered.allocator(), fields.object.get(key).?), .{}, &out.writer);
        }
        try out.writer.writeByte(')');
    }
    return out.toOwnedSlice();
}
pub fn serialize(gpa: std.mem.Allocator, entries: []const *const session.SessionEntry) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    var first = true;
    for (entries) |entry| {
        if (entry.entry_type == .compaction) {
            try label(&out.writer, &first, "[Compaction summary]: ", entry.content);
        } else if (entry.entry_type == .branch_summary) {
            try label(&out.writer, &first, "[Branch summary]: ", entry.content);
        } else if (entry.entry_type == .custom_message or std.mem.eql(u8, entry.role, "user") or std.mem.eql(u8, entry.role, "bashExecution")) {
            if (entry.content.len != 0) try label(&out.writer, &first, "[User]: ", entry.content);
        } else if (std.mem.eql(u8, entry.role, "assistant")) {
            if (entry.meta.has_text_content orelse (entry.content.len != 0)) try label(&out.writer, &first, "[Assistant]: ", entry.content);
            if (entry.tool_calls_json) |raw| {
                const rendered = try calls(gpa, raw);
                defer gpa.free(rendered);
                if (rendered.len != 0) try label(&out.writer, &first, "[Assistant tool calls]: ", rendered);
            }
        } else if (std.mem.eql(u8, entry.role, "tool") or std.mem.eql(u8, entry.role, "toolResult")) {
            if (entry.content.len == 0) continue;
            const units = try std.unicode.wtf8ToWtf16LeAlloc(gpa, entry.content);
            defer gpa.free(units);
            const kept = @min(units.len, 2000);
            const prefix = try std.unicode.wtf16LeToWtf8Alloc(gpa, units[0..kept]);
            defer gpa.free(prefix);
            try label(&out.writer, &first, "[Tool result]: ", prefix);
            if (kept < units.len) try out.writer.print("\n\n[... {d} more characters truncated]", .{units.len - kept});
        }
    }
    return out.toOwnedSlice();
}

/// Exercise each actual caller through real upstream-message Session parsing.
pub fn testSourceCases(comptime caller: *const fn (std.mem.Allocator, []const *const session.SessionEntry) anyerror![]u8) !void {
    const gpa = std.testing.allocator;
    var source = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("../durable/fixtures/durable-89-compaction-serialization-source.json"), .{});
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        var input: std.Io.Writer.Allocating = .init(gpa);
        defer input.deinit();
        try input.writer.writeAll("{\"type\":\"session\",\"version\":3,\"id\":\"source89\",\"cwd\":\"C:/fixture\"}\n");
        for (row.object.get("messages").?.array.items, 0..) |message, index| {
            try input.writer.print("{{\"type\":\"message\",\"id\":\"m{d}\",\"message\":", .{index});
            try std.json.Stringify.value(message, .{}, &input.writer);
            try input.writer.writeAll("}\n");
        }
        var loaded = try session.Session.parseJsonl(gpa, input.written());
        defer loaded.deinit();
        const entries = try gpa.alloc(*const session.SessionEntry, loaded.entries.items.len);
        defer gpa.free(entries);
        for (loaded.entries.items, 0..) |*entry, index| entries[index] = entry;
        const actual = try caller(gpa, entries);
        defer gpa.free(actual);
        try std.testing.expectEqualStrings(row.object.get("codingAgent").?.string, actual);
    }
}
