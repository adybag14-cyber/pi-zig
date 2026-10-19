//! Actual c268 context helpers in separate Source/native Engines.
//! Controls exercise the real regexp, original shared source-info/range owners,
//! canonical C435 retirement, and actual current-fatal/cancellation boundaries.
const std = @import("std");
const h = @import("extensions/native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const helpers = @import("extensions/native_sdk_public_context_helpers.zig");
const source_info = @import("extensions/native_sdk_source_information.zig");
const range = @import("extensions/native_sdk_read_line_range.zig");
const PromptScope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/sdk-context-helpers-observer.mjs");

fn publish(s: *h.Scope, name: [*:0]const u8, input: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, input);
}
fn rendererCall(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: PromptScope = .{ .engine = engine };
    return v.owned.finishValue(&s, rendererBody(&s, args));
}
fn rendererBody(s: *PromptScope, args: []const c.JSValue) !c.JSValue {
    return h.duplicate(s.engine, try range.format(s, v.arg(args, 0), v.arg(args, 1)));
}
fn prepare(engine: *h.Engine) !void {
    return h.statement(engine, prepareBody, .{});
}
fn prepareBody(s: *h.Scope) !void {
    const engine = s.engine;
    const native = try v.own(s, try helpers.create(engine));
    const repeated = try v.own(s, try helpers.create(engine));
    try std.testing.expect(v.equal(s, native, repeated));
    const info = try v.own(s, try source_info.create(engine));
    try std.testing.expect(v.equal(s, info, try v.own(s, try source_info.create(engine))));
    try std.testing.expect(v.equal(s, try v.get(s, native, "createSyntheticSourceInfo"), try v.get(s, info, "createSyntheticSourceInfo")));
    const factory = try v.own(s, try engine.eval(
        @embedFile("extensions/fixtures/sdk-context-helpers-c268-source.mjs"),
        "actual-c268-context-helpers-factory.js", c.JS_EVAL_TYPE_GLOBAL));
    const reference = try v.call(s, factory, c.pi_js_undefined(), &.{});
    try publish(s, "contextNative", native);
    try publish(s, "contextNativeInfo", info);
    try publish(s, "contextSource", reference);
    try publish(s, "contextSourceInfo", try v.get(s, reference, "sourceInfo"));
    try publish(s, "contextRendererRange", try v.ordinary(s, "actualRendererRange", 2, rendererCall, &.{}));
    try publish(s, "contextHooks", try v.own(s, try retirement.createNativeRetirementHooks(engine)));
}
fn run(engine: *h.Engine, source: []const u8) !void {
    engine.freeValue(try engine.evalModule(source, "actual-sdk-context-helpers-control.mjs"));
}
fn clean(engine: *h.Engine) !void {
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
fn both(comptime name: []const u8, comptime extra: []const u8) !void {
    inline for (.{ .{ "contextSource", "contextSourceInfo" }, .{ "contextNative", "contextNativeInfo" } }) |subject| {
        const engine = try h.Engine.init(std.testing.allocator, .{ .interrupt_budget = 2_000_000 });
        defer engine.deinit(); try prepare(engine);
        try run(engine, observer ++ "\n" ++ name ++ "(" ++ subject[0] ++ "," ++ subject[1] ++ ",contextHooks" ++ extra ++ ");\n");
        try clean(engine);
    }
}
fn recordBody(s: *h.Scope) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.global(s, "contextHooks"), "record"));
}
const FatalKind = enum { current, retirement, cancelled };
fn fatal(comptime name: []const u8, comptime extra: []const u8, comptime kind: FatalKind) !void {
    const engine = try h.Engine.init(std.testing.allocator, .{});
    defer engine.deinit(); try prepare(engine);
    const original = try h.expression(engine, recordBody, .{});
    defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\n" ++ name ++
        "(contextNative,contextNativeInfo,contextHooks" ++ extra ++ ");\n"));
    switch (kind) {
        .current => try retirement.verifyRecordedActualNativeFatal(engine, original),
        .retirement => try retirement.verifyActualRetirementFatal(engine, original, 0),
        .cancelled => try retirement.verifyActualCancellationNoGuestClose(engine, original),
    }
    try retirement.verifyNoVisits(original, .{1,2,3});
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "SDK context helpers actual public shapes and shared source-info owner identity" {
    try both("observeContextShapes", "");
    const engine = try h.Engine.init(std.testing.allocator, .{});
    defer engine.deinit(); try prepare(engine);
    try run(engine,
        \\if (Reflect.ownKeys(contextNative).join(",") !== "parseSkillBlock,formatReadLineRange,createSyntheticSourceInfo") throw new Error("actual three-name record");
        \\if (contextRendererRange(" 2 ","3") !== contextNative.formatReadLineRange(" 2 ","3")) throw new Error("same renderer range body");
    );
    try clean(engine);
}
test "SDK context helpers parseSkillBlock uses the actual complete regex framing" { try both("observeSkillBasics", ""); }
test "SDK context helpers parseSkillBlock selects the live match method and fresh intrinsic regexp" { try both("observeSkillLiteral", ""); }
test "SDK context helpers parseSkillBlock preserves ordered raw capture getters" { try both("observeSkillFields", ""); }
test "SDK context helpers parseSkillBlock retires actual callees receivers and lexical match" { try both("observeSkillRetirement", ""); }
test "SDK context helpers parseSkillBlock preserves optional trim and logical-or semantics" { try both("observeSkillOptional", ""); }
test "SDK context helpers formatReadLineRange retains c268 numeric and nullish branches" { try both("observeRangeBasics", ""); }
test "SDK context helpers formatReadLineRange uses live repeated Number and isFinite calls" { try both("observeRangeLiveNumber", ""); }
test "SDK context helpers strict trim predicate retires before the Number getter" { try both("observeRangeTrimRetirement", ""); }
test "SDK context helpers finite predicate retires before the next argument conversion" { try both("observeRangeFiniteRetirement", ""); }
test "SDK context helpers range templates use intrinsic numeric string conversion" { try both("observeRangeTemplates", ""); }
test "SDK context helpers source-info records preserve ordered getters and nullish defaults" { try both("observeSourceInfoRecords", ""); }
test "SDK context helpers synthetic path helpers preserve actual raw short-circuit values" { try both("observeSourcePaths", ""); }
test "SDK context helpers synthetic path chain retires each actual receiver and callee" { try both("observeSourceChainRetirement", ""); }
test "SDK context helpers same-getter private DATA remains ordinary in every public body" {
    try both("observeContextPrivateData", ",\"match\"");
    try both("observeContextPrivateData", ",\"trim\"");
    try both("observeContextPrivateData", ",\"range\"");
    try both("observeContextPrivateData", ",\"source\"");
}
test "SDK context helpers actual skill capture B prevents later fields and guest catch" { try fatal("observeSkillCurrentFatal", "", .current); }
test "SDK context helpers actual optional trim receiver retirement B prevents return" { try fatal("observeSkillTrimFatal", "", .retirement); }
test "SDK context helpers actual trim predicate retirement B precedes Number lookup" { try fatal("observeRangeTrimFailure", ",false", .retirement); }
test "SDK context helpers actual trim predicate cancellation prevents Number and guest continuation" { try fatal("observeRangeTrimFailure", ",true", .cancelled); }
test "SDK context helpers actual source-info origin B prevents baseDir and guest catch" { try fatal("observeSourceInfoCurrentFatal", "", .current); }
