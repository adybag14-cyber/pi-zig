//! One native libuv service and completion FIFO per actual Env I/O Hub.
//! TCP and FS retain their own genuine actors. This owner contains only native
//! client dispatch and the shared wake/loop lifetime; no Socket or Errno input.
const std = @import("std");
const em = @import("engine.zig");
const a = @import("native_node_argument_values.zig");
const env = @import("native_env_io.zig");
const wake = @import("native_owner_wake.zig");
const completion_wake = @import("native_owner_completion.zig");
const Completion = @import("native_sdk_owned_completion.zig").Completion;
const c = em.c;
pub const uv = @cImport({ @cInclude("native_uv_tcp.h"); @cInclude("native_uv_fs.h"); });
const service_tag: u8 = 0;

pub const Kind = enum(u1) { tcp, fs };
/// Private compiled owners only. Each client stays in the Hub through this
/// resource's stopped() drain. No client pointer is sent to the native loop.
pub const Client = struct {
    raw: *anyopaque,
    ready: *const fn (*anyopaque) bool,
    complete: *const fn (*anyopaque, *uv.PiUvEvent) anyerror!void,
    abandon: *const fn (*anyopaque, *uv.PiUvEvent) anyerror!void,
};
pub const Acquisition = union(enum) { ready: *Owner, failed: c_int };
pub const Owner = struct {
    hub: *env.Hub,
    service: *uv.PiUvService,
    wake_ref: wake.Ref,
    clients: [2]?Client = .{ null, null },
    busy: bool = false,
    stopping: bool = false,

    pub fn client(self: *Owner, kind: Kind) ?Client {
        return self.clients[@intFromEnum(kind)];
    }
    pub fn attach(self: *Owner, kind: Kind, input: Client) !void {
        try self.hub.assertOwner();
        if (self.stopping or self.hub.stopping) return error.NativeEnvClosed;
        const slot = &self.clients[@intFromEnum(kind)];
        if (slot.* != null) return error.NativeUvClientAlreadyInstalled;
        slot.* = input;
    }
    fn eventClient(self: *Owner, event: *uv.PiUvEvent) !Client {
        const kind: Kind = if (uv.pi_uv_event_info(event).kind == uv.PI_UV_FS_COMPLETION) .fs else .tcp;
        return self.client(kind) orelse return error.NativeUvCompletionOwnerRequired;
    }
    fn deliver(self: *Owner, event: *uv.PiUvEvent, abandoned: bool) !void {
        if (uv.pi_uv_event_info(event).kind == uv.PI_UV_NATIVE_ALLOCATION_FAILURE)
            return error.OutOfMemory;
        const selected = try self.eventClient(event);
        if (abandoned) return selected.abandon(selected.raw, event);
        return selected.complete(selected.raw, event);
    }
    fn poll(raw: *anyopaque) !bool {
        const self: *Owner = @ptrCast(@alignCast(raw));
        try self.hub.assertOwner();
        try self.hub.engine.checkNativeEntry();
        if (self.stopping or self.hub.stopping) return error.NativeEnvClosed;
        if (self.busy or c.JS_IsJobPending(self.hub.engine.runtime)) return false;
        // Preserve the actual TCP construction/callback reentry gate before
        // consuming any shared FIFO entry. FS uses its own same-owner gate.
        for (self.clients) |optional| if (optional) |selected|
            if (!selected.ready(selected.raw)) return false;
        const event = uv.pi_uv_service_next(self.service) orelse return false;
        self.busy = true;
        defer self.busy = false;
        const engine = self.hub.engine;
        engine.native_exception_diagnostics_suppressed += 1;
        defer engine.native_exception_diagnostics_suppressed -= 1;
        var completion = Completion.initVoid(engine, self.deliver(event, false));
        uv.pi_uv_event_release(event);
        try completion.finishVoid();
        return true; // The existing Hub owns the subsequent checkpoint.
    }
    fn referenced(raw: *anyopaque) bool {
        const self: *Owner = @ptrCast(@alignCast(raw));
        return !self.stopping and uv.pi_uv_service_has_referenced(self.service) != 0;
    }
    fn stop(raw: *anyopaque) void {
        const self: *Owner = @ptrCast(@alignCast(raw));
        if (self.stopping) return;
        std.debug.assert(!self.busy);
        self.stopping = true;
        const status = uv.pi_uv_service_stop(self.service);
        const actual = uv.pi_uv_service_snapshot(self.service);
        if (status != 0 or actual.thread_joined == 0 or actual.live_handles != 0 or actual.pending_requests != 0)
            std.debug.panic("libuv service owner did not close: status={d}", .{status});
    }
    fn record(s: *a.Scope, err: anyerror) void {
        s.boundary.escaping();
        if (err == error.OutOfMemory and !s.boundary.isFatal()) {
            _ = s.engine.throwNativeOutOfMemoryFatal();
            s.boundary.escaping();
        }
    }
    fn stopped(raw: *anyopaque) void {
        const self: *Owner = @ptrCast(@alignCast(raw));
        const engine = self.hub.engine;
        std.debug.assert(self.stopping);
        // Hub calls every resource stop before any stopped callback. Actual FS
        // owners have disabled JS and still execute their native Wrapper/After
        // cleanup, so request_waiting reaches zero before realm destruction.
        var handles = a.Scope.init(engine);
        var failure: ?anyerror = null;
        while (uv.pi_uv_service_next(self.service)) |event| {
            self.deliver(event, true) catch |err| {
                record(&handles, err);
                if (failure == null) failure = err;
            };
            uv.pi_uv_event_release(event);
            handles.pending() catch |err| {
                record(&handles, err);
                if (failure == null) failure = err;
            };
        }
        self.clients = .{ null, null };
        uv.pi_uv_service_release(self.service);
        wake.release(self.wake_ref);
        hostDestroy(engine, self);
        const ignored = handles.finish(if (failure) |err|
            @as(anyerror!c.JSValue, err) else c.pi_js_undefined()) catch return;
        engine.freeValue(ignored);
    }
};

