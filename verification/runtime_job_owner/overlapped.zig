//! One operation owns its OVERLAPPED/buffer until completed, not merely cancelled.
const std = @import("std");
const w = @import("win32.zig");
pub const Poll = union(enum) { pending, complete: u32, failed: u32 };
pub const Operation = struct {
    file: w.H,
    event: ?w.H,
    overlapped: w.Overlapped = std.mem.zeroes(w.Overlapped),
    pending: bool = false,
    completion: ?Poll = null,
    cancellation_requested: bool = false,

    /// init issues no I/O. Keep the returned state at a stable address thereafter.
    pub fn init(file: w.H) !Operation {
        const event = w.CreateEventW(null, 1, 0, null) orelse return error.IoEventFailed;
        return .{ .file = file, .event = event };
    }
    fn prepare(self: *Operation, offset: u64) !void {
        if (self.pending or self.event == null) return error.IoStateNotReusable;
        if (w.ResetEvent(self.event.?) == 0) return error.IoEventResetFailed;
        self.overlapped = std.mem.zeroes(w.Overlapped);
        self.overlapped.event = self.event;
        self.overlapped.offset = offset;
        self.completion = null;
        self.cancellation_requested = false;
    }
    pub fn read(self: *Operation, buffer: []u8) !void {
        if (buffer.len == 0 or buffer.len > 65536) return error.IoBufferLimit;
        try self.prepare(0);
        self.pending = true;
        if (w.ReadFile(self.file, buffer.ptr, @intCast(buffer.len), null, &self.overlapped) == 0) {
            const cause = w.GetLastError();
            if (cause != w.error_io_pending) {
                self.pending = false;
                self.completion = .{ .failed = cause };
            }
        }
    }
    pub fn write(self: *Operation, buffer: []const u8, offset: u64) !void {
        if (buffer.len == 0 or buffer.len > 65536) return error.IoBufferLimit;
        try self.prepare(offset);
        self.pending = true;
        if (w.WriteFile(self.file, buffer.ptr, @intCast(buffer.len), null, &self.overlapped) == 0) {
            const cause = w.GetLastError();
            if (cause != w.error_io_pending) {
                self.pending = false;
                self.completion = .{ .failed = cause };
            }
        }
    }
    pub fn poll(self: *Operation) Poll {
        if (self.completion) |completion| return completion;
        if (!self.pending) return .{ .failed = 87 };
        var count: u32 = 0;
        if (w.GetOverlappedResult(self.file, &self.overlapped, &count, 0) != 0) {
            self.pending = false;
            self.completion = .{ .complete = count };
        } else {
            const cause = w.GetLastError();
            if (cause == 996) return .pending; // ERROR_IO_INCOMPLETE
            self.pending = false;
            self.completion = .{ .failed = cause };
        }
        return self.completion.?;
    }
    pub fn cancel(self: *Operation) !void {
        if (!self.pending or self.cancellation_requested) return;
        self.cancellation_requested = true;
        if (w.CancelIoEx(self.file, &self.overlapped) == 0 and w.GetLastError() != w.error_not_found)
            return error.IoCancellationRequestFailed;
        // Even ERROR_NOT_FOUND is not a completion proof. poll remains required.
    }
    pub fn close(self: *Operation) !void {
        if (self.pending) return error.PendingIoStateMustRemainAlive;
        if (self.event) |event| {
            if (w.CloseHandle(event) == 0) return error.IoEventCloseFailed;
            self.event = null;
        }
    }
};

pub const Capture = struct {
    read: Operation,
    write: Operation,
    buffer: [65536]u8 = undefined,
    state: enum { idle, reading, writing, eof, failed } = .idle,
    buffered: usize = 0,
    written_in_buffer: usize = 0,
    bytes_received: u64 = 0,
    bytes_written: u64 = 0,
    limit: u64 = 8 * 1024 * 1024,
    first_error: ?anyerror = null,
    overflow: bool = false,
    hash: std.crypto.hash.sha2.Sha256 = std.crypto.hash.sha2.Sha256.init(.{}),

    pub fn init(reader: w.H, sink: w.H) !Capture {
        var read = try Operation.init(reader);
        errdefer read.close() catch {};
        const write = try Operation.init(sink);
        return .{ .read = read, .write = write };
    }
    pub fn advance(self: *Capture) !void {
        switch (self.state) {
            .idle => {
                try self.read.read(&self.buffer);
                self.state = .reading;
            },
            .reading => switch (self.read.poll()) {
                .pending => {},
                .failed => |cause| {
                    if (cause == w.error_broken_pipe or cause == w.error_pipe_not_connected) self.state = .eof else {
                        self.first_error = self.first_error orelse error.OutputReadFailed;
                        self.state = .failed;
                    }
                },
                .complete => |count| {
                    if (count == 0) {
                        // A peer zero-length WriteFile can complete a pipe read
                        // with zero bytes without disconnecting. Rearm; only a
                        // broken/disconnected completion establishes pipe EOF.
                        self.state = .idle;
                        return;
                    }
                    if (count > self.buffer.len) return error.OutputReadCountInvalid;
                    self.bytes_received = std.math.add(u64, self.bytes_received, count) catch return error.OutputCountOverflow;
                    const allowed = @min(@as(u64, count), self.limit - self.bytes_written);
                    self.overflow = allowed < count;
                    if (self.overflow) self.first_error = self.first_error orelse error.OutputLimitExceeded;
                    if (allowed == 0) {
                        self.state = .failed;
                        return;
                    }
                    self.buffered = @intCast(allowed);
                    self.written_in_buffer = 0;
                    try self.write.write(self.buffer[0..self.buffered], self.bytes_written);
                    self.state = .writing;
                },
            },
            .writing => switch (self.write.poll()) {
                .pending => {},
                .failed => {
                    self.first_error = self.first_error orelse error.OutputWriteFailed;
                    self.state = .failed;
                },
                .complete => |count| {
                    if (count == 0 or count > self.buffered - self.written_in_buffer) return error.OutputWriteCountInvalid;
                    self.hash.update(self.buffer[self.written_in_buffer..][0..count]);
                    self.written_in_buffer += count;
                    self.bytes_written += count;
                    if (self.written_in_buffer < self.buffered) {
                        try self.write.write(self.buffer[self.written_in_buffer..self.buffered], self.bytes_written);
                    } else {
                        self.state = if (self.overflow) .failed else .idle;
                    }
                },
            },
            .eof, .failed => {},
        }
    }
    pub fn cancel(self: *Capture) !void {
        var failure: ?anyerror = null;
        self.read.cancel() catch |err| { failure = err; };
        self.write.cancel() catch |err| { failure = failure orelse err; };
        if (failure) |err| return err;
    }
    pub fn ioRetired(self: *Capture) bool {
        _ = self.read.poll();
        _ = self.write.poll();
        return !self.read.pending and !self.write.pending;
    }
    pub fn close(self: *Capture) !void {
        try self.read.close();
        try self.write.close();
    }
};
