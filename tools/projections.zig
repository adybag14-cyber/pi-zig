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
    return validateNamedPackage(gpa, bytes, "@earendil-works/pi-coding-agent");
}

pub fn validateNamedPackage(gpa: std.mem.Allocator, bytes: []const u8, expected_name: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, bytes, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidUpstreamPackage;
    const name = parsed.value.object.get("name") orelse return error.InvalidUpstreamPackage;
    const version = parsed.value.object.get("version") orelse return error.InvalidUpstreamPackage;
    if (name != .string or version != .string or !std.mem.eql(u8, name.string, expected_name)) return error.InvalidUpstreamPackage;
    _ = std.SemanticVersion.parse(version.string) catch return error.InvalidUpstreamVersion;
    return gpa.dupe(u8, version.string);
}

fn tarSize(header: []const u8) !usize {
    if (header.len != 512) return error.InvalidSourceArchive;
    return std.fmt.parseInt(usize, std.mem.trim(u8, header[124..136], "\x00 "), 8) catch return error.UnsupportedSourceArchive;
}

/// Git's uncompressed tar carries its immutable commit in the global PAX
/// comment. Other archive formats fail explicitly instead of being mislabeled.
pub fn archiveCommit(bytes: []const u8) ![]const u8 {
    if (bytes.len < 1024 or bytes[156] != 'g') return error.UnsupportedSourceArchive;
    const size = try tarSize(bytes[0..512]);
    if (size > bytes.len - 512) return error.InvalidSourceArchive;
    const payload = bytes[512 .. 512 + size];
    var offset: usize = 0;
    var commit: ?[]const u8 = null;
    while (offset < payload.len) {
        const separator = std.mem.indexOfScalarPos(u8, payload, offset, ' ') orelse return error.InvalidSourceArchive;
        const length = std.fmt.parseInt(usize, payload[offset..separator], 10) catch return error.InvalidSourceArchive;
        if (length <= separator - offset + 1 or length > payload.len - offset) return error.InvalidSourceArchive;
        const end = offset + length;
        if (payload[end - 1] != '\n') return error.InvalidSourceArchive;
        const record = payload[separator + 1 .. end - 1];
        if (std.mem.startsWith(u8, record, "comment=")) {
            if (commit != null or record.len != 48) return error.InvalidSourceArchive;
            for (record[8..]) |byte| if (!std.ascii.isHex(byte)) return error.InvalidSourceArchive;
            commit = record[8..];
        }
        offset = end;
    }
    return commit orelse error.MissingSourceArchiveCommit;
}

pub fn archiveFile(bytes: []const u8, requested_path: []const u8) ![]const u8 {
    var offset: usize = 0;
    while (offset <= bytes.len and bytes.len - offset >= 512) {
        const header = bytes[offset .. offset + 512];
        if (header[0] == 0) return error.SourceArchiveFileMissing;
        const size = try tarSize(header);
        const begin = offset + 512;
        if (size > bytes.len - begin) return error.InvalidSourceArchive;
        const name = std.mem.trimEnd(u8, header[0..100], "\x00");
        const prefix = std.mem.trimEnd(u8, header[345..500], "\x00");
        if (prefix.len == 0 and std.mem.eql(u8, name, requested_path)) {
            if (header[156] != '0' and header[156] != 0) return error.InvalidSourceArchive;
            return bytes[begin .. begin + size];
        }
        const padded = std.math.add(usize, size, 511) catch return error.InvalidSourceArchive;
        const advance = std.math.mul(usize, padded / 512, 512) catch return error.InvalidSourceArchive;
        offset = std.math.add(usize, begin, advance) catch return error.InvalidSourceArchive;
    }
    return error.SourceArchiveFileMissing;
}

test "source archive provenance rejects unsupported containers and malformed PAX records" {
    try std.testing.expectError(error.UnsupportedSourceArchive, archiveCommit("not a Git tar"));
    var bytes = [_]u8{0} ** 1024;
    bytes[156] = 'g';
    @memcpy(bytes[124..135], "00000000064");
    @memcpy(bytes[512..564], "52 comment=83692682f095528f8b71652ddacff7075e36e893\n");
    try std.testing.expectEqualStrings("83692682f095528f8b71652ddacff7075e36e893", try archiveCommit(&bytes));
    bytes[512] = '0';
    try std.testing.expectError(error.InvalidSourceArchive, archiveCommit(&bytes));
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
