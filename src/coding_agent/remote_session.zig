//! High-level remote coding-agent session lifecycle.
//!
//! This is the native event-driven counterpart of the original TypeScript
//! `RemoteSession`. It layers exclusive lease ownership, transcript projection,
//! replacement rollback, prompt/steer selection, abort preemption, model and
//! thinking updates, reconnect, listener isolation and asynchronous disposal on
//! top of the protocol client. Operations return immediately after their frame
//! is queued; callers continue pumping the client's transport until lifecycle
//! listeners report completion.
const std = @import("std");
const protocol = @import("../protocol/root.zig");
const msg = protocol.messages;
const client_pkg = @import("../client/root.zig");
const client_mod = client_pkg.client;
const lease_mod = client_pkg.lease;
const connection_mod = client_pkg.connection;
const transcript_mod = @import("remote_transcript.zig");

pub const Lifecycle = enum { unbound, ready, busy, disposed };
pub const Operation = enum { open, create, submit, abort, set_model, set_thinking, reconnect };
pub const FailureSource = enum { local, server, disconnected, disposed, protocol_violation, transport_failure };

pub const Failure = struct {
    source: FailureSource,
    code: ?msg.ProtocolErrorCode = null,
    message: []const u8,
    owned: bool = false,

    fn deinit(self: *Failure, gpa: std.mem.Allocator) void {
        if (self.owned) gpa.free(self.message);
        self.* = undefined;
    }
};

pub const Listener = struct {
    context: ?*anyopaque = null,
    callback: *const fn (?*anyopaque, *const RemoteSession) anyerror!void,
};

pub const ErrorListener = struct {
    context: ?*anyopaque = null,
    callback: *const fn (?*anyopaque, anyerror) void,
};

pub const Options = struct {
    transcript: transcript_mod.Options = .{},
    on_listener_error: ?ErrorListener = null,
};

pub const StartResult = union(enum) {
    no_op,
    queued: u64,
    failed,
};

pub const ReconnectResult = enum { started, failed };

pub const Error = error{
    Disposed,
    Busy,
    Unbound,
    SessionNotIdle,
    SessionCannotAcceptInput,
    TooManyPendingRequests,
    NotReadyToDestroy,
    MissingSnapshot,
    SessionMismatch,
};

const PendingKind = enum {
    attach_candidate,
    create_candidate,
    detach_previous,
    cleanup_candidate,
    cleanup_unleased_candidate,
    prompt,
    steer,
    abort,
    set_model,
    set_thinking,
    dispose_current,
};

const max_pending_requests = 16;

const PendingSlot = struct {
    owner: ?*RemoteSession = null,
    kind: PendingKind = .prompt,
    active: bool = false,
};

const ListenerEntry = struct {
    id: u64,
    listener: Listener,
};

