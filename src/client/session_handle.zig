//! Lease-safe high-level session handle for the native Pi client.
//!
//! This ports the original `SessionHandle` convenience surface onto Zig's
//! explicit event-driven request model. A handle owns exactly one lease, gates
//! commands on live attachment state, exposes session-scoped subscriptions, and
//! distinguishes explicit detach failures (lease restored) from disposal
//! failures (lease relinquished and reconciliation scheduled).
const std = @import("std");
const protocol = @import("../protocol/root.zig");
const msg = protocol.messages;
const client_mod = @import("client.zig");
const lease_mod = @import("lease.zig");
const state_mod = @import("state.zig");

pub const Error = error{
    InvalidLease,
    LeaseDetached,
    ReleaseInProgress,
    NotReadyToDestroy,
};

pub const ReleaseOutcome = union(enum) {
    success,
    failure: client_mod.RequestFailure,
};

pub const ReleaseCallback = struct {
    context: ?*anyopaque = null,
    callback: *const fn (?*anyopaque, *SessionHandle, ReleaseOutcome) anyerror!void,
};

pub const ReleaseStart = union(enum) {
    no_op,
    released_locally,
    queued: u64,
};

pub const SessionHandle = struct {
    gpa: std.mem.Allocator,
    client: *client_mod.Client,
    session_id: []u8,
    lease_id: lease_mod.LeaseId,
    release_pending: bool = false,
    release_relinquish_on_failure: bool = false,
    release_callback: ?ReleaseCallback = null,
    released: bool = false,

    /// Adopts an already-reserved lease. On failure ownership remains with the
    /// caller. The returned pointer is stable so request callbacks can retain it.
    pub fn adopt(
        gpa: std.mem.Allocator,
        client: *client_mod.Client,
        session_id: []const u8,
        lease_id: lease_mod.LeaseId,
    ) !*SessionHandle {
        const leased_session = client.sessionLeaseSessionId(lease_id) orelse return Error.InvalidLease;
        if (!std.mem.eql(u8, leased_session, session_id)) return Error.InvalidLease;
        const owned_id = try gpa.dupe(u8, session_id);
        errdefer gpa.free(owned_id);
        const self = try gpa.create(SessionHandle);
        self.* = .{
            .gpa = gpa,
            .client = client,
            .session_id = owned_id,
            .lease_id = lease_id,
        };
        return self;
    }

    pub fn id(self: *const SessionHandle) []const u8 {
        return self.session_id;
    }

    pub fn active(self: *SessionHandle) bool {
        if (self.released) return false;
        return self.client.leaseActive(self.lease_id);
    }

    pub fn attached(self: *SessionHandle) bool {
        return self.active();
    }

    pub fn snapshot(self: *SessionHandle) ?*const msg.SessionSnapshot {
        if (!self.active()) return null;
        return self.client.sessionSnapshot(self.session_id);
    }

    pub fn subscribe(self: *SessionHandle, listener: state_mod.SessionSnapshotListener) !state_mod.ListenerId {
        try self.assertActive();
        return self.client.subscribeSession(self.session_id, listener);
    }

    pub fn onEvent(self: *SessionHandle, listener: state_mod.EventListener) !state_mod.ListenerId {
        try self.assertActive();
        return self.client.onSessionEvent(self.session_id, listener);
    }

    pub fn unsubscribe(self: *SessionHandle, listener_id: state_mod.ListenerId) bool {
        return self.client.unsubscribe(listener_id);
    }

    pub fn beginPrompt(self: *SessionHandle, text: []const u8, callback: ?client_mod.RequestCallback) !u64 {
        return self.request(.{ .prompt = .{ .session_id = self.session_id, .text = text } }, callback);
    }

    pub fn beginSteer(self: *SessionHandle, text: []const u8, callback: ?client_mod.RequestCallback) !u64 {
        return self.request(.{ .steer = .{ .session_id = self.session_id, .text = text } }, callback);
    }

    pub fn beginAbort(self: *SessionHandle, callback: ?client_mod.RequestCallback) !u64 {
        return self.request(.{ .abort = .{ .session_id = self.session_id } }, callback);
    }

    pub fn beginSetModel(self: *SessionHandle, model: msg.ModelRef, callback: ?client_mod.RequestCallback) !u64 {
        return self.request(.{ .set_model = .{ .session_id = self.session_id, .model = model } }, callback);
    }

    pub fn beginSetThinking(self: *SessionHandle, thinking_level: msg.ThinkingLevel, callback: ?client_mod.RequestCallback) !u64 {
        return self.request(.{ .set_thinking = .{ .session_id = self.session_id, .thinking_level = thinking_level } }, callback);
    }

    pub fn beginDetach(self: *SessionHandle, callback: ?ReleaseCallback) !ReleaseStart {
        return self.beginRelease(false, callback);
    }

    pub fn beginDispose(self: *SessionHandle, callback: ?ReleaseCallback) !ReleaseStart {
        return self.beginRelease(true, callback);
    }

    pub fn canDestroy(self: *SessionHandle) bool {
        if (self.release_pending) return false;
        if (self.released) return true;
        const state = self.client.sessionLeaseState(self.lease_id) orelse return true;
        return state == .released or state == .invalidated;
    }

    pub fn destroy(self: *SessionHandle) !void {
        if (!self.canDestroy()) return Error.NotReadyToDestroy;
        _ = self.client.removeSessionLease(self.lease_id);
        self.gpa.free(self.session_id);
        const gpa = self.gpa;
        self.* = undefined;
        gpa.destroy(self);
    }

    fn assertActive(self: *SessionHandle) !void {
        if (!self.active()) return Error.LeaseDetached;
        if (self.release_pending) return Error.ReleaseInProgress;
    }

    fn request(self: *SessionHandle, command: msg.Command, callback: ?client_mod.RequestCallback) !u64 {
        try self.assertActive();
        return self.client.requestForLease(self.lease_id, command, callback);
    }

    fn beginRelease(self: *SessionHandle, relinquish_on_failure: bool, callback: ?ReleaseCallback) !ReleaseStart {
        if (self.release_pending) return Error.ReleaseInProgress;
        if (self.released) {
            self.invokeRelease(callback, .success);
            return .no_op;
        }
        const action = try self.client.beginLeaseRelease(self.lease_id);
        switch (action) {
            .none => {
                _ = self.client.removeSessionLease(self.lease_id);
                self.released = true;
                self.invokeRelease(callback, .success);
                return .no_op;
            },
            .released_locally => {
                _ = self.client.removeSessionLease(self.lease_id);
                self.released = true;
                self.invokeRelease(callback, .success);
                return .released_locally;
            },
            .detach_required => {},
        }

        self.release_pending = true;
        self.release_relinquish_on_failure = relinquish_on_failure;
        self.release_callback = callback;
        const token = self.client.request(.{ .detach = .{ .session_id = self.session_id } }, .{
            .context = self,
            .callback = onReleaseResponse,
        }) catch |err| {
            // A transport failure invokes the callback synchronously. Only roll
            // back here when the callback did not already settle the handle.
            if (self.release_pending) {
                self.release_pending = false;
                self.release_callback = null;
                self.client.finishLeaseRelease(self.lease_id, false, relinquish_on_failure) catch {};
                if (relinquish_on_failure) {
                    _ = self.client.removeSessionLease(self.lease_id);
                    self.released = true;
                }
            }
            return err;
        };
        return .{ .queued = token };
    }

    fn onReleaseResponse(raw: ?*anyopaque, _: u64, outcome: client_mod.RequestOutcome) anyerror!void {
        const self: *SessionHandle = @ptrCast(@alignCast(raw.?));
        if (!self.release_pending) return;
        const callback = self.release_callback;
        const relinquish = self.release_relinquish_on_failure;
        self.release_pending = false;
        self.release_callback = null;
        switch (outcome) {
            .success => {
                try self.client.finishLeaseRelease(self.lease_id, true, relinquish);
                _ = self.client.removeSessionLease(self.lease_id);
                self.released = true;
                self.invokeRelease(callback, .success);
            },
            .failure => |failure| {
                self.client.finishLeaseRelease(self.lease_id, false, relinquish) catch {};
                if (relinquish) {
                    _ = self.client.removeSessionLease(self.lease_id);
                    self.released = true;
                }
                self.invokeRelease(callback, .{ .failure = failure });
            },
        }
    }

    fn invokeRelease(self: *SessionHandle, callback: ?ReleaseCallback, outcome: ReleaseOutcome) void {
        if (callback) |handler| handler.callback(handler.context, self, outcome) catch |err| self.client.reportExternalListenerError(err);
    }
};

