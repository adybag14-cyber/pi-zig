//! Terminal input primitives used by the interactive frontend.
const std = @import("std");
const builtin = @import("builtin");
const rich_keys = @import("keys.zig");
const terminal_text = @import("terminal_text.zig");

pub const progress_keepalive_ms: u64 = 1000;
pub const progress_active_sequence = "\x1b]9;4;3\x07";
pub const progress_clear_sequence = "\x1b]9;4;0\x07";
pub const native_shift_enter_sequence = "\x1b[13;2u";
pub const desired_kitty_keyboard_protocol_flags: u32 = 7;
pub const keyboard_protocol_response_fragment_timeout_ms: u64 = 150;
pub const kitty_keyboard_protocol_query = "\x1b[>7u\x1b[?u\x1b[c";
pub const kitty_keyboard_protocol_pop = "\x1b[<u";
pub const modify_other_keys_enable = "\x1b[>4;2m";
pub const modify_other_keys_disable = "\x1b[>4;0m";
pub const bracketed_paste_enable = "\x1b[?2004h";
pub const bracketed_paste_disable = "\x1b[?2004l";

pub const KeyboardProtocolNegotiation = union(enum) {
    kitty_flags: u32,
    device_attributes,
};

/// Parse the two replies involved in the progressive Kitty negotiation:
/// `CSI ? flags u` and the fallback device-attributes sentinel.
pub fn parseKeyboardProtocolNegotiationSequence(sequence: []const u8) ?KeyboardProtocolNegotiation {
    if (std.mem.startsWith(u8, sequence, "\x1b[?") and std.mem.endsWith(u8, sequence, "u")) {
        const digits = sequence[3 .. sequence.len - 1];
        if (digits.len == 0) return null;
        const flags = std.fmt.parseUnsigned(u32, digits, 10) catch return null;
        return .{ .kitty_flags = flags };
    }
    if (std.mem.startsWith(u8, sequence, "\x1b[?") and std.mem.endsWith(u8, sequence, "c")) {
        const fields = sequence[3 .. sequence.len - 1];
        for (fields) |byte| if (!std.ascii.isDigit(byte) and byte != ';') return null;
        return .device_attributes;
    }
    return null;
}

pub fn isKeyboardProtocolNegotiationPrefix(sequence: []const u8) bool {
    if (std.mem.eql(u8, sequence, "\x1b[")) return true;
    if (!std.mem.startsWith(u8, sequence, "\x1b[?")) return false;
    for (sequence[3..]) |byte| if (!std.ascii.isDigit(byte) and byte != ';') return false;
    return true;
}

pub const NegotiationDecision = union(enum) {
    pending,
    forward: []u8,
    negotiated: KeyboardProtocolNegotiation,
};

/// Reassembles negotiation replies that were split by an unusually short
/// transport/event boundary, without swallowing ordinary CSI input.
pub const KeyboardProtocolNegotiator = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8) = .empty,

    pub fn init(allocator: std.mem.Allocator) KeyboardProtocolNegotiator {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *KeyboardProtocolNegotiator) void {
        self.buffer.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn feed(self: *KeyboardProtocolNegotiator, sequence: []const u8) !NegotiationDecision {
        if (self.buffer.items.len > 0) {
            try self.buffer.appendSlice(self.allocator, sequence);
            if (parseKeyboardProtocolNegotiationSequence(self.buffer.items)) |reply| {
                self.buffer.clearRetainingCapacity();
                return .{ .negotiated = reply };
            }
            if (isKeyboardProtocolNegotiationPrefix(self.buffer.items)) return .pending;
            const forward = try self.allocator.dupe(u8, self.buffer.items);
            self.buffer.clearRetainingCapacity();
            return .{ .forward = forward };
        }
        if (parseKeyboardProtocolNegotiationSequence(sequence)) |reply| return .{ .negotiated = reply };
        if (isKeyboardProtocolNegotiationPrefix(sequence)) {
            try self.buffer.appendSlice(self.allocator, sequence);
            return .pending;
        }
        return .{ .forward = try self.allocator.dupe(u8, sequence) };
    }

    pub fn flush(self: *KeyboardProtocolNegotiator) !?[]u8 {
        if (self.buffer.items.len == 0) return null;
        const owned = try self.allocator.dupe(u8, self.buffer.items);
        self.buffer.clearRetainingCapacity();
        return owned;
    }
};

pub fn normalizeNativeShiftEnterInput(data: []const u8, should_detect: bool, shift_pressed: bool) []const u8 {
    if (should_detect and shift_pressed and std.mem.eql(u8, data, "\r")) return native_shift_enter_sequence;
    return data;
}

pub fn normalizeAppleTerminalInput(data: []const u8, is_apple_terminal: bool, shift_pressed: bool) []const u8 {
    return normalizeNativeShiftEnterInput(data, is_apple_terminal, shift_pressed);
}

