//! Terminal mouse protocol decoding used by the alternate-screen application.
const std = @import("std");

pub const Button = enum {
    left,
    middle,
    right,
    none,
    wheel_up,
    wheel_down,
    wheel_left,
    wheel_right,
};

pub const Kind = enum { press, release, drag, move, scroll };

pub const Modifiers = packed struct(u8) {
    shift: bool = false,
    alt: bool = false,
    ctrl: bool = false,
    _padding: u5 = 0,
};

pub const Event = struct {
    kind: Kind,
    button: Button,
    x: usize,
    y: usize,
    modifiers: Modifiers = .{},
};

fn parseUnsigned(bytes: []const u8) ?usize {
    if (bytes.len == 0) return null;
    return std.fmt.parseUnsigned(usize, bytes, 10) catch null;
}

fn decodeCode(code_raw: usize, released: bool, x: usize, y: usize) Event {
    const code = code_raw & 0xff;
    const modifiers = Modifiers{
        .shift = (code & 4) != 0,
        .alt = (code & 8) != 0,
        .ctrl = (code & 16) != 0,
    };
    if ((code & 64) != 0) {
        const wheel: Button = switch (code & 3) {
            0 => .wheel_up,
            1 => .wheel_down,
            2 => .wheel_left,
            else => .wheel_right,
        };
        return .{ .kind = .scroll, .button = wheel, .x = x, .y = y, .modifiers = modifiers };
    }
    const motion = (code & 32) != 0;
    const button: Button = switch (code & 3) {
        0 => .left,
        1 => .middle,
        2 => .right,
        else => .none,
    };
    return .{
        .kind = if (released or button == .none) .release else if (motion and button != .none) .drag else if (motion) .move else .press,
        .button = button,
        .x = x,
        .y = y,
        .modifiers = modifiers,
    };
}

/// Decode SGR 1006 (`CSI < Cb ; Cx ; Cy M/m`) and legacy X10 mouse reports.
/// Coordinates are normalized to zero-based terminal cells.
pub fn parse(data: []const u8) ?Event {
    if (std.mem.startsWith(u8, data, "\x1b[<") and data.len >= 7) {
        const final = data[data.len - 1];
        if (final != 'M' and final != 'm') return null;
        var fields = std.mem.splitScalar(u8, data[3 .. data.len - 1], ';');
        const code = parseUnsigned(fields.next() orelse return null) orelse return null;
        const x_raw = parseUnsigned(fields.next() orelse return null) orelse return null;
        const y_raw = parseUnsigned(fields.next() orelse return null) orelse return null;
        if (fields.next() != null or x_raw == 0 or y_raw == 0) return null;
        return decodeCode(code, final == 'm', x_raw - 1, y_raw - 1);
    }
    if (data.len == 6 and std.mem.startsWith(u8, data, "\x1b[M")) {
        if (data[3] < 32 or data[4] < 33 or data[5] < 33) return null;
        const code: usize = data[3] - 32;
        return decodeCode(code, (code & 3) == 3, data[4] - 33, data[5] - 33);
    }
    return null;
}

test "SGR mouse reports buttons drag modifiers release and wheels" {
    const down = parse("\x1b[<0;4;3M").?;
    try std.testing.expectEqual(Kind.press, down.kind);
    try std.testing.expectEqual(Button.left, down.button);
    try std.testing.expectEqual(@as(usize, 3), down.x);
    try std.testing.expectEqual(@as(usize, 2), down.y);

    const drag = parse("\x1b[<52;8;9M").?;
    try std.testing.expectEqual(Kind.drag, drag.kind);
    try std.testing.expect(drag.modifiers.shift and drag.modifiers.ctrl);

    try std.testing.expectEqual(Kind.release, parse("\x1b[<0;4;3m").?.kind);
    try std.testing.expectEqual(Button.wheel_down, parse("\x1b[<65;1;1M").?.button);
}

test "legacy X10 mouse coordinates normalize to zero" {
    const event = parse("\x1b[M !!").?;
    try std.testing.expectEqual(Kind.press, event.kind);
    try std.testing.expectEqual(@as(usize, 0), event.x);
    try std.testing.expectEqual(@as(usize, 0), event.y);
    try std.testing.expect(parse("\x1b[M\x1f!!") == null);
}
