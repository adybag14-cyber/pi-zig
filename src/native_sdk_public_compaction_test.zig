//! Actual shared-AI/public-compaction graph controls. The imported AI compat,
//! completion, UUID, retry, branch and serializer implementations are genuine.
//! No completion callback or public namespace is supplied by the fixture.
const std = @import("std");
const h = @import("extensions/native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const assembly = @import("extensions/native_sdk_session_ai_assembly.zig");
const public = @import("extensions/native_sdk_public_compaction.zig");

fn prepare(engine: *h.Engine) !void {
    var s: h.Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, prepareBody(&s));
}
fn prepareBody(s: *h.Scope) !void {
    const engine = s.engine;
    engine.native_io = std.testing.io;
    const ai = try v.own(s, try @import("extensions/native_sdk_ai_imports.zig").create(engine));
    const compat = try v.get(s, ai, "compat");
    const shared = try v.own(s, try assembly.create(engine, compat));
    const compaction = try v.get(s, shared, "compaction");
    const global = try v.own(s, c.JS_GetGlobalObject(engine.context));
    try v.put(s, global, "actualSharedCompaction", shared);
    try v.put(s, global, "actualCompactionIndex", compaction);
    const request = try v.get(s, shared, "completeSummarization");
    try std.testing.expect(v.equal(s, compaction, try v.own(s, try public.create(engine, request))));
    try std.testing.expect(v.equal(s, shared, try v.own(s, try assembly.create(engine, compat))));
    const core = try v.own(s, try @import("extensions/native_sdk_public_compaction_core.zig").create(engine));
    const branch = try v.own(s, try @import("extensions/native_sdk_branch_summary.zig").exports(engine, request));
    const summary = try v.own(s, try @import("extensions/native_sdk_summary_generation.zig").exports(engine, request));
    const serializer = try v.own(s, try @import("extensions/native_sdk_compaction_text.zig").exports(engine));
    inline for (.{
        .{ "calculateContextTokens", core }, .{ "DEFAULT_COMPACTION_SETTINGS", core },
        .{ "estimateTokens", core }, .{ "findCutPoint", core }, .{ "findTurnStartIndex", core },
        .{ "getLastAssistantUsage", core }, .{ "shouldCompact", core },
        .{ "collectEntriesForBranchSummary", branch }, .{ "generateBranchSummary", branch },
        .{ "prepareBranchEntries", branch }, .{ "compact", summary },
        .{ "generateSummary", summary }, .{ "generateSummaryWithUsage", summary },
        .{ "serializeConversation", serializer },
    }) |entry| try std.testing.expect(v.equal(s, try v.get(s, compaction, entry[0]), try v.get(s, entry[1], entry[0])));
    try v.put(s, global, "actualCompactionCore", core);
}
fn run(engine: *h.Engine, source: []const u8) !void {
    engine.freeValue(try engine.evalModule(source, "actual-compaction-index-control.mjs"));
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
test "SDK public compaction index contains all fourteen actual owner bindings" {
    const engine = try h.Engine.init(std.testing.allocator, .{});
    defer engine.deinit(); try prepare(engine);
    try run(engine,
        \\const expected=["calculateContextTokens","collectEntriesForBranchSummary","compact","DEFAULT_COMPACTION_SETTINGS","estimateTokens","findCutPoint","findTurnStartIndex","generateBranchSummary","generateSummary","generateSummaryWithUsage","getLastAssistantUsage","prepareBranchEntries","serializeConversation","shouldCompact"].sort();
        \\const actual=Reflect.ownKeys(actualCompactionIndex).sort();
        \\if(JSON.stringify(actual)!==JSON.stringify(expected))throw new Error("actual compaction index bindings");
        \\for(const name of expected)if(name!=="DEFAULT_COMPACTION_SETTINGS"&&typeof actualCompactionIndex[name]!=="function")throw new Error(name);
    );
}
test "SDK public compaction shares session branch functions and mutable default object" {
    const engine = try h.Engine.init(std.testing.allocator, .{});
    defer engine.deinit(); try prepare(engine);
    try run(engine,
        \\for(const name of ["compact","generateSummary","generateSummaryWithUsage"])if(actualCompactionIndex[name]!==actualSharedCompaction[name])throw new Error("session import "+name);
        \\for(const name of ["collectEntriesForBranchSummary","generateBranchSummary","prepareBranchEntries"])if(actualCompactionIndex[name]!==actualSharedCompaction.branchSummary[name])throw new Error("branch import "+name);
        \\const defaults=actualCompactionIndex.DEFAULT_COMPACTION_SETTINGS;
        \\const old=defaults.keepRecentTokens;
        \\try{defaults.keepRecentTokens=41;if(actualCompactionCore.DEFAULT_COMPACTION_SETTINGS.keepRecentTokens!==41)throw new Error("same exported default binding");}
        \\finally{defaults.keepRecentTokens=old;}
    );
}
test "SDK public compaction executes its real pure bodies and intrinsic branch async body" {
    const engine = try h.Engine.init(std.testing.allocator, .{});
    defer engine.deinit(); try prepare(engine);
    try run(engine,
        \\const api=actualCompactionIndex;
        \\if(api.calculateContextTokens({input:11,output:7,cacheRead:3,cacheWrite:2})!==23)throw new Error("actual usage");
        \\if(api.serializeConversation([{role:"user",content:"hello"}])!=="[User]: hello")throw new Error("actual serializer");
        \\if(api.prepareBranchEntries([]).messages.length!==0)throw new Error("actual preparation");
        \\const saved=globalThis.Promise;
        \\try{globalThis.Promise=function(){throw new Error("global Promise must not construct branch AF");};const pending=api.generateBranchSummary([],{model:{contextWindow:4096}});if(!(pending instanceof saved))throw new Error("actual async capability");if(await pending!==undefined)throw new Error("actual empty branch result");}
        \\finally{globalThis.Promise=saved;}
    );
}
