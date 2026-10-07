//! Node path rules selected by the remote handshake, independent of host OS.
const std = @import("std");
const urls = @import("../extensions/file_urls.zig");
pub const Platform = enum { posix, windows };
pub const Info = struct { platform: Platform, home: []const u8, cwd: []const u8, ambient_cwd: []const u8 = "", drive_cwds: std.json.Value = .{ .object = .empty } };
fn separator(platform: Platform, byte: u8) bool {
    return byte == '/' or (platform == .windows and byte == '\\');
}
const Root = struct { length: usize = 0, device: []const u8 = "", absolute: bool = false };
fn root(platform: Platform, path: []const u8) Root {
    if (path.len == 0) return .{};
    if (platform == .posix) return .{ .length = if (path[0] == '/') 1 else 0, .absolute = path[0] == '/' };
    if (path.len >= 2 and std.ascii.isAlphabetic(path[0]) and path[1] == ':') return .{ .device = path[0..2], .length = if (path.len > 2 and separator(platform, path[2])) 3 else 2, .absolute = path.len > 2 and separator(platform, path[2]) };
    if (!separator(platform, path[0])) return .{};
    if (path.len >= 2 and separator(platform, path[1])) {
        var end: usize = 2;
        const server = end;
        while (end < path.len and !separator(platform, path[end])) : (end += 1) {}
        if (end > server and end < path.len) {
            while (end < path.len and separator(platform, path[end])) : (end += 1) {}
            const share = end;
            while (end < path.len and !separator(platform, path[end])) : (end += 1) {}
            if (end > share) return .{ .length = end, .device = path[0..end], .absolute = true };
        }
    }
    return .{ .length = 1, .absolute = true };
}
fn normalized(gpa: std.mem.Allocator, platform: Platform, device: []const u8, absolute: bool, tail: []const u8, trailing: bool) ![]u8 {
    var components: std.ArrayList([]const u8) = .empty;
    defer components.deinit(gpa);
    var iterator = std.mem.tokenizeAny(u8, tail, if (platform == .windows) "/\\" else "/");
    while (iterator.next()) |part| {
        if (std.mem.eql(u8, part, ".")) continue;
        if (std.mem.eql(u8, part, "..")) {
            if (components.items.len > 0 and !std.mem.eql(u8, components.items[components.items.len - 1], "..")) {
                _ = components.pop();
                continue;
            }
            if (absolute) continue;
        }
        try components.append(gpa, part);
    }
    const sep: u8 = if (platform == .windows) '\\' else '/';
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    for (device) |byte| try out.append(gpa, if (separator(platform, byte)) sep else byte);
    if (absolute) try out.append(gpa, sep);
    for (components.items, 0..) |part, index| {
        if (index != 0) try out.append(gpa, sep);
        try out.appendSlice(gpa, part);
    }
    if (out.items.len == 0 or (!absolute and components.items.len == 0)) try out.append(gpa, '.');
    if (trailing and out.items[out.items.len - 1] != sep) try out.append(gpa, sep);
    return out.toOwnedSlice(gpa);
}
pub fn join(gpa: std.mem.Allocator, platform: Platform, parts: []const []const u8) ![]u8 {
    var joined: std.ArrayList(u8) = .empty;
    defer joined.deinit(gpa);
    for (parts) |part| {
        if (part.len == 0) continue;
        if (joined.items.len != 0) try joined.append(gpa, if (platform == .windows) '\\' else '/');
        try joined.appendSlice(gpa, part);
    }
    // win32.join treats a UNC root only when the first nonempty part starts
    // with exactly two separators followed by a server name.
    if (platform == .windows and joined.items.len > 1 and separator(platform, joined.items[0]) and separator(platform, joined.items[1])) {
        const first = blk: {
            for (parts) |part| if (part.len != 0) break :blk part;
            break :blk "";
        };
        if (first.len < 3 or !separator(platform, first[0]) or !separator(platform, first[1]) or separator(platform, first[2])) {
            var skip: usize = 1;
            while (skip < joined.items.len and separator(platform, joined.items[skip])) : (skip += 1) {}
            std.mem.copyForwards(u8, joined.items[1..], joined.items[skip..]);
            joined.items.len -= skip - 1;
        }
    }
    const parsed = root(platform, joined.items);
    return normalized(gpa, platform, parsed.device, parsed.absolute, joined.items[parsed.length..], joined.items.len > 0 and separator(platform, joined.items[joined.items.len - 1]));
}
pub fn resolve(gpa: std.mem.Allocator, info: Info, cwd: []const u8, input: []const u8) ![]u8 {
    var transformed: ?[]u8 = null;
    defer if (transformed) |value| gpa.free(value);
    if (std.mem.eql(u8, input, "~")) transformed = try gpa.dupe(u8, info.home) else if (std.mem.startsWith(u8, input, "~/") or (info.platform == .windows and std.mem.startsWith(u8, input, "~\\"))) transformed = try join(gpa, info.platform, &.{ info.home, input[2..] }) else if (std.mem.startsWith(u8, input, "file://")) transformed = urls.toPath(gpa, input, info.platform == .windows) catch |err| if (err == error.OutOfMemory) return err else null;
    const path = transformed orelse input;
    const parsed = root(info.platform, path);
    if (parsed.absolute and parsed.device.len != 0 or (info.platform == .posix and parsed.absolute)) return normalized(gpa, info.platform, parsed.device, true, path[parsed.length..], false);
    // Upstream calls win32.resolve(input) without a base for rooted absolute
    // paths. This uses the caller's process cwd, despite the remote-path docs.
    var base = if (parsed.absolute) info.ambient_cwd else cwd;
    var drive_root: [3]u8 = undefined;
    if (parsed.device.len == 2 and !std.ascii.eqlIgnoreCase(parsed.device, root(info.platform, cwd).device)) {
        var key = [_]u8{ std.ascii.toUpper(parsed.device[0]), ':' };
        base = if (info.drive_cwds == .object) if (info.drive_cwds.object.get(&key)) |value| if (value == .string) value.string else info.cwd else info.cwd else info.cwd;
        if (!std.ascii.eqlIgnoreCase(root(info.platform, base).device, parsed.device)) {
            drive_root = .{ parsed.device[0], ':', '\\' };
            base = &drive_root;
        }
    }
    const base_root = root(info.platform, base);
    const device = if (parsed.device.len != 0) parsed.device else base_root.device;
    if (parsed.absolute) return normalized(gpa, info.platform, device, true, path[parsed.length..], false);
    const tail = try std.fmt.allocPrint(gpa, "{s}{c}{s}", .{ base[base_root.length..], if (info.platform == .windows) @as(u8, '\\') else @as(u8, '/'), path[parsed.length..] });
    defer gpa.free(tail);
    return normalized(gpa, info.platform, device, base_root.absolute, tail, false);
}
pub fn basename(platform: Platform, path: []const u8) []const u8 {
    var end = path.len;
    while (end > 0 and separator(platform, path[end - 1])) : (end -= 1) {}
    var start = end;
    while (start > 0 and !separator(platform, path[start - 1])) : (start -= 1) {}
    if (platform == .windows and start == 0 and end >= 2 and path[1] == ':') start = 2;
    return path[start..end];
}
test "remote paths match actual latest upstream RemoteExecutionEnv across host-independent platforms" {
    const gpa = std.testing.allocator;
    const capture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/remote-path-7fb59f9.json"), .{});
    defer capture.deinit();
    for (capture.value.object.get("fixtures").?.array.items) |fixture| {
        const value = fixture.object.get("info").?;
        const info: Info = .{ .platform = if (std.mem.eql(u8, value.object.get("os").?.string, "windows")) .windows else .posix, .home = value.object.get("home").?.string, .cwd = value.object.get("cwd").?.string, .ambient_cwd = fixture.object.get("ambientCwd").?.string, .drive_cwds = value.object.get("driveCwds").? };
        var parts: std.ArrayList([]const u8) = .empty;
        defer parts.deinit(gpa);
        const is_resolve = std.mem.eql(u8, fixture.object.get("kind").?.string, "resolve");
        if (!is_resolve) for (fixture.object.get("parts").?.array.items) |part| try parts.append(gpa, part.string);
        const actual = if (is_resolve) try resolve(gpa, info, fixture.object.get("cwd").?.string, fixture.object.get("input").?.string) else try join(gpa, info.platform, parts.items);
        defer gpa.free(actual);
        try std.testing.expectEqualStrings(fixture.object.get("result").?.string, actual);
    }
}