pub const RemoteSession = struct {
    gpa: std.mem.Allocator,
    client: *client_mod.Client,
    options: Options,

    lifecycle_state: Lifecycle = .unbound,
    active_operation: ?Operation = null,
    disposed: bool = false,

    session_id: ?[]u8 = null,
    lease_id: ?lease_mod.LeaseId = null,
    transcript: ?transcript_mod.State = null,
    snapshot_listener_id: ?client_pkg.state.ListenerId = null,
    event_listener_id: ?client_pkg.state.ListenerId = null,
    connection_listener_id: u64 = 0,

    candidate_id: ?[]u8 = null,
    candidate_lease_id: ?lease_mod.LeaseId = null,
    candidate_attached: bool = false,
    candidate_operation: ?Operation = null,

    reconnect_target: ?[]u8 = null,
    reconnect_connecting: bool = false,

    last_failure_value: ?Failure = null,
    pending_slots: [max_pending_requests]PendingSlot = [_]PendingSlot{.{}} ** max_pending_requests,
    pending_count: usize = 0,

    listeners: std.ArrayList(ListenerEntry) = .empty,
    next_listener_id: u64 = 1,
    notifying: bool = false,

    pub fn create(gpa: std.mem.Allocator, client: *client_mod.Client, options: Options) !*RemoteSession {
        const self = try gpa.create(RemoteSession);
        errdefer gpa.destroy(self);
        self.* = .{
            .gpa = gpa,
            .client = client,
            .options = options,
        };
        self.connection_listener_id = try client.onConnectionStateChange(.{
            .context = self,
            .callback = onConnectionState,
        });
        return self;
    }

    pub fn destroy(self: *RemoteSession) !void {
        if (!self.canDestroy()) return Error.NotReadyToDestroy;
        if (self.connection_listener_id != 0) _ = self.client.removeConnectionStateListener(self.connection_listener_id);
        self.connection_listener_id = 0;
        self.clearBindingMemory();
        self.discardCandidateLocal();
        if (self.reconnect_target) |value| self.gpa.free(value);
        self.reconnect_target = null;
        self.clearFailure();
        self.listeners.deinit(self.gpa);
        const gpa = self.gpa;
        self.* = undefined;
        gpa.destroy(self);
    }

    pub fn canDestroy(self: *const RemoteSession) bool {
        return self.disposed and self.pending_count == 0 and self.lease_id == null and
            self.candidate_lease_id == null and self.candidate_id == null and
            self.candidate_operation == null and self.reconnect_target == null;
    }

    pub fn lifecycle(self: *const RemoteSession) Lifecycle {
        return self.lifecycle_state;
    }

    pub fn operation(self: *const RemoteSession) ?Operation {
        return self.active_operation;
    }

    pub fn connectionState(self: *const RemoteSession) connection_mod.ConnectionState {
        return self.client.connectionState();
    }

    pub fn isDisposed(self: *const RemoteSession) bool {
        return self.disposed;
    }

    pub fn id(self: *const RemoteSession) ?[]const u8 {
        return self.session_id;
    }

    pub fn snapshot(self: *const RemoteSession) ?*const msg.SessionSnapshot {
        if (self.transcript) |*state| return &state.snapshot;
        return null;
    }

    pub fn phase(self: *const RemoteSession) ?msg.SessionPhase {
        return if (self.snapshot()) |value| value.phase else null;
    }

    pub fn lastFailure(self: *const RemoteSession) ?*const Failure {
        if (self.last_failure_value) |*value| return value;
        return null;
    }

    pub fn visibleTranscriptAlloc(self: *const RemoteSession, allocator: std.mem.Allocator) ![]msg.TranscriptItem {
        if (self.transcript) |*state| return state.selectAlloc(allocator);
        return allocator.alloc(msg.TranscriptItem, 0);
    }

    pub fn models(self: *const RemoteSession) []const msg.ModelMetadata {
        return if (self.client.snapshot()) |value| value.models else &.{};
    }

    pub fn sessions(self: *const RemoteSession) []const msg.SessionMetadata {
        return if (self.client.snapshot()) |value| value.sessions else &.{};
    }

    pub fn subscribe(self: *RemoteSession, listener: Listener) !u64 {
        if (self.disposed) return Error.Disposed;
        const listener_id = self.next_listener_id;
        self.next_listener_id +%= 1;
        if (self.next_listener_id == 0) self.next_listener_id = 1;
        try self.listeners.append(self.gpa, .{ .id = listener_id, .listener = listener });
        self.callListener(listener);
        return listener_id;
    }

    pub fn unsubscribe(self: *RemoteSession, id_value: u64) bool {
        for (self.listeners.items, 0..) |entry, index| {
            if (entry.id == id_value) {
                _ = self.listeners.orderedRemove(index);
                return true;
            }
        }
        return false;
    }

    pub fn beginOpen(self: *RemoteSession, session_id_value: []const u8) !StartResult {
        try self.assertAvailableForReplacement(.open, session_id_value);
        if (self.session_id) |current| {
            if (std.mem.eql(u8, current, session_id_value)) return .no_op;
        }
        self.clearFailure();
        self.beginBusy(.open);
        return self.startCandidateOpen(session_id_value, .open);
    }

    pub fn beginCreate(
        self: *RemoteSession,
        cwd: ?[]const u8,
        name: ?[]const u8,
        model: ?msg.ModelRef,
        thinking_level: ?msg.ThinkingLevel,
    ) !StartResult {
        try self.assertAvailableForReplacement(.create, null);
        self.clearFailure();
        self.beginBusy(.create);
        self.candidate_operation = .create;
        return self.queueCommand(.create_candidate, .{ .create = .{
            .cwd = cwd,
            .name = name,
            .model = model,
            .thinking_level = thinking_level,
        } });
    }

    pub fn beginSubmit(self: *RemoteSession, text: []const u8) !StartResult {
        try self.assertReady();
        const normalized = std.mem.trim(u8, text, " \t\r\n");
        if (normalized.len == 0) return .no_op;
        const snapshot_value = self.snapshot() orelse return Error.Unbound;
        const kind: PendingKind = switch (snapshot_value.phase) {
            .idle => .prompt,
            .turn => .steer,
            else => return Error.SessionCannotAcceptInput,
        };
        self.clearFailure();
        self.beginBusy(.submit);
        const lease_id_value = self.lease_id orelse return Error.Unbound;
        const command: msg.Command = if (kind == .prompt)
            .{ .prompt = .{ .session_id = snapshot_value.id, .text = normalized } }
        else
            .{ .steer = .{ .session_id = snapshot_value.id, .text = normalized } };
        return self.queueLeaseCommand(lease_id_value, kind, command);
    }

    pub fn beginAbort(self: *RemoteSession) !StartResult {
        if (self.disposed) return Error.Disposed;
        const preempting_submit = self.lifecycle_state == .busy and self.active_operation == .submit;
        if (self.lifecycle_state == .busy and !preempting_submit) return Error.Busy;
        const snapshot_value = self.snapshot() orelse return Error.Unbound;
        if (snapshot_value.phase == .idle and !preempting_submit) return .no_op;
        const lease_id_value = self.lease_id orelse return Error.Unbound;
        self.clearFailure();
        self.beginBusy(.abort);
        return self.queueLeaseCommand(lease_id_value, .abort, .{ .abort = .{ .session_id = snapshot_value.id } });
    }

    pub fn beginSetModel(self: *RemoteSession, model: msg.ModelRef) !StartResult {
        try self.assertIdleReady();
        const snapshot_value = self.snapshot().?;
        const lease_id_value = self.lease_id.?;
        self.clearFailure();
        self.beginBusy(.set_model);
        return self.queueLeaseCommand(lease_id_value, .set_model, .{ .set_model = .{
            .session_id = snapshot_value.id,
            .model = model,
        } });
    }

    pub fn beginSetThinking(self: *RemoteSession, thinking_level: msg.ThinkingLevel) !StartResult {
        try self.assertIdleReady();
        const snapshot_value = self.snapshot().?;
        const lease_id_value = self.lease_id.?;
        self.clearFailure();
        self.beginBusy(.set_thinking);
        return self.queueLeaseCommand(lease_id_value, .set_thinking, .{ .set_thinking = .{
            .session_id = snapshot_value.id,
            .thinking_level = thinking_level,
        } });
    }

    /// Recreates the underlying connection and re-acquires the current session.
    /// The caller owns `transport` and must pump it until the hello and attach
    /// responses arrive. A disconnect during the new handshake fails reconnect.
    pub fn beginReconnect(self: *RemoteSession, transport: client_mod.ByteTransport) !ReconnectResult {
        try self.assertReady();
        const current_id = self.session_id orelse return Error.Unbound;
        self.clearFailure();
        if (self.reconnect_target) |old| self.gpa.free(old);
        self.reconnect_target = try self.gpa.dupe(u8, current_id);
        self.beginBusy(.reconnect);
        self.reconnect_connecting = false;
        self.client.disconnect();
        self.reconnect_connecting = true;
        self.client.reconnect(transport) catch |err| {
            self.reconnect_connecting = false;
            self.setLocalFailure(err);
            self.finishReconnectFailure();
            return .failed;
        };
        return .started;
    }

    /// Marks the session disposed immediately, then performs any final detach
    /// through the ordinary request pump. `destroy` becomes legal only after all
    /// pending callbacks and detach cleanup have completed.
    pub fn beginDispose(self: *RemoteSession) StartResult {
        if (self.disposed) return .no_op;
        self.disposed = true;
        self.lifecycle_state = .disposed;
        self.active_operation = null;
        self.notify();
        self.listeners.clearRetainingCapacity();
        self.unsubscribeBinding();
        if (self.transcript) |*state| state.deinit();
        self.transcript = null;
        if (self.reconnect_target) |target| self.gpa.free(target);
        self.reconnect_target = null;
        self.reconnect_connecting = false;

        if (self.lease_id) |lease_id_value| {
            const action = self.client.beginLeaseRelease(lease_id_value) catch {
                _ = self.client.removeSessionLease(lease_id_value);
                self.lease_id = null;
                self.freeCurrentId();
                return .failed;
            };
            switch (action) {
                .none, .released_locally => {
                    _ = self.client.removeSessionLease(lease_id_value);
                    self.lease_id = null;
                    self.freeCurrentId();
                },
                .detach_required => {
                    const id_value = self.session_id orelse {
                        self.client.finishLeaseRelease(lease_id_value, false, true) catch {};
                        _ = self.client.removeSessionLease(lease_id_value);
                        self.lease_id = null;
                        return .failed;
                    };
                    return self.queueCommand(.dispose_current, .{ .detach = .{ .session_id = id_value } });
                },
            }
        }
        self.freeCurrentId();
        if (self.candidate_attached) self.cleanupCandidate() else if (self.candidate_operation == null) self.discardCandidateLocal();
        return .no_op;
    }

    fn assertReady(self: *const RemoteSession) !void {
        if (self.disposed) return Error.Disposed;
        if (self.lifecycle_state == .busy) return Error.Busy;
        if (self.lifecycle_state != .ready or self.session_id == null or self.lease_id == null) return Error.Unbound;
    }

    fn assertIdleReady(self: *const RemoteSession) !void {
        try self.assertReady();
        if (self.snapshot().?.phase != .idle) return Error.SessionNotIdle;
    }

    fn assertAvailableForReplacement(self: *const RemoteSession, _: Operation, target: ?[]const u8) !void {
        if (self.disposed) return Error.Disposed;
        if (self.lifecycle_state == .busy) return Error.Busy;
        if (self.session_id) |current| {
            if (target) |value| if (std.mem.eql(u8, current, value)) return;
            if (self.snapshot()) |snapshot_value| if (snapshot_value.phase != .idle) return Error.SessionNotIdle;
        }
    }

    fn startCandidateOpen(self: *RemoteSession, session_id_value: []const u8, operation_value: Operation) StartResult {
        self.discardCandidateLocal();
        self.candidate_id = self.gpa.dupe(u8, session_id_value) catch |err| {
            self.setLocalFailure(err);
            self.candidate_operation = null;
            self.settleLifecycle();
            self.notify();
            return .failed;
        };
        self.candidate_lease_id = self.client.reserveSessionLease(session_id_value, .exclusive) catch |err| {
            self.setLocalFailure(err);
            self.discardCandidateLocal();
            self.candidate_operation = null;
            if (operation_value == .reconnect) self.finishReconnectFailure() else {
                self.settleLifecycle();
                self.notify();
            }
            return .failed;
        };
        self.candidate_attached = false;
        self.candidate_operation = operation_value;
        return self.queueCommand(.attach_candidate, .{ .attach = .{ .session_id = self.candidate_id.? } });
    }

    fn queueLeaseCommand(self: *RemoteSession, lease_id_value: lease_mod.LeaseId, kind: PendingKind, command: msg.Command) StartResult {
        const slot = self.reservePendingSlot(kind) catch |err| {
            self.setLocalFailure(err);
            self.handlePendingFailure(kind);
            return .failed;
        };
        const token = self.client.requestForLease(lease_id_value, command, .{
            .context = slot,
            .callback = onRequestComplete,
        }) catch |err| {
            if (slot.active) {
                self.releasePendingSlot(slot);
                self.setLocalFailure(err);
                self.handlePendingFailure(kind);
            }
            return .failed;
        };
        return .{ .queued = token };
    }

    fn queueCommand(self: *RemoteSession, kind: PendingKind, command: msg.Command) StartResult {
        const slot = self.reservePendingSlot(kind) catch |err| {
            self.setLocalFailure(err);
            self.handlePendingFailure(kind);
            return .failed;
        };
        const token = self.client.request(command, .{
            .context = slot,
            .callback = onRequestComplete,
        }) catch |err| {
            if (slot.active) {
                self.releasePendingSlot(slot);
                self.setLocalFailure(err);
                self.handlePendingFailure(kind);
            }
            return .failed;
        };
        return .{ .queued = token };
    }

    fn reservePendingSlot(self: *RemoteSession, kind: PendingKind) !*PendingSlot {
        for (&self.pending_slots) |*slot| {
            if (slot.active) continue;
            slot.* = .{ .owner = self, .kind = kind, .active = true };
            self.pending_count += 1;
            return slot;
        }
        return Error.TooManyPendingRequests;
    }

    fn releasePendingSlot(self: *RemoteSession, slot: *PendingSlot) void {
        if (!slot.active) return;
        slot.active = false;
        slot.owner = null;
        self.pending_count -|= 1;
    }

    fn onRequestComplete(raw: ?*anyopaque, _: u64, outcome: client_mod.RequestOutcome) anyerror!void {
        const slot: *PendingSlot = @ptrCast(@alignCast(raw.?));
        const self = slot.owner orelse return;
        const kind = slot.kind;
        self.releasePendingSlot(slot);
        self.handleRequestOutcome(kind, outcome) catch |err| {
            self.setLocalFailure(err);
            self.handleInternalFailure(kind);
        };
    }

    fn handleRequestOutcome(self: *RemoteSession, kind: PendingKind, outcome: client_mod.RequestOutcome) !void {
        switch (outcome) {
            .failure => |failure| {
                self.setRequestFailure(failure);
                self.handlePendingFailure(kind);
            },
            .success => |result| try self.handlePendingSuccess(kind, result),
        }
    }

    fn handlePendingSuccess(self: *RemoteSession, kind: PendingKind, result: msg.CommandResult) !void {
        switch (kind) {
            .attach_candidate => {
                const snapshot_value = result.attach;
                const expected = self.candidate_id orelse return Error.SessionMismatch;
                if (!std.mem.eql(u8, expected, snapshot_value.id)) return Error.SessionMismatch;
                self.candidate_attached = true;
                if (self.disposed) {
                    self.cleanupCandidate();
                    return;
                }
                self.acceptCandidate();
            },
            .create_candidate => {
                const snapshot_value = result.create;
                self.candidate_id = try self.gpa.dupe(u8, snapshot_value.id);
                self.candidate_lease_id = self.client.reserveSessionLease(snapshot_value.id, .exclusive) catch |err| {
                    self.setLocalFailure(err);
                    self.candidate_attached = true;
                    self.cleanupCandidate();
                    return;
                };
                self.candidate_attached = true;
                if (self.disposed) {
                    self.cleanupCandidate();
                    return;
                }
                self.acceptCandidate();
            },
            .detach_previous => {
                if (self.lease_id) |lease_id_value| {
                    try self.client.finishLeaseRelease(lease_id_value, true, false);
                    _ = self.client.removeSessionLease(lease_id_value);
                    self.lease_id = null;
                }
                self.commitCandidate() catch |err| {
                    self.setLocalFailure(err);
                    self.clearBindingMemory();
                    self.cleanupCandidate();
                    return;
                };
            },
            .cleanup_candidate => {
                if (self.candidate_lease_id) |lease_id_value| {
                    try self.client.finishLeaseRelease(lease_id_value, true, true);
                    _ = self.client.removeSessionLease(lease_id_value);
                    self.candidate_lease_id = null;
                }
                self.finishCandidateCleanup();
            },
            .cleanup_unleased_candidate => self.finishCandidateCleanup(),
            .dispose_current => {
                if (self.lease_id) |lease_id_value| {
                    try self.client.finishLeaseRelease(lease_id_value, true, true);
                    _ = self.client.removeSessionLease(lease_id_value);
                    self.lease_id = null;
                }
                self.freeCurrentId();
            },
            .prompt, .steer, .abort, .set_model, .set_thinking => self.finishDirectOperation(kind),
        }
    }

    fn handlePendingFailure(self: *RemoteSession, kind: PendingKind) void {
        switch (kind) {
            .attach_candidate => {
                self.discardCandidateLocal();
                self.finishReplacementFailure();
            },
            .create_candidate => self.finishReplacementFailure(),
            .detach_previous => {
                if (self.lease_id) |lease_id_value| self.client.finishLeaseRelease(lease_id_value, false, false) catch {};
                self.cleanupCandidate();
            },
            .cleanup_candidate => {
                if (self.candidate_lease_id) |lease_id_value| {
                    self.client.finishLeaseRelease(lease_id_value, false, true) catch {};
                    _ = self.client.removeSessionLease(lease_id_value);
                    self.candidate_lease_id = null;
                }
                self.finishCandidateCleanup();
            },
            .cleanup_unleased_candidate => self.finishCandidateCleanup(),
            .dispose_current => {
                if (self.lease_id) |lease_id_value| {
                    self.client.finishLeaseRelease(lease_id_value, false, true) catch {};
                    _ = self.client.removeSessionLease(lease_id_value);
                    self.lease_id = null;
                }
                self.freeCurrentId();
            },
            .prompt, .steer, .abort, .set_model, .set_thinking => self.finishDirectOperation(kind),
        }
    }

    fn handleInternalFailure(self: *RemoteSession, kind: PendingKind) void {
        switch (kind) {
            .attach_candidate, .create_candidate, .detach_previous => self.cleanupCandidate(),
            .cleanup_candidate, .cleanup_unleased_candidate => self.finishCandidateCleanup(),
            .dispose_current => {
                if (self.lease_id) |lease_id_value| {
                    _ = self.client.removeSessionLease(lease_id_value);
                    self.lease_id = null;
                }
                self.freeCurrentId();
            },
            .prompt, .steer, .abort, .set_model, .set_thinking => self.finishDirectOperation(kind),
        }
    }

    fn acceptCandidate(self: *RemoteSession) void {
        if (self.lease_id == null) {
            self.commitCandidate() catch |err| {
                self.setLocalFailure(err);
                self.cleanupCandidate();
            };
            return;
        }
        const old_lease = self.lease_id.?;
        const action = self.client.beginLeaseRelease(old_lease) catch |err| {
            self.setLocalFailure(err);
            self.cleanupCandidate();
            return;
        };
        switch (action) {
            .none, .released_locally => {
                _ = self.client.removeSessionLease(old_lease);
                self.lease_id = null;
                self.commitCandidate() catch |err| {
                    self.setLocalFailure(err);
                    self.clearBindingMemory();
                    self.cleanupCandidate();
                };
            },
            .detach_required => {
                const old_id = self.session_id orelse {
                    self.client.finishLeaseRelease(old_lease, false, false) catch {};
                    self.setLocalFailure(Error.Unbound);
                    self.cleanupCandidate();
                    return;
                };
                _ = self.queueCommand(.detach_previous, .{ .detach = .{ .session_id = old_id } });
            },
        }
    }

    fn commitCandidate(self: *RemoteSession) !void {
        const id_value = self.candidate_id orelse return Error.MissingSnapshot;
        const lease_id_value = self.candidate_lease_id orelse return Error.MissingSnapshot;
        const snapshot_value = self.client.sessionSnapshot(id_value) orelse return Error.MissingSnapshot;
        if (!snapshot_value.attached) return Error.MissingSnapshot;

        var new_transcript = try transcript_mod.State.init(self.gpa, snapshot_value.*, self.options.transcript);
        errdefer new_transcript.deinit();
        const new_snapshot_listener = try self.client.subscribeSession(id_value, .{
            .context = self,
            .callback = onSessionSnapshot,
        });
        errdefer _ = self.client.unsubscribe(new_snapshot_listener);
        const new_event_listener = try self.client.onSessionEvent(id_value, .{
            .context = self,
            .callback = onSessionEvent,
        });
        errdefer _ = self.client.unsubscribe(new_event_listener);

        self.clearBindingMemory();
        self.session_id = id_value;
        self.lease_id = lease_id_value;
        self.transcript = new_transcript;
        self.snapshot_listener_id = new_snapshot_listener;
        self.event_listener_id = new_event_listener;
        self.candidate_id = null;
        self.candidate_lease_id = null;
        self.candidate_attached = false;
        const completed_operation = self.candidate_operation;
        self.candidate_operation = null;
        if (completed_operation == .reconnect) {
            if (self.reconnect_target) |target| self.gpa.free(target);
            self.reconnect_target = null;
            self.reconnect_connecting = false;
        }
        self.settleLifecycle();
        self.notify();
    }

    fn cleanupCandidate(self: *RemoteSession) void {
        if (self.candidate_id == null) {
            self.finishCandidateCleanup();
            return;
        }
        if (!self.candidate_attached) {
            self.discardCandidateLocal();
            self.finishReplacementFailure();
            return;
        }
        if (self.candidate_lease_id) |lease_id_value| {
            const action = self.client.beginLeaseRelease(lease_id_value) catch {
                _ = self.client.removeSessionLease(lease_id_value);
                self.candidate_lease_id = null;
                self.finishCandidateCleanup();
                return;
            };
            switch (action) {
                .none, .released_locally => {
                    _ = self.client.removeSessionLease(lease_id_value);
                    self.candidate_lease_id = null;
                    self.finishCandidateCleanup();
                },
                .detach_required => _ = self.queueCommand(.cleanup_candidate, .{ .detach = .{ .session_id = self.candidate_id.? } }),
            }
        } else {
            _ = self.queueCommand(.cleanup_unleased_candidate, .{ .detach = .{ .session_id = self.candidate_id.? } });
        }
    }

    fn finishCandidateCleanup(self: *RemoteSession) void {
        self.discardCandidateLocal();
        self.finishReplacementFailure();
    }

    fn finishReplacementFailure(self: *RemoteSession) void {
        const operation_value = self.candidate_operation;
        self.candidate_operation = null;
        if (operation_value == .reconnect) {
            if (self.reconnect_target) |target| self.gpa.free(target);
            self.reconnect_target = null;
            self.reconnect_connecting = false;
        }
        self.settleLifecycle();
        self.notify();
    }

    fn finishReconnectFailure(self: *RemoteSession) void {
        if (self.reconnect_target) |target| self.gpa.free(target);
        self.reconnect_target = null;
        self.reconnect_connecting = false;
        self.candidate_operation = null;
        self.discardCandidateLocal();
        self.settleLifecycle();
        self.notify();
    }

    fn finishDirectOperation(self: *RemoteSession, _: PendingKind) void {
        self.settleLifecycle();
        self.notify();
    }

    fn beginBusy(self: *RemoteSession, operation_value: Operation) void {
        self.lifecycle_state = .busy;
        self.active_operation = operation_value;
        self.notify();
    }

    fn settleLifecycle(self: *RemoteSession) void {
        if (self.disposed) {
            self.lifecycle_state = .disposed;
            self.active_operation = null;
            return;
        }
        if (self.candidate_operation) |operation_value| {
            self.lifecycle_state = .busy;
            self.active_operation = operation_value;
            return;
        }
        if (self.reconnect_target != null) {
            self.lifecycle_state = .busy;
            self.active_operation = .reconnect;
            return;
        }
        if (self.hasPending(.abort)) {
            self.lifecycle_state = .busy;
            self.active_operation = .abort;
            return;
        }
        if (self.hasPending(.prompt) or self.hasPending(.steer)) {
            self.lifecycle_state = .busy;
            self.active_operation = .submit;
            return;
        }
        if (self.hasPending(.set_model)) {
            self.lifecycle_state = .busy;
            self.active_operation = .set_model;
            return;
        }
        if (self.hasPending(.set_thinking)) {
            self.lifecycle_state = .busy;
            self.active_operation = .set_thinking;
            return;
        }
        self.active_operation = null;
        self.lifecycle_state = if (self.session_id != null and self.lease_id != null) .ready else .unbound;
    }

    fn hasPending(self: *const RemoteSession, kind: PendingKind) bool {
        for (self.pending_slots) |slot| if (slot.active and slot.kind == kind) return true;
        return false;
    }

    fn onSessionSnapshot(raw: ?*anyopaque, snapshot_value: *const msg.SessionSnapshot) anyerror!void {
        const self: *RemoteSession = @ptrCast(@alignCast(raw.?));
        if (self.disposed) return;
        if (self.transcript) |*state| {
            _ = try state.applySnapshot(snapshot_value.*);
            self.notify();
        }
    }

    fn onSessionEvent(raw: ?*anyopaque, event: *const msg.ServerEvent) anyerror!void {
        const self: *RemoteSession = @ptrCast(@alignCast(raw.?));
        switch (event.*) {
            .session_progress => |progress| {
                if (self.disposed) return;
                if (self.transcript) |*state| {
                    try state.applyProgress(progress.progress);
                    self.notify();
                }
            },
            .session_removed => |removed| {
                if (self.session_id) |current| {
                    if (!std.mem.eql(u8, current, removed.session_id)) return;
                    if (self.lease_id) |lease_id_value| _ = self.client.removeSessionLease(lease_id_value);
                    self.lease_id = null;
                    self.clearBindingMemory();
                    self.settleLifecycle();
                    self.notify();
                }
            },
            else => {},
        }
    }

    fn onConnectionState(raw: ?*anyopaque, state: connection_mod.ConnectionState) anyerror!void {
        const self: *RemoteSession = @ptrCast(@alignCast(raw.?));
        switch (state) {
            .connected => {
                if (self.disposed) return;
                if (self.reconnect_target) |target| {
                    self.reconnect_connecting = false;
                    _ = self.startCandidateOpen(target, .reconnect);
                }
            },
            .connecting => {},
            .disconnected => {
                if (self.lease_id) |lease_id_value| _ = self.client.removeSessionLease(lease_id_value);
                self.lease_id = null;
                self.clearBindingMemory();
                if (self.candidate_lease_id) |lease_id_value| _ = self.client.removeSessionLease(lease_id_value);
                self.candidate_lease_id = null;
                self.candidate_attached = false;
                if (self.candidate_id) |id_value| self.gpa.free(id_value);
                self.candidate_id = null;
                self.candidate_operation = null;

                if (self.reconnect_target != null and self.reconnect_connecting) {
                    self.setStaticFailure(.disconnected, "reconnect transport disconnected");
                    self.finishReconnectFailure();
                } else {
                    self.settleLifecycle();
                    self.notify();
                }
            },
        }
    }

    fn clearBindingMemory(self: *RemoteSession) void {
        self.unsubscribeBinding();
        if (self.transcript) |*state| state.deinit();
        self.transcript = null;
        self.freeCurrentId();
    }

    fn unsubscribeBinding(self: *RemoteSession) void {
        if (self.snapshot_listener_id) |id_value| _ = self.client.unsubscribe(id_value);
        if (self.event_listener_id) |id_value| _ = self.client.unsubscribe(id_value);
        self.snapshot_listener_id = null;
        self.event_listener_id = null;
    }

    fn freeCurrentId(self: *RemoteSession) void {
        if (self.session_id) |id_value| self.gpa.free(id_value);
        self.session_id = null;
    }

    fn discardCandidateLocal(self: *RemoteSession) void {
        if (self.candidate_lease_id) |lease_id_value| _ = self.client.removeSessionLease(lease_id_value);
        self.candidate_lease_id = null;
        if (self.candidate_id) |id_value| self.gpa.free(id_value);
        self.candidate_id = null;
        self.candidate_attached = false;
    }

    fn setRequestFailure(self: *RemoteSession, failure: client_mod.RequestFailure) void {
        switch (failure) {
            .server => |server_failure| self.setServerFailure(server_failure),
            .client => |client_failure| switch (client_failure) {
                .disconnected => self.setStaticFailure(.disconnected, "client disconnected"),
                .disposed => self.setStaticFailure(.disposed, "client disposed"),
                .protocol_violation => self.setStaticFailure(.protocol_violation, "protocol violation"),
                .transport_failure => self.setStaticFailure(.transport_failure, "transport failure"),
            },
        }
    }

    fn setServerFailure(self: *RemoteSession, failure: msg.ProtocolError) void {
        self.clearFailure();
        const copied = self.gpa.dupe(u8, failure.message) catch {
            self.last_failure_value = .{ .source = .server, .code = failure.code, .message = "server request failed" };
            return;
        };
        self.last_failure_value = .{ .source = .server, .code = failure.code, .message = copied, .owned = true };
    }

    fn setLocalFailure(self: *RemoteSession, err: anyerror) void {
        const source: FailureSource = if (err == client_mod.Error.Disconnected)
            .disconnected
        else if (err == client_mod.Error.Disposed)
            .disposed
        else
            .local;
        self.setStaticFailure(source, @errorName(err));
    }

    fn setStaticFailure(self: *RemoteSession, source: FailureSource, message: []const u8) void {
        self.clearFailure();
        self.last_failure_value = .{ .source = source, .message = message };
    }

    fn clearFailure(self: *RemoteSession) void {
        if (self.last_failure_value) |*failure| failure.deinit(self.gpa);
        self.last_failure_value = null;
    }

    fn notify(self: *RemoteSession) void {
        if (self.notifying) return;
        self.notifying = true;
        defer self.notifying = false;
        const snapshot_listeners = self.gpa.dupe(ListenerEntry, self.listeners.items) catch {
            for (self.listeners.items) |entry| self.callListener(entry.listener);
            return;
        };
        defer self.gpa.free(snapshot_listeners);
        for (snapshot_listeners) |entry| {
            var still_registered = false;
            for (self.listeners.items) |current| {
                if (current.id == entry.id) {
                    still_registered = true;
                    break;
                }
            }
            if (still_registered) self.callListener(entry.listener);
        }
    }

    fn callListener(self: *RemoteSession, listener: Listener) void {
        listener.callback(listener.context, self) catch |err| {
            if (self.options.on_listener_error) |handler| handler.callback(handler.context, err);
        };
    }
};

