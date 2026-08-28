//! Pure JSON response builders for RPC session/introspection commands.
const std = @import("std");
const session_mod = @import("../agent/session.zig");
const providers = @import("../ai/providers.zig");
const prompts_mod = @import("prompts.zig");
const skills_mod = @import("skills.zig");

pub const Error = error{UnknownEntry};

fn writeNullableString(writer: *std.Io.Writer, value: ?[]const u8) !void {
    if (value) |text| try std.json.Stringify.value(text, .{}, writer) else try writer.writeAll("null");
}

fn nextJsonlLine(it: *std.mem.SplitIterator(u8, .scalar)) ?[]const u8 {
    while (it.next()) |line| if (line.len > 0) return line;
    return null;
}

pub fn formatEntriesJson(
    gpa: std.mem.Allocator,
    sess: *const session_mod.Session,
    since: ?[]const u8,
) ![]u8 {
    var start: usize = 0;
    if (since) |cursor| {
        var found = false;
        for (sess.entries.items, 0..) |entry, index| {
            if (std.mem.eql(u8, entry.id, cursor)) {
                start = index + 1;
                found = true;
                break;
            }
        }
        if (!found) return Error.UnknownEntry;
    }

    const jsonl = try sess.toJsonl(gpa);
    defer gpa.free(jsonl);
    var lines = std.mem.splitScalar(u8, jsonl, '\n');
    _ = nextJsonlLine(&lines); // session header

    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"entries\":[");
    var entry_index: usize = 0;
    var emitted: usize = 0;
    while (nextJsonlLine(&lines)) |line| : (entry_index += 1) {
        if (entry_index < start) continue;
        if (emitted > 0) try out.writer.writeByte(',');
        try out.writer.writeAll(line);
        emitted += 1;
    }
    try out.writer.writeAll("],\"leafId\":");
    try writeNullableString(&out.writer, sess.lastEntryId());
    try out.writer.writeByte('}');
    return try out.toOwnedSlice();
}

fn parentExists(sess: *const session_mod.Session, parent_id: []const u8) bool {
    for (sess.entries.items) |entry| if (std.mem.eql(u8, entry.id, parent_id)) return true;
    return false;
}

fn writeTreeNode(
    writer: *std.Io.Writer,
    sess: *const session_mod.Session,
    entry_lines: []const []const u8,
    index: usize,
    active: []bool,
) !void {
    // Broken/cyclic imported sessions are kept finite rather than crashing RPC.
    if (active[index]) {
        try writer.writeAll("{\"entry\":");
        try writer.writeAll(entry_lines[index]);
        try writer.writeAll(",\"children\":[]}");
        return;
    }
    active[index] = true;
    defer active[index] = false;

    const entry = sess.entries.items[index];
    try writer.writeAll("{\"entry\":");
    try writer.writeAll(entry_lines[index]);
    try writer.writeAll(",\"children\":[");
    var child_count: usize = 0;
    for (sess.entries.items, 0..) |candidate, child_index| {
        const parent = candidate.parent_id orelse continue;
        if (!std.mem.eql(u8, parent, entry.id)) continue;
        if (child_count > 0) try writer.writeByte(',');
        try writeTreeNode(writer, sess, entry_lines, child_index, active);
        child_count += 1;
    }
    try writer.writeByte(']');
    if (sess.getLabel(entry.id)) |label| {
        try writer.writeAll(",\"label\":");
        try std.json.Stringify.value(label, .{}, writer);
    }
    try writer.writeByte('}');
}

