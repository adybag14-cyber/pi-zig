//! Prepared controls for actual exported loop AF boundaries and synchronous
//! for-of close semantics. Original Source loop fixtures are unchanged.
const std = @import("std");
const em = @import("extensions/engine.zig");
const p = @import("extensions/native_agent_af_values.zig");
const functions = @import("extensions/native_node_function.zig");
const loops = @import("extensions/native_agent_loop.zig");
const c = em.c;
fn install(engine: *em.Engine) !void {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    const global = try s.own(c.JS_GetGlobalObject(engine.context));
    const start = try s.own(try loops.loopFunction(engine, false));
    const continuation = try s.own(try loops.loopFunction(engine, true));
    try std.testing.expect(c.JS_IsAsyncFunction(start) and c.JS_IsAsyncFunction(continuation));
    try s.put(global, "runAgentLoop", start); try s.put(global, "runAgentLoopContinue", continuation);
}
fn run(engine: *em.Engine, source: []const u8, name: [:0]const u8) !void { const value = try engine.evalModule(source, name); engine.freeValue(value); }
test "native Agent loop AF real metadata and continuation validation rejects before events" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try install(engine);
    try run(engine,
        \\if(runAgentLoop.name!=='runAgentLoop'||runAgentLoop.length!==6||runAgentLoopContinue.name!=='runAgentLoopContinue'||runAgentLoopContinue.length!==5||Object.hasOwn(runAgentLoop,'prototype'))throw Error('metadata');let constructor=false;try{new runAgentLoop()}catch(e){constructor=e instanceof TypeError}if(!constructor)throw Error('constructor');
        \\let events=0,outer;try{outer=runAgentLoopContinue({messages:[]},{},()=>events++,undefined,()=>{})}catch(e){throw Error('validation escaped synchronously')};let rejected=false;try{await outer}catch(e){rejected=e.message==='Cannot continue: no messages in context'}if(!rejected||events!==0)throw Error('validation branch');
        \\const reason={};let same=false;try{await runAgentLoopContinue({get messages(){throw reason}},{},()=>events++,undefined,()=>{})}catch(e){same=e===reason}if(!same||events!==0)throw Error('getter reason');
    , "agent-loop-af-metadata.mjs");
}
test "native Agent loop AF real initial emits gate iteration and final Await runLoop" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try install(engine);
    try run(engine,
        \\const events=[],reason={},context={messages:[],tools:[]};let first,second,steering=0;
        \\const config={getSteeringMessages(){if(this!==config)throw Error('receiver');steering++;throw reason}};
        \\function emit(event){if(this!==undefined)throw Error('emit receiver');events.push(event.type);return new Promise(r=>{if(event.type==='agent_start')first=r;else if(event.type==='turn_start')second=r;else throw Error('unexpected event')})}
        \\const outer=runAgentLoop([],context,config,emit,undefined,()=>{});if(events.join(',')!=='agent_start'||steering!==0)throw Error('first gate');first();for(let i=0;i<128&&!second;i++)await Promise.resolve();if(events.join(',')!=='agent_start,turn_start'||steering!==0||!second)throw Error('second gate');second();let same=false;try{await outer}catch(e){same=e===reason}if(!same||steering!==1||events.length!==2)throw Error('runLoop Await rejection');
    , "agent-loop-af-gates.mjs");
}
test "native Agent loop AF synchronous IteratorClose preserves rejected body reason and never awaits return" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try install(engine);
    try run(engine,
        \\const original=Array.prototype[Symbol.iterator],reason={},cleanup={},message={role:'user'},events=[];let reads=0,closed=0,thenReads=0;
        \\const iterator={get next(){reads++;return function(){return{done:false,value:message}}},return(){closed++;return{get then(){thenReads++;throw cleanup}}}};
        \\function emit(event){events.push(event.type);if(event.type==='turn_start')Array.prototype[Symbol.iterator]=function(){return iterator};if(event.type==='message_start'){Array.prototype[Symbol.iterator]=original;return Promise.reject(reason)}}
        \\let same=false;try{await runAgentLoop([],{messages:[],tools:[]},{},emit,undefined,()=>{})}catch(e){same=e===reason}finally{Array.prototype[Symbol.iterator]=original}if(!same||reads!==1||closed!==1||thenReads!==0||events.join(',')!=='agent_start,turn_start,message_start')throw Error('for-of close semantics');
    , "agent-loop-af-close.mjs");
}
test "native Agent loop AF ordinary IteratorClose getter error cannot replace rejected body DATA" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try install(engine);
    try run(engine,
        \\const original=Array.prototype[Symbol.iterator],reason={},cleanup={};let closed=0;
        \\const iterator={next(){return{done:false,value:{role:'user'}}},get return(){closed++;throw cleanup}};
        \\function emit(event){if(event.type==='turn_start')Array.prototype[Symbol.iterator]=function(){return iterator};if(event.type==='message_start'){Array.prototype[Symbol.iterator]=original;return Promise.reject(reason)}}
        \\let same=false;try{await runAgentLoop([],{messages:[],tools:[]},{},emit,undefined,()=>{})}catch(e){same=e===reason}finally{Array.prototype[Symbol.iterator]=original}if(!same||closed!==1)throw Error('original throw lost');
    , "agent-loop-af-close-getter.mjs");
}
test "native Agent loop AF abrupt iterator value precedes body and does not close" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try install(engine);
    try run(engine,
        \\const original=Array.prototype[Symbol.iterator],reason={};let closed=0,starts=0;
        \\const iterator={next(){return{done:false,get value(){Array.prototype[Symbol.iterator]=original;throw reason}}},return(){closed++;return{}}};
        \\function emit(event){if(event.type==='turn_start')Array.prototype[Symbol.iterator]=function(){return iterator};if(event.type==='message_start')starts++}
        \\let same=false;try{await runAgentLoop([],{messages:[],tools:[]},{},emit,undefined,()=>{})}catch(e){same=e===reason}finally{Array.prototype[Symbol.iterator]=original}if(!same||closed!==0||starts!==0)throw Error('IteratorValue boundary');
    , "agent-loop-af-step.mjs");
}
test "native Agent loop AF first rejected private input remains DATA with no iterator close" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try install(engine);
    try std.testing.expectError(error.JavaScriptException, engine.checked(engine.throwNativeOutOfMemory()));
    const reason = engine.captured_exception orelse return error.MissingReason; c.JS_SetUncatchableError(engine.context, reason);
    const generation = c.pi_js_native_allocation_error_generation(reason);
    var s: p.Scope = .{ .engine = engine }; defer s.deinit(); try s.put(try s.own(c.JS_GetGlobalObject(engine.context)), "reason", reason);
    try run(engine,
        \\let calls=0,same=false;try{await runAgentLoop([],{messages:[],tools:[]},{},()=>{calls++;return Promise.reject(reason)},undefined,()=>{})}catch(e){same=e===reason}if(!same||calls!==1)throw Error('rejected DATA');
    , "agent-loop-af-data.mjs");
    try std.testing.expect(c.JS_IsUncatchableError(reason)); try std.testing.expectEqual(generation, c.pi_js_native_allocation_error_generation(reason));
}
fn hostOOM(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return error.OutOfMemory; }
test "native Agent loop AF actual IteratorClose native fatal precedes ordinary rejected DATA" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try install(engine);
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    const global = try s.own(c.JS_GetGlobalObject(engine.context));
    try s.put(global, "closeNativeFailure", try s.own(try functions.createArrow(engine, "closeNativeFailure", 0, hostOOM, &.{})));
    try std.testing.expectError(error.JavaScriptException, engine.evalModule(
        \\const original=Array.prototype[Symbol.iterator],reason={};globalThis.caughtLoopFatal=false;
        \\const iterator={next(){return{done:false,value:{role:'user'}}},return:closeNativeFailure};
        \\function emit(event){if(event.type==='turn_start')Array.prototype[Symbol.iterator]=function(){return iterator};if(event.type==='message_start'){Array.prototype[Symbol.iterator]=original;return Promise.reject(reason)}}
        \\try{await runAgentLoop([],{messages:[],tools:[]},{},emit,undefined,()=>{})}catch(e){globalThis.caughtLoopFatal=true}finally{Array.prototype[Symbol.iterator]=original}
    , "agent-loop-af-close-native.mjs"));
    const reason = engine.captured_exception orelse return error.MissingReason;
    try std.testing.expect(c.JS_IsUncatchableError(reason)); try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    const caught = try s.get(global, "caughtLoopFatal"); try std.testing.expect(!s.truthy(caught));
}

