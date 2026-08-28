//! Project trust storage and resource detection compatible with upstream Pi.
const std = @import("std");
const Io = std.Io;
const config = @import("../config.zig");

pub const Decision = ?bool;

pub const Entry = struct {
    path: []u8,
    decision: bool,

    pub fn deinit(self: *Entry, gpa: std.mem.Allocator) void {
        gpa.free(self.path);
        self.* = undefined;
    }
};

pub const Update = struct {
    path: []const u8,
    decision: Decision,
};

pub const Option = struct {
    label: []u8,
    trusted: bool,
    updates: []Update,
    saved_path: ?[]u8 = null,

    pub fn deinit(self: *Option, gpa: std.mem.Allocator) void {
        gpa.free(self.label);
        for (self.updates) |update| gpa.free(@constCast(update.path));
        gpa.free(self.updates);
        if (self.saved_path) |path| gpa.free(path);
        self.* = undefined;
    }
};

fn normalizedPath(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    // `path.resolve` performs the lexical canonicalization needed for stable
    // trust keys without requiring the target to exist.
    return std.fs.path.resolve(gpa, &.{path});
}

fn parentPath(path: []const u8) ?[]const u8 {
    const parent = std.fs.path.dirname(path) orelse return null;
    if (std.mem.eql(u8, parent, path)) return null;
    return parent;
}

pub fn getParentPath(gpa: std.mem.Allocator, cwd: []const u8) !?[]u8 {
    const normalized = try normalizedPath(gpa, cwd);
    defer gpa.free(normalized);
    const parent = parentPath(normalized) orelse return null;
    return try gpa.dupe(u8, parent);
}

pub fn getOptions(gpa: std.mem.Allocator, cwd: []const u8, include_session_only: bool) ![]Option {
    const trust_path = try normalizedPath(gpa, cwd);
    defer gpa.free(trust_path);
    var options: std.ArrayList(Option) = .empty;
    errdefer {
        for (options.items) |*option| option.deinit(gpa);
        options.deinit(gpa);
    }

    const self_update_path = try gpa.dupe(u8, trust_path);
    const self_updates = try gpa.alloc(Update, 1);
    self_updates[0] = .{ .path = self_update_path, .decision = true };
    try options.append(gpa, .{
        .label = try gpa.dupe(u8, "Trust"),
        .trusted = true,
        .updates = self_updates,
        .saved_path = try gpa.dupe(u8, trust_path),
    });

    if (parentPath(trust_path)) |parent| {
        const parent_owned = try gpa.dupe(u8, parent);
        const child_owned = try gpa.dupe(u8, trust_path);
        const updates = try gpa.alloc(Update, 2);
        updates[0] = .{ .path = parent_owned, .decision = true };
        updates[1] = .{ .path = child_owned, .decision = null };
        try options.append(gpa, .{
            .label = try std.fmt.allocPrint(gpa, "Trust parent folder ({s})", .{parent}),
            .trusted = true,
            .updates = updates,
            .saved_path = try gpa.dupe(u8, parent),
        });
    }

    if (include_session_only) {
        try options.append(gpa, .{
            .label = try gpa.dupe(u8, "Trust (this session only)"),
            .trusted = true,
            .updates = try gpa.alloc(Update, 0),
        });
    }

    const deny_path = try gpa.dupe(u8, trust_path);
    const deny_updates = try gpa.alloc(Update, 1);
    deny_updates[0] = .{ .path = deny_path, .decision = false };
    try options.append(gpa, .{
        .label = try gpa.dupe(u8, "Do not trust"),
        .trusted = false,
        .updates = deny_updates,
        .saved_path = try gpa.dupe(u8, trust_path),
    });
    if (include_session_only) {
        try options.append(gpa, .{
            .label = try gpa.dupe(u8, "Do not trust (this session only)"),
            .trusted = false,
            .updates = try gpa.alloc(Update, 0),
        });
    }
    return try options.toOwnedSlice(gpa);
}

