//! Concurrent native MCP request ownership and initialize/close fences.
const std = @import("std");
const protocol = @import("protocol.zig");
const json = protocol.json;
const Value = protocol.Value;
const Transport = @import("transport.zig").Transport;
const CallbackFrame = struct { client: *Client, owner: ?*const anyopaque, previous: ?*CallbackFrame };
threadlocal var callback_frames: ?*CallbackFrame = null;
pub const State = enum { idle, connecting, connected, closed };
pub const Context = struct {
    abort_flag: ?*bool = null,
    pub fn aborted(self: Context) bool {
        return if (self.abort_flag) |flag| @atomicLoad(bool, flag, .acquire) else false;
    }
};
pub const Notification = *const fn (?*anyopaque, []const u8, ?Value) anyerror!void;
pub const ErrorListener = *const fn (?*anyopaque, anyerror) void;
pub const Progress = *const fn (?*anyopaque, Value) anyerror!void;
pub const Options = struct {
    name: []const u8 = "pi-zig",
    version: []const u8 = "1.0.3",
    title: ?[]const u8 = null,
    capabilities: ?Value = null,
    roots: ?Value = null,
    request_timeout_ms: f64 = 30_000,
    context: ?*anyopaque = null,
    on_notification: ?Notification = null,
    on_error: ?ErrorListener = null,
    max_pending: usize = 1024,
    /// Optional monotonic clock for deterministic deadline policy verification.
    /// Production uses Io.Clock.awake; context must outlive this Client.
    clock_context: ?*anyopaque = null,
    clock_now_ms: ?*const fn (?*anyopaque, std.Io) i64 = null,
};
pub const RequestOptions = struct { context: Context = .{}, timeout_ms: ?f64 = null, on_progress: ?Progress = null, progress_context: ?*anyopaque = null, on_remote_error: ?Progress = null, remote_error_context: ?*anyopaque = null };
const Pending = struct {
    id: u64,
    event: std.Io.Event = .unset,
    reply: ?json.Owned = null,
    cause: ?anyerror = null,
    canceled: bool = false,
    callbacks: usize = 0,
    options: RequestOptions,
    deadline: std.atomic.Value(i64) = .init(0),
    timeout_ms: f64,
};
const CancelReason = enum { closed, timeout, aborted };
pub const Client = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    transport: Transport,
    owned: json.Owned,
    options: Options,
    mutex: std.Io.Mutex = .init,
    close_mutex: std.Io.Mutex = .init,
    changed: std.Io.Condition = .init,
    state: State = .idle,
    connect_active: bool = false,
    next_id: u64 = 1,
    pending: std.AutoHashMap(u64, *Pending),
    notifying: std.ArrayList(*bool) = .empty,
    initialized: ?json.Owned = null,
    callback_thread: std.atomic.Value(std.Thread.Id) = .init(0),
    /// Bound once before transport.start; callback frames snapshot this owner.
    callback_owner: ?*const anyopaque = null,
    unknown_responses: std.atomic.Value(usize) = .init(0),
    pub fn create(gpa: std.mem.Allocator, io: std.Io, transport: Transport, options: Options) !*Client {
        if (options.max_pending == 0) return error.InvalidMcpPendingLimit;
        const self = try gpa.create(Client);
        errdefer gpa.destroy(self);
        self.* = .{ .gpa = gpa, .io = io, .transport = transport, .owned = try json.Owned.empty(gpa), .options = options, .pending = .init(gpa) };
        errdefer self.owned.deinit();
        const a = self.owned.arena.allocator();
        self.options.name = try a.dupe(u8, options.name);
        self.options.version = try a.dupe(u8, options.version);
        if (options.title) |title| self.options.title = try a.dupe(u8, title);
        if (options.capabilities) |capabilities| {
            if (capabilities != .object) return error.InvalidMcpCapabilities;
            self.options.capabilities = try json.clone(a, capabilities);
        }
        if (options.roots) |roots| {
            if (roots != .array) return error.InvalidMcpRoots;
            self.options.roots = try json.clone(a, roots);
        }
        return self;
    }
    pub fn deinit(self: *Client) void {
        // A callback cannot destroy the client it is executing through. The
        // caller must retry teardown after returning to its owning safe point.
        self.close() catch return;
        self.pending.deinit();
        self.notifying.deinit(self.gpa);
        if (self.initialized) |*value| value.deinit();
        self.owned.deinit();
        const gpa = self.gpa;
        gpa.destroy(self);
    }
    pub fn connectionState(self: *Client) State {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.state;
    }
    pub fn pendingCount(self: *Client) usize {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.pending.count();
    }
    pub fn inCallback(self: *Client) bool {
        var frame = callback_frames;
        while (frame) |value| {
            if (value.client == self) return true;
            frame = value.previous;
        }
        return self.callback_thread.load(.acquire) == std.Thread.getCurrentId();
    }
    pub fn inOwnerCallback(owner: *const anyopaque) bool {
        var frame = callback_frames;
        while (frame) |value| {
            if (value.owner == owner) return true;
            frame = value.previous;
        }
        return false;
    }
    fn reentrant(self: *Client) bool {
        return self.inCallback();
    }
    pub fn connect(self: *Client) !json.Owned {
        if (self.reentrant()) return error.ReentrantMcpConnect;
        try self.mutex.lock(self.io);
        if (self.state != .idle) {
            self.mutex.unlock(self.io);
            return error.InvalidMcpClientState;
        }
        self.state = .connecting;
        self.connect_active = true;
        self.mutex.unlock(self.io);
        defer self.finishConnect();
        errdefer {
            self.finishConnect();
            self.close() catch {};
        }
        try self.transport.start(.{ .context = self, .message = receive, .failure = reportRaw, .closed = transportClosed });
        var params = try json.Owned.empty(self.gpa);
        defer params.deinit();
        const a = params.arena.allocator();
        var value: Value = .{ .object = .empty };
        try value.object.put(a, "protocolVersion", .{ .string = @import("client.zig").latest_protocol_version });
        var capabilities = if (self.options.capabilities) |data| try json.clone(a, data) else Value{ .object = .empty };
        if (self.options.roots != null and json.get(capabilities, "roots") == null) try capabilities.object.put(a, "roots", .{ .object = .empty });
        try value.object.put(a, "capabilities", capabilities);
        var info: Value = .{ .object = .empty };
        try info.object.put(a, "name", .{ .string = self.options.name });
        try info.object.put(a, "version", .{ .string = self.options.version });
        if (self.options.title) |title| try info.object.put(a, "title", .{ .string = title });
        try value.object.put(a, "clientInfo", info);
        var response = try self.requestInternal("initialize", value, .{}, true);
        errdefer response.deinit();
        try validateInitialize(response.value);
        var snapshot = try json.Owned.empty(self.gpa);
        errdefer snapshot.deinit();
        snapshot.value = try json.clone(snapshot.arena.allocator(), response.value);
        try self.transport.setProtocolVersion(try protocol.text(response.value, "protocolVersion"));
        try self.notifyInternal("notifications/initialized", null, true);
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        if (self.state == .closed) return error.McpConnectionClosed;
        self.initialized = snapshot;
        self.state = .connected;
        return response;
    }
    fn finishConnect(self: *Client) void {
        self.mutex.lockUncancelable(self.io);
        self.connect_active = false;
        self.changed.broadcast(self.io);
        self.mutex.unlock(self.io);
    }
    pub fn request(self: *Client, method: []const u8, params: ?Value, options: RequestOptions) !json.Owned {
        return self.requestInternal(method, params, options, false);
    }
    fn requestInternal(self: *Client, method: []const u8, params: ?Value, options: RequestOptions, connecting: bool) !json.Owned {
        if (self.reentrant()) return error.ReentrantMcpRequest;
        if (options.context.aborted()) return error.McpRequestAborted;
        var pending: Pending = .{ .id = 0, .options = options, .timeout_ms = options.timeout_ms orelse self.options.request_timeout_ms };
        try self.mutex.lock(self.io);
        if (self.state != .connected and !(connecting and self.state == .connecting)) {
            self.mutex.unlock(self.io);
            return error.McpConnectionClosed;
        }
        if (self.pending.count() >= self.options.max_pending) {
            self.mutex.unlock(self.io);
            return error.McpPendingLimit;
        }
        if (self.next_id > protocol.max_id) {
            self.mutex.unlock(self.io);
            return error.McpRequestIdExhausted;
        }
        pending.id = self.next_id;
        self.next_id += 1;
        self.pending.put(pending.id, &pending) catch |cause| {
            self.mutex.unlock(self.io);
            return cause;
        };
        self.mutex.unlock(self.io);
        defer {
            self.retirePending(&pending);
            if (pending.reply) |*reply| reply.deinit();
        }
        var request_params = try json.Owned.empty(self.gpa);
        defer request_params.deinit();
        var data = params;
        if (options.on_progress != null) {
            var object = if (params) |param| try json.clone(request_params.arena.allocator(), param) else Value{ .object = .empty };
            if (object != .object) return error.InvalidMcpParams;
            var meta = if (json.get(object, "_meta")) |existing| if (existing == .object) try json.clone(request_params.arena.allocator(), existing) else Value{ .object = .empty } else Value{ .object = .empty };
            try meta.object.put(request_params.arena.allocator(), "progressToken", .{ .integer = @intCast(pending.id) });
            try object.object.put(request_params.arena.allocator(), "_meta", meta);
            data = object;
        }
        var envelope = try protocol.request(self.gpa, pending.id, method, data);
        defer envelope.deinit();
        self.mutex.lockUncancelable(self.io);
        resetDeadline(self, &pending);
        self.mutex.unlock(self.io);
        const Race = union(enum) { response: anyerror!void, canceled: anyerror!CancelReason };
        var queue: [2]Race = undefined;
        var select = std.Io.Select(Race).init(self.io, &queue);
        defer while (select.cancel()) |_| {};
        try select.concurrent(.response, sendAwait, .{ self, &pending, envelope.value });
        try select.concurrent(.canceled, watchPending, .{ self, &pending });
        const winner = try select.await();
        var cancellation: ?CancelReason = null;
        switch (winner) {
            .response => |result| result catch |cause| {
                if (!self.hasReply(&pending)) {
                    self.mutex.lockUncancelable(self.io);
                    const committed = pending.cause;
                    self.mutex.unlock(self.io);
                    if (committed != null and committed.? == error.McpTimeout) cancellation = .timeout else return committed orelse cause;
                }
            },
            .canceled => |result| cancellation = try result,
        }
        if (cancellation) |reason| {
            const cause: anyerror = switch (reason) {
                .closed => error.McpConnectionClosed,
                .timeout => error.McpTimeout,
                .aborted => error.McpRequestAborted,
            };
            @atomicStore(bool, &pending.canceled, true, .release);
            while (select.cancel()) |_| {}
            if (!self.hasReply(&pending)) {
                if (cause != error.McpConnectionClosed and !std.mem.eql(u8, method, "initialize")) self.cancelNotification(pending.id, if (cause == error.McpTimeout) "Request timed out" else "Aborted") catch |failure| self.report(failure);
                return cause;
            }
        }
        self.mutex.lockUncancelable(self.io);
        if (pending.cause) |cause| {
            self.mutex.unlock(self.io);
            return cause;
        }
        var reply = pending.reply orelse {
            self.mutex.unlock(self.io);
            return error.McpMissingResponse;
        };
        pending.reply = null;
        self.mutex.unlock(self.io);
        if (json.get(reply.value, "error")) |failure| {
            defer reply.deinit();
            if (options.on_remote_error) |callback| {
                var frame: CallbackFrame = .{ .client = self, .owner = self.callback_owner, .previous = callback_frames };
                callback_frames = &frame;
                defer callback_frames = frame.previous;
                try callback(options.remote_error_context, failure);
            }
            return error.McpRemoteError;
        }
        const result = try protocol.field(reply.value, "result");
        reply.value = result;
        return reply;
    }
    fn sendAwait(self: *Client, pending: *Pending, value: Value) anyerror!void {
        try self.transport.send(value, &pending.canceled);
        try pending.event.wait(self.io);
    }
    fn hasReply(self: *Client, pending: *Pending) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return pending.reply != null;
    }
    fn watchPending(self: *Client, pending: *Pending) anyerror!CancelReason {
        while (true) {
            if (@atomicLoad(bool, &pending.canceled, .acquire)) return .closed;
            if (pending.options.context.aborted()) return .aborted;
            const end = pending.deadline.load(.acquire);
            if (end != 0 and self.nowMs() >= end and self.expireObserved(pending, end)) return .timeout;
            try self.io.sleep(.fromMilliseconds(5), .awake);
        }
    }
    /// The observed deadline may have been replaced by a concurrently received progress frame.
    /// Publish expiry under the same mutex as progress/reset and result publication.
    fn expireObserved(self: *Client, pending: *Pending, observed: i64) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const current = pending.deadline.load(.acquire);
        if (current == 0 or current != observed or pending.reply != null or pending.cause != null or @atomicLoad(bool, &pending.canceled, .acquire)) return false;
        if (self.nowMs() < current) return false;
        pending.cause = error.McpTimeout;
        @atomicStore(bool, &pending.canceled, true, .release);
        return true;
    }
    fn retirePending(self: *Client, pending: *Pending) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        _ = self.pending.remove(pending.id);
        self.changed.broadcast(self.io);
        while (pending.callbacks > 0) self.changed.waitUncancelable(self.io, &self.mutex);
    }
    fn releaseCallback(self: *Client, pending: *Pending) void {
        self.mutex.lockUncancelable(self.io);
        pending.callbacks -= 1;
        self.changed.broadcast(self.io);
        self.mutex.unlock(self.io);
    }
    fn resetDeadline(self: *Client, pending: *Pending) void {
        const timeout = pending.timeout_ms;
        if (!std.math.isFinite(timeout) or timeout <= 0) {
            pending.deadline.store(0, .release);
            return;
        }
        const millis: i64 = @intFromFloat(@min(@ceil(timeout), @as(f64, @floatFromInt(std.math.maxInt(i64) / 2))));
        pending.deadline.store(self.nowMs() +| millis, .release);
    }
    fn nowMs(self: *Client) i64 {
        return if (self.options.clock_now_ms) |clock| clock(self.options.clock_context, self.io) else std.Io.Clock.awake.now(self.io).toMilliseconds();
    }
    pub fn notify(self: *Client, method: []const u8, params: ?Value) !void {
        return self.notifyInternal(method, params, false);
    }
    fn notifyInternal(self: *Client, method: []const u8, params: ?Value, connecting: bool) !void {
        var canceled = false;
        try self.mutex.lock(self.io);
        const allowed = self.state == .connected or (connecting and self.state == .connecting);
        if (allowed) self.notifying.append(self.gpa, &canceled) catch |cause| {
            self.mutex.unlock(self.io);
            return cause;
        };
        self.mutex.unlock(self.io);
        if (!allowed) return error.McpConnectionClosed;
        defer {
            self.mutex.lockUncancelable(self.io);
            for (self.notifying.items, 0..) |entry, index| if (entry == &canceled) {
                _ = self.notifying.swapRemove(index);
                break;
            };
            self.changed.broadcast(self.io);
            self.mutex.unlock(self.io);
        }
        var envelope = try protocol.request(self.gpa, null, method, params);
        defer envelope.deinit();
        const Race = union(enum) { sent: anyerror!void, canceled: anyerror!void };
        var queue: [2]Race = undefined;
        var select = std.Io.Select(Race).init(self.io, &queue);
        defer while (select.cancel()) |_| {};
        try select.concurrent(.sent, sendNotification, .{ self, envelope.value, &canceled });
        try select.concurrent(.canceled, watchCanceled, .{ self.io, &canceled });
        switch (try select.await()) {
            .sent => |result| try result,
            .canceled => |result| {
                try result;
                return error.McpConnectionClosed;
            },
        }
    }
    fn sendNotification(self: *Client, value: Value, canceled: *bool) anyerror!void {
        return self.transport.send(value, canceled);
    }
    fn watchCanceled(io: std.Io, flag: *bool) anyerror!void {
        while (!@atomicLoad(bool, flag, .acquire)) try io.sleep(.fromMilliseconds(5), .awake);
    }
    fn cancelNotification(self: *Client, id: u64, reason: []const u8) !void {
        var params = try json.Owned.empty(self.gpa);
        defer params.deinit();
        const a = params.arena.allocator();
        var data: Value = .{ .object = .empty };
        try data.object.put(a, "requestId", .{ .integer = @intCast(id) });
        try data.object.put(a, "reason", .{ .string = reason });
        try self.notify("notifications/cancelled", data);
    }
    fn from(raw: ?*anyopaque) *Client {
        return @ptrCast(@alignCast(raw.?));
    }
    fn reportRaw(raw: ?*anyopaque, cause: anyerror) void {
        const self = from(raw);
        if (cause == error.OutOfMemory) {
            self.mutex.lockUncancelable(self.io);
            var pending = self.pending.iterator();
            while (pending.next()) |item| {
                if (item.value_ptr.*.reply == null and item.value_ptr.*.cause == null) item.value_ptr.*.cause = cause;
                item.value_ptr.*.event.set(self.io);
            }
            self.mutex.unlock(self.io);
        }
        self.report(cause);
    }
    fn report(self: *Client, cause: anyerror) void {
        var frame: CallbackFrame = .{ .client = self, .owner = self.callback_owner, .previous = callback_frames };
        callback_frames = &frame;
        defer callback_frames = frame.previous;
        if (self.options.on_error) |callback| callback(self.options.context, cause);
    }
    fn transportClosed(raw: ?*anyopaque) void {
        from(raw).markClosed();
    }
    fn markClosed(self: *Client) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.state = .closed;
        var pending = self.pending.iterator();
        while (pending.next()) |item| {
            if (item.value_ptr.*.reply == null and item.value_ptr.*.cause == null) item.value_ptr.*.cause = error.McpConnectionClosed;
            @atomicStore(bool, &item.value_ptr.*.canceled, true, .release);
            item.value_ptr.*.event.set(self.io);
        }
        for (self.notifying.items) |flag| @atomicStore(bool, flag, true, .release);
        self.changed.broadcast(self.io);
    }
    fn receive(raw: ?*anyopaque, value: Value) !void {
        const self = from(raw);
        var frame: CallbackFrame = .{ .client = self, .owner = self.callback_owner, .previous = callback_frames };
        callback_frames = &frame;
        defer callback_frames = frame.previous;
        self.callback_thread.store(std.Thread.getCurrentId(), .release);
        defer self.callback_thread.store(0, .release);
        switch (try protocol.kind(value)) {
            .response => {
                const id = try protocol.field(value, "id");
                const numeric = json.asInteger(id) catch {
                    _ = self.unknown_responses.fetchAdd(1, .monotonic);
                    self.report(error.UnknownMcpResponse);
                    return;
                };
                self.mutex.lockUncancelable(self.io);
                defer self.mutex.unlock(self.io);
                const pending = self.pending.get(numeric) orelse {
                    _ = self.unknown_responses.fetchAdd(1, .monotonic);
                    return;
                };
                if (pending.cause != null or pending.reply != null) return;
                var owned = json.Owned.empty(self.gpa) catch |cause| {
                    pending.cause = cause;
                    pending.event.set(self.io);
                    return cause;
                };
                errdefer owned.deinit();
                owned.value = json.clone(owned.arena.allocator(), value) catch |cause| {
                    pending.cause = cause;
                    pending.event.set(self.io);
                    return cause;
                };
                pending.reply = owned;
                pending.event.set(self.io);
            },
            .notification => {
                const method = try protocol.text(value, "method");
                const params = json.get(value, "params");
                if (std.mem.eql(u8, method, "notifications/progress") and params != null and params.? == .object) {
                    const token = json.get(params.?, "progressToken");
                    const amount = json.get(params.?, "progress");
                    if (token != null and amount != null and (amount.? == .integer or amount.? == .float)) {
                        const id = json.asInteger(token.?) catch 0;
                        var callback: ?Progress = null;
                        var context: ?*anyopaque = null;
                        var retained: ?*Pending = null;
                        self.mutex.lockUncancelable(self.io);
                        if (self.pending.get(id)) |pending| if (pending.cause == null and pending.reply == null and !@atomicLoad(bool, &pending.canceled, .acquire)) {
                            resetDeadline(self, pending);
                            callback = pending.options.on_progress;
                            context = pending.options.progress_context;
                            if (callback != null) {
                                pending.callbacks += 1;
                                retained = pending;
                            }
                        };
                        self.mutex.unlock(self.io);
                        if (retained) |pending| {
                            defer self.releaseCallback(pending);
                            if (callback) |function| function(context, params.?) catch |cause| self.report(cause);
                        }
                    }
                }
                if (self.options.on_notification) |callback| callback(self.options.context, method, params) catch |cause| self.report(cause);
            },
            .request => {
                const method = try protocol.text(value, "method");
                var response: json.Owned = undefined;
                if (std.mem.eql(u8, method, "ping")) response = try protocol.response(self.gpa, try protocol.field(value, "id"), .{ .object = .empty }, false) else if (std.mem.eql(u8, method, "roots/list") and self.options.roots != null) {
                    var result = try json.Owned.empty(self.gpa);
                    defer result.deinit();
                    var data: Value = .{ .object = .empty };
                    try data.object.put(result.arena.allocator(), "roots", self.options.roots.?);
                    response = try protocol.response(self.gpa, try protocol.field(value, "id"), data, false);
                } else {
                    var failure = try json.Owned.empty(self.gpa);
                    defer failure.deinit();
                    const message = try std.fmt.allocPrint(failure.arena.allocator(), "Method not found: {s}", .{method});
                    response = try protocol.response(self.gpa, try protocol.field(value, "id"), try protocol.rpcError(failure.arena.allocator(), -32601, message), true);
                }
                defer response.deinit();
                try self.transport.send(response.value, null);
            },
        }
    }
    pub fn close(self: *Client) !void {
        if (self.reentrant()) return error.ReentrantMcpClose;
        self.close_mutex.lockUncancelable(self.io);
        defer self.close_mutex.unlock(self.io);
        self.markClosed();
        self.mutex.lockUncancelable(self.io);
        while (self.pending.count() > 0 or self.connect_active or self.notifying.items.len > 0) self.changed.waitUncancelable(self.io, &self.mutex);
        self.mutex.unlock(self.io);
        try self.transport.close();
    }
};
pub fn validateInitialize(value: Value) !void {
    if (value != .object) return error.InvalidMcpInitialize;
    const capabilities = try protocol.field(value, "capabilities");
    const info = try protocol.field(value, "serverInfo");
    if (capabilities != .object or info != .object) return error.InvalidMcpInitialize;
    _ = try protocol.text(info, "name");
    _ = try protocol.text(info, "version");
    if (json.get(value, "instructions")) |instructions| if (instructions != .string) return error.InvalidMcpInitialize;
    const version = try protocol.text(value, "protocolVersion");
    for (@import("client.zig").supported_protocol_versions) |supported| if (std.mem.eql(u8, version, supported)) return;
    return error.UnsupportedMcpProtocol;
}
const DeadlineTestTransport = struct {
    fail_close: bool = false,
    const Receiver = @import("transport.zig").Receiver;
    fn start(_: *anyopaque, _: Receiver) !void {}
    fn send(_: *anyopaque, _: Value, _: ?*bool) !void {}
    fn close(raw: *anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(raw));
        if (self.fail_close) return error.InjectedMcpTransportClose;
    }
    const vtable: Transport.VTable = .{ .start = start, .send = send, .close = close };
    fn transport(self: *@This()) Transport {
        return .{ .context = self, .vtable = &vtable };
    }
};