const TestReleaseProbe = struct {
    calls: usize = 0,
    success: bool = false,

    fn callback(raw: ?*anyopaque, _: *SessionHandle, outcome: ReleaseOutcome) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.calls += 1;
        self.success = outcome == .success;
    }
};

const MemoryTransport = struct {
    gpa: std.mem.Allocator,
    sent: std.ArrayList([]u8) = .empty,

    fn deinit(self: *@This()) void {
        for (self.sent.items) |bytes| self.gpa.free(bytes);
        self.sent.deinit(self.gpa);
    }
    fn transport(self: *@This()) client_mod.ByteTransport {
        return .{ .context = self, .send_fn = send, .close_fn = close };
    }
    fn send(raw: ?*anyopaque, bytes: []const u8) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        try self.sent.append(self.gpa, try self.gpa.dupe(u8, bytes));
    }
    fn close(_: ?*anyopaque) void {}
};

fn feedJson(client: *client_mod.Client, json: []const u8) !void {
    const frame = try protocol.codec.encodeJsonFrame(std.testing.allocator, json);
    defer std.testing.allocator.free(frame);
    try client.feed(frame);
}

const empty_server =
    "{\"serverId\":\"server-1\",\"protocolVersion\":1,\"revision\":0,\"sessions\":[],\"models\":[]}";
