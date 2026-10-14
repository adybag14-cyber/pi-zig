const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const js = @import("extensions/native_js_values.zig");
const c = em.c;
// Controlled dependency boundary for orchestration tests. The genuine Source
// driver registers the same caller function through its actual compat registry.
// This does not implement or qualify the native global API-provider registry.
fn defaultCompletion(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const receiver = js.global(engine, "globalThis") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(receiver);
    const function = sdk.get(engine, receiver, "summaryDefaultEntry") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(function);
    return js.call(engine, function, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| sdk.fail(engine, err);
}
fn setup(engine: *em.Engine) !void {
    engine.native_io = std.testing.io;
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/native_bigint_host.zig").install(engine);
    const uuid = try @import("extensions/native_ai_uuid.zig").create(engine);
    defer engine.freeValue(uuid);
    const complete_simple = try engine.checked(c.JS_NewCFunction(engine.context, defaultCompletion, "completeSimple", 3));
    defer engine.freeValue(complete_simple);
    const retry_assistant = try @import("extensions/native_ai_retry_call.zig").create(engine);
    defer engine.freeValue(retry_assistant);
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try sdk.put(engine, exports, "completeSummarization", try @import("extensions/native_sdk_complete_summarization.zig").create(engine, uuid, complete_simple, retry_assistant));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "summaryAPI", c.JS_DupValue(engine.context, exports));
}
test "native complete summarization matches28 original request retry stream await return and dependency observations" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try setup(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/sdk-complete-summary-b45.json");
    try sdk.put(engine, global, "completeSummarySource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-complete-summary-b45.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-complete-summary-b45.input.txt") ++
        "\nif(completeSummaryRows.length!==28||completeSummarySource.rows.length!==28)throw Error('all28 required');for(let i=0;i<28;i++)if(JSON.stringify(completeSummaryRows[i])!==JSON.stringify(completeSummarySource.rows[i]))throw Error(JSON.stringify({case:i,actual:completeSummaryRows[i],expected:completeSummarySource.rows[i]}));", "native-sdk-complete-summary-source.mjs") catch |err| {
        std.debug.print("Complete summary Source: {s}\n", .{engine.last_error orelse "none"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native complete summarization pending producer retains actual request and result receivers across collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try setup(engine);
    const prepared = try engine.evalModule(
        \\globalThis.summaryRetained=summaryAPI.completeSummarization;delete globalThis.summaryAPI;globalThis.summaryExpected={role:'assistant',content:[],stopReason:'stop'};globalThis.summaryStream={result(){if(this!==summaryStream)throw Error('stream receiver');return summaryExpected;}};globalThis.summaryPending=summaryRetained({}, {messages:[]},{sessionId:'kept'},()=>new Promise(resolve=>{globalThis.summaryRelease=resolve;}));export const ready=true;
    , "native-sdk-complete-summary-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\summaryRelease(summaryStream);if(await summaryPending!==summaryExpected)throw Error('pending request identity');delete globalThis.summaryRetained;delete globalThis.summaryExpected;delete globalThis.summaryStream;delete globalThis.summaryPending;delete globalThis.summaryRelease;export const completed=true;
    , "native-sdk-complete-summary-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native complete summarization all host allocations release complete request producer retry and result graphs" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            setup(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const expected={role:'assistant',content:[],stopReason:'stop'},model={},context={messages:[]},options={sessionId:'owned'};let held;const value=await summaryAPI.completeSummarization(model,context,options,(m,c,o)=>{if(m!==model||c!==context||o===options||o.cacheRetention!=='none')throw Error('request graph');held=o;return Promise.resolve({result(){return Promise.resolve(expected);}});});if(value!==expected||held.sessionId!=='owned')throw Error('completion graph');globalThis.summaryDefaultEntry=()=>expected;if(await summaryAPI.completeSummarization(model,context,options)!==expected)throw Error('default dependency');delete globalThis.summaryDefaultEntry;export const proof=true;
            , "native-sdk-complete-summary-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
