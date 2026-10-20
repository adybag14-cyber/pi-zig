//! Physical controls for the one shared libuv service and typed FS requests.
//! These use real files, intrinsic backing leases and actual UV callbacks.
//! The original twelve TCP controls stay in their unchanged separate root.
const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
    @cInclude("native_uv_tcp.h");
    @cInclude("native_uv_fs.h");
    @cInclude("uv.h");
    @cInclude("fcntl.h");
});
const gpa = std.testing.allocator;
const io = std.testing.io;
const memory_limit: usize = 16 * 1024 * 1024;
const wake_slot: u32 = 29;
const wake_generation: u64 = 0x8172635445362718;
var wake_count: std.atomic.Value(usize) = .init(0);
var wrong_wake: std.atomic.Value(bool) = .init(false);
fn notified(slot: u32, generation: u64) callconv(.c) void {
    if (slot != wake_slot or generation != wake_generation)
        wrong_wake.store(true, .release);
    _ = wake_count.fetchAdd(1, .monotonic);
}
fn status(value: c_int) !void {
    if (value < 0) {
        std.debug.print("actual FS transport status {d}: {s}\n",
            .{ value, std.mem.span(c.pi_uv_error_name(value)) });
        return error.ActualFSTransportStatus;
    }
}
fn allocated(value: c.PiUvResult) !void {
    try std.testing.expectEqual(@as(c_int, 0), value.allocation_failed);
    try status(value.status);
}
fn descriptorStatus(fd: c_int) c_int {
    var request: c.uv_fs_t = undefined;
    const result = c.uv_fs_fstat(null, &request, fd, null);
    c.uv_fs_req_cleanup(&request);
    return result;
}
fn closeDescriptor(fd: c_int) void {
    var request: c.uv_fs_t = undefined;
    _ = c.uv_fs_close(null, &request, fd, null);
    c.uv_fs_req_cleanup(&request);
}
const File = struct {
    temporary: std.testing.TmpDir,
    path: [:0]u8,
    fn init(self: *File, bytes: []const u8) !void {
        self.temporary = std.testing.tmpDir(.{});
        errdefer self.temporary.cleanup();
        try self.temporary.dir.writeFile(io, .{ .sub_path = "actual.bin", .data = bytes });
        const directory = try self.temporary.dir.realPathFileAlloc(io, ".", gpa);
        defer gpa.free(directory);
        const joined = try std.fs.path.join(gpa, &.{directory, "actual.bin"});
        defer gpa.free(joined);
        self.path = try gpa.dupeZ(u8, joined);
    }
    fn deinit(self: *File) void {
        gpa.free(self.path);
        self.temporary.cleanup();
    }
};
const Fixture = struct {
    runtime: ?*c.JSRuntime = null,
    context: ?*c.JSContext = null,
    memory: ?*anyopaque = null,
    service: ?*c.PiUvService = null,
    requests: [32]?*c.PiUvFsRequest = @splat(null),
    events: [64]?*c.PiUvEvent = @splat(null),
    endpoints: [8]?*c.PiUvEndpoint = @splat(null),
    descriptors: [16]c_int = @splat(-1),
    // Successful OPEN results have an independent descriptor entitlement.
    // Keep its unclaimed result visible even if a wait/assertion fails.
    opens: [32]?*c.PiUvFsRequest = @splat(null),
    closes: [16]?struct { request: *c.PiUvFsRequest, descriptor: c_int } = @splat(null),

    fn init(self: *Fixture) !void {
        self.* = .{};
        wake_count.store(0, .release);
        wrong_wake.store(false, .release);
        self.runtime = c.pi_js_new_runtime(memory_limit, &self.memory) orelse return error.OutOfMemory;
        errdefer self.deinit();
        self.context = c.JS_NewContext(self.runtime.?) orelse return error.OutOfMemory;
        try allocated(c.pi_uv_service_create(self.memory, notified,
            wake_slot, wake_generation, &self.service));
        try std.testing.expect(self.service != null);
    }
    fn checked(self: *Fixture, value: c.JSValue) !c.JSValue {
        if (c.JS_IsException(value) or c.JS_HasException(self.context.?)) {
            if (!c.JS_IsException(value)) c.JS_FreeValue(self.context.?, value);
            const reason = c.JS_GetException(self.context.?);
            c.JS_FreeValue(self.context.?, reason);
            return error.ActualFSTransportJavaScriptException;
        }
        return value;
    }
    fn keepRequest(self: *Fixture, value: *c.PiUvFsRequest) !void {
        for (&self.requests) |*slot| if (slot.* == null) {
            slot.* = value;
            return;
        };
        c.pi_uv_fs_request_release(value);
        return error.ActualFSRequestControlCapacity;
    }
    fn request(self: *Fixture, kind: c_int, token: u64) !*c.PiUvFsRequest {
        var result: ?*c.PiUvFsRequest = null;
        const outcome = c.pi_uv_fs_request_create(self.service.?, kind, token, &result);
        if (result) |value| try self.keepRequest(value);
        try allocated(outcome);
        return result orelse return error.ActualFSRequestMissing;
    }
    fn releaseRequest(self: *Fixture, value: *c.PiUvFsRequest) void {
        for (&self.requests) |*slot| if (slot.* == value) {
            slot.* = null;
            c.pi_uv_fs_request_release(value);
            return;
        };
        @panic("actual FS control lost its request entitlement");
    }
    fn storeEvent(self: *Fixture, value: *c.PiUvEvent) !void {
        for (&self.events) |*slot| if (slot.* == null) {
            slot.* = value;
            return;
        };
        c.pi_uv_event_release(value);
        return error.ActualFSEventControlCapacity;
    }
    fn releaseEvent(self: *Fixture, value: *c.PiUvEvent) void {
        for (&self.events) |*slot| if (slot.* == value) {
            slot.* = null;
            c.pi_uv_event_release(value);
            return;
        };
        @panic("actual FS control lost its event entitlement");
    }
    fn take(self: *Fixture, kind: c_int, token: u64) !*c.PiUvEvent {
        const until = c.uv_hrtime() + 10 * std.time.ns_per_s;
        while (true) {
            for (self.events) |slot| if (slot) |event| {
                const info = c.pi_uv_event_info(event);
                if (info.kind == kind and info.token == token) return event;
                if (info.kind == c.PI_UV_NATIVE_ALLOCATION_FAILURE)
                    return error.UnexpectedActualFSAllocationEvent;
            };
            if (c.pi_uv_service_next(self.service.?)) |event| {
                try self.storeEvent(event);
                continue;
            }
            if (c.uv_hrtime() >= until) return error.ActualFSCompletionTimeout;
            c.uv_sleep(1);
        }
    }
    fn waitQueued(self: *Fixture, count: usize) !void {
        const until = c.uv_hrtime() + 10 * std.time.ns_per_s;
        while (c.pi_uv_service_snapshot(self.service.?).queued_events < count) {
            if (c.uv_hrtime() >= until) return error.ActualFSCompletionTimeout;
            c.uv_sleep(1);
        }
    }
    fn next(self: *Fixture) !*c.PiUvEvent {
        const event = c.pi_uv_service_next(self.service.?) orelse
            return error.ActualFSQueuedEventRequired;
        try self.storeEvent(event);
        return event;
    }
    fn empty(self: *Fixture) !void {
        const extra = c.pi_uv_service_next(self.service.?);
        if (extra) |event| try self.storeEvent(event);
        try std.testing.expect(extra == null);
        try std.testing.expectEqual(@as(usize, 0),
            c.pi_uv_service_snapshot(self.service.?).queued_events);
    }
    fn ownDescriptor(self: *Fixture, fd: c_int) !c_int {
        for (&self.descriptors) |*slot| if (slot.* == -1) {
            slot.* = fd;
            return fd;
        };
        closeDescriptor(fd);
        return error.ActualFSDescriptorControlCapacity;
    }
    fn forgetDescriptor(self: *Fixture, fd: c_int) void {
        for (&self.descriptors) |*slot| if (slot.* == fd) {
            slot.* = -1;
            return;
        };
        @panic("actual FS control lost its descriptor entitlement");
    }
    fn submitOpen(self: *Fixture, request_value: *c.PiUvFsRequest, path: [*:0]const u8) !c_int {
        for (&self.opens) |*slot| if (slot.* == null) {
            slot.* = request_value;
            return c.pi_uv_fs_open(request_value, path, c.O_RDONLY, 0);
        };
        return error.ActualFSOpenControlCapacity;
    }
    fn adoptOpen(self: *Fixture, request_value: *c.PiUvFsRequest, result: i64) !c_int {
        for (&self.opens) |*slot| if (slot.* == request_value) {
            slot.* = null;
            return if (result >= 0) try self.ownDescriptor(@intCast(result)) else -1;
        };
        return error.ActualFSOpenControlOwnerRequired;
    }
    fn open(self: *Fixture, path: [*:0]const u8, token: u64) !c_int {
        const request_value = try self.request(c.PI_UV_FS_OPEN, token);
        try status(try self.submitOpen(request_value, path));
        const event = try self.take(c.PI_UV_FS_COMPLETION, token);
        defer self.releaseEvent(event);
        const actual = c.pi_uv_fs_request_info(request_value);
        // Adopt a successful native fd before any following assertion can fail.
        const fd = try self.adoptOpen(request_value, actual.result);
        try std.testing.expect(c.pi_uv_event_fs_request(event) == request_value);
        try std.testing.expectEqual(@as(c_int, 1), actual.accepted);
        if (actual.result < 0) try status(@intCast(actual.result));
        c.pi_uv_fs_request_cleanup(request_value);
        return fd;
    }
    fn read(self: *Fixture, fd: c_int, backing: *const c.JSPiArrayBufferLease,
        offset: usize, length: u32, position: i64, token: u64) !i64
    {
        const request_value = try self.request(c.PI_UV_FS_READ, token);
        try status(c.pi_uv_fs_read(request_value, fd, backing, offset, length, position));
        const event = try self.take(c.PI_UV_FS_COMPLETION, token);
        defer self.releaseEvent(event);
        const actual = c.pi_uv_fs_request_info(request_value);
        try std.testing.expect(c.pi_uv_event_fs_request(event) == request_value);
        try std.testing.expectEqual(@as(c_int, 1), actual.accepted);
        try std.testing.expectEqual(@as(c_int, c.PI_UV_FS_READ), actual.kind);
        c.pi_uv_fs_request_cleanup(request_value);
        return actual.result;
    }
    fn submitClose(self: *Fixture, request_value: *c.PiUvFsRequest, fd: c_int) !c_int {
        for (&self.closes) |*slot| if (slot.* == null) {
            slot.* = .{ .request = request_value, .descriptor = fd };
            return c.pi_uv_fs_close(request_value, fd);
        };
        return error.ActualFSCloseControlCapacity;
    }
    fn completeClose(self: *Fixture, request_value: *c.PiUvFsRequest, result: i64) void {
        for (&self.closes) |*slot| if (slot.*) |closing| {
            if (closing.request != request_value) continue;
            slot.* = null;
            if (result == 0) self.forgetDescriptor(closing.descriptor);
            return;
        };
        @panic("actual FS control lost its close entitlement");
    }
    fn close(self: *Fixture, fd: c_int, token: u64) !void {
        const request_value = try self.request(c.PI_UV_FS_CLOSE, token);
        try status(try self.submitClose(request_value, fd));
        const event = try self.take(c.PI_UV_FS_COMPLETION, token);
        defer self.releaseEvent(event);
        const actual = c.pi_uv_fs_request_info(request_value);
        self.completeClose(request_value, actual.result);
        try std.testing.expectEqual(@as(i64, 0), actual.result);
        try std.testing.expectEqual(@as(c_int, 1), actual.accepted);
        try std.testing.expect(c.pi_uv_event_fs_request(event) == request_value);
        c.pi_uv_fs_request_cleanup(request_value);
    }
    fn endpoint(self: *Fixture) !*c.PiUvEndpoint {
        var result: ?*c.PiUvEndpoint = null;
        const outcome = c.pi_uv_tcp_create(self.service.?, &result);
        if (result) |value| {
            for (&self.endpoints) |*slot| if (slot.* == null) {
                slot.* = value;
                try allocated(outcome);
                return value;
            };
            c.pi_uv_endpoint_abandon(value);
            c.pi_uv_endpoint_release(value);
            return error.ActualFSEndpointControlCapacity;
        }
        try allocated(outcome);
        return error.ActualFSNativeEndpointRequired;
    }
    fn stop(self: *Fixture) !void {
        try std.testing.expectEqual(@as(c_int, 0), c.pi_uv_service_stop(self.service.?));
        const snapshot = c.pi_uv_service_snapshot(self.service.?);
        try std.testing.expect(snapshot.thread_joined != 0 and snapshot.close_requested != 0);
        try std.testing.expectEqual(@as(usize, 0), snapshot.live_handles);
        try std.testing.expectEqual(@as(usize, 0), snapshot.pending_requests);
        try std.testing.expectEqual(@as(c_int, 0), snapshot.loop_close_status);
        try std.testing.expect(!wrong_wake.load(.acquire));
    }
    fn dropVm(self: *Fixture) void {
        if (self.context) |context| { self.context = null; c.JS_FreeContext(context); }
        if (self.runtime) |runtime| { self.runtime = null; c.JS_FreeRuntime(runtime); }
    }
    fn deinit(self: *Fixture) void {
        if (self.service) |service| {
            if (c.pi_uv_service_stop(service) != 0)
                @panic("actual FS control service did not join");
            for (&self.opens) |*slot| if (slot.*) |request_value| {
                slot.* = null;
                const result = c.pi_uv_fs_request_info(request_value).result;
                if (result >= 0) closeDescriptor(@intCast(result));
            };
            // An actual close may have succeeded before a failed wait/assertion.
            // Consume that descriptor entitlement before generic fallback close.
            for (&self.closes) |*slot| if (slot.*) |closing| {
                slot.* = null;
                if (c.pi_uv_fs_request_info(closing.request).result == 0)
                    self.forgetDescriptor(closing.descriptor);
            };
            for (&self.events) |*slot| if (slot.*) |event| {
                slot.* = null;
                c.pi_uv_event_release(event);
            };
            while (c.pi_uv_service_next(service)) |event| c.pi_uv_event_release(event);
            for (&self.requests) |*slot| if (slot.*) |request_value| {
                slot.* = null;
                c.pi_uv_fs_request_release(request_value);
            };
            for (&self.endpoints) |*slot| if (slot.*) |endpoint_value| {
                slot.* = null;
                c.pi_uv_endpoint_release(endpoint_value);
            };
            c.pi_uv_service_release(service);
            self.service = null;
        }
        for (&self.descriptors) |*slot| if (slot.* != -1) {
            const fd = slot.*;
            slot.* = -1;
            closeDescriptor(fd);
        };
        self.dropVm();
        if (self.memory) |memory| { self.memory = null; c.pi_js_release_memory_owner(memory); }
    }
};
const Buffer = struct {
    buffer: ?c.JSValue = null,
    view: ?c.JSValue = null,
    lease: c.JSPiArrayBufferLease = std.mem.zeroes(c.JSPiArrayBufferLease),
    fn init(self: *Buffer, f: *Fixture, length: usize) !void {
        self.* = .{};
        errdefer self.deinit(f);
        self.buffer = try f.checked(c.JS_NewArrayBufferCopy(f.context.?, null, length));
        var args = [_]c.JSValue{self.buffer.?};
        self.view = try f.checked(c.JS_NewTypedArray(f.context.?, 1, &args, c.JS_TYPED_ARRAY_UINT8));
        const result = c.JS_PiAcquireArrayBufferView(f.context.?, self.view.?, &self.lease);
        try std.testing.expectEqual(@as(c_int, 1), result);
        try std.testing.expect(!c.JS_HasException(f.context.?));
        try std.testing.expectEqual(length, self.lease.byte_length);
    }
    fn dropJs(self: *Buffer, f: *Fixture) void {
        if (self.view) |value| { self.view = null; c.JS_FreeValue(f.context.?, value); }
        if (self.buffer) |value| { self.buffer = null; c.JS_FreeValue(f.context.?, value); }
    }
    fn deinit(self: *Buffer, f: *Fixture) void {
        self.dropJs(f);
        c.JS_PiReleaseArrayBufferLease(&self.lease);
    }
};

