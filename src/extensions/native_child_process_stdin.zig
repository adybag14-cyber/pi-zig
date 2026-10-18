//! One-step input pump; never starts a blocking writer or retains guest values.
const std = @import("std");
const builtin = @import("builtin");
const windows = @import("native_child_process_stdin_windows.zig");
pub const Pump = struct {
    windows_slot: ?*windows.Slot = null,
    posix_file: ?std.Io.File = null,
    offset: usize = 0,
    pending_length: usize = 0,
    failure: ?anyerror = null,
    retirement_pending: bool = false,

    pub fn adoptPosix(self: *Pump, file: std.Io.File) !void {
        if (builtin.os.tag == .windows) return error.NativeStdinWrongPlatform;
        // Preserve existing flags; only this owned parent write endpoint changes.
        var flags: usize = while (true) {
            const rc = std.posix.system.fcntl(file.handle, std.posix.F.GETFL, @as(usize, 0));
            switch (std.posix.errno(rc)) { .SUCCESS => break @intCast(rc), .INTR => continue, else => return error.NativeStdinNonblockingFailed }
        };
        flags |= @as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK");
        while (true) switch (std.posix.errno(std.posix.system.fcntl(file.handle, std.posix.F.SETFL, flags))) {
            .SUCCESS => break, .INTR => continue, else => return error.NativeStdinNonblockingFailed,
        };
        var owned = file;
        owned.flags.nonblocking = true;
        self.posix_file = owned;
    }
    pub fn step(self: *Pump, io: std.Io, bytes: []const u8) !void {
        if (self.failure != null) return;
        if (builtin.os.tag == .windows) {
            const slot = self.windows_slot orelse return;
            if (slot.pending) {
                const count = slot.completion() catch |err| { self.failure = err; self.retire(io); return; };
                if (count) |written| {
                    if (written == 0 or written > self.pending_length) { self.failure = error.NativeStdinInvalidWriteProgress; self.retire(io); return; }
                    self.offset += written;
                    self.pending_length = 0;
                } else return;
            }
            if (self.offset == bytes.len) { self.retire(io); return; }
            const chunk = bytes[self.offset..@min(bytes.len, self.offset + windows.chunk_size)];
            const count = slot.write(chunk) catch |err| { self.failure = err; self.retire(io); return; };
            if (count) |written| {
                if (written == 0 or written > chunk.len) { self.failure = error.NativeStdinInvalidWriteProgress; self.retire(io); return; }
                self.offset += written;
                if (self.offset == bytes.len) self.retire(io);
            } else self.pending_length = chunk.len;
        } else {
            const file = self.posix_file orelse return;
            if (self.offset == bytes.len) { self.retire(io); return; }
            var descriptors = [_]std.posix.pollfd{.{ .fd = file.handle, .events = std.posix.POLL.OUT, .revents = 0 }};
            if (try std.posix.poll(&descriptors, 0) == 0) return;
            if (descriptors[0].revents & (std.posix.POLL.OUT | std.posix.POLL.HUP | std.posix.POLL.ERR) == 0) return;
            const chunk = bytes[self.offset..@min(bytes.len, self.offset + windows.chunk_size)];
            // The actual native std.Io backend owns its existing SIGPIPE handling;
            // this adapter changes no process-global signal disposition. A single
            // nonblocking write returns WouldBlock rather than awaiting pressure.
            const written = file.writeStreaming(io, &.{}, &.{chunk}, 1) catch |err| switch (err) {
                error.WouldBlock => return,
                error.Canceled => return err,
                else => { self.failure = err; self.retire(io); return; },
            };
            if (written == 0 or written > chunk.len) { self.failure = error.NativeStdinInvalidWriteProgress; self.retire(io); return; }
            self.offset += written;
            if (self.offset == bytes.len) self.retire(io);
        }
    }
    pub fn retire(self: *Pump, io: std.Io) void {
        if (builtin.os.tag == .windows) if (self.windows_slot) |slot| {
            self.windows_slot = null;
            if (!slot.retire()) self.retirement_pending = true;
        };
        if (self.posix_file) |file| { self.posix_file = null; file.close(io); }
    }
};
