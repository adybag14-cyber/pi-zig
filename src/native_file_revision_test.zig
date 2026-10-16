//! Focused real-filesystem tests. Root's native lane must execute these before
//! this Source-only checkpoint is described as native validated.
const std = @import("std");
const builtin = @import("builtin");
const revision = @import("extensions/native_file_revision.zig");
const file_stat = @import("extensions/native_file_stat.zig");

fn absolute(tmp: std.Io.Dir, leaf: []const u8) ![]u8 {
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.realPath(std.testing.io, &buffer);
    return std.fs.path.join(std.testing.allocator, &.{ buffer[0..length], leaf });
}
fn create(dir: std.Io.Dir, name: []const u8, text: []const u8) !void {
    const file = try dir.createFile(std.testing.io, name, .{});
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, text, 0);
}

test "file revision rejects missing and embedded NUL paths without truncating an existing file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try create(tmp.dir, "present", "retained");
    const path = try absolute(tmp.dir, "present");
    defer std.testing.allocator.free(path);
    const missing = try absolute(tmp.dir, "missing");
    defer std.testing.allocator.free(missing);
    try std.testing.expectEqual(null, try revision.revisionAlloc(std.testing.allocator, missing));
    const invalid = try std.mem.concat(std.testing.allocator, u8, &.{ path, "\x00suffix" });
    defer std.testing.allocator.free(invalid);
    try std.testing.expectEqual(null, try revision.revisionAlloc(std.testing.allocator, invalid));
    const valid = (try revision.revisionAlloc(std.testing.allocator, path)).?;
    defer std.testing.allocator.free(valid);
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, valid, ":"));
}

test "file revision retains full kernel integer fields and observes same inode mutation" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try create(tmp.dir, "precision-\xc3\xa9", "old");
    const path = try absolute(tmp.dir, "precision-\xc3\xa9");
    defer std.testing.allocator.free(path);
    const before = try file_stat.read(std.testing.allocator, path);
    const before_revision = (try revision.revisionAlloc(std.testing.allocator, path)).?;
    defer std.testing.allocator.free(before_revision);
    const expected = try std.fmt.allocPrint(std.testing.allocator, "{d}:{d}:{d}:{d}:{d}", .{ before.dev, before.ino, before.size, before.mtime_ns, before.ctime_ns });
    defer std.testing.allocator.free(expected);
    try std.testing.expectEqualStrings(expected, before_revision);
    try create(tmp.dir, "precision-\xc3\xa9", "a longer mutation");
    const after = try file_stat.read(std.testing.allocator, path);
    try std.testing.expectEqual(before.dev, after.dev);
    try std.testing.expectEqual(before.ino, after.ino);
    try std.testing.expectEqual(@as(u64, 17), after.size);
    const after_revision = (try revision.revisionAlloc(std.testing.allocator, path)).?;
    defer std.testing.allocator.free(after_revision);
    try std.testing.expect(!std.mem.eql(u8, before_revision, after_revision));
    // Current real timestamps exceed exact IEEE754 integer precision. A
    // decimal revision must preserve their final digits instead of rounding.
    try std.testing.expect(after.mtime_ns > 9007199254740991);
}

test "replacement and identical cross directory basenames keep real file identities" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try create(tmp.dir, "entry", "same");
    try create(tmp.dir, "replacement", "same");
    const path = try absolute(tmp.dir, "entry");
    defer std.testing.allocator.free(path);
    const first = try file_stat.read(std.testing.allocator, path);
    // Preserve the old object while replacing its original pathname. This
    // avoids inode-reuse ambiguity in the identity assertion.
    try tmp.dir.rename("entry", tmp.dir, "retained-old", std.testing.io);
    try tmp.dir.rename("replacement", tmp.dir, "entry", std.testing.io);
    const replaced = try file_stat.read(std.testing.allocator, path);
    try std.testing.expect(first.dev != replaced.dev or first.ino != replaced.ino);
    try tmp.dir.createDir(std.testing.io, "other", .default_dir);
    try create(tmp.dir, "other/entry", "same");
    const other = try absolute(tmp.dir, "other/entry");
    defer std.testing.allocator.free(other);
    const separate = try file_stat.read(std.testing.allocator, other);
    try std.testing.expect(replaced.dev != separate.dev or replaced.ino != separate.ino);
    const directory = try absolute(tmp.dir, "other");
    defer std.testing.allocator.free(directory);
    const directory_stat = try file_stat.read(std.testing.allocator, directory);
    if (builtin.os.tag == .windows) try std.testing.expectEqual(@as(u64, 0), directory_stat.size);
}

