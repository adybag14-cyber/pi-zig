// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Original node_file.cc CheckOpenPermissions, including its synchronous throw
//! policy when OpenFileHandle has selected an asynchronous request. This helper
//! consumes the caller's already-created/namespaced BufferValue span. It does
//! not select a request, open a descriptor or publish any fs binding.
const a = @import("native_node_argument_values.zig");
const permission_error = @import("native_node_permission_error.zig");
const charged = @import("native_env_charged_allocator.zig");
pub const abi = @cImport({
    @cUndef("_FORTIFY_SOURCE");
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("native_node_permission.h");
    @cInclude("uv.h");
});
pub const PermissionKeys = permission_error.Keys;

/// These are the actual native Environment's Permission, paths, private Map,
/// debug and trace owners. They are borrowed for the complete call, including
/// Error setter reentry. The original caller likewise keeps its BufferValue
/// storage alive until CheckOpenPermissions and any nested error callbacks end.
pub const NativeInputs = struct {
    permission: *abi.PiNodePermission,
    environment: *const abi.PiNodePermissionEnvironment,
};

fn admit(s: *a.Scope, inputs: NativeInputs) !void {
    try s.pending();
    const env = inputs.environment;
    if (env.context != @as(?*abi.JSContext, @ptrCast(s.engine.context)) or
        env.paths == null or env.map == null or env.trace == null or
        env.process_debug == null)
        return error.ActualOpenPermissionEnvironmentRequired;
    const debug = env.process_debug[0];
    if (debug.enabled == null or debug.format_insert == null or
        debug.format_tree_line == null)
        return error.ActualOpenPermissionDebugRequired;
    const trace = env.trace[0];
    if ((trace.print_native_stack != 0 and trace.native_stack == null) or
        (trace.print_js_stack != 0 and trace.js_stack == null))
        return error.ActualOpenPermissionTraceRequired;
}

const Permission = enum { read, write };
fn requireGranted(s: *a.Scope, inputs: NativeInputs, keys: PermissionKeys,
    path: []const u8, comptime permission: Permission) !void
{
    try s.pending();
    // Always enter the actual policy. Its own original enabled_ check decides
    // whether permission enforcement is disabled; there is no cached shortcut.
    const granted = abi.pi_node_permission_is_granted(inputs.permission,
        s.engine.native_memory_owner, inputs.environment,
        if (permission == .read) abi.PI_NODE_PERMISSION_FS_READ
        else abi.PI_NODE_PERMISSION_FS_WRITE, path.ptr, path.len);
    try s.pending();
    if (granted != 0) return;

    // The native message has the real Engine's charged lifetime through every
    // inherited Error setter. No guest allocator/policy supplies the denial.
    var memory = charged.ChargedAllocator.init(s.engine);
    defer memory.deinit();
    _ = try if (permission == .read)
        permission_error.throwFileSystemRead(s, memory.allocator(), keys, path)
    else permission_error.throwFileSystemWrite(s, memory.allocator(), keys, path);
    return error.ActualOpenPermissionDenialDidNotEscape;
}

/// Complete CheckOpenPermissions for the actual platform's libuv flags.
/// Both access-mode comparisons are intentional: malformed mode combinations
/// require both policies. Write-like side effects require write permission even
/// with O_RDONLY, including O_TEMPORARY on Windows. Read denial returns before
/// querying write, and no denial is converted to an FSReqPromise rejection.
pub fn checkOpenPermissions(s: *a.Scope, inputs: NativeInputs,
    keys: PermissionKeys, path: []const u8, flags: c_int) !void
{
    try admit(s, inputs);
    const actual_keys = try keys.retain(s);
    const rwflags = flags &
        (abi.UV_FS_O_RDONLY | abi.UV_FS_O_WRONLY | abi.UV_FS_O_RDWR);
    const write_as_side_effect = flags &
        (abi.UV_FS_O_APPEND | abi.UV_FS_O_CREAT |
         abi.UV_FS_O_TRUNC | abi.UV_FS_O_TEMPORARY);
    if (rwflags != abi.UV_FS_O_WRONLY)
        try requireGranted(s, inputs, actual_keys, path, .read);
    if (rwflags != abi.UV_FS_O_RDONLY or write_as_side_effect != 0)
        try requireGranted(s, inputs, actual_keys, path, .write);
}
