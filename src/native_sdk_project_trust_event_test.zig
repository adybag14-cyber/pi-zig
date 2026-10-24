//! Actual original runner function and native owner, in separate VM realms.
//! Source-only authored controls; no compiler, metadata, or runtime result claimed.
const std = @import("std");
const h = @import("extensions/native_sdk_session_locals.zig");
const v = h.v;
const c = h.c;
const subject_owner = @import("extensions/native_sdk_project_trust_event.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/sdk-project-trust-event-observer.mjs");

fn brand(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_bool(context, @intFromBool(argc > 0 and c.JS_IsAsyncFunction(argv[0])));
}
fn collect(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(c.JS_GetRuntime(context));
    return c.pi_js_undefined();
}
fn promisePending(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_bool(context, @intFromBool(argc > 0 and
        c.JS_PromiseState(context, argv[0]) == c.JS_PROMISE_PENDING));
}
fn pendingNormal(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const global = c.JS_GetGlobalObject(context);
    const reason = c.JS_GetPropertyStr(context, global, "trustPendingReason");
    c.JS_FreeValue(context, global);
    _ = c.JS_Throw(context, reason); // Actual pending event plus a normal return.
    return c.JS_NewInt32(context, 17);
}
fn prepareBody(s: *h.Scope) !void {
    const engine = s.engine;
    engine.native_io = std.testing.io;
    const global = try v.own(s, c.JS_GetGlobalObject(engine.context));
    const native = try v.own(s, try subject_owner.create(engine));
    const repeated = try v.own(s, try subject_owner.create(engine));
    try std.testing.expect(v.equal(s, native, repeated));
    const source = try v.own(s, try engine.eval(
        @embedFile("extensions/fixtures/sdk-project-trust-event-original.mjs"),
        "original-runner-project-trust-function.js", c.JS_EVAL_TYPE_GLOBAL));
    try v.put(s, global, "trustEventNative", native);
    try v.put(s, global, "trustEventSource", source);
    try v.put(s, global, "trustEventHooks", try v.own(s, try retirement.createNativeRetirementHooks(engine)));
    try v.put(s, global, "trustEventIsAsync", try v.own(s, try engine.checked(
        c.JS_NewCFunction(engine.context, brand, "trustEventIsAsync", 1))));
    try v.put(s, global, "trustEventGC", try v.own(s, try engine.checked(
        c.JS_NewCFunction(engine.context, collect, "trustEventGC", 0))));
    try v.put(s, global, "trustEventPromisePending", try v.own(s, try engine.checked(
        c.JS_NewCFunction(engine.context, promisePending, "trustEventPromisePending", 1))));
    try v.put(s, global, "trustEventPendingNormal", try v.own(s, try engine.checked(
        c.JS_NewCFunction(engine.context, pendingNormal, "trustEventPendingNormal", 0))));
}
fn prepare(engine: *h.Engine) !void { return h.statement(engine, prepareBody, .{}); }
fn run(engine: *h.Engine, source: []const u8) !void {
    engine.freeValue(try engine.evalModule(source, "native-project-trust-event-control.mjs"));
}
fn clean(engine: *h.Engine) !void {
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
fn both(comptime name: []const u8, comptime arguments: []const u8) !void {
    inline for (.{ "trustEventSource", "trustEventNative" }) |selected| {
        const engine = try h.Engine.init(std.testing.allocator, .{ .interrupt_budget = 2_000_000 });
        defer engine.deinit();
        try prepare(engine);
        try run(engine, observer ++ "\nawait " ++ name ++ "(" ++ selected ++ arguments ++ ");\n");
        try clean(engine);
    }
}
fn recordBody(s: *h.Scope) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.global(s, "trustEventHooks"), "record"));
}
fn record(engine: *h.Engine) !c.JSValue { return h.expression(engine, recordBody, .{}); }

