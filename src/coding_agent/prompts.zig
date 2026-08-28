//! Prompt-template loading and slash-command expansion.
//!
//! This mirrors the original coding-agent semantics:
//! - global, trusted-project, and explicit file/directory resources;
//! - YAML-like frontmatter for `description` and `argument-hint`;
//! - `$1`, `$@`, `$ARGUMENTS`, defaults, and bash-style argument slices.
const std = @import("std");
const Io = std.Io;

pub const PromptTemplate = struct {
    name: []const u8,
    path: []const u8,
    description: []const u8,
    argument_hint: ?[]const u8 = null,
    content: []const u8,

    pub fn deinit(self: *PromptTemplate, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        gpa.free(self.path);
        gpa.free(self.description);
        if (self.argument_hint) |value| gpa.free(value);
        gpa.free(self.content);
        self.* = undefined;
    }
};

const ParsedDocument = struct {
    description: []const u8 = "",
    argument_hint: ?[]const u8 = null,
    body: []const u8,
};

/// Discover default global and trusted-project templates.
pub fn discover(gpa: std.mem.Allocator, io: Io, cwd: []const u8, agent_dir: ?[]const u8) ![]PromptTemplate {
    return discoverTrusted(gpa, io, cwd, agent_dir, true);
}

pub fn discoverTrusted(gpa: std.mem.Allocator, io: Io, cwd: []const u8, agent_dir: ?[]const u8, trust_project: bool) ![]PromptTemplate {
    return loadTrusted(gpa, io, cwd, agent_dir, trust_project, &.{}, true);
}

/// Load templates from defaults plus explicit files/directories. Explicit paths
/// remain active when `include_defaults` is false, matching `--no-prompt-templates`
/// combined with one or more `--prompt-template` options.
pub fn loadTrusted(
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    agent_dir: ?[]const u8,
    trust_project: bool,
    explicit_paths: []const []const u8,
    include_defaults: bool,
) ![]PromptTemplate {
    var list: std.ArrayList(PromptTemplate) = .empty;
    errdefer deinitList(gpa, &list);

    if (include_defaults) {
        if (agent_dir) |ad| {
            const path = try std.fs.path.join(gpa, &.{ ad, "prompts" });
            defer gpa.free(path);
            try scanDir(gpa, io, path, &list);
        }
        if (trust_project) {
            const path = try std.fs.path.join(gpa, &.{ cwd, ".pi", "prompts" });
            defer gpa.free(path);
            try scanDir(gpa, io, path, &list);
        }
    }

    for (explicit_paths) |path| try loadPath(gpa, io, path, &list);
    return try list.toOwnedSlice(gpa);
}

fn deinitList(gpa: std.mem.Allocator, list: *std.ArrayList(PromptTemplate)) void {
    for (list.items) |*item| item.deinit(gpa);
    list.deinit(gpa);
}

fn loadPath(gpa: std.mem.Allocator, io: Io, path: []const u8, out: *std.ArrayList(PromptTemplate)) !void {
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return;
    switch (stat.kind) {
        .directory => try scanDir(gpa, io, path, out),
        .file => if (std.mem.endsWith(u8, path, ".md")) try loadFile(gpa, io, path, out),
        else => {},
    }
}

fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

fn scanDir(gpa: std.mem.Allocator, io: Io, dir_path: []const u8, out: *std.ArrayList(PromptTemplate)) !void {
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch return;
    defer dir.close(io);

    var names: std.ArrayList([]const u8) = .empty;
    defer {
        for (names.items) |name| gpa.free(name);
        names.deinit(gpa);
    }
    var iterator = dir.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file and entry.kind != .sym_link) continue;
        if (!std.mem.endsWith(u8, entry.name, ".md")) continue;
        try names.append(gpa, try gpa.dupe(u8, entry.name));
    }
    std.mem.sort([]const u8, names.items, {}, lessThan);
    for (names.items) |name| {
        const full = try std.fs.path.join(gpa, &.{ dir_path, name });
        defer gpa.free(full);
        try loadFile(gpa, io, full, out);
    }
}

fn loadFile(gpa: std.mem.Allocator, io: Io, path: []const u8, out: *std.ArrayList(PromptTemplate)) !void {
    const raw = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(512 * 1024)) catch return;
    defer gpa.free(raw);
    const filename = std.fs.path.basename(path);
    const name = if (std.mem.endsWith(u8, filename, ".md")) filename[0 .. filename.len - 3] else filename;
    if (name.len == 0) return;

    const document = parseDocument(raw);
    const fallback = firstDescriptionLine(document.body);
    const description_source = if (document.description.len > 0) document.description else fallback;
    const description = try truncateDescription(gpa, description_source);
    errdefer gpa.free(description);
    const hint = if (document.argument_hint) |value| try gpa.dupe(u8, value) else null;
    errdefer if (hint) |value| gpa.free(value);

    try out.append(gpa, .{
        .name = try gpa.dupe(u8, name),
        .path = try gpa.dupe(u8, path),
        .description = description,
        .argument_hint = hint,
        .content = try gpa.dupe(u8, document.body),
    });
}

