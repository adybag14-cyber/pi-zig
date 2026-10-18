//! Nonblocking Linux owner transport over actual reviewed pidfd/socket ownership.
//! Caller withdraws its epoll lease before every mutation/step/retirement. No VM,
//! worker join, polling timer, PID fallback, inferred exec success or fake EOF.
const std = @import("std");
const owned = @import("native_child_process_owned_linux.zig");
const spawn = @import("native_child_process_spawn_linux.zig");
const epoll = @import("native_child_process_epoll_linux.zig");
const shared = @import("native_child_process_async_transport.zig");
pub const Demand = shared.Demand;
pub const Output = shared.Output;
pub const WriteCompletion = shared.WriteCompletion;
pub const EndpointCompletion = shared.EndpointCompletion;
pub const ShutdownCompletion = struct { failure: ?anyerror = null };
pub const Step = struct {
    launch: ?spawn.Status = null,
    stdout: Output = .none, stderr: Output = .none,
    child_exit: ?@import("native_child_process_transport.zig").Result = null,
    // Actual shutdown request completion, including native failure/cancellation.
    // It is not proof of successful SHUT_WR, endpoint close or producer EOF.
    input_finished: ?ShutdownCompletion = null,
    resubmit: shared.Resubmit = .{},
};
pub const Transport = struct {
    process: owned.Owned,
    input: [shared.maximum_chunk]u8 = undefined,
    token: ?u64 = null, length: usize = 0, accepted: usize = 0,
    write_completion: ?WriteCompletion = null,
    endpoint_completion: [3]?EndpointCompletion = .{null} ** 3,
    retirement_reported: [3]bool = .{false} ** 3,
    input_closed: bool, output_closed: [2]bool,
    close_input: bool = false, close_outputs: [2]bool = .{false} ** 2,
    finish_requested: bool = false, finish_delivered: bool = false,
    shutdown_failure: ?anyerror = null,
    launch_delivered: bool = false, exit_delivered: bool = false,
    disposed: bool = false,
    /// Moves a caller's sole native ownership. No fallible work remains here.
    pub fn take(actual: *owned.Owned) Transport {
        const result: Transport = .{ .process = actual.*, .input_closed = actual.endpoints[0] == null, .output_closed = .{actual.endpoints[1] == null, actual.endpoints[2] == null} };
        actual.detached = true; actual.ticket.charged = false;
        actual.ticket.watch.pidfd = null; actual.ticket.exec_status_fd = null;
        actual.endpoints = .{null} ** 3;
        return result;
    }
    pub fn beginChunk(self: *Transport, data: []const u8, token: u64) !void {
        if (self.disposed or self.input_closed or self.close_input or self.finish_requested) return error.NativeChildInputClosed;
        if (self.token != null or self.write_completion != null) return error.NativeChildWriteAcknowledgementRequired;
        if (data.len > self.input.len) return error.NativeChildWriteSegmentTooLarge;
        @memcpy(self.input[0..data.len], data); self.length = data.len; self.accepted = 0; self.token = token;
    }
    pub fn takeWriteCompletion(self: *Transport) ?WriteCompletion { const result = self.write_completion; self.write_completion = null; return result; }
    pub fn takeEndpointCompletion(self: *Transport) ?EndpointCompletion {
        for (&self.endpoint_completion) |*item| if (item.*) |value| { item.* = null; return value; };
        return null;
    }
    pub fn finishInput(self: *Transport) !void {
        if (self.disposed or self.input_closed or self.close_input) return error.NativeChildInputClosed;
        if (self.token != null or self.write_completion != null) return error.NativeChildWriteAcknowledgementRequired;
        self.finish_requested = true;
    }
    pub fn closeInput(self: *Transport) void { if (!self.disposed and !self.input_closed) self.close_input = true; }
    pub fn destroyOutput(self: *Transport, index: usize) !void { if (index >= 2) return error.NativeLinuxChildOutputIndex; if (!self.disposed and !self.output_closed[index]) self.close_outputs[index] = true; }
    fn completeWrite(self: *Transport, failure: ?anyerror) void {
        const token = self.token orelse return;
        self.write_completion = .{ .token = token, .acceptedBytes = self.accepted, .failure = failure };
        self.token = null;
    }
    fn closeEndpoint(self: *Transport, index: usize) void {
        if (self.retirement_reported[index]) return;
        self.retirement_reported[index] = true;
        // closeEndpointAfterWithdraw disowns the integer BEFORE close and never
        // retries it. A reported native failure remains terminal metadata.
        var failure: ?anyerror = null;
        self.process.closeEndpointAfterWithdraw(index) catch |err| { failure = err; };
        const absent = self.process.endpoints[index] == null;
        if (index == 0) self.input_closed = absent else self.output_closed[index - 1] = absent;
        self.endpoint_completion[index] = .{ .endpoint = @enumFromInt(index), .failure = failure, .retirementPending = !absent };
    }
    fn outputStep(self: *Transport, index: usize, demand: bool) !Output {
        if (self.output_closed[index]) return .none;
        if (self.close_outputs[index]) { self.closeEndpoint(index + 1); return .none; }
        if (!demand) return .none;
        return switch (try self.process.readOnce(index)) {
            .pending => .none, .bytes => |data| .{ .bytes = data },
            .eof => .eof, .failure => |failure| .{ .failure = failure },
        };
    }
    pub fn stepAfterWithdraw(self: *Transport, demand: Demand) !Step {
        if (self.disposed) return error.NativeLinuxChildOwnerDetached;
        var result: Step = .{};
        if (!self.launch_delivered) {
            const status = try self.process.takeLaunchAfterWithdraw();
            switch (status) { .pending => {}, else => { self.launch_delivered = true; result.launch = status; } }
        }
        if (self.close_input and !self.input_closed) {
            self.completeWrite(error.NativeChildInputClosed);
            self.closeEndpoint(0);
            if (self.finish_requested and !self.finish_delivered) {
                self.finish_delivered = true; self.shutdown_failure = error.NativeChildInputClosed;
                result.input_finished = .{ .failure = self.shutdown_failure };
            }
        } else if (self.token != null) {
            if (self.accepted == self.length) self.completeWrite(null) else switch (try self.process.writeOnce(self.input[self.accepted..self.length])) {
                .pending => {},
                .accepted => |count| {
                    if (count > self.length - self.accepted) return error.NativeLinuxChildWriteProgressInvalid;
                    self.accepted += count;
                    if (self.accepted == self.length) self.completeWrite(null) else if (count != 0) result.resubmit.stdin = true;
                },
                .failure => |failure| { self.completeWrite(failure); self.close_input = true; result.resubmit.stdin = true; },
            };
        }
        if (self.finish_requested and !self.finish_delivered and !self.input_closed and !self.close_input and self.token == null and self.write_completion == null) {
            const completion: ?owned.Shutdown = self.process.finishInputAfterWrites() catch |failure| failed: {
                self.shutdown_failure = failure; self.finish_delivered = true;
                result.input_finished = .{ .failure = failure }; break :failed null;
            };
            if (completion) |status| switch (status) {
                .pending => {},
                .completed => { self.finish_delivered = true; result.input_finished = .{}; },
            };
        }
        result.stdout = try self.outputStep(0, demand.stdout);
        result.stderr = try self.outputStep(1, demand.stderr);
        switch (result.stdout) { .bytes => result.resubmit.stdout = demand.stdout, else => {} }
        switch (result.stderr) { .bytes => result.resubmit.stderr = demand.stderr, else => {} }
        if (!self.exit_delivered) if (try self.process.observeExitAfterWithdraw()) |exit| { self.exit_delivered = true; result.child_exit = exit; };
        return result;
    }
    pub fn snapshot(self: *Transport, demand: Demand, deadline: ?u64) !epoll.Snapshot {
        return self.process.snapshot((self.token != null or (self.finish_requested and !self.finish_delivered)) and !self.close_input, demand.stdout and !self.close_outputs[0], demand.stderr and !self.close_outputs[1], deadline);
    }
    pub fn canDispose(self: *const Transport) bool {
        if (!self.launch_delivered or !self.exit_delivered or !self.input_closed or !self.output_closed[0] or !self.output_closed[1] or self.token != null or self.write_completion != null) return false;
        for (self.endpoint_completion) |item| if (item != null) return false;
        return true;
    }
    pub fn disposeAfterWithdraw(self: *Transport) !void {
        if (!self.canDispose()) return error.NativeChildEndpointAcknowledgementRequired;
        try self.process.disposeExitedAfterWithdraw(); self.disposed = true;
    }
    pub fn detachToReaperAfterWithdraw(self: *Transport) !@import("native_child_process_reaper_linux.zig").Admission {
        const admission = try self.process.moveToReaperAfterWithdraw(); self.disposed = true; return admission;
    }
};
