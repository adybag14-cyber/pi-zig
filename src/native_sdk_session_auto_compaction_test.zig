//! Actual automatic body; controlled receiver collaborators are test inputs,
//! not replacements installed into the production session prototype.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
fn setup(engine: *em.Engine, environment: *std.process.Environ.Map) !void {
    try @import("native_sdk_session_compaction_test.zig").setup(engine, environment);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const manual = try scope.get(global, "manualCompactionAPI");
    const prototype = try scope.object();
    try @import("extensions/native_sdk_session_auto_compaction.zig").install(engine, prototype);
    const api = try scope.object();
    try scope.put(api, "run", try scope.get(prototype, "_runAutoCompaction"));
    try scope.put(api, "failed", try scope.get(manual, "failed"));
    try scope.put(api, "refresh", try scope.get(manual, "refresh"));
    try scope.put(global, "autoCompactionAPI", api);
}
fn run(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    setup(engine, &environment) catch |err| return engine.nativeAllocationError(err, generation);
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-session-auto-compaction-b45.input.txt"), "automatic-compaction-original40.mjs") catch |err| {
        std.debug.print("Actual automatic compaction40 failed: {s}\n", .{engine.last_error orelse @errorName(err)});
        return engine.nativeAllocationError(err, generation);
    };
    engine.freeValue(result);
    if (generation != engine.native_allocation_generation) return error.OutOfMemory;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const actual = try engine.stringify(try scope.get(global, "autoCompactionRows"));
    defer gpa.free(actual);
    const bytes = @embedFile("extensions/fixtures/sdk-session-auto-compaction-b45.json");
    const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "auto-original40.json")));
    const raw = try engine.stringify(try scope.get(expected, "rows"));
    defer gpa.free(raw);
    if (!std.mem.eql(u8, actual, raw)) {
        std.debug.print("Actual auto40:\n{s}\nExpected original40:\n{s}\n", .{ actual, raw });
        return error.NativeAutomaticCompactionMismatch;
    }
}
test "native automatic compaction matches actual b45 auto40 and controller ownership" {
    try run(std.testing.allocator);
}
test "native automatic compaction complete representative host allocation universe" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "sdk-auto-compact40", run, .{});
}
test "native automatic compaction descriptor matches genuine Source166" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const result = try engine.evalModule(
        \\const f=autoCompactionAPI.run;if(f.name!=='_runAutoCompaction'||f.length!==2||Object.hasOwn(f,'prototype')||Object.getPrototypeOf(f)!==Object.getPrototypeOf(async()=>{}))throw Error('actual async Source method descriptor');
    , "automatic-compaction-descriptor.mjs");
    engine.freeValue(result);
}

test "native automatic compaction pending summary retains owned controller and preserves replacement through GC" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const prepared = try engine.evalModule(
        \\globalThis.autoGcEvents=[];globalThis.autoGcSaved=[];globalThis.autoGcIdle=0;globalThis.autoGcReplacement={replacement:true};globalThis.autoGcSession={model:{id:'owned'},_entryIdsByMessage:new WeakMap(),agent:{state:{messages:[]},hasQueuedMessages(){throw Error('retry must bypass queue lookup');}},settingsManager:{getCompactionSettings(){return{enabled:true,reserveTokens:4,keepRecentTokens:1};}},sessionManager:{getBranch(){return[{id:'old',parentId:null,type:'message',message:{role:'user',content:'old',timestamp:0}},{id:'new',parentId:'old',type:'message',message:{role:'user',content:'new',timestamp:1}}];},appendCompaction(summary){autoGcSaved.push({type:'compaction',summary});},getEntries(){return autoGcSaved;},buildSessionProjection(){return{entries:[],messages:[]};}},_extensionRunner:{hasHandlers(){return false;},emit(event){autoGcEvents.push(event.type);}},_emit(event){autoGcEvents.push(event.type);},_resolveIdleWaitIfIdle(){autoGcIdle++;if(this._autoCompactionAbortController!==autoGcReplacement)throw Error('replacement overwritten');},_runDefaultCompaction(){globalThis.autoGcControllerWeak=new WeakRef(this._autoCompactionAbortController);this._autoCompactionAbortController=autoGcReplacement;return new Promise(resolve=>{globalThis.autoGcRelease=resolve;});},_emitSessionCompactFailed:autoCompactionAPI.failed,_refreshFinalizedContext:autoCompactionAPI.refresh};globalThis.autoGcWeak=new WeakRef(autoGcSession);globalThis.autoGcPending=autoCompactionAPI.run.call(autoGcSession,'overflow',true);delete globalThis.autoGcSession;export const ready=true;
    , "automatic-compaction-gc-prepare.mjs");
    engine.freeValue(prepared);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const retained = try engine.eval("autoGcWeak.deref()!==undefined&&autoGcControllerWeak.deref()!==undefined&&typeof autoGcRelease==='function'", "automatic-compaction-gc-retained.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(retained);
    try std.testing.expect(c.JS_ToBool(engine.context, retained) == 1);
    engine.finishJob();
    const completed = try engine.evalModule(
        \\autoGcRelease({summary:'retained automatic',firstKeptEntryId:'new',tokensBefore:9});if((await autoGcPending)!==true||autoGcIdle!==1||JSON.stringify(autoGcEvents)!==JSON.stringify(['compaction_start','session_compact','compaction_end']))throw Error('pending automatic graph lost');delete globalThis.autoGcPending;delete globalThis.autoGcRelease;delete globalThis.autoGcSaved;export const completed=true;
    , "automatic-compaction-gc-complete.mjs");
    engine.freeValue(completed);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const collected = try engine.eval("autoGcWeak.deref()===undefined&&autoGcControllerWeak.deref()===undefined", "automatic-compaction-gc-collected.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(collected);
    try std.testing.expect(c.JS_ToBool(engine.context, collected) == 1);
}