const attached_session =
    "{\"id\":\"s1\",\"cwd\":\"/tmp\",\"createdAt\":1,\"updatedAt\":1,\"phase\":\"idle\",\"model\":{\"provider\":\"test\",\"id\":\"model\"},\"thinkingLevel\":\"off\",\"attached\":true,\"locked\":false,\"revision\":1,\"transcript\":[],\"queuedSteer\":[],\"queuedSteerCount\":0}";

test "session handle commands are lease gated and final shared release detaches" {
    const gpa = std.testing.allocator;
    var transport: MemoryTransport = .{ .gpa = gpa };
    defer transport.deinit();
    var client = try client_mod.Client.init(gpa, .{});
    defer client.deinit();
    try client.connect(transport.transport());
    try feedJson(&client, "{\"type\":\"hello\",\"version\":1,\"connectionId\":\"c1\",\"snapshot\":" ++ empty_server ++ "}");
    _ = try client.request(.{ .attach = .{ .session_id = "s1" } }, null);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-1\",\"ok\":true,\"result\":{\"command\":\"attach\",\"session\":" ++ attached_session ++ "}}");

    const first_lease = try client.reserveSessionLease("s1", .shared);
    const second_lease = try client.reserveSessionLease("s1", .shared);
    const first = try SessionHandle.adopt(gpa, &client, "s1", first_lease);
    const second = try SessionHandle.adopt(gpa, &client, "s1", second_lease);
    _ = try first.beginPrompt("hello", null);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-2\",\"ok\":true,\"result\":{\"command\":\"prompt\",\"session\":" ++ attached_session ++ "}}");

    var first_probe: TestReleaseProbe = .{};
    try std.testing.expectEqual(ReleaseStart.released_locally, try first.beginDispose(.{ .context = &first_probe, .callback = TestReleaseProbe.callback }));
    try std.testing.expect(first_probe.success);
    try first.destroy();

    var second_probe: TestReleaseProbe = .{};
    try std.testing.expect((try second.beginDetach(.{ .context = &second_probe, .callback = TestReleaseProbe.callback })) == .queued);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-3\",\"ok\":true,\"result\":{\"command\":\"detach\",\"sessionId\":\"s1\"}}");
    try std.testing.expect(second_probe.success);
    try second.destroy();
}

