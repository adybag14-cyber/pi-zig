//! Native event-driven Pi client built over the incremental connection core.
//! The API is synchronous at the transport boundary (matching Zig's explicit
//! I/O model); request completions arrive through isolated callbacks.
const std = @import("std");
const protocol = @import("../protocol/root.zig");
const msg = protocol.messages;
const server_json = protocol.server_json;
const connection_mod = @import("connection.zig");
const request_encoder = @import("request.zig");
const state_mod = @import("state.zig");
const lease_mod = @import("lease.zig");

pub const Error = error{
    Disposed,
    Disconnected,
    MissingTransport,
    ResponseWithoutRequest,
    ResponseCommandMismatch,
    InvalidRequestId,
    LeaseDetached,
};

pub const ClientFailure = enum {
    disconnected,
    disposed,
    protocol_violation,
    transport_failure,
};

pub const RequestFailure = union(enum) {
    server: msg.ProtocolError,
    client: ClientFailure,
};

pub const RequestOutcome = union(enum) {
    success: msg.CommandResult,
    failure: RequestFailure,
};

pub const RequestCallback = struct {
    context: ?*anyopaque = null,
    callback: *const fn (?*anyopaque, u64, RequestOutcome) anyerror!void,
};

pub const ConnectionListener = struct {
    context: ?*anyopaque = null,
    callback: *const fn (?*anyopaque, connection_mod.ConnectionState) anyerror!void,
};

pub const ByteTransport = struct {
    context: ?*anyopaque = null,
    send_fn: *const fn (?*anyopaque, []const u8) anyerror!void,
    close_fn: *const fn (?*anyopaque) void,

    pub fn send(self: ByteTransport, bytes: []const u8) !void {
        return self.send_fn(self.context, bytes);
    }
    pub fn close(self: ByteTransport) void {
        self.close_fn(self.context);
    }
};

pub const Options = struct {
    max_frame_length: usize = protocol.framing.DEFAULT_MAX_FRAME_LENGTH,
    listener_error_handler: ?state_mod.ListenerErrorHandler = null,
};

const PendingRequest = struct {
    command: msg.CommandName,
    callback: ?RequestCallback,
};

const ConnectionSubscription = struct {
    id: u64,
    listener: ConnectionListener,
};

