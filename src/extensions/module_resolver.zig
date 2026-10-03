//! Native resolution of extension files and user-installed ESM packages.
const std = @import("std");

pub const Resolver = struct {
    io: std.Io,

    fn file(self: *Resolver, gpa: std.mem.Allocator, path: []const u8) !?[]u8 {
        const stat = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch |err| switch (err) {
            error.FileNotFound, error.NotDir => return null,
            else => return err,
        };
        if (stat.kind != .file) return null;
        const resolved = try std.Io.Dir.cwd().realPathFileAlloc(self.io, path, gpa);
        errdefer gpa.free(resolved);
        for (resolved) |*byte| if (byte.* == '\\') {
            byte.* = '/';
        };
        return resolved;
    }

    fn packageJson(self: *Resolver, gpa: std.mem.Allocator, directory: []const u8) !?std.json.Value {
        const path = try std.fs.path.join(gpa, &.{ directory, "package.json" });
        defer gpa.free(path);
        const bytes = std.Io.Dir.cwd().readFileAlloc(self.io, path, gpa, .limited(1024 * 1024)) catch |err| switch (err) {
            error.FileNotFound, error.NotDir => return null,
            else => return err,
        };
        defer gpa.free(bytes);
        const value = try std.json.parseFromSliceLeaky(std.json.Value, gpa, bytes, .{ .allocate = .alloc_always });
        if (value != .object) return error.InvalidExtensionPackage;
        return value;
    }

    fn local(self: *Resolver, gpa: std.mem.Allocator, path: []const u8, allow_directory: bool) anyerror![]u8 {
        if (try self.file(gpa, path)) |resolved| return resolved;
        if (std.fs.path.extension(path).len == 0) {
            for ([_][]const u8{ ".js", ".ts", ".mjs", ".mts", ".cts", ".cjs" }) |extension| {
                const candidate = try std.fmt.allocPrint(gpa, "{s}{s}", .{ path, extension });
                defer gpa.free(candidate);
                if (try self.file(gpa, candidate)) |resolved| return resolved;
            }
        }
        if (allow_directory) {
            if (try self.packageJson(gpa, path)) |package| {
                for ([_][]const u8{ "module", "main" }) |field| if (package.object.get(field)) |entry| {
                    if (entry != .string) return error.InvalidExtensionPackage;
                    const candidate = try std.fs.path.resolve(gpa, &.{ path, entry.string });
                    defer gpa.free(candidate);
                    return self.local(gpa, candidate, false);
                };
            }
            for ([_][]const u8{ "index.js", "index.ts", "index.mjs", "index.mts" }) |index| {
                const candidate = try std.fs.path.join(gpa, &.{ path, index });
                defer gpa.free(candidate);
                if (try self.file(gpa, candidate)) |resolved| return resolved;
            }
        }
        return error.ExtensionModuleNotFound;
    }

    const Target = union(enum) { missing, blocked, path: []const u8 };

    fn validateTarget(path: []const u8) !void {
        if (!std.mem.startsWith(u8, path, "./")) return error.InvalidExtensionPackageTarget;
        var parts = std.mem.splitAny(u8, path[2..], "/\\");
        while (parts.next()) |part| {
            if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..") or std.ascii.eqlIgnoreCase(part, "node_modules") or std.mem.indexOfAny(u8, part, "\x00?#") != null) return error.InvalidExtensionPackageTarget;
            // Encoded target paths need URL decoding before filesystem lookup;
            // never treat them as literal names or allow encoded traversal.
            if (std.mem.indexOfScalar(u8, part, '%') != null) return error.UnsupportedExtensionPackageEncoding;
        }
    }

    fn conditionalTarget(value: std.json.Value) anyerror!Target {
        switch (value) {
            .null => return .blocked,
            .string => {
                try validateTarget(value.string);
                return .{ .path = value.string };
            },
            .object => |fields| {
                var iterator = fields.iterator();
                while (iterator.next()) |entry| {
                    const key = entry.key_ptr.*;
                    var decimal = key.len > 0;
                    for (key) |byte| if (byte < '0' or byte > '9') {
                        decimal = false;
                    };
                    const index = if (decimal) std.fmt.parseInt(u32, key, 10) catch null else null;
                    if (index != null and index.? != std.math.maxInt(u32) and (key.len == 1 or key[0] != '0')) return error.InvalidExtensionPackageExports;
                    if (std.mem.eql(u8, key, "import") or std.mem.eql(u8, key, "node") or std.mem.eql(u8, key, "default")) {
                        const resolved = try conditionalTarget(entry.value_ptr.*);
                        if (resolved != .missing) return resolved;
                    }
                }
                return .missing;
            },
            .array => |items| {
                var last_error: ?anyerror = null;
                for (items.items) |item| {
                    const target = conditionalTarget(item) catch |err| {
                        if (err != error.InvalidExtensionPackageTarget) return err;
                        last_error = err;
                        continue;
                    };
                    if (target != .missing) return target;
                }
                if (last_error) |err| return err;
                return .blocked;
            },
            else => return error.InvalidExtensionPackageExports,
        }
    }

    fn exportedTarget(gpa: std.mem.Allocator, exports: std.json.Value, key: []const u8) ![]const u8 {
        var selected = exports;
        var capture: ?[]const u8 = null;
        if (exports == .object) {
            var subpaths = false;
            var conditions = false;
            var iterator = exports.object.iterator();
            while (iterator.next()) |entry| {
                if (std.mem.startsWith(u8, entry.key_ptr.*, ".")) subpaths = true else conditions = true;
            }
            if (subpaths and conditions) return error.InvalidExtensionPackageExports;
            if (subpaths) {
                if (exports.object.get(key)) |exact| {
                    selected = exact;
                } else {
                    var best: ?[]const u8 = null;
                    iterator = exports.object.iterator();
                    while (iterator.next()) |entry| {
                        const pattern = entry.key_ptr.*;
                        const star = std.mem.indexOfScalar(u8, pattern, '*') orelse continue;
                        if (std.mem.indexOfScalarPos(u8, pattern, star + 1, '*') != null) continue;
                        const trailer = pattern[star + 1 ..];
                        if (key.len < pattern.len or !std.mem.startsWith(u8, key, pattern[0..star]) or !std.mem.endsWith(u8, key, trailer)) continue;
                        if (best) |previous| {
                            const previous_star = std.mem.indexOfScalar(u8, previous, '*').?;
                            if (star < previous_star or (star == previous_star and pattern.len <= previous.len)) continue;
                        }
                        best = pattern;
                        selected = entry.value_ptr.*;
                        capture = key[star .. key.len - trailer.len];
                    }
                    if (best == null) return error.ExtensionSubpathNotExported;
                }
            } else if (!std.mem.eql(u8, key, ".")) return error.ExtensionSubpathNotExported;
        } else if (!std.mem.eql(u8, key, ".")) return error.ExtensionSubpathNotExported;
        const resolved = try conditionalTarget(selected);
        if (resolved != .path) return error.ExtensionSubpathNotExported;
        if (capture) |matched| {
            const replaced = try std.mem.replaceOwned(u8, gpa, resolved.path, "*", matched);
            try validateTarget(replaced);
            return replaced;
        }
        return resolved.path;
    }

    fn packageEntry(self: *Resolver, gpa: std.mem.Allocator, directory: []const u8, subpath: []const u8) ![]u8 {
        const package = try self.packageJson(gpa, directory) orelse {
            const path = try std.fs.path.join(gpa, &.{ directory, subpath });
            defer gpa.free(path);
            return self.local(gpa, path, true);
        };
        if (package.object.get("exports")) |exports| {
            const key = if (subpath.len == 0) try gpa.dupe(u8, ".") else try std.fmt.allocPrint(gpa, "./{s}", .{subpath});
            defer gpa.free(key);
            const target = try exportedTarget(gpa, exports, key);
            const path = try std.fs.path.resolve(gpa, &.{ directory, target });
            defer gpa.free(path);
            return try self.file(gpa, path) orelse error.ExtensionModuleNotFound;
        }
        if (subpath.len > 0) {
            const path = try std.fs.path.join(gpa, &.{ directory, subpath });
            defer gpa.free(path);
            return self.local(gpa, path, true);
        }
        return self.local(gpa, directory, true);
    }

    /// The caller uses a temporary arena, and owns the final canonical path.
    pub fn resolve(self: *Resolver, gpa: std.mem.Allocator, importer: []const u8, specifier: []const u8) ![]u8 {
        if (specifier.len == 0 or std.mem.indexOfScalar(u8, specifier, 0) != null) return error.InvalidExtensionModuleSpecifier;
        if (std.mem.indexOfAny(u8, specifier, "?#") != null) return error.UnsupportedExtensionModuleQuery;
        const directory = std.fs.path.dirname(importer) orelse ".";
        if (std.fs.path.isAbsolute(specifier) or std.mem.startsWith(u8, specifier, "./") or std.mem.startsWith(u8, specifier, "../")) {
            const path = try std.fs.path.resolve(gpa, &.{ directory, specifier });
            defer gpa.free(path);
            return self.local(gpa, path, true);
        }
        if (std.mem.indexOfScalar(u8, specifier, ':') != null or std.mem.indexOfScalar(u8, specifier, '\\') != null) return error.UnsupportedExtensionModuleSpecifier;
        var split = std.mem.indexOfScalar(u8, specifier, '/') orelse specifier.len;
        if (specifier[0] == '@') {
            if (split == specifier.len) return error.InvalidExtensionPackageName;
            split = std.mem.indexOfScalarPos(u8, specifier, split + 1, '/') orelse specifier.len;
        }
        const name = specifier[0..split];
        if (name.len == 0 or name[0] == '.' or std.mem.indexOfScalar(u8, name, '%') != null) return error.InvalidExtensionPackageName;
        if (std.mem.endsWith(u8, specifier, "/")) return error.InvalidExtensionPackageName;
        const subpath = if (split < specifier.len) specifier[split + 1 ..] else "";
        var parts = std.mem.splitScalar(u8, subpath, '/');
        while (parts.next()) |part| if (std.mem.eql(u8, part, "..") or std.mem.eql(u8, part, ".")) return error.InvalidExtensionPackageName;
        var ancestor = directory;
        while (true) {
            const package_dir = try std.fs.path.join(gpa, &.{ ancestor, "node_modules", name });
            defer gpa.free(package_dir);
            const stat = std.Io.Dir.cwd().statFile(self.io, package_dir, .{}) catch |err| switch (err) {
                error.FileNotFound, error.NotDir => null,
                else => return err,
            };
            if (stat != null and stat.?.kind == .directory) return self.packageEntry(gpa, package_dir, subpath);
            const parent = std.fs.path.dirname(ancestor) orelse break;
            if (std.mem.eql(u8, parent, ancestor)) break;
            ancestor = parent;
        }
        return error.ExtensionModuleNotFound;
    }
};

