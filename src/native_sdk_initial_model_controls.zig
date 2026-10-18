//! Prepared source-only controls. Inputs MUST come from the actual native
//! application owner's graph.imports / factoryExports(), never a fabricated
//! completed namespace, Models class, resource loader, or session constructor.
const std = @import("std");
const x = @import("extensions/native_sdk_initial_model_values.zig");
const c = x.c;
pub fn verifyActualAsyncMetadata(engine: *x.em.Engine, actual_imports: c.JSValue) !void {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishVoid(&s, metadata(&o, actual_imports));
}
fn metadata(o: *x.Ops, actual_imports: c.JSValue) !void {
    const function = try o.get(actual_imports, "findInitialModel");
    try std.testing.expect(c.JS_IsAsyncFunction(function));
    try std.testing.expect(!c.JS_IsConstructor(o.s.engine.context, function));
    try std.testing.expect(o.equal(try o.get(function, "length"), c.JS_NewInt32(o.s.engine.context, 1)));
    try std.testing.expect(o.equal(try o.get(function, "name"), try o.text("findInitialModel")));
}
/// real_subject.actualCases supplies actual scoped/saved/snapshot/empty inputs
/// with real modelRuntime instances. Borrowed receiver negatives are explicitly
/// labelled in the common Source/native fixture. This returns a real Promise;
/// Root owns its admitted job pump, original comparison and realm retirement.
pub fn startActualResolverCaller(engine: *x.em.Engine, actual_imports: c.JSValue, real_subject: c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, resolverCaller(&o, actual_imports, real_subject));
}
fn resolverCaller(o: *x.Ops, actual_imports: c.JSValue, real_subject: c.JSValue) !c.JSValue {
    const e = o.s.engine;
    const caller = try o.own(try e.eval(@embedFile("extensions/fixtures/sdk-initial-model-caller.mjs"), "actual-initial-model-caller.js", c.JS_EVAL_TYPE_GLOBAL));
    return c.JS_DupValue(e.context, try o.call(caller, c.pi_js_undefined(), &.{ actual_imports, real_subject }));
}
/// Direct real factory caller. Actual startup options must omit a supplied
/// model and have no restorable session model. Root's application owner keeps
/// the actual runtime/services/resources alive and retires the returned real
/// AgentSession through the genuine lifecycle after observation. This function
/// creates no alternate factory and does not claim startup/fullapp qualification.
pub fn startActualFactoryCaller(engine: *x.em.Engine, actual_factory_exports: c.JSValue, actual_startup_options: c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, factoryCaller(&o, actual_factory_exports, actual_startup_options));
}
fn factoryCaller(o: *x.Ops, actual_factory_exports: c.JSValue, actual_startup_options: c.JSValue) !c.JSValue {
    const factory = try o.get(actual_factory_exports, "createAgentSession");
    try std.testing.expect(c.JS_IsAsyncFunction(factory));
    return c.JS_DupValue(o.s.engine.context, try o.call(factory, c.pi_js_undefined(), &.{actual_startup_options}));
}
pub fn verifyAcceptedOriginalRows(engine: *x.em.Engine, actual_rows: c.JSValue, accepted_original_rows: c.JSValue) !void {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishVoid(&s, compare(&o, actual_rows, accepted_original_rows));
}
fn compare(o: *x.Ops, actual_rows: c.JSValue, accepted_original_rows: c.JSValue) !void {
    const json = try o.global("JSON"); const stringify = try o.get(json, "stringify");
    const actual = try o.call(stringify, json, &.{actual_rows});
    const original = try o.call(stringify, json, &.{accepted_original_rows});
    try std.testing.expect(o.equal(actual, original));
}
/// C/AF pending-before-body prerequisite, exercised on the REAL installed
/// resolver export. No options getter may run before this actual event exits.
pub fn verifyActualPendingBeforeEntry(engine: *x.em.Engine, actual_imports: c.JSValue) !void {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishVoid(&s, pendingBeforeEntry(&o, actual_imports));
}
fn pendingBeforeEntry(o: *x.Ops, actual_imports: c.JSValue) !void {
    const e = o.s.engine; const function = try o.get(actual_imports, "findInitialModel");
    const reason = try o.object();
    _ = c.JS_Throw(e.context, c.JS_DupValue(e.context, reason));
    const raw = c.JS_Call(e.context, function, c.pi_js_undefined(), 0, null);
    // Record the actual call outcome before any returned native root retires.
    var observed = x.owned.Completion.initValue(e, @as(anyerror!c.JSValue, error.JavaScriptException));
    const exceptional = c.JS_IsException(raw);
    if (!exceptional) observed.release(raw);
    const action = try observed.finishAction();
    switch (action) {
        .thrown => |actual| {
            const equal = o.equal(actual, reason); _ = try o.own(actual);
            try std.testing.expect(exceptional and equal);
        },
        .returned, .awaited => |value| { _ = try o.own(value); return error.PendingInitialModelEntryWasLost; },
    }
}
/// A manually flagged/private-tagged historical diagnostic is intentionally
/// DATA. It is not an actual current NativeInvocation event. Real valid options
/// must still produce the genuine outer Promise; payload flags are unchanged.
pub fn verifyFlaggedHistoricalDiagnosticData(engine: *x.em.Engine, actual_imports: c.JSValue, actual_options: c.JSValue) !void {
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishVoid(&s, historicalData(&o, actual_imports, actual_options));
}
fn historicalData(o: *x.Ops, actual_imports: c.JSValue, actual_options: c.JSValue) !void {
    const e = o.s.engine;
    try std.testing.expect(e.captured_exception == null and !c.JS_HasException(e.context));
    const function = try o.get(actual_imports, "findInitialModel");
    const generation = e.native_allocation_generation;
    const reason = try o.allocation(c.JS_NewError(e.context), generation);
    c.JS_SetUncatchableError(e.context, reason);
    c.pi_js_mark_native_allocation_error(reason, if (generation == 0) 1 else generation);
    e.captured_exception = c.JS_DupValue(e.context, reason);
    const promise = try o.call(function, c.pi_js_undefined(), &.{actual_options});
    try std.testing.expect(c.JS_PromiseState(e.context, promise) >= 0);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(!c.JS_HasException(e.context));
}
