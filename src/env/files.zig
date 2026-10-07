//! Pi-env daemon filesystem operations with retained connection-owned handles.
const std = @import("std");
const builtin = @import("builtin");
const fs = @import("../durable/filesystem.zig");
const types = @import("../durable/types.zig");
const metadata = @import("metadata.zig");
const frame = @import("frame.zig");
pub const Reply = struct {
    gpa: std.mem.Allocator,
    kind: frame.Kind,
    json: []u8,
    payload: []u8 = &.{},
    pub fn deinit(self: *Reply) void {
        self.gpa.free(self.json);
        self.gpa.free(self.payload);
    }
    fn success(gpa: std.mem.Allocator, value: anytype) !Reply {
        return .{ .gpa = gpa, .kind = .result, .json = try std.json.Stringify.valueAlloc(gpa, value, .{ .emit_null_optional_fields = false }) };
    }
    fn failure(gpa: std.mem.Allocator, code: []const u8, err: anyerror, path: ?[]const u8) !Reply {
        return .{ .gpa = gpa, .kind = .remote_error, .json = try std.json.Stringify.valueAlloc(gpa, .{ .code = code, .message = @errorName(err), .path = path }, .{ .emit_null_optional_fields = false }) };
    }
};
fn call(server: *Server, object: anytype, payload: []const u8) !Reply {
    const encoded = try std.json.Stringify.valueAlloc(server.filesystem.gpa, object, .{});
    defer server.filesystem.gpa.free(encoded);
    const parsed = try std.json.parseFromSlice(std.json.Value, server.filesystem.gpa, encoded, .{});
    defer parsed.deinit();
    return server.dispatch(parsed.value, payload, .{});
}
fn parsedSuccess(reply: *Reply) !std.json.Parsed(std.json.Value) {
    if (reply.kind != .result) std.debug.print("Remote filesystem failure: {s}\n", .{reply.json});
    try std.testing.expectEqual(frame.Kind.result, reply.kind);
    return std.json.parseFromSlice(std.json.Value, reply.gpa, reply.json, .{});
}
fn lossyName(gpa: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const Sink = struct {
        gpa: std.mem.Allocator,
        output: std.ArrayList(u8) = .empty,
        pub fn codepoint(self: *@This(), scalar: u21) !void {
            var encoded: [4]u8 = undefined;
            const length = try std.unicode.utf8Encode(scalar, &encoded);
            try self.output.appendSlice(self.gpa, encoded[0..length]);
        }
    };
    var sink: Sink = .{ .gpa = gpa };
    defer sink.output.deinit(gpa);
    var decoder: @import("../durable/decode.zig").Decoder = .{ .drop_initial_bom = false };
    try decoder.push(bytes, &sink);
    try decoder.finish(&sink);
    return sink.output.toOwnedSlice(gpa);
}
test "directory names preserve BOM and encode invalid native bytes with decoded-path errors" {
    const gpa = std.testing.allocator;
    const decoded = try lossyName(gpa, "\xef\xbb\xbf\xff\xe2\x82");
    defer gpa.free(decoded);
    try std.testing.expectEqualStrings("\xef\xbb\xbf\xef\xbf\xbd\xef\xbf\xbd", decoded);
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    tmp.dir.writeFile(io, .{ .sub_path = "bad-\xff", .data = "original-byte-name" }) catch |err| switch (err) {
        error.BadPathName => {
            // APFS rejects this byte spelling with EILSEQ. Keep decoder proof
            // above, verify the failed creation left no entry, and prove the
            // same filesystem accepts and round-trips a valid Unicode name.
            var iterator = tmp.dir.iterate();
            try std.testing.expectEqual(@as(?std.Io.Dir.Entry, null), try iterator.next(io));
            try tmp.dir.writeFile(io, .{ .sub_path = "valid-Ω", .data = "original-byte-name" });
            const valid = try tmp.dir.readFileAlloc(io, "valid-Ω", gpa, .limited(64));
            defer gpa.free(valid);
            try std.testing.expectEqualStrings("original-byte-name", valid);
            return;
        },
        else => return err,
    };
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    var server = try Server.init(gpa, io, buffer[0..length], null);
    defer server.deinit();
    var opened = try call(&server, .{ .op = "opendir", .path = buffer[0..length] }, "");
    defer opened.deinit();
    const value = try parsedSuccess(&opened);
    defer value.deinit();
    var listed = try call(&server, .{ .op = "readdir", .handle = value.value.object.get("handle").?, .max = 10 }, "");
    defer listed.deinit();
    const list = try parsedSuccess(&listed);
    defer list.deinit();
    const entries = list.value.object.get("entries").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), entries.len);
    try std.testing.expectEqualStrings("bad-\xef\xbf\xbd", entries[0].object.get("name").?.string);
    try std.testing.expectEqualStrings("ENOENT", entries[0].object.get("error").?.object.get("code").?.string);
    const raw = entries[0].object.get("raw").?.array.items;
    try std.testing.expectEqual(@as(usize, 5), raw.len);
    try std.testing.expectEqual(@as(i64, 255), raw[4].integer);
}
test "native remote file dispatch matches captured original daemon scans bytes retained handles and error codes" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const captured = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/windows-daemon-b78.json"), .{});
    defer captured.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    var server = try Server.init(gpa, io, buffer[0..length], null);
    defer server.deinit();
    const path = try std.fs.path.join(gpa, &.{ buffer[0..length], "nested", "bytes.txt" });
    defer gpa.free(path);
    const renamed = try std.fs.path.join(gpa, &.{ buffer[0..length], "renamed.txt" });
    defer gpa.free(renamed);
    const data = [_]u8{ 239, 187, 191, 65, 13, 10, 240, 159, 154, 128, 10, 255, 66, 10 };
    var written = try call(&server, .{ .op = "write", .path = path, .append = false }, &data);
    defer written.deinit();
    var write_result = try parsedSuccess(&written);
    write_result.deinit();
    var opened = try call(&server, .{ .op = "open", .path = path, .noFollow = true }, "");
    defer opened.deinit();
    const open_result = try parsedSuccess(&opened);
    defer open_result.deinit();
    const id = open_result.value.object.get("handle").?.integer;
    const actual_info = open_result.value.object.get("info").?.object;
    const expected_info = captured.value.object.get("fileInfo").?.object;
    try std.testing.expectEqualStrings(expected_info.get("name").?.string, actual_info.get("name").?.string);
    try std.testing.expectEqualStrings(expected_info.get("kind").?.string, actual_info.get("kind").?.string);
    try std.testing.expectEqual(expected_info.get("size").?.integer, actual_info.get("size").?.integer);
    for (captured.value.object.get("scans").?.array.items) |case| {
        const range = case.object.get("range").?.object;
        var reply = if (range.get("endLine")) |end|
            try call(&server, .{ .op = "scanLines", .handle = id, .startLine = range.get("startLine").?, .endLine = end }, "")
        else
            try call(&server, .{ .op = "scanLines", .handle = id, .startLine = range.get("startLine").? }, "");
        defer reply.deinit();
        const scan = try parsedSuccess(&reply);
        defer scan.deinit();
        var expected = case.object.get("scan").?.object.iterator();
        while (expected.next()) |entry| try std.testing.expectEqual(entry.value_ptr.integer, scan.value.object.get(entry.key_ptr.*).?.integer);
    }
    for (captured.value.object.get("binary").?.array.items) |case| {
        var reply = try call(&server, .{ .op = "pread", .handle = id, .offset = case.object.get("offset").?, .length = case.object.get("length").? }, "");
        defer reply.deinit();
        const result = try parsedSuccess(&reply);
        result.deinit();
        const expected = case.object.get("bytes").?.array.items;
        try std.testing.expectEqual(expected.len, reply.payload.len);
        for (expected, reply.payload) |wanted, byte| try std.testing.expectEqual(@as(u8, @intCast(wanted.integer)), byte);
    }
    var moved = try call(&server, .{ .op = "rename", .path = path, .to = renamed }, "");
    defer moved.deinit();
    const moved_result = try parsedSuccess(&moved);
    moved_result.deinit();
    var retained = try call(&server, .{ .op = "pread", .handle = id, .offset = 0, .length = 100 }, "");
    defer retained.deinit();
    try std.testing.expectEqualSlices(u8, &data, retained.payload);
    var closed = try call(&server, .{ .op = "close", .handle = id }, "");
    defer closed.deinit();
    try std.testing.expectEqual(@as(u32, 0), server.handles.count());
    var missing_handle = try call(&server, .{ .op = "pread", .handle = id, .offset = 0, .length = 1 }, "");
    defer missing_handle.deinit();
    const missing = try std.json.parseFromSlice(std.json.Value, gpa, missing_handle.json, .{});
    defer missing.deinit();
    try std.testing.expectEqualStrings("EBADF", missing.value.object.get("code").?.string);
    var absent = try call(&server, .{ .op = "lstat", .path = path }, "");
    defer absent.deinit();
    const absent_result = try std.json.parseFromSlice(std.json.Value, gpa, absent.json, .{});
    defer absent_result.deinit();
    try std.testing.expectEqualStrings("ENOENT", absent_result.value.object.get("code").?.string);
    var directory = try call(&server, .{ .op = "rm", .path = buffer[0..length], .recursive = false, .force = false }, "");
    defer directory.deinit();
    const directory_result = try std.json.parseFromSlice(std.json.Value, gpa, directory.json, .{});
    defer directory_result.deinit();
    try std.testing.expectEqualStrings("ERR_FS_EISDIR", directory_result.value.object.get("code").?.string);
}
pub fn errorCode(err: anyerror) []const u8 {
    return switch (err) {
        error.FileNotFound => "ENOENT",
        error.NotDir => "ENOTDIR",
        error.IsDir => "EISDIR",
        error.PathAlreadyExists => "EEXIST",
        error.DirNotEmpty => "ENOTEMPTY",
        error.NameTooLong => "ENAMETOOLONG",
        error.AccessDenied => if (builtin.os.tag == .windows) "EPERM" else "EACCES",
        error.PermissionDenied => "EPERM",
        error.BadFileDescriptor, error.BadHandle => "EBADF",
        error.InvalidArgument, error.BadPathName, error.InvalidField => "EINVAL",
        error.SymLinkLoop => "ELOOP",
        error.OutOfMemory => "ENOMEM",
        error.Canceled => "aborted",
        error.OperationUnsupported => "ENOTSUP",
        error.TooManyHandles => "EMFILE",
        else => "UNKNOWN",
    };
}
const Directory = struct {
    directory: std.Io.Dir,
    iterator: std.Io.Dir.Iterator,
    path: []u8,
    fn deinit(self: *Directory, gpa: std.mem.Allocator, io: std.Io) void {
        self.directory.close(io);
        gpa.free(self.path);
    }
};
const FileHandle = struct {
    reader: fs.BinaryReader,
    failed: bool = false,
    append: bool = false,
};
test "retained write chunks stay on the opened inode and poisoned writes reject later chunks" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    var server = try Server.init(gpa, io, buffer[0..length], null);
    defer server.deinit();
    const path = try std.fs.path.join(gpa, &.{ buffer[0..length], "nested", "written" });
    defer gpa.free(path);
    const moved = try std.fs.path.join(gpa, &.{ buffer[0..length], "moved" });
    defer gpa.free(moved);
    var first = try call(&server, .{ .op = "write", .path = path, .keep = true }, "first");
    defer first.deinit();
    const result = try parsedSuccess(&first);
    defer result.deinit();
    const id = result.value.object.get("handle").?.integer;
    var renamed = try call(&server, .{ .op = "rename", .path = path, .to = moved }, "");
    defer renamed.deinit();
    const renamed_result = try parsedSuccess(&renamed);
    renamed_result.deinit();
    var replacement = try call(&server, .{ .op = "write", .path = path }, "replacement");
    defer replacement.deinit();
    var chunk = try call(&server, .{ .op = "writeChunk", .handle = id }, "-second");
    defer chunk.deinit();
    const chunk_result = try parsedSuccess(&chunk);
    chunk_result.deinit();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, moved, gpa, .limited(128));
    defer gpa.free(bytes);
    try std.testing.expectEqualStrings("first-second", bytes);
    var closed = try call(&server, .{ .op = "close", .handle = id }, "");
    defer closed.deinit();
    const absent = try std.fs.path.join(gpa, &.{ buffer[0..length], "missing", "child" });
    defer gpa.free(absent);
    var missing_parent = try call(&server, .{ .op = "write", .path = absent, .parents = false }, "refused");
    defer missing_parent.deinit();
    try std.testing.expectEqual(frame.Kind.remote_error, missing_parent.kind);
    var readonly = try call(&server, .{ .op = "open", .path = path }, "");
    defer readonly.deinit();
    const opened = try parsedSuccess(&readonly);
    defer opened.deinit();
    const read_id = opened.value.object.get("handle").?.integer;
    var failed = try call(&server, .{ .op = "writeChunk", .handle = read_id }, "invalid");
    defer failed.deinit();
    try std.testing.expectEqual(frame.Kind.remote_error, failed.kind);
    var poisoned = try call(&server, .{ .op = "writeChunk", .handle = read_id }, "later");
    defer poisoned.deinit();
    const failure = try std.json.parseFromSlice(std.json.Value, gpa, poisoned.json, .{});
    defer failure.deinit();
    try std.testing.expectEqualStrings("EBADF", failure.value.object.get("code").?.string);
}
test "whole-file read handles retain platform cursor semantics captured from the original daemon" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "input", .data = "abcdef" });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    var server = try Server.init(gpa, io, buffer[0..length], null);
    defer server.deinit();
    const path = try std.fs.path.join(gpa, &.{ buffer[0..length], "input" });
    defer gpa.free(path);
    var opened = try call(&server, .{ .op = "open", .path = path, .mode = "read" }, "");
    defer opened.deinit();
    const info = try parsedSuccess(&opened);
    defer info.deinit();
    try std.testing.expectEqualStrings("file", info.value.object.get("stat").?.object.get("kind").?.string);
    const id = info.value.object.get("handle").?.integer;
    var first = try call(&server, .{ .op = "pread", .handle = id, .length = 2 }, "");
    defer first.deinit();
    try std.testing.expectEqualStrings("ab", first.payload);
    var positioned = try call(&server, .{ .op = "pread", .handle = id, .offset = 4, .length = 2 }, "");
    defer positioned.deinit();
    try std.testing.expectEqualStrings("ef", positioned.payload);
    var next = try call(&server, .{ .op = "pread", .handle = id, .length = 8 }, "");
    defer next.deinit();
    const next_result = try parsedSuccess(&next);
    next_result.deinit();
    // Rust's Windows seek_read advances the shared native cursor. POSIX pread
    // preserves it. This is an upstream platform distinction, not a normalized API.
    try std.testing.expectEqualStrings(if (builtin.os.tag == .windows) "" else "cdef", next.payload);
    var end = try call(&server, .{ .op = "pread", .handle = id, .length = 8 }, "");
    defer end.deinit();
    const end_result = try parsedSuccess(&end);
    end_result.deinit();
    try std.testing.expectEqual(@as(usize, 0), end.payload.len);
    var directory = try call(&server, .{ .op = "open", .path = buffer[0..length], .mode = "read" }, "");
    defer directory.deinit();
    const dir_info = try parsedSuccess(&directory);
    defer dir_info.deinit();
    var refused = try call(&server, .{ .op = "pread", .handle = dir_info.value.object.get("handle").?, .length = 8 }, "");
    defer refused.deinit();
    const failure = try std.json.parseFromSlice(std.json.Value, gpa, refused.json, .{});
    defer failure.deinit();
    try std.testing.expectEqualStrings("EISDIR", failure.value.object.get("code").?.string);
}
fn retainedWriteAllocation(gpa: std.mem.Allocator, path: []const u8) !void {
    var server = try Server.init(gpa, std.testing.io, std.fs.path.dirname(path).?, null);
    defer server.deinit();
    var reply = try call(&server, .{ .op = "write", .path = path, .keep = true }, "allocation");
    defer reply.deinit();
    const value = try parsedSuccess(&reply);
    defer value.deinit();
    var chunk = try call(&server, .{ .op = "writeChunk", .handle = value.value.object.get("handle").? }, "-chunk");
    defer chunk.deinit();
}
test "retained write handle admission releases ownership at every allocation failure" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(std.testing.io, &buffer);
    const path = try std.fs.path.join(gpa, &.{ buffer[0..length], "allocation" });
    defer gpa.free(path);
    try std.testing.checkAllAllocationFailures(gpa, retainedWriteAllocation, .{path});
}
const Handle = union(enum) {
    file: FileHandle,
    directory: Directory,
    fn deinit(self: *Handle, gpa: std.mem.Allocator, io: std.Io) void {
        switch (self.*) {
            .file => |*file| file.reader.deinit(),
            .directory => |*directory| directory.deinit(gpa, io),
        }
    }
};
const Lease = struct {
    handle: *Handle,
    references: std.atomic.Value(usize) = .init(1),
    mutex: std.Io.Mutex = .init,
    fn release(self: *Lease, gpa: std.mem.Allocator, io: std.Io) void {
        if (self.references.fetchSub(1, .acq_rel) != 1) return;
        self.handle.deinit(gpa, io);
        gpa.destroy(self.handle);
        gpa.destroy(self);
    }
};
const FileLease = struct {
    lease: *Lease,
    reader: *fs.BinaryReader,
    server: *Server,
    locked: bool,
    fn deinit(self: FileLease) void {
        const owner = self.server;
        if (self.locked) self.lease.mutex.unlock(owner.filesystem.io);
        self.lease.release(owner.filesystem.gpa, owner.filesystem.io);
    }
};
pub const Server = struct {
    filesystem: fs.FileSystem,
    handles: std.AutoHashMap(u64, *Lease),
    registry_mutex: std.Io.Mutex = .init,
    next_handle: u64 = 1,
    pub fn init(gpa: std.mem.Allocator, io: std.Io, cwd: []const u8, home: ?[]const u8) !Server {
        return .{ .filesystem = try fs.FileSystem.init(gpa, io, cwd, home), .handles = .init(gpa) };
    }
    pub fn deinit(self: *Server) void {
        var iterator = self.handles.valueIterator();
        while (iterator.next()) |handle| {
            handle.*.release(self.filesystem.gpa, self.filesystem.io);
        }
        self.handles.deinit();
        self.filesystem.deinit();
    }
    fn text(json: std.json.Value, name: []const u8) ![]const u8 {
        if (json != .object) return error.InvalidField;
        const value = json.object.get(name) orelse return error.InvalidField;
        if (value != .string or std.mem.indexOfScalar(u8, value.string, 0) != null) return error.InvalidField;
        return value.string;
    }
    fn number(json: std.json.Value, name: []const u8) !u64 {
        if (json != .object) return error.InvalidField;
        const value = json.object.get(name) orelse return error.InvalidField;
        if (value != .integer or value.integer < 0) return error.InvalidField;
        return @intCast(value.integer);
    }
    fn boolean(json: std.json.Value, name: []const u8) bool {
        const value = json.object.get(name) orelse return false;
        return value == .bool and value.bool;
    }
    fn retain(self: *Server, json: std.json.Value) !*Lease {
        const id = try number(json, "handle");
        self.registry_mutex.lockUncancelable(self.filesystem.io);
        defer self.registry_mutex.unlock(self.filesystem.io);
        const lease = self.handles.get(id) orelse return error.BadHandle;
        _ = lease.references.fetchAdd(1, .monotonic);
        return lease;
    }
    fn file(self: *Server, json: std.json.Value, locked: bool) !FileLease {
        const lease = try self.retain(json);
        errdefer lease.release(self.filesystem.gpa, self.filesystem.io);
        if (lease.handle.* != .file) return error.BadHandle;
        if (locked) lease.mutex.lockUncancelable(self.filesystem.io);
        return .{ .lease = lease, .reader = &lease.handle.file.reader, .server = self, .locked = locked };
    }
    fn admit(self: *Server, handle: *Handle) !u64 {
        // Caller holds the registry lock while constructing the matching reply.
        if (self.handles.count() >= 4096) return error.TooManyHandles;
        if (self.next_handle >= 9007199254740991) return error.HandleIdentityExhausted;
        const id = self.next_handle;
        const lease = try self.filesystem.gpa.create(Lease);
        errdefer self.filesystem.gpa.destroy(lease);
        lease.* = .{ .handle = handle };
        try self.handles.putNoClobber(id, lease);
        self.next_handle += 1;
        return id;
    }
    fn operationFailure(self: *Server, failure: types.FileError) !Reply {
        var owned = failure;
        defer owned.deinit(self.filesystem.gpa);
        return Reply.failure(self.filesystem.gpa, if (failure.code == .aborted) "aborted" else errorCode(failure.cause orelse error.InvalidArgument), failure.cause orelse error.InvalidArgument, failure.path);
    }
    fn plain(self: *Server, outcome: types.Result(void)) !Reply {
        return switch (outcome) {
            .value => Reply.success(self.filesystem.gpa, std.json.Value{ .object = .empty }),
            .failure => |err| self.operationFailure(err),
        };
    }
    pub fn dispatch(self: *Server, json: std.json.Value, payload: []const u8, context: types.Context) !Reply {
        return self.operation(json, payload, context) catch |err| {
            if (err == error.OutOfMemory) return err;
            const path: ?[]const u8 = if (json == .object) if (json.object.get("path")) |value| if (value == .string) value.string else null else null else null;
            return Reply.failure(self.filesystem.gpa, errorCode(err), err, path);
        };
    }
    fn operation(self: *Server, json: std.json.Value, payload: []const u8, context: types.Context) !Reply {
        const gpa = self.filesystem.gpa;
        const io = self.filesystem.io;
        const op = try text(json, "op");
        if (context.aborted()) return Reply.failure(gpa, "aborted", error.Canceled, null);
        if (std.mem.eql(u8, op, "close")) {
            const id = try number(json, "handle");
            self.registry_mutex.lockUncancelable(io);
            const removed = self.handles.fetchRemove(id);
            self.registry_mutex.unlock(io);
            if (removed) |entry| entry.value.release(gpa, io);
            return Reply.success(gpa, std.json.Value{ .object = .empty });
        }
        if (std.mem.eql(u8, op, "writeChunk")) {
            const leased = try self.file(json, true);
            defer leased.deinit();
            const handle = leased.lease.handle;
            if (handle.* != .file or handle.file.failed) return error.BadHandle;
            const target = handle.file.reader.file orelse return error.BadHandle;
            self.writeBytes(target, payload, handle.file.append) catch |err| {
                handle.file.failed = true;
                return err;
            };
            return Reply.success(gpa, std.json.Value{ .object = .empty });
        }
        if (std.mem.eql(u8, op, "pread")) {
            const positional = json.object.get("offset");
            const leased = try self.file(json, builtin.os.tag == .windows or positional == null or positional.? != .integer or positional.?.integer < 0);
            defer leased.deinit();
            const reader = leased.reader;
            const count = @min(try number(json, "length"), frame.maximum_payload);
            const offset = json.object.get("offset");
            if (offset == null or offset.? != .integer or offset.?.integer < 0) {
                const target = reader.file orelse return error.BadHandle;
                var info = try metadata.fstat(gpa, io, reader.path, target);
                defer info.deinit(gpa);
                if (info.kind == .directory) return error.IsDir;
                const bytes = try gpa.alloc(u8, @intCast(count));
                defer gpa.free(bytes);
                const read = if (bytes.len == 0) 0 else target.readStreaming(io, &.{bytes}) catch |err| switch (err) {
                    error.EndOfStream => 0,
                    else => return err,
                };
                var reply = try Reply.success(gpa, std.json.Value{ .object = .empty });
                errdefer reply.deinit();
                reply.payload = try gpa.dupe(u8, bytes[0..read]);
                return reply;
            }
            const result = try reader.read(@intCast(offset.?.integer), count, context);
            if (result == .failure) return self.operationFailure(result.failure);
            errdefer gpa.free(result.value);
            var reply = try Reply.success(gpa, std.json.Value{ .object = .empty });
            reply.payload = result.value;
            return reply;
        }
        if (std.mem.eql(u8, op, "fstat")) {
            const leased = try self.file(json, false);
            defer leased.deinit();
            const reader = leased.reader;
            var info = try metadata.fstat(gpa, io, reader.path, reader.file orelse return error.BadHandle);
            defer info.deinit(gpa);
            return Reply.success(gpa, info);
        }
        if (std.mem.eql(u8, op, "scanLines")) {
            const leased = try self.file(json, false);
            defer leased.deinit();
            const reader = leased.reader;
            const options: @import("../durable/line_scan.zig").Options = .{ .startLine = try number(json, "startLine"), .endLine = if (json.object.contains("endLine")) try number(json, "endLine") else null };
            const result = try reader.scanLines(options, context);
            return switch (result) {
                .value => |value| Reply.success(gpa, value),
                .failure => |err| self.operationFailure(err),
            };
        }
        if (std.mem.eql(u8, op, "readdir")) return self.readDirectory(json, context);
        const path = try text(json, "path");
        if (!std.fs.path.isAbsolute(path)) return error.InvalidField;
        if (std.mem.eql(u8, op, "lstat")) {
            var info = try metadata.lstat(gpa, io, path);
            defer info.deinit(gpa);
            return Reply.success(gpa, info);
        }
        if (std.mem.eql(u8, op, "open")) {
            const mode = json.object.get("mode");
            if (mode != null and mode.? == .string and std.mem.eql(u8, mode.?.string, "read")) {
                const target = try std.Io.Dir.cwd().openFile(io, path, .{ .allow_directory = true });
                var transferred = false;
                defer if (!transferred) target.close(io);
                const owned_path = try gpa.dupe(u8, path);
                errdefer gpa.free(owned_path);
                const handle = try gpa.create(Handle);
                errdefer gpa.destroy(handle);
                handle.* = .{ .file = .{ .reader = .{ .gpa = gpa, .io = io, .path = owned_path, .file = target } } };
                self.registry_mutex.lockUncancelable(io);
                defer self.registry_mutex.unlock(io);
                var reply = if (metadata.fstat(gpa, io, path, target)) |value| block: {
                    var info = value;
                    defer info.deinit(gpa);
                    break :block try Reply.success(gpa, .{ .handle = self.next_handle, .stat = info });
                } else |err| try Reply.success(gpa, .{ .handle = self.next_handle, .statError = .{ .code = errorCode(err), .message = @errorName(err), .path = path } });
                errdefer reply.deinit();
                _ = try self.admit(handle);
                transferred = true;
                return reply;
            }
            const result = try self.filesystem.openBinaryReader(path, .{ .noFollow = boolean(json, "noFollow") }, context);
            if (result == .failure) return self.operationFailure(result.failure);
            var owned = result.value;
            errdefer owned.deinit();
            const handle = try gpa.create(Handle);
            errdefer gpa.destroy(handle);
            handle.* = .{ .file = .{ .reader = owned } };
            var info = try metadata.fstat(gpa, io, path, handle.file.reader.file.?);
            defer info.deinit(gpa);
            self.registry_mutex.lockUncancelable(io);
            defer self.registry_mutex.unlock(io);
            if (self.next_handle >= 9007199254740991) return error.HandleIdentityExhausted;
            var reply = try Reply.success(gpa, .{ .handle = self.next_handle, .info = info });
            errdefer reply.deinit();
            _ = try self.admit(handle);
            return reply;
        }
        if (std.mem.eql(u8, op, "opendir")) {
            const directory = try std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
            errdefer directory.close(io);
            const owned = try gpa.dupe(u8, path);
            errdefer gpa.free(owned);
            const handle = try gpa.create(Handle);
            errdefer gpa.destroy(handle);
            handle.* = .{ .directory = .{ .directory = directory, .iterator = directory.iterate(), .path = owned } };
            self.registry_mutex.lockUncancelable(io);
            defer self.registry_mutex.unlock(io);
            if (self.next_handle >= 9007199254740991) return error.HandleIdentityExhausted;
            var reply = try Reply.success(gpa, .{ .handle = self.next_handle });
            errdefer reply.deinit();
            _ = try self.admit(handle);
            return reply;
        }
        if (std.mem.eql(u8, op, "write")) return self.write(json, path, payload);
        if (std.mem.eql(u8, op, "truncate")) return self.plain(try self.filesystem.truncateFile(path, try number(json, "size"), context));
        if (std.mem.eql(u8, op, "fsync")) return self.plain(try self.filesystem.flushFile(path, context));
        if (std.mem.eql(u8, op, "rename")) return self.plain(try self.filesystem.renameFile(path, try text(json, "to"), context));
        if (std.mem.eql(u8, op, "mkdir")) return self.plain(try self.filesystem.createDir(path, .{ .recursive = boolean(json, "recursive") }, context));
        if (std.mem.eql(u8, op, "rm")) {
            if (!boolean(json, "recursive")) {
                var info = metadata.lstat(gpa, io, path) catch |err| {
                    if (err == error.FileNotFound and boolean(json, "force")) return Reply.success(gpa, std.json.Value{ .object = .empty });
                    return err;
                };
                defer info.deinit(gpa);
                if (info.kind == .directory) return Reply.failure(gpa, "ERR_FS_EISDIR", error.IsDir, path);
            }
            return self.plain(try self.filesystem.remove(path, .{ .recursive = boolean(json, "recursive"), .force = boolean(json, "force") }, context));
        }
        if (std.mem.eql(u8, op, "realpath")) {
            const result = try self.filesystem.canonicalPath(path, context);
            if (result == .failure) return self.operationFailure(result.failure);
            defer gpa.free(result.value);
            return Reply.success(gpa, .{ .path = result.value });
        }
        if (std.mem.eql(u8, op, "mkdtemp")) {
            const alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
            for (0..128) |_| {
                var random: [6]u8 = undefined;
                try io.randomSecure(&random);
                var suffix: [6]u8 = undefined;
                for (random, 0..) |byte, index| suffix[index] = alphabet[byte % alphabet.len];
                const temporary = try std.fmt.allocPrint(gpa, "{s}{s}", .{ path, suffix });
                defer gpa.free(temporary);
                std.Io.Dir.cwd().createDir(io, temporary, @enumFromInt(0o700)) catch |err| {
                    if (err == error.PathAlreadyExists) continue;
                    return err;
                };
                errdefer std.Io.Dir.cwd().deleteDir(io, temporary) catch {};
                return Reply.success(gpa, .{ .path = temporary });
            }
            return error.PathAlreadyExists;
        }
        return error.InvalidField;
    }
    fn writeBytes(self: *Server, target: std.Io.File, payload: []const u8, append: bool) !void {
        if (append and builtin.os.tag == .windows) return fs.appendWindows(target, payload);
        try target.writeStreamingAll(self.filesystem.io, payload);
    }
    fn write(self: *Server, json: std.json.Value, path: []const u8, payload: []const u8) !Reply {
        const gpa = self.filesystem.gpa;
        const io = self.filesystem.io;
        const parents_value = json.object.get("parents");
        const parents = if (parents_value) |value| if (value == .bool) value.bool else true else true;
        if (parents) if (std.fs.path.dirname(path)) |parent| try std.Io.Dir.cwd().createDirPath(io, parent);
        const append = boolean(json, "append");
        const target = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = !append });
        var transferred = false;
        defer if (!transferred) target.close(io);
        if (append and builtin.os.tag != .windows) {
            const flags = std.posix.system.fcntl(target.handle, std.posix.F.GETFL, @as(usize, 0));
            if (std.posix.errno(flags) != .SUCCESS) return error.AppendFlagsFailed;
            const mask: u32 = @bitCast(std.posix.O{ .APPEND = true });
            if (std.posix.errno(std.posix.system.fcntl(target.handle, std.posix.F.SETFL, @as(usize, @intCast(flags)) | mask)) != .SUCCESS) return error.AppendFlagsFailed;
        }
        try self.writeBytes(target, payload, append);
        if (!boolean(json, "keep")) return Reply.success(gpa, std.json.Value{ .object = .empty });
        const owned_path = try gpa.dupe(u8, path);
        errdefer gpa.free(owned_path);
        const handle = try gpa.create(Handle);
        errdefer gpa.destroy(handle);
        handle.* = .{ .file = .{ .reader = .{ .gpa = gpa, .io = io, .path = owned_path, .file = target }, .append = append } };
        self.registry_mutex.lockUncancelable(io);
        defer self.registry_mutex.unlock(io);
        var reply = try Reply.success(gpa, .{ .handle = self.next_handle });
        errdefer reply.deinit();
        _ = try self.admit(handle);
        transferred = true;
        return reply;
    }
    fn readDirectory(self: *Server, json: std.json.Value, context: types.Context) !Reply {
        const gpa = self.filesystem.gpa;
        const io = self.filesystem.io;
        const lease = try self.retain(json);
        defer lease.release(gpa, io);
        lease.mutex.lockUncancelable(io);
        defer lease.mutex.unlock(io);
        const handle = lease.handle;
        if (handle.* != .directory) return error.BadHandle;
        const maximum = @min(try number(json, "max"), 4096);
        if (maximum == 0) return error.InvalidField;
        const Entry = struct { name: []const u8, raw: ?[]u16 = null, info: ?metadata.Info = null, @"error": ?struct { code: []const u8, message: []const u8 } = null };
        var entries: std.ArrayList(Entry) = .empty;
        defer {
            for (entries.items) |*entry| {
                gpa.free(entry.name);
                if (entry.raw) |raw| gpa.free(raw);
                if (entry.info) |*info| info.deinit(gpa);
            }
            entries.deinit(gpa);
        }
        var done = false;
        while (entries.items.len < maximum) {
            if (context.aborted()) return Reply.failure(gpa, "aborted", error.Canceled, handle.directory.path);
            const entry = (try handle.directory.iterator.next(io)) orelse {
                done = true;
                break;
            };
            const name = try lossyName(gpa, entry.name);
            errdefer gpa.free(name);
            const raw: ?[]u16 = if (!std.mem.eql(u8, name, entry.name)) block: {
                const values = try gpa.alloc(u16, entry.name.len);
                for (entry.name, values) |byte, *value| value.* = byte;
                break :block values;
            } else null;
            errdefer if (raw) |values| gpa.free(values);
            // Node stats the decoded path, so an invalid original byte name
            // normally becomes ENOENT while raw preserves libuv's sort input.
            const path = try std.fs.path.join(gpa, &.{ handle.directory.path, name });
            defer gpa.free(path);
            const info = metadata.lstat(gpa, io, path) catch |err| {
                try entries.append(gpa, .{ .name = name, .raw = raw, .@"error" = .{ .code = errorCode(err), .message = @errorName(err) } });
                continue;
            };
            var owned = info;
            errdefer owned.deinit(gpa);
            try entries.append(gpa, .{ .name = name, .raw = raw, .info = info });
        }
        return Reply.success(gpa, .{ .entries = entries.items, .done = done });
    }
};
test "native remote directory paging temporary directories and truncate preserve daemon fields" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    var server = try Server.init(gpa, io, buffer[0..length], null);
    defer server.deinit();
    const path = try std.fs.path.join(gpa, &.{ buffer[0..length], "file" });
    defer gpa.free(path);
    var written = try call(&server, .{ .op = "write", .path = path, .append = false }, "abc");
    defer written.deinit();
    var appended = try call(&server, .{ .op = "write", .path = path, .append = true }, "def");
    defer appended.deinit();
    var truncated = try call(&server, .{ .op = "truncate", .path = path, .size = 8 }, "");
    defer truncated.deinit();
    var flushed = try call(&server, .{ .op = "fsync", .path = path }, "");
    defer flushed.deinit();
    const bytes = try tmp.dir.readFileAlloc(io, "file", gpa, .limited(100));
    defer gpa.free(bytes);
    try std.testing.expectEqualSlices(u8, "abcdef\x00\x00", bytes);
    var opened = try call(&server, .{ .op = "opendir", .path = buffer[0..length] }, "");
    defer opened.deinit();
    const value = try parsedSuccess(&opened);
    defer value.deinit();
    const id = value.value.object.get("handle").?.integer;
    var seen: usize = 0;
    while (true) {
        var page = try call(&server, .{ .op = "readdir", .handle = id, .max = 1 }, "");
        defer page.deinit();
        const decoded = try parsedSuccess(&page);
        defer decoded.deinit();
        for (decoded.value.object.get("entries").?.array.items) |entry| {
            try std.testing.expect(entry.object.get("error") == null);
            try std.testing.expectEqualStrings("file", entry.object.get("name").?.string);
            try std.testing.expectEqual(@as(i64, 8), entry.object.get("info").?.object.get("size").?.integer);
            seen += 1;
        }
        if (decoded.value.object.get("done").?.bool) break;
    }
    try std.testing.expectEqual(@as(usize, 1), seen);
    const prefix = try std.fs.path.join(gpa, &.{ buffer[0..length], "owned-" });
    defer gpa.free(prefix);
    var temporary = try call(&server, .{ .op = "mkdtemp", .path = prefix }, "");
    defer temporary.deinit();
    const created = try parsedSuccess(&temporary);
    defer created.deinit();
    const directory = created.value.object.get("path").?.string;
    try std.testing.expect(std.mem.startsWith(u8, directory, prefix));
    try std.testing.expectEqual(prefix.len + 6, directory.len);
    if (builtin.os.tag != .windows) {
        const info = try std.Io.Dir.cwd().statFile(io, directory, .{});
        try std.testing.expectEqual(@as(u32, 0o700), @as(u32, @intCast(@intFromEnum(info.permissions))) & 0o777);
    }
    var removed = try call(&server, .{ .op = "rm", .path = directory, .recursive = true, .force = false }, "");
    defer removed.deinit();
    const removal = try parsedSuccess(&removed);
    removal.deinit();
}
fn allocationCase(gpa: std.mem.Allocator, path: []const u8) !void {
    var server = try Server.init(gpa, std.testing.io, std.fs.path.dirname(path).?, null);
    defer server.deinit();
    var opened = try call(&server, .{ .op = "open", .path = path, .noFollow = true }, "");
    defer opened.deinit();
    const value = try std.json.parseFromSlice(std.json.Value, gpa, opened.json, .{});
    defer value.deinit();
    if (opened.kind == .result) {
        var read = try call(&server, .{ .op = "pread", .handle = value.value.object.get("handle").?, .offset = 0, .length = 64 }, "");
        defer read.deinit();
    }
}
test "native remote handle admission and detached reply allocation failures release ownership" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "file", .data = "owned-remote" });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    const path = try std.fs.path.join(gpa, &.{ buffer[0..length], "file" });
    defer gpa.free(path);
    try std.testing.checkAllAllocationFailures(gpa, allocationCase, .{path});
}
