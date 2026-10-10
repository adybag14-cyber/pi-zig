//! Serialize an allocation-failure counter shared by real reader/owner threads.
//! The underlying allocator still receives every allocation and failure index.
const std = @import("std");
pub const Synchronized = struct {
    backing: std.mem.Allocator,
    held: std.atomic.Value(bool) = .init(false),
    pub fn allocator(self: *Synchronized) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn acquire(self: *Synchronized) void {
        while (self.held.cmpxchgWeak(false, true, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
    }
    fn release(self: *Synchronized) void {
        self.held.store(false, .release);
    }
    fn from(raw: *anyopaque) *Synchronized {
        return @ptrCast(@alignCast(raw));
    }
    fn alloc(raw: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self = from(raw);
        self.acquire();
        defer self.release();
        return self.backing.rawAlloc(len, alignment, ra);
    }
    fn resize(raw: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, len: usize, ra: usize) bool {
        const self = from(raw);
        self.acquire();
        defer self.release();
        return self.backing.rawResize(bytes, alignment, len, ra);
    }
    fn remap(raw: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, len: usize, ra: usize) ?[*]u8 {
        const self = from(raw);
        self.acquire();
        defer self.release();
        return self.backing.rawRemap(bytes, alignment, len, ra);
    }
    fn free(raw: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, ra: usize) void {
        const self = from(raw);
        self.acquire();
        defer self.release();
        self.backing.rawFree(bytes, alignment, ra);
    }
};
