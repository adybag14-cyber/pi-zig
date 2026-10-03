//! Native tracked-source inventory. Generation never certifies feature parity.
const std = @import("std");
const excluded = [_][]const u8{ ".git", ".zig-cache", "zig-out", "node_modules", "__pycache__" };

pub fn includePath(path: []const u8) !bool {
    if (path.len == 0 or std.fs.path.isAbsolute(path) or std.mem.indexOfAny(u8, path, "\r\n\\") != null) return error.InvalidInventoryPath;
    if (std.mem.eql(u8, path, "FILES.sha256")) return false;
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (std.mem.eql(u8, part, "..") or std.mem.eql(u8, part, ".") or part.len == 0) return error.InvalidInventoryPath;
        for (excluded) |name| if (std.mem.eql(u8, part, name)) return false;
    }
    return true;
}

fn less(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

const Inventory = struct { paths: std.ArrayList([]const u8) = .empty };

fn inventory(gpa: std.mem.Allocator, io: std.Io) !Inventory {
    const result = try std.process.run(gpa, io, .{
        .argv = &.{ "git", "ls-files", "--cached", "--others", "--exclude-standard", "-z" },
        .stdout_limit = .limited(16 * 1024 * 1024),
        .stderr_limit = .limited(8192),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(30), .clock = .real } },
    });
    // This function uses the caller's arena; all path slices stay owned by it.
    if (result.term != .exited or result.term.exited != 0) return error.InventoryGitFailed;
    var output: Inventory = .{};
    var paths = std.mem.tokenizeScalar(u8, result.stdout, 0);
    while (paths.next()) |path| {
        if (!try includePath(path)) continue;
        const stat = std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch |err| switch (err) {
            error.FileNotFound => continue, // Deleted files are still in the index until staged.
            else => return err,
        };
        if (stat.kind == .sym_link) return error.UnsupportedInventorySymlink;
        if (stat.kind != .file) continue;
        try output.paths.append(gpa, path);
    }
    var found = false;
    for (output.paths.items) |path| if (std.mem.eql(u8, path, "ARTIFACT-MANIFEST.json")) {
        found = true;
        break;
    };
    if (!found) try output.paths.append(gpa, "ARTIFACT-MANIFEST.json");
    std.mem.sort([]const u8, output.paths.items, {}, less);
    var length: usize = 0;
    for (output.paths.items) |path| {
        if (length > 0 and std.mem.eql(u8, output.paths.items[length - 1], path)) continue;
        output.paths.items[length] = path;
        length += 1;
    }
    output.paths.items.len = length;
    return output;
}

const Digest = struct { hex: [64]u8, bytes: u64, lines: usize };

fn digestFile(io: std.Io, path: []const u8) !Digest {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    const before = try file.stat(io);
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    var bytes: u64 = 0;
    var lines: usize = 0;
    var last: ?u8 = null;
    var buffer: [64 * 1024]u8 = undefined;
    while (true) {
        const size = file.readStreaming(io, &.{&buffer}) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (size == 0) continue;
        hash.update(buffer[0..size]);
        bytes += size;
        lines += std.mem.count(u8, buffer[0..size], "\n");
        last = buffer[size - 1];
    }
    if (last != null and last.? != '\n') lines += 1;
    const after = try file.stat(io);
    if (bytes != before.size or before.size != after.size or !std.meta.eql(before.mtime, after.mtime)) return error.InventoryFileChanged;
    var hash_bytes: [32]u8 = undefined;
    hash.final(&hash_bytes);
    return .{ .hex = std.fmt.bytesToHex(hash_bytes, .lower), .bytes = bytes, .lines = lines };
}

fn readJson(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !std.json.Value {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(16 * 1024 * 1024));
    return std.json.parseFromSliceLeaky(std.json.Value, gpa, bytes, .{ .allocate = .alloc_always });
}

fn writeFile(io: std.Io, path: []const u8, bytes: []const u8) !void {
    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    try file.writePositionalAll(io, bytes, 0);
}

