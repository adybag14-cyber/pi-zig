//! Whole tracked-tree drift detection; no source program is executed.
const std = @import("std");
pub const File = struct { mode: []const u8, kind: []const u8, object: []const u8, path: []const u8 };
pub const Contract = struct { schema_version: u32 = 1, upstream_commit: []const u8, object_format: []const u8, files: []const File };
pub const Difference = struct { added: usize = 0, removed: usize = 0, changed: usize = 0 };

fn git(gpa: std.mem.Allocator, io: std.Io, root: []const u8, arguments: []const []const u8) ![]u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    try argv.appendSlice(gpa, &.{ "git", "-C", root });
    try argv.appendSlice(gpa, arguments);
    const result = try std.process.run(gpa, io, .{ .argv = argv.items, .stdout_limit = .limited(32 * 1024 * 1024), .stderr_limit = .limited(8192), .timeout = .{ .duration = .{ .raw = .fromSeconds(30), .clock = .awake } } });
    defer gpa.free(result.stderr);
    errdefer gpa.free(result.stdout);
    if (result.term != .exited or result.term.exited != 0) return error.UpstreamGitFailed;
    return result.stdout;
}

pub fn parseTree(gpa: std.mem.Allocator, tree: []const u8) ![]File {
    var files: std.ArrayList(File) = .empty;
    errdefer files.deinit(gpa);
    var records = std.mem.splitScalar(u8, tree, 0);
    while (records.next()) |record| {
        if (record.len == 0) continue;
        const tab = std.mem.indexOfScalar(u8, record, '\t') orelse return error.InvalidUpstreamTree;
        var header = std.mem.splitScalar(u8, record[0..tab], ' ');
        const mode = header.next() orelse return error.InvalidUpstreamTree;
        const kind = header.next() orelse return error.InvalidUpstreamTree;
        const object = header.next() orelse return error.InvalidUpstreamTree;
        if (header.next() != null or (object.len != 40 and object.len != 64) or record.len == tab + 1) return error.InvalidUpstreamTree;
        for (object) |byte| if (!std.ascii.isHex(byte)) return error.InvalidUpstreamTree;
        if (!std.unicode.utf8ValidateSlice(record[tab + 1 ..])) return error.UnsupportedUpstreamPathEncoding;
        try files.append(gpa, .{ .mode = mode, .kind = kind, .object = object, .path = record[tab + 1 ..] });
    }
    return files.toOwnedSlice(gpa);
}

pub fn capture(gpa: std.mem.Allocator, io: std.Io, root: []const u8, expected_commit: []const u8) ![]u8 {
    const commit = try git(gpa, io, root, &.{ "rev-parse", "HEAD" });
    defer gpa.free(commit);
    if (!std.mem.eql(u8, std.mem.trim(u8, commit, "\r\n"), expected_commit)) return error.UpstreamCommitMismatch;
    const dirty = try git(gpa, io, root, &.{ "status", "--porcelain", "--untracked-files=no" });
    defer gpa.free(dirty);
    if (dirty.len != 0) return error.DirtyUpstreamSource;
    const format = try git(gpa, io, root, &.{ "rev-parse", "--show-object-format" });
    defer gpa.free(format);
    const tree = try git(gpa, io, root, &.{ "ls-tree", "-r", "-z", "HEAD" });
    defer gpa.free(tree);
    const files = try parseTree(gpa, tree);
    defer gpa.free(files);
    return std.json.Stringify.valueAlloc(gpa, Contract{ .upstream_commit = expected_commit, .object_format = std.mem.trim(u8, format, "\r\n"), .files = files }, .{ .whitespace = .indent_2 });
}

pub fn compare(gpa: std.mem.Allocator, expected: []const File, actual: []const File, writer: *std.Io.Writer) !Difference {
    var before: std.StringHashMapUnmanaged(File) = .empty;
    defer before.deinit(gpa);
    var after: std.StringHashMapUnmanaged(File) = .empty;
    defer after.deinit(gpa);
    for (expected) |file| {
        const slot = try before.getOrPut(gpa, file.path);
        if (slot.found_existing) return error.DuplicateUpstreamPath;
        slot.value_ptr.* = file;
    }
    for (actual) |file| {
        const slot = try after.getOrPut(gpa, file.path);
        if (slot.found_existing) return error.DuplicateUpstreamPath;
        slot.value_ptr.* = file;
    }
    var difference: Difference = .{};
    for (actual) |file| {
        if (before.get(file.path)) |old| {
            if (!std.mem.eql(u8, old.object, file.object) or !std.mem.eql(u8, old.mode, file.mode) or !std.mem.eql(u8, old.kind, file.kind)) {
                difference.changed += 1;
                try writer.print("changed: {s}\n", .{file.path});
            }
        } else {
            difference.added += 1;
            try writer.print("added: {s}\n", .{file.path});
        }
    }
    for (expected) |file| if (!after.contains(file.path)) {
        difference.removed += 1;
        try writer.print("removed: {s}\n", .{file.path});
    };
    return difference;
}