pub const Client = struct {
    gpa: std.mem.Allocator,
    connection: connection_mod.Connection,
    state: state_mod.ClientState,
    leases: lease_mod.Manager,
    transport: ?ByteTransport = null,
    transport_closed: bool = true,
    pending: std.AutoHashMap(u64, PendingRequest),
    server_owner: ?server_json.ParsedServerMessage = null,
    session_owners: std.StringHashMap(server_json.ParsedServerMessage),
    connection_listeners: std.ArrayList(ConnectionSubscription) = .empty,
    request_sequence: u64 = 0,
    listener_sequence: u64 = 1,
    disposed: bool = false,
    last_failure: ?ClientFailure = null,

    pub fn init(gpa: std.mem.Allocator, options: Options) !Client {
        return .{
            .gpa = gpa,
            .connection = try connection_mod.Connection.init(gpa, options.max_frame_length),
            .state = state_mod.ClientState.init(gpa, options.listener_error_handler),
            .leases = lease_mod.Manager.init(gpa),
            .pending = std.AutoHashMap(u64, PendingRequest).init(gpa),
            .session_owners = std.StringHashMap(server_json.ParsedServerMessage).init(gpa),
        };
    }

    pub fn deinit(self: *Client) void {
        if (!self.disposed) self.dispose();
        self.clearSnapshotOwners();
        self.connection_listeners.deinit(self.gpa);
        self.session_owners.deinit();
        self.pending.deinit();
        self.leases.deinit();
        self.state.deinit();
        self.connection.deinit();
        self.* = undefined;
    }

    pub fn connectionState(self: *const Client) connection_mod.ConnectionState {
        return self.connection.state;
    }

    pub fn connected(self: *const Client) bool {
        return self.connection.state == .connected;
    }

    pub fn snapshot(self: *const Client) ?*const msg.ServerSnapshot {
        return self.state.snapshot();
    }

    pub fn sessionSnapshot(self: *const Client, session_id: []const u8) ?*const msg.SessionSnapshot {
        return self.state.getSessionSnapshot(session_id);
    }

    pub fn connect(self: *Client, transport: ByteTransport) !void {
        if (self.disposed) return Error.Disposed;
        if (self.connection.state != .disconnected) return switch (self.connection.state) {
            .connecting => connection_mod.Error.AlreadyConnecting,
            .connected => connection_mod.Error.AlreadyConnected,
            .disconnected => unreachable,
        };
        self.state.reset();
        self.clearSnapshotOwners();
        self.last_failure = null;
        self.transport = transport;
        self.transport_closed = false;
        const connection_handlers = self.handlers();
        const hello = self.connection.start(connection_handlers) catch |err| {
            self.closeTransport();
            return err;
        };
        defer self.gpa.free(hello);
        try self.connection.markTransportReady();
        transport.send(hello) catch |err| {
            self.last_failure = .transport_failure;
            self.connection.disconnect(connection_handlers);
            self.closeTransport();
            return err;
        };
    }

    pub fn reconnect(self: *Client, transport: ByteTransport) !void {
        return self.connect(transport);
    }

    pub fn feed(self: *Client, chunk: []const u8) !void {
        if (self.disposed) return Error.Disposed;
        if (self.transport == null) return Error.MissingTransport;
        self.connection.push(chunk, self.handlers()) catch |err| {
            if (self.last_failure == null) self.last_failure = .protocol_violation;
            self.closeTransport();
            return err;
        };
    }

    pub fn transportEnded(self: *Client) !void {
        if (self.disposed) return Error.Disposed;
        self.connection.end(self.handlers()) catch |err| {
            self.closeTransport();
            return err;
        };
        self.closeTransport();
    }

    pub fn disconnect(self: *Client) void {
        if (self.connection.state != .disconnected) {
            self.last_failure = .disconnected;
            self.connection.disconnect(self.handlers());
        }
        self.closeTransport();
    }

    pub fn dispose(self: *Client) void {
        if (self.disposed) return;
        self.disposed = true;
        self.rejectAllPending(.disposed);
        self.connection.disconnect(self.handlers());
        self.closeTransport();
        self.clearSnapshotOwners();
        self.state.reset();
        self.last_failure = .disposed;
    }

    pub fn subscribe(self: *Client, listener: state_mod.ServerSnapshotListener) !state_mod.ListenerId {
        if (self.disposed) return Error.Disposed;
        return self.state.subscribe(listener);
    }

    pub fn onEvent(self: *Client, listener: state_mod.EventListener) !state_mod.ListenerId {
        if (self.disposed) return Error.Disposed;
        return self.state.onEvent(listener);
    }

    pub fn subscribeSession(self: *Client, session_id: []const u8, listener: state_mod.SessionSnapshotListener) !state_mod.ListenerId {
        if (self.disposed) return Error.Disposed;
        return self.state.subscribeSession(session_id, listener);
    }

    pub fn onSessionEvent(self: *Client, session_id: []const u8, listener: state_mod.EventListener) !state_mod.ListenerId {
        if (self.disposed) return Error.Disposed;
        return self.state.onSessionEvent(session_id, listener);
    }

    pub fn unsubscribe(self: *Client, id: state_mod.ListenerId) bool {
        return self.state.unsubscribe(id);
    }

    pub fn onConnectionStateChange(self: *Client, listener: ConnectionListener) !u64 {
        if (self.disposed) return Error.Disposed;
        const id = self.listener_sequence;
        self.listener_sequence +%= 1;
        if (self.listener_sequence == 0) self.listener_sequence = 1;
        try self.connection_listeners.append(self.gpa, .{ .id = id, .listener = listener });
        return id;
    }

    pub fn removeConnectionStateListener(self: *Client, id: u64) bool {
        for (self.connection_listeners.items, 0..) |entry, index| {
            if (entry.id == id) {
                _ = self.connection_listeners.orderedRemove(index);
                return true;
            }
        }
        return false;
    }

    pub fn request(self: *Client, command: msg.Command, callback: ?RequestCallback) !u64 {
        if (self.disposed) return Error.Disposed;
        if (!self.connected()) return Error.Disconnected;
        const transport = self.transport orelse return Error.MissingTransport;
        const token = self.allocateRequestToken();
        const request_id = try std.fmt.allocPrint(self.gpa, "request-{d}", .{token});
        defer self.gpa.free(request_id);
        const frame = try request_encoder.encodeRequestFrame(self.gpa, request_id, command, self.connection.max_frame_length);
        defer self.gpa.free(frame);
        try self.pending.put(token, .{ .command = @enumFromInt(@intFromEnum(command)), .callback = callback });
        transport.send(frame) catch |err| {
            _ = self.pending.remove(token);
            if (callback) |handler| self.invokeRequestCallback(handler, token, .{ .failure = .{ .client = .transport_failure } });
            self.last_failure = .transport_failure;
            self.connection.disconnect(self.handlers());
            self.closeTransport();
            return err;
        };
        return token;
    }

    pub fn reserveSessionLease(self: *Client, session_id: []const u8, mode: lease_mod.Mode) !lease_mod.LeaseId {
        if (self.disposed) return Error.Disposed;
        return self.leases.reserve(session_id, mode);
    }

    pub fn leaseActive(self: *Client, lease_id: lease_mod.LeaseId) bool {
        const session_id = self.leases.sessionId(lease_id) orelse return false;
        return self.leases.isActive(lease_id, self.state.isSessionAttached(session_id));
    }

    pub fn beginLeaseRelease(self: *Client, lease_id: lease_mod.LeaseId) !lease_mod.ReleaseAction {
        if (self.disposed) return Error.Disposed;
        return self.leases.beginRelease(lease_id);
    }

    pub fn finishLeaseRelease(self: *Client, lease_id: lease_mod.LeaseId, success: bool, relinquish_on_failure: bool) !void {
        return self.leases.finishRelease(lease_id, success, relinquish_on_failure);
    }

    /// Removes completed, invalidated, or abandoned lease bookkeeping. Active
    /// leases are relinquished locally, so callers must detach from the server
    /// first whenever the session is actually attached.
    pub fn removeSessionLease(self: *Client, lease_id: lease_mod.LeaseId) bool {
        return self.leases.removeLease(lease_id);
    }

    pub fn sessionLeaseState(self: *Client, lease_id: lease_mod.LeaseId) ?lease_mod.State {
        return self.leases.state(lease_id);
    }

    pub fn sessionLeaseSessionId(self: *Client, lease_id: lease_mod.LeaseId) ?[]const u8 {
        return self.leases.sessionId(lease_id);
    }

    pub fn sessionCleanupRequired(self: *const Client, session_id: []const u8) bool {
        return self.leases.requiresCleanup(session_id);
    }

    pub fn markSessionCleanupReconciled(self: *Client, session_id: []const u8) bool {
        return self.leases.markReconciled(session_id);
    }

    /// Routes diagnostics from higher-level wrappers through the same isolated
    /// listener-error hook as core state and connection listeners.
    pub fn reportExternalListenerError(self: *Client, err: anyerror) void {
        self.reportListenerError(err);
    }

    pub fn requestForLease(self: *Client, lease_id: lease_mod.LeaseId, command: msg.Command, callback: ?RequestCallback) !u64 {
        if (!self.leaseActive(lease_id)) return Error.LeaseDetached;
        const expected_session = self.leases.sessionId(lease_id) orelse return Error.LeaseDetached;
        const actual_session = commandSessionId(command) orelse return Error.LeaseDetached;
        if (!std.mem.eql(u8, expected_session, actual_session)) return Error.LeaseDetached;
        return self.request(command, callback);
    }

    fn handlers(self: *Client) connection_mod.Handlers {
        return .{
            .context = self,
            .on_handshake = onHandshake,
            .on_handshake_error = onHandshakeError,
            .on_message = onMessage,
            .on_state_change = onConnectionState,
        };
    }

    fn onHandshake(raw: ?*anyopaque, parsed_value: server_json.ParsedServerMessage) anyerror!void {
        const self: *Client = @ptrCast(@alignCast(raw.?));
        var parsed = parsed_value;
        errdefer parsed.deinit();
        if (self.server_owner) |*previous| previous.deinit();
        self.server_owner = parsed;
        const stable = self.server_owner.?.message.hello.snapshot;
        _ = self.state.applyServerSnapshot(stable);
    }

    fn onHandshakeError(raw: ?*anyopaque, parsed_value: server_json.ParsedServerMessage) anyerror!void {
        const self: *Client = @ptrCast(@alignCast(raw.?));
        var parsed = parsed_value;
        defer parsed.deinit();
        self.last_failure = .protocol_violation;
    }

    fn onMessage(raw: ?*anyopaque, parsed_value: server_json.ParsedServerMessage) anyerror!void {
        const self: *Client = @ptrCast(@alignCast(raw.?));
        switch (parsed_value.message) {
            .response => try self.handleResponse(parsed_value),
            .event => try self.handleEvent(parsed_value),
            .hello, .hello_error => unreachable,
        }
    }

    fn onConnectionState(raw: ?*anyopaque, next: connection_mod.ConnectionState) void {
        const self: *Client = @ptrCast(@alignCast(raw.?));
        if (next == .disconnected) {
            self.state.clearAttachments();
            self.leases.invalidateAll() catch {};
            if (!self.disposed) self.rejectAllPending(self.last_failure orelse .disconnected);
        }
        for (self.connection_listeners.items) |entry| {
            entry.listener.callback(entry.listener.context, next) catch |err| self.reportListenerError(err);
        }
    }

    fn handleResponse(self: *Client, parsed_value: server_json.ParsedServerMessage) !void {
        var parsed = parsed_value;
        const response_id = switch (parsed.message.response) {
            .ok => |value| value.id,
            .err => |value| value.id,
        };
        const token = parseRequestToken(response_id) orelse {
            parsed.deinit();
            return Error.InvalidRequestId;
        };
        const pending = self.pending.fetchRemove(token) orelse {
            parsed.deinit();
            return Error.ResponseWithoutRequest;
        };
        switch (parsed.message.response) {
            .err => |failure| {
                if (pending.value.callback) |callback| self.invokeRequestCallback(callback, token, .{ .failure = .{ .server = failure.error_info } });
                parsed.deinit();
            },
            .ok => |success| {
                const actual: msg.CommandName = @enumFromInt(@intFromEnum(success.result));
                if (actual != pending.value.command) {
                    if (pending.value.callback) |callback| self.invokeRequestCallback(callback, token, .{ .failure = .{ .client = .protocol_violation } });
                    parsed.deinit();
                    return Error.ResponseCommandMismatch;
                }
                try self.applySuccessfulResult(token, pending.value.callback, parsed);
            },
        }
    }

    fn applySuccessfulResult(
        self: *Client,
        token: u64,
        callback: ?RequestCallback,
        parsed_value: server_json.ParsedServerMessage,
    ) !void {
        var parsed = parsed_value;
        const result = parsed.message.response.ok.result;
        if (resultSessionSnapshot(result)) |session| {
            const accepted = if (self.state.getSessionSnapshot(session.id)) |current| session.revision >= current.revision else true;
            if (accepted) {
                try self.storeSessionOwner(session.id, parsed);
                const stable_result = self.session_owners.getPtr(session.id).?.message.response.ok.result;
                try self.state.applyResult(stable_result);
                if (callback) |handler| self.invokeRequestCallback(handler, token, .{ .success = stable_result });
            } else {
                try self.state.applyResult(result);
                if (callback) |handler| self.invokeRequestCallback(handler, token, .{ .success = result });
                parsed.deinit();
            }
            return;
        }
        try self.state.applyResult(result);
        if (callback) |handler| self.invokeRequestCallback(handler, token, .{ .success = result });
        parsed.deinit();
    }

    fn handleEvent(self: *Client, parsed_value: server_json.ParsedServerMessage) !void {
        var parsed = parsed_value;
        switch (parsed.message.event) {
            .server_snapshot => |snapshot_value| {
                const accepted = if (self.state.snapshot()) |current| snapshot_value.revision >= current.revision else true;
                if (accepted) {
                    if (self.server_owner) |*previous| previous.deinit();
                    self.server_owner = parsed;
                    const event = self.server_owner.?.message.event;
                    try self.state.applyEvent(event);
                } else {
                    try self.state.applyEvent(parsed.message.event);
                    parsed.deinit();
                }
            },
            .session_snapshot => |snapshot_value| {
                const accepted = if (self.state.getSessionSnapshot(snapshot_value.id)) |current| snapshot_value.revision >= current.revision else true;
                if (accepted) {
                    try self.storeSessionOwner(snapshot_value.id, parsed);
                    const event = self.session_owners.getPtr(snapshot_value.id).?.message.event;
                    try self.state.applyEvent(event);
                } else {
                    try self.state.applyEvent(parsed.message.event);
                    parsed.deinit();
                }
            },
            .session_removed => |removed| {
                const id_copy = try self.gpa.dupe(u8, removed.session_id);
                defer self.gpa.free(id_copy);
                try self.state.applyEvent(parsed.message.event);
                try self.leases.invalidateSession(id_copy);
                self.removeSessionOwner(id_copy);
                parsed.deinit();
            },
            .session_progress => {
                try self.state.applyEvent(parsed.message.event);
                parsed.deinit();
            },
        }
    }

    fn storeSessionOwner(self: *Client, session_id: []const u8, parsed: server_json.ParsedServerMessage) !void {
        if (self.session_owners.getPtr(session_id)) |previous| {
            previous.deinit();
            previous.* = parsed;
            return;
        }
        const key = try self.gpa.dupe(u8, session_id);
        errdefer self.gpa.free(key);
        try self.session_owners.put(key, parsed);
    }

    fn removeSessionOwner(self: *Client, session_id: []const u8) void {
        if (self.session_owners.fetchRemove(session_id)) |removed| {
            self.gpa.free(removed.key);
            var parsed = removed.value;
            parsed.deinit();
        }
    }

    fn clearSnapshotOwners(self: *Client) void {
        if (self.server_owner) |*owner| owner.deinit();
        self.server_owner = null;
        var iterator = self.session_owners.iterator();
        while (iterator.next()) |entry| {
            self.gpa.free(entry.key_ptr.*);
            entry.value_ptr.deinit();
        }
        self.session_owners.clearRetainingCapacity();
    }

    fn rejectAllPending(self: *Client, failure: ClientFailure) void {
        var callbacks: std.ArrayList(struct { token: u64, callback: RequestCallback }) = .empty;
        defer callbacks.deinit(self.gpa);
        var iterator = self.pending.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.callback) |callback| callbacks.append(self.gpa, .{ .token = entry.key_ptr.*, .callback = callback }) catch {};
        }
        self.pending.clearRetainingCapacity();
        for (callbacks.items) |entry| self.invokeRequestCallback(entry.callback, entry.token, .{ .failure = .{ .client = failure } });
    }

    fn invokeRequestCallback(self: *Client, callback: RequestCallback, token: u64, outcome: RequestOutcome) void {
        callback.callback(callback.context, token, outcome) catch |err| self.reportListenerError(err);
    }

    fn reportListenerError(self: *Client, err: anyerror) void {
        if (self.state.listener_error_handler) |handler| handler.callback(handler.context, err);
    }

    fn closeTransport(self: *Client) void {
        if (self.transport_closed) return;
        self.transport_closed = true;
        if (self.transport) |transport| transport.close();
        self.transport = null;
    }

    fn allocateRequestToken(self: *Client) u64 {
        while (true) {
            self.request_sequence +%= 1;
            if (self.request_sequence == 0) self.request_sequence = 1;
            if (!self.pending.contains(self.request_sequence)) return self.request_sequence;
        }
    }
};