pub fn generate(gpa: std.mem.Allocator, io: std.Io, checkpoint: u32, writer: *std.Io.Writer) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    const files = try inventory(allocator, io);
    const package_bytes = try std.Io.Dir.cwd().readFileAlloc(io, "build.zig.zon", allocator, .limited(1024 * 1024));
    const package = try std.zon.parse.fromSliceAlloc(struct { version: []const u8 }, allocator, try allocator.dupeZ(u8, package_bytes), null, .{ .ignore_unknown_fields = true });
    _ = try std.SemanticVersion.parse(package.version);
    const catalog = try readJson(allocator, io, "src/ai/catalog_source.json");
    if (catalog != .object) return error.InvalidCatalogManifest;
    const initial_digests = try allocator.alloc(Digest, files.paths.items.len);
    var total_bytes: u64 = 0;
    var zig_files: usize = 0;
    var zig_lines: usize = 0;
    for (files.paths.items, 0..) |path, index| {
        if (std.mem.eql(u8, path, "ARTIFACT-MANIFEST.json")) continue;
        const digest = try digestFile(io, path);
        initial_digests[index] = digest;
        total_bytes += digest.bytes;
        if (std.mem.startsWith(u8, path, "src/") and std.mem.endsWith(u8, path, ".zig")) {
            zig_files += 1;
            zig_lines += digest.lines;
        }
    }
    var projection: std.json.ObjectMap = .empty;
    for ([_][2][]const u8{
        .{ "models", "modelCount" },                                          .{ "providers", "providerCount" },          .{ "upstream_commit", "upstreamCommit" }, .{ "upstream_version", "upstreamVersion" },
        .{ "upstream_source_archive_sha256", "upstreamSourceArchiveSha256" }, .{ "catalog_revision", "catalogRevision" }, .{ "catalog_sha256", "catalogSha256" },   .{ "upstream_release_archive_sha256", "upstreamReleaseArchiveSha256" },
        .{ "upstream_structure_sha256", "upstreamModelDataStructureHash" },
    }) |pair| if (catalog.object.get(pair[1])) |value| try projection.put(allocator, pair[0], value);
    const source_digest = try digestFile(io, "src/ai/catalog_source.json");
    try projection.put(allocator, "source", .{ .string = "src/ai/catalog_source.json" });
    try projection.put(allocator, "generated", .{ .string = "src/ai/catalog_generated.zig" });
    try projection.put(allocator, "source_sha256", .{ .string = &source_digest.hex });
    var manifest: std.json.ObjectMap = .empty;
    try manifest.put(allocator, "schema_version", .{ .integer = 2 });
    try manifest.put(allocator, "checkpoint", .{ .integer = checkpoint });
    try manifest.put(allocator, "status", .{ .string = "in_progress" });
    try manifest.put(allocator, "parity_certified", .{ .bool = false });
    try manifest.put(allocator, "release_version", .{ .string = package.version });
    try manifest.put(allocator, "root", .{ .string = "pi-zig" });
    try manifest.put(allocator, "complete_inventory", .{ .string = "FILES.sha256" });
    try manifest.put(allocator, "continuation", .{ .string = "UPSTREAM-UPDATE-20261003.md" });
    try manifest.put(allocator, "file_count_excluding_FILES_sha256", .{ .integer = @intCast(files.paths.items.len) });
    try manifest.put(allocator, "total_bytes_excluding_FILES_sha256_and_ARTIFACT_MANIFEST", .{ .integer = @intCast(total_bytes) });
    try manifest.put(allocator, "generated_catalog", .{ .object = projection });
    var counts: std.json.ObjectMap = .empty;
    try counts.put(allocator, "files", .{ .integer = @intCast(zig_files) });
    try counts.put(allocator, "lines", .{ .integer = @intCast(zig_lines) });
    try manifest.put(allocator, "zig_source", .{ .object = counts });
    var exclusions: std.json.Array = .init(allocator);
    for (excluded) |name| try exclusions.append(.{ .string = name });
    try manifest.put(allocator, "excluded_generated_paths", .{ .array = exclusions });
    const old_manifest = readJson(allocator, io, "ARTIFACT-MANIFEST.json") catch |err| switch (err) {
        error.FileNotFound => std.json.Value.null,
        else => return err,
    };
    if (old_manifest == .object) if (old_manifest.object.get("retired_reference")) |retired| try manifest.put(allocator, "retired_reference", retired);
    var output: std.Io.Writer.Allocating = .init(allocator);
    try std.json.Stringify.value(std.json.Value{ .object = manifest }, .{ .whitespace = .indent_2 }, &output.writer);
    try output.writer.writeByte('\n');
    try writeFile(io, "ARTIFACT-MANIFEST.json", output.written());
    var hashes: std.Io.Writer.Allocating = .init(allocator);
    for (files.paths.items, 0..) |path, index| {
        const digest = try digestFile(io, path);
        if (!std.mem.eql(u8, path, "ARTIFACT-MANIFEST.json") and !std.meta.eql(digest, initial_digests[index])) return error.InventoryFileChanged;
        try hashes.writer.print("{s}  {s}\n", .{ digest.hex, path });
    }
    try writeFile(io, "FILES.sha256", hashes.written());
    try writer.print("files={d}\nbytes_without_manifests={d}\nzig_files={d}\nzig_lines={d}\n", .{ files.paths.items.len, total_bytes, zig_files, zig_lines });
}

pub fn verify(gpa: std.mem.Allocator, io: std.Io, writer: *std.Io.Writer) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    const files = try inventory(allocator, io);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, "FILES.sha256", allocator, .limited(16 * 1024 * 1024));
    var lines = std.mem.tokenizeScalar(u8, bytes, '\n');
    var index: usize = 0;
    while (lines.next()) |line| {
        if (line.len < 67 or !std.mem.eql(u8, line[64..66], "  ")) return error.InvalidInventoryRecord;
        if (index >= files.paths.items.len or !std.mem.eql(u8, files.paths.items[index], line[66..])) return error.StaleArtifactInventory;
        for (line[0..64]) |byte| if (!std.ascii.isHex(byte)) return error.InvalidInventoryDigest;
        const digest = try digestFile(io, line[66..]);
        if (!std.mem.eql(u8, &digest.hex, line[0..64])) return error.ArtifactDigestMismatch;
        index += 1;
    }
    if (index != files.paths.items.len) return error.StaleArtifactInventory;
    try writer.print("verified_artifact_files={d}\n", .{index});
}

test "artifact inventory excludes generated directories and rejects ambiguous paths" {
    try std.testing.expect(try includePath("src/engine.zig"));
    try std.testing.expect(try includePath("vendor/parser.c"));
    try std.testing.expect(!try includePath("FILES.sha256"));
    try std.testing.expect(!try includePath("src/.zig-cache/generated.zig"));
    for ([_][]const u8{ "../outside", "src/../outside", "bad\nname", "src\\engine.zig" }) |path| try std.testing.expectError(error.InvalidInventoryPath, includePath(path));
}
