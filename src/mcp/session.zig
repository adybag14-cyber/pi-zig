//! Concurrent native MCP request ownership and initialize/close fences.
const std = @import("std");
const protocol = @import("protocol.zig");
const json = protocol.json;
const Value = protocol.Value;
const Transport = @import("transport.zig").Transport;
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
};
pub const RequestOptions = struct { context: Context = .{}, timeout_ms: ?f64 = null, on_progress: ?Progress = null, progress_context: ?*anyopaque = null, on_remote_error: ?Progress = null, remote_error_context: ?*anyopaque = null };
const Pending = struct {
    id: u64,
    event: std.Io.Event = .unset,
    reply: ?json.Owned = null,
    cause: ?anyerror = null,
    canceled: bool = false,
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
        self.close() catch {};
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
    fn reentrant(self: *Client) bool {
        return self.callback_thread.load(.acquire) == std.Thread.getCurrentId();
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
            self.mutex.lockUncancelable(self.io);
            _ = self.pending.remove(pending.id);
            self.changed.broadcast(self.io);
            self.mutex.unlock(self.io);
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
        resetDeadline(self, &pending);
        const Race = union(enum) { response: anyerror!void, canceled: anyerror!CancelReason };
        var queue: [2]Race = undefined;
        var select = std.Io.Select(Race).init(self.io, &queue);
        defer while (select.cancel()) |_| {};
        try select.concurrent(.response, sendAwait, .{ self, &pending, envelope.value });
        try select.concurrent(.canceled, watchPending, .{ self, &pending });
        const winner = try select.await();
        switch (winner) {
            .response => |result| result catch |cause| {
                if (!self.hasReply(&pending)) return cause;
            },
            .canceled => |result| {
                const reason = try result;
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
            },
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
            if (options.on_remote_error) |callback| try callback(options.remote_error_context, failure);
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
            if (end != 0 and std.Io.Clock.awake.now(self.io).toMilliseconds() >= end) return .timeout;
            try self.io.sleep(.fromMilliseconds(5), .awake);
        }
    }
    fn resetDeadline(self: *Client, pending: *Pending) void {
        const timeout = pending.timeout_ms;
        if (!std.math.isFinite(timeout) or timeout <= 0) {
            pending.deadline.store(0, .release);
            return;
        }
        const millis: i64 = @intFromFloat(@min(@ceil(timeout), @as(f64, @floatFromInt(std.math.maxInt(i64) / 2))));
        pending.deadline.store(std.Io.Clock.awake.now(self.io).toMilliseconds() + millis, .release);
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
                        self.mutex.lockUncancelable(self.io);
                        if (self.pending.get(id)) |pending| {
                            resetDeadline(self, pending);
                            callback = pending.options.on_progress;
                            context = pending.options.progress_context;
                        }
                        self.mutex.unlock(self.io);
                        if (callback) |function| function(context, params.?) catch |cause| self.report(cause);
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
