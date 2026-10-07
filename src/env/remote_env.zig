//! Native RemoteExecutionEnv client adapters. Returned values own their bytes.
const std = @import("std");
const wire = @import("frame.zig");
const native = @import("connection.zig");
const lazy = @import("lazy_connection.zig");
const paths = @import("remote_path.zig");
const types = @import("../durable/types.zig");
const fs = @import("../durable/filesystem.zig");
const decode = @import("../durable/decode.zig");
const scan = @import("../durable/line_scan.zig");
const shell = @import("../durable/shell.zig");
const watching = @import("../durable/watch.zig");
const remote_watching = @import("remote_watch.zig");
pub const Transport = union(enum) {
    native: *native.Connection,
    lazy: *lazy.Connection,
    pub fn begin(self: Transport, value: anytype, payload: []const u8, session: ?u64) !native.Ticket {
        return switch (self) {
            .native => |connection| connection.begin(value, payload, session),
            .lazy => |connection| connection.begin(value, payload, session),
        };
    }
};
pub const Options = struct { connection: Transport, id: []const u8, cwd: []const u8, shellPath: ?[]const u8 = null, shellEnv: ?*const std.process.Environ.Map = null, watch: remote_watching.Options = .{} };
const read_chunk = 256 * 1024;
const file_chunk = 512 * 1024;
const depth = 8;
fn string(value: std.json.Value, field: []const u8) ![]const u8 {
    if (value != .object) return error.InvalidDaemonJson;
    const entry = value.object.get(field) orelse return error.InvalidDaemonJson;
    return if (entry == .string) entry.string else error.InvalidDaemonJson;
}
fn number(value: std.json.Value, field: []const u8) !u64 {
    if (value != .object) return error.InvalidDaemonJson;
    const entry = value.object.get(field) orelse return error.InvalidDaemonJson;
    return if (entry == .integer and entry.integer >= 0) @intCast(entry.integer) else error.InvalidDaemonJson;
}
fn numeric(value: std.json.Value, field: []const u8) !f64 {
    if (value != .object) return error.InvalidDaemonJson;
    const entry = value.object.get(field) orelse return error.InvalidDaemonJson;
    return switch (entry) {
        .integer => |n| @floatFromInt(n),
        .float => |n| n,
        else => error.InvalidDaemonJson,
    };
}
fn errorCode(code: []const u8) types.FileErrorCode {
    const mappings = .{ .{ "aborted", types.FileErrorCode.aborted }, .{ "ENOENT", types.FileErrorCode.not_found }, .{ "EACCES", types.FileErrorCode.permission_denied }, .{ "EPERM", types.FileErrorCode.permission_denied }, .{ "ENOTDIR", types.FileErrorCode.not_directory }, .{ "EISDIR", types.FileErrorCode.is_directory }, .{ "EINVAL", types.FileErrorCode.invalid }, .{ "SYMLINK", types.FileErrorCode.invalid }, .{ "NOT_REGULAR", types.FileErrorCode.invalid } };
    inline for (mappings) |entry| if (std.mem.eql(u8, code, entry[0])) return entry[1];
    return .unknown;
}
pub fn remoteFailure(comptime T: type, gpa: std.mem.Allocator, json: std.json.Value, fallback: ?[]const u8) !types.Result(T) {
    const code = errorCode(try string(json, "code"));
    const message = try gpa.dupe(u8, try string(json, "message"));
    errdefer gpa.free(message);
    const path = if (json.object.get("path")) |value| if (value == .string) value.string else fallback else fallback;
    var result = try types.failure(T, gpa, code, path, null, message);
    result.failure.message_owned = true;
    return result;
}
fn checked(comptime T: type, gpa: std.mem.Allocator, reply: wire.Frame, path: ?[]const u8) !?types.Result(T) {
    if (reply.kind == .remote_error) return try remoteFailure(T, gpa, reply.json.value, path);
    if (reply.kind != .result) return error.UnexpectedDaemonFrame;
    return null;
}
fn toInfo(gpa: std.mem.Allocator, platform: paths.Platform, path: []const u8, value: std.json.Value) !types.Result(types.FileInfo) {
    const remote_kind = try string(value, "kind");
    const kind: types.FileKind = if (std.mem.eql(u8, remote_kind, "file")) .file else if (std.mem.eql(u8, remote_kind, "directory")) .directory else if (std.mem.eql(u8, remote_kind, "symlink")) .symlink else return types.failure(types.FileInfo, gpa, .invalid, path, null, "Unsupported file type");
    const name = try gpa.dupe(u8, paths.basename(platform, path));
    errdefer gpa.free(name);
    const owned_path = try gpa.dupe(u8, path);
    errdefer gpa.free(owned_path);
    return .{ .value = .{ .name = name, .path = owned_path, .kind = kind, .size = try number(value, "size"), .mtimeMs = (try numeric(value, "mtimeSec")) * 1000 + (try numeric(value, "mtimeNsec")) / 1e6 } };
}
fn final(ticket: native.Ticket, context: ?types.Context) !wire.Frame {
    if (context == null) return ticket.next(60_000);
    var canceled = false;
    const deadline = std.Io.Clock.awake.now(ticket.connection.io).addDuration(.fromSeconds(60));
    while (true) {
        if (!canceled and context.?.aborted()) {
            try ticket.cancel(false);
            canceled = true;
        }
        var reply = ticket.next(50) catch |err| {
            if (err == error.Timeout and std.Io.Clock.awake.now(ticket.connection.io).nanoseconds < deadline.nanoseconds) continue;
            return err;
        };
        if (reply.kind == .event) {
            reply.deinit();
            continue;
        }
        return reply;
    }
}
pub const RemoteExecutionEnv = struct {
    gpa: std.mem.Allocator,
    connection: Transport,
    id: []u8,
    cwd: []u8,
    shell_path: ?[]u8,
    shell_env: ?*const std.process.Environ.Map,
    watch_options: remote_watching.Options = .{},
    running_mutex: std.Io.Mutex = .init,
    running: std.AutoHashMapUnmanaged(struct { connection: *native.Connection, id: u32 }, native.Ticket) = .empty,
    pub fn init(gpa: std.mem.Allocator, options: Options) !RemoteExecutionEnv {
        const id = try gpa.dupe(u8, options.id);
        errdefer gpa.free(id);
        const cwd = try gpa.dupe(u8, options.cwd);
        errdefer gpa.free(cwd);
        const shell_path = if (options.shellPath) |path| try gpa.dupe(u8, path) else null;
        return .{ .gpa = gpa, .connection = options.connection, .id = id, .cwd = cwd, .shell_path = shell_path, .shell_env = options.shellEnv, .watch_options = options.watch };
    }
    /// Readers and outstanding commands must be released before their env.
    /// The transport is borrowed; destruction never closes somebody else's session.
    pub fn deinit(self: *RemoteExecutionEnv) void {
        self.gpa.free(self.id);
        self.gpa.free(self.cwd);
        if (self.shell_path) |path| self.gpa.free(path);
        self.running.deinit(self.gpa);
        self.* = undefined;
    }
    pub fn setCwd(self: *RemoteExecutionEnv, input: []const u8) !void {
        const path = try self.resolvePath(input);
        self.gpa.free(self.cwd);
        self.cwd = path;
    }
    fn request(self: *const RemoteExecutionEnv, value: anytype, payload: []const u8) !wire.Frame {
        var ticket = try self.connection.begin(value, payload, null);
        defer ticket.deinit();
        return final(ticket, null);
    }
    fn info(self: *const RemoteExecutionEnv) !wire.Frame {
        var reply = try self.request(.{ .op = "hello", .protocol = 1 }, "");
        errdefer reply.deinit();
        if (reply.kind != .result) return error.InvalidDaemonHandshake;
        return reply;
    }
    fn pathInfo(reply: wire.Frame) !paths.Info {
        const value = reply.json.value;
        return .{ .platform = if (std.mem.eql(u8, try string(value, "os"), "windows")) .windows else .posix, .home = try string(value, "home"), .cwd = try string(value, "cwd"), .drive_cwds = value.object.get("driveCwds") orelse .{ .object = .empty } };
    }
    pub fn resolvePath(self: *const RemoteExecutionEnv, path: []const u8) ![]u8 {
        var reply = try self.info();
        defer reply.deinit();
        const ambient_cwd = try std.process.currentPathAlloc(switch (self.connection) {
            .native => |connection| connection.io,
            .lazy => |connection| connection.io,
        }, self.gpa);
        defer self.gpa.free(ambient_cwd);
        var path_info = try pathInfo(reply);
        path_info.ambient_cwd = ambient_cwd;
        return paths.resolve(self.gpa, path_info, self.cwd, path);
    }
    fn platform(self: *const RemoteExecutionEnv) !paths.Platform {
        var reply = try self.info();
        defer reply.deinit();
        return (try pathInfo(reply)).platform;
    }
    pub fn absolutePath(self: *const RemoteExecutionEnv, path: []const u8, _: types.Context) !types.Result([]u8) {
        return .{ .value = self.resolvePath(path) catch |err| return types.fromError([]u8, self.gpa, err, path) };
    }
    pub fn joinPath(self: *const RemoteExecutionEnv, parts: []const []const u8, _: types.Context) !types.Result([]u8) {
        const remote = self.platform() catch |err| return types.fromError([]u8, self.gpa, err, null);
        return .{ .value = try paths.join(self.gpa, remote, parts) };
    }
    fn prepared(self: *const RemoteExecutionEnv, path: []const u8, context: types.Context) !types.Result([]u8) {
        const resolved = self.resolvePath(path) catch |err| return types.fromError([]u8, self.gpa, err, path);
        if (context.aborted()) {
            defer self.gpa.free(resolved);
            return types.failure([]u8, self.gpa, .aborted, resolved, null, "aborted");
        }
        return .{ .value = resolved };
    }
    fn open(self: *const RemoteExecutionEnv, path: []u8, mode_read: bool, no_follow: bool, need_size: bool) !types.Result(Handle) {
        var ticket = try self.connection.begin(.{ .op = "open", .path = path, .mode = if (mode_read) "read" else "reader", .noFollow = no_follow }, "", null);
        defer ticket.deinit();
        var reply = final(ticket, null) catch |err| return types.fromError(Handle, self.gpa, err, path);
        defer reply.deinit();
        if (try checked(Handle, self.gpa, reply, path)) |failure| return failure;
        const id = try number(reply.json.value, "handle");
        var handle: Handle = .{ .env = self, .id = id, .session = ticket.session, .path = path };
        errdefer handle.close();
        if (need_size) {
            if (reply.json.value.object.get("statError")) |failure| {
                handle.close();
                return remoteFailure(Handle, self.gpa, failure, path);
            }
            const stat = reply.json.value.object.get("stat") orelse return error.InvalidDaemonJson;
            handle.size = if (std.mem.eql(u8, try string(stat, "kind"), "file")) try number(stat, "size") else 0;
        }
        return .{ .value = handle };
    }
    pub fn openBinaryReader(self: *const RemoteExecutionEnv, path: []const u8, options: fs.OpenBinaryOptions, context: types.Context) !types.Result(BinaryReader) {
        const prepared_path = try self.prepared(path, context);
        if (prepared_path == .failure) return .{ .failure = prepared_path.failure };
        const resolved = prepared_path.value;
        var transferred = false;
        defer if (!transferred) self.gpa.free(resolved);
        const opened = self.open(resolved, false, options.noFollow, false) catch |err| return types.fromError(BinaryReader, self.gpa, err, resolved);
        if (opened == .failure) return .{ .failure = opened.failure };
        var handle = opened.value;
        if (context.aborted()) {
            handle.close();
            return types.failure(BinaryReader, self.gpa, .aborted, resolved, null, "aborted");
        }
        transferred = true;
        return .{ .value = .{ .handle = handle, .gpa = self.gpa, .path = handle.path } };
    }
    pub fn openTextLineReader(self: *const RemoteExecutionEnv, path: []const u8, context: types.Context) !types.Result(TextLineReader) {
        const prepared_path = try self.prepared(path, context);
        if (prepared_path == .failure) return .{ .failure = prepared_path.failure };
        const resolved = prepared_path.value;
        var transferred = false;
        defer if (!transferred) self.gpa.free(resolved);
        const opened = self.open(resolved, true, false, false) catch |err| return types.fromError(TextLineReader, self.gpa, err, resolved);
        if (opened == .failure) return .{ .failure = opened.failure };
        var handle = opened.value;
        if (context.aborted()) {
            handle.close();
            return types.failure(TextLineReader, self.gpa, .aborted, resolved, null, "aborted");
        }
        transferred = true;
        return .{ .value = .{ .handle = handle } };
    }
    fn readFile(self: *const RemoteExecutionEnv, path: []const u8, text: bool, context: types.Context) !types.Result([]u8) {
        const prepared_path = try self.prepared(path, context);
        if (prepared_path == .failure) return .{ .failure = prepared_path.failure };
        const resolved = prepared_path.value;
        defer self.gpa.free(resolved);
        const opened = self.open(resolved, true, false, true) catch |err| return types.fromError([]u8, self.gpa, err, resolved);
        if (opened == .failure) return .{ .failure = opened.failure };
        var handle = opened.value;
        defer handle.close();
        if (context.aborted()) return types.failure([]u8, self.gpa, .aborted, resolved, null, "The operation was aborted");
        if (handle.size > 2147483647) {
            const message = try std.fmt.allocPrint(self.gpa, "File size ({d}) is greater than 2 GiB", .{handle.size});
            errdefer self.gpa.free(message);
            var failure = try types.failure([]u8, self.gpa, .unknown, resolved, null, message);
            failure.failure.message_owned = true;
            return failure;
        }
        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(self.gpa);
        if (handle.size == 0) {
            while (true) {
                if (context.aborted()) return types.failure([]u8, self.gpa, .aborted, resolved, null, "The operation was aborted");
                var reply = handle.request(.{ .op = "pread", .length = 64 * 1024, .handle = handle.id }, "", null) catch |err| return types.fromError([]u8, self.gpa, err, resolved);
                defer reply.deinit();
                if (try checked([]u8, self.gpa, reply, resolved)) |failure| return failure;
                if (reply.payload.len == 0) break;
                try output.appendSlice(self.gpa, reply.payload);
            }
        } else if (!text and handle.size <= file_chunk) {
            // Upstream's single small binary read has no after-read abort check.
            var reply = handle.request(.{ .op = "pread", .handle = handle.id, .offset = 0, .length = handle.size }, "", null) catch |err| return types.fromError([]u8, self.gpa, err, resolved);
            defer reply.deinit();
            if (try checked([]u8, self.gpa, reply, resolved)) |failure| return failure;
            try output.appendSlice(self.gpa, reply.payload);
        } else {
            var read = try handle.readRange(0, handle.size, if (text) @intCast(@min(handle.size, file_chunk)) else file_chunk, context, text);
            if (read == .failure) {
                if (read.failure.code == .aborted) read.failure.message = "The operation was aborted";
                return read;
            }
            defer self.gpa.free(read.value);
            try output.appendSlice(self.gpa, read.value);
        }
        return .{ .value = if (text) try decode.decode(self.gpa, output.items, true) else try output.toOwnedSlice(self.gpa) };
    }
    pub fn readBinaryFile(self: *const RemoteExecutionEnv, path: []const u8, context: types.Context) !types.Result([]u8) {
        return self.readFile(path, false, context);
    }
    pub fn readTextFile(self: *const RemoteExecutionEnv, path: []const u8, context: types.Context) !types.Result([]u8) {
        return self.readFile(path, true, context);
    }
    pub fn readTextLines(self: *const RemoteExecutionEnv, path: []const u8, max_lines: ?u64, context: types.Context) !types.Result([][]u8) {
        var lines: std.ArrayList([]u8) = .empty;
        defer {
            for (lines.items) |line| self.gpa.free(line);
            lines.deinit(self.gpa);
        }
        if (max_lines == 0) return .{ .value = try lines.toOwnedSlice(self.gpa) };
        const opened = try self.openTextLineReader(path, context);
        if (opened == .failure) return .{ .failure = opened.failure };
        var reader = opened.value;
        defer reader.deinit();
        while (max_lines == null or lines.items.len < max_lines.?) {
            const line = try reader.readLine(context);
            if (line == .failure) return .{ .failure = line.failure };
            const value = line.value orelse break;
            errdefer self.gpa.free(value.text);
            try lines.append(self.gpa, value.text);
        }
        return .{ .value = try lines.toOwnedSlice(self.gpa) };
    }
    fn write(self: *const RemoteExecutionEnv, path: []const u8, bytes: []const u8, append: bool, context: types.Context) !types.Result(void) {
        const prepared_path = try self.prepared(path, context);
        if (prepared_path == .failure) return .{ .failure = prepared_path.failure };
        const resolved = prepared_path.value;
        defer self.gpa.free(resolved);
        var first = try self.connection.begin(.{ .op = "write", .path = resolved, .append = append, .keep = bytes.len > file_chunk }, bytes[0..@min(bytes.len, file_chunk)], null);
        defer first.deinit();
        var reply = final(first, null) catch |err| return types.fromError(void, self.gpa, err, resolved);
        defer reply.deinit();
        if (try checked(void, self.gpa, reply, resolved)) |failure| return failure;
        if (bytes.len > file_chunk) {
            var handle: Handle = .{ .env = self, .id = try number(reply.json.value, "handle"), .session = first.session, .path = resolved };
            defer handle.close();
            var queued: std.ArrayList(native.Ticket) = .empty;
            defer {
                drain(&queued);
                queued.deinit(self.gpa);
            }
            try queued.ensureTotalCapacity(self.gpa, depth);
            var offset: usize = file_chunk;
            while (offset < bytes.len) : (offset += file_chunk) {
                if (!append and context.aborted()) {
                    // Await admitted writes before reporting abort: a failure
                    // that happened first still wins, as in the original.
                    while (queued.items.len != 0) {
                        var ticket = queued.orderedRemove(0);
                        defer ticket.deinit();
                        var finished = final(ticket, null) catch |err| return types.fromError(void, self.gpa, err, resolved);
                        defer finished.deinit();
                        if (try checked(void, self.gpa, finished, resolved)) |failure| return failure;
                    }
                    return types.failure(void, self.gpa, .aborted, resolved, null, "The operation was aborted");
                }
                const ticket = handle.begin(.{ .op = "writeChunk", .handle = handle.id }, bytes[offset..@min(bytes.len, offset + file_chunk)]) catch |err| return types.fromError(void, self.gpa, err, resolved);
                queued.appendAssumeCapacity(ticket);
                if (queued.items.len == depth) {
                    var head = queued.orderedRemove(0);
                    defer head.deinit();
                    var finished = final(head, null) catch |err| return types.fromError(void, self.gpa, err, resolved);
                    defer finished.deinit();
                    if (try checked(void, self.gpa, finished, resolved)) |failure| return failure;
                }
            }
            while (queued.items.len != 0) {
                var ticket = queued.orderedRemove(0);
                defer ticket.deinit();
                var finished = final(ticket, null) catch |err| return types.fromError(void, self.gpa, err, resolved);
                defer finished.deinit();
                if (try checked(void, self.gpa, finished, resolved)) |failure| return failure;
            }
        }
        if (append and context.aborted()) return types.failure(void, self.gpa, .aborted, resolved, null, "aborted");
        return .{ .value = {} };
    }
    pub fn writeFile(self: *const RemoteExecutionEnv, path: []const u8, bytes: []const u8, context: types.Context) !types.Result(void) {
        return self.write(path, bytes, false, context);
    }
    pub fn appendFile(self: *const RemoteExecutionEnv, path: []const u8, bytes: []const u8, context: types.Context) !types.Result(void) {
        return self.write(path, bytes, true, context);
    }
    pub fn fileInfo(self: *const RemoteExecutionEnv, path: []const u8, context: types.Context) !types.Result(types.FileInfo) {
        const prepared_path = try self.prepared(path, context);
        if (prepared_path == .failure) return .{ .failure = prepared_path.failure };
        const resolved = prepared_path.value;
        defer self.gpa.free(resolved);
        var reply = self.request(.{ .op = "lstat", .path = resolved }, "") catch |err| return types.fromError(types.FileInfo, self.gpa, err, resolved);
        defer reply.deinit();
        if (try checked(types.FileInfo, self.gpa, reply, resolved)) |failure| return failure;
        return toInfo(self.gpa, try self.platform(), resolved, reply.json.value);
    }
    pub fn exists(self: *const RemoteExecutionEnv, path: []const u8, context: types.Context) !types.Result(bool) {
        var result = try self.fileInfo(path, context);
        if (result == .value) {
            result.value.deinit(self.gpa);
            return .{ .value = true };
        }
        if (result.failure.code == .not_found) {
            result.failure.deinit(self.gpa);
            return .{ .value = false };
        }
        return .{ .failure = result.failure };
    }
    fn simple(self: *const RemoteExecutionEnv, path: []const u8, fields: anytype, both: bool, context: types.Context) !types.Result(void) {
        const prepared_path = try self.prepared(path, context);
        if (prepared_path == .failure) return .{ .failure = prepared_path.failure };
        const resolved = prepared_path.value;
        defer self.gpa.free(resolved);
        const encoded = try std.json.Stringify.valueAlloc(self.gpa, fields, .{});
        defer self.gpa.free(encoded);
        var request_json = try std.json.parseFromSlice(std.json.Value, self.gpa, encoded, .{});
        defer request_json.deinit();
        // Avoid serializing generic fields through a long-lived arena.
        try request_json.value.object.put(request_json.arena.allocator(), "path", .{ .string = resolved });
        var reply = self.request(request_json.value, "") catch |err| return types.fromError(void, self.gpa, err, resolved);
        defer reply.deinit();
        if (try checked(void, self.gpa, reply, resolved)) |failure| return failure;
        if (both and context.aborted()) return types.failure(void, self.gpa, .aborted, resolved, null, "aborted");
        return .{ .value = {} };
    }
    pub fn createDir(self: *const RemoteExecutionEnv, path: []const u8, options: fs.CreateDirOptions, context: types.Context) !types.Result(void) {
        return self.simple(path, .{ .op = "mkdir", .recursive = options.recursive }, false, context);
    }
    pub fn remove(self: *const RemoteExecutionEnv, path: []const u8, options: fs.RemoveOptions, context: types.Context) !types.Result(void) {
        return self.simple(path, .{ .op = "rm", .recursive = options.recursive, .force = options.force }, false, context);
    }
    pub fn flushFile(self: *const RemoteExecutionEnv, path: []const u8, context: types.Context) !types.Result(void) {
        return self.simple(path, .{ .op = "fsync" }, true, context);
    }
    pub fn truncateFile(self: *const RemoteExecutionEnv, path: []const u8, size: u64, context: types.Context) !types.Result(void) {
        if (size > scan.max_safe_integer) {
            const prepared_path = try self.prepared(path, context);
            if (prepared_path == .failure) return .{ .failure = prepared_path.failure };
            defer self.gpa.free(prepared_path.value);
            return types.failure(void, self.gpa, .invalid, prepared_path.value, null, "File size must be a non-negative safe integer");
        }
        return self.simple(path, .{ .op = "truncate", .size = size }, true, context);
    }
    pub fn renameFile(self: *const RemoteExecutionEnv, source: []const u8, destination: []const u8, context: types.Context) !types.Result(void) {
        const from = self.resolvePath(source) catch |err| return types.fromError(void, self.gpa, err, source);
        defer self.gpa.free(from);
        const to = self.resolvePath(destination) catch |err| return types.fromError(void, self.gpa, err, source);
        defer self.gpa.free(to);
        if (context.aborted()) return types.failure(void, self.gpa, .aborted, to, null, "aborted");
        var reply = self.request(.{ .op = "rename", .path = from, .to = to }, "") catch |err| return types.fromError(void, self.gpa, err, from);
        defer reply.deinit();
        if (try checked(void, self.gpa, reply, from)) |failure| return failure;
        return .{ .value = {} };
    }
    pub fn canonicalPath(self: *const RemoteExecutionEnv, path: []const u8, context: types.Context) !types.Result([]u8) {
        const prepared_path = try self.prepared(path, context);
        if (prepared_path == .failure) return .{ .failure = prepared_path.failure };
        const resolved = prepared_path.value;
        defer self.gpa.free(resolved);
        var reply = self.request(.{ .op = "realpath", .path = resolved }, "") catch |err| return types.fromError([]u8, self.gpa, err, resolved);
        defer reply.deinit();
        if (try checked([]u8, self.gpa, reply, resolved)) |failure| return failure;
        return .{ .value = try self.gpa.dupe(u8, try string(reply.json.value, "path")) };
    }
    pub fn openDirReader(self: *const RemoteExecutionEnv, path: []const u8, context: types.Context) !types.Result(DirReader) {
        const prepared_path = try self.prepared(path, context);
        if (prepared_path == .failure) return .{ .failure = prepared_path.failure };
        const resolved = prepared_path.value;
        var transferred = false;
        defer if (!transferred) self.gpa.free(resolved);
        var ticket = self.connection.begin(.{ .op = "opendir", .path = resolved }, "", null) catch |err| return types.fromError(DirReader, self.gpa, err, resolved);
        defer ticket.deinit();
        var reply = final(ticket, null) catch |err| return types.fromError(DirReader, self.gpa, err, resolved);
        defer reply.deinit();
        if (try checked(DirReader, self.gpa, reply, resolved)) |failure| return failure;
        var handle: Handle = .{ .env = self, .id = try number(reply.json.value, "handle"), .session = ticket.session, .path = resolved };
        errdefer handle.close();
        if (context.aborted()) {
            handle.close();
            return types.failure(DirReader, self.gpa, .aborted, resolved, null, "aborted");
        }
        transferred = true;
        return .{ .value = .{ .handle = handle } };
    }
    pub fn listDir(self: *const RemoteExecutionEnv, path: []const u8, context: types.Context) !types.Result([]types.FileInfo) {
        const opened = try self.openDirReader(path, context);
        if (opened == .failure) return .{ .failure = opened.failure };
        var reader = opened.value;
        defer reader.deinit();
        const remote = try self.platform();
        var entries: std.ArrayList(DirectoryEntry) = .empty;
        defer {
            for (entries.items) |*entry| entry.deinit(self.gpa);
            entries.deinit(self.gpa);
        }
        while (!reader.done) {
            var reply = reader.handle.request(.{ .op = "readdir", .handle = reader.handle.id, .max = 1000 }, "", null) catch |err| return types.fromError([]types.FileInfo, self.gpa, err, reader.handle.path);
            defer reply.deinit();
            if (try checked([]types.FileInfo, self.gpa, reply, reader.handle.path)) |failure| return failure;
            const values = reply.json.value.object.get("entries") orelse return error.InvalidDaemonJson;
            if (values != .array) return error.InvalidDaemonJson;
            for (values.array.items) |value| {
                var entry = try directoryEntry(self.gpa, remote, reader.handle.path, value);
                errdefer entry.deinit(self.gpa);
                try entries.append(self.gpa, entry);
            }
            reader.done = (reply.json.value.object.get("done") orelse return error.InvalidDaemonJson).bool;
        }
        if (remote == .posix) std.mem.sort(DirectoryEntry, entries.items, {}, DirectoryEntry.less);
        var infos: std.ArrayList(types.FileInfo) = .empty;
        defer {
            for (infos.items) |*value| value.deinit(self.gpa);
            infos.deinit(self.gpa);
        }
        for (entries.items) |*entry| {
            if (context.aborted()) return types.failure([]types.FileInfo, self.gpa, .aborted, reader.handle.path, null, "aborted");
            if (entry.result) |result| {
                if (result == .failure) {
                    entry.result = null;
                    return .{ .failure = result.failure };
                }
                try infos.append(self.gpa, result.value);
                entry.result = null;
            }
        }
        return .{ .value = try infos.toOwnedSlice(self.gpa) };
    }
    pub fn createTempDir(self: *const RemoteExecutionEnv, prefix: ?[]const u8, context: types.Context) !types.Result([]u8) {
        if (context.aborted()) return types.failure([]u8, self.gpa, .aborted, null, null, "aborted");
        var info_reply = self.info() catch |err| return types.fromError([]u8, self.gpa, err, null);
        defer info_reply.deinit();
        const path = try paths.join(self.gpa, (try pathInfo(info_reply)).platform, &.{ try string(info_reply.json.value, "tmpdir"), prefix orelse "tmp-" });
        defer self.gpa.free(path);
        var reply = self.request(.{ .op = "mkdtemp", .path = path }, "") catch |err| return types.fromError([]u8, self.gpa, err, null);
        defer reply.deinit();
        if (try checked([]u8, self.gpa, reply, null)) |failure| return failure;
        return .{ .value = try self.gpa.dupe(u8, try string(reply.json.value, "path")) };
    }
    pub fn createTempFile(self: *const RemoteExecutionEnv, options: fs.TempFileOptions, context: types.Context) !types.Result([]u8) {
        const dir = try self.createTempDir("tmp-", context);
        if (dir == .failure) return dir;
        defer self.gpa.free(dir.value);
        var uuid: [16]u8 = undefined;
        try self.io().randomSecure(&uuid);
        uuid[6] = (uuid[6] & 0xf) | 0x40;
        uuid[8] = (uuid[8] & 0x3f) | 0x80;
        const hex = std.fmt.bytesToHex(uuid, .lower);
        const filename = try std.fmt.allocPrint(self.gpa, "{s}{s}-{s}-{s}-{s}-{s}{s}", .{ options.prefix, hex[0..8], hex[8..12], hex[12..16], hex[16..20], hex[20..], options.suffix });
        defer self.gpa.free(filename);
        const path = try paths.join(self.gpa, try self.platform(), &.{ dir.value, filename });
        var transferred = false;
        defer if (!transferred) self.gpa.free(path);
        var reply = self.request(.{ .op = "write", .path = path, .append = false, .parents = false }, "") catch |err| return types.fromError([]u8, self.gpa, err, path);
        defer reply.deinit();
        if (try checked([]u8, self.gpa, reply, path)) |failure| return failure;
        transferred = true;
        return .{ .value = path };
    }
    pub fn io(self: *const RemoteExecutionEnv) std.Io {
        return switch (self.connection) {
            .native => |connection| connection.io,
            .lazy => |connection| connection.io,
        };
    }
    pub fn watch(self: *const RemoteExecutionEnv, targets: []const watching.Target, callback: watching.Callback, callback_context: ?*anyopaque, context: types.Context) !types.Result(*remote_watching.Watcher) {
        if (context.aborted()) return types.failure(*remote_watching.Watcher, self.gpa, .aborted, null, null, "aborted");
        const resolved = try self.gpa.alloc(watching.Target, targets.len);
        var copied: usize = 0;
        defer {
            for (resolved[0..copied]) |target| self.gpa.free(target.path);
            self.gpa.free(resolved);
        }
        for (targets, resolved) |target, *slot| {
            const path = self.resolvePath(target.path) catch |err| return types.fromError(*remote_watching.Watcher, self.gpa, err, null);
            slot.* = target;
            slot.path = path;
            copied += 1;
        }
        if (context.aborted()) return types.failure(*remote_watching.Watcher, self.gpa, .aborted, null, null, "aborted");
        const opened = remote_watching.Watcher.open(self.gpa, self.io(), self.connection, resolved, self.watch_options, callback, callback_context) catch |err| return types.fromError(*remote_watching.Watcher, self.gpa, err, null);
        if (opened == .failure) return opened;
        if (context.aborted()) {
            opened.value.deinit();
            return types.failure(*remote_watching.Watcher, self.gpa, .aborted, null, null, "aborted");
        }
        return opened;
    }
    pub fn cleanup(self: *RemoteExecutionEnv, _: types.Context) void {
        self.running_mutex.lockUncancelable(self.io());
        defer self.running_mutex.unlock(self.io());
        var iterator = self.running.valueIterator();
        while (iterator.next()) |ticket| ticket.cancel(true) catch {};
        self.running.clearRetainingCapacity();
    }
    fn executionFailure(self: *const RemoteExecutionEnv, code: shell.ExecutionErrorCode, message: []const u8, cause: ?anyerror, spill: ?[]const u8) !shell.Result {
        const owned = try self.gpa.dupe(u8, message);
        errdefer self.gpa.free(owned);
        const path = if (spill) |value| try self.gpa.dupe(u8, value) else null;
        return .{ .failure = .{ .code = code, .message = owned, .message_owned = true, .cause = cause, .spillPath = path } };
    }
    pub fn exec(self: *RemoteExecutionEnv, command: shell.Command, options: shell.Options, context: types.Context) !shell.Result {
        if (context.aborted()) return self.executionFailure(.aborted, "aborted", null, null);
        const timeout_ms = shell.timeoutMilliseconds(options.timeout) catch {
            return self.executionFailure(.timeout, if (options.timeout != null and std.math.isFinite(options.timeout.?) and options.timeout.? > 0) "Invalid timeout: maximum is 2147483.647 seconds" else "Invalid timeout: must be a finite number of seconds", null, null);
        };
        const cwd = if (options.cwd) |path| if (path.len > 0) self.resolvePath(path) catch |err| return self.executionFailure(.unknown, @errorName(err), err, null) else try self.gpa.dupe(u8, self.cwd) else try self.gpa.dupe(u8, self.cwd);
        defer self.gpa.free(cwd);
        if (context.aborted()) return self.executionFailure(.aborted, "aborted", null, null);
        var env: std.json.ObjectMap = .empty;
        defer env.deinit(self.gpa);
        if (options.inheritEnv) if (self.shell_env) |base| {
            var iterator = base.iterator();
            while (iterator.next()) |entry| try env.put(self.gpa, entry.key_ptr.*, .{ .string = entry.value_ptr.* });
        };
        if (options.env) |extra| {
            var iterator = extra.iterator();
            while (iterator.next()) |entry| try env.put(self.gpa, entry.key_ptr.*, .{ .string = entry.value_ptr.* });
        }
        var ticket = self.connection.begin(.{ .op = "exec", .command = if (command == .text) command.text else null, .argv = if (command == .argv) command.argv else null, .cwd = cwd, .env = std.json.Value{ .object = env }, .inheritEnv = options.inheritEnv, .shellPath = self.shell_path, .timeoutMs = timeout_ms, .spill = options.spill, .window = options.window }, "", null) catch |err| return self.executionFailure(.unknown, @errorName(err), err, null);
        defer ticket.deinit();
        self.running_mutex.lockUncancelable(self.io());
        self.running.put(self.gpa, .{ .connection = ticket.connection, .id = ticket.id }, ticket) catch |err| {
            self.running_mutex.unlock(self.io());
            ticket.cancel(false) catch {};
            var ended = final(ticket, null) catch return err;
            ended.deinit();
            return err;
        };
        self.running_mutex.unlock(self.io());
        defer {
            self.running_mutex.lockUncancelable(self.io());
            _ = self.running.remove(.{ .connection = ticket.connection, .id = ticket.id });
            self.running_mutex.unlock(self.io());
        }
        var aborted = false;
        var callback_error: ?anyerror = null;
        while (true) {
            if (!aborted and context.aborted()) {
                ticket.cancel(false) catch |err| return self.executionFailure(.unknown, @errorName(err), err, null);
                aborted = true;
            }
            var reply = ticket.next(50) catch |err| {
                if (err == error.Timeout) continue;
                if (callback_error) |cause| return self.executionFailure(.callback_error, @errorName(cause), cause, null);
                return self.executionFailure(.unknown, @errorName(err), err, null);
            };
            defer reply.deinit();
            if (reply.kind == .event) {
                const kind = try string(reply.json.value, "kind");
                if (!std.mem.eql(u8, kind, "output") or callback_error != null or options.onOutput == null or reply.payload.len == 0) continue;
                const text = try decode.decode(self.gpa, reply.payload, true);
                defer self.gpa.free(text);
                const stream: shell.Stream = if (std.mem.eql(u8, try string(reply.json.value, "stream"), "stderr")) .stderr else .stdout;
                var info_value: shell.OutputInfo = .{ .stream = stream };
                if (reply.json.value.object.get("skipped")) |skipped| {
                    const parsed = try std.json.parseFromValue(@import("../durable/output_window.zig").ShellOutputSkip, self.gpa, skipped, .{ .ignore_unknown_fields = true });
                    defer parsed.deinit();
                    info_value.skipped = parsed.value;
                }
                options.onOutput.?(options.output_context, text, context, info_value) catch |err| {
                    callback_error = err;
                    ticket.cancel(false) catch {};
                    aborted = true;
                };
                continue;
            }
            if (callback_error) |cause| return self.executionFailure(.callback_error, @errorName(cause), cause, null);
            const value = reply.json.value;
            const spill = if (value.object.get("spillPath")) |path| if (path == .string) path.string else null else null;
            if (reply.kind == .remote_error) {
                const code = try string(value, "code");
                if (std.mem.eql(u8, code, "timeout")) {
                    const message = try std.fmt.allocPrint(self.gpa, "timeout:{d}", .{options.timeout orelse 0});
                    defer self.gpa.free(message);
                    return self.executionFailure(.timeout, message, null, spill);
                }
                const mapped: shell.ExecutionErrorCode = if (std.mem.eql(u8, code, "aborted")) .aborted else if (std.mem.eql(u8, code, "shell_unavailable")) .shell_unavailable else if (std.mem.eql(u8, code, "spawn_error")) .spawn_error else .unknown;
                return self.executionFailure(mapped, if (mapped == .aborted) "aborted" else try string(value, "message"), null, spill);
            }
            if (reply.kind != .result) return error.UnexpectedDaemonFrame;
            const exit_code = value.object.get("exitCode") orelse return error.InvalidDaemonJson;
            if (exit_code != .integer) return error.InvalidDaemonJson;
            return .{ .value = .{ .exitCode = exit_code.integer, .spillPath = if (spill) |path| try self.gpa.dupe(u8, path) else null } };
        }
    }
};
const DirectoryEntry = struct {
    key: []u8,
    result: ?types.Result(types.FileInfo),
    fn deinit(self: *DirectoryEntry, gpa: std.mem.Allocator) void {
        gpa.free(self.key);
        if (self.result) |*result| switch (result.*) {
            .value => |*value| value.deinit(gpa),
            .failure => |*failure| failure.deinit(gpa),
        };
    }
    fn less(_: void, a: DirectoryEntry, b: DirectoryEntry) bool {
        return std.mem.order(u8, a.key, b.key) == .lt;
    }
};
fn directoryEntry(gpa: std.mem.Allocator, platform: paths.Platform, parent: []const u8, value: std.json.Value) !DirectoryEntry {
    const name = try string(value, "name");
    const key = if (value.object.get("raw")) |raw| blk: {
        if (raw != .array) return error.InvalidDaemonJson;
        const bytes = try gpa.alloc(u8, raw.array.items.len);
        errdefer gpa.free(bytes);
        for (raw.array.items, bytes) |byte, *slot| {
            if (byte != .integer or byte.integer < 0 or byte.integer > 255) return error.InvalidDaemonJson;
            slot.* = @intCast(byte.integer);
        }
        break :blk bytes;
    } else try gpa.dupe(u8, name);
    errdefer gpa.free(key);
    const path = try paths.resolve(gpa, .{ .platform = platform, .home = "", .cwd = parent }, parent, name);
    defer gpa.free(path);
    if (value.object.get("error")) |failure| return .{ .key = key, .result = try remoteFailure(types.FileInfo, gpa, failure, path) };
    var info = try toInfo(gpa, platform, path, value.object.get("info") orelse return error.InvalidDaemonJson);
    if (info == .failure) {
        info.failure.deinit(gpa);
        return .{ .key = key, .result = null };
    }
    return .{ .key = key, .result = info };
}
pub const DirReader = struct {
    handle: Handle,
    done: bool = false,
    pub fn close(self: *DirReader, _: types.Context) void {
        self.handle.close();
    }
    pub fn deinit(self: *DirReader) void {
        self.handle.deinit();
    }
    pub fn next(self: *DirReader, max_entries: u64, context: types.Context) !types.Result(types.DirPage) {
        const gpa = self.handle.env.gpa;
        const path = self.handle.path;
        if (context.aborted()) return types.failure(types.DirPage, gpa, .aborted, path, null, "aborted");
        if (self.handle.closed) return types.failure(types.DirPage, gpa, .invalid, path, null, "Directory reader is closed");
        if (max_entries == 0 or max_entries > scan.max_safe_integer) return types.failure(types.DirPage, gpa, .invalid, path, null, "maxEntries must be a positive safe integer");
        const remote = try self.handle.env.platform();
        var infos: std.ArrayList(types.FileInfo) = .empty;
        defer {
            for (infos.items) |*value| value.deinit(gpa);
            infos.deinit(gpa);
        }
        while (!self.done and infos.items.len < max_entries) {
            var reply = self.handle.request(.{ .op = "readdir", .handle = self.handle.id, .max = max_entries - infos.items.len }, "", null) catch |err| return types.fromError(types.DirPage, gpa, err, path);
            defer reply.deinit();
            if (try checked(types.DirPage, gpa, reply, path)) |failure| return failure;
            if (context.aborted()) return types.failure(types.DirPage, gpa, .aborted, path, null, "aborted");
            const values = reply.json.value.object.get("entries") orelse return error.InvalidDaemonJson;
            if (values != .array) return error.InvalidDaemonJson;
            for (values.array.items) |value| {
                var entry = try directoryEntry(gpa, remote, path, value);
                defer entry.deinit(gpa);
                if (entry.result) |result| {
                    if (result == .failure) {
                        if (result.failure.code == .not_found) continue;
                        entry.result = null;
                        return .{ .failure = result.failure };
                    }
                    try infos.append(gpa, result.value);
                    entry.result = null;
                }
            }
            self.done = (reply.json.value.object.get("done") orelse return error.InvalidDaemonJson).bool;
        }
        return .{ .value = .{ .entries = try infos.toOwnedSlice(gpa), .done = self.done } };
    }
};
fn allocationCase(gpa: std.mem.Allocator, value: std.json.Value) !void {
    const path = try paths.resolve(gpa, .{ .platform = .windows, .cwd = "C:\\remote", .home = "D:\\Ω" }, "C:\\owned", "~/🦊/../file");
    defer gpa.free(path);
    var first = try remoteFailure(void, gpa, value, path);
    defer first.failure.deinit(gpa);
    var second = try remoteFailure(void, gpa, value, path);
    defer second.failure.deinit(gpa);
    try std.testing.expectEqualStrings("captured-message-Ω🦊", first.failure.message);
    try std.testing.expectEqualStrings("/remote/path", second.failure.path.?);
    second.failure.deinit(gpa);
    try std.testing.expectEqualStrings("captured-message-Ω🦊", first.failure.message);
    var unused_connection: native.Connection = undefined;
    var env = try RemoteExecutionEnv.init(gpa, .{ .connection = .{ .native = &unused_connection }, .id = "allocation-owner", .cwd = "C:\\owned" });
    defer env.deinit();
    var execution = try env.executionFailure(.timeout, "owned-execution-message", null, "/owned/spill");
    defer execution.failure.deinit(gpa);
    try std.testing.expectEqualStrings("owned-execution-message", execution.failure.message);
    execution.failure.deinit(gpa);
}
test "remote owned error messages survive independent copies and every induced allocation failure; deinit is idempotent" {
    const gpa = std.testing.allocator;
    const capture = try std.json.parseFromSlice(std.json.Value, gpa, "{\"code\":\"ENOENT\",\"message\":\"captured-message-Ω🦊\",\"path\":\"/remote/path\"}", .{});
    defer capture.deinit();
    try std.testing.checkAllAllocationFailures(gpa, allocationCase, .{capture.value});
    var literal = try types.failure(void, gpa, .invalid, null, null, "borrowed-message");
    literal.failure.deinit(gpa);
    literal.failure.deinit(gpa);
}
fn drain(queued: *std.ArrayList(native.Ticket)) void {
    for (queued.items) |*ticket| {
        var reply = final(ticket.*, null) catch {
            ticket.deinit();
            continue;
        };
        reply.deinit();
        ticket.deinit();
    }
    queued.clearRetainingCapacity();
}
pub const Handle = struct {
    env: *const RemoteExecutionEnv,
    id: u64,
    session: u64,
    path: []u8,
    size: u64 = 0,
    closed: bool = false,
    fn begin(self: *const Handle, value: anytype, payload: []const u8) !native.Ticket {
        return self.env.connection.begin(value, payload, self.session);
    }
    fn request(self: *const Handle, value: anytype, payload: []const u8, context: ?types.Context) !wire.Frame {
        var ticket = try self.begin(value, payload);
        defer ticket.deinit();
        return final(ticket, context);
    }
    pub fn close(self: *Handle) void {
        if (self.closed) return;
        self.closed = true;
        var reply = self.request(.{ .op = "close", .handle = self.id }, "", null) catch return;
        reply.deinit();
    }
    fn deinit(self: *Handle) void {
        self.close();
        self.env.gpa.free(self.path);
        self.* = undefined;
    }
    fn readRange(self: *Handle, offset: u64, length: u64, chunk: usize, context: types.Context, stop_short: bool) !types.Result([]u8) {
        const gpa = self.env.gpa;
        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(gpa);
        var queued: std.ArrayList(native.Ticket) = .empty;
        defer {
            drain(&queued);
            queued.deinit(gpa);
        }
        var lengths: std.ArrayList(usize) = .empty;
        defer lengths.deinit(gpa);
        try queued.ensureTotalCapacity(gpa, depth);
        try lengths.ensureTotalCapacity(gpa, depth);
        var next: u64 = offset;
        const end = std.math.add(u64, offset, length) catch return types.failure([]u8, gpa, .invalid, self.path, null, "Offset overflow");
        while (stop_short or output.items.len < length) {
            while (queued.items.len < depth and (stop_short or next < end)) {
                const size: usize = if (stop_short) chunk else @intCast(@min(end - next, chunk));
                const ticket = self.begin(.{ .op = "pread", .handle = self.id, .offset = next, .length = size }, "") catch |err| return types.fromError([]u8, gpa, err, self.path);
                queued.appendAssumeCapacity(ticket);
                lengths.appendAssumeCapacity(size);
                next += size;
            }
            var head = queued.orderedRemove(0);
            defer head.deinit();
            const expected = lengths.orderedRemove(0);
            var reply = final(head, null) catch |err| return types.fromError([]u8, gpa, err, self.path);
            defer reply.deinit();
            if (try checked([]u8, gpa, reply, self.path)) |failure| return failure;
            if (context.aborted()) return types.failure([]u8, gpa, .aborted, self.path, null, "aborted");
            if (reply.payload.len > expected) return error.InvalidDaemonPayload;
            if (reply.payload.len == 0) break;
            try output.appendSlice(gpa, reply.payload);
            if (stop_short and output.items.len == length) break;
            if (reply.payload.len < expected) {
                if (stop_short) break;
                drain(&queued);
                lengths.clearRetainingCapacity();
                next = offset + output.items.len;
            }
        }
        return .{ .value = try output.toOwnedSlice(gpa) };
    }
};
pub const BinaryReader = struct {
    handle: Handle,
    gpa: std.mem.Allocator,
    path: []const u8,
    pub fn close(self: *BinaryReader, _: types.Context) void {
        self.handle.close();
    }
    pub fn deinit(self: *BinaryReader) void {
        self.handle.deinit();
    }
    pub fn info(self: *BinaryReader, context: types.Context) !types.Result(types.FileInfo) {
        const h = &self.handle;
        if (context.aborted()) return types.failure(types.FileInfo, h.env.gpa, .aborted, h.path, null, "aborted");
        if (h.closed) return types.failure(types.FileInfo, h.env.gpa, .invalid, h.path, null, "Binary reader is closed");
        var reply = h.request(.{ .op = "fstat", .handle = h.id }, "", null) catch |err| return types.fromError(types.FileInfo, h.env.gpa, err, h.path);
        defer reply.deinit();
        if (try checked(types.FileInfo, h.env.gpa, reply, h.path)) |failure| return failure;
        return toInfo(h.env.gpa, try h.env.platform(), h.path, reply.json.value);
    }
    pub fn read(self: *BinaryReader, offset: u64, length: u64, context: types.Context) !types.Result([]u8) {
        const h = &self.handle;
        if (context.aborted()) return types.failure([]u8, h.env.gpa, .aborted, h.path, null, "aborted");
        if (h.closed) return types.failure([]u8, h.env.gpa, .invalid, h.path, null, "Binary reader is closed");
        if (offset > scan.max_safe_integer or length > scan.max_safe_integer) return types.failure([]u8, h.env.gpa, .invalid, h.path, null, "Offset and length must be non-negative safe integers");
        return h.readRange(offset, length, read_chunk, context, false);
    }
    pub fn scanLines(self: *BinaryReader, options: scan.Options, context: types.Context) !types.Result(scan.LineScan) {
        const h = &self.handle;
        if (context.aborted()) return types.failure(scan.LineScan, h.env.gpa, .aborted, h.path, null, "aborted");
        if (h.closed) return types.failure(scan.LineScan, h.env.gpa, .invalid, h.path, null, "Binary reader is closed");
        _ = scan.LineScanner.init(options) catch return types.failure(scan.LineScan, h.env.gpa, .invalid, h.path, null, "Invalid line range");
        var reply = h.request(.{ .op = "scanLines", .handle = h.id, .startLine = options.startLine, .endLine = options.endLine }, "", context) catch |err| return types.fromError(scan.LineScan, h.env.gpa, err, h.path);
        defer reply.deinit();
        if (try checked(scan.LineScan, h.env.gpa, reply, h.path)) |failure| return failure;
        const parsed = try std.json.parseFromValue(scan.LineScan, h.env.gpa, reply.json.value, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();
        return .{ .value = parsed.value };
    }
};
pub const TextLineReader = struct {
    handle: Handle,
    decoder: decode.Decoder = decode.streamDecoder(),
    offset: u64 = 0,
    buffered: std.ArrayList(u8) = .empty,
    ended: bool = false,
    pub fn close(self: *TextLineReader, _: types.Context) void {
        self.handle.close();
        self.buffered.clearRetainingCapacity();
    }
    pub fn deinit(self: *TextLineReader) void {
        self.buffered.deinit(self.handle.env.gpa);
        self.handle.deinit();
    }
    pub fn readLine(self: *TextLineReader, context: types.Context) !types.Result(?types.TextLine) {
        const h = &self.handle;
        const gpa = h.env.gpa;
        if (context.aborted()) return types.failure(?types.TextLine, gpa, .aborted, h.path, null, "aborted");
        if (h.closed) return types.failure(?types.TextLine, gpa, .invalid, h.path, null, "Text line reader is closed");
        while (true) {
            if (std.mem.indexOfScalar(u8, self.buffered.items, '\n')) |end| {
                const text = try gpa.dupe(u8, self.buffered.items[0..end]);
                std.mem.copyForwards(u8, self.buffered.items, self.buffered.items[end + 1 ..]);
                self.buffered.items.len -= end + 1;
                return .{ .value = .{ .text = text, .terminated = true } };
            }
            if (self.ended) {
                if (self.buffered.items.len == 0) return .{ .value = null };
                return .{ .value = .{ .text = try self.buffered.toOwnedSlice(gpa), .terminated = false } };
            }
            var reply = h.request(.{ .op = "pread", .handle = h.id, .offset = self.offset, .length = 64 * 1024 }, "", null) catch |err| return types.fromError(?types.TextLine, gpa, err, h.path);
            defer reply.deinit();
            if (try checked(?types.TextLine, gpa, reply, h.path)) |failure| return failure;
            if (context.aborted()) return types.failure(?types.TextLine, gpa, .aborted, h.path, null, "aborted");
            self.offset += reply.payload.len;
            const sink: decode.Text = .{ .gpa = gpa, .output = &self.buffered };
            if (reply.payload.len == 0) {
                try self.decoder.finish(sink);
                self.ended = true;
            } else try self.decoder.push(reply.payload, sink);
        }
    }
};
test "remote native adapters execute retained readers pipelined writes UTF8 and owned failures against actual daemon" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const capture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/remote-adapter-7fb59f9.json"), .{});
    defer capture.deinit();
    const expected = capture.value.object.get("files").?;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const program = environ.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    const connection = try native.Connection.start(gpa, io, &.{program}, 1);
    defer connection.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const size = try tmp.dir.realPath(io, &buffer);
    var env = try RemoteExecutionEnv.init(gpa, .{ .connection = .{ .native = connection }, .id = "pi-env:owned-test", .cwd = buffer[0..size] });
    defer env.deinit();
    const content = try gpa.alloc(u8, 5 * 1024 * 1024 + 19);
    defer gpa.free(content);
    for (content, 0..) |*byte, index| byte.* = @intCast(index % 251);
    try std.testing.expect((try env.writeFile("nested/Ω🦊", content, .{})) == .value);
    const opened = try env.openBinaryReader("nested/Ω🦊", .{}, .{});
    try std.testing.expect(opened == .value);
    var reader = opened.value;
    defer reader.deinit();
    try std.testing.expect((try env.renameFile("nested/Ω🦊", "retained", .{})) == .value);
    try std.testing.expect((try env.writeFile("nested/Ω🦊", "replacement", .{})) == .value);
    const actual = try reader.read(5, content.len, .{});
    try std.testing.expect(actual == .value);
    defer gpa.free(actual.value);
    try std.testing.expectEqualSlices(u8, content[5..], actual.value);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(actual.value, &digest, .{});
    const actual_hash = std.fmt.bytesToHex(digest, .lower);
    try std.testing.expectEqualStrings(try string(expected, "retainedHash"), &actual_hash);
    var info_result = try reader.info(.{});
    try std.testing.expect(info_result == .value);
    defer info_result.value.deinit(gpa);
    try std.testing.expectEqual(content.len, info_result.value.size);
    try std.testing.expectEqual(try number(expected, "retainedSize"), info_result.value.size);
    const whole = try env.readBinaryFile("retained", .{});
    try std.testing.expect(whole == .value);
    defer gpa.free(whole.value);
    try std.testing.expectEqualSlices(u8, content, whole.value);
    const text = "\xef\xbb\xbfA\r\n🚀\nlast\xf0\x9f";
    try std.testing.expect((try env.writeFile("lines", text, .{})) == .value);
    const full_text = try env.readTextFile("lines", .{});
    try std.testing.expect(full_text == .value);
    defer gpa.free(full_text.value);
    try std.testing.expectEqualStrings("\xef\xbb\xbfA\r\n🚀\nlast�", full_text.value);
    try std.testing.expectEqualStrings(try string(expected, "text"), full_text.value);
    const lines = try env.readTextLines("lines", null, .{});
    try std.testing.expect(lines == .value);
    defer fs.freeTextLines(gpa, lines.value);
    try std.testing.expectEqual(@as(usize, 3), lines.value.len);
    try std.testing.expectEqualStrings("A\r", lines.value[0]);
    try std.testing.expectEqualStrings("last�", lines.value[2]);
    for (lines.value, expected.object.get("lines").?.array.items) |actual_line, expected_line| try std.testing.expectEqualStrings(expected_line.string, actual_line);
    const text_reader = try env.openTextLineReader("lines", .{});
    try std.testing.expect(text_reader == .value);
    var line_reader = text_reader.value;
    defer line_reader.deinit();
    var line = try line_reader.readLine(.{});
    try std.testing.expect(line == .value and line.value != null);
    defer line.value.?.deinit(gpa);
    try std.testing.expect(line.value.?.terminated);
    line_reader.close(.{});
    var line_closed = try line_reader.readLine(.{});
    try std.testing.expect(line_closed == .failure);
    defer line_closed.failure.deinit(gpa);
    const binary_lines = try env.openBinaryReader("lines", .{}, .{});
    var line_scan = binary_lines.value;
    defer line_scan.deinit();
    const scanned = try line_scan.scanLines(.{ .startLine = 1 }, .{});
    try std.testing.expect(scanned == .value);
    try std.testing.expectEqual(@as(u64, 2), scanned.value.newlines);
    try std.testing.expect((try env.appendFile("lines", "tail", .{})) == .value);
    try std.testing.expect((try env.truncateFile("lines", 3, .{})) == .value);
    try std.testing.expect((try env.flushFile("lines", .{})) == .value);
    try std.testing.expect((try env.createDir("directory", .{}, .{})) == .value);
    try std.testing.expect((try env.writeFile("directory/z", "z", .{})) == .value);
    try std.testing.expect((try env.writeFile("directory/a", "a", .{})) == .value);
    const dir_open = try env.openDirReader("directory", .{});
    try std.testing.expect(dir_open == .value);
    var dir = dir_open.value;
    defer dir.deinit();
    var page = try dir.next(1, .{});
    try std.testing.expect(page == .value and page.value.entries.len == 1);
    page.value.deinit(gpa);
    var page2 = try dir.next(1, .{});
    try std.testing.expect(page2 == .value and page2.value.entries.len == 1);
    page2.value.deinit(gpa);
    var final_page = try dir.next(1, .{});
    try std.testing.expect(final_page == .value and final_page.value.done and final_page.value.entries.len == 0);
    final_page.value.deinit(gpa);
    const listing = try env.listDir("directory", .{});
    try std.testing.expect(listing == .value and listing.value.len == 2);
    defer {
        for (listing.value) |*entry| entry.deinit(gpa);
        gpa.free(listing.value);
    }
    if (@import("builtin").os.tag != .windows) try std.testing.expectEqualStrings("a", listing.value[0].name);
    const temp_dir = try env.createTempDir("remote-env-proof-", .{});
    try std.testing.expect(temp_dir == .value);
    defer gpa.free(temp_dir.value);
    defer {
        var removed = env.remove(temp_dir.value, .{ .recursive = true }, .{}) catch unreachable;
        if (removed == .failure) removed.failure.deinit(gpa);
    }
    const temp_file = try env.createTempFile(.{ .prefix = "Ω-", .suffix = ".proof" }, .{});
    try std.testing.expect(temp_file == .value);
    defer gpa.free(temp_file.value);
    defer {
        const parent = std.fs.path.dirname(temp_file.value).?;
        var removed = env.remove(parent, .{ .recursive = true }, .{}) catch unreachable;
        if (removed == .failure) removed.failure.deinit(gpa);
    }
    try std.testing.expect((try env.exists(temp_file.value, .{})).value);
    const canonical = try env.canonicalPath("directory/../lines", .{});
    try std.testing.expect(canonical == .value);
    defer gpa.free(canonical.value);
    try std.testing.expect((try env.exists("lines", .{})).value);
    try std.testing.expect(!(try env.exists("missing", .{})).value);
    var missing = try env.readBinaryFile("missing", .{});
    try std.testing.expect(missing == .failure);
    defer missing.failure.deinit(gpa);
    try std.testing.expectEqual(types.FileErrorCode.not_found, missing.failure.code);
    try std.testing.expectEqualStrings(try string(expected, "missing"), @tagName(missing.failure.code));
    try std.testing.expect(missing.failure.message_owned);
    var direct_error = try env.request(.{ .op = "open", .path = missing.failure.path.?, .mode = "read" }, "");
    defer direct_error.deinit();
    try std.testing.expectEqualStrings(try string(direct_error.json.value, "message"), missing.failure.message);
    try std.testing.expect(std.mem.endsWith(u8, missing.failure.path.?, "missing"));
    var directory_read = try env.readBinaryFile("directory", .{});
    try std.testing.expect(directory_read == .failure);
    defer directory_read.failure.deinit(gpa);
    try std.testing.expectEqualStrings(try string(expected, "directory"), @tagName(directory_read.failure.code));
    if (@import("builtin").os.tag != .windows) {
        const dev_null = try env.readBinaryFile("/dev/null", .{});
        try std.testing.expect(dev_null == .value);
        defer gpa.free(dev_null.value);
        try std.testing.expectEqual(@as(usize, 0), dev_null.value.len);
        var invalid_device = try env.openBinaryReader("/dev/null", .{}, .{});
        try std.testing.expect(invalid_device == .failure);
        defer invalid_device.failure.deinit(gpa);
        try std.testing.expectEqual(types.FileErrorCode.invalid, invalid_device.failure.code);
    }
    var abort: std.atomic.Value(bool) = .init(true);
    var canceled = try env.writeFile("must-not-exist", "x", .{ .abort_flag = &abort });
    try std.testing.expect(canceled == .failure);
    defer canceled.failure.deinit(gpa);
    try std.testing.expectEqual(types.FileErrorCode.aborted, canceled.failure.code);
    try std.testing.expect(!(try env.exists("must-not-exist", .{})).value);
    reader.close(.{});
    reader.close(.{});
    var closed = try reader.read(0, 1, .{});
    try std.testing.expect(closed == .failure);
    defer closed.failure.deinit(gpa);
    try std.testing.expectEqualStrings(try string(expected, "closed"), closed.failure.message);
    var invalid = try line_scan.read(scan.max_safe_integer + 1, 0, .{});
    try std.testing.expect(invalid == .failure);
    defer invalid.failure.deinit(gpa);
    try std.testing.expect((try env.remove("directory", .{ .recursive = true }, .{})) == .value);
}
test "remote command facade callback precedence timeout abort and cleanup cross actual owned daemon processes" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const program = environ.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    const fixture = environ.get("PI_TEST_SSH_FIXTURE") orelse return error.SkipZigTest;
    const connection = try native.Connection.start(gpa, io, &.{program}, 1);
    defer connection.deinit();
    const cwd = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(cwd);
    var env = try RemoteExecutionEnv.init(gpa, .{ .connection = .{ .native = connection }, .id = "exec-owned", .cwd = cwd });
    defer env.deinit();
    const Collector = struct {
        gpa: std.mem.Allocator,
        text: std.ArrayList(u8) = .empty,
        abort: ?*std.atomic.Value(bool) = null,
        fail: bool = false,
        cleanup_env: ?*RemoteExecutionEnv = null,
        fn output(raw: ?*anyopaque, text: []const u8, _: types.Context, _: shell.OutputInfo) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            try self.text.appendSlice(self.gpa, text);
            if (self.abort) |flag| flag.store(true, .release);
            if (self.cleanup_env) |running_env| running_env.cleanup(.{});
            if (self.fail) return error.CallbackProof;
        }
    };
    var collector: Collector = .{ .gpa = gpa };
    defer collector.text.deinit(gpa);
    var success = try env.exec(.{ .argv = &.{ fixture, "unicode" } }, .{ .onOutput = Collector.output, .output_context = &collector }, .{});
    try std.testing.expect(success == .value);
    defer success.value.deinit(gpa);
    try std.testing.expectEqual(@as(i64, 37), success.value.exitCode);
    try std.testing.expect(std.mem.indexOf(u8, collector.text.items, "Ω🦊") != null);
    collector.fail = true;
    var callback = try env.exec(.{ .argv = &.{ fixture, "tick" } }, .{ .onOutput = Collector.output, .output_context = &collector }, .{});
    try std.testing.expect(callback == .failure);
    defer callback.failure.deinit(gpa);
    try std.testing.expectEqual(shell.ExecutionErrorCode.callback_error, callback.failure.code);
    try std.testing.expectEqualStrings("CallbackProof", callback.failure.message);
    collector.fail = false;
    var aborted: std.atomic.Value(bool) = .init(false);
    collector.abort = &aborted;
    var canceled = try env.exec(.{ .argv = &.{ fixture, "tick" } }, .{ .onOutput = Collector.output, .output_context = &collector }, .{ .abort_flag = &aborted });
    try std.testing.expect(canceled == .failure);
    defer canceled.failure.deinit(gpa);
    try std.testing.expectEqual(shell.ExecutionErrorCode.aborted, canceled.failure.code);
    collector.abort = null;
    collector.cleanup_env = &env;
    var killed = try env.exec(.{ .argv = &.{ fixture, "tick" } }, .{ .onOutput = Collector.output, .output_context = &collector }, .{});
    try std.testing.expect(killed == .value);
    defer killed.value.deinit(gpa);
    try std.testing.expectEqual(@as(i64, if (@import("builtin").os.tag == .windows) 1 else 137), killed.value.exitCode);
    collector.cleanup_env = null;
    var timeout = try env.exec(.{ .argv = &.{ fixture, "tick" } }, .{ .timeout = 0.2 }, .{});
    try std.testing.expect(timeout == .failure);
    defer timeout.failure.deinit(gpa);
    try std.testing.expectEqual(shell.ExecutionErrorCode.timeout, timeout.failure.code);
    try std.testing.expectEqualStrings("timeout:0.2", timeout.failure.message);
    var invalid_timeout = try env.exec(.{ .argv = &.{fixture} }, .{ .timeout = std.math.inf(f64) }, .{});
    try std.testing.expect(invalid_timeout == .failure);
    defer invalid_timeout.failure.deinit(gpa);
    try std.testing.expectEqualStrings("Invalid timeout: must be a finite number of seconds", invalid_timeout.failure.message);
    try std.testing.expectEqual(@as(u32, 0), env.running.count());
}