test "session handle explicit detach failure restores while dispose relinquishes" {
    const gpa = std.testing.allocator;
    var transport: MemoryTransport = .{ .gpa = gpa };
    defer transport.deinit();
    var client = try client_mod.Client.init(gpa, .{});
    defer client.deinit();
    try client.connect(transport.transport());
    try feedJson(&client, "{\"type\":\"hello\",\"version\":1,\"connectionId\":\"c1\",\"snapshot\":" ++ empty_server ++ "}");
    _ = try client.request(.{ .attach = .{ .session_id = "s1" } }, null);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-1\",\"ok\":true,\"result\":{\"command\":\"attach\",\"session\":" ++ attached_session ++ "}}");

    const lease = try client.reserveSessionLease("s1", .exclusive);
    const handle = try SessionHandle.adopt(gpa, &client, "s1", lease);
    _ = try handle.beginDetach(null);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-2\",\"ok\":false,\"error\":{\"code\":\"internal_error\",\"message\":\"detach failed\"}}");
    try std.testing.expect(handle.active());
    try std.testing.expect(!handle.canDestroy());

    _ = try handle.beginDispose(null);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-3\",\"ok\":false,\"error\":{\"code\":\"internal_error\",\"message\":\"detach failed again\"}}");
    try std.testing.expect(handle.canDestroy());
    try std.testing.expect(client.sessionCleanupRequired("s1"));
    try handle.destroy();
}

pub const AcquisitionStatus = enum { pending, succeeded, failed };
pub const AcquisitionFailureSource = enum { local, server, disconnected, disposed, protocol_violation, transport_failure };

pub const AcquisitionFailure = struct {
    source: AcquisitionFailureSource,
    code: ?msg.ProtocolErrorCode = null,
    message: []u8,

    pub fn deinit(self: *AcquisitionFailure, gpa: std.mem.Allocator) void {
        gpa.free(self.message);
        self.* = undefined;
    }
};

pub const AcquisitionCallback = struct {
    context: ?*anyopaque = null,
    callback: *const fn (?*anyopaque, *Acquisition) anyerror!void,
};

const AcquisitionPhase = enum { reconcile, attach, complete };

