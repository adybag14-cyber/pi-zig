//! Built-in coding tools: read, write, edit, bash, grep, find, ls.
const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");
const truncate_mod = @import("truncate.zig");

pub const ToolResult = struct {
    content: []u8,
    is_error: bool,

    pub fn deinit(self: *ToolResult, gpa: std.mem.Allocator) void {
        gpa.free(self.content);
        self.* = undefined;
    }
};

pub const ToolContext = struct {
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    /// Cooperative abort: checked around long tools (bash).
    abort_flag: ?*bool = null,
};

pub const ToolName = enum {
    read,
    write,
    edit,
    bash,
    grep,
    find,
    ls,

    pub fn fromString(s: []const u8) ?ToolName {
        inline for (std.meta.fields(ToolName)) |f| {
            if (std.mem.eql(u8, s, f.name)) return @enumFromInt(f.value);
        }
        return null;
    }

    pub fn asString(self: ToolName) []const u8 {
        return @tagName(self);
    }
};

pub const all_tool_names = [_][]const u8{ "read", "write", "edit", "bash", "grep", "find", "ls" };

pub const ToolFilter = struct {
    /// If non-null, only these tools are enabled.
    allow: ?[]const []const u8 = null,
    /// Tools to exclude (applied after allow).
    exclude: ?[]const []const u8 = null,
    no_tools: bool = false,

    pub fn isEnabled(self: ToolFilter, name: []const u8) bool {
        if (self.no_tools) return false;
        if (self.allow) |a| {
            var found = false;
            for (a) |t| {
                if (std.mem.eql(u8, t, name)) {
                    found = true;
                    break;
                }
            }
            if (!found) return false;
        }
        if (self.exclude) |ex| {
            for (ex) |t| {
                if (std.mem.eql(u8, t, name)) return false;
            }
        }
        return true;
    }

    pub fn enabledNames(self: ToolFilter, gpa: std.mem.Allocator) ![]const []const u8 {
        var list: std.ArrayList([]const u8) = .empty;
        errdefer list.deinit(gpa);
        for (all_tool_names) |n| {
            if (self.isEnabled(n)) try list.append(gpa, n);
        }
        return try list.toOwnedSlice(gpa);
    }
};

// Schemas aligned with upstream pi-coding-agent tools (plus legacy aliases accepted at execute time).
const schema_read =
    \\{"type":"function","function":{"name":"read","description":"Read a file from the filesystem. Supports optional 1-indexed line offset and limit.","parameters":{"type":"object","properties":{"path":{"type":"string","description":"Path to the file to read (relative or absolute)"},"offset":{"type":"number","description":"Line number to start reading from (1-indexed)"},"limit":{"type":"number","description":"Maximum number of lines to read"}},"required":["path"]}}}
;
const schema_write =
    \\{"type":"function","function":{"name":"write","description":"Write content to a file, creating parent directories as needed.","parameters":{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}}}
;
const schema_edit =
    \\{"type":"function","function":{"name":"edit","description":"Apply one or more exact-string replacements in a file. Prefer edits[] with oldText/newText (upstream pi). Legacy old_string/new_string also accepted.","parameters":{"type":"object","properties":{"path":{"type":"string"},"edits":{"type":"array","items":{"type":"object","properties":{"oldText":{"type":"string"},"newText":{"type":"string"}},"required":["oldText","newText"]}},"old_string":{"type":"string"},"new_string":{"type":"string"},"oldText":{"type":"string"},"newText":{"type":"string"}},"required":["path"]}}}
;
const schema_bash =
    \\{"type":"function","function":{"name":"bash","description":"Run a shell command and return stdout, stderr, and exit code. Optional timeout in seconds.","parameters":{"type":"object","properties":{"command":{"type":"string"},"timeout":{"type":"number","description":"Timeout in seconds (default 120)"}},"required":["command"]}}}
;
const schema_grep =
    \\{"type":"function","function":{"name":"grep","description":"Search files for a pattern. Uses regex when possible (rg if available); set literal=true for substring match.","parameters":{"type":"object","properties":{"pattern":{"type":"string"},"path":{"type":"string"},"glob":{"type":"string"},"ignoreCase":{"type":"boolean"},"literal":{"type":"boolean"},"limit":{"type":"number"},"context":{"type":"number","description":"Lines of context before/after match"}},"required":["pattern"]}}}
;
const schema_find =
    \\{"type":"function","function":{"name":"find","description":"Find files by glob-like pattern (* and **).","parameters":{"type":"object","properties":{"pattern":{"type":"string"},"path":{"type":"string"},"limit":{"type":"number"}},"required":["pattern"]}}}
;
const schema_ls =
    \\{"type":"function","function":{"name":"ls","description":"List directory entries.","parameters":{"type":"object","properties":{"path":{"type":"string"},"limit":{"type":"number"}},"required":[]}}}
;

fn schemaFor(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "read")) return schema_read;
    if (std.mem.eql(u8, name, "write")) return schema_write;
    if (std.mem.eql(u8, name, "edit")) return schema_edit;
    if (std.mem.eql(u8, name, "bash")) return schema_bash;
    if (std.mem.eql(u8, name, "grep")) return schema_grep;
    if (std.mem.eql(u8, name, "find")) return schema_find;
    if (std.mem.eql(u8, name, "ls")) return schema_ls;
    return null;
}

/// Full OpenAI tools array for enabled tools (caller frees).
/// Includes built-in suite plus monorepo extended tool shards when not filtered out.
pub fn toolSchemasJson(gpa: std.mem.Allocator, filter: ToolFilter) ![]u8 {
    const extended = @import("tools_extended.zig");
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "[");
    var first = true;
    for (all_tool_names) |n| {
        if (!filter.isEnabled(n)) continue;
        const s = schemaFor(n) orelse continue;
        if (!first) try out.append(gpa, ',');
        first = false;
        try out.appendSlice(gpa, s);
    }
    // Merge extended catalog tools (product surface from tools_shard_*)
    if (!filter.no_tools) {
        const ext_json = try extended.openAiToolsJson(gpa);
        defer gpa.free(ext_json);
        if (ext_json.len >= 2) {
            const inner = ext_json[1 .. ext_json.len - 1];
            if (inner.len > 0) {
                if (!first) try out.append(gpa, ',');
                try out.appendSlice(gpa, inner);
                first = false;
            }
        }
    }
    try out.appendSlice(gpa, "]");
    return try out.toOwnedSlice(gpa);
}

