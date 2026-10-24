// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Complete OpenFileHandle argument/path/permission work before GetReqWrap.
//! Actual request selection, tracing, uv dispatch and AfterOpenFileHandle remain
//! callers' subsequent owners. This supplier installs no public fs namespace.
const std = @import("std");
const builtin = @import("builtin");
const a = @import("native_node_argument_values.zig");
const callbacks = @import("native_node_callback_scope.zig");
const buffer = @import("native_node_buffer_value.zig");
const permissions = @import("native_node_fs_open_permissions.zig");
const check = @import("native_node_check_failure.zig");
const c = a.c;
const abi = permissions.abi;

const NamespaceCopy = struct {
    target: *buffer.BufferValue,
    failure: ?anyerror = null,
    called: bool = false,
    fn receive(raw: ?*anyopaque, bytes: [*c]const u8,
        length: usize) callconv(.c) void
    {
        const self: *NamespaceCopy = @ptrCast(@alignCast(raw.?));
        self.called = true;
        self.target.copyFromNative(bytes[0..length]) catch |err| {
            self.failure = err;
        };
    }
};

/// Borrow genuine same-Engine native path/private Map/trace owners through the
/// whole call, including native allocation GC and permission Error reentry.
pub fn toNamespacedPath(s: *a.Scope, path: *buffer.BufferValue,
    environment: *const abi.PiNodePermissionEnvironment) !void
{
    try s.pending();
    if (try path.storage.environment.requireEngine() != s.engine or
        environment.context != @as(?*abi.JSContext, @ptrCast(s.engine.context)) or
        environment.paths == null or environment.map == null or environment.trace == null)
        return error.ActualOpenFileHandlePathEnvironmentRequired;
    const input = path.bytes() orelse return error.ActualOpenFileHandlePathRequired;
    // Original path.cc is a true no-op on POSIX and on an empty Windows path.
    if (builtin.os.tag != .windows or input.len == 0) return;
    var capture: NamespaceCopy = .{ .target = path };
    const span: abi.PiNodeEnvironmentPathSpan = .{ .data = input.ptr, .length = input.len };
    abi.pi_node_environment_path_to_namespaced(environment.paths,
        s.engine.native_memory_owner, @ptrCast(s.engine.context), environment.map,
        environment.trace, &span, NamespaceCopy.receive, &capture);
    try s.pending();
    if (capture.failure) |err| return err;
    if (!capture.called) return error.ActualOpenFileHandleNamespaceCopyRequired;
}

fn int32(s: *a.Scope, value: c.JSValue, comptime position: u8) !c_int {
    const info: check.AssertionInfo = .{
        .file_line = if (position == 1) "src/node_file.cc:2196" else "src/node_file.cc:2199",
        .message = if (position == 1) "args[1]->IsInt32()" else "args[2]->IsInt32()",
        .function = "node::fs::OpenFileHandle",
    };
    if (!c.JS_IsNumber(value)) check.assertion(s.engine, info);
    var number: f64 = 0;
    try s.pending();
    const status = c.JS_ToFloat64(s.engine.context, &number, value);
    try s.pending();
    if (status < 0) return error.ActualOpenFileHandlePrimitiveNumberRequired;
    const negative_zero = number == 0 and (@as(u64, @bitCast(number)) >> 63) != 0;
    if (!std.math.isFinite(number) or @trunc(number) != number or negative_zero or
        number < std.math.minInt(i32) or number > std.math.maxInt(i32))
        check.assertion(s.engine, info);
    return @intFromFloat(number);
}

pub const Arguments = struct {
    path: buffer.BufferValue = .{},
    flags: c_int = 0,
    mode: c_int = 0,

    /// The native callback keeps this stack owner at one address through uv
    /// admission. BufferValue and the genuine native Environment stay alive
    /// across every nested permission Error setter and its native GC.
    pub fn init(self: *Arguments, s: *a.Scope, environment: *callbacks.Environment,
        inputs: permissions.NativeInputs, keys: permissions.PermissionKeys,
        args: []const c.JSValue) !void
    {
        self.* = .{};
        if (args.len < 3) check.assertion(s.engine, .{
            .file_line = "src/node_file.cc:2190", .message = "(argc) >= (3)",
            .function = "node::fs::OpenFileHandle",
        });
        try self.path.init(s, environment, args[0]);
        errdefer self.path.deinit();
        if (self.path.bytes() == null) check.assertion(s.engine, .{
            .file_line = "src/node_file.cc:2193", .message = "(*path) != nullptr",
            .function = "node::fs::OpenFileHandle",
        });
        try toNamespacedPath(s, &self.path, inputs.environment);
        self.flags = try int32(s, args[1], 1);
        self.mode = try int32(s, args[2], 2);
        // Permission denial is synchronous even for the later async route.
        // Do not select or allocate any request before this original check.
        try permissions.checkOpenPermissions(s, inputs, keys,
            self.path.bytes().?, self.flags);
    }
    pub fn deinit(self: *Arguments) void { self.path.deinit(); }
};