fn parseRequestToken(id: []const u8) ?u64 {
    const prefix = "request-";
    if (!std.mem.startsWith(u8, id, prefix) or id.len == prefix.len) return null;
    const value = std.fmt.parseInt(u64, id[prefix.len..], 10) catch return null;
    if (value == 0) return null;
    return value;
}

fn resultSessionSnapshot(result: msg.CommandResult) ?msg.SessionSnapshot {
    return switch (result) {
        .create => |value| value,
        .attach => |value| value,
        .prompt => |value| value,
        .steer => |value| value,
        .abort => |value| value,
        .set_model => |value| value,
        .set_thinking => |value| value,
        .list, .detach => null,
    };
}

fn commandSessionId(command: msg.Command) ?[]const u8 {
    return switch (command) {
        .attach => |value| value.session_id,
        .detach => |value| value.session_id,
        .prompt => |value| value.session_id,
        .steer => |value| value.session_id,
        .abort => |value| value.session_id,
        .set_model => |value| value.session_id,
        .set_thinking => |value| value.session_id,
        .list, .create => null,
    };
}

const empty_server =
    "{\"serverId\":\"server-1\",\"protocolVersion\":1,\"revision\":0,\"sessions\":[],\"models\":[]}";
const session_one =
    "{\"id\":\"s1\",\"cwd\":\"/tmp\",\"createdAt\":1,\"updatedAt\":1,\"phase\":\"idle\",\"model\":{\"provider\":\"test\",\"id\":\"model\"},\"thinkingLevel\":\"off\",\"attached\":true,\"locked\":false,\"revision\":1,\"transcript\":[],\"queuedSteer\":[],\"queuedSteerCount\":0}";
