//! Prepared raw ABI controls; not installed or compiled. A thin package root
//! must import this file with the real adapter helper and proposed C shim.
const std=@import("std");
const v=@import("extensions/native_ai_provider_values.zig");
const c=v.c;
extern fn JS_PiGetPropertyReceiver(?*c.JSContext,c.JSValue,c.JSAtom,c.JSValue)c.JSValue;
fn get(engine:*v.em.Engine,base:c.JSValue,receiver:c.JSValue)!c.JSValue{
    engine.native_exception_diagnostics_suppressed+=1;defer engine.native_exception_diagnostics_suppressed-=1;
    const atom=c.JS_NewAtom(engine.context,"value");if(atom==c.JS_ATOM_NULL)return v.js.capture(engine);defer c.JS_FreeAtom(engine.context,atom);
    const result=JS_PiGetPropertyReceiver(engine.context,base,atom,receiver);
    if(c.JS_HasException(engine.context)){const reason=c.JS_GetException(engine.context);engine.freeValue(result);return engine.checked(c.JS_Throw(engine.context,reason));}
    return engine.checked(result);
}
fn setup(engine:*v.em.Engine,source:[]const u8)!void{const result=try engine.eval(source,"receiver-get-control.js",c.JS_EVAL_TYPE_GLOBAL);engine.freeValue(result);}
test "receiver Get ordinary accessor uses actual receiver and live base"{
    const engine=try v.em.Engine.init(std.testing.allocator,.{});defer engine.deinit();var s:v.Scope=.{.engine=engine};defer s.deinit();
    try setup(engine,"globalThis.Receiver={marker:true};globalThis.Base={get value(){return this}};globalThis.Other={get value(){return this.marker}};globalThis.Home=Object.create(Base)");
    const receiver=try s.global("Receiver");const home=try s.global("Home");const base=try s.own(try engine.checked(c.JS_GetPrototype(engine.context,home)));const value=try s.own(try get(engine,base,receiver));try std.testing.expect(s.equal(receiver,value));
    const other=try s.global("Other");if(c.JS_SetPrototype(engine.context,home,other)<0)return v.js.capture(engine);const changed=try s.own(try engine.checked(c.JS_GetPrototype(engine.context,home)));const yes=try s.own(try get(engine,changed,receiver));try std.testing.expect(s.truthy(yes));
}
test "receiver Get actual Proxy receives original target key and receiver"{
    const engine=try v.em.Engine.init(std.testing.allocator,.{});defer engine.deinit();var s:v.Scope=.{.engine=engine};defer s.deinit();
    try setup(engine,"globalThis.Receiver={};globalThis.Marker={};globalThis.Calls=0;const target={};globalThis.Base=new Proxy(target,{get(actual,key,receiver){if(actual!==target||key!=='value'||receiver!==Receiver)throw Error('get trap arguments');Calls++;return Marker}})");
    const value=try s.own(try get(engine,try s.global("Base"),try s.global("Receiver")));try std.testing.expect(s.equal(value,try s.global("Marker")));try std.testing.expect(s.equal(try s.global("Calls"),c.JS_NewInt32(engine.context,1)));
}
test "receiver Get ordinary and Proxy raw throw identity avoids diagnostic coercion"{
    for([_]bool{false,true})|proxy|{
        const engine=try v.em.Engine.init(std.testing.allocator,.{});defer engine.deinit();var s:v.Scope=.{.engine=engine};defer s.deinit();
        try setup(engine,if(proxy)"globalThis.Coercions=0;globalThis.Reason={toString(){Coercions++;throw Error('coerced')}};globalThis.Base=new Proxy({},{get(){throw Reason}});globalThis.Receiver={}" else "globalThis.Coercions=0;globalThis.Reason={toString(){Coercions++;throw Error('coerced')}};globalThis.Base={get value(){throw Reason}};globalThis.Receiver={}");
        try std.testing.expectError(error.JavaScriptException,get(engine,try s.global("Base"),try s.global("Receiver")));try std.testing.expect(s.equal(engine.captured_exception.?,try s.global("Reason")));try std.testing.expect(s.equal(try s.global("Coercions"),c.JS_NewInt32(engine.context,0)));try std.testing.expectEqual(@as(usize,0),engine.native_exception_diagnostics_suppressed);
    }
}
fn event(context:?*c.JSContext,_:c.JSValue,_:c_int,_:[*c]c.JSValue)callconv(.c)c.JSValue{
    const engine=v.em.Engine.fromContext(context.?);const global=c.JS_GetGlobalObject(context);defer engine.freeValue(global);const fresh=c.JS_GetPropertyStr(context,global,"Fresh");defer engine.freeValue(fresh);
    const value=c.JS_NewObject(context);if(c.JS_IsException(value))return value;
    if(c.JS_ToBool(context,fresh)!=0)_ = engine.throwNativeOutOfMemory() else _ = c.JS_Throw(context,c.JS_GetPropertyStr(context,global,"Reason"));return value;
}
test "receiver Get normalizes native success plus pending without replacing raw reason"{
    for([_]bool{false,true})|fresh|{
        const engine=try v.em.Engine.init(std.testing.allocator,.{});defer engine.deinit();var s:v.Scope=.{.engine=engine};defer s.deinit();try engine.bindFunction("ReceiverPending",event,0);
        try setup(engine,if(fresh)"globalThis.Fresh=true;globalThis.Reason={};globalThis.Base={get value(){return ReceiverPending()}};globalThis.Receiver={}" else "globalThis.Fresh=false;globalThis.Reason={};globalThis.Base={get value(){return ReceiverPending()}};globalThis.Receiver={}");
        const generation=engine.native_allocation_generation;try std.testing.expectError(error.JavaScriptException,get(engine,try s.global("Base"),try s.global("Receiver")));
        try std.testing.expect(s.equal(engine.captured_exception.?,if(fresh)engine.native_allocation_exception.?else try s.global("Reason")));if(fresh)try std.testing.expectEqual(generation+%1,engine.native_allocation_generation);
    }
}
