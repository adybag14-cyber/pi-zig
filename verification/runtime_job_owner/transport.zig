//! Fixed-size private control transport; buffers remain until I/O completion.
const std = @import("std");
const w = @import("win32.zig");
const protocol = @import("protocol.zig");
const Operation = @import("overlapped.zig").Operation;
pub const Channel = struct {
    handle: w.H,
    reader: Operation,
    writer: Operation,
    input: [@sizeOf(protocol.Frame)]u8 = undefined,
    output: [@sizeOf(protocol.Frame)]u8 = undefined,
    input_count: usize = 0,
    output_count: usize = 0,
    ready: ?protocol.Frame = null,
    sending: bool = false,
    started_read: bool = false,
    closed: bool = false,
    received_bytes: u64 = 0,
    sent_bytes: u64 = 0,
    pub fn init(handle: w.H) !Channel {
        var reader = try Operation.init(handle);
        errdefer reader.close() catch {};
        const writer = try Operation.init(handle);
        return .{ .handle = handle, .reader = reader, .writer = writer };
    }
    pub fn receive(self: *Channel) !void {
        if (self.closed or self.ready != null) return;
        if (!self.started_read) {
            try self.reader.read(self.input[self.input_count..]);
            self.started_read = true;
        }
        switch (self.reader.poll()) {
            .pending => {},
            .failed => |cause| {
                self.closed = true;
                if (cause == w.error_broken_pipe or cause == w.error_pipe_not_connected) {
                    if (self.input_count != 0) return error.TruncatedControlFrame;
                    return;
                }
                return error.ControlReadFailed;
            },
            .complete => |count| {
                self.started_read = false;
                if (count > self.input.len - self.input_count) return error.ControlReadCountInvalid;
                if (count == 0) return; // zero-length write is not EOF
                self.input_count += count;
                self.received_bytes += count;
                if (self.received_bytes > 32 * 1024 * 1024) return error.ControlProtocolLimit;
                if (self.input_count == self.input.len) {
                    var frame: protocol.Frame = undefined;
                    @memcpy(std.mem.asBytes(&frame), &self.input);
                    self.ready = frame;
                }
            },
        }
    }
    pub fn take(self: *Channel) ?protocol.Frame {
        const frame = self.ready orelse return null;
        self.ready = null;
        self.input_count = 0;
        return frame;
    }
    pub fn send(self: *Channel, frame: *const protocol.Frame) !void {
        if (self.sending) return error.ControlWriteAlreadyPending;
        if (self.sent_bytes + @sizeOf(protocol.Frame) > 32 * 1024 * 1024) return error.ControlProtocolLimit;
        @memcpy(&self.output, std.mem.asBytes(frame));
        self.output_count = 0;
        self.sending = true;
        try self.writer.write(&self.output, 0);
    }
    pub fn advanceWrite(self: *Channel) !void {
        if (!self.sending) return;
        switch (self.writer.poll()) {
            .pending => {},
            .failed => return error.ControlWriteFailed,
            .complete => |count| {
                if (count == 0 or count > self.output.len - self.output_count) return error.ControlWriteCountInvalid;
                self.output_count += count;
                self.sent_bytes += count;
                if (self.output_count == self.output.len) self.sending = false else
                    try self.writer.write(self.output[self.output_count..], 0);
            },
        }
    }
    pub fn cancel(self: *Channel) !void {
        var first: ?anyerror = null;
        self.reader.cancel() catch |err| { first = err; };
        self.writer.cancel() catch |err| { first = first orelse err; };
        if (first) |err| return err;
    }
    pub fn retired(self: *Channel) bool {
        _ = self.reader.poll();
        _ = self.writer.poll();
        return !self.reader.pending and !self.writer.pending;
    }
    pub fn closeRetired(self: *Channel) !void {
        try self.reader.close();
        try self.writer.close();
    }
};