fn parseDocument(raw: []const u8) ParsedDocument {
    var result = ParsedDocument{ .body = raw };
    var lines = std.mem.splitScalar(u8, raw, '\n');
    const first_raw = lines.next() orelse return result;
    if (!std.mem.eql(u8, std.mem.trim(u8, first_raw, " \t\r"), "---")) return result;

    // Offset immediately after the first line, including its newline when present.
    var offset: usize = first_raw.len;
    if (offset < raw.len and raw[offset] == '\n') offset += 1;
    var found_end = false;
    while (lines.next()) |line_raw| {
        const line_start = offset;
        offset += line_raw.len;
        if (offset < raw.len and raw[offset] == '\n') offset += 1;
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (std.mem.eql(u8, line, "---")) {
            result.body = raw[offset..];
            found_end = true;
            break;
        }
        _ = line_start;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const key = std.mem.trim(u8, line[0..colon], " \t");
        var value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        if (value.len >= 2 and ((value[0] == '"' and value[value.len - 1] == '"') or (value[0] == '\'' and value[value.len - 1] == '\''))) {
            value = value[1 .. value.len - 1];
        }
        if (std.mem.eql(u8, key, "description")) result.description = value;
        if (std.mem.eql(u8, key, "argument-hint")) result.argument_hint = value;
    }
    if (!found_end) return .{ .body = raw };
    return result;
}

fn firstDescriptionLine(body: []const u8) []const u8 {
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len > 0) return trimmed;
    }
    return "";
}

fn truncateDescription(gpa: std.mem.Allocator, description: []const u8) ![]u8 {
    if (description.len <= 60) return try gpa.dupe(u8, description);
    return try std.fmt.allocPrint(gpa, "{s}...", .{description[0..60]});
}

/// Expand `{{key}}` placeholders. This older programmatic API remains useful for
/// callers that provide named variables; slash templates use `substituteArgs`.
pub fn expand(gpa: std.mem.Allocator, template: []const u8, keys: []const []const u8, values: []const []const u8) ![]u8 {
    std.debug.assert(keys.len == values.len);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    var index: usize = 0;
    while (index < template.len) {
        if (template[index] == '{' and index + 1 < template.len and template[index + 1] == '{') {
            const start = index + 2;
            const end = std.mem.indexOfPos(u8, template, start, "}}") orelse {
                try out.append(gpa, template[index]);
                index += 1;
                continue;
            };
            const key = std.mem.trim(u8, template[start..end], " \t");
            var replaced = false;
            for (keys, values) |candidate, value| {
                if (std.mem.eql(u8, candidate, key)) {
                    try out.appendSlice(gpa, value);
                    replaced = true;
                    break;
                }
            }
            if (!replaced) try out.appendSlice(gpa, template[index .. end + 2]);
            index = end + 2;
            continue;
        }
        try out.append(gpa, template[index]);
        index += 1;
    }
    return try out.toOwnedSlice(gpa);
}

pub fn parseCommandArgs(gpa: std.mem.Allocator, raw: []const u8) ![]const []const u8 {
    var arguments: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (arguments.items) |value| gpa.free(value);
        arguments.deinit(gpa);
    }
    var current: std.ArrayList(u8) = .empty;
    defer current.deinit(gpa);
    var quote: ?u8 = null;

    for (raw) |byte| {
        if (quote) |active| {
            if (byte == active) {
                quote = null;
            } else {
                try current.append(gpa, byte);
            }
        } else if (byte == '\'' or byte == '"') {
            quote = byte;
        } else if (std.ascii.isWhitespace(byte)) {
            if (current.items.len > 0) {
                try arguments.append(gpa, try gpa.dupe(u8, current.items));
                current.clearRetainingCapacity();
            }
        } else {
            try current.append(gpa, byte);
        }
    }
    if (current.items.len > 0) try arguments.append(gpa, try gpa.dupe(u8, current.items));
    return try arguments.toOwnedSlice(gpa);
}

pub fn freeCommandArgs(gpa: std.mem.Allocator, args: []const []const u8) void {
    for (args) |value| gpa.free(value);
    gpa.free(args);
}

fn appendAllArgs(gpa: std.mem.Allocator, out: *std.ArrayList(u8), args: []const []const u8) !void {
    for (args, 0..) |value, index| {
        if (index > 0) try out.append(gpa, ' ');
        try out.appendSlice(gpa, value);
    }
}

