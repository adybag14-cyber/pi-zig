//! Native-only file IO packet. The Env IO worker invokes run; this module has
//! no Engine, JS values, guest callback, nextTick or process-signaling access.
const std = @import("std");
const builtin = @import("builtin");
const uv = if (builtin.os.tag == .windows) @cImport({ @cInclude("native_uv_fs_write.h"); }) else struct {};

/// Windows owns a real CRT descriptor through the single shared libuv owner.
/// Each retained operation entitlement keeps this native object alive; it never
/// creates an independent HANDLE association.
pub const File = if (builtin.os.tag == .windows) struct {
    handle: *uv.PiUvFileHandle,
    pub fn close(self: @This(), _: std.Io) void { _ = uv.pi_uv_file_release(self.handle); }
} else std.Io.File;

pub fn retainFile(file: File) File {
    if (builtin.os.tag == .windows) uv.pi_uv_file_retain(file.handle);
    return file;
}

pub const Operation = enum { open, write, sync, close };
pub const Packet = struct {
    io: std.Io,
    operation: Operation,
    path: []const u8 = &.{},
    windows_path: ?[:0]const u8 = null,
    memory_owner: ?*anyopaque = null,
    mode: u32 = 0o666,
    descriptor_value: ?c_int = null,
    create_options: std.Io.Dir.CreateFileOptions = .{},
    append: bool = false,
    file: ?File = null,
    position: ?u64 = null,
    bytes: []const u8 = &.{},
    opened: ?File = null,
    transferred: usize = 0,
    failure: ?anyerror = null,
    uv_status: c_int = 0,
    rollback_close_status: c_int = 0,
    completed: bool = false,
    ran: bool = false,
    stopped: std.atomic.Value(bool) = .init(false),
    pub fn cancel(self: *Packet) void { self.stopped.store(true, .release); }
    pub fn run(self: *Packet) void {
        if (self.failure != null) { self.completed = true; return; }
        if (self.stopped.load(.acquire)) { self.failure = error.Canceled; self.completed = true; return; }
        self.ran = true;
        self.perform() catch |err| { self.failure = err; };
        self.completed = true;
    }
    fn perform(self: *Packet) !void {
        return if (builtin.os.tag == .windows) self.performWindows() else self.performPosix();
    }
    fn performPosix(self: *Packet) !void {
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
    fn performWindows(self: *Packet) !void {
        switch (self.operation) {
            .open => {
                const path = self.windows_path orelse return error.MissingNativeWindowsWritePath;
                const flags = uv.pi_uv_fs_write_open_flags(@intFromBool(self.append),
                    @intFromBool(self.create_options.exclusive));
                const result = uv.pi_uv_file_open(self.memory_owner, path.ptr,
                    flags, @bitCast(self.mode));
                self.uv_status = result.uv_status;
                self.rollback_close_status = result.rollback_close_status;
                if (result.native_allocation_failure != 0) return error.OutOfMemory;
                if (result.handle) |handle| self.opened = .{ .handle = handle };
            },
            .write => {
                const file = self.file orelse return error.BadFileDescriptor;
                if (self.bytes.len == 0) return;
                _ = file;
                const fd = self.descriptor_value orelse return error.MissingNativeWindowsWriteDescriptor;
                const position: i64 = if (self.position) |given| @intCast(given) else -1;
                const result = uv.pi_uv_fs_write(fd, self.bytes.ptr, self.bytes.len, position);
                self.uv_status = result.uv_status;
                if (result.uv_status == 0) self.transferred = @intCast(result.bytes_written);
            },
            .sync => {
                const file = self.file orelse return error.BadFileDescriptor;
                _ = file;
                self.uv_status = uv.pi_uv_fs_fsync(self.descriptor_value orelse return error.MissingNativeWindowsWriteDescriptor);
            },
            .close => {
                const file = self.file orelse return error.BadFileDescriptor;
                // The VM registry admitted this sole close before submission.
                // Atomic physical-fd exchange prevents cleanup closing a reuse.
                self.uv_status = uv.pi_uv_file_close_work(file.handle);
            },
        }
    }
    /// Completion publishes the shared owner's closed view on the VM owner,
    /// after the actual physical close returned and before its JS callback.
    pub fn publishClose(self: *Packet) void {
        if (builtin.os.tag == .windows and self.ran and self.completed and self.operation == .close)
            if (self.file) |file| uv.pi_uv_file_finish_close(file.handle);
    }
    /// Called only after worker return/Group cancellation has retired it.
    /// An abandoned successful open must not leak its unadopted handle.
    pub fn retireUnadopted(self: *Packet) void {
        if (self.opened) |file| { self.opened = null; file.close(self.io); }
        if (builtin.os.tag == .windows) {
            self.publishClose();
            // All Windows packets hold a native reference. Hub destruction
            // occurs only after their real workers have returned.
            if (self.file) |file| { self.file = null; file.close(self.io); }
        } else if (self.operation == .close) {
            if (self.file) |file| { self.file = null; file.close(self.io); }
        }
    }
};
pub fn descriptor(file: File) !u64 {
    if (builtin.os.tag == .windows) {
        const fd = uv.pi_uv_file_descriptor(file.handle);
        if (fd < 0) return error.BadFileDescriptor;
        return @intCast(fd);
    }
    return @intCast(file.handle);
}
