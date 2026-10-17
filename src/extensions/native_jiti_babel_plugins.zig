//! Actual array-spread argument consumption for the native Babel plugin gate.
//! Source reloads opts.babel.plugins after successful Array.isArray. No object
//! CopyDataProperties, length inference, custom plugin execution or fake Close.
const std=@import("std");
const v=@import("native_ai_provider_values.zig");
const c=v.c;
fn currentValue(engine:*v.em.Engine,owned:c.JSValue)!c.JSValue{
    if(c.JS_HasException(engine.context)){
        const reason=c.JS_GetException(engine.context);
        engine.freeValue(owned);
        return engine.checked(c.JS_Throw(engine.context,reason));
    }
    return owned;
}
fn get(engine:*v.em.Engine,object:c.JSValue,name:[*:0]const u8)!c.JSValue{return currentValue(engine,try v.js.get(engine,object,name));}
fn call(engine:*v.em.Engine,function:c.JSValue,receiver:c.JSValue,args:[]const c.JSValue)!c.JSValue{return currentValue(engine,try v.js.call(engine,function,receiver,args));}
pub fn nonempty(engine:*v.em.Engine,options:c.JSValue)!bool{
    engine.native_exception_diagnostics_suppressed+=1;defer engine.native_exception_diagnostics_suppressed-=1;
    const generation=engine.native_allocation_generation;
    return nonemptyBody(engine,options) catch |err| {
        if(err==error.JavaScriptException)if(engine.captured_exception)|reason|try @import("native_async_body.zig").rethrowRecognizedAllocation(engine,reason,generation);
        return err;
    };
}
fn nonemptyBody(engine:*v.em.Engine,options:c.JSValue)!bool{
    if(c.JS_HasException(engine.context))return v.js.capture(engine);
    if(!try hasBabel(engine,options))return false;
    const yes=try pluginsAreArray(engine,options);
    const admitted=c.JS_ToBool(engine.context,yes)!=0;
    engine.freeValue(yes);
    if(!admitted)return false;
    // Same live second receiver/getter evaluation as ...opts.babel.plugins.
    const iterator=try spreadIterator(engine,options);defer engine.freeValue(iterator);
    return consume(engine,iterator);
}
fn hasBabel(engine:*v.em.Engine,options:c.JSValue)!bool{
    const babel=try get(engine,options,"babel");defer engine.freeValue(babel);
    return c.JS_ToBool(engine.context,babel)!=0;
}
fn readPlugins(engine:*v.em.Engine,options:c.JSValue)!c.JSValue{
    const receiver=try get(engine,options,"babel");defer engine.freeValue(receiver);
    return get(engine,receiver,"plugins");
}
fn pluginsAreArray(engine:*v.em.Engine,options:c.JSValue)!c.JSValue{
    const array=try currentValue(engine,try v.js.global(engine,"Array"));defer engine.freeValue(array);
    const is_array=try get(engine,array,"isArray");defer engine.freeValue(is_array);
    const argument=try readPlugins(engine,options);defer engine.freeValue(argument);
    return call(engine,is_array,array,&.{argument});
}
fn spreadIterator(engine:*v.em.Engine,options:c.JSValue)!c.JSValue{
    const iterable=try readPlugins(engine,options);defer engine.freeValue(iterable);
    const symbol=try currentValue(engine,try engine.checked(c.JS_GetIteratorSymbol(engine.context)));defer engine.freeValue(symbol);
    const method=try currentValue(engine,try v.js.getKey(engine,iterable,symbol));defer engine.freeValue(method);
    return call(engine,method,iterable,&.{});
}
fn nextValue(engine:*v.em.Engine,next:c.JSValue,iterator:c.JSValue)!?c.JSValue{
    const step=try call(engine,next,iterator,&.{});defer engine.freeValue(step);
    if(!c.JS_IsObject(step))return v.js.typeError(engine,"Iterator result is not an object");
    const done=try get(engine,step,"done");
    const finished=c.JS_ToBool(engine.context,done)!=0;
    engine.freeValue(done);
    if(finished)return null;
    return try get(engine,step,"value");
}
fn consume(engine:*v.em.Engine,iterator:c.JSValue)!bool{
    if(!c.JS_IsObject(iterator))return v.js.typeError(engine,"Iterator is not an object");
    const next=try get(engine,iterator,"next");defer engine.freeValue(next);
    // Actual spread keeps every yielded value rooted until argument evaluation
    // finishes. Define own array data properties without a live push/setter.
    const values=try currentValue(engine,try v.js.array(engine));defer engine.freeValue(values);
    var index:usize=0;var steps:usize=0;
    while(true){
        if(c.JS_HasException(engine.context))return v.js.capture(engine);
        steps+|=1;try @import("native_jiti_budget.zig").check(engine,steps);
        const value=(try nextValue(engine,next,iterator)) orelse return index!=0;
        if(index>std.math.maxInt(u32)){engine.freeValue(value);return error.UnsupportedBabelPluginArgumentCount;}
        if(c.JS_DefinePropertyValueUint32(engine.context,values,@intCast(index),value,c.JS_PROP_C_W_E)<0)return v.js.capture(engine);
        if(c.JS_HasException(engine.context))return v.js.capture(engine);
        index+=1;
    }
    // Abrupt iterator creation/Step/Value does not invoke iterator.return.
}