fn checkpointGC(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(c.JS_GetRuntime(context));
    return c.pi_js_undefined();
}
test "native Agent loop AF completed iterator and step roots retire before actual configuration call" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try install(engine);
    try engine.bindFunction("CheckpointLoopGC", checkpointGC, 0);
    const setup = try engine.evalModule(
        \\globalThis.savedLoopArrayIterator=Array.prototype[Symbol.iterator];
        \\globalThis.loopIteratorPool={next(){globalThis.loopIteratorPool=null;Array.prototype[Symbol.iterator]=savedLoopArrayIterator;return{done:true}}};
        \\globalThis.loopIteratorWeak=new WeakRef(loopIteratorPool);globalThis.loopNextWeak=new WeakRef(loopIteratorPool.next);export const ready=true;
    , "agent-loop-af-retirement-setup.mjs"); engine.freeValue(setup);
    // A completed HOST job checkpoint, not a checkpoint inserted between the
    // actual AF microtasks. Neither WeakRef is dereferenced before the probe.
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try std.testing.expect(!@import("extensions/native_async_scope.zig").isActive(engine));
    engine.finishJob();
    try run(engine,
        \\const reason={};let probes=0;const config={getSteeringMessages(){CheckpointLoopGC();if(loopIteratorWeak.deref()!==undefined||loopNextWeak.deref()!==undefined)throw Error('completed iterator retained across configuration call');probes++;throw reason}};
        \\function emit(event){if(event.type==='turn_start')Array.prototype[Symbol.iterator]=function(){return loopIteratorPool}}
        \\let same=false;try{await runAgentLoop([],{messages:[],tools:[]},config,emit,undefined,()=>{})}catch(e){if(e!==reason)throw e;same=true}finally{Array.prototype[Symbol.iterator]=savedLoopArrayIterator}if(!same||probes!==1)throw Error('actual configuration retirement checkpoint');
    , "agent-loop-af-retirement-run.mjs");
}

