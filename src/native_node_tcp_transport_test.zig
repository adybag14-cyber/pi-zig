//! Physical controls over the unchanged libuv/llhttp dependencies and the
//! actual native TCP event owner. No process or guest network substitute is
//! used. Source authoring is separate from Root's build/runtime qualification.
const std = @import("std");
const c = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("engine_abi.h");
    @cInclude("native_uv_tcp.h");
    @cInclude("uv.h");
    @cInclude("llhttp.h");
});
const limit: usize = 16 * 1024 * 1024;
const wake_slot: u32 = 17;
const wake_generation: u64 = 0x1020304050607080;
var wake_count: std.atomic.Value(usize) = .init(0);
var wrong_wake: std.atomic.Value(bool) = .init(false);
fn notified(slot: u32, generation: u64) callconv(.c) void {
    if (slot != wake_slot or generation != wake_generation) wrong_wake.store(true, .release);
    _ = wake_count.fetchAdd(1, .monotonic);
}
fn status(result: c_int) !void {
    if (result < 0) {
        std.debug.print("actual libuv status {d}: {s}\n", .{ result, std.mem.span(c.pi_uv_error_name(result)) });
        return error.ActualTcpStatusFailure;
    }
}
fn allocated(result: c.PiUvResult) !void {
    try std.testing.expectEqual(@as(c_int, 0), result.allocation_failed);
    try status(result.status);
}
const Pair = struct { listener: *c.PiUvEndpoint, client: *c.PiUvEndpoint, server: *c.PiUvEndpoint, port: u16 };
const Fixture = struct {
    runtime: ?*c.JSRuntime = null,
    owner: ?*anyopaque = null,
    service: ?*c.PiUvService = null,
    endpoints: [16]?*c.PiUvEndpoint = @splat(null),
    events: [32]?*c.PiUvEvent = @splat(null),
    runtime_bytes: usize = 0,
    fn init(self: *Fixture) !void {
        self.* = .{};
        wake_count.store(0, .release); wrong_wake.store(false, .release);
        self.runtime = c.pi_js_new_runtime(limit, &self.owner) orelse return error.OutOfMemory;
        errdefer self.deinit();
        self.runtime_bytes = c.pi_js_native_memory_used(self.owner);
        try allocated(c.pi_uv_service_create(self.owner, notified, wake_slot, wake_generation, &self.service));
        try std.testing.expect(self.service != null);
    }
    fn own(self: *Fixture, endpoint: *c.PiUvEndpoint) !*c.PiUvEndpoint {
        for (&self.endpoints) |*slot| if (slot.* == null) { slot.* = endpoint; return endpoint; };
        c.pi_uv_endpoint_abandon(endpoint); c.pi_uv_endpoint_release(endpoint);
        return error.ActualTcpEndpointControlCapacity;
    }
    fn create(self: *Fixture) !*c.PiUvEndpoint {
        var endpoint: ?*c.PiUvEndpoint = null;
        try allocated(c.pi_uv_tcp_create(self.service.?, &endpoint));
        return self.own(endpoint orelse return error.ActualTcpCreatedEndpointMissing);
    }
    fn storeEvent(self: *Fixture, event: *c.PiUvEvent) !void {
        for (&self.events) |*slot| if (slot.* == null) { slot.* = event; return; };
        c.pi_uv_event_release(event);
        return error.ActualTcpEventControlCapacity;
    }
    fn eventMatches(event: *c.PiUvEvent, kind: c_int, endpoint: ?*c.PiUvEndpoint, token: ?u64) bool {
        const info = c.pi_uv_event_info(event);
        return info.kind == kind and (endpoint == null or info.source == endpoint) and
            (token == null or info.token == token.?);
    }
    fn take(self: *Fixture, kind: c_int, endpoint: ?*c.PiUvEndpoint, token: ?u64) !*c.PiUvEvent {
        const until = c.uv_hrtime() + 10 * std.time.ns_per_s;
        while (true) {
            for (self.events) |slot| if (slot) |event| {
                if (eventMatches(event, kind, endpoint, token)) return event;
                if (c.pi_uv_event_info(event).kind == c.PI_UV_NATIVE_ALLOCATION_FAILURE)
                    return error.UnexpectedActualTcpAllocationEvent;
            };
            if (c.pi_uv_service_next(self.service.?)) |event| {
                try self.storeEvent(event); continue;
            }
            if (c.uv_hrtime() >= until) return error.ActualTcpCompletionTimeout;
            c.uv_sleep(1);
        }
    }
    fn releaseEvent(self: *Fixture, event: *c.PiUvEvent) void {
        for (&self.events) |*slot| if (slot.* == event) {
            slot.* = null; c.pi_uv_event_release(event); return;
        };
        @panic("actual TCP control lost its event owner");
    }
    fn accept(self: *Fixture, listener: *c.PiUvEndpoint) !*c.PiUvEndpoint {
        const event = try self.take(c.PI_UV_ACCEPT, listener, null);
        defer self.releaseEvent(event);
        const endpoint = c.pi_uv_event_take_accepted(event) orelse return error.ActualTcpAcceptMissingEndpoint;
        try std.testing.expect(c.pi_uv_event_take_accepted(event) == null);
        return self.own(endpoint);
    }
    fn connect(self: *Fixture, client: *c.PiUvEndpoint, port: u16, token: u64) !void {
        try allocated(c.pi_uv_tcp_connect(client, "127.0.0.1", port, token));
        const event = try self.take(c.PI_UV_CONNECT, client, token);
        defer self.releaseEvent(event);
        try status(c.pi_uv_event_info(event).status);
    }
    fn pair(self: *Fixture) !Pair {
        const listener = try self.create();
        try status(c.pi_uv_tcp_bind(listener, "127.0.0.1", 0, 0));
        try status(c.pi_uv_tcp_listen(listener, 16));
        var address: c.PiUvAddress = undefined;
        try status(c.pi_uv_tcp_address(listener, 0, &address));
        try std.testing.expectEqual(@as(c_int, 4), address.family);
        try std.testing.expect(address.port > 0 and address.port <= 65535);
        const client = try self.create();
        try self.connect(client, @intCast(address.port), 1001);
        const server = try self.accept(listener);
        return .{ .listener = listener, .client = client, .server = server, .port = @intCast(address.port) };
    }
    fn write(self: *Fixture, endpoint: *c.PiUvEndpoint, bytes: []const u8, token: u64) !void {
        try allocated(c.pi_uv_tcp_write(endpoint, bytes.ptr, bytes.len, token));
        try self.writeDone(endpoint, bytes.len, token);
    }
    fn writeDone(self: *Fixture, endpoint: *c.PiUvEndpoint, length: usize, token: u64) !void {
        const event = try self.take(c.PI_UV_WRITE, endpoint, token);
        defer self.releaseEvent(event);
        const info = c.pi_uv_event_info(event);
        try status(info.status); try std.testing.expectEqual(length, info.length);
    }
    fn readAll(self: *Fixture, endpoint: *c.PiUvEndpoint, output: []u8) !void {
        if (output.len == 0) return;
        try status(c.pi_uv_tcp_read_start(endpoint));
        var offset: usize = 0;
        while (offset < output.len) {
            const event = try self.take(c.PI_UV_READ, endpoint, null);
            errdefer self.releaseEvent(event);
            const info = c.pi_uv_event_info(event);
            try status(info.status);
            try std.testing.expect(info.length > 0 and info.length <= output.len - offset);
            @memcpy(output[offset..][0..info.length], info.bytes[0..info.length]);
            offset += info.length;
            // Demand is a separate operation; ACK alone never starts a read.
            if (offset < output.len) try status(c.pi_uv_tcp_read_start(endpoint));
            self.releaseEvent(event);
        }
    }
    fn fillBudget(self: *Fixture) !usize {
        const remaining = limit - c.pi_js_native_memory_used(self.owner);
        try std.testing.expect(c.pi_js_native_memory_reserve(self.owner, remaining) != 0);
        try std.testing.expectEqual(limit, c.pi_js_native_memory_used(self.owner));
        return remaining;
    }
    fn stop(self: *Fixture) !void {
        const service = self.service orelse return;
        try std.testing.expectEqual(@as(c_int, 0), c.pi_uv_service_stop(service));
        const actual = c.pi_uv_service_snapshot(service);
        try std.testing.expect(actual.thread_joined != 0 and actual.close_requested != 0);
        try std.testing.expectEqual(@as(usize, 0), actual.live_handles);
        try std.testing.expectEqual(@as(usize, 0), actual.pending_requests);
        try std.testing.expectEqual(@as(c_int, 0), actual.loop_close_status);
        try std.testing.expect(!wrong_wake.load(.acquire));
    }
    fn deinit(self: *Fixture) void {
        if (self.service) |service| {
            if (c.pi_uv_service_stop(service) != 0) @panic("actual TCP control worker did not join");
            for (&self.events) |*slot| if (slot.*) |event| { slot.* = null; c.pi_uv_event_release(event); };
            while (c.pi_uv_service_next(service)) |event| c.pi_uv_event_release(event);
            for (&self.endpoints) |*slot| if (slot.*) |endpoint| { slot.* = null; c.pi_uv_endpoint_release(endpoint); };
            c.pi_uv_service_release(service); self.service = null;
        }
        if (self.runtime) |runtime| { c.JS_FreeRuntime(runtime); self.runtime = null; }
        if (self.owner) |owner| { c.pi_js_release_memory_owner(owner); self.owner = null; }
    }
};