test "mcp.runtime deadline arbitration rejects a stale observation after actual progress reset" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var transport: DeadlineTestTransport = .{};
    const client = try Client.create(gpa, io, transport.transport(), .{});
    defer client.deinit();
    client.state = .connected;
    var pending: Pending = .{ .id = 1, .options = .{}, .timeout_ms = 60 };
    pending.deadline.store(std.Io.Clock.awake.now(io).toMilliseconds() - 1, .release);
    try client.pending.put(pending.id, &pending);
    defer client.retirePending(&pending);
    const Race = struct {
        client: *Client,
        pending: *Pending,
        observed: std.Io.Event = .unset,
        reset: std.Io.Event = .unset,
        expired: bool = true,
        fn run(self: *@This()) void {
            const old = self.pending.deadline.load(.acquire);
            self.observed.set(std.testing.io);
            self.reset.waitUncancelable(std.testing.io);
            self.expired = self.client.expireObserved(self.pending, old);
        }
    };
    var race: Race = .{ .client = client, .pending = &pending };
    const owner = try std.Thread.spawn(.{}, Race.run, .{&race});
    var joined = false;
    defer {
        race.reset.set(io);
        if (!joined) owner.join();
    }
    try race.observed.wait(io);
    var progress = try json.Owned.parse(gpa, "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\",\"params\":{\"progressToken\":1,\"progress\":1}}");
    defer progress.deinit();
    try Client.receive(client, progress.value);
    race.reset.set(io);
    owner.join();
    joined = true;
    // Avoid a second join in the cleanup path.
    try std.testing.expect(!race.expired);
    try std.testing.expect(pending.cause == null and !@atomicLoad(bool, &pending.canceled, .acquire));
}