test "file revision follows a real symlink or matches the genuine Source host denial" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try create(tmp.dir, "target", "symlink target");
    tmp.dir.symLink(std.testing.io, "target", "link", .{}) catch |err| switch (err) {
        error.AccessDenied, error.PermissionDenied => {
            const captured = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("extensions/fixtures/file-revision-source-4954.json"), .{});
            defer captured.deinit();
            try std.testing.expectEqualStrings("host-denied-creation", captured.value.object.get("symlink").?.object.get("status").?.string);
            try std.testing.expectEqualStrings("EPERM", captured.value.object.get("symlink").?.object.get("code").?.string);
            return;
        },
        else => return err,
    };
    const target = try absolute(tmp.dir, "target");
    defer std.testing.allocator.free(target);
    const link = try absolute(tmp.dir, "link");
    defer std.testing.allocator.free(link);
    const target_revision = (try revision.revisionAlloc(std.testing.allocator, target)).?;
    defer std.testing.allocator.free(target_revision);
    const link_revision = (try revision.revisionAlloc(std.testing.allocator, link)).?;
    defer std.testing.allocator.free(link_revision);
    try std.testing.expectEqualStrings(target_revision, link_revision);
}

test "private allocation failures remain errors rather than Source missing revisions" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try create(tmp.dir, "allocation", "present");
    const path = try absolute(tmp.dir, "allocation");
    defer std.testing.allocator.free(path);
    // The native path conversion allocates before the kernel stat, and the
    // returned decimal string allocates afterward. Both boundaries must keep
    // a private host OOM distinct from Source's ordinary stat failure result.
    for (0..2) |index| {
        var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{ .fail_index = index });
        try std.testing.expectError(error.OutOfMemory, revision.revisionAlloc(failing.allocator(), path));
    }
}

test "native revisions equal actual Source bigint stat strings on six retained physical paths" {
    const captured = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("extensions/fixtures/file-revision-source-4954.json"), .{});
    defer captured.deinit();
    try std.testing.expectEqualStrings("4954d760504c11df9b2cbdc040346107b6a8153d", captured.value.object.get("sourceHead").?.string);
    try std.testing.expectEqualStrings("passed", captured.value.object.get("status").?.string);
    const files = captured.value.object.get("finalFiles").?.array.items;
    try std.testing.expectEqual(@as(usize, 6), files.len);
    var present: usize = 0;
    for (files) |file| {
        _ = file_stat.read(std.testing.allocator, file.object.get("path").?.string) catch |err| switch (err) {
            error.FileStatOpenFailed, error.FileStatFailed => continue,
            else => return err,
        };
        present += 1;
    }
    // These are deliberately retained original Windows physical objects, not
    // recreated fixtures with invented IDs/times. Other hosts cannot replay
    // their identity; report that as a skipped test instead of a native pass.
    if (present == 0) return error.SkipZigTest;
    try std.testing.expectEqual(files.len, present);
    const em = @import("extensions/engine.zig");
    const c = em.c;
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try std.testing.expect(c.JS_IsUndefined(try revision.getFileRevision(engine, c.JS_NewInt32(engine.context, 42))));
    for (files) |file| {
        const path = file.object.get("path").?.string;
        const argument = try engine.checked(c.JS_NewStringLen(engine.context, path.ptr, path.len));
        defer engine.freeValue(argument);
        const result = try revision.getFileRevision(engine, argument);
        defer engine.freeValue(result);
        try std.testing.expect(c.JS_IsString(result));
        const actual = try engine.toString(result);
        defer std.testing.allocator.free(actual);
        try std.testing.expectEqualStrings(file.object.get("revision").?.string, actual);
        // std.Io's Win32 absolute-path conversion follows ordinary Win32
        // trimming. Preserve the exact original Source filename when reading
        // the physical content, including its trailing U+0020.
        const physical_path = if (builtin.os.tag == .windows) try std.fmt.allocPrint(std.testing.allocator, "\\\\?\\{s}", .{path}) else try std.testing.allocator.dupe(u8, path);
        defer std.testing.allocator.free(physical_path);
        const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, physical_path, std.testing.allocator, .limited(1024 * 1024));
        defer std.testing.allocator.free(bytes);
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
        const hex = std.fmt.bytesToHex(digest, .lower);
        try std.testing.expectEqualStrings(file.object.get("sha256").?.string, &hex);
        if (builtin.os.tag == .windows and std.mem.endsWith(u8, path, " ")) {
            try std.testing.expectEqual(null, try revision.revisionAlloc(std.testing.allocator, std.mem.trimEnd(u8, path, " ")));
        }
    }
}