/// Default full schema JSON (all tools) as a static string for simple cases.
pub const tool_schemas_json_all =
    \\[{"type":"function","function":{"name":"read","description":"Read a file from the filesystem.","parameters":{"type":"object","properties":{"path":{"type":"string","description":"Path to the file to read"}},"required":["path"]}}},{"type":"function","function":{"name":"write","description":"Write content to a file, creating parent directories as needed.","parameters":{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}}},{"type":"function","function":{"name":"edit","description":"Replace an exact string in a file.","parameters":{"type":"object","properties":{"path":{"type":"string"},"old_string":{"type":"string"},"new_string":{"type":"string"}},"required":["path","old_string","new_string"]}}},{"type":"function","function":{"name":"bash","description":"Run a shell command and return stdout, stderr, and exit code.","parameters":{"type":"object","properties":{"command":{"type":"string"}},"required":["command"]}}},{"type":"function","function":{"name":"grep","description":"Search files for a pattern.","parameters":{"type":"object","properties":{"pattern":{"type":"string"},"path":{"type":"string"},"glob":{"type":"string"},"ignoreCase":{"type":"boolean"},"limit":{"type":"number"}},"required":["pattern"]}}},{"type":"function","function":{"name":"find","description":"Find files by glob-like pattern.","parameters":{"type":"object","properties":{"pattern":{"type":"string"},"path":{"type":"string"},"limit":{"type":"number"}},"required":["pattern"]}}},{"type":"function","function":{"name":"ls","description":"List directory entries.","parameters":{"type":"object","properties":{"path":{"type":"string"},"limit":{"type":"number"}},"required":[]}}}]
;

pub fn execute(ctx: ToolContext, name: []const u8, arguments_json: []const u8) !ToolResult {
    if (std.mem.eql(u8, name, "read")) return executeRead(ctx, arguments_json);
    if (std.mem.eql(u8, name, "write")) return executeWrite(ctx, arguments_json);
    if (std.mem.eql(u8, name, "edit")) return executeEdit(ctx, arguments_json);
    if (std.mem.eql(u8, name, "bash")) return executeBash(ctx, arguments_json);
    if (std.mem.eql(u8, name, "grep")) return executeGrep(ctx, arguments_json);
    if (std.mem.eql(u8, name, "find")) return executeFind(ctx, arguments_json);
    if (std.mem.eql(u8, name, "ls")) return executeLs(ctx, arguments_json);
    // Monorepo extended tools (tools_shard_*) — real product dispatch path
    const extended = @import("tools_extended.zig");
    if (try extended.execute(ctx.gpa, name, arguments_json)) |content| {
        return try maybeTruncate(ctx.gpa, content, false);
    }
    return try errMsg(ctx.gpa, "unknown tool: {s}", .{name});
}

fn ownedResult(msg: []u8, is_error: bool) ToolResult {
    return .{ .content = msg, .is_error = is_error };
}

/// Apply upstream-aligned output truncation (2000 lines / 50KB) to tool output.
/// Takes ownership of `msg` and may free/replace it.
fn maybeTruncate(gpa: std.mem.Allocator, msg: []u8, is_error: bool) !ToolResult {
    // Errors stay short; still cap pathological messages.
    if (is_error and msg.len < 4096) return ownedResult(msg, true);
    const truncated = try truncate_mod.apply(gpa, msg);
    gpa.free(msg);
    return ownedResult(truncated, is_error);
}

fn errMsg(gpa: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !ToolResult {
    return ownedResult(try std.fmt.allocPrint(gpa, fmt, args), true);
}

fn okMsg(gpa: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !ToolResult {
    return ownedResult(try std.fmt.allocPrint(gpa, fmt, args), false);
}

fn resolvePath(gpa: std.mem.Allocator, cwd: []const u8, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path)) return try gpa.dupe(u8, path);
    return try std.fs.path.join(gpa, &.{ cwd, path });
}

fn parseStringField(gpa: std.mem.Allocator, arguments_json: []const u8, field: []const u8) !?[]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, arguments_json, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const v = parsed.value.object.get(field) orelse return null;
    if (v != .string) return null;
    return try gpa.dupe(u8, v.string);
}

/// Path field: accepts `path` or upstream alias `file_path`.
fn parsePathField(gpa: std.mem.Allocator, arguments_json: []const u8) !?[]u8 {
    if (try parseStringField(gpa, arguments_json, "path")) |p| return p;
    return try parseStringField(gpa, arguments_json, "file_path");
}

fn parseBoolField(gpa: std.mem.Allocator, arguments_json: []const u8, field: []const u8) bool {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, arguments_json, .{}) catch return false;
    defer parsed.deinit();
    if (parsed.value != .object) return false;
    const v = parsed.value.object.get(field) orelse return false;
    return switch (v) {
        .bool => |b| b,
        else => false,
    };
}

fn parseIntField(gpa: std.mem.Allocator, arguments_json: []const u8, field: []const u8, default: i64) i64 {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, arguments_json, .{}) catch return default;
    defer parsed.deinit();
    if (parsed.value != .object) return default;
    const v = parsed.value.object.get(field) orelse return default;
    return switch (v) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => default,
    };
}

fn executeRead(ctx: ToolContext, arguments_json: []const u8) !ToolResult {
    const path_owned = try parsePathField(ctx.gpa, arguments_json) orelse
        return try errMsg(ctx.gpa, "read: missing path", .{});
    defer ctx.gpa.free(path_owned);

    const offset_raw = parseIntField(ctx.gpa, arguments_json, "offset", 0); // 0 = unset; 1-indexed when set
    const limit_raw = parseIntField(ctx.gpa, arguments_json, "limit", 0); // 0 = no limit

    const full = try resolvePath(ctx.gpa, ctx.cwd, path_owned);
    defer ctx.gpa.free(full);

    const data = std.Io.Dir.cwd().readFileAlloc(ctx.io, full, ctx.gpa, .limited(8 * 1024 * 1024)) catch |err| {
        return try errMsg(ctx.gpa, "read failed: {s}", .{@errorName(err)});
    };

    // Apply line offset/limit when requested (upstream pi read tool)
    if (offset_raw > 0 or limit_raw > 0) {
        defer ctx.gpa.free(data);
        const start_line: usize = if (offset_raw > 0) @intCast(offset_raw) else 1;
        const max_lines: ?usize = if (limit_raw > 0) @intCast(limit_raw) else null;
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(ctx.gpa);
        var line_no: usize = 1;
        var kept: usize = 0;
        var it = std.mem.splitScalar(u8, data, '\n');
        while (it.next()) |line| {
            defer line_no += 1;
            if (line_no < start_line) continue;
            if (max_lines) |ml| {
                if (kept >= ml) break;
            }
            if (out.items.len > 0) try out.append(ctx.gpa, '\n');
            try out.appendSlice(ctx.gpa, line);
            kept += 1;
        }
        return try maybeTruncate(ctx.gpa, try out.toOwnedSlice(ctx.gpa), false);
    }

    return try maybeTruncate(ctx.gpa, data, false);
}

