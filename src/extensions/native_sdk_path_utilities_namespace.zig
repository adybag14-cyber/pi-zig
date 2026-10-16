//! Actual coding-agent utils/paths.ts public namespace over the real native
//! Source bodies and one captured node:fs realpathSync binding.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const c = js.c;
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const source = @import("native_sdk_source_paths.zig");
const functions = @import("native_node_function.zig");
const Method = enum { canonicalizePath, getFileRevision, isLocalPath, normalizeWindowsShellPath, normalizePath, resolvePath, getCwdRelativePath, formatPathRelativeToCwdOrAbsolute };
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
pub fn create(engine: *em.Engine, actual_filesystem: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const canonical = try scope.get(actual_filesystem, "realpathSync");
    if (!c.JS_IsFunction(engine.context, canonical)) return error.RequiredActualSdkRealpath;
    const result = try scope.object();
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const method: Method = @enumFromInt(field.value);
        const Adapter = struct {
            fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                return dispatch(host, args, roots, method);
            }
        };
        const length: c_int = switch (method) {
            .getCwdRelativePath, .formatPathRelativeToCwdOrAbsolute => 2,
            else => 1,
        };
        try scope.put(result, field.name, try scope.own(try functions.create(engine, field.name, length, Adapter.call, &.{canonical})));
    }
    return c.JS_DupValue(engine.context, result);
}
/// Complete the actual paths namespace for PackageManager using its captured
/// process and utils/child-process.ts binding. The application supplies these
/// real inputs once; namespace assembly neither launches nor simulates a child.
pub fn createWithPlatform(engine: *em.Engine, actual_filesystem: c.JSValue, actual_process: c.JSValue, spawn_process_sync: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.own(try create(engine, actual_filesystem));
    const mark = try scope.own(try @import("native_sdk_path_cloud_sync.zig").create(engine, actual_process, spawn_process_sync));
    try @import("native_sdk_package_data.zig").put(engine, result, "markPathIgnoredByCloudSync", mark);
    return c.JS_DupValue(engine.context, result);
}
fn canonicalize(engine: *em.Engine, function: c.JSValue, input: c.JSValue) !c.JSValue {
    const generation = engine.native_allocation_generation;
    const previous = if (engine.captured_exception) |value| c.JS_DupValue(engine.context, value) else null;
    defer if (previous) |value| engine.freeValue(value);
    return js.call(engine, function, c.pi_js_undefined(), &.{input}) catch |err| {
        if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
        if (c.JS_HasException(engine.context)) engine.freeValue(c.JS_GetException(engine.context));
        if (engine.captured_exception) |value| engine.freeValue(value);
        engine.captured_exception = if (previous) |value| c.JS_DupValue(engine.context, value) else null;
        return c.JS_DupValue(engine.context, input);
    };
}
fn localPath(engine: *em.Engine, input: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const trimmed = try scope.invoke(input, "trim", &.{});
    inline for (.{ "npm:", "git:", "github:", "http:", "https:", "ssh:", "builtin:" }) |prefix| {
        if (scope.truthy(try scope.invoke(trimmed, "startsWith", &.{try scope.text(prefix)}))) return c.pi_js_bool(engine.context, 0);
    }
    return c.pi_js_bool(engine.context, 1);
}
fn dispatch(engine: *em.Engine, args: []const c.JSValue, roots: []const c.JSValue, method: Method) !c.JSValue {
    return switch (method) {
        .canonicalizePath => canonicalize(engine, roots[0], arg(args, 0)),
        .getFileRevision => @import("native_file_revision.zig").getFileRevision(engine, arg(args, 0)),
        .isLocalPath => localPath(engine, arg(args, 0)),
        .normalizeWindowsShellPath => source.windowsShell(engine, arg(args, 0)),
        .normalizePath => source.normalize(engine, arg(args, 0), arg(args, 1)),
        .resolvePath => source.resolve(engine, arg(args, 0), arg(args, 1), arg(args, 2)),
        .getCwdRelativePath => source.cwdRelative(engine, arg(args, 0), arg(args, 1)),
        .formatPathRelativeToCwdOrAbsolute => source.display(engine, arg(args, 0), arg(args, 1)),
    };
}
