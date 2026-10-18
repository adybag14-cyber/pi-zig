//! Actual c268 serializer/contentText controls. Source and native subjects use
//! separate fresh Engine realms and the real C sole-holder recorder.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const c = v.c;
const serializer = @import("extensions/native_sdk_compaction_text.zig");
const content = @import("extensions/native_ai_content_text.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/sdk-public-compaction-text-observer.mjs");
fn publish(s: *v.Scope, name: [*:0]const u8, value: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, value);
}
fn prepare(engine: *v.em.Engine) !void {
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, prepareBody(&s));
}
fn prepareBody(s: *v.Scope) !void {
    const actual = try v.own(s, try serializer.exports(s.engine));
    const text = try v.own(s, try content.create(s.engine));
    const factory = try v.own(s, try s.engine.eval(@embedFile("extensions/fixtures/sdk-public-compaction-text-c268-source.mjs"), "actual-compaction-text-source.js", c.JS_EVAL_TYPE_GLOBAL));
    const reference = try v.call(s, factory, c.pi_js_undefined(), &.{});
    try publish(s, "compactionTextNative", actual);
    try publish(s, "compactionTextSource", reference);
    try publish(s, "actualContentText", text);
    try publish(s, "compactionTextHooks", try v.own(s, try retirement.createNativeRetirementHooks(s.engine)));
}
fn run(engine: *v.em.Engine, source: []const u8) !void {
    const result = try engine.evalModule(source, "actual-compaction-text-control.mjs");
    engine.freeValue(result);
}
fn clean(engine: *v.em.Engine) !void {
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}
fn both(comptime name: []const u8, comptime argument: []const u8) !void {
    inline for (.{ .{ "compactionTextSource", "compactionTextSource.contentText" }, .{ "compactionTextNative", "actualContentText" } }) |subject| {
        const engine = try v.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 }); defer engine.deinit();
        try prepare(engine);
        try run(engine, observer ++ "\n" ++ name ++ "(" ++ subject[0] ++ "," ++ subject[1] ++ ",compactionTextHooks" ++ argument ++ ");\n");
        try clean(engine);
    }
}
fn record(engine: *v.em.Engine) !c.JSValue {
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, recordBody(&s));
}
fn recordBody(s: *v.Scope) !c.JSValue { return v.duplicate(s, try v.get(s, try v.global(s, "compactionTextHooks"), "record")); }
fn cache(s: *v.Scope) !void {
    try std.testing.expect(v.equal(s, try v.own(s, try serializer.exports(s.engine)), try v.global(s, "compactionTextNative")));
    try std.testing.expect(v.equal(s, try v.own(s, try content.create(s.engine)), try v.global(s, "actualContentText")));
}
test "SDK public compaction text actual ordinary exports and retained content owner" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    var s: v.Scope = .{ .engine = engine }; try v.owned.finishVoid(&s, cache(&s));
    try run(engine,
        \\for(const api of[compactionTextSource,compactionTextNative]){
        \\for(const[name,length]of [["serializeConversation",1],["getSummarizationFailure",2]]){
        \\const fn=api[name];if(fn.name!==name||fn.length!==length||Object.getPrototypeOf(fn)!==Function.prototype||!Object.hasOwn(fn,"prototype"))throw Error("ordinary serializer function shape");
        \\}
        \\}
        \\for(const fn of[compactionTextSource.contentText,actualContentText])if(fn.name!=="contentText"||fn.length!==1||!Object.hasOwn(fn,"prototype")||Object.getPrototypeOf(fn)!==Function.prototype)throw Error("ordinary contentText default-parameter shape");
    );
    try clean(engine);
}
test "SDK public compaction text actual text extraction serialization and truncation" { try both("observeCompactionTextBasic", ""); }
test "SDK public compaction text actual filter map join receiver and callee retirement" { try both("observeContentTextReceivers", ""); }
test "SDK public compaction text actual destructured parameters close before template coercion" { try both("observeCompactionTextPair", ",false"); }
test "SDK public compaction text actual normal IteratorClose rejects a primitive result" { try both("observeCompactionTextPair", ",true"); }
test "SDK public compaction text actual entries map join completes before name getter" { try both("observeCompactionTextExpression", ""); }
test "SDK public compaction text actual nested head and branch slot reentry order" { try both("observeCompactionTextHeads", ",false"); }
test "SDK public compaction text actual failure label and reason evaluation" { try both("observeCompactionTextFailure", ""); }
test "SDK public compaction text actual assistant role and content getters remain repeated" { try both("observeCompactionTextRoleReads", ""); }
test "SDK public compaction text actual private DATA crosses two iterator scopes" { try both("observeCompactionTextPrivateData", ""); }
test "SDK public compaction text actual nested IteratorClose keeps original throw" { try both("observeCompactionTextClose", ",false"); }
test "SDK public compaction text actual next failure closes only the outer iterator" { try both("observeCompactionTextClose", ",true"); }
test "SDK public compaction text actual branch reset B preempts following argument getter" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nobserveCompactionTextHeads(compactionTextNative,actualContentText,compactionTextHooks,true);"));
    try retirement.verifyActualRetirementFatal(engine, original, 2);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "SDK public compaction text actual current B bypasses guest catch" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nobserveCompactionTextCurrentFatal(compactionTextNative,actualContentText,compactionTextHooks);"));
    try retirement.verifyRecordedActualNativeFatal(engine, original);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
