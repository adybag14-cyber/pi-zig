//! Serialize a supplied allocator when a test deliberately shares one failure
//! ledger across an owner VM and worker threads. No allocation is bypassed.
const std = @import("std");
pub const Locked = struct {
    backing: std.mem.Allocator,
    mutex: std.atomic.Mutex = .unlocked,
    fn lock(self: *Locked) void {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
    }
    pub fn allocator(self: *Locked) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, address: usize) ?[*]u8 {
        const self: *Locked = @ptrCast(@alignCast(context));
        self.lock();
        defer self.mutex.unlock();
        return self.backing.rawAlloc(len, alignment, address);
    }
    fn resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, len: usize, address: usize) bool {
        const self: *Locked = @ptrCast(@alignCast(context));
        self.lock();
        defer self.mutex.unlock();
        return self.backing.rawResize(memory, alignment, len, address);
    }
    fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, len: usize, address: usize) ?[*]u8 {
        const self: *Locked = @ptrCast(@alignCast(context));
        self.lock();
        defer self.mutex.unlock();
        return self.backing.rawRemap(memory, alignment, len, address);
    }
    fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, address: usize) void {
        const self: *Locked = @ptrCast(@alignCast(context));
        self.lock();
        defer self.mutex.unlock();
        self.backing.rawFree(memory, alignment, address);
    }
};
