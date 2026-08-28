//! AGENTS.md / CLAUDE.md walk + SYSTEM.md / APPEND_SYSTEM.md + global ~/.pi/agent
const std = @import("std");
const Io = std.Io;

pub const ContextKind = enum { agents_override, agents, claude, system, append_system, other };

pub const ContextFile = struct {
    path: []const u8,
    content: []const u8,
    kind: ContextKind = .other,

    pub fn deinit(self: *ContextFile, gpa: std.mem.Allocator) void {
        gpa.free(self.path);
        gpa.free(self.content);
        self.* = undefined;
    }
};

pub const ContextBundle = struct {
    files: []ContextFile,
    /// If SYSTEM.md found, replaces default system prompt body.
    system_override: ?[]const u8 = null,
    /// APPEND_SYSTEM.md contents joined.
    append_system: []const u8 = "",

    pub fn deinit(self: *ContextBundle, gpa: std.mem.Allocator) void {
        for (self.files) |*f| f.deinit(gpa);
        gpa.free(self.files);
        if (self.system_override) |s| gpa.free(s);
        if (self.append_system.len > 0) gpa.free(self.append_system);
        self.* = undefined;
    }
};

/// Discover context files.
/// 1. global agent dir: AGENTS.md, CLAUDE.md, SYSTEM.md, APPEND_SYSTEM.md
/// 2. walk cwd→root (when trust_project): AGENTS.md prefer over CLAUDE.md; SYSTEM.md; APPEND_SYSTEM.md
pub fn discover(
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    global_dir: ?[]const u8,
) !ContextBundle {
    return discoverTrusted(gpa, io, cwd, global_dir, true);
}

pub fn discoverTrusted(
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    global_dir: ?[]const u8,
    trust_project: bool,
) !ContextBundle {
    var files: std.ArrayList(ContextFile) = .empty;
    errdefer {
        for (files.items) |*f| f.deinit(gpa);
        files.deinit(gpa);
    }

    var system_override: ?[]u8 = null;
    errdefer if (system_override) |s| gpa.free(s);
    var append_parts: std.ArrayList([]const u8) = .empty;
    defer {
        for (append_parts.items) |p| gpa.free(p);
        append_parts.deinit(gpa);
    }

    if (global_dir) |gdir| {
        _ = try tryLoadDirectoryContext(gpa, io, gdir, &files);
        if (try loadOptional(gpa, io, gdir, "SYSTEM.md")) |s| {
            if (system_override) |old| gpa.free(old);
            system_override = s;
        }
        if (try loadOptional(gpa, io, gdir, "APPEND_SYSTEM.md")) |a| {
            try append_parts.append(gpa, a);
        }
    }

    if (trust_project) {
        var current = try gpa.dupe(u8, cwd);
        defer gpa.free(current);
        var depth: usize = 0;

        while (depth < 64) : (depth += 1) {
            _ = try tryLoadDirectoryContext(gpa, io, current, &files);
            // Project SYSTEM.md overrides global
            if (try loadOptional(gpa, io, current, "SYSTEM.md")) |s| {
                if (system_override) |old| gpa.free(old);
                system_override = s;
            }
            if (try loadOptional(gpa, io, current, "APPEND_SYSTEM.md")) |a| {
                try append_parts.append(gpa, a);
            }

            const parent = std.fs.path.dirname(current) orelse break;
            if (parent.len == 0) break;
            if (std.mem.eql(u8, parent, current)) break;
            if (parent.len >= current.len) break;
            const next = try gpa.dupe(u8, parent);
            gpa.free(current);
            current = next;
        }
    }

    var append_joined: []u8 = try gpa.dupe(u8, "");
    if (append_parts.items.len > 0) {
        gpa.free(append_joined);
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);
        for (append_parts.items, 0..) |p, i| {
            if (i > 0) try out.appendSlice(gpa, "\n\n");
            try out.appendSlice(gpa, p);
        }
        append_joined = try out.toOwnedSlice(gpa);
    }

    return .{
        .files = try files.toOwnedSlice(gpa),
        .system_override = system_override,
        .append_system = append_joined,
    };
}