const empty_server =
    "{\"serverId\":\"server-1\",\"protocolVersion\":1,\"revision\":0,\"sessions\":[],\"models\":[]}";
const session_one =
    "{\"id\":\"s1\",\"cwd\":\"/tmp\",\"createdAt\":1,\"updatedAt\":1,\"phase\":\"idle\",\"model\":{\"provider\":\"test\",\"id\":\"model\"},\"thinkingLevel\":\"off\",\"attached\":true,\"locked\":false,\"revision\":1,\"transcript\":[{\"id\":\"a1\",\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"saved\"}],\"model\":{\"provider\":\"test\",\"id\":\"model\"},\"timestamp\":1,\"status\":\"complete\",\"stopReason\":\"stop\"}],\"queuedSteer\":[],\"queuedSteerCount\":0}";
const session_one_turn =
    "{\"id\":\"s1\",\"cwd\":\"/tmp\",\"createdAt\":1,\"updatedAt\":2,\"phase\":\"turn\",\"model\":{\"provider\":\"test\",\"id\":\"model\"},\"thinkingLevel\":\"off\",\"attached\":true,\"locked\":true,\"revision\":2,\"transcript\":[{\"id\":\"a1\",\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"saved\"}],\"model\":{\"provider\":\"test\",\"id\":\"model\"},\"timestamp\":1,\"status\":\"streaming\"}],\"queuedSteer\":[],\"queuedSteerCount\":0}";
