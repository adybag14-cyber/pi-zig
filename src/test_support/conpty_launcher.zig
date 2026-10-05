//! Fixture-only launcher inside a private pseudoconsole and owned job.
const std = @import("std");
const builtin = @import("builtin");
const w = std.os.windows;
extern "kernel32" fn SetStdHandle(u32, w.HANDLE) callconv(.winapi) w.BOOL;
extern "kernel32" fn WaitForSingleObject(w.HANDLE, u32) callconv(.winapi) u32;
extern "kernel32" fn GetExitCodeProcess(w.HANDLE, *u32) callconv(.winapi) w.BOOL;
extern "kernel32" fn ExitProcess(u32) callconv(.winapi) noreturn;
extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, ?*w.SECURITY_ATTRIBUTES, u32, u32, ?w.HANDLE) callconv(.winapi) w.HANDLE;

pub fn main(init: std.process.Init) !void {
    if (comptime builtin.os.tag != .windows) return error.UnsupportedConPtyLauncher;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 4) return error.InvalidConPtyLauncherArguments;
    const error_handle: w.HANDLE = @ptrFromInt(try std.fmt.parseInt(usize, args[1], 10));
    const duration = try std.fmt.parseInt(u32, args[2], 10);
    // The parent's pipe stdhandles are deliberately excluded by the handle
    // allowlist. Open only the console created by our pseudoconsole attribute.
    var attributes: w.SECURITY_ATTRIBUTES = .{ .nLength = @sizeOf(w.SECURITY_ATTRIBUTES), .lpSecurityDescriptor = null, .bInheritHandle = .TRUE };
    const input_handle = CreateFileW(std.unicode.utf8ToUtf16LeStringLiteral("CONIN$"), 0xc0000000, 3, &attributes, 3, 0, null);
    if (input_handle == w.INVALID_HANDLE_VALUE) return error.ConPtyInputOpenFailed;
    defer w.CloseHandle(input_handle);
    const output_handle = CreateFileW(std.unicode.utf8ToUtf16LeStringLiteral("CONOUT$"), 0xc0000000, 3, &attributes, 3, 0, null);
    if (output_handle == w.INVALID_HANDLE_VALUE) return error.ConPtyOutputOpenFailed;
    defer w.CloseHandle(output_handle);
    if (!SetStdHandle(@bitCast(@as(i32, -10)), input_handle).toBool() or !SetStdHandle(@bitCast(@as(i32, -11)), output_handle).toBool()) return error.ConPtyConsoleBindFailed;
    if (!SetStdHandle(@bitCast(@as(i32, -12)), error_handle).toBool()) return error.ConPtyStderrFailed;
    const errors: std.Io.File = .{ .handle = error_handle, .flags = .{ .nonblocking = false } };
    defer errors.close(init.io);
    var child = try std.process.spawn(init.io, .{ .argv = args[3..], .stdin = .inherit, .stdout = .inherit, .stderr = .{ .file = errors }, .environ_map = init.environ_map });
    var reaped = false;
    defer if (!reaped) child.kill(init.io);
    const end = std.Io.Clock.awake.now(init.io).toMilliseconds() + duration;
    while (true) {
        const waited = WaitForSingleObject(child.id.?, 10);
        if (waited == 0) break;
        if (waited != 258) return error.ConPtyChildWaitFailed;
        if (std.Io.Clock.awake.now(init.io).toMilliseconds() >= end) return error.ConPtyChildTimeout;
    }
    var native_exit_code: u32 = undefined;
    if (!GetExitCodeProcess(child.id.?, &native_exit_code).toBool()) return error.ConPtyExitCodeFailed;
    _ = try child.wait(init.io);
    reaped = true;
    // Child.Term narrows Windows exit codes to u8. Keep the actual DWORD.
    ExitProcess(native_exit_code);
}
