//! Actual c268 callback bodies with the same explicit HTTP import host in both
//! realms. Real page/AbortController/URL owners remain active. This group does
//! not qualify physical node:http sockets or public provider login composition.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const c = v.c;
const callback = @import("extensions/native_ai_oauth_callback_server.zig");
const page = @import("extensions/native_ai_oauth_page.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/oauth-callback-server-observer.mjs");
const host_source =
    \\const state = {};
    \\const apply = Reflect.apply;
    \\function createServer(...args) { return apply(state.createServer, this, args); }
    \\export const http = { createServer };
    \\export { state };
;
fn publish(s: *v.Scope, name: [*:0]const u8, value: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, value);
}
fn prepare(engine: *v.em.Engine) !void {
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/native_url.zig").install(engine);
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, prepareBody(&s));
}
fn prepareBody(s: *v.Scope) !void {
    const host = try v.own(s, try s.engine.evalModule(host_source, "actual-callback-import-host.mjs"));
    const http = try v.get(s, host, "http");
    const page_native = try v.own(s, try page.create(s.engine));
    const page_source = try v.own(s, try s.engine.evalModule(
        @embedFile("extensions/fixtures/oauth-page-c268-source.mjs"), "actual-c268-callback-page.mjs"));
    const actual = try v.own(s, try callback.createWithInputs(s.engine, .{ .http = http, .page = page_native }));
    const again = try v.own(s, try callback.createWithInputs(s.engine, .{ .http = http, .page = page_native }));
    try std.testing.expect(v.equal(s, actual, again));
    const dependencies = try v.object(s);
    try v.put(s, dependencies, "http", http);
    try v.put(s, dependencies, "page", page_source);
    try publish(s, "__oauthCallbackSourceDependencies", dependencies);
    const reference = try v.own(s, try s.engine.evalModule(
        @embedFile("extensions/fixtures/oauth-callback-server-c268-source.mjs"), "actual-c268-callback-server.mjs"));
    try publish(s, "callbackNative", actual);
    try publish(s, "callbackSource", reference);
    try publish(s, "callbackControl", try v.get(s, host, "state"));
    try publish(s, "callbackPageSource", page_source);
    try publish(s, "callbackHooks", try v.own(s, try retirement.createNativeRetirementHooks(s.engine)));
}
fn run(engine: *v.em.Engine, source: []const u8) !void {
    const result = try engine.evalModule(source, "actual-callback-source-control.mjs");
    engine.freeValue(result);
}
fn both(comptime tail: []const u8) !void {
    inline for (.{ "callbackSource", "callbackNative" }) |name| {
        const engine = try v.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 2_000_000 });
        defer engine.deinit();
        try prepare(engine);
        try run(engine, observer ++ "\nconst callbackSelected = " ++ name ++ ";\n" ++ tail);
        try std.testing.expect(engine.native_fatal_invocation == null);
        try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
        try std.testing.expect(!c.JS_HasException(engine.context));
        try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    }
}
fn record(engine: *v.em.Engine) !c.JSValue {
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, recordBody(&s));
}
fn recordBody(s: *v.Scope) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.global(s, "callbackHooks"), "record"));
}
fn currentFatal(comptime mode: []const u8) !void {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++
        "\nawait observeCallbackCurrentFatal(callbackNative,callbackControl,callbackHooks,\"" ++ mode ++ "\");"));
    try retirement.verifyRecordedActualNativeFatal(engine, original);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "AI OAuth callback genuine declarations and actual cached module owner" { try both("await observeCallbackShapes(callbackSelected);"); }
test "AI OAuth callback performs real listen Await before hooks and redirect URI" { try both("await observeCallbackListen(callbackSelected,callbackControl);"); }
test "AI OAuth callback actual request routes send complete real page output" { try both("await observeCallbackRoutes(callbackSelected,callbackControl,callbackPageSource);"); }
test "AI OAuth callback one request Await shares claimed state and exact completed identity" { try both("await observeCallbackCompletion(callbackSelected,callbackControl,callbackPageSource);"); }
test "AI OAuth callback request catch normalizes ordinary failure and preserves Error identity" { try both("await observeCallbackRequestCatch(callbackSelected,callbackControl,callbackPageSource);"); }
test "AI OAuth callback initial abort listen rejection and non TCP address follow Source boundaries" { try both("await observeCallbackStartFailures(callbackSelected,callbackControl);"); }
test "AI OAuth callback abort timeout and settled finish use actual cleanup order" { try both("await observeCallbackAbortTimeout(callbackSelected,callbackControl);"); }
test "AI OAuth callback uses two live Promise constructors with an intrinsic async result" { try both("await observeCallbackPromise(callbackSelected,callbackControl);"); }
test "AI OAuth callback binds options with one ToObject before subsequent live reads" { try both("await observeCallbackBindings(callbackSelected,callbackControl,callbackHooks);"); }
test "AI OAuth callback manual and callback routes perform actual two Await and abort" { try both("await observeCallbackManual(callbackSelected,callbackControl);"); }
test "AI OAuth callback manual rejection callback rejection and finally override keep Source identity" { try both("await observeCallbackManualFailures(callbackSelected);"); }
test "AI OAuth callback initial prompt and then failures precede the Source try" { try both("await observeCallbackPromptOutsideTry(callbackSelected);"); }
test "AI OAuth callback late Promise executor assigns the original closed waiter cells" { try both("await observeCallbackLateExecutor(callbackSelected,callbackControl);"); }
test "AI OAuth callback finish performs the actual inherited error in operation" { try both("await observeCallbackInheritedError(callbackSelected,callbackControl);"); }
test "AI OAuth callback URL constructor and argument retire before request method" { try both("await observeCallbackRequestOperands(callbackSelected,callbackControl,callbackHooks);"); }
test "AI OAuth callback state predicate and searchParams call retire before separate reads" { try both("await observeCallbackStatePredicate(callbackSelected,callbackControl,callbackHooks);"); }
test "AI OAuth callback prompt then and catch receivers retire at actual call boundaries" { try both("await observeCallbackManualChain(callbackSelected,callbackHooks);"); }
test "AI OAuth callback Error predicate and String call retire before following construction" { try both("await observeCallbackNormalizedError(callbackSelected,callbackHooks);"); }
test "AI OAuth callback listener retains only options after Start terminal argument retirement" { try both("await observeCallbackStartCaptures(callbackSelected,callbackControl,callbackHooks);"); }
test "AI OAuth callback request captures and URL local survive Await until actual terminal" { try both("await observeCallbackRequestCaptures(callbackSelected,callbackControl,callbackHooks);"); }
test "AI OAuth callback same operation private DATA remains ordinary in three actual bodies" {
    inline for (.{ "start", "manual", "request" }) |mode| try both(
        "await observeCallbackPrivateData(callbackSelected,callbackControl,callbackHooks,\"" ++ mode ++ "\");");
}
test "AI OAuth callback actual current B in options getter preempts guest catch" { try currentFatal("start"); }
test "AI OAuth callback actual current B in manual prompt getter preempts guest catch" { try currentFatal("manual"); }
test "AI OAuth callback actual state predicate retirement fatal prevents later reads" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++
        "\nawait observeCallbackPredicateFatal(callbackNative,callbackControl,callbackHooks);"));
    try retirement.verifyActualRetirementFatal(engine, original, 0);
    const reached = c.JS_GetPropertyStr(engine.context, original, "guestReached"); defer engine.freeValue(reached);
    try std.testing.expect(c.JS_IsBool(reached) and c.JS_ToBool(engine.context, reached) == 0);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