const session_three =
    "{\"id\":\"s1\",\"cwd\":\"/tmp\",\"createdAt\":1,\"updatedAt\":3,\"phase\":\"idle\",\"model\":{\"provider\":\"test\",\"id\":\"model\"},\"thinkingLevel\":\"high\",\"attached\":true,\"locked\":false,\"revision\":3,\"transcript\":[],\"queuedSteer\":[],\"queuedSteerCount\":0}";

const MemoryTransport = struct {
    gpa: std.mem.Allocator,
    sent: std.ArrayList([]u8) = .empty,
    closes: usize = 0,

    fn deinit(self: *@This()) void {
        for (self.sent.items) |bytes| self.gpa.free(bytes);
        self.sent.deinit(self.gpa);
    }
    fn transport(self: *@This()) ByteTransport {
        return .{ .context = self, .send_fn = send, .close_fn = close };
    }
    fn send(raw: ?*anyopaque, bytes: []const u8) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        try self.sent.append(self.gpa, try self.gpa.dupe(u8, bytes));
    }
    fn close(raw: ?*anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.closes += 1;
    }
};

fn feedJson(client: *Client, json: []const u8) !void {
    const frame = try protocol.codec.encodeJsonFrame(std.testing.allocator, json);
    defer std.testing.allocator.free(frame);
    try client.feed(frame);
}