pub fn verify(gpa: std.mem.Allocator, io: std.Io, root: []const u8, manifest: []const u8, writer: *std.Io.Writer) !void {
    const parsed = try std.json.parseFromSlice(Contract, gpa, manifest, .{});
    defer parsed.deinit();
    if (parsed.value.schema_version != 1) return error.UnsupportedUpstreamContract;
    const commit = try git(gpa, io, root, &.{ "rev-parse", "HEAD" });
    defer gpa.free(commit);
    const actual_json = try capture(gpa, io, root, std.mem.trim(u8, commit, "\r\n"));
    defer gpa.free(actual_json);
    const actual = try std.json.parseFromSlice(Contract, gpa, actual_json, .{});
    defer actual.deinit();
    if (!std.mem.eql(u8, parsed.value.object_format, actual.value.object_format)) return error.UpstreamObjectFormatChanged;
    const difference = try compare(gpa, parsed.value.files, actual.value.files, writer);
    try writer.print("upstream_files={d} added={d} removed={d} changed={d}\n", .{ actual.value.files.len, difference.added, difference.removed, difference.changed });
    if (difference.added + difference.removed + difference.changed != 0) return error.UpstreamContractDrift;
    if (!std.mem.eql(u8, parsed.value.upstream_commit, actual.value.upstream_commit)) return error.UpstreamCommitChanged;
}

test "upstream tree diff catches new packages deleted APIs content modes and kind changes without line-ending assumptions" {
    const a = "0000000000000000000000000000000000000000";
    const b = "1111111111111111111111111111111111111111";
    const before = [_]File{ .{ .mode = "100644", .kind = "blob", .object = a, .path = "packages/old/api.ts" }, .{ .mode = "100644", .kind = "blob", .object = a, .path = "same" }, .{ .mode = "100644", .kind = "blob", .object = a, .path = "deleted" } };
    const after = [_]File{ .{ .mode = "100755", .kind = "blob", .object = b, .path = "packages/old/api.ts" }, .{ .mode = "100644", .kind = "blob", .object = a, .path = "same" }, .{ .mode = "160000", .kind = "commit", .object = a, .path = "packages/new" } };
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try std.testing.expectEqual(Difference{ .added = 1, .removed = 1, .changed = 1 }, try compare(std.testing.allocator, &before, &after, &output.writer));
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "packages/new") != null);
    try std.testing.expectError(error.DuplicateUpstreamPath, compare(std.testing.allocator, &before, &.{ after[0], after[0] }, &output.writer));
}

test "upstream tree parser retains whitespace paths rejects malformed object identities and frees failed admission" {
    const tree = "100644 blob 0000000000000000000000000000000000000000\tpath with\ttab.ts\x00";
    const files = try parseTree(std.testing.allocator, tree);
    defer std.testing.allocator.free(files);
    try std.testing.expectEqualStrings("path with\ttab.ts", files[0].path);
    try std.testing.expectError(error.InvalidUpstreamTree, parseTree(std.testing.allocator, "100644 blob bad\tfile\x00"));
    const Sweep = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const values = try parseTree(gpa, tree);
            defer gpa.free(values);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Sweep.run, .{});
}

test "upstream whole-tree gate verifies actual Git commits rejects provenance-only changes and dirty source" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(root);
    const commands = [_][]const []const u8{
        &.{ "init", "-q" },
        &.{ "config", "user.name", "Pi Contract Fixture" },
        &.{ "config", "user.email", "fixture@invalid.example" },
        &.{ "config", "core.autocrlf", "false" },
    };
    for (commands) |command| {
        const output = try git(gpa, io, root, command);
        gpa.free(output);
    }
    try tmp.dir.writeFile(io, .{ .sub_path = "api.txt", .data = "original\n" });
    for ([_][]const []const u8{ &.{ "add", "." }, &.{ "commit", "-qm", "original" } }) |command| {
        const output = try git(gpa, io, root, command);
        gpa.free(output);
    }
    const commit = try git(gpa, io, root, &.{ "rev-parse", "HEAD" });
    defer gpa.free(commit);
    const manifest = try capture(gpa, io, root, std.mem.trim(u8, commit, "\r\n"));
    defer gpa.free(manifest);
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    try verify(gpa, io, root, manifest, &output.writer);
    const provenance = try git(gpa, io, root, &.{ "commit", "--allow-empty", "-qm", "new provenance" });
    defer gpa.free(provenance);
    try std.testing.expectError(error.UpstreamCommitChanged, verify(gpa, io, root, manifest, &output.writer));
    try tmp.dir.writeFile(io, .{ .sub_path = "api.txt", .data = "dirty\n" });
    try std.testing.expectError(error.DirtyUpstreamSource, verify(gpa, io, root, manifest, &output.writer));
    const added = try git(gpa, io, root, &.{ "add", "." });
    defer gpa.free(added);
    const changed = try git(gpa, io, root, &.{ "commit", "-qm", "changed API" });
    defer gpa.free(changed);
    try std.testing.expectError(error.UpstreamContractDrift, verify(gpa, io, root, manifest, &output.writer));
}
