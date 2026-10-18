//! Real production SDK-manager capture order, without selecting a new host.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const sdk = @import("extensions/native_sdk.zig");
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const key = "\x00sdk-actual-manager-imports";

test "SDK manager worker bootstrap captures same original managers during real TUI editor install" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try @import("extensions/native_tui.zig").install(engine);
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const actual_module = engine.native_module_values.get("@earendil-works/pi-coding-agent") orelse return error.RequiredActualWorkerSdkModule;
    const session = try s.get(actual_module, "SessionManager");
    const settings = try s.get(actual_module, "SettingsManager");
    const captured_before_call = engine.native_module_values.get(key) orelse return error.RequiredOriginalManagersAtWorkerBootstrap;
    c.JS_RunGC(engine.runtime);
    const imports = try s.own(try sdk.managerImports(engine));
    try std.testing.expect(s.equal(imports, captured_before_call));
    try std.testing.expect(s.equal(session, try s.get(imports, "SessionManager")));
    try std.testing.expect(s.equal(settings, try s.get(imports, "SettingsManager")));
    try std.testing.expect(!engine.native_module_names.contains(key));
    try std.testing.expect(engine.native_fatal_invocation == null);
}

test "SDK manager worker bootstrap never reconstructs from guest mutable prototype constructor" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try @import("extensions/native_tui.zig").install(engine);
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const actual_module = engine.native_module_values.get("@earendil-works/pi-coding-agent") orelse return error.RequiredActualWorkerSdkModule;
    const first = try s.get(actual_module, "SessionManager");
    const second = try s.get(actual_module, "SettingsManager");
    const global = try s.own(c.JS_GetGlobalObject(engine.context));
    try s.put(global, "ActualSessionManager", first); try s.put(global, "ActualSettingsManager", second);
    const changed = try engine.evalModule(
        \\globalThis.managerConstructorReads=0;
        \\for(const actual of [ActualSessionManager,ActualSettingsManager])Object.defineProperty(actual.prototype,'constructor',{configurable:true,get(){managerConstructorReads++;throw Error('must retain actual constructor, not reflect it')}});
        \\export const changed=true;
    , "actual-worker-manager-constructor-mutation.mjs");
    engine.freeValue(changed);
    const imports = try s.own(try sdk.managerImports(engine));
    try std.testing.expect(s.equal(first, try s.get(imports, "SessionManager")));
    try std.testing.expect(s.equal(second, try s.get(imports, "SettingsManager")));
    try std.testing.expect(s.equal(try s.get(global, "managerConstructorReads"), c.JS_NewInt32(engine.context, 0)));
}

test "SDK manager worker bootstrap fresh private route retains real manager identity without public selection" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const first = try s.own(try sdk.managerImports(engine));
    c.JS_RunGC(engine.runtime);
    const second = try s.own(try sdk.managerImports(engine));
    try std.testing.expect(s.equal(first, second));
    inline for (.{ "SessionManager", "SettingsManager" }) |name| {
        try std.testing.expect(c.JS_IsConstructor(engine.context, try s.get(first, name)));
        try std.testing.expect(s.equal(try s.get(first, name), try s.get(second, name)));
    }
    try std.testing.expect(!engine.native_module_names.contains("@earendil-works/pi-coding-agent"));
    try std.testing.expect(!engine.native_module_names.contains("pi-coding-agent"));
}

test "SDK manager worker bootstrap actual entry reason precedes armed GPA and class effects" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try em.Engine.init(failing.allocator(), .{}); defer engine.deinit();
    const exports = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(exports);
    const reason = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(reason);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
    const allocations = failing.alloc_index;
    failing.fail_index = allocations;
    const result = sdk.install(engine, exports);
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expectError(error.JavaScriptException, result);
    try std.testing.expectEqual(allocations, failing.alloc_index);
    try std.testing.expectEqual(@as(c.JSClassID, 0), engine.native_sdk_class);
    try std.testing.expect(!engine.native_module_values.contains(key));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception orelse return error.RequiredActualEntryReason));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}

const Cleanup = struct { engine: *em.Engine, reason: c.JSValue, fatal: bool, calls: usize = 0 };
fn cleanup(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const self: *Cleanup = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
    self.calls += 1;
    if (self.fatal) { _ = self.engine.throwNativeOutOfMemory(); self.reason = self.engine.native_allocation_exception.?; }
    else _ = c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, self.reason));
}
fn cleanupToken(self: *Cleanup) !c.JSValue {
    var id: c.JSClassID = 0; _ = c.JS_NewClassID(self.engine.runtime, &id);
    const definition: c.JSClassDef = .{ .class_name = "Actual manager projection diagnostic retirement", .finalizer = cleanup };
    if (c.JS_NewClass(self.engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const value = try self.engine.checked(c.JS_NewObjectClass(self.engine.context, id));
    _ = c.JS_SetOpaque(value, self); return value;
}
test "SDK manager worker bootstrap never publishes projection before diagnostic retirement succeeds" {
    for ([_]bool{ false, true }) |fatal| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        const exports = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(exports);
        const reason = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(reason);
        var state: Cleanup = .{ .engine = engine, .reason = reason, .fatal = fatal };
        engine.captured_exception = try cleanupToken(&state); // Sole diagnostic DATA.
        try std.testing.expectError(error.JavaScriptException, sdk.install(engine, exports));
        try std.testing.expectEqual(@as(usize, 1), state.calls);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, state.reason, engine.captured_exception orelse return error.RequiredActualManagerCleanupReason));
        try std.testing.expect(!engine.native_module_values.contains(key));
        try std.testing.expect(engine.native_fatal_invocation == null);
        try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
        // Existing SDK class-install failure is sticky; no retry-success or
        // public module completion is inferred from any partial class state.
    }
}
