//! Product bridge: monorepo tool-definition shards → agent tool schemas + execute path.
const std = @import("std");
const g = @import("generated_root.zig");

pub const ExtendedTool = struct {
    name: []const u8,
    description: []const u8,
    parameters_json: []const u8,
    dangerous: bool,
};

fn collectFrom(comptime tools: anytype, out: *std.ArrayList(ExtendedTool), gpa: std.mem.Allocator) !void {
    for (tools) |t| {
        try out.append(gpa, .{
            .name = t.name,
            .description = t.description,
            .parameters_json = t.parameters_json,
            .dangerous = t.dangerous,
        });
    }
}

/// All extended tool specs from tools_shard_* (caller frees slice only).
pub fn listAll(gpa: std.mem.Allocator) ![]ExtendedTool {
    var out: std.ArrayList(ExtendedTool) = .empty;
    errdefer out.deinit(gpa);
    try collectFrom(g.tools_shard_0.tools, &out, gpa);
    try collectFrom(g.tools_shard_1.tools, &out, gpa);
    try collectFrom(g.tools_shard_2.tools, &out, gpa);
    try collectFrom(g.tools_shard_3.tools, &out, gpa);
    try collectFrom(g.tools_shard_4.tools, &out, gpa);
    try collectFrom(g.tools_shard_5.tools, &out, gpa);
    try collectFrom(g.tools_shard_6.tools, &out, gpa);
    try collectFrom(g.tools_shard_7.tools, &out, gpa);
    try collectFrom(g.tools_shard_8.tools, &out, gpa);
    try collectFrom(g.tools_shard_9.tools, &out, gpa);
    try collectFrom(g.tools_shard_10.tools, &out, gpa);
    try collectFrom(g.tools_shard_11.tools, &out, gpa);
    try collectFrom(g.tools_shard_12.tools, &out, gpa);
    try collectFrom(g.tools_shard_13.tools, &out, gpa);
    try collectFrom(g.tools_shard_14.tools, &out, gpa);
    try collectFrom(g.tools_shard_15.tools, &out, gpa);
    try collectFrom(g.tools_shard_16.tools, &out, gpa);
    try collectFrom(g.tools_shard_17.tools, &out, gpa);
    try collectFrom(g.tools_shard_18.tools, &out, gpa);
    try collectFrom(g.tools_shard_19.tools, &out, gpa);
    return try out.toOwnedSlice(gpa);
}

pub fn findByName(name: []const u8) ?ExtendedTool {
    inline for (.{
        g.tools_shard_0,  g.tools_shard_1,  g.tools_shard_2,  g.tools_shard_3,
        g.tools_shard_4,  g.tools_shard_5,  g.tools_shard_6,  g.tools_shard_7,
        g.tools_shard_8,  g.tools_shard_9,  g.tools_shard_10, g.tools_shard_11,
        g.tools_shard_12, g.tools_shard_13, g.tools_shard_14, g.tools_shard_15,
        g.tools_shard_16, g.tools_shard_17, g.tools_shard_18, g.tools_shard_19,
    }) |shard| {
        if (shard.findTool(name)) |t| {
            return .{
                .name = t.name,
                .description = t.description,
                .parameters_json = t.parameters_json,
                .dangerous = t.dangerous,
            };
        }
    }
    return null;
}

pub fn totalCount() usize {
    var n: usize = 0;
    inline for (.{
        g.tools_shard_0,  g.tools_shard_1,  g.tools_shard_2,  g.tools_shard_3,
        g.tools_shard_4,  g.tools_shard_5,  g.tools_shard_6,  g.tools_shard_7,
        g.tools_shard_8,  g.tools_shard_9,  g.tools_shard_10, g.tools_shard_11,
        g.tools_shard_12, g.tools_shard_13, g.tools_shard_14, g.tools_shard_15,
        g.tools_shard_16, g.tools_shard_17, g.tools_shard_18, g.tools_shard_19,
    }) |shard| {
        n += shard.toolCount();
    }
    return n;
}

/// Build OpenAI tools JSON array for extended tools (caller frees).
pub fn openAiToolsJson(gpa: std.mem.Allocator) ![]u8 {
    // Prefer shard openaiToolsJson merge for fidelity to shipped schemas
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("[");
    var first = true;
    inline for (.{
        g.tools_shard_0,  g.tools_shard_1,  g.tools_shard_2,  g.tools_shard_3,
        g.tools_shard_4,  g.tools_shard_5,  g.tools_shard_6,  g.tools_shard_7,
        g.tools_shard_8,  g.tools_shard_9,  g.tools_shard_10, g.tools_shard_11,
        g.tools_shard_12, g.tools_shard_13, g.tools_shard_14, g.tools_shard_15,
        g.tools_shard_16, g.tools_shard_17, g.tools_shard_18, g.tools_shard_19,
    }) |shard| {
        const part = try shard.openaiToolsJson(gpa);
        defer gpa.free(part);
        // part is "[...]" — strip brackets and merge
        if (part.len >= 2) {
            const inner = part[1 .. part.len - 1];
            if (inner.len > 0) {
                if (!first) try aw.writer.writeAll(",");
                try aw.writer.writeAll(inner);
                first = false;
            }
        }
    }
    try aw.writer.writeAll("]");
    return try aw.toOwnedSlice();
}

/// Execute an extended tool by name via shipped tools_shard_* preview functions.
/// Returns null if not an extended tool.
pub fn execute(gpa: std.mem.Allocator, name: []const u8, arguments_json: []const u8) !?[]u8 {
    const tool = findByName(name) orelse return null;
    _ = tool;
    const dispatch = @import("tools_dispatch.zig");
    return try dispatch.executePreview(gpa, name, arguments_json);
}

test "tools extended total and find product path" {
    try std.testing.expect(totalCount() >= 800); // 20 shards × 40 tools
    const first = g.tools_shard_0.tools[0].name;
    const t = findByName(first);
    try std.testing.expect(t != null);
    try std.testing.expectEqualStrings(first, t.?.name);

    const gpa = std.testing.allocator;
    const out = try execute(gpa, first, "{\"path\":\"a.txt\"}");
    defer if (out) |o| gpa.free(o);
    try std.testing.expect(out != null);
    // Must call real shard preview, not a string stub
    try std.testing.expect(std.mem.indexOf(u8, out.?, "preview:read_0_0") != null);
}

test "tools extended openai json non-empty" {
    const gpa = std.testing.allocator;
    const js = try openAiToolsJson(gpa);
    defer gpa.free(js);
    try std.testing.expect(js.len > 10);
    try std.testing.expect(std.mem.indexOf(u8, js, "\"type\":\"function\"") != null);
}
