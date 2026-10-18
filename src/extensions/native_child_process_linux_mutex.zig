//! Process-lifetime native mutex. No Engine, allocator, std.Io backend or VM
//! pointer is retained; permanent aligned futex storage is never relocated.
const std = @import("std");
const linux = std.os.linux;
pub const Mutex = struct {
    state: std.atomic.Value(u32) = .init(0),
    pub fn lock(self: *Mutex) void {
        if (self.state.cmpxchgStrong(0, 1, .acquire, .monotonic) == null) return;
        while (true) {
            if (self.state.swap(2, .acquire) == 0) return;
            switch (linux.errno(linux.futex_4arg(&self.state.raw, .{ .cmd = .WAIT, .private = true }, 2, null))) {
                .SUCCESS, .INTR, .AGAIN => {},
                // Valid aligned permanent storage and fixed valid operation
                // cannot yield EINVAL/EFAULT. Never silently enter an unlocked
                // section or turn kernel failure into arbitrary timed polling.
                else => unreachable,
            }
        }
    }
    pub fn unlock(self: *Mutex) void {
        if (self.state.swap(0, .release) == 2) {
            switch (linux.errno(linux.futex_3arg(&self.state.raw, .{ .cmd = .WAKE, .private = true }, 1))) {
                .SUCCESS => {},
                else => unreachable,
            }
        }
    }
};
