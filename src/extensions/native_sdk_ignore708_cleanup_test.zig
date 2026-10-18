//! UNRUN native producer witnesses, separate from original Source observations.
const std=@import("std");
const em=@import("engine.zig");
const supplier=@import("native_sdk_ignore708.zig");
const c=em.c;
const Probe=struct{engine:*em.Engine,count:*usize,reason:c.JSValue,callable:c.JSValue};
fn finalize(runtime:?*c.JSRuntime,value:c.JSValue)callconv(.c)void{
    const state:*Probe=@ptrCast(@alignCast(c.JS_GetOpaque(value,c.JS_GetClassID(value)) orelse return)); state.count.*+=1;
    _=c.JS_Throw(state.engine.context,state.reason); c.JS_FreeValueRT(runtime,state.callable); state.engine.gpa.destroy(state);
}
fn mark(runtime:?*c.JSRuntime,value:c.JSValue,marker:?*const c.JS_MarkFunc)callconv(.c)void{
    const state:*Probe=@ptrCast(@alignCast(c.JS_GetOpaque(value,c.JS_GetClassID(value)) orelse return)); c.JS_MarkValue(runtime,state.reason,marker); c.JS_MarkValue(runtime,state.callable,marker);
}
fn call(context:?*c.JSContext,value:c.JSValue,receiver:c.JSValue,argc:c_int,argv:[*c]c.JSValue,_:c_int)callconv(.c)c.JSValue{
    const state:*Probe=@ptrCast(@alignCast(c.JS_GetOpaque(value,c.JS_GetClassID(value)).?)); return c.JS_Call(context,state.callable,receiver,argc,argv);
}
fn probe(engine:*em.Engine,count:*usize,reason:c.JSValue,callable:c.JSValue)!c.JSValue{
    var class:c.JSClassID=0; _=c.JS_NewClassID(engine.runtime,&class); const definition:c.JSClassDef=.{.class_name="IgnoreCleanupWitness",.finalizer=finalize,.gc_mark=mark,.call=call};
    if(c.JS_NewClass(engine.runtime,class,&definition)<0)return error.OutOfMemory; const state=try engine.gpa.create(Probe); errdefer engine.gpa.destroy(state);
    const value=try engine.checked(c.JS_NewObjectProtoClass(engine.context,c.pi_js_null(),class)); state.*=.{.engine=engine,.count=count,.reason=c.JS_DupValue(engine.context,reason),.callable=c.JS_DupValue(engine.context,callable)}; _=c.JS_SetOpaque(value,state); return value;
}
fn put(engine:*em.Engine,name:[*:0]const u8,value:c.JSValue)!void{const root=c.JS_GetGlobalObject(engine.context);defer engine.freeValue(root);if(c.JS_DefinePropertyValueStr(engine.context,root,name,value,c.JS_PROP_C_W_E)<0)return error.JavaScriptException;}
fn get(engine:*em.Engine,name:[*:0]const u8)!c.JSValue{const root=c.JS_GetGlobalObject(engine.context);defer engine.freeValue(root);return engine.checked(c.JS_GetPropertyStr(engine.context,root,name));}
fn eval(engine:*em.Engine,source:[]const u8)!void{const value=try engine.eval(source,"ignore-owned-control.js",c.JS_EVAL_TYPE_GLOBAL);engine.freeValue(value);}
fn take(context:?*c.JSContext,_:c.JSValue,_:c_int,_:[*c]c.JSValue)callconv(.c)c.JSValue{
    const root=c.JS_GetGlobalObject(context);defer c.JS_FreeValue(context,root);const value=c.JS_GetPropertyStr(context,root,"ignoreCleanupSeed"); const atom=c.JS_NewAtom(context,"ignoreCleanupSeed");defer c.JS_FreeAtom(context,atom);_=c.JS_DeleteProperty(context,root,atom,0);return value;
}
fn pending(context:?*c.JSContext,receiver:c.JSValue,argc:c_int,argv:[*c]c.JSValue)callconv(.c)c.JSValue{const value=take(context,receiver,argc,argv);_=em.Engine.fromContext(context.?).throwNativeOutOfMemory();return value;}
fn reenter(context:?*c.JSContext,_:c.JSValue,_:c_int,_:[*c]c.JSValue)callconv(.c)c.JSValue{const engine=em.Engine.fromContext(context.?);return supplier.createDefault(engine) catch |err| @import("native_sdk.zig").fail(engine,err);}
fn platform(engine:*em.Engine)!void{var env:std.process.Environ.Map=.init(std.testing.allocator);defer env.deinit();try @import("native_process.zig").install(engine,std.testing.io,&env,&.{"ignore708-native-owned-controls"});}
test "private consumed ignore708 first raw reason cleanup OOM and historical DATA" {
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();try platform(engine);try put(engine,"privateIgnore708",try supplier.createDefault(engine));
    try put(engine,"takeIgnoreCleanup",try engine.checked(c.JS_NewCFunction(engine.context,take,"takeIgnoreCleanup",0)));
    try eval(engine,"globalThis.ignoreA={a:1};globalThis.ignoreB={b:1}");const reason=try get(engine,"ignoreB");defer engine.freeValue(reason);var count:usize=0;
    try put(engine,"ignoreCleanupSeed",try probe(engine,&count,reason,c.pi_js_undefined()));
    try eval(engine,"let rawCaught=false;try{privateIgnore708().add([{get [Symbol.for('node-ignore')](){return takeIgnoreCleanup()},get _rules(){throw ignoreA}}])}catch(error){rawCaught=error===ignoreA}if(!rawCaught)throw Error('ordinary A displaced by finalizer B')");
    try std.testing.expectEqual(@as(usize,1),count);
    _=engine.throwNativeOutOfMemory();const history=c.JS_GetException(engine.context);try std.testing.expect(!c.JS_IsUncatchableError(history));try put(engine,"ignoreHistory",history);
    try eval(engine,"let historyCaught=false;try{privateIgnore708().add([{get pattern(){throw ignoreHistory}}])}catch(error){historyCaught=error===ignoreHistory}if(!historyCaught)throw Error('historical private tag promoted')");
    try put(engine,"ignoreCleanupSeed",try probe(engine,&count,reason,c.pi_js_undefined()));
    const array=try get(engine,"Array");defer engine.freeValue(array);const prototype=try engine.checked(c.JS_GetPropertyStr(engine.context,array,"prototype"));defer engine.freeValue(prototype);
    const original=try engine.checked(c.JS_GetPropertyStr(engine.context,prototype,"forEach"));defer engine.freeValue(original);
    if(c.JS_SetPropertyStr(engine.context,prototype,"forEach",try engine.checked(c.JS_NewCFunction(engine.context,pending,"rawIgnoreOOM",1)))<0)return error.JavaScriptException;
    const invoke=try engine.eval("(()=>privateIgnore708().add(['x']))","ignore708-raw-oom.js",c.JS_EVAL_TYPE_GLOBAL);defer engine.freeValue(invoke);
    const result=c.JS_Call(engine.context,invoke,c.pi_js_undefined(),0,null);try std.testing.expect(c.JS_IsException(result));const actual=c.JS_GetException(engine.context);defer engine.freeValue(actual);
    try std.testing.expect(c.JS_IsUncatchableError(actual));try std.testing.expect(c.JS_IsStrictEqual(engine.context,actual,engine.native_allocation_exception.?));try std.testing.expectEqual(@as(usize,2),count);
    if(c.JS_SetPropertyStr(engine.context,prototype,"forEach",c.JS_DupValue(engine.context,original))<0)return error.JavaScriptException;
}
test "private consumed ignore708 initializer guard and cleanup failure cannot publish cache" {
    const engine=try em.Engine.init(std.testing.allocator,.{});defer engine.deinit();try platform(engine);try put(engine,"reenterIgnore708",try engine.checked(c.JS_NewCFunction(engine.context,reenter,"reenterIgnore708",0)));
    try eval(engine,"globalThis.originalIgnoreSymbolFor=Symbol.for;globalThis.ignoreReentry=[];Symbol.for=function(...args){try{reenterIgnore708();ignoreReentry.push(false)}catch(error){ignoreReentry.push(error instanceof TypeError)}return Reflect.apply(originalIgnoreSymbolFor,this,args)}");
    const factory=try supplier.createDefault(engine);defer engine.freeValue(factory);
    try eval(engine,"Symbol.for=originalIgnoreSymbolFor;if(ignoreReentry.length!==1||!ignoreReentry[0])throw Error('initializer reentry guard')");
    const fresh=try em.Engine.init(std.testing.allocator,.{});defer fresh.deinit();try platform(fresh);try eval(fresh,"globalThis.originalIgnoreSymbolFor=Symbol.for;globalThis.ignoreB={b:1}");
    const callable=try get(fresh,"originalIgnoreSymbolFor");defer fresh.freeValue(callable);const reason=try get(fresh,"ignoreB");defer fresh.freeValue(reason);var count:usize=0;
    try put(fresh,"ignoreCleanupSeed",try probe(fresh,&count,reason,callable));try put(fresh,"takeIgnoreCleanup",try fresh.checked(c.JS_NewCFunction(fresh.context,take,"takeIgnoreCleanup",0)));
    try eval(fresh,"Object.defineProperty(Symbol,'for',{configurable:true,get(){return takeIgnoreCleanup()}})");
    if(supplier.createDefault(fresh))|unexpected|{fresh.freeValue(unexpected);return error.ExpectedIgnoreInitializationCleanupFailure;}else|err|try std.testing.expect(err==error.JavaScriptException);
    try std.testing.expectEqual(@as(usize,1),count);try std.testing.expect(c.JS_IsStrictEqual(fresh.context,fresh.captured_exception.?,reason));
    try std.testing.expect(!fresh.native_module_values.contains("\x00sdk-actual-ignore708-default"));try std.testing.expect(!fresh.native_module_values.contains("\x00sdk-actual-ignore708-initializing"));
}
