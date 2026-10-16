//! No received bytes are executable code or unbounded JSON. All frames are fixed.
const std = @import("std");
const w = @import("win32.zig");
pub const magic: u64 = 0x50495a49474a4f42;
pub const Kind = enum(u32) {
    ready = 1,
    node_intent = 2,
    node_created_suspended = 3,
    node_resume_ack = 4,
    node_resumed = 5,
    node_exit_recorded = 6,
    node_references_released = 7,
    postseals_complete = 8,
    abort = 9,
    worker_terminal = 10,
    worker_containment_ack = 11,
};
pub const Frame = extern struct {
    marker: u64,
    schema: u32,
    kind: u32,
    sequence: u64,
    nonce: [32]u8,
    pid: u32,
    parent_pid: u32,
    creation_filetime_utc: u64,
    worker_local_node_handle: u64,
    code: u32,
    flags: u32,
    input_sha256: [32]u8,
};
pub const Direction = enum { from_worker, from_supervisor };
pub const Receiver = struct {
    nonce: [32]u8,
    next_sequence: u64 = 1,
    direction: Direction,
    worker_pid: u32,
    node_pid: ?u32 = null,
    node_creation: ?u64 = null,
    state: enum { initial, ready, intended, created, acknowledged, running, exited, released, sealed, terminal, aborted } = .initial,
    pub fn accept(self: *Receiver, frame: *const Frame) !Kind {
        if (frame.marker != magic or frame.schema != 1 or frame.flags != 0 or frame.sequence != self.next_sequence or
            !std.crypto.timing_safe.eql([32]u8, frame.nonce, self.nonce)) return error.InvalidProtocolFrame;
        const kind = std.enums.fromInt(Kind, frame.kind) orelse return error.UnknownProtocolKind;
        if (kind == .abort) {
            if (self.state == .terminal or self.state == .aborted) return error.DuplicateProtocolTerminal;
            self.state = .aborted;
            self.next_sequence += 1;
            return kind;
        }
        if (self.direction == .from_supervisor) {
            // The worker only accepts the one suspension-bound resume ACK.
            if (kind != .node_resume_ack or self.state != .created or self.node_pid == null or
                frame.pid != self.node_pid.? or frame.parent_pid != self.worker_pid or
                frame.creation_filetime_utc != self.node_creation.?)
                return error.UnexpectedSupervisorAcknowledgement;
            self.state = .acknowledged;
        } else switch (kind) {
            .ready => {
                if (self.state != .initial or frame.pid != self.worker_pid) return error.InvalidWorkerReady;
                self.state = .ready;
            },
            .node_intent => {
                if (self.state != .ready) return error.DuplicateNodeIntent;
                self.state = .intended;
            },
            .node_created_suspended => {
                if (self.state != .intended or frame.pid == 0 or frame.parent_pid != self.worker_pid or
                    frame.worker_local_node_handle == 0 or frame.creation_filetime_utc == 0)
                    return error.InvalidSuspendedNodeRecord;
                self.node_pid = frame.pid;
                self.node_creation = frame.creation_filetime_utc;
                self.state = .created;
            },
            .node_resumed => {
                if (self.state != .acknowledged or self.node_pid == null or frame.pid != self.node_pid.?)
                    return error.UnacknowledgedNodeResume;
                self.state = .running;
            },
            .node_exit_recorded => {
                if (self.state != .running or frame.pid != self.node_pid.?) return error.InvalidNodeExitRecord;
                self.state = .exited;
            },
            .node_references_released => {
                if (self.state != .exited or frame.pid != self.node_pid.?) return error.InvalidNodeReferenceRelease;
                self.state = .released;
            },
            .postseals_complete => {
                if (self.state != .released or frame.pid != self.worker_pid) return error.InvalidPostsealRecord;
                self.state = .sealed;
            },
            .worker_terminal => {
                if (self.state != .sealed or frame.pid != self.worker_pid) return error.InvalidWorkerTerminal;
                self.state = .terminal;
            },
            .node_resume_ack, .worker_containment_ack, .abort => return error.InvalidWorkerMessage,
        }
        self.next_sequence += 1;
        return kind;
    }
    /// Called locally only after ACK was flushed/sent; not a received worker bit.
    pub fn acknowledgedNode(self: *Receiver) !void {
        if (self.direction != .from_worker or self.state != .created) return error.InvalidAckTransition;
        self.state = .acknowledged;
    }
    /// Worker's receive-side expectation is bound to its own suspended launch.
    pub fn expectNodeAcknowledgement(self: *Receiver, pid: u32, creation: u64) !void {
        if (self.direction != .from_supervisor or self.state != .initial or pid == 0 or creation == 0)
            return error.InvalidLocalNodeExpectation;
        self.node_pid = pid;
        self.node_creation = creation;
        self.state = .created;
    }
};
pub const WorkerBootstrap = struct {
    frame: Frame,
    authenticated: bool = false,
    /// Accept only over the inherited private channel, with nonce and intent
    /// SHA from this attempt. Supervisor sends this before worker resume only
    /// after creation-time job membership and full worker identity are verified.
    pub fn authenticate(self: *WorkerBootstrap, expected_nonce: [32]u8, expected_intent: [32]u8,
        worker_pid: u32, supervisor_pid: u32, creation: u64, inherited_client: w.H) !void
    {
        var actual_server: u32 = 0;
        if (w.GetNamedPipeServerProcessId(inherited_client, &actual_server) == 0 or actual_server != supervisor_pid)
            return error.WorkerBootstrapServerMismatch;
        const frame = &self.frame;
        if (self.authenticated or frame.marker != magic or frame.schema != 1 or
            frame.kind != @intFromEnum(Kind.worker_containment_ack) or frame.sequence != 0 or
            frame.flags != 0 or frame.code != 0 or frame.worker_local_node_handle != 0 or
            frame.pid != worker_pid or frame.parent_pid != supervisor_pid or frame.creation_filetime_utc != creation or
            !std.crypto.timing_safe.eql([32]u8, frame.nonce, expected_nonce) or
            !std.crypto.timing_safe.eql([32]u8, frame.input_sha256, expected_intent))
            return error.InvalidWorkerContainmentBootstrap;
        self.authenticated = true;
    }
};
comptime { if (@sizeOf(Frame) != 120) @compileError("Protocol frame layout changed"); }
