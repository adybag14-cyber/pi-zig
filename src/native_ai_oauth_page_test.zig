//! Genuine c268 OAuth page helpers and original accepted runtime fixture.
//! The intrinsic template compiler correction is an explicit dependency.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const c = v.c;
const page = @import("extensions/native_ai_oauth_page.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/oauth-page-observer.mjs");

fn publish(s: *v.Scope, name: [*:0]const u8, value: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, value);
}
fn prepare(engine: *v.em.Engine) !void {
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, prepareBody(&s));
}
fn prepareBody(s: *v.Scope) !void {
    const actual = try v.own(s, try page.create(s.engine));
    const again = try v.own(s, try page.create(s.engine));
    try std.testing.expect(v.equal(s, actual, again));
    const reference = try v.own(s, try s.engine.evalModule(
        @embedFile("extensions/fixtures/oauth-page-c268-source.mjs"), "actual-c268-oauth-page.mjs"));
    try publish(s, "pageNative", actual);
    try publish(s, "pageSource", reference);
    try publish(s, "pageHooks", try v.own(s, try retirement.createNativeRetirementHooks(s.engine)));
}
fn run(engine: *v.em.Engine, source: []const u8) !void {
    const result = try engine.evalModule(source, "actual-oauth-page-control.mjs");
    engine.freeValue(result);
}
fn both(comptime tail: []const u8) !void {
    inline for (.{ "pageSource", "pageNative" }) |name| {
        const engine = try v.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
        defer engine.deinit(); try prepare(engine);
        try run(engine, observer ++ "\nconst pageSelected=" ++ name ++ ";\n" ++ tail);
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
    return v.duplicate(s, try v.get(s, try v.global(s, "pageHooks"), "record"));
}
test "AI OAuth page real ordinary exports cached owner and complete exact HTML" { try both("observePageBasic(pageSelected,pageSource);"); }
test "AI OAuth page performs five actual live replaceAll receiver calls" { try both("observePageChain(pageSelected);"); }
test "AI OAuth page input failures are synchronous and preserve getter identity" { try both("observePageInputFailures(pageSelected);"); }
test "AI OAuth page details predicate retires before its separate inherited read" { try both("observePagePredicate(pageSelected,pageHooks);"); }
test "AI OAuth page previous chained receiver and callee retire before next getter" { try both("observePageCallRetirement(pageSelected,pageHooks);"); }
test "AI OAuth page escaped locals survive eager intrinsic template conversion" { try both("observePageLocalsAndTemplates(pageSelected,pageHooks);"); }
test "AI OAuth page same-operation private DATA remains ordinary" { try both("observePagePrivateData(pageSelected,pageHooks);"); }
test "AI OAuth page current native B preempts the guest getter and catch" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nobservePageCurrentFatal(pageNative,pageHooks);"));
    try retirement.verifyRecordedActualNativeFatal(engine, original);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "AI OAuth page actual receiver retirement fatal blocks the following getter" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nobservePageRetirementFatal(pageNative,pageHooks);"));
    try retirement.verifyActualRetirementFatal(engine, original, 0);
    const reached = c.JS_GetPropertyStr(engine.context, original, "guestReached");
    defer engine.freeValue(reached);
    try std.testing.expect(c.JS_IsBool(reached) and c.JS_ToBool(engine.context, reached) == 0);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "AI OAuth page template rejection retires all locals and skips later conversion" { try both("observePageTemplateThrow(pageSelected,pageHooks);"); }
