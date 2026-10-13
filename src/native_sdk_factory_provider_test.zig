const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;
test "native SDK factory provider callbacks actual selected inventory" {
    const functions = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, functions.len);
    defer std.testing.allocator.free(names);
    for (functions, names) |function, *name| name.* = function.name;
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(encoded);
    std.debug.print("FACTORY_PROVIDER_TEST_INVENTORY={s}\n", .{encoded});
}
fn create(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    if (argc != 6) return c.JS_ThrowTypeError(context, "six native factory collaborators required");
    return @import("extensions/native_sdk_factory_provider_callbacks.zig").create(engine, args[0], args[1], args[2], args[3], args[4], args[5]) catch |err| sdk.fail(engine, err);
}
fn setup(engine: *em.Engine, environment: *std.process.Environ.Map) !void {
    engine.native_io = std.testing.io;
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/native_process.zig").install(engine, std.testing.io, environment, &.{"native-sdk-provider"});
    try @import("extensions/native_url.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const exports = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    try @import("extensions/native_agent_complete.zig").install(engine, exports);
    try sdk.put(engine, global, "providerSDK", c.JS_DupValue(engine.context, exports));
    try sdk.put(engine, global, "cacheWarmerAPI", try @import("extensions/native_cache_warmer.zig").createBindings(engine));
    try sdk.put(engine, global, "createFactoryProviderCallbacks", try engine.checked(c.JS_NewCFunction(engine.context, create, "createFactoryProviderCallbacks", 6)));
    const adapter = try engine.evalModule(@embedFile("extensions/fixtures/sdk-factory-provider-native-adapter.input.txt"), "native-sdk-provider-adapter.mjs");
    engine.freeValue(adapter);
}
test "native SDK factory provider callbacks match24 genuine latest Source cases over actual native collaborators" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/sdk-factory-provider-e622.json");
    try sdk.put(engine, global, "factoryProviderSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-factory-provider-e622.json")));
    const observed = engine.evalModule(@embedFile("extensions/fixtures/sdk-factory-provider-e622.input.txt") ++
        "\nif(factoryProviderRows.length!==24||factoryProviderSource.rows.length!==24)throw Error('24 original Source cases required');for(let i=0;i<24;i++)if(JSON.stringify(factoryProviderRows[i])!==JSON.stringify(factoryProviderSource.rows[i]))throw Error(JSON.stringify({case:i,actual:factoryProviderRows[i],expected:factoryProviderSource.rows[i]}));", "native-sdk-provider-source.mjs") catch |err| {
        std.debug.print("Factory provider Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(observed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK factory provider callbacks retain pending response rejection and prefix closure through collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const prepared = try engine.evalModule(
        \\const state=await createProviderCallbackCase();state.settings.getProviderRetrySettings=()=>({});state.settings.getHttpIdleTimeoutMs=()=>0;state.settings.getWebSocketConnectTimeoutMs=()=>1;state.settings.getEnableInstallTelemetry=()=>false;const first={role:'user',content:'first'};state.agent.state.messages=[first];let prefix;state.warmer.start=(_,check)=>prefix=check;state.models.streamSimple=()=>({stream:true});await state.callbacks.streamFn(state.model,{}, {sessionId:state.manager.getSessionId()});let reject;state.runnerRef.current={hasHandlers:()=>true,emit:()=>new Promise((_,no)=>reject=no)};const marker={owned:true};const pending=state.callbacks.onResponse({status:200,headers:{}}).then(()=>{throw Error('response should reject')},reason=>{if(reason!==marker)throw Error('rejection identity')});globalThis.providerPending={state,first,prefix,reject,marker,pending};export const prepared=true;
    , "native-sdk-provider-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\const p=providerPending;p.state.agent.state.messages=[p.first,{role:'assistant',content:[]}];if(!p.prefix())throw Error('prefix lost live agent after collection');p.state.agent.state.messages=[{...p.first}];if(p.prefix())throw Error('prefix lost original identity');p.reject(p.marker);await p.pending;p.state.dispose();delete globalThis.providerPending;export const completed=true;
    , "native-sdk-provider-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK factory provider callbacks every allocation failure releases collaborator and asynchronous owner graph" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            var environment: std.process.Environ.Map = .init(gpa);
            defer environment.deinit();
            try setup(engine, &environment);
            const generation = engine.native_allocation_generation;
            const observed = engine.evalModule(
                \\const state=await createProviderCallbackCase();state.settings.getProviderRetrySettings=()=>({});state.settings.getHttpIdleTimeoutMs=()=>0;state.settings.getWebSocketConnectTimeoutMs=()=>1;state.settings.getEnableInstallTelemetry=()=>false;state.models.streamSimple=()=>({stream:true});state.warmer.start=()=>{};const observed=await state.callbacks.streamFn(state.model,{}, {sessionId:state.manager.getSessionId()});state.runnerRef.current={hasHandlers:()=>true,emit:()=>Promise.resolve(1),emitBeforeProviderRequest:value=>value};await state.callbacks.onResponse({status:200,headers:{}});await state.callbacks.onProviderStreamEvent({},state.model);if(await state.callbacks.onPayload(observed)!==observed)throw Error('payload identity');state.dispose();export const proof=true;
            , "native-sdk-provider-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(observed);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
