//! Context-aware completion for the native interactive editor.
const std = @import("std");
const Io = std.Io;
const providers = @import("../ai/providers.zig");
const session_mod = @import("../agent/session.zig");
const fuzzy = @import("../tui/fuzzy.zig");
const path_utils = @import("path_utils.zig");
const prompts = @import("prompts.zig");

pub const command_names = [_][]const u8{
    "?",     "changelog", "clone",    "compact", "copy",   "exit",    "export",
    "fork",  "help",      "hotkeys",  "import",  "login",  "logout",  "model",
    "name",  "new",       "quit",     "reload",  "resume", "session", "settings",
    "share", "skill",     "thinking", "tree",
};

pub const Result = struct {
    text: []u8,
    cursor: usize,

    pub fn deinit(self: *Result, gpa: std.mem.Allocator) void {
        gpa.free(self.text);
        self.* = undefined;
    }
};

fn replaceRange(
    gpa: std.mem.Allocator,
    line: []const u8,
    start: usize,
    end: usize,
    replacement: []const u8,
) !Result {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, line[0..start]);
    try out.appendSlice(gpa, replacement);
    const cursor = out.items.len;
    try out.appendSlice(gpa, line[end..]);
    return .{ .text = try out.toOwnedSlice(gpa), .cursor = cursor };
}

fn commonPrefixLen(values: []const []const u8) usize {
    if (values.len == 0) return 0;
    var length = values[0].len;
    for (values[1..]) |value| {
        length = @min(length, value.len);
        var index: usize = 0;
        while (index < length and std.ascii.toLower(values[0][index]) == std.ascii.toLower(value[index])) : (index += 1) {}
        length = index;
    }
    return length;
}

fn completeCommand(
    gpa: std.mem.Allocator,
    line: []const u8,
    cursor: usize,
    prompt_templates: []const prompts.PromptTemplate,
    extension_commands: []const []const u8,
    enable_skill_commands: bool,
) !?Result {
    if (cursor == 0 or line[0] != '/') return null;
    for (line[0..cursor]) |byte| if (std.ascii.isWhitespace(byte)) return null;
    const query = line[1..cursor];
    var matches: std.ArrayList([]const u8) = .empty;
    defer matches.deinit(gpa);
    for (command_names) |name| {
        if (!enable_skill_commands and std.mem.eql(u8, name, "skill")) continue;
        if (query.len <= name.len and std.ascii.eqlIgnoreCase(name[0..query.len], query)) try matches.append(gpa, name);
    }
    for (prompt_templates) |template| {
        const name = template.name;
        if (query.len > name.len or !std.ascii.eqlIgnoreCase(name[0..query.len], query)) continue;
        var duplicate = false;
        for (matches.items) |existing| {
            if (std.ascii.eqlIgnoreCase(existing, name)) {
                duplicate = true;
                break;
            }
        }
        if (!duplicate) try matches.append(gpa, name);
    }
    for (extension_commands) |name| {
        if (query.len > name.len or !std.ascii.eqlIgnoreCase(name[0..query.len], query)) continue;
        var duplicate = false;
        for (matches.items) |existing| {
            if (std.ascii.eqlIgnoreCase(existing, name)) {
                duplicate = true;
                break;
            }
        }
        if (!duplicate) try matches.append(gpa, name);
    }
    if (matches.items.len == 0) return null;
    const prefix_len = commonPrefixLen(matches.items);
    var replacement: std.ArrayList(u8) = .empty;
    defer replacement.deinit(gpa);
    try replacement.append(gpa, '/');
    try replacement.appendSlice(gpa, matches.items[0][0..prefix_len]);
    if (matches.items.len == 1) try replacement.append(gpa, ' ');
    if (std.mem.eql(u8, replacement.items, line[0..cursor])) return null;
    return try replaceRange(gpa, line, 0, cursor, replacement.items);
}

