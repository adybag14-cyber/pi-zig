const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;
fn install(engine: *em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const api = try sdk.object(engine);
    defer engine.freeValue(api);
    try sdk.put(engine, api, "estimateTokens", try @import("extensions/native_sdk_compaction_estimate.zig").create(engine));
    try sdk.put(engine, global, "tokenEstimateAPI", c.JS_DupValue(engine.context, api));
}
test "native SDK compaction estimate matches30 original iterator getter coercion and function metadata observations" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/sdk-compaction-estimate-1692.json");
    try sdk.put(engine, global, "tokenEstimateSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-compaction-estimate-1692.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-compaction-estimate-1692.input.txt") ++
        "\nif(tokenEstimateSource.sourceHead!=='1692bba6347a287ab0f3cb554a4430fafffc474b'||tokenEstimateRows.length!==30||tokenEstimateSource.rows.length!==30)throw Error('30 original observations required');for(let i=0;i<30;i++)if(JSON.stringify(tokenEstimateRows[i])!==JSON.stringify(tokenEstimateSource.rows[i]))throw Error(JSON.stringify({case:i,actual:tokenEstimateRows[i],expected:tokenEstimateSource.rows[i]}));", "native-sdk-compaction-estimate-source.mjs") catch |err| {
        std.debug.print("Compaction estimate Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native SDK compaction estimate retained ordinary export remains constructable after collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const prepared = try engine.evalModule(
        \\globalThis.retainedEstimate=tokenEstimateAPI.estimateTokens;delete globalThis.tokenEstimateAPI;export const prepared=true;
    , "native-sdk-compaction-estimate-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\if(retainedEstimate({role:'user',content:'abcde'})!==2||!(new retainedEstimate({role:'user',content:''}) instanceof retainedEstimate))throw Error('retained estimate export lost');delete globalThis.retainedEstimate;export const completed=true;
    , "native-sdk-compaction-estimate-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK compaction estimate every allocation failure releases iterator ordinary function and coercion roots" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            install(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const e=tokenEstimateAPI.estimateTokens;if(e({role:'system',content:[{type:'text',text:'a'},{type:'image'}],sections:{first:'abc',skip:null},toolsAdded:[{name:'read'}]})<=1200)throw Error('system estimate');if(e({role:'assistant',content:[{type:'text',text:'text'},{type:'thinking',thinking:'reason'},{type:'toolCall',name:'read',arguments:{path:'a'}}]})<=0)throw Error('assistant estimate');const marker={},content={*[Symbol.iterator](){try{yield{type:'text',get text(){throw marker;}};}finally{}}};try{e({role:'user',content});throw Error('expected getter failure');}catch(error){if(error!==marker)throw error;}export const proof=true;
            , "native-sdk-compaction-estimate-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
