//! Fixed per-process storage, with scratch reclaimed as a whole between checks.
//! Do not reset a region while any thread/I/O operation still references it.
const std = @import("std");
pub const total_bytes = 256 * 1024 * 1024;
pub const permanent_bytes = 32 * 1024 * 1024;
pub const Storage = struct {
    bytes: []u8,
    permanent: std.heap.FixedBufferAllocator,
    scratch: std.heap.FixedBufferAllocator,
    scratch_leased: bool = false,
    pub fn create() !Storage {
        const bytes = try std.heap.page_allocator.alloc(u8, total_bytes);
        return .{ .bytes = bytes,
            .permanent = std.heap.FixedBufferAllocator.init(bytes[0..permanent_bytes]),
            .scratch = std.heap.FixedBufferAllocator.init(bytes[permanent_bytes..]) };
    }
    pub fn retain(self: *Storage) std.mem.Allocator { return self.permanent.allocator(); }
    /// Only one synchronous validation/phase task owns scratch at a time. Its
    /// full object graph, parsed JSON, maps and callbacks must retire before release.
    pub fn leaseScratch(self: *Storage) !std.mem.Allocator {
        if (self.scratch_leased) return error.ScratchRegionAlreadyLeased;
        self.scratch_leased = true;
        return self.scratch.allocator();
    }
    pub fn releaseScratch(self: *Storage) !void {
        if (!self.scratch_leased) return error.ScratchRegionNotLeased;
        self.scratch.reset();
        self.scratch_leased = false;
    }
    /// Controller must prove every metadata/persistence/sealer/I/O state retired.
    /// Unknown or blocked operations require process exit without freeing storage.
    pub fn close(self: *Storage, all_async_retired: bool) !void {
        if (!all_async_retired or self.scratch_leased) return error.LiveStorageGraphMustRemainAlive;
        std.heap.page_allocator.free(self.bytes);
        self.* = undefined;
    }
};