fn commandAndArg(line: []const u8, cursor: usize) ?struct { command: []const u8, arg_start: usize } {
    if (cursor == 0 or line[0] != '/') return null;
    var command_end: usize = 1;
    while (command_end < cursor and !std.ascii.isWhitespace(line[command_end])) : (command_end += 1) {}
    if (command_end == cursor) return null;
    var arg_start = command_end;
    while (arg_start < cursor and std.ascii.isWhitespace(line[arg_start])) : (arg_start += 1) {}
    return .{ .command = line[1..command_end], .arg_start = arg_start };
}

fn completeModel(
    gpa: std.mem.Allocator,
    line: []const u8,
    cursor: usize,
    arg_start: usize,
    models: []const providers.ModelInfo,
) !?Result {
    if (models.len == 0) return null;
    const query = line[arg_start..cursor];
    var best_index: ?usize = null;
    var best_score: i32 = std.math.minInt(i32);
    for (models, 0..) |model, index| {
        const fields = [_][]const u8{ model.providerName(), model.id, model.display };
        const candidate_score = if (query.len == 0) 0 else fuzzy.bestScore(&fields, query) orelse continue;
        if (best_index == null or candidate_score > best_score) {
            best_index = index;
            best_score = candidate_score;
        }
    }
    const model = models[best_index orelse return null];
    const identity = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ model.providerName(), model.id });
    defer gpa.free(identity);
    if (std.mem.eql(u8, query, identity)) return null;
    return try replaceRange(gpa, line, arg_start, cursor, identity);
}

fn completeTree(
    gpa: std.mem.Allocator,
    line: []const u8,
    cursor: usize,
    arg_start: usize,
    session: *const session_mod.Session,
) !?Result {
    const query = line[arg_start..cursor];
    var matches: std.ArrayList([]const u8) = .empty;
    defer matches.deinit(gpa);
    for (session.entries.items) |entry| {
        if (query.len <= entry.id.len and std.mem.startsWith(u8, entry.id, query)) try matches.append(gpa, entry.id);
    }
    if (matches.items.len == 0) return null;
    const prefix_len = commonPrefixLen(matches.items);
    var replacement: std.ArrayList(u8) = .empty;
    defer replacement.deinit(gpa);
    try replacement.appendSlice(gpa, matches.items[0][0..prefix_len]);
    if (matches.items.len == 1) try replacement.append(gpa, ' ');
    if (std.mem.eql(u8, replacement.items, query)) return null;
    return try replaceRange(gpa, line, arg_start, cursor, replacement.items);
}

fn activeTokenStart(line: []const u8, cursor: usize) usize {
    var start: usize = 0;
    var quote: ?u8 = null;
    var index: usize = 0;
    while (index < cursor) : (index += 1) {
        const byte = line[index];
        if (byte == '\\' and index + 1 < cursor) {
            index += 1;
            continue;
        }
        if (byte == '\'' or byte == '"') {
            if (quote == null) quote = byte else if (quote.? == byte) quote = null;
            continue;
        }
        if (quote == null and std.ascii.isWhitespace(byte)) start = index + 1;
    }
    return start;
}

fn decodeToken(gpa: std.mem.Allocator, raw: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var quote: ?u8 = null;
    var index: usize = 0;
    while (index < raw.len) {
        const byte = raw[index];
        if (byte == '\'' or byte == '"') {
            if (quote == null) {
                quote = byte;
                index += 1;
                continue;
            }
            if (quote.? == byte) {
                quote = null;
                index += 1;
                continue;
            }
        }
        if (byte == '\\' and index + 1 < raw.len) {
            const next = raw[index + 1];
            if (std.ascii.isWhitespace(next) or next == '\'' or next == '"' or next == '\\') {
                try out.append(gpa, next);
                index += 2;
                continue;
            }
        }
        try out.append(gpa, byte);
        index += 1;
    }
    return try out.toOwnedSlice(gpa);
}

const PathMatch = struct { name: []u8, kind: std.Io.File.Kind, depth: usize = 0 };

