//! Source WASI clock conversion and deterministic context seed, without global TZ.
const std = @import("std");
pub const Clock = struct {
    started_at: f64,
    now: f64,
    seed: u32,
    pub fn validate(self: Clock) !void {
        if (!std.math.isFinite(self.started_at) or self.started_at < 0) return error.InvalidStartedAt;
        if (!std.math.isFinite(self.now) or self.now < self.started_at) return error.InvalidClock;
    }
    pub fn init(started_at: f64, seed: f64) !Clock {
        if (!std.math.isFinite(started_at) or started_at < 0) return error.InvalidStartedAt;
        if (!std.math.isFinite(seed) or @floor(seed) != seed or seed < 0 or seed > 0xffffffff) return error.InvalidSeed;
        return .{ .started_at = started_at, .now = started_at, .seed = @intFromFloat(seed) };
    }
    pub fn advance(self: *Clock, now: f64) !void {
        if (!std.math.isFinite(now)) return error.InvalidClock;
        self.now = @max(self.now, now);
    }
    pub fn realtime(self: Clock) f64 {
        return @floatFromInt(nanoseconds(self.now) / 1_000_000);
    }
    pub fn elapsed(self: Clock) f64 {
        return @as(f64, @floatFromInt(nanoseconds(self.now - self.started_at))) / 1_000_000;
    }
};

/// Source applies Math.round, converts that exact Number to BigInt, multiplies
/// by 1,000,000 and writes setBigUint64. Extracting the IEEE integer's low bits
/// preserves wrapping for every finite nonnegative input without a u64 cast trap.
fn nanoseconds(milliseconds: f64) u64 {
    const floor = @floor(milliseconds);
    const rounded = floor + @as(f64, if (milliseconds - floor >= 0.5) 1 else 0);
    if (rounded < 1) return 0;
    const bits: u64 = @bitCast(rounded);
    const exponent: i32 = @as(i32, @intCast((bits >> 52) & 0x7ff)) - 1023;
    const significand = (bits & 0x000fffffffffffff) | 0x0010000000000000;
    const low = if (exponent >= 116) @as(u64, 0) else if (exponent >= 52)
        significand << @as(u6, @intCast(exponent - 52))
    else
        significand >> @as(u6, @intCast(52 - exponent));
    return low *% 1_000_000;
}

test "CodeMode virtual clock keeps Source rounding wrapping monotonicity and finite validation" {
    var clock = try Clock.init(1.5, 4294967295);
    try std.testing.expectEqual(@as(f64, 2), clock.realtime());
    try std.testing.expectEqual(@as(f64, 0), clock.elapsed());
    try clock.advance(-1);
    try std.testing.expectEqual(@as(f64, 1.5), clock.now);
    try clock.advance(2);
    try std.testing.expectEqual(@as(f64, 1), clock.elapsed());
    try std.testing.expectError(error.InvalidClock, clock.advance(std.math.inf(f64)));
    try std.testing.expectEqual(@as(u64, 0), nanoseconds(0.49999999999999994));
    try std.testing.expectEqual(@as(u64, 1_000_000), nanoseconds(0.5));
    try std.testing.expectEqual(@as(u64, 0), nanoseconds(0x1p116));
}

test "CodeMode virtual clock matches all 48 actual upstream WASI clock conversions" {
    const source = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("fixtures/codemode-clock-045-source.json"), .{});
    defer source.deinit();
    const Number = struct {
        fn read(value: std.json.Value) f64 {
            return switch (value) {
                .integer => |v| @floatFromInt(v),
                .float => |v| v,
                .number_string => |v| std.fmt.parseFloat(f64, v) catch unreachable,
                else => unreachable,
            };
        }
    };
    const rows = source.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 48), rows.len);
    for (rows, 0..) |row, index| {
        var clock = try Clock.init(Number.read(row.object.get("startedAt").?), Number.read(row.object.get("seed").?));
        if (row.object.get("now")) |now| try clock.advance(Number.read(now));
        const expected = row.object.get("result").?.object.get("value").?.array.items;
        if (clock.realtime() != Number.read(expected[0]) or clock.elapsed() != Number.read(expected[1])) std.debug.print("Clock conversion Source row {d} realtime={d} elapsed={d}\n", .{ index, clock.realtime(), clock.elapsed() });
        try std.testing.expectEqual(Number.read(expected[0]), clock.realtime());
        try std.testing.expectEqual(Number.read(expected[1]), clock.elapsed());
    }
}
