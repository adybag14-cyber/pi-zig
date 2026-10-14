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
    const dependencies = try sdk.object(engine);
    defer engine.freeValue(dependencies);
    // A real native HTTP/SSE stream function supplies the private lexical
    // import identity. These auth tests never invoke or certify that transport.
    // Complete compat-module/factory import assembly remains a separate gate.
    try @import("extensions/native_sdk_chat_transport.zig").install(engine, dependencies);
    try sdk.put(engine, dependencies, "convertToLlm", try @import("extensions/native_sdk_messages.zig").create(engine));
    try @import("extensions/native_sdk_session_request_auth.zig").install(engine, prototype, dependencies);
    try sdk.put(engine, global, "authDefaultStream", try sdk.get(engine, dependencies, "streamSimple"));
    const source = @embedFile("extensions/fixtures/sdk-session-request-auth-1692.json");
    try sdk.put(engine, global, "sessionAuthSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-session-request-auth-1692.json")));
    const adapter = try engine.evalModule(
        \\globalThis.createAuthCase=async()=>{const state=createNativeConstructorPhase();return{...state,model:state.agent.state.model};};
    , "native-sdk-session-request-auth-adapter.mjs");
    engine.freeValue(adapter);
}
test "native SDK session request auth match49 original factory authentication headers virtual routes and branch selection cases" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-session-request-auth-1692.input.txt") ++
        "\nif(sessionAuthSource.sourceHead!=='1692bba6347a287ab0f3cb554a4430fafffc474b')throw Error('Current upstream contract required');if(sessionAuthRows.length!==49||sessionAuthSource.rows.length!==49)throw Error('49 original cases required');for(let i=0;i<49;i++)if(JSON.stringify(sessionAuthRows[i])!==JSON.stringify(sessionAuthSource.rows[i]))throw Error(JSON.stringify({case:i,actual:sessionAuthRows[i],expected:sessionAuthSource.rows[i]}));", "native-sdk-session-request-auth-source.mjs") catch |err| {
        std.debug.print("Session request auth Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session request auth retains pending request model signal result and lexical imports across collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const prepared = try engine.evalModule(
        \\const state=await createAuthCase(),signal={},result={auth:{apiKey:'key',headers:{keep:'a',drop:null}}};let release;state.session._modelRuntime={getAuth(model,options){if(model!==state.model||options.signal!==signal)throw Error('input identity');return new Promise(resolve=>{release=()=>resolve(result);});}};const work=state.session._getRequiredRequestAuth(state.model,signal);globalThis.authRetained={state,signal,result,release,work};export const prepared=true;
    , "native-sdk-session-request-auth-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\authRetained.release();const result=await authRetained.work;if(result.model!==authRetained.state.model||result.apiKey!=='key'||result.headers.keep!=='a'||'drop'in result.headers)throw Error('auth owner lost');authRetained.state.dispose();delete globalThis.authRetained;export const completed=true;
    , "native-sdk-session-request-auth-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session request auth every allocation failure releases required optional routing and branch graphs" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            var environment: std.process.Environ.Map = .init(gpa);
            defer environment.deinit();
            try setup(engine, &environment);
            const generation = engine.native_allocation_generation;
            const result = engine.evalModule(
                \\const state=await createAuthCase(),physical=state.model,virtual={...physical,api:'pi-virtual',id:'router'},signal={aborted:false};state.session._modelRuntime={getAuth:async()=>({auth:{apiKey:'key',headers:{keep:'a',drop:null},baseUrl:'https://override.invalid'},env:{A:'1'}}),resolveModel:async()=>({model:physical,thinkingLevel:'high'}),getModel:()=>undefined};const required=await state.session._getRequiredRequestAuth(physical,signal);if(required.apiKey!=='key'||required.headers.keep!=='a'||'drop'in required.headers)throw Error('required auth');const summary=await state.session._getSummarizationRequestAuth(virtual,signal);if(summary.thinkingLevel!=='high'||summary.model.baseUrl!=='https://override.invalid')throw Error('summary auth');state.agent.state.model=virtual;state.manager.getBranch=()=>[{type:'model_change',provider:'p',modelId:'old'}];let appended=false;state.manager.appendModelChange=(provider,id)=>{appended=provider===physical.provider&&id==='router';};state.session._recordSelection();if(!appended)throw Error('selection record');state.dispose();export const proof=true;
            , "native-sdk-session-request-auth-allocations.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