test "client handshake request correlation and authoritative snapshot state" {
    const gpa = std.testing.allocator;
    var transport: MemoryTransport = .{ .gpa = gpa };
    defer transport.deinit();
    var client = try Client.init(gpa, .{});
    defer client.deinit();
    try client.connect(transport.transport());
    try std.testing.expectEqual(@as(usize, 1), transport.sent.items.len);
    var hello = try protocol.codec.decodeClientFrame(gpa, transport.sent.items[0]);
    defer protocol.json.deinitClientMessage(gpa, &hello);
    try std.testing.expect(hello == .hello);
    try feedJson(&client, "{\"type\":\"hello\",\"version\":1,\"connectionId\":\"c1\",\"snapshot\":" ++ empty_server ++ "}");
    try std.testing.expect(client.connected());

    const CallbackContext = struct {
        success: usize = 0,
        revision: u64 = 0,
        fn complete(raw: ?*anyopaque, _: u64, outcome: RequestOutcome) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            switch (outcome) {
                .success => |result| {
                    self.success += 1;
                    self.revision = result.attach.revision;
                },
                .failure => return error.UnexpectedFailure,
            }
        }
    };
    var callback_context: CallbackContext = .{};
    const token = try client.request(.{ .attach = .{ .session_id = "s1" } }, .{ .context = &callback_context, .callback = CallbackContext.complete });
    try std.testing.expectEqual(@as(u64, 1), token);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-1\",\"ok\":true,\"result\":{\"command\":\"attach\",\"session\":" ++ session_one ++ "}}");
    try std.testing.expectEqual(@as(usize, 1), callback_context.success);
    try std.testing.expectEqual(@as(u64, 1), client.sessionSnapshot("s1").?.revision);

    try feedJson(&client, "{\"type\":\"event\",\"event\":{\"type\":\"session_snapshot\",\"snapshot\":" ++ session_three ++ "}}");
    try std.testing.expectEqual(@as(u64, 3), client.sessionSnapshot("s1").?.revision);
    const token2 = try client.request(.{ .set_thinking = .{ .session_id = "s1", .thinking_level = .medium } }, null);
    try std.testing.expectEqual(@as(u64, 2), token2);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-2\",\"ok\":true,\"result\":{\"command\":\"set_thinking\",\"session\":" ++ session_one ++ "}}");
    try std.testing.expectEqual(@as(u64, 3), client.sessionSnapshot("s1").?.revision);
}

