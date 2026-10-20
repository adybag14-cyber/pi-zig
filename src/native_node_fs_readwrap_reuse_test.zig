//! Real raw-span and completed-request reuse controls for the shared UV service.
//! This root consumes the separately reviewed read_buffer/request_reset ABI.
//! Every dequeued event has a distinct ticket, even when its embedded address
//! is reused. After Reset an older ticket is release-only: never inspect it.
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
const wake_slot: u32 = 43;
const wake_generation: u64 = 0x43524f5752455553;
var wrong_wake: std.atomic.Value(bool) = .init(false);

fn notified(slot: u32, generation: u64) callconv(.c) void {
    if (slot != wake_slot or generation != wake_generation)
        wrong_wake.store(true, .release);
}
fn status(actual: c_int) !void {
    if (actual < 0) {
        std.debug.print("actual FS reuse status {d}: {s}\n",
            .{ actual, std.mem.span(c.pi_uv_error_name(actual)) });
        return error.ActualFSReuseStatus;
    }
}
fn allocated(actual: c.PiUvResult) !void {
    try std.testing.expectEqual(@as(c_int, 0), actual.allocation_failed);
    try status(actual.status);
}
fn closeDescriptor(fd: c_int) void {
    var native: c.uv_fs_t = undefined;
    _ = c.uv_fs_close(null, &native, fd, null);
    c.uv_fs_req_cleanup(&native);
}
const File = struct {
    temporary: std.testing.TmpDir,
    path: [:0]u8,
    fn init(self: *File, bytes: []const u8) !void {
        self.temporary = std.testing.tmpDir(.{});
        errdefer self.temporary.cleanup();
        try self.temporary.dir.writeFile(io, .{ .sub_path = "reuse.bin", .data = bytes });
        const directory = try self.temporary.dir.realPathFileAlloc(io, ".", gpa);
        defer gpa.free(directory);
        const joined = try std.fs.path.join(gpa, &.{ directory, "reuse.bin" });
        defer gpa.free(joined);
        self.path = try gpa.dupeZ(u8, joined);
    }
    fn deinit(self: *File) void {
        gpa.free(self.path);
        self.temporary.cleanup();
    }
};
const Ticket = usize;
const Fixture = struct {
    runtime: ?*c.JSRuntime = null,
    context: ?*c.JSContext = null,
    memory: ?*anyopaque = null,
    service: ?*c.PiUvService = null,
    requests: [16]?*c.PiUvFsRequest = @splat(null),
    // Each slot is one actual entitlement, not a unique pointer registry.
    // Multiple occupied slots may intentionally contain the same address.
    events: [32]?*c.PiUvEvent = @splat(null),
    descriptors: [8]c_int = @splat(-1),

    fn init(self: *Fixture) !void {
        self.* = .{};
        wrong_wake.store(false, .release);
        self.runtime = c.pi_js_new_runtime(memory_limit, &self.memory) orelse return error.OutOfMemory;
        errdefer self.deinit();
        self.context = c.JS_NewContext(self.runtime.?) orelse return error.OutOfMemory;
        try allocated(c.pi_uv_service_create(self.memory, notified,
            wake_slot, wake_generation, &self.service));
        try std.testing.expect(self.service != null);
    }
    fn checked(self: *Fixture, result: c.JSValue) !c.JSValue {
        if (c.JS_IsException(result) or c.JS_HasException(self.context.?)) {
            c.JS_FreeValue(self.context.?, result);
            const reason = c.JS_GetException(self.context.?);
            c.JS_FreeValue(self.context.?, reason);
            return error.ActualFSReuseJavaScriptException;
        }
        return result;
    }
    fn keepRequest(self: *Fixture, native_request: *c.PiUvFsRequest) !void {
        for (&self.requests) |*slot| if (slot.* == null) {
            slot.* = native_request;
            return;
        };
        c.pi_uv_fs_request_release(native_request);
        return error.ActualFSReuseRequestCapacity;
    }
    fn request(self: *Fixture, kind: c_int, token: u64) !*c.PiUvFsRequest {
        var result: ?*c.PiUvFsRequest = null;
        const outcome = c.pi_uv_fs_request_create(self.service.?, kind, token, &result);
        if (result) |native_request| try self.keepRequest(native_request);
        try allocated(outcome);
        return result orelse error.ActualFSReuseRequestRequired;
    }
    fn releaseRequest(self: *Fixture, native_request: *c.PiUvFsRequest) void {
        for (&self.requests) |*slot| if (slot.* == native_request) {
            slot.* = null;
            c.pi_uv_fs_request_release(native_request);
            return;
        };
        @panic("actual FS reuse request entitlement missing");
    }
    fn ownEvent(self: *Fixture, native_event: *c.PiUvEvent) !Ticket {
        for (&self.events, 0..) |*slot, index| if (slot.* == null) {
            slot.* = native_event;
            return index;
        };
        c.pi_uv_event_release(native_event);
        return error.ActualFSReuseEventCapacity;
    }
    fn eventPointer(self: *Fixture, ticket: Ticket) *c.PiUvEvent {
        return self.events[ticket] orelse @panic("actual FS reuse event entitlement missing");
    }
    fn releaseEvent(self: *Fixture, ticket: Ticket) void {
        const native_event = self.eventPointer(ticket);
        self.events[ticket] = null;
        c.pi_uv_event_release(native_event);
    }
    fn next(self: *Fixture) !Ticket {
        const until = c.uv_hrtime() + 10 * std.time.ns_per_s;
        while (true) {
            if (c.pi_uv_service_next(self.service.?)) |native_event|
                return self.ownEvent(native_event);
            if (c.uv_hrtime() >= until) return error.ActualFSReuseTimeout;
            c.uv_sleep(1);
        }
    }
    fn completion(self: *Fixture, native_request: *c.PiUvFsRequest, token: u64) !Ticket {
        const ticket = try self.next();
        errdefer self.releaseEvent(ticket);
        const native_event = self.eventPointer(ticket);
        const info = c.pi_uv_event_info(native_event);
        try std.testing.expectEqual(@as(c_int, c.PI_UV_FS_COMPLETION), info.kind);
        try std.testing.expectEqual(token, info.token);
        try std.testing.expect(c.pi_uv_event_fs_request(native_event) == native_request);
        return ticket;
    }
    fn waitQueued(self: *Fixture, count: usize) !void {
        const until = c.uv_hrtime() + 10 * std.time.ns_per_s;
        while (c.pi_uv_service_snapshot(self.service.?).queued_events < count) {
            if (c.uv_hrtime() >= until) return error.ActualFSReuseTimeout;
            c.uv_sleep(1);
        }
    }
    fn empty(self: *Fixture) !void {
        const extra = c.pi_uv_service_next(self.service.?);
        if (extra) |native_event| _ = try self.ownEvent(native_event);
        try std.testing.expect(extra == null);
        try std.testing.expectEqual(@as(usize, 0),
            c.pi_uv_service_snapshot(self.service.?).queued_events);
    }
    fn open(self: *Fixture, path: [*:0]const u8) !c_int {
        var native: c.uv_fs_t = undefined;
        const result = c.uv_fs_open(null, &native, path, c.O_RDONLY, 0, null);
        c.uv_fs_req_cleanup(&native);
        if (result < 0) { try status(result); unreachable; }
        for (&self.descriptors) |*slot| if (slot.* == -1) {
            slot.* = result;
            return result;
        };
        closeDescriptor(result);
        return error.ActualFSReuseDescriptorCapacity;
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
                @panic("actual FS reuse service did not join");
            for (&self.events) |*slot| if (slot.*) |native_event| {
                slot.* = null;
                c.pi_uv_event_release(native_event);
            };
            while (c.pi_uv_service_next(service)) |native_event|
                c.pi_uv_event_release(native_event);
            for (&self.requests) |*slot| if (slot.*) |native_request| {
                slot.* = null;
                c.pi_uv_fs_request_release(native_request);
            };
            c.pi_uv_service_release(service);
            self.service = null;
        }
        for (&self.descriptors) |*slot| if (slot.* != -1) {
            const fd = slot.*; slot.* = -1; closeDescriptor(fd);
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
        const acquired = c.JS_PiAcquireArrayBufferView(f.context.?, self.view.?, &self.lease);
        try std.testing.expectEqual(@as(c_int, 1), acquired);
        try std.testing.expect(!c.JS_HasException(f.context.?));
    }
    fn dropJs(self: *Buffer, f: *Fixture) void {
        if (self.view) |held| { self.view = null; c.JS_FreeValue(f.context.?, held); }
        if (self.buffer) |held| { self.buffer = null; c.JS_FreeValue(f.context.?, held); }
    }
    fn deinit(self: *Buffer, f: *Fixture) void {
        self.dropJs(f);
        c.JS_PiReleaseArrayBufferLease(&self.lease);
    }
};
fn completed(native_request: *c.PiUvFsRequest, expected: i64) !void {
    const info = c.pi_uv_fs_request_info(native_request);
    try std.testing.expectEqual(@as(c_int, c.PI_UV_FS_READ), info.kind);
    try std.testing.expectEqual(@as(c_int, 1), info.accepted);
    try std.testing.expectEqual(expected, info.result);
}