fn collectRecursivePathMatches(
    gpa: std.mem.Allocator,
    io: Io,
    root: []const u8,
    relative: []const u8,
    prefix: []const u8,
    depth: usize,
    matches: *std.ArrayList(PathMatch),
) !void {
    if (depth > 8 or matches.items.len >= 512) return;
    const directory_path = if (relative.len == 0) try gpa.dupe(u8, root) else try std.fs.path.join(gpa, &.{ root, relative });
    defer gpa.free(directory_path);
    var dir = std.Io.Dir.cwd().openDir(io, directory_path, .{ .iterate = true }) catch return;
    defer dir.close(io);
    var children: std.ArrayList([]u8) = .empty;
    defer {
        for (children.items) |child| gpa.free(child);
        children.deinit(gpa);
    }
    var iterator = dir.iterate();
    while (try iterator.next(io)) |entry| {
        if (std.mem.eql(u8, entry.name, ".git") or std.mem.eql(u8, entry.name, "node_modules") or std.mem.eql(u8, entry.name, ".zig-cache")) continue;
        const candidate = if (relative.len == 0) try gpa.dupe(u8, entry.name) else try std.fs.path.join(gpa, &.{ relative, entry.name });
        errdefer gpa.free(candidate);
        if (prefix.len <= entry.name.len and std.ascii.startsWithIgnoreCase(entry.name, prefix)) {
            try matches.append(gpa, .{ .name = candidate, .kind = entry.kind, .depth = depth });
        } else {
            gpa.free(candidate);
        }
        if (entry.kind == .directory) {
            const child = if (relative.len == 0) try gpa.dupe(u8, entry.name) else try std.fs.path.join(gpa, &.{ relative, entry.name });
            try children.append(gpa, child);
        }
        if (matches.items.len >= 512) break;
    }
    std.mem.sort([]u8, children.items, {}, struct {
        fn lessThan(_: void, lhs: []u8, rhs: []u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.lessThan);
    for (children.items) |child| try collectRecursivePathMatches(gpa, io, root, child, prefix, depth + 1, matches);
}

fn completePath(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    cwd: []const u8,
    line: []const u8,
    cursor: usize,
    token_start: usize,
    has_at: bool,
) !?Result {
    const raw_token = line[token_start..cursor];
    var decoded = try decodeToken(gpa, raw_token);
    defer gpa.free(decoded);
    if (has_at) {
        if (decoded.len == 0 or decoded[0] != '@' or std.mem.startsWith(u8, decoded, "@@")) return null;
        const without_at = try gpa.dupe(u8, decoded[1..]);
        gpa.free(decoded);
        decoded = without_at;
    }

    const separator_index = blk: {
        const slash = std.mem.lastIndexOfScalar(u8, decoded, '/');
        const backslash = std.mem.lastIndexOfScalar(u8, decoded, '\\');
        if (slash == null) break :blk backslash;
        if (backslash == null) break :blk slash;
        break :blk @max(slash.?, backslash.?);
    };
    const typed_dir = if (separator_index) |index| decoded[0 .. index + 1] else "";
    const basename = if (separator_index) |index| decoded[index + 1 ..] else decoded;
    const scan_input = if (typed_dir.len > 0) typed_dir else ".";
    const scan_dir = path_utils.resolvePath(gpa, environ, scan_input, cwd, .{ .normalize_unicode_spaces = true }) catch return null;
    defer gpa.free(scan_dir);

    var matches: std.ArrayList(PathMatch) = .empty;
    defer {
        for (matches.items) |match| gpa.free(match.name);
        matches.deinit(gpa);
    }
    if (has_at and typed_dir.len == 0) {
        try collectRecursivePathMatches(gpa, io, scan_dir, "", basename, 0, &matches);
    } else {
        var dir = std.Io.Dir.cwd().openDir(io, scan_dir, .{ .iterate = true }) catch return null;
        defer dir.close(io);
        var iterator = dir.iterate();
        while (try iterator.next(io)) |entry| {
            if (basename.len > entry.name.len or !std.ascii.startsWithIgnoreCase(entry.name, basename)) continue;
            try matches.append(gpa, .{ .name = try gpa.dupe(u8, entry.name), .kind = entry.kind });
        }
    }
    if (matches.items.len == 0) return null;
    std.mem.sort(PathMatch, matches.items, {}, struct {
        fn lessThan(_: void, lhs: PathMatch, rhs: PathMatch) bool {
            if (lhs.depth != rhs.depth) return lhs.depth < rhs.depth;
            return std.mem.lessThan(u8, lhs.name, rhs.name);
        }
    }.lessThan);

    var preferred_count: usize = 1;
    while (preferred_count < matches.items.len and matches.items[preferred_count].depth == matches.items[0].depth) : (preferred_count += 1) {}
    const names = try gpa.alloc([]const u8, preferred_count);
    defer gpa.free(names);
    for (matches.items[0..preferred_count], 0..) |match, index| names[index] = match.name;
    var prefix_len = commonPrefixLen(names);
    if (has_at and prefix_len <= basename.len) prefix_len = matches.items[0].name.len;

    var completed_path: std.ArrayList(u8) = .empty;
    defer completed_path.deinit(gpa);
    try completed_path.appendSlice(gpa, typed_dir);
    try completed_path.appendSlice(gpa, matches.items[0].name[0..prefix_len]);
    const unique = preferred_count == 1;
    const is_directory = unique and matches.items[0].kind == .directory;
    if (is_directory and (completed_path.items.len == 0 or (completed_path.items[completed_path.items.len - 1] != '/' and completed_path.items[completed_path.items.len - 1] != '\\'))) {
        try completed_path.append(gpa, std.fs.path.sep);
    }

    var replacement: std.ArrayList(u8) = .empty;
    defer replacement.deinit(gpa);
    if (has_at) try replacement.append(gpa, '@');
    const needs_quotes = std.mem.indexOfAny(u8, completed_path.items, " \t") != null;
    if (needs_quotes) try replacement.append(gpa, '"');
    try replacement.appendSlice(gpa, completed_path.items);
    if (needs_quotes) try replacement.append(gpa, '"');
    if (unique and !is_directory) try replacement.append(gpa, ' ');
    if (std.mem.eql(u8, replacement.items, raw_token)) return null;
    return try replaceRange(gpa, line, token_start, cursor, replacement.items);
}

pub fn complete(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    cwd: []const u8,
    line: []const u8,
    cursor: usize,
    models: []const providers.ModelInfo,
    prompt_templates: []const prompts.PromptTemplate,
    extension_commands: []const []const u8,
    session: *const session_mod.Session,
    enable_skill_commands: bool,
) !?Result {
    const bounded_cursor = @min(cursor, line.len);
    if (try completeCommand(gpa, line, bounded_cursor, prompt_templates, extension_commands, enable_skill_commands)) |result| return result;
    if (commandAndArg(line, bounded_cursor)) |parsed| {
        if (std.ascii.eqlIgnoreCase(parsed.command, "model")) return try completeModel(gpa, line, bounded_cursor, parsed.arg_start, models);
        if (std.ascii.eqlIgnoreCase(parsed.command, "tree")) return try completeTree(gpa, line, bounded_cursor, parsed.arg_start, session);
        if (std.ascii.eqlIgnoreCase(parsed.command, "import") or std.ascii.eqlIgnoreCase(parsed.command, "export")) {
            return try completePath(gpa, io, environ, cwd, line, bounded_cursor, parsed.arg_start, false);
        }
    }
    const token_start = activeTokenStart(line, bounded_cursor);
    if (token_start < bounded_cursor and line[token_start] == '@') {
        return try completePath(gpa, io, environ, cwd, line, bounded_cursor, token_start, true);
    }
    return null;
}

test "completion expands commands models and tree ids" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var session = try session_mod.Session.init(gpa, "completion", ".");
    defer session.deinit();
    _ = try session.appendMessage(null, "user", "hello", null, null);
    const models = [_]providers.ModelInfo{.{ .provider = .anthropic, .id = "claude-sonnet-4", .display = "Claude Sonnet 4" }};

    var command = (try complete(gpa, std.testing.io, &env, ".", "/mod", 4, &models, &.{}, &.{}, &session, true)).?;
    defer command.deinit(gpa);
    try std.testing.expectEqualStrings("/model ", command.text);

    var model = (try complete(gpa, std.testing.io, &env, ".", "/model cs4", 10, &models, &.{}, &.{}, &session, true)).?;
    defer model.deinit(gpa);
    try std.testing.expectEqualStrings("/model anthropic/claude-sonnet-4", model.text);

    var tree = (try complete(gpa, std.testing.io, &env, ".", "/tree m", 7, &models, &.{}, &.{}, &session, true)).?;
    defer tree.deinit(gpa);
    try std.testing.expectEqualStrings("/tree m1 ", tree.text);

    const templates = [_]prompts.PromptTemplate{.{
        .name = "review",
        .path = "review.md",
        .description = "Review",
        .content = "Review $1",
    }};
    var template = (try complete(gpa, std.testing.io, &env, ".", "/rev", 4, &models, &templates, &.{"audit-native"}, &session, true)).?;
    defer template.deinit(gpa);
    try std.testing.expectEqualStrings("/review ", template.text);

    var extension_command = (try complete(gpa, std.testing.io, &env, ".", "/audit-n", 8, &models, &templates, &.{"audit-native"}, &session, true)).?;
    defer extension_command.deinit(gpa);
    try std.testing.expectEqualStrings("/audit-native ", extension_command.text);
}

test "completion omits disabled skill command" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var session = try session_mod.Session.init(gpa, "completion-skills", ".");
    defer session.deinit();

    try std.testing.expect((try complete(gpa, std.testing.io, &env, ".", "/ski", 4, &.{}, &.{}, &.{}, &session, false)) == null);
    var enabled = (try complete(gpa, std.testing.io, &env, ".", "/ski", 4, &.{}, &.{}, &.{}, &session, true)).?;
    defer enabled.deinit(gpa);
    try std.testing.expectEqualStrings("/skill ", enabled.text);
}

