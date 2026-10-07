//! Source velocity-based wheel scrolling, independent of terminal I/O.
const std = @import("std");
pub const Lines = union(enum) { auto, fixed: f64 };
pub const Accelerator = struct {
    lines: Lines = .auto,
    accelerate: bool = true,
    last_time: f64 = -std.math.inf(f64),
    last_direction: i8 = 0,
    average_gap: ?f64 = null,
    carry: f64 = 0,
    pub fn setLines(self: *Accelerator, lines: Lines) void {
        self.lines = lines;
        self.last_time = -std.math.inf(f64);
        self.last_direction = 0;
        self.average_gap = null;
        self.carry = 0;
    }
    pub fn next(self: *Accelerator, direction: i8, now: f64) f64 {
        if (self.lines == .fixed) return if (std.math.isFinite(self.lines.fixed)) @max(1, @floor(self.lines.fixed)) else 1;
        if (!self.accelerate) return 1;
        const gap = now - self.last_time;
        const same_gesture = direction == self.last_direction and gap <= 200;
        self.last_time = now;
        self.last_direction = direction;
        if (!same_gesture) {
            self.average_gap = null;
            self.carry = 0;
            return 1;
        }
        if (gap < 5) return 1;
        self.average_gap = if (self.average_gap) |previous| (previous + gap) / 2 else gap;
        const lines = @min(6, @max(1, 100 / self.average_gap.?)) + self.carry;
        const whole = @floor(lines);
        self.carry = lines - whole;
        return whole;
    }
};