test "mcp.runtime deadline genuine expiry retires late progress while received result wins" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var transport: DeadlineTestTransport = .{};
    const client = try Client.create(gpa, io, transport.transport(), .{});
    defer client.deinit();
    client.state = .connected;
    var pending: Pending = .{ .id = 1, .options = .{}, .timeout_ms = 60 };
    try client.pending.put(1, &pending);
    defer client.retirePending(&pending);
    const expired = std.Io.Clock.awake.now(io).toMilliseconds() - 1;
    pending.deadline.store(expired, .release);
    var result = try json.Owned.empty(gpa);
    result.value = .{ .object = .empty };
    pending.reply = result;
    try std.testing.expect(!client.expireObserved(&pending, expired));
    pending.reply.?.deinit();
    pending.reply = null;
    try std.testing.expect(client.expireObserved(&pending, expired));
    try std.testing.expectEqual(error.McpTimeout, pending.cause.?);
    var progress = try json.Owned.parse(gpa, "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\",\"params\":{\"progressToken\":1,\"progress\":1}}");
    defer progress.deinit();
    try Client.receive(client, progress.value);
    try std.testing.expectEqual(expired, pending.deadline.load(.acquire));
    try std.testing.expect(@atomicLoad(bool, &pending.canceled, .acquire));
}

