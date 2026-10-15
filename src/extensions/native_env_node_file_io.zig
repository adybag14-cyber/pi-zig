//! Native FileHandle operations used by the Node readers. Workers never enter the VM.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const errors = @import("native_env_node_errors.zig");
const owner = @import("native_env_io.zig");
const c = js.c;
const uv = @import("native_uv_api").c;
const leases = @import("native_env_io_lease.zig");
const Method = enum(c_int) { read, write, stat, truncate, sync, close, datasync, chmod, chown, utimes, readv, writev };
const Native = struct {
    extern "c" fn _open_osfhandle(isize, c_int) c_int;
    extern "c" fn _close(c_int) c_int;
};
const State = struct {
    engine: *js.Engine,
    file: ?std.Io.File,
    fd: isize,
    writable: bool,
    // Existing descriptor owners retain their original typed-array accessor.
    // Only explicit private byte-view owners opt in before frontend parity.
    array_buffer_views: bool = false,
    lease_policy: ?leases.Policy = null,
    bindings: c.JSValue,
    close_promise: c.JSValue,
    closing: bool = false,
    closed: std.atomic.Value(bool) = .init(false),
    mutex: std.Io.Mutex = .init,
    active: std.atomic.Value(u32) = .init(0),
    epoch: std.atomic.Value(u32) = .init(0),
    fn closeNative(self: *State) void {
        const file = self.file orelse return;
        _ = file;
        var request: uv.uv_fs_t = undefined;
        _ = uv.uv_fs_close(null, &request, @intCast(self.fd), null);
        uv.uv_fs_req_cleanup(&request);
        self.file = null;
    }
};
fn viewBacking(self: *State, value: c.JSValue, offset: *usize, length: *usize, element: *usize) c.JSValue {
    return if (self.array_buffer_views)
        c.JS_PiGetArrayBufferViewBuffer(self.engine.context, value, offset, length, element)
    else
        c.JS_GetTypedArrayBuffer(self.engine.context, value, offset, length, element);
}
fn state(engine: *js.Engine, receiver: c.JSValue) !*State {
    const result = c.JS_GetOpaque2(engine.context, receiver, engine.native_env_node_file_class) orelse return js.capture(engine);
    return @ptrCast(@alignCast(result));
}
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    // Every pending task roots its receiver. Hub teardown joins workers before releasing those roots.
    self.closeNative();
    c.JS_FreeValueRT(runtime, self.bindings);
    c.JS_FreeValueRT(runtime, self.close_promise);
    self.engine.gpa.destroy(self);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visitor: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, self.bindings, visitor);
    c.JS_MarkValue(runtime, self.close_promise, visitor);
}
fn syscall(method: Method) []const u8 {
    return switch (method) {
        .read, .readv => "read",
        .write, .writev => "write",
        .stat => "fstat",
        .truncate => "ftruncate",
        .sync => "fsync",
        .close => "close",
        .datasync => "fdatasync",
        .chmod => "fchmod",
        .chown => "fchown",
        .utimes => "futimes",
    };
}
fn closedError(scope: *h.Scope, method: Method) !c.JSValue {
    const result = try scope.own(try js.builtin(scope.engine, "Error", &.{try scope.text("file closed")}));
    try scope.put(result, "code", try scope.text("EBADF"));
    try scope.put(result, "syscall", try scope.text(switch (method) {
        .readv => "readv",
        .writev => "writev",
        else => syscall(method),
    }));
    return result;
}
fn systemFailure(scope: *h.Scope, method: Method, failure: anyerror) !c.JSValue {
    const windows = builtin.os.tag == .windows;
    const fields: errors.SystemFailure = switch (failure) {
        error.FileNotFound => .{ .code = "ENOENT", .description = "no such file or directory", .errno = if (windows) -4058 else -2, .syscall = syscall(method) },
        error.IsDir => .{ .code = "EISDIR", .description = "illegal operation on a directory", .errno = if (windows) -4068 else -21, .syscall = syscall(method) },
        error.PermissionDenied => .{ .code = "EPERM", .description = "operation not permitted", .errno = if (windows) -4048 else -1, .syscall = syscall(method) },
        error.AccessDenied => .{ .code = "EACCES", .description = "permission denied", .errno = if (windows) -4092 else -13, .syscall = syscall(method) },
        error.InvalidArgument => .{ .code = "EINVAL", .description = "invalid argument", .errno = if (windows) -4071 else -22, .syscall = syscall(method) },
        else => return error.UnclassifiedNativeNodeFileFailure,
    };
    return errors.systemError(scope, fields);
}
pub fn statsValue(scope: *h.Scope, info: uv.uv_stat_t, bindings: c.JSValue, big: bool) !c.JSValue {
    return @import("native_env_node_stats.zig").create(scope, bindings, info, big);
}
const Job = struct {
    task: owner.Task,
    self: *State,
    receiver: c.JSValue,
    target: c.JSValue,
    views: c.JSValue,
    vectors: []uv.uv_buf_t = &.{},
    pinned: ?leases.Set = null,
    method: Method,
    bytes: []u8 = &.{},
    count: usize = 0,
    from: usize = 0,
    position: ?u64 = null,
    size: u64 = 0,
    stat: ?uv.uv_stat_t = null,
    native_status: c_int = 0,
    bigint: bool = false,
    mode: c_int = 0,
    uid: uv.uv_uid_t = 0,
    gid: uv.uv_gid_t = 0,
    atime: f64 = 0,
    mtime: f64 = 0,
    failure: ?anyerror = null,
    aborted: std.atomic.Value(bool) = .init(false),
    has_reference: bool = false,
    fn run(task: *owner.Task) void {
        const self: *Job = @alignCast(@fieldParentPtr("task", task));
        self.execute() catch |err| {
            self.failure = err;
        };
        task.finish();
    }
    fn releaseReference(self: *Job) void {
        if (!self.has_reference) return;
        self.has_reference = false;
        const before = self.self.active.fetchSub(1, .release);
        if (before == 1 and self.self.closing) self.self.closed.store(true, .release);
        _ = self.self.epoch.fetchAdd(1, .release);
        self.task.hub.io.futexWake(u32, &self.self.epoch.raw, std.math.maxInt(u32));
    }
    fn execute(self: *Job) !void {
        const io = self.task.hub.io;
        if (self.method == .close) while (true) {
            const observed = self.self.epoch.load(.acquire);
            if (self.self.active.load(.acquire) == 0) break;
            try io.futexWait(u32, &self.self.epoch.raw, observed);
        };
        if (self.aborted.load(.acquire)) return error.Canceled;
        try self.self.mutex.lock(io);
        defer self.self.mutex.unlock(io);
        const file = self.self.file orelse return error.NativeFileClosed;
        _ = file;
        // The public writev fast path never enters libuv for an empty array.
        // No request exists in that path, so there is nothing to clean up.
        if (self.method == .writev and self.vectors.len == 0) return;
        if (self.pinned) |pins| {
            const operation: c.JSPiIOOperation = switch (self.method) {
                .read => c.JS_PI_IO_READ,
                .write => c.JS_PI_IO_WRITE,
                .readv => c.JS_PI_IO_READV,
                .writev => c.JS_PI_IO_WRITEV,
                else => unreachable,
            };
            for (pins.slots, 0..) |slot, index| if (slot) |lease| {
                const status = try leases.Lease.nativeStatus(lease.status(operation, index));
                if (status < 0) {
                    self.native_status = status;
                    return;
                }
            };
        }
        var request: uv.uv_fs_t = undefined;
        defer uv.uv_fs_req_cleanup(&request);
        const fd: uv.uv_file = @intCast(self.self.fd);
        const result = switch (self.method) {
            .close => close: {
                self.self.file = null;
                break :close uv.uv_fs_close(null, &request, fd, null);
            },
            .stat => uv.uv_fs_fstat(null, &request, fd, null),
            .truncate => uv.uv_fs_ftruncate(null, &request, fd, @intCast(self.size), null),
            .sync => uv.uv_fs_fsync(null, &request, fd, null),
            .datasync => uv.uv_fs_fdatasync(null, &request, fd, null),
            .chmod => uv.uv_fs_fchmod(null, &request, fd, self.mode, null),
            .chown => uv.uv_fs_fchown(null, &request, fd, self.uid, self.gid, null),
            .utimes => uv.uv_fs_futime(null, &request, fd, self.atime, self.mtime, null),
            .read, .write => operation: {
                var buffer = if (self.pinned) |pins| pins.slots[0].?.buffer() else uv.uv_buf_init(self.bytes.ptr, @intCast(self.bytes.len));
                break :operation if (self.method == .read) uv.uv_fs_read(null, &request, fd, &buffer, 1, if (self.position) |at| @intCast(at) else -1, null) else uv.uv_fs_write(null, &request, fd, &buffer, 1, if (self.position) |at| @intCast(at) else -1, null);
            },
            .readv, .writev => operation: {
                break :operation if (self.method == .readv) uv.uv_fs_read(null, &request, fd, self.vectors.ptr, @intCast(self.vectors.len), if (self.position) |at| @intCast(at) else -1, null) else uv.uv_fs_write(null, &request, fd, self.vectors.ptr, @intCast(self.vectors.len), if (self.position) |at| @intCast(at) else -1, null);
            },
        };
        if (result < 0) self.native_status = result else if (self.method == .stat) self.stat = request.statbuf else if (self.method == .read or self.method == .write or self.method == .readv or self.method == .writev) self.count = @intCast(result);
    }
    fn cancel(task: *owner.Task) void {
        const self: *Job = @alignCast(@fieldParentPtr("task", task));
        self.aborted.store(true, .release);
    }
    fn complete(task: *owner.Task) anyerror!void {
        const self: *Job = @alignCast(@fieldParentPtr("task", task));
        const engine = self.self.engine;
        var scope: h.Scope = .{ .engine = engine };
        defer scope.deinit();
        defer self.releaseReference();
        if (self.native_status < 0) {
            const reason = try errors.systemError(&scope, .{ .code = std.mem.span(uv.uv_err_name(self.native_status)), .description = std.mem.span(uv.uv_strerror(self.native_status)), .errno = self.native_status, .syscall = syscall(self.method) });
            self.releaseReference();
            return task.settled(true, reason);
        }
        if (self.failure) |failure| {
            if (failure == error.OutOfMemory) return failure;
            const reason = if (failure == error.NativeFileClosed) try closedError(&scope, self.method) else try systemFailure(&scope, self.method, failure);
            self.releaseReference();
            return task.settled(true, reason);
        }
        const result = switch (self.method) {
            .stat => try statsValue(&scope, self.stat.?, self.self.bindings, self.bigint),
            .read, .write => read: {
                if (self.pinned == null) {
                    var offset: usize = undefined;
                    var length: usize = undefined;
                    var element: usize = undefined;
                    const backing = try scope.own(try engine.checked(viewBacking(self.self, self.target, &offset, &length, &element)));
                    var total: usize = undefined;
                    const data = c.JS_GetArrayBuffer(engine.context, &total, backing);
                    if ((data == null and self.count != 0) or offset > total or length > total - offset or self.from > length or self.count > length - self.from) return error.NativeReadDestinationDetached;
                    if (self.method == .read and self.count != 0) @memcpy(data[offset + self.from ..][0..self.count], self.bytes[0..self.count]);
                }
                const object = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
                try scope.put(object, if (self.method == .read) "bytesRead" else "bytesWritten", c.JS_NewFloat64(engine.context, @floatFromInt(self.count)));
                try scope.put(object, "buffer", self.target);
                break :read object;
            },
            .readv, .writev => vector: {
                if (self.method == .readv and self.pinned == null) {
                    var consumed: usize = 0;
                    for (self.vectors, 0..) |buffer, index| {
                        const count = @min(@as(usize, @intCast(buffer.len)), self.count - consumed);
                        if (count == 0) continue;
                        const view = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, self.views, @intCast(index))));
                        var offset: usize = undefined;
                        var length: usize = undefined;
                        var element: usize = undefined;
                        const backing = try scope.own(try engine.checked(viewBacking(self.self, view, &offset, &length, &element)));
                        var total: usize = undefined;
                        const data = c.JS_GetArrayBuffer(engine.context, &total, backing);
                        if (data == null or offset > total or length > total - offset or count > length) return error.NativeReadDestinationDetached;
                        @memcpy(data[offset..][0..count], buffer.base[0..count]);
                        consumed += count;
                    }
                    if (consumed != self.count) return error.InvalidNativeReadVectorCount;
                }
                const object = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
                try scope.put(object, if (self.method == .readv) "bytesRead" else "bytesWritten", c.JS_NewFloat64(engine.context, @floatFromInt(self.count)));
                try scope.put(object, "buffers", self.target);
                break :vector object;
            },
            else => c.pi_js_undefined(),
        };
        self.releaseReference();
        try task.settled(false, result);
    }
    fn destroy(task: *owner.Task) void {
        const self: *Job = @alignCast(@fieldParentPtr("task", task));
        const engine = self.self.engine;
        self.releaseReference();
        // Hub.group.cancel joins before abandoned tasks are destroyed. Normal
        // task.finish publishes worker completion before pump destroys the Job.
        if (self.pinned) |*pins| pins.deinit();
        engine.gpa.free(self.bytes);
        engine.gpa.free(self.vectors);
        engine.freeValue(self.views);
        engine.freeValue(self.target);
        engine.freeValue(self.receiver);
        task.releaseFunctions();
        engine.gpa.destroy(self);
    }
};
fn number(engine: *js.Engine, value: c.JSValue) !f64 {
    var result: f64 = undefined;
    if (c.JS_ToFloat64(engine.context, &result, value) < 0) return js.capture(engine);
    return result;
}
// These descriptor primitives receive normalized numeric arguments from the
// public FileHandle layer. Keep casts bounded even before that layer is installed.
fn boundedInteger(engine: *js.Engine, value: c.JSValue, min: f64, max: f64) !f64 {
    if (!c.JS_IsNumber(value)) return error.InvalidNativeFileInteger;
    const result = try number(engine, value);
    if (!std.math.isFinite(result) or @trunc(result) != result or result < min or result > max) return error.InvalidNativeFileInteger;
    return result;
}
fn invoke(engine: *js.Engine, receiver: c.JSValue, args: []const c.JSValue, method: Method) !c.JSValue {
    const self = try state(engine, receiver);
    var scope: h.Scope = .{ .engine = engine };
    defer scope.deinit();
    if (self.closed.load(.acquire)) {
        if (method == .close) return @import("native_durable.zig").resolvedPromise(engine, c.pi_js_undefined());
        return h.throw(&scope, try closedError(&scope, method));
    }
    if (method == .close and self.closing) return c.JS_DupValue(engine.context, self.close_promise);
    var functions: [2]c.JSValue = undefined;
    const new_promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    var transferred = false;
    errdefer if (!transferred) {
        engine.freeValue(functions[0]);
        engine.freeValue(functions[1]);
    };
    const promise = try scope.own(new_promise);
    const hub = try owner.get(engine);
    const job = try engine.gpa.create(Job);
    job.* = .{ .task = .{ .hub = hub, .work = Job.run, .complete = Job.complete, .destroy = Job.destroy, .cancel = Job.cancel, .resolve = functions[0], .reject = functions[1] }, .self = self, .receiver = c.JS_DupValue(engine.context, receiver), .target = c.pi_js_undefined(), .views = c.pi_js_undefined(), .method = method };
    transferred = true;
    errdefer Job.destroy(&job.task);
    if (method == .read or method == .write) {
        const target = h.arg(args, 0);
        var offset: usize = undefined;
        var length: usize = undefined;
        var element: usize = undefined;
        const backing = try scope.own(try engine.checked(viewBacking(self, target, &offset, &length, &element)));

        const from = try number(engine, h.arg(args, 1));
        const count = try number(engine, h.arg(args, 2));
        if (!std.math.isFinite(from) or from < 0 or from > @as(f64, @floatFromInt(length)) or @trunc(from) != from or !std.math.isFinite(count) or count < 0 or count > @as(f64, @floatFromInt(length)) - from or @trunc(count) != count) return error.InvalidNativeReadRange;
        job.from = @intFromFloat(from);
        if (self.lease_policy) |*policy| {
            job.pinned = try leases.Set.init(engine, 1);
            job.pinned.?.slots[0] = try leases.Lease.acquire(policy, backing, offset + job.from, @intFromFloat(count), method == .read);
        } else job.bytes = try engine.gpa.alloc(u8, @intFromFloat(count));
        job.target = c.JS_DupValue(engine.context, target);
        if (method == .write and self.lease_policy == null) {
            var total: usize = undefined;
            const data = c.JS_GetArrayBuffer(engine.context, &total, backing);
            if ((data == null and job.bytes.len != 0) or offset > total or length > total - offset) return error.InvalidNativeNodeContent;
            if (job.bytes.len != 0) @memcpy(job.bytes, data[offset + job.from ..][0..job.bytes.len]);
        }
        const position = h.arg(args, 3);
        if (self.array_buffer_views and c.JS_IsBigInt(position)) {
            // The private Node frontend validates the full signed-64-bit
            // BigInt range before admission. Preserve it through C libuv;
            // existing typed-only owners keep their original numeric route.
            const minimum = try scope.own(try engine.checked(c.JS_NewBigInt64(engine.context, -1)));
            const maximum = try scope.own(try engine.checked(c.JS_NewBigInt64(engine.context, std.math.maxInt(i64))));
            if (scope.truthy(try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 4, position, minimum)))) or scope.truthy(try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 6, position, maximum))))) return error.InvalidNativeFilePosition;
            var at: i64 = undefined;
            if (c.JS_ToBigInt64(engine.context, &at, position) < 0) return js.capture(engine);
            if (at >= 0) job.position = @intCast(at);
        } else if (!h.nullish(position)) {
            const at = try number(engine, position);
            if (std.math.isFinite(at) and at >= 0 and at <= 9007199254740991 and @trunc(at) == at) job.position = @intFromFloat(at);
        }
    } else if (method == .readv or method == .writev) {
        const buffers = h.arg(args, 0);
        if (!c.JS_IsArray(buffers)) return error.InvalidNativeFileVector;
        const count: u32 = @intFromFloat(try boundedInteger(engine, try scope.get(buffers, "length"), 0, std.math.maxInt(u32)));
        const views = try scope.array();
        job.views = c.JS_DupValue(engine.context, views);
        job.target = c.JS_DupValue(engine.context, buffers);
        job.vectors = try engine.gpa.alloc(uv.uv_buf_t, count);
        if (self.lease_policy != null) job.pinned = try leases.Set.init(engine, count);
        var total: usize = 0;
        for (job.vectors, 0..) |*buffer, index| {
            const view = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, buffers, @intCast(index))));
            var offset: usize = undefined;
            var length: usize = undefined;
            var element: usize = undefined;
            const backing = try scope.own(try engine.checked(viewBacking(self, view, &offset, &length, &element)));
            if (length > std.math.maxInt(c_uint)) return error.InvalidNativeFileVectorLength;
            if (self.lease_policy) |*policy| {
                const lease = try leases.Lease.acquire(policy, backing, offset, length, method == .readv);
                job.pinned.?.slots[index] = lease;
                buffer.* = lease.buffer();
            } else buffer.* = uv.uv_buf_init(null, @intCast(length));
            total = try std.math.add(usize, total, length);
            try scope.index(views, @intCast(index), view);
        }
        if (self.lease_policy == null) {
            job.bytes = try engine.gpa.alloc(u8, total);
            var cursor: usize = 0;
            for (job.vectors, 0..) |*buffer, index| {
                const length: usize = @intCast(buffer.len);
                buffer.base = job.bytes.ptr + cursor;
                if (method == .writev and length != 0) {
                    const view = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, views, @intCast(index))));
                    var offset: usize = undefined;
                    var view_length: usize = undefined;
                    var element: usize = undefined;
                    const backing = try scope.own(try engine.checked(viewBacking(self, view, &offset, &view_length, &element)));
                    var backing_length: usize = undefined;
                    const data = c.JS_GetArrayBuffer(engine.context, &backing_length, backing);
                    if (data == null or offset > backing_length or view_length > backing_length - offset or length > view_length) return error.InvalidNativeNodeContent;
                    @memcpy(job.bytes[cursor..][0..length], data[offset..][0..length]);
                }
                cursor += length;
            }
        }
        const position = h.arg(args, 1);
        if (c.JS_IsNumber(position)) {
            const at = try number(engine, position);
            if (std.math.isFinite(at) and at >= 0 and at <= 9007199254740991 and @trunc(at) == at) job.position = @intFromFloat(at);
        }
    } else if (method == .truncate) job.size = @intFromFloat(try boundedInteger(engine, h.arg(args, 0), 0, 9007199254740991)) else if (method == .stat) job.bigint = scope.truthy(try h.optional(&scope, h.arg(args, 0), "bigint")) else if (method == .chmod) {
        const mode: u32 = @intFromFloat(try boundedInteger(engine, h.arg(args, 0), 0, std.math.maxInt(u32)));
        job.mode = @bitCast(mode);
    } else if (method == .chown) {
        const uid = try boundedInteger(engine, h.arg(args, 0), -1, std.math.maxInt(u32));
        const gid = try boundedInteger(engine, h.arg(args, 1), -1, std.math.maxInt(u32));
        job.uid = if (uid == -1) std.math.maxInt(uv.uv_uid_t) else @truncate(@as(u32, @intFromFloat(uid)));
        job.gid = if (gid == -1) std.math.maxInt(uv.uv_gid_t) else @truncate(@as(u32, @intFromFloat(gid)));
    } else if (method == .utimes) {
        if (!c.JS_IsNumber(h.arg(args, 0)) or !c.JS_IsNumber(h.arg(args, 1))) return error.InvalidNativeFileTime;
        job.atime = try number(engine, h.arg(args, 0));
        job.mtime = try number(engine, h.arg(args, 1));
        // Normalized Date/string inputs may deliberately carry libuv's
        // UV_FS_UTIME_OMIT (NaN) and UV_FS_UTIME_NOW (Infinity) values.
    }
    if (method == .close) {
        self.closing = true;
        if (self.active.load(.acquire) == 0) self.closed.store(true, .release);
    } else {
        _ = self.active.fetchAdd(1, .release);
        job.has_reference = true;
    }
    job.task.hub.submit(&job.task) catch |err| {
        if (method == .close) {
            self.closing = false;
            self.closed.store(false, .release);
        }
        return err;
    };
    if (method == .close) self.close_promise = c.JS_DupValue(engine.context, promise);
    return c.JS_DupValue(engine.context, promise);
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(raw)) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn boundClose(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return invoke(engine, data[0], &.{}, .close) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn fdValue(context: ?*c.JSContext, receiver: c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const self = state(engine, receiver) catch |err| return @import("native_durable.zig").reject(engine, err);
    return c.JS_NewInt64(engine.context, if (self.closed.load(.acquire)) -1 else self.fd);
}
pub fn create(scope: *h.Scope, file: std.Io.File, writable: bool, bindings: c.JSValue) !c.JSValue {
    return createFile(scope, file, writable, bindings, false);
}
// Private opt-in for genuine normalized ArrayBufferView operations. No public
// module or existing FileHandle owner selects this path until integration gates.
pub fn createArrayBufferViewFile(scope: *h.Scope, file: std.Io.File, writable: bool, bindings: c.JSValue) !c.JSValue {
    return createFile(scope, file, writable, bindings, true);
}
fn createFile(scope: *h.Scope, file: std.Io.File, writable: bool, bindings: c.JSValue, array_buffer_views: bool) !c.JSValue {
    const fd: isize = if (builtin.os.tag == .windows) Native._open_osfhandle(@intCast(@intFromPtr(file.handle)), 0x8000 | @as(c_int, if (writable) 2 else 0)) else file.handle;
    if (fd < 0) {
        file.close(scope.engine.native_io.?);
        return error.NativeFileDescriptorAdmissionFailed;
    }
    return createWithDescriptor(scope, file, fd, writable, bindings, array_buffer_views);
}
fn createWithDescriptor(scope: *h.Scope, file: std.Io.File, fd: isize, writable: bool, bindings: c.JSValue, array_buffer_views: bool) !c.JSValue {
    const engine = scope.engine;
    // This function consumes the native file on every outcome.
    var transferred = false;
    defer if (!transferred) {
        var request: uv.uv_fs_t = undefined;
        _ = uv.uv_fs_close(null, &request, @intCast(fd), null);
        uv.uv_fs_req_cleanup(&request);
    };
    if (engine.native_env_node_file_class == 0) {
        _ = c.JS_NewClassID(engine.runtime, &engine.native_env_node_file_class);
        const definition: c.JSClassDef = .{ .class_name = "FileHandle", .finalizer = finalize, .gc_mark = mark };
        if (c.JS_NewClass(engine.runtime, engine.native_env_node_file_class, &definition) < 0) return error.OutOfMemory;
    }
    const prototype = try scope.object();
    const value = try scope.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, prototype, engine.native_env_node_file_class)));
    const self = try engine.gpa.create(State);
    errdefer if (!transferred) engine.gpa.destroy(self);
    self.* = .{ .engine = engine, .file = file, .fd = fd, .writable = writable, .array_buffer_views = array_buffer_views, .bindings = c.JS_DupValue(engine.context, bindings), .close_promise = c.pi_js_undefined() };
    _ = c.JS_SetOpaque(value, self);
    transferred = true;
    const atom = c.JS_NewAtom(engine.context, "fd");
    defer c.JS_FreeAtom(engine.context, atom);
    const getter = try engine.checked(c.JS_NewCFunction2(engine.context, @ptrCast(&fdValue), "get fd", 0, c.JS_CFUNC_getter, 0));
    if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    inline for (std.meta.fields(Method)) |field| {
        if (comptime field.value == @intFromEnum(Method.close)) continue;
        const function = try engine.checked(c.JS_NewCFunctionMagic(engine.context, dispatch, field.name, switch (@as(Method, @enumFromInt(field.value))) {
            .read, .write => 4,
            .truncate, .chmod => 1,
            .chown, .utimes, .readv, .writev => 2,
            else => 0,
        }, c.JS_CFUNC_generic_magic, @intCast(field.value)));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    var close_data = [_]c.JSValue{value};
    try scope.put(value, "close", try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, boundClose, "close", 0, 0, 1, &close_data))));
    return c.JS_DupValue(engine.context, value);
}

