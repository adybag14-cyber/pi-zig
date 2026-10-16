//! Native-only file IO packet. The Env IO worker invokes run; this module has
//! no Engine, JS values, guest callback, nextTick or process-signaling access.
const std = @import("std");
const builtin = @import("builtin");
pub const Operation = enum { open, write, sync, close };
pub const Packet = struct {
    io: std.Io,
    operation: Operation,
    path: []const u8 = &.{},
    create_options: std.Io.Dir.CreateFileOptions = .{},
    append: bool = false,
    file: ?std.Io.File = null,
    position: ?u64 = null,
    bytes: []const u8 = &.{},
    opened: ?std.Io.File = null,
    transferred: usize = 0,
    failure: ?anyerror = null,
    completed: bool = false,
    pub fn run(self: *Packet) void {
        if (self.failure != null) { self.completed = true; return; }
        if (builtin.os.tag == .windows and self.append and (self.operation == .open or self.operation == .write)) {
            // The existing direct NtWriteFile append helper is synchronous and
            // outside Threaded.Syscall.start. Group cancellation is not proof
            // that it can retire such an operation. Reject before opening until
            // the Windows append owner has its own cancellation-aware review.
            self.failure = error.RequiredCancellationAwareWindowsAppend;
            self.completed = true;
            return;
        }
        self.perform() catch |err| { self.failure = err; };
        self.completed = true;
    }
    fn perform(self: *Packet) !void {
        switch (self.operation) {
            .open => {
                const file = try std.Io.Dir.cwd().createFile(self.io, self.path, self.create_options);
                errdefer file.close(self.io);
                if (builtin.os.tag != .windows) {
                    if (self.append) {
                        const flags = std.posix.system.fcntl(file.handle, std.posix.F.GETFL, @as(usize, 0));
                        if (std.posix.errno(flags) != .SUCCESS) return error.Unexpected;
                        const mask: u32 = @bitCast(std.posix.O{ .APPEND = true });
                        if (std.posix.errno(std.posix.system.fcntl(file.handle, std.posix.F.SETFL, @as(usize, @intCast(flags)) | mask)) != .SUCCESS) return error.Unexpected;
                    }
                }
                self.opened = file;
            },
            .write => {
                const file = self.file orelse return error.BadFileDescriptor;
                if (self.bytes.len == 0) return;
                // A native operation may complete partially. The Source
                // WriteStream retry loop, on the VM owner, decides the suffix.
                if (self.position) |position| {
                    self.transferred = try file.writePositional(self.io, &.{self.bytes}, position);
                } else {
                    self.transferred = try file.writeStreaming(self.io, &.{}, &.{self.bytes}, 1);
                }
            },
            .sync => try (self.file orelse return error.BadFileDescriptor).sync(self.io),
            .close => {
                const file = self.file orelse return error.BadFileDescriptor;
                self.file = null;
                file.close(self.io);
            },
        }
    }
    /// Called only after worker return/Group cancellation has retired it.
    /// An abandoned successful open must not leak its unadopted handle.
    pub fn retireUnadopted(self: *Packet) void {
        if (self.opened) |file| { self.opened = null; file.close(self.io); }
        if (self.operation == .close) if (self.file) |file| { self.file = null; file.close(self.io); };
    }
};
pub fn descriptor(file: std.Io.File) !u64 {
    return if (builtin.os.tag == .windows) error.RequiredReviewedWindowsCrtDescriptorBridge else @intCast(file.handle);
}