fn notify(slot: u32, generation: u64) callconv(.c) void {
    if (slot > std.math.maxInt(u8)) return;
    wake.notify(.{ .slot = @intCast(slot), .generation = generation });
}
fn hostCreate(engine: *em.Engine, comptime T: type) !*T {
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(T)) == 0)
        return error.OutOfMemory;
    errdefer c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(T));
    return engine.gpa.create(T);
}
fn hostDestroy(engine: *em.Engine, value: anytype) void {
    const size = @sizeOf(@TypeOf(value.*));
    engine.gpa.destroy(value);
    c.pi_js_native_memory_release(engine.native_memory_owner, size);
}

/// Domain callers preserve their own actual native-error construction for an
/// ordinary loop status. Only this wrapper's proven allocation failure is OOM.
/// Publication follows complete wake/loop/resource admission.
pub fn acquire(engine: *em.Engine) !Acquisition {
    try engine.checkNativeEntry();
    const hub = try env.get(engine);
    try hub.assertOwner();
    if (hub.stopping) return error.NativeEnvClosed;
    for (hub.resources.items) |resource| if (resource.tag == @as(?*const anyopaque, &service_tag)) {
        const self: *Owner = @ptrCast(@alignCast(resource.raw));
        if (self.stopping) return error.NativeEnvClosed;
        return .{ .ready = self };
    };
    const reference = try completion_wake.acquireNativeWake(engine);
    const self = hostCreate(engine, Owner) catch |err| {
        var completion = Completion.initVoid(engine, err);
        wake.release(reference);
        try completion.finishVoid();
        unreachable;
    };
    var service: ?*uv.PiUvService = null;
    const started = uv.pi_uv_service_create(engine.native_memory_owner, notify,
        reference.slot, reference.generation, &service);
    if (started.status < 0 or started.allocation_failed != 0) {
        var completion = Completion.initVoid(engine, if (started.allocation_failed != 0)
            @as(anyerror!void, error.OutOfMemory) else @as(anyerror!void, {}));
        hostDestroy(engine, self);
        wake.release(reference);
        try completion.finishVoid();
        return .{ .failed = started.status };
    }
    const actual = service orelse unreachable;
    hub.resources.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var completion = Completion.initVoid(engine, err);
        if (uv.pi_uv_service_stop(actual) != 0) @panic("libuv service admission rollback did not join");
        while (uv.pi_uv_service_next(actual)) |event| uv.pi_uv_event_release(event);
        uv.pi_uv_service_release(actual);
        hostDestroy(engine, self);
        wake.release(reference);
        try completion.finishVoid();
        unreachable;
    };
    self.* = .{ .hub = hub, .service = actual, .wake_ref = reference };
    hub.resources.appendAssumeCapacity(.{
        .raw = self, .tag = &service_tag, .poll = Owner.poll,
        .referenced = Owner.referenced, .stop = Owner.stop, .stopped = Owner.stopped,
    });
    return .{ .ready = self };
}
