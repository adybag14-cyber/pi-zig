//! Release metadata must identify a completed native parity checkpoint.
const std = @import("std");

pub const Identity = struct {
    version: []const u8,
    upstream_version: []const u8,
    upstream_commit: []const u8,
};

fn text(object: std.json.ObjectMap, name: []const u8) ![]const u8 {
    const value = object.get(name) orelse return error.MissingReleaseMetadata;
    if (value != .string) return error.InvalidReleaseMetadata;
    return value.string;
}

pub fn validate(gpa: std.mem.Allocator, manifest_bytes: []const u8, catalog_bytes: []const u8, identity: Identity, tag: ?[]const u8) !void {
    var manifest = try std.json.parseFromSlice(std.json.Value, gpa, manifest_bytes, .{});
    defer manifest.deinit();
    var catalog = try std.json.parseFromSlice(std.json.Value, gpa, catalog_bytes, .{});
    defer catalog.deinit();
    if (manifest.value != .object or catalog.value != .object) return error.InvalidReleaseMetadata;
    const root = manifest.value.object;
    const schema = root.get("schema_version") orelse return error.MissingReleaseMetadata;
    if (schema != .integer or schema.integer != 2) return error.UnsupportedReleaseMetadataSchema;
    if (!std.mem.eql(u8, try text(root, "status"), "complete")) return error.IncompleteParityCheckpoint;
    const certified = root.get("parity_certified") orelse return error.MissingReleaseMetadata;
    if (certified != .bool or !certified.bool) return error.UncertifiedParityCheckpoint;
    if (!std.mem.eql(u8, try text(root, "release_version"), identity.version)) return error.ReleaseVersionMismatch;
    _ = try std.SemanticVersion.parse(identity.version);
    if (tag) |value| {
        if (!std.mem.startsWith(u8, value, "v") or !std.mem.eql(u8, value[1..], identity.version)) return error.ReleaseTagMismatch;
    }
    const generated = root.get("generated_catalog") orelse return error.MissingReleaseMetadata;
    if (generated != .object) return error.InvalidReleaseMetadata;
    if (!std.mem.eql(u8, try text(generated.object, "upstream_version"), identity.upstream_version) or
        !std.mem.eql(u8, try text(catalog.value.object, "upstreamVersion"), identity.upstream_version)) return error.UncertifiedUpstreamVersion;
    if (!std.mem.eql(u8, try text(generated.object, "upstream_commit"), identity.upstream_commit) or
        !std.mem.eql(u8, try text(catalog.value.object, "upstreamCommit"), identity.upstream_commit)) return error.UncertifiedUpstreamCommit;
    if (identity.upstream_commit.len != 40) return error.InvalidUpstreamCommit;
    for (identity.upstream_commit) |byte| if (!std.ascii.isHex(byte)) return error.InvalidUpstreamCommit;
    const digest = try text(catalog.value.object, "upstreamSourceArchiveSha256");
    if (digest.len != 64) return error.InvalidUpstreamSourceDigest;
    for (digest) |byte| if (!std.ascii.isHex(byte)) return error.InvalidUpstreamSourceDigest;
    if (!std.mem.eql(u8, try text(generated.object, "upstream_source_archive_sha256"), digest)) return error.UpstreamSourceDigestMismatch;
}

test "release metadata rejects incomplete unknown and inconsistent checkpoint contracts" {
    const identity: Identity = .{ .version = "1.1.0", .upstream_version = "1.0.2", .upstream_commit = "0123456789012345678901234567890123456789" };
    const catalog = "{\"upstreamVersion\":\"1.0.2\",\"upstreamCommit\":\"0123456789012345678901234567890123456789\",\"upstreamSourceArchiveSha256\":\"0123456789012345678901234567890123456789012345678901234567890123\"}";
    const complete = "{\"schema_version\":2,\"status\":\"complete\",\"parity_certified\":true,\"release_version\":\"1.1.0\",\"generated_catalog\":{\"upstream_version\":\"1.0.2\",\"upstream_commit\":\"0123456789012345678901234567890123456789\",\"upstream_source_archive_sha256\":\"0123456789012345678901234567890123456789012345678901234567890123\"}}";
    try validate(std.testing.allocator, complete, catalog, identity, "v1.1.0");
    try validate(std.testing.allocator, complete, catalog, identity, null);
    try std.testing.expectError(error.ReleaseTagMismatch, validate(std.testing.allocator, complete, catalog, identity, "v1.2.0"));
    try std.testing.expectError(error.ReleaseTagMismatch, validate(std.testing.allocator, complete, catalog, identity, "1.1.0"));
    try std.testing.expectError(error.MissingReleaseMetadata, validate(std.testing.allocator, "{}", catalog, identity, null));
    const replacements = [_]struct { old: []const u8, new: []const u8, err: anyerror }{
        .{ .old = "\"schema_version\":2", .new = "\"schema_version\":3", .err = error.UnsupportedReleaseMetadataSchema },
        .{ .old = "\"status\":\"complete\"", .new = "\"status\":\"in_progress\"", .err = error.IncompleteParityCheckpoint },
        .{ .old = "\"parity_certified\":true", .new = "\"parity_certified\":false", .err = error.UncertifiedParityCheckpoint },
        .{ .old = "\"release_version\":\"1.1.0\"", .new = "\"release_version\":\"1.2.0\"", .err = error.ReleaseVersionMismatch },
        .{ .old = "\"upstream_version\":\"1.0.2\"", .new = "\"upstream_version\":\"0.84.4\"", .err = error.UncertifiedUpstreamVersion },
        .{ .old = "\"upstream_commit\":\"0123456789012345678901234567890123456789\"", .new = "\"upstream_commit\":\"1123456789012345678901234567890123456789\"", .err = error.UncertifiedUpstreamCommit },
    };
    for (replacements) |replacement| {
        const changed = try std.mem.replaceOwned(u8, std.testing.allocator, complete, replacement.old, replacement.new);
        defer std.testing.allocator.free(changed);
        try std.testing.expectError(replacement.err, validate(std.testing.allocator, changed, catalog, identity, null));
    }
}