test "native actual FS transport constructs request storage before dispatch and rolls it back unsubmitted" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const before = c.pi_js_native_memory_used(f.memory);
    inline for (.{ c.PI_UV_FS_READ, c.PI_UV_FS_OPEN, c.PI_UV_FS_CLOSE }) |kind| {
        const request_value = try f.request(kind, @intCast(kind));
        try std.testing.expect(c.pi_js_native_memory_used(f.memory) > before);
        try std.testing.expectEqual(@as(c_int, c.UV_EINVAL), c.pi_uv_fs_cancel(request_value));
        try std.testing.expectEqual(@as(usize, 0), c.pi_uv_service_snapshot(f.service.?).pending_requests);
        try f.empty();
        f.releaseRequest(request_value);
        try std.testing.expectEqual(before, c.pi_js_native_memory_used(f.memory));
    }
}
test "native actual FS transport distinguishes charged wrapper allocation failure from ordinary invalid input" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const used = c.pi_js_native_memory_used(f.memory);
    const reservation = memory_limit - used;
    try std.testing.expect(c.pi_js_native_memory_reserve(f.memory, reservation) != 0);
    var output: ?*c.PiUvFsRequest = null;
    const exhausted = c.pi_uv_fs_request_create(f.service.?, c.PI_UV_FS_READ, 10, &output);
    c.pi_js_native_memory_release(f.memory, reservation);
    if (output) |value| try f.keepRequest(value);
    try std.testing.expectEqual(@as(c_int, c.UV_ENOMEM), exhausted.status);
    try std.testing.expectEqual(@as(c_int, 1), exhausted.allocation_failed);
    try std.testing.expect(output == null);
    try std.testing.expectEqual(used, c.pi_js_native_memory_used(f.memory));
    const invalid = c.pi_uv_fs_request_create(f.service.?, -1, 11, &output);
    if (output) |value| try f.keepRequest(value);
    try std.testing.expectEqual(@as(c_int, c.UV_EINVAL), invalid.status);
    try std.testing.expectEqual(@as(c_int, 0), invalid.allocation_failed);
    try std.testing.expect(output == null);
    try f.empty();
}
test "native actual FS transport opens a real path and defers uv cleanup until the explicit cutpoint" {
    var file: File = undefined; try file.init("path bytes"); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const supplied = try gpa.dupeZ(u8, file.path); defer gpa.free(supplied);
    const request_value = try f.request(c.PI_UV_FS_OPEN, 21);
    try status(try f.submitOpen(request_value, supplied));
    @memset(supplied[0..supplied.len], 'x');
    const event = try f.take(c.PI_UV_FS_COMPLETION, 21);
    const info = c.pi_uv_fs_request_info(request_value);
    const fd = try f.adoptOpen(request_value, info.result);
    try std.testing.expect(info.result >= 0);
    try std.testing.expect(info.path != null);
    try std.testing.expectEqualStrings(file.path, std.mem.span(info.path));
    try std.testing.expectEqual(@as(c_int, 0), info.cleaned);
    try std.testing.expect(c.pi_uv_event_fs_request(event) == request_value);
    c.pi_uv_fs_request_cleanup(request_value);
    c.pi_uv_fs_request_cleanup(request_value);
    const cleaned = c.pi_uv_fs_request_info(request_value);
    try std.testing.expect(cleaned.path == null and cleaned.cleaned == 1);
    try std.testing.expectEqual(@as(c_int, 0), descriptorStatus(fd));
    f.releaseEvent(event);
    f.releaseRequest(request_value);
    try std.testing.expectEqual(@as(c_int, 0), descriptorStatus(fd));
    try f.close(fd, 22);
    try std.testing.expectEqual(@as(c_int, c.UV_EBADF), descriptorStatus(fd));
}
test "native actual FS transport reads the real offset span position EOF and zero length" {
    var file: File = undefined; try file.init("ABCDEFGH"); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fd = try f.open(file.path, 30);
    var buffer: Buffer = .{}; try buffer.init(&f, 16); defer buffer.deinit(&f);
    @memset(buffer.lease.data[0..buffer.lease.byte_length], 0xcc);
    try std.testing.expectEqual(@as(i64, 3), try f.read(fd, &buffer.lease, 4, 3, 2, 31));
    try std.testing.expectEqualStrings("CDE", buffer.lease.data[4..7]);
    try std.testing.expectEqual(@as(u8, 0xcc), buffer.lease.data[3]);
    try std.testing.expectEqual(@as(u8, 0xcc), buffer.lease.data[7]);
    try std.testing.expectEqual(@as(i64, 2), try f.read(fd, &buffer.lease, 0, 2, -1, 32));
    try std.testing.expectEqualStrings("AB", buffer.lease.data[0..2]);
    try std.testing.expectEqual(@as(i64, 2), try f.read(fd, &buffer.lease, 2, 2, -1, 33));
    try std.testing.expectEqualStrings("CD", buffer.lease.data[2..4]);
    try std.testing.expectEqual(@as(i64, 0), try f.read(fd, &buffer.lease, 8, 3, 100, 34));
    try std.testing.expectEqual(@as(i64, 0), try f.read(fd, &buffer.lease, 8, 0, 0, 35));
    try f.close(fd, 36);
}
test "native actual FS transport reports ordinary bad descriptor through one genuine accepted callback" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    var buffer: Buffer = .{}; try buffer.init(&f, 8); defer buffer.deinit(&f);
    const request_value = try f.request(c.PI_UV_FS_READ, 41);
    try status(c.pi_uv_fs_read(request_value, -1, &buffer.lease, 0, 1, 0));
    const event = try f.take(c.PI_UV_FS_COMPLETION, 41);
    const info = c.pi_uv_fs_request_info(request_value);
    try std.testing.expectEqual(@as(c_int, 1), info.accepted);
    try std.testing.expectEqual(@as(i64, c.UV_EBADF), info.result);
    try std.testing.expectEqual(@as(c_int, c.UV_EBADF), c.pi_uv_event_info(event).status);
    try std.testing.expectEqual(@as(c_int, c.UV_EINVAL), c.pi_uv_fs_cancel(request_value));
    c.pi_uv_fs_request_cleanup(request_value);
    f.releaseEvent(event);
    try f.empty();
    try std.testing.expectEqual(@as(usize, 0), c.pi_uv_service_snapshot(f.service.?).pending_requests);
}
test "native actual FS transport rejects invalid spans without submitting or consuming the request" {
    var file: File = undefined; try file.init("span"); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fd = try f.open(file.path, 50);
    var buffer: Buffer = .{}; try buffer.init(&f, 8); defer buffer.deinit(&f);
    const request_value = try f.request(c.PI_UV_FS_READ, 51);
    const before = c.pi_js_native_memory_used(f.memory);
    try std.testing.expectEqual(@as(c_int, c.UV_EINVAL),
        c.pi_uv_fs_read(request_value, fd, &buffer.lease, 9, 0, 0));
    try std.testing.expectEqual(@as(c_int, c.UV_EINVAL),
        c.pi_uv_fs_read(request_value, fd, &buffer.lease, 7, 2, 0));
    try std.testing.expectEqual(@as(c_int, c.UV_EINVAL),
        c.pi_uv_fs_read(request_value, fd, &buffer.lease, 0, std.math.maxInt(u32), 0));
    try std.testing.expectEqual(before, c.pi_js_native_memory_used(f.memory));
    try f.empty();
    try status(c.pi_uv_fs_read(request_value, fd, &buffer.lease, 0, 4, 0));
    const event = try f.take(c.PI_UV_FS_COMPLETION, 51);
    try std.testing.expectEqual(@as(i64, 4), c.pi_uv_fs_request_info(request_value).result);
    try std.testing.expectEqualStrings("span", buffer.lease.data[0..4]);
    try std.testing.expectEqual(@as(c_int, c.UV_EINVAL),
        c.pi_uv_fs_read(request_value, fd, &buffer.lease, 0, 4, 0));
    c.pi_uv_fs_request_cleanup(request_value);
    f.releaseEvent(event);
    try f.close(fd, 52);
}
test "native actual FS transport retains the original backing allocation through guest detachment" {
    var file: File = undefined; try file.init("detached"); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fd = try f.open(file.path, 60);
    var buffer: Buffer = .{}; try buffer.init(&f, 8); defer buffer.deinit(&f);
    const bytes = buffer.lease.data;
    const request_value = try f.request(c.PI_UV_FS_READ, 61);
    try status(c.pi_uv_fs_read(request_value, fd, &buffer.lease, 0, 8, 0));
    c.JS_DetachArrayBuffer(f.context.?, buffer.buffer.?);
    const length = try f.checked(c.JS_GetPropertyStr(f.context.?, buffer.buffer.?, "byteLength"));
    defer c.JS_FreeValue(f.context.?, length);
    var actual_length: i32 = -1;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(f.context.?, &actual_length, length));
    try std.testing.expectEqual(@as(i32, 0), actual_length);
    buffer.dropJs(&f);
    c.JS_PiReleaseArrayBufferLease(&buffer.lease);
    const event = try f.take(c.PI_UV_FS_COMPLETION, 61);
    try std.testing.expectEqual(@as(i64, 8), c.pi_uv_fs_request_info(request_value).result);
    try std.testing.expectEqualStrings("detached", bytes[0..8]);
    c.pi_uv_fs_request_cleanup(request_value);
    f.releaseEvent(event);
    try f.close(fd, 62);
}
test "native actual FS transport request backing and event survive the original runtime and memory entitlement" {
    const owners_before = c.pi_js_native_memory_owners();
    var file: File = undefined; try file.init("native"); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fd = try f.open(file.path, 70);
    var buffer: Buffer = .{}; try buffer.init(&f, 6); defer buffer.deinit(&f);
    const bytes = buffer.lease.data;
    const request_value = try f.request(c.PI_UV_FS_READ, 71);
    try status(c.pi_uv_fs_read(request_value, fd, &buffer.lease, 0, 6, 0));
    buffer.dropJs(&f);
    c.JS_PiReleaseArrayBufferLease(&buffer.lease);
    f.dropVm();
    c.pi_js_release_memory_owner(f.memory); f.memory = null;
    try std.testing.expectEqual(owners_before + 1, c.pi_js_native_memory_owners());
    const event = try f.take(c.PI_UV_FS_COMPLETION, 71);
    try std.testing.expectEqual(@as(i64, 6), c.pi_uv_fs_request_info(request_value).result);
    try std.testing.expectEqualStrings("native", bytes[0..6]);
    try f.stop();
    c.pi_uv_fs_request_cleanup(request_value);
    f.releaseEvent(event);
    f.deinit();
    try std.testing.expectEqual(owners_before, c.pi_js_native_memory_owners());
}
test "native actual FS transport event owns a request after its initial caller entitlement is released" {
    var file: File = undefined; try file.init("event"); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fd = try f.open(file.path, 80);
    var buffer: Buffer = .{}; try buffer.init(&f, 5); defer buffer.deinit(&f);
    const request_value = try f.request(c.PI_UV_FS_READ, 81);
    try status(c.pi_uv_fs_read(request_value, fd, &buffer.lease, 0, 5, 0));
    f.releaseRequest(request_value);
    const event = try f.take(c.PI_UV_FS_COMPLETION, 81);
    const retained = c.pi_uv_event_fs_request(event) orelse return error.ActualFSEventRequestMissing;
    try std.testing.expect(retained == request_value);
    try std.testing.expectEqual(@as(i64, 5), c.pi_uv_fs_request_info(retained).result);
    c.pi_uv_fs_request_retain(retained);
    try f.keepRequest(retained);
    f.releaseEvent(event);
    try std.testing.expectEqual(@as(i64, 5), c.pi_uv_fs_request_info(retained).result);
    try std.testing.expectEqualStrings("event", buffer.lease.data[0..5]);
    c.pi_uv_fs_request_cleanup(retained);
    f.releaseRequest(retained);
    try f.close(fd, 82);
}
test "native actual FS transport cancellation preserves the one actual callback across completion races" {
    var file: File = undefined; try file.init("cancel"); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fd = try f.open(file.path, 90);
    var buffer: Buffer = .{}; try buffer.init(&f, 6); defer buffer.deinit(&f);
    const request_value = try f.request(c.PI_UV_FS_READ, 91);
    try status(c.pi_uv_fs_read(request_value, fd, &buffer.lease, 0, 6, 0));
    const canceled = c.pi_uv_fs_cancel(request_value);
    try std.testing.expect(canceled == 0 or canceled == c.UV_EBUSY or canceled == c.UV_EINVAL);
    const event = try f.take(c.PI_UV_FS_COMPLETION, 91);
    const info = c.pi_uv_fs_request_info(request_value);
    try std.testing.expectEqual(@as(c_int, 1), info.accepted);
    if (canceled == 0) {
        try std.testing.expectEqual(@as(i64, c.UV_ECANCELED), info.result);
    } else {
        try std.testing.expectEqual(@as(i64, 6), info.result);
        try std.testing.expectEqualStrings("cancel", buffer.lease.data[0..6]);
    }
    try std.testing.expectEqual(@as(c_int, c.UV_EINVAL), c.pi_uv_fs_cancel(request_value));
    c.pi_uv_fs_request_cleanup(request_value);
    f.releaseEvent(event);
    try f.empty();
    try f.close(fd, 92);
}
test "native actual FS transport rejected open admission cannot cancel an uninitialized work request" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const request_value = try f.request(c.PI_UV_FS_OPEN, 101);
    if (builtin.os.tag == .windows) {
        // Actual fs__capture_path rejects this before uv__work_submit while
        // the real uv_fs_t INIT has already executed.
        const invalid_utf8 = [_:0]u8{0xff};
        const rejected = c.pi_uv_fs_open(request_value, &invalid_utf8, c.O_RDONLY, 0);
        try std.testing.expect(rejected < 0);
        const info = c.pi_uv_fs_request_info(request_value);
        try std.testing.expectEqual(@as(i64, rejected), info.result);
        try std.testing.expect(info.accepted == 0 and info.path == null);
    } else {
        // Unix accepts arbitrary non-NUL path bytes. Its no-admission control
        // uses the typed API's genuine null-path rejection without pretending
        // that a Windows UTF-16 conversion runs on this platform.
        try std.testing.expectEqual(@as(c_int, c.UV_EINVAL),
            c.pi_uv_fs_open(request_value, null, c.O_RDONLY, 0));
    }
    try std.testing.expectEqual(@as(c_int, c.UV_EINVAL), c.pi_uv_fs_cancel(request_value));
    try std.testing.expectEqual(@as(usize, 0), c.pi_uv_service_snapshot(f.service.?).pending_requests);
    try f.empty();
    c.pi_uv_fs_request_cleanup(request_value);
}
test "native actual FS transport and TCP closure share one ordered native event FIFO" {
    var file: File = undefined; try file.init("fifo"); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    inline for (.{ false, true }) |fs_first| {
        const fs_token: u64 = if (fs_first) 113 else 111;
        const tcp_token: u64 = if (fs_first) 114 else 112;
        const endpoint_value = try f.endpoint();
        const request_value = try f.request(c.PI_UV_FS_OPEN, fs_token);
        if (fs_first) {
            try status(try f.submitOpen(request_value, file.path));
        } else try status(c.pi_uv_tcp_close(endpoint_value, tcp_token));
        try f.waitQueued(1);
        if (fs_first) {
            try status(c.pi_uv_tcp_close(endpoint_value, tcp_token));
        } else try status(try f.submitOpen(request_value, file.path));
        try f.waitQueued(2);
        // Adopt the successful fd before any order assertion can fail.
        const info = c.pi_uv_fs_request_info(request_value);
        const fd = try f.adoptOpen(request_value, info.result);
        try std.testing.expect(info.result >= 0);
        const first = try f.next();
        const second = try f.next();
        const fs_event = if (fs_first) first else second;
        const tcp_event = if (fs_first) second else first;
        try std.testing.expectEqual(fs_token, c.pi_uv_event_info(fs_event).token);
        try std.testing.expectEqual(@as(c_int, c.PI_UV_FS_COMPLETION), c.pi_uv_event_info(fs_event).kind);
        try std.testing.expect(c.pi_uv_event_fs_request(fs_event) == request_value);
        try std.testing.expectEqual(tcp_token, c.pi_uv_event_info(tcp_event).token);
        try std.testing.expectEqual(@as(c_int, c.PI_UV_CLOSE), c.pi_uv_event_info(tcp_event).kind);
        try std.testing.expect(c.pi_uv_event_fs_request(tcp_event) == null);
        c.pi_uv_fs_request_cleanup(request_value);
        f.releaseEvent(first); f.releaseEvent(second);
        try f.empty();
        try f.close(fd, fs_token + 100);
    }
}
test "native actual FS transport stop joins all accepted requests and retains every completion for draining" {
    var file: File = undefined; try file.init("join"); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fd = try f.open(file.path, 120);
    var buffer: Buffer = .{}; try buffer.init(&f, 32); defer buffer.deinit(&f);
    var requests: [8]*c.PiUvFsRequest = undefined;
    for (&requests, 0..) |*slot, index| {
        slot.* = try f.request(c.PI_UV_FS_READ, 121 + index);
        try status(c.pi_uv_fs_read(slot.*, fd, &buffer.lease, index * 4, 4, 0));
    }
    try f.stop();
    try std.testing.expectEqual(@as(usize, 8), c.pi_uv_service_snapshot(f.service.?).queued_events);
    for (requests, 0..) |request_value, index| {
        const event = try f.take(c.PI_UV_FS_COMPLETION, 121 + index);
        const info = c.pi_uv_fs_request_info(request_value);
        try std.testing.expectEqual(@as(c_int, 1), info.accepted);
        try std.testing.expect(info.result == 4 or info.result == c.UV_ECANCELED);
        if (info.result == 4)
            try std.testing.expectEqualStrings("join", buffer.lease.data[index * 4 ..][0..4]);
        c.pi_uv_fs_request_cleanup(request_value);
        f.releaseEvent(event);
        f.releaseRequest(request_value);
    }
    try f.empty();
    try std.testing.expect(!wrong_wake.load(.acquire));
    try std.testing.expect(wake_count.load(.acquire) >= 9);
}
test "native actual FS transport stopped admission remains an ordinary status with explicit cleanup and no event" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const request_value = try f.request(c.PI_UV_FS_CLOSE, 141);
    try f.stop();
    try std.testing.expectEqual(@as(c_int, c.UV_ECANCELED), c.pi_uv_fs_close(request_value, -1));
    const info = c.pi_uv_fs_request_info(request_value);
    try std.testing.expectEqual(@as(i64, c.UV_ECANCELED), info.result);
    try std.testing.expect(info.accepted == 0 and info.path == null and info.cleaned == 0);
    c.pi_uv_fs_request_cleanup(request_value);
    c.pi_uv_fs_request_cleanup(request_value);
    try std.testing.expectEqual(@as(c_int, 1), c.pi_uv_fs_request_info(request_value).cleaned);
    try std.testing.expectEqual(@as(c_int, c.UV_ECANCELED), c.pi_uv_fs_cancel(request_value));
    try f.empty();
}
