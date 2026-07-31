//! Extension host: load declarative extension manifests and invoke hooks.
//! Full TS extension host is out of process; this runs Zig/JSON plugins.
const std = @import("std");
const Io = std.Io;

pub const ExtensionManifest = struct {
    name: []const u8,
    version: []const u8 = "0.0.0",
    /// Hook names: session_start, before_prompt, after_tool, etc.
    hooks: []const []const u8 = &.{},
    /// Path to plugin script/binary (optional).
    entry: []const u8 = "",

    pub fn deinit(self: *ExtensionManifest, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        gpa.free(self.version);
        for (self.hooks) |h| gpa.free(h);
        gpa.free(self.hooks);
        if (self.entry.len > 0) gpa.free(self.entry);
        self.* = undefined;
    }
};

pub const Host = struct {
    gpa: std.mem.Allocator,
    io: Io,
    extensions: std.ArrayList(ExtensionManifest) = .empty,
    /// Last hook event payloads for tests/observability.
    last_hook: []const u8 = "",

    pub fn deinit(self: *Host) void {
        for (self.extensions.items) |*e| e.deinit(self.gpa);
        self.extensions.deinit(self.gpa);
        if (self.last_hook.len > 0) self.gpa.free(self.last_hook);
        self.* = undefined;
    }

    /// Load extension.json from a directory.
    pub fn loadDir(self: *Host, dir_path: []const u8) !void {
        const man_path = try std.fs.path.join(self.gpa, &.{ dir_path, "extension.json" });
        defer self.gpa.free(man_path);
        const raw = std.Io.Dir.cwd().readFileAlloc(self.io, man_path, self.gpa, .limited(256 * 1024)) catch return;
        defer self.gpa.free(raw);
        try self.loadJson(raw, dir_path);
    }

    pub fn loadJson(self: *Host, raw: []const u8, base_dir: []const u8) !void {
        var parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, raw, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidManifest;
        const name = if (parsed.value.object.get("name")) |v| (if (v == .string) v.string else "unnamed") else "unnamed";
        const version = if (parsed.value.object.get("version")) |v| (if (v == .string) v.string else "0.0.0") else "0.0.0";
        var hooks_list: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (hooks_list.items) |h| self.gpa.free(h);
            hooks_list.deinit(self.gpa);
        }
        if (parsed.value.object.get("hooks")) |h| {
            if (h == .array) {
                for (h.array.items) |item| {
                    if (item == .string) try hooks_list.append(self.gpa, try self.gpa.dupe(u8, item.string));
                }
            }
        }
        var entry: []const u8 = "";
        if (parsed.value.object.get("entry")) |e| {
            if (e == .string) {
                entry = try std.fs.path.join(self.gpa, &.{ base_dir, e.string });
            }
        }
        try self.extensions.append(self.gpa, .{
            .name = try self.gpa.dupe(u8, name),
            .version = try self.gpa.dupe(u8, version),
            .hooks = try hooks_list.toOwnedSlice(self.gpa),
            .entry = entry,
        });
    }

    /// Fire a named hook; records payload. Entry processes may be spawned later.
    pub fn emit(self: *Host, hook: []const u8, payload_json: []const u8) !void {
        if (self.last_hook.len > 0) self.gpa.free(self.last_hook);
        self.last_hook = try std.fmt.allocPrint(self.gpa, "{s}:{s}", .{ hook, payload_json });
        for (self.extensions.items) |ext| {
            for (ext.hooks) |h| {
                if (std.mem.eql(u8, h, hook)) {
                    // Future: spawn ext.entry with payload on stdin
                    _ = ext.entry;
                }
            }
        }
    }

    pub fn hasHook(self: *const Host, hook: []const u8) bool {
        for (self.extensions.items) |ext| {
            for (ext.hooks) |h| {
                if (std.mem.eql(u8, h, hook)) return true;
            }
        }
        return false;
    }
};

test "load extension manifest and emit hook" {
    const gpa = std.testing.allocator;
    var host = Host{ .gpa = gpa, .io = std.testing.io };
    defer host.deinit();
    try host.loadJson(
        \\{"name":"demo","version":"1.0.0","hooks":["before_prompt","after_tool"],"entry":"plugin.js"}
    , "/ext/demo");
    try std.testing.expectEqual(@as(usize, 1), host.extensions.items.len);
    try std.testing.expect(host.hasHook("before_prompt"));
    try host.emit("before_prompt", "{\"text\":\"hi\"}");
    try std.testing.expect(std.mem.indexOf(u8, host.last_hook, "before_prompt") != null);
}
