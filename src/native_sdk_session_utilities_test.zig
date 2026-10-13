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
    try @import("extensions/native_sdk_session_utilities.zig").install(engine, prototype);
    const source = @embedFile("extensions/fixtures/sdk-session-utilities-e622.json");
    try sdk.put(engine, global, "sessionUtilitySource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-session-utilities-e622.json")));
    const adapter = try engine.evalModule(
        \\globalThis.createUtilityCase=async()=>{const state=createNativeConstructorPhase();state.session._extensionRunner={};return state;};
    , "native-sdk-session-utilities-adapter.mjs");
    engine.freeValue(adapter);
}
test "native SDK session utilities match34 original factory transcript queries replacement contexts descriptors and thrown identities" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-session-utilities-e622.input.txt") ++
        "\nif(sessionUtilityRows.length!==34||sessionUtilitySource.rows.length!==34)throw Error('34 original cases required');for(let i=0;i<34;i++)if(JSON.stringify(sessionUtilityRows[i])!==JSON.stringify(sessionUtilitySource.rows[i]))throw Error(JSON.stringify({case:i,actual:sessionUtilityRows[i],expected:sessionUtilitySource.rows[i]}));", "native-sdk-session-utilities-source.mjs") catch |err| {
        std.debug.print("Session utilities Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session utilities replacement callbacks retain lexical session across collection and live method mutation" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try setup(engine, &environment);
    const prepared = try engine.evalModule(
        \\const state=await createUtilityCase();state.session._extensionRunner.createCommandContext=()=>({});globalThis.utilityRetained={state,context:state.session.createReplacedSessionContext(),message:{},options:{}};export const prepared=true;
    , "native-sdk-session-utilities-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\const{state,context,message,options}=utilityRetained;const marker={};state.session.sendCustomMessage=function(m,o){if(this!==state.session||m!==message||o!==options)throw Error('lexical owner lost');return marker;};if(context.sendMessage.call({},message,options)!==marker)throw Error('identity lost');state.dispose();delete globalThis.utilityRetained;export const completed=true;
    , "native-sdk-session-utilities-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK session utilities every allocation failure releases callback descriptor iterator and lexical session owner graphs" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            var environment: std.process.Environ.Map = .init(gpa);
            defer environment.deinit();
            try setup(engine, &environment);
            const generation = engine.native_allocation_generation;
            const result = engine.evalModule(
                \\const state=await createUtilityCase();state.session._extensionRunner.createCommandContext=()=>({get field(){return 7;}});const context=state.session.createReplacedSessionContext();state.session.sendCustomMessage=message=>message;const marker={};if(context.sendMessage(marker)!==marker||context.field!==7)throw Error('replacement context');state.agent.state.messages=[{role:'assistant',stopReason:'stop',content:[{type:'text',text:' text '}]}];if(state.session.getLastAssistantText()!=='text')throw Error('assistant text');state.manager.getEntries=()=>[{type:'message',id:'user',message:{role:'user',content:[{type:'text',text:'hello'}]}}];if(state.session.getUserMessagesForForking()[0].text!=='hello')throw Error('fork text');state.dispose();export const proof=true;
            , "native-sdk-session-utilities-allocations.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
