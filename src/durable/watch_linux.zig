//! Small owned inotify backend. Snapshots and scope rules stay in watch.zig.
const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;
pub const Installed = struct { descriptor: i32, inode: std.Io.File.INode, device: u64 };
pub const Backend = struct {
    gpa: std.mem.Allocator,
    fd: i32,
    installed: std.StringHashMapUnmanaged(Installed) = .empty,
    pub fn init(gpa: std.mem.Allocator) !Backend {
        if (builtin.os.tag != .linux) return error.OperationUnsupported;
        const result = linux.inotify_init1(linux.IN.CLOEXEC | linux.IN.NONBLOCK);
        if (linux.errno(result) != .SUCCESS) return error.NativeWatchUnavailable;
        return .{ .gpa = gpa, .fd = @intCast(result) };
    }
    pub fn deinit(self: *Backend) void {
        if (builtin.os.tag == .linux) _ = linux.close(self.fd);
        var keys = self.installed.keyIterator();
        while (keys.next()) |key| self.gpa.free(key.*);
        self.installed.deinit(self.gpa);
    }
    pub fn remove(self: *Backend, path: []const u8) void {
        const entry = self.installed.fetchRemove(path) orelse return;
        var shared = false;
        var iterator = self.installed.valueIterator();
        while (iterator.next()) |installed| if (installed.descriptor == entry.value.descriptor) {
            shared = true;
            break;
        };
        if (builtin.os.tag == .linux and !shared) _ = linux.inotify_rm_watch(self.fd, entry.value.descriptor);
        self.gpa.free(entry.key);
    }
    pub fn add(self: *Backend, path: []const u8, inode: std.Io.File.INode, device: u64) !bool {
        if (builtin.os.tag != .linux) return error.OperationUnsupported;
        if (self.installed.contains(path)) return false;
        const terminated = try self.gpa.dupeZ(u8, path);
        defer self.gpa.free(terminated);
        const mask = linux.IN.MODIFY | linux.IN.ATTRIB | linux.IN.MOVE | linux.IN.CREATE | linux.IN.DELETE | linux.IN.DELETE_SELF | linux.IN.MOVE_SELF;
        const result = linux.inotify_add_watch(self.fd, terminated, mask);
        switch (linux.errno(result)) {
            .SUCCESS => {},
            .NOENT, .ACCES, .NOTDIR => return false,
            else => return error.NativeWatchUnavailable,
        }
        const descriptor: i32 = @intCast(result);
        const owned = try self.gpa.dupe(u8, path);
        errdefer self.gpa.free(owned);
        self.installed.put(self.gpa, owned, .{ .descriptor = descriptor, .inode = inode, .device = device }) catch |err| {
            _ = linux.inotify_rm_watch(self.fd, descriptor);
            return err;
        };
        return true;
    }
    /// Sink has event(path) !void and overflow() !void. Events about one inode
    /// watched by several lexical paths are delivered under each spelling.
    pub fn drain(self: *Backend, sink: anytype) !void {
        if (builtin.os.tag != .linux) return;
        var buffer: [64 * 1024]u8 = undefined;
        while (true) {
            const result = linux.read(self.fd, &buffer, buffer.len);
            const count: usize = switch (linux.errno(result)) {
                .SUCCESS => result,
                .AGAIN => return,
                .INTR => continue,
                else => return error.NativeWatchUnavailable,
            };
            if (count == 0) return;
            var offset: usize = 0;
            while (offset < count) {
                if (count - offset < 16) return error.InvalidNativeWatchEvent;
                const descriptor: i32 = std.mem.readInt(i32, buffer[offset..][0..4], builtin.cpu.arch.endian());
                const mask = std.mem.readInt(u32, buffer[offset + 4 ..][0..4], builtin.cpu.arch.endian());
                const length = std.mem.readInt(u32, buffer[offset + 12 ..][0..4], builtin.cpu.arch.endian());
                if (length > count - offset - 16) return error.InvalidNativeWatchEvent;
                if (mask & linux.IN.Q_OVERFLOW != 0) try sink.overflow();
                if (mask & linux.IN.IGNORED == 0) {
                    const encoded = buffer[offset + 16 ..][0..length];
                    const end = std.mem.indexOfScalar(u8, encoded, 0) orelse encoded.len;
                    const name = try @import("decode.zig").decode(self.gpa, encoded[0..end], true);
                    defer self.gpa.free(name);
                    var iterator = self.installed.iterator();
                    while (iterator.next()) |entry| if (entry.value_ptr.descriptor == descriptor) {
                        const path = if (name.len == 0) try self.gpa.dupe(u8, entry.key_ptr.*) else try std.fs.path.join(self.gpa, &.{ entry.key_ptr.*, name });
                        defer self.gpa.free(path);
                        try sink.event(path);
                    };
                }
                offset += 16 + length;
            }
        }
    }
};
/// Linux statfs on x86_64/aarch64: only f_type is inspected, but the syscall
/// receives a generously sized aligned buffer for all supported native fields.
pub fn unreliable(gpa: std.mem.Allocator, paths: anytype) !bool {
    if (builtin.os.tag != .linux) return false;
    for (paths) |target| {
        var candidate: ?[]const u8 = target.path;
        while (candidate) |path| {
            const terminated = try gpa.dupeZ(u8, path);
            defer gpa.free(terminated);
            var info: [256]u8 align(8) = undefined;
            const result = linux.syscall2(.statfs, @intFromPtr(terminated.ptr), @intFromPtr(&info));
            if (linux.errno(result) == .SUCCESS) {
                const magic = std.mem.readInt(u64, info[0..8], builtin.cpu.arch.endian()) & 0xffffffff;
                for ([_]u64{ 0x6969, 0x517b, 0xff534d42, 0xfe534d42, 0x65735546, 0x01021997, 0x0bd00bd0, 0x47504653, 0x00c36400, 0x5346414f, 0x6b414653, 0x5dca2df5 }) |unreliable_kind| if (magic == unreliable_kind) return true;
                break;
            }
            const parent = std.fs.path.dirname(path);
            if (parent != null and std.mem.eql(u8, parent.?, path)) break;
            candidate = parent;
        }
    }
    return false;
}