fn pathExists(io: Io, path: []const u8) bool {
    std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

pub fn hasTrustRequiringProjectResources(
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    home_dir: []const u8,
) !bool {
    const normalized_cwd = try normalizedPath(gpa, cwd);
    defer gpa.free(normalized_cwd);
    const normalized_home = try normalizedPath(gpa, home_dir);
    defer gpa.free(normalized_home);
    const user_agents_skills = try std.fs.path.join(gpa, &.{ normalized_home, ".agents", "skills" });
    defer gpa.free(user_agents_skills);

    const resources = [_][]const u8{
        "settings.json",
        "packages.json",
        "npm",
        "git",
        "extensions",
        "skills",
        "prompts",
        "themes",
        "SYSTEM.md",
        "APPEND_SYSTEM.md",
    };
    for (resources) |resource| {
        const candidate = try std.fs.path.join(gpa, &.{ normalized_cwd, config.CONFIG_DIR_NAME, resource });
        defer gpa.free(candidate);
        if (pathExists(io, candidate)) return true;
    }

    var current = try gpa.dupe(u8, normalized_cwd);
    defer gpa.free(current);
    while (true) {
        const candidate = try std.fs.path.join(gpa, &.{ current, ".agents", "skills" });
        defer gpa.free(candidate);
        if (!std.mem.eql(u8, candidate, user_agents_skills) and pathExists(io, candidate)) return true;
        const parent = parentPath(current) orelse return false;
        if (std.mem.eql(u8, parent, current)) return false;
        const next = try gpa.dupe(u8, parent);
        gpa.free(current);
        current = next;
    }
}

pub const ResolveInput = struct {
    override: ?bool = null,
    has_resources: bool,
    stored: Decision = null,
    default_policy: @import("settings.zig").DefaultProjectTrust = .ask,
    has_ui: bool = false,
};

pub const ResolveResult = union(enum) {
    resolved: bool,
    ask_ui,
};

/// Pure startup policy resolution. UI selection is intentionally returned to
/// the caller so interactive frontends can present the full trust options.
pub fn resolvePolicy(input: ResolveInput) ResolveResult {
    if (input.override) |value| return .{ .resolved = value };
    if (!input.has_resources) return .{ .resolved = true };
    if (input.stored) |value| return .{ .resolved = value };
    return switch (input.default_policy) {
        .always => .{ .resolved = true },
        .never => .{ .resolved = false },
        .ask => if (input.has_ui) .ask_ui else .{ .resolved = false },
    };
}

pub const Store = struct {
    gpa: std.mem.Allocator,
    io: Io,
    path: []u8,

    pub fn init(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8) !Store {
        return .{ .gpa = gpa, .io = io, .path = try std.fs.path.join(gpa, &.{ agent_dir, "trust.json" }) };
    }

    pub fn initPath(gpa: std.mem.Allocator, io: Io, path: []const u8) !Store {
        return .{ .gpa = gpa, .io = io, .path = try gpa.dupe(u8, path) };
    }

    pub fn deinit(self: *Store) void {
        self.gpa.free(self.path);
        self.* = undefined;
    }

    fn ensureParent(self: *const Store) !void {
        if (std.fs.path.dirname(self.path)) |parent| try std.Io.Dir.cwd().createDirPath(self.io, parent);
    }

    fn openLocked(self: *const Store, lock: std.Io.File.Lock) !std.Io.File {
        try self.ensureParent();
        return std.Io.Dir.cwd().createFile(self.io, self.path, .{ .read = true, .truncate = false, .lock = lock });
    }

    fn readRoot(self: *const Store, file: std.Io.File) !std.json.Parsed(std.json.Value) {
        const file_len = try file.length(self.io);
        if (file_len > 4 * 1024 * 1024) return error.TrustFileTooLarge;
        const len: usize = @intCast(file_len);
        const raw = if (len == 0) try self.gpa.dupe(u8, "{}") else blk: {
            const data = try self.gpa.alloc(u8, len);
            errdefer self.gpa.free(data);
            const got = try file.readPositionalAll(self.io, data, 0);
            if (got != len) return error.UnexpectedEndOfFile;
            break :blk data;
        };
        defer self.gpa.free(raw);
        var parsed = std.json.parseFromSlice(std.json.Value, self.gpa, raw, .{}) catch return error.InvalidTrustJson;
        errdefer parsed.deinit();
        if (parsed.value != .object) return error.InvalidTrustJson;
        var it = parsed.value.object.iterator();
        while (it.next()) |kv| switch (kv.value_ptr.*) {
            .bool, .null => {},
            else => return error.InvalidTrustJson,
        };
        return parsed;
    }

    fn writeRoot(self: *const Store, file: std.Io.File, root: std.json.Value) !void {
        var keys: std.ArrayList([]const u8) = .empty;
        defer keys.deinit(self.gpa);
        var it = root.object.iterator();
        while (it.next()) |kv| try keys.append(self.gpa, kv.key_ptr.*);
        std.mem.sort([]const u8, keys.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        var out: std.Io.Writer.Allocating = .init(self.gpa);
        defer out.deinit();
        try out.writer.writeAll("{\n");
        for (keys.items, 0..) |key, i| {
            if (i != 0) try out.writer.writeAll(",\n");
            try out.writer.writeAll("  ");
            try std.json.Stringify.value(key, .{}, &out.writer);
            try out.writer.writeAll(": ");
            try std.json.Stringify.value(root.object.get(key).?, .{}, &out.writer);
        }
        if (keys.items.len > 0) try out.writer.writeByte('\n');
        try out.writer.writeAll("}\n");
        try file.setLength(self.io, 0);
        try file.writePositionalAll(self.io, out.written(), 0);
    }

    pub fn get(self: *const Store, cwd: []const u8) !Decision {
        var entry = try self.getEntry(cwd) orelse return null;
        defer entry.deinit(self.gpa);
        return entry.decision;
    }

    pub fn getEntry(self: *const Store, cwd: []const u8) !?Entry {
        const file = try self.openLocked(.shared);
        defer file.close(self.io);
        var parsed = try self.readRoot(file);
        defer parsed.deinit();
        var current = try normalizedPath(self.gpa, cwd);
        defer self.gpa.free(current);
        while (true) {
            if (parsed.value.object.get(current)) |value| {
                if (value == .bool) return .{ .path = try self.gpa.dupe(u8, current), .decision = value.bool };
            }
            const parent = parentPath(current) orelse return null;
            if (std.mem.eql(u8, parent, current)) return null;
            const next = try self.gpa.dupe(u8, parent);
            self.gpa.free(current);
            current = next;
        }
    }

    pub fn set(self: *const Store, cwd: []const u8, decision: Decision) !void {
        const update = [_]Update{.{ .path = cwd, .decision = decision }};
        try self.setMany(&update);
    }

    pub fn setMany(self: *const Store, updates: []const Update) !void {
        const file = try self.openLocked(.exclusive);
        defer file.close(self.io);
        var parsed = try self.readRoot(file);
        defer parsed.deinit();
        const a = parsed.arena.allocator();
        for (updates) |update| {
            const key = try normalizedPath(a, update.path);
            if (update.decision) |decision| {
                try parsed.value.object.put(a, key, .{ .bool = decision });
            } else {
                _ = parsed.value.object.orderedRemove(key);
            }
        }
        try self.writeRoot(file, parsed.value);
    }
};

test "project trust store inherits parent and child override" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_n = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_n];
    const agent = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent);
    const parent = try std.fs.path.join(gpa, &.{ root, "trusted-parent" });
    defer gpa.free(parent);
    const child = try std.fs.path.join(gpa, &.{ parent, "project" });
    defer gpa.free(child);
    try std.Io.Dir.cwd().createDirPath(io, child);
    var store = try Store.init(gpa, io, agent);
    defer store.deinit();
    try std.testing.expect((try store.get(child)) == null);
    try store.set(parent, true);
    try std.testing.expectEqual(true, (try store.get(child)).?);
    try store.set(child, false);
    try std.testing.expectEqual(false, (try store.get(child)).?);
    try store.set(child, null);
    try std.testing.expectEqual(true, (try store.get(child)).?);
}

