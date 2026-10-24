// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Complete private CommonJS branch of native BindingData::ReadPackageJSON.
//! The original caller has selected is_esm=false. The general ESM dispatcher
//! remains unregistered until its actual native Ada/FileURLToPath owner exists.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const native = @import("native_node_async_wrap_state.zig");
const bindings = @import("native_node_modules_binding_data.zig");
const values = @import("native_node_package_json_values.zig");
const nearest = @import("native_node_module_nearest_parent.zig");
const permission_error = @import("native_node_permission_error.zig");
const check = @import("native_node_check_failure.zig");
const c = a.c;
const abi = nearest.abi;
pub const NativeInputs = nearest.NativeInputs;
pub const PermissionKeys = permission_error.Keys;

/// Reuses the sealed nearest-parent native-borrow contract without changing
/// that packet. These native owners and keys remain live through error reentry.
fn admit(s: *a.Scope, inputs: NativeInputs) !void {
    try s.pending();
    const env = inputs.environment;
    if (env.context != @as(?*abi.JSContext, @ptrCast(s.engine.context)) or
        env.paths == null or env.map == null or env.trace == null or
        env.process_debug == null)
        return error.ActualModuleNativeEnvironmentRequired;
    const debug = env.process_debug[0];
    if (debug.enabled == null or debug.format_insert == null or
        debug.format_tree_line == null)
        return error.ActualModuleNativeDebugRequired;
    const trace = env.trace[0];
    if ((trace.print_native_stack != 0 and trace.native_stack == null) or
        (trace.print_js_stack != 0 and trace.js_stack == null))
        return error.ActualModuleNativeTraceRequired;
}

const NamespaceCapture = struct {
    engine: *a.v.em.Engine,
    allocator: std.mem.Allocator,
    bytes: ?[:0]u8 = null,
    fn receive(raw: ?*anyopaque, bytes: [*c]const u8,
        length: usize) callconv(.c) void
    {
        const self: *NamespaceCapture = @ptrCast(@alignCast(raw.?));
        self.bytes = self.allocator.dupeZ(u8, bytes[0..length]) catch
            check.heapOutOfMemory(self.engine, null);
    }
};
fn namespaced(s: *a.Scope, allocator: std.mem.Allocator,
    inputs: NativeInputs, path: []const u8) ![:0]u8
{
    var captured: NamespaceCapture = .{ .engine = s.engine, .allocator = allocator };
    const env = inputs.environment;
    const span: abi.PiNodeEnvironmentPathSpan = .{ .data = path.ptr, .length = path.len };
    abi.pi_node_environment_path_to_namespaced(env.paths,
        s.engine.native_memory_owner, @ptrCast(s.engine.context), env.map,
        env.trace, &span, NamespaceCapture.receive, &captured);
    const result = captured.bytes orelse return error.ActualNamespacedPathRequired;
    errdefer allocator.free(result);
    try s.pending();
    // ReadPackageJSON calls ToNamespacedPath directly. It does not restore
    // trailing separators or perform the nearest-parent NormalizePath step.
    return result;
}

fn readBody(s: *a.Scope, registry: *native.Registry, inputs: NativeInputs,
    keys: PermissionKeys, args: []const c.JSValue) !c.JSValue
{
    if (args.len < 1) check.assertion(s.engine, .{
        .file_line = "src/node_modules.cc:258",
        .message = "(args.Length()) >= (1)",
        .function = "node::modules::BindingData::ReadPackageJSON",
    });
    if (!c.JS_IsString(args[0])) check.assertion(s.engine, .{
        .file_line = "src/node_modules.cc:259",
        .message = "args[0]->IsString()",
        .function = "node::modules::BindingData::ReadPackageJSON",
    });
    try s.pending();
    const data = bindings.get(registry) orelse return error.ActualModulesBindingRequired;
    if (try data.environment.requireEngine() != s.engine)
        return error.ActualModulesBindingEngineMismatch;
    // Retain the actual weak-slot target before any native path allocation or
    // inherited Error setter can reenter and grow this native package cache.
    _ = try s.own(a.duplicate(s.engine,
        data.wrapper orelse return error.ActualModulesBindingRetired));
    try admit(s, inputs);
    const actual_keys = try keys.retain(s);
    const allocator = data.packageCache().allocator();
    const path = try values.utf8(s, allocator, args[0]);
    defer allocator.free(path);

    // The original macro always calls the actual native policy; disabled
    // Permission is handled by that owner itself. The resource is the complete
    // original BufferValue bytes, before ToNamespacedPath and any cache read.
    try s.pending();
    const granted = abi.pi_node_permission_is_granted(inputs.permission,
        s.engine.native_memory_owner, inputs.environment,
        abi.PI_NODE_PERMISSION_FS_READ, path.ptr, path.len);
    try s.pending();
    if (granted == 0)
        return permission_error.throwFileSystemRead(s, allocator, actual_keys, path);

    const normalized = try namespaced(s, allocator, inputs, path);
    defer allocator.free(normalized);
    const entry = (try data.getPackageJSON(s, normalized)) orelse
        return c.pi_js_undefined();
    return a.duplicate(s.engine, try values.serialize(s, entry.config.?, entry.path));
}

/// Actual private native consumer for the already-selected CommonJS branch.
/// The caller has already selected is_esm=false; ESM dispatch remains a
/// separate dependency. This leaf is not installed as the general callback.
pub fn readCommonJSPackageJSON(engine: *a.v.em.Engine,
    registry: *native.Registry, inputs: NativeInputs, keys: PermissionKeys,
    args: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, readBody, .{registry, inputs, keys, args});
}
