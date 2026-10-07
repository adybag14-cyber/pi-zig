//! Owned overlapped ReadDirectoryChangesW subscriptions. Scope stays in watch.zig.
const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;
const HANDLE = windows.HANDLE;
const Overlapped = extern struct {
    internal: usize = 0,
    internal_high: usize = 0,
    offset: u32 = 0,
    offset_high: u32 = 0,
    event: ?HANDLE = null,
};
extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, ?*anyopaque, u32, u32, ?HANDLE) callconv(.winapi) HANDLE;
extern "kernel32" fn GetFileAttributesW([*:0]const u16) callconv(.winapi) u32;
extern "kernel32" fn CreateEventW(?*anyopaque, i32, i32, ?[*:0]const u16) callconv(.winapi) ?HANDLE;
extern "kernel32" fn ResetEvent(HANDLE) callconv(.winapi) i32;
extern "kernel32" fn ReadDirectoryChangesW(HANDLE, *anyopaque, u32, i32, u32, ?*u32, *Overlapped, ?*anyopaque) callconv(.winapi) i32;
extern "kernel32" fn GetOverlappedResult(HANDLE, *Overlapped, *u32, i32) callconv(.winapi) i32;
extern "kernel32" fn CancelIoEx(HANDLE, *Overlapped) callconv(.winapi) i32;
extern "kernel32" fn CloseHandle(HANDLE) callconv(.winapi) i32;
extern "kernel32" fn GetLastError() callconv(.winapi) u32;
extern "kernel32" fn GetCurrentProcess() callconv(.winapi) HANDLE;
extern "kernel32" fn GetProcessHandleCount(HANDLE, *u32) callconv(.winapi) i32;
const State = struct {
    handle: HANDLE,
    event: HANDLE,
    overlapped: Overlapped,
    buffer: [16 * 1024]u8 align(4) = undefined,
    parent: []u8,
    file_name: ?[]u8,
    pending: bool = false,
    fn arm(self: *State) !void {
        _ = ResetEvent(self.event);
        self.overlapped = .{ .event = self.event };
        // The source notify backend subscribes name/attribute/size/write/
        // creation/security changes, and never access/read notifications.
        if (ReadDirectoryChangesW(self.handle, &self.buffer, self.buffer.len, 0, 0x15f, null, &self.overlapped, null) == 0) return error.NativeWatchUnavailable;
        self.pending = true;
    }
    fn deinit(self: *State, gpa: std.mem.Allocator) void {
        if (self.pending) {
            _ = CancelIoEx(self.handle, &self.overlapped);
            var completed: u32 = 0;
            // The kernel must retire this exact operation before its buffer,
            // OVERLAPPED and event are freed. No borrowed process is involved.
            _ = GetOverlappedResult(self.handle, &self.overlapped, &completed, 1);
        }
        _ = CloseHandle(self.handle);
        _ = CloseHandle(self.event);
        gpa.free(self.parent);
        if (self.file_name) |name| gpa.free(name);
        gpa.destroy(self);
    }
};
pub const Installed = struct { inode: std.Io.File.INode, device: u64, state: *State };
pub const Backend = struct {
    gpa: std.mem.Allocator,
    installed: std.StringHashMapUnmanaged(Installed) = .empty,
    pub fn init(gpa: std.mem.Allocator) !Backend {
        if (builtin.os.tag != .windows) return error.OperationUnsupported;
        return .{ .gpa = gpa };
    }
    pub fn deinit(self: *Backend) void {
        var iterator = self.installed.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.state.deinit(self.gpa);
            self.gpa.free(entry.key_ptr.*);
        }
        self.installed.deinit(self.gpa);
    }
    pub fn remove(self: *Backend, path: []const u8) void {
        const entry = self.installed.fetchRemove(path) orelse return;
        entry.value.state.deinit(self.gpa);
        self.gpa.free(entry.key);
    }
    pub fn add(self: *Backend, path: []const u8, inode: std.Io.File.INode, device: u64) !bool {
        if (self.installed.contains(path)) return false;
        const encoded = try std.unicode.wtf8ToWtf16LeAllocZ(self.gpa, path);
        defer self.gpa.free(encoded);
        const attributes = GetFileAttributesW(encoded);
        if (attributes == 0xffffffff) switch (GetLastError()) {
            2, 3, 5 => return false,
            else => return error.NativeWatchUnavailable,
        };
        const directory = attributes & 0x10 != 0;
        const parent = try self.gpa.dupe(u8, if (directory) path else std.fs.path.dirname(path) orelse return false);
        errdefer self.gpa.free(parent);
        const file_name = if (directory) null else try self.gpa.dupe(u8, std.fs.path.basename(path));
        errdefer if (file_name) |name| self.gpa.free(name);
        const parent_encoded = try std.unicode.wtf8ToWtf16LeAllocZ(self.gpa, parent);
        defer self.gpa.free(parent_encoded);
        const handle = CreateFileW(parent_encoded, 1, 7, null, 3, 0x42000000, null);
        if (handle == windows.INVALID_HANDLE_VALUE) switch (GetLastError()) {
            2, 3, 5, 267 => return false,
            else => return error.NativeWatchUnavailable,
        };
        errdefer _ = CloseHandle(handle);
        const event = CreateEventW(null, 1, 0, null) orelse return error.NativeWatchUnavailable;
        errdefer _ = CloseHandle(event);
        const state = try self.gpa.create(State);
        errdefer self.gpa.destroy(state);
        state.* = .{ .handle = handle, .event = event, .overlapped = .{ .event = event }, .parent = parent, .file_name = file_name };
        const owned = try self.gpa.dupe(u8, path);
        errdefer self.gpa.free(owned);
        // Publish registry ownership before arming the kernel operation.
        try self.installed.put(self.gpa, owned, .{ .inode = inode, .device = device, .state = state });
        state.arm() catch |err| {
            _ = self.installed.remove(owned);
            return err;
        };
        return true;
    }
    pub fn drain(self: *Backend, sink: anytype) !void {
        var iterator = self.installed.iterator();
        while (iterator.next()) |entry| {
            const state = entry.value_ptr.state;
            var count: u32 = 0;
            if (GetOverlappedResult(state.handle, &state.overlapped, &count, 0) == 0) switch (GetLastError()) {
                996 => continue, // ERROR_IO_INCOMPLETE
                1022 => { // ERROR_NOTIFY_ENUM_DIR: coverage needs a rescan
                    state.pending = false;
                    try sink.overflow();
                    try state.arm();
                    continue;
                },
                else => return error.NativeWatchUnavailable,
            };
            state.pending = false;
            if (count == 0) try sink.overflow();
            var offset: usize = 0;
            while (offset < count) {
                if (count - offset < 12) return error.InvalidNativeWatchEvent;
                const next = std.mem.readInt(u32, state.buffer[offset..][0..4], .little);
                const length = std.mem.readInt(u32, state.buffer[offset + 8 ..][0..4], .little);
                if (length % 2 != 0 or length > count - offset - 12) return error.InvalidNativeWatchEvent;
                const units: []align(1) const u16 = std.mem.bytesAsSlice(u16, state.buffer[offset + 12 ..][0..length]);
                const aligned = try self.gpa.alloc(u16, units.len);
                defer self.gpa.free(aligned);
                @memcpy(aligned, units);
                const wtf8 = try std.unicode.wtf16LeToWtf8Alloc(self.gpa, aligned);
                defer self.gpa.free(wtf8);
                const name = try @import("decode.zig").decode(self.gpa, wtf8, true);
                defer self.gpa.free(name);
                if (state.file_name == null or std.ascii.eqlIgnoreCase(state.file_name.?, name)) {
                    const path = if (state.file_name != null) try self.gpa.dupe(u8, entry.key_ptr.*) else try std.fs.path.join(self.gpa, &.{ state.parent, name });
                    defer self.gpa.free(path);
                    try sink.event(path);
                }
                if (next == 0) break;
                if (next < 12 + length or next > count - offset) return error.InvalidNativeWatchEvent;
                offset += next;
            }
            try state.arm();
        }
    }
};
pub fn unreliable(_: std.mem.Allocator, _: anytype) !bool {
    return false;
}

fn allocationProbe(gpa: std.mem.Allocator, path: []const u8) !void {
    var backend = try Backend.init(gpa);
    defer backend.deinit();
    try std.testing.expect(try backend.add(path, 1, 0));
    backend.remove(path);
    try std.testing.expectEqual(@as(u32, 0), backend.installed.count());
}
test "durable watch Windows native kernel handles retire through cancellation and every allocation failure" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(std.testing.io, &buffer);
    // Warm up the operation before comparing process handle counts.
    try allocationProbe(std.testing.allocator, buffer[0..length]);
    var before: u32 = 0;
    try std.testing.expect(GetProcessHandleCount(GetCurrentProcess(), &before) != 0);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{buffer[0..length]});
    for (0..100) |_| try allocationProbe(std.testing.allocator, buffer[0..length]);
    var after: u32 = 0;
    try std.testing.expect(GetProcessHandleCount(GetCurrentProcess(), &after) != 0);
    try std.testing.expectEqual(before, after);
}
