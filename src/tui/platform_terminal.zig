//! Platform terminal readiness and native Windows console primitives.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
pub const Ready = enum { input, timeout, dead };
pub const win = struct {
    const w = std.os.windows;
    pub const Coord = extern struct { x: i16, y: i16 };
    pub const Rect = extern struct { left: i16, top: i16, right: i16, bottom: i16 };
    pub const BufferInfo = extern struct { size: Coord, cursor: Coord, attributes: u16, window: Rect, maximum: Coord };
    pub extern "kernel32" fn GetConsoleMode(w.HANDLE, *u32) callconv(.winapi) w.BOOL;
    pub extern "kernel32" fn SetConsoleMode(w.HANDLE, u32) callconv(.winapi) w.BOOL;
    pub extern "kernel32" fn GetConsoleCP() callconv(.winapi) u32;
    pub extern "kernel32" fn GetConsoleOutputCP() callconv(.winapi) u32;
    pub extern "kernel32" fn SetConsoleCP(u32) callconv(.winapi) w.BOOL;
    pub extern "kernel32" fn SetConsoleOutputCP(u32) callconv(.winapi) w.BOOL;
    pub extern "kernel32" fn GetConsoleScreenBufferInfo(w.HANDLE, *BufferInfo) callconv(.winapi) w.BOOL;
    pub extern "kernel32" fn WaitForSingleObject(w.HANDLE, u32) callconv(.winapi) u32;
    pub const KeyEvent = extern struct { down: i32, repeats: u16, virtual_key: u16, scan_code: u16, character: u16, modifiers: u32 };
    pub const InputRecord = extern struct { kind: u16, payload: extern union { key: KeyEvent, storage: [4]u32 } };
    pub extern "kernel32" fn PeekConsoleInputW(w.HANDLE, *InputRecord, u32, *u32) callconv(.winapi) w.BOOL;
    pub extern "kernel32" fn ReadConsoleInputW(w.HANDLE, *InputRecord, u32, *u32) callconv(.winapi) w.BOOL;
    pub extern "kernel32" fn ReadConsoleW(w.HANDLE, [*]u16, u32, *u32, ?*anyopaque) callconv(.winapi) w.BOOL;
};

pub const ConsoleInputState = struct {
    bytes: [8192]u8 = undefined,
    length: usize = 0,
    index: usize = 0,
    high: ?u16 = null,

    fn emit(self: *ConsoleInputState, scalar: u21) void {
        const count = std.unicode.utf8Encode(scalar, self.bytes[self.length..][0..4]) catch unreachable;
        self.length += count;
    }
    pub fn feed(self: *ConsoleInputState, units: []const u16) void {
        std.debug.assert(self.index == self.length and units.len <= 2048);
        self.index = 0;
        self.length = 0;
        for (units) |unit| {
            if (self.high) |high| {
                self.high = null;
                if (std.unicode.utf16IsLowSurrogate(unit)) {
                    self.emit(std.unicode.utf16DecodeSurrogatePair(&.{ high, unit }) catch unreachable);
                    continue;
                }
                self.emit(0xfffd);
            }
            if (std.unicode.utf16IsHighSurrogate(unit)) self.high = unit else self.emit(if (std.unicode.utf16IsLowSurrogate(unit)) 0xfffd else unit);
        }
    }
    pub fn take(self: *ConsoleInputState) ?u8 {
        if (self.index == self.length) return null;
        const byte = self.bytes[self.index];
        self.index += 1;
        return byte;
    }
};

// The process has one stdin lease. This state follows that lease between the
// persistent owner and acknowledged modal readers, retaining split surrogates.
var console_input: ConsoleInputState = .{};

pub fn inputBuffered(reader: *Io.File.Reader) bool {
    if (reader.interface.seek < reader.interface.end) return true;
    if (comptime builtin.os.tag == .windows) return console_input.index < console_input.length;
    return false;
}

