//! Platform handshake metadata derived from the validated catalog pin.
const std = @import("std");
pub const version = @import("../ai/catalog_generated.zig").upstream_version;
fn addDrive(gpa: std.mem.Allocator, object: *std.json.ObjectMap, name: []const u8, value: []const u8) !void {
    if (name.len != 3 or name[0] != '=' or !std.ascii.isAlphabetic(name[1]) or name[2] != ':') return;
    const key = try gpa.dupe(u8, name[1..]);
    errdefer gpa.free(key);
    key[0] = std.ascii.toUpper(key[0]);
    const destination = try object.getOrPut(gpa, key);
    if (destination.found_existing) gpa.free(key) else destination.key_ptr.* = key;
    destination.value_ptr.* = .{ .string = value };
}
pub fn driveCwds(gpa: std.mem.Allocator, environ: *const std.process.Environ.Map, windows: bool) !std.json.Value {
    var object: std.json.ObjectMap = .empty;
    errdefer {
        for (object.keys()) |key| gpa.free(key);
        object.deinit(gpa);
    }
    if (windows) {
        var iterator = environ.iterator();
        while (iterator.next()) |entry| {
            // The environment stays owned by the daemon for every hello reply.
            try addDrive(gpa, &object, entry.key_ptr.*, entry.value_ptr.*);
        }
    }
    return .{ .object = object };
}
pub fn deinitDriveCwds(gpa: std.mem.Allocator, value: *std.json.Value) void {
    for (value.object.keys()) |key| gpa.free(key);
    value.object.deinit(gpa);
}
test "handshake drive paths retain Unicode and canonical uppercase drive keys only on Windows" {
    const gpa = std.testing.allocator;
    var environ: std.process.Environ.Map = .init(gpa);
    defer environ.deinit();
    try environ.put("PATH", "irrelevant");
    // POSIX environment keys cannot contain '='; exercise Windows records as
    // native raw metadata without changing the actual process environment.
    var windows: std.json.Value = .{ .object = .empty };
    defer deinitDriveCwds(gpa, &windows);
    try addDrive(gpa, &windows.object, "=c:", "C:\\owned Ω🦊");
    try addDrive(gpa, &windows.object, "PATH", "irrelevant");
    try addDrive(gpa, &windows.object, "=not-a-drive", "ignored");
    try std.testing.expectEqual(@as(u32, 1), windows.object.count());
    try std.testing.expectEqualStrings("C:\\owned Ω🦊", windows.object.get("C:").?.string);
    var posix = try driveCwds(gpa, &environ, false);
    defer deinitDriveCwds(gpa, &posix);
    try std.testing.expectEqual(@as(u32, 0), posix.object.count());
    try std.testing.expect(version.len != 0);
}