test "native actual FS reuse initial Reset preserves unsubmitted storage and charge" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const native_request = try f.request(c.PI_UV_FS_READ, 1);
    const used = c.pi_js_native_memory_used(f.memory);
    try std.testing.expectEqual(@as(c_int, 0), c.pi_uv_fs_request_reset(native_request));
    try std.testing.expectEqual(@as(c_int, 0), c.pi_uv_fs_request_reset(native_request));
    try std.testing.expectEqual(used, c.pi_js_native_memory_used(f.memory));
    try std.testing.expectEqual(@as(c_int, c.UV_EINVAL), c.pi_uv_fs_request_reset(null));
    c.pi_uv_fs_request_cleanup(native_request);
    try std.testing.expectEqual(@as(c_int, c.UV_EBUSY), c.pi_uv_fs_request_reset(native_request));
    try f.empty();
}
test "native actual FS reuse raw span preserves offset sentinels and payload after cleanup" {
    var file: File = undefined; try file.init("0123456789abcdef"); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fd = try f.open(file.path);
    const native_request = try f.request(c.PI_UV_FS_READ, 2);
    var bytes: [12]u8 = @splat(0xa5);
    try status(c.pi_uv_fs_read_buffer(native_request, fd, @ptrCast(bytes[3..].ptr), 5, 4));
    const ticket = try f.completion(native_request, 2); defer f.releaseEvent(ticket);
    try completed(native_request, 5);
    c.pi_uv_fs_request_cleanup(native_request);
    // Cleanup retires request-owned metadata, never this caller's raw payload.
    try std.testing.expectEqualSlices(u8, &.{ 0xa5, 0xa5, 0xa5 }, bytes[0..3]);
    try std.testing.expectEqualStrings("45678", bytes[3..8]);
    try std.testing.expectEqualSlices(u8, &.{ 0xa5, 0xa5, 0xa5, 0xa5 }, bytes[8..]);
}
test "native actual FS reuse invalid raw spans leave the same request admissible" {
    var file: File = undefined; try file.init("raw"); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fd = try f.open(file.path);
    const native_request = try f.request(c.PI_UV_FS_READ, 3);
    const wrong_kind = try f.request(c.PI_UV_FS_OPEN, 30);
    var bytes: [3]u8 = @splat(0);
    try std.testing.expectEqual(@as(c_int, c.UV_EINVAL),
        c.pi_uv_fs_read_buffer(native_request, fd, null, 1, 0));
    try std.testing.expectEqual(@as(c_int, c.UV_EINVAL),
        c.pi_uv_fs_read_buffer(wrong_kind, fd, @ptrCast(&bytes), bytes.len, 0));
    if (builtin.os.tag == .windows and @bitSizeOf(usize) > @bitSizeOf(c_ulong)) {
        const too_large: usize = @as(usize, std.math.maxInt(c_ulong)) + 1;
        try std.testing.expectEqual(@as(c_int, c.UV_EINVAL),
            c.pi_uv_fs_read_buffer(native_request, fd, @ptrCast(&bytes), too_large, 0));
    }
    try f.empty();
    try status(c.pi_uv_fs_read_buffer(native_request, fd, @ptrCast(&bytes), bytes.len, 0));
    const ticket = try f.completion(native_request, 3); defer f.releaseEvent(ticket);
    try completed(native_request, 3);
    c.pi_uv_fs_request_cleanup(native_request);
    try std.testing.expectEqualStrings("raw", &bytes);
}
test "native actual FS reuse Reset rejects submitted and queued work until actual dequeue" {
    var file: File = undefined; try file.init("queued"); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fd = try f.open(file.path);
    const native_request = try f.request(c.PI_UV_FS_READ, 4);
    var bytes: [6]u8 = @splat(0);
    try status(c.pi_uv_fs_read_buffer(native_request, fd, @ptrCast(&bytes), bytes.len, 0));
    try std.testing.expectEqual(@as(c_int, c.UV_EBUSY), c.pi_uv_fs_request_reset(native_request));
    try f.waitQueued(1);
    c.pi_uv_fs_request_cleanup(native_request);
    try std.testing.expectEqual(@as(c_int, c.UV_EBUSY), c.pi_uv_fs_request_reset(native_request));
    try std.testing.expectEqual(@as(usize, 1), c.pi_uv_service_snapshot(f.service.?).queued_events);
    const ticket = try f.completion(native_request, 4); defer f.releaseEvent(ticket);
    try completed(native_request, 6);
    try std.testing.expectEqual(@as(c_int, 0), c.pi_uv_fs_request_reset(native_request));
    try std.testing.expectEqualStrings("queued", &bytes);
}
test "native actual FS reuse dequeued result still requires actual cleanup before Reset" {
    var file: File = undefined; try file.init("clear"); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fd = try f.open(file.path);
    const native_request = try f.request(c.PI_UV_FS_READ, 5);
    var bytes: [5]u8 = @splat(0);
    try status(c.pi_uv_fs_read_buffer(native_request, fd, @ptrCast(&bytes), bytes.len, 0));
    const ticket = try f.completion(native_request, 5); defer f.releaseEvent(ticket);
    try completed(native_request, 5);
    try std.testing.expectEqual(@as(c_int, c.UV_EBUSY), c.pi_uv_fs_request_reset(native_request));
    try std.testing.expectEqual(@as(c_int, 0), c.pi_uv_fs_request_info(native_request).cleaned);
    c.pi_uv_fs_request_cleanup(native_request);
    c.pi_uv_fs_request_cleanup(native_request);
    try std.testing.expectEqual(@as(c_int, 0), c.pi_uv_fs_request_reset(native_request));
    try f.empty();
}
test "native actual FS reuse new completion queues before old event entitlement retires" {
    var file: File = undefined; try file.init("firstSECOND"); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fd = try f.open(file.path);
    const native_request = try f.request(c.PI_UV_FS_READ, 6);
    var first: [5]u8 = @splat(0); var second: [6]u8 = @splat(0);
    try status(c.pi_uv_fs_read_buffer(native_request, fd, @ptrCast(&first), first.len, 0));
    const old_ticket = try f.completion(native_request, 6);
    const embedded_address = f.eventPointer(old_ticket);
    try completed(native_request, 5);
    c.pi_uv_fs_request_cleanup(native_request);
    try status(c.pi_uv_fs_request_reset(native_request));
    try status(c.pi_uv_fs_read_buffer(native_request, fd, @ptrCast(&second), second.len, 5));
    try f.waitQueued(1);
    // Old info is now invalid. Releasing this entitlement may not touch next.
    f.releaseEvent(old_ticket);
    try std.testing.expectEqual(@as(usize, 1), c.pi_uv_service_snapshot(f.service.?).queued_events);
    const new_ticket = try f.completion(native_request, 6); defer f.releaseEvent(new_ticket);
    try std.testing.expect(f.eventPointer(new_ticket) == embedded_address);
    try completed(native_request, 6);
    c.pi_uv_fs_request_cleanup(native_request);
    try std.testing.expectEqualStrings("first", &first);
    try std.testing.expectEqualStrings("SECOND", &second);
    try f.empty();
}
test "native actual FS reuse old release preserves the reused embedded event FIFO next link" {
    var file: File = undefined; try file.init("ABC"); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fd = try f.open(file.path);
    const reused = try f.request(c.PI_UV_FS_READ, 7);
    const other = try f.request(c.PI_UV_FS_READ, 70);
    var first: [1]u8 = @splat(0); var second: [1]u8 = @splat(0); var third: [1]u8 = @splat(0);
    try status(c.pi_uv_fs_read_buffer(reused, fd, @ptrCast(&first), 1, 0));
    const old_ticket = try f.completion(reused, 7);
    try completed(reused, 1);
    c.pi_uv_fs_request_cleanup(reused);
    try status(c.pi_uv_fs_request_reset(reused));
    try status(c.pi_uv_fs_read_buffer(reused, fd, @ptrCast(&second), 1, 1));
    try f.waitQueued(1);
    try status(c.pi_uv_fs_read_buffer(other, fd, @ptrCast(&third), 1, 2));
    try f.waitQueued(2);
    f.releaseEvent(old_ticket);
    try std.testing.expectEqual(@as(usize, 2), c.pi_uv_service_snapshot(f.service.?).queued_events);
    const first_new = try f.completion(reused, 7); defer f.releaseEvent(first_new);
    const second_new = try f.completion(other, 70); defer f.releaseEvent(second_new);
    try completed(reused, 1); try completed(other, 1);
    c.pi_uv_fs_request_cleanup(reused); c.pi_uv_fs_request_cleanup(other);
    try std.testing.expectEqualStrings("A", &first);
    try std.testing.expectEqualStrings("B", &second);
    try std.testing.expectEqualStrings("C", &third);
    try f.empty();
}
test "native actual FS reuse several event tickets may own one embedded address" {
    var file: File = undefined; try file.init("01234"); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fd = try f.open(file.path);
    const native_request = try f.request(c.PI_UV_FS_READ, 8);
    var bytes: [5]u8 = @splat(0);
    var tickets: [5]Ticket = undefined;
    var first_address: ?*c.PiUvEvent = null;
    for (&bytes, 0..) |*byte, index| {
        try status(c.pi_uv_fs_read_buffer(native_request, fd, @ptrCast(byte), 1, @intCast(index)));
        tickets[index] = try f.completion(native_request, 8);
        const address = f.eventPointer(tickets[index]);
        if (first_address) |held| try std.testing.expect(address == held) else first_address = address;
        try completed(native_request, 1);
        c.pi_uv_fs_request_cleanup(native_request);
        if (index + 1 < bytes.len) try status(c.pi_uv_fs_request_reset(native_request));
    }
    for (tickets) |ticket| f.releaseEvent(ticket);
    try std.testing.expectEqualStrings("01234", &bytes);
    try f.empty();
}
test "native actual FS reuse completion owns request after old event and explicit owner retire" {
    var file: File = undefined; try file.init("alive"); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fd = try f.open(file.path);
    const native_request = try f.request(c.PI_UV_FS_READ, 9);
    var first: [1]u8 = @splat(0); var second: [4]u8 = @splat(0);
    try status(c.pi_uv_fs_read_buffer(native_request, fd, @ptrCast(&first), 1, 0));
    const old_ticket = try f.completion(native_request, 9);
    c.pi_uv_fs_request_cleanup(native_request);
    try status(c.pi_uv_fs_request_reset(native_request));
    try status(c.pi_uv_fs_read_buffer(native_request, fd, @ptrCast(&second), second.len, 1));
    f.releaseRequest(native_request);
    f.releaseEvent(old_ticket);
    const new_ticket = try f.completion(native_request, 9);
    try completed(native_request, 4);
    c.pi_uv_fs_request_cleanup(native_request);
    f.releaseEvent(new_ticket);
    // No request access follows its final entitlement retirement.
    try f.stop();
    try std.testing.expectEqualStrings("a", &first);
    try std.testing.expectEqualStrings("live", &second);
    try f.empty();
}
test "native actual FS reuse lease cleanup releases backing before later raw span" {
    var file: File = undefined; try file.init("leaseRAW"); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fd = try f.open(file.path);
    const native_request = try f.request(c.PI_UV_FS_READ, 10);
    var buffer: Buffer = undefined; try buffer.init(&f, 5); defer buffer.deinit(&f);
    const data = buffer.lease.data;
    try status(c.pi_uv_fs_read(native_request, fd, &buffer.lease, 0, 5, 0));
    buffer.dropJs(&f);
    c.JS_PiReleaseArrayBufferLease(&buffer.lease);
    const old_ticket = try f.completion(native_request, 10);
    try completed(native_request, 5);
    try std.testing.expectEqualStrings("lease", data[0..5]);
    const charged = c.pi_js_native_memory_used(f.memory);
    c.pi_uv_fs_request_cleanup(native_request);
    try std.testing.expect(c.pi_js_native_memory_used(f.memory) < charged);
    try status(c.pi_uv_fs_request_reset(native_request));
    var raw: [3]u8 = @splat(0);
    try status(c.pi_uv_fs_read_buffer(native_request, fd, @ptrCast(&raw), raw.len, 5));
    const new_ticket = try f.completion(native_request, 10); defer f.releaseEvent(new_ticket);
    f.releaseEvent(old_ticket);
    try completed(native_request, 3);
    c.pi_uv_fs_request_cleanup(native_request);
    try std.testing.expectEqualStrings("RAW", &raw);
}
test "native actual FS reuse raw request can later acquire a genuine JS backing lease" {
    var file: File = undefined; try file.init("RAWlease"); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fd = try f.open(file.path);
    const native_request = try f.request(c.PI_UV_FS_READ, 11);
    var raw: [3]u8 = @splat(0);
    try status(c.pi_uv_fs_read_buffer(native_request, fd, @ptrCast(&raw), raw.len, 0));
    const old_ticket = try f.completion(native_request, 11);
    c.pi_uv_fs_request_cleanup(native_request);
    try status(c.pi_uv_fs_request_reset(native_request));
    var buffer: Buffer = undefined; try buffer.init(&f, 5); defer buffer.deinit(&f);
    try status(c.pi_uv_fs_read(native_request, fd, &buffer.lease, 0, 5, 3));
    const new_ticket = try f.completion(native_request, 11); defer f.releaseEvent(new_ticket);
    f.releaseEvent(old_ticket);
    try completed(native_request, 5);
    c.pi_uv_fs_request_cleanup(native_request);
    try std.testing.expectEqualStrings("RAW", &raw);
    try std.testing.expectEqualStrings("lease", buffer.lease.data[0..5]);
}
test "native actual FS reuse null zero length and later EOF preserve real result zero" {
    var file: File = undefined; try file.init("x"); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fd = try f.open(file.path);
    const native_request = try f.request(c.PI_UV_FS_READ, 12);
    try status(c.pi_uv_fs_read_buffer(native_request, fd, null, 0, 0));
    const old_ticket = try f.completion(native_request, 12);
    try completed(native_request, 0);
    c.pi_uv_fs_request_cleanup(native_request);
    try status(c.pi_uv_fs_request_reset(native_request));
    var raw: [2]u8 = @splat(0x81);
    try status(c.pi_uv_fs_read_buffer(native_request, fd, @ptrCast(&raw), raw.len, 50));
    const new_ticket = try f.completion(native_request, 12); defer f.releaseEvent(new_ticket);
    f.releaseEvent(old_ticket);
    try completed(native_request, 0);
    c.pi_uv_fs_request_cleanup(native_request);
    try std.testing.expectEqualSlices(u8, &.{ 0x81, 0x81 }, &raw);
}
test "native actual FS reuse cancellation and stop retain exactly the reused completion" {
    var file: File = undefined; try file.init("cancel"); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fd = try f.open(file.path);
    const native_request = try f.request(c.PI_UV_FS_READ, 13);
    var first: [1]u8 = @splat(0); var second: [6]u8 = @splat(0);
    try status(c.pi_uv_fs_read_buffer(native_request, fd, @ptrCast(&first), 1, 0));
    const old_ticket = try f.completion(native_request, 13);
    c.pi_uv_fs_request_cleanup(native_request);
    try status(c.pi_uv_fs_request_reset(native_request));
    try status(c.pi_uv_fs_read_buffer(native_request, fd, @ptrCast(&second), second.len, 0));
    const cancelled = c.pi_uv_fs_cancel(native_request);
    try std.testing.expect(cancelled == 0 or cancelled == c.UV_EBUSY or cancelled == c.UV_EINVAL);
    try f.stop();
    f.releaseEvent(old_ticket);
    const new_ticket = try f.completion(native_request, 13); defer f.releaseEvent(new_ticket);
    const result = c.pi_uv_fs_request_info(native_request);
    try std.testing.expectEqual(@as(c_int, 1), result.accepted);
    try std.testing.expect(result.result == second.len or result.result == c.UV_ECANCELED);
    if (cancelled == 0) try std.testing.expectEqual(@as(i64, c.UV_ECANCELED), result.result);
    if (result.result >= 0) try std.testing.expectEqualStrings("cancel", &second);
    c.pi_uv_fs_request_cleanup(native_request);
    try status(c.pi_uv_fs_request_reset(native_request));
    // A stopped service returns an actual unaccepted status and no event.
    try std.testing.expectEqual(@as(c_int, c.UV_ECANCELED),
        c.pi_uv_fs_read_buffer(native_request, fd, @ptrCast(&second), second.len, 0));
    const rejected = c.pi_uv_fs_request_info(native_request);
    try std.testing.expectEqual(@as(c_int, 0), rejected.accepted);
    try std.testing.expectEqual(@as(i64, c.UV_ECANCELED), rejected.result);
    c.pi_uv_fs_request_cleanup(native_request);
    try status(c.pi_uv_fs_request_reset(native_request));
    try f.empty();
}
test "native actual FS reuse raw admission and Reset preserve actual pending without JS heap work" {
    var file: File = undefined; try file.init("native"); defer file.deinit();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const fd = try f.open(file.path);
    const native_request = try f.request(c.PI_UV_FS_READ, 14);
    var raw: [6]u8 = @splat(0);
    _ = c.JS_Throw(f.context.?, c.JS_NewInt32(f.context.?, 31415));
    const charged = c.pi_js_native_memory_used(f.memory);
    c.JS_SetMemoryLimit(f.runtime.?, 1);
    defer c.JS_SetMemoryLimit(f.runtime.?, 0);
    try status(c.pi_uv_fs_read_buffer(native_request, fd, @ptrCast(&raw), raw.len, 0));
    const ticket = try f.completion(native_request, 14); defer f.releaseEvent(ticket);
    try completed(native_request, 6);
    c.pi_uv_fs_request_cleanup(native_request);
    try status(c.pi_uv_fs_request_reset(native_request));
    try std.testing.expectEqual(charged, c.pi_js_native_memory_used(f.memory));
    try std.testing.expect(c.JS_HasException(f.context.?));
    const reason = c.JS_GetException(f.context.?);
    defer c.JS_FreeValue(f.context.?, reason);
    var integer: i32 = 0;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(f.context.?, &integer, reason));
    try std.testing.expectEqual(@as(i32, 31415), integer);
    try std.testing.expectEqualStrings("native", &raw);
    try std.testing.expect(!c.JS_HasException(f.context.?));
}