test "native extension resolver picks nearest package and resolves typed files and directory entries" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "workspace/node_modules/dep/lib");
    try tmp.dir.createDirPath(io, "node_modules/dep");
    try tmp.dir.createDirPath(io, "workspace/helpers");
    try tmp.dir.writeFile(io, .{ .sub_path = "workspace/extension.ts", .data = "export default () => {};" });
    try tmp.dir.writeFile(io, .{ .sub_path = "workspace/marker.ts", .data = "export const marker='typed';" });
    try tmp.dir.writeFile(io, .{ .sub_path = "workspace/helpers/index.js", .data = "export const marker='directory';" });
    try tmp.dir.writeFile(io, .{ .sub_path = "workspace/node_modules/dep/package.json", .data = "{\"type\":\"module\",\"exports\":{\".\":{\"require\":\"./wrong.cjs\",\"import\":\"./lib/index.js\"},\"./extra\":\"./lib/extra.js\",\"./blocked\":null,\"./escape\":\"./../secret.js\"}}" });
    try tmp.dir.writeFile(io, .{ .sub_path = "workspace/node_modules/dep/lib/index.js", .data = "export const marker='nearest';" });
    try tmp.dir.writeFile(io, .{ .sub_path = "workspace/node_modules/dep/lib/extra.js", .data = "export const marker='extra';" });
    try tmp.dir.writeFile(io, .{ .sub_path = "node_modules/dep/package.json", .data = "{\"main\":\"index.js\"}" });
    try tmp.dir.writeFile(io, .{ .sub_path = "node_modules/dep/index.js", .data = "export const marker='outer';" });
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const importer = try tmp.dir.realPathFileAlloc(io, "workspace/extension.ts", allocator);
    var resolver: Resolver = .{ .io = io };
    try std.testing.expect(std.mem.endsWith(u8, try resolver.resolve(allocator, importer, "./marker"), "/workspace/marker.ts"));
    try std.testing.expect(std.mem.endsWith(u8, try resolver.resolve(allocator, importer, "./helpers"), "/workspace/helpers/index.js"));
    try std.testing.expect(std.mem.endsWith(u8, try resolver.resolve(allocator, importer, "dep"), "/workspace/node_modules/dep/lib/index.js"));
    try std.testing.expect(std.mem.endsWith(u8, try resolver.resolve(allocator, importer, "dep/extra"), "/workspace/node_modules/dep/lib/extra.js"));
    try std.testing.expectError(error.ExtensionSubpathNotExported, resolver.resolve(allocator, importer, "dep/blocked"));
    try std.testing.expectError(error.InvalidExtensionPackageTarget, resolver.resolve(allocator, importer, "dep/escape"));
    try std.testing.expectError(error.InvalidExtensionPackageName, resolver.resolve(allocator, importer, "dep/../secret"));
    try std.testing.expectError(error.ExtensionModuleNotFound, resolver.resolve(allocator, importer, "absent-native-fixture"));
}

