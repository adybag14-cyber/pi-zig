//! settings.json global + project merge.
const std = @import("std");
const Io = std.Io;

pub const Settings = struct {
    model: ?[]const u8 = null,
    provider: ?[]const u8 = null,
    tools: ?[]const []const u8 = null,
    max_turns: usize = 16,
    /// Owned storage for parsed strings
    arena_owned: bool = false,

    pub fn deinit(self: *Settings, gpa: std.mem.Allocator) void {
        if (self.model) |m| gpa.free(m);
        if (self.provider) |p| gpa.free(p);
        if (self.tools) |t| {
            for (t) |x| gpa.free(x);
            gpa.free(t);
        }
        self.* = undefined;
    }
};

pub fn loadFile(gpa: std.mem.Allocator, io: Io, path: []const u8) !Settings {
    const raw = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => return err,
    };
    defer gpa.free(raw);
    return try parse(gpa, raw);
}

pub fn parse(gpa: std.mem.Allocator, raw: []const u8) !Settings {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return .{};

    var s: Settings = .{};
    errdefer s.deinit(gpa);

    if (parsed.value.object.get("model")) |v| {
        if (v == .string) s.model = try gpa.dupe(u8, v.string);
    }
    if (parsed.value.object.get("provider")) |v| {
        if (v == .string) s.provider = try gpa.dupe(u8, v.string);
    }
    if (parsed.value.object.get("max_turns") orelse parsed.value.object.get("maxTurns")) |v| {
        if (v == .integer) s.max_turns = @intCast(v.integer);
    }
    if (parsed.value.object.get("tools")) |v| {
        if (v == .array) {
            var list: std.ArrayList([]const u8) = .empty;
            errdefer {
                for (list.items) |x| gpa.free(x);
                list.deinit(gpa);
            }
            for (v.array.items) |item| {
                if (item == .string) try list.append(gpa, try gpa.dupe(u8, item.string));
            }
            s.tools = try list.toOwnedSlice(gpa);
        }
    }
    return s;
}

/// Merge global then project (project wins).
/// When `trust_project` is false, project `.pi/settings.json` is skipped (--no-approve).
pub fn loadMerge(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: ?[]const u8,
    cwd: []const u8,
) !Settings {
    return loadMergeTrusted(gpa, io, agent_dir, cwd, true);
}

pub fn loadMergeTrusted(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: ?[]const u8,
    cwd: []const u8,
    trust_project: bool,
) !Settings {
    var result: Settings = .{};
    errdefer result.deinit(gpa);

    if (agent_dir) |ad| {
        const p = try std.fs.path.join(gpa, &.{ ad, "settings.json" });
        defer gpa.free(p);
        var g = try loadFile(gpa, io, p);
        defer g.deinit(gpa);
        try mergeInto(gpa, &result, g);
    }

    // project: .pi/settings.json (only when trusted)
    if (trust_project) {
        const p = try std.fs.path.join(gpa, &.{ cwd, ".pi", "settings.json" });
        defer gpa.free(p);
        var proj = try loadFile(gpa, io, p);
        defer proj.deinit(gpa);
        try mergeInto(gpa, &result, proj);
    }

    return result;
}

fn mergeInto(gpa: std.mem.Allocator, dst: *Settings, src: Settings) !void {
    if (src.model) |m| {
        if (dst.model) |old| gpa.free(old);
        dst.model = try gpa.dupe(u8, m);
    }
    if (src.provider) |p| {
        if (dst.provider) |old| gpa.free(old);
        dst.provider = try gpa.dupe(u8, p);
    }
    if (src.tools) |t| {
        if (dst.tools) |old| {
            for (old) |x| gpa.free(x);
            gpa.free(old);
        }
        var list: std.ArrayList([]const u8) = .empty;
        for (t) |x| try list.append(gpa, try gpa.dupe(u8, x));
        dst.tools = try list.toOwnedSlice(gpa);
    }
    if (src.max_turns != 16 or dst.max_turns == 16) {
        // always take src max_turns if explicitly different, or just take it
        dst.max_turns = src.max_turns;
    }
}

