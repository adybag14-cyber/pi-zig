//! Genuine branch-summary AF over actual completion, preparation and shared
//! conversion/text/file owners. Fresh Source/native realms; no host substitute.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const c = v.c;
const branch = @import("extensions/native_sdk_branch_summary.zig");
const entries = @import("extensions/native_sdk_public_branch_entries.zig");
const completion = @import("extensions/native_sdk_complete_summarization.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/sdk-branch-summary-observer.mjs");
fn publish(s: *v.Scope, name: [*:0]const u8, value: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, value);
}
fn evaluateFactory(s: *v.Scope, source: []const u8, args: []const c.JSValue) !c.JSValue {
    const factory = try v.own(s, try s.engine.eval(source, "actual-branch-summary-source-factory.js", c.JS_EVAL_TYPE_GLOBAL));
    return v.call(s, factory, c.pi_js_undefined(), args);
}
fn prepare(engine: *v.em.Engine) !void {
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, prepareBody(&s));
}
fn prepareBody(s: *v.Scope) !void {
    const inputs = try v.own(s, try s.engine.eval(
        \\(function(){"use strict";const state={};
        \\return {state,uuidv7:function(){return state.uuidv7()},
        \\completeSimple:function(...args){return state.completeSimple(...args)},
        \\retryAssistantCall:function(...args){return state.retryAssistantCall(...args)}}})()
        , "actual-branch-summary-controlled-inputs.js", c.JS_EVAL_TYPE_GLOBAL));
    const uuid = try v.get(s, inputs, "uuidv7");
    const simple = try v.get(s, inputs, "completeSimple");
    const retry = try v.get(s, inputs, "retryAssistantCall");
    const native_complete = try v.own(s, try completion.create(s.engine, uuid, simple, retry));
    const actual = try v.own(s, try branch.exports(s.engine, native_complete));
    const native_entries = try v.own(s, try entries.create(s.engine));
    try std.testing.expect(v.equal(s, actual, try v.own(s, try branch.exports(s.engine, native_complete))));
    inline for (.{ "collectEntriesForBranchSummary", "prepareBranchEntries" }) |name|
        try std.testing.expect(v.equal(s, try v.get(s, actual, name), try v.get(s, native_entries, name)));
    const source_messages = try evaluateFactory(s, @embedFile("extensions/fixtures/sdk-summary-messages-c268-source.mjs"), &.{});
    const source_transcript = try evaluateFactory(s, @embedFile("extensions/fixtures/sdk-summary-transcript-c268-source.mjs"), &.{});
    const source_usage = try evaluateFactory(s, @embedFile("extensions/fixtures/sdk-summary-usage-c268-source.mjs"), &.{});
    const source_text = try evaluateFactory(s, @embedFile("extensions/fixtures/sdk-public-compaction-text-c268-source.mjs"), &.{});
    const source_files = try evaluateFactory(s, @embedFile("extensions/fixtures/sdk-compaction-file-ops-c268-source.mjs"), &.{});
    const source_entries = try evaluateFactory(s, @embedFile("extensions/fixtures/sdk-public-branch-entries-c268-source.mjs"), &.{});
    const convert = try v.get(s, source_messages, "convertToLlm");
    const normalize = try v.get(s, source_transcript, "normalizeContext");
    const serialize = try v.get(s, source_text, "serializeConversation");
    const failure = try v.get(s, source_text, "getSummarizationFailure");
    const content = try v.get(s, source_text, "contentText");
    const lists = try v.get(s, source_files, "computeFileLists");
    const format = try v.get(s, source_files, "formatFileOperations");
    const source_summary = try evaluateFactory(s, @embedFile("extensions/fixtures/sdk-summary-c268-source.mjs"), &.{
        uuid, simple, retry, convert, normalize, serialize, failure, content, lists, format, source_usage,
    });
    const reference = try evaluateFactory(s, @embedFile("extensions/fixtures/sdk-branch-summary-c268-source.mjs"), &.{
        try v.get(s, source_entries, "collectEntriesForBranchSummary"), try v.get(s, source_entries, "prepareBranchEntries"),
        convert, serialize, normalize, try v.get(s, source_summary, "completeSummarization"), failure, content, lists, format,
    });
    try publish(s, "branchSummaryNative", actual);
    try publish(s, "branchSummarySource", reference);
    try publish(s, "branchSummaryControl", try v.get(s, inputs, "state"));
    try publish(s, "branchSummaryHooks", try v.own(s, try retirement.createNativeRetirementHooks(s.engine)));
}
fn run(engine: *v.em.Engine, source: []const u8) !void {
    const result = try engine.evalModule(source, "actual-branch-summary-control.mjs"); engine.freeValue(result);
}
fn clean(engine: *v.em.Engine) !void {
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}
fn both(comptime name: []const u8, comptime argument: []const u8) !void {
    inline for (.{ "branchSummarySource", "branchSummaryNative" }) |subject| {
        const engine = try v.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 2_000_000 });
        defer engine.deinit(); try prepare(engine);
        try run(engine, observer ++ "\nawait " ++ name ++ "(" ++ subject ++ ",branchSummaryControl,branchSummaryHooks" ++ argument ++ ");\n");
        try clean(engine);
    }
}
fn record(engine: *v.em.Engine) !c.JSValue {
    var s: v.Scope = .{ .engine = engine }; return v.owned.finishValue(&s, recordBody(&s));
}
fn recordBody(s: *v.Scope) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.global(s, "branchSummaryHooks"), "record"));
}
test "SDK branch summary genuine AF declarations and actual reused entry owners" { try both("observeBranchSummaryShapes", ""); }
test "SDK branch summary genuine AF empty route runs synchronously without a source Await" { try both("observeBranchSummaryEmpty", ""); }
test "SDK branch summary genuine AF options destructure one boxed receiver before budget" { try both("observeBranchSummaryBindings", ""); }
test "SDK branch summary genuine AF actual budget defaults fallback and arithmetic" { try both("observeBranchSummaryBudget", ""); }
test "SDK branch summary genuine AF actual preparation conversion and file tracking" { try both("observeBranchSummaryComplete", ""); }
test "SDK branch summary genuine AF session stream uses actual awaited result and retry arguments" { try both("observeBranchSummaryStream", ""); }
test "SDK branch summary genuine AF intrinsic prompts and generic preamble addition keep their hints" { try both("observeBranchSummaryTemplates", ""); }
test "SDK branch summary genuine AF instruction branches and early abrupt conversion" { try both("observeBranchSummaryInstructions", ""); }
test "SDK branch summary genuine AF aborted failure and tool paths skip later response fields" { try both("observeBranchSummaryStops", ""); }
test "SDK branch summary genuine AF live response content methods callbacks and usage" { try both("observeBranchSummaryResponse", ""); }
test "SDK branch summary genuine AF Date expression retires before completion call" { try both("observeBranchSummaryDate", ""); }
test "SDK branch summary genuine AF status and content temporaries retire before next getters" { try both("observeBranchSummaryPredicates", ""); }
test "SDK branch summary genuine AF arguments and local capture survive real Await" { try both("observeBranchSummaryLocals", ""); }
test "SDK branch summary genuine AF returned record adoption precedes input retirement" { try both("observeBranchSummaryAdoption", ""); }
test "SDK branch summary genuine AF ordinary private DATA remains exact across both boundaries" {
    try both("observeBranchSummaryData", ",\"before\"");
    try both("observeBranchSummaryData", ",\"after\"");
}
test "SDK branch summary genuine AF failure record keeps actual error interpolation hint" { try both("observeBranchSummaryFailureValue", ""); }
test "SDK branch summary genuine AF current B preempts later option fields and guest rejection" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nawait observeBranchSummaryCurrentFatal(branchSummaryNative,branchSummaryControl,branchSummaryHooks);"));
    try retirement.verifyRecordedActualNativeFatal(engine, original);
    try retirement.verifyNoVisits(original, .{ 1, 2, 3 });
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "SDK branch summary genuine AF post Await status retirement B blocks the next operation" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nawait observeBranchSummaryStatusStop(branchSummaryNative,branchSummaryControl,branchSummaryHooks,false);"));
    try retirement.verifyActualRetirementFatal(engine, original, 0);
    try retirement.verifyNoVisits(original, .{ 1, 2, 3 });
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "SDK branch summary genuine AF post Await cancellation skips later getters and catch" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nawait observeBranchSummaryStatusStop(branchSummaryNative,branchSummaryControl,branchSummaryHooks,true);"));
    try retirement.verifyActualCancellationNoGuestClose(engine, original);
    try retirement.verifyNoVisits(original, .{3});
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "SDK branch summary genuine AF real preparation IteratorClose preserves body rejection" { try both("observeBranchSummaryIteratorClose", ""); }