/// Event-driven equivalent of `PiClient.acquireSession`. The operation owns its
/// successful handle until `takeHandle` is called and owns any copied failure
/// until `destroy`. This makes callback lifetimes independent of frame arenas.
pub const Acquisition = struct {
    gpa: std.mem.Allocator,
    client: *client_mod.Client,
    session_id: []u8,
    mode: lease_mod.Mode,
    lease_id: lease_mod.LeaseId,
    completion: ?AcquisitionCallback,
    status_value: AcquisitionStatus = .pending,
    phase: AcquisitionPhase = .attach,
    handle: ?*SessionHandle = null,
    failure_value: ?AcquisitionFailure = null,
    request_pending: bool = false,

    pub fn begin(
        gpa: std.mem.Allocator,
        client: *client_mod.Client,
        session_id: []const u8,
        mode: lease_mod.Mode,
        completion: ?AcquisitionCallback,
    ) !*Acquisition {
        const owned_id = try gpa.dupe(u8, session_id);
        errdefer gpa.free(owned_id);
        const lease_id = try client.reserveSessionLease(session_id, mode);
        errdefer _ = client.removeSessionLease(lease_id);
        const self = try gpa.create(Acquisition);
        self.* = .{
            .gpa = gpa,
            .client = client,
            .session_id = owned_id,
            .mode = mode,
            .lease_id = lease_id,
            .completion = completion,
        };
        self.start();
        return self;
    }

    pub fn status(self: *const Acquisition) AcquisitionStatus {
        return self.status_value;
    }

    pub fn failure(self: *const Acquisition) ?*const AcquisitionFailure {
        if (self.failure_value) |*value| return value;
        return null;
    }

    pub fn takeHandle(self: *Acquisition) ?*SessionHandle {
        const value = self.handle;
        self.handle = null;
        return value;
    }

    pub fn canDestroy(self: *const Acquisition) bool {
        return self.status_value != .pending and self.handle == null and !self.request_pending;
    }

    pub fn destroy(self: *Acquisition) !void {
        if (!self.canDestroy()) return Error.NotReadyToDestroy;
        if (self.failure_value) |*value| value.deinit(self.gpa);
        self.gpa.free(self.session_id);
        const gpa = self.gpa;
        self.* = undefined;
        gpa.destroy(self);
    }

    fn start(self: *Acquisition) void {
        if (self.client.sessionCleanupRequired(self.session_id)) {
            self.phase = .reconcile;
            self.queue(.{ .detach = .{ .session_id = self.session_id } });
            return;
        }
        if (self.client.leaseActive(self.lease_id)) {
            self.completeAttached();
            return;
        }
        self.phase = .attach;
        self.queue(.{ .attach = .{ .session_id = self.session_id } });
    }

    fn queue(self: *Acquisition, command: msg.Command) void {
        self.request_pending = true;
        _ = self.client.request(command, .{
            .context = self,
            .callback = onResponse,
        }) catch |err| {
            // Client transports may report the same send failure through the
            // callback before returning. Preserve exactly one completion.
            if (self.status_value == .pending and self.request_pending) {
                self.request_pending = false;
                self.failLocal(err);
            }
        };
    }

    fn onResponse(raw: ?*anyopaque, _: u64, outcome: client_mod.RequestOutcome) anyerror!void {
        const self: *Acquisition = @ptrCast(@alignCast(raw.?));
        if (self.status_value != .pending) return;
        self.request_pending = false;
        switch (outcome) {
            .failure => |request_failure| self.failRequest(request_failure),
            .success => switch (self.phase) {
                .reconcile => {
                    _ = self.client.markSessionCleanupReconciled(self.session_id);
                    self.phase = .attach;
                    self.queue(.{ .attach = .{ .session_id = self.session_id } });
                },
                .attach => self.completeAttached(),
                .complete => {},
            },
        }
    }

    fn completeAttached(self: *Acquisition) void {
        if (!self.client.leaseActive(self.lease_id)) {
            self.failStatic(.local, null, "session attach did not yield an active snapshot");
            return;
        }
        self.handle = SessionHandle.adopt(self.gpa, self.client, self.session_id, self.lease_id) catch |err| {
            self.failLocal(err);
            return;
        };
        self.phase = .complete;
        self.status_value = .succeeded;
        self.invokeCompletion();
    }

    fn failRequest(self: *Acquisition, request_failure: client_mod.RequestFailure) void {
        switch (request_failure) {
            .server => |server_failure| self.failStatic(.server, server_failure.code, server_failure.message),
            .client => |client_failure| switch (client_failure) {
                .disconnected => self.failStatic(.disconnected, null, "client disconnected"),
                .disposed => self.failStatic(.disposed, null, "client disposed"),
                .protocol_violation => self.failStatic(.protocol_violation, null, "protocol violation"),
                .transport_failure => self.failStatic(.transport_failure, null, "transport failure"),
            },
        }
    }

    fn failLocal(self: *Acquisition, err: anyerror) void {
        self.failStatic(.local, null, @errorName(err));
    }

    fn failStatic(self: *Acquisition, source: AcquisitionFailureSource, code: ?msg.ProtocolErrorCode, message: []const u8) void {
        if (self.status_value != .pending) return;
        _ = self.client.removeSessionLease(self.lease_id);
        const owned = self.gpa.dupe(u8, message) catch self.gpa.dupe(u8, "acquisition failed") catch {
            self.status_value = .failed;
            self.phase = .complete;
            self.invokeCompletion();
            return;
        };
        self.failure_value = .{ .source = source, .code = code, .message = owned };
        self.status_value = .failed;
        self.phase = .complete;
        self.invokeCompletion();
    }

    fn invokeCompletion(self: *Acquisition) void {
        if (self.completion) |handler| handler.callback(handler.context, self) catch |err| self.client.reportExternalListenerError(err);
    }
};

const AcquisitionProbe = struct {
    calls: usize = 0,
    status: AcquisitionStatus = .pending,

    fn callback(raw: ?*anyopaque, operation: *Acquisition) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.calls += 1;
        self.status = operation.status();
    }
};

