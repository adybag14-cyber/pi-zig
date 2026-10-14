const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
test {
    _ = @import("native_sdk_compaction_threshold_test.zig");
}
fn setup(engine: *em.Engine) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const dependencies = try scope.object();
    try @import("extensions/native_sdk_session_estimate.zig").install(engine, dependencies);
    const prototype = try scope.object();
    try @import("extensions/native_sdk_check_compaction.zig").install(engine, prototype, dependencies);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "checkCompactionB06", try scope.get(prototype, "_checkCompaction"));
}
fn run(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    try setup(engine);
    const evaluated = engine.evalModule(@embedFile("extensions/fixtures/sdk-check-compaction-b06.input.txt"), "check-compaction-original32.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(evaluated);
    if (generation != engine.native_allocation_generation) return error.OutOfMemory;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const actual = try engine.stringify(try scope.get(global, "checkCompactionB06Rows"));
    defer gpa.free(actual);
    const bytes = @embedFile("extensions/fixtures/sdk-check-compaction-b06.json");
    const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "check-original32.json")));
    const raw = try engine.stringify(try scope.get(expected, "rows"));
    defer gpa.free(raw);
    if (!std.mem.eql(u8, actual, raw)) {
        std.debug.print("Actual check32:\n{s}\nOriginal check32:\n{s}\n", .{ actual, raw });
        return error.NativeCheckCompactionMismatch;
    }
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
test "native check compaction selected inventory" {
    const tests = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, tests.len);
    defer std.testing.allocator.free(names);
    for (tests, names) |function, *name| name.* = function.name;
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(encoded);
    std.debug.print("CHECK_COMPACTION_TEST_INVENTORY={s}\n", .{encoded});
}
test "native check compaction actual b06 overflow length edits stale usage and one retry" {
    try run(std.testing.allocator);
}
test "native check compaction complete host allocation universe" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "check-compaction32", run, .{});
}
test "native check compaction actual async method descriptor" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try setup(engine);
    const evaluated = try engine.evalModule(
        \\const f=checkCompactionB06;if(f.name!=='_checkCompaction'||f.length!==1||Object.hasOwn(f,'prototype')||Object.getPrototypeOf(f)!==Object.getPrototypeOf(async()=>{}))throw Error('async checkCompaction descriptor');
    , "check-compaction-descriptor.mjs");
    engine.freeValue(evaluated);
}

test "native check compaction pending recovery retains message and session through GC and retires both" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    errdefer std.debug.print("Pending compaction GC failure: {s}\n", .{engine.last_error orelse "none"});
    try setup(engine);
    const prepared = try engine.evalModule(
        \\globalThis.checkGcMessage={role:'assistant',stopReason:'error',errorMessage:'maximum context length exceeded',timestamp:10,usage:{input:0,output:0,cacheRead:0,cacheWrite:0,totalTokens:0}};
        \\globalThis.checkGcSession={model:{contextWindow:100,maxTokens:50},agent:{state:{messages:[]}},settingsManager:{getCompactionSettings(){return{enabled:true,reserveTokens:20};}},sessionManager:{getBranch(){return[];},buildSessionProjection(){return{entries:[],messages:[]};}},_modelForMessage(){return this.model;},_findPersistedMessageEntryId(){return undefined;},_omitRecoveryAttempt(){if(!this._overflowRecoveryAttempted)throw Error('recovery omission order');},_runAutoCompaction(reason,retry){if(reason!=='overflow'||retry!==true)throw Error('recovery arguments');return new Promise(resolve=>{globalThis.checkGcRelease=resolve;});}};
        \\globalThis.checkGcSessionWeak=new WeakRef(checkGcSession);globalThis.checkGcMessageWeak=new WeakRef(checkGcMessage);globalThis.checkGcPending=checkCompactionB06.call(checkGcSession,checkGcMessage);delete globalThis.checkGcSession;delete globalThis.checkGcMessage;export const ready=true;
    , "check-compaction-gc-prepare.mjs");
    engine.freeValue(prepared);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const retained = try engine.eval("checkGcSessionWeak.deref()!==undefined&&checkGcMessageWeak.deref()!==undefined&&typeof checkGcRelease==='function'", "check-compaction-gc-retained.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(retained);
    try std.testing.expect(c.JS_ToBool(engine.context, retained) == 1);
    engine.finishJob();
    const completed = try engine.evalModule(
        // Hold caller references while inspecting the settled postcondition;
        // the asynchronous invocation may retire its own roots on completion.
        \\globalThis.checkGcAssertionSession=checkGcSessionWeak.deref();globalThis.checkGcAssertionMessage=checkGcMessageWeak.deref();if(!checkGcAssertionSession||!checkGcAssertionMessage)throw Error('pending recovery roots lost');checkGcRelease(true);if((await checkGcPending)!==true||checkGcAssertionSession._failedResponse!==checkGcAssertionMessage)throw Error('pending recovery message lost');delete globalThis.checkGcAssertionSession;delete globalThis.checkGcAssertionMessage;delete globalThis.checkGcPending;delete globalThis.checkGcRelease;export const done=true;
    , "check-compaction-gc-complete.mjs");
    engine.freeValue(completed);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const collected = try engine.eval("checkGcSessionWeak.deref()===undefined&&checkGcMessageWeak.deref()===undefined", "check-compaction-gc-collected.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(collected);
    try std.testing.expect(c.JS_ToBool(engine.context, collected) == 1);
}
