//! Actual libuv1.51 Windows VT/legacy output algorithms, Node24.14 authority.
//! Joyent/Node contributors MIT; original tty.c + notices retained. No VM/JS.
//! This is deliberately not TextEncoder/TextDecoder: libuv accepts overlong and
//! invalid UTF8 scalar encodings and retains incomplete sequences across writes.
const std = @import("std");
const w = std.os.windows;
const H = w.HANDLE;
const legacy = @import("native_node_tty_windows_legacy.zig");
pub const Coord = legacy.Coord;
pub const ScreenInfo = legacy.ScreenInfo;
pub const CursorInfo = legacy.CursorInfo;
const api = struct {
    extern "kernel32" fn AcquireSRWLockExclusive(*w.SRWLOCK) callconv(.winapi) void;
    extern "kernel32" fn ReleaseSRWLockExclusive(*w.SRWLOCK) callconv(.winapi) void;
    extern "kernel32" fn WriteConsoleW(H, [*]const u16, u32, *u32, ?*anyopaque) callconv(.winapi) i32;
    extern "kernel32" fn GetLastError() callconv(.winapi) u32;
    extern "kernel32" fn GetConsoleMode(H, *u32) callconv(.winapi) i32;
    extern "kernel32" fn SetConsoleMode(H, u32) callconv(.winapi) i32;
};
// Actual libuv serializes the entire write buffer set with its process-global
// output lock, not each 8192-unit flush. Canonical sync hook passes the whole
// remaining Source Buffer, including inputs larger than a pipe's64KiB segment.
var output_gate: w.SRWLOCK = .{};
var vt_checked = false;
var vt_supported = false;
pub const maximum_console_units = 8192;
/// Exact once-per-process libuv VT detection and initial style capture, under
/// the whole-console output lock. No failed VT attempt becomes passthrough.
pub fn initialize(handle: H, info: *const ScreenInfo, cursor: *const CursorInfo) bool {
    api.AcquireSRWLockExclusive(&output_gate);
    defer api.ReleaseSRWLockExclusive(&output_gate);
    if (!vt_checked) {
        vt_checked = true;
        var mode: u32 = 0;
        vt_supported = api.GetConsoleMode(handle, &mode) != 0 and api.SetConsoleMode(handle, mode | 4) != 0;
    }
    legacy.initializeLocked(info, cursor);
    return vt_supported;
}
pub fn applyMode(handle: H, mode: u32) ?u32 {
    api.AcquireSRWLockExclusive(&output_gate);
    defer api.ReleaseSRWLockExclusive(&output_gate);
    if (api.SetConsoleMode(handle, mode) == 0) return api.GetLastError();
    return null;
}
pub const Result = struct {
    failure: ?u32 = null,
    /// Full byte acceptance includes native decoder carry, exactly as Source.
    /// On error Source reports UV failure; an unknown input prefix is NOT zero.
    accepted_bytes: ?usize = null,
    /// Continuous input prefix represented by successful prior native flushes.
    /// A failed current native call may have unobserved effects;0 here never
    /// asserts that the console received no data from that failed call.
    confirmed_bytes: usize = 0,
    partial_successful_call: bool = false,
    native_calls: usize = 0,
    requested_utf16_units: u64 = 0,
    reported_written_utf16_units: u64 = 0,
};
pub const Decoder = struct {
    bytes_left: u8 = 0,
    codepoint: u32 = 0,
    previous_eol: u8 = 0,
    legacy_state: legacy.State = .{},
    pub fn writeVtBlocking(self: *Decoder, handle: H, bytes: []const u8) Result {
        return self.writeBlocking(handle, bytes, true);
    }
    /// Caller selects actual observed/cached native VT capability. Both paths
    /// retain decoder/EOL/parser carry and use one lock for the WHOLE write.
    pub fn writeBlocking(self: *Decoder, handle: H, bytes: []const u8, virtual_terminal: bool) Result {
        api.AcquireSRWLockExclusive(&output_gate);
        defer api.ReleaseSRWLockExclusive(&output_gate);
        var result: Result = .{};
        var buffer: [maximum_console_units]u16 = undefined;
        var used: usize = 0;
        var buffered_end: usize = 0;
        var index: usize = 0;
        while (index < bytes.len) {
            const byte = bytes[index];
            var repeat_byte = false;
            if (self.bytes_left == 0) {
                const not_byte = ~byte;
                if (not_byte != 0) {
                    const first_zero: u8 = 7 - @as(u8, @intCast(@clz(not_byte)));
                    if (first_zero == 7) {
                        self.codepoint = byte;
                    } else if (first_zero <= 5) {
                        // first_zero0 needs a shift8, whose mask is zero. C's
                        // integer promotion defines that case before u8 cast.
                        const mask: u32 = @as(u32, 0xff) >> @as(u5, @intCast(8 - first_zero));
                        self.codepoint = mask & byte;
                        self.bytes_left = 6 - first_zero;
                    } else self.codepoint = 0xfffd;
                } else self.codepoint = 0xfffd;
            } else if ((byte & 0xc0) == 0x80) {
                self.bytes_left -= 1;
                self.codepoint = (self.codepoint << 6) | @as(u32, byte & 0x3f);
            } else {
                self.bytes_left = 0;
                self.codepoint = 0xfffd;
                repeat_byte = true; // Source j-- parses this start byte again.
            }
            if (self.bytes_left != 0) { index += 1; continue; }
            const scalar = self.codepoint;
            if (!virtual_terminal) {
                const action = self.legacy_state.feed(scalar);
                if (action != .text) {
                    if (action != .skip) {
                        flush(handle, &buffer, &used, buffered_end, &result);
                        self.legacy_state.applyLocked(handle, action, &result.failure);
                    }
                    if (!repeat_byte) index += 1;
                    continue;
                }
            }
            if (scalar == 0x0a or scalar == 0x0d) {
                if (scalar == 0x0a and self.previous_eol != 0x0d) {
                    ensure(handle, &buffer, &used, buffered_end, 2, &result);
                    buffer[used] = 0x0d; buffer[used + 1] = 0x0a; used += 2;
                } else if (scalar == 0x0d and self.previous_eol == 0x0a) {
                    // Source suppresses CR immediately following LF, including
                    // across separate writes. Do not reset previous_eol here.
                } else {
                    ensure(handle, &buffer, &used, buffered_end, 1, &result);
                    buffer[used] = @truncate(scalar); used += 1;
                }
                self.previous_eol = @truncate(scalar);
            } else if (scalar <= 0xffff) {
                ensure(handle, &buffer, &used, buffered_end, 1, &result);
                buffer[used] = @truncate(scalar); used += 1;
                self.previous_eol = 0;
            } else {
                ensure(handle, &buffer, &used, buffered_end, 2, &result);
                self.codepoint = scalar - 0x10000;
                const reduced = self.codepoint;
                // Match C WCHAR truncation even for accepted invalid scalars.
                buffer[used] = @truncate(reduced / 0x400 + 0xd800);
                buffer[used + 1] = @truncate(reduced % 0x400 + 0xdc00);
                used += 2; self.previous_eol = 0;
            }
            buffered_end = if (repeat_byte) index else index + 1;
            if (!repeat_byte) index += 1;
        }
        flush(handle, &buffer, &used, buffered_end, &result);
        // Source keeps parsing and updates carry even after a native failure;
        // no later WriteConsoleW call follows the first failed native call.
        if (result.failure == null) {
            result.accepted_bytes = bytes.len;
            if (!result.partial_successful_call) result.confirmed_bytes = bytes.len;
        }
        return result;
    }
};
fn ensure(handle: H, buffer: *[maximum_console_units]u16, used: *usize, buffered_end: usize, needed: usize, result: *Result) void {
    if (needed > buffer.len - used.*) flush(handle, buffer, used, buffered_end, result);
}
fn flush(handle: H, buffer: *[maximum_console_units]u16, used: *usize, buffered_end: usize, result: *Result) void {
    if (used.* != 0 and result.failure == null) {
        var written: u32 = 0;
        result.native_calls += 1;
        result.requested_utf16_units +|= used.*;
        if (api.WriteConsoleW(handle, buffer, @intCast(used.*), &written, null) == 0) result.failure = api.GetLastError() else {
            // Pinned libuv uv__tty_emit_text uses the actual BOOL status. Keep
            // the actual count as a diagnostic; do not silently retry/add IO.
            result.reported_written_utf16_units +|= written;
            if (written != used.*) result.partial_successful_call = true;
            if (!result.partial_successful_call) result.confirmed_bytes = buffered_end;
        }
    }
    used.* = 0;
}