fn executeWrite(ctx: ToolContext, arguments_json: []const u8) !ToolResult {
    const path_owned = try parsePathField(ctx.gpa, arguments_json) orelse
        return try errMsg(ctx.gpa, "write: missing path", .{});
    defer ctx.gpa.free(path_owned);
    const content_owned = try parseStringField(ctx.gpa, arguments_json, "content") orelse
        return try errMsg(ctx.gpa, "write: missing content", .{});
    defer ctx.gpa.free(content_owned);

    const full = try resolvePath(ctx.gpa, ctx.cwd, path_owned);
    defer ctx.gpa.free(full);

    if (std.fs.path.dirname(full)) |parent| {
        if (parent.len > 0) {
            std.Io.Dir.cwd().createDirPath(ctx.io, parent) catch |err| {
                return try errMsg(ctx.gpa, "write mkdir failed: {s}", .{@errorName(err)});
            };
        }
    }

    std.Io.Dir.cwd().writeFile(ctx.io, .{
        .sub_path = full,
        .data = content_owned,
    }) catch |err| {
        return try errMsg(ctx.gpa, "write failed: {s}", .{@errorName(err)});
    };

    return try okMsg(ctx.gpa, "Wrote {d} bytes to {s}", .{ content_owned.len, path_owned });
}

const EditPair = struct { old: []const u8, new: []const u8 };

fn collectEditPairs(gpa: std.mem.Allocator, arguments_json: []const u8) ![]EditPair {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, arguments_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidArgs;

    var list: std.ArrayList(EditPair) = .empty;
    errdefer {
        for (list.items) |p| {
            gpa.free(p.old);
            gpa.free(p.new);
        }
        list.deinit(gpa);
    }

    // Upstream: edits: [{oldText, newText}, ...]
    if (parsed.value.object.get("edits")) |ev| {
        if (ev == .array) {
            for (ev.array.items) |item| {
                if (item != .object) continue;
                const ot = item.object.get("oldText") orelse item.object.get("old_string") orelse continue;
                const nt = item.object.get("newText") orelse item.object.get("new_string") orelse continue;
                if (ot != .string or nt != .string) continue;
                try list.append(gpa, .{
                    .old = try gpa.dupe(u8, ot.string),
                    .new = try gpa.dupe(u8, nt.string),
                });
            }
        }
    }

    // Single-edit aliases: oldText/newText or old_string/new_string
    if (list.items.len == 0) {
        const old = parsed.value.object.get("oldText") orelse parsed.value.object.get("old_string");
        const newv = parsed.value.object.get("newText") orelse parsed.value.object.get("new_string");
        if (old != null and newv != null and old.? == .string and newv.? == .string) {
            try list.append(gpa, .{
                .old = try gpa.dupe(u8, old.?.string),
                .new = try gpa.dupe(u8, newv.?.string),
            });
        }
    }

    if (list.items.len == 0) return error.MissingEdits;
    return try list.toOwnedSlice(gpa);
}

fn freeEditPairs(gpa: std.mem.Allocator, pairs: []EditPair) void {
    for (pairs) |p| {
        gpa.free(p.old);
        gpa.free(p.new);
    }
    gpa.free(pairs);
}

fn executeEdit(ctx: ToolContext, arguments_json: []const u8) !ToolResult {
    const path_owned = try parsePathField(ctx.gpa, arguments_json) orelse
        return try errMsg(ctx.gpa, "edit: missing path", .{});
    defer ctx.gpa.free(path_owned);

    const pairs = collectEditPairs(ctx.gpa, arguments_json) catch |err| switch (err) {
        error.MissingEdits => return try errMsg(ctx.gpa, "edit: missing edits[] or oldText/newText (or old_string/new_string)", .{}),
        else => return try errMsg(ctx.gpa, "edit: invalid arguments", .{}),
    };
    defer freeEditPairs(ctx.gpa, pairs);

    const full = try resolvePath(ctx.gpa, ctx.cwd, path_owned);
    defer ctx.gpa.free(full);

    const original = std.Io.Dir.cwd().readFileAlloc(ctx.io, full, ctx.gpa, .limited(8 * 1024 * 1024)) catch |err| {
        return try errMsg(ctx.gpa, "edit read failed: {s}", .{@errorName(err)});
    };
    defer ctx.gpa.free(original);

    // Match ALL edits against the original file (upstream non-incremental semantics),
    // then apply from highest index to lowest so positions stay valid.
    const Match = struct { start: usize, end: usize, new: []const u8, old: []const u8 };
    var matches: std.ArrayList(Match) = .empty;
    defer matches.deinit(ctx.gpa);

    for (pairs) |pair| {
        const found = findUniqueMatch(original, pair.old) orelse {
            // Fuzzy: collapse whitespace runs and retry
            const fuzzy = try findFuzzyUniqueMatch(ctx.gpa, original, pair.old);
            if (fuzzy) |f| {
                try matches.append(ctx.gpa, .{ .start = f.start, .end = f.end, .new = pair.new, .old = pair.old });
                continue;
            }
            return try errMsg(ctx.gpa, "edit: oldText not found: {s}", .{truncatePreview(pair.old, 60)});
        };
        try matches.append(ctx.gpa, .{ .start = found.start, .end = found.end, .new = pair.new, .old = pair.old });
    }

    // Overlap check
    for (matches.items, 0..) |a, i| {
        for (matches.items[i + 1 ..]) |b| {
            if (!(a.end <= b.start or b.end <= a.start)) {
                return try errMsg(ctx.gpa, "edit: overlapping edits are not allowed", .{});
            }
        }
    }

    // Sort by start descending
    std.mem.sort(Match, matches.items, {}, struct {
        fn less(_: void, a: Match, b: Match) bool {
            return a.start > b.start;
        }
    }.less);

    var working = try ctx.gpa.dupe(u8, original);
    defer ctx.gpa.free(working);
    var diff_summary: std.ArrayList(u8) = .empty;
    defer diff_summary.deinit(ctx.gpa);

    for (matches.items) |m| {
        var next: std.ArrayList(u8) = .empty;
        defer next.deinit(ctx.gpa);
        try next.appendSlice(ctx.gpa, working[0..m.start]);
        try next.appendSlice(ctx.gpa, m.new);
        try next.appendSlice(ctx.gpa, working[m.end..]);
        ctx.gpa.free(working);
        working = try next.toOwnedSlice(ctx.gpa);
        try diff_summary.appendSlice(ctx.gpa, "@@ edit\n- ");
        try diff_summary.appendSlice(ctx.gpa, truncatePreview(m.old, 80));
        try diff_summary.appendSlice(ctx.gpa, "\n+ ");
        try diff_summary.appendSlice(ctx.gpa, truncatePreview(m.new, 80));
        try diff_summary.append(ctx.gpa, '\n');
    }

    std.Io.Dir.cwd().writeFile(ctx.io, .{
        .sub_path = full,
        .data = working,
    }) catch |err| {
        return try errMsg(ctx.gpa, "edit write failed: {s}", .{@errorName(err)});
    };

    return try okMsg(ctx.gpa, "Edited {s} ({d} replacement(s))\n{s}", .{ path_owned, matches.items.len, diff_summary.items });
}