fn appendSliceArgs(gpa: std.mem.Allocator, out: *std.ArrayList(u8), args: []const []const u8, one_based_start: usize, length: ?usize) !void {
    const start = if (one_based_start == 0) 0 else one_based_start - 1;
    if (start >= args.len) return;
    const end = if (length) |count| @min(args.len, start + count) else args.len;
    try appendAllArgs(gpa, out, args[start..end]);
}

fn parseUnsigned(raw: []const u8) ?usize {
    if (raw.len == 0) return null;
    var value: usize = 0;
    for (raw) |byte| {
        if (!std.ascii.isDigit(byte)) return null;
        value = std.math.mul(usize, value, 10) catch return null;
        value = std.math.add(usize, value, byte - '0') catch return null;
    }
    return value;
}

fn positional(args: []const []const u8, one_based: usize) []const u8 {
    if (one_based == 0 or one_based > args.len) return "";
    return args[one_based - 1];
}

/// Substitute the original prompt-template argument syntax without recursively
/// re-expanding replacement/default text.
pub fn substituteArgs(gpa: std.mem.Allocator, content: []const u8, args: []const []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var index: usize = 0;

    while (index < content.len) {
        if (content[index] != '$') {
            try out.append(gpa, content[index]);
            index += 1;
            continue;
        }

        // Braced forms: defaults and argument slices.
        if (index + 1 < content.len and content[index + 1] == '{') {
            const end = std.mem.indexOfScalarPos(u8, content, index + 2, '}') orelse {
                try out.append(gpa, '$');
                index += 1;
                continue;
            };
            const expression = content[index + 2 .. end];
            if (std.mem.startsWith(u8, expression, "@:")) {
                var parts = std.mem.splitScalar(u8, expression[2..], ':');
                const start_raw = parts.next() orelse "";
                const length_raw = parts.next();
                if (parts.next() == null) {
                    if (parseUnsigned(start_raw)) |start| {
                        const length = if (length_raw) |raw| parseUnsigned(raw) else null;
                        if (length_raw == null or length != null) {
                            try appendSliceArgs(gpa, &out, args, start, length);
                            index = end + 1;
                            continue;
                        }
                    }
                }
            }
            if (std.mem.indexOf(u8, expression, ":-")) |separator| {
                const target = expression[0..separator];
                const default = expression[separator + 2 ..];
                if (std.mem.eql(u8, target, "@") or std.mem.eql(u8, target, "ARGUMENTS")) {
                    if (args.len > 0) try appendAllArgs(gpa, &out, args) else try out.appendSlice(gpa, default);
                    index = end + 1;
                    continue;
                }
                if (parseUnsigned(target)) |position| {
                    const value = positional(args, position);
                    try out.appendSlice(gpa, if (value.len > 0) value else default);
                    index = end + 1;
                    continue;
                }
            }
            try out.appendSlice(gpa, content[index .. end + 1]);
            index = end + 1;
            continue;
        }

        // Simple forms: $ARGUMENTS, $@, and $N.
        if (std.mem.startsWith(u8, content[index + 1 ..], "ARGUMENTS")) {
            try appendAllArgs(gpa, &out, args);
            index += 1 + "ARGUMENTS".len;
            continue;
        }
        if (index + 1 < content.len and content[index + 1] == '@') {
            try appendAllArgs(gpa, &out, args);
            index += 2;
            continue;
        }
        var digit_end = index + 1;
        while (digit_end < content.len and std.ascii.isDigit(content[digit_end])) : (digit_end += 1) {}
        if (digit_end > index + 1) {
            if (parseUnsigned(content[index + 1 .. digit_end])) |position| try out.appendSlice(gpa, positional(args, position));
            index = digit_end;
            continue;
        }

        try out.append(gpa, '$');
        index += 1;
    }
    return try out.toOwnedSlice(gpa);
}

pub fn findByName(templates: []const PromptTemplate, name: []const u8) ?*const PromptTemplate {
    for (templates) |*template| if (std.mem.eql(u8, template.name, name)) return template;
    return null;
}

/// Expand `/template arg...`; returns null when the text is not a known template.
pub fn expandInvocation(gpa: std.mem.Allocator, text: []const u8, templates: []const PromptTemplate) !?[]u8 {
    if (text.len < 2 or text[0] != '/') return null;
    var command_end: usize = 1;
    while (command_end < text.len and !std.ascii.isWhitespace(text[command_end])) : (command_end += 1) {}
    const name = text[1..command_end];
    const template = findByName(templates, name) orelse return null;
    var args_start = command_end;
    while (args_start < text.len and std.ascii.isWhitespace(text[args_start])) : (args_start += 1) {}
    const args = try parseCommandArgs(gpa, text[args_start..]);
    defer freeCommandArgs(gpa, args);
    return try substituteArgs(gpa, template.content, args);
}

