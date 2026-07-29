//! Local path packages: install / list / remove.
const std = @import("std");
const Io = std.Io;

pub const Package = struct {
    name: []const u8,
    path: []const u8,

    pub fn deinit(self: *Package, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        gpa.free(self.path);
        self.* = undefined;
    }
};

fn packagesJsonPath(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fs.path.join(gpa, &.{ agent_dir, "packages.json" });
}

pub fn list(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8) ![]Package {
    const path = try packagesJsonPath(gpa, agent_dir);
    defer gpa.free(path);
    const raw = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024)) catch {
        return try gpa.alloc(Package, 0);
    };
    defer gpa.free(raw);
    return try parsePackages(gpa, raw);
}

fn parsePackages(gpa: std.mem.Allocator, raw: []const u8) ![]Package {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return try gpa.alloc(Package, 0);

    var list_out: std.ArrayList(Package) = .empty;
    errdefer {
        for (list_out.items) |*p| p.deinit(gpa);
        list_out.deinit(gpa);
    }
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const name = item.object.get("name") orelse continue;
        const pth = item.object.get("path") orelse continue;
        if (name != .string or pth != .string) continue;
        try list_out.append(gpa, .{
            .name = try gpa.dupe(u8, name.string),
            .path = try gpa.dupe(u8, pth.string),
        });
    }
    return try list_out.toOwnedSlice(gpa);
}

fn savePackages(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8, packages: []const Package) !void {
    try std.Io.Dir.cwd().createDirPath(io, agent_dir);
    var aw: std.Io.Writer.Allocating = .init(gpa);
    defer aw.deinit();
    try aw.writer.writeAll("[");
    for (packages, 0..) |p, i| {
        if (i > 0) try aw.writer.writeAll(",");
        try aw.writer.writeAll("{\"name\":");
        try std.json.Stringify.value(p.name, .{}, &aw.writer);
        try aw.writer.writeAll(",\"path\":");
        try std.json.Stringify.value(p.path, .{}, &aw.writer);
        try aw.writer.writeAll("}");
    }
    try aw.writer.writeAll("]");
    const path = try packagesJsonPath(gpa, agent_dir);
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = aw.written() });
}

/// Install from source like `path:./local-pkg` or bare path.
pub fn install(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8, source: []const u8, cwd: []const u8) !Package {
    var path_str = source;
    if (std.mem.startsWith(u8, source, "path:")) {
        path_str = source["path:".len..];
    }
    const abs = if (std.fs.path.isAbsolute(path_str))
        try gpa.dupe(u8, path_str)
    else
        try std.fs.path.join(gpa, &.{ cwd, path_str });
    defer gpa.free(abs);

    // Resolve name from directory basename or package.json "pi" / name field
    var name = std.fs.path.basename(abs);
    // strip trailing sep
    while (name.len > 0 and (name[name.len - 1] == '/' or name[name.len - 1] == '\\')) {
        name = name[0 .. name.len - 1];
        name = std.fs.path.basename(name);
    }

    // Validate path exists
    std.Io.Dir.cwd().access(io, abs, .{}) catch return error.PackageNotFound;

    const packages = try list(gpa, io, agent_dir);
    defer {
        for (packages) |*p| {
            var mut = p.*;
            mut.deinit(gpa);
        }
        gpa.free(packages);
    }

    // Replace if same name
    var new_list: std.ArrayList(Package) = .empty;
    defer {
        // ownership transferred carefully
    }
    errdefer {
        for (new_list.items) |*p| p.deinit(gpa);
        new_list.deinit(gpa);
    }

    for (packages) |p| {
        if (std.mem.eql(u8, p.name, name)) continue;
        try new_list.append(gpa, .{
            .name = try gpa.dupe(u8, p.name),
            .path = try gpa.dupe(u8, p.path),
        });
    }
    const installed: Package = .{
        .name = try gpa.dupe(u8, name),
        .path = try gpa.dupe(u8, abs),
    };
    try new_list.append(gpa, .{
        .name = try gpa.dupe(u8, installed.name),
        .path = try gpa.dupe(u8, installed.path),
    });

    try savePackages(gpa, io, agent_dir, new_list.items);
    for (new_list.items) |*p| p.deinit(gpa);
    new_list.deinit(gpa);

    return installed;
}

pub fn remove(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8, name: []const u8) !bool {
    const packages = try list(gpa, io, agent_dir);
    defer {
        for (packages) |*p| {
            var mut = p.*;
            mut.deinit(gpa);
        }
        gpa.free(packages);
    }

    var new_list: std.ArrayList(Package) = .empty;
    errdefer {
        for (new_list.items) |*p| p.deinit(gpa);
        new_list.deinit(gpa);
    }
    var found = false;
    for (packages) |p| {
        if (std.mem.eql(u8, p.name, name)) {
            found = true;
            continue;
        }
        try new_list.append(gpa, .{
            .name = try gpa.dupe(u8, p.name),
            .path = try gpa.dupe(u8, p.path),
        });
    }
    if (!found) return false;
    try savePackages(gpa, io, agent_dir, new_list.items);
    for (new_list.items) |*p| p.deinit(gpa);
    new_list.deinit(gpa);
    return true;
}

/// Collect skills/ dirs from installed packages.
pub fn packageSkillDirs(gpa: std.mem.Allocator, packages: []const Package) ![]const []const u8 {
    var list_out: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (list_out.items) |p| gpa.free(p);
        list_out.deinit(gpa);
    }
    for (packages) |p| {
        const skills = try std.fs.path.join(gpa, &.{ p.path, "skills" });
        try list_out.append(gpa, skills);
    }
    return try list_out.toOwnedSlice(gpa);
}

test "install list remove package" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];

    const agent = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent);
    try std.Io.Dir.cwd().createDirPath(io, agent);

    const pkg = try std.fs.path.join(gpa, &.{ root, "mypkg" });
    defer gpa.free(pkg);
    try std.Io.Dir.cwd().createDirPath(io, pkg);
    const skills = try std.fs.path.join(gpa, &.{ pkg, "skills" });
    defer gpa.free(skills);
    try std.Io.Dir.cwd().createDirPath(io, skills);

    var installed = try install(gpa, io, agent, "path:mypkg", root);
    defer installed.deinit(gpa);
    try std.testing.expectEqualStrings("mypkg", installed.name);

    const packages = try list(gpa, io, agent);
    defer {
        for (packages) |*p| {
            var mut = p.*;
            mut.deinit(gpa);
        }
        gpa.free(packages);
    }
    try std.testing.expectEqual(@as(usize, 1), packages.len);

    try std.testing.expect(try remove(gpa, io, agent, "mypkg"));
    const after = try list(gpa, io, agent);
    defer {
        for (after) |*p| {
            var mut = p.*;
            mut.deinit(gpa);
        }
        gpa.free(after);
    }
    try std.testing.expectEqual(@as(usize, 0), after.len);
}