test "mcp.runtime public request return joins borrowed progress callback and rejects self close" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var transport: DeadlineTestTransport = .{};
    const Capture = struct {
        client: *Client,
        entered: std.Io.Event = .unset,
        release: std.Io.Event = .unset,
        count: usize = 0,
        errors: usize = 0,
        self_close: ?anyerror = null,
        completed: std.atomic.Value(bool) = .init(false),
        fn progress(raw: ?*anyopaque, _: Value) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.count += 1;
            self.entered.set(std.testing.io);
            self.release.waitUncancelable(std.testing.io);
            self.client.close() catch |cause| {
                self.self_close = cause;
            };
            return error.OriginalMcpProgress;
        }
        fn errorListener(raw: ?*anyopaque, cause: anyerror) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (cause == error.OriginalMcpProgress) {
                self.errors += 1;
                self.completed.store(true, .release);
            }
        }
    };
    var capture: Capture = .{ .client = undefined };
    const client = try Client.create(gpa, io, transport.transport(), .{ .context = &capture, .on_error = Capture.errorListener });
    defer client.deinit();
    client.state = .connected;
    capture.client = client;
    const Requester = struct {
        client: *Client,
        capture: *Capture,
        reply: ?json.Owned = null,
        cause: ?anyerror = null,
        returned_early: bool = false,
        done: std.atomic.Value(bool) = .init(false),
        fn run(self: *@This()) void {
            self.reply = self.client.request("progress", null, .{ .timeout_ms = 0, .on_progress = Capture.progress, .progress_context = self.capture }) catch |cause| {
                self.cause = cause;
                self.done.store(true, .release);
                return;
            };
            self.returned_early = !self.capture.completed.load(.acquire);
            self.done.store(true, .release);
        }
    };
    var requester: Requester = .{ .client = client, .capture = &capture };
    const requesting = try std.Thread.spawn(.{}, Requester.run, .{&requester});
    var requesting_joined = false;
    defer {
        capture.release.set(io);
        if (!requesting_joined) {
            client.close() catch {};
            requesting.join();
        }
        if (requester.reply) |*reply| reply.deinit();
    }
    while (client.pendingCount() != 1) try io.sleep(.fromMilliseconds(1), .awake);
    var progress = try json.Owned.parse(gpa, "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\",\"params\":{\"progressToken\":1,\"progress\":1}}");
    defer progress.deinit();
    const Reader = struct {
        client: *Client,
        value: Value,
        cause: ?anyerror = null,
        fn run(self: *@This()) void {
            Client.receive(self.client, self.value) catch |cause| {
                self.cause = cause;
            };
        }
    };
    var reader: Reader = .{ .client = client, .value = progress.value };
    const receiving = try std.Thread.spawn(.{}, Reader.run, .{&reader});
    var receiving_joined = false;
    defer {
        capture.release.set(io);
        if (!receiving_joined) receiving.join();
    }
    try capture.entered.wait(io);
    var response = try json.Owned.parse(gpa, "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"done\":true}}");
    defer response.deinit();
    try Client.receive(client, response.value);
    while (client.pendingCount() != 0) try io.sleep(.fromMilliseconds(1), .awake);
    try std.testing.expect(!requester.done.load(.acquire));
    client.callback_thread.store(0, .release);
    try Client.receive(client, progress.value);
    try std.testing.expectEqual(@as(usize, 1), capture.count);
    capture.release.set(io);
    receiving.join();
    receiving_joined = true;
    requesting.join();
    requesting_joined = true;
    try std.testing.expectEqual(error.ReentrantMcpClose, capture.self_close.?);
    try std.testing.expectEqual(@as(usize, 1), capture.errors);
    try std.testing.expect(!requester.returned_early and requester.cause == null and reader.cause == null);
    try std.testing.expect((try protocol.field(requester.reply.?.value, "done")).bool);
}

