//! Thread-safe native allocation charged to the engine's actual aggregate C
//! memory owner. No worker enters QuickJS or raises either memory ceiling.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
pub const ChargedAllocator = struct {
    owner: ?*anyopaque,
    used: std.atomic.Value(usize) = .init(0),
    const child = std.heap.smp_allocator;
    pub fn init(engine: *js.Engine) ChargedAllocator {
        c.pi_js_retain_memory_owner(engine.native_memory_owner);
        return .{ .owner = engine.native_memory_owner };
    }
    pub fn deinit(self: *ChargedAllocator) void {
        std.debug.assert(self.used.load(.acquire) == 0);
        c.pi_js_release_memory_owner(self.owner);
        self.* = undefined;
    }
    pub fn allocator(self: *ChargedAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn reserve(self: *ChargedAllocator, bytes: usize) bool {
        if (c.pi_js_native_memory_reserve(self.owner, bytes) == 0) return false;
        _ = self.used.fetchAdd(bytes, .release);
        return true;
    }
    fn release(self: *ChargedAllocator, bytes: usize) void {
        const previous = self.used.fetchSub(bytes, .acq_rel);
        std.debug.assert(previous >= bytes);
        c.pi_js_native_memory_release(self.owner, bytes);
    }
    fn alloc(raw: *anyopaque, length: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *ChargedAllocator = @ptrCast(@alignCast(raw));
        if (!self.reserve(length)) return null;
        const result = child.rawAlloc(length, alignment, ra) orelse {
            self.release(length);
            return null;
        };
        return result;
    }
    fn resize(raw: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, length: usize, ra: usize) bool {
        const self: *ChargedAllocator = @ptrCast(@alignCast(raw));
        const extra = length -| bytes.len;
        if (!self.reserve(extra)) return false;
        if (!child.rawResize(bytes, alignment, length, ra)) {
            self.release(extra);
            return false;
        }
        if (length < bytes.len) self.release(bytes.len - length);
        return true;
    }
    fn remap(raw: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, length: usize, ra: usize) ?[*]u8 {
        const self: *ChargedAllocator = @ptrCast(@alignCast(raw));
        const extra = length -| bytes.len;
        if (!self.reserve(extra)) return null;
        const result = child.rawRemap(bytes, alignment, length, ra) orelse {
            self.release(extra);
            return null;
        };
        if (length < bytes.len) self.release(bytes.len - length);
        return result;
    }
    fn free(raw: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, ra: usize) void {
        const self: *ChargedAllocator = @ptrCast(@alignCast(raw));
        child.rawFree(bytes, alignment, ra);
        self.release(bytes.len);
    }
};
