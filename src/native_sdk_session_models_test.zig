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
    try @import("extensions/native_sdk_session_models.zig").install(engine, prototype);
    try sdk.put(engine, global, "modelValueAPI", try @import("extensions/native_ai_model_values.zig").bindings(engine));
    const source = @embedFile("extensions/fixtures/sdk-session-models-e622.json");
    try sdk.put(engine, global, "sessionModelSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-session-models-e622.json")));
    const adapter = try engine.evalModule(
        \\globalThis.createModelCase=async()=>{const state=createNativeConstructorPhase();state.session._extensionRunner={emit(){return Promise.resolve();}};return{...state,model:state.agent.state.model};};
    , "native-sdk-session-models-adapter.mjs");
    engine.freeValue(adapter);
}
test "native SDK session models match43 original factory selection thinking capabilities scoped cycles persistence and identity cases" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-session-models-e622.input.txt") ++
        "\nif(sessionModelRows.length!==43||sessionModelSource.rows.length!==43)throw Error('43 original factory cases required');for(let i=0;i<43;i++)if(JSON.stringify(sessionModelRows[i])!==JSON.stringify(sessionModelSource.rows[i]))throw Error(JSON.stringify({case:i,actual:sessionModelRows[i],expected:sessionModelSource.rows[i]}));", "native-sdk-session-models-source.mjs") catch |err| {
        std.debug.print("Session models Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session models retain pending auth model previous selection and extension event through collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const prepared = try engine.evalModule(
        \\const state=await createModelCase(),target={...state.model,id:'retained',reasoning:true};let release;const events=[];state.session._modelRuntime={checkAuth:()=>new Promise(resolve=>{release=()=>resolve(true);})};state.session._extensionRunner={emit(event){events.push(event);return Promise.resolve();}};const work=state.session.setModel(target);globalThis.modelRetained={state,target,release,events,work};export const prepared=true;
    , "native-sdk-session-models-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\modelRetained.release();await modelRetained.work;if(modelRetained.state.session.model!==modelRetained.target||!modelRetained.events.some(event=>event.type==='model_select'&&event.model===modelRetained.target))throw Error('model owner lost');await modelRetained.state.settings.flush();modelRetained.state.dispose();delete globalThis.modelRetained;export const completed=true;
    , "native-sdk-session-models-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session models all allocation failures release auth thinking scoped selection and settings graphs" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            var environment: std.process.Environ.Map = .init(gpa);
            defer environment.deinit();
            try setup(engine, &environment);
            const generation = engine.native_allocation_generation;
            const result = engine.evalModule(
                \\const state=await createModelCase(),a={...state.model,id:'a',reasoning:true},b={...state.model,id:'b',reasoning:true,thinkingLevelMap:{xhigh:'xhigh',max:'max'}};state.session._modelRuntime={checkAuth:()=>true,getAvailableSnapshot:()=>[a,b]};state.session.setScopedModels([{model:a,thinkingLevel:'low'},{model:b,thinkingLevel:'high'}]);await state.session.setModel(a,{persist:true});const result=await state.session.cycleModel();if(result.model!==b||!result.isScoped||state.session.thinkingLevel!=='high')throw Error('scoped cycle mismatch');state.session.cycleThinkingLevel({persist:true});await state.settings.flush();state.dispose();export const proof=true;
            , "native-sdk-session-models-allocations.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
