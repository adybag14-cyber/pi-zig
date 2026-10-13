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
    try @import("extensions/native_sdk_session_public_values.zig").install(engine, prototype);
    try @import("extensions/native_sdk_session_prompt_handlers.zig").install(engine, prototype);
    const source = @embedFile("extensions/fixtures/sdk-prompt-handlers-e622.json");
    const fixture = try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-prompt-handlers-e622.json"));
    defer engine.freeValue(fixture);
    try sdk.put(engine, global, "promptHandlersSource", c.JS_DupValue(engine.context, fixture));
    const adapter = try engine.evalModule(
        \\globalThis.createPromptHandlersCase=async()=>createNativeConstructorPhase();
        \\globalThis.skillFixturePath='src/extensions/fixtures/sdk-prompt-handlers-skill.md';
    , "native-sdk-prompt-handlers-adapter.mjs");
    engine.freeValue(adapter);
}
test "native SDK session prompt handlers match35 original factory input command skill and descriptor cases" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const observed = engine.evalModule(@embedFile("extensions/fixtures/sdk-prompt-handlers-e622.input.txt") ++
        "\nif(promptHandlerRows.length!==35||promptHandlersSource.rows.length!==35)throw Error('35 original factory cases required');for(let i=0;i<35;i++)if(JSON.stringify(promptHandlerRows[i])!==JSON.stringify(promptHandlersSource.rows[i]))throw Error(JSON.stringify({case:i,actual:promptHandlerRows[i],expected:promptHandlersSource.rows[i]}));", "native-sdk-prompt-handlers-source.mjs") catch |err| {
        std.debug.print("Session prompt handlers Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(observed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session prompt handlers retain pending runner context receiver and command failure across collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const prepared = try engine.evalModule(
        \\const state=await createPromptHandlersCase(),runner=state.session._extensionRunner,reason={tag:'failure'},context={tag:'context'},events=[];let release;state.session._extensionRunner={getCommand:()=>({handler(args,ctx){if(args!=='args'||ctx!==context)throw Error('arguments lost');return new Promise((resolve,reject)=>{release=()=>reject(reason);});}}),createCommandContext:()=>context,emitError(event){events.push(event);}};globalThis.handlerRetained={state,runner,release,events,work:state.session._tryExecuteExtensionCommand('/hello args')};handlerRetained.release=release;export const prepared=true;
    , "native-sdk-prompt-handlers-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\handlerRetained.release();if(await handlerRetained.work!==true||handlerRetained.events.length!==1||handlerRetained.events[0].extensionPath!=='command:hello'||handlerRetained.events[0].error!=='[object Object]')throw Error('command roots lost');handlerRetained.state.session._extensionRunner=handlerRetained.runner;handlerRetained.state.dispose();delete globalThis.handlerRetained;export const completed=true;
    , "native-sdk-prompt-handlers-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session prompt handlers all allocation failures release input command and ordinary session graphs" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            var environment: std.process.Environ.Map = .init(gpa);
            defer environment.deinit();
            try setup(engine, &environment);
            const generation = engine.native_allocation_generation;
            const observed = engine.evalModule(
                \\const state=await createPromptHandlersCase(),events=[];state.session._extensionRunner={hasHandlers:()=>true,emitInput:()=>({action:'transform',text:'new',images:null}),getCommand:()=>({handler(){throw new Error('command failure');}}),createCommandContext:()=>({tag:'context'}),emitError(event){events.push(event);}};const input=await state.session._runInputHandlers('old',['image'],'rpc','steer');if(input.text!=='new'||input.images[0]!=='image')throw Error('input mismatch');if(await state.session._tryExecuteExtensionCommand('/hello args')!==true||events[0].error!=='command failure')throw Error('command mismatch');state.session._resourceLoader={getSkills:()=>({skills:[{name:'demo',filePath:skillFixturePath,baseDir:'/skills/demo'}]})};if(!state.session._expandSkillCommand('/skill:demo args').includes('A real skill body'))throw Error('skill mismatch');state.dispose();export const proof=true;
            , "native-sdk-prompt-handlers-allocations.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(observed);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
