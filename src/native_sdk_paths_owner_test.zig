//! Actual canonical paths producer and real native cleanup controls, unrun.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const paths = @import("extensions/native_sdk_path_utilities_namespace.zig");
const fs_owner = @import("extensions/native_sdk_filesystem_namespaces.zig");
const js = @import("extensions/native_js_values.zig");
const owned = @import("extensions/native_sdk_owned_completion.zig");
const namespace_key = "pi-private:actual-sdk-path-utilities";
const filesystem_key = "pi-private:actual-sdk-path-filesystem";

fn install(engine: *em.Engine) !c.JSValue {
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/node_path.zig").install(engine, std.testing.io);
    try @import("extensions/node_url.zig").install(engine);
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    return engine.native_module_values.get("node:fs") orelse error.RequiredActualNodeFilesystem;
}
test "SDK actual paths owner retains one module and actual function identities" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const filesystem = try install(engine);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const first = try s.own(try paths.create(engine, filesystem));
    c.JS_RunGC(engine.runtime);
    const second = try s.own(try paths.create(engine, filesystem));
    try std.testing.expect(s.equal(first, second));
    inline for (.{ "normalizePath", "resolvePath", "getFileRevision", "isLocalPath" }) |name|
        try std.testing.expect(s.equal(try s.get(first, name), try s.get(second, name)));
    try std.testing.expect(!engine.native_module_names.contains(namespace_key));
    try std.testing.expect(!engine.native_module_names.contains(filesystem_key));
    const unrelated = try s.object();
    try std.testing.expectError(error.ActualSdkPathsFilesystemChanged, paths.create(engine, unrelated));
    try std.testing.expect(s.equal(first, try s.own(try paths.create(engine, filesystem))));
}
const Emission = struct { engine: *em.Engine, reason: c.JSValue, private_oom: bool, calls: usize = 0 };
fn emit(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Emission = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
    state.calls += 1;
    if (state.private_oom) {
        _ = state.engine.throwNativeOutOfMemory();
        state.reason = state.engine.native_allocation_exception.?;
    } else _ = c.JS_Throw(state.engine.context, c.JS_DupValue(state.engine.context, state.reason));
}
fn token(state: *Emission) !c.JSValue {
    var id: c.JSClassID = 0;
    _ = c.JS_NewClassID(state.engine.runtime, &id);
    const definition: c.JSClassDef = .{ .class_name = "Actual paths diagnostic cleanup", .finalizer = emit };
    if (c.JS_NewClass(state.engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const result = try state.engine.checked(c.JS_NewObjectClass(state.engine.context, id));
    _ = c.JS_SetOpaque(result, state);
    return result;
}
test "SDK actual paths owner publishes only after actual diagnostic cleanup succeeds" {
    for ([_]bool{ false, true }) |private_oom| {
        const engine = try em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        const filesystem = try install(engine);
        var s: Scope = .{ .engine = engine };
        defer s.deinit();
        const reason = try s.own(try engine.checked(c.JS_NewError(engine.context)));
        var state: Emission = .{ .engine = engine, .reason = reason, .private_oom = private_oom };
        // Sole old diagnostic DATA owner. Its finalizer creates a NEW event;
        // the diagnostic's class/value is never used as fatal authority.
        engine.captured_exception = try token(&state);
        try std.testing.expectError(error.JavaScriptException, paths.create(engine, filesystem));
        try std.testing.expectEqual(@as(usize, 1), state.calls);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, state.reason, engine.captured_exception orelse return error.RequiredActualPathsCleanupReason));
        try std.testing.expect(!engine.native_module_values.contains(namespace_key));
        try std.testing.expect(!engine.native_module_values.contains(filesystem_key));
        try std.testing.expect(engine.native_fatal_invocation == null);
        try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    }
}
test "SDK actual paths owner real GPA failure cannot commit a partial namespace" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try em.Engine.init(failing.allocator(), .{});
    defer engine.deinit();
    const filesystem = try install(engine);
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.JavaScriptException, paths.create(engine, filesystem));
    failing.fail_index = std.math.maxInt(usize);
    const reason = engine.captured_exception orelse return error.RequiredActualPathsAllocationReason;
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    try std.testing.expect(!engine.native_module_values.contains(namespace_key));
    try std.testing.expect(!engine.native_module_values.contains(filesystem_key));
    try std.testing.expect(engine.native_fatal_invocation == null);
}

