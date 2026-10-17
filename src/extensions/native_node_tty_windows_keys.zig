//! Node24/libuv Windows raw console input-record translation. Joyent/Node MIT;
//! original tty.c/key table and notices retained. No replacement TextDecoder.
const std = @import("std");
const input = @import("native_node_tty_windows_input_worker.zig");
pub const Feed = enum { ignored, resize, pending };
pub const State = struct {
    high_surrogate: ?u16 = null,
    key: [16]u8 = undefined,
    length: usize = 0,
    offset: usize = 0,
    repeats: u16 = 0,
    pub fn pending(self: *const State) bool { return self.length != 0; }
    /// Caller drains the prior key before consuming another kernel record.
    /// Pending bytes/repeats survive real readable backpressure unchanged.
    pub fn feed(self: *State, record: input.InputRecord) !Feed {
        if (self.pending()) return error.NativeTtyKeyStillPending;
        if (record.kind == 4) return .resize; // WINDOW_BUFFER_SIZE_EVENT
        if (record.kind != 1) return .ignored; // KEY_EVENT
        const key = record.payload.key;
        if (key.down == 0 and (key.virtual_key != 0x12 or key.character == 0)) return .ignored;
        const alt = key.modifiers & 3 != 0;
        const ctrl = key.modifiers & 12 != 0;
        const shift = key.modifiers & 16 != 0;
        if (key.modifiers & 2 != 0 and key.modifiers & 0x100 == 0 and composingKey(key.virtual_key)) return .ignored;
        var used: usize = 0;
        if (key.character != 0) {
            if (key.character >= 0xd800 and key.character < 0xdc00) {
                self.high_surrogate = key.character;
                return .ignored;
            }
            if (alt and !ctrl and key.down != 0) { self.key[0] = 0x1b; used = 1; }
            if (self.high_surrogate) |high| {
                self.high_surrogate = null;
                if (key.character >= 0xdc00 and key.character <= 0xdfff) {
                    const scalar: u21 = 0x10000 + (@as(u21, high - 0xd800) << 10) + (key.character - 0xdc00);
                    used += try std.unicode.wtf8Encode(scalar, self.key[used..][0..4]);
                } else {
                    // uv_utf16_to_wtf8 preserves an unmatched high surrogate;
                    // it does not replace it or swallow the next character.
                    used += try std.unicode.wtf8Encode(@intCast(high), self.key[used..][0..4]);
                    used += try std.unicode.wtf8Encode(@intCast(key.character), self.key[used..][0..4]);
                }
            } else used += try std.unicode.wtf8Encode(@intCast(key.character), self.key[used..][0..4]);
        } else {
            const sequence = functionKey(key.virtual_key, shift, ctrl) orelse return .ignored;
            if (alt) { self.key[0] = 0x1b; used = 1; }
            @memcpy(self.key[used .. used + sequence.len], sequence);
            used += sequence.len;
        }
        self.length = used; self.offset = 0; self.repeats = key.repeats;
        return .pending;
    }
    /// Native bounded delivery. Source decrements the actual WORD repeat count
    /// with unsigned wrap, including an injected0 count. It is never collapsed
    /// to one repeat or discarded to satisfy a host queue bound.
    pub fn drain(self: *State, bytes: []u8) usize {
        var used: usize = 0;
        while (self.length != 0 and used < bytes.len) {
            if (self.offset < self.length) {
                bytes[used] = self.key[self.offset]; used += 1; self.offset += 1;
            } else {
                self.repeats -%= 1;
                if (self.repeats != 0) self.offset = 0 else { self.length = 0; self.offset = 0; }
            }
        }
        // Consuming exactly the last byte leaves Source's repeat bookkeeping
        // pending until the next drive, before any new input record is read.
        return used;
    }
};
fn composingKey(key: u16) bool {
    return switch (key) { 0x2d, 0x23, 0x28, 0x22, 0x25, 0x0c, 0x27, 0x24, 0x26, 0x21, 0x60...0x69 => true, else => false };
}
fn functionKey(key: u16, shift: bool, ctrl: bool) ?[]const u8 {
    const index: usize = if (shift and ctrl) 3 else if (ctrl) 2 else if (shift) 1 else 0;
    const variants: [4][]const u8 = switch (key) {
        0x2d, 0x60 => .{ "\x1b[2~", "\x1b[2;2~", "\x1b[2;5~", "\x1b[2;6~" },
        0x23, 0x61 => .{ "\x1b[4~", "\x1b[4;2~", "\x1b[4;5~", "\x1b[4;6~" },
        0x28, 0x62 => .{ "\x1b[B", "\x1b[1;2B", "\x1b[1;5B", "\x1b[1;6B" },
        0x22, 0x63 => .{ "\x1b[6~", "\x1b[6;2~", "\x1b[6;5~", "\x1b[6;6~" },
        0x25, 0x64 => .{ "\x1b[D", "\x1b[1;2D", "\x1b[1;5D", "\x1b[1;6D" },
        0x0c, 0x65 => .{ "\x1b[G", "\x1b[1;2G", "\x1b[1;5G", "\x1b[1;6G" },
        0x27, 0x66 => .{ "\x1b[C", "\x1b[1;2C", "\x1b[1;5C", "\x1b[1;6C" },
        0x24, 0x67 => .{ "\x1b[1~", "\x1b[1;2~", "\x1b[1;5~", "\x1b[1;6~" },
        0x26, 0x68 => .{ "\x1b[A", "\x1b[1;2A", "\x1b[1;5A", "\x1b[1;6A" },
        0x21, 0x69 => .{ "\x1b[5~", "\x1b[5;2~", "\x1b[5;5~", "\x1b[5;6~" },
        0x2e, 0x6e => .{ "\x1b[3~", "\x1b[3;2~", "\x1b[3;5~", "\x1b[3;6~" },
        0x70 => .{ "\x1b[[A", "\x1b[23~", "\x1b[11^", "\x1b[23^" },
        0x71 => .{ "\x1b[[B", "\x1b[24~", "\x1b[12^", "\x1b[24^" },
        0x72 => .{ "\x1b[[C", "\x1b[25~", "\x1b[13^", "\x1b[25^" },
        0x73 => .{ "\x1b[[D", "\x1b[26~", "\x1b[14^", "\x1b[26^" },
        0x74 => .{ "\x1b[[E", "\x1b[28~", "\x1b[15^", "\x1b[28^" },
        0x75 => .{ "\x1b[17~", "\x1b[29~", "\x1b[17^", "\x1b[29^" },
        0x76 => .{ "\x1b[18~", "\x1b[31~", "\x1b[18^", "\x1b[31^" },
        0x77 => .{ "\x1b[19~", "\x1b[32~", "\x1b[19^", "\x1b[32^" },
        0x78 => .{ "\x1b[20~", "\x1b[33~", "\x1b[20^", "\x1b[33^" },
        0x79 => .{ "\x1b[21~", "\x1b[34~", "\x1b[21^", "\x1b[34^" },
        0x7a => .{ "\x1b[23~", "\x1b[23$", "\x1b[23^", "\x1b[23@" },
        0x7b => .{ "\x1b[24~", "\x1b[24$", "\x1b[24^", "\x1b[24@" },
        else => return null,
    };
    return variants[index];
}
/// Normal ReadConsoleW uses uv_utf16_to_wtf8 for EACH completed native read;
/// unlike raw KEY_EVENT state it has no cross-read high-surrogate cell.
pub fn lineBytes(units: []const u16, output: []u8) !usize {
    if (units.len > output.len / 3) return error.NativeTtyInputBufferTooSmall;
    var used: usize = 0;
    var index: usize = 0;
    while (index < units.len) : (index += 1) {
        const current = units[index];
        if (current >= 0xd800 and current <= 0xdbff and index + 1 < units.len and units[index + 1] >= 0xdc00 and units[index + 1] <= 0xdfff) {
            const scalar: u21 = 0x10000 + (@as(u21, current - 0xd800) << 10) + (units[index + 1] - 0xdc00);
            used += try std.unicode.wtf8Encode(scalar, output[used..][0..4]); index += 1;
        } else {
            // Four-byte scratch is required by utf8Encode's API even when the
            // actual code unit consumes at most3. The caller uses8192 bytes
            // for at most2730 units, retaining two spare native bytes.
            if (output.len - used < 4) {
                var scratch: [4]u8 = undefined;
                const count = try std.unicode.wtf8Encode(@intCast(current), &scratch);
                @memcpy(output[used .. used + count], scratch[0..count]); used += count;
            } else used += try std.unicode.wtf8Encode(@intCast(current), output[used..][0..4]);
        }
    }
    return used;
}
