//! Additive UNRUN controls on actual already-spawned children. Native holders
//! are observer values, never substitute child/stream/callback graphs.
const std = @import("std");
const x = @import("extensions/native_sdk_exec_values.zig");
const waiter = @import("extensions/native_wait_for_child_process.zig");
const f = @import("extensions/native_node_function.zig");
const c = x.c;
const Carrier = struct { engine: *x.em.Engine, box: c.JSValue };
fn retired(rt: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Carrier = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    const engine = state.engine;
    const previous = c.JS_GetPropertyStr(engine.context, state.box, "retired");
    var count: i32 = 0; _ = c.JS_ToInt32(engine.context, &count, previous); engine.freeValue(previous);
    _ = c.JS_DefinePropertyValueStr(engine.context, state.box, "retired", c.JS_NewInt32(engine.context, count + 1), c.JS_PROP_C_W_E);
    c.JS_FreeValueRT(rt, state.box); engine.gpa.destroy(state); c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Carrier));
}
fn mark(rt: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Carrier = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return)); c.JS_MarkValue(rt, state.box, visit);
}
fn carrier(o: *x.Ops, box: c.JSValue) !c.JSValue {
    const engine = o.s.engine;
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(Carrier)) == 0) return error.OutOfMemory;
    var attached = false; errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Carrier));
    const state = try engine.gpa.create(Carrier); errdefer if (!attached) engine.gpa.destroy(state);
    var id: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &id);
    const definition: c.JSClassDef = .{ .class_name = "Actual discarded waiter observer", .finalizer = retired, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const value = try o.own(try engine.checked(c.JS_NewObjectClass(engine.context, id)));
    state.* = .{ .engine = engine, .box = c.JS_DupValue(engine.context, box) }; _ = c.JS_SetOpaque(value, state); attached = true;
    return value;
}
fn delegatedOnce(engine: *x.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, delegatedBody(&o, receiver, args, roots));
}
fn delegatedBody(o: *x.Ops, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    _ = try o.call(roots[0], receiver, args); // The REAL stream method runs.
    try o.put(roots[1], "onceCalled", c.pi_js_bool(o.s.engine.context, 1));
    return c.JS_DupValue(o.s.engine.context, try carrier(o, roots[1])); // Sole discarded return observer.
}
fn onceGetter(engine: *x.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, onceGetterBody(&o, roots));
}
fn onceGetterBody(o: *x.Ops, roots: []const c.JSValue) !c.JSValue {
    const held = try carrier(o, roots[1]);
    // A nonconstructible real method avoids an artificial function/prototype
    // cycle: its sole carrier retires with the Source callee temporary.
    return f.createMethod(o.s.engine, "observedOnce", 2, delegatedOnce, &.{ roots[0], roots[1], held });
}
fn stderrGetter(engine: *x.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, stderrGetterBody(&o, roots));
}
fn stderrGetterBody(o: *x.Ops, roots: []const c.JSValue) !c.JSValue {
    if (o.truthy(try o.get(roots[1], "onceCalled")) and !o.truthy(try o.get(roots[1], "checked"))) {
        try o.put(roots[1], "observed", try o.get(roots[1], "retired"));
        try o.put(roots[1], "checked", c.pi_js_bool(o.s.engine.context, 1));
    }
    return c.JS_DupValue(o.s.engine.context, roots[0]); // Genuine stream, never a fake receiver.
}
fn accessor(engine: *x.em.Engine, object: c.JSValue, name: [*:0]const u8, getter: c.JSValue) !void {
    const atom = c.JS_NewAtom(engine.context, name); if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, object, atom, c.JS_DupValue(engine.context, getter), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return @import("extensions/native_js_values.zig").capture(engine);
}
/// real_child must be a genuine running child with actual pipe streams. The
/// once override delegates to the captured real method and returns a sole
/// native observer. The next actual child.stderr getter must see BOTH callee
/// and discarded-return observers retired. Old69a sees zero at that point.
pub fn verifyDiscardedOnceBeforeNextActualGetter(engine: *x.em.Engine, real_child: c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; defer s.deinit();
    const stdout = try s.get(real_child, "stdout"); const stderr = try s.get(real_child, "stderr"); const once = try s.get(stdout, "once");
    const box = try s.object(); try s.put(box, "retired", c.JS_NewInt32(engine.context, 0)); try s.put(box, "observed", c.JS_NewInt32(engine.context, -1));
    try s.put(box, "onceCalled", c.pi_js_bool(engine.context, 0)); try s.put(box, "checked", c.pi_js_bool(engine.context, 0));
    const get_once = try s.own(try f.createMethod(engine, "get once", 0, onceGetter, &.{ once, box }));
    const get_stderr = try s.own(try f.createMethod(engine, "get stderr", 0, stderrGetter, &.{ stderr, box }));
    try accessor(engine, stdout, "once", get_once); try accessor(engine, real_child, "stderr", get_stderr);
    const function = try s.own(try waiter.create(engine));
    const pending = try s.call(function, c.pi_js_undefined(), &.{real_child}); c.JS_PromiseMarkAsHandled(engine.context, pending);
    try std.testing.expect(s.equal(try s.get(box, "observed"), c.JS_NewInt32(engine.context, 2)));
    // Restore only AFTER the causal assertion; any failure uses real owner
    // teardown, without a catch/ignored guest restoration path.
    try x.guest.put(&s, stdout, "once", once); try x.guest.put(&s, real_child, "stderr", stderr);
    return c.JS_DupValue(engine.context, pending);
}
fn createPrivateData(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = x.em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemory(); // Deliberately UNMARKED, returned DATA.
    const value = c.JS_GetException(context);
    if (argc > 0 and c.JS_DefinePropertyValueStr(context, argv[0], "actual", c.JS_DupValue(context, value), c.JS_PROP_C_W_E) < 0) { engine.freeValue(value); return c.JS_Throw(context, c.JS_GetException(context)); }
    return value; // No actual pending/current producer event at return.
}
/// A JS getter creates private DATA A and then ordinarily throws A in the SAME
/// get operation. A new tag in that operation is not fatal authority. The real
/// Source Promise must reject with unchanged, unmarked A (BE5514 countercase).
pub fn verifyPrivateDataCreatedThenThrownInActualGetter(engine: *x.em.Engine, real_child: c.JSValue) !void {
    try std.testing.expect(engine.native_fatal_invocation == null and !c.JS_HasException(engine.context));
    var s: x.Scope = .{ .engine = engine }; defer s.deinit();
    const stdout = try s.get(real_child, "stdout"); const box = try s.object(); try s.put(box, "actual", c.pi_js_undefined());
    const make = try s.own(try engine.checked(c.JS_NewCFunction(engine.context, createPrivateData, "actualPrivateData", 1)));
    const setup = try s.own(try engine.eval(
        \\(function(child,make,box){Object.defineProperty(child,'stdout',{configurable:true,get(){const A=make(box);throw A}})})
    , "actual-waiter-data-getter.js", c.JS_EVAL_TYPE_GLOBAL));
    _ = try s.call(setup, c.pi_js_undefined(), &.{ real_child, make, box });
    const function = try s.own(try waiter.create(engine));
    const pending = try s.call(function, c.pi_js_undefined(), &.{real_child}); c.JS_PromiseMarkAsHandled(engine.context, pending);
    try std.testing.expectEqual(@as(c_int, c.JS_PROMISE_REJECTED), c.JS_PromiseState(engine.context, pending));
    const reason = c.JS_PromiseResult(engine.context, pending); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, try s.get(box, "actual")));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try std.testing.expect(!c.JS_HasException(engine.context));
    try x.guest.put(&s, real_child, "stdout", stdout); // Replace the configurable accessor on success.
}