/// Actual frontend supplies its real process/spawnProcessSync imports. This
/// executes no child, but deliberately accepts no dummy transport to qualify
/// a supplier merely because this profile only observes import identities.
pub fn verifyActualCloudImports(engine: *em.Engine, filesystem: c.JSValue, process: c.JSValue, spawn_process_sync: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const basic = try s.own(try paths.create(engine, filesystem));
    const normalize = try s.get(basic, "normalizePath");
    const completed = try s.own(try paths.createWithPlatform(engine, filesystem, process, spawn_process_sync));
    try std.testing.expect(s.equal(basic, completed));
    try std.testing.expect(s.equal(normalize, try s.get(completed, "normalizePath")));
    const mark = try s.get(completed, "markPathIgnoredByCloudSync");
    try std.testing.expect(c.JS_IsFunction(engine.context, mark));
    c.JS_RunGC(engine.runtime);
    const repeated = try s.own(try paths.createWithPlatform(engine, filesystem, process, spawn_process_sync));
    try std.testing.expect(s.equal(completed, repeated));
    try std.testing.expect(s.equal(mark, try s.get(repeated, "markPathIgnoredByCloudSync")));
}

fn neverCalled(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn selected(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const ctx = context.?;
    if (magic != 0) return c.JS_Throw(ctx, c.JS_DupValue(ctx, roots[0]));
    const value = c.JS_GetPropertyStr(ctx, roots[0], "carrier");
    if (c.JS_IsException(value)) return value;
    const atom = c.JS_NewAtom(ctx, "carrier");
    if (atom == c.JS_ATOM_NULL) return failedSelection(ctx, value);
    defer c.JS_FreeAtom(ctx, atom);
    if (c.JS_DeleteProperty(ctx, roots[0], atom, c.JS_PROP_THROW) < 0) return failedSelection(ctx, value);
    return value; // Sole carrier ref transferred; holder no longer owns it.
}
fn failedSelection(context: *c.JSContext, value: c.JSValue) c.JSValue {
    const engine = em.Engine.fromContext(context);
    var completion = owned.Completion.initValue(engine, js.capture(engine));
    completion.release(value);
    return completion.finishValue() catch |err| @import("extensions/native_sdk.zig").fail(engine, err);
}
fn defineGetter(engine: *em.Engine, object: c.JSValue, name: [*:0]const u8, getter: c.JSValue) !void {
    const atom = c.JS_NewAtom(engine.context, name);
    if (atom == c.JS_ATOM_NULL) return js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, object, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(engine);
}
fn platformErrorCleanup(private_oom: bool) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const filesystem = try install(engine);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const original = try s.own(try engine.checked(c.JS_NewError(engine.context)));
    const later = try s.own(try engine.checked(c.JS_NewError(engine.context)));
    var emission: Emission = .{ .engine = engine, .reason = later, .private_oom = private_oom };
    const holder = try s.object();
    const function = try engine.checked(c.pi_js_function_magic(engine.context, neverCalled, "actual unwind carrier", 0, 0));
    // This controlled callable is never invoked or published as a successful
    // fs implementation. Its sole token tests the real factory's error exit.
    try js.define(engine, function, "token", try token(&emission));
    try js.define(engine, holder, "carrier", function); // consumes sole function.
    var carrier_data = [_]c.JSValue{holder};
    const first_getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, selected, "get existsSync", 0, 0, 1, &carrier_data));
    var error_data = [_]c.JSValue{original};
    const second_getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, selected, "get mkdirSync", 0, 1, 1, &error_data));
    try defineGetter(engine, filesystem, "existsSync", first_getter);
    try defineGetter(engine, filesystem, "mkdirSync", second_getter);
    try std.testing.expectError(error.JavaScriptException, fs_owner.createPlatform(engine));
    try std.testing.expectEqual(@as(usize, 1), emission.calls);
    const actual = engine.captured_exception orelse return error.RequiredActualFilesystemOwnerError;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, if (private_oom) emission.reason else original));
    try std.testing.expect(!engine.native_module_values.contains("pi-native:actual-sdk-filesystem-platform"));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
test "SDK actual paths owner platform first ordinary error beats ordinary sole carrier cleanup" { try platformErrorCleanup(false); }
test "SDK actual paths owner platform fresh native carrier OOM promotes over ordinary error" { try platformErrorCleanup(true); }
