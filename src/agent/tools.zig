//! Built-in coding tools: read, write, edit, bash, grep, find, ls.
const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");

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

const schema_read =
    \\{"type":"function","function":{"name":"read","description":"Read a file from the filesystem.","parameters":{"type":"object","properties":{"path":{"type":"string","description":"Path to the file to read"}},"required":["path"]}}}
;
const schema_write =
    \\{"type":"function","function":{"name":"write","description":"Write content to a file, creating parent directories as needed.","parameters":{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}}}
;
const schema_edit =
    \\{"type":"function","function":{"name":"edit","description":"Replace an exact string in a file.","parameters":{"type":"object","properties":{"path":{"type":"string"},"old_string":{"type":"string"},"new_string":{"type":"string"}},"required":["path","old_string","new_string"]}}}
;
const schema_bash =
    \\{"type":"function","function":{"name":"bash","description":"Run a shell command and return stdout, stderr, and exit code.","parameters":{"type":"object","properties":{"command":{"type":"string"}},"required":["command"]}}}
;
const schema_grep =
    \\{"type":"function","function":{"name":"grep","description":"Search files for a pattern (substring). Supports optional path, glob filter, ignoreCase, limit.","parameters":{"type":"object","properties":{"pattern":{"type":"string"},"path":{"type":"string"},"glob":{"type":"string"},"ignoreCase":{"type":"boolean"},"limit":{"type":"number"}},"required":["pattern"]}}}
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
pub fn toolSchemasJson(gpa: std.mem.Allocator, filter: ToolFilter) ![]u8 {
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
    return try errMsg(ctx.gpa, "unknown tool: {s}", .{name});
}

fn ownedResult(msg: []u8, is_error: bool) ToolResult {
    return .{ .content = msg, .is_error = is_error };
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
    const path_owned = try parseStringField(ctx.gpa, arguments_json, "path") orelse
        return try errMsg(ctx.gpa, "read: missing path", .{});
    defer ctx.gpa.free(path_owned);

    const full = try resolvePath(ctx.gpa, ctx.cwd, path_owned);
    defer ctx.gpa.free(full);

    const data = std.Io.Dir.cwd().readFileAlloc(ctx.io, full, ctx.gpa, .limited(8 * 1024 * 1024)) catch |err| {
        return try errMsg(ctx.gpa, "read failed: {s}", .{@errorName(err)});
    };
    return ownedResult(data, false);
}

fn executeWrite(ctx: ToolContext, arguments_json: []const u8) !ToolResult {
    const path_owned = try parseStringField(ctx.gpa, arguments_json, "path") orelse
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

fn executeEdit(ctx: ToolContext, arguments_json: []const u8) !ToolResult {
    const path_owned = try parseStringField(ctx.gpa, arguments_json, "path") orelse
        return try errMsg(ctx.gpa, "edit: missing path", .{});
    defer ctx.gpa.free(path_owned);
    const old_owned = try parseStringField(ctx.gpa, arguments_json, "old_string") orelse
        return try errMsg(ctx.gpa, "edit: missing old_string", .{});
    defer ctx.gpa.free(old_owned);
    const new_owned = try parseStringField(ctx.gpa, arguments_json, "new_string") orelse
        return try errMsg(ctx.gpa, "edit: missing new_string", .{});
    defer ctx.gpa.free(new_owned);

    const full = try resolvePath(ctx.gpa, ctx.cwd, path_owned);
    defer ctx.gpa.free(full);

    const original = std.Io.Dir.cwd().readFileAlloc(ctx.io, full, ctx.gpa, .limited(8 * 1024 * 1024)) catch |err| {
        return try errMsg(ctx.gpa, "edit read failed: {s}", .{@errorName(err)});
    };
    defer ctx.gpa.free(original);

    const idx = std.mem.indexOf(u8, original, old_owned) orelse {
        return try errMsg(ctx.gpa, "edit: old_string not found", .{});
    };
    if (std.mem.indexOfPos(u8, original, idx + old_owned.len, old_owned) != null) {
        return try errMsg(ctx.gpa, "edit: old_string is not unique", .{});
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(ctx.gpa);
    try out.appendSlice(ctx.gpa, original[0..idx]);
    try out.appendSlice(ctx.gpa, new_owned);
    try out.appendSlice(ctx.gpa, original[idx + old_owned.len ..]);

    std.Io.Dir.cwd().writeFile(ctx.io, .{
        .sub_path = full,
        .data = out.items,
    }) catch |err| {
        return try errMsg(ctx.gpa, "edit write failed: {s}", .{@errorName(err)});
    };

    return try okMsg(ctx.gpa, "Edited {s}", .{path_owned});
}

fn executeBash(ctx: ToolContext, arguments_json: []const u8) !ToolResult {
    const command = try parseStringField(ctx.gpa, arguments_json, "command") orelse
        return try errMsg(ctx.gpa, "bash: missing command", .{});
    defer ctx.gpa.free(command);

    const argv: []const []const u8 = if (builtin.os.tag == .windows)
        &[_][]const u8{ "cmd.exe", "/C", command }
    else
        &[_][]const u8{ "sh", "-c", command };

    const run_result = std.process.run(ctx.gpa, ctx.io, .{
        .argv = argv,
        .cwd = .{ .path = ctx.cwd },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    }) catch |err| {
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

    return ownedResult(try std.fmt.allocPrint(ctx.gpa, "exit={d}\nstdout:\n{s}\nstderr:\n{s}", .{
        code,
        run_result.stdout,
        run_result.stderr,
    }), code != 0);
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
    const limit: usize = @intCast(@max(1, parseIntField(ctx.gpa, arguments_json, "limit", 100)));

    const search_root = try resolvePath(ctx.gpa, ctx.cwd, path_opt orelse ".");
    defer ctx.gpa.free(search_root);

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
        try grepFile(ctx, search_root, search_root, pattern, ignore_case, &out, &matches, limit);
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
            try grepFile(ctx, full, entry.path, pattern, ignore_case, &out, &matches, limit);
        }
    }

    if (out.items.len == 0) {
        return try okMsg(ctx.gpa, "No matches for {s}", .{pattern});
    }
    return ownedResult(try out.toOwnedSlice(ctx.gpa), false);
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
    const data = std.Io.Dir.cwd().readFileAlloc(ctx.io, full_path, ctx.gpa, .limited(2 * 1024 * 1024)) catch return;
    defer ctx.gpa.free(data);

    var line_no: usize = 1;
    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |line| {
        if (matches.* >= limit) return;
        const hit = if (ignore_case)
            containsIgnoreCase(line, pattern)
        else
            std.mem.indexOf(u8, line, pattern) != null;
        if (hit) {
            const line_out = try std.fmt.allocPrint(ctx.gpa, "{s}:{d}:{s}\n", .{ display_path, line_no, line });
            defer ctx.gpa.free(line_out);
            try out.appendSlice(ctx.gpa, line_out);
            matches.* += 1;
        }
        line_no += 1;
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
    return ownedResult(try out.toOwnedSlice(ctx.gpa), false);
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
    return ownedResult(try out.toOwnedSlice(ctx.gpa), false);
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

test "matchGlob basics" {
    try std.testing.expect(matchGlob("*.txt", "a.txt"));
    try std.testing.expect(!matchGlob("*.txt", "a.md"));
    try std.testing.expect(matchGlob("**/*.md", "sub/b.md"));
    try std.testing.expect(matchGlob("sub/*", "sub/b.md"));
}
