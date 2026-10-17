//! Additive negative-entry controls over actual cached SDK/platform owners.
//! Unused imports are explicit undefined sentinels, never a completed graph.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const bootstrap = @import("extensions/native_sdk_application_bootstrap.zig");
const app = @import("extensions/native_sdk_application_assembly.zig");
const assembly = @import("extensions/native_sdk_default_real_assembly.zig");
const runtime = @import("extensions/native_sdk_runtime_imports.zig");
const Route = enum { default_assembly, application, bootstrap, runtime };
const Cleanup = enum { ordinary, fatal, raw_private };
const Emission = struct { engine: *em.Engine, reason: c.JSValue, kind: Cleanup, calls: usize = 0 };
var selected: ?c.JSValue = null;
var selected_calls: usize = 0;

fn emit(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Emission = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
    state.calls += 1;
    if (state.kind == .raw_private) {
        _ = state.engine.throwNativeOutOfMemory();
        state.reason = state.engine.native_allocation_exception.?;
    } else _ = c.JS_Throw(state.engine.context, c.JS_DupValue(state.engine.context, state.reason));
}
fn neverCalled(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    selected_calls += 1;
    return c.pi_js_undefined();
}
fn transfer(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const value = selected orelse return error.RequiredSoleOwnedApplicationCarrier;
    selected = null;
    return value;
}
fn reject(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, roots[0])));
}
fn installGet(engine: *em.Engine, object: c.JSValue, name: [*:0]const u8, callback: c.JSValue) !void {
    const atom = c.JS_NewAtom(engine.context, name);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, object, atom, callback, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0)
        return @import("extensions/native_js_values.zig").capture(engine);
}
fn installCarrier(engine: *em.Engine, owner: c.JSValue, first: [*:0]const u8, second: [*:0]const u8, original: c.JSValue, emission: *Emission) !void {
    var id: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &id);
    const definition: c.JSClassDef = .{ .class_name = "Actual SDK owner cleanup control", .finalizer = emit };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const token = try engine.checked(c.JS_NewObjectClass(engine.context, id));
    _ = c.JS_SetOpaque(token, emission);
    selected = @import("extensions/native_node_function.zig").createArrow(engine, "ownedCarrier", 0, neverCalled, &.{token}) catch |err| { engine.freeValue(token); return err; };
    engine.freeValue(token); // Sole token owner is the transferred function.
    selected_calls = 0;
    try installGet(engine, owner, first, try @import("extensions/native_node_function.zig").createArrow(engine, "get carrier", 0, transfer, &.{}));
    try installGet(engine, owner, second, try @import("extensions/native_node_function.zig").createArrow(engine, "get original reason", 0, reject, &.{original}));
}
fn unused(comptime T: type) T {
    var value: T = undefined;
    inline for (std.meta.fields(T)) |field| {
        if (field.type == c.JSValue) @field(value, field.name) = c.pi_js_undefined();
    }
    return value;
}
fn invoke(engine: *em.Engine, route: Route, paths: c.JSValue) !c.JSValue {
    return switch (route) {
        .default_assembly => blk: {
            var inputs = unused(assembly.Inputs);
            inputs.paths = paths;
            break :blk assembly.create(engine, inputs);
        },
        .application => app.create(engine, unused(app.Inputs)),
        .bootstrap => bootstrap.create(engine, unused(bootstrap.Completed)),
        .runtime => blk: {
            var inputs = unused(runtime.Inputs);
            inputs.user_agent_runtime = .native_zig;
            break :blk runtime.create(engine, inputs);
        },
    };
}
fn verifyRoute(route: Route) !void {
    for ([_]Cleanup{ .ordinary, .fatal, .raw_private }) |kind| {
        var environment: std.process.Environ.Map = .init(std.testing.allocator);
        defer environment.deinit();
        const engine = try em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        try bootstrap.installPlatform(engine, std.testing.io, &environment, &.{"actual-sdk-owner-cleanup"});
        var s: Scope = .{ .engine = engine };
        defer s.deinit();
        const original = try s.own(try engine.eval("globalThis.ownerReasonDiagnostics=0;({toString(){ownerReasonDiagnostics++;return 'not an observation'}})", "actual-owner-reason.js", c.JS_EVAL_TYPE_GLOBAL));
        const cleanup = try s.own(try engine.checked(c.JS_NewError(engine.context)));
        if (kind == .fatal) c.JS_SetUncatchableError(engine.context, cleanup);
        var emission: Emission = .{ .engine = engine, .reason = cleanup, .kind = kind };
        const paths = engine.native_module_values.get("node:path") orelse return error.RequiredActualPathNamespace;
        const owner = switch (route) {
            .default_assembly => paths,
            .application, .bootstrap => try s.own(try @import("extensions/native_sdk_ai_imports.zig").create(engine)),
            .runtime => try s.own(try @import("extensions/native_sdk_filesystem_namespaces.zig").createPlatform(engine)),
        };
        const first: [*:0]const u8 = switch (route) { .default_assembly => "join", .application, .bootstrap => "ai", .runtime => "paths" };
        const second: [*:0]const u8 = switch (route) { .default_assembly => "dirname", .application, .bootstrap => "compat", .runtime => "filesystem" };
        try installCarrier(engine, owner, first, second, original, &emission);
        defer { if (selected) |value| engine.freeValue(value); selected = null; }
        const suppression = engine.native_exception_diagnostics_suppressed;
        try std.testing.expectError(error.JavaScriptException, invoke(engine, route, paths));
        const expected = if (kind == .ordinary) original else emission.reason;
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, expected, engine.captured_exception orelse return error.RequiredActualOwnerReason));
        try std.testing.expectEqual(@as(usize, 1), emission.calls);
        try std.testing.expectEqual(@as(usize, 0), selected_calls);
        try std.testing.expect(selected == null);
        try std.testing.expectEqual(suppression, engine.native_exception_diagnostics_suppressed);
        try std.testing.expect(engine.native_fatal_invocation == null);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, try s.global("ownerReasonDiagnostics"), c.JS_NewInt32(engine.context, 0)));
    }
}

test "SDK actual application owner default assembly records reason before actual path carrier cleanup" {
    try verifyRoute(.default_assembly);
}
test "SDK actual application owner application assembly records reason before actual AI carrier cleanup" {
    try verifyRoute(.application);
}
test "SDK actual application owner bootstrap preserves inner actual AI reason through its own retirement" {
    try verifyRoute(.bootstrap);
}
test "SDK actual application owner runtime imports records reason before actual platform carrier cleanup" {
    try verifyRoute(.runtime);
}
test "SDK actual application owner actual pending entry wins before cold owner allocation" {
    for ([_]Route{ .default_assembly, .application, .bootstrap, .runtime }) |route| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const engine = try em.Engine.init(failing.allocator(), .{});
        defer engine.deinit();
        const original = try engine.checked(c.JS_NewError(engine.context));
        defer engine.freeValue(original);
        _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, original));
        const allocation_index = failing.alloc_index;
        failing.fail_index = allocation_index;
        try std.testing.expectError(error.JavaScriptException, invoke(engine, route, c.pi_js_undefined()));
        failing.fail_index = std.math.maxInt(usize);
        try std.testing.expectEqual(allocation_index, failing.alloc_index);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, engine.captured_exception orelse return error.RequiredEntryReason));
        try std.testing.expect(engine.native_fatal_invocation == null);
        try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    }
}
