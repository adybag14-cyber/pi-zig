//! Actual c268 file-operation utilities. Each Source/native comparison uses
//! a fresh Engine realm and the existing real C sole-holder recorder.
const std = @import("std");
const v = @import("extensions/native_public_values.zig");
const c = v.c;
const operations = @import("extensions/native_sdk_compaction_file_ops.zig");
const retirement = @import("native_sdk_initial_model_retirement_controls.zig");
const observer = @embedFile("extensions/fixtures/sdk-compaction-file-ops-observer.mjs");
fn publish(s: *v.Scope, name: [*:0]const u8, value: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, value);
}
fn prepare(engine: *v.em.Engine) !void {
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, prepareBody(&s));
}
fn prepareBody(s: *v.Scope) !void {
    const actual = try v.own(s, try operations.exports(s.engine));
    const factory = try v.own(s, try s.engine.eval(@embedFile("extensions/fixtures/sdk-compaction-file-ops-c268-source.mjs"), "actual-compaction-file-ops-source.js", c.JS_EVAL_TYPE_GLOBAL));
    const reference = try v.call(s, factory, c.pi_js_undefined(), &.{});
    try publish(s, "fileOpsNative", actual);
    try publish(s, "fileOpsSource", reference);
    try publish(s, "fileOpsHooks", try v.own(s, try retirement.createNativeRetirementHooks(s.engine)));
}
fn run(engine: *v.em.Engine, source: []const u8) !void {
    const result = try engine.evalModule(source, "actual-compaction-file-ops-control.mjs");
    engine.freeValue(result);
}
fn clean(engine: *v.em.Engine) !void {
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}
fn both(comptime name: []const u8, comptime argument: []const u8) !void {
    inline for (.{ "fileOpsSource", "fileOpsNative" }) |subject| {
        const engine = try v.em.Engine.init(std.testing.allocator, .{ .interrupt_budget = 1_000_000 });
        defer engine.deinit();
        try prepare(engine);
        try run(engine, observer ++ "\n" ++ name ++ "(" ++ subject ++ ",fileOpsHooks" ++ argument ++ ");\n");
        try clean(engine);
    }
}
fn record(engine: *v.em.Engine) !c.JSValue {
    var s: v.Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, recordBody(&s));
}
fn recordBody(s: *v.Scope) !c.JSValue {
    return v.duplicate(s, try v.get(s, try v.global(s, "fileOpsHooks"), "record"));
}
fn cache(s: *v.Scope) !void {
    try std.testing.expect(v.equal(s, try v.own(s, try operations.exports(s.engine)), try v.global(s, "fileOpsNative")));
}
test "SDK public compaction file operations actual ordinary exports and completed cache" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    var s: v.Scope = .{ .engine = engine }; try v.owned.finishVoid(&s, cache(&s));
    try run(engine,
        \\for(const api of[fileOpsSource,fileOpsNative]){
        \\if(Object.keys(api).join()!=="createFileOps,extractFileOpsFromMessage,computeFileLists,formatFileOperations")throw Error("file-operation export order");
        \\for(const[name,length]of [["createFileOps",0],["extractFileOpsFromMessage",2],["computeFileLists",1],["formatFileOperations",2]]){
        \\const fn=api[name];if(fn.name!==name||fn.length!==length||Object.getPrototypeOf(fn)!==Function.prototype||!Object.hasOwn(fn,"prototype"))throw Error("ordinary file-operation function shape");
        \\}
        \\}
    );
    try clean(engine);
}
test "SDK public compaction file operations actual message extraction sorted lists and summary tags" { try both("observeFileOpsBasic", ""); }
test "SDK public compaction file operations actual live Set constructors retire between fields" { try both("observeFileOpsConstructors", ""); }
test "SDK public compaction file operations actual optional-chain receiver retires before fallback iteration" { try both("observeFileOpsNestedReceiver", ""); }
test "SDK public compaction file operations actual Array predicate completes before repeated content" { try both("observeFileOpsArrayPredicate", ""); }
test "SDK public compaction file operations actual nested call head survives next and done" { try both("observeFileOpsHeads", ",\"call\""); }
test "SDK public compaction file operations actual assistant block head survives next and done" { try both("observeFileOpsHeads", ",\"block\""); }
test "SDK public compaction file operations actual in getter path and add evaluation order" { try both("observeFileOpsArgumentOrder", ""); }
test "SDK public compaction file operations actual primitive in operand error" { try both("observeFileOpsPrimitiveIn", ""); }
test "SDK public compaction file operations actual array append probe repeated lookup and retained iterable" { try both("observeFileOpsSpread", ""); }
test "SDK public compaction file operations actual array append closes next failure" { try both("observeFileOpsSpreadClose", ""); }
test "SDK public compaction file operations actual filter predicate and sort receiver retirement" { try both("observeFileOpsListExpressions", ""); }
test "SDK public compaction file operations actual format call and template retirement order" { try both("observeFileOpsFormatExpressions", ""); }
test "SDK public compaction file operations actual private DATA remains ordinary through close" { try both("observeFileOpsPrivateData", ""); }
test "SDK public compaction file operations actual current B preempts catch and close" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nobserveFileOpsCurrentFatal(fileOpsNative,fileOpsHooks);"));
    try retirement.verifyRecordedActualNativeFatal(engine, original);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "SDK public compaction file operations actual head retirement cancellation preempts getters and close" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{}); defer engine.deinit(); try prepare(engine);
    const original = try record(engine); defer engine.freeValue(original);
    try std.testing.expectError(error.JavaScriptException, run(engine, observer ++ "\nobserveFileOpsCancellation(fileOpsNative,fileOpsHooks);"));
    try retirement.verifyActualCancellationNoGuestClose(engine, original);
    try std.testing.expect(engine.native_fatal_invocation == null);
}