const Span = struct { start: usize, end: usize };

fn findUniqueMatch(hay: []const u8, needle: []const u8) ?Span {
    if (needle.len == 0) return null;
    const idx = std.mem.indexOf(u8, hay, needle) orelse return null;
    if (std.mem.indexOfPos(u8, hay, idx + needle.len, needle) != null) return null;
    return .{ .start = idx, .end = idx + needle.len };
}

/// Collapse runs of whitespace to single space for fuzzy unique match (models often drift on indent).
fn collapseWs(gpa: std.mem.Allocator, s: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var i: usize = 0;
    var in_ws = false;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
            if (!in_ws) {
                try out.append(gpa, ' ');
                in_ws = true;
            }
        } else {
            try out.append(gpa, c);
            in_ws = false;
        }
    }
    return try out.toOwnedSlice(gpa);
}

fn findFuzzyUniqueMatch(gpa: std.mem.Allocator, hay: []const u8, needle: []const u8) !?Span {
    const n_col = try collapseWs(gpa, needle);
    defer gpa.free(n_col);
    if (n_col.len == 0) return null;

    // Scan original by expanding windows; map collapsed needle back to original span.
    // Strategy: find all substrings of hay whose collapse equals n_col — require exactly one.
    var first: ?Span = null;
    var start: usize = 0;
    while (start < hay.len) : (start += 1) {
        // Expand end until collapsed length >= needle collapsed length
        var end = start;
        var col: std.ArrayList(u8) = .empty;
        defer col.deinit(gpa);
        var in_ws = false;
        while (end < hay.len and col.items.len < n_col.len) {
            const c = hay[end];
            end += 1;
            if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
                if (!in_ws and col.items.len > 0) {
                    try col.append(gpa, ' ');
                    in_ws = true;
                }
            } else {
                try col.append(gpa, c);
                in_ws = false;
            }
        }
        // Trim trailing space from col for compare
        var cslice = col.items;
        while (cslice.len > 0 and cslice[cslice.len - 1] == ' ') cslice = cslice[0 .. cslice.len - 1];
        var nslice = n_col;
        while (nslice.len > 0 and nslice[nslice.len - 1] == ' ') nslice = nslice[0 .. nslice.len - 1];
        // Also trim leading
        while (cslice.len > 0 and cslice[0] == ' ') cslice = cslice[1..];
        while (nslice.len > 0 and nslice[0] == ' ') nslice = nslice[1..];
        if (std.mem.eql(u8, cslice, nslice)) {
            if (first != null) return null; // not unique
            first = .{ .start = start, .end = end };
        }
    }
    return first;
}

fn truncatePreview(s: []const u8, max: usize) []const u8 {
    if (s.len <= max) return s;
    return s[0..max];
}

fn executeBash(ctx: ToolContext, arguments_json: []const u8) !ToolResult {
    const command = try parseStringField(ctx.gpa, arguments_json, "command") orelse
        return try errMsg(ctx.gpa, "bash: missing command", .{});
    defer ctx.gpa.free(command);

    if (ctx.abort_flag) |f| {
        if (f.*) return try errMsg(ctx.gpa, "bash: aborted before start", .{});
    }

    const timeout_sec: i64 = @intCast(@max(1, parseIntField(ctx.gpa, arguments_json, "timeout", 120)));
    const argv: []const []const u8 = if (builtin.os.tag == .windows)
        &[_][]const u8{ "cmd.exe", "/C", command }
    else
        &[_][]const u8{ "sh", "-c", command };

    // Mid-process kill: spawn Child, poll abort_flag, kill on abort or timeout.
    return executeBashKillable(ctx, argv, timeout_sec);
}

