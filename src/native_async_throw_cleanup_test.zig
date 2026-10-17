//! Actual native VM cleanup controls, prepared only. All throwing native
//! getters obey the C exception convention; native finalizers emit pending
//! events during real owned-value release, not through guest flag properties.
const std = @import("std");
const em = @import("extensions/engine.zig");
const af = @import("extensions/native_async_function.zig");
const c = em.c;
const Probe = struct {
    engine: *em.Engine,
    initial: c.JSValue,
    original: c.JSValue,
    cleanup_fatal: c.JSValue,
    displaced_cleanup: c.JSValue,
    state_cleanup: c.JSValue,
    token_class: c.JSClassID = 0,
    result_class: c.JSClassID = 0,
    original_class: c.JSClassID = 0,
    state_class: c.JSClassID = 0,
    initial_count: usize = 0,
    result_count: usize = 0,
    original_count: usize = 0,
    state_count: usize = 0,
};
var active: ?*Probe = null;
fn probeOf(owner: c.JSValue) *Probe { return @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)).?)); }
fn initialFree(_: ?*c.JSRuntime, owner: c.JSValue) callconv(.c) void {
    const p = probeOf(owner); p.initial_count += 1;
    const reason = p.original; p.original = c.pi_js_undefined();
    _ = c.JS_Throw(p.engine.context, reason); // Consumes sole-owned original.
}
fn resultFree(_: ?*c.JSRuntime, owner: c.JSValue) callconv(.c) void {
    const p = probeOf(owner); p.result_count += 1;
    _ = c.JS_Throw(p.engine.context, c.JS_DupValue(p.engine.context, p.cleanup_fatal));
}
fn originalFree(_: ?*c.JSRuntime, owner: c.JSValue) callconv(.c) void {
    const p = probeOf(owner); p.original_count += 1;
    _ = c.JS_Throw(p.engine.context, c.JS_DupValue(p.engine.context, p.displaced_cleanup));
}
fn stateFree(_: ?*c.JSRuntime, owner: c.JSValue) callconv(.c) void {
    const p = probeOf(owner); p.state_count += 1;
    _ = c.JS_Throw(p.engine.context, c.JS_DupValue(p.engine.context, p.state_cleanup));
}
fn newClass(engine: *em.Engine, finalizer: *const fn (?*c.JSRuntime, c.JSValue) callconv(.c) void) !c.JSClassID {
    var id: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &id);
    const definition: c.JSClassDef = .{ .class_name = "Actual AF pending cleanup fixture", .finalizer = finalizer };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    return id;
}
fn token(p: *Probe, class: c.JSClassID) !c.JSValue {
    const result = try p.engine.checked(c.JS_NewObjectClass(p.engine.context, class));
    _ = c.JS_SetOpaque(result, p);
    return result;
}
fn poisonConstructor(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const p = active.?;
    const reason = p.initial; p.initial = c.pi_js_undefined();
    return c.JS_Throw(context, reason); // No retained alias on the getter.
}
fn cleanupBody(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, _: c.JSValue) !af.Action {
    const p = active.?;
    if (completion == .start) {
        af.replaceState(engine, state, try token(p, p.state_class));
        return .{ .awaited = c.JS_DupValue(engine.context, args[0]) };
    }
    if (completion != .rejected) return error.ExpectedActualAwaitSetupThrow;
    // Source consumes the ordinary input. VM then releases its last owned
    // resumed_input reference, whose token raises the initial actual event.
    return .{ .returned = try token(p, p.result_class) };
}
test "native Await DATA C3 resumed input result displaced error and frame cleanup preserve first actual fatal" {
    for ([_]bool{ false, true }) |original_fatal| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        const b = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(b);
        const ordinary_c = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(ordinary_c);
        const ordinary_d = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(ordinary_d);
        c.JS_SetUncatchableError(engine.context, b);
        var p: Probe = .{ .engine = engine, .initial = try engine.checked(c.JS_NewError(engine.context)), .original = try engine.checked(c.JS_NewError(engine.context)), .cleanup_fatal = b, .displaced_cleanup = ordinary_c, .state_cleanup = ordinary_d };
        active = &p; defer active = null;
        p.token_class = try newClass(engine, initialFree);
        p.result_class = try newClass(engine, resultFree);
        p.original_class = try newClass(engine, originalFree);
        p.state_class = try newClass(engine, stateFree);
        const borrowed_original = p.original;
        if (original_fatal) c.JS_SetUncatchableError(engine.context, p.original);
        try std.testing.expect(c.JS_IsUncatchableError(b));
        if (c.JS_DefinePropertyValueStr(engine.context, p.initial, "cleanup", try token(&p, p.token_class), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        if (c.JS_DefinePropertyValueStr(engine.context, p.original, "cleanup", try token(&p, p.original_class), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        const input = try engine.checked(c.JS_NewSettledPromise(engine.context, false, c.pi_js_undefined())); defer engine.freeValue(input);
        const getter = try engine.checked(c.JS_NewCFunction(engine.context, poisonConstructor, "get constructor", 0));
        const atom = c.JS_NewAtom(engine.context, "constructor"); defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DefinePropertyGetSet(engine.context, input, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
        const function = try af.createResumable(engine, "actualCleanup", 1, cleanupBody, &.{}); defer engine.freeValue(function);
        var args = [_]c.JSValue{input};
        const result = c.JS_Call(engine.context, function, c.pi_js_undefined(), args.len, &args); defer engine.freeValue(result);
        try std.testing.expect(c.JS_IsException(result) and c.JS_HasException(engine.context));
        const reason = c.JS_GetException(engine.context);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, if (original_fatal) borrowed_original else b));
        try std.testing.expect(c.JS_IsUncatchableError(reason));
        try std.testing.expectEqual(@as(usize, 1), p.initial_count);
        try std.testing.expectEqual(@as(usize, 1), p.result_count);
        try std.testing.expectEqual(@as(usize, 1), p.state_count);
        try std.testing.expectEqual(@as(usize, if (original_fatal) 0 else 1), p.original_count);
        try std.testing.expect(!c.JS_HasException(engine.context));
        engine.freeValue(reason); // Only now can the selected fatal A be freed.
        if (original_fatal) {
            const cleanup = c.JS_GetException(engine.context); defer engine.freeValue(cleanup);
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, ordinary_c, cleanup));
        }
        try std.testing.expectEqual(@as(usize, 1), p.original_count);
        try std.testing.expect(!c.JS_HasException(engine.context));
    }
}
var entered: usize = 0;
fn mustNotEnter(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue, _: *c.JSValue, _: af.Completion, _: c.JSValue) !af.Action {
    entered += 1;
    const bytes = try engine.gpa.alloc(u8, 1); defer engine.gpa.free(bytes);
    return .{ .returned = c.pi_js_undefined() };
}
test "native Await DATA C3 actual pending entry precedes native body and armed GPA failure" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try em.Engine.init(failing.allocator(), .{}); defer engine.deinit();
    const function = try af.createResumable(engine, "mustNotEnter", 0, mustNotEnter, &.{}); defer engine.freeValue(function);
    const marker = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(marker);
    c.JS_SetUncatchableError(engine.context, marker);
    entered = 0;
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, marker));
    failing.fail_index = failing.alloc_index;
    const result = c.JS_Call(engine.context, function, c.pi_js_undefined(), 0, null); defer engine.freeValue(result);
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expectEqual(@as(usize, 0), entered);
    try std.testing.expect(!failing.has_induced_failure);
    const actual = c.JS_GetException(engine.context); defer engine.freeValue(actual);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, marker, actual));
}
