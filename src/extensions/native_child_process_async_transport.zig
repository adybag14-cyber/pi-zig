//! Byte-only owner-thread seam for genuine Node stream adapters. No JS values,
//! callbacks, scheduling loops, blocking writer or implicit child termination.
const std = @import("std");
const builtin = @import("builtin");
const transport = @import("native_child_process_transport.zig");
const windows = @import("native_child_process_stdin_windows.zig");
const windows_output = @import("native_child_process_output_windows.zig");
const waits = @import("native_child_process_wait_registry.zig");
const shutdown = @import("native_child_process_shutdown_windows.zig");
pub const maximum_chunk = 64 * 1024;
pub const Demand = struct { stdout: bool = true, stderr: bool = true };
pub const Endpoint = enum { stdin, stdout, stderr };
pub const Output = union(enum) { none, bytes: []const u8, eof, failure: anyerror };
pub const Resubmit = struct { stdin: bool = false, stdout: bool = false, stderr: bool = false };
pub const Step = struct {
    stdout: Output = .none, stderr: Output = .none, child_exit: ?transport.Result = null,
    // The genuine owner scheduler must queue another bounded step for these
    // channels: no pending event exists to wake read resubmission after data/0.
    resubmit: Resubmit = .{},
    retirement_deadline_ms: ?u64 = null,
};
pub const PendingOutputEvent = struct { event: std.os.windows.HANDLE, generation: u64 };
pub const WriteCompletion = struct {
    token: u64,
    acceptedBytes: usize,
    // A failed/canceled kernel operation may have delivered an unobserved
    // partial suffix. This is uncertainty, not a count of definitely lost bytes.
    unconfirmedBytes: usize = 0,
    failure: ?anyerror = null,
};
pub const EndpointCompletion = struct { endpoint: Endpoint, failure: ?anyerror = null, retirementPending: bool = false };
pub const AsyncTransport = struct {
    process: transport.Process,
    input: [maximum_chunk]u8 = undefined,
    output: [2][maximum_chunk]u8 = undefined,
    token: ?u64 = null,
    length: usize = 0,
    accepted: usize = 0,
    pending_length: usize = 0,
    write_completion: ?WriteCompletion = null,
    endpoint_completion: [3]?EndpointCompletion = .{ null, null, null },
    input_closed: bool = false,
    output_closed: [2]bool = .{ false, false },
    output_ready: [2]?usize = .{ null, null },
    output_retiring: [2]bool = .{ false, false },
    output_retirement_started: [2]?u64 = .{ null, null },
    output_close_failure: [2]?anyerror = .{ null, null },
    finish_requested: bool = false,
    close_requested: bool = false,
    close_failure: ?anyerror = null,
    retirement_started: ?u64 = null,
    retirement_deadline_seen: bool = false,
    retirement_unconfirmed: usize = 0,
    // Node close callbacks require real operation retirement while the owner is
    // live. Engine detach alone may transfer pending operations to quarantine.
    strict_endpoint_retirement: bool = false,
    output_deadline_seen: [2]bool = .{ false, false },
    windows_shutdown: ?shutdown.Ticket = null,
    windows_shutdown_submitted: bool = false,
    windows_shutdown_cancelling: bool = false,
    windows_shutdown_result: ?shutdown.Completion = null,
    windows_shutdown_fault: ?anyerror = null,
    exit_delivered: bool = false,
    disposed: bool = false,
    operation_sequences: [3]u64 = .{ 0, 0, 0 },

    pub fn init(io: std.Io, gpa: std.mem.Allocator, argv: []const []const u8, cwd: ?[]const u8, env: *const @import("native_child_process_environment.zig").Environment, options: transport.Options) !AsyncTransport {
        var native_options = options;
        if (builtin.os.tag == .windows) native_options.windows_overlapped_output = true;
        var process = try transport.Process.spawn(io, gpa, argv, cwd, env, native_options);
        errdefer process.deinit(io); // creation rollback owns this exact child
        if (builtin.os.tag != .windows) {
            if (process.child.stdout) |file| try nonblocking(file);
            if (process.child.stderr) |file| try nonblocking(file);
        }
        return .{ .process = process, .input_closed = options.stdio[0] != .pipe, .output_closed = .{ options.stdio[1] != .pipe, options.stdio[2] != .pipe } };
    }
    /// Called only by the private owner, after pre-spawn ticket reservation.
    /// Failure leaves an unassociated ticket and actual transport separately
    /// owned by Driver rollback; no running child is freed early.
    pub fn attachWindowsShutdown(self: *AsyncTransport, ticket: shutdown.Ticket) !void {
        if (builtin.os.tag != .windows or self.windows_shutdown != null) return error.NativePipeShutdownAssociationMismatch;
        const slot = self.process.input.windows_slot orelse return error.NativePipeShutdownServerEndpointRequired;
        try shutdown.associate(ticket, slot);
        self.windows_shutdown = ticket;
    }
    pub fn beginChunk(self: *AsyncTransport, bytes: []const u8, token: u64) !void {
        if (self.disposed or self.input_closed or self.finish_requested or self.close_requested) return error.NativeChildInputClosed;
        if (self.token != null or self.write_completion != null) return error.NativeChildWriteAcknowledgementRequired;
        if (bytes.len > maximum_chunk) return error.NativeChildWriteSegmentTooLarge;
        @memcpy(self.input[0..bytes.len], bytes);
        self.token = token;
        self.length = bytes.len;
        self.accepted = 0;
        self.pending_length = 0;
    }
    pub fn takeWriteCompletion(self: *AsyncTransport) ?WriteCompletion {
        const result = self.write_completion;
        self.write_completion = null;
        return result;
    }
    pub fn finishInput(self: *AsyncTransport) !void {
        if (self.disposed or self.input_closed or self.close_requested) return error.NativeChildInputClosed;
        self.finish_requested = true;
    }
    pub fn closeInput(self: *AsyncTransport) void {
        if (self.disposed or self.input_closed or self.close_requested) return;
        self.close_requested = true;
        self.close_failure = error.NativeChildInputClosed;
    }
    pub fn takeEndpointCompletion(self: *AsyncTransport) ?EndpointCompletion {
        for (&self.endpoint_completion) |*record| if (record.*) |value| { record.* = null; return value; };
        return null;
    }
    /// Caller owns scheduling and demand. Each span expires on the next step;
    /// copy it before invoking live VM push/callbacks or making another step.
    pub fn step(self: *AsyncTransport, demand: Demand) !Step {
        if (self.disposed) return error.NativeChildTransportDisposed;
        var result: Step = .{};
        try self.process.observeExit();
        if (self.process.exited and !self.exit_delivered) {
            self.exit_delivered = true;
            result.child_exit = self.process.result;
            if (!self.input_closed) { self.close_requested = true; self.close_failure = if (self.token != null) error.BrokenPipe else null; }
        }
        self.inputStep();
        if (self.windows_shutdown_fault) |failure| return failure;
        if (builtin.os.tag == .windows) {
            result.stdout = self.readWindowsOutput(.stdout, demand.stdout);
            result.stderr = self.readWindowsOutput(.stderr, demand.stderr);
            result.resubmit.stdout = self.needsOutputResubmit(0, demand.stdout);
            result.resubmit.stderr = self.needsOutputResubmit(1, demand.stderr);
            if (self.process.input.windows_slot) |slot| result.resubmit.stdin = !self.close_requested and self.token != null and !slot.pending;
            if (!self.input_closed and !self.retirement_deadline_seen) if (self.retirement_started) |started| result.retirement_deadline_ms = started +| 250;
            for (self.output_retirement_started, self.output_closed, self.output_deadline_seen) |maybe_started, closed, deadline_seen| if (!closed and !deadline_seen) if (maybe_started) |started| {
                const deadline = started +| 250;
                result.retirement_deadline_ms = if (result.retirement_deadline_ms) |prior| @min(prior, deadline) else deadline;
            };
        } else {
            if (demand.stdout and !self.output_closed[0]) result.stdout = self.readOutput(.stdout);
            if (demand.stderr and !self.output_closed[1]) result.stderr = self.readOutput(.stderr);
            result.resubmit.stdout = demand.stdout and switch (result.stdout) { .bytes => true, else => false };
            result.resubmit.stderr = demand.stderr and switch (result.stderr) { .bytes => true, else => false };
        }
        if (self.finish_requested and !self.close_requested and self.token == null and self.write_completion == null and !self.input_closed and !self.windows_shutdown_submitted) result.resubmit.stdin = true;
        // A write failure may finish its IRP before failWrite requests close.
        // Queue the FIRST retirement step even without another kernel event;
        // once started, real pending events/deadlines own further progress.
        if (self.close_requested and !self.input_closed and self.retirement_started == null) result.resubmit.stdin = true;
        return result;
    }
    fn needsOutputResubmit(self: *AsyncTransport, index: usize, demand: bool) bool {
        if (!demand or self.output_closed[index] or self.output_retiring[index] or self.output_ready[index] != null) return false;
        const slot = self.process.windows_outputs[index] orelse return false;
        return !slot.pending;
    }
    /// Borrowed process-lifetime events, armed only while an operation is pending.
    /// Scheduler must retain this owner and reject stale generation notifications;
    /// these event handles convey no authority to close endpoints or signal a child.
    pub fn pendingWindowsOutputEvents(self: *AsyncTransport) [2]?PendingOutputEvent {
        var events: [2]?PendingOutputEvent = .{ null, null };
        if (builtin.os.tag == .windows and !self.disposed) for (self.process.windows_outputs, 0..) |maybe_slot, index| if (maybe_slot) |slot| {
            if (slot.pending) events[index] = .{ .event = slot.event.?, .generation = slot.generation };
        };
        return events;
    }
    fn advanceOperation(self: *AsyncTransport, channel: usize) !void {
        if (self.operation_sequences[channel] == std.math.maxInt(u64)) return error.NativeChildOperationSequenceExhausted;
        self.operation_sequences[channel] += 1;
    }
    pub fn watchSnapshot(self: *AsyncTransport) !waits.Snapshot {
        if (builtin.os.tag != .windows) return error.RequiredNativePosixChildReadiness;
        var result: waits.Snapshot = .{ .exited = self.process.exited };
        if (self.process.input.windows_slot) |slot| if (slot.pending) { result.events[0] = .{ .handle = slot.event.?, .endpoint_generation = slot.generation, .operation_sequence = self.operation_sequences[0] }; };
        if (result.events[0] == null) if (self.windows_shutdown) |ticket| if (try shutdown.pending(ticket)) |pending| { result.events[0] = .{ .handle = pending.event, .endpoint_generation = pending.generation, .operation_sequence = self.operation_sequences[0] }; };
        for (self.process.windows_outputs, 0..) |maybe_slot, index| if (maybe_slot) |slot| if (slot.pending) { result.events[index + 1] = .{ .handle = slot.event.?, .endpoint_generation = slot.generation, .operation_sequence = self.operation_sequences[index + 1] }; };
        if (!self.input_closed and !self.retirement_deadline_seen) if (self.retirement_started) |started| result.deadline_ms = started +| 250;
        for (self.output_retirement_started, self.output_closed, self.output_deadline_seen) |maybe_started, closed, deadline_seen| if (!closed and !deadline_seen) if (maybe_started) |started| {
            const due = started +| 250;
            result.deadline_ms = if (result.deadline_ms) |prior| @min(prior, due) else due;
        };
        return result;
    }
    fn completeWrite(self: *AsyncTransport, failure: ?anyerror, unconfirmed: usize) void {
        const token = self.token orelse return;
        std.debug.assert(self.write_completion == null);
        self.write_completion = .{ .token = token, .acceptedBytes = self.accepted, .unconfirmedBytes = unconfirmed, .failure = failure };
        self.token = null;
        std.crypto.secureZero(u8, &self.input);
    }
    fn failWrite(self: *AsyncTransport, failure: anyerror) void {
        self.close_requested = true;
        self.close_failure = failure;
        // Keep the token until actual endpoint retirement, so a cancellation
        // race can still contribute observed completed bytes to its one ack.
    }
    fn inputStep(self: *AsyncTransport) void {
        if (self.input_closed) return;
        if (self.close_requested) { self.retireInput(); return; }
        if (self.token != null) {
            if (builtin.os.tag == .windows) {
                const slot = self.process.input.windows_slot orelse { self.failWrite(error.NativeChildInputClosed); return; };
                if (slot.pending) {
                    const count = slot.completion() catch |err| { self.failWrite(err); return; };
                    if (count) |written| {
                        if (written == 0 or written > self.pending_length) { self.failWrite(error.NativeStdinInvalidWriteProgress); return; }
                        self.accepted += written;
                        self.pending_length = 0;
                    } else return;
                    // One input operation per step: do not issue the suffix
                    // in the same step as completion observation.
                } else if (self.accepted < self.length) {
                    const bytes = self.input[self.accepted..self.length];
                    self.advanceOperation(0) catch |err| { self.failWrite(err); return; };
                    const count = slot.write(bytes) catch |err| { self.pending_length = if (slot.pending) bytes.len else 0; self.failWrite(err); return; };
                    if (count) |written| {
                        if (written == 0 or written > bytes.len) { self.failWrite(error.NativeStdinInvalidWriteProgress); return; }
                        self.accepted += written;
                    } else self.pending_length = bytes.len;
                }
            } else if (self.accepted < self.length) {
                const file = self.process.input.posix_file orelse { self.failWrite(error.NativeChildInputClosed); return; };
                if (!(ready(file.handle, std.posix.POLL.OUT) catch |err| { self.failWrite(err); return; })) return;
                const bytes = self.input[self.accepted..self.length];
                // Native Threaded backend's existing SIGPIPE policy must outlive
                // this owner; there is no process-global signal mutation here.
                const rc = std.posix.system.write(file.handle, bytes.ptr, bytes.len);
                switch (std.posix.errno(rc)) {
                    .SUCCESS => { const written: usize = @intCast(rc); if (written == 0 or written > bytes.len) { self.failWrite(error.NativeStdinInvalidWriteProgress); return; } self.accepted += written; },
                    .INTR, .AGAIN => return,
                    .PIPE => { self.failWrite(error.BrokenPipe); return; },
                    else => { self.failWrite(error.NativeChildInputWriteFailed); return; },
                }
            }
            if (self.accepted == self.length) self.completeWrite(null, 0);
        }
        // _final must not complete while a write acknowledgement is unconsumed.
        if (self.finish_requested and self.token == null and self.write_completion == null) {
            if (builtin.os.tag == .windows and self.windows_shutdown != null) {
                if (!self.flushInputAfterWrites()) return;
            }
            self.close_requested = true; self.retireInput();
        }
    }
    fn flushInputAfterWrites(self: *AsyncTransport) bool {
        const ticket = self.windows_shutdown orelse return true;
        if (!self.windows_shutdown_submitted) {
            const slot = self.process.input.windows_slot orelse { self.windows_shutdown_fault = error.NativePipeShutdownServerEndpointRequired; return false; };
            self.advanceOperation(0) catch |err| { self.windows_shutdown_fault = err; return false; };
            shutdown.submitAfterWrites(ticket, slot) catch |err| { self.windows_shutdown_fault = err; return false; };
            self.windows_shutdown_submitted = true;
        }
        const completion = shutdown.poll(ticket) catch |err| { self.windows_shutdown_fault = err; return false; };
        const result = completion orelse return false;
        self.windows_shutdown_result = result;
        shutdown.releaseCompletedAfterWithdraw(ticket) catch |err| { self.windows_shutdown_fault = err; return false; };
        self.windows_shutdown = null;
        switch (result.outcome) {
            .flushed => {},
            .cancelled_before_call => { if (self.close_failure == null) self.close_failure = error.NativeStdinOperationAborted; },
            .failed => |code| { if (self.close_failure == null) self.close_failure = switch (code) { 109, 232, 233 => error.BrokenPipe, 995 => error.NativeStdinOperationAborted, else => error.NativePipeShutdownFailed }; },
        }
        return true;
    }
    fn retireInput(self: *AsyncTransport) void {
        var pending_cleanup = self.process.input.retirement_pending;
        var unconfirmed = self.retirement_unconfirmed;
        if (builtin.os.tag == .windows) if (self.windows_shutdown) |ticket| {
            if (!self.windows_shutdown_cancelling) {
                self.advanceOperation(0) catch |err| { self.windows_shutdown_fault = err; return; };
                shutdown.cancel(ticket) catch |err| { self.windows_shutdown_fault = err; return; };
                self.windows_shutdown_cancelling = true;
            }
        };
        if (builtin.os.tag == .windows) {
            if (self.process.input.windows_slot) |slot| {
                if (self.retirement_started == null) { self.retirement_started = windows.monotonicMilliseconds(); slot.requestCancellation(); }
                if (slot.pending) {
                    const count = slot.completion() catch |err| failed: { if (self.close_failure == null) self.close_failure = err; break :failed null; };
                    if (count) |written| {
                        if (written <= self.pending_length) self.accepted += written else self.close_failure = error.NativeStdinInvalidWriteProgress;
                        self.pending_length = 0;
                    }
                }
                if (slot.pending) {
                    if (windows.monotonicMilliseconds() -| self.retirement_started.? < 250) return;
                    self.retirement_deadline_seen = true;
                    if (self.strict_endpoint_retirement) {
                        // No Node close acknowledgement while its actual IRP
                        // still owns storage. Native detach can quarantine it.
                        if (self.windows_shutdown) |ticket| shutdown.markQuarantined(ticket) catch {};
                        return;
                    }
                    unconfirmed = self.pending_length;
                    slot.quarantine();
                    self.process.input.windows_slot = null;
                    self.process.input.retirement_pending = true;
                    pending_cleanup = true;
                    self.close_failure = error.NativeStdinRetirementPending;
                } else {
                    unconfirmed = self.pending_length;
                    self.process.input.windows_slot = null;
                    const retired = slot.retire(); // no pending operation; no wait
                    std.debug.assert(retired);
                    if (!retired) { pending_cleanup = true; self.process.input.retirement_pending = true; self.close_failure = error.NativeStdinRetirementPending; }
                }
            }
        } else if (self.process.input.posix_file) |file| { self.process.input.posix_file = null; file.close(self.process.io); };
        self.retirement_unconfirmed = unconfirmed;
        if (builtin.os.tag == .windows) if (self.windows_shutdown) |ticket| {
            if (self.retirement_started == null) self.retirement_started = windows.monotonicMilliseconds();
            const completion = shutdown.poll(ticket) catch |err| { self.windows_shutdown_fault = err; return; };
            if (completion) |result| {
                self.windows_shutdown_result = result;
                shutdown.releaseCompletedAfterWithdraw(ticket) catch |err| { self.windows_shutdown_fault = err; return; };
                self.windows_shutdown = null;
            } else {
                if (windows.monotonicMilliseconds() -| self.retirement_started.? >= 250) {
                    self.retirement_deadline_seen = true;
                    shutdown.markQuarantined(ticket) catch {};
                }
                return;
            }
        };
        self.input_closed = true;
        const write_failure: ?anyerror = if (self.close_failure) |reason| reason else if (self.token != null) error.NativeChildInputClosed else null;
        self.completeWrite(write_failure, unconfirmed);
        self.endpoint_completion[0] = .{ .endpoint = .stdin, .failure = self.close_failure, .retirementPending = pending_cleanup };
    }
    fn readOutput(self: *AsyncTransport, stream: transport.Stream) Output {
        const index = @intFromEnum(stream);
        const file = (if (stream == .stdout) self.process.child.stdout else self.process.child.stderr) orelse return self.endOutput(stream, error.NativeChildOutputMissing);
        if (!(ready(file.handle, std.posix.POLL.IN) catch |err| return self.endOutput(stream, err))) return .none;
        const rc = std.posix.system.read(file.handle, &self.output[index], maximum_chunk);
        switch (std.posix.errno(rc)) {
            .SUCCESS => { const count: usize = @intCast(rc); if (count == 0) return self.endOutput(stream, null); return .{ .bytes = self.output[index][0..count] }; },
            .INTR, .AGAIN => return .none,
            else => return self.endOutput(stream, error.NativeChildOutputReadFailed),
        }
    }
    fn readWindowsOutput(self: *AsyncTransport, stream: transport.Stream, demand: bool) Output {
        const index = @intFromEnum(stream);
        if (self.output_closed[index]) return .none;
        if (self.output_retiring[index]) { self.retireWindowsOutput(index); return .none; }
        const slot = self.process.windows_outputs[index] orelse return self.failWindowsOutput(index, error.NativeChildOutputMissing);
        if (self.output_ready[index] == null) {
            const count: ?usize = if (slot.pending) slot.completion() catch |err| return self.windowsReadFailure(index, err)
                else if (demand) self.beginWindowsOutput(slot, index) catch |err| return self.windowsReadFailure(index, err)
                else return .none;
            if (count) |received| {
                if (received == 0) return .none; // zero-length producer write, not EOF
                self.output_ready[index] = received;
            } else return .none;
        }
        if (!demand) return .none; // one completed 64 KiB chunk remains retained
        const received = self.output_ready[index].?;
        @memcpy(self.output[index][0..received], slot.bytes(received));
        self.output_ready[index] = null;
        // No new read here. Step.resubmit queues the next bounded owner step.
        return .{ .bytes = self.output[index][0..received] };
    }
    fn beginWindowsOutput(self: *AsyncTransport, slot: *windows_output.Slot, index: usize) !?usize {
        try self.advanceOperation(index + 1);
        return slot.beginRead();
    }
    fn windowsReadFailure(self: *AsyncTransport, index: usize, failure: anyerror) Output {
        if (failure == error.EndOfStream) {
            // Slot reports this only for an actually completed broken-pipe read.
            self.output_retiring[index] = true;
            self.retireWindowsOutput(index);
            return .eof;
        }
        return self.failWindowsOutput(index, failure);
    }
    fn failWindowsOutput(self: *AsyncTransport, index: usize, failure: anyerror) Output {
        self.output_close_failure[index] = failure;
        self.output_retiring[index] = true;
        self.startOutputRetirement(index);
        if (self.process.windows_outputs[index]) |slot| { if (!slot.pending) self.retireWindowsOutput(index); }
        else self.retireWindowsOutput(index);
        return .{ .failure = failure };
    }
    fn startOutputRetirement(self: *AsyncTransport, index: usize) void {
        if (self.output_retirement_started[index] != null) return;
        self.output_retirement_started[index] = windows_output.monotonicMilliseconds();
        if (self.process.windows_outputs[index]) |slot| slot.requestCancellation();
    }
    fn retireWindowsOutput(self: *AsyncTransport, index: usize) void {
        self.startOutputRetirement(index);
        var pending_cleanup = false;
        if (self.process.windows_outputs[index]) |slot| {
            if (slot.pending) _ = slot.completion() catch null;
            if (slot.pending) {
                if (windows_output.monotonicMilliseconds() -| self.output_retirement_started[index].? < 250) return;
                self.output_deadline_seen[index] = true;
                if (self.strict_endpoint_retirement) return; // actual Node close still owns this IRP
                slot.quarantine();
                self.process.windows_outputs[index] = null;
                pending_cleanup = true;
                self.process.output_retirement_pending = true;
                self.output_close_failure[index] = error.NativeChildOutputRetirementPending;
            } else {
                self.process.windows_outputs[index] = null;
                const retired = slot.retire(); // completion observed; no wait
                std.debug.assert(retired);
                if (!retired) { pending_cleanup = true; self.process.output_retirement_pending = true; self.output_close_failure[index] = error.NativeChildOutputRetirementPending; }
            }
        }
        self.output_ready[index] = null; // destruction discards only completed data
        self.output_closed[index] = true;
        self.endpoint_completion[index + 1] = .{ .endpoint = if (index == 0) .stdout else .stderr, .failure = self.output_close_failure[index], .retirementPending = pending_cleanup };
    }
    fn endOutput(self: *AsyncTransport, stream: transport.Stream, failure: ?anyerror) Output {
        const index = @intFromEnum(stream);
        if (self.output_closed[index]) return .none;
        if (stream == .stdout) { if (self.process.child.stdout) |file| file.close(self.process.io); self.process.child.stdout = null; }
        else { if (self.process.child.stderr) |file| file.close(self.process.io); self.process.child.stderr = null; }
        self.output_closed[index] = true;
        self.endpoint_completion[index + 1] = .{ .endpoint = if (stream == .stdout) .stdout else .stderr, .failure = failure };
        return if (failure) |err| .{ .failure = err } else .eof;
    }
    pub fn destroyOutput(self: *AsyncTransport, stream: transport.Stream) void {
        const index = @intFromEnum(stream);
        if (self.disposed or self.output_closed[index] or self.output_retiring[index]) return;
        // Deliberate destruction is an endpoint acknowledgement, never a
        // confirmed producer EOF event and never authority to signal a child.
        if (builtin.os.tag == .windows) {
            self.output_retiring[index] = true;
            self.output_close_failure[index] = error.NativeChildOutputDestroyed;
            self.startOutputRetirement(index);
            if (self.process.windows_outputs[index]) |slot| { if (!slot.pending) self.retireWindowsOutput(index); }
            else self.retireWindowsOutput(index);
        } else _ = self.endOutput(stream, error.NativeChildOutputDestroyed);
    }
    pub fn signal(self: *AsyncTransport, force: bool) bool {
        if (self.disposed) return false;
        return self.process.signal(force);
    }
    pub fn disposeExited(self: *AsyncTransport) !void {
        if (self.disposed) {
            if (self.process.output_retirement_pending) return error.NativeChildOutputRetirementPending;
            if (self.process.input.retirement_pending) return error.NativeStdinRetirementPending;
            return;
        }
        if (!self.process.exited) return error.NativeChildStillRunning;
        if (self.windows_shutdown != null) return error.NativePipeShutdownCompletionRequired;
        if (!self.input_closed or !self.output_closed[0] or !self.output_closed[1] or self.token != null or self.write_completion != null) return error.NativeChildEndpointAcknowledgementRequired;
        for (self.endpoint_completion) |record| if (record != null) return error.NativeChildEndpointAcknowledgementRequired;
        self.process.deinit(self.process.io); // observed exited; no child signal
        self.disposed = true;
        if (self.process.output_retirement_pending) return error.NativeChildOutputRetirementPending;
        if (self.process.input.retirement_pending) return error.NativeStdinRetirementPending;
    }
    /// Engine shutdown only, after scheduler withdraw and wake detachment. No
    /// worker join/wait/VM callback. Returned handle transfers to native reaping.
    pub fn detachForShutdown(self: *AsyncTransport) !?std.os.windows.HANDLE {
        if (builtin.os.tag != .windows) return error.RequiredNativePosixChildReaping;
        if (self.disposed) return null;
        if (!self.process.exited) _ = self.process.signal(true);
        if (self.windows_shutdown) |ticket| {
            // Sink is already detached. Pre-reserved native references and the
            // duplicated server keep flush/cancel ownership out of this Engine.
            shutdown.detach(ticket) catch |err| { self.windows_shutdown_fault = err; };
            self.windows_shutdown = null;
        }
        if (self.process.input.windows_slot) |slot| {
            slot.requestCancellation();
            if (slot.pending) _ = slot.completion() catch null;
            self.process.input.windows_slot = null;
            if (slot.pending) { slot.quarantine(); self.process.input.retirement_pending = true; }
            else { const retired = slot.retire(); std.debug.assert(retired); }
        }
        for (&self.process.windows_outputs) |*maybe_slot| if (maybe_slot.*) |slot| {
            slot.requestCancellation();
            if (slot.pending) _ = slot.completion() catch null;
            maybe_slot.* = null;
            if (slot.pending) { slot.quarantine(); self.process.output_retirement_pending = true; }
            else { const retired = slot.retire(); std.debug.assert(retired); }
        };
        if (self.process.child.thread_handle) |handle| { std.os.windows.CloseHandle(handle); self.process.child.thread_handle = null; }
        const process_handle = self.process.child.id;
        self.process.child.id = null;
        self.input_closed = true;
        self.output_closed = .{ true, true };
        self.disposed = true;
        return process_handle;
    }
};
fn nonblocking(file: std.Io.File) !void {
    const got = std.posix.system.fcntl(file.handle, std.posix.F.GETFL, @as(usize, 0));
    if (std.posix.errno(got) != .SUCCESS) return error.NativeChildOutputNonblockingFailed;
    const flags: usize = @intCast(got);
    if (std.posix.errno(std.posix.system.fcntl(file.handle, std.posix.F.SETFL, flags | (@as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK")))) != .SUCCESS) return error.NativeChildOutputNonblockingFailed;
}
fn ready(fd: std.posix.fd_t, requested: i16) !bool {
    var descriptors = [_]std.posix.pollfd{.{ .fd = fd, .events = requested, .revents = 0 }};
    const rc = std.posix.system.poll(&descriptors, 1, 0);
    switch (std.posix.errno(rc)) { .SUCCESS => {}, .INTR => return false, else => return error.NativeChildEndpointPollFailed }
    if (rc == 0) return false;
    if (descriptors[0].revents & std.posix.POLL.NVAL != 0) return error.NativeChildEndpointInvalid;
    return descriptors[0].revents & (requested | std.posix.POLL.HUP | std.posix.POLL.ERR | std.posix.POLL.NVAL) != 0;
}
