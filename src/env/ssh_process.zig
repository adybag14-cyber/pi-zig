//! Bounded SSH subprocess I/O with concurrent upload and exact child ownership.
const std = @import("std");
const ssh = @import("ssh.zig");
const Io = std.Io;
const ownership = @import("../durable/process_ownership.zig");
pub const Failure = enum { host_key_changed, host_key_unknown, ssh_failed };
pub fn classifyFailure(diagnostics: []const u8) Failure {
    if (std.mem.indexOf(u8, diagnostics, "REMOTE HOST IDENTIFICATION HAS CHANGED") != null) return .host_key_changed;
    if (std.mem.indexOf(u8, diagnostics, "Host key verification failed") != null) return .host_key_unknown;
    if (std.mem.indexOf(u8, diagnostics, "No ") != null and std.mem.indexOf(u8, diagnostics, " host key is known") != null) return .host_key_unknown;
    return .ssh_failed;
}
pub const Options = struct {
    stdin: []const u8 = "",
    strict: bool = true,
    known_hosts_override: ?[]const u8 = null,
    timeout_ms: u64 = 60_000,
    output_limit: usize = 1024 * 1024,
    environ_map: ?*const std.process.Environ.Map = null,
    keep_stdin_open: bool = false,
};
pub const Result = struct {
    gpa: std.mem.Allocator,
    term: std.process.Child.Term,
    stdout: []u8,
    stderr: []u8,
    pub fn deinit(self: *Result) void {
        self.gpa.free(self.stdout);
        self.gpa.free(self.stderr);
    }
    pub fn check(self: *const Result) !void {
        if (self.term == .exited and self.term.exited == 0) return;
        return switch (classifyFailure(self.stderr)) {
            .host_key_changed => error.HostKeyChanged,
            .host_key_unknown => error.HostKeyUnknown,
            .ssh_failed => error.SshFailed,
        };
    }
};
fn upload(io: Io, file: Io.File, bytes: []const u8, close: bool) !void {
    defer if (close) file.close(io);
    try file.writeStreamingAll(io, bytes);
}
pub fn run(gpa: std.mem.Allocator, io: Io, target: ssh.Target, command: []const u8, options: Options) !Result {
    var args = try ssh.arguments(gpa, target, options.strict, options.known_hosts_override);
    defer args.deinit();
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    try argv.append(gpa, target.program);
    try argv.appendSlice(gpa, args.values.items);
    if (std.mem.indexOfScalar(u8, command, 0) != null) return error.InvalidSshArgument;
    try argv.append(gpa, command);
    return runProgram(gpa, io, argv.items, options);
}
pub fn runProgram(gpa: std.mem.Allocator, io: Io, argv: []const []const u8, options: Options) !Result {
    const windows = @import("builtin").os.tag == .windows;
    var child = try std.process.spawn(io, .{ .argv = argv, .environ_map = options.environ_map, .stdin = .pipe, .stdout = .pipe, .stderr = .pipe, .create_no_window = true, .pgid = if (windows) null else 0, .start_suspended = windows });
    errdefer child.kill(io);
    var control = try ownership.Control.init(&child);
    defer control.deinit();
    errdefer control.kill();
    // Detach the stdin file from Child before transferring it to the writer:
    // kill/wait then cannot race a double close against the upload task.
    const input = child.stdin.?;
    child.stdin = null;
    var transferred = false;
    defer if (!transferred or options.keep_stdin_open) input.close(io);
    var writer = try io.concurrent(upload, .{ io, input, options.stdin, !options.keep_stdin_open });
    transferred = true;
    var storage: Io.File.MultiReader.Buffer(2) = undefined;
    var reader: Io.File.MultiReader = undefined;
    reader.init(gpa, io, storage.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer {
        // Break blocked reads/writes by terminating only this unreaped child,
        // then join all I/O before freeing buffers or returning to the caller.
        control.kill();
        child.kill(io);
        reader.deinit();
        _ = writer.cancel(io) catch {};
    }
    const deadline = Io.Clock.awake.now(io).addDuration(.fromMilliseconds(@intCast(@min(options.timeout_ms, std.math.maxInt(i64)))));
    const timeout: Io.Timeout = if (options.timeout_ms == 0) .none else .{ .deadline = .{ .raw = deadline, .clock = .awake } };
    while (reader.fill(4096, timeout)) |_| {
        if (reader.reader(0).buffered().len > options.output_limit or reader.reader(1).buffered().len > options.output_limit) return error.SshOutputTooLarge;
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    }
    try reader.checkAnyError();
    // An SSH process can refuse authentication before accepting the upload.
    // Its exit diagnostics take precedence over a resulting broken pipe.
    // Closed pipes do not prove that the process exited. Peek without reaping
    // so the same deadline and exact group/job still bound this final wait.
    while (try control.peek() == null) {
        if (options.timeout_ms != 0 and Io.Clock.awake.now(io).nanoseconds >= deadline.nanoseconds) return error.Timeout;
        try io.sleep(.fromMilliseconds(5), .awake);
    }
    _ = writer.await(io) catch {};
    const term = try child.wait(io);
    const stdout = try reader.toOwnedSlice(0);
    errdefer gpa.free(stdout);
    const stderr = try reader.toOwnedSlice(1);
    return .{ .gpa = gpa, .term = term, .stdout = stdout, .stderr = stderr };
}
test "SSH failure classification prioritizes changed key and retains unrelated errors" {
    try std.testing.expectEqual(Failure.host_key_changed, classifyFailure("WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!\nHost key verification failed."));
    try std.testing.expectEqual(Failure.host_key_unknown, classifyFailure("No ED25519 host key is known for alias and you have requested strict checking."));
    try std.testing.expectEqual(Failure.host_key_unknown, classifyFailure("Host key verification failed."));
    try std.testing.expectEqual(Failure.ssh_failed, classifyFailure("Permission denied (publickey)."));
}
test "SSH I/O drains both pipes during bounded upload and keeps authentication error precedence" {
    const gpa = std.testing.allocator;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const program = environ.get("PI_TEST_SSH_FIXTURE") orelse return error.SkipZigTest;
    const input = try gpa.alloc(u8, 2 * 1024 * 1024);
    defer gpa.free(input);
    for (input, 0..) |*byte, index| byte.* = @truncate(index);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input, &digest, .{});
    const expected = try std.fmt.allocPrint(gpa, "\n{d}:{s}\n", .{ input.len, std.fmt.bytesToHex(digest, .lower) });
    defer gpa.free(expected);
    var result = try runProgram(gpa, std.testing.io, &.{ program, "upload" }, .{ .stdin = input, .timeout_ms = 10_000 });
    defer result.deinit();
    try result.check();
    try std.testing.expect(std.mem.endsWith(u8, result.stdout, expected));
    try std.testing.expectEqual(@as(usize, 64 * 1024), result.stderr.len);
    var transport = try run(gpa, std.testing.io, .{ .host = "owned-fixture", .known_hosts_file = "private known hosts", .host_key_alias = "fixed", .program = program }, "upload", .{ .stdin = input, .timeout_ms = 10_000 });
    defer transport.deinit();
    try transport.check();
    try std.testing.expect(std.mem.endsWith(u8, transport.stdout, expected));
    var refused = try runProgram(gpa, std.testing.io, &.{ program, "untrusted" }, .{ .stdin = input, .timeout_ms = 10_000 });
    defer refused.deinit();
    try std.testing.expectError(error.HostKeyUnknown, refused.check());
    try std.testing.expectError(error.Timeout, runProgram(gpa, std.testing.io, &.{ program, "timeout" }, .{ .stdin = input, .timeout_ms = 50 }));
    try std.testing.expectError(error.Timeout, runProgram(gpa, std.testing.io, &.{ program, "closed-output" }, .{ .stdin = input, .timeout_ms = 50 }));
    try std.testing.expectError(error.SshOutputTooLarge, runProgram(gpa, std.testing.io, &.{ program, "upload" }, .{ .stdin = input, .output_limit = 16, .timeout_ms = 10_000 }));
    var framed = try runProgram(gpa, std.testing.io, &.{ program, "end-marker" }, .{ .stdin = "YWJj\nPI-ENV-END\n", .keep_stdin_open = true, .timeout_ms = 10_000 });
    defer framed.deinit();
    try framed.check();
    try std.testing.expectEqualStrings("END-MARKER-ACK\n", framed.stdout);
}