pub fn formatTreeJson(gpa: std.mem.Allocator, sess: *const session_mod.Session) ![]u8 {
    const jsonl = try sess.toJsonl(gpa);
    defer gpa.free(jsonl);
    var split = std.mem.splitScalar(u8, jsonl, '\n');
    _ = nextJsonlLine(&split);
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(gpa);
    while (nextJsonlLine(&split)) |line| try lines.append(gpa, line);

    const active = try gpa.alloc(bool, sess.entries.items.len);
    defer gpa.free(active);
    @memset(active, false);

    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"tree\":[");
    var roots: usize = 0;
    for (sess.entries.items, 0..) |entry, index| {
        const is_root = if (entry.parent_id) |parent| !parentExists(sess, parent) else true;
        if (!is_root) continue;
        if (roots > 0) try out.writer.writeByte(',');
        try writeTreeNode(&out.writer, sess, lines.items, index, active);
        roots += 1;
    }
    // A pure cycle has no natural root; expose each cycle member as a finite root.
    if (roots == 0 and sess.entries.items.len > 0) {
        for (sess.entries.items, 0..) |_, index| {
            if (index > 0) try out.writer.writeByte(',');
            try writeTreeNode(&out.writer, sess, lines.items, index, active);
        }
    }
    try out.writer.writeAll("],\"leafId\":");
    try writeNullableString(&out.writer, sess.lastEntryId());
    try out.writer.writeByte('}');
    return try out.toOwnedSlice();
}

pub fn formatForkMessagesJson(gpa: std.mem.Allocator, sess: *const session_mod.Session) ![]u8 {
    const branch = try sess.branchEntries(gpa);
    defer gpa.free(branch);
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"messages\":[");
    var count: usize = 0;
    for (branch) |entry| {
        if (!std.mem.eql(u8, entry.role, "user")) continue;
        if (count > 0) try out.writer.writeByte(',');
        try out.writer.writeAll("{\"entryId\":");
        try std.json.Stringify.value(entry.id, .{}, &out.writer);
        try out.writer.writeAll(",\"text\":");
        try std.json.Stringify.value(entry.content, .{}, &out.writer);
        try out.writer.writeByte('}');
        count += 1;
    }
    try out.writer.writeAll("]}");
    return try out.toOwnedSlice();
}

pub fn formatLastAssistantTextJson(gpa: std.mem.Allocator, sess: *const session_mod.Session) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"text\":");
    try writeNullableString(&out.writer, sess.lastAssistantText());
    try out.writer.writeByte('}');
    return try out.toOwnedSlice();
}

fn countToolCalls(gpa: std.mem.Allocator, raw: []const u8) usize {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return 0;
    defer parsed.deinit();
    return if (parsed.value == .array) parsed.value.array.items.len else 0;
}

fn estimateContextTokens(gpa: std.mem.Allocator, sess: *const session_mod.Session) !u64 {
    const branch = try sess.contextEntries(gpa);
    defer gpa.free(branch);
    var i = branch.len;
    while (i > 0) {
        i -= 1;
        const entry = branch[i];
        if (!std.mem.eql(u8, entry.role, "assistant")) continue;
        const reported = entry.meta.usage_input + entry.meta.usage_output + entry.meta.usage_cache_read + entry.meta.usage_cache_write;
        if (reported > 0) return reported;
    }
    var chars: u64 = 0;
    for (branch) |entry| chars +|= @intCast(entry.content.len + entry.meta.thinking.len);
    return @max(1, (chars + 3) / 4);
}

pub fn formatSessionStatsJson(
    gpa: std.mem.Allocator,
    sess: *const session_mod.Session,
    session_file: ?[]const u8,
    context_window: u64,
) ![]u8 {
    var users: u64 = 0;
    var assistants: u64 = 0;
    var tool_results: u64 = 0;
    var tool_calls: u64 = 0;
    var input: u64 = 0;
    var output: u64 = 0;
    var cache_read: u64 = 0;
    var cache_write: u64 = 0;
    var cost: f64 = 0;
    for (sess.entries.items) |entry| {
        if (std.mem.eql(u8, entry.role, "user")) users += 1;
        if (std.mem.eql(u8, entry.role, "assistant")) assistants += 1;
        if (std.mem.eql(u8, entry.role, "tool")) tool_results += 1;
        if (entry.tool_calls_json) |raw| tool_calls += countToolCalls(gpa, raw);
        input +|= entry.meta.usage_input;
        output +|= entry.meta.usage_output;
        cache_read +|= entry.meta.usage_cache_read;
        cache_write +|= entry.meta.usage_cache_write;
        cost += entry.meta.cost_total;
    }
    const total = input +| output +| cache_read +| cache_write;

    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"sessionFile\":");
    try writeNullableString(&out.writer, session_file);
    try out.writer.writeAll(",\"sessionId\":");
    try std.json.Stringify.value(sess.id, .{}, &out.writer);
    try out.writer.print(",\"userMessages\":{d},\"assistantMessages\":{d},\"toolCalls\":{d},\"toolResults\":{d},\"totalMessages\":{d}", .{ users, assistants, tool_calls, tool_results, users + assistants + tool_results });
    try out.writer.print(",\"tokens\":{{\"input\":{d},\"output\":{d},\"cacheRead\":{d},\"cacheWrite\":{d},\"total\":{d}}},\"cost\":{d}", .{ input, output, cache_read, cache_write, total, cost });
    if (context_window > 0) {
        const context_tokens = try estimateContextTokens(gpa, sess);
        const percent = @min(@as(u64, 100), @divFloor(context_tokens *| 100, context_window));
        try out.writer.print(",\"contextUsage\":{{\"tokens\":{d},\"contextWindow\":{d},\"percent\":{d}}}", .{ context_tokens, context_window, percent });
    }
    try out.writer.writeByte('}');
    return try out.toOwnedSlice();
}

