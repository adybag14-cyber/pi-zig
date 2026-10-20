//! Owner-thread libuv transport for the existing canonical Socket.
//! The native service contains no Engine or JSValue. Hub delivery enters the
//! actual Socket owner; private accept/connect callbacks belong to the genuine
//! net frontend. This file does not publish a net or http module.
const std = @import("std");
const p = @import("native_public_values.zig");
const c = p.c;
const Engine = p.em.Engine;
const env = @import("native_env_io.zig");
const shared_service = @import("native_node_uv_service.zig");
const socket = @import("native_node_net_socket.zig");
const uv = shared_service.uv;
const Completion = p.owned.Completion;
const controller_tag: u8 = 0;

pub const Address = uv.PiUvAddress;
pub const Snapshot = uv.PiUvSnapshot;

/// These are native callbacks of the actual Source Server/TCP owner, not public
/// replacement handlers. root must retain context until native close delivery.
pub const ListenerCallbacks = struct {
    root: c.JSValue,
    context: *anyopaque,
    accept: *const fn (*anyopaque, *Controller, *Accepted) anyerror!void,
    failure: *const fn (*anyopaque, *Controller, c_int) anyerror!void,
    closed: *const fn (*anyopaque, *Controller) anyerror!void,
};
/// One genuine request owner, retained from successful uv submission through
/// its real completion. Immediate submission failure does not invoke complete.
pub const ConnectCallback = struct {
    root: c.JSValue,
    context: *anyopaque,
    complete: *const fn (*anyopaque, *Controller, c.JSValue, c_int, u64) anyerror!void,
};
pub const Inputs = struct {
    provider: *const socket.Provider,
    /// The completed shared internal/errors ErrnoException, acquired by the
    /// real bootstrap from its original Error and internal require bindings.
    errno_exception: c.JSValue,
};

const Operation = enum {
    read, write, shutdown, close, reference, connect, bind, listen,
    nodelay, keepalive, getsockname, getpeername,
    fn text(self: Operation) []const u8 {
        return switch (self) {
            .reference => "ref",
            .nodelay => "setNoDelay",
            .keepalive => "setKeepAlive",
            else => @tagName(self),
        };
    }
};