pub fn resolveEscapeTimeoutMs(environ: *const std.process.Environ.Map) u64 {
    if (environ.get("PI_TUI_ESC_TIMEOUT")) |configured| {
        const value = std.fmt.parseUnsigned(u64, configured, 10) catch 0;
        if (value > 0) return value;
    }
    if (environ.get("SSH_CONNECTION") != null or environ.get("SSH_TTY") != null) return 100;
    return 10;
}

pub const Dimensions = struct {
    columns: usize,
    rows: usize,
};

pub fn dimensionsFromEnvironment(environ: *const std.process.Environ.Map, fallback: Dimensions) Dimensions {
    var result = fallback;
    if (environ.get("COLUMNS")) |value| {
        const parsed = std.fmt.parseUnsigned(usize, value, 10) catch 0;
        if (parsed > 0) result.columns = std.math.clamp(parsed, @as(usize, 20), @as(usize, 10_000));
    }
    if (environ.get("LINES")) |value| {
        const parsed = std.fmt.parseUnsigned(usize, value, 10) catch 0;
        if (parsed > 0) result.rows = std.math.clamp(parsed, @as(usize, 3), @as(usize, 10_000));
    }
    return result;
}

/// Query the controlling terminal directly on Linux, then fall back to the
/// portable COLUMNS/LINES hints. Zero-sized pseudo-terminal replies are
/// treated as unavailable.
pub fn terminalDimensions(environ: *const std.process.Environ.Map, fallback: Dimensions) Dimensions {
    if (comptime builtin.os.tag == .linux) {
        var size: std.posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
        const linux = std.os.linux;
        const fd: usize = @bitCast(@as(isize, std.Io.File.stdout().handle));
        const result = linux.syscall3(.ioctl, fd, linux.T.IOCGWINSZ, @intFromPtr(&size));
        if (linux.errno(result) == .SUCCESS and size.col > 0 and size.row > 0) {
            return .{ .columns = size.col, .rows = size.row };
        }
    }
    return dimensionsFromEnvironment(environ, fallback);
}

pub fn moveBySequence(buffer: []u8, lines: isize) ![]const u8 {
    if (lines == 0) return buffer[0..0];
    const amount: usize = @intCast(if (lines < 0) -lines else lines);
    return std.fmt.bufPrint(buffer, "\x1b[{d}{c}", .{ amount, if (lines < 0) @as(u8, 'A') else @as(u8, 'B') });
}

pub const hide_cursor = "\x1b[?25l";
pub const show_cursor = "\x1b[?25h";
pub const clear_line = "\x1b[K";
pub const clear_from_cursor = "\x1b[J";
pub const clear_screen = "\x1b[2J\x1b[H";

pub const Key = union(enum) {
    text: u8,
    enter,
    backspace,
    tab,
    escape,
    up,
    down,
    left,
    right,
    home,
    end,
    delete,
    ctrl_c,
    ctrl_d,
    unknown,
};

/// Decode one common terminal key sequence. Returns null when more bytes are needed.
pub fn decodeKey(bytes: []const u8) ?struct { key: Key, consumed: usize } {
    if (bytes.len == 0) return null;
    const b = bytes[0];
    if (b == 3) return .{ .key = .ctrl_c, .consumed = 1 };
    if (b == 4) return .{ .key = .ctrl_d, .consumed = 1 };
    if (b == '\r' or b == '\n') return .{ .key = .enter, .consumed = 1 };
    if (b == 0x7f or b == 0x08) return .{ .key = .backspace, .consumed = 1 };
    if (b == '\t') return .{ .key = .tab, .consumed = 1 };
    if (b != 0x1b) return .{ .key = .{ .text = b }, .consumed = 1 };
    if (bytes.len == 1) return null;
    if (bytes[1] != '[' and bytes[1] != 'O') return .{ .key = .escape, .consumed = 1 };
    if (bytes.len < 3) return null;
    return switch (bytes[2]) {
        'A' => .{ .key = .up, .consumed = 3 },
        'B' => .{ .key = .down, .consumed = 3 },
        'C' => .{ .key = .right, .consumed = 3 },
        'D' => .{ .key = .left, .consumed = 3 },
        'H' => .{ .key = .home, .consumed = 3 },
        'F' => .{ .key = .end, .consumed = 3 },
        '3' => if (bytes.len >= 4 and bytes[3] == '~') .{ .key = .delete, .consumed = 4 } else null,
        else => .{ .key = .unknown, .consumed = 3 },
    };
}

/// Decode a complete rich key sequence, including Kitty CSI-u and
/// xterm modifyOtherKeys input.
pub fn decodeRichKey(bytes: []const u8, options: rich_keys.ParseOptions) ?rich_keys.ParsedKey {
    return rich_keys.parseKeyWithOptions(bytes, options);
}

pub fn visibleWidth(bytes: []const u8) usize {
    return terminal_text.visibleWidth(bytes);
}

test "key decoding" {
    try std.testing.expect(decodeKey("\x1b[A").?.key == .up);
    try std.testing.expect(decodeKey("\x03").?.key == .ctrl_c);
}

