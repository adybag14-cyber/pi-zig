const std = @import("std");
const builtin = @import("builtin");
const fs = @import("../durable/filesystem.zig");
const types = @import("../durable/types.zig");
const files = @import("files.zig");
const remote = @import("remote_env.zig");
const local = @import("local_env.zig");
const capability = @import("../durable/env_capability.zig");
const connection = @import("connection.zig");
const info = @import("info.zig");
fn externalTmp() !std.testing.TmpDir {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const root = try @import("../durable/startup.zig").tempDirectory(gpa, &environ);
    defer gpa.free(root);
    const parent = try std.Io.Dir.cwd().openDir(io, root, .{});
    errdefer parent.close(io);
    var bytes: [12]u8 = undefined;
    try io.randomSecure(&bytes);
    var name: [16]u8 = undefined;
    _ = std.base64.url_safe.Encoder.encode(&name, &bytes);
    // The standard TmpDir owner deletes only this freshly created random child of the opened OS temp directory.
    const dir = try parent.createDirPathOpen(io, &name, .{});
    return .{ .dir = dir, .parent_dir = parent, .sub_path = name };
}
fn tree(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, fixture: std.json.Value) !void {
    var iterator = fixture.object.get("files").?.object.iterator();
    while (iterator.next()) |entry| {
        if (std.fs.path.dirname(entry.key_ptr.*)) |parent| try dir.createDirPath(io, parent);
        try dir.writeFile(io, .{ .sub_path = entry.key_ptr.*, .data = entry.value_ptr.string });
    }
    for (fixture.object.get("directories").?.array.items) |entry| try dir.createDirPath(io, entry.string);
    _ = gpa;
}
fn windowsJunction(gpa: std.mem.Allocator, io: std.Io, target: []const u8, link: []const u8) !void {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const windows = std.os.windows;
    const Native = struct {
        extern "kernel32" fn DeviceIoControl(windows.HANDLE, u32, ?*const anyopaque, u32, ?*anyopaque, u32, *u32, ?*anyopaque) callconv(.winapi) windows.BOOL;
    };
    try std.Io.Dir.cwd().createDir(io, link, .default_dir);
    const handle = try fs.openWindowsNoFollow(io, gpa, link, 0x40000000);
    defer handle.close(io);
    const substituted = try std.fmt.allocPrint(gpa, "\\??\\{s}", .{target});
    defer gpa.free(substituted);
    const substitute = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, substituted);
    defer gpa.free(substitute);
    const printed = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, target);
    defer gpa.free(printed);
    const substitute_length = substitute.len * 2;
    const print_length = printed.len * 2;
    const bytes = try gpa.alloc(u8, 16 + substitute_length + 2 + print_length + 2);
    defer gpa.free(bytes);
    @memset(bytes, 0);
    std.mem.writeInt(u32, bytes[0..4], 0xa0000003, .little);
    std.mem.writeInt(u16, bytes[4..6], @intCast(bytes.len - 8), .little);
    std.mem.writeInt(u16, bytes[10..12], @intCast(substitute_length), .little);
    std.mem.writeInt(u16, bytes[12..14], @intCast(substitute_length + 2), .little);
    std.mem.writeInt(u16, bytes[14..16], @intCast(print_length), .little);
    @memcpy(bytes[16..][0..substitute_length], std.mem.sliceAsBytes(substitute));
    @memcpy(bytes[16 + substitute_length + 2 ..][0..print_length], std.mem.sliceAsBytes(printed));
    var returned: u32 = 0;
    if (Native.DeviceIoControl(handle.handle, 0x000900a4, bytes.ptr, @intCast(bytes.len), null, 0, &returned, null) == .FALSE) return error.JunctionCreationFailed;
}
test "listFiles daemon bytes match actual e6220e1 source across hierarchical ignores globals hidden bounds and errors" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const fixture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/list-files-e6220e1.json"), .{});
    defer fixture.deinit();
    var tmp = try externalTmp();
    defer tmp.cleanup();
    try tree(gpa, io, tmp.dir, fixture.value);
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = buffer[0..try tmp.dir.realPath(io, &buffer)];
    const home = try std.fs.path.join(gpa, &.{ root, "home" });
    defer gpa.free(home);
    var server = try files.Server.init(gpa, io, root, home);
    defer server.deinit();
    for (fixture.value.object.get("cases").?.array.items) |case| {
        const path = try std.fs.path.join(gpa, &.{ root, case.object.get("path").?.string });
        defer gpa.free(path);
        var request: std.json.Value = .{ .object = .empty };
        defer request.object.deinit(gpa);
        var options = case.object.get("options").?.object.iterator();
        while (options.next()) |entry| try request.object.put(gpa, entry.key_ptr.*, entry.value_ptr.*);
        try request.object.put(gpa, "op", .{ .string = "listFiles" });
        try request.object.put(gpa, "path", .{ .string = path });
        var reply = try server.dispatch(request, "", .{});
        defer reply.deinit();
        const json = try std.json.parseFromSlice(std.json.Value, gpa, reply.json, .{});
        defer json.deinit();
        const expected_kind: u8 = @intCast(case.object.get("kind").?.integer);
        if (@intFromEnum(reply.kind) != expected_kind) std.debug.print("listFiles case {s}: {s}\n", .{ case.object.get("name").?.string, reply.json });
        try std.testing.expectEqual(expected_kind, @intFromEnum(reply.kind));
        const expected = case.object.get("json").?.object;
        if (reply.kind == .result) {
            if (expected.get("count").?.integer != json.value.object.get("count").?.integer) std.debug.print("listFiles count mismatch {s}\n", .{case.object.get("name").?.string});
            try std.testing.expectEqual(expected.get("count").?.integer, json.value.object.get("count").?.integer);
            try std.testing.expectEqual(expected.get("truncated").?.bool, json.value.object.get("truncated").?.bool);
            const encoded = case.object.get("payload").?.string;
            const bytes = try gpa.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(encoded));
            defer gpa.free(bytes);
            try std.base64.standard.Decoder.decode(bytes, encoded);
            if (!std.mem.eql(u8, bytes, reply.payload)) std.debug.print("listFiles case {s}\nexpected: {s}\nactual: {s}\n", .{ case.object.get("name").?.string, bytes, reply.payload });
            try std.testing.expectEqualStrings(bytes, reply.payload);
        } else try std.testing.expectEqualStrings(expected.get("code").?.string, json.value.object.get("code").?.string);
    }
}
test "listFiles protocol errors and nullish defaults match genuine Source without changing other filesystem paths" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = try externalTmp();
    defer tmp.cleanup();
    for ([_][]const u8{ "a", "b", "c" }) |name| try tmp.dir.writeFile(io, .{ .sub_path = name, .data = "" });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = buffer[0..try tmp.dir.realPath(io, &buffer)];
    var server = try files.Server.init(gpa, io, root, null);
    defer server.deinit();
    const fixture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/list-files-errors-e6220e1.json"), .{});
    defer fixture.deinit();
    for (fixture.value.array.items) |case| {
        const name = case.object.get("name").?.string;
        const path = if (std.mem.eql(u8, name, "empty")) try gpa.dupe(u8, "") else if (std.mem.eql(u8, name, "wildcard")) try std.fs.path.join(gpa, &.{ root, "?" }) else if (std.mem.eql(u8, name, "nul")) try std.fmt.allocPrint(gpa, "{s}\x00", .{root}) else try gpa.dupe(u8, root);
        defer gpa.free(path);
        var request: std.json.Value = .{ .object = .empty };
        defer request.object.deinit(gpa);
        var fields = case.object.get("input").?.object.iterator();
        while (fields.next()) |entry| try request.object.put(gpa, entry.key_ptr.*, entry.value_ptr.*);
        try request.object.put(gpa, "op", .{ .string = "listFiles" });
        try request.object.put(gpa, "path", if (std.mem.eql(u8, name, "path-null")) .null else .{ .string = path });
        var reply = try server.dispatch(request, "", .{});
        defer reply.deinit();
        try std.testing.expectEqual(@as(u8, @intCast(case.object.get("kind").?.integer)), @intFromEnum(reply.kind));
        const json = try std.json.parseFromSlice(std.json.Value, gpa, reply.json, .{});
        defer json.deinit();
        if (reply.kind == .remote_error) {
            try std.testing.expectEqualStrings(case.object.get("code").?.string, json.value.object.get("code").?.string);
        } else {
            try std.testing.expectEqualStrings("fa\x00fb\x00fc\x00", reply.payload);
            try std.testing.expectEqual(@as(i64, 3), json.value.object.get("count").?.integer);
        }
    }
    var original = try server.filesystem.absolutePath("bad\x00path", .{});
    defer original.failure.deinit(gpa);
    try std.testing.expectEqual(types.FileErrorCode.invalid, original.failure.code);
}
test "listFiles remote local capability retained directory paging and old daemon fallback use real native transport" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const program = environ.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    const fixture = environ.get("PI_TEST_SSH_FIXTURE") orelse return error.SkipZigTest;
    const client = try connection.Connection.start(gpa, io, &.{program}, 1);
    defer client.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = buffer[0..try tmp.dir.realPath(io, &buffer)];
    var owner = try remote.RemoteExecutionEnv.init(gpa, .{ .connection = .{ .native = client }, .id = "listFiles", .cwd = root });
    defer owner.deinit();
    var local_owner = try local.LocalExecutionEnv.init(gpa, io, .{ .node = .{ .cwd = root, .environ = &environ, .temp_dir = root }, .connection = .{ .native = client } });
    defer local_owner.deinit();
    var env = capability.ExecutionEnv.from(&local_owner);
    try std.testing.expect((try env.writeFile("a", "local-files", .{})) == .value);
    try std.testing.expect((try owner.writeFile("b", "remote-files", .{})) == .value);
    try std.testing.expect((try owner.writeFile("c", "end", .{})) == .value);
    var actual = try owner.listFiles(".", .{ .maxEntries = 2 }, .{});
    defer if (actual == .value) actual.value.deinit(gpa) else actual.failure.deinit(gpa);
    var same = try env.listFiles(".", .{ .maxEntries = 2 }, .{});
    defer if (same == .value) same.value.deinit(gpa) else same.failure.deinit(gpa);
    try std.testing.expect(actual == .value and same == .value);
    try std.testing.expect(actual.value.truncated and same.value.truncated);
    try std.testing.expectEqual(@as(usize, 2), actual.value.entries.len);
    for (actual.value.entries, same.value.entries) |a, b| {
        try std.testing.expectEqualStrings(a.path, b.path);
        try std.testing.expectEqual(a.kind, b.kind);
    }
    var opened = try owner.openDirReader(".", .{});
    try std.testing.expect(opened == .value);
    defer opened.value.deinit();
    var count: usize = 0;
    while (true) {
        var page = try opened.value.next(1, .{});
        try std.testing.expect(page == .value);
        defer page.value.deinit(gpa);
        count += page.value.entries.len;
        if (page.value.done) break;
    }
    try std.testing.expectEqual(@as(usize, 3), count);
    var flag: std.atomic.Value(bool) = .init(true);
    var aborted = try owner.listFiles(".", .{}, .{ .abort_flag = &flag });
    defer aborted.failure.deinit(gpa);
    try std.testing.expectEqual(types.FileErrorCode.aborted, aborted.failure.code);
    var invalid = try owner.listFiles(".", .{ .maxEntries = 9007199254740992 }, .{ .abort_flag = &flag });
    defer invalid.failure.deinit(gpa);
    try std.testing.expectEqual(types.FileErrorCode.invalid, invalid.failure.code);
    const old = try connection.Connection.start(gpa, io, &.{ fixture, "old-daemon" }, 2);
    defer old.deinit();
    var old_owner = try remote.RemoteExecutionEnv.init(gpa, .{ .connection = .{ .native = old }, .id = "old", .cwd = "/" });
    defer old_owner.deinit();
    var unsupported = try old_owner.listFiles(".", .{}, .{});
    defer unsupported.failure.deinit(gpa);
    try std.testing.expectEqual(types.FileErrorCode.not_supported, unsupported.failure.code);
    var old_local = try local.LocalExecutionEnv.init(gpa, io, .{ .node = .{ .cwd = root, .environ = &environ, .temp_dir = root }, .connection = .{ .native = old } });
    defer old_local.deinit();
    var local_unsupported = try old_local.listFiles(".", .{}, .{});
    defer local_unsupported.failure.deinit(gpa);
    try std.testing.expectEqual(types.FileErrorCode.not_supported, local_unsupported.failure.code);
}
test "listFiles nodePlatform maps the exact Source names and preserves unknown names" {
    const cases = .{ .{ "windows", "aarch64", "win32", "arm64" }, .{ "macos", "x86_64", "darwin", "x64" }, .{ "linux", "x86", "linux", "ia32" }, .{ "android", "riscv64", "android", "riscv64" } };
    inline for (cases) |case| {
        const platform = info.nodePlatform(.{ .os = case[0], .arch = case[1] });
        try std.testing.expectEqualStrings(case[2], platform.platform);
        try std.testing.expectEqualStrings(case[3], platform.arch);
    }
}
test "listFiles ignore parser and globs match genuine Source daemon walks including invalid UTF8" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const fixture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/list-files-ignore-e6220e1.json"), .{});
    defer fixture.deinit();
    var tmp = try externalTmp();
    defer tmp.cleanup();
    for (fixture.value.object.get("files").?.array.items) |file| {
        if (std.fs.path.dirname(file.string)) |parent| try tmp.dir.createDirPath(io, parent);
        try tmp.dir.writeFile(io, .{ .sub_path = file.string, .data = "" });
    }
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = buffer[0..try tmp.dir.realPath(io, &buffer)];
    for (fixture.value.object.get("cases").?.array.items) |case| {
        const pattern: []u8 = if (case.object.get("patternBytes")) |raw| decoded: {
            const bytes = try gpa.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(raw.string));
            errdefer gpa.free(bytes);
            try std.base64.standard.Decoder.decode(bytes, raw.string);
            break :decoded bytes;
        } else try gpa.dupe(u8, case.object.get("pattern").?.string);
        defer gpa.free(pattern);
        try tmp.dir.writeFile(io, .{ .sub_path = ".gitignore", .data = pattern });
        var listing = try fs.listing.list(gpa, io, root, null, .{}, .{});
        defer listing.deinit(gpa);
        const actual = try listing.payload(gpa);
        defer gpa.free(actual);
        const encoded = case.object.get("payload").?.string;
        const bytes = try gpa.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(encoded));
        defer gpa.free(bytes);
        try std.base64.standard.Decoder.decode(bytes, encoded);
        if (!std.mem.eql(u8, bytes, actual)) std.debug.print("listFiles ignore pattern: {s}\n", .{pattern});
        try std.testing.expectEqualStrings(bytes, actual);
    }
}
fn allocationListing(gpa: std.mem.Allocator, root: []const u8) !void {
    var result = try fs.listing.list(gpa, std.testing.io, root, null, .{ .gitignore = false }, .{});
    defer result.deinit(gpa);
    const bytes = try result.payload(gpa);
    defer gpa.free(bytes);
}
test "listFiles owned walk and payload remain leak free at every allocation failure" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "sub");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "sub/file", .data = "" });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = buffer[0..try tmp.dir.realPath(std.testing.io, &buffer)];
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationListing, .{root});
}
fn allocationIgnored(gpa: std.mem.Allocator, root: []const u8, home: []const u8) !void {
    var result = try fs.listing.list(gpa, std.testing.io, root, home, .{}, .{});
    defer result.deinit(gpa);
}
test "listFiles ignore stacks global config and nested branches remain leak free at every allocation failure" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = try externalTmp();
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "project/.git/info");
    try tmp.dir.createDirPath(io, "project/sub");
    try tmp.dir.createDirPath(io, "home");
    try tmp.dir.writeFile(io, .{ .sub_path = "home/.gitconfig", .data = "excludesfile = ~/global-ignore\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "home/global-ignore", .data = "global\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "project/.gitignore", .data = "*{.log,.tmp}\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "project/.git/info/exclude", .data = "exclude\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "project/sub/.gitignore", .data = "!keep\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "project/sub/keep", .data = "" });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const base = buffer[0..try tmp.dir.realPath(io, &buffer)];
    const root = try std.fs.path.join(gpa, &.{ base, "project" });
    defer gpa.free(root);
    const home = try std.fs.path.join(gpa, &.{ base, "home" });
    defer gpa.free(home);
    try std.testing.checkAllAllocationFailures(gpa, allocationIgnored, .{ root, home });
}
test "listFiles links stay unfollowed while an explicit linked root can be listed" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = try externalTmp();
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "dir");
    try tmp.dir.writeFile(io, .{ .sub_path = "dir/inner.txt", .data = "" });
    tmp.dir.symLink(io, "dir", "link", .{ .is_directory = true }) catch |err| {
        if (builtin.os.tag == .windows and (err == error.AccessDenied or err == error.PermissionDenied)) return error.SkipZigTest;
        return err;
    };
    try tmp.dir.symLink(io, "missing", "dangling", .{});
    var dir = try tmp.dir.openDir(io, "dir", .{});
    defer dir.close(io);
    try dir.symLink(io, "..", "loop", .{ .is_directory = true });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = buffer[0..try tmp.dir.realPath(io, &buffer)];
    var result = try fs.listing.list(gpa, io, root, null, .{}, .{});
    defer result.deinit(gpa);
    const payload = try result.payload(gpa);
    defer gpa.free(payload);
    try std.testing.expectEqualStrings("ldangling\x00ddir\x00fdir/inner.txt\x00ldir/loop\x00llink\x00", payload);
    const linked = try std.fs.path.join(gpa, &.{ root, "link" });
    defer gpa.free(linked);
    var through = try fs.listing.list(gpa, io, linked, null, .{}, .{});
    defer through.deinit(gpa);
    const linked_payload = try through.payload(gpa);
    defer gpa.free(linked_payload);
    try std.testing.expectEqualStrings("finner.txt\x00lloop\x00", linked_payload);
}
test "listFiles Windows junctions hidden attributes and unpaired UTF16 names match genuine Source bytes" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = try externalTmp();
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "links/dir");
    try tmp.dir.createDirPath(io, "names");
    try tmp.dir.createDirPath(io, "unicode");
    try tmp.dir.writeFile(io, .{ .sub_path = "links/dir/inner.txt", .data = "" });
    try tmp.dir.writeFile(io, .{ .sub_path = "names/bad-\xed\xa0\x80", .data = "" });
    try tmp.dir.writeFile(io, .{ .sub_path = "names/attribute-hidden", .data = "" });
    try tmp.dir.writeFile(io, .{ .sub_path = "unicode/é", .data = "" });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = buffer[0..try tmp.dir.realPath(io, &buffer)];
    const target = try std.fs.path.join(gpa, &.{ root, "links", "dir" });
    defer gpa.free(target);
    const link = try std.fs.path.join(gpa, &.{ root, "links", "link" });
    defer gpa.free(link);
    const loop_target = try std.fs.path.join(gpa, &.{ root, "links" });
    defer gpa.free(loop_target);
    const loop_path = try std.fs.path.join(gpa, &.{ root, "links", "dir", "loop" });
    defer gpa.free(loop_path);
    try windowsJunction(gpa, io, target, link);
    try windowsJunction(gpa, io, loop_target, loop_path);
    const hidden_path = try std.fs.path.join(gpa, &.{ root, "names", "attribute-hidden" });
    defer gpa.free(hidden_path);
    const hidden_wide = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, hidden_path);
    defer gpa.free(hidden_wide);
    const Native = struct {
        extern "kernel32" fn SetFileAttributesW([*:0]const u16, u32) callconv(.winapi) std.os.windows.BOOL;
    };
    try std.testing.expect(Native.SetFileAttributesW(hidden_wide.ptr, 2) != .FALSE);
    const fixture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/list-files-windows-edges-e6220e1.json"), .{});
    defer fixture.deinit();
    for (fixture.value.object.get("cases").?.array.items) |case| {
        const path = try std.fs.path.join(gpa, &.{ root, case.object.get("path").?.string });
        defer gpa.free(path);
        var listing = try fs.listing.list(gpa, io, path, null, try fs.ListFilesOptions.fromJson(case.object.get("options").?), .{});
        defer listing.deinit(gpa);
        const actual = try listing.payload(gpa);
        defer gpa.free(actual);
        const encoded = case.object.get("payload").?.string;
        const bytes = try gpa.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(encoded));
        defer gpa.free(bytes);
        try std.base64.standard.Decoder.decode(bytes, encoded);
        try std.testing.expectEqualStrings(bytes, actual);
        try std.testing.expectEqual(case.object.get("json").?.object.get("truncated").?.bool, listing.truncated);
    }
}
test "listFiles real daemon cancels an admitted walk and keeps subsequent bounded requests healthy" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const program = environ.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    const client = try connection.Connection.start(gpa, io, &.{program}, 8);
    defer client.deinit();
    var tmp = try externalTmp();
    defer tmp.cleanup();
    for (0..100) |d| {
        var name_buffer: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buffer, "d{d}", .{d});
        try tmp.dir.createDirPath(io, name);
        for (0..100) |f| {
            var file_buffer: [64]u8 = undefined;
            try tmp.dir.writeFile(io, .{ .sub_path = try std.fmt.bufPrint(&file_buffer, "d{d}/f{d}", .{ d, f }), .data = "" });
        }
    }
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = buffer[0..try tmp.dir.realPath(io, &buffer)];
    var ticket = try client.begin(.{ .op = "listFiles", .path = root }, "", null);
    defer ticket.deinit();
    try ticket.cancel(false);
    var canceled = try ticket.next(10_000);
    defer canceled.deinit();
    try std.testing.expect(canceled.kind == .remote_error);
    try std.testing.expectEqualStrings("aborted", canceled.json.value.object.get("code").?.string);
    var owner = try remote.RemoteExecutionEnv.init(gpa, .{ .connection = .{ .native = client }, .id = "cancel-listing", .cwd = root });
    defer owner.deinit();
    var complete = try owner.listFiles(".", .{}, .{});
    defer if (complete == .value) complete.value.deinit(gpa) else complete.failure.deinit(gpa);
    try std.testing.expect(complete == .value);
    try std.testing.expectEqual(@as(usize, 10_100), complete.value.entries.len);
    try std.testing.expect(!complete.value.truncated);
    var bounded = try owner.listFiles(".", .{ .maxEntries = 5000 }, .{});
    defer if (bounded == .value) bounded.value.deinit(gpa) else bounded.failure.deinit(gpa);
    try std.testing.expect(bounded == .value);
    try std.testing.expectEqual(@as(usize, 5000), bounded.value.entries.len);
    try std.testing.expect(bounded.value.truncated);
}