/// Independent native lifetime used by Socket finalizers after Hub retirement.
/// It owns no Engine, allocator with Engine lifetime, JSValue, or worker ticket.
const NativeEndpoint = struct {
    service: *uv.PiUvService,
    endpoint: *uv.PiUvEndpoint,
    memory_owner: ?*anyopaque,
    references: std.atomic.Value(usize) = .init(1),
    last_status: c_int = 0,
    last_operation: Operation = .read,
    close_observed: bool = false,

    /// Consumes endpoint only on success. All allocation failures remain typed.
    fn create(engine: *Engine, service: *uv.PiUvService, endpoint: *uv.PiUvEndpoint) !*NativeEndpoint {
        if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(NativeEndpoint)) == 0)
            return error.OutOfMemory;
        errdefer c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(NativeEndpoint));
        const self = try std.heap.c_allocator.create(NativeEndpoint);
        c.pi_js_retain_memory_owner(engine.native_memory_owner);
        self.* = .{ .service = service, .endpoint = endpoint, .memory_owner = engine.native_memory_owner };
        return self;
    }
    fn from(raw: *anyopaque) *NativeEndpoint { return @ptrCast(@alignCast(raw)); }
    fn retain(raw: *anyopaque) void {
        const old = from(raw).references.fetchAdd(1, .monotonic);
        std.debug.assert(old != 0 and old != std.math.maxInt(usize));
    }
    fn release(raw: *anyopaque) void {
        const self = from(raw);
        const old = self.references.fetchSub(1, .acq_rel);
        std.debug.assert(old != 0);
        if (old != 1) return;
        const memory_owner = self.memory_owner;
        uv.pi_uv_endpoint_release(self.endpoint);
        std.heap.c_allocator.destroy(self);
        c.pi_js_native_memory_release(memory_owner, @sizeOf(NativeEndpoint));
        c.pi_js_release_memory_owner(memory_owner);
    }
    fn abandon(raw: *anyopaque) void { uv.pi_uv_endpoint_abandon(from(raw).endpoint); }
    fn status(self: *NativeEndpoint, result: c_int, operation: Operation) !void {
        if (result >= 0) return;
        self.last_status = result;
        self.last_operation = operation;
        return error.NativeTcpLibuvFailure;
    }
    fn allocatedStatus(self: *NativeEndpoint, result: uv.PiUvResult, operation: Operation) !void {
        if (result.allocation_failed != 0) return error.OutOfMemory;
        try self.status(result.status, operation);
    }
    fn read(raw: *anyopaque) !void {
        const self = from(raw);
        try self.status(uv.pi_uv_tcp_read_start(self.endpoint), .read);
    }
    fn write(raw: *anyopaque, bytes: []const u8, token: u64) !void {
        const self = from(raw);
        try self.allocatedStatus(uv.pi_uv_tcp_write(self.endpoint, bytes.ptr, bytes.len, token), .write);
    }
    fn finish(raw: *anyopaque, token: u64) !bool {
        const self = from(raw);
        if (self.close_observed) return true;
        const result = uv.pi_uv_tcp_shutdown(self.endpoint, token);
        if (result.allocation_failed != 0) return error.OutOfMemory;
        // Source Socket accepts the real synchronous UV_ENOTCONN result.
        if (result.status < 0 and std.mem.eql(u8, statusName(result.status), "ENOTCONN")) return true;
        try self.status(result.status, .shutdown);
        return false;
    }
    fn destroy(raw: *anyopaque, token: u64) !bool {
        const self = from(raw);
        const result = uv.pi_uv_tcp_close(self.endpoint, token);
        try self.status(result, .close);
        return result == 1;
    }
    fn referenced(raw: *anyopaque, yes: bool) !void {
        const self = from(raw);
        try self.status(uv.pi_uv_tcp_set_referenced(self.endpoint, @intFromBool(yes)), .reference);
    }
    fn errorValue(raw: *anyopaque, engine: *Engine, failure: anyerror) !c.JSValue {
        try engine.checkNativeEntry();
        if (failure != error.NativeTcpLibuvFailure) return failure;
        const self = from(raw);
        const controller = try Controller.existing(engine, self.service);
        return controller.errnoValue(self.last_status, self.last_operation.text());
    }
    fn hooks(self: *NativeEndpoint) socket.Hooks {
        return .{ .context = self, .read = read, .write = write, .finish = finish,
            .destroy = destroy, .referenced = referenced, .error_value = errorValue,
            .retain = retain, .abandon = abandon, .release = release };
    }
};

/// One external native entitlement. Its release never pretends a native close.
pub const ListenerLease = struct {
    native: *NativeEndpoint,
    pub fn retain(self: ListenerLease) ListenerLease { NativeEndpoint.retain(self.native); return self; }
    pub fn release(self: *ListenerLease) void { NativeEndpoint.release(self.native); self.* = undefined; }
    pub fn abandon(self: ListenerLease) void { NativeEndpoint.abandon(self.native); }
    pub fn bind(self: ListenerLease, address_text: [:0]const u8, port: u16, flags: u32) c_int {
        return uv.pi_uv_tcp_bind(self.native.endpoint, address_text.ptr, port, flags);
    }
    pub fn listen(self: ListenerLease, backlog: c_int) c_int {
        return uv.pi_uv_tcp_listen(self.native.endpoint, backlog);
    }
    pub fn close(self: ListenerLease) c_int { return uv.pi_uv_tcp_close(self.native.endpoint, 0); }
    pub fn referenced(self: ListenerLease, yes: bool) c_int {
        return uv.pi_uv_tcp_set_referenced(self.native.endpoint, @intFromBool(yes));
    }
    pub fn address(self: ListenerLease, result: *Address) c_int {
        return uv.pi_uv_tcp_address(self.native.endpoint, 0, result);
    }
};