/// Load the single context file selected for one directory. An override is
/// directory-local: it replaces AGENTS.md/CLAUDE.md only at this level while
/// parent and child directory context files continue to layer normally.
fn tryLoadDirectoryContext(
    gpa: std.mem.Allocator,
    io: Io,
    dir: []const u8,
    out: *std.ArrayList(ContextFile),
) !bool {
    if (try tryLoad(gpa, io, dir, "AGENTS.override.md", .agents_override, out)) return true;
    if (try tryLoad(gpa, io, dir, "AGENTS.md", .agents, out)) return true;
    return try tryLoad(gpa, io, dir, "CLAUDE.md", .claude, out);
}

fn tryLoad(
    gpa: std.mem.Allocator,
    io: Io,
    dir: []const u8,
    name: []const u8,
    kind: ContextKind,
    out: *std.ArrayList(ContextFile),
) !bool {
    const path = try std.fs.path.join(gpa, &.{ dir, name });
    defer gpa.free(path);
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    errdefer gpa.free(data);
    try out.append(gpa, .{
        .path = try gpa.dupe(u8, path),
        .content = data,
        .kind = kind,
    });
    return true;
}

fn loadOptional(gpa: std.mem.Allocator, io: Io, dir: []const u8, name: []const u8) !?[]u8 {
    const path = try std.fs.path.join(gpa, &.{ dir, name });
    defer gpa.free(path);
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    return data;
}

pub fn assembleContextPrompt(gpa: std.mem.Allocator, files: []const ContextFile) ![]u8 {
    if (files.len == 0) return try gpa.dupe(u8, "");
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "# Project context files\n\n");
    for (files) |f| {
        try out.appendSlice(gpa, "## ");
        try out.appendSlice(gpa, f.path);
        try out.appendSlice(gpa, "\n\n");
        try out.appendSlice(gpa, f.content);
        try out.appendSlice(gpa, "\n\n");
    }
    return try out.toOwnedSlice(gpa);
}

test "discover AGENTS and SYSTEM" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];

    const agents = try std.fs.path.join(gpa, &.{ root, "AGENTS.md" });
    defer gpa.free(agents);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = agents, .data = "root agents" });

    const system = try std.fs.path.join(gpa, &.{ root, "SYSTEM.md" });
    defer gpa.free(system);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = system, .data = "custom system" });

    const append = try std.fs.path.join(gpa, &.{ root, "APPEND_SYSTEM.md" });
    defer gpa.free(append);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = append, .data = "append me" });

    var bundle = try discover(gpa, io, root, null);
    defer bundle.deinit(gpa);

    try std.testing.expect(bundle.files.len >= 1);
    try std.testing.expect(bundle.system_override != null);
    try std.testing.expectEqualStrings("custom system", bundle.system_override.?);
    try std.testing.expect(std.mem.indexOf(u8, bundle.append_system, "append me") != null);
}

test "AGENTS override replaces only same-directory context" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];
    const child = try std.fs.path.join(gpa, &.{ root, "child" });
    defer gpa.free(child);
    try std.Io.Dir.cwd().createDirPath(io, child);

    const root_agents = try std.fs.path.join(gpa, &.{ root, "AGENTS.md" });
    defer gpa.free(root_agents);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = root_agents, .data = "root instructions" });

    const child_agents = try std.fs.path.join(gpa, &.{ child, "AGENTS.md" });
    defer gpa.free(child_agents);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = child_agents, .data = "shadowed child instructions" });

    const child_claude = try std.fs.path.join(gpa, &.{ child, "CLAUDE.md" });
    defer gpa.free(child_claude);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = child_claude, .data = "shadowed claude instructions" });

    const child_override = try std.fs.path.join(gpa, &.{ child, "AGENTS.override.md" });
    defer gpa.free(child_override);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = child_override, .data = "child override" });

    var bundle = try discover(gpa, io, child, null);
    defer bundle.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 2), bundle.files.len);
    var saw_root = false;
    var saw_override = false;
    for (bundle.files) |file| {
        if (file.kind == .agents and std.mem.eql(u8, file.content, "root instructions")) saw_root = true;
        if (file.kind == .agents_override and std.mem.eql(u8, file.content, "child override")) saw_override = true;
        try std.testing.expect(!std.mem.eql(u8, file.content, "shadowed child instructions"));
        try std.testing.expect(!std.mem.eql(u8, file.content, "shadowed claude instructions"));
    }
    try std.testing.expect(saw_root);
    try std.testing.expect(saw_override);
}