test "native project trust event genuine AsyncFunction cached identity and fresh empty result" {
    try both("observeTrustEventShape", "");
}
test "native project trust event snapshots every extension through live map get slice before dispatch" {
    try both("observeTrustEventSnapshot", "");
}
test "native project trust event optional slice and nullish fallback allocate distinct arrays" {
    try both("observeTrustEventNullish", "");
}
test "native project trust event handlers and extension list are snapshotted across intrinsic Await" {
    try both("observeTrustEventSnapshotMutation", "");
}
test "native project trust event plain handler values suspend before trusted lookup" {
    try both("observeTrustEventPlainAwait", "");
}
test "native project trust event intrinsic Await adopts thenable without public Promise then" {
    try both("observeTrustEventThenable", "");
}
test "native project trust event synchronous throw records error and continues before returning Promise" {
    try both("observeTrustEventFailures", ",false");
}
test "native project trust event genuine rejected Await uses original catch and first deciding result" {
    try both("observeTrustEventFailures", ",true");
}
test "native project trust event null result is caught and undefined trusted still wins" {
    try both("observeTrustEventLooseResult", "");
}
test "native project trust event trusted getter remains inside catch with ordinary String fallback" {
    try both("observeTrustEventTrustedFailure", "");
}
test "native project trust event push path type and repeated live Error checks follow object literal order" {
    try both("observeTrustEventFormatOrder", ",false");
}
test "native project trust event live String call and second independent instanceof remain observable" {
    try both("observeTrustEventFormatOrder", ",true");
}
test "native project trust event snapshot failure prevents every handler before any iterator starts" {
    try both("observeTrustEventSnapshotFailure", "");
}
test "native project trust event generic outer and inner iterators cache next and exhaust without return" {
    try both("observeTrustEventGenericIteration", "");
}
test "native project trust event primitive snapshot row is boxed once for both binding getters" {
    try both("observeTrustEventPrimitiveRow", "");
}
test "native project trust event failed inner next skips its own return and closes outer" {
    try both("observeTrustEventStepFailure", ",'innerStepFailure'");
}
test "native project trust event failed iterator value lookup skips own return and closes outer" {
    try both("observeTrustEventStepFailure", ",'valueFailure'");
}
test "native project trust event failed iterator done lookup skips own return and closes outer" {
    try both("observeTrustEventStepFailure", ",'doneFailure'");
}
test "native project trust event nonobject next result rejects before inner IteratorClose" {
    try both("observeTrustEventStepFailure", ",'nonobjectStep'");
}
test "native project trust event failed outer next never calls its own return" {
    try both("observeTrustEventStepFailure", ",'outerStepFailure'");
}
test "native project trust event inner next getter failure precedes creation of its catch record" {
    try both("observeTrustEventStartFailure", ",false");
}
test "native project trust event noniterable inner value closes existing outer record" {
    try both("observeTrustEventStartFailure", ",true");
}
test "native project trust event successful result closes inner then outer with exact receivers" {
    try both("observeTrustEventReturnClose", "");
}
test "native project trust event primitive inner return is TypeError and later outer throw cannot replace it" {
    try both("observeTrustEventBadClose", ",'inner'");
}
test "native project trust event primitive outer return fails outside handler catch" {
    try both("observeTrustEventBadClose", ",'outer'");
}
test "native project trust event noncallable return method fails and closes outer" {
    try both("observeTrustEventBadClose", ",'noncallable'");
}
test "native project trust event formatting getter failure closes both iterators preserving first throw" {
    try both("observeTrustEventFormattingFailure", ",false");
}
test "native project trust event errors push getter precedes row fields and its throw closes both iterators" {
    try both("observeTrustEventFormattingFailure", ",true");
}
test "native project trust event throw IteratorClose ignores primitive close results" {
    try both("observeTrustEventThrowClosePrimitive", "");
}
test "native project trust event nested invocation retains independent suspended activation" {
    try both("observeTrustEventReentry", "");
}
test "native project trust event successful private DATA thrown synchronously remains ordinary" {
    try both("observeTrustEventPrivateData", ",trustEventHooks,false");
}
test "native project trust event private DATA in rejected Await is not inferred to be fatal" {
    try both("observeTrustEventPrivateData", ",trustEventHooks,true");
}
test "native project trust event actual arguments unused extra argument and receiver survive GC across Await" {
    try both("observeTrustEventAwaitRoots", ",trustEventHooks");
}
test "native project trust event abandoned actual suspension retires arguments without settling outer Promise" {
    try both("observeTrustEventAbandonedRoots", ",trustEventHooks");
}
test "native project trust event actual pending exception beats a normal native handler return" {
    const engine = try h.Engine.init(std.testing.allocator, .{});
    defer engine.deinit(); try prepare(engine);
    try run(engine, observer ++ "\nawait observeTrustEventPendingNormal(trustEventNative);");
    try clean(engine);
}
test "native project trust event actual native fatal before Await bypasses catch formatting and iterator close" {
    const engine = try h.Engine.init(std.testing.allocator, .{});
    defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++
        "\nawait observeTrustEventFatal(trustEventNative,trustEventHooks,false);"));
    try retirement.verifyRecordedActualNativeFatal(engine, original);
    try retirement.verifyNoVisits(original, .{ 1, 2, 3 });
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "native project trust event actual native fatal after Await bypasses handler catch and outer catch" {
    const engine = try h.Engine.init(std.testing.allocator, .{});
    defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++
        "\nawait observeTrustEventFatal(trustEventNative,trustEventHooks,true);"));
    try retirement.verifyRecordedActualNativeFatal(engine, original);
    try retirement.verifyNoVisits(original, .{ 1, 2, 3 });
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "native project trust event trusted temporary retirement fatal occurs before normal IteratorClose" {
    const engine = try h.Engine.init(std.testing.allocator, .{});
    defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++
        "\nawait observeTrustEventRetirementFatal(trustEventNative,trustEventHooks,false);"));
    try retirement.verifyActualRetirementFatal(engine, original, 0);
    try retirement.verifyNoVisits(original, .{ 1, 2, 3 });
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "native project trust event trusted temporary cancellation bypasses guest catch and close" {
    const engine = try h.Engine.init(std.testing.allocator, .{});
    defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++
        "\nawait observeTrustEventRetirementFatal(trustEventNative,trustEventHooks,true);"));
    try retirement.verifyActualCancellationNoGuestClose(engine, original);
    try retirement.verifyNoVisits(original, .{ 1, 2, 3 });
    try std.testing.expect(engine.native_fatal_invocation == null);
}

test "native project trust event escaped snapshot arrow retains original captured event after activation exits" {
    try both("observeTrustEventEscapedSnapshot", "");
}
test "native project trust event instanceof constructor operands retire before message and stack getters" {
    try both("observeTrustEventConstructorRetirement", ",trustEventHooks");
}
test "native project trust event trusted comparison temporary retires before normal IteratorClose" {
    try both("observeTrustEventTrustedRetirement", ",trustEventHooks");
}