fn executeBashKillable(ctx: ToolContext, argv: []const []const u8, timeout_sec: i64) !ToolResult {
    // When no abort flag, use reliable process.run (timeout only).
    if (ctx.abort_flag == null) {
        const run_result = std.process.run(ctx.gpa, ctx.io, .{
            .argv = argv,
            .cwd = .{ .path = ctx.cwd },
            .stdout_limit = .limited(1024 * 1024),
            .stderr_limit = .limited(1024 * 1024),
            .timeout = .{ .duration = .{ .raw = .fromSeconds(timeout_sec), .clock = .real } },
        }) catch |err| {
            if (err == error.Timeout) return try errMsg(ctx.gpa, "bash: timed out after {d}s", .{timeout_sec});
            return try errMsg(ctx.gpa, "bash spawn failed: {s}", .{@errorName(err)});
        };
        defer ctx.gpa.free(run_result.stdout);
        defer ctx.gpa.free(run_result.stderr);
        const code: i32 = switch (run_result.term) {
            .exited => |c| @intCast(c),
            .signal => -1,
            .stopped => -1,
            .unknown => |u| -@as(i32, @intCast(u)),
        };
        const body = try std.fmt.allocPrint(ctx.gpa, "exit={d}\nstdout:\n{s}\nstderr:\n{s}", .{
            code, run_result.stdout, run_result.stderr,
        });
        return try maybeTruncate(ctx.gpa, body, code != 0);
    }

    // Abort-capable path: Child + OS force-kill (not Child.kill — that races with wait).
    // Waiter owns wait/cleanup; main only signals the process.
    var child = std.process.spawn(ctx.io, .{
        .argv = argv,
        .cwd = .{ .path = ctx.cwd },
        .stdout = .pipe,
        .stderr = .pipe,
        .stdin = .ignore,
    }) catch |err| {
        return try errMsg(ctx.gpa, "bash spawn failed: {s}", .{@errorName(err)});
    };

    const WaitState = struct {
        term: ?std.process.Child.Term = null,
        done: std.atomic.Value(bool) = .init(false),
        child: *std.process.Child,
        io: Io,
        gpa: std.mem.Allocator,
        stdout: []u8 = &.{},
        stderr: []u8 = &.{},
    };
    var state = WaitState{ .child = &child, .io = ctx.io, .gpa = ctx.gpa };

    // Drain stdout/stderr concurrently so full pipes don't deadlock wait.
    const PipeState = struct {
        file: ?std.Io.File,
        io: Io,
        gpa: std.mem.Allocator,
        out: *[]u8,
    };
    const drainPipe = struct {
        fn run(ps: *PipeState) void {
            const f = ps.file orelse {
                ps.out.* = ps.gpa.alloc(u8, 0) catch &.{};
                return;
            };
            var aw: std.Io.Writer.Allocating = .init(ps.gpa);
            defer aw.deinit();
            var buf: [4096]u8 = undefined;
            while (true) {
                var slice = [_][]u8{buf[0..]};
                const n = f.readStreaming(ps.io, &slice) catch break;
                if (n == 0) break;
                aw.writer.writeAll(buf[0..n]) catch break;
                if (aw.written().len > 1024 * 1024) break;
            }
            ps.out.* = aw.toOwnedSlice() catch &.{};
        }
    }.run;

    var stdout_owned: []u8 = &.{};
    var stderr_owned: []u8 = &.{};
    var out_ps = PipeState{ .file = child.stdout, .io = ctx.io, .gpa = ctx.gpa, .out = &stdout_owned };
    var err_ps = PipeState{ .file = child.stderr, .io = ctx.io, .gpa = ctx.gpa, .out = &stderr_owned };
    const out_thr = try std.Thread.spawn(.{}, drainPipe, .{&out_ps});
    const err_thr = try std.Thread.spawn(.{}, drainPipe, .{&err_ps});

    const waiter = try std.Thread.spawn(.{}, struct {
        fn run(s: *WaitState) void {
            defer s.done.store(true, .release);
            s.term = s.child.wait(s.io) catch null;
        }
    }.run, .{&state});

    const deadline_ms: i64 = timeout_sec * 1000;
    var elapsed_ms: i64 = 0;
    var killed_for_abort = false;
    var killed_for_timeout = false;
    while (!state.done.load(.acquire)) {
        if (ctx.abort_flag) |f| {
            if (f.*) {
                forceKillProcess(&child);
                killed_for_abort = true;
                break;
            }
        }
        if (elapsed_ms >= deadline_ms) {
            forceKillProcess(&child);
            killed_for_timeout = true;
            break;
        }
        const st: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(50), .clock = .real } };
        st.sleep(ctx.io) catch {};
        elapsed_ms += 50;
    }
    waiter.join();
    out_thr.join();
    err_thr.join();
    state.stdout = stdout_owned;
    state.stderr = stderr_owned;
    defer if (state.stdout.len > 0) ctx.gpa.free(state.stdout);
    defer if (state.stderr.len > 0) ctx.gpa.free(state.stderr);

    if (killed_for_abort) return try errMsg(ctx.gpa, "bash: aborted (process killed)", .{});
    if (killed_for_timeout) return try errMsg(ctx.gpa, "bash: timed out after {d}s (process killed)", .{timeout_sec});

    const code: i32 = if (state.term) |t| switch (t) {
        .exited => |c| @intCast(c),
        .signal => -1,
        .stopped => -1,
        .unknown => |u| -@as(i32, @intCast(u)),
    } else -1;

    const body = try std.fmt.allocPrint(ctx.gpa, "exit={d}\nstdout:\n{s}\nstderr:\n{s}", .{
        code, state.stdout, state.stderr,
    });
    return try maybeTruncate(ctx.gpa, body, code != 0);
}

/// Signal the OS process without Zig Child cleanup (waiter owns wait/cleanup).
fn forceKillProcess(child: *std.process.Child) void {
    const id = child.id orelse return;
    if (builtin.os.tag == .windows) {
        // Do not call Child.kill — it races with the waiter thread's wait().
        _ = std.os.windows.ntdll.NtTerminateProcess(id, @enumFromInt(1));
    } else {
        std.posix.kill(id, std.posix.SIG.KILL) catch {};
    }
}

/// Try ripgrep for regex search. Returns null if rg is unavailable.
fn tryRipgrep(
    ctx: ToolContext,
    pattern: []const u8,
    search_root: []const u8,
    glob_opt: ?[]const u8,
    ignore_case: bool,
    limit: usize,
    context_lines: usize,
) !?ToolResult {
    var argv_list: std.ArrayList([]const u8) = .empty;
    defer argv_list.deinit(ctx.gpa);
    try argv_list.append(ctx.gpa, "rg");
    try argv_list.append(ctx.gpa, "-n");
    try argv_list.append(ctx.gpa, "--no-heading");
    try argv_list.append(ctx.gpa, "--color");
    try argv_list.append(ctx.gpa, "never");
    if (ignore_case) try argv_list.append(ctx.gpa, "-i");
    if (context_lines > 0) {
        const cstr = try std.fmt.allocPrint(ctx.gpa, "{d}", .{context_lines});
        defer ctx.gpa.free(cstr);
        try argv_list.append(ctx.gpa, "-C");
        try argv_list.append(ctx.gpa, cstr);
    }
    const max_str = try std.fmt.allocPrint(ctx.gpa, "{d}", .{limit});
    defer ctx.gpa.free(max_str);
    try argv_list.append(ctx.gpa, "-m");
    try argv_list.append(ctx.gpa, max_str);
    if (glob_opt) |g| {
        try argv_list.append(ctx.gpa, "-g");
        try argv_list.append(ctx.gpa, g);
    }
    try argv_list.append(ctx.gpa, "--");
    try argv_list.append(ctx.gpa, pattern);
    try argv_list.append(ctx.gpa, search_root);

    const run_result = std.process.run(ctx.gpa, ctx.io, .{
        .argv = argv_list.items,
        .cwd = .{ .path = ctx.cwd },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(64 * 1024),
        .timeout = .{ .duration = .{
            .raw = .fromSeconds(60),
            .clock = .real,
        } },
    }) catch return null;
    defer ctx.gpa.free(run_result.stdout);
    defer ctx.gpa.free(run_result.stderr);

    // rg not found / spawn failure already caught; exit 2 usually means error, 1 no matches
    const code: u8 = switch (run_result.term) {
        .exited => |c| @intCast(c),
        else => return null,
    };
    // If rg missing, Windows often returns non-zero with empty and error message
    if (code > 1 and run_result.stdout.len == 0) {
        if (std.mem.indexOf(u8, run_result.stderr, "not recognized") != null or
            std.mem.indexOf(u8, run_result.stderr, "not found") != null)
            return null;
    }
    if (run_result.stdout.len == 0) {
        return try okMsg(ctx.gpa, "No matches for {s}", .{pattern});
    }
    return try maybeTruncate(ctx.gpa, try ctx.gpa.dupe(u8, run_result.stdout), false);
}