test "session acquisition attaches and returns an owned high-level handle" {
    const gpa = std.testing.allocator;
    var transport: MemoryTransport = .{ .gpa = gpa };
    defer transport.deinit();
    var client = try client_mod.Client.init(gpa, .{});
    defer client.deinit();
    try client.connect(transport.transport());
    try feedJson(&client, "{\"type\":\"hello\",\"version\":1,\"connectionId\":\"c1\",\"snapshot\":" ++ empty_server ++ "}");
    var probe: AcquisitionProbe = .{};
    const acquisition = try Acquisition.begin(gpa, &client, "s1", .exclusive, .{
        .context = &probe,
        .callback = AcquisitionProbe.callback,
    });
    try std.testing.expectEqual(AcquisitionStatus.pending, acquisition.status());
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-1\",\"ok\":true,\"result\":{\"command\":\"attach\",\"session\":" ++ attached_session ++ "}}");
    try std.testing.expectEqual(@as(usize, 1), probe.calls);
    try std.testing.expectEqual(AcquisitionStatus.succeeded, acquisition.status());
    const handle = acquisition.takeHandle().?;
    try acquisition.destroy();
    try std.testing.expect(handle.active());
    _ = try handle.beginDispose(null);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-2\",\"ok\":true,\"result\":{\"command\":\"detach\",\"sessionId\":\"s1\"}}");
    try handle.destroy();
}

test "session acquisition reconciles abandoned cleanup before reattaching" {
    const gpa = std.testing.allocator;
    var transport: MemoryTransport = .{ .gpa = gpa };
    defer transport.deinit();
    var client = try client_mod.Client.init(gpa, .{});
    defer client.deinit();
    try client.connect(transport.transport());
    try feedJson(&client, "{\"type\":\"hello\",\"version\":1,\"connectionId\":\"c1\",\"snapshot\":" ++ empty_server ++ "}");
    _ = try client.request(.{ .attach = .{ .session_id = "s1" } }, null);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-1\",\"ok\":true,\"result\":{\"command\":\"attach\",\"session\":" ++ attached_session ++ "}}");
    const abandoned_lease = try client.reserveSessionLease("s1", .exclusive);
    _ = try client.beginLeaseRelease(abandoned_lease);
    try client.finishLeaseRelease(abandoned_lease, false, true);
    _ = client.removeSessionLease(abandoned_lease);
    try std.testing.expect(client.sessionCleanupRequired("s1"));

    const acquisition = try Acquisition.begin(gpa, &client, "s1", .exclusive, null);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-2\",\"ok\":true,\"result\":{\"command\":\"detach\",\"sessionId\":\"s1\"}}");
    try std.testing.expect(!client.sessionCleanupRequired("s1"));
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-3\",\"ok\":true,\"result\":{\"command\":\"attach\",\"session\":" ++ attached_session ++ "}}");
    const handle = acquisition.takeHandle().?;
    try acquisition.destroy();
    _ = try handle.beginDispose(null);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-4\",\"ok\":true,\"result\":{\"command\":\"detach\",\"sessionId\":\"s1\"}}");
    try handle.destroy();
}

test "failed session acquisition owns a durable error and releases its lease" {
    const gpa = std.testing.allocator;
    var transport: MemoryTransport = .{ .gpa = gpa };
    defer transport.deinit();
    var client = try client_mod.Client.init(gpa, .{});
    defer client.deinit();
    try client.connect(transport.transport());
    try feedJson(&client, "{\"type\":\"hello\",\"version\":1,\"connectionId\":\"c1\",\"snapshot\":" ++ empty_server ++ "}");
    const acquisition = try Acquisition.begin(gpa, &client, "missing", .exclusive, null);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-1\",\"ok\":false,\"error\":{\"code\":\"not_found\",\"message\":\"session missing\"}}");
    try std.testing.expectEqual(AcquisitionStatus.failed, acquisition.status());
    try std.testing.expectEqualStrings("session missing", acquisition.failure().?.message);
    try std.testing.expectError(lease_mod.Error.UnknownLease, client.beginLeaseRelease(acquisition.lease_id));
    try acquisition.destroy();
}

pub const CreationOptions = struct {
    cwd: ?[]const u8 = null,
    name: ?[]const u8 = null,
    model: ?msg.ModelRef = null,
    thinking_level: ?msg.ThinkingLevel = null,
};

pub const CreationStatus = AcquisitionStatus;
pub const CreationCallback = struct {
    context: ?*anyopaque = null,
    callback: *const fn (?*anyopaque, *Creation) anyerror!void,
};

const CreationPhase = enum { create, cleanup, complete };

