//! Theme resource discovery and collision handling.
const std = @import("std");
const Io = std.Io;
const theme_mod = @import("theme.zig");

pub const DiagnosticKind = enum { invalid, duplicate };

pub const Diagnostic = struct {
    kind: DiagnosticKind,
    path: []u8,
    message: []u8,

    pub fn deinit(self: *Diagnostic, gpa: std.mem.Allocator) void {
        gpa.free(self.path);
        gpa.free(self.message);
        self.* = undefined;
    }
};

pub const Registry = struct {
    gpa: std.mem.Allocator,
    io: Io,
    themes: std.ArrayList(theme_mod.Theme) = .empty,
    sources: std.ArrayList([]u8) = .empty,
    diagnostics: std.ArrayList(Diagnostic) = .empty,

    pub fn init(gpa: std.mem.Allocator, io: Io) Registry {
        return .{ .gpa = gpa, .io = io };
    }

    pub fn deinit(self: *Registry) void {
        for (self.themes.items) |*theme| theme.deinit(self.gpa);
        self.themes.deinit(self.gpa);
        for (self.sources.items) |source| self.gpa.free(source);
        self.sources.deinit(self.gpa);
        for (self.diagnostics.items) |*diagnostic| diagnostic.deinit(self.gpa);
        self.diagnostics.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn find(self: *const Registry, name: []const u8) ?*const theme_mod.Theme {
        for (self.themes.items) |*theme| {
            if (std.mem.eql(u8, theme.name, name)) return theme;
        }
        return null;
    }

    pub fn sourceFor(self: *const Registry, name: []const u8) ?[]const u8 {
        for (self.themes.items, 0..) |theme, index| {
            if (std.mem.eql(u8, theme.name, name)) return self.sources.items[index];
        }
        return null;
    }

    fn addDiagnostic(self: *Registry, kind: DiagnosticKind, path: []const u8, message: []const u8) !void {
        try self.diagnostics.append(self.gpa, .{
            .kind = kind,
            .path = try self.gpa.dupe(u8, path),
            .message = try self.gpa.dupe(u8, message),
        });
    }

    fn loadThemeFile(self: *Registry, path: []const u8) !void {
        var loaded = theme_mod.loadFile(self.gpa, self.io, path) catch |err| {
            const message = try std.fmt.allocPrint(self.gpa, "failed to load theme: {s}", .{@errorName(err)});
            defer self.gpa.free(message);
            try self.addDiagnostic(.invalid, path, message);
            return;
        };
        errdefer loaded.deinit(self.gpa);
        if (self.find(loaded.name)) |_| {
            const winner = self.sourceFor(loaded.name) orelse "<unknown>";
            const message = try std.fmt.allocPrint(self.gpa, "theme name '{s}' already loaded from {s}; first definition wins", .{ loaded.name, winner });
            defer self.gpa.free(message);
            try self.addDiagnostic(.duplicate, path, message);
            loaded.deinit(self.gpa);
            return;
        }
        try self.themes.append(self.gpa, loaded);
        errdefer _ = self.themes.pop();
        try self.sources.append(self.gpa, try self.gpa.dupe(u8, path));
    }

    fn loadDirectory(self: *Registry, path: []const u8, missing_ok: bool) !void {
        var dir = std.Io.Dir.cwd().openDir(self.io, path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => if (missing_ok) return else return error.ThemePathNotFound,
            else => return err,
        };
        defer dir.close(self.io);
        var names: std.ArrayList([]const u8) = .empty;
        defer {
            for (names.items) |name| self.gpa.free(name);
            names.deinit(self.gpa);
        }
        var iterator = dir.iterate();
        while (try iterator.next(self.io)) |entry| {
            if (!std.mem.endsWith(u8, entry.name, ".json")) continue;
            var is_file = entry.kind == .file;
            if (!is_file and entry.kind == .sym_link) {
                const child = try std.fs.path.join(self.gpa, &.{ path, entry.name });
                defer self.gpa.free(child);
                const stat = std.Io.Dir.cwd().statFile(self.io, child, .{}) catch continue;
                is_file = stat.kind == .file;
            }
            if (!is_file) continue;
            try names.append(self.gpa, try self.gpa.dupe(u8, entry.name));
        }
        std.mem.sort([]const u8, names.items, {}, struct {
            fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
                return std.mem.order(u8, lhs, rhs) == .lt;
            }
        }.lessThan);
        for (names.items) |name| {
            const child = try std.fs.path.join(self.gpa, &.{ path, name });
            defer self.gpa.free(child);
            try self.loadThemeFile(child);
        }
    }

    /// Load an explicit JSON file or a directory of JSON themes. Missing or
    /// unsupported explicit paths are errors; malformed files become diagnostics
    /// so one broken theme cannot suppress the rest of a directory.
    pub fn loadPath(self: *Registry, path: []const u8) !void {
        const stat = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => return error.ThemePathNotFound,
            else => return err,
        };
        switch (stat.kind) {
            .directory => try self.loadDirectory(path, false),
            .file => {
                if (!std.mem.endsWith(u8, path, ".json")) return error.UnsupportedThemePath;
                try self.loadThemeFile(path);
            },
            else => return error.UnsupportedThemePath,
        }
    }

    /// Discover global themes first and trusted project themes second, matching
    /// the original resource precedence. Missing default directories are normal.
    pub fn discover(self: *Registry, cwd: []const u8, agent_dir: ?[]const u8, trust_project: bool) !void {
        if (agent_dir) |agent| {
            const global = try std.fs.path.join(self.gpa, &.{ agent, "themes" });
            defer self.gpa.free(global);
            try self.loadDirectory(global, true);
        }
        if (trust_project) {
            const project = try std.fs.path.join(self.gpa, &.{ cwd, ".pi", "themes" });
            defer self.gpa.free(project);
            try self.loadDirectory(project, true);
        }
    }
};