test "native actual TCP empty service owns native loop and closes its independent budget" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try std.testing.expectEqual(@as(c_uint, 0x013300), c.uv_version());
    try std.testing.expect(c.pi_js_native_memory_used(f.owner) > f.runtime_bytes);
    const before = c.pi_uv_service_snapshot(f.service.?);
    try std.testing.expectEqual(@as(usize, 0), before.live_handles);
    try std.testing.expect(before.thread_joined == 0);
    try f.stop();
    while (c.pi_uv_service_next(f.service.?)) |event| c.pi_uv_event_release(event);
    c.pi_uv_service_release(f.service.?); f.service = null;
    try std.testing.expectEqual(f.runtime_bytes, c.pi_js_native_memory_used(f.owner));
}
test "native actual TCP binds ephemeral IPv4 and reports actual local and peer addresses" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const pair = try f.pair();
    var peer: c.PiUvAddress = undefined; try status(c.pi_uv_tcp_address(pair.client, 1, &peer));
    try std.testing.expectEqual(@as(c_uint, pair.port), peer.port);
    try std.testing.expectEqualStrings("127.0.0.1", std.mem.sliceTo(&peer.address, 0));
    var local: c.PiUvAddress = undefined; try status(c.pi_uv_tcp_address(pair.client, 0, &local));
    var server_peer: c.PiUvAddress = undefined; try status(c.pi_uv_tcp_address(pair.server, 1, &server_peer));
    try std.testing.expectEqual(local.port, server_peer.port);
    try std.testing.expect(local.port > 0 and local.family == 4);
    try status(c.pi_uv_tcp_nodelay(pair.client, 1));
    try status(c.pi_uv_tcp_keepalive(pair.client, 1, 30));
    try f.stop(); try std.testing.expect(wake_count.load(.acquire) >= 2);
}
test "native actual TCP copies caller write bytes and preserves tokens across real segmented reads" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const pair = try f.pair();
    const length = 96 * 1024 + 137;
    var expected: [length]u8 = undefined;
    for (&expected, 0..) |*byte, index| byte.* = @truncate(index * 37 + 11);
    var supplied = expected;
    try allocated(c.pi_uv_tcp_write(pair.client, &supplied, supplied.len, 0x123456));
    @memset(&supplied, 0xee); // The submitted request owns its actual copy.
    var received: [length]u8 = undefined;
    try f.readAll(pair.server, &received);
    try f.writeDone(pair.client, expected.len, 0x123456);
    try std.testing.expectEqualSlices(u8, &expected, &received);
    try f.stop();
}
test "native actual TCP read packet owns bytes until release and resumes only with new demand" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const pair = try f.pair();
    try status(c.pi_uv_tcp_read_start(pair.server));
    try f.write(pair.client, "first", 201);
    const held = try f.take(c.PI_UV_READ, pair.server, null);
    var held_owned = true; defer if (held_owned) f.releaseEvent(held);
    const first = c.pi_uv_event_info(held);
    try status(first.status); try std.testing.expect(first.length > 0 and first.length <= 5);
    try std.testing.expectEqualSlices(u8, "first"[0..first.length], first.bytes[0..first.length]);
    try status(c.pi_uv_tcp_read_stop(pair.server));
    try f.write(pair.client, "second", 202);
    try status(c.pi_uv_tcp_read_start(pair.server)); // Held read slot cannot be reused before ACK.
    try std.testing.expectEqualSlices(u8, "first"[0..first.length], first.bytes[0..first.length]);
    f.releaseEvent(held); held_owned = false;
    var result: [11]u8 = undefined; @memcpy(result[0..first.length], "first"[0..first.length]);
    try f.readAll(pair.server, result[first.length..]);
    try std.testing.expectEqualStrings("firstsecond", &result);
    try f.stop();
}
test "native actual TCP half close yields real EOF while the opposite direction remains writable" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const pair = try f.pair();
    try status(c.pi_uv_tcp_read_start(pair.server));
    try allocated(c.pi_uv_tcp_shutdown(pair.client, 301));
    const shutdown = try f.take(c.PI_UV_SHUTDOWN, pair.client, 301);
    try status(c.pi_uv_event_info(shutdown).status); f.releaseEvent(shutdown);
    const eof = try f.take(c.PI_UV_EOF, pair.server, null);
    try std.testing.expectEqual(@as(c_int, c.UV_EOF), c.pi_uv_event_info(eof).status);
    f.releaseEvent(eof);
    try f.write(pair.server, "reply", 302);
    var received: [5]u8 = undefined; try f.readAll(pair.client, &received);
    try std.testing.expectEqualStrings("reply", &received);
    try f.stop();
}
test "native actual TCP releasing an unclaimed accept closes the real accepted connection" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const listener = try f.create();
    try status(c.pi_uv_tcp_bind(listener, "127.0.0.1", 0, 0)); try status(c.pi_uv_tcp_listen(listener, 4));
    var address: c.PiUvAddress = undefined; try status(c.pi_uv_tcp_address(listener, 0, &address));
    const client = try f.create(); try f.connect(client, @intCast(address.port), 401);
    const accepted = try f.take(c.PI_UV_ACCEPT, listener, null);
    try status(c.pi_uv_tcp_read_start(client));
    f.releaseEvent(accepted); // No caller entitlement was taken.
    const eof = try f.take(c.PI_UV_EOF, client, null);
    try std.testing.expectEqual(@as(c_int, c.UV_EOF), c.pi_uv_event_info(eof).status); f.releaseEvent(eof);
    try f.stop();
}
test "native actual TCP numeric argument errors remain ordinary libuv statuses without callbacks" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const endpoint = try f.create();
    const before = c.pi_uv_service_snapshot(f.service.?);
    const bind = c.pi_uv_tcp_bind(endpoint, "not-a-numeric-address", 80, 0);
    try std.testing.expectEqual(@as(c_int, c.UV_EINVAL), bind);
    const connect = c.pi_uv_tcp_connect(endpoint, "127.0.0.1", 65536, 501);
    try std.testing.expectEqual(@as(c_int, c.UV_EINVAL), connect.status);
    try std.testing.expectEqual(@as(c_int, 0), connect.allocation_failed);
    const after = c.pi_uv_service_snapshot(f.service.?);
    try std.testing.expectEqual(before.pending_requests, after.pending_requests);
    try std.testing.expectEqual(before.queued_events, after.queued_events);
    try f.stop();
}
test "native actual TCP exhausted shared budget is a distinct wrapper allocation producer" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const used = c.pi_js_native_memory_used(f.owner);
    const reservation = try f.fillBudget();
    var filled = true; defer if (filled) c.pi_js_native_memory_release(f.owner, reservation);
    var endpoint: ?*c.PiUvEndpoint = null;
    const failed = c.pi_uv_tcp_create(f.service.?, &endpoint);
    try std.testing.expect(failed.status == c.UV_ENOMEM and failed.allocation_failed == 1 and endpoint == null);
    try std.testing.expectEqual(@as(usize, 0), c.pi_uv_service_snapshot(f.service.?).live_handles);
    c.pi_js_native_memory_release(f.owner, reservation); filled = false;
    try std.testing.expectEqual(used, c.pi_js_native_memory_used(f.owner));
    _ = try f.create();
    try f.stop();
}
test "native actual TCP read allocation failure is delivered by its real embedded owner event" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const pair = try f.pair();
    try f.write(pair.client, "pending", 601);
    const reservation = try f.fillBudget();
    var filled = true; defer if (filled) c.pi_js_native_memory_release(f.owner, reservation);
    try status(c.pi_uv_tcp_read_start(pair.server));
    const failed = try f.take(c.PI_UV_NATIVE_ALLOCATION_FAILURE, null, null);
    const info = c.pi_uv_event_info(failed);
    try std.testing.expectEqual(@as(c_int, c.UV_ENOMEM), info.status);
    f.releaseEvent(failed);
    c.pi_js_native_memory_release(f.owner, reservation); filled = false;
    try f.stop();
}
test "native actual TCP close tokens use observed native closure and never a second close" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const endpoint = try f.create();
    try std.testing.expectEqual(@as(c_int, 0), c.pi_uv_tcp_close(endpoint, 701));
    const event = try f.take(c.PI_UV_CLOSE, endpoint, 701);
    try status(c.pi_uv_event_info(event).status); f.releaseEvent(event);
    try std.testing.expectEqual(@as(c_int, 1), c.pi_uv_tcp_close(endpoint, 702));
    try std.testing.expectEqual(@as(usize, 0), c.pi_uv_service_snapshot(f.service.?).live_handles);
    try f.stop();
}
test "native actual TCP listener reference tracks actual active handle and queued closure separately" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const listener = try f.create();
    try status(c.pi_uv_tcp_bind(listener, "127.0.0.1", 0, 0)); try status(c.pi_uv_tcp_listen(listener, 4));
    try std.testing.expect(c.pi_uv_service_has_referenced(f.service.?) != 0);
    try status(c.pi_uv_tcp_set_referenced(listener, 0));
    try std.testing.expectEqual(@as(c_int, 0), c.pi_uv_service_has_referenced(f.service.?));
    try status(c.pi_uv_tcp_set_referenced(listener, 1));
    try std.testing.expect(c.pi_uv_service_has_referenced(f.service.?) != 0);
    try std.testing.expectEqual(@as(c_int, 0), c.pi_uv_tcp_close(listener, 801));
    const event = try f.take(c.PI_UV_CLOSE, listener, 801);
    f.releaseEvent(event);
    try std.testing.expectEqual(@as(c_int, 0), c.pi_uv_service_has_referenced(f.service.?));
    try f.stop();
}
test "native actual TCP native endpoint and event owners can outlive their original VM runtime" {
    const owners_before = c.pi_js_native_memory_owners();
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    const endpoint = try f.create();
    try std.testing.expectEqual(@as(c_int, 0), c.pi_uv_tcp_close(endpoint, 901));
    const event = try f.take(c.PI_UV_CLOSE, endpoint, 901);
    try f.stop();
    c.JS_FreeRuntime(f.runtime.?); f.runtime = null;
    c.pi_js_release_memory_owner(f.owner); f.owner = null;
    // The runtime and caller entitlement are both gone. Only actual native
    // service/endpoint/event ownership may keep this independent owner alive.
    try std.testing.expectEqual(owners_before + 1, c.pi_js_native_memory_owners());
    try std.testing.expectEqual(@as(u64, 901), c.pi_uv_event_info(event).token);
    f.releaseEvent(event);
    for (&f.endpoints) |*slot| if (slot.*) |value| { slot.* = null; c.pi_uv_endpoint_release(value); };
    while (c.pi_uv_service_next(f.service.?)) |remaining| c.pi_uv_event_release(remaining);
    c.pi_uv_service_release(f.service.?); f.service = null;
    try std.testing.expectEqual(owners_before, c.pi_js_native_memory_owners());
}