const session_two =
    "{\"id\":\"s2\",\"cwd\":\"/tmp\",\"createdAt\":2,\"updatedAt\":2,\"phase\":\"idle\",\"model\":{\"provider\":\"test\",\"id\":\"model2\"},\"thinkingLevel\":\"low\",\"attached\":true,\"locked\":false,\"revision\":1,\"transcript\":[],\"queuedSteer\":[],\"queuedSteerCount\":0}";

const MemoryTransport = struct {
    gpa: std.mem.Allocator,
    sent: std.ArrayList([]u8) = .empty,
    closes: usize = 0,

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
    fn close(raw: ?*anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.closes += 1;
    }
};

fn feedJson(client: *client_mod.Client, json: []const u8) !void {
    const frame = try protocol.codec.encodeJsonFrame(std.testing.allocator, json);
    defer std.testing.allocator.free(frame);
    try client.feed(frame);
}

fn connectMemoryClient(client: *client_mod.Client, transport: *MemoryTransport) !void {
    try client.connect(transport.transport());
    try feedJson(client, "{\"type\":\"hello\",\"version\":1,\"connectionId\":\"c1\",\"snapshot\":" ++ empty_server ++ "}");
}

test "remote session opens projects progress and selects prompt versus steer" {
    const gpa = std.testing.allocator;
    var transport: MemoryTransport = .{ .gpa = gpa };
    defer transport.deinit();
    var client = try client_mod.Client.init(gpa, .{});
    defer client.deinit();
    try connectMemoryClient(&client, &transport);
    const remote = try RemoteSession.create(gpa, &client, .{});
    const opening = try remote.beginOpen("s1");
    try std.testing.expect(opening == .queued);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-1\",\"ok\":true,\"result\":{\"command\":\"attach\",\"session\":" ++ session_one ++ "}}");
    try std.testing.expectEqual(Lifecycle.ready, remote.lifecycle());
    try std.testing.expectEqualStrings("s1", remote.id().?);

    try feedJson(&client, "{\"type\":\"event\",\"event\":{\"type\":\"session_progress\",\"sessionId\":\"s1\",\"progress\":{\"type\":\"assistant_delta\",\"messageId\":\"a1\",\"contentIndex\":0,\"kind\":\"text\",\"delta\":\" plus\"}}}");
    const visible = try remote.visibleTranscriptAlloc(gpa);
    defer gpa.free(visible);
    try std.testing.expectEqualStrings("saved plus", visible[0].assistant.content[0].text.text);

    const prompt = try remote.beginSubmit(" hello ");
    try std.testing.expect(prompt == .queued);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-2\",\"ok\":true,\"result\":{\"command\":\"prompt\",\"session\":" ++ session_one_turn ++ "}}");
    try std.testing.expectEqual(Lifecycle.ready, remote.lifecycle());
    const steer = try remote.beginSubmit("adjust");
    try std.testing.expect(steer == .queued);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-3\",\"ok\":true,\"result\":{\"command\":\"steer\",\"session\":" ++ session_one_turn ++ "}}");
    try std.testing.expectEqual(Lifecycle.ready, remote.lifecycle());

    const disposing = remote.beginDispose();
    try std.testing.expect(disposing == .queued);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-4\",\"ok\":true,\"result\":{\"command\":\"detach\",\"sessionId\":\"s1\"}}");
    try std.testing.expect(remote.canDestroy());
    try remote.destroy();
}

