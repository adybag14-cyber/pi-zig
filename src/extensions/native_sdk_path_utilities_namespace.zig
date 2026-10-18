//! Actual coding-agent utils/paths.ts public namespace over the real native
//! Source bodies and one captured node:fs realpathSync binding.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const c = js.c;
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const source = @import("native_sdk_source_paths.zig");
const functions = @import("native_node_function.zig");
const owned = @import("native_sdk_owned_completion.zig");
const guest = @import("native_sdk_guest_operation.zig");
const guards = @import("native_agent_af_values.zig");
const sdk = @import("native_sdk.zig");
const namespace_key = "pi-private:actual-sdk-path-utilities";
const filesystem_key = "pi-private:actual-sdk-path-filesystem";
const cloud_process_key = "pi-private:actual-sdk-path-cloud-process";
const cloud_spawn_key = "pi-private:actual-sdk-path-cloud-spawn";
const Creating = struct { engine: *em.Engine, cloud: bool, previous: ?*Creating };
threadlocal var creating: ?*Creating = null;
fn alreadyCreating(engine: *em.Engine, cloud: bool) bool {
    var cursor = creating;
    while (cursor) |entry| : (cursor = entry.previous) if (entry.engine == engine and entry.cloud == cloud) return true;
    return false;
}
const Method = enum { canonicalizePath, getFileRevision, isLocalPath, normalizeWindowsShellPath, normalizePath, resolvePath, getCwdRelativePath, formatPathRelativeToCwdOrAbsolute };
fn root(scope: *Scope, value: c.JSValue) !c.JSValue { return owned.ownRoot(scope, value); }
fn get(scope: *Scope, target: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return guest.get(scope, target, name);
}
fn put(scope: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    return guest.put(scope, target, name, value);
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
pub fn create(engine: *em.Engine, actual_filesystem: c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(namespace_key)) |cached| {
        const filesystem = engine.native_module_values.get(filesystem_key) orelse return error.ActualSdkPathsCacheIncomplete;
        if (!c.JS_IsStrictEqual(engine.context, actual_filesystem, filesystem)) return error.ActualSdkPathsFilesystemChanged;
        return c.JS_DupValue(engine.context, cached);
    }
    if (alreadyCreating(engine, false)) return error.ActualSdkPathsCreationReentry;
    var entry: Creating = .{ .engine = engine, .cloud = false, .previous = creating };
    creating = &entry;
    defer creating = entry.previous;
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const result = createOwned(engine, actual_filesystem) catch |err|
        return engine.checked(engine.leaveNativeInvocation(&invocation, @import("native_sdk.zig").fail(engine, err)));
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
fn createOwned(engine: *em.Engine, actual_filesystem: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    const namespace = try owned.finishValue(&scope, createBody(&scope, actual_filesystem));
    // All constructor Scope/diagnostic retirement precedes cache publication.
    // Reserve AFTER observable getters so reentry cannot consume our capacity.
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 2) catch |err| {
        var failed = owned.Completion.initValue(engine, err);
        failed.release(namespace);
        return failed.finishValue();
    };
    engine.native_module_values.putAssumeCapacity(filesystem_key, c.JS_DupValue(engine.context, actual_filesystem));
    engine.native_module_values.putAssumeCapacity(namespace_key, c.JS_DupValue(engine.context, namespace));
    return namespace;
}
fn createBody(scope: *Scope, actual_filesystem: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const canonical = try get(scope, actual_filesystem, "realpathSync");
    if (!c.JS_IsFunction(engine.context, canonical)) return error.RequiredActualSdkRealpath;
    const result = try root(scope, try sdk.object(engine));
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
        try put(scope, result, field.name, try root(scope, try functions.create(engine, field.name, length, Adapter.call, &.{canonical})));
    }
    return c.JS_DupValue(engine.context, result);
}
/// Complete the actual paths namespace for PackageManager using its captured
/// process and utils/child-process.ts binding. The application supplies these
/// real inputs once; namespace assembly neither launches nor simulates a child.
pub fn createWithPlatform(engine: *em.Engine, actual_filesystem: c.JSValue, actual_process: c.JSValue, spawn_process_sync: c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    if (alreadyCreating(engine, true)) return error.ActualSdkPathsCloudCreationReentry;
    var entry: Creating = .{ .engine = engine, .cloud = true, .previous = creating };
    creating = &entry;
    defer creating = entry.previous;
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const result = completeOwned(engine, actual_filesystem, actual_process, spawn_process_sync) catch |err|
        return engine.checked(engine.leaveNativeInvocation(&invocation, @import("native_sdk.zig").fail(engine, err)));
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
fn completeOwned(engine: *em.Engine, filesystem: c.JSValue, process: c.JSValue, spawn: c.JSValue) !c.JSValue {
    const namespace = try create(engine, filesystem);
    if (engine.native_module_values.get(cloud_process_key)) |known| {
        const known_spawn = engine.native_module_values.get(cloud_spawn_key) orelse return releaseFailure(engine, error.ActualSdkPathsCloudCacheIncomplete, namespace, null);
        if (!c.JS_IsStrictEqual(engine.context, known, process) or !c.JS_IsStrictEqual(engine.context, known_spawn, spawn)) return releaseFailure(engine, error.ActualSdkPathsCloudImportsChanged, namespace, null);
        // Preserve any later ordinary guest mutation of the actual export.
        return namespace;
    }
    var scope: Scope = .{ .engine = engine };
    const mark = owned.finishValue(&scope, @import("native_sdk_path_cloud_sync.zig").create(engine, process, spawn)) catch |err|
        return releaseFailure(engine, err, namespace, null);
    // These are private bootstrap phases over a real ordinary namespace, not a
    // guest-visible partially completed source module. Reject pre-initialized
    // cloud exports rather than replacing somebody else's owned value.
    const atom = c.JS_NewAtom(engine.context, "markPathIgnoredByCloudSync");
    if (atom == c.JS_ATOM_NULL) return releaseFailure(engine, js.capture(engine), namespace, mark);
    defer c.JS_FreeAtom(engine.context, atom);
    var descriptor: c.JSPropertyDescriptor = undefined;
    const found = c.JS_GetOwnProperty(engine.context, &descriptor, namespace, atom);
    if (found < 0) return releaseFailure(engine, js.capture(engine), namespace, mark);
    if (found != 0) {
        var failed = owned.Completion.initValue(engine, error.ActualSdkPathsCloudExportAlreadyPresent);
        failed.release(descriptor.setter);
        failed.release(descriptor.getter);
        failed.release(descriptor.value);
        failed.release(mark);
        failed.release(namespace);
        return failed.finishValue();
    }
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 2) catch |err|
        return releaseFailure(engine, err, namespace, mark);
    // Reserve and install the PRIVATE import roots before the VM property
    // operation. Reentry into this synchronous completion is rejected above;
    // no later GPA reservation or unchecked put can follow export definition.
    engine.native_module_values.putAssumeCapacity(cloud_process_key, c.JS_DupValue(engine.context, process));
    engine.native_module_values.putAssumeCapacity(cloud_spawn_key, c.JS_DupValue(engine.context, spawn));
    guest.put(&scope, namespace, "markPathIgnoredByCloudSync", mark) catch |err| {
        var failed = owned.Completion.initValue(engine, err);
        const old_spawn = engine.native_module_values.fetchRemove(cloud_spawn_key).?;
        const old_process = engine.native_module_values.fetchRemove(cloud_process_key).?;
        failed.release(old_spawn.value);
        failed.release(old_process.value);
        failed.release(mark);
        failed.release(namespace);
        return failed.finishValue();
    };
    var completed = owned.Completion.initValue(engine, namespace);
    completed.release(mark); // The actual namespace retains this binding.
    return completed.finishValue();
}
fn releaseFailure(engine: *em.Engine, err: anyerror, namespace: c.JSValue, mark: ?c.JSValue) !c.JSValue {
    var failed = owned.Completion.initValue(engine, err);
    if (mark) |value| failed.release(value);
    failed.release(namespace);
    return failed.finishValue();
}
fn canonicalize(engine: *em.Engine, function: c.JSValue, input: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    const result = guest.call(&scope, function, c.pi_js_undefined(), &.{input}) catch |err| {
        // Source catches ordinary realpath failures. A retained current native
        // event must bypass that catch; diagnostic tags/newness are DATA.
        engine.checkNativeEntry() catch |current| return owned.finishValue(&scope, @as(anyerror!c.JSValue, current));
        if (err != error.JavaScriptException) return owned.finishValue(&scope, @as(anyerror!c.JSValue, err));
        const reason = engine.captured_exception orelse return owned.finishValue(&scope, @as(anyerror!c.JSValue, err));
        engine.captured_exception = null;
        var selected = owned.Completion.initValue(engine, c.JS_DupValue(engine.context, input));
        selected.release(reason);
        selected.releaseScope(&scope);
        return selected.finishValue();
    };
    return owned.finishValue(&scope, c.JS_DupValue(engine.context, result));
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
