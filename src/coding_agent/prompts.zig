//! Prompt templates with {{var}} expansion.
const std = @import("std");
const Io = std.Io;

pub const PromptTemplate = struct {
    name: []const u8,
    path: []const u8,
    content: []const u8,

    pub fn deinit(self: *PromptTemplate, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        gpa.free(self.path);
        gpa.free(self.content);
        self.* = undefined;
    }
};

/// Discover ~/.pi/agent/prompts/*.md and <cwd>/.pi/prompts/*.md
pub fn discover(gpa: std.mem.Allocator, io: Io, cwd: []const u8, agent_dir: ?[]const u8) ![]PromptTemplate {
    var list: std.ArrayList(PromptTemplate) = .empty;
    errdefer {
        for (list.items) |*p| p.deinit(gpa);
        list.deinit(gpa);
    }

    if (agent_dir) |ad| {
        const p = try std.fs.path.join(gpa, &.{ ad, "prompts" });
        defer gpa.free(p);
        try scanDir(gpa, io, p, &list);
    }
    {
        const p = try std.fs.path.join(gpa, &.{ cwd, ".pi", "prompts" });
        defer gpa.free(p);
        try scanDir(gpa, io, p, &list);
    }
    return try list.toOwnedSlice(gpa);
}

fn scanDir(gpa: std.mem.Allocator, io: Io, dir_path: []const u8, out: *std.ArrayList(PromptTemplate)) !void {
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch return;
    defer dir.close(io);
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".md")) continue;
        const full = try std.fs.path.join(gpa, &.{ dir_path, entry.name });
        defer gpa.free(full);
        const content = std.Io.Dir.cwd().readFileAlloc(io, full, gpa, .limited(512 * 1024)) catch continue;
        errdefer gpa.free(content);
        const name = if (std.mem.endsWith(u8, entry.name, ".md"))
            entry.name[0 .. entry.name.len - 3]
        else
            entry.name;
        try out.append(gpa, .{
            .name = try gpa.dupe(u8, name),
            .path = try gpa.dupe(u8, full),
            .content = content,
        });
    }
}

/// Expand {{key}} placeholders using vars map (linear search).
pub fn expand(gpa: std.mem.Allocator, template: []const u8, keys: []const []const u8, values: []const []const u8) ![]u8 {
    std.debug.assert(keys.len == values.len);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    var i: usize = 0;
    while (i < template.len) {
        if (template[i] == '{' and i + 1 < template.len and template[i + 1] == '{') {
            const start = i + 2;
            const end = std.mem.indexOfPos(u8, template, start, "}}") orelse {
                try out.append(gpa, template[i]);
                i += 1;
                continue;
            };
            const key = std.mem.trim(u8, template[start..end], " \t");
            var replaced = false;
            for (keys, values) |k, v| {
                if (std.mem.eql(u8, k, key)) {
                    try out.appendSlice(gpa, v);
                    replaced = true;
                    break;
                }
            }
            if (!replaced) {
                try out.appendSlice(gpa, template[i .. end + 2]);
            }
            i = end + 2;
        } else {
            try out.append(gpa, template[i]);
            i += 1;
        }
    }
    return try out.toOwnedSlice(gpa);
}

pub fn findByName(templates: []const PromptTemplate, name: []const u8) ?PromptTemplate {
    for (templates) |t| {
        if (std.mem.eql(u8, t.name, name)) return t;
    }
    return null;
}

test "expand placeholders" {
    const gpa = std.testing.allocator;
    const keys = [_][]const u8{ "name", "cwd" };
    const values = [_][]const u8{ "pi", "/tmp" };
    const out = try expand(gpa, "Hello {{name}} in {{cwd}}!", &keys, &values);
    defer gpa.free(out);
    try std.testing.expectEqualStrings("Hello pi in /tmp!", out);
}

test "discover prompt templates" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];

    const pdir = try std.fs.path.join(gpa, &.{ root, ".pi", "prompts" });
    defer gpa.free(pdir);
    try std.Io.Dir.cwd().createDirPath(io, pdir);
    const pf = try std.fs.path.join(gpa, &.{ pdir, "greet.md" });
    defer gpa.free(pf);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = pf, .data = "Hi {{name}}" });

    const templates = try discover(gpa, io, root, null);
    defer {
        for (templates) |*t| {
            var mut = t.*;
            mut.deinit(gpa);
        }
        gpa.free(templates);
    }
    try std.testing.expectEqual(@as(usize, 1), templates.len);
    try std.testing.expectEqualStrings("greet", templates[0].name);
}
