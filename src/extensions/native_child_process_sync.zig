//! Synchronous real-process collection. One bounded input step runs alongside
//! both output drains; no blocking writer task or writer join exists.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const c = js.c;
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const transport = @import("native_child_process_transport.zig");
const options = @import("native_child_process_options.zig");
const Collector = struct {
    gpa: std.mem.Allocator,
    output: [2]std.ArrayList(u8) = .{ .empty, .empty },
    maximum: usize,
    control: *transport.Control,
    overflow: bool = false,
    fn write(raw: *anyopaque, stream: transport.Stream, bytes: []const u8) !void {
        const self: *Collector = @ptrCast(@alignCast(raw));
        try self.output[@intFromEnum(stream)].appendSlice(self.gpa, bytes);
        // Node spawn_sync.cc counts the two output channels together. Zero
        // disables the limit, and the actual received overflow chunk remains.
        if (self.maximum != 0 and self.output[0].items.len +| self.output[1].items.len > self.maximum) {
            self.overflow = true;
            self.control.terminate.store(true, .release);
        }
    }
    fn deinit(self: *Collector) void { for (&self.output) |*output| output.deinit(self.gpa); }
};
fn outputValue(scope: *Scope, config: *const options.Config, index: usize, bytes: []const u8) !c.JSValue {
    if (config.options.stdio[index + 1] == .ignore) return c.pi_js_null();
    if (config.encoding) |encoding| {
        const text = try @import("binary_encoding.zig").decode(scope.engine.gpa, bytes, encoding);
        defer scope.engine.gpa.free(text);
        return scope.text(text);
    }
    return scope.own(try @import("node_buffer.zig").fromBytes(scope.engine, bytes));
}
pub fn errorValue(scope: *Scope, err: anyerror, config: *const options.Config, synchronous: bool) !c.JSValue {
    if (err == error.OutOfMemory) return err;
    // Retained pending kernel ownership is an explicit private native failure,
    // never fabricated Node EIO or evidence of clean process/handle retirement.
    if (err == error.NativeStdinRetirementPending or err == error.NativeStdinRetirementCapacity or err == error.NativeStdinRetirementWatcherFailed or err == error.NativeStdinThreadImpersonationUnsupported) return err;
    const code: []const u8 = switch (err) { error.FileNotFound => "ENOENT", error.AccessDenied, error.PermissionDenied => "EACCES", error.InvalidExe => "EINVAL", error.NativeChildTimedOut => "ETIMEDOUT", error.NativeChildMaxBuffer => "ENOBUFS", error.BrokenPipe => "EPIPE", else => "EIO" };
    const syscall = try std.fmt.allocPrint(scope.engine.gpa, "{s} {s}", .{ if (synchronous) "spawnSync" else "spawn", config.original_file });
    defer scope.engine.gpa.free(syscall);
    const message = try std.fmt.allocPrint(scope.engine.gpa, "{s} {s}", .{ syscall, code });
    defer scope.engine.gpa.free(message);
    const value = try scope.own(try js.builtin(scope.engine, "Error", &.{try scope.text(message)}));
    const errno: i32 = if (std.mem.eql(u8, code, "ENOENT")) (if (builtin.os.tag == .windows) -4058 else -2) else if (std.mem.eql(u8, code, "EACCES")) (if (builtin.os.tag == .windows) -4092 else -13) else if (std.mem.eql(u8, code, "EINVAL")) (if (builtin.os.tag == .windows) -4071 else -22) else if (std.mem.eql(u8, code, "ETIMEDOUT")) (if (builtin.os.tag == .windows) -4039 else -110) else if (std.mem.eql(u8, code, "ENOBUFS")) (if (builtin.os.tag == .windows) -4060 else -105) else if (std.mem.eql(u8, code, "EPIPE")) (if (builtin.os.tag == .windows) -4047 else -32) else (if (builtin.os.tag == .windows) -4070 else -5);
    try scope.put(value, "errno", c.JS_NewInt32(scope.engine.context, errno));
    try scope.put(value, "code", try scope.text(code));
    try scope.put(value, "syscall", try scope.text(syscall));
    try scope.put(value, "path", try scope.text(config.original_file));
    const arguments = try scope.array();
    for (config.argv.items[1..], 0..) |text, index| try scope.index(arguments, @intCast(index), try scope.text(text));
    try scope.put(value, "spawnargs", arguments);
    return value;
}
pub fn run(engine: *js.Engine, config: *options.Config) !c.JSValue {
    // This is a native unsupported boundary, not a fabricated Node spawn EIO
    // or validation error for names Node itself accepts.
    if (builtin.os.tag != .windows) _ = try config.environment.posixMap();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    const io = engine.native_io orelse return error.NativeIoUnavailable;
    var process = transport.Process.spawn(io, engine.gpa, config.argv.items, config.cwd, &config.environment, config.options) catch |err| {
        try scope.put(result, "error", try errorValue(&scope, err, config, true));
        try scope.put(result, "status", c.pi_js_null()); try scope.put(result, "signal", c.pi_js_null()); try scope.put(result, "output", c.pi_js_null());
        try scope.put(result, "pid", c.JS_NewInt32(engine.context, 0)); try scope.put(result, "stdout", c.pi_js_null()); try scope.put(result, "stderr", c.pi_js_null());
        return c.JS_DupValue(engine.context, result);
    };
    var process_owned = true;
    defer if (process_owned) process.deinit(io);
    const identity = process.identity;
    var control: transport.Control = .{ .timeout_ms = config.timeout_ms, .kill_force = config.kill_force, .close_pipes_on_kill = true };
    var collector: Collector = .{ .gpa = engine.gpa, .maximum = config.max_buffer, .control = &control };
    defer collector.deinit();
    process_owned = false;
    const term = try process.run(io, &control, .{ .context = &collector, .write = Collector.write }, config.input orelse &.{});
    const failure: ?anyerror = if (control.timed_out) error.NativeChildTimedOut else if (collector.overflow) error.NativeChildMaxBuffer else process.input.failure;
    if (failure) |err| try scope.put(result, "error", try errorValue(&scope, err, config, true));
    const signalled = term.signal != null or ((control.timed_out or collector.overflow) and control.signal_sent.load(.acquire));
    try scope.put(result, "status", if (signalled) c.pi_js_null() else c.JS_NewInt64(engine.context, term.code));
    const signal: c.JSValue = if (!signalled) c.pi_js_null() else try scope.text(if (config.kill_force or term.signal == 9) "SIGKILL" else "SIGTERM");
    try scope.put(result, "signal", signal);
    const output = try scope.array();
    try scope.index(output, 0, c.pi_js_null());
    const stdout = try outputValue(&scope, config, 0, collector.output[0].items);
    const stderr = try outputValue(&scope, config, 1, collector.output[1].items);
    try scope.index(output, 1, stdout); try scope.index(output, 2, stderr);
    try scope.put(result, "output", output);
    try scope.put(result, "pid", c.JS_NewUint32(engine.context, identity.pid));
    try scope.put(result, "stdout", stdout); try scope.put(result, "stderr", stderr);
    return c.JS_DupValue(engine.context, result);
}
