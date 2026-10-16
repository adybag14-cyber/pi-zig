//! SHA512 lock pins plus a full initial cache manifest; mutable diffs stay visible.
const std = @import("std");
const files = @import("files.zig");
const manifest = @import("manifest.zig");
const Deadline = @import("deadline.zig").Deadline;
const Pin = struct {
    package: []const u8,
    integrity: []const u8,
    required_original_installed: bool,
    cache_relative: []const u8,
};
pub const Record = struct { package: []const u8, cache_relative: []const u8, expected: [64]u8, actual: [64]u8, exact: bool };
pub const Sink = struct {
    context: *anyopaque,
    write_fn: *const fn (*anyopaque, Record) anyerror!void,
};
pub fn windowsRelative(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    const result = try allocator.dupe(u8, value);
    errdefer allocator.free(result);
    for (result) |*byte| {
        if (byte.* == '/') byte.* = '\\';
    }
    try files.relative(result);
    return result;
}
pub fn checkPins(allocator: std.mem.Allocator, pins_path: []const u8, cache_root: []const u8,
    deadline: Deadline, sink: Sink) !void
{
    try files.contained(cache_root, files.container ++ "\\upstream\\runtime");
    const bytes = try files.readBounded(allocator, pins_path, 2 * 1024 * 1024);
    defer allocator.free(bytes);
    const parsed = try std.json.parseFromSlice([]Pin, allocator, bytes, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    if (parsed.value.len != 365) return error.Exact365CachePinsRequired;
    var required: usize = 0;
    var mismatched: usize = 0;
    for (parsed.value) |pin| {
        if (!pin.required_original_installed) continue;
        required += 1;
        try deadline.normal();
        if (!std.mem.startsWith(u8, pin.integrity, "sha512-")) return error.ExactSha512IntegrityRequired;
        const encoded = pin.integrity[7..];
        const decoder = std.base64.standard.Decoder;
        if (try decoder.calcSizeForSlice(encoded) != 64) return error.Sha512IntegrityLength;
        var expected: [64]u8 = undefined;
        try decoder.decode(&expected, encoded);
        const relative = try windowsRelative(allocator, pin.cache_relative);
        defer allocator.free(relative);
        const path = try files.join(allocator, cache_root, relative);
        defer allocator.free(path);
        const actual = try files.hash512(allocator, path);
        const exact = std.crypto.timing_safe.eql([64]u8, expected, actual);
        if (!exact) mismatched += 1;
        try sink.write_fn(sink.context, .{ .package = pin.package, .cache_relative = relative,
            .expected = expected, .actual = actual, .exact = exact });
    }
    if (required != 281 or mismatched != 0) return error.RequiredOriginalCachePinNegative;
}
pub fn checkInitial(allocator: std.mem.Allocator, baseline_jsonl: []const u8, cache_root: []const u8,
    deadline: Deadline, sink: manifest.Sink) !manifest.Report
{
    var baseline = try manifest.Manifest.loadJsonl(allocator, baseline_jsonl, 558);
    defer baseline.deinit();
    const report = try manifest.checkTree(allocator, cache_root, &baseline, deadline, sink);
    try report.requireExact(0);
    return report;
}
// Later mutable-cache snapshots must enumerate all actual files, retain every
// addition/removal/change, and rerun checkPins. They must not replace the frozen
// initial558 authority with the first arbitrary live snapshot observed.
