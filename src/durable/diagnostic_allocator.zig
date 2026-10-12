//! Timing-only pass-through for the ORIGINAL allocator. No allocation policy,
//! return address, alignment, safety option, or stack depth is replaced.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;
pub const Probe = struct {
    backing: Allocator,
    io: std.Io,
    enabled: std.atomic.Value(bool) = .init(false),
    calls: [4]std.atomic.Value(u64) = .{std.atomic.Value(u64).init(0)} ** 4,
    nanoseconds: [4]std.atomic.Value(u64) = .{std.atomic.Value(u64).init(0)} ** 4,
    allocated_bytes: std.atomic.Value(u64) = .init(0),
    pub fn allocator(self: *Probe) Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn begin(self: *Probe) ?i96 {
        return if (self.enabled.load(.acquire)) std.Io.Clock.awake.now(self.io).toNanoseconds() else null;
    }
    fn end(self: *Probe, kind: usize, started: ?i96) void {
        if (started) |stamp| {
            _ = self.calls[kind].fetchAdd(1, .monotonic);
            _ = self.nanoseconds[kind].fetchAdd(@intCast(@max(0, std.Io.Clock.awake.now(self.io).toNanoseconds() - stamp)), .monotonic);
        }
    }
    fn alloc(raw: *anyopaque, length: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
        const self: *Probe = @ptrCast(@alignCast(raw));
        const started = self.begin();
        defer self.end(0, started);
        const result = self.backing.rawAlloc(length, alignment, ret_addr);
        if (started != null and result != null) _ = self.allocated_bytes.fetchAdd(length, .monotonic);
        return result;
    }
    fn resize(raw: *anyopaque, memory: []u8, alignment: Alignment, length: usize, ret_addr: usize) bool {
        const self: *Probe = @ptrCast(@alignCast(raw));
        const started = self.begin();
        defer self.end(1, started);
        return self.backing.rawResize(memory, alignment, length, ret_addr);
    }
    fn remap(raw: *anyopaque, memory: []u8, alignment: Alignment, length: usize, ret_addr: usize) ?[*]u8 {
        const self: *Probe = @ptrCast(@alignCast(raw));
        const started = self.begin();
        defer self.end(2, started);
        return self.backing.rawRemap(memory, alignment, length, ret_addr);
    }
    fn free(raw: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
        const self: *Probe = @ptrCast(@alignCast(raw));
        const started = self.begin();
        defer self.end(3, started);
        self.backing.rawFree(memory, alignment, ret_addr);
    }
    pub fn print(self: *Probe) void {
        std.debug.print("Original allocator profile allocatedBytes={d}; counts/nanoseconds include overlapping worker calls\n", .{self.allocated_bytes.load(.acquire)});
        inline for (.{ "alloc", "resize", "remap", "free" }, 0..) |name, kind| std.debug.print("Original allocator profile operation={s} calls={d} nanoseconds={d}\n", .{ name, self.calls[kind].load(.acquire), self.nanoseconds[kind].load(.acquire) });
    }
};
