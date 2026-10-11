//! Physical POSIX primitive gates. Daemon/client integration is separate.
const std = @import("std");
const builtin = @import("builtin");
extern "c" fn pi_env_pty_spawn(program: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, env: [*:null]const ?[*:0]const u8, cwd: [*:0]const u8, cols: u16, rows: u16, master: *c_int, pid: *c_int) c_int;
extern "c" fn pi_env_pty_resize(master: c_int, cols: u16, rows: u16) c_int;
extern "c" fn pi_env_pty_read(master: c_int, bytes: [*]u8, length: usize) isize;
extern "c" fn pi_env_pty_write(master: c_int, bytes: [*]const u8, length: usize) isize;
extern "c" fn pi_env_pty_peek(pid: c_int, code: *i64) c_int;
extern "c" fn pi_env_pty_foreground(master: c_int) c_int;
extern "c" fn pi_env_pty_kill(pid: c_int) c_int;
extern "c" fn pi_env_pty_reap(pid: c_int) c_int;
extern "c" fn pi_env_pty_close(master: c_int) void;

const Owned = struct {
    master: c_int,
    pid: c_int,
    fn deinit(self: *Owned) void {
        // The unreaped child reserves this exact PID even if it has exited.
        _ = pi_env_pty_kill(self.pid);
        _ = pi_env_pty_reap(self.pid);
        pi_env_pty_close(self.master);
        self.* = undefined;
    }
    fn write(self: Owned, bytes: []const u8) !void {
        const io = std.testing.io;
        const deadline = std.Io.Clock.awake.now(io).addDuration(.fromSeconds(5));
        var offset: usize = 0;
        while (offset < bytes.len) {
            const count = pi_env_pty_write(self.master, bytes[offset..].ptr, bytes.len - offset);
            if (count < -1 or count == 0) return error.TerminalWriteFailed;
            if (count > 0) offset += @intCast(count);
            if (std.Io.Clock.awake.now(io).nanoseconds >= deadline.nanoseconds) return error.TerminalWriteTimeout;
            if (count == -1) try io.sleep(.fromMilliseconds(1), .awake);
        }
    }
    fn collect(self: Owned, bytes: *std.ArrayList(u8)) !i64 {
        const io = std.testing.io;
        const deadline = std.Io.Clock.awake.now(io).addDuration(.fromSeconds(5));
        var buffer: [4096]u8 = undefined;
        var code: i64 = 0;
        var exited = false;
        var ended = false;
        while (!exited or !ended) {
            const count = pi_env_pty_read(self.master, &buffer, buffer.len);
            if (count < -1) return error.TerminalReadFailed;
            if (count > 0) try bytes.appendSlice(std.testing.allocator, buffer[0..@intCast(count)]);
            if (count == 0) ended = true;
            const state = pi_env_pty_peek(self.pid, &code);
            if (state < 0) return error.TerminalWaitFailed;
            exited = state == 1;
            if (std.Io.Clock.awake.now(io).nanoseconds >= deadline.nanoseconds) return error.TerminalReadTimeout;
            if (!exited or !ended) try io.sleep(.fromMilliseconds(1), .awake);
        }
        return code;
    }
};
fn shell() !Owned {
    const argv = [_:null]?[*:0]const u8{ "/bin/sh", "-i" };
    const env = [_:null]?[*:0]const u8{ "TERM=xterm-256color", "PS1=", "PATH=/usr/bin:/bin" };
    var result: Owned = .{ .master = -1, .pid = -1 };
    const status = pi_env_pty_spawn("/bin/sh", &argv, &env, "/", 80, 24, &result.master, &result.pid);
    try std.testing.expectEqual(@as(c_int, 0), status);
    return result;
}
test "POSIX terminal primitive owns a controlling TTY raw bytes resized cells and the unreaped exit" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var terminal = try shell();
    defer terminal.deinit();
    try std.testing.expectEqual(@as(c_int, 0), pi_env_pty_resize(terminal.master, 100, 30));
    try terminal.write("test -t 0 && printf 'TTY-OK\\n'; stty size; printf '\\377\\000RAW\\n'; exit 3\n");
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i64, 3), try terminal.collect(&output));
    try std.testing.expect(std.mem.indexOf(u8, output.items, "TTY-OK\r\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "30 100\r\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\xff\x00RAW\r\n") != null);
    var repeated: i64 = 0;
    try std.testing.expectEqual(@as(c_int, 1), pi_env_pty_peek(terminal.pid, &repeated));
    try std.testing.expectEqual(@as(i64, 3), repeated);
}
test "POSIX terminal primitive reports a foreground job and cancellation preserves the owned root" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var terminal = try shell();
    defer terminal.deinit();
    try terminal.write("sleep 30\n");
    const io = std.testing.io;
    const deadline = std.Io.Clock.awake.now(io).addDuration(.fromSeconds(5));
    var foreground: c_int = 0;
    while (foreground <= 0 or foreground == terminal.pid) {
        foreground = pi_env_pty_foreground(terminal.master);
        if (std.Io.Clock.awake.now(io).nanoseconds >= deadline.nanoseconds) return error.TerminalForegroundTimeout;
        try io.sleep(.fromMilliseconds(1), .awake);
    }
    // Killing the retained session leader hangs up its controlling terminal.
    // EOF also proves that the foreground job released its slave descriptor.
    try std.testing.expectEqual(@as(c_int, 0), pi_env_pty_kill(terminal.pid));
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i64, 137), try terminal.collect(&output));
}
test "POSIX terminal primitive spawn errors do not publish a child or descriptor" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const argv = [_:null]?[*:0]const u8{"/pi-missing-terminal-program"};
    const env = [_:null]?[*:0]const u8{};
    var master: c_int = -1;
    var pid: c_int = -1;
    try std.testing.expect(pi_env_pty_spawn(argv[0].?, &argv, &env, "/", 80, 24, &master, &pid) < 0);
    try std.testing.expectEqual(@as(c_int, -1), master);
    try std.testing.expectEqual(@as(c_int, -1), pid);
}