test "theme registry loads sorted directory and keeps first duplicate" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];
    const a = try std.fs.path.join(gpa, &.{ root, "a.json" });
    defer gpa.free(a);
    const b = try std.fs.path.join(gpa, &.{ root, "b.json" });
    defer gpa.free(b);
    const c = try std.fs.path.join(gpa, &.{ root, "c.json" });
    defer gpa.free(c);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = b, .data = "{\"name\":\"second\",\"accent\":\"green\"}" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = a, .data = "{\"name\":\"first\",\"accent\":\"red\"}" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = c, .data = "{\"name\":\"first\",\"accent\":\"blue\"}" });
    var registry = Registry.init(gpa, io);
    defer registry.deinit();
    try registry.loadPath(root);
    try std.testing.expectEqual(@as(usize, 2), registry.themes.items.len);
    try std.testing.expectEqualStrings("first", registry.themes.items[0].name);
    try std.testing.expectEqualStrings("31", registry.themes.items[0].accent_sgr);
    try std.testing.expectEqual(@as(usize, 1), registry.diagnostics.items.len);
    try std.testing.expectEqual(DiagnosticKind.duplicate, registry.diagnostics.items[0].kind);
}

test "theme registry records malformed files without blocking valid siblings" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];
    const bad = try std.fs.path.join(gpa, &.{ root, "bad.json" });
    defer gpa.free(bad);
    const good = try std.fs.path.join(gpa, &.{ root, "good.json" });
    defer gpa.free(good);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = bad, .data = "{" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = good, .data = "{\"name\":\"good\"}" });
    var registry = Registry.init(gpa, io);
    defer registry.deinit();
    try registry.loadPath(root);
    try std.testing.expect(registry.find("good") != null);
    try std.testing.expectEqual(@as(usize, 1), registry.diagnostics.items.len);
    try std.testing.expectEqual(DiagnosticKind.invalid, registry.diagnostics.items[0].kind);
}

test "theme registry reports missing explicit path" {
    var registry = Registry.init(std.testing.allocator, std.testing.io);
    defer registry.deinit();
    try std.testing.expectError(error.ThemePathNotFound, registry.loadPath("definitely-missing-theme.json"));
}