/// Keeps the same actual Socket/opaque state. Caller retires this entitlement
/// through its own C435 completion; the Hub independently owns active delivery.
pub const SocketLease = struct {
    native: *NativeEndpoint,
    owned: socket.Owned,
    pub fn clone(self: *const SocketLease) SocketLease {
        NativeEndpoint.retain(self.native);
        return .{ .native = self.native, .owned = self.owned.clone() };
    }
    pub fn value(self: *const SocketLease) c.JSValue { return self.owned.socket; }
    pub fn retireInto(self: *SocketLease, completion: *Completion) void {
        completion.release(self.owned.socket);
        completion.release(self.owned.holder);
        NativeEndpoint.release(self.native);
        self.* = undefined;
    }
    pub fn stopRead(self: *const SocketLease) c_int { return uv.pi_uv_tcp_read_stop(self.native.endpoint); }
    pub fn noDelay(self: *const SocketLease, yes: bool) c_int {
        return uv.pi_uv_tcp_nodelay(self.native.endpoint, @intFromBool(yes));
    }
    pub fn keepAlive(self: *const SocketLease, yes: bool, delay_seconds: u32) c_int {
        return uv.pi_uv_tcp_keepalive(self.native.endpoint, @intFromBool(yes), delay_seconds);
    }
    pub fn address(self: *const SocketLease, peer: bool, result: *Address) c_int {
        return uv.pi_uv_tcp_address(self.native.endpoint, @intFromBool(peer), result);
    }
};

/// Only lives on the owner stack during actual ACCEPT delivery. An unclaimed
/// event retains its close entitlement; adopt transfers that exact endpoint.
pub const Accepted = struct {
    event: *uv.PiUvEvent,
    claimed: bool = false,
    pub fn adopt(self: *Accepted, controller: *Controller, options: c.JSValue) !SocketLease {
        try controller.entry();
        if (self.claimed) return error.NativeTcpAcceptAlreadyClaimed;
        const endpoint = uv.pi_uv_event_take_accepted(self.event) orelse return error.NativeTcpAcceptMissingEndpoint;
        self.claimed = true;
        return controller.attachSocket(endpoint, options);
    }
};

const PendingConnect = struct {
    next: ?*PendingConnect = null,
    token: u64,
    callback: ConnectCallback,
};
const Entry = struct {
    next: ?*Entry = null,
    native: *NativeEndpoint,
    socket_value: ?socket.Owned = null,
    listener: ?ListenerCallbacks = null,
    connects: ?*PendingConnect = null,
};