test "remote session replacement detaches previous only after candidate attaches" {
    const gpa = std.testing.allocator;
    var transport: MemoryTransport = .{ .gpa = gpa };
    defer transport.deinit();
    var client = try client_mod.Client.init(gpa, .{});
    defer client.deinit();
    try connectMemoryClient(&client, &transport);
    const remote = try RemoteSession.create(gpa, &client, .{});

    _ = try remote.beginOpen("s1");
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-1\",\"ok\":true,\"result\":{\"command\":\"attach\",\"session\":" ++ session_one ++ "}}");
    _ = try remote.beginOpen("s2");
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-2\",\"ok\":true,\"result\":{\"command\":\"attach\",\"session\":" ++ session_two ++ "}}");
    try std.testing.expectEqualStrings("s1", remote.id().?);
    try std.testing.expectEqual(Operation.open, remote.operation().?);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-3\",\"ok\":true,\"result\":{\"command\":\"detach\",\"sessionId\":\"s1\"}}");
    try std.testing.expectEqualStrings("s2", remote.id().?);
    try std.testing.expectEqual(Lifecycle.ready, remote.lifecycle());

    _ = remote.beginDispose();
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-4\",\"ok\":true,\"result\":{\"command\":\"detach\",\"sessionId\":\"s2\"}}");
    try remote.destroy();
}