test "client rejects unmatched and command-mismatched responses" {
    const gpa = std.testing.allocator;
    var transport: MemoryTransport = .{ .gpa = gpa };
    defer transport.deinit();
    var client = try Client.init(gpa, .{});
    defer client.deinit();
    try client.connect(transport.transport());
    try feedJson(&client, "{\"type\":\"hello\",\"version\":1,\"connectionId\":\"c1\",\"snapshot\":" ++ empty_server ++ "}");
    try std.testing.expectError(Error.ResponseWithoutRequest, feedJson(&client, "{\"type\":\"response\",\"id\":\"request-99\",\"ok\":true,\"result\":{\"command\":\"list\",\"sessions\":[]}}"));
    try std.testing.expect(!client.connected());

    try client.connect(transport.transport());
    try feedJson(&client, "{\"type\":\"hello\",\"version\":1,\"connectionId\":\"c2\",\"snapshot\":" ++ empty_server ++ "}");
    _ = try client.request(.{ .list = {} }, null);
    try std.testing.expectError(Error.ResponseCommandMismatch, feedJson(&client, "{\"type\":\"response\",\"id\":\"request-1\",\"ok\":true,\"result\":{\"command\":\"detach\",\"sessionId\":\"s1\"}}"));
    try std.testing.expect(!client.connected());
}

