//! Archive-bound projection of upstream's published configuration schemas.
const std = @import("std");
const projections = @import("projections.zig");
pub const names = [_][]const u8{ "keybindings", "models", "settings", "theme" };
pub fn project(gpa: std.mem.Allocator, io: std.Io, archive: []const u8, expected_commit: []const u8, destination: []const u8, check: bool) !void {
    if (!std.mem.eql(u8, try projections.archiveCommit(archive), expected_commit)) return error.SourceArchiveCommitMismatch;
    const version = try projections.validateNamedPackage(gpa, try projections.archiveFile(archive, "packages/coding-agent/package.json"), "@earendil-works/pi-coding-agent");
    defer gpa.free(version);
    var contents: [names.len][]const u8 = undefined;
    for (names, 0..) |name, index| {
        const path = try std.fmt.allocPrint(gpa, "packages/coding-agent/schemas/{s}.schema.json", .{name});
        defer gpa.free(path);
        contents[index] = try projections.archiveFile(archive, path);
        const parsed = try std.json.parseFromSlice(std.json.Value, gpa, contents[index], .{});
        defer parsed.deinit();
        if (parsed.value != .object or parsed.value.object.get("$schema") == null or parsed.value.object.get("$id") == null or parsed.value.object.get("properties") == null) return error.InvalidPublishedConfigSchema;
    }
    if (!check) try std.Io.Dir.cwd().createDirPath(io, destination);
    for (names, contents) |name, bytes| {
        const path = try std.fmt.allocPrint(gpa, "{s}/{s}.schema.json", .{ destination, name });
        defer gpa.free(path);
        if (check) {
            const existing = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024));
            defer gpa.free(existing);
            if (!std.mem.eql(u8, existing, bytes)) return error.ConfigSchemaProjectionDrift;
        } else {
            const file = try std.Io.Dir.cwd().createFile(io, path, .{});
            defer file.close(io);
            try file.writePositionalAll(io, bytes, 0);
        }
    }
    var archive_digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(archive, &archive_digest, .{});
    var manifest: std.Io.Writer.Allocating = .init(gpa);
    defer manifest.deinit();
    try manifest.writer.writeAll("{\"upstreamCommit\":");
    try std.json.Stringify.value(expected_commit, .{}, &manifest.writer);
    try manifest.writer.print(",\"archiveSha256\":\"{s}\",\"schemas\":[", .{std.fmt.bytesToHex(archive_digest, .lower)});
    for (names, contents, 0..) |name, bytes, index| {
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
        if (index > 0) try manifest.writer.writeByte(',');
        try manifest.writer.print("{{\"name\":\"{s}.schema.json\",\"sha256\":\"{s}\"}}", .{ name, std.fmt.bytesToHex(digest, .lower) });
    }
    try manifest.writer.writeAll("]}\n");
    const manifest_path = try std.fmt.allocPrint(gpa, "{s}/SOURCE.json", .{destination});
    defer gpa.free(manifest_path);
    if (check) {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(io, manifest_path, gpa, .limited(1024 * 1024));
        defer gpa.free(bytes);
        if (!std.mem.eql(u8, bytes, manifest.written())) return error.ConfigSchemaManifestDrift;
    } else {
        const file = try std.Io.Dir.cwd().createFile(io, manifest_path, .{});
        defer file.close(io);
        try file.writePositionalAll(io, manifest.written(), 0);
    }
}