test "remote session abort preempts submit lifecycle and disposal survives detach failure" {
    const gpa = std.testing.allocator;
    var transport: MemoryTransport = .{ .gpa = gpa };
    defer transport.deinit();
    var client = try client_mod.Client.init(gpa, .{});
    defer client.deinit();
    try connectMemoryClient(&client, &transport);
    const remote = try RemoteSession.create(gpa, &client, .{});
    _ = try remote.beginOpen("s1");
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-1\",\"ok\":true,\"result\":{\"command\":\"attach\",\"session\":" ++ session_one_turn ++ "}}");
    _ = try remote.beginSubmit("steer");
    _ = try remote.beginAbort();
    try std.testing.expectEqual(Operation.abort, remote.operation().?);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-3\",\"ok\":true,\"result\":{\"command\":\"abort\",\"session\":" ++ session_one ++ "}}");
    try std.testing.expectEqual(Operation.submit, remote.operation().?);
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-2\",\"ok\":true,\"result\":{\"command\":\"steer\",\"session\":" ++ session_one ++ "}}");
    try std.testing.expectEqual(Lifecycle.ready, remote.lifecycle());

    _ = remote.beginDispose();
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-4\",\"ok\":false,\"error\":{\"code\":\"internal_error\",\"message\":\"detach failed\"}}");
    try std.testing.expect(remote.canDestroy());
    try std.testing.expectEqualStrings("detach failed", remote.lastFailure().?.message);
    try remote.destroy();
}