test "client disconnect invalidates leases and rejects pending requests" {
    const gpa = std.testing.allocator;
    var transport: MemoryTransport = .{ .gpa = gpa };
    defer transport.deinit();
    var client = try Client.init(gpa, .{});
    defer client.deinit();
    try client.connect(transport.transport());
    try feedJson(&client, "{\"type\":\"hello\",\"version\":1,\"connectionId\":\"c1\",\"snapshot\":" ++ empty_server ++ "}");
    try feedJson(&client, "{\"type\":\"event\",\"event\":{\"type\":\"session_snapshot\",\"snapshot\":" ++ session_one ++ "}}");
    const lease = try client.reserveSessionLease("s1", .exclusive);
    try std.testing.expect(client.leaseActive(lease));
    const CallbackContext = struct {
        disconnected: usize = 0,
        fn complete(raw: ?*anyopaque, _: u64, outcome: RequestOutcome) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (outcome == .failure and outcome.failure == .client and outcome.failure.client == .disconnected) self.disconnected += 1;
        }
    };
    var callback_context: CallbackContext = .{};
    _ = try client.request(.{ .list = {} }, .{ .context = &callback_context, .callback = CallbackContext.complete });
    client.disconnect();
    try std.testing.expectEqual(@as(usize, 1), callback_context.disconnected);
    try std.testing.expect(!client.leaseActive(lease));
    try std.testing.expectEqual(@as(usize, 1), transport.closes);
}
