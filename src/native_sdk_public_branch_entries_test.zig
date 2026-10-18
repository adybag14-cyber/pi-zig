//! Actual branch collection and budget preparation with the real projection,
//! file-operation and estimator owners. Source/native cases use fresh realms.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const c = v.c;
const branch = @import("extensions/native_sdk_public_branch_entries.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/sdk-public-branch-entries-observer.mjs");
fn publish(s: *v.Scope, name: [*:0]const u8, value: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, value);
}
fn prepare(engine: *v.em.Engine) !void {
    var scope: v.Scope = .{ .engine = engine };
    return v.owned.finishVoid(&scope, prepareBody(&scope));
}
fn prepareBody(s: *v.Scope) !void {
    const actual = try v.own(s, try branch.create(s.engine));
    const factory = try v.own(s, try s.engine.eval(@embedFile("extensions/fixtures/sdk-public-branch-entries-c268-source.mjs"), "actual-branch-entries-source.js", c.JS_EVAL_TYPE_GLOBAL));
    const reference = try v.call(s, factory, c.pi_js_undefined(), &.{});
    try publish(s, "branchNative", actual);
    try publish(s, "branchSource", reference);
    try publish(s, "branchHooks", try v.own(s, try retirement.createNativeRetirementHooks(s.engine)));
}
fn run(engine: *v.em.Engine, source: []const u8) !void {
    const result = try engine.evalModule(source, "actual-branch-entries-control.mjs");
    engine.freeValue(result);
}
fn clean(engine: *v.em.Engine) !void {
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}
fn both(comptime name: []const u8, comptime argument: []const u8) !void {
    inline for (.{ "branchSource", "branchNative" }) |subject| {
        const engine = try v.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
        defer engine.deinit();
        try prepare(engine);
        try run(engine, observer ++ "\n" ++ name ++ "(" ++ subject ++ ",branchHooks" ++ argument ++ ");\n");
        try clean(engine);
    }
}
fn record(engine: *v.em.Engine) !c.JSValue {
    var scope: v.Scope = .{ .engine = engine };
    return v.owned.finishValue(&scope, recordBody(&scope));
}
fn recordBody(s: *v.Scope) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.global(s, "branchHooks"), "record"));
}
fn cache(s: *v.Scope) !void {
    try std.testing.expect(v.equal(s, try v.own(s, try branch.create(s.engine)), try v.global(s, "branchNative")));
}
test "SDK public branch entries actual ordinary exports and completed cache" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    var scope: v.Scope = .{ .engine = engine };
    try v.owned.finishVoid(&scope, cache(&scope));
    try run(engine,
        \\for(const api of [branchSource,branchNative]){
        \\if(Object.keys(api).join()!=="collectEntriesForBranchSummary,prepareBranchEntries")throw Error("branch export order");
        \\for(const [name,length]of [["collectEntriesForBranchSummary",3],["prepareBranchEntries",1]]){
        \\const fn=api[name];if(fn.name!==name||fn.length!==length||Object.getPrototypeOf(fn)!==Function.prototype||!Object.hasOwn(fn,"prototype"))throw Error("actual ordinary branch function shape");
        \\}
        \\}
    );
    try clean(engine);
}
test "SDK public branch entries actual ancestor collection chronological identities and empty guards" { try both("observeBranchCollectBasic", ""); }
test "SDK public branch entries actual Set getBranch and map expression retirement" { try both("observeBranchCollectExpressions", ""); }
test "SDK public branch entries actual has callee indexed receiver and repeated matching id" { try both("observeBranchCollectRepeatedId", ""); }
test "SDK public branch entries actual while entry survives final condition and reverse" { try both("observeBranchCollectEntrySlots", ""); }
test "SDK public branch entries actual message records estimates and cumulative file tracking" { try both("observeBranchPrepareBasic", ""); }
test "SDK public branch entries actual budget and important summary exception" { try both("observeBranchPrepareBudget", ""); }
test "SDK public branch entries actual first-pass head survives next done and second pass" { try both("observeBranchOuterHead", ""); }
test "SDK public branch entries actual details and nested path heads survive later source operations" { try both("observeBranchDetailAndPathHeads", ""); }
test "SDK public branch entries actual reverse body slots reset before next index" { try both("observeBranchReverseSlots", ""); }
test "SDK public branch entries actual record argument getters and Date method receiver" {
    try both("observeBranchRecordOrder", ",\"custom_message\"");
    try both("observeBranchRecordOrder", ",\"branch_summary\"");
    try both("observeBranchRecordOrder", ",\"compaction\"");
}
test "SDK public branch entries actual message role receiver retires before repeated getter" {
    try both("observeBranchRepeatedMessage", ",\"user\"");
    try both("observeBranchRepeatedMessage", ",\"toolResult\"");
}
test "SDK public branch entries actual budget threshold insertion and total coercion order" { try both("observeBranchBudgetCoercion", ""); }
test "SDK public branch entries actual nested IteratorClose preserves body throw" { try both("observeBranchNestedClose", ",\"ordinary\""); }
test "SDK public branch entries actual private DATA remains ordinary through nested close" { try both("observeBranchNestedClose", ",\"data\""); }
test "SDK public branch entries actual current B preempts both closes and guest catch" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    const original = try record(engine);
    defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nobserveBranchNestedClose(branchNative,branchHooks,\"fatal\");"));
    try retirement.verifyRecordedActualNativeFatal(engine, original);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "SDK public branch entries actual token retirement B preempts following index and catch" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    const original = try record(engine);
    defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nobserveBranchSlotStop(branchNative,branchHooks,false);"));
    try retirement.verifyActualRetirementFatal(engine, original, 0);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "SDK public branch entries actual token retirement cancellation preempts following index and catch" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try prepare(engine);
    const original = try record(engine);
    defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nobserveBranchSlotStop(branchNative,branchHooks,true);"));
    try retirement.verifyActualCancellationNoGuestClose(engine, original);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