/// Event-driven equivalent of `PiClient.createSession`. A successful create
/// atomically becomes an exclusive high-level handle. If local lease adoption
/// fails after the server created and attached the session, a compensating
/// detach is issued before the failed operation is reported complete.
pub const Creation = struct {
    gpa: std.mem.Allocator,
    client: *client_mod.Client,
    completion: ?CreationCallback,
    status_value: CreationStatus = .pending,
    phase: CreationPhase = .create,
    request_pending: bool = false,
    session_id: ?[]u8 = null,
    lease_id: ?lease_mod.LeaseId = null,
    handle: ?*SessionHandle = null,
    failure_value: ?AcquisitionFailure = null,

    pub fn begin(
        gpa: std.mem.Allocator,
        client: *client_mod.Client,
        options: CreationOptions,
        completion: ?CreationCallback,
    ) !*Creation {
        const self = try gpa.create(Creation);
        self.* = .{ .gpa = gpa, .client = client, .completion = completion };
        self.queue(.{ .create = .{
            .cwd = options.cwd,
            .name = options.name,
            .model = options.model,
            .thinking_level = options.thinking_level,
        } });
        return self;
    }

    pub fn status(self: *const Creation) CreationStatus {
        return self.status_value;
    }

    pub fn failure(self: *const Creation) ?*const AcquisitionFailure {
        if (self.failure_value) |*value| return value;
        return null;
    }

    pub fn id(self: *const Creation) ?[]const u8 {
        return self.session_id;
    }

    pub fn takeHandle(self: *Creation) ?*SessionHandle {
        const value = self.handle;
        self.handle = null;
        return value;
    }

    pub fn canDestroy(self: *const Creation) bool {
        return self.status_value != .pending and !self.request_pending and self.handle == null;
    }

    pub fn destroy(self: *Creation) !void {
        if (!self.canDestroy()) return Error.NotReadyToDestroy;
        if (self.failure_value) |*value| value.deinit(self.gpa);
        if (self.session_id) |value| self.gpa.free(value);
        if (self.lease_id) |value| _ = self.client.removeSessionLease(value);
        const gpa = self.gpa;
        self.* = undefined;
        gpa.destroy(self);
    }

    fn queue(self: *Creation, command: msg.Command) void {
        self.request_pending = true;
        _ = self.client.request(command, .{ .context = self, .callback = onResponse }) catch |err| {
            if (self.status_value == .pending and self.request_pending) {
                self.request_pending = false;
                self.failLocal(err);
            }
        };
    }

    fn onResponse(raw: ?*anyopaque, _: u64, outcome: client_mod.RequestOutcome) anyerror!void {
        const self: *Creation = @ptrCast(@alignCast(raw.?));
        if (self.status_value != .pending) return;
        self.request_pending = false;
        switch (outcome) {
            .failure => |request_failure| {
                if (self.phase == .cleanup) {
                    self.finishFailed();
                } else {
                    self.failRequest(request_failure);
                }
            },
            .success => |result| switch (self.phase) {
                .create => self.acceptCreate(result.create),
                .cleanup => self.finishFailed(),
                .complete => {},
            },
        }
    }

    fn acceptCreate(self: *Creation, snapshot_value: msg.SessionSnapshot) void {
        self.session_id = self.gpa.dupe(u8, snapshot_value.id) catch |err| {
            self.failLocal(err);
            return;
        };
        const lease_id = self.client.reserveSessionLease(snapshot_value.id, .exclusive) catch |err| {
            self.setFailure(.local, null, @errorName(err));
            self.phase = .cleanup;
            self.queue(.{ .detach = .{ .session_id = self.session_id.? } });
            return;
        };
        self.lease_id = lease_id;
        self.handle = SessionHandle.adopt(self.gpa, self.client, snapshot_value.id, lease_id) catch |err| {
            _ = self.client.removeSessionLease(lease_id);
            self.lease_id = null;
            self.setFailure(.local, null, @errorName(err));
            self.phase = .cleanup;
            self.queue(.{ .detach = .{ .session_id = self.session_id.? } });
            return;
        };
        self.lease_id = null; // ownership transferred to the handle
        self.phase = .complete;
        self.status_value = .succeeded;
        self.invokeCompletion();
    }

    fn failRequest(self: *Creation, request_failure: client_mod.RequestFailure) void {
        switch (request_failure) {
            .server => |server_failure| self.failStatic(.server, server_failure.code, server_failure.message),
            .client => |client_failure| switch (client_failure) {
                .disconnected => self.failStatic(.disconnected, null, "client disconnected"),
                .disposed => self.failStatic(.disposed, null, "client disposed"),
                .protocol_violation => self.failStatic(.protocol_violation, null, "protocol violation"),
                .transport_failure => self.failStatic(.transport_failure, null, "transport failure"),
            },
        }
    }

    fn failLocal(self: *Creation, err: anyerror) void {
        self.failStatic(.local, null, @errorName(err));
    }

    fn failStatic(self: *Creation, source: AcquisitionFailureSource, code: ?msg.ProtocolErrorCode, message: []const u8) void {
        self.setFailure(source, code, message);
        self.finishFailed();
    }

    fn setFailure(self: *Creation, source: AcquisitionFailureSource, code: ?msg.ProtocolErrorCode, message: []const u8) void {
        if (self.failure_value) |*old| old.deinit(self.gpa);
        const owned = self.gpa.dupe(u8, message) catch self.gpa.dupe(u8, "session creation failed") catch return;
        self.failure_value = .{ .source = source, .code = code, .message = owned };
    }

    fn finishFailed(self: *Creation) void {
        if (self.status_value != .pending) return;
        if (self.lease_id) |value| {
            _ = self.client.removeSessionLease(value);
            self.lease_id = null;
        }
        if (self.failure_value == null) self.setFailure(.local, null, "session creation failed");
        self.phase = .complete;
        self.status_value = .failed;
        self.invokeCompletion();
    }

    fn invokeCompletion(self: *Creation) void {
        if (self.completion) |handler| handler.callback(handler.context, self) catch |err| self.client.reportExternalListenerError(err);
    }
};

