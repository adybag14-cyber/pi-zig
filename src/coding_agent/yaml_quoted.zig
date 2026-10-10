//! Native translation of yaml2.9.0 resolve-flow-scalar.doubleQuotedValue.
//! Values remain actual UTF16 units, including isolated escaped surrogates.
const std = @import("std");
pub const Failure = struct { offset: usize, code: []const u8, message: []u16 };
pub const Decoded = struct {
    allocator: std.mem.Allocator,
    value: []u16,
    failure: ?Failure = null,
    pub fn deinit(self: *Decoded) void {
        self.allocator.free(self.value);
        if (self.failure) |failure| self.allocator.free(failure.message);
        self.* = undefined;
    }
};
fn escaped(unit: u16) ?u16 {
    return switch (unit) {
        '0' => 0,
        'a' => 7,
        'b' => 8,
        'e' => 0x1b,
        'f' => 0x0c,
        'n' => '\n',
        'r' => '\r',
        't' => '\t',
        'v' => 0x0b,
        'N' => 0x85,
        '_' => 0xa0,
        'L' => 0x2028,
        'P' => 0x2029,
        ' ', '"', '/', '\\', '\t' => unit,
        else => null,
    };
}
fn errorMessage(allocator: std.mem.Allocator, prefix: []const u8, raw: []const u16) ![]u16 {
    var message: std.ArrayList(u16) = .empty;
    errdefer message.deinit(allocator);
    for (prefix) |byte| try message.append(allocator, byte);
    try message.appendSlice(allocator, raw);
    return message.toOwnedSlice(allocator);
}
pub fn decode(allocator: std.mem.Allocator, source: []const u16) !Decoded {
    var value: std.ArrayList(u16) = .empty;
    errdefer value.deinit(allocator);
    var failure: ?Failure = null;
    errdefer if (failure) |found| allocator.free(found.message);
    var index: usize = 1;
    const stop = source.len -| 1;
    while (index < stop) : (index += 1) {
        const unit = source[index];
        if (unit == '\r' and index + 1 < source.len and source[index + 1] == '\n') continue;
        if (unit == '\n') {
            var count: usize = 0;
            while (index + 1 < source.len) {
                const next = source[index + 1];
                if (next != ' ' and next != '\t' and next != '\n' and next != '\r') break;
                if (next == '\r' and (index + 2 >= source.len or source[index + 2] != '\n')) break;
                if (next == '\n') count += 1;
                index += 1;
            }
            if (count == 0) try value.append(allocator, ' ') else try value.appendNTimes(allocator, '\n', count);
        } else if (unit == '\\') {
            const start = index;
            index += 1;
            const next: ?u16 = if (index < source.len) source[index] else null;
            if (next != null and escaped(next.?) != null) {
                try value.append(allocator, escaped(next.?).?);
            } else if (next != null and (next.? == '\n' or (next.? == '\r' and index + 1 < source.len and source[index + 1] == '\n'))) {
                if (next.? == '\r') index += 1;
                while (index + 1 < source.len and (source[index + 1] == ' ' or source[index + 1] == '\t')) index += 1;
            } else if (next != null and (next.? == 'x' or next.? == 'u' or next.? == 'U')) {
                const count: usize = if (next.? == 'x') 2 else if (next.? == 'u') 4 else 8;
                const digits = source[@min(index + 1, source.len)..@min(index + 1 + count, source.len)];
                var code: u32 = 0;
                var valid = digits.len == count;
                for (digits) |digit| {
                    if (digit > 0x7f) {
                        valid = false;
                        break;
                    }
                    const number = std.fmt.charToDigit(@intCast(digit), 16) catch {
                        valid = false;
                        break;
                    };
                    code = (code << 4) | number;
                }
                if (valid and code <= 0x10ffff) {
                    if (code <= 0xffff) try value.append(allocator, @intCast(code)) else {
                        const supplementary = code - 0x10000;
                        try value.append(allocator, @intCast(0xd800 + (supplementary >> 10)));
                        try value.append(allocator, @intCast(0xdc00 + (supplementary & 1023)));
                    }
                } else {
                    const raw = source[start..@min(source.len, start + count + 2)];
                    if (failure == null) failure = .{ .offset = start, .code = "BAD_DQ_ESCAPE", .message = try errorMessage(allocator, "Invalid escape sequence ", raw) };
                    try value.appendSlice(allocator, raw);
                }
                index += count;
            } else {
                const raw = source[start..@min(source.len, start + 2)];
                if (failure == null) failure = .{ .offset = start, .code = "BAD_DQ_ESCAPE", .message = try errorMessage(allocator, "Invalid escape sequence ", raw) };
                try value.appendSlice(allocator, raw);
            }
        } else if (unit == ' ' or unit == '\t') {
            const start = index;
            while (index + 1 < source.len and (source[index + 1] == ' ' or source[index + 1] == '\t')) index += 1;
            const newline = index + 1 < source.len and (source[index + 1] == '\n' or (source[index + 1] == '\r' and index + 2 < source.len and source[index + 2] == '\n'));
            if (!newline) try value.appendSlice(allocator, source[start .. index + 1]);
        } else try value.append(allocator, unit);
    }
    if ((source.len <= 1 or source[source.len - 1] != '"') and failure == null)
        failure = .{ .offset = source.len, .code = "MISSING_CHAR", .message = try errorMessage(allocator, "Missing closing \"quote", &.{}) };
    return .{ .allocator = allocator, .value = try value.toOwnedSlice(allocator), .failure = failure };
}