test "visible width strips ansi" {
    try std.testing.expectEqual(@as(usize, 3), visibleWidth("\x1b[31mabc\x1b[0m"));
}

/// Resolve the interactive rendering width from the standard COLUMNS hint.
/// Invalid or implausible values fall back rather than making the renderer fail.
pub fn columnsFromEnvironment(environ: *const std.process.Environ.Map, fallback: usize) usize {
    const value = environ.get("COLUMNS") orelse return @max(@as(usize, 20), fallback);
    const parsed = std.fmt.parseUnsigned(usize, value, 10) catch return @max(@as(usize, 20), fallback);
    return std.math.clamp(parsed, @as(usize, 20), @as(usize, 1000));
}

pub const alternate_screen_enter = "\x1b[?1049h\x1b[H\x1b[2J";
pub const alternate_screen_leave = "\x1b[?1049l";

pub fn supportsFullscreen(io: std.Io) bool {
    return (std.Io.File.stdin().isTty(io) catch false) and (std.Io.File.stdout().isTty(io) catch false);
}

pub fn enterAlternateScreen(io: std.Io) !void {
    try std.Io.File.stdout().writeStreamingAll(io, alternate_screen_enter);
}

pub fn leaveAlternateScreen(io: std.Io) !void {
    try std.Io.File.stdout().writeStreamingAll(io, alternate_screen_leave);
}

test "alternate screen sequences use DEC private mode 1049" {
    try std.testing.expect(std.mem.indexOf(u8, alternate_screen_enter, "?1049h") != null);
    try std.testing.expect(std.mem.indexOf(u8, alternate_screen_leave, "?1049l") != null);
}

test "terminal columns use environment with bounded fallback" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try std.testing.expectEqual(@as(usize, 96), columnsFromEnvironment(&env, 96));
    try env.put("COLUMNS", "132");
    try std.testing.expectEqual(@as(usize, 132), columnsFromEnvironment(&env, 80));
    try env.put("COLUMNS", "2");
    try std.testing.expectEqual(@as(usize, 20), columnsFromEnvironment(&env, 80));
}

test "terminal negotiation parser handles Kitty flags and device attributes" {
    const flags = parseKeyboardProtocolNegotiationSequence("\x1b[?7u") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 7), flags.kitty_flags);
    try std.testing.expect(parseKeyboardProtocolNegotiationSequence("\x1b[?1;2c").? == .device_attributes);
    try std.testing.expect(parseKeyboardProtocolNegotiationSequence("\x1b[A") == null);
}

test "terminal negotiation buffer reassembles and safely forwards prefixes" {
    const allocator = std.testing.allocator;
    var negotiation = KeyboardProtocolNegotiator.init(allocator);
    defer negotiation.deinit();
    try std.testing.expect((try negotiation.feed("\x1b[")) == .pending);
    const complete = try negotiation.feed("?7u");
    try std.testing.expectEqual(@as(u32, 7), complete.negotiated.kitty_flags);
    try std.testing.expect((try negotiation.feed("\x1b[")) == .pending);
    const ordinary = try negotiation.feed("A");
    defer allocator.free(ordinary.forward);
    try std.testing.expectEqualStrings("\x1b[A", ordinary.forward);
}

test "escape timeout, dimensions and native Shift Enter follow environment policy" {
    const allocator = std.testing.allocator;
    var environment = std.process.Environ.Map.init(allocator);
    defer environment.deinit();
    try std.testing.expectEqual(@as(u64, 10), resolveEscapeTimeoutMs(&environment));
    try environment.put("SSH_TTY", "/dev/pts/1");
    try std.testing.expectEqual(@as(u64, 100), resolveEscapeTimeoutMs(&environment));
    try environment.put("PI_TUI_ESC_TIMEOUT", "275");
    try environment.put("COLUMNS", "132");
    try environment.put("LINES", "40");
    try std.testing.expectEqual(@as(u64, 275), resolveEscapeTimeoutMs(&environment));
    try std.testing.expectEqual(Dimensions{ .columns = 132, .rows = 40 }, dimensionsFromEnvironment(&environment, .{ .columns = 80, .rows = 24 }));
    try std.testing.expectEqualStrings(native_shift_enter_sequence, normalizeNativeShiftEnterInput("\r", true, true));
    try std.testing.expectEqualStrings("\r", normalizeNativeShiftEnterInput("\r", true, false));
}

test "terminal control constants and relative motion are exact" {
    var buffer: [32]u8 = undefined;
    try std.testing.expectEqualStrings("\x1b[3A", try moveBySequence(&buffer, -3));
    try std.testing.expectEqualStrings("\x1b[4B", try moveBySequence(&buffer, 4));
    try std.testing.expectEqualStrings("", try moveBySequence(&buffer, 0));
    try std.testing.expectEqualStrings("\x1b]9;4;0\x07", progress_clear_sequence);
}
