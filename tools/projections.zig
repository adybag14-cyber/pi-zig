//! Commit-pinned upstream projections without executing upstream programs.
const std = @import("std");

fn git(gpa: std.mem.Allocator, io: std.Io, argv: []const []const u8, limit: usize) ![]u8 {
    const result = try std.process.run(gpa, io, .{
        .argv = argv,
        .stdout_limit = .limited(limit),
        .stderr_limit = .limited(8192),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(30), .clock = .real } },
    });
    defer gpa.free(result.stderr);
    errdefer gpa.free(result.stdout);
    if (result.term != .exited or result.term.exited != 0) return error.UpstreamGitFailed;
    return result.stdout;
}

pub fn validatePackage(gpa: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, bytes, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidUpstreamPackage;
    const name = parsed.value.object.get("name") orelse return error.InvalidUpstreamPackage;
    const version = parsed.value.object.get("version") orelse return error.InvalidUpstreamPackage;
    if (name != .string or version != .string or !std.mem.eql(u8, name.string, "@earendil-works/pi-coding-agent")) return error.InvalidUpstreamPackage;
    _ = std.SemanticVersion.parse(version.string) catch return error.InvalidUpstreamVersion;
    return gpa.dupe(u8, version.string);
}

pub fn changelog(gpa: std.mem.Allocator, io: std.Io, upstream_root: []const u8, expected_commit: []const u8) ![]u8 {
    if (expected_commit.len != 40) return error.InvalidUpstreamCommit;
    for (expected_commit) |byte| if (!std.ascii.isHex(byte)) return error.InvalidUpstreamCommit;
    const actual = try git(gpa, io, &.{ "git", "-C", upstream_root, "rev-parse", "HEAD" }, 256);
    defer gpa.free(actual);
    if (!std.ascii.eqlIgnoreCase(std.mem.trim(u8, actual, " \t\r\n"), expected_commit)) return error.UpstreamCheckoutMismatch;
    const package_ref = try std.fmt.allocPrint(gpa, "{s}:packages/coding-agent/package.json", .{expected_commit});
    defer gpa.free(package_ref);
    const package = try git(gpa, io, &.{ "git", "-C", upstream_root, "show", package_ref }, 1024 * 1024);
    defer gpa.free(package);
    const version = try validatePackage(gpa, package);
    defer gpa.free(version);
    const changelog_ref = try std.fmt.allocPrint(gpa, "{s}:packages/coding-agent/CHANGELOG.md", .{expected_commit});
    defer gpa.free(changelog_ref);
    const bytes = try git(gpa, io, &.{ "git", "-C", upstream_root, "show", changelog_ref }, 16 * 1024 * 1024);
    errdefer gpa.free(bytes);
    const heading = try std.fmt.allocPrint(gpa, "## [{s}]", .{version});
    defer gpa.free(heading);
    if (std.mem.indexOf(u8, bytes, heading) == null and std.mem.indexOf(u8, bytes, "## [Unreleased]") == null) return error.InvalidUpstreamChangelog;
    // Git show reads the immutable object, not potentially modified worktree files.
    return bytes;
}

test "upstream package projection accepts future major and prerelease versions" {
    const gpa = std.testing.allocator;
    for ([_][]const u8{ "1.0.1", "2.3.0", "3.0.0-dev.2+build.5" }) |version| {
        const bytes = try std.fmt.allocPrint(gpa, "{{\"name\":\"@earendil-works/pi-coding-agent\",\"version\":\"{s}\"}}", .{version});
        defer gpa.free(bytes);
        const projected = try validatePackage(gpa, bytes);
        defer gpa.free(projected);
        try std.testing.expectEqualStrings(version, projected);
    }
    try std.testing.expectError(error.InvalidUpstreamPackage, validatePackage(gpa, "{\"name\":\"other\",\"version\":\"1.0.0\"}"));
    try std.testing.expectError(error.InvalidUpstreamVersion, validatePackage(gpa, "{\"name\":\"@earendil-works/pi-coding-agent\",\"version\":\"latest\"}"));
}
