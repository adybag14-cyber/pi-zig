// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Private modules::BindingData nearest-parent consumers from node_modules.cc.
//! The binding assembler supplies the actual typed Realm registry and native
//! Permission/Environment owners. This file installs no public Module namespace.
const std = @import("std");
const builtin = @import("builtin");
const a = @import("native_node_argument_values.zig");
const native = @import("native_node_async_wrap_state.zig");
const bindings = @import("native_node_modules_binding_data.zig");
const cache = @import("native_node_package_json_cache.zig");
const values = @import("native_node_package_json_values.zig");
const paths = @import("native_node_package_path.zig");
const check = @import("native_node_check_failure.zig");
const c = a.c;
pub const abi = @cImport(@cInclude("native_node_permission.h"));
const Engine = a.v.em.Engine;

/// Required synchronous borrow of the genuine, co-owned native Environment.
/// paths, private MapKVStore, trace and per-process Debug operations stay alive
/// through return, including inherited Error.prototype.code setter reentry.
/// There is no optional policy callback, process-global map or allow default.
pub const NativeInputs = struct {
    permission: *abi.PiNodePermission,
    environment: *const abi.PiNodePermissionEnvironment,

    fn admit(self: NativeInputs, s: *a.Scope) !void {
        try s.pending();
        const env = self.environment;
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
    fn granted(self: NativeInputs, s: *a.Scope, resource: []const u8) !bool {
        try s.pending();
        const result = abi.pi_node_permission_is_granted(self.permission,
            s.engine.native_memory_owner, self.environment,
            abi.PI_NODE_PERMISSION_FS_READ, resource.ptr, resource.len);
        try s.pending();
        return result != 0;
    }
};

fn allocation(engine: *Engine, result: anytype) @TypeOf(result) {
    return result catch |err| {
        if (err == error.OutOfMemory) check.heapOutOfMemory(engine, null);
        return err;
    };
}
const NamespaceCapture = struct {
    engine: *Engine,
    allocator: std.mem.Allocator,
    bytes: ?[:0]u8 = null,

    fn receive(raw: ?*anyopaque, bytes: [*c]const u8,
        length: usize) callconv(.c) void
    {
        const self: *NamespaceCapture = @ptrCast(@alignCast(raw.?));
        // This is owned BufferValue-equivalent storage, not a borrowed native
        // callback span. A real failed native allocation is process-fatal.
        self.bytes = self.allocator.dupeZ(u8, bytes[0..length]) catch
            check.heapOutOfMemory(self.engine, null);
    }
};

/// NormalizePath: test the native preferred separator before ToNamespacedPath,
/// then restore the empty final component removed by Windows PathResolve.
/// BufferValue UTF8 conversion already replaced lone surrogates and kept NUL.
fn normalizePath(s: *a.Scope, allocator: std.mem.Allocator,
    inputs: NativeInputs, input: []const u8) ![:0]u8
{
    const separator: u8 = if (builtin.os.tag == .windows) '\\' else '/';
    const trailing = input.len != 0 and input[input.len - 1] == separator;
    var captured: NamespaceCapture = .{ .engine = s.engine, .allocator = allocator };
    const env = inputs.environment;
    const span: abi.PiNodeEnvironmentPathSpan = .{ .data = input.ptr, .length = input.len };
    abi.pi_node_environment_path_to_namespaced(env.paths,
        s.engine.native_memory_owner, @ptrCast(s.engine.context), env.map,
        env.trace, &span, NamespaceCapture.receive, &captured);
    const normalized = captured.bytes orelse return error.ActualNamespacedPathRequired;
    errdefer allocator.free(normalized);
    try s.pending();
    if (!trailing or
        (normalized.len != 0 and normalized[normalized.len - 1] == separator))
        return normalized;
    const restored = try allocation(s.engine,
        allocator.allocSentinel(u8, normalized.len + 1, 0));
    @memcpy(restored[0..normalized.len], normalized);
    restored[normalized.len] = separator;
    allocator.free(normalized);
    return restored;
}

/// TraverseParent preserves the original ordering: parent, terminal root,
/// live native permission, node_modules boundary, physical/native cached read.
fn traverseParent(s: *a.Scope, data: *bindings.BindingData,
    inputs: NativeInputs, normalized: []const u8) !?*const cache.Entry
{
    const allocator = data.packageCache().allocator();
    const permissions_enabled = abi.pi_node_permission_enabled(inputs.permission) != 0;
    var current = normalized;
    while (true) {
        try s.pending();
        current = paths.parent(current, paths.native);
        if (std.mem.eql(u8, paths.parent(current, paths.native), current))
            return null;
        if (permissions_enabled) {
            const generic = try allocation(s.engine,
                paths.generic(allocator, current, paths.native));
            defer allocator.free(generic);
            if (!try inputs.granted(s, generic)) return null;
        }
        if (std.mem.eql(u8, paths.filename(current, paths.native), "node_modules"))
            return null;
        const joined = try allocation(s.engine,
            paths.appendPackage(allocator, current, paths.native));
        defer allocator.free(joined);
        const package_path = try allocation(s.engine, allocator.dupeZ(u8, joined));
        defer allocator.free(package_path);
        // The found Config has a stable cache-owned address. Invalid Configs
        // throw before another parent is visited and never become cache hits.
        if (try data.getPackageJSON(s, package_path)) |entry| return entry;
    }
}

fn nearestBody(s: *a.Scope, registry: *native.Registry,
    inputs: NativeInputs, args: []const c.JSValue, only_type: bool) !c.JSValue
{
    // Original native CHECKs are not guest TypeErrors or coercion hooks.
    if (args.len < 1) check.assertion(s.engine, .{
        .file_line = if (only_type) "src/node_modules.cc:373" else "src/node_modules.cc:356",
        .message = "(args.Length()) >= (1)",
        .function = if (only_type) "node::modules::BindingData::GetNearestParentPackageJSONType"
            else "node::modules::BindingData::GetNearestParentPackageJSON",
    });
    if (!c.JS_IsString(args[0])) check.assertion(s.engine, .{
        .file_line = if (only_type) "src/node_modules.cc:374" else "src/node_modules.cc:357",
        .message = "args[0]->IsString()",
        .function = if (only_type) "node::modules::BindingData::GetNearestParentPackageJSONType"
            else "node::modules::BindingData::GetNearestParentPackageJSON",
    });
    try s.pending();
    const data = bindings.get(registry) orelse return error.ActualModulesBindingRequired;
    if (try data.environment.requireEngine() != s.engine)
        return error.ActualModulesBindingEngineMismatch;
    // The typed Realm slot is weak. Retain its actual wrapper before path
    // allocation and hold it through serialization and native Error reentry.
    _ = try s.own(a.duplicate(s.engine,
        data.wrapper orelse return error.ActualModulesBindingRetired));
    try inputs.admit(s);
    const allocator = data.packageCache().allocator();
    const input = try values.utf8(s, allocator, args[0]);
    defer allocator.free(input);
    const normalized = try normalizePath(s, allocator, inputs, input);
    defer allocator.free(normalized);
    const entry = (try traverseParent(s, data, inputs, normalized)) orelse
        return c.pi_js_undefined();
    if (only_type) {
        const value = entry.views().type;
        const bytes: [*]const u8 = @ptrCast(value.data);
        return a.duplicate(s.engine, try s.text(bytes[0..value.length]));
    }
    return a.duplicate(s.engine, try values.serialize(s, entry.config.?, entry.path));
}

pub fn getNearestParentPackageJSON(engine: *Engine, registry: *native.Registry,
    inputs: NativeInputs, args: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, nearestBody, .{registry, inputs, args, false});
}
pub fn getNearestParentPackageJSONType(engine: *Engine, registry: *native.Registry,
    inputs: NativeInputs, args: []const c.JSValue) !c.JSValue
{
    return a.expression(engine, nearestBody, .{registry, inputs, args, true});
}
