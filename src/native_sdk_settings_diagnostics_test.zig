//! Genuine-VM differential controls for the complete original diagnostics
//! functions. No SDK manager, Set implementation or production error owner is
//! replaced: per-case descriptor inputs observe the original live operations.
const std = @import("std");
const h = @import("extensions/native_sdk_session_locals.zig");
const v = h.v;
const c = h.c;
const sdk = @import("extensions/native_sdk.zig");
const owner = @import("extensions/native_sdk_settings_diagnostics.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/sdk-settings-diagnostics-observer.mjs");
const original = @embedFile("extensions/fixtures/sdk-settings-diagnostics-4954-source.mjs");
fn publish(s: *h.Scope, name: [*:0]const u8, value: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, value);
}
fn prepare(engine: *h.Engine, source: bool) !void {
    var environment: std.process.Environ.Map = .init(engine.gpa);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"settings-diagnostics-control"});
    try @import("extensions/native_stream.zig").install(engine);
    return h.statement(engine, prepareBody, .{source});
}
fn prepareBody(s: *h.Scope, source: bool) !void {
    const engine = s.engine;
    const managers = try v.own(s, try sdk.managerImports(engine));
    const constructor = try v.get(s, managers, "SettingsManager");
    const manager = try v.invoke(s, constructor, "inMemory", &.{});
    const data = try v.own(s, v.duplicate(s, (try sdk.state(engine, manager)).data));
    const diagnostics = if (source) result: {
        const factory = try v.own(s, try engine.eval(original, "original-settings-diagnostics.js", c.JS_EVAL_TYPE_GLOBAL));
        break :result try v.call(s, factory, c.pi_js_undefined(), &.{});
    } else try v.own(s, try owner.create(engine));
    const subject = try v.object(s);
    try v.put(s, subject, "owner", diagnostics);
    try v.put(s, subject, "manager", manager);
    try v.put(s, subject, "data", data);
    try v.put(s, subject, "SettingsManager", constructor);
    try publish(s, "diagnosticSubject", subject);
    try publish(s, "diagnosticHooks", try v.own(s, try retirement.createNativeRetirementHooks(engine)));
}
fn run(engine: *h.Engine, source: []const u8) !void {
    const evaluation = try engine.evalModule(source, "actual-settings-diagnostics-control.mjs");
    defer engine.freeValue(evaluation);
    engine.freeValue(try engine.awaitValue(evaluation));
}
fn clean(engine: *h.Engine) !void {
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
fn observedBody(s: *h.Scope) !c.JSValue {
    return v.duplicate(s, try v.global(s, "diagnosticObserved"));
}
fn capture(comptime name: []const u8, source: bool) ![]u8 {
    const engine = try h.Engine.init(std.testing.allocator, .{ .interrupt_budget = 4_000_000 });
    defer engine.deinit();
    try prepare(engine, source);
    try run(engine, observer ++ "\nglobalThis.diagnosticObserved = JSON.stringify(await " ++ name ++ "(diagnosticSubject,diagnosticHooks));\n");
    const value = try h.expression(engine, observedBody, .{});
    defer engine.freeValue(value);
    try std.testing.expect(c.JS_IsString(value));
    try clean(engine);
    return engine.toString(value);
}
fn both(comptime name: []const u8) !void {
    const expected = try capture(name, true);
    defer std.testing.allocator.free(expected);
    const actual = try capture(name, false);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}
fn recordBody(s: *h.Scope) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.global(s, "diagnosticHooks"), "record"));
}
const Fatal = enum { current, retirement, cancelled };
fn fatal(comptime name: []const u8, comptime kind: Fatal) !void {
    const engine = try h.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine, false);
    const record = try h.expression(engine, recordBody, .{});
    defer engine.freeValue(record);
    try std.testing.expectError(error.JavaScriptException, run(engine,
        observer ++ "\n" ++ name ++ "(diagnosticSubject,diagnosticHooks);\n"));
    switch (kind) {
        .current => try retirement.verifyRecordedActualNativeFatal(engine, record),
        .retirement => try retirement.verifyActualRetirementFatal(engine, record, 0),
        .cancelled => try retirement.verifyActualCancellationNoGuestClose(engine, record),
    }
    try retirement.verifyNoVisits(record, .{1,2,3});
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "native settings diagnostics complete original ordinary export shapes" { try both("observeDiagnosticShapes"); }
test "native settings diagnostics genuine manager drains path and scope diagnostics exactly once" { try both("observeDiagnosticDrain"); }
test "native settings diagnostics genuine fromStorage load failure retains original message" { try both("observeDiagnosticStorage"); }
test "native settings diagnostics truthy path selection and original template conversions" { try both("observeDiagnosticPaths"); }
test "native settings diagnostics live map receiver arrow shape and direct return" { try both("observeDiagnosticLiveMap"); }
test "native settings diagnostics actual map preserves sparse error-array holes" { try both("observeDiagnosticSparseMap"); }
test "native settings diagnostics destructured scope path error Get ordering" { try both("observeDiagnosticDestructure"); }
test "native settings diagnostics primitive destructuring retains original shared wrapper" { try both("observeDiagnosticPrimitiveBox"); }
test "native settings diagnostics location conversion precedes error message Get and conversion" { try both("observeDiagnosticMessageOrder"); }
test "native settings diagnostics nullish rows reject after actual manager drain" { try both("observeDiagnosticNullishRow"); }
test "native settings diagnostics template symbol conversion failures match original" { try both("observeDiagnosticSymbols"); }
test "native settings diagnostics destructuring failure retains identity and suppresses later Get" { try both("observeDiagnosticDestructureFailure"); }
test "native settings diagnostics escaped map arrow survives outer invocation" { try both("observeDiagnosticMapEscape"); }
test "native settings diagnostics map lookup failure occurs after draining genuine manager" { try both("observeDiagnosticMapFailure"); }
test "native settings diagnostics deduplication preserves first type message identity and order" { try both("observeDiagnosticFirstOccurrence"); }
test "native settings diagnostics original NUL separator collision semantics" { try both("observeDiagnosticNulCollision"); }
test "native settings diagnostics actual sparse and generic filter behavior" { try both("observeDiagnosticSparseFilter"); }
test "native settings diagnostics live Set construction precedes filter lookup and call" { try both("observeDiagnosticSetOrder"); }
test "native settings diagnostics Set construction failure suppresses filter lookup" { try both("observeDiagnosticSetFailure"); }
test "native settings diagnostics live Set has add receiver key and duplicate suppression" { try both("observeDiagnosticHasAdd"); }
test "native settings diagnostics truthy has result retires before callback returns" { try both("observeDiagnosticTruthyHasRetirement"); }
test "native settings diagnostics ignored add result retires before acceptance returns" { try both("observeDiagnosticAddRetirement"); }
test "native settings diagnostics key type conversion precedes message lookup" { try both("observeDiagnosticKeyOrder"); }
test "native settings diagnostics key conversion throw suppresses message and retains identity" { try both("observeDiagnosticKeyFailure"); }
test "native settings diagnostics escaped predicates retain separate invocation Sets" { try both("observeDiagnosticEscape"); }
test "native settings diagnostics escaped predicate retains seen after filter throws" { try both("observeDiagnosticEscapeAfterThrow"); }
test "native settings diagnostics captured native seen lifetime matches original closure" { try both("observeDiagnosticSetLifetime"); }
test "native settings diagnostics successful private native Error remains ordinary thrown data" { try both("observeDiagnosticPrivateData"); }
test "native settings diagnostics destructured local retirement matches actual original VM" { try both("observeDiagnosticRowLifetime"); }
test "native settings diagnostics ordinary function constructor primitive return semantics" { try both("observeDiagnosticConstructorReturn"); }

