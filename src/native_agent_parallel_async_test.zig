//! Prepared actual-VM controls for the Source parallel per-tool async arrow.
const std = @import("std");
const em = @import("extensions/engine.zig");
const p = @import("extensions/native_agent_af_values.zig");
const completion = @import("extensions/native_agent_af_completion.zig");
const functions = @import("extensions/native_node_function.zig");
const parallel = @import("extensions/native_agent_parallel_async.zig");
const c = em.c;
fn make(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: p.Scope = .{ .engine = engine };
    return completion.finishValue(&s, makeValue(&s, args[0]));
}
fn makeValue(s: *p.Scope, input: c.JSValue) !c.JSValue {
    return parallel.create(s.engine, try p.get(s, input, "context"), try p.get(s, input, "assistant"), try p.get(s, input, "prepared"), try p.get(s, input, "config"), try p.get(s, input, "signal"), try p.get(s, input, "emit"), try p.get(s, input, "toolCall"));
}
fn install(engine: *em.Engine) !void {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    const g = try s.own(c.JS_GetGlobalObject(engine.context));
    try s.put(g, "makeParallel", try s.own(try functions.createArrow(engine, "makeParallel", 1, make, &.{})));
    const probe = try s.own(try parallel.create(engine, c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined()));
    try std.testing.expect(c.JS_IsAsyncFunction(probe));
}
fn run(engine: *em.Engine, source: []const u8, name: [:0]const u8) !void { const value = try engine.evalModule(source, name); engine.freeValue(value); }
test "native Agent parallel AF real abort branch captures signal and awaits end before exact finalized return" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try install(engine);
    try run(engine,
        \\const call={id:'c',name:'tool',arguments:{}},signal={aborted:false},events=[];let release;
        \\const entry=makeParallel({context:{},assistant:{},prepared:{},config:{},signal,toolCall:call,emit(event){events.push(event);return new Promise(r=>{release=r})}});
        \\if(entry.name!==''||entry.length!==0||Object.hasOwn(entry,'prototype'))throw Error('metadata');let ctor=false;try{new entry()}catch(e){ctor=e instanceof TypeError}if(!ctor)throw Error('constructor');
        \\signal.aborted=true;let settled=false;const outer=entry.call({ignored:true}).then(r=>{settled=true;return r});if(events.length!==1||events[0].type!=='tool_execution_end'||settled)throw Error('abort end boundary');await Promise.resolve();if(settled)throw Error('end not awaited');release();const value=await outer;if(value.toolCall!==call||value.isError!==true||value.result.content[0].text!=='Operation aborted')throw Error('abort result');
    , "agent-parallel-af-abort.mjs");
}
test "native Agent parallel AF real execute finalize and end boundaries retain update and method receivers" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try install(engine);
    try run(engine,
        \\let tick=0;globalThis.performance={now(){return tick++}};const call={id:'c',name:'tool',arguments:{v:1}},signal={aborted:false},context={},assistant={},events=[];let executeDone,updateDone,endDone,hook=0;
        \\const tool={execute(id,args,seenSignal,onUpdate){if(this!==tool||id!=='c'||args.v!==1||seenSignal!==signal)throw Error('execute receiver');onUpdate({content:[]});return new Promise(r=>{executeDone=r})}};
        \\const config={afterToolCall(request,seenSignal){if(this!==config||request.context!==context||request.assistantMessage!==assistant||seenSignal!==signal)throw Error('hook receiver');hook++;return {structuredContent:{edited:true}}}};
        \\const prepared={toolCall:call,tool,args:call.arguments};const entry=makeParallel({context,assistant,prepared,config,signal,toolCall:call,emit(event){events.push(event);return new Promise(r=>{if(event.type==='tool_execution_update')updateDone=r;else if(event.type==='tool_execution_end')endDone=r;else throw Error('event')})}});
        \\let settled=false;const result=entry().then(r=>{settled=true;return r});if(!executeDone||!updateDone||events[0].toolCallId!=='c')throw Error('execution start');executeDone({content:[]});for(let i=0;i<4;i++)await Promise.resolve();if(hook!==0||settled)throw Error('updates not awaited');updateDone();for(let i=0;i<128&&!endDone;i++)await Promise.resolve();if(hook!==1||!endDone||settled)throw Error('finalize/end boundary');endDone();const outcome=await result;if(outcome.toolCall!==call||outcome.result.structuredContent.edited!==true||outcome.isError!==false||events.length!==2)throw Error('final outcome');
    , "agent-parallel-af-execute.mjs");
}
test "native Agent parallel AF ordinary sink failure rejects exact Source reason" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try install(engine);
    try run(engine,
        \\const reason={},call={id:'c',name:'tool'};const entry=makeParallel({context:{},assistant:{},prepared:{},config:{},signal:{aborted:true},toolCall:call,emit(){throw reason}});let outer;try{outer=entry()}catch(e){throw Error('sync throw')};let same=false;try{await outer}catch(e){same=e===reason}if(!same)throw Error('sink reason identity');
    , "agent-parallel-af-rejection.mjs");
}
test "native Agent parallel AF marked private Await rejection stays DATA" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try install(engine);
    try std.testing.expectError(error.JavaScriptException, engine.checked(engine.throwNativeOutOfMemory()));
    const reason = engine.captured_exception orelse return error.MissingReason; c.JS_SetUncatchableError(engine.context, reason);
    const generation = c.pi_js_native_allocation_error_generation(reason);
    var s: p.Scope = .{ .engine = engine }; defer s.deinit(); try s.put(try s.own(c.JS_GetGlobalObject(engine.context)), "reason", reason);
    try run(engine,
        \\const call={id:'c',name:'tool'};const entry=makeParallel({context:{},assistant:{},prepared:{},config:{},signal:{aborted:true},toolCall:call,emit(){return Promise.reject(reason)}});let same=false;try{await entry()}catch(e){same=e===reason}if(!same)throw Error('Await DATA identity');
    , "agent-parallel-af-data.mjs");
    try std.testing.expect(c.JS_IsUncatchableError(reason)); try std.testing.expectEqual(generation, c.pi_js_native_allocation_error_generation(reason));
}
