//! Actual Node24/libuv legacy Windows console translator. The caller holds
//! the SAME whole-write output lock used by UTF8 decoding and WriteConsoleW.
//! No VM, allocator, worker callback, invented terminal or ANSI passthrough.
const std = @import("std");
const w = std.os.windows;
const H = w.HANDLE;
const resize_error: u32 = @intFromEnum(w.Win32Error.INVALID_PARAMETER);
pub const Coord = extern struct { x: i16, y: i16 };
pub const Rect = extern struct { left: i16, top: i16, right: i16, bottom: i16 };
pub const ScreenInfo = extern struct { size: Coord, cursor: Coord, attributes: u16, window: Rect, maximum: Coord };
pub const CursorInfo = extern struct { size: u32, visible: i32 };
const api = struct {
    extern "kernel32" fn GetConsoleScreenBufferInfo(H, *ScreenInfo) callconv(.winapi) i32;
    extern "kernel32" fn SetConsoleCursorPosition(H, Coord) callconv(.winapi) i32;
    extern "kernel32" fn GetConsoleCursorInfo(H, *CursorInfo) callconv(.winapi) i32;
    extern "kernel32" fn SetConsoleCursorInfo(H, *const CursorInfo) callconv(.winapi) i32;
    extern "kernel32" fn SetConsoleTextAttribute(H, u16) callconv(.winapi) i32;
    extern "kernel32" fn FillConsoleOutputCharacterW(H, u16, u32, Coord, *u32) callconv(.winapi) i32;
    extern "kernel32" fn FillConsoleOutputAttribute(H, u16, u32, Coord, *u32) callconv(.winapi) i32;
    extern "kernel32" fn GetLastError() callconv(.winapi) u32;
};
const normal = 0; const escape = 0x0002; const csi = 0x0004; const st_control = 0x0008;
const ignore = 0x0010; const in_arg = 0x0020; const in_string = 0x0040;
const backslash_seen = 0x0080; const extension = 0x0100; const decscusr = 0x0200;
pub const Move = struct { x: i32, x_relative: bool, y: i32, y_relative: bool };
pub const Action = union(enum) {
    text, skip, flush, reset, move: Move, clear: struct { direction: u16, entire: bool },
    style, save: bool, restore: bool, visible: bool, shape: u16,
};
var virtual_offset: i32 = -1;
var virtual_height: i32 = -1;
var virtual_width: i32 = -1;
var initial_captured = false;
var initial_attributes: u16 = 7;
var initial_cursor: CursorInfo = .{ .size = 25, .visible = 1 };
var initial_fg: i16 = 7; var initial_bg: i16 = 0;
var initial_fg_bright: i16 = 0; var initial_bg_bright: i16 = 0; var initial_inverse: i16 = 0;
pub fn initializeLocked(info: *const ScreenInfo, cursor: *const CursorInfo) void {
    if (!initial_captured) {
        initial_attributes = if (info.attributes == 0) 7 else info.attributes;
        initial_fg = ansiColor(initial_attributes); initial_bg = ansiColor(initial_attributes >> 4);
        initial_fg_bright = @intFromBool(initial_attributes & 8 != 0);
        initial_bg_bright = @intFromBool(initial_attributes & 0x80 != 0);
        initial_inverse = @intFromBool(initial_attributes & 0x4000 != 0);
        initial_cursor = cursor.*; initial_captured = true;
    }
    updateWindow(info);
}
fn ansiColor(bits: u16) i16 { return @as(i16, if (bits & 4 != 0) 1 else 0) | @as(i16, if (bits & 2 != 0) 2 else 0) | @as(i16, if (bits & 1 != 0) 4 else 0); }
fn nativeColor(bits: i16) u16 { return @as(u16, if (bits & 1 != 0) 4 else 0) | @as(u16, if (bits & 2 != 0) 2 else 0) | @as(u16, if (bits & 4 != 0) 1 else 0); }
fn updateWindow(info: *const ScreenInfo) void {
    virtual_width = info.size.x; virtual_height = @as(i32, info.window.bottom) - info.window.top + 1;
    if (virtual_offset == -1) virtual_offset = info.cursor.y else if (virtual_offset < @as(i32, info.cursor.y) - virtual_height + 1) virtual_offset = @as(i32, info.cursor.y) - virtual_height + 1;
    if (virtual_offset + virtual_height > info.size.y) virtual_offset = @as(i32, info.size.y) - virtual_height;
    if (virtual_offset < 0) virtual_offset = 0;
}
fn coordinate(info: *const ScreenInfo, move: Move) Coord {
    updateWindow(info);
    const y = std.math.clamp((if (move.y_relative) @as(i32, info.cursor.y) else virtual_offset) + move.y, virtual_offset, virtual_offset + virtual_height - 1);
    const x = std.math.clamp((if (move.x_relative) @as(i32, info.cursor.x) else 0) + move.x, 0, virtual_width - 1);
    return .{ .x = @intCast(x), .y = @intCast(y) };
}
pub const State = struct {
    parser: u16 = normal,
    argc: u8 = 0,
    argv: [4]u16 = .{0} ** 4,
    saved_position: ?Coord = null,
    saved_attributes: ?u16 = null,
    pub fn feed(self: *State, scalar: u32) Action {
        if (self.parser == normal) {
            if (scalar == 0x1b) { self.parser = escape; return .skip; }
            if (scalar == 0x9b) { self.parser = csi; self.argc = 0; return .skip; }
            return .text;
        }
        if (self.parser == escape) {
            switch (scalar) {
                '[' => { self.parser = csi; self.argc = 0; return .skip; },
                '^', '_', 'P', ']' => { self.parser = st_control; return .skip; },
                0x1b => return .skip,
                'c' => { self.parser = normal; return .reset; },
                '7' => { self.parser = normal; return .{ .save = true }; },
                '8' => { self.parser = normal; return .{ .restore = true }; },
                else => { self.parser = normal; return if (scalar >= '@' and scalar <= '_') .skip else .text; },
            }
        }
        if (self.parser == ignore) { if (scalar >= '@' and scalar <= '~') self.parser = normal; return .skip; }
        if (self.parser == decscusr) {
            if (scalar >= '@' and scalar <= '~') {
                self.parser = normal;
                const kind = if (self.argc != 0) self.argv[0] else 1;
                return if (scalar == 'q' and kind <= 6) .{ .shape = kind } else .skip;
            }
            // Source falls through to ordinary text for this first invalid
            // byte, then ignores subsequent sequence bytes until a final.
            self.parser = ignore; return .text;
        }
        if (self.parser & csi != 0) {
            if (scalar >= '0' and scalar <= '9') {
                if (self.parser & in_arg == 0) {
                    if (self.argc >= self.argv.len) { self.parser = ignore; return .skip; }
                    self.parser |= in_arg; self.argv[self.argc] = @intCast(scalar - '0'); self.argc += 1;
                } else {
                    const value = @as(u32, self.argv[self.argc - 1]) * 10;
                    if (value > 65535) { self.parser = ignore; return .skip; }
                    // Source checks the product before adding the final digit,
                    // then stores unsigned short (65539 consequently wraps).
                    self.argv[self.argc - 1] = @truncate(value + scalar - '0');
                }
                return .skip;
            }
            if (scalar == ';') {
                if (self.parser & in_arg != 0) self.parser &= ~@as(u16, in_arg) else {
                    if (self.argc >= self.argv.len) { self.parser = ignore; return .skip; }
                    self.argv[self.argc] = 0; self.argc += 1;
                }
                return .skip;
            }
            if (scalar == '?' and self.parser & (in_arg | extension) == 0 and self.argc == 0) { self.parser |= extension; return .skip; }
            if (scalar == ' ' and self.parser & extension == 0) { self.parser = decscusr; return .skip; }
            if (scalar >= '@' and scalar <= '~') {
                const extended = self.parser & extension != 0; self.parser = normal;
                if (extended) return if (self.argc == 1 and self.argv[0] == 25 and (scalar == 'l' or scalar == 'h')) .{ .visible = scalar == 'h' } else .skip;
                const first: i32 = if (self.argc != 0) self.argv[0] else 1;
                return switch (scalar) {
                    'A' => .{ .move = .{ .x = 0, .x_relative = true, .y = -first, .y_relative = true } },
                    'B' => .{ .move = .{ .x = 0, .x_relative = true, .y = first, .y_relative = true } },
                    'C' => .{ .move = .{ .x = first, .x_relative = true, .y = 0, .y_relative = true } },
                    'D' => .{ .move = .{ .x = -first, .x_relative = true, .y = 0, .y_relative = true } },
                    'E' => .{ .move = .{ .x = 0, .x_relative = false, .y = first, .y_relative = true } },
                    'F' => .{ .move = .{ .x = 0, .x_relative = false, .y = -first, .y_relative = true } },
                    'G' => .{ .move = .{ .x = if (self.argc != 0 and first != 0) first - 1 else 0, .x_relative = false, .y = 0, .y_relative = true } },
                    'H', 'f' => .{ .move = .{ .x = if (self.argc >= 2 and self.argv[1] != 0) @as(i32, self.argv[1]) - 1 else 0, .x_relative = false, .y = if (self.argc >= 1 and first != 0) first - 1 else 0, .y_relative = false } },
                    'J', 'K' => if (self.argc == 0 or self.argv[0] <= 2) .{ .clear = .{ .direction = if (self.argc != 0) self.argv[0] else 0, .entire = scalar == 'J' } } else .flush,
                    'm' => .style, 's' => .{ .save = false }, 'u' => .{ .restore = false },
                    else => .skip,
                };
            }
            self.parser = ignore; return .skip;
        }
        if (self.parser & st_control != 0) {
            if (self.parser & in_string != 0) {
                if (self.parser & backslash_seen == 0) {
                    if (scalar == '"') self.parser &= ~@as(u16, in_string) else if (scalar == '\\') self.parser |= backslash_seen;
                } else self.parser &= ~@as(u16, backslash_seen);
            } else if (scalar == 7 or (scalar == '\\' and self.parser & escape != 0)) self.parser = normal else if (scalar == 0x1b) self.parser |= escape else if (scalar == '"') {
                self.parser |= in_string; self.parser &= ~@as(u16, escape | backslash_seen);
            } else self.parser &= ~@as(u16, escape);
            return .skip;
        }
        unreachable; // only native parser transitions can reach this field.
    }
    /// Actual synchronous kernel operations. Source style/visibility/shape
    /// helpers intentionally lack the other helpers' prior-error early guard.
    pub fn applyLocked(self: *State, handle: H, action: Action, failure: *?u32) void {
        switch (action) {
            .text, .skip => unreachable,
            .flush => {},
            .move => |move| moveCaret(handle, move, failure),
            .reset => reset(handle, failure),
            .clear => |clear| clearRegion(handle, clear.direction, clear.entire, failure),
            .style => self.setStyle(handle, failure),
            .save => |attributes| self.save(handle, attributes, failure),
            .restore => |attributes| self.restore(handle, attributes, failure),
            .visible, .shape => {
                var cursor: CursorInfo = undefined;
                if (api.GetConsoleCursorInfo(handle, &cursor) == 0) { failure.* = api.GetLastError(); return; }
                switch (action) { .visible => |value| cursor.visible = @intFromBool(value), .shape => |value| cursor.size = if (value == 0) initial_cursor.size else if (value <= 2) 100 else 25, else => unreachable }
                if (api.SetConsoleCursorInfo(handle, &cursor) == 0) failure.* = api.GetLastError();
            },
        }
    }
    fn save(self: *State, handle: H, attributes: bool, failure: *?u32) void {
        if (failure.* != null) return;
        var info: ScreenInfo = undefined;
        if (api.GetConsoleScreenBufferInfo(handle, &info) == 0) { failure.* = api.GetLastError(); return; }
        updateWindow(&info); self.saved_position = .{ .x = info.cursor.x, .y = @intCast(@as(i32, info.cursor.y) - virtual_offset) };
        if (attributes) self.saved_attributes = info.attributes & 0x88;
    }
    fn restore(self: *State, handle: H, attributes: bool, failure: *?u32) void {
        if (failure.* != null) return;
        if (self.saved_position) |position| { moveCaret(handle, .{ .x = position.x, .x_relative = false, .y = position.y, .y_relative = false }, failure); if (failure.* != null) return; }
        if (attributes) if (self.saved_attributes) |saved| {
            var info: ScreenInfo = undefined;
            if (api.GetConsoleScreenBufferInfo(handle, &info) == 0) { failure.* = api.GetLastError(); return; }
            if (api.SetConsoleTextAttribute(handle, (info.attributes & ~@as(u16, 0x88)) | saved) == 0) failure.* = api.GetLastError();
        };
    }
    fn setStyle(self: *State, handle: H, failure: *?u32) void {
        var fg: i16 = -1; var bg: i16 = -1; var fg_bright: i16 = -1; var bg_bright: i16 = -1; var inverse: i16 = -1;
        if (self.argc == 0) { fg = initial_fg; bg = initial_bg; fg_bright = initial_fg_bright; bg_bright = initial_bg_bright; inverse = initial_inverse; }
        for (self.argv[0..self.argc]) |unsigned| {
            const arg: i16 = @bitCast(unsigned);
            switch (arg) {
                0 => { fg = initial_fg; bg = initial_bg; fg_bright = initial_fg_bright; bg_bright = initial_bg_bright; inverse = initial_inverse; },
                1 => fg_bright = 1, 2 => { fg_bright = 0; bg_bright = 0; }, 5 => bg_bright = 1, 7 => inverse = 1,
                21, 22 => fg_bright = 0, 25 => bg_bright = 0, 27 => inverse = 0,
                30...37 => fg = arg - 30, 39 => { fg = initial_fg; fg_bright = initial_fg_bright; },
                40...47 => bg = arg - 40, 49 => { bg = initial_bg; bg_bright = initial_bg_bright; },
                90...97 => { fg_bright = 1; fg = arg - 90; }, 100...107 => { bg_bright = 1; bg = arg - 100; }, else => {},
            }
        }
        if (fg == -1 and bg == -1 and fg_bright == -1 and bg_bright == -1 and inverse == -1) return;
        var info: ScreenInfo = undefined;
        if (api.GetConsoleScreenBufferInfo(handle, &info) == 0) { failure.* = api.GetLastError(); return; }
        if (info.attributes & 0x4000 != 0) flip(&info.attributes);
        if (fg != -1) info.attributes = (info.attributes & ~@as(u16, 7)) | nativeColor(fg);
        if (bg != -1) info.attributes = (info.attributes & ~@as(u16, 0x70)) | (nativeColor(bg) << 4);
        if (fg_bright != -1) info.attributes = (info.attributes & ~@as(u16, 8)) | @as(u16, if (fg_bright != 0) 8 else 0);
        if (bg_bright != -1) info.attributes = (info.attributes & ~@as(u16, 0x80)) | @as(u16, if (bg_bright != 0) 0x80 else 0);
        if (inverse != -1) info.attributes = (info.attributes & ~@as(u16, 0x4000)) | @as(u16, if (inverse != 0) 0x4000 else 0);
        if (info.attributes & 0x4000 != 0) flip(&info.attributes);
        if (api.SetConsoleTextAttribute(handle, info.attributes) == 0) failure.* = api.GetLastError();
    }
};
fn flip(attributes: *u16) void { const fg = attributes.* & 0xf; const bg = attributes.* & 0xf0; attributes.* = (attributes.* & 0xff00) | (fg << 4) | (bg >> 4); }
fn moveCaret(handle: H, move: Move, failure: *?u32) void {
    if (failure.* != null) return;
    while (true) {
        var info: ScreenInfo = undefined;
        // Source accesses uninitialized info after a failed query. Retain the
        // actual failure rather than invent coordinates from undefined bytes.
        if (api.GetConsoleScreenBufferInfo(handle, &info) == 0) { failure.* = api.GetLastError(); return; }
        if (api.SetConsoleCursorPosition(handle, coordinate(&info, move)) != 0) return;
        const failed = api.GetLastError(); if (failed != resize_error) { failure.* = failed; return; }
        // Exact Source resize retry: query fresh real dimensions before retry.
    }
}
fn reset(handle: H, failure: *?u32) void {
    if (failure.* != null) return;
    const origin: Coord = .{ .x = 0, .y = 0 };
    if (api.SetConsoleTextAttribute(handle, initial_attributes) == 0) { failure.* = api.GetLastError(); return; }
    if (api.SetConsoleCursorPosition(handle, origin) == 0) { failure.* = api.GetLastError(); return; }
    while (true) {
        var info: ScreenInfo = undefined;
        if (api.GetConsoleScreenBufferInfo(handle, &info) == 0) { failure.* = api.GetLastError(); return; }
        var written: u32 = 0; const count: u32 = @intCast(@as(i32, info.size.x) * info.size.y);
        if (api.FillConsoleOutputCharacterW(handle, ' ', count, origin, &written) != 0 and api.FillConsoleOutputAttribute(handle, initial_attributes, written, origin, &written) != 0) {
            virtual_offset = 0; updateWindow(&info); break;
        }
        const failed = api.GetLastError(); if (failed != resize_error) { failure.* = failed; return; }
    }
    if (api.SetConsoleCursorInfo(handle, &initial_cursor) == 0) failure.* = api.GetLastError();
}
fn clearRegion(handle: H, direction: u16, entire: bool, failure: *?u32) void {
    if (failure.* != null) return;
    const x1: i32 = 0; const x1r = direction == 0;
    const x2: i32 = if (direction == 1) 0 else 65535; const x2r = direction == 1;
    while (true) {
        var info: ScreenInfo = undefined;
        if (api.GetConsoleScreenBufferInfo(handle, &info) == 0) { failure.* = api.GetLastError(); return; }
        const start = coordinate(&info, .{ .x = x1, .x_relative = x1r, .y = if (entire) x1 else 0, .y_relative = if (entire) x1r else true });
        const end = coordinate(&info, .{ .x = x2, .x_relative = x2r, .y = if (entire) x2 else 0, .y_relative = if (entire) x2r else true });
        const count: u32 = @intCast((@as(i32, end.y) * info.size.x + end.x) - (@as(i32, start.y) * info.size.x + start.x) + 1);
        var written: u32 = 0;
        if (api.FillConsoleOutputCharacterW(handle, ' ', count, start, &written) != 0 and api.FillConsoleOutputAttribute(handle, info.attributes, written, start, &written) != 0) return;
        const failed = api.GetLastError(); if (failed != resize_error) { failure.* = failed; return; }
    }
}