test "native package exports honor nested fallback null blocks and wildcard specificity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const nested = try std.json.parseFromSliceLeaky(std.json.Value, allocator, "{\"import\":{\"unknown-condition\":\"./unused.js\"},\"default\":\"./fallback.js\"}", .{});
    try std.testing.expectEqualStrings("./fallback.js", try Resolver.exportedTarget(allocator, nested, "."));
    const blocked = try std.json.parseFromSliceLeaky(std.json.Value, allocator, "{\"import\":null,\"default\":\"./fallback.js\"}", .{});
    try std.testing.expectError(error.ExtensionSubpathNotExported, Resolver.exportedTarget(allocator, blocked, "."));
    const patterns = try std.json.parseFromSliceLeaky(std.json.Value, allocator, "{\"./*\":\"./fallback/*.js\",\"./lib/*\":\"./general/*.js\",\"./lib/*.js\":\"./specific/*.js\",\"./lib/private/*\":null}", .{});
    try std.testing.expectEqualStrings("./specific/sample.js", try Resolver.exportedTarget(allocator, patterns, "./lib/sample.js"));
    try std.testing.expectError(error.ExtensionSubpathNotExported, Resolver.exportedTarget(allocator, patterns, "./lib/private/hidden.js"));
    try std.testing.expectError(error.InvalidExtensionPackageTarget, Resolver.exportedTarget(allocator, patterns, "./lib/../escape.js"));
    const fallback = try std.json.parseFromSliceLeaky(std.json.Value, allocator, "[\"invalid-relative.js\",\"./valid.js\"]", .{});
    try std.testing.expectEqualStrings("./valid.js", try Resolver.exportedTarget(allocator, fallback, "."));
    const mixed = try std.json.parseFromSliceLeaky(std.json.Value, allocator, "{\".\":\"./main.js\",\"import\":\"./other.js\"}", .{});
    try std.testing.expectError(error.InvalidExtensionPackageExports, Resolver.exportedTarget(allocator, mixed, "."));
}