pub const Controller = struct {
    hub: *env.Hub,
    service: *uv.PiUvService,
    provider: socket.Provider,
    errno_exception: c.JSValue,
    entries: ?*Entry = null,
    busy: usize = 0,
    stopping: bool = false,

    fn existing(engine: *Engine, service: *uv.PiUvService) !*Controller {
        const raw = engine.native_env_context orelse return error.NativeTcpOwnerDetached;
        const hub: *env.Hub = @ptrCast(@alignCast(raw));
        try hub.assertOwner();
        if (hub.stopping) return error.NativeEnvClosed;
        for (hub.resources.items) |resource| if (resource.tag == @as(?*const anyopaque, &controller_tag)) {
            const self: *Controller = @ptrCast(@alignCast(resource.raw));
            if (self.service == service and !self.stopping) return self;
        };
        return error.NativeTcpOwnerDetached;
    }
    fn entry(self: *Controller) !void {
        try self.hub.assertOwner();
        try self.hub.engine.checkNativeEntry();
        if (self.stopping or self.hub.stopping) return error.NativeEnvClosed;
    }
    pub fn snapshot(self: *Controller) Snapshot { return uv.pi_uv_service_snapshot(self.service); }

    pub fn createListener(self: *Controller, callbacks: ListenerCallbacks) !ListenerLease {
        try self.entry();
        if (!c.JS_IsObject(callbacks.root)) return error.RequiredActualTcpListenerOwner;
        const endpoint = try self.newEndpoint();
        const native = NativeEndpoint.create(self.hub.engine, self.service, endpoint) catch |err| {
            var completion = Completion.initVoid(self.hub.engine, err);
            uv.pi_uv_endpoint_abandon(endpoint); uv.pi_uv_endpoint_release(endpoint);
            try completion.finishVoid(); unreachable;
        };
        const item = hostCreate(self.hub.engine, Entry) catch |err| {
            var completion = Completion.initVoid(self.hub.engine, err);
            NativeEndpoint.abandon(native); NativeEndpoint.release(native);
            try completion.finishVoid(); unreachable;
        };
        var held = callbacks;
        held.root = c.JS_DupValue(self.hub.engine.context, callbacks.root);
        item.* = .{ .native = native, .listener = held, .next = self.entries };
        self.entries = item;
        NativeEndpoint.retain(native);
        return .{ .native = native };
    }
    pub fn createSocket(self: *Controller, options: c.JSValue) !SocketLease {
        try self.entry();
        return self.attachSocket(try self.newEndpoint(), options);
    }
    fn newEndpoint(self: *Controller) !*uv.PiUvEndpoint {
        var endpoint: ?*uv.PiUvEndpoint = null;
        const result = uv.pi_uv_tcp_create(self.service, &endpoint);
        if (result.allocation_failed != 0) {
            var completion = Completion.initVoid(self.hub.engine, error.OutOfMemory);
            try completion.finishVoid(); unreachable;
        }
        if (result.status < 0) {
            try raiseStatus(self.hub.engine, self.errno_exception, result.status, "socket");
            unreachable;
        }
        return endpoint orelse return error.NativeTcpMissingCreatedEndpoint;
    }
    /// Consumes one actual endpoint on every return, including pending failure.
    fn attachSocket(self: *Controller, endpoint: *uv.PiUvEndpoint, options: c.JSValue) !SocketLease {
        self.busy += 1; defer self.busy -= 1;
        const engine = self.hub.engine;
        self.entry() catch |err| {
            var completion = Completion.initVoid(engine, err);
            uv.pi_uv_endpoint_abandon(endpoint); uv.pi_uv_endpoint_release(endpoint);
            try completion.finishVoid(); unreachable;
        };
        const native = NativeEndpoint.create(engine, self.service, endpoint) catch |err| {
            var completion = Completion.initVoid(engine, err);
            uv.pi_uv_endpoint_abandon(endpoint); uv.pi_uv_endpoint_release(endpoint);
            try completion.finishVoid(); unreachable;
        };
        const item = hostCreate(engine, Entry) catch |err| {
            var completion = Completion.initVoid(engine, err);
            NativeEndpoint.abandon(native); NativeEndpoint.release(native);
            try completion.finishVoid(); unreachable;
        };
        const actual = self.provider.createOwned(options, native.hooks()) catch |err| {
            var completion = Completion.initVoid(engine, err);
            NativeEndpoint.abandon(native); NativeEndpoint.release(native);
            hostDestroy(engine, item);
            try completion.finishVoid(); unreachable;
        };
        var completion = Completion.initVoid(engine, engine.checkNativeEntry());
        completion.finishVoid() catch |err| {
            var rollback = Completion.initVoid(engine, err);
            rollback.release(actual.socket); rollback.release(actual.holder);
            NativeEndpoint.abandon(native); NativeEndpoint.release(native);
            hostDestroy(engine, item);
            try rollback.finishVoid(); unreachable;
        };
        // No guest call, root retirement or allocation after this publication.
        item.* = .{ .native = native, .socket_value = actual, .next = self.entries };
        self.entries = item;
        NativeEndpoint.retain(native);
        return .{ .native = native, .owned = actual.clone() };
    }
    pub fn connect(self: *Controller, lease: *const SocketLease, address: [:0]const u8,
        port: u16, token: u64, callback: ConnectCallback) !c_int
    {
        try self.entry();
        if (lease.owned.engine != self.hub.engine or lease.native.service != self.service)
            return error.NativeTcpSocketOwnerMismatch;
        const item = self.find(lease.native.endpoint) orelse return error.NativeTcpSocketOwnerDetached;
        if (!c.JS_IsObject(callback.root)) return error.RequiredActualTcpConnectOwner;
        var previous = item.connects;
        while (previous) |request| : (previous = request.next)
            if (request.token == token) return error.NativeTcpDuplicateConnectToken;
        const request = try hostCreate(self.hub.engine, PendingConnect);
        var held = callback;
        held.root = c.JS_DupValue(self.hub.engine.context, callback.root);
        request.* = .{ .token = token, .callback = held };
        const result = uv.pi_uv_tcp_connect(lease.native.endpoint, address.ptr, port, token);
        if (result.status < 0 or result.allocation_failed != 0) {
            var completion = Completion.initVoid(self.hub.engine,
                if (result.allocation_failed != 0) @as(anyerror!void, error.OutOfMemory) else @as(anyerror!void, {}));
            completion.release(request.callback.root); hostDestroy(self.hub.engine, request);
            try completion.finishVoid();
            return result.status;
        }
        request.next = item.connects; item.connects = request;
        return result.status;
    }
    pub fn errnoValue(self: *Controller, status: c_int, syscall: []const u8) !c.JSValue {
        try self.entry();
        return createErrnoValue(self.hub.engine, self.errno_exception, status, syscall);
    }
    fn find(self: *Controller, endpoint: ?*uv.PiUvEndpoint) ?*Entry {
        var cursor = self.entries;
        while (cursor) |item| : (cursor = item.next) if (item.native.endpoint == endpoint) return item;
        return null;
    }
    fn detach(self: *Controller, item: *Entry) void {
        var slot = &self.entries;
        while (slot.*) |current| : (slot = &current.next) if (current == item) {
            slot.* = item.next; item.next = null; return;
        };
        unreachable;
    }
    fn retireEntry(self: *Controller, item: *Entry, completion: *Completion) void {
        while (item.connects) |request| {
            item.connects = request.next;
            completion.release(request.callback.root); hostDestroy(self.hub.engine, request);
        }
        if (item.socket_value) |actual| {
            item.socket_value = null;
            completion.release(actual.socket); completion.release(actual.holder);
        }
        if (item.listener) |actual| { item.listener = null; completion.release(actual.root); }
        NativeEndpoint.release(item.native); hostDestroy(self.hub.engine, item);
    }
    fn dispatch(self: *Controller, event: *uv.PiUvEvent) !void {
        const info = uv.pi_uv_event_info(event);
        if (info.kind == uv.PI_UV_NATIVE_ALLOCATION_FAILURE) return error.OutOfMemory;
        const item = self.find(info.source) orelse return;
        switch (info.kind) {
            uv.PI_UV_ACCEPT => {
                const listener = item.listener orelse return error.NativeTcpUnexpectedAccept;
                var accepted: Accepted = .{ .event = event };
                try listener.accept(listener.context, self, &accepted);
            },
            uv.PI_UV_LISTEN_ERROR => {
                const listener = item.listener orelse return error.NativeTcpUnexpectedListenFailure;
                try listener.failure(listener.context, self, info.status);
            },
            uv.PI_UV_READ => {
                if (item.socket_value) |*actual| {
                    if (info.status < 0) {
                        var scope: p.Scope = .{ .engine = self.hub.engine };
                        return p.owned.finishVoid(&scope, self.readFailure(&scope, actual, info.status));
                    }
                    const data: []const u8 = if (info.length == 0) &.{} else info.bytes[0..info.length];
                    if (!try actual.push(data)) try item.native.status(uv.pi_uv_tcp_read_stop(item.native.endpoint), .read);
                }
            },
            uv.PI_UV_EOF => if (item.socket_value) |*actual| try actual.eof(),
            uv.PI_UV_WRITE => if (item.socket_value) |*actual| {
                var scope: p.Scope = .{ .engine = self.hub.engine };
                return p.owned.finishVoid(&scope, self.writeComplete(&scope, actual, info));
            },
            uv.PI_UV_SHUTDOWN => if (item.socket_value) |*actual| {
                // Node's afterShutdown calls the already-retained callback;
                // its completion status is not an Error-constructor operation.
                try actual.completeFinal(info.token, c.pi_js_null());
            },
            uv.PI_UV_CONNECT => try self.connectComplete(item, info),
            uv.PI_UV_CLOSE => {
                item.native.close_observed = true;
                self.detach(item); // Reentrant guest work cannot find a retired entry.
                const result = self.closeComplete(item, info.token);
                var completion = Completion.initVoid(self.hub.engine, result);
                self.retireEntry(item, &completion);
                try completion.finishVoid();
            },
            else => return error.NativeTcpUnexpectedCompletion,
        }
    }
    fn readFailure(self: *Controller, scope: *p.Scope, actual: *socket.Owned, status: c_int) !void {
        const reason = try p.own(scope, try self.errnoValue(status, "read"));
        _ = try p.invoke(scope, actual.socket, "destroy", &.{reason});
    }
    fn writeComplete(self: *Controller, scope: *p.Scope, actual: *socket.Owned, info: uv.PiUvEventInfo) !void {
        const reason = if (info.status < 0)
            try p.own(scope, try self.errnoValue(info.status, "write")) else c.pi_js_null();
        try actual.completeWrite(info.token, info.length, reason);
    }
    fn connectComplete(self: *Controller, item: *Entry, info: uv.PiUvEventInfo) !void {
        var slot = &item.connects;
        while (slot.*) |request| : (slot = &request.next) if (request.token == info.token) {
            slot.* = request.next;
            const callback = request.callback;
            const result: anyerror!void = if (item.socket_value) |actual|
                callback.complete(callback.context, self, actual.socket, info.status, info.token)
                else error.NativeTcpConnectSocketMissing;
            var completion = Completion.initVoid(self.hub.engine, result);
            completion.release(callback.root); hostDestroy(self.hub.engine, request);
            return completion.finishVoid();
        };
        return error.NativeTcpStaleConnectCompletion;
    }
    fn closeComplete(self: *Controller, item: *Entry, token: u64) !void {
        if (item.socket_value) |*actual| {
            if (token != 0) try actual.completeDestroy(token, c.pi_js_null());
        }
        if (item.listener) |listener| try listener.closed(listener.context, self);
    }
    fn ready(raw: *anyopaque) bool {
        const self: *Controller = @ptrCast(@alignCast(raw));
        return self.busy == 0 and !self.stopping;
    }
    fn deliver(raw: *anyopaque, event: *uv.PiUvEvent) !void {
        const self: *Controller = @ptrCast(@alignCast(raw));
        try self.entry();
        self.busy += 1;
        defer self.busy -= 1;
        return self.dispatch(event);
    }
    fn abandon(_: *anyopaque, _: *uv.PiUvEvent) !void {
        // Preserve original TCP teardown: queued events are released without
        // invoking guest actors; stopped() then retires their native entries.
    }
    fn stop(raw: *anyopaque) void {
        const self: *Controller = @ptrCast(@alignCast(raw));
        if (self.stopping) return;
        std.debug.assert(self.busy == 0);
        self.stopping = true;
        const actual = uv.pi_uv_service_snapshot(self.service);
        // The shared service was registered before this controller, so its
        // sole stop owner has already drained callbacks and joined the loop.
        if (actual.thread_joined == 0 or actual.live_handles != 0 or actual.pending_requests != 0)
            @panic("libuv TCP controller stopped before its shared service");
        var cursor = self.entries;
        while (cursor) |item| : (cursor = item.next) item.native.close_observed = true;
    }
    fn stopped(raw: *anyopaque) void {
        const self: *Controller = @ptrCast(@alignCast(raw));
        const engine = self.hub.engine;
        std.debug.assert(self.stopping);
        // The earlier shared resource has drained/released the actual FIFO.
        var completion = Completion.initVoid(engine, {});
        while (self.entries) |item| {
            self.entries = item.next; item.next = null;
            self.retireEntry(item, &completion);
        }
        completion.release(self.provider.constructor);
        completion.release(self.provider.states);
        completion.release(self.errno_exception);
        _ = completion.finishVoid() catch {};
        uv.pi_uv_service_release(self.service);
        hostDestroy(engine, self);
    }
};

