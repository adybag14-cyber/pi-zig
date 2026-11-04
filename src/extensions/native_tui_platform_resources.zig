//! Validate the real installed TUI origin without evaluating identity sources.
const std = @import("std");
const js = @import("native_js_values.zig");
const loader = @import("native_tui_platform_loader.zig");
pub const relative_root = "native-resources/pi-tui";
const IdentityFile = struct { name: []const u8, size: usize, digest: []const u8 };
const identity_files = [_]IdentityFile{
    .{ .name = "package.json", .size = 1593, .digest = "a6a82af81ed5b6069267eabfdcf047d0af8013695b0e64d72f3c9f44f8e8124e" },
    .{ .name = "dist/index.js", .size = 3130, .digest = "6068ae4207de753d9ec00dbe14aee199e6160d1dea0db9c8a92f65d08ffc6e80" },
    .{ .name = "dist/native-platform.js", .size = 1723, .digest = "bd3deaa60d547941511128f7bcf40083cff0130a836bd3baf168baee370ccdf2" },
    .{ .name = "dist/native-module-path.js", .size = 931, .digest = "3f7c149d50329f897f5c84326e3054a0d5df4c9444250a6839ebe1a4b19db056" },
};
fn matches(bytes: []const u8, expected: []const u8) bool {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    const digits = "0123456789abcdef";
    if (expected.len != 64) return false;
    for (hash, 0..) |byte, index| {
        if (digits[byte >> 4] != expected[index * 2] or digits[byte & 15] != expected[index * 2 + 1]) return false;
    }
    return true;
}
fn validatePackage(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidNativeTuiPackageOrigin;
    inline for (.{ .{ "name", "@earendil-works/pi-tui" }, .{ "version", "1.3.0" }, .{ "main", "dist/index.js" } }) |pair| {
        const value = parsed.value.object.get(pair[0]) orelse return error.InvalidNativeTuiPackageOrigin;
        if (value != .string or !std.mem.eql(u8, value.string, pair[1])) return error.InvalidNativeTuiPackageOrigin;
    }
}
/// Used by the actual startup assembler and by focused tests with actual files.
/// Prebuild admission is intentionally deferred to require(), so missing,
// wrong-host, changed, and cached native candidates keep their original order.
pub fn bindRoot(engine: *js.Engine, io: std.Io, root: []const u8) !void {
    if (!std.fs.path.isAbsolute(root)) return error.ActualTuiModuleIdentityRequired;
    var files: [identity_files.len]?[:0]u8 = @splat(null);
    defer for (files) |file| if (file) |path| engine.gpa.free(path);
    for (identity_files, 0..) |item, index| {
        const path = try std.fs.path.join(engine.gpa, &.{root, item.name});
        defer engine.gpa.free(path);
        const actual = try std.Io.Dir.cwd().realPathFileAlloc(io, path, engine.gpa);
        files[index] = actual;
        const bytes = try std.Io.Dir.cwd().readFileAlloc(io, actual, engine.gpa, .limited(item.size + 1));
        defer engine.gpa.free(bytes);
        if (bytes.len != item.size or !matches(bytes, item.digest)) return error.NativeTuiModuleIdentityChanged;
        if (index == 0) try validatePackage(engine.gpa, bytes);
    }
    return loader.bind(engine, .{
        .platform_filename = files[2].?,
        .candidates_filename = files[3].?,
        .package_entry = files[1].?,
    });
}
/// The path is derived from the actual native executable, not guest argv[0],
/// mutable process.execPath, a historical workspace, or a builtin alias.
pub fn bindInstalled(engine: *js.Engine, io: std.Io) !void {
    const executable = try std.process.executablePathAlloc(io, engine.gpa);
    defer engine.gpa.free(executable);
    const directory = std.fs.path.dirname(executable) orelse return error.ActualTuiModuleIdentityRequired;
    const root = try std.fs.path.join(engine.gpa, &.{directory, relative_root});
    defer engine.gpa.free(root);
    return bindRoot(engine, io, root);
}
