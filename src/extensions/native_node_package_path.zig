// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Native package-binding path work from Node24 src/path.cc/node_modules.cc.
//! These operations never dispatch through the mutable public node:path object.
const std = @import("std");
const builtin = @import("builtin");
pub const Flavor = enum { posix, win32 };
pub const native: Flavor = if (builtin.os.tag == .windows) .win32 else .posix;
fn separator(flavor: Flavor, byte: u8) bool { return byte == '/' or (flavor == .win32 and byte == '\\'); }
fn letter(byte: u8) bool { return std.ascii.isAlphabetic(byte); }
const Root = struct { end: usize = 0, device: []const u8 = "", absolute: bool = false };
fn windowsRoot(gpa: std.mem.Allocator, path: []const u8) !Root {
    if (path.len == 0) return .{};
    if (path.len == 1) return if (separator(.win32, path[0])) .{ .end = 1, .absolute = true } else .{};
    if (!separator(.win32, path[0])) {
        if (!letter(path[0]) or path[1] != ':') return .{};
        const absolute = path.len > 2 and separator(.win32, path[2]);
        return .{ .end = if (absolute) 3 else 2, .device = path[0..2], .absolute = absolute };
    }
    var result: Root = .{ .absolute = true };
    if (!separator(.win32, path[1])) return result;
    var index: usize = 2;
    const first_start = index;
    while (index < path.len and !separator(.win32, path[index])) : (index += 1) {}
    if (index == path.len or index == first_start) return result;
    const first = path[first_start..index];
    const slash_start = index;
    while (index < path.len and separator(.win32, path[index])) : (index += 1) {}
    if (index == path.len or index == slash_start) return result;
    const share_start = index;
    while (index < path.len and !separator(.win32, path[index])) : (index += 1) {}
    if (std.mem.eql(u8, first, ".") or std.mem.eql(u8, first, "?"))
        return .{ .end = 4, .device = try std.fmt.allocPrint(gpa, "\\\\{s}", .{first}), .absolute = true };
    result.end = index;
    result.device = try std.fmt.allocPrint(gpa, "\\\\{s}\\{s}", .{ first, path[share_start..index] });
    return result;
}
fn normalizedTail(gpa: std.mem.Allocator, pieces: []const []const u8, above_root: bool) ![]u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    defer parts.deinit(gpa);
    var index = pieces.len;
    while (index != 0) {
        index -= 1;
        var tokens = std.mem.splitAny(u8, pieces[index], "/\\");
        while (tokens.next()) |part| {
            if (part.len == 0 or std.mem.eql(u8, part, ".")) continue;
            if (std.mem.eql(u8, part, "..")) {
                if (parts.items.len > 0 and !std.mem.eql(u8, parts.items[parts.items.len - 1], "..")) _ = parts.pop()
                else if (above_root) try parts.append(gpa, part);
            } else try parts.append(gpa, part);
        }
    }
    return std.mem.join(gpa, "\\", parts.items);
}
/// Single-path PathResolve, the exact overload used by ToNamespacedPath.
/// directory and drive_directory are native process values, never guest getters.
pub fn resolveWindows(gpa: std.mem.Allocator, input: []const u8, directory: []const u8, drive_directory: ?[]const u8) ![]u8 {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const temporary = arena.allocator();
    var device: []const u8 = "";
    var absolute = false;
    var pieces: std.ArrayList([]const u8) = .empty;
    for (0..2) |pass| {
        var path = input;
        if (pass == 1) {
            path = directory;
            if (device.len != 0) {
                if (drive_directory) |saved| if (saved.len != 0) { path = saved; };
                const prefix = path[0..@min(path.len, 2)];
                if (path.len == 0 or (!std.ascii.eqlIgnoreCase(prefix, device) and path.len > 2 and path[2] == '/'))
                    path = try std.fmt.allocPrint(temporary, "{s}\\", .{device});
            }
        }
        const root = try windowsRoot(temporary, path);
        if (root.device.len != 0) {
            if (device.len != 0 and !std.ascii.eqlIgnoreCase(device, root.device)) continue;
            if (device.len == 0) device = root.device;
        }
        if (absolute) {
            if (device.len != 0) break;
        } else {
            try pieces.append(temporary, path[root.end..]);
            absolute = root.absolute;
            if (absolute and device.len != 0) break;
        }
    }
    const tail = try normalizedTail(temporary, pieces.items, !absolute);
    if (absolute) return std.fmt.allocPrint(gpa, "{s}\\{s}", .{ device, tail });
    if (device.len != 0 or tail.len != 0) return std.fmt.allocPrint(gpa, "{s}{s}", .{ device, tail });
    return gpa.dupe(u8, ".");
}
pub fn namespacedWithDirectory(gpa: std.mem.Allocator, input: []const u8, directory: []const u8, drive_directory: ?[]const u8, flavor: Flavor) ![]u8 {
    if (flavor == .posix or input.len == 0) return gpa.dupe(u8, input);
    const resolved = try resolveWindows(gpa, input, directory, drive_directory);
    defer gpa.free(resolved);
    if (resolved.len <= 2) return gpa.dupe(u8, input);
    if (std.mem.startsWith(u8, resolved, "\\\\") and resolved[2] != '?' and resolved[2] != '.')
        return std.fmt.allocPrint(gpa, "\\\\?\\UNC\\{s}", .{resolved[2..]});
    if (letter(resolved[0]) and resolved[1] == ':' and resolved[2] == '\\')
        return std.fmt.allocPrint(gpa, "\\\\?\\{s}", .{resolved});
    return gpa.dupe(u8, resolved);
}
const Windows = struct {
    extern "kernel32" fn GetCurrentDirectoryW(u32, ?[*]u16) callconv(.winapi) u32;
    extern "kernel32" fn GetModuleFileNameW(?*anyopaque, [*]u16, u32) callconv(.winapi) u32;
    extern "kernel32" fn GetEnvironmentVariableW([*:0]const u16, ?[*]u16, u32) callconv(.winapi) u32;
};
fn executableDirectoryWindows(gpa: std.mem.Allocator) ![]u8 {
    var length: u32 = 512;
    while (true) {
        const buffer = try gpa.alloc(u16, length);
        defer gpa.free(buffer);
        const count = Windows.GetModuleFileNameW(null, buffer.ptr, @intCast(buffer.len));
        if (count == 0) return error.NativePackageExecutablePathFailed;
        if (count < buffer.len) {
            // Environment::GetCwd uses exec_path.substr before its final native
            // separator, including the drive-root "C:" spelling.
            var end: usize = count;
            var cursor: usize = count;
            while (cursor != 0) {
                cursor -= 1;
                if (buffer[cursor] == '\\') { end = cursor; break; }
            }
            return std.unicode.wtf16LeToWtf8Alloc(gpa, buffer[0..end]);
        }
        length = try std.math.mul(u32, length, 2);
    }
}
fn currentDirectoryWindows(gpa: std.mem.Allocator) ![]u8 {
    var length = Windows.GetCurrentDirectoryW(0, null);
    if (length == 0) return executableDirectoryWindows(gpa);
    while (true) {
        const buffer = try gpa.alloc(u16, length);
        defer gpa.free(buffer);
        const count = Windows.GetCurrentDirectoryW(@intCast(buffer.len), buffer.ptr);
        if (count == 0) return executableDirectoryWindows(gpa);
        if (count < buffer.len) return std.unicode.wtf16LeToWtf8Alloc(gpa, buffer[0..count]);
        length = count + 1;
    }
}
fn driveDirectoryWindows(gpa: std.mem.Allocator, input: []const u8) !?[]u8 {
    if (input.len < 2 or !letter(input[0]) or input[1] != ':' or (input.len > 2 and separator(.win32, input[2]))) return null;
    const name = [_:0]u16{ '=', input[0], ':' };
    var length = Windows.GetEnvironmentVariableW(&name, null, 0);
    if (length == 0) return null;
    while (true) {
        const buffer = try gpa.alloc(u16, length);
        defer gpa.free(buffer);
        const count = Windows.GetEnvironmentVariableW(&name, buffer.ptr, @intCast(buffer.len));
        if (count == 0) return null;
        if (count < buffer.len) return try std.unicode.wtf16LeToWtf8Alloc(gpa, buffer[0..count]);
        length = count + 1;
    }
}
pub fn namespaced(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    if (builtin.os.tag != .windows or input.len == 0) return gpa.dupe(u8, input);
    const directory = try currentDirectoryWindows(gpa);
    defer gpa.free(directory);
    const drive = try driveDirectoryWindows(gpa, input);
    defer if (drive) |value| gpa.free(value);
    return namespacedWithDirectory(gpa, input, directory, drive, .win32);
}
/// std::filesystem root-name/root-directory decomposition. Namespace and UNC
/// roots keep their actual first component; no public dirname normalization.
fn rootEnd(path: []const u8, flavor: Flavor) usize {
    var end: usize = 0;
    if (flavor == .win32) {
        if (path.len >= 2 and letter(path[0]) and path[1] == ':') end = 2
        else if (path.len >= 4 and separator(flavor, path[0]) and separator(flavor, path[3]) and
            (path.len == 4 or !separator(flavor, path[4])) and
            ((separator(flavor, path[1]) and (path[2] == '?' or path[2] == '.')) or (path[1] == '?' and path[2] == '?'))) end = 3
        else if (path.len >= 3 and separator(flavor, path[0]) and separator(flavor, path[1]) and !separator(flavor, path[2])) {
            end = 3;
            while (end < path.len and !separator(flavor, path[end])) : (end += 1) {}
        }
    }
    while (end < path.len and separator(flavor, path[end])) : (end += 1) {}
    return end;
}
pub fn parent(path: []const u8, flavor: Flavor) []const u8 {
    const root = rootEnd(path, flavor);
    if (path.len <= root) return path;
    var end = path.len;
    if (separator(flavor, path[end - 1])) {
        while (end > root and separator(flavor, path[end - 1])) : (end -= 1) {}
        return path[0..end];
    }
    while (end > root and !separator(flavor, path[end - 1])) : (end -= 1) {}
    while (end > root and separator(flavor, path[end - 1])) : (end -= 1) {}
    return path[0..end];
}
pub fn filename(path: []const u8, flavor: Flavor) []const u8 {
    const root = rootEnd(path, flavor);
    var begin = path.len;
    while (begin > root and !separator(flavor, path[begin - 1])) : (begin -= 1) {}
    return path[begin..];
}
pub fn appendPackage(gpa: std.mem.Allocator, path: []const u8, flavor: Flavor) ![]u8 {
    const slash: []const u8 = if (flavor == .win32) "\\" else "/";
    return std.fmt.allocPrint(gpa, "{s}{s}package.json", .{ path, if (path.len == 0 or separator(flavor, path[path.len - 1])) "" else slash });
}
/// MSVC generic_wstring replaces backslashes and preserves every separator.
/// The POSIX generic spelling collapses redundant directory separators.
pub fn generic(gpa: std.mem.Allocator, path: []const u8, flavor: Flavor) ![]u8 {
    if (flavor == .win32) {
        const output = try gpa.dupe(u8, path);
        for (output) |*byte| if (byte.* == '\\') { byte.* = '/'; };
        return output;
    }
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(gpa);
    for (path) |byte| {
        if (byte != '/' or output.items.len == 0 or output.items[output.items.len - 1] != '/')
            try output.append(gpa, byte);
    }
    return output.toOwnedSlice(gpa);
}
