//! Native resolution of extension files and user-installed ESM packages.
const std = @import("std");
const builtin = @import("builtin");
const file_urls = @import("file_urls.zig");

pub const Resolver = struct {
    io: std.Io,
    alias_depth: usize = 0,
    native_modules: ?*const std.StringHashMapUnmanaged(void) = null,
    require_mode: bool = false,

    pub fn preferExternal(specifier: []const u8) bool {
        return std.mem.eql(u8, specifier, "typebox") or std.mem.startsWith(u8, specifier, "typebox/") or std.mem.eql(u8, specifier, "@sinclair/typebox") or std.mem.startsWith(u8, specifier, "@sinclair/typebox/");
    }

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
            const extensions: []const []const u8 = if (self.require_mode) &.{ ".js", ".json", ".ts", ".cts", ".cjs" } else &.{ ".js", ".ts", ".mjs", ".mts", ".cts", ".cjs" };
            for (extensions) |extension| {
                const candidate = try std.fmt.allocPrint(gpa, "{s}{s}", .{ path, extension });
                defer gpa.free(candidate);
                if (try self.file(gpa, candidate)) |resolved| return resolved;
            }
        }
        if (allow_directory) {
            if (try self.packageJson(gpa, path)) |package| {
                const fields: []const []const u8 = if (self.require_mode) &.{"main"} else &.{ "module", "main" };
                for (fields) |field| if (package.object.get(field)) |entry| {
                    if (entry != .string) return error.InvalidExtensionPackage;
                    const candidate = try std.fs.path.resolve(gpa, &.{ path, entry.string });
                    defer gpa.free(candidate);
                    return self.local(gpa, candidate, false);
                };
            }
            const indices: []const []const u8 = if (self.require_mode) &.{ "index.js", "index.json", "index.ts" } else &.{ "index.js", "index.ts", "index.mjs", "index.mts" };
            for (indices) |index| {
                const candidate = try std.fs.path.join(gpa, &.{ path, index });
                defer gpa.free(candidate);
                if (try self.file(gpa, candidate)) |resolved| return resolved;
            }
        }
        return error.ExtensionModuleNotFound;
    }

    const Target = union(enum) { missing, blocked, path: []const u8 };

    fn validateTarget(gpa: std.mem.Allocator, path: []const u8) !void {
        if (!std.mem.startsWith(u8, path, "./")) return error.InvalidExtensionPackageTarget;
        if (std.mem.indexOfAny(u8, path, "\\?#\x00") != null) return error.InvalidExtensionPackageTarget;
        const decoded = file_urls.decodePath(gpa, path) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => return error.InvalidExtensionPackageTarget,
        };
        defer gpa.free(decoded);
        var parts = std.mem.splitScalar(u8, decoded[2..], '/');
        while (parts.next()) |part| {
            if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..") or std.ascii.eqlIgnoreCase(part, "node_modules")) return error.InvalidExtensionPackageTarget;
        }
    }

    fn conditionalTargetMode(gpa: std.mem.Allocator, value: std.json.Value, allow_external: bool, require_mode: bool) anyerror!Target {
        return conditionalTargetDepth(gpa, value, allow_external, require_mode, 0);
    }

    fn conditionalTargetDepth(gpa: std.mem.Allocator, value: std.json.Value, allow_external: bool, require_mode: bool, depth: usize) anyerror!Target {
        if (depth >= 32) return error.ExtensionPackageConditionDepth;
        switch (value) {
            .null => return .blocked,
            .string => {
                if (!allow_external or std.mem.startsWith(u8, value.string, "./")) {
                    try validateTarget(gpa, value.string);
                } else if (value.string.len == 0 or value.string[0] == '.' or value.string[0] == '/' or std.mem.indexOfAny(u8, value.string, "\\\x00") != null or (std.mem.indexOfScalar(u8, value.string, ':') != null and !std.mem.startsWith(u8, value.string, "node:"))) return error.InvalidExtensionPackageTarget;
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
                    if (std.mem.eql(u8, key, if (require_mode) "require" else "import") or std.mem.eql(u8, key, "node") or std.mem.eql(u8, key, "default")) {
                        const resolved = try conditionalTargetDepth(gpa, entry.value_ptr.*, allow_external, require_mode, depth + 1);
                        if (resolved != .missing) return resolved;
                    }
                }
                return .missing;
            },
            .array => |items| {
                var last_error: ?anyerror = null;
                for (items.items) |item| {
                    const target = conditionalTargetDepth(gpa, item, allow_external, require_mode, depth + 1) catch |err| {
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

    const Match = struct { value: std.json.Value, capture: ?[]const u8 = null };

    fn patternMatch(map: std.json.ObjectMap, key: []const u8) ?Match {
        if (std.mem.indexOfScalar(u8, key, '*') == null) {
            if (map.get(key)) |exact| return .{ .value = exact };
        }
        var best: ?[]const u8 = null;
        var match: ?Match = null;
        var iterator = map.iterator();
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
            match = .{ .value = entry.value_ptr.*, .capture = key[star .. key.len - trailer.len] };
        }
        return match;
    }

    fn exportedTarget(gpa: std.mem.Allocator, exports: std.json.Value, key: []const u8) ![]const u8 {
        return exportedTargetMode(gpa, exports, key, false);
    }

    fn exportedTargetMode(gpa: std.mem.Allocator, exports: std.json.Value, key: []const u8, require_mode: bool) ![]const u8 {
        var selected = exports;
        var capture: ?[]const u8 = null;
        if (exports == .object) {
            var subpaths = false;
            var conditions = false;
            var iterator = exports.object.iterator();
            while (iterator.next()) |entry| {
                if (std.mem.startsWith(u8, entry.key_ptr.*, ".")) {
                    if (!std.mem.eql(u8, entry.key_ptr.*, ".") and !std.mem.startsWith(u8, entry.key_ptr.*, "./")) return error.InvalidExtensionPackageExports;
                    subpaths = true;
                } else conditions = true;
            }
            if (subpaths and conditions) return error.InvalidExtensionPackageExports;
            if (subpaths) {
                const match = patternMatch(exports.object, key) orelse return error.ExtensionSubpathNotExported;
                selected = match.value;
                capture = match.capture;
            } else if (!std.mem.eql(u8, key, ".")) return error.ExtensionSubpathNotExported;
        } else if (!std.mem.eql(u8, key, ".")) return error.ExtensionSubpathNotExported;
        const resolved = try conditionalTargetMode(gpa, selected, false, require_mode);
        if (resolved != .path) return error.ExtensionSubpathNotExported;
        if (capture) |matched| {
            const replaced = try std.mem.replaceOwned(u8, gpa, resolved.path, "*", matched);
            try validateTarget(gpa, replaced);
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
            const target = try exportedTargetMode(gpa, exports, key, self.require_mode);
            const decoded = try file_urls.decodePath(gpa, target);
            defer gpa.free(decoded);
            const path = try std.fs.path.resolve(gpa, &.{ directory, decoded });
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

    fn importAlias(self: *Resolver, gpa: std.mem.Allocator, importer: []const u8, specifier: []const u8) anyerror![]u8 {
        if (specifier.len < 2 or specifier[1] == '/' or self.alias_depth >= 32) return error.InvalidExtensionImportAlias;
        self.alias_depth += 1;
        defer self.alias_depth -= 1;
        var directory = std.fs.path.dirname(importer) orelse ".";
        while (true) {
            if (try self.packageJson(gpa, directory)) |package| {
                const imports = package.object.get("imports") orelse return error.ExtensionImportAliasMissing;
                if (imports != .object) return error.InvalidExtensionPackageImports;
                for (imports.object.keys()) |key| if (key.len < 2 or key[0] != '#' or key[1] == '/') return error.InvalidExtensionPackageImports;
                const match = patternMatch(imports.object, specifier) orelse return error.ExtensionImportAliasMissing;
                var target = try conditionalTargetMode(gpa, match.value, true, self.require_mode);
                if (target != .path) return error.ExtensionImportAliasMissing;
                if (match.capture) |capture| {
                    target = .{ .path = try std.mem.replaceOwned(u8, gpa, target.path, "*", capture) };
                    if (std.mem.startsWith(u8, target.path, "./")) try validateTarget(gpa, target.path);
                }
                if (!std.mem.startsWith(u8, target.path, "./")) {
                    const base = try std.fs.path.join(gpa, &.{ directory, "package.json" });
                    defer gpa.free(base);
                    return self.resolve(gpa, base, target.path);
                }
                const decoded = try file_urls.decodePath(gpa, target.path);
                defer gpa.free(decoded);
                const path = try std.fs.path.resolve(gpa, &.{ directory, decoded });
                defer gpa.free(path);
                return try self.file(gpa, path) orelse error.ExtensionModuleNotFound;
            }
            if (std.mem.eql(u8, std.fs.path.basename(directory), "node_modules")) break;
            const parent = std.fs.path.dirname(directory) orelse break;
            if (std.mem.eql(u8, parent, directory)) break;
            directory = parent;
        }
        return error.ExtensionImportAliasMissing;
    }

    /// The caller uses a temporary arena, and owns the final canonical path.
    pub fn resolve(self: *Resolver, gpa: std.mem.Allocator, importer: []const u8, specifier: []const u8) ![]u8 {
        if (specifier.len == 0 or std.mem.indexOfScalar(u8, specifier, 0) != null) return error.InvalidExtensionModuleSpecifier;
        if (self.native_modules) |modules| if (modules.contains(specifier) and !preferExternal(specifier)) return gpa.dupe(u8, specifier);
        if (specifier[0] == '#') return self.importAlias(gpa, importer, specifier);
        if (std.ascii.startsWithIgnoreCase(specifier, "file:")) {
            if (self.require_mode) return error.UnsupportedNativeRequireUrl;
            const uri = try std.Uri.parse(specifier);
            if (uri.query != null or uri.fragment != null) return error.UnsupportedExtensionModuleQuery;
            const path = try file_urls.toPath(gpa, specifier, builtin.os.tag == .windows);
            defer gpa.free(path);
            return try self.file(gpa, path) orelse error.ExtensionModuleNotFound;
        }
        if (std.mem.indexOfAny(u8, specifier, "?#") != null) return error.UnsupportedExtensionModuleQuery;
        const directory = std.fs.path.dirname(importer) orelse ".";
        if (std.fs.path.isAbsolute(specifier) or std.mem.startsWith(u8, specifier, "./") or std.mem.startsWith(u8, specifier, "../")) {
            const decoded = if (self.require_mode) try gpa.dupe(u8, specifier) else try file_urls.decodePath(gpa, specifier);
            defer gpa.free(decoded);
            const path = try std.fs.path.resolve(gpa, &.{ directory, decoded });
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
        var scope = directory;
        while (true) {
            if (try self.packageJson(gpa, scope)) |package| {
                if (package.object.get("name")) |package_name| {
                    if (package_name == .string and std.mem.eql(u8, package_name.string, name) and package.object.contains("exports")) return self.packageEntry(gpa, scope, subpath);
                }
                break; // Only the nearest package scope defines self-reference.
            }
            if (std.mem.eql(u8, std.fs.path.basename(scope), "node_modules")) break;
            const parent = std.fs.path.dirname(scope) orelse break;
            if (std.mem.eql(u8, parent, scope)) break;
            scope = parent;
        }
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
        if (self.native_modules) |modules| if (modules.contains(specifier)) return gpa.dupe(u8, specifier);
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

test "native package imports and self references stay within the nearest package scope" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "project/lib");
    try tmp.dir.createDirPath(io, "project/node_modules/native-external");
    try tmp.dir.writeFile(io, .{ .sub_path = "project/node_modules/native-external/package.json", .data = "{\"exports\":\"./index.js\"}" });
    try tmp.dir.writeFile(io, .{ .sub_path = "project/node_modules/native-external/index.js", .data = "export const marker='external';" });
    try tmp.dir.writeFile(io, .{ .sub_path = "project/package.json", .data = "{\"name\":\"native-project\",\"exports\":{\"./shared\":\"./lib/shared.js\",\"./space\":\"./lib/a%20b.js\",\"./encoded-traversal\":\"./%2e%2e/secret.js\"},\"imports\":{\"#shared\":{\"import\":\"./lib/shared.js\"},\"#*\":\"./wrong/*.js\",\"#lib/*\":\"./lib/*.js\",\"#blocked\":null,\"#external\":\"native-external\",\"#fs\":\"node:fs\",\"#cycle-one\":\"#cycle-two\",\"#cycle-two\":\"#cycle-one\"}}" });
    try tmp.dir.writeFile(io, .{ .sub_path = "project/extension.mjs", .data = "export default()=>{};" });
    try tmp.dir.writeFile(io, .{ .sub_path = "project/lib/shared.js", .data = "export const marker='scoped';" });
    try tmp.dir.writeFile(io, .{ .sub_path = "project/lib/a b.js", .data = "export const marker='encoded-space';" });
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const importer = try tmp.dir.realPathFileAlloc(io, "project/extension.mjs", allocator);
    var resolver: Resolver = .{ .io = io };
    try std.testing.expectEqualStrings(try resolver.resolve(allocator, importer, "#shared"), try resolver.resolve(allocator, importer, "native-project/shared"));
    try std.testing.expectError(error.ExtensionImportAliasMissing, resolver.resolve(allocator, importer, "#blocked"));
    try std.testing.expectError(error.ExtensionSubpathNotExported, resolver.resolve(allocator, importer, "native-project/private"));
    try std.testing.expectError(error.InvalidExtensionImportAlias, resolver.resolve(allocator, importer, "#"));
    try std.testing.expect(std.mem.endsWith(u8, try resolver.resolve(allocator, importer, "#external"), "/native-external/index.js"));
    try std.testing.expectError(error.InvalidExtensionImportAlias, resolver.resolve(allocator, importer, "#cycle-one"));
    try std.testing.expectEqualStrings(try resolver.resolve(allocator, importer, "#shared"), try resolver.resolve(allocator, importer, "#lib/shared"));
    const encoded = try resolver.resolve(allocator, importer, "native-project/space");
    try std.testing.expect(std.mem.endsWith(u8, encoded, "/lib/a b.js"));
    const url = try file_urls.fromPath(allocator, encoded, builtin.os.tag == .windows);
    try std.testing.expectEqualStrings(encoded, try resolver.resolve(allocator, importer, url));
    try std.testing.expectEqualStrings(encoded, try resolver.resolve(allocator, importer, "./lib/a%20b.js"));
    try std.testing.expectError(error.InvalidExtensionPackageTarget, resolver.resolve(allocator, importer, "native-project/encoded-traversal"));
    var modules: std.StringHashMapUnmanaged(void) = .empty;
    defer modules.deinit(allocator);
    try modules.put(allocator, "node:fs", {});
    resolver.native_modules = &modules;
    try std.testing.expectEqualStrings("node:fs", try resolver.resolve(allocator, importer, "#fs"));
    try modules.put(allocator, "typebox", {});
    try std.testing.expectEqualStrings("typebox", try resolver.resolve(allocator, importer, "typebox"));
    try tmp.dir.createDirPath(io, "project/node_modules/typebox");
    try tmp.dir.writeFile(io, .{ .sub_path = "project/node_modules/typebox/package.json", .data = "{\"type\":\"module\",\"exports\":{\"import\":\"./module.js\",\"require\":\"./common.cjs\"}}" });
    try tmp.dir.writeFile(io, .{ .sub_path = "project/node_modules/typebox/module.js", .data = "export const native='external';" });
    try tmp.dir.writeFile(io, .{ .sub_path = "project/node_modules/typebox/common.cjs", .data = "exports.native='external';" });
    try std.testing.expect(std.mem.endsWith(u8, try resolver.resolve(allocator, importer, "typebox"), "/typebox/module.js"));
    resolver.require_mode = true;
    try std.testing.expect(std.mem.endsWith(u8, try resolver.resolve(allocator, importer, "typebox"), "/typebox/common.cjs"));
    resolver.require_mode = false;
    try tmp.dir.createDirPath(io, "project/subscope");
    try tmp.dir.writeFile(io, .{ .sub_path = "project/subscope/package.json", .data = "{}" });
    try tmp.dir.writeFile(io, .{ .sub_path = "project/subscope/extension.js", .data = "export default()=>{};" });
    const nested = try tmp.dir.realPathFileAlloc(io, "project/subscope/extension.js", allocator);
    try std.testing.expectError(error.ExtensionImportAliasMissing, resolver.resolve(allocator, nested, "#shared"));
    try std.testing.expectError(error.ExtensionModuleNotFound, resolver.resolve(allocator, nested, "native-project/shared"));
}

test "native package conditions have a finite recursion budget" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var target: std.json.Value = .{ .string = "./valid.js" };
    for (0..40) |_| {
        var object: std.json.ObjectMap = .empty;
        try object.put(allocator, "import", target);
        target = .{ .object = object };
    }
    try std.testing.expectError(error.ExtensionPackageConditionDepth, Resolver.exportedTarget(allocator, target, "."));
}
