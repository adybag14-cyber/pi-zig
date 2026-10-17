//! Real process-console original-mode authority. Mirrors libuv's CONIN$ mode
//! snapshot/reset instead of independently restoring every TTY wrapper close.
//! One bounded process-lifetime native handle, no Engine/JS/Io pointer stored.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const frontend = @import("native_node_tty_frontend_mode.zig");
const w = std.os.windows;
const H = w.HANDLE;
const api = struct {
    extern "kernel32" fn AcquireSRWLockExclusive(*w.SRWLOCK) callconv(.winapi) void;
    extern "kernel32" fn ReleaseSRWLockExclusive(*w.SRWLOCK) callconv(.winapi) void;
    extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, ?*anyopaque, u32, u32, ?H) callconv(.winapi) H;
    extern "kernel32" fn GetConsoleMode(H, *u32) callconv(.winapi) i32;
    extern "kernel32" fn SetConsoleMode(H, u32) callconv(.winapi) i32;
    extern "kernel32" fn GetLastError() callconv(.winapi) u32;
};
var gate: w.SRWLOCK = .{};
var initialized = false;
var input: ?H = null;
var original: ?u32 = null;
var users: usize = 0;
var need_reset = false;
var initialize_error: ?u32 = null;
var reset_error: ?u32 = null;
/// Each actual TTY provider acquires once/releases once at stop. Embedded
/// frontend's validated native original snapshot wins at first initialization;
/// it must not be replaced with a mode already changed by a guest/TUI.
pub fn attach(engine: *v.em.Engine, capability: ?frontend.Snapshot) !void {
    if (capability) |frontend_snapshot| try frontend_snapshot.validate(engine);
    api.AcquireSRWLockExclusive(&gate); defer api.ReleaseSRWLockExclusive(&gate);
    if (users == std.math.maxInt(usize)) return error.NativeTtyModeAuthorityReferences;
    if (!initialized) {
        initialized = true;
        const handle = api.CreateFileW(std.unicode.utf8ToUtf16LeStringLiteral("CONIN$"), 0xc0000000, 1, null, 3, 0, null);
        if (@intFromPtr(handle) == std.math.maxInt(usize)) initialize_error = api.GetLastError() else {
            input = handle;
            var mode: u32 = 0;
            if (api.GetConsoleMode(handle, &mode) != 0) original = if (capability) |frontend_snapshot| frontend_snapshot.original_mode else mode else initialize_error = api.GetLastError();
        }
    }
    users += 1;
}
pub fn markRawVtAttempt() void {
    api.AcquireSRWLockExclusive(&gate); defer api.ReleaseSRWLockExclusive(&gate);
    need_reset = true; // Source marks before its actual RAW_VT SetConsoleMode.
}
pub fn release() void {
    api.AcquireSRWLockExclusive(&gate); defer api.ReleaseSRWLockExclusive(&gate);
    std.debug.assert(users != 0); users -= 1;
    if (users == 0 and need_reset) {
        need_reset = false;
        if (input) |handle| if (original) |mode| {
            // No wrapper close can restore a different live provider's mode.
            // Failed reset remains a real diagnostic, never a fake success.
            if (api.SetConsoleMode(handle, mode) == 0) reset_error = api.GetLastError();
        };
    }
}
pub const Snapshot = struct { providers: usize, has_native_input: bool, original_mode: ?u32, reset_requested: bool, initialize_error: ?u32, reset_error: ?u32 };
pub fn snapshot() Snapshot {
    api.AcquireSRWLockExclusive(&gate); defer api.ReleaseSRWLockExclusive(&gate);
    return .{ .providers = users, .has_native_input = input != null, .original_mode = original, .reset_requested = need_reset, .initialize_error = initialize_error, .reset_error = reset_error };
}
