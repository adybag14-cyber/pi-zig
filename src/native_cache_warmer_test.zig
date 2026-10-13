const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;
test "native SDK cache warmer selected inventory" {
    const functions = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, functions.len);
    defer std.testing.allocator.free(names);
    for (functions, names) |function, *name| name.* = function.name;
    const bytes = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(bytes);
    std.debug.print("CACHE_WARMER_TEST_INVENTORY={s}\n", .{bytes});
}
fn setup(engine: *em.Engine, environment: *std.process.Environ.Map) !void {
    engine.native_io = std.testing.io;
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/native_process.zig").install(engine, std.testing.io, environment, &.{"native-cache-warmer"});
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "cacheWarmerAPI", try @import("extensions/native_cache_warmer.zig").createBindings(engine));
    try sdk.put(engine, global, "calculateCost", try @import("extensions/native_ai_cost.zig").create(engine));
    try sdk.put(engine, global, "getProviderEnvValue", try @import("extensions/native_provider_env.zig").create(engine));
}
test "native SDK cache warmer matches70 genuine latest Source economics lifecycle cancellation and class cases" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/sdk-cache-warmer-e622.json");
    try sdk.put(engine, global, "cacheWarmerSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-cache-warmer-e622.json")));
    const observed = engine.evalModule(@embedFile("extensions/fixtures/sdk-cache-warmer-e622.input.txt") ++
        "\nif(cacheWarmerRows.length!==70||cacheWarmerSource.rows.length!==70)throw Error('70 genuine Source cases required');for(let i=0;i<70;i++)if(JSON.stringify(cacheWarmerRows[i])!==JSON.stringify(cacheWarmerSource.rows[i]))throw Error(JSON.stringify({case:i,actual:cacheWarmerRows[i],expected:cacheWarmerSource.rows[i]}));", "native-cache-warmer-source.mjs") catch |err| {
        std.debug.print("Cache warmer latest Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(observed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK cache warmer real timer refresh and cancellation survive explicit collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const module = try engine.evalModule(
        \\const{CacheWarmer}=cacheWarmerAPI;const calls=[];const model={id:'fixture',provider:'fixture',api:'openai-completions',promptCache:{short:11},cost:{input:10,output:20,cacheRead:1,cacheWrite:12.5}};const manager={getBranch(){return[{type:'message',message:{role:'assistant',usage:{input:2000000,cacheRead:0,cacheWrite:0}}}]},appendUsage(...args){calls.push(args);return args}};const warmer=new CacheWarmer({streamSimple(){return{result:async()=>({provider:'fixture',model:'fixture',stopReason:'stop',usage:{cost:{total:.1}}})}}},manager,()=> 'always');warmer.onWarmed=()=>warmer.cancel();warmer.start({model,context:{messages:[]},options:{cacheRetention:'short'}},()=>true);globalThis.retainedCacheWarmer=warmer;export const ready=true;
    , "native-cache-warmer-live-setup.mjs");
    engine.freeValue(module);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\await new Promise(resolve=>setTimeout(resolve,1300));if(retainedCacheWarmer.status.reason!=='inactive'||retainedCacheWarmer.run!==undefined)throw Error('real warming callback did not cancel');delete globalThis.retainedCacheWarmer;export const completed=true;
    , "native-cache-warmer-live-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK cache warmer formatters match34 genuine latest Source statuses prices and intrinsic regular expressions" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/sdk-cache-warmer-format-e622.json");
    try sdk.put(engine, global, "cacheWarmerFormattingSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-cache-warmer-format-e622.json")));
    const observed = engine.evalModule(@embedFile("extensions/fixtures/sdk-cache-warmer-format-e622.input.txt") ++
        "\nif(cacheWarmerFormattingRows.length!==34||cacheWarmerFormattingSource.rows.length!==34)throw Error('34 Source formatter cases required');for(let i=0;i<34;i++)if(JSON.stringify(cacheWarmerFormattingRows[i])!==JSON.stringify(cacheWarmerFormattingSource.rows[i]))throw Error(JSON.stringify({case:i,actual:cacheWarmerFormattingRows[i],expected:cacheWarmerFormattingSource.rows[i]}));", "native-cache-warmer-format.mjs") catch |err| {
        std.debug.print("Cache warmer formatter Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(observed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK cache warmer allocation failures retain fatal provenance and release owner graphs" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            var environment: std.process.Environ.Map = .init(gpa);
            defer environment.deinit();
            try setup(engine, &environment);
            const generation = engine.native_allocation_generation;
            const module = engine.evalModule(
                \\const{CacheWarmer}=cacheWarmerAPI;const originalTimeout=globalThis.setTimeout,originalClear=globalThis.clearTimeout;let callback;globalThis.setTimeout=fn=>{callback=fn;return{unref(){}}};globalThis.clearTimeout=()=>{};try{const model={api:'openai-completions',promptCache:{short:20},cost:{input:10,output:20,cacheRead:1,cacheWrite:12.5}},manager={getBranch:()=>[{type:'message',message:{role:'assistant',usage:{input:2000000,cacheRead:0,cacheWrite:0}}}],appendUsage:()=>({type:'usage'})};const warmer=new CacheWarmer({streamSimple:()=>({result:async()=>({provider:'fixture',model:'fixture',stopReason:'stop',usage:{cost:{total:.1}}})})},manager,()=> 'always');warmer.start({model,context:{messages:[]},options:{cacheRetention:'short'}},()=>true);cacheWarmerAPI.formatCacheWarmingStatus(warmer.status,0);cacheWarmerAPI.formatCacheWarmingUsage({note:'extension override',usage:{cost:{total:.1}}});getProviderEnvValue('PI_CACHE_RETENTION',{PI_CACHE_RETENTION:'long'});await warmer.refresh(warmer.run);warmer.cancel();callback=undefined;}finally{globalThis.setTimeout=originalTimeout;globalThis.clearTimeout=originalClear}export const proof=true;
            , "native-cache-warmer-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(module);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