pub fn formatSettings(gpa: std.mem.Allocator, s: Settings) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const header = try std.fmt.allocPrint(gpa, "model={s}\nprovider={s}\nmax_turns={d}\n", .{
        s.model orelse "(default)",
        s.provider orelse "(default)",
        s.max_turns,
    });
    defer gpa.free(header);
    try out.appendSlice(gpa, header);
    if (s.tools) |t| {
        try out.appendSlice(gpa, "tools=");
        for (t, 0..) |name, i| {
            if (i > 0) try out.append(gpa, ',');
            try out.appendSlice(gpa, name);
        }
        try out.append(gpa, '\n');
    }
    return try out.toOwnedSlice(gpa);
}

/// Store API keys as simple KEY=value lines in agent_dir/credentials
pub fn credentialsPath(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fs.path.join(gpa, &.{ agent_dir, "credentials" });
}

pub fn saveCredential(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8, key: []const u8, value: []const u8) !void {
    _ = gpa;
    try std.Io.Dir.cwd().createDirPath(io, agent_dir);
    const path = try std.fs.path.join(std.heap.page_allocator, &.{ agent_dir, "credentials" });
    defer std.heap.page_allocator.free(path);
    // Append or write simple file
    const line = try std.fmt.allocPrint(std.heap.page_allocator, "{s}={s}\n", .{ key, value });
    defer std.heap.page_allocator.free(line);
    // Read existing, replace key
    const existing = std.Io.Dir.cwd().readFileAlloc(io, path, std.heap.page_allocator, .limited(64 * 1024)) catch "";
    defer if (existing.len > 0) std.heap.page_allocator.free(existing);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.heap.page_allocator);
    var replaced = false;
    var it = std.mem.splitScalar(u8, existing, '\n');
    while (it.next()) |ln| {
        if (ln.len == 0) continue;
        if (std.mem.indexOfScalar(u8, ln, '=')) |eq| {
            if (std.mem.eql(u8, ln[0..eq], key)) {
                try out.appendSlice(std.heap.page_allocator, line);
                replaced = true;
                continue;
            }
        }
        try out.appendSlice(std.heap.page_allocator, ln);
        try out.append(std.heap.page_allocator, '\n');
    }
    if (!replaced) try out.appendSlice(std.heap.page_allocator, line);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = out.items });
}

pub fn loadCredential(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8, key: []const u8) !?[]u8 {
    const path = try credentialsPath(gpa, agent_dir);
    defer gpa.free(path);
    const existing = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 * 1024)) catch return null;
    defer gpa.free(existing);
    var it = std.mem.splitScalar(u8, existing, '\n');
    while (it.next()) |ln| {
        if (std.mem.indexOfScalar(u8, ln, '=')) |eq| {
            if (std.mem.eql(u8, ln[0..eq], key)) {
                return try gpa.dupe(u8, ln[eq + 1 ..]);
            }
        }
    }
    return null;
}

pub fn clearCredentials(io: Io, agent_dir: []const u8) !void {
    const path = try std.fs.path.join(std.heap.page_allocator, &.{ agent_dir, "credentials" });
    defer std.heap.page_allocator.free(path);
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "" }) catch {};
}

test "loadMergeTrusted skips project when untrusted" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];

    const pi_dir = try std.fs.path.join(gpa, &.{ root, ".pi" });
    defer gpa.free(pi_dir);
    try std.Io.Dir.cwd().createDirPath(io, pi_dir);
    const proj_settings = try std.fs.path.join(gpa, &.{ pi_dir, "settings.json" });
    defer gpa.free(proj_settings);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = proj_settings,
        .data =
            \\{"model":"project-only-model","max_turns":3}
        ,
    });

    var untrusted = try loadMergeTrusted(gpa, io, null, root, false);
    defer untrusted.deinit(gpa);
    try std.testing.expect(untrusted.model == null);

    var trusted = try loadMergeTrusted(gpa, io, null, root, true);
    defer trusted.deinit(gpa);
    try std.testing.expectEqualStrings("project-only-model", trusted.model.?);
    try std.testing.expectEqual(@as(usize, 3), trusted.max_turns);
}

test "parse and merge settings" {
    const gpa = std.testing.allocator;
    var s = try parse(gpa,
        \\{"model":"gpt-4o","provider":"openai","max_turns":8,"tools":["read","bash"]}
    );
    defer s.deinit(gpa);
    try std.testing.expectEqualStrings("gpt-4o", s.model.?);
    try std.testing.expectEqual(@as(usize, 8), s.max_turns);
    try std.testing.expectEqual(@as(usize, 2), s.tools.?.len);
}