/// Simple glob match: supports `*` (segment) and `**` (recursive path).
pub fn matchGlob(pattern: []const u8, path: []const u8) bool {
    // Normalize to forward slashes for matching
    return matchGlobRec(pattern, path);
}

fn matchGlobRec(pattern: []const u8, path: []const u8) bool {
    var pi: usize = 0;
    var si: usize = 0;
    while (pi < pattern.len) {
        if (pi + 1 < pattern.len and pattern[pi] == '*' and pattern[pi + 1] == '*') {
            // ** — match any number of path chars
            pi += 2;
            if (pi < pattern.len and (pattern[pi] == '/' or pattern[pi] == '\\')) pi += 1;
            if (pi >= pattern.len) return true;
            while (si <= path.len) : (si += 1) {
                if (matchGlobRec(pattern[pi..], path[si..])) return true;
            }
            return false;
        } else if (pattern[pi] == '*') {
            pi += 1;
            // match within segment (no /)
            if (pi >= pattern.len) {
                // rest of segment only
                while (si < path.len and path[si] != '/' and path[si] != '\\') si += 1;
                return si >= path.len or path[si] == '/' or path[si] == '\\' or matchGlobRec(pattern[pi..], path[si..]);
            }
            while (si < path.len) {
                if (path[si] == '/' or path[si] == '\\') break;
                if (matchGlobRec(pattern[pi..], path[si..])) return true;
                si += 1;
            }
            return matchGlobRec(pattern[pi..], path[si..]);
        } else if (pattern[pi] == '?' ) {
            if (si >= path.len) return false;
            if (path[si] == '/' or path[si] == '\\') return false;
            pi += 1;
            si += 1;
        } else {
            if (si >= path.len) return false;
            const pc = if (pattern[pi] == '\\') '/' else pattern[pi];
            const sc = if (path[si] == '\\') '/' else path[si];
            if (pc != sc) return false;
            pi += 1;
            si += 1;
        }
    }
    return si >= path.len;
}

fn executeGrep(ctx: ToolContext, arguments_json: []const u8) !ToolResult {
    const pattern = try parseStringField(ctx.gpa, arguments_json, "pattern") orelse
        return try errMsg(ctx.gpa, "grep: missing pattern", .{});
    defer ctx.gpa.free(pattern);
    const path_opt = try parseStringField(ctx.gpa, arguments_json, "path");
    defer if (path_opt) |p| ctx.gpa.free(p);
    const glob_opt = try parseStringField(ctx.gpa, arguments_json, "glob");
    defer if (glob_opt) |g| ctx.gpa.free(g);
    const ignore_case = parseBoolField(ctx.gpa, arguments_json, "ignoreCase");
    const literal = parseBoolField(ctx.gpa, arguments_json, "literal");
    const limit: usize = @intCast(@max(1, parseIntField(ctx.gpa, arguments_json, "limit", 100)));
    const context_lines: usize = @intCast(@max(0, parseIntField(ctx.gpa, arguments_json, "context", 0)));

    const search_root = try resolvePath(ctx.gpa, ctx.cwd, path_opt orelse ".");
    defer ctx.gpa.free(search_root);

    // Prefer ripgrep when available for real regex (unless literal=true)
    if (!literal) {
        if (try tryRipgrep(ctx, pattern, search_root, glob_opt, ignore_case, limit, context_lines)) |rg_result| {
            return rg_result;
        }
    }

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(ctx.gpa);
    var matches: usize = 0;

    // If single file
    const is_dir = blk: {
        std.Io.Dir.cwd().access(ctx.io, search_root, .{}) catch {
            return try errMsg(ctx.gpa, "grep: path not found: {s}", .{search_root});
        };
        var d = std.Io.Dir.cwd().openDir(ctx.io, search_root, .{ .iterate = true }) catch {
            break :blk false;
        };
        d.close(ctx.io);
        break :blk true;
    };

    if (!is_dir) {
        try grepFileCtx(ctx, search_root, search_root, pattern, ignore_case, &out, &matches, limit, context_lines);
    } else {
        var dir = std.Io.Dir.cwd().openDir(ctx.io, search_root, .{ .iterate = true }) catch |err| {
            return try errMsg(ctx.gpa, "grep open failed: {s}", .{@errorName(err)});
        };
        defer dir.close(ctx.io);
        var walker = try dir.walk(ctx.gpa);
        defer walker.deinit();
        while (try walker.next(ctx.io)) |entry| {
            if (matches >= limit) break;
            if (entry.kind != .file) continue;
            if (glob_opt) |g| {
                if (!matchGlob(g, entry.path)) continue;
            }
            // skip common heavy dirs
            if (std.mem.indexOf(u8, entry.path, "node_modules") != null) continue;
            if (std.mem.indexOf(u8, entry.path, ".git") != null) continue;
            if (std.mem.indexOf(u8, entry.path, "zig-cache") != null) continue;

            const full = try std.fs.path.join(ctx.gpa, &.{ search_root, entry.path });
            defer ctx.gpa.free(full);
            try grepFileCtx(ctx, full, entry.path, pattern, ignore_case, &out, &matches, limit, context_lines);
        }
    }

    if (out.items.len == 0) {
        return try okMsg(ctx.gpa, "No matches for {s}", .{pattern});
    }
    return try maybeTruncate(ctx.gpa, try out.toOwnedSlice(ctx.gpa), false);
}

fn grepFile(
    ctx: ToolContext,
    full_path: []const u8,
    display_path: []const u8,
    pattern: []const u8,
    ignore_case: bool,
    out: *std.ArrayList(u8),
    matches: *usize,
    limit: usize,
) !void {
    // context_lines not threaded here; fallback path is match lines only (rg handles -C).
    try grepFileCtx(ctx, full_path, display_path, pattern, ignore_case, out, matches, limit, 0);
}