test "native settings diagnostics current native fatal preempts guest catch and later reads" { try fatal("observeDiagnosticCurrentFatal", .current); }
test "native settings diagnostics has result retirement fatal prevents guest continuation" { try fatal("observeDiagnosticHasRetirementFatal", .retirement); }
test "native settings diagnostics has result retirement cancellation prevents guest continuation" { try fatal("observeDiagnosticHasRetirementCancel", .cancelled); }
test "native settings diagnostics pending entry precedes cold or warm private cache" {
    inline for (.{ false, true }) |warm| {
        const engine = try h.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        if (warm) engine.freeValue(try owner.create(engine));
        const reason = try sdk.object(engine);
        defer engine.freeValue(reason);
        _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
        try std.testing.expectError(error.JavaScriptException, owner.create(engine));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception orelse return error.MissingOriginalPending));
        try std.testing.expectEqual(warm, engine.native_module_values.contains("pi-private:actual-sdk-settings-diagnostics"));
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
}
test "native settings diagnostics complete private owner is cached with stable function identity" {
    const engine = try h.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const a = try owner.create(engine);
    defer engine.freeValue(a);
    const b = try owner.create(engine);
    defer engine.freeValue(b);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, a, b));
    inline for (.{ "collectSettingsDiagnostics", "deduplicateDiagnostics" }) |name| {
        const av = try h.get(engine, a, name);
        defer engine.freeValue(av);
        const bv = try h.get(engine, b, name);
        defer engine.freeValue(bv);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, av, bv));
        try std.testing.expect(c.JS_IsFunction(engine.context, av));
    }
    try clean(engine);
}
