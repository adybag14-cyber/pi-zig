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
    try @import("extensions/native_sdk_session_prompt.zig").install(engine, prototype);
    try @import("extensions/native_sdk_session_queue.zig").install(engine, prototype);
    const source = @embedFile("extensions/fixtures/sdk-session-prompt-e622.json");
    const fixture = try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-session-prompt-e622.json"));
    defer engine.freeValue(fixture);
    try sdk.put(engine, global, "sessionPromptSource", c.JS_DupValue(engine.context, fixture));
    const adapter = try engine.evalModule(
        \\globalThis.createPromptCase=async()=>createNativeConstructorPhase();
    , "native-sdk-session-prompt-adapter.mjs");
    engine.freeValue(adapter);
}
test "native SDK session prompt preflight and queues match27 original factory command input streaming auth and deferred cases" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-session-prompt-e622.input.txt") ++
        "\nif(sessionPromptRows.length!==27||sessionPromptSource.rows.length!==27)throw Error('27 original factory cases required');for(let i=0;i<27;i++)if(JSON.stringify(sessionPromptRows[i])!==JSON.stringify(sessionPromptSource.rows[i]))throw Error(JSON.stringify({case:i,actual:sessionPromptRows[i],expected:sessionPromptSource.rows[i]}));", "native-sdk-session-prompt-source.mjs") catch |err| {
        std.debug.print("Session prompt Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session prompt preflight and queues retain deferred prompt options receiver and input promise across collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const prepared = try engine.evalModule(
        \\const state=await createPromptCase(),events=[],options={preflightResult:result=>events.push(result)};state.session._isEmittingAgentSettled=true;await state.session.prompt('retained',options);let release;state.session._isEmittingAgentSettled=false;state.session._extensionRunner={hasHandlers:()=>true,emitInput(text){if(text!=='retained')throw Error('text lost');return new Promise(resolve=>{release=()=>resolve({action:'handled'});});}};const work=state.session._deferredSettledActions[0]();globalThis.promptRetained={state,events,options,work,release};export const prepared=true;
    , "native-sdk-session-prompt-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\promptRetained.release();await promptRetained.work;if(promptRetained.events.length!==1||promptRetained.events[0]!=='handled')throw Error('prompt owner lost');promptRetained.state.dispose();delete globalThis.promptRetained;export const completed=true;
    , "native-sdk-session-prompt-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session prompt preflight and queues all allocation failures release queue input deferred and session graphs" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            var environment: std.process.Environ.Map = .init(gpa);
            defer environment.deinit();
            try setup(engine, &environment);
            const generation = engine.native_allocation_generation;
            const result = engine.evalModule(
                \\const state=await createPromptCase();state.session._isAgentRunActive=true;state.session._extensionRunner={hasHandlers:()=>false,getCommand:()=>undefined};state.session._resourceLoader={getPrompts:()=>({prompts:[]}),getSkills:()=>({skills:[]})};globalThis.promptAllocationPhase='prompt';await state.session.prompt('hello',{expandPromptTemplates:false,streamingBehavior:'steer'});globalThis.promptAllocationPhase='followUp';if(await state.session.followUp('next')!=='queued'||state.session._steeringMessages[0]!=='hello'||state.session._followUpMessages[0]!=='next')throw Error('queue mismatch');globalThis.promptAllocationPhase='defer';state.session._isEmittingAgentSettled=true;await state.session.prompt('deferred');state.session._isEmittingAgentSettled=false;state.session._extensionRunner={hasHandlers:()=>true,emitInput:()=>({action:'handled'})};globalThis.promptAllocationPhase='action';await state.session._deferredSettledActions[0]();globalThis.promptAllocationPhase='dispose';state.dispose();export const proof=true;
            , "native-sdk-session-prompt-allocations.mjs") catch |err| {
                const failure = engine.nativeAllocationError(err, generation);
                if (failure != error.OutOfMemory) {
                    std.debug.print("Prompt allocation failure {s}: {s}\n", .{ @errorName(failure), engine.last_error orelse "no diagnostic" });
                    const global = c.JS_GetGlobalObject(engine.context);
                    defer engine.freeValue(global);
                    const phase = c.JS_GetPropertyStr(engine.context, global, "promptAllocationPhase");
                    defer engine.freeValue(phase);
                    if (engine.toString(phase)) |bytes| {
                        defer engine.gpa.free(bytes);
                        std.debug.print("Prompt allocation phase: {s}\n", .{bytes});
                    } else |_| {}
                }
                return failure;
            };
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
