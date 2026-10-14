//! Actual manual compaction methods; caller-controlled summary generation is
//! explicit here, while lower summary generation has its own genuine corpus.
const std = @import("std");
const builtin = @import("builtin");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
pub fn setup(engine: *em.Engine, environment: *std.process.Environ.Map) !void {
    try @import("native_sdk_complete_summarization_test.zig").setup(engine);
    try @import("extensions/native_crypto_random.zig").install(engine);
    try @import("extensions/abort_signal.zig").install(engine);
    try environment.put("PI_PACKAGE_DIR", if (builtin.os.tag == .windows) "C:/Users/adyba/pi-upstream-runtime-19cb534-20261012/packages/coding-agent" else "/owned/pi-package");
    try @import("extensions/native_process.zig").install(engine, std.testing.io, environment, &.{"native-manual-compaction"});
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const request = try scope.get(try scope.get(global, "summaryAPI"), "completeSummarization");
    const generation = try scope.own(try @import("extensions/native_sdk_summary_generation.zig").exports(engine, request));
    const prototype = try scope.object();
    try @import("extensions/native_sdk_session_compaction.zig").install(engine, prototype, try scope.get(generation, "compact"));
    const api = try scope.object();
    inline for (.{ "compact", "clear", "failed", "refresh", "defaultSummary" }, .{ "compact", "_clearManualCompactionState", "_emitSessionCompactFailed", "_refreshFinalizedContext", "_runDefaultCompaction" }) |key, name| try scope.put(api, key, try scope.get(prototype, name));
    const files = try scope.own(try @import("extensions/native_sdk_compaction_files.zig").exports(engine));
    try scope.put(api, "createFileOps", try scope.get(files, "createFileOps"));
    try scope.put(global, "manualCompactionAPI", api);
    try scope.put(global, "manualCompactionPrototype", prototype);
}
fn run(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    setup(engine, &environment) catch |err| return engine.nativeAllocationError(err, generation);
    const evaluated = engine.evalModule(@embedFile("extensions/fixtures/sdk-session-manual-compaction-b45.input.txt"), "manual-compaction-original44.mjs") catch |err| {
        std.debug.print("Actual manual compaction44 failed: {s}\n", .{engine.last_error orelse @errorName(err)});
        return engine.nativeAllocationError(err, generation);
    };
    engine.freeValue(evaluated);
    if (generation != engine.native_allocation_generation) return error.OutOfMemory;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const actual = try engine.stringify(try scope.get(global, "manualCompactionRows"));
    defer gpa.free(actual);
    const bytes = if (builtin.os.tag == .windows) @embedFile("extensions/fixtures/sdk-session-manual-compaction-b45.json") else @embedFile("extensions/fixtures/sdk-session-manual-compaction-b45-posix.json");
    const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "manual-original44.json")));
    const raw = try engine.stringify(try scope.get(expected, "rows"));
    defer gpa.free(raw);
    if (!std.mem.eql(u8, actual, raw)) {
        std.debug.print("Actual manual44:\n{s}\nExpected original44:\n{s}\n", .{ actual, raw });
        return error.NativeManualCompactionMismatch;
    }
}
test "native ordinary compaction matches actual b45 manual44 including persistence failure and finally" {
    try run(std.testing.allocator);
}
test "native ordinary compaction complete representative host allocation universe" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "sdk-manual-compact44", run, .{});
}
test "native ordinary compaction installed method descriptors match genuine Source166 subset" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const bytes = @embedFile("extensions/fixtures/sdk-session-prototype-original-e622.json");
    try scope.put(global, "manualClassSource", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "manual-class-source.json"))));
    const checked = try engine.evalModule(
        \\const p=manualCompactionPrototype, summarize=f=>({name:f.name,length:f.length,async:Object.getPrototypeOf(f)===Object.getPrototypeOf(async()=>{}),ownPrototype:Object.hasOwn(f,'prototype')});for(const key of Reflect.ownKeys(p)){const d=Object.getOwnPropertyDescriptor(p,key),actual={key,kind:'data',enumerable:d.enumerable,configurable:d.configurable,writable:d.writable,valueType:typeof d.value,function:summarize(d.value)},expected=manualClassSource.descriptors.find(x=>x.key===key);if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({actual,expected}));}if(Reflect.ownKeys(p).length!==5)throw Error('five actual ordinary methods');
    , "manual-class-descriptors.mjs");
    engine.freeValue(checked);
}

test "native ordinary compaction pending summary owns session until completion and releases it after collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const prepared = try engine.evalModule(
        \\globalThis.compactGcEvents=[];globalThis.compactGcSaved=[];globalThis.compactGcIdle=0;globalThis.compactGcSession={model:{id:'owned'},_entryIdsByMessage:new WeakMap(),agent:{state:{messages:[]}},abort(){return Promise.resolve();},settingsManager:{getCompactionSettings(){return{enabled:true,reserveTokens:4,keepRecentTokens:1};}},sessionManager:{getBranch(){return[{id:'old',parentId:null,type:'message',message:{role:'user',content:'old',timestamp:0}},{id:'new',parentId:'old',type:'message',message:{role:'user',content:'new',timestamp:1}}];},appendCompaction(summary){compactGcSaved.push({type:'compaction',summary});},getEntries(){return compactGcSaved;},buildSessionProjection(){return{entries:[],messages:[]};}},_extensionRunner:{hasHandlers(){return false;},emit(event){compactGcEvents.push(event.type);}},_emit(event){compactGcEvents.push(event.type);},_resolveIdleWaitIfIdle(){compactGcIdle++;},_runDefaultCompaction(){return new Promise(resolve=>{globalThis.compactGcRelease=resolve;});},_clearManualCompactionState:manualCompactionAPI.clear,_emitSessionCompactFailed:manualCompactionAPI.failed,_refreshFinalizedContext:manualCompactionAPI.refresh};globalThis.compactGcWeak=new WeakRef(compactGcSession);globalThis.compactGcPending=manualCompactionAPI.compact.call(compactGcSession,'owned');delete globalThis.compactGcSession;export const ready=true;
    , "manual-compaction-gc-prepare.mjs");
    engine.freeValue(prepared);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const retained = try engine.eval("compactGcWeak.deref()!==undefined&&typeof compactGcRelease==='function'", "manual-compaction-gc-retained.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(retained);
    try std.testing.expect(c.JS_ToBool(engine.context, retained) == 1);
    engine.finishJob();
    const completed = try engine.evalModule(
        \\compactGcRelease({summary:'retained summary',firstKeptEntryId:'new',tokensBefore:9});if((await compactGcPending).summary!=='retained summary'||compactGcIdle!==2||JSON.stringify(compactGcEvents)!==JSON.stringify(['compaction_start','session_compact','compaction_end']))throw Error('pending manual graph lost');delete globalThis.compactGcPending;delete globalThis.compactGcRelease;delete globalThis.compactGcSaved;export const completed=true;
    , "manual-compaction-gc-complete.mjs");
    engine.freeValue(completed);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const collected = try engine.eval("compactGcWeak.deref()===undefined", "manual-compaction-gc-collected.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(collected);
    try std.testing.expect(c.JS_ToBool(engine.context, collected) == 1);
}
