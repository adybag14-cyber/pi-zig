//! Prepared causal host control. Root must pass the actual sealed bundle's
//! validate_function and captured Error constructor; no substitute dependency.
//! No standalone fake require/namespace; no build entry or execution here.
const std=@import("std");
const em=@import("extensions/engine.zig");
const c=em.c;
const State=struct{
    engine:*em.Engine,error_class:c.JSValue,stack_atom:c.JSAtom,holder_class:c.JSClassID,
    replacement_getter:c.JSValue,second:c.JSValue,ordinary_cleanup:c.JSValue,
    fatal_cleanup:bool,finalized:usize=0,slot_live_at_free:bool=false,
    fatal:?c.JSValue=null,raw_fatal:bool=false,
};
var active:?*State=null; // serial owner-only control, never a production root.
fn secondGetter(context:?*c.JSContext,_:c.JSValue,_:c_int,_:[*c]c.JSValue)callconv(.c)c.JSValue{
    const state=active.?;std.debug.assert(state.engine.context==context);
    return c.JS_Throw(context,c.JS_DupValue(context,state.second));
}
fn originalGetter(context:?*c.JSContext,_:c.JSValue,_:c_int,_:[*c]c.JSValue)callconv(.c)c.JSValue{
    const state=active.?;std.debug.assert(state.engine.context==context);
    if(c.JS_DefinePropertyGetSet(context,state.error_class,state.stack_atom,c.JS_DupValue(context,state.replacement_getter),c.pi_js_undefined(),c.JS_PROP_CONFIGURABLE|c.JS_PROP_THROW)<0)return c.JS_Throw(context,c.JS_GetException(context));
    const holder=c.JS_NewObjectClass(context,state.holder_class);if(c.JS_IsException(holder))return holder;
    _=c.JS_SetOpaque(holder,state);
    // Sole holder reference moves into the real current exception. Hide's
    // super throws, then the actual wrapper's stack-limit getter throws B.
    return c.JS_Throw(context,holder);
}
fn finalize(_: ?*c.JSRuntime,value:c.JSValue)callconv(.c)void{
    const state:*State=@ptrCast(@alignCast(c.JS_GetOpaque(value,c.JS_GetClassID(value)).?));
    state.finalized+=1;
    state.slot_live_at_free=c.JS_HasException(state.engine.context) or state.engine.captured_exception!=null;
    if(state.fatal_cleanup){
        _=state.engine.throwNativeOutOfMemory();const reason=c.JS_GetException(state.engine.context);
        state.fatal=c.JS_DupValue(state.engine.context,reason);
        state.raw_fatal=!c.JS_IsUncatchableError(reason) and c.pi_js_native_allocation_error_generation(reason)==state.engine.native_allocation_generation;
        _=c.JS_Throw(state.engine.context,reason);
    }else _=c.JS_Throw(state.engine.context,c.JS_DupValue(state.engine.context,state.ordinary_cleanup));
}
fn restore(engine:*em.Engine,target:c.JSValue,atom:c.JSAtom,original:c.JSPropertyDescriptor)void{
    var flags:c_int=(original.flags&(c.JS_PROP_CONFIGURABLE|c.JS_PROP_ENUMERABLE|c.JS_PROP_WRITABLE))|c.JS_PROP_HAS_CONFIGURABLE|c.JS_PROP_HAS_ENUMERABLE;
    flags|=if(original.flags&c.JS_PROP_GETSET!=0)c.JS_PROP_HAS_GET|c.JS_PROP_HAS_SET else c.JS_PROP_HAS_VALUE|c.JS_PROP_HAS_WRITABLE;
    std.debug.assert(c.JS_DefineProperty(engine.context,target,atom,original.value,original.getter,original.setter,flags|c.JS_PROP_THROW)>=0);
}
pub fn run(engine:*em.Engine,actual_validate_function:c.JSValue,actual_error_class:c.JSValue,fatal_cleanup:bool)!void{
    if(!c.JS_IsFunction(engine.context,actual_validate_function) or !c.JS_IsFunction(engine.context,actual_error_class))return error.RequiredGenuineReadlineControlInputs;
    try std.testing.expect(active==null);
    const atom=c.JS_NewAtom(engine.context,"stackTraceLimit");if(atom==c.JS_ATOM_NULL)return error.OutOfMemory;defer c.JS_FreeAtom(engine.context,atom);
    var original:c.JSPropertyDescriptor=undefined;
    try std.testing.expect(c.JS_GetOwnProperty(engine.context,&original,actual_error_class,atom)==1);
    defer {engine.freeValue(original.value);engine.freeValue(original.getter);engine.freeValue(original.setter);}
    var holder_class:c.JSClassID=0;if(c.JS_NewClassID(engine.runtime,&holder_class)==0)return error.OutOfMemory;
    const definition:c.JSClassDef=.{.class_name="Actual Readline Catch Holder",.finalizer=finalize};
    if(c.JS_NewClass(engine.runtime,holder_class,&definition)<0)return error.OutOfMemory;
    const second=try engine.checked(c.JS_NewError(engine.context));defer engine.freeValue(second);
    const ordinary=try engine.checked(c.JS_NewError(engine.context));defer engine.freeValue(ordinary);
    const replacement_getter=try engine.checked(c.JS_NewCFunction(engine.context,secondGetter,"actualSecondReason",0));defer engine.freeValue(replacement_getter);
    var state:State=.{.engine=engine,.error_class=actual_error_class,.stack_atom=atom,.holder_class=holder_class,.replacement_getter=replacement_getter,.second=second,.ordinary_cleanup=ordinary,.fatal_cleanup=fatal_cleanup};
    defer if(state.fatal)|reason|engine.freeValue(reason);
    active=&state;defer active=null;
    defer restore(engine,actual_error_class,atom,original);
    // Actual data property makes the Hide save/zero path admitted regardless
    // of whether Root's native stack owner installed its ordinary descriptor.
    if(c.JS_DefinePropertyValue(engine.context,actual_error_class,atom,c.JS_NewInt32(engine.context,10),c.JS_PROP_C_W_E|c.JS_PROP_THROW)<0)return error.ControlSetupFailed;
    const callback=try engine.checked(c.JS_NewObject(engine.context));defer engine.freeValue(callback);
    const getter=try engine.checked(c.JS_NewCFunction(engine.context,originalGetter,"actualConstructorReason",0));
    const constructor_atom=c.JS_NewAtom(engine.context,"constructor");if(constructor_atom==c.JS_ATOM_NULL){engine.freeValue(getter);return error.OutOfMemory;}defer c.JS_FreeAtom(engine.context,constructor_atom);
    if(c.JS_DefinePropertyGetSet(engine.context,callback,constructor_atom,getter,c.pi_js_undefined(),c.JS_PROP_CONFIGURABLE|c.JS_PROP_THROW)<0)return error.ControlSetupFailed;
    const name=try engine.checked(c.JS_NewString(engine.context,"callback"));defer engine.freeValue(name);
    var args=[_]c.JSValue{callback,name};
    const result=c.JS_Call(engine.context,actual_validate_function,c.pi_js_undefined(),2,&args);defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result));
    const reason=c.JS_GetException(engine.context);defer engine.freeValue(reason);
    const wanted=if(fatal_cleanup)state.fatal orelse return error.MissingActualCleanupFatal else second;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context,wanted,reason));
    try std.testing.expectEqual(@as(usize,1),state.finalized);
    try std.testing.expect(!state.slot_live_at_free);
    try std.testing.expectEqual(fatal_cleanup,c.JS_IsUncatchableError(reason));
    if(fatal_cleanup)try std.testing.expect(state.raw_fatal);
    try std.testing.expect(engine.captured_exception==null);
    c.JS_ClearUncatchableError(engine.context,reason);
}
