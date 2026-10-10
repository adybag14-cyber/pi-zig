//! Actual framed worker startup with the genuine Source terminal factory.
const std = @import("std");
const runtime_mod = @import("extensions/js_runtime.zig");
const bridge_mod = @import("extensions/process_stream_bridge.zig");
const protocol = @import("extensions/process_stream_protocol.zig");
const Io = std.Io;
const Frontend = struct {
    io: Io,
    input: []const u8,
    mutex: Io.Mutex = .init,
    sink: ?bridge_mod.Sink = null,
    output: std.ArrayList(u8) = .empty,
    errors: std.ArrayList(u8) = .empty,
    sent: bool = false,
    detached: usize = 0,
    fn guard(raw: ?*anyopaque) !void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.detached != 0) return error.ActualProcessFrontendDetached;
    }
    fn metadata(_: ?*anyopaque) !protocol.Metadata {
        return .{ .stdin_tty = false, .stdin_raw = false, .stdout_tty = false, .stderr_tty = false, .columns = null, .rows = null };
    }
    fn control(_: ?*anyopaque, operation: protocol.Control) !void {
        if (operation == .raw_mode) return error.PipeCannotSetRawMode;
    }
    fn write(raw: ?*anyopaque, output: protocol.Output, bytes: []const u8) !void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const destination = if (output == .stdout) &self.output else &self.errors;
        try destination.appendSlice(std.testing.allocator, bytes);
        if (!self.sent and std.mem.indexOf(u8, self.output.items, "SDK_STDIO_READY\n") != null) {
            self.sent = true;
            // These frames arrive BEFORE the parent acknowledges this
            // synchronous write. The guest must not execute them reentrantly.
            // Holding this native-only delivery lock also makes detach join
            // every use of the borrowed runtime sink context.
            const sink = self.sink orelse return error.ProcessSinkNotAttachedBeforeFactory;
            try sink.input(self.input);
            try sink.end();
        }
    }
    fn attach(raw: ?*anyopaque, sink: bridge_mod.Sink) !void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.sink != null) return error.ProcessSinkAlreadyAttached;
        self.sink = sink;
    }
    fn detach(raw: ?*anyopaque, sink: bridge_mod.Sink) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        std.debug.assert(self.sink.?.matches(sink));
        self.sink = null;
        self.detached += 1;
    }
    fn bridge(self: *@This()) bridge_mod.Bridge {
        return .{ .context = self, .guard_fn = guard, .metadata_fn = metadata, .control_fn = control, .write_fn = write, .attach_fn = attach, .detach_fn = detach };
    }
};
fn decode(value: std.json.Value) ![]u8 {
    const bytes = try std.testing.allocator.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(value.string));
    errdefer std.testing.allocator.free(bytes);
    try std.base64.standard.Decoder.decode(bytes, value.string);
    return bytes;
}
test "native process stdio factory startup uses byte-only replies and genuine Source terminal input EOF and output" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var inherited = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer inherited.deinit();
    const binary = inherited.get("PI_NATIVE_STDIO_TEST_BINARY") orelse return error.MissingNativeStdioFixtureBinary;
    var source = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("extensions/fixtures/sdk-process-terminal-startup-original-6fb.json"), .{});
    defer source.deinit();
    const input = try decode(source.value.object.get("inputBase64").?);
    defer gpa.free(input);
    const expected_output = try decode(source.value.object.get("stdoutBase64").?);
    defer gpa.free(expected_output);
    const expected_error = try decode(source.value.object.get("stderrBase64").?);
    defer gpa.free(expected_error);
    var frontend: Frontend = .{ .io = io, .input = input };
    defer frontend.output.deinit(gpa);
    defer frontend.errors.deinit(gpa);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "stdio-factory.mjs", .data = @embedFile("extensions/fixtures/sdk-process-terminal-startup-original-6fb.input.txt") });
    var path: [Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &path);
    const script = try std.fs.path.join(gpa, &.{ path[0..length], "stdio-factory.mjs" });
    defer gpa.free(script);
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try environment.put("PATH", std.fs.path.dirname(binary).?);
    try environment.put("HOME", path[0..length]);
    try environment.put("USERPROFILE", path[0..length]);
    try environment.put("PI_AGENT_DIR", path[0..length]);
    try environment.put("PI_OFFLINE", "1");
    if (inherited.get("SystemRoot")) |value| try environment.put("SystemRoot", value);
    var started = try runtime_mod.Runtime.startNativeGroup(gpa, io, &.{script}, .{ .executable = binary, .environ_map = &environment, .process_bridge = frontend.bridge() });
    var open = true;
    defer if (open) started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    const result = try started.runtime.invokeCommand("stdio-inspect", "", "{}");
    defer gpa.free(result);
    const expected = try decode(source.value.object.get("observationsJsonBase64").?);
    defer gpa.free(expected);
    try std.testing.expectEqualStrings(expected, result);
    started.runtime.deinit();
    open = false;
    try std.testing.expectEqual(@as(usize, 1), frontend.detached);
    try std.testing.expect(frontend.sent);
    try std.testing.expectEqualSlices(u8, expected_output, frontend.output.items);
    try std.testing.expectEqualSlices(u8, expected_error, frontend.errors.items);
}