pub fn pollByte(reader: *Io.File.Reader) !?u8 {
    if (reader.interface.seek < reader.interface.end) return try reader.interface.takeByte();
    if (comptime builtin.os.tag == .windows) {
        const handle = reader.file.handle;
        var mode: u32 = 0;
        if (handle == Io.File.stdin().handle and win.GetConsoleMode(handle, &mode).toBool() and mode & 2 == 0) {
            if (console_input.take()) |byte| return byte;
            switch (try waitInput(0)) {
                .timeout => return null,
                .dead => return error.DeadTerminal,
                .input => {},
            }
            var units: [2048]u16 = undefined;
            var count: u32 = 0;
            if (!win.ReadConsoleW(handle, &units, units.len, &count, null).toBool()) return switch (std.os.windows.GetLastError()) {
                .INVALID_HANDLE, .BROKEN_PIPE => error.DeadTerminal,
                .OPERATION_ABORTED => error.Canceled,
                .ACCESS_DENIED => error.AccessDenied,
                .NOT_ENOUGH_MEMORY => error.SystemResources,
                else => error.ConsoleReadFailed,
            };
            if (count == 0) return error.EndOfStream;
            console_input.feed(units[0..count]);
            return console_input.take();
        }
    }
    return try reader.interface.takeByte();
}

pub fn readByte(reader: *Io.File.Reader) !u8 {
    while (true) {
        if (try pollByte(reader)) |byte| return byte;
        // Bounded polling preserves managed dialog cancellation; direct console
        // reads occur only after an actual character-bearing readiness record.
        try reader.io.sleep(.fromMilliseconds(10), .awake);
    }
}

test "native console decoder preserves split surrogate pairs across stdin owner handoff" {
    var state: ConsoleInputState = .{};
    state.feed(&.{ 'Ω', 0xd83e });
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(std.testing.allocator);
    while (state.take()) |byte| try bytes.append(std.testing.allocator, byte);
    try std.testing.expectEqualStrings("Ω", bytes.items);
    state.feed(&.{ 0xdd8a, 'x', 0xdc00 });
    while (state.take()) |byte| try bytes.append(std.testing.allocator, byte);
    try std.testing.expectEqualStrings("Ω🦊x�", bytes.items);
}
pub fn waitInput(timeout_ms: u32) !Ready {
    if (comptime builtin.os.tag == .windows) {
        // Console handles also signal for resize, mouse, modifier and key-up
        // records. ReadFile consumes translated VT characters and would block
        // on those records, starving the scene mailbox and streaming paints.
        const handle = Io.File.stdin().handle;
        var remaining = timeout_ms;
        while (true) {
            switch (win.WaitForSingleObject(handle, remaining)) {
                258 => return .timeout,
                0 => {},
                else => return error.DeadTerminal,
            }
            var record: win.InputRecord = undefined;
            var count: u32 = 0;
            if (!win.PeekConsoleInputW(handle, &record, 1, &count).toBool()) return error.DeadTerminal;
            if (count == 0) return .timeout;
            if (record.kind == 1 and record.payload.key.down != 0) {
                const key = record.payload.key;
                if (key.character != 0 or (key.virtual_key >= 0x21 and key.virtual_key <= 0x2e) or (key.virtual_key >= 0x70 and key.virtual_key <= 0x87)) return .input;
            }
            if (!win.ReadConsoleInputW(handle, &record, 1, &count).toBool()) return error.DeadTerminal;
            // Never extend the caller's deadline while discarding events.
            remaining = 0;
        }
    } else if (comptime builtin.os.tag == .linux) {
        const linux = std.os.linux;
        var fd: linux.pollfd = .{ .fd = Io.File.stdin().handle, .events = linux.POLL.IN, .revents = 0 };
        const result = linux.poll(@ptrCast(&fd), 1, @intCast(timeout_ms));
        if (linux.errno(result) == .INTR) return .timeout;
        if (linux.errno(result) != .SUCCESS) return error.TerminalPollFailed;
        if (fd.revents & (linux.POLL.HUP | linux.POLL.ERR) != 0) return .dead;
        return if (fd.revents & linux.POLL.IN != 0) .input else .timeout;
    } else if (comptime builtin.os.tag == .macos) {
        var fd: std.posix.pollfd = .{ .fd = Io.File.stdin().handle, .events = std.posix.POLL.IN, .revents = 0 };
        _ = try std.posix.poll(@as(*[1]std.posix.pollfd, @ptrCast(&fd)), @intCast(timeout_ms));
        if (fd.revents & (std.posix.POLL.HUP | std.posix.POLL.ERR) != 0) return .dead;
        return if (fd.revents & std.posix.POLL.IN != 0) .input else .timeout;
    }
    return error.UnsupportedTerminal;
}