fn frontmatterDescription(content: []const u8) []const u8 {
    var lines = std.mem.splitScalar(u8, content, '\n');
    const first = std.mem.trim(u8, lines.next() orelse return "", " \t\r");
    if (!std.mem.eql(u8, first, "---")) return "";
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.eql(u8, line, "---")) break;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        if (!std.mem.eql(u8, std.mem.trim(u8, line[0..colon], " \t"), "description")) continue;
        var value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        if (value.len >= 2 and ((value[0] == '"' and value[value.len - 1] == '"') or (value[0] == '\'' and value[value.len - 1] == '\''))) value = value[1 .. value.len - 1];
        return value;
    }
    return "";
}

fn locationFor(path: []const u8, cwd: []const u8, agent_dir: ?[]const u8) []const u8 {
    if (std.mem.startsWith(u8, path, cwd)) return "project";
    if (agent_dir) |dir| if (std.mem.startsWith(u8, path, dir)) return "user";
    return "path";
}

pub const ExtensionCommandInfo = struct {
    name: []const u8,
    description: []const u8 = "",
    argument_hint: ?[]const u8 = null,
    extension_name: []const u8,
    entry_path: []const u8 = "",
};

pub fn formatCommandsJson(
    gpa: std.mem.Allocator,
    extension_commands: []const ExtensionCommandInfo,
    prompt_templates: []const prompts_mod.PromptTemplate,
    skills: []const skills_mod.Skill,
    cwd: []const u8,
    agent_dir: ?[]const u8,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"commands\":[");
    var count: usize = 0;
    for (extension_commands) |command| {
        if (count > 0) try out.writer.writeByte(',');
        try out.writer.writeAll("{\"name\":");
        try std.json.Stringify.value(command.name, .{}, &out.writer);
        if (command.description.len > 0) {
            try out.writer.writeAll(",\"description\":");
            try std.json.Stringify.value(command.description, .{}, &out.writer);
        }
        if (command.argument_hint) |argument_hint| {
            try out.writer.writeAll(",\"argumentHint\":");
            try std.json.Stringify.value(argument_hint, .{}, &out.writer);
        }
        try out.writer.writeAll(",\"source\":\"extension\",\"extension\":");
        try std.json.Stringify.value(command.extension_name, .{}, &out.writer);
        if (command.entry_path.len > 0) {
            try out.writer.writeAll(",\"path\":");
            try std.json.Stringify.value(command.entry_path, .{}, &out.writer);
        }
        try out.writer.writeByte('}');
        count += 1;
    }
    for (prompt_templates) |template| {
        if (count > 0) try out.writer.writeByte(',');
        try out.writer.writeAll("{\"name\":");
        try std.json.Stringify.value(template.name, .{}, &out.writer);
        if (template.description.len > 0) {
            try out.writer.writeAll(",\"description\":");
            try std.json.Stringify.value(template.description, .{}, &out.writer);
        }
        if (template.argument_hint) |argument_hint| {
            try out.writer.writeAll(",\"argumentHint\":");
            try std.json.Stringify.value(argument_hint, .{}, &out.writer);
        }
        try out.writer.writeAll(",\"source\":\"prompt\",\"location\":");
        try std.json.Stringify.value(locationFor(template.path, cwd, agent_dir), .{}, &out.writer);
        try out.writer.writeAll(",\"path\":");
        try std.json.Stringify.value(template.path, .{}, &out.writer);
        try out.writer.writeByte('}');
        count += 1;
    }
    for (skills) |skill| {
        if (count > 0) try out.writer.writeByte(',');
        const name = try std.fmt.allocPrint(gpa, "skill:{s}", .{skill.name});
        defer gpa.free(name);
        try out.writer.writeAll("{\"name\":");
        try std.json.Stringify.value(name, .{}, &out.writer);
        try out.writer.writeAll(",\"description\":");
        try std.json.Stringify.value(skill.description, .{}, &out.writer);
        try out.writer.writeAll(",\"source\":\"skill\",\"location\":");
        try std.json.Stringify.value(locationFor(skill.path, cwd, agent_dir), .{}, &out.writer);
        try out.writer.writeAll(",\"path\":");
        try std.json.Stringify.value(skill.path, .{}, &out.writer);
        try out.writer.writeByte('}');
        count += 1;
    }
    try out.writer.writeAll("]}");
    return try out.toOwnedSlice();
}

