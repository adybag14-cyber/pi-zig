const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;
fn setup(engine: *em.Engine, environment: *std.process.Environ.Map) !void {
    try @import("native_sdk_session_prompt_handlers_test.zig").setup(engine, environment);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const namespace = try sdk.get(engine, global, "constructorPhaseSDK");
    defer engine.freeValue(namespace);
    const constructor = try sdk.get(engine, namespace, "AgentSession");
    defer engine.freeValue(constructor);
    const prototype = try sdk.get(engine, constructor, "prototype");
    defer engine.freeValue(prototype);
    try @import("extensions/native_sdk_session_statistics.zig").install(engine, prototype);
    const source = @embedFile("extensions/fixtures/sdk-session-statistics-1692.json");
    try sdk.put(engine, global, "sessionStatisticsSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-session-statistics-1692.json")));
    const adapter = try engine.evalModule(
        \\globalThis.createStatisticsCase=async()=>createNativeConstructorPhase();
    , "native-sdk-session-statistics-adapter.mjs");
    engine.freeValue(adapter);
}
test "native SDK session statistics match36 original factory billing context compaction getters and coercion cases" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-session-statistics-1692.input.txt") ++
        "\nif(sessionStatisticsSource.sourceHead!=='1692bba6347a287ab0f3cb554a4430fafffc474b'||sessionStatisticsRows.length!==36||sessionStatisticsSource.rows.length!==36)throw Error('36 original latest cases required');for(let i=0;i<36;i++)if(JSON.stringify(sessionStatisticsRows[i])!==JSON.stringify(sessionStatisticsSource.rows[i]))throw Error(JSON.stringify({case:i,actual:sessionStatisticsRows[i],expected:sessionStatisticsSource.rows[i]}));", "native-sdk-session-statistics-source.mjs") catch |err| {
        std.debug.print("Session statistics Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session statistics retained collection callbacks preserve compaction and membership roots across collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const prepared = try engine.evalModule(
        \\const state=await createStatisticsCase(),compact={id:'compact',type:'compaction'},after={id:'after',type:'message',message:{role:'assistant',stopReason:'stop',content:[],usage:{input:1,output:2,cacheRead:3,cacheWrite:4,totalTokens:10,cost:{total:0}}}},branch=[compact,after];const finders=[];let contains;branch.findIndex=function(callback){finders.push(callback);return Array.prototype.findIndex.call(this,callback);};branch.slice=function(...args){const sliced=Array.prototype.slice.apply(this,args);sliced.some=function(callback){contains=callback;return Array.prototype.some.call(this,callback);};return sliced;};state.manager.getBranch=()=>branch;state.manager.buildSessionProjection=()=>({messages:[after.message],entries:[{sourceEntry:after,messages:[after.message]}]});const value=state.session.getContextUsage();if(value.tokens!==10)throw Error('context usage');globalThis.statisticsRetained={state,finder:finders[0],contains,compact,after};export const prepared=true;
    , "native-sdk-session-statistics-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\const r=statisticsRetained;if(!r.finder(r.compact)||r.finder(r.after)||!r.contains(r.after)||r.contains(r.compact))throw Error('retained callback roots');r.state.dispose();delete globalThis.statisticsRetained;export const completed=true;
    , "native-sdk-session-statistics-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session statistics every allocation failure releases billed totals context collections and callback roots" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            var environment: std.process.Environ.Map = .init(gpa);
            defer environment.deinit();
            const generation = engine.native_allocation_generation;
            setup(engine, &environment) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const state=await createStatisticsCase(),compact={id:'compact',type:'compaction'},usage={input:1,output:2,cacheRead:3,cacheWrite:4,totalTokens:10,cost:{total:0.5}},after={id:'after',type:'message',message:{role:'assistant',stopReason:'stop',usage,content:[{type:'toolCall',name:'tool',arguments:{}}]}},branch=[compact,after];state.manager.getBranch=()=>branch;state.manager.getEntries=()=>branch;state.manager.buildSessionProjection=()=>({messages:[after.message],entries:[{sourceEntry:after,messages:[after.message]}]});const result=state.session.getSessionStats();if(result.tokens.total!==10||result.cost!==0.5||result.toolCalls!==1||result.contextUsage.tokens!==10)throw Error('statistics allocation result');state.dispose();export const proof=true;
            , "native-sdk-session-statistics-allocations.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