test "mcp.runtime connection callback close and deinit reject before an external closer lock and later normal teardown succeeds" {
    const connection = @import("connection.zig");
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const Factory = struct {
        fn create(_: ?*anyopaque, _: std.mem.Allocator, _: std.Io, _: usize) !connection.Lease {
            return error.UnusedTestFactory;
        }
    };
    for ([_]bool{ false, true }) |race_close| {
        var transport: DeadlineTestTransport = .{};
        var owner = connection.Connection.init(gpa, io, .{ .factory = Factory.create });
        const client = try Client.create(gpa, io, transport.transport(), .{});
        client.callback_owner = &owner;
        client.state = .connected;
        owner.client = client;
        owner.state = .ready;
        defer owner.deinit();
        const borrow = try owner.acquire();
        const Capture = struct {
            owner: *connection.Connection,
            client: *Client,
            entered: std.Io.Event = .unset,
            release: std.Io.Event = .unset,
            rejected: bool = false,
            fn progress(raw: ?*anyopaque, _: Value) !void {
                const self: *@This() = @ptrCast(@alignCast(raw.?));
                self.entered.set(std.testing.io);
                self.release.waitUncancelable(std.testing.io);
                try std.testing.expectError(error.ReentrantMcpConnectionClose, self.owner.close());
                self.owner.deinit();
                self.client.deinit();
                // Void teardown must preserve the live callback owner, which
                // will be destroyed once this callback and Borrow retire.
                try std.testing.expect(Client.inOwnerCallback(self.owner));
                self.rejected = true;
            }
        };
        var capture: Capture = .{ .owner = &owner, .client = client };
        const Requester = struct {
            borrow: connection.Borrow,
            capture: *Capture,
            cause: ?anyerror = null,
            reply: ?json.Owned = null,
            fn run(self: *@This()) void {
                defer self.borrow.release();
                self.reply = self.borrow.client.request("progress", null, .{ .timeout_ms = 0, .on_progress = Capture.progress, .progress_context = self.capture }) catch |cause| {
                    self.cause = cause;
                    return;
                };
            }
        };
        var requester: Requester = .{ .borrow = borrow, .capture = &capture };
        const requesting = try std.Thread.spawn(.{}, Requester.run, .{&requester});
        var requesting_joined = false;
        defer {
            capture.release.set(io);
            if (!requesting_joined) {
                client.close() catch {};
                requesting.join();
            }
            if (requester.reply) |*reply| reply.deinit();
        }
        const end = std.Io.Clock.awake.now(io).toMilliseconds() + 2000;
        while (client.pendingCount() != 1) {
            if (std.Io.Clock.awake.now(io).toMilliseconds() >= end) return error.TestRequestDidNotEnter;
            try io.sleep(.fromMilliseconds(1), .awake);
        }
        var progress = try json.Owned.parse(gpa, "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\",\"params\":{\"progressToken\":1,\"progress\":1}}");
        defer progress.deinit();
        const Reader = struct {
            client: *Client,
            value: Value,
            cause: ?anyerror = null,
            fn run(self: *@This()) void {
                Client.receive(self.client, self.value) catch |cause| {
                    self.cause = cause;
                };
            }
        };
        var reader: Reader = .{ .client = client, .value = progress.value };
        const receiving = try std.Thread.spawn(.{}, Reader.run, .{&reader});
        var receiving_joined = false;
        defer {
            capture.release.set(io);
            if (!receiving_joined) receiving.join();
        }
        try capture.entered.wait(io);
        const Closer = struct {
            owner: *connection.Connection,
            cause: ?anyerror = null,
            fn run(self: *@This()) void {
                self.owner.close() catch |cause| {
                    self.cause = cause;
                };
            }
        };
        var closer: Closer = .{ .owner = &owner };
        var closing: ?std.Thread = null;
        defer if (closing) |thread| thread.join();
        if (race_close) {
            closing = try std.Thread.spawn(.{}, Closer.run, .{&closer});
            while (client.connectionState() != .closed) {
                if (std.Io.Clock.awake.now(io).toMilliseconds() >= end) return error.TestCloseDidNotEnter;
                try io.sleep(.fromMilliseconds(1), .awake);
            }
        } else {
            var response = try json.Owned.parse(gpa, "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"done\":true}}");
            defer response.deinit();
            try Client.receive(client, response.value);
        }
        capture.release.set(io);
        receiving.join();
        receiving_joined = true;
        requesting.join();
        requesting_joined = true;
        if (closing) |thread| {
            thread.join();
            closing = null;
        }
        try std.testing.expect(capture.rejected and reader.cause == null and closer.cause == null);
        if (!race_close) {
            try std.testing.expect(!owner.shutdown.load(.acquire));
            try std.testing.expectEqual(State.connected, client.connectionState());
            try std.testing.expect(requester.cause == null);
        } else try std.testing.expectEqual(error.McpConnectionClosed, requester.cause.?);
        transport.fail_close = true;
        try std.testing.expectError(error.InjectedMcpTransportClose, owner.close());
        owner.deinit();
        try std.testing.expect(owner.client == client);
        transport.fail_close = false;
        try owner.close();
        try owner.close();
        try std.testing.expectEqual(connection.State.closed, owner.connectionState());
    }
}
