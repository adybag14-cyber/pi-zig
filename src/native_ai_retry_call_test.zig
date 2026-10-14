const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;
fn install(engine: *em.Engine) !void {
    engine.native_io = std.testing.io;
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const api = try sdk.object(engine);
    defer engine.freeValue(api);
    try sdk.put(engine, api, "retryAssistantCall", try @import("extensions/native_ai_retry_call.zig").create(engine));
    try sdk.put(engine, global, "aiRetryAPI", c.JS_DupValue(engine.context, api));
}
test "native AI retry call matches30 original callbacks promises abort classes getters and error identities" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/ai-retry-call-1692.json");
    try sdk.put(engine, global, "aiRetrySource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "ai-retry-call-1692.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/ai-retry-call-1692.input.txt") ++
        "\nif(aiRetrySource.sourceHead!=='1692bba6347a287ab0f3cb554a4430fafffc474b'||aiRetryRows.length!==30||aiRetrySource.rows.length!==30)throw Error('30 original observations required');for(let i=0;i<30;i++)if(JSON.stringify(aiRetryRows[i])!==JSON.stringify(aiRetrySource.rows[i]))throw Error(JSON.stringify({case:i,actual:aiRetryRows[i],expected:aiRetrySource.rows[i]}));", "native-ai-retry-call-source.mjs") catch |err| {
        std.debug.print("AI retry Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native AI retry call retains pending producer and private abort constructor across collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const prepared = try engine.evalModule(
        \\globalThis.retainedRetry=aiRetryAPI.retryAssistantCall;delete globalThis.aiRetryAPI;const response={role:'assistant',stopReason:'stop',content:[]};let release;const pending=new Promise(resolve=>{release=()=>resolve(response);});globalThis.pendingRetry={response,release,work:retainedRetry(()=>pending,undefined,undefined)};export const prepared=true;
    , "native-ai-retry-call-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\pendingRetry.release();if(await pendingRetry.work!==pendingRetry.response)throw Error('pending producer identity');const aborted=await retainedRetry(()=>Promise.resolve({role:'assistant',stopReason:'error',errorMessage:'terminated',content:[]}),{enabled:true,maxRetries:1,baseDelayMs:0},{aborted:true});if(aborted.stopReason!=='aborted'||Object.hasOwn(aborted,'errorMessage'))throw Error('retained abort class');delete globalThis.retainedRetry;delete globalThis.pendingRetry;export const completed=true;
    , "native-ai-retry-call-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native AI retry call every allocation releases actual async producer callbacks sleep and private subclass roots" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            install(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const f=aiRetryAPI.retryAssistantCall,error={role:'assistant',stopReason:'error',errorMessage:'terminated',content:[]},success={role:'assistant',stopReason:'stop',content:[]},policy={enabled:true,maxRetries:1,baseDelayMs:0};let calls=0,finished=0;const callbacks={onRetryScheduled(){},onRetryAttemptStart(){},onRetryFinished(){finished++;}};if(await f(()=>Promise.resolve(++calls===1?error:success),policy,undefined,callbacks)!==success||finished!==1)throw Error('retry graph');const aborted=await f(()=>Promise.resolve(error),policy,{aborted:true},callbacks);if(aborted.stopReason!=='aborted'||Object.hasOwn(aborted,'errorMessage')||finished!==2)throw Error('abort graph');const marker={};try{await f(()=>Promise.resolve(error),policy,undefined,{onRetryScheduled(){throw marker;}});throw Error('expected callback rejection');}catch(reason){if(reason!==marker)throw reason;}export const proof=true;
            , "native-ai-retry-call-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
