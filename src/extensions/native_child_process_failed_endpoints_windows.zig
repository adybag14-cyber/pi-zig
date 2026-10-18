//! Actual failed-launch parent endpoints. No Process, PID, exit status, synthetic
//! fd or synthetic EOF exists here. The failed CreateProcess call has already
//! closed every child-side handle; reads/writes observe their real kernel peers.
const std = @import("std");
const input = @import("native_child_process_stdin_windows.zig");
const output = @import("native_child_process_output_windows.zig");
const native = @import("native_child_process_windows.zig");
const io = @import("native_child_process_async_transport.zig");
const waits = @import("native_child_process_wait_registry.zig");
const shutdown = @import("native_child_process_shutdown_windows.zig");
pub const Output = io.Output;
pub const Write = io.WriteCompletion;
pub const Endpoint = io.EndpointCompletion;
pub const Step = struct {
    stdout: Output = .none, stderr: Output = .none,
    resubmit: io.Resubmit = .{},
};
pub const Owner = struct {
    failure: anyerror,
    stdin: ?*input.Slot,
    outputs: [2]?*output.Slot,
    sequence: [3]u64 = .{0} ** 3,
    closed: [3]bool,
    retiring: [3]bool = .{false} ** 3,
    write_token: ?u64 = null, write_length: usize = 0,
    completion: ?Write = null,
    endpoints: [3]?Endpoint = .{null} ** 3,
    output_ready: [2]?usize = .{null} ** 2,
    // Source delivery owns this frame's spans until the next step. The real slot
    // buffer remains stable; no read is started while its completed data is held.
    published: [2]bool = .{false} ** 2,
    detached: bool = false,
    shutdown_ticket: ?shutdown.Ticket = null,
    shutdown_submitted: bool = false, shutdown_cancelling: bool = false,
    shutdown_result: ?shutdown.Completion = null,
    input_failure: ?anyerror = null,
    output_failure: [2]?anyerror = .{null} ** 2,
    finish_requested: bool = false,
    retirement_started: ?u64 = null, deadline_seen: bool = false,
    pub fn adopt(failed: native.Failed) Owner {
        return .{ .failure = failed.failure, .stdin = failed.input_slot, .outputs = failed.output_slots, .closed = .{ failed.input_slot == null, failed.output_slots[0] == null, failed.output_slots[1] == null } };
    }
    pub fn attachShutdown(self: *Owner, ticket: shutdown.Ticket) !void {
        if (self.shutdown_ticket != null) return error.NativePipeShutdownAssociationMismatch;
        try shutdown.associate(ticket, self.stdin orelse return error.NativePipeShutdownServerEndpointRequired);
        self.shutdown_ticket = ticket;
    }
    fn advance(self: *Owner, index: usize) !void {
        if (self.sequence[index] == std.math.maxInt(u64)) return error.NativeFailedLaunchOperationExhausted;
        self.sequence[index] += 1;
    }
    /// Copies through the actual Slot before return. A completed synchronous
    /// result is recorded, never delivered inline into the guest write callback.
    pub fn beginChunk(self: *Owner, bytes: []const u8, token: u64) !void {
        if (self.detached or self.closed[0] or self.retiring[0] or self.finish_requested) return error.BrokenPipe;
        if (self.write_token != null or self.completion != null) return error.NativeChildWriteAcknowledgementRequired;
        if (bytes.len > input.chunk_size) return error.NativeChildWriteSegmentTooLarge;
        try self.advance(0);
        self.write_token = token; self.write_length = bytes.len;
        if (bytes.len == 0) { self.completeWrite(0, null); return; }
        const slot = self.stdin.?;
        const count = slot.write(bytes) catch |failure| {
            // An inconsistent API result can still have a live IRP. Preserve
            // the exact token/buffer until actual completion is observed.
            if (slot.pending) return;
            self.completeWrite(0, failure); return;
        };
        if (count) |accepted| self.completeWrite(accepted, null);
    }
    fn completeWrite(self: *Owner, accepted: usize, failure: ?anyerror) void {
        const token = self.write_token orelse return;
        self.write_token = null;
        if (accepted > self.write_length) {
            self.completion = .{ .token = token, .acceptedBytes = 0, .unconfirmedBytes = self.write_length, .failure = error.NativeFailedLaunchWriteProgressInvalid };
            return;
        }
        self.completion = .{ .token = token, .acceptedBytes = accepted, .unconfirmedBytes = if (failure != null) self.write_length - accepted else 0, .failure = failure };
    }
    fn recordShutdown(self: *Owner, completion: shutdown.Completion) void {
        self.shutdown_result = completion;
        if (self.input_failure != null) return;
        self.input_failure = switch (completion.outcome) {
            .flushed => null,
            .cancelled_before_call => error.NativeStdinOperationAborted,
            .failed => |code| switch (code) { 109, 232, 233 => error.BrokenPipe, 995 => error.NativeStdinOperationAborted, else => error.NativePipeShutdownFailed },
        };
    }
    pub fn takeWriteCompletion(self: *Owner) ?Write { const value = self.completion; self.completion = null; return value; }
    pub fn takeEndpointCompletion(self: *Owner) ?Endpoint {
        for (&self.endpoints) |*entry| if (entry.*) |value| { entry.* = null; return value; };
        return null;
    }
    pub fn closeInput(self: *Owner) void { if (!self.closed[0]) { self.retiring[0] = true; if (self.stdin) |slot| slot.requestCancellation(); } }
    pub fn finishInput(self: *Owner) !void {
        if (self.detached or self.closed[0] or self.retiring[0]) return error.NativeChildInputClosed;
        if (self.shutdown_ticket == null) return error.NativePipeShutdownAssociationMismatch;
        self.finish_requested = true;
    }
    pub fn destroyOutput(self: *Owner, index: usize) !void {
        if (index >= 2) return error.NativeFailedLaunchOutputIndex;
        if (self.closed[index + 1]) return;
        self.retiring[index + 1] = true;
        if (self.outputs[index]) |slot| slot.requestCancellation();
    }
    fn retireInput(self: *Owner) !void {
        const slot = self.stdin orelse return;
        if (self.shutdown_ticket) |ticket| {
            if (!self.shutdown_cancelling) {
                try self.advance(0);
                try shutdown.cancel(ticket); self.shutdown_cancelling = true;
                self.retirement_started = input.monotonicMilliseconds();
            }
            const result = try shutdown.poll(ticket);
            if (result) |completion| {
                try shutdown.releaseCompletedAfterWithdraw(ticket);
                self.shutdown_ticket = null; self.recordShutdown(completion);
            } else {
                if (!self.deadline_seen and input.monotonicMilliseconds() -| self.retirement_started.? >= 250) { self.deadline_seen = true; try shutdown.markQuarantined(ticket); }
                return;
            }
        }
        if (slot.pending or self.write_token != null or self.completion != null) return;
        self.stdin = null;
        const retired = slot.retire(); // No pending operation: no blocking wait.
        self.closed[0] = true;
        self.endpoints[0] = .{ .endpoint = .stdin, .failure = if (retired) self.input_failure else error.NativeChildStdinRetirementPending, .retirementPending = !retired };
    }
    fn retireOutput(self: *Owner, index: usize) void {
        const slot = self.outputs[index] orelse return;
        if (slot.pending) return;
        self.outputs[index] = null; self.output_ready[index] = null;
        const retired = slot.retire();
        self.closed[index + 1] = true;
        self.endpoints[index + 1] = .{ .endpoint = if (index == 0) .stdout else .stderr, .failure = if (retired) self.output_failure[index] else error.NativeChildOutputRetirementPending, .retirementPending = !retired };
    }
    fn outputFailure(self: *Owner, index: usize, failure: anyerror) Output {
        if (failure != error.EndOfStream) self.output_failure[index] = failure;
        self.retiring[index + 1] = true;
        if (self.outputs[index]) |slot| { if (!slot.pending) self.retireOutput(index); };
        // EndOfStream comes exclusively from the actual completed broken-pipe
        // read. Closing child sides/failed launch alone never manufactures EOF.
        return if (failure == error.EndOfStream) .eof else .{ .failure = failure };
    }
    fn readOutput(self: *Owner, index: usize, demand: bool) !Output {
        const slot = self.outputs[index] orelse return .none;
        if (self.retiring[index + 1]) {
            if (slot.pending) _ = slot.completion() catch null;
            if (!slot.pending) self.retireOutput(index);
            return .none;
        }
        if (slot.pending) {
            if (slot.completion() catch |failure| return self.outputFailure(index, failure)) |count| {
                if (count != 0) self.output_ready[index] = count;
            } else return .none;
        } else if (self.output_ready[index] == null and demand) {
            try self.advance(index + 1);
            if (slot.beginRead() catch |failure| return self.outputFailure(index, failure)) |count| {
                if (count != 0) self.output_ready[index] = count;
            } else return .none;
        }
        if (!demand) return .none;
        const count = self.output_ready[index] orelse return .none;
        self.published[index] = true;
        return .{ .bytes = slot.bytes(count) };
    }
    /// Caller withdraws borrowed wait interests before every step or control.
    /// Public error dispatch/flush and actual Socket consumption are VM-owner
    /// policies; this byte owner reports neither a child exit nor a close event.
    pub fn step(self: *Owner, demand: io.Demand) !Step {
        if (self.detached) return error.NativeFailedLaunchOwnerDetached;
        for (&self.published, 0..) |*published, index| if (published.*) { published.* = false; self.output_ready[index] = null; };
        if (self.stdin) |slot| {
            if (slot.pending) {
                const count = slot.completion() catch |failure| failed: {
                    if (!slot.pending) self.completeWrite(0, failure);
                    break :failed null;
                };
                if (count) |accepted| self.completeWrite(accepted, null);
            }
            if (self.finish_requested and !self.retiring[0] and !slot.pending and self.write_token == null and self.completion == null) {
                const ticket = self.shutdown_ticket orelse return error.NativePipeShutdownAssociationMismatch;
                if (!self.shutdown_submitted) { try self.advance(0); try shutdown.submitAfterWrites(ticket, slot); self.shutdown_submitted = true; }
                if (try shutdown.poll(ticket)) |completion| {
                    try shutdown.releaseCompletedAfterWithdraw(ticket);
                    self.recordShutdown(completion); self.shutdown_ticket = null;
                    self.retiring[0] = true;
                }
            }
            if (self.retiring[0]) try self.retireInput();
        }
        var result: Step = .{ .stdout = try self.readOutput(0, demand.stdout), .stderr = try self.readOutput(1, demand.stderr) };
        result.resubmit.stdin = !self.closed[0] and !self.stdin.?.pending and self.completion == null and ((self.finish_requested and !self.retiring[0] and !self.shutdown_submitted) or (self.retiring[0] and !self.shutdown_cancelling and self.shutdown_ticket != null));
        result.resubmit.stdout = demand.stdout and !self.closed[1] and !self.outputs[0].?.pending and (self.output_ready[0] == null or self.published[0]);
        result.resubmit.stderr = demand.stderr and !self.closed[2] and !self.outputs[1].?.pending and (self.output_ready[1] == null or self.published[1]);
        return result;
    }
    pub fn watchSnapshot(self: *Owner) !waits.Snapshot {
        var snapshot: waits.Snapshot = .{ .exited = true }; // No process watch.
        if (self.stdin) |slot| if (slot.pending) { snapshot.events[0] = .{ .handle = slot.event.?, .endpoint_generation = slot.generation, .operation_sequence = self.sequence[0] }; };
        // The pool also requests this lease's owner checkpoint on completion.
        // Do not replace a pending write event with the shutdown event.
        if (snapshot.events[0] == null) if (self.shutdown_ticket) |ticket| if (try shutdown.pending(ticket)) |pending| {
            snapshot.events[0] = .{ .handle = pending.event, .endpoint_generation = pending.generation, .operation_sequence = self.sequence[0] };
        };
        if (!self.deadline_seen) if (self.retirement_started) |started| { snapshot.deadline_ms = started +| 250; };
        for (self.outputs, 0..) |maybe_slot, index| if (maybe_slot) |slot| if (slot.pending) { snapshot.events[index + 1] = .{ .handle = slot.event.?, .endpoint_generation = slot.generation, .operation_sequence = self.sequence[index + 1] }; };
        return snapshot;
    }
    pub fn settled(self: *const Owner) bool {
        if (self.write_token != null or self.completion != null) return false;
        for (self.closed) |closed| if (!closed) return false;
        for (self.endpoints) |endpoint| if (endpoint != null) return false;
        return true;
    }
    /// Only Engine teardown uses quarantine; attached Source close waits for
    /// actual cancellation completion. No worker/IRP retains JS or this object.
    pub fn detachAfterWithdraw(self: *Owner) void {
        if (self.detached) return;
        self.detached = true;
        if (self.shutdown_ticket) |ticket| { self.shutdown_ticket = null; shutdown.detach(ticket) catch {}; }
        if (self.stdin) |slot| { self.stdin = null; if (slot.pending) { slot.requestCancellation(); slot.quarantine(); } else { _ = slot.retire(); } }
        for (&self.outputs) |*maybe_slot| if (maybe_slot.*) |slot| { maybe_slot.* = null; if (slot.pending) { slot.requestCancellation(); slot.quarantine(); } else { _ = slot.retire(); } };
    }
};
