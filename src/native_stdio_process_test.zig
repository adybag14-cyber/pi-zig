//! Genuine Source ProcessTerminal over actual standalone SDK process pipes.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
extern fn pi_durable_peek_child(pid: c_int, exit_code: *i64) callconv(.c) c_int;
fn waitOwnedExit(child: *std.process.Child, io: Io) !std.process.Child.Term {
    const deadline = Io.Clock.awake.now(io).toMilliseconds() + 10000;
    while (true) {
        const exited = if (comptime builtin.os.tag == .windows) windows: {
            var timeout: std.os.windows.LARGE_INTEGER = -1;
            break :windows switch (std.os.windows.ntdll.NtWaitForSingleObject(child.id.?, .FALSE, &timeout)) {
                std.os.windows.NTSTATUS.WAIT_0 => true,
                .TIMEOUT => false,
                else => return error.NativeStdioChildStatusFailed,
            };
        } else posix: {
            var exit_code: i64 = 0;
            break :posix switch (pi_durable_peek_child(child.id.?, &exit_code)) {
                0 => false,
                1 => true,
                else => return error.NativeStdioChildStatusFailed,
            };
        };
        if (exited) return child.wait(io);
        if (Io.Clock.awake.now(io).toMilliseconds() >= deadline) return error.NativeStdioChildExitTimeout;
        try io.sleep(.fromMilliseconds(5), .awake);
    }
}
const Capture = struct {
    file: Io.File,
    bytes: std.ArrayList(u8) = .empty,
    ready: Io.Event = .unset,
    done: Io.Event = .unset,
    failure: ?anyerror = null,
    fn run(self: *Capture) void {
        defer self.done.set(std.testing.io);
        var buffer: [4096]u8 = undefined;
        while (true) {
            var vectors = [_][]u8{&buffer};
            const count = self.file.readStreaming(std.testing.io, &vectors) catch |err| {
                if (err != error.EndOfStream) self.failure = err;
                return;
            };
            if (count == 0) return;
            if (self.bytes.items.len + count > 65536) {
                self.failure = error.NativeStdioOutputLimit;
                return;
            }
            self.bytes.appendSlice(std.testing.allocator, buffer[0..count]) catch |err| {
                self.failure = err;
                return;
            };
            if (std.mem.indexOf(u8, self.bytes.items, "SDK_STDIO_READY\n") != null) self.ready.set(std.testing.io);
        }
    }
};
fn decode(gpa: std.mem.Allocator, value: std.json.Value) ![]u8 {
    const encoded = value.string;
    const result = try gpa.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(encoded));
    errdefer gpa.free(result);
    try std.base64.standard.Decoder.decode(result, encoded);
    return result;
}
test "native actual SDK stdio pipes match genuine Source metadata Unicode EOF and binary output" {
    try actualStdioProcess(@embedFile("extensions/fixtures/sdk-actual-stdio-original-6fb.input.txt"), @embedFile("extensions/fixtures/sdk-actual-stdio-original-6fb.json"));
}
test "native actual SDK stdio global input and output survive SDK disposal while original ctx stays stale" {
    try actualStdioProcess(@embedFile("extensions/fixtures/sdk-actual-stdio-sdk-scope-original-6fb.input.txt"), @embedFile("extensions/fixtures/sdk-actual-stdio-sdk-scope-original-6fb.json"));
}
test "native actual SDK stdio pause exits and joins the blocked owned reader with the parent input pipe still open" {
    try actualStdioProcess(@embedFile("extensions/fixtures/sdk-actual-stdio-pause-original-6fb.input.txt"), @embedFile("extensions/fixtures/sdk-actual-stdio-pause-original-6fb.json"));
}
fn actualStdioProcess(script_input: []const u8, golden_source: []const u8) !void {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var inherited = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer inherited.deinit();
    const binary = inherited.get("PI_NATIVE_STDIO_TEST_BINARY") orelse return error.MissingNativeStdioFixtureBinary;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "stdio.mjs", .data = script_input });
    var path: [Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &path);
    const script = try std.fs.path.join(gpa, &.{ path[0..length], "stdio.mjs" });
    defer gpa.free(script);
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try environment.put("PATH", std.fs.path.dirname(binary).?);
    try environment.put("HOME", path[0..length]);
    try environment.put("USERPROFILE", path[0..length]);
    try environment.put("PI_AGENT_DIR", path[0..length]);
    try environment.put("PI_OFFLINE", "1");
    if (inherited.get("SystemRoot")) |root| try environment.put("SystemRoot", root);
    var source = try std.json.parseFromSlice(std.json.Value, gpa, golden_source, .{});
    defer source.deinit();
    const input = try decode(gpa, source.value.object.get("inputBase64").?);
    defer gpa.free(input);
    const expected_output = try decode(gpa, source.value.object.get("stdoutBase64").?);
    defer gpa.free(expected_output);
    const expected_error = try decode(gpa, source.value.object.get("stderrBase64").?);
    defer gpa.free(expected_error);
    var child = try std.process.spawn(io, .{ .argv = &.{ binary, script }, .cwd = .{ .path = path[0..length] }, .environ_map = &environment, .stdin = .pipe, .stdout = .pipe, .stderr = .pipe, .create_no_window = true });
    var reaped = false;
    var output: Capture = .{ .file = child.stdout.? };
    var errors: Capture = .{ .file = child.stderr.? };
    defer output.bytes.deinit(gpa);
    defer errors.bytes.deinit(gpa);
    var readers: Io.Group = .init;
    defer {
        if (!reaped) child.kill(io);
        readers.cancel(io);
        readers.await(io) catch {};
    }
    try readers.concurrent(io, Capture.run, .{&output});
    try readers.concurrent(io, Capture.run, .{&errors});
    try output.ready.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(10), .clock = .awake } });
    try child.stdin.?.writeStreamingAll(io, input);
    const close_input = if (source.value.object.get("closeInput")) |value| value.bool else true;
    if (close_input) {
        child.stdin.?.close(io);
        child.stdin = null;
    }
    try output.done.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(10), .clock = .awake } });
    try errors.done.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(10), .clock = .awake } });
    try readers.await(io);
    const term = try waitOwnedExit(&child, io);
    reaped = true;
    if (term != .exited or term.exited != 0) std.debug.print("Actual stdio child failed; stderr={s}\n", .{errors.bytes.items});
    try std.testing.expect(term == .exited and term.exited == 0);
    if (output.failure) |err| return err;
    if (errors.failure) |err| return err;
    try std.testing.expectEqualSlices(u8, expected_output, output.bytes.items);
    try std.testing.expectEqualSlices(u8, expected_error, errors.bytes.items);
}
