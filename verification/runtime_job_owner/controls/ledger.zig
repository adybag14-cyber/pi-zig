//! Bounded durable native descendant records; no inherited writer handle.
const std = @import("std");
const w = @import("../win32.zig");
const files = @import("../files.zig");
const Kernel = @import("../process.zig").KernelIdentity;
pub const Ledger = struct {
    handle: ?w.H,
    bytes: usize = 0,
    pub fn open(allocator: std.mem.Allocator, root: []const u8, parent: *const Kernel) !Ledger {
        try files.contained(root, files.container ++ "\\evidence");
        const path = try std.fmt.allocPrint(allocator, "{s}\\descendant-{d}-{d}.jsonl",
            .{ root, parent.pid, parent.creation_filetime_utc });
        try files.contained(path, root);
        try files.requirePhysicalAncestors(allocator, path);
        const handle = try files.openLeaf(allocator, path, w.generic_write, w.create_new, 0);
        errdefer _ = w.CloseHandle(handle);
        var flags: u32 = 0;
        if (w.GetHandleInformation(handle, &flags) == 0 or flags & w.handle_flag_inherit != 0)
            return error.DescendantLedgerInheritable;
        return .{ .handle = handle };
    }
    pub fn append(self: *Ledger, value: anytype) !void {
        var buffer: [65536]u8 = undefined;
        var writer: std.Io.Writer = .fixed(&buffer);
        try std.json.Stringify.value(value, .{}, &writer);
        try writer.writeByte('\n');
        const bytes = writer.buffered();
        if (bytes.len > 1024 * 1024 - self.bytes) return error.DescendantLedgerLimit;
        const handle = self.handle orelse return error.DescendantLedgerClosed;
        var offset: usize = 0;
        while (offset < bytes.len) {
            var count: u32 = 0;
            if (w.WriteFile(handle, bytes[offset..].ptr, @intCast(bytes.len - offset), &count, null) == 0 or
                count == 0 or count > bytes.len - offset) return error.DescendantLedgerWrite;
            offset += count; self.bytes += count;
        }
        if (w.FlushFileBuffers(handle) == 0) return error.DescendantLedgerFlush;
    }
    pub fn close(self: *Ledger) !void {
        if (self.handle) |handle| {
            if (w.CloseHandle(handle) == 0) return error.DescendantLedgerClose;
            self.handle = null;
        }
    }
};
