//! Real private Node v24.13 HTTP header checks. The complete common and
//! physical HTTP server owners are separate; these are actual value bodies.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const c = v.c;
const checks = @import("extensions/native_node_http_header_checks.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/native-node-http-header-checks-observer.mjs");
fn publish(s: *v.Scope, name: [*:0]const u8, value: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, value);
}
fn nativeFactory(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return checks.create(engine);
}
fn sourceFactory(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, sourceFactoryBody(&s, roots));
}
fn sourceFactoryBody(s: *v.Scope, roots: []const c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, roots[0], c.pi_js_undefined(), &.{roots[1]}));
}
fn prepare(engine: *v.em.Engine) !void {
    var s: v.Scope = .{ .engine = engine };
    try v.owned.finishVoid(&s, prepareBody(&s));
}
fn prepareBody(s: *v.Scope) !void {
    const engine = s.engine;
    engine.native_io = std.testing.io;
    const factory = try v.own(s, try engine.eval(
        @embedFile("extensions/fixtures/native-node-http-header-checks-v24-source.mjs"),
        "actual-node-v24-http-header-factory.js", c.JS_EVAL_TYPE_GLOBAL));
    const typed_constructor = try v.global(s, "Uint8Array");
    const reference = try v.call(s, factory, c.pi_js_undefined(), &.{typed_constructor});
    try publish(s, "headerSource", reference);
    try publish(s, "headerNative", try v.own(s, try checks.create(engine)));
    try publish(s, "headerCreateSource", try v.ordinary(s, "createSourceHTTPHeaderChecks", 0, sourceFactory, &.{factory, typed_constructor}));
    try publish(s, "headerCreateNative", try v.ordinary(s, "createNativeHTTPHeaderChecks", 0, nativeFactory, &.{}));
    try publish(s, "headerHooks", try v.own(s, try retirement.createNativeRetirementHooks(engine)));
}
fn run(engine: *v.em.Engine, source: []const u8) !void {
    engine.freeValue(try engine.evalModule(source, "actual-node-http-header-control.mjs"));
}
fn clean(engine: *v.em.Engine) !void {
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
fn both(comptime name: []const u8, comptime extra: []const u8) !void {
    inline for (.{ "headerSource", "headerNative" }) |subject| {
        const engine = try v.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 2_000_000 });
        defer engine.deinit(); try prepare(engine);
        try run(engine, observer ++ "\n" ++ name ++ "(" ++ subject ++ ",headerHooks" ++ extra ++ ");");
        try clean(engine);
    }
}
fn bothCreation(comptime name: []const u8) !void {
    inline for (.{ "headerCreateSource", "headerCreateNative" }) |subject| {
        const engine = try v.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 2_000_000 });
        defer engine.deinit(); try prepare(engine);
        try run(engine, observer ++ "\n" ++ name ++ "(" ++ subject ++ ");");
        try clean(engine);
    }
}
fn record(engine: *v.em.Engine) !c.JSValue {
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, recordBody(&s));
}
fn recordBody(s: *v.Scope) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.global(s, "headerHooks"), "record"));
}
fn noGuestCatch(engine: *v.em.Engine, original: c.JSValue) !void {
    const value = c.JS_GetPropertyStr(engine.context, original, "guestReached");
    defer engine.freeValue(value);
    try std.testing.expect(c.JS_IsBool(value) and c.JS_ToBool(engine.context, value) == 0);
}
test "Node HTTP header checks actual helper shapes and private regexp values" { try both("observeHeaderShapes", ""); }
test "Node HTTP header checks complete byte table and actual regex character ranges" { try both("observeHeaderMatrix", ""); }
test "Node HTTP header checks repeated live lengths and short-method order" { try both("observeHeaderShortOrder", ""); }
test "Node HTTP header checks predicate operands retire before later reads" { try both("observeHeaderPredicateRetirement", ""); }
test "Node HTTP header checks live regexp test returns actual private DATA" { try both("observeHeaderLongReturn", ""); }
test "Node HTTP header checks actual RegExp test consumes live exec behavior" { try both("observeHeaderLiveExec", ""); }
test "Node HTTP header checks callee and computed key retire before typed lookup" { try both("observeHeaderComputedKeyRetirement", ""); }
test "Node HTTP header checks same length getter private DATA stays ordinary" { try both("observeHeaderPrivateData", ",false"); }
test "Node HTTP header checks same regex getter private DATA stays ordinary" { try both("observeHeaderPrivateData", ",true"); }
test "Node HTTP header checks actual current B prevents later reads and guest catch" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nobserveHeaderCurrentFatal(headerNative,headerHooks);"));
    try retirement.verifyRecordedActualNativeFatal(engine, original);
    try retirement.verifyNoVisits(original, .{1,2});
    try noGuestCatch(engine, original);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "Node HTTP header checks actual key retirement B precedes the typed getter" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nobserveHeaderKeyFatal(headerNative,headerHooks);"));
    try retirement.verifyActualRetirementFatal(engine, original, 0);
    try retirement.verifyNoVisits(original, .{1,2,3});
    try noGuestCatch(engine, original);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "Node HTTP header checks creation uses retained real intrinsics" { try bothCreation("observeHeaderIntrinsicCreation"); }
test "Node HTTP header checks literal table uses actual iterable typed construction" { try bothCreation("observeHeaderTableIterator"); }
