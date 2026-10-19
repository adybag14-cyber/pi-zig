//! Genuine c268 summary/compaction async owners and their actual conversion,
//! normalization and usage dependencies. Separate Source/native Engine realms.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const c = v.c;
const completion = @import("extensions/native_sdk_complete_summarization.zig");
const summary = @import("extensions/native_sdk_summary_generation.zig");
const messages = @import("extensions/native_sdk_messages.zig");
const transcript = @import("extensions/native_ai_transcript_context.zig");
const usage = @import("extensions/native_sdk_usage_combine.zig");
const file_ops = @import("extensions/native_sdk_compaction_file_ops.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/sdk-summary-observer.mjs");

fn publish(s: *v.Scope, name: [*:0]const u8, value: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, value);
}
fn evaluateFactory(s: *v.Scope, source: []const u8, args: []const c.JSValue) !c.JSValue {
    const factory = try v.own(s, try s.engine.eval(source, "actual-summary-source-factory.js", c.JS_EVAL_TYPE_GLOBAL));
    return v.call(s, factory, c.pi_js_undefined(), args);
}
fn combineCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return usage.combine(engine, v.arg(args, 0), v.arg(args, 1));
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
        , "actual-summary-controlled-inputs.js", c.JS_EVAL_TYPE_GLOBAL));
    const uuid = try v.get(s, inputs, "uuidv7");
    const simple = try v.get(s, inputs, "completeSimple");
    const retry = try v.get(s, inputs, "retryAssistantCall");
    const native_complete = try v.own(s, try completion.create(s.engine, uuid, simple, retry));
    const native_summary = try v.own(s, try summary.exports(s.engine, native_complete));
    const native_transcript = try v.own(s, try transcript.exports(s.engine));
    const native_files = try v.own(s, try file_ops.exports(s.engine));
    const actual = try v.object(s);
    try v.put(s, actual, "completeSummarization", native_complete);
    inline for (.{ "generateSummary", "generateSummaryWithUsage", "compact" }) |name|
        try v.put(s, actual, name, try v.get(s, native_summary, name));
    try v.put(s, actual, "convertToLlm", try v.own(s, try messages.create(s.engine)));
    inline for (.{ "normalizeContext", "createInitialSystemMessage" }) |name|
        try v.put(s, actual, name, try v.get(s, native_transcript, name));
    // A test-only projection of the exact private native combine body.
    try v.put(s, actual, "combineUsage", try v.ordinary(s, "combineUsage", 2, combineCall, &.{}));
    try v.put(s, actual, "createFileOps", try v.get(s, native_files, "createFileOps"));

    const source_messages = try evaluateFactory(s, @embedFile("extensions/fixtures/sdk-summary-messages-c268-source.mjs"), &.{});
    const source_transcript = try evaluateFactory(s, @embedFile("extensions/fixtures/sdk-summary-transcript-c268-source.mjs"), &.{});
    const source_usage = try evaluateFactory(s, @embedFile("extensions/fixtures/sdk-summary-usage-c268-source.mjs"), &.{});
    const source_text = try evaluateFactory(s, @embedFile("extensions/fixtures/sdk-public-compaction-text-c268-source.mjs"), &.{});
    const source_files = try evaluateFactory(s, @embedFile("extensions/fixtures/sdk-compaction-file-ops-c268-source.mjs"), &.{});
    const source_convert = try v.get(s, source_messages, "convertToLlm");
    const source_normalize = try v.get(s, source_transcript, "normalizeContext");
    const reference = try evaluateFactory(s, @embedFile("extensions/fixtures/sdk-summary-c268-source.mjs"), &.{
        uuid, simple, retry, source_convert, source_normalize,
        try v.get(s, source_text, "serializeConversation"), try v.get(s, source_text, "getSummarizationFailure"),
        try v.get(s, source_text, "contentText"), try v.get(s, source_files, "computeFileLists"),
        try v.get(s, source_files, "formatFileOperations"), source_usage,
    });
    try v.put(s, reference, "convertToLlm", source_convert);
    try v.put(s, reference, "normalizeContext", source_normalize);
    try v.put(s, reference, "createInitialSystemMessage", try v.get(s, source_transcript, "createInitialSystemMessage"));
    try v.put(s, reference, "combineUsage", source_usage);
    try v.put(s, reference, "createFileOps", try v.get(s, source_files, "createFileOps"));
    try publish(s, "summaryNative", actual);
    try publish(s, "summarySource", reference);
    try publish(s, "summaryControl", try v.get(s, inputs, "state"));
    try publish(s, "summaryHooks", try v.own(s, try retirement.createNativeRetirementHooks(s.engine)));
    try std.testing.expect(v.equal(s, native_summary, try v.own(s, try summary.exports(s.engine, native_complete))));
    try std.testing.expect(v.equal(s, native_transcript, try v.own(s, try transcript.exports(s.engine))));
}
fn run(engine: *v.em.Engine, source: []const u8) !void {
    const result = try engine.evalModule(source, "actual-summary-control.mjs");
    engine.freeValue(result);
}
fn clean(engine: *v.em.Engine) !void {
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}
fn both(comptime name: []const u8, comptime argument: []const u8) !void {
    inline for (.{ "summarySource", "summaryNative" }) |subject| {
        const engine = try v.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 2_000_000 });
        defer engine.deinit();
        try prepare(engine);
        try run(engine, observer ++ "\nawait " ++ name ++ "(" ++ subject ++ ",summaryControl,summaryHooks" ++ argument ++ ");\n");
        try clean(engine);
    }
}
fn record(engine: *v.em.Engine) !c.JSValue {
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, recordBody(&s));
}
fn recordBody(s: *v.Scope) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.global(s, "summaryHooks"), "record"));
}
test "SDK summary genuine AF export shapes and completed actual owners" { try both("observeSummaryShapes", ""); }
test "SDK summary genuine AF option spread repeated routing and retry arguments" { try both("observeSummaryCopy", ""); }
test "SDK summary genuine AF zero Await outer body and intrinsic return adoption" { try both("observeSummaryZeroAwait", ""); }
test "SDK summary genuine AF stream producer performs its actual Await before result" { try both("observeSummaryStreamAwait", ""); }
test "SDK summary genuine AF retained produce closes only its actual captured inputs" { try both("observeSummaryProducerCapture", ""); }
test "SDK summary genuine AF actual result callee retires before return adoption" { try both("observeSummaryStreamTemporaries", ""); }
test "SDK summary genuine AF ordinary private DATA keeps exact identity before and after Await" {
    try both("observeSummaryPrivateData", ",\"retry\"");
    try both("observeSummaryPrivateData", ",\"stream\"");
}
test "SDK summary genuine AF c268 options omit obsolete reserveTokens and maxTokens" { try both("observeSummaryBasic", ""); }
test "SDK summary genuine AF intrinsic templates convert before later expressions" { try both("observeSummaryTemplates", ""); }
test "SDK summary genuine AF response predicates methods and final usage remain live" { try both("observeSummaryResponse", ""); }
test "SDK summary genuine AF actual failure and tool stop paths" { try both("observeSummaryErrors", ""); }
test "SDK summary genuine AF Date receiver and callee retire before complete request" { try both("observeSummaryDate", ""); }
test "SDK summary genuine AF local response and borrowed input survive real Await" { try both("observeSummaryLocal", ""); }
test "SDK summary genuine AF compact whole split and combined usage use actual owners" { try both("observeSummaryCompactRoutes", ""); }
test "SDK summary genuine AF compact destructures one boxed receiver and ignores settings" { try both("observeSummaryCompactBindings", ""); }
test "SDK summary genuine AF split text coerces history before turn text" { try both("observeSummaryCompactTemplates", ""); }
test "SDK summary genuine AF actual message transforms preserve identity and coercion hints" { try both("observeSummaryMessages", ""); }
test "SDK summary genuine AF actual map filter callbacks and temporary retirement" { try both("observeSummaryMessageCalls", ""); }
test "SDK summary genuine AF normalization keeps identity and actual array spread" { try both("observeSummaryNormalize", ""); }
test "SDK summary genuine AF usage optional rereads and cost receiver retirement" { try both("observeSummaryUsage", ""); }
test "SDK summary genuine AF ordinary response and Error constructor DATA stay ordinary" {
    try both("observeSummaryResponseData", ",\"response\"");
    try both("observeSummaryResponseData", ",\"constructor\"");
}
test "SDK summary genuine AF current native B preempts rejection and later getters" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nawait observeSummaryCurrentFatal(summaryNative,summaryControl,summaryHooks);"));
    try retirement.verifyRecordedActualNativeFatal(engine, original);
    try retirement.verifyNoVisits(original, .{ 1, 2 });
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "SDK summary genuine AF reasoning predicate retirement preserves current B before Date" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nawait observeSummaryPredicateRetirement(summaryNative,summaryControl,summaryHooks,false);"));
    try retirement.verifyActualRetirementFatal(engine, original, 0);
    try retirement.verifyNoVisits(original, .{1});
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "SDK summary genuine AF reasoning predicate cancellation preempts Date and request" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nawait observeSummaryPredicateRetirement(summaryNative,summaryControl,summaryHooks,true);"));
    try retirement.verifyActualCancellationNoGuestClose(engine, original);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