const ListenerProbe = struct {
    calls: usize = 0,
    errors: usize = 0,

    fn listener(raw: ?*anyopaque, _: *const RemoteSession) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.calls += 1;
        if (self.calls == 2) return error.DeliberateListenerFailure;
    }

    fn onError(raw: ?*anyopaque, _: anyerror) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.errors += 1;
    }
};

test "remote session reconnects through a replacement transport and reacquires ownership" {
    const gpa = std.testing.allocator;
    var first_transport: MemoryTransport = .{ .gpa = gpa };
    defer first_transport.deinit();
    var second_transport: MemoryTransport = .{ .gpa = gpa };
    defer second_transport.deinit();
    var client = try client_mod.Client.init(gpa, .{});
    defer client.deinit();
    try connectMemoryClient(&client, &first_transport);
    const remote = try RemoteSession.create(gpa, &client, .{});

    _ = try remote.beginOpen("s1");
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-1\",\"ok\":true,\"result\":{\"command\":\"attach\",\"session\":" ++ session_one ++ "}}");
    try std.testing.expectEqual(connection_mod.ConnectionState.connected, remote.connectionState());

    try std.testing.expectEqual(ReconnectResult.started, try remote.beginReconnect(second_transport.transport()));
    try std.testing.expectEqual(Operation.reconnect, remote.operation().?);
    try std.testing.expectEqual(connection_mod.ConnectionState.connecting, remote.connectionState());
    try std.testing.expect(remote.id() == null);
    try feedJson(&client, "{\"type\":\"hello\",\"version\":1,\"connectionId\":\"c2\",\"snapshot\":" ++ empty_server ++ "}");
    try std.testing.expectEqual(connection_mod.ConnectionState.connected, remote.connectionState());
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-2\",\"ok\":true,\"result\":{\"command\":\"attach\",\"session\":" ++ session_one ++ "}}");
    try std.testing.expectEqualStrings("s1", remote.id().?);
    try std.testing.expectEqual(Lifecycle.ready, remote.lifecycle());

    _ = remote.beginDispose();
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-3\",\"ok\":true,\"result\":{\"command\":\"detach\",\"sessionId\":\"s1\"}}");
    try remote.destroy();
}