test "session creation returns an exclusive owned handle" {
    const gpa = std.testing.allocator;
    var transport: MemoryTransport = .{ .gpa = gpa };
    defer transport.deinit();
    var client = try client_mod.Client.init(gpa, .{});
    defer client.deinit();
    try client.connect(transport.transport());
    try feedJson(&client, "{\"type\":\"hello\",\"version\":1,\"connectionId\":\"c1\",\"snapshot\":" ++ empty_server ++ "}");
    const creation = try Creation.begin(gpa, &client, .{ .cwd = "/tmp", .name = "created" }, null);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-1\",\"ok\":true,\"result\":{\"command\":\"create\",\"session\":" ++ attached_session ++ "}}");
    try std.testing.expectEqual(CreationStatus.succeeded, creation.status());
    try std.testing.expectEqualStrings("s1", creation.id().?);
    const handle = creation.takeHandle().?;
    try creation.destroy();
    try std.testing.expect(handle.active());
    try std.testing.expectError(lease_mod.Error.SessionAlreadyLeased, client.reserveSessionLease("s1", .exclusive));
    _ = try handle.beginDispose(null);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-2\",\"ok\":true,\"result\":{\"command\":\"detach\",\"sessionId\":\"s1\"}}");
    try handle.destroy();
}

test "session creation compensates with detach when exclusive adoption conflicts" {
    const gpa = std.testing.allocator;
    var transport: MemoryTransport = .{ .gpa = gpa };
    defer transport.deinit();
    var client = try client_mod.Client.init(gpa, .{});
    defer client.deinit();
    try client.connect(transport.transport());
    try feedJson(&client, "{\"type\":\"hello\",\"version\":1,\"connectionId\":\"c1\",\"snapshot\":" ++ empty_server ++ "}");
    const existing = try client.reserveSessionLease("s1", .shared);
    const creation = try Creation.begin(gpa, &client, .{}, null);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-1\",\"ok\":true,\"result\":{\"command\":\"create\",\"session\":" ++ attached_session ++ "}}");
    try std.testing.expectEqual(CreationStatus.pending, creation.status());
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-2\",\"ok\":true,\"result\":{\"command\":\"detach\",\"sessionId\":\"s1\"}}");
    try std.testing.expectEqual(CreationStatus.failed, creation.status());
    try std.testing.expectEqualStrings("SessionAlreadyLeased", creation.failure().?.message);
    try creation.destroy();
    _ = client.removeSessionLease(existing);
}