fn statusName(status: c_int) []const u8 { return std.mem.span(uv.pi_uv_error_name(status)); }
fn hostCreate(engine: *Engine, comptime T: type) !*T {
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(T)) == 0) return error.OutOfMemory;
    errdefer c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(T));
    return engine.gpa.create(T);
}
fn hostDestroy(engine: *Engine, value: anytype) void {
    const size = @sizeOf(@TypeOf(value.*));
    engine.gpa.destroy(value);
    c.pi_js_native_memory_release(engine.native_memory_owner, size);
}
fn errnoBody(scope: *p.Scope, constructor: c.JSValue, status: c_int, syscall: []const u8) !c.JSValue {
    return p.duplicate(scope, try p.construct(scope, constructor,
        &.{ c.JS_NewInt32(scope.engine.context, status), try p.text(scope, syscall) }));
}
fn createErrnoValue(engine: *Engine, constructor: c.JSValue, status: c_int, syscall: []const u8) !c.JSValue {
    var scope: p.Scope = .{ .engine = engine };
    return p.owned.finishValue(&scope, errnoBody(&scope, constructor, status, syscall));
}
fn raiseStatus(engine: *Engine, constructor: c.JSValue, status: c_int, syscall: []const u8) !void {
    const reason = try createErrnoValue(engine, constructor, status, syscall);
    _ = try engine.checked(c.JS_Throw(engine.context, reason));
    unreachable;
}