test "remote session reconnect failure becomes unbound and listener failures are isolated" {
    const gpa = std.testing.allocator;
    var first_transport: MemoryTransport = .{ .gpa = gpa };
    defer first_transport.deinit();
    var second_transport: MemoryTransport = .{ .gpa = gpa };
    defer second_transport.deinit();
    var client = try client_mod.Client.init(gpa, .{});
    defer client.deinit();
    try connectMemoryClient(&client, &first_transport);
    var probe: ListenerProbe = .{};
    const remote = try RemoteSession.create(gpa, &client, .{
        .on_listener_error = .{ .context = &probe, .callback = ListenerProbe.onError },
    });
    _ = try remote.subscribe(.{ .context = &probe, .callback = ListenerProbe.listener });

    _ = try remote.beginOpen("s1");
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-1\",\"ok\":true,\"result\":{\"command\":\"attach\",\"session\":" ++ session_one ++ "}}");
    try std.testing.expectEqual(@as(usize, 1), probe.errors);

    try std.testing.expectEqual(ReconnectResult.started, try remote.beginReconnect(second_transport.transport()));
    try client.transportEnded();
    try std.testing.expectEqual(Lifecycle.unbound, remote.lifecycle());
    try std.testing.expect(remote.id() == null);
    try std.testing.expectEqual(FailureSource.disconnected, remote.lastFailure().?.source);

    _ = remote.beginDispose();
    try std.testing.expect(remote.canDestroy());
    try remote.destroy();
}

test "remote session removal invalidates the binding without corrupting listeners" {
    const gpa = std.testing.allocator;
    var transport: MemoryTransport = .{ .gpa = gpa };
    defer transport.deinit();
    var client = try client_mod.Client.init(gpa, .{});
    defer client.deinit();
    try connectMemoryClient(&client, &transport);
    const remote = try RemoteSession.create(gpa, &client, .{});
    _ = try remote.beginOpen("s1");
    try feedJson(&client, "{\"type\":\"response\",\"id\":\"request-1\",\"ok\":true,\"result\":{\"command\":\"attach\",\"session\":" ++ session_one ++ "}}");
    try feedJson(&client, "{\"type\":\"event\",\"event\":{\"type\":\"session_removed\",\"sessionId\":\"s1\"}}");
    try std.testing.expectEqual(Lifecycle.unbound, remote.lifecycle());
    try std.testing.expect(remote.id() == null);
    try std.testing.expect(remote.snapshot() == null);
    try std.testing.expectError(Error.Unbound, remote.beginSubmit("hello"));
    _ = remote.beginDispose();
    try remote.destroy();
}