test "project trust options match parent session and deny choices" {
    const gpa = std.testing.allocator;
    const cwd = if (@import("builtin").os.tag == .windows) "C:\\work\\project" else "/work/project";
    const options = try getOptions(gpa, cwd, true);
    defer {
        for (options) |*option| option.deinit(gpa);
        gpa.free(options);
    }
    try std.testing.expectEqual(@as(usize, 5), options.len);
    try std.testing.expectEqualStrings("Trust", options[0].label);
    try std.testing.expect(options[1].trusted);
    try std.testing.expectEqual(@as(usize, 2), options[1].updates.len);
    try std.testing.expect(options[1].updates[1].decision == null);
    try std.testing.expectEqualStrings("Trust (this session only)", options[2].label);
    try std.testing.expect(!options[3].trusted);
}

test "detect trust requiring project resources and ignore user agents skills" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var home_buf: [std.fs.max_path_bytes]u8 = undefined;
    const home_n = try tmp.dir.realPath(io, &home_buf);
    const home = home_buf[0..home_n];
    const project = try std.fs.path.join(gpa, &.{ home, "project" });
    defer gpa.free(project);
    try std.Io.Dir.cwd().createDirPath(io, project);
    const user_skills = try std.fs.path.join(gpa, &.{ home, ".agents", "skills" });
    defer gpa.free(user_skills);
    try std.Io.Dir.cwd().createDirPath(io, user_skills);
    try std.testing.expect(!(try hasTrustRequiringProjectResources(gpa, io, home, home)));
    try std.testing.expect(!(try hasTrustRequiringProjectResources(gpa, io, project, home)));

    const pi = try std.fs.path.join(gpa, &.{ project, config.CONFIG_DIR_NAME });
    defer gpa.free(pi);
    try std.Io.Dir.cwd().createDirPath(io, pi);
    const settings = try std.fs.path.join(gpa, &.{ pi, "settings.json" });
    defer gpa.free(settings);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = settings, .data = "{}" });
    try std.testing.expect(try hasTrustRequiringProjectResources(gpa, io, project, home));

    std.Io.Dir.cwd().deleteFile(io, settings) catch {};
    const nested = try std.fs.path.join(gpa, &.{ project, "nested", "work" });
    defer gpa.free(nested);
    try std.Io.Dir.cwd().createDirPath(io, nested);
    const project_skills = try std.fs.path.join(gpa, &.{ project, ".agents", "skills" });
    defer gpa.free(project_skills);
    try std.Io.Dir.cwd().createDirPath(io, project_skills);
    try std.testing.expect(try hasTrustRequiringProjectResources(gpa, io, nested, home));
}

test "project trust startup policy matches override store default and no-ui ordering" {
    try std.testing.expect((resolvePolicy(.{ .override = false, .has_resources = false })).resolved == false);
    try std.testing.expect((resolvePolicy(.{ .has_resources = false })).resolved == true);
    try std.testing.expect((resolvePolicy(.{ .has_resources = true, .stored = true, .default_policy = .never })).resolved == true);
    try std.testing.expect((resolvePolicy(.{ .has_resources = true, .default_policy = .always })).resolved == true);
    try std.testing.expect((resolvePolicy(.{ .has_resources = true, .default_policy = .never })).resolved == false);
    try std.testing.expect((resolvePolicy(.{ .has_resources = true, .default_policy = .ask, .has_ui = false })).resolved == false);
    try std.testing.expect(resolvePolicy(.{ .has_resources = true, .default_policy = .ask, .has_ui = true }) == .ask_ui);
}
