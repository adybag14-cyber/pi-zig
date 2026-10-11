//! yaml2.9.0 timestamp.resolve and JavaScript Date.UTC normalization.
const std = @import("std");
const Cursor = struct {
    bytes: []const u8,
    index: usize = 0,
    fn number(self: *Cursor, minimum: usize, maximum: usize) ?i64 {
        const start = self.index;
        var value: i64 = 0;
        while (self.index < self.bytes.len and self.index - start < maximum and std.ascii.isDigit(self.bytes[self.index])) : (self.index += 1)
            value = value * 10 + self.bytes[self.index] - '0';
        return if (self.index - start >= minimum) value else null;
    }
    fn take(self: *Cursor, byte: u8) bool {
        if (self.index == self.bytes.len or self.bytes[self.index] != byte) return false;
        self.index += 1;
        return true;
    }
};
pub fn resolve(input: []const u8) ?f64 {
    var cursor: Cursor = .{ .bytes = input };
    var year = cursor.number(4, 4) orelse return null;
    if (!cursor.take('-')) return null;
    const month = cursor.number(1, 2) orelse return null;
    if (!cursor.take('-')) return null;
    const day = cursor.number(1, 2) orelse return null;
    var hour: i64 = 0;
    var minute: i64 = 0;
    var second: i64 = 0;
    var milliseconds: i64 = 0;
    var zone: i64 = 0;
    if (cursor.index < input.len) {
        if (!cursor.take('T') and !cursor.take('t')) {
            const start = cursor.index;
            while (cursor.index < input.len and (input[cursor.index] == ' ' or input[cursor.index] == '\t')) cursor.index += 1;
            if (cursor.index == start) return null;
        }
        hour = cursor.number(1, 2) orelse return null;
        if (!cursor.take(':')) return null;
        minute = cursor.number(1, 2) orelse return null;
        if (!cursor.take(':')) return null;
        second = cursor.number(1, 2) orelse return null;
        if (cursor.take('.')) {
            const start = cursor.index;
            while (cursor.index < input.len and std.ascii.isDigit(input[cursor.index])) : (cursor.index += 1) {
                if (cursor.index - start < 3) milliseconds = milliseconds * 10 + input[cursor.index] - '0';
            }
            if (cursor.index == start) return null;
            for (@min(3, cursor.index - start)..3) |_| milliseconds *= 10;
        }
        if (cursor.index < input.len) {
            while (cursor.index < input.len and (input[cursor.index] == ' ' or input[cursor.index] == '\t')) cursor.index += 1;
            if (!cursor.take('Z')) {
                const negative = cursor.take('-');
                if (!negative and !cursor.take('+')) return null;
                const zone_hour = cursor.number(1, 2) orelse return null;
                if (zone_hour > 29) return null;
                zone = zone_hour;
                if (cursor.take(':')) zone = zone * 60 + (cursor.number(2, 2) orelse return null);
                if (negative) zone = -zone;
                // Preserve Source's absolute-value heuristic, including its
                // behavior for offsets such as +00:15. Do not "correct" it.
                if (@abs(zone) < 30) zone *= 60;
            }
        }
    }
    if (cursor.index != input.len) return null;
    if (year >= 0 and year <= 99) year += 1900;
    const month_index = month - 1;
    year += @divFloor(month_index, 12);
    const normalized_month = @mod(month_index, 12) + 1;
    const days = civilDays(year, normalized_month) + day - 1;
    return @floatFromInt(days * 86_400_000 + hour * 3_600_000 + minute * 60_000 + second * 1000 + milliseconds - zone * 60_000);
}
fn civilDays(input_year: i64, month: i64) i64 {
    const year = input_year - @as(i64, if (month <= 2) 1 else 0);
    const era = @divFloor(year, 400);
    const within = year - era * 400;
    const day_of_year = @divFloor(153 * (month + @as(i64, if (month > 2) -3 else 9)) + 2, 5);
    return era * 146097 + within * 365 + @divFloor(within, 4) - @divFloor(within, 100) + day_of_year - 719468;
}
