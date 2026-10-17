//! Private VM operations for the actual c268 Durable Object SQLite adapter.
//! No storage implementation, host SQL alias or JavaScript implementation body.
const std=@import("std");
pub const v=@import("native_ai_provider_values.zig");
pub const c=v.c;
pub const functions=@import("native_mlly_function.zig");
pub const af=@import("native_async_function.zig");
const allocation=@import("native_async_body.zig");
pub fn current(engine:*v.em.Engine,owned:c.JSValue)!c.JSValue{
    if(c.JS_HasException(engine.context)){
        const reason=c.JS_GetException(engine.context);engine.freeValue(owned);
        return engine.checked(c.JS_Throw(engine.context,reason));
    }
    return owned;
}
pub fn pending(engine:*v.em.Engine)!void{if(c.JS_HasException(engine.context))return v.js.capture(engine);}
pub fn get(engine:*v.em.Engine,object:c.JSValue,name:[*:0]const u8)!c.JSValue{return current(engine,try v.js.get(engine,object,name));}
pub fn call(engine:*v.em.Engine,callee:c.JSValue,receiver:c.JSValue,args:[]const c.JSValue)!c.JSValue{return current(engine,try v.js.call(engine,callee,receiver,args));}
pub fn invoke(engine:*v.em.Engine,receiver:c.JSValue,name:[*:0]const u8,args:[]const c.JSValue)!c.JSValue{
    const callee=try get(engine,receiver,name);defer engine.freeValue(callee);return call(engine,callee,receiver,args);
}
pub fn global(engine:*v.em.Engine,name:[*:0]const u8)!c.JSValue{return current(engine,try v.js.global(engine,name));}
pub fn set(engine:*v.em.Engine,object:c.JSValue,name:[*:0]const u8,value:c.JSValue)!void{
    if(c.JS_SetPropertyStr(engine.context,object,name,c.JS_DupValue(engine.context,value))<0)return v.js.capture(engine);try pending(engine);
}
pub fn define(engine:*v.em.Engine,object:c.JSValue,name:[*:0]const u8,value:c.JSValue,flags:c_int)!void{
    if(c.JS_DefinePropertyValueStr(engine.context,object,name,c.JS_DupValue(engine.context,value),flags|c.JS_PROP_THROW)<0)return v.js.capture(engine);try pending(engine);
}
pub fn field(engine:*v.em.Engine,object:c.JSValue,name:[*:0]const u8,value:c.JSValue)!void{return define(engine,object,name,value,c.JS_PROP_C_W_E);}
pub fn new(engine:*v.em.Engine,constructor:c.JSValue,args:[]const c.JSValue)!c.JSValue{return current(engine,try engine.checked(c.JS_CallConstructor(engine.context,constructor,@intCast(args.len),@constCast(args.ptr))));}
pub fn binary(engine:*v.em.Engine,op:c_int,left:c.JSValue,right:c.JSValue)!c.JSValue{return current(engine,try engine.checked(c.JS_PiBinaryOperator(engine.context,op,left,right)));}
pub fn caught(engine:*v.em.Engine,err:anyerror,generation:u64)!c.JSValue{
    if(err==error.OutOfMemory)return err;
    if(c.JS_HasException(engine.context))_ = engine.checked(c.JS_Throw(engine.context,c.JS_GetException(engine.context))) catch {};
    if(err!=error.JavaScriptException)return err;
    const reason=engine.captured_exception orelse return err;
    try allocation.rethrowRecognizedAllocation(engine,reason,functions.trustedGeneration(engine,generation));
    if(c.JS_IsUncatchableError(reason))return err;
    engine.captured_exception=null;return reason;
}
pub fn reject(engine:*v.em.Engine,err:anyerror,generation:u64)!af.Action{
    if(err==error.OutOfMemory){_ = try engine.checked(functions.failure(engine,err,generation));unreachable;}
    return .{.thrown=try caught(engine,err,generation)};
}
pub fn argsArray(engine:*v.em.Engine,args:[]const c.JSValue)!c.JSValue{
    const result=try current(engine,try v.js.array(engine));errdefer engine.freeValue(result);
    for(args,0..)|value,index|if(c.JS_DefinePropertyValueUint32(engine.context,result,@intCast(index),c.JS_DupValue(engine.context,value),c.JS_PROP_C_W_E)<0)return v.js.capture(engine);
    return result;
}
pub fn errorValue(engine:*v.em.Engine,name:[*:0]const u8,text:c.JSValue)!c.JSValue{
    const ctor=try global(engine,name);defer engine.freeValue(ctor);return new(engine,ctor,&.{text});
}
pub fn throw(engine:*v.em.Engine,reason:c.JSValue)anyerror{
    _ = engine.checked(c.JS_Throw(engine.context,c.JS_DupValue(engine.context,reason))) catch|err|return err;unreachable;
}
pub fn textError(engine:*v.em.Engine,name:[*:0]const u8,message:[*:0]const u8)anyerror{
    const constructor=global(engine,name) catch|err|return err;defer engine.freeValue(constructor);
    const text=engine.checked(c.JS_NewString(engine.context,message)) catch|err|return err;defer engine.freeValue(text);
    const reason=new(engine,constructor,&.{text}) catch|err|return err;defer engine.freeValue(reason);return throw(engine,reason);
}
// Class construction has its own charged/traced callback owner, so prototype
// lookup/object allocation occurs within the same exact pending/fatal boundary.
const Class=struct{engine:*v.em.Engine,name:[:0]const u8,callback:*const fn(*v.em.Engine,c.JSValue,[]const c.JSValue,c.JSValue)anyerror!c.JSValue,owner:c.JSValue,reserved:usize};
fn classFree(runtime:?*c.JSRuntime,value:c.JSValue)callconv(.c)void{
    const state:*Class=@ptrCast(@alignCast(c.JS_GetOpaque(value,c.JS_GetClassID(value)) orelse return));const engine=state.engine;const reserved=state.reserved;
    c.JS_FreeValueRT(runtime,state.owner);engine.gpa.destroy(state);c.pi_js_native_memory_release(engine.native_memory_owner,reserved);
}
fn classMark(runtime:?*c.JSRuntime,value:c.JSValue,marker:?*const c.JS_MarkFunc)callconv(.c)void{
    const state:*Class=@ptrCast(@alignCast(c.JS_GetOpaque(value,c.JS_GetClassID(value)) orelse return));c.JS_MarkValue(runtime,state.owner,marker);
}
fn classCall(_: ?*c.JSContext,function:c.JSValue,target:c.JSValue,argc:c_int,argv:[*c]c.JSValue,flags:c_int)callconv(.c)c.JSValue{
    const state:*Class=@ptrCast(@alignCast(c.JS_GetOpaque(function,c.JS_GetClassID(function)).?));const engine=state.engine;
    engine.native_exception_diagnostics_suppressed+=1;defer engine.native_exception_diagnostics_suppressed-=1;const generation=engine.native_allocation_generation;
    pending(engine) catch|err|return functions.failure(engine,err,generation);
    if(flags&c.JS_CALL_FLAG_CONSTRUCTOR==0)return c.JS_ThrowTypeError(engine.context,"Class constructor %s cannot be invoked without 'new'",state.name.ptr);
    const result=state.callback(engine,target,if(argc>0)argv[0..@intCast(argc)]else &.{},state.owner) catch|err|return functions.failure(engine,err,generation);
    return current(engine,result) catch|err|functions.failure(engine,err,generation);
}
pub fn class(engine:*v.em.Engine,name:[:0]const u8,length:c_int,prototype:c.JSValue,base:?c.JSValue,callback:@FieldType(Class,"callback"),owner:c.JSValue)!c.JSValue{
    const reserved=@sizeOf(Class);if(c.pi_js_native_memory_reserve(engine.native_memory_owner,reserved)==0)return error.OutOfMemory;
    var attached=false;errdefer if(!attached)c.pi_js_native_memory_release(engine.native_memory_owner,reserved);
    const state=try engine.gpa.create(Class);errdefer if(!attached)engine.gpa.destroy(state);
    var id:c.JSClassID=0;if(c.JS_NewClassID(engine.runtime,&id)==0)return error.OutOfMemory;
    const definition:c.JSClassDef=.{.class_name="Native Durable Object SQLite class",.call=classCall,.finalizer=classFree,.gc_mark=classMark};if(c.JS_NewClass(engine.runtime,id,&definition)<0)return error.OutOfMemory;
    const function_prototype=if(base)|value|c.JS_DupValue(engine.context,value)else try engine.checked(c.JS_GetFunctionProto(engine.context));defer engine.freeValue(function_prototype);
    const result=try engine.checked(c.JS_NewObjectProtoClass(engine.context,function_prototype,id));errdefer engine.freeValue(result);
    state.*=.{.engine=engine,.name=name,.callback=callback,.owner=c.JS_DupValue(engine.context,owner),.reserved=reserved};_ = c.JS_SetOpaque(result,state);attached=true;_ = c.JS_SetConstructorBit(engine.context,result,true);
    const label=try engine.checked(c.JS_NewString(engine.context,name.ptr));defer engine.freeValue(label);
    try define(engine,result,"name",label,c.JS_PROP_CONFIGURABLE);try define(engine,result,"length",c.JS_NewInt32(engine.context,length),c.JS_PROP_CONFIGURABLE);try define(engine,result,"prototype",prototype,0);
    try define(engine,prototype,"constructor",result,c.JS_PROP_CONFIGURABLE|c.JS_PROP_WRITABLE);return result;
}
// Separate inert C/H prerequisite is prepared under verification. No active C/H
// bytes are edited by this leaf. Composition requires its reviewed real ABI.
extern fn JS_PiGetPropertyReceiver(?*c.JSContext,c.JSValue,c.JSAtom,c.JSValue)c.JSValue;
/// Genuine internal Get with actual accessor/Proxy receiver and owned result.
pub fn superGet(engine:*v.em.Engine,home:c.JSValue,receiver:c.JSValue,name:[*:0]const u8)!c.JSValue{
    engine.native_exception_diagnostics_suppressed+=1;defer engine.native_exception_diagnostics_suppressed-=1;
    const parent=try current(engine,try engine.checked(c.JS_GetPrototype(engine.context,home)));defer engine.freeValue(parent);
    const atom=c.JS_NewAtom(engine.context,name);if(atom==c.JS_ATOM_NULL)return v.js.capture(engine);defer c.JS_FreeAtom(engine.context,atom);
    return current(engine,try engine.checked(JS_PiGetPropertyReceiver(engine.context,parent,atom,receiver)));
}
/// Array-literal/argument spread: actual IteratorRecord, no invented Close on
/// abrupt iterator creation/Step/Value. All yielded arguments remain rooted.
pub fn spread(engine:*v.em.Engine,iterable:c.JSValue)!c.JSValue{
    const iterator=try makeIterator(engine,iterable);defer engine.freeValue(iterator);
    if(!c.JS_IsObject(iterator))return v.js.typeError(engine,"Iterator is not an object");
    const next=try get(engine,iterator,"next");defer engine.freeValue(next);
    const result=try current(engine,try v.js.array(engine));errdefer engine.freeValue(result);var index:u32=0;var steps:usize=0;
    while(true){steps+|=1;try @import("native_jiti_budget.zig").check(engine,steps);const value=(try step(engine,next,iterator)) orelse break;
        if(c.JS_DefinePropertyValueUint32(engine.context,result,index,value,c.JS_PROP_C_W_E)<0)return v.js.capture(engine);try pending(engine);
        index=std.math.add(u32,index,1) catch return error.CloudflareArgumentCountOverflow;
    }
    return result;
}
fn makeIterator(engine:*v.em.Engine,iterable:c.JSValue)!c.JSValue{
    const symbol=try engine.checked(c.JS_GetIteratorSymbol(engine.context));defer engine.freeValue(symbol);
    const method=try current(engine,try v.js.getKey(engine,iterable,symbol));defer engine.freeValue(method);return call(engine,method,iterable,&.{});
}
fn step(engine:*v.em.Engine,next:c.JSValue,iterator:c.JSValue)!?c.JSValue{
    const result=try call(engine,next,iterator,&.{});defer engine.freeValue(result);if(!c.JS_IsObject(result))return v.js.typeError(engine,"Iterator result is not an object");
    const done=try get(engine,result,"done");const finished=c.JS_ToBool(engine.context,done)!=0;engine.freeValue(done);if(finished)return null;return try get(engine,result,"value");
}
pub fn callSpread(engine:*v.em.Engine,callee:c.JSValue,receiver:c.JSValue,first:c.JSValue,iterable:c.JSValue)!c.JSValue{
    const values=try spread(engine,iterable);defer engine.freeValue(values);const length=try get(engine,values,"length");defer engine.freeValue(length);var count:u32=0;if(c.JS_ToUint32(engine.context,&count,length)<0)return v.js.capture(engine);
    if(count>=std.math.maxInt(c_int))return error.CloudflareArgumentCountOverflow;
    const size=try std.math.mul(usize,@as(usize,count)+1,@sizeOf(c.JSValue));if(c.pi_js_native_memory_reserve(engine.native_memory_owner,size)==0)return error.OutOfMemory;defer c.pi_js_native_memory_release(engine.native_memory_owner,size);
    const args=try engine.gpa.alloc(c.JSValue,@as(usize,count)+1);defer engine.gpa.free(args);args[0]=first;var initialized:usize=0;defer for(args[1..][0..initialized])|value|engine.freeValue(value);
    for(args[1..],0..)|*slot,index|{slot.*=try current(engine,try engine.checked(c.JS_GetPropertyUint32(engine.context,values,@intCast(index))));initialized+=1;}
    return call(engine,callee,receiver,args);
}