test "expand named placeholders" {
    const gpa = std.testing.allocator;
    const keys = [_][]const u8{ "name", "cwd" };
    const values = [_][]const u8{ "pi", "/tmp" };
    const out = try expand(gpa, "Hello {{name}} in {{cwd}}!", &keys, &values);
    defer gpa.free(out);
    try std.testing.expectEqualStrings("Hello pi in /tmp!", out);
}

test "prompt argument substitution matches positional defaults and slices" {
    const gpa = std.testing.allocator;
    const args = try parseCommandArgs(gpa, "one 'two words' three four");
    defer freeCommandArgs(gpa, args);
    const out = try substituteArgs(
        gpa,
        "$1|$2|$@|$ARGUMENTS|${5:-fallback}|${@:-none}|${@:2}|${@:2:2}|${@:0:1}",
        args,
    );
    defer gpa.free(out);
    try std.testing.expectEqualStrings(
        "one|two words|one two words three four|one two words three four|fallback|one two words three four|two words three four|two words three|one",
        out,
    );
}

test "replacement text is not recursively substituted" {
    const gpa = std.testing.allocator;
    const args = try parseCommandArgs(gpa, "'$2'");
    defer freeCommandArgs(gpa, args);
    const out = try substituteArgs(gpa, "$1 ${2:-$1}", args);
    defer gpa.free(out);
    try std.testing.expectEqualStrings("$2 $1", out);
}

test "frontmatter is stripped and exposed as metadata" {
    const document = parseDocument("---\ndescription: 'Review code'\nargument-hint: <path>\n---\nCheck $1\n");
    try std.testing.expectEqualStrings("Review code", document.description);
    try std.testing.expectEqualStrings("<path>", document.argument_hint.?);
    try std.testing.expectEqualStrings("Check $1\n", document.body);
}

test "explicit prompt paths work while defaults are disabled" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &path_buffer);
    const root = path_buffer[0..length];

    const default_dir = try std.fs.path.join(gpa, &.{ root, ".pi", "prompts" });
    defer gpa.free(default_dir);
    try std.Io.Dir.cwd().createDirPath(io, default_dir);
    const hidden = try std.fs.path.join(gpa, &.{ default_dir, "hidden.md" });
    defer gpa.free(hidden);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = hidden, .data = "hidden" });

    const explicit_dir = try std.fs.path.join(gpa, &.{ root, "extra prompts" });
    defer gpa.free(explicit_dir);
    try std.Io.Dir.cwd().createDirPath(io, explicit_dir);
    const explicit_file = try std.fs.path.join(gpa, &.{ explicit_dir, "review.md" });
    defer gpa.free(explicit_file);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = explicit_file, .data = "---\ndescription: Review things\n---\nReview $1" });

    const templates = try loadTrusted(gpa, io, root, null, true, &.{explicit_dir}, false);
    defer {
        for (templates) |*template| template.deinit(gpa);
        gpa.free(templates);
    }
    try std.testing.expectEqual(@as(usize, 1), templates.len);
    try std.testing.expectEqualStrings("review", templates[0].name);
    try std.testing.expectEqualStrings("Review things", templates[0].description);
    const expanded = (try expandInvocation(gpa, "/review src/main.zig", templates)).?;
    defer gpa.free(expanded);
    try std.testing.expectEqualStrings("Review src/main.zig", expanded);
}

test "untrusted default discovery excludes project templates" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &path_buffer);
    const root = path_buffer[0..length];
    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);
    const global_dir = try std.fs.path.join(gpa, &.{ agent_dir, "prompts" });
    defer gpa.free(global_dir);
    try std.Io.Dir.cwd().createDirPath(io, global_dir);
    const global_file = try std.fs.path.join(gpa, &.{ global_dir, "global.md" });
    defer gpa.free(global_file);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = global_file, .data = "global" });
    const project_dir = try std.fs.path.join(gpa, &.{ root, ".pi", "prompts" });
    defer gpa.free(project_dir);
    try std.Io.Dir.cwd().createDirPath(io, project_dir);
    const project_file = try std.fs.path.join(gpa, &.{ project_dir, "project.md" });
    defer gpa.free(project_file);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = project_file, .data = "project" });

    const templates = try discoverTrusted(gpa, io, root, agent_dir, false);
    defer {
        for (templates) |*template| template.deinit(gpa);
        gpa.free(templates);
    }
    try std.testing.expectEqual(@as(usize, 1), templates.len);
    try std.testing.expectEqualStrings("global", templates[0].name);
}
