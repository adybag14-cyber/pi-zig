//! SDK cache paths and owned file operations; callers supply the complete env snapshot.
const std = @import("std");
pub const Fields = std.StringArrayHashMapUnmanaged([]u8);
pub fn home(env: *const std.process.Environ.Map) ![]const u8 {
    return env.get("HOME") orelse env.get("USERPROFILE") orelse return error.AwsHomeDirectoryMissing;
}
pub fn path(a: std.mem.Allocator, env: *const std.process.Environ.Map, kind: enum { sso, login }, id: []const u8) ![]u8 {
    const directory = if (kind == .login) if (env.get("AWS_LOGIN_CACHE_DIRECTORY")) |override| try a.dupe(u8, override) else try std.fs.path.join(a, &.{ try home(env), ".aws", "login", "cache" }) else try std.fs.path.join(a, &.{ try home(env), ".aws", "sso", "cache" });
    defer a.free(directory);
    var digest: [32]u8 = @splat(0);
    const length: usize = if (kind == .sso) 20 else 32;
    if (kind == .sso) std.crypto.hash.Sha1.hash(id, digest[0..20], .{}) else std.crypto.hash.sha2.Sha256.hash(id, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    const leaf = try std.fmt.allocPrint(a, "{s}.json", .{hex[0 .. length * 2]});
    defer a.free(leaf);
    return std.fs.path.join(a, &.{ directory, leaf });
}
pub fn read(a: std.mem.Allocator, io: std.Io, file: []const u8) !std.json.Parsed(std.json.Value) {
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, file, a, .limited(1024 * 1024));
    defer {
        @memset(raw, 0);
        a.free(raw);
    }
    return std.json.parseFromSlice(std.json.Value, a, raw, .{ .allocate = .alloc_always });
}
pub fn write(a: std.mem.Allocator, io: std.Io, file: []const u8, value: std.json.Value) !void {
    const raw = try std.json.Stringify.valueAlloc(a, value, .{ .whitespace = .indent_2 });
    defer {
        @memset(raw, 0);
        a.free(raw);
    }
    if (std.fs.path.dirname(file)) |directory| std.Io.Dir.cwd().createDirPath(io, directory) catch {};
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = file, .data = raw });
}
pub fn section(a: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, name: []const u8) !?Fields {
    const override = env.get("AWS_CONFIG_FILE");
    const config = if (override != null and override.?.len != 0) try a.dupe(u8, override.?) else try std.fs.path.join(a, &.{ try home(env), ".aws", "config" });
    defer a.free(config);
    const raw = std.Io.Dir.cwd().readFileAlloc(io, config, a, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return null,
        else => return err,
    };
    defer {
        @memset(raw, 0);
        a.free(raw);
    }
    var fields: Fields = .empty;
    errdefer deinitFields(a, &fields);
    var found = false;
    var active = false;
    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == ';' or line[0] == '#') continue;
        if (line[0] == '[') {
            const end = std.mem.indexOfScalar(u8, line, ']') orelse {
                active = false;
                continue;
            };
            active = std.mem.eql(u8, std.mem.trim(u8, line[1..end], " \t"), name);
            found = found or active;
            continue;
        }
        if (!active) continue;
        const equal = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..equal], " \t");
        const value = std.mem.trim(u8, line[equal + 1 ..], " \t");
        const owned_key = try a.dupe(u8, key);
        errdefer a.free(owned_key);
        const owned_value = try a.dupe(u8, value);
        errdefer a.free(owned_value);
        const entry = try fields.getOrPut(a, key);
        if (entry.found_existing) {
            a.free(owned_key);
            a.free(entry.value_ptr.*);
        } else entry.key_ptr.* = owned_key;
        entry.value_ptr.* = owned_value;
    }
    if (!found) {
        deinitFields(a, &fields);
        return null;
    }
    return fields;
}
pub fn deinitFields(a: std.mem.Allocator, fields: *Fields) void {
    for (fields.keys()) |key| a.free(key);
    for (fields.values()) |value| {
        @memset(value, 0);
        a.free(value);
    }
    fields.deinit(a);
}
pub fn iso(a: std.mem.Allocator, unix: i64) ![]u8 {
    if (unix < 0) return error.AwsInvalidExpiration;
    const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(unix) };
    const year_day = epoch.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day = epoch.getDaySeconds();
    return std.fmt.allocPrint(a, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.000Z", .{ year_day.year, month_day.month.numeric(), month_day.day_index + 1, day.getHoursIntoDay(), day.getMinutesIntoHour(), day.getSecondsIntoMinute() });
}