/// One controller per actual Hub. Inputs are the completed canonical Socket and
/// shared ErrnoException actors. Publication follows all admission allocations.
pub fn acquire(engine: *Engine, inputs: Inputs) !*Controller {
    try engine.checkNativeEntry();
    const hub = try env.get(engine); try hub.assertOwner();
    if (hub.stopping) return error.NativeEnvClosed;
    if (inputs.provider.engine != engine or !c.JS_IsConstructor(engine.context, inputs.errno_exception))
        return error.RequiredActualTcpDependencies;
    for (hub.resources.items) |resource| if (resource.tag == @as(?*const anyopaque, &controller_tag)) {
        const existing: *Controller = @ptrCast(@alignCast(resource.raw));
        if (existing.stopping or !c.JS_IsStrictEqual(engine.context, existing.provider.constructor, inputs.provider.constructor) or
            !c.JS_IsStrictEqual(engine.context, existing.provider.states, inputs.provider.states) or
            !c.JS_IsStrictEqual(engine.context, existing.errno_exception, inputs.errno_exception))
            return error.NativeTcpDependencyMismatch;
        return existing;
    };
    const shared = switch (try shared_service.acquire(engine)) {
        .ready => |actual| actual,
        .failed => |status| {
            try raiseStatus(engine, inputs.errno_exception, status, "uv_loop");
            unreachable;
        },
    };
    const self = try hostCreate(engine, Controller);
    const provider = inputs.provider.clone(engine) catch |err| {
        var completion = Completion.initVoid(engine, err);
        hostDestroy(engine, self);
        try completion.finishVoid();
        unreachable;
    };
    hub.resources.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var completion = Completion.initVoid(engine, err);
        completion.release(provider.constructor);
        completion.release(provider.states);
        hostDestroy(engine, self);
        try completion.finishVoid();
        unreachable;
    };
    self.* = .{ .hub = hub, .service = shared.service, .provider = provider,
        .errno_exception = c.JS_DupValue(engine.context, inputs.errno_exception) };
    shared.attach(.tcp, .{
        .raw = self, .ready = Controller.ready,
        .complete = Controller.deliver, .abandon = Controller.abandon,
    }) catch |err| {
        var completion = Completion.initVoid(engine, err);
        completion.release(self.provider.constructor);
        completion.release(self.provider.states);
        completion.release(self.errno_exception);
        hostDestroy(engine, self);
        try completion.finishVoid();
        unreachable;
    };
    // No guest call/allocation follows attachment. Controller's own native
    // service entitlement survives the earlier shared resource's stopped().
    uv.pi_uv_service_retain(shared.service);
    hub.resources.appendAssumeCapacity(.{
        .raw = self, .tag = &controller_tag,
        .stop = Controller.stop, .stopped = Controller.stopped,
    });
    return self;
}
