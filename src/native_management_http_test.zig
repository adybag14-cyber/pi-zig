//! Registration is deliberately left to the central build owner: this lane
//! adds new modules/tests only and has no native build grant.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
fn install(engine: *v.em.Engine) !void {
    engine.native_io = std.testing.io;
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/abort_signal.zig").install(engine);
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(try scope.own(c.JS_GetGlobalObject(engine.context)), "managementHTTPAPI", try scope.own(try @import("extensions/native_management_http.zig").create(engine)));
}
fn evaluate(engine: *v.em.Engine, source: []const u8, name: [:0]const u8) !void {
    const result = engine.evalModule(source, name) catch |err| {
        std.debug.print("Management HTTP: {s}\n", .{engine.last_error orelse @errorName(err)});
        return err;
    };
    engine.freeValue(result);
}
test "native management HTTP actual retry status cancellation getter order and deadlines" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000, .interrupt_budget = 10000000 });
    defer engine.deinit();
    try install(engine);
    try evaluate(engine, @embedFile("extensions/fixtures/management-http-4954.input.txt") ++
        \\if(managementRows.length!==51)throw Error('complete51 controls');const by=name=>managementRows.find(row=>row.name===name).value;if(!by('identity-no-signal').identity||!by('identity-no-signal').seen.init||by('identity-no-signal').seen.ua!=='explicit-caller')throw Error('literal inputs and caller UA');for(const status of [408,425,429,500,502,503,504]){const result=by('status-'+status);if(result.calls!==2||result.cancel!==1||!result.identity||result.order.join(',')!=='fetch:0,cancel-start,cancel-end,fetch:1')throw Error('awaited discard before immediate retry')}if(by('maximum-2.8').calls!==3||by('maximum--1').calls!==1||by('abort-error-terminal').calls!==1||by('attempt-aborted-boolean').calls!==2||by('attempt-aborted-string').calls!==1||by('overall-permits-abort-retry').calls!==2)throw Error('retry/AbortError distinction');if(by('cancel-error-next-check-outside-try').calls!==1||!by('cancel-error-next-check-outside-try').identity||by('outside-try-parent-getter').sync||by('outside-try-null-options').sync)throw Error('async and try boundaries');if(by('genuine-attempt-timeout').calls!==2||!by('genuine-attempt-timeout').identity||by('genuine-overall-timeout-terminal').calls!==1||!by('genuine-caller-abort-terminal').identity)throw Error('actual signals');for(const ua of managementRawUserAgents)if(!ua.includes('; zig/0.16.0; quickjs-ng/')||ua.includes('; node/')||ua.includes('; bun/'))throw Error('truthful native runtime identity');
    , "native-management-http-controls.mjs");
    c.JS_RunGC(engine.runtime);
}
test "native management HTTP retained helper roots preserve response and rejection identity across GC" {
    const engine = try v.em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    try evaluate(engine,
        \\globalThis.keptManagement=managementHTTPAPI;delete globalThis.managementHTTPAPI;globalThis.fetch=function(){return new Promise(resolve=>globalThis.managementResume=resolve)};globalThis.managementPending=keptManagement.fetchWithRetry({input:1},undefined,{maxRetries:0});
    , "native-management-http-gc-before.mjs");
    c.JS_RunGC(engine.runtime);
    try evaluate(engine,
        \\const response={status:200};managementResume(response);if(await managementPending!==response)throw Error('pending identity');const failure={marker:'original',toString(){throw Error('must not coerce')}};globalThis.fetch=()=>Promise.reject(failure);if(await keptManagement.fetchWithRetry('input',undefined,{maxRetries:0}).then(()=>null,error=>error)!==failure)throw Error('raw rejection');if(!keptManagement.getPiUserAgent('retained').startsWith('pi/retained ('))throw Error('retained UA');delete globalThis.managementResume;delete globalThis.managementPending;delete globalThis.keptManagement;delete globalThis.fetch;
    , "native-management-http-gc-after.mjs");
    c.JS_RunGC(engine.runtime);
}
test "native management HTTP every host allocation preserves native OOM and releases pending retries" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try v.em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            install(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\let calls=0;globalThis.fetch=()=>++calls===1?{status:503,body:{async cancel(){await Promise.resolve()}}}:{status:200};const response=await managementHTTPAPI.fetchWithRetry({input:true},{headers:{'User-Agent':'explicit'}},{maxRetries:1,attemptTimeoutMs:100});if(response.status!==200||calls!==2||!managementHTTPAPI.getPiUserAgent('oom').startsWith('pi/oom ('))throw Error('owned retry probe');delete globalThis.fetch;
            , "native-management-http-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
