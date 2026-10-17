//! Prepared real builtin/namespace and SourceLoader boundary controls. Actual
//! TTY assembly must already be installed; no dummy builtin carrier is created.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
pub fn loaderReplacement(engine: *v.em.Engine) !void {
    const Control = struct {
        const State = struct { calls: usize = 0, actual_path: bool = false };
        fn normalize(raw: ?*anyopaque, gpa: std.mem.Allocator, base: []const u8, name: []const u8) ![]u8 {
            const state: *State = @ptrCast(@alignCast(raw.?)); state.calls += 1;
            state.actual_path = std.mem.eql(u8, base, "fixture/entry.mjs") and std.mem.eql(u8, name, "./dep.mjs");
            return gpa.dupe(u8, "fixture/dep.mjs");
        }
        fn load(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8) ![]u8 { return error.UnexpectedFixtureLoad; }
    };
    const previous = engine.source_loader;
    // Restore through the public setter when available. A fresh loader-less
    // Engine is kept loader-less afterward; aliases keep the host normalizer.
    defer if (previous) |loader| engine.setSourceLoader(loader) else engine.source_loader = null;
    var state: Control.State = .{};
    engine.setSourceLoader(.{ .context = &state, .load = Control.load, .normalize = Control.normalize });
    try engine.registerModule("fixture/dep.mjs", "export const observed = 'actual-user-input';");
    const namespace = try engine.evalModule(
        "import * as a from 'tty'; import * as b from 'node:tty'; import { observed } from './dep.mjs'; export const aliases = a === b; export { observed };",
        "fixture/entry.mjs"); defer engine.freeValue(namespace);
    const aliases = try engine.checked(c.JS_GetPropertyStr(engine.context, namespace, "aliases")); defer engine.freeValue(aliases);
    try std.testing.expect(c.JS_ToBool(engine.context, aliases) == 1);
    try std.testing.expect(state.actual_path and state.calls == 1);
    // Replacing the loader again must not disable aliases or call its custom
    // normalizer for a builtin. normalizeRequire also retains bare host names.
    engine.setSourceLoader(.{ .context = &state, .load = Control.load });
    const result = try engine.evalModule("import * as a from 'tty'; import * as b from 'node:tty'; export const aliases = a === b;", "fixture/replaced.mjs"); defer engine.freeValue(result);
    const same = try engine.checked(c.JS_GetPropertyStr(engine.context, result, "aliases")); defer engine.freeValue(same);
    try std.testing.expect(c.JS_ToBool(engine.context, same) == 1);
    const canonical = try engine.normalizeRequire("fixture/replaced.mjs", "tty"); defer engine.gpa.free(canonical);
    try std.testing.expectEqualStrings("node:tty", canonical);
    const bare = (try engine.requireBuiltin("tty")) orelse return error.MissingActualTty; defer engine.freeValue(bare);
    const prefixed = (try engine.requireBuiltin("node:tty")) orelse return error.MissingActualTty; defer engine.freeValue(prefixed);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, bare, prefixed));
    try std.testing.expectEqual(@as(usize, 1), state.calls);
}

/// Pending actual reason must win before duplicate/conflict checks or any new
/// alias ownership; no arbitrary toString or half mutation is admitted.
pub fn pendingEntry(engine: *v.em.Engine) !void {
    const Control = struct {
        var calls: usize = 0;
        fn string(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
            calls += 1; return c.JS_NewString(context, "must-not-format-pending-alias-reason");
        }
    };
    Control.calls = 0;
    const reason = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(reason);
    const string = try engine.checked(c.JS_NewCFunction(engine.context, Control.string, "actualAliasReasonToString", 0));
    if (c.JS_DefinePropertyValueStr(engine.context, reason, "toString", string, c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
    const before = engine.native_builtin_aliases.count();
    const suppression = engine.native_exception_diagnostics_suppressed;
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
    engine.registerBuiltinAlias("tty", "node:tty") catch |err| {
        try std.testing.expect(err == error.JavaScriptException);
        const observed = engine.captured_exception orelse return error.MissingActualAliasPendingReason;
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, observed));
        try std.testing.expectEqual(before, engine.native_builtin_aliases.count());
        try std.testing.expectEqual(@as(usize, 0), Control.calls);
        try std.testing.expectEqual(suppression, engine.native_exception_diagnostics_suppressed);
        engine.captured_exception = null; engine.freeValue(observed);
        try std.testing.expect(!c.JS_HasException(engine.context));
        return;
    };
    return error.ExpectedActualAliasPendingFailure;
}