pub fn activeContextWindow(model: ?providers.ModelInfo) u64 {
    return if (model) |value| value.context_window else 0;
}

test "RPC entries use durable JSONL shapes and cursor semantics" {
    const gpa = std.testing.allocator;
    var sess = try session_mod.Session.init(gpa, "rpc-data", "/tmp");
    defer sess.deinit();
    const first = try sess.appendMessage(null, "user", "hello", null, null);
    _ = try sess.appendMessage(first, "assistant", "world", null, null);
    const all = try formatEntriesJson(gpa, &sess, null);
    defer gpa.free(all);
    try std.testing.expect(std.mem.indexOf(u8, all, "\"type\":\"message\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, all, "\"leafId\":\"m2\"") != null);
    const tail = try formatEntriesJson(gpa, &sess, first);
    defer gpa.free(tail);
    try std.testing.expect(std.mem.indexOf(u8, tail, "hello") == null);
    try std.testing.expect(std.mem.indexOf(u8, tail, "world") != null);
    try std.testing.expectError(Error.UnknownEntry, formatEntriesJson(gpa, &sess, "missing"));
}

test "RPC tree, fork messages, last text, and stats are structured" {
    const gpa = std.testing.allocator;
    var sess = try session_mod.Session.init(gpa, "rpc-data", "/tmp");
    defer sess.deinit();
    const first = try sess.appendMessage(null, "user", "hello", null, null);
    _ = try sess.appendMessageMeta(first, "assistant", "world", null, "[{\"id\":\"c1\"}]", null, .{
        .usage_input = 10,
        .usage_output = 5,
        .cost_total = 0.25,
    });
    const tree = try formatTreeJson(gpa, &sess);
    defer gpa.free(tree);
    try std.testing.expect(std.mem.indexOf(u8, tree, "\"children\":[{") != null);
    const forks = try formatForkMessagesJson(gpa, &sess);
    defer gpa.free(forks);
    try std.testing.expect(std.mem.indexOf(u8, forks, "\"entryId\":\"m1\"") != null);
    const last = try formatLastAssistantTextJson(gpa, &sess);
    defer gpa.free(last);
    try std.testing.expectEqualStrings("{\"text\":\"world\"}", last);
    const stats = try formatSessionStatsJson(gpa, &sess, "/tmp/s.jsonl", 100);
    defer gpa.free(stats);
    try std.testing.expect(std.mem.indexOf(u8, stats, "\"toolCalls\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, stats, "\"total\":15") != null);
}

test "RPC commands include native extension metadata" {
    const gpa = std.testing.allocator;
    const extensions = [_]ExtensionCommandInfo{.{
        .name = "audit",
        .description = "Audit a path",
        .argument_hint = "<path>",
        .extension_name = "quality",
        .entry_path = "/tmp/quality",
    }};
    const data = try formatCommandsJson(gpa, &extensions, &.{}, &.{}, "/tmp", null);
    defer gpa.free(data);
    try std.testing.expect(std.mem.indexOf(u8, data, "\"source\":\"extension\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, data, "\"argumentHint\":\"<path>\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, data, "\"extension\":\"quality\"") != null);
}
