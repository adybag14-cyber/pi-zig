//! Additive genuine native controls, prepared and UNRUN. No original rows,
//! parser implementation, URL result or expected JSON is manufactured here.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const x = @import("extensions/native_sdk_git_url_values.zig");
const f = @import("extensions/native_node_function.zig");
const parser = @import("extensions/native_sdk_git_url.zig");
const c = v.c;
const Carrier = struct { engine: *v.em.Engine, secondary: c.JSValue, box: c.JSValue, fatal: bool };
fn retire(rt: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
    const state: *Carrier = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    const engine = state.engine;
    _ = c.JS_DefinePropertyValueStr(engine.context, state.box, "retired", c.JS_NewInt32(engine.context, 1), c.JS_PROP_C_W_E);
    if (state.fatal) {
        _ = engine.throwNativeOutOfMemoryFatal();
        const reason = c.JS_GetException(engine.context);
        _ = c.JS_DefinePropertyValueStr(engine.context, state.box, "actualFatal", c.JS_DupValue(engine.context, reason), c.JS_PROP_C_W_E);
        _ = c.JS_Throw(engine.context, reason);
    } else _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, state.secondary));
    c.JS_FreeValueRT(rt, state.secondary); c.JS_FreeValueRT(rt, state.box);
    engine.gpa.destroy(state); c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Carrier));
}
fn mark(rt: ?*c.JSRuntime, object: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Carrier = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    c.JS_MarkValue(rt, state.secondary, visit); c.JS_MarkValue(rt, state.box, visit);
}
fn throwPrimary(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, roots[0])));
}
fn makeTrim(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, makeTrimBody(&o, roots));
}
fn makeTrimBody(o: *x.Ops, roots: []const c.JSValue) !c.JSValue {
    const engine = o.s.engine;
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(Carrier)) == 0) return error.OutOfMemory;
    var attached = false;
    errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Carrier));
    const state = try engine.gpa.create(Carrier); errdefer if (!attached) engine.gpa.destroy(state);
    var id: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &id);
    const definition: c.JSClassDef = .{ .class_name = "Actual Git callback carrier", .finalizer = retire, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const carrier = try o.own(try engine.checked(c.JS_NewObjectClass(engine.context, id)));
    state.* = .{ .engine = engine, .secondary = c.JS_DupValue(engine.context, roots[1]), .box = c.JS_DupValue(engine.context, roots[2]), .fatal = c.JS_ToBool(engine.context, roots[3]) != 0 };
    _ = c.JS_SetOpaque(carrier, state); attached = true;
    return f.createArrow(engine, "actualTrim", 0, throwPrimary, &.{ roots[0], carrier });
}
fn actualNodeUrl(engine: *v.em.Engine) !c.JSValue { return engine.native_module_values.get("node:url") orelse error.RequiredActualNodeUrlNamespace; }
/// The actual parser obtains a sole callback carrier from its live trim getter.
/// The callback throws A; its real native finalizer then publishes ordinary B
/// or fresh fatal C during the parser's actual Scope retirement.
pub fn verifyFirstReasonAcrossActualCarrierRetirement(engine: *v.em.Engine, fatal: bool) !void {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const actual = try s.own(try parser.create(engine, try actualNodeUrl(engine)));
    const parse = try s.get(actual, "parseGitUrl");
    const primary = try s.object(); const secondary = try s.object(); const box = try s.object();
    try s.put(box, "retired", c.JS_NewInt32(engine.context, 0)); try s.put(box, "actualFatal", c.pi_js_undefined());
    const getter = try s.own(try f.create(engine, "get trim", 0, makeTrim, &.{ primary, secondary, box, c.pi_js_bool(engine.context, @intFromBool(fatal)) }));
    const source = try s.object(); const atom = c.JS_NewAtom(engine.context, "trim"); if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, source, atom, c.JS_DupValue(engine.context, getter), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return v.js.capture(engine);
    var args = [_]c.JSValue{source};
    const result = c.JS_Call(engine.context, parse, c.pi_js_undefined(), 1, &args); defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result));
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    const retired = try s.get(box, "retired");
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, retired, c.JS_NewInt32(engine.context, 1)));
    const expected = if (fatal) try s.get(box, "actualFatal") else primary;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, expected));
    try std.testing.expectEqual(fatal, c.JS_IsUncatchableError(reason));
    // Fresh-realm teardown, with no guest restoration after a failed assertion.
}
pub fn verifyWeakMapCannotAdmitPrivateStringKeyCache(engine: *v.em.Engine) !void {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    const weak = try s.global("WeakMap");
    if (c.JS_SetPropertyStr(engine.context, global, "Map", c.JS_DupValue(engine.context, weak)) < 0) return v.js.capture(engine);
    const result = parser.create(engine, try actualNodeUrl(engine));
    if (result) |value| { engine.freeValue(value); return error.WeakMapIncorrectlyAdmitted; }
    else |err| try std.testing.expect(err == error.JavaScriptException);
    const reason = engine.captured_exception orelse return error.MissingMapAdmissionReason;
    const message = try s.get(reason, "message");
    try std.testing.expect(s.truthy(try s.invoke(message, "includes", &.{try s.text("UnsupportedHostedGitMapConstructorInterposition")})));
}
fn pendingSetter(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    _ = c.JS_ThrowTypeError(context, "actual successful-status setter event");
    // A deliberately genuine native producer with successful status + pending.
    // This tests the raw C status boundary, not a fabricated URL/parser result.
    return c.pi_js_undefined();
}
pub fn verifySuccessfulSetterStatusSurfacesActualPending(engine: *v.em.Engine) !void {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit(); var o: x.Ops = .{ .s = &s };
    const target = try s.object();
    const setter = try s.own(try engine.checked(c.JS_NewCFunction(engine.context, pendingSetter, "actualGitPendingSetter", 1)));
    const atom = c.JS_NewAtom(engine.context, "pathname"); if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, target, atom, c.pi_js_undefined(), c.JS_DupValue(engine.context, setter), c.JS_PROP_CONFIGURABLE) < 0) return v.js.capture(engine);
    const raw_value = try s.text("/raw-status");
    const raw_status = c.JS_SetPropertyStr(engine.context, target, "pathname", c.JS_DupValue(engine.context, raw_value));
    try std.testing.expect(raw_status >= 0);
    try std.testing.expect(c.JS_HasException(engine.context));
    const raw_reason = c.JS_GetException(engine.context); defer engine.freeValue(raw_reason);
    o.set(target, "pathname", try s.text("/actual")) catch |err| {
        try std.testing.expect(err == error.JavaScriptException);
        try std.testing.expect(engine.captured_exception != null or c.JS_HasException(engine.context));
        return;
    };
    return error.SuccessfulStatusIgnoredActualPending;
}
pub fn verifyFactoryDoesNotDiagnoseOrdinaryGetterReason(engine: *v.em.Engine) !void {
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    const setup = try engine.evalModule(
        \\globalThis.actualGitDiagnosticReads=0;
        \\globalThis.actualGitCreateReason={get toString(){actualGitDiagnosticReads++;throw new Error('must not diagnose')}};
        \\Object.defineProperty(Object,'assign',{configurable:true,get(){throw actualGitCreateReason}});
    , "actual-git-factory-getter.mjs"); engine.freeValue(setup);
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    const primary = try s.get(global, "actualGitCreateReason");
    const suppression = engine.native_exception_diagnostics_suppressed;
    if (parser.create(engine, try actualNodeUrl(engine))) |value| {
        engine.freeValue(value); return error.FactoryUnexpectedlyIgnoredGetterFailure;
    } else |err| try std.testing.expect(err == error.JavaScriptException);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, primary, engine.captured_exception orelse return error.FactoryReasonLost));
    const reads = try s.get(global, "actualGitDiagnosticReads");
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reads, c.JS_NewInt32(engine.context, 0)));
    try std.testing.expectEqual(suppression, engine.native_exception_diagnostics_suppressed);
    // No guest restore after failure; this entry owns a fresh realm.
}