/// Fresh actual composition, with its genuine private TTY export record.
/// Root supplies independent fresh Engines for each admitted failure index.
/// Canonical C module already exists; failed alias allocation owns no module
/// or partial alias and cannot expose a second namespace on normal-GPA retry.
pub fn allocationFailure(engine: *v.em.Engine, actual_tty_exports: c.JSValue, fail_after: usize) !void {
    try std.testing.expectEqual(@as(usize, 0), engine.native_builtin_aliases.count());
    try std.testing.expect(!engine.native_module_names.contains("tty") and !engine.native_module_names.contains("node:tty"));
    try engine.registerValueModule("node:tty", actual_tty_exports);
    const actual_gpa = engine.gpa;
    var failing = std.testing.FailingAllocator.init(actual_gpa, .{ .fail_index = fail_after, .resize_fail_index = 0 });
    engine.gpa = failing.allocator(); defer engine.gpa = actual_gpa;
    engine.registerBuiltinAlias("tty", "node:tty") catch |err| {
        engine.gpa = actual_gpa;
        try std.testing.expect(err == error.OutOfMemory and failing.has_induced_failure);
        try std.testing.expectEqual(@as(usize, 0), engine.native_builtin_aliases.count());
        try std.testing.expect(engine.native_module_names.contains("node:tty") and !engine.native_module_names.contains("tty"));
        const not_yet = try engine.requireBuiltin("tty"); defer if (not_yet) |value| engine.freeValue(value);
        try std.testing.expect(not_yet == null);
        try engine.registerBuiltinAlias("tty", "node:tty");
        const namespace = try engine.evalModule("import * as a from 'tty'; import * as b from 'node:tty'; export const same = a === b;", "alias-allocation-retry.mjs"); defer engine.freeValue(namespace);
        const same = try engine.checked(c.JS_GetPropertyStr(engine.context, namespace, "same")); defer engine.freeValue(same);
        try std.testing.expect(c.JS_ToBool(engine.context, same) == 1);
        try std.testing.expectEqual(@as(usize, 1), engine.native_builtin_aliases.count());
        engine.registerModule("tty", "export const forbidden = true;") catch |duplicate| {
            try std.testing.expect(duplicate == error.DuplicateExtensionModule);
            return;
        };
        return error.ExpectedAliasShadowRejection;
    };
    return error.ExpectedActualAliasAllocationFailure;
}

/// Actual Bfb producer+invocation, with B already captured and VM slot empty.
/// After leaving that invocation, the SAME flagged value is historical DATA;
/// successful admission then proves this is not a blanket flag/history guard.
pub fn currentFatalEntry(engine: *v.em.Engine, actual_tty_exports: c.JSValue) !void {
    try std.testing.expectEqual(@as(usize, 0), engine.native_builtin_aliases.count());
    try engine.registerValueModule("node:tty", actual_tty_exports);
    var invocation: v.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    defer if (invocation.active) {
        const result = engine.leaveNativeInvocation(&invocation, c.pi_js_undefined());
        engine.freeValue(result);
        if (c.JS_HasException(engine.context)) engine.freeValue(c.JS_GetException(engine.context));
    };
    var threw = false;
    const produced = engine.checked(engine.throwNativeOutOfMemoryFatal()) catch |err| block: {
        try std.testing.expect(err == error.JavaScriptException);
        threw = true; break :block c.pi_js_undefined();
    };
    defer engine.freeValue(produced);
    try std.testing.expect(threw);
    const reason = c.JS_DupValue(engine.context, engine.captured_exception orelse return error.MissingActualAliasFatal); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason) and !c.JS_HasException(engine.context));
    engine.registerBuiltinAlias("tty", "node:tty") catch |err| {
        try std.testing.expect(err == error.JavaScriptException);
        try std.testing.expectEqual(@as(usize, 0), engine.native_builtin_aliases.count());
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception orelse return error.MissingAliasFatalCapture));
        const captured = engine.captured_exception.?; engine.captured_exception = null; engine.freeValue(captured);
        const result = engine.leaveNativeInvocation(&invocation, c.pi_js_undefined()); defer engine.freeValue(result);
        try std.testing.expect(c.JS_IsException(result));
        const leaving = c.JS_GetException(engine.context); defer engine.freeValue(leaving);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, leaving));
        try std.testing.expect(engine.native_fatal_invocation == null);
        engine.captured_exception = c.JS_DupValue(engine.context, reason);
        try engine.registerBuiltinAlias("tty", "node:tty");
        try std.testing.expectEqual(@as(usize, 1), engine.native_builtin_aliases.count());
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception.?));
        const history = engine.captured_exception.?; engine.captured_exception = null; engine.freeValue(history);
        c.JS_ClearUncatchableError(engine.context, reason);
        return;
    };
    return error.ExpectedCurrentFatalAliasEntryFailure;
}