// Takes ownership of a descriptor created by the pinned libuv open primitive.
pub fn createDescriptor(scope: *h.Scope, fd: uv.uv_file, writable: bool, bindings: c.JSValue) !c.JSValue {
    const native_file: std.Io.File = .{ .handle = if (builtin.os.tag == .windows) @ptrCast(uv.uv_get_osfhandle(fd).?) else fd, .flags = .{ .nonblocking = false } };
    return createWithDescriptor(scope, native_file, fd, writable, bindings, false);
}
pub fn createArrayBufferViewDescriptor(scope: *h.Scope, fd: uv.uv_file, writable: bool, bindings: c.JSValue) !c.JSValue {
    const native_file: std.Io.File = .{ .handle = if (builtin.os.tag == .windows) @ptrCast(uv.uv_get_osfhandle(fd).?) else fd, .flags = .{ .nonblocking = false } };
    return createWithDescriptor(scope, native_file, fd, writable, bindings, true);
}

// Genuine worker barrier for source-bound pending-I/O tests. These operations
// are not compiled into application callers and do not change buffer ownership.
pub fn holdForPendingOwnershipTest(engine: *js.Engine, receiver: c.JSValue) !void {
    if (!builtin.is_test) @compileError("Pending I/O barrier is test-only");
    const self = try state(engine, receiver);
    try self.mutex.lock(engine.native_io.?);
}
pub fn releaseForPendingOwnershipTest(engine: *js.Engine, receiver: c.JSValue) void {
    if (!builtin.is_test) @compileError("Pending I/O barrier is test-only");
    const raw = c.JS_GetOpaque(receiver, engine.native_env_node_file_class) orelse unreachable;
    const self: *State = @ptrCast(@alignCast(raw));
    self.mutex.unlock(engine.native_io.?);
}

// REVIEW ONLY: existing constructors and the default frontend never select it.
// The caller supplies an explicit aggregate virtual-address reservation cap.
pub fn createLeasedArrayBufferViewFile(scope: *h.Scope, file: std.Io.File, writable: bool, bindings: c.JSValue, virtual_limit: usize) !c.JSValue {
    const policy = leases.Policy.init(scope.engine, virtual_limit) catch |err| {
        file.close(scope.engine.native_io.?);
        return err;
    };
    const value = try createFile(scope, file, writable, bindings, true);
    errdefer scope.engine.freeValue(value);
    (try state(scope.engine, value)).lease_policy = policy;
    return value;
}
