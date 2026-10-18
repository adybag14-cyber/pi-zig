//! Actual c268 public compaction core controls. Each Source/native observer
//! runs in a fresh realm over the same real C retirement holder facility.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const c = v.c;
const compaction = @import("extensions/native_sdk_public_compaction_core.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/sdk-public-compaction-core-observer.mjs");

fn publish(s: *v.Scope, name: [*:0]const u8, value: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, value);
}
fn prepare(engine: *v.em.Engine) !void {
    engine.native_io = std.testing.io;
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, prepareBody(&s));
}
fn prepareBody(s: *v.Scope) !void {
    const actual = try v.own(s, try compaction.create(s.engine));
    const uuid = try v.own(s, try @import("extensions/native_node_crypto_uuid_binding.zig").create(s.engine));
    const session_factory = try v.own(s, try s.engine.eval(@embedFile("extensions/fixtures/sdk-public-session-helpers-c268-source.mjs"), "actual-compaction-session-source.js", c.JS_EVAL_TYPE_GLOBAL));
    const session = try v.call(s, session_factory, c.pi_js_undefined(), &.{uuid});
    const factory = try v.own(s, try s.engine.eval(@embedFile("extensions/fixtures/sdk-public-compaction-core-c268-source.mjs"), "actual-compaction-core-source.js", c.JS_EVAL_TYPE_GLOBAL));
    const reference = try v.call(s, factory, c.pi_js_undefined(), &.{try v.get(s, session, "sessionEntryToContextMessages")});
    try publish(s, "compactionNative", actual);
    try publish(s, "compactionSource", reference);
    try publish(s, "compactionHooks", try v.own(s, try retirement.createNativeRetirementHooks(s.engine)));
}
fn run(engine: *v.em.Engine, source: []const u8) !void {
    const result = try engine.evalModule(source, "actual-public-compaction-core-control.mjs");
    engine.freeValue(result);
}
fn clean(engine: *v.em.Engine) !void {
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}
fn both(comptime name: []const u8, comptime argument: []const u8) !void {
    inline for (.{ "compactionSource", "compactionNative" }) |subject| {
        const engine = try v.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
        defer engine.deinit();
        try prepare(engine);
        try run(engine, observer ++ "\n" ++ name ++ "(" ++ subject ++ ",compactionHooks" ++ argument ++ ");\n");
        try clean(engine);
    }
}
fn record(engine: *v.em.Engine) !c.JSValue {
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, recordBody(&s));
}
fn recordBody(s: *v.Scope) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.global(s, "compactionHooks"), "record"));
}
test "SDK public compaction core actual ordinary shapes defaults and cached owner identity" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try prepare(engine);
    var s: v.Scope = .{ .engine = engine };
    const checked = verifyCache(&s);
    try v.owned.finishVoid(&s, checked);
    try run(engine,
        \\const names={calculateContextTokens:1,getLastAssistantUsage:1,shouldCompact:3,findTurnStartIndex:3,findCutPoint:4,estimateTokens:1};
        \\for(const api of[compactionSource,compactionNative]){
        \\if(Object.keys(api).length!==7)throw Error("actual seven core bindings");
        \\for(const[name,length]of Object.entries(names)){
        \\const fn=api[name];if(fn.name!==name||fn.length!==length||Object.getPrototypeOf(fn)!==Function.prototype||!Object.hasOwn(fn,"prototype"))throw Error("actual ordinary shape "+name);
        \\}
        \\const settings=api.DEFAULT_COMPACTION_SETTINGS;
        \\if(settings.enabled!==true||settings.reserveTokens!==16384||settings.keepRecentTokens!==20000)throw Error("actual default compaction settings");
        \\settings.enabled=false;if(api.DEFAULT_COMPACTION_SETTINGS!==settings||api.shouldCompact(100000,1,settings))throw Error("mutable settings binding");
        \\if(!(new api.estimateTokens({role:"unknown"}) instanceof api.estimateTokens))throw Error("ordinary construction path");
        \\}
    );
    try clean(engine);
}
fn verifyCache(s: *v.Scope) !void {
    const again = try v.own(s, try compaction.create(s.engine));
    try std.testing.expect(v.equal(s, again, try v.global(s, "compactionNative")));
}
test "SDK public compaction core actual usage getter and coercion order" { try both("observeCompactionUsage", ""); }
test "SDK public compaction core actual last valid usage and repeated live getters" { try both("observeCompactionLastUsage", ""); }
test "SDK public compaction core actual reserve operand retires before outer comparison" { try both("observeCompactionThreshold", ""); }
test "SDK public compaction core actual token estimates for every role" { try both("observeCompactionEstimates", ""); }
test "SDK public compaction core actual JSON callee and returned receiver retirement" { try both("observeCompactionJSONRetirement", ",false"); }
test "SDK public compaction core actual text helper head survives next and retires before caller" { try both("observeCompactionTextHeads", ""); }
test "SDK public compaction core actual system section head survives following expressions" { try both("observeCompactionSystemHeads", ""); }
test "SDK public compaction core actual cut metadata compaction boundaries and split turns" { try both("observeCompactionCuts", ""); }
test "SDK public compaction core actual live array methods and callback shapes" { try both("observeCompactionMethods", ""); }
test "SDK public compaction core actual BigInt decrement and temporary turn entry retirement" { try both("observeCompactionTurnNumeric", ""); }
test "SDK public compaction core actual IteratorClose preserves head and original throw" { try both("observeCompactionClose", ",false"); }
test "SDK public compaction core actual iterator next failure omits guest close" { try both("observeCompactionClose", ",true"); }
test "SDK public compaction core actual same-operation private DATA remains ordinary" { try both("observeCompactionPrivateData", ""); }
test "SDK public compaction core actual retirement B preempts returned length getter" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try prepare(engine); const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nobserveCompactionJSONRetirement(compactionNative,compactionHooks,true);"));
    try retirement.verifyActualRetirementFatal(engine, original, 1);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "SDK public compaction core actual current B bypasses guest catch" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try prepare(engine); const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nobserveCompactionCurrentFatal(compactionNative,compactionHooks);"));
    try retirement.verifyRecordedActualNativeFatal(engine, original);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "SDK public compaction core actual cancellation on new head preempts body and close" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 }); defer engine.deinit();
    try prepare(engine); const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nobserveCompactionCancellation(compactionNative,compactionHooks);"));
    try retirement.verifyActualCancellationNoGuestClose(engine, original);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