test "native Agent loop AF real step and previous message retire before later Source callbacks" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try install(engine);
    try engine.bindFunction("CheckpointLoopGC", checkpointGC, 0);
    const setup = try engine.evalModule(
        \\globalThis.savedLoopArrayIterator=Array.prototype[Symbol.iterator];globalThis.loopNextCalls=0;
        \\globalThis.loopValuePool={id:'temporary'};globalThis.loopStepPool={done:false,value:loopValuePool};globalThis.loopValueWeak=new WeakRef(loopValuePool);globalThis.loopStepWeak=new WeakRef(loopStepPool);
        \\globalThis.loopIteratorPool={next(){if(++loopNextCalls===1){const value=loopStepPool;globalThis.loopStepPool=null;globalThis.loopValuePool=null;return value}CheckpointLoopGC();if(loopStepWeak.deref()!==undefined||loopValueWeak.deref()!==undefined)throw Error('previous step/message retained into next');globalThis.loopIteratorPool=null;Array.prototype[Symbol.iterator]=savedLoopArrayIterator;return{done:true}}};export const ready=true;
    , "agent-loop-af-value-retirement-setup.mjs"); engine.freeValue(setup);
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime)); try std.testing.expect(!@import("extensions/native_async_scope.zig").isActive(engine)); engine.finishJob();
    try run(engine,
        \\const reason={},events=[];let probes=0;const config={getSteeringMessages(){probes++;throw reason}};
        \\function emit(event){events.push(event.type);if(event.type==='turn_start')Array.prototype[Symbol.iterator]=function(){return loopIteratorPool};if(event.type==='message_start'){CheckpointLoopGC();if(loopStepWeak.deref()!==undefined||event.message.id!=='temporary')throw Error('step retained into Source body')}}
        \\let same=false;try{await runAgentLoop([],{messages:[],tools:[]},config,emit,undefined,()=>{})}catch(e){if(e!==reason)throw e;same=true}finally{Array.prototype[Symbol.iterator]=savedLoopArrayIterator}if(!same||probes!==1||loopNextCalls!==2||events.join(',')!=='agent_start,turn_start,message_start,message_end')throw Error('real Source retirement boundaries');
    , "agent-loop-af-value-retirement-run.mjs");
}

test "native Agent loop AF iterator method retires before actual next getter" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit(); try install(engine);
    try engine.bindFunction("CheckpointLoopGC", checkpointGC, 0);
    const setup = try engine.evalModule(
        \\globalThis.savedLoopArrayIterator=Array.prototype[Symbol.iterator];globalThis.loopMethodChecks=0;
        \\globalThis.loopIteratorPool={get next(){CheckpointLoopGC();if(loopMethodWeak.deref()!==undefined)throw Error('iterator method retained into next getter');loopMethodChecks++;return function(){globalThis.loopIteratorPool=null;return{done:true}}}};
        \\globalThis.loopMethodPool=function(){return loopIteratorPool};globalThis.loopMethodWeak=new WeakRef(loopMethodPool);export const ready=true;
    , "agent-loop-af-method-retirement-setup.mjs"); engine.freeValue(setup);
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime)); try std.testing.expect(!@import("extensions/native_async_scope.zig").isActive(engine)); engine.finishJob();
    try run(engine,
        \\const reason={},config={getSteeringMessages(){throw reason}};function emit(event){if(event.type==='turn_start')Object.defineProperty(Array.prototype,Symbol.iterator,{configurable:true,get(){const value=loopMethodPool;globalThis.loopMethodPool=null;Object.defineProperty(Array.prototype,Symbol.iterator,{value:savedLoopArrayIterator,configurable:true,writable:true});return value}})}
        \\let same=false;try{await runAgentLoop([],{messages:[],tools:[]},config,emit,undefined,()=>{})}catch(e){if(e!==reason)throw e;same=true}finally{Object.defineProperty(Array.prototype,Symbol.iterator,{value:savedLoopArrayIterator,configurable:true,writable:true})}if(!same||loopMethodChecks!==1)throw Error('real iterator method boundary');
    , "agent-loop-af-method-retirement-run.mjs");
}