test "completion quotes file paths and descends directories" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "hello world.txt", .data = "hello" });
    try tmp.dir.createDirPath(io, "folder one");
    var root_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];
    var session = try session_mod.Session.init(gpa, "completion-files", root);
    defer session.deinit();

    var file = (try complete(gpa, io, &env, root, "inspect @hel", 12, &.{}, &.{}, &.{}, &session, true)).?;
    defer file.deinit(gpa);
    try std.testing.expectEqualStrings("inspect @\"hello world.txt\" ", file.text);

    var folder = (try complete(gpa, io, &env, root, "@fol", 4, &.{}, &.{}, &.{}, &session, true)).?;
    defer folder.deinit(gpa);
    try std.testing.expect(std.mem.startsWith(u8, folder.text, "@\"folder one"));
}

test "recursive at completion prefers shallower matches and reaches nested files" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "target.txt", .data = "root" });
    try tmp.dir.createDirPath(io, "deep");
    try tmp.dir.writeFile(io, .{ .sub_path = "deep/target.txt", .data = "deep" });
    try tmp.dir.writeFile(io, .{ .sub_path = "deep/needle.txt", .data = "needle" });
    var root_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root = root_buf[0..try tmp.dir.realPath(io, &root_buf)];
    var session = try session_mod.Session.init(gpa, "completion-recursive", root);
    defer session.deinit();

    var shallow = (try complete(gpa, io, &env, root, "@tar", 4, &.{}, &.{}, &.{}, &session, true)).?;
    defer shallow.deinit(gpa);
    try std.testing.expectEqualStrings("@target.txt ", shallow.text);

    var nested = (try complete(gpa, io, &env, root, "@nee", 4, &.{}, &.{}, &.{}, &session, true)).?;
    defer nested.deinit(gpa);
    try std.testing.expect(std.mem.indexOf(u8, nested.text, "needle.txt") != null);
    try std.testing.expect(std.mem.indexOf(u8, nested.text, "deep") != null);
}
