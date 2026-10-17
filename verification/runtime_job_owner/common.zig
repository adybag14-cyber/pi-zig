//! Native waits and fresh owned directories; never shell out to another owner.
const std = @import("std");
const w = @import("win32.zig");
const files = @import("files.zig");
const protocol = @import("protocol.zig");
const Channel = @import("transport.zig").Channel;
const Deadline = @import("deadline.zig").Deadline;
pub fn freshDirectory(allocator: std.mem.Allocator, path: []const u8, root: []const u8) !void {
    try files.contained(path, root);
    try files.requirePhysicalAncestors(allocator, path);
    const utf8 = try std.fmt.allocPrint(allocator, "\\\\?\\{s}", .{path});
    defer allocator.free(utf8);
    const wide = try std.unicode.utf8ToUtf16LeAllocZ(allocator, utf8);
    defer allocator.free(wide);
    if (w.CreateDirectoryW(wide.ptr, null) == 0) return error.FreshEvidenceDirectoryRequired;
}
pub fn ensureDirectory(allocator: std.mem.Allocator, path: []const u8, root: []const u8) !void {
    try files.contained(path, root);
    const utf8 = try std.fmt.allocPrint(allocator, "\\\\?\\{s}", .{path});
    defer allocator.free(utf8);
    const wide = try std.unicode.utf8ToUtf16LeAllocZ(allocator, utf8);
    defer allocator.free(wide);
    if (w.CreateDirectoryW(wide.ptr, null) == 0 and w.GetLastError() != 183) return error.EvidenceParentCreateFailed;
    try files.requirePhysicalAncestors(allocator, path);
    const handle = try files.openLeaf(allocator, path, w.generic_read, w.open_existing, w.file_flag_backup_semantics);
    defer _ = w.CloseHandle(handle);
    if ((try files.requirePhysical(handle)).attributes & w.file_attribute_directory == 0) return error.EvidenceParentNotDirectory;
}
pub fn selfPath(allocator: std.mem.Allocator) ![]u8 {
    var buffer: [32768]u16 = undefined;
    const units = w.GetModuleFileNameW(null, &buffer, buffer.len);
    if (units == 0 or units >= buffer.len) return error.OwnerImagePathUnverifiable;
    return std.unicode.utf16LeToUtf8Alloc(allocator, buffer[0..units]);
}
pub fn waitChannel(channel: *Channel, end_ms: u64) !void {
    if (w.GetTickCount64() >= end_ms) return error.ControlDeadline;
    var handles: [2]w.H = undefined;
    var count: usize = 0;
    if (channel.reader.pending) { handles[count] = channel.reader.event.?; count += 1; }
    if (channel.writer.pending) { handles[count] = channel.writer.event.?; count += 1; }
    try waitPending(handles[0..count], end_ms);
}
/// Completed manual-reset I/O events stay signaled. Only pending operations
/// enter the wait set; an empty set uses a bounded wait on our live process.
pub fn waitPending(handles: []const w.H, end_ms: u64) !void {
    if (w.GetTickCount64() >= end_ms) return error.ControlDeadline;
    const timeout = @min(250, Deadline.remaining(end_ms));
    const result = if (handles.len == 0) w.WaitForSingleObject(w.GetCurrentProcess(), timeout) else
        w.WaitForMultipleObjects(@intCast(handles.len), handles.ptr, 0, timeout);
    if (result == w.wait_failed) return error.ControlWaitFailed;
}
pub fn send(channel: *Channel, message_frame: *const protocol.Frame, end_ms: u64) !void {
    try channel.send(message_frame);
    while (channel.sending) {
        if (w.GetTickCount64() >= end_ms) return error.ControlDeadline;
        try channel.advanceWrite();
        if (channel.sending) try waitChannel(channel, end_ms);
    }
}
pub fn receive(channel: *Channel, end_ms: u64) !protocol.Frame {
    while (true) {
        if (w.GetTickCount64() >= end_ms) return error.ControlDeadline;
        try channel.receive();
        if (channel.take()) |message_frame| return message_frame;
        if (channel.closed) return error.ControlClosed;
        try waitChannel(channel, end_ms);
    }
}
pub fn frame(kind: protocol.Kind, sequence: u64, nonce: [32]u8, pid: u32, parent: u32,
    creation: u64, intent: [32]u8) protocol.Frame
{
    return .{ .marker = protocol.magic, .schema = 1, .kind = @intFromEnum(kind), .sequence = sequence,
        .nonce = nonce, .pid = pid, .parent_pid = parent, .creation_filetime_utc = creation,
        .worker_local_node_handle = 0, .code = 0, .flags = 0, .input_sha256 = intent };
}

pub const Watchdog = struct {
    hard_ms: std.atomic.Value(u64),
    stop_event: ?w.H = null,
    thread: ?w.H = null,
    attempted: bool = false,
    pub fn start(self: *Watchdog) !void {
        if (self.attempted) return error.WatchdogOneShot;
        self.attempted = true;
        self.stop_event = w.CreateEventW(null, 1, 0, null) orelse return error.WatchdogEventFailed;
        self.thread = w.CreateThread(null, 1024 * 1024, run, self, 0, null) orelse return error.WatchdogThreadFailed;
    }
    fn run(raw: ?*anyopaque) callconv(.winapi) u32 {
        const self: *Watchdog = @ptrCast(@alignCast(raw.?));
        while (true) {
            const hard_ms = self.hard_ms.load(.acquire);
            if (w.GetTickCount64() >= hard_ms) break;
            if (w.WaitForSingleObject(self.stop_event.?, @min(250, Deadline.remaining(hard_ms))) == w.wait_object) return 0;
        }
        // Own-process hard fallback only. Closing its sole fresh job handle
        // invokes kill-on-close. This path has no fabricated terminal/zero proof.
        w.ExitProcess(124);
    }
    pub fn shorten(self: *Watchdog, hard_ms: u64) !void {
        // The main thread is the sole deadline writer; the watchdog only reads.
        if (hard_ms > self.hard_ms.load(.acquire)) return error.WorkerDeadlineExtension;
        self.hard_ms.store(hard_ms, .release);
    }
    pub fn stopRetired(self: *Watchdog, hard_ms: u64) !void {
        if (self.stop_event) |event| if (w.SetEvent(event) == 0) return error.WatchdogStopFailed;
        if (self.thread) |thread| {
            if (w.WaitForSingleObject(thread, Deadline.remaining(hard_ms)) != w.wait_object) return error.WatchdogRetirementUnproven;
            if (w.CloseHandle(thread) == 0) return error.WatchdogThreadCloseFailed;
            self.thread = null;
        }
        if (self.stop_event) |event| {
            if (w.CloseHandle(event) == 0) return error.WatchdogEventCloseFailed;
            self.stop_event = null;
        }
    }
};
