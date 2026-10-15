//! Latest Source navigateTree and genuine branch-summary collaborator corpus.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
pub fn setup(engine: *em.Engine, environment: *std.process.Environ.Map) !void {
    engine.native_io = std.testing.io;
    try @import("extensions/native_process.zig").install(engine, std.testing.io, environment, &.{"native-sdk-navigate"});
    try @import("extensions/abort_signal.zig").install(engine);
    // Actual completeSummarization with native uuid/retry; the caller-provided
    // stream in every nonempty fixture prevents use of the controlled default.
    try @import("native_sdk_complete_summarization_test.zig").setup(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const complete = try scope.get(try scope.get(global, "summaryAPI"), "completeSummarization");
    const api = try scope.own(try @import("extensions/native_sdk_branch_summary.zig").exports(engine, complete));
    const sdk_namespace = try scope.object();
    try sdk.install(engine, sdk_namespace);
    try scope.put(api, "SessionManager", try scope.get(sdk_namespace, "SessionManager"));
    const prototype = try scope.object();
    try @import("extensions/native_sdk_session_navigate.zig").install(engine, prototype, api);
    try scope.put(api, "prototype", prototype);
    const refresh = try scope.object();
    try @import("extensions/native_sdk_session_compaction.zig").installHelpers(engine, refresh);
    try scope.put(api, "refresh", try scope.get(refresh, "_refreshFinalizedContext"));
    try scope.put(global, "navigationAPI", api);
}
test "native SDK navigate actual latest Source branch helpers and full method corpus" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const evaluated = engine.evalModule(@embedFile("extensions/fixtures/sdk-session-navigate-5ab.input.txt"), "native-sdk-navigate-source.mjs") catch |err| {
        std.debug.print("Navigate corpus failed: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    engine.freeValue(evaluated);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const actual = try engine.stringify(try scope.get(global, "navigationRows"));
    defer std.testing.allocator.free(actual);
    const bytes = @embedFile("extensions/fixtures/sdk-session-navigate-5ab.json");
    const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "navigate-source-5ab.json")));
    const reference = try engine.stringify(try scope.get(expected, "rows"));
    defer std.testing.allocator.free(reference);
    if (!std.mem.eql(u8, actual, reference)) {
        std.debug.print("Actual navigate:\n{s}\nExpected:\n{s}\n", .{ actual, reference });
        return error.NativeNavigateDifferentialMismatch;
    }
}

fn ownership(gpa: std.mem.Allocator, comptime reject_auth: bool) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try setup(engine, &environment);
    const program =
        \\globalThis.navigationGcIdle=0;globalThis.navigationGcRejectAuth=
    ++ (if (reject_auth) "true;" else "false;") ++
        \\(()=>{const manager=navigationAPI.SessionManager.inMemory('C:/navigation');const target=manager.appendMessage({role:'user',content:'target',timestamp:0});manager.appendMessage({role:'assistant',content:[{type:'text',text:'old'}],api:'fixture',provider:'fixture',model:'fixture',usage:{input:1,output:0,cacheRead:0,cacheWrite:0,totalTokens:1,cost:{input:0,output:0,cacheRead:0,cacheWrite:0,total:0}},stopReason:'stop',timestamp:0});const s=Object.assign(Object.create(navigationAPI.prototype),{sessionManager:manager,isStreaming:false,isCompacting:false,model:{id:'fixture',contextWindow:2048,maxTokens:1000},agent:{state:{messages:[],tools:[]}},_entryIdsByMessage:new WeakMap(),settingsManager:{getBranchSummarySettings(){return{reserveTokens:0}}},_extensionRunner:{hasHandlers(){return!navigationGcRejectAuth},emit(event){if(event.type==='session_before_tree')return new Promise(resolve=>{globalThis.navigationGcRelease=resolve})}},_getSummarizationRequestAuth(){return new Promise((resolve,reject)=>{globalThis.navigationGcRelease=reject})},_refreshFinalizedContext(){navigationAPI.refresh.call(this)},_restoreToolsFromTranscript(){},_resolveIdleWaitIfIdle(){if(this._branchSummaryAbortController!==undefined)throw Error('controller not cleared before idle');navigationGcIdle++}});globalThis.navigationGcWeak=new WeakRef(s);globalThis.navigationGcPending=s.navigateTree(target,{summarize:navigationGcRejectAuth});})();export const ready=true;
    ;
    const prepared = try engine.evalModule(program, "native-navigation-gc-ready.mjs");
    engine.freeValue(prepared);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const retained = try engine.eval("navigationGcWeak.deref()!==undefined&&typeof navigationGcRelease==='function'", "native-navigation-gc-retained.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(retained);
    try std.testing.expect(c.JS_ToBool(engine.context, retained) == 1);
    engine.finishJob();
    const completion = if (reject_auth)
        \\const marker={raw:'auth'};navigationGcRelease(marker);let caught=false;try{await navigationGcPending}catch(error){if(error!==marker)throw Error('raw rejection replaced');caught=true}if(!caught||navigationGcIdle!==1)throw Error('auth finally missing');delete globalThis.navigationGcRelease;delete globalThis.navigationGcPending;export const complete=true;
    else
        \\navigationGcRelease();const result=await navigationGcPending;if(result.cancelled||result.editorText!=='target'||navigationGcIdle!==1)throw Error('before-tree graph lost');delete globalThis.navigationGcRelease;delete globalThis.navigationGcPending;export const complete=true;
    ;
    const completed = try engine.evalModule(completion, "native-navigation-gc-complete.mjs");
    engine.freeValue(completed);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const collected = try engine.eval("navigationGcWeak.deref()===undefined", "native-navigation-gc-collected.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(collected);
    try std.testing.expect(c.JS_ToBool(engine.context, collected) == 1);
}
test "native SDK navigate pending before-tree retains session until completion then releases graph" {
    try ownership(std.testing.allocator, false);
}
test "native SDK navigate pending auth raw rejection runs finally and releases session graph" {
    try ownership(std.testing.allocator, true);
}