fn grepFileCtx(
    ctx: ToolContext,
    full_path: []const u8,
    display_path: []const u8,
    pattern: []const u8,
    ignore_case: bool,
    out: *std.ArrayList(u8),
    matches: *usize,
    limit: usize,
    context_lines: usize,
) !void {
    const data = std.Io.Dir.cwd().readFileAlloc(ctx.io, full_path, ctx.gpa, .limited(2 * 1024 * 1024)) catch return;
    defer ctx.gpa.free(data);

    // Materialize lines for context windows
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(ctx.gpa);
    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |line| {
        try lines.append(ctx.gpa, line);
    }

    var line_no: usize = 1;
    while (line_no <= lines.items.len) : (line_no += 1) {
        if (matches.* >= limit) return;
        const line = lines.items[line_no - 1];
        const hit = if (ignore_case)
            containsIgnoreCase(line, pattern)
        else
            std.mem.indexOf(u8, line, pattern) != null;
        if (hit) {
            if (context_lines > 0) {
                const start = if (line_no > context_lines) line_no - context_lines else 1;
                const end = @min(lines.items.len, line_no + context_lines);
                var ln = start;
                while (ln <= end) : (ln += 1) {
                    const mark: u8 = if (ln == line_no) ':' else '-';
                    const line_out = try std.fmt.allocPrint(ctx.gpa, "{s}{c}{d}{c}{s}\n", .{ display_path, mark, ln, mark, lines.items[ln - 1] });
                    defer ctx.gpa.free(line_out);
                    try out.appendSlice(ctx.gpa, line_out);
                }
            } else {
                const line_out = try std.fmt.allocPrint(ctx.gpa, "{s}:{d}:{s}\n", .{ display_path, line_no, line });
                defer ctx.gpa.free(line_out);
                try out.appendSlice(ctx.gpa, line_out);
            }
            matches.* += 1;
        }
    }
}

fn containsIgnoreCase(hay: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (hay.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(hay[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn executeFind(ctx: ToolContext, arguments_json: []const u8) !ToolResult {
    const pattern = try parseStringField(ctx.gpa, arguments_json, "pattern") orelse
        return try errMsg(ctx.gpa, "find: missing pattern", .{});
    defer ctx.gpa.free(pattern);
    const path_opt = try parseStringField(ctx.gpa, arguments_json, "path");
    defer if (path_opt) |p| ctx.gpa.free(p);
    const limit: usize = @intCast(@max(1, parseIntField(ctx.gpa, arguments_json, "limit", 1000)));

    const search_root = try resolvePath(ctx.gpa, ctx.cwd, path_opt orelse ".");
    defer ctx.gpa.free(search_root);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(ctx.gpa);
    var count: usize = 0;

    var dir = std.Io.Dir.cwd().openDir(ctx.io, search_root, .{ .iterate = true }) catch |err| {
        return try errMsg(ctx.gpa, "find open failed: {s}", .{@errorName(err)});
    };
    defer dir.close(ctx.io);
    var walker = try dir.walk(ctx.gpa);
    defer walker.deinit();
    while (try walker.next(ctx.io)) |entry| {
        if (count >= limit) break;
        if (entry.kind != .file and entry.kind != .directory) continue;
        if (std.mem.indexOf(u8, entry.path, "node_modules") != null) continue;
        if (std.mem.indexOf(u8, entry.path, ".git") != null) continue;
        if (matchGlob(pattern, entry.path) or matchGlob(pattern, entry.basename)) {
            try out.appendSlice(ctx.gpa, entry.path);
            try out.append(ctx.gpa, '\n');
            count += 1;
        }
    }

    if (out.items.len == 0) {
        return try okMsg(ctx.gpa, "No files matching {s}", .{pattern});
    }
    return try maybeTruncate(ctx.gpa, try out.toOwnedSlice(ctx.gpa), false);
}

fn executeLs(ctx: ToolContext, arguments_json: []const u8) !ToolResult {
    const path_opt = try parseStringField(ctx.gpa, arguments_json, "path");
    defer if (path_opt) |p| ctx.gpa.free(p);
    const limit: usize = @intCast(@max(1, parseIntField(ctx.gpa, arguments_json, "limit", 500)));

    const full = try resolvePath(ctx.gpa, ctx.cwd, path_opt orelse ".");
    defer ctx.gpa.free(full);

    var dir = std.Io.Dir.cwd().openDir(ctx.io, full, .{ .iterate = true }) catch |err| {
        return try errMsg(ctx.gpa, "ls failed: {s}", .{@errorName(err)});
    };
    defer dir.close(ctx.io);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(ctx.gpa);
    var count: usize = 0;
    var it = dir.iterate();
    while (try it.next(ctx.io)) |entry| {
        if (count >= limit) {
            try out.appendSlice(ctx.gpa, "... (limit reached)\n");
            break;
        }
        const kind_ch: u8 = switch (entry.kind) {
            .directory => 'd',
            .file => 'f',
            .sym_link => 'l',
            else => '?',
        };
        const line_out = try std.fmt.allocPrint(ctx.gpa, "{c} {s}\n", .{ kind_ch, entry.name });
        defer ctx.gpa.free(line_out);
        try out.appendSlice(ctx.gpa, line_out);
        count += 1;
    }
    if (out.items.len == 0) {
        return try okMsg(ctx.gpa, "(empty directory)", .{});
    }
    return try maybeTruncate(ctx.gpa, try out.toOwnedSlice(ctx.gpa), false);
}

test "read write edit tools on temp fixture" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];

    const ctx = ToolContext{ .gpa = gpa, .io = io, .cwd = tmp_path };

    var w = try execute(ctx, "write",
        \\{"path":"hello.txt","content":"hello world"}
    );
    defer w.deinit(gpa);
    try std.testing.expect(!w.is_error);

    var r = try execute(ctx, "read",
        \\{"path":"hello.txt"}
    );
    defer r.deinit(gpa);
    try std.testing.expect(!r.is_error);
    try std.testing.expectEqualStrings("hello world", r.content);

    var e = try execute(ctx, "edit",
        \\{"path":"hello.txt","old_string":"world","new_string":"pi"}
    );
    defer e.deinit(gpa);
    try std.testing.expect(!e.is_error);

    var r2 = try execute(ctx, "read",
        \\{"path":"hello.txt"}
    );
    defer r2.deinit(gpa);
    try std.testing.expectEqualStrings("hello pi", r2.content);
}

test "bash tool echoes" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];
    const ctx = ToolContext{ .gpa = gpa, .io = io, .cwd = tmp_path };

    var b = try execute(ctx, "bash",
        \\{"command":"echo pi-bash-ok"}
    );
    defer b.deinit(gpa);
    try std.testing.expect(std.mem.indexOf(u8, b.content, "pi-bash-ok") != null);
    try std.testing.expect(std.mem.indexOf(u8, b.content, "exit=0") != null);
}

