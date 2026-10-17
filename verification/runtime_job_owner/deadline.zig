//! No deadline is extended to finish a probe, flush, member or pipe.
const w = @import("win32.zig");
pub const Deadline = struct {
    start_ms: u64,
    hard_ms: u64,
    cutoff_ms: u64,
    worker_cutoff_ms: u64,
    pub fn start() Deadline {
        const now = w.GetTickCount64();
        return .{ .start_ms = now, .hard_ms = now + 900_000, .cutoff_ms = now + 890_000,
            .worker_cutoff_ms = now + 650_000 };
    }
    pub fn inherited(start_ms: u64) !Deadline {
        const now = w.GetTickCount64();
        if (start_ms > now or now - start_ms >= 890000) return error.ExpiredInheritedDeadline;
        return .{ .start_ms = start_ms, .hard_ms = start_ms + 900000, .cutoff_ms = start_ms + 890000,
            .worker_cutoff_ms = start_ms + 650000 };
    }
    pub fn normal(self: Deadline) !void {
        if (w.GetTickCount64() >= self.cutoff_ms) return error.RetirementReserveReached;
    }
    pub fn admitNode(self: Deadline) !u64 {
        const now = w.GetTickCount64();
        if (now >= self.worker_cutoff_ms or self.hard_ms - now < 550_000)
            return error.InsufficientFullNodeBudget;
        return now + 300_000;
    }
    pub fn finalStageEnd(self: Deadline, early_retirement_start_ms: u64) u64 {
        return @min(early_retirement_start_ms + 240000, self.cutoff_ms);
    }
    pub fn regularUntil(self: Deadline, end_ms: u64) Deadline {
        var bounded = self;
        bounded.cutoff_ms = @min(end_ms, self.cutoff_ms);
        return bounded;
    }
    pub fn retirementEnd(self: Deadline) u64 {
        return @min(w.GetTickCount64() + 10_000, self.hard_ms);
    }
    pub fn remaining(end_ms: u64) u32 {
        const now = w.GetTickCount64();
        return @intCast(@min(end_ms -| now, 0xfffffffe));
    }
};

pub fn availablePhysical() !u64 {
    var memory: w.MemoryStatus = @import("std").mem.zeroes(w.MemoryStatus);
    memory.length = @sizeOf(w.MemoryStatus);
    if (w.GlobalMemoryStatusEx(&memory) == 0) return error.MemoryAdmissionUnverifiable;
    return memory.available_physical;
}

pub fn requireFreshMemory() !void {
    if (try availablePhysical() < 16 * 1024 * 1024 * 1024) return error.Fresh16GiBAdmissionDenied;
}

pub fn requirePressureMargin() !void {
    if (try availablePhysical() < 4 * 1024 * 1024 * 1024) return error.PhysicalMemoryPressure;
}
