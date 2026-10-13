const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;
fn setup(engine: *em.Engine, environment: *std.process.Environ.Map) !void {
    try @import("native_sdk_session_constructor_phase_test.zig").setup(engine, environment);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const namespace = try sdk.get(engine, global, "constructorPhaseSDK");
    defer engine.freeValue(namespace);
    const constructor = try sdk.get(engine, namespace, "AgentSession");
    defer engine.freeValue(constructor);
    const prototype = try sdk.get(engine, constructor, "prototype");
    defer engine.freeValue(prototype);
    try @import("extensions/native_sdk_session_loadout.zig").install(engine, prototype);
    try @import("extensions/native_sdk_session_public_values.zig").install(engine, prototype);
    try sdk.put(engine, global, "SessionValuesPrototype", c.JS_DupValue(engine.context, prototype));
    const source = @embedFile("extensions/fixtures/sdk-session-values-e622.json");
    try sdk.put(engine, global, "sessionValuesSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-session-values-e622.json")));
    const adapter = try engine.evalModule(
        \\globalThis.createSessionValuesCase=async()=>{const state=createNativeConstructorPhase();return{...state,session:state.session,runnerRef:state.session._extensionRunnerRef}};
    , "native-sdk-public-values-adapter.mjs");
    engine.freeValue(adapter);
}
test "native SDK session public values match43 genuine Source getter descriptor route tool metadata and live flag cases" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const observed = engine.evalModule(@embedFile("extensions/fixtures/sdk-session-values-e622.input.txt") ++
        "\nif(sessionValuesRows.length!==43||sessionValuesSource.rows.length!==43)throw Error('43 original Source cases required');for(let i=0;i<43;i++)if(JSON.stringify(sessionValuesRows[i])!==JSON.stringify(sessionValuesSource.rows[i]))throw Error(JSON.stringify({case:i,actual:sessionValuesRows[i],expected:sessionValuesSource.rows[i]}));", "native-sdk-public-values-source.mjs") catch |err| {
        std.debug.print("Session public values Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(observed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session public values actual constructor receiver survives collection and reads new ordinary fields" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const prepared = try engine.evalModule(
        \\globalThis.retainedValues=createNativeConstructorPhase();const s=retainedValues.session;s._baseSystemPromptOptions={forceSystemPrompt:'before'};s._steeringMessages=['a'];export const prepared=true;
    , "native-sdk-public-values-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\const s=retainedValues.session;s._baseSystemPromptOptions.forceSystemPrompt='after';s._followUpMessages=['b'];if(s.systemPrompt!=='after'||s.pendingMessageCount!==2||s.modelRuntime!==s._modelRuntime)throw Error('getter snapshots replaced live fields');retainedValues.dispose();delete globalThis.retainedValues;export const completed=true;
    , "native-sdk-public-values-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session public values all allocation failures release live routes tool info and constructor graphs" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            var environment: std.process.Environ.Map = .init(gpa);
            defer environment.deinit();
            try setup(engine, &environment);
            const generation = engine.native_allocation_generation;
            const observed = engine.evalModule(
                \\const state=createNativeConstructorPhase(),s=state.session;s._baseSystemPromptOptions={forceSystemPrompt:'fixture'};s._toolDefinitions=new Map([['tool',{definition:{name:'tool',description:'d',parameters:{},annotations:{readOnlyHint:true}},sourceInfo:{path:'fixture'}}]]);if(s.systemPrompt!=='fixture'||s.getAllTools()[0].exposure!=='direct')throw Error('live public methods');state.agent.state.model={api:'pi-virtual'};state.agent.state.messages=[{role:'assistant',provider:'p',model:'m',stopReason:'stop'}];s._modelRuntime={getPhysicalModel:()=>({id:'m'})};if(s.routedModel.model.id!=='m')throw Error('route');state.dispose();export const proof=true;
            , "native-sdk-public-values-allocations.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(observed);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