test "grep find ls tools" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];
    const ctx = ToolContext{ .gpa = gpa, .io = io, .cwd = tmp_path };

    // setup files
    {
        var w1 = try execute(ctx, "write",
            \\{"path":"a.txt","content":"alpha unique-token beta"}
        );
        defer w1.deinit(gpa);
        var w2 = try execute(ctx, "write",
            \\{"path":"sub/b.md","content":"no match here"}
        );
        defer w2.deinit(gpa);
    }

    var g = try execute(ctx, "grep",
        \\{"pattern":"unique-token"}
    );
    defer g.deinit(gpa);
    try std.testing.expect(!g.is_error);
    try std.testing.expect(std.mem.indexOf(u8, g.content, "unique-token") != null);

    var f = try execute(ctx, "find",
        \\{"pattern":"*.txt"}
    );
    defer f.deinit(gpa);
    try std.testing.expect(!f.is_error);
    try std.testing.expect(std.mem.indexOf(u8, f.content, "a.txt") != null);

    var l = try execute(ctx, "ls",
        \\{"path":"."}
    );
    defer l.deinit(gpa);
    try std.testing.expect(!l.is_error);
    try std.testing.expect(std.mem.indexOf(u8, l.content, "a.txt") != null);
}

test "tool filter allowlist" {
    const gpa = std.testing.allocator;
    const filter = ToolFilter{ .allow = &[_][]const u8{ "read", "write" } };
    try std.testing.expect(filter.isEnabled("read"));
    try std.testing.expect(!filter.isEnabled("bash"));
    const json = try toolSchemasJson(gpa, filter);
    defer gpa.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"read\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"bash\"") == null);
}

test "extended tools product path in schemas and execute" {
    const gpa = std.testing.allocator;
    const filter = ToolFilter{};
    const json = try toolSchemasJson(gpa, filter);
    defer gpa.free(json);
    const ext_name = @import("generated_root.zig").tools_shard_0.tools[0].name;
    try std.testing.expect(std.mem.indexOf(u8, json, ext_name) != null);

    const ctx = ToolContext{ .gpa = gpa, .io = std.testing.io, .cwd = "." };
    var r = try execute(ctx, ext_name, "{\"path\":\"x.txt\"}");
    defer r.deinit(gpa);
    try std.testing.expect(!r.is_error);
    try std.testing.expect(std.mem.indexOf(u8, r.content, "preview:read_0_0") != null);
}

test "matchGlob basics" {
    try std.testing.expect(matchGlob("*.txt", "a.txt"));
    try std.testing.expect(!matchGlob("*.txt", "a.md"));
    try std.testing.expect(matchGlob("**/*.md", "sub/b.md"));
    try std.testing.expect(matchGlob("sub/*", "sub/b.md"));
}

test "edit multi-edit matches all on original not sequential" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];
    const ctx = ToolContext{ .gpa = gpa, .io = io, .cwd = tmp_path };

    // Both needles exist in original; sequential apply would break the second if order wrong
    var w = try execute(ctx, "write",
        \\{"path":"m.txt","content":"foo bar foo"}
    );
    defer w.deinit(gpa);

    // Two non-overlapping unique replacements on original content
    var e = try execute(ctx, "edit",
        \\{"path":"m.txt","edits":[{"oldText":"foo bar","newText":"X"},{"oldText":" foo","newText":" Y"}]}
    );
    defer e.deinit(gpa);
    try std.testing.expect(!e.is_error);

    var r = try execute(ctx, "read",
        \\{"path":"m.txt"}
    );
    defer r.deinit(gpa);
    try std.testing.expectEqualStrings("X Y", r.content);
}

test "edit accepts oldText/newText and multi-edit edits array" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];
    const ctx = ToolContext{ .gpa = gpa, .io = io, .cwd = tmp_path };

    var w = try execute(ctx, "write",
        \\{"path":"e.txt","content":"alpha beta gamma"}
    );
    defer w.deinit(gpa);

    var e1 = try execute(ctx, "edit",
        \\{"path":"e.txt","oldText":"beta","newText":"BETA"}
    );
    defer e1.deinit(gpa);
    try std.testing.expect(!e1.is_error);
    try std.testing.expect(std.mem.indexOf(u8, e1.content, "replacement") != null);

    var r1 = try execute(ctx, "read",
        \\{"path":"e.txt"}
    );
    defer r1.deinit(gpa);
    try std.testing.expectEqualStrings("alpha BETA gamma", r1.content);

    var e2 = try execute(ctx, "edit",
        \\{"path":"e.txt","edits":[{"oldText":"alpha","newText":"A"},{"oldText":"gamma","newText":"G"}]}
    );
    defer e2.deinit(gpa);
    try std.testing.expect(!e2.is_error);

    var r2 = try execute(ctx, "read",
        \\{"path":"e.txt"}
    );
    defer r2.deinit(gpa);
    try std.testing.expectEqualStrings("A BETA G", r2.content);
}

test "read supports offset and limit lines" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];
    const ctx = ToolContext{ .gpa = gpa, .io = io, .cwd = tmp_path };

    var w = try execute(ctx, "write",
        \\{"path":"lines.txt","content":"L1\nL2\nL3\nL4\nL5"}
    );
    defer w.deinit(gpa);

    var r = try execute(ctx, "read",
        \\{"path":"lines.txt","offset":2,"limit":2}
    );
    defer r.deinit(gpa);
    try std.testing.expect(!r.is_error);
    try std.testing.expectEqualStrings("L2\nL3", r.content);
}

test "read tool truncates oversized file output" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];
    const ctx = ToolContext{ .gpa = gpa, .io = io, .cwd = tmp_path };

    // Build a file exceeding the default 2000-line limit via write tool path.
    var big: std.ArrayList(u8) = .empty;
    defer big.deinit(gpa);
    var i: usize = 0;
    while (i < 2500) : (i += 1) {
        try big.appendSlice(gpa, "line-content-for-truncation-test\n");
    }
    const path = try std.fs.path.join(gpa, &.{ tmp_path, "big.txt" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = big.items });

    var r = try execute(ctx, "read",
        \\{"path":"big.txt"}
    );
    defer r.deinit(gpa);
    try std.testing.expect(!r.is_error);
    try std.testing.expect(std.mem.indexOf(u8, r.content, "truncated") != null);
    // Output should be well under full size
    try std.testing.expect(r.content.len < big.items.len);
}