fn initialStdoutGetter(engine: *x.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, initialStdoutBody(&o, roots));
}
fn initialStdoutBody(o: *x.Ops, roots: []const c.JSValue) !c.JSValue {
    if (!o.truthy(try o.get(roots[1], "firstRead"))) {
        try o.put(roots[1], "firstRead", c.pi_js_bool(o.s.engine.context, 1));
        // This value is consumed only by Source's strict-null comparison.
        // Subsequent stream operations receive the actual OS pipe stream.
        return c.JS_DupValue(o.s.engine.context, try carrier(o, roots[1]));
    }
    return c.JS_DupValue(o.s.engine.context, roots[0]);
}
fn initialStderrGetter(engine: *x.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, initialStderrBody(&o, roots));
}
fn initialStderrBody(o: *x.Ops, roots: []const c.JSValue) !c.JSValue {
    if (!o.truthy(try o.get(roots[1], "checked"))) {
        try o.put(roots[1], "observed", try o.get(roots[1], "retired"));
        try o.put(roots[1], "checked", c.pi_js_bool(o.s.engine.context, 1));
    }
    return c.JS_DupValue(o.s.engine.context, roots[0]);
}
/// Real child and real listener/stream graph. Only the first stdout null-test
/// result is a sole native observer; it must retire before the stderr getter.
/// The original broad executor Scope observes zero, the corrected owner one.
pub fn verifyInitialNullProbeBeforeNextActualGetter(engine: *x.em.Engine, real_child: c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; defer s.deinit();
    const stdout = try s.get(real_child, "stdout"); const stderr = try s.get(real_child, "stderr");
    const box = try s.object();
    try s.put(box, "retired", c.JS_NewInt32(engine.context, 0));
    try s.put(box, "observed", c.JS_NewInt32(engine.context, -1));
    try s.put(box, "firstRead", c.pi_js_bool(engine.context, 0));
    try s.put(box, "checked", c.pi_js_bool(engine.context, 0));
    const get_stdout = try s.own(try f.createMethod(engine, "get stdout", 0, initialStdoutGetter, &.{ stdout, box }));
    const get_stderr = try s.own(try f.createMethod(engine, "get stderr", 0, initialStderrGetter, &.{ stderr, box }));
    try accessor(engine, real_child, "stdout", get_stdout); try accessor(engine, real_child, "stderr", get_stderr);
    const function = try s.own(try waiter.create(engine));
    const pending = try s.call(function, c.pi_js_undefined(), &.{real_child});
    c.JS_PromiseMarkAsHandled(engine.context, pending);
    try std.testing.expect(s.equal(try s.get(box, "observed"), c.JS_NewInt32(engine.context, 1)));
    try x.guest.put(&s, real_child, "stdout", stdout); try x.guest.put(&s, real_child, "stderr", stderr);
    return c.JS_DupValue(engine.context, pending);
}
