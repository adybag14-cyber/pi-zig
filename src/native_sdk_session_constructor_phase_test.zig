//! Scope: the real constructor initialization and hook-installation phase,
//! observed immediately before original Source _buildRuntime executes.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const construction = @import("extensions/native_sdk_session_construct.zig");
const c = em.c;
fn phase(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return initialize(engine, if (argc > 0) args[0] else c.pi_js_undefined(), roots[0]) catch |err| sdk.fail(engine, err);
}
fn initialize(engine: *em.Engine, config: c.JSValue, target: c.JSValue) !c.JSValue {
    const session = try @import("extensions/native_class.zig").object(engine, target);
    errdefer engine.freeValue(session);
    try construction.initializeDeclarations(engine, session);
    try construction.initializeConfig(engine, session, config);
    try construction.prepareRuntime(engine, session);
    return session;
}
pub fn setup(engine: *em.Engine, environment: *std.process.Environ.Map) !void {
    engine.native_io = std.testing.io;
    try @import("extensions/abort_signal.zig").install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/native_process.zig").install(engine, std.testing.io, environment, &.{"native-sdk-constructor-phase"});
    const namespace = try sdk.object(engine);
    defer engine.freeValue(namespace);
    try sdk.install(engine, namespace);
    try @import("extensions/native_agent_complete.zig").install(engine, namespace);
    const dependencies = try sdk.object(engine);
    defer engine.freeValue(dependencies);
    try @import("extensions/native_sdk_session_estimate.zig").install(engine, dependencies);
    try sdk.put(engine, dependencies, "convertToLlm", try @import("extensions/native_sdk_messages.zig").create(engine));
    try sdk.put(engine, dependencies, "normalizeToolResultImages", try @import("extensions/native_sdk_tool_result_images.zig").create(engine));
    const prototype = try sdk.object(engine);
    defer engine.freeValue(prototype);
    try @import("extensions/native_sdk_session_events.zig").install(engine, prototype);
    try @import("extensions/native_sdk_session_hooks.zig").installWithDependencies(engine, prototype, dependencies);
    const constructor = try construction.constructor(engine, prototype);
    defer engine.freeValue(constructor);
    // This constructor is private and deliberately has no fake runtime builder.
    // The adapter stops at the exact captured Source phase for comparison.
    try sdk.put(engine, namespace, "AgentSession", c.JS_DupValue(engine.context, constructor));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "constructorPhaseSDK", c.JS_DupValue(engine.context, namespace));
    try sdk.put(engine, global, "cacheWarmerAPI", try @import("extensions/native_cache_warmer.zig").createBindings(engine));
    var roots = [_]c.JSValue{constructor};
    try sdk.put(engine, global, "prepareNativeConstructorPhase", try engine.checked(c.JS_NewCFunctionData2(engine.context, phase, "prepareNativeConstructorPhase", 1, 0, roots.len, &roots)));
    const source = @embedFile("extensions/fixtures/sdk-constructor-e622.json");
    try sdk.put(engine, global, "constructorPhaseSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-constructor-e622.json")));
    const adapter = try engine.evalModule(
        \\globalThis.createNativeConstructorPhase=()=>{const{Agent,SettingsManager,SessionManager,DefaultResourceLoader}=constructorPhaseSDK;const model={id:'fixture',name:'fixture',provider:'fixture',api:'openai-completions',baseUrl:'https://fixture.invalid',reasoning:false,input:['text'],cost:{input:0,output:0,cacheRead:0,cacheWrite:0},contextWindow:10000,maxTokens:1000};const agent=new Agent({initialState:{model,thinkingLevel:'off',systemPrompt:'',messages:[],tools:[]},streamFn(){throw Error('phase must not stream')}}),settings=SettingsManager.inMemory({retry:{enabled:false},compaction:{enabled:false},cacheWarming:'off'}),manager=SessionManager.inMemory(),models={streamSimple(){throw Error('phase must not stream')}},warmer=new cacheWarmerAPI.CacheWarmer(models,manager,()=>settings.getCacheWarmingMode()),loader=new DefaultResourceLoader({noExtensions:true});const session=prepareNativeConstructorPhase({agent,sessionManager:manager,settingsManager:settings,cwd:constructorPhaseSource.rows[0].find(field=>field.key==='_cwd').value,resourceLoader:loader,modelRuntime:models,cacheWarmer:warmer,extensionRunnerRef:{},initialActiveToolNames:[],usesDefaultTools:false,allowedToolNames:[]});return{session,agent,settings,manager,models,warmer,loader,dispose(){session._unsubscribeAgent();warmer.cancel()}}};
    , "native-sdk-constructor-phase-adapter.mjs");
    engine.freeValue(adapter);
}
test "native SDK constructor initialization phase matches66 original live field descriptors and actual native hooks" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const observed = engine.evalModule(
        \\const state=createNativeConstructorPhase(),session=state.session;const summarize=v=>v===undefined?{type:'undefined'}:typeof v==='function'?{type:'function',name:v.name,length:v.length,prototype:Object.hasOwn(v,'prototype'),async:Object.getPrototypeOf(v)===Object.getPrototypeOf(async()=>{})}:v instanceof Map?{type:'Map',size:v.size}:v instanceof Set?{type:'Set',values:[...v]}:v instanceof WeakMap?{type:'WeakMap'}:v instanceof WeakSet?{type:'WeakSet'}:Array.isArray(v)?{type:'Array',length:v.length}:v!==null&&typeof v==='object'?{type:'object'}:{type:typeof v,value:v};const actual=Object.entries(Object.getOwnPropertyDescriptors(session)).map(([key,d])=>({key,writable:d.writable,enumerable:d.enumerable,configurable:d.configurable,...summarize(d.value)})),expected=constructorPhaseSource.rows[0];if(actual.length!==66||expected.length!==66||JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({actual,expected}));if(session.agent!==state.agent||session.sessionManager!==state.manager||session.settingsManager!==state.settings||session._resourceLoader!==state.loader||session._modelRuntime!==state.models||session._cacheWarmer!==state.warmer||!(session instanceof constructorPhaseSDK.AgentSession))throw Error('constructor reference identity');state.dispose();export const proof=true;
    , "native-sdk-constructor-phase-source.mjs") catch |err| {
        std.debug.print("Constructor initialization phase Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(observed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK constructor initialization phase all allocation failures release ordinary fields subscriptions and hook graphs" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            var environment: std.process.Environ.Map = .init(gpa);
            defer environment.deinit();
            try setup(engine, &environment);
            const generation = engine.native_allocation_generation;
            const observed = engine.evalModule(
                \\const state=createNativeConstructorPhase();if(Object.keys(state.session).length!==66||typeof state.agent.beforeToolCall!=='function'||typeof state.agent.afterToolCall!=='function')throw Error('constructor hook phase');state.dispose();export const proof=true;
            , "native-sdk-constructor-phase-allocations.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(observed);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
