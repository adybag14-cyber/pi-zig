//! Actual-capability observer entry point. No Cloudflare storage implementation
//! or successful SQL callback is manufactured by this verification source.
const std=@import("std");
const v=@import("extensions/native_ai_provider_values.zig");
const c=v.c;
const adapter=@import("extensions/native_chord_sqlite_cloudflare.zig");
const h=@import("extensions/native_chord_sqlite_cloudflare_values.zig");
/// storage must be the real externally provided Durable Object capability,
/// admitted by its owner. label names only that owner's disposable SQL table.
/// Returns every raw observation; no expected/captured Source rows exist yet.
pub fn collectActual(engine:*v.em.Engine,actual_storage:c.JSValue,owned_table_label:c.JSValue)!c.JSValue{
    const exports=try adapter.create(engine);defer engine.freeValue(exports);
    const observer=try engine.evalModule(@embedFile("extensions/fixtures/chord-sqlite-cloudflare-c268-observer.mjs"),"actual-cloudflare-c268-observer.mjs");defer engine.freeValue(observer);
    const function=try v.js.get(engine,observer,"default");defer engine.freeValue(function);
    const promise=try v.js.call(engine,function,c.pi_js_undefined(),&.{exports,actual_storage,owned_table_label});defer engine.freeValue(promise);return engine.awaitValue(promise);
}
/// Preparation only. Genuine original rows must be supplied by a separately
/// authorized real-binding Source capture. Return a complete comparison report
/// so its future owner can persist it BEFORE asserting the matched field.
pub fn compareAccepted(engine:*v.em.Engine,actual_storage:c.JSValue,owned_table_label:c.JSValue,accepted_original_rows:c.JSValue)!c.JSValue{
    var s:v.Scope=.{.engine=engine};defer s.deinit();const actual=try s.own(try collectActual(engine,actual_storage,owned_table_label));const json=try s.global("JSON");
    const actual_text=try s.invoke(json,"stringify",&.{actual});const source_text=try s.invoke(json,"stringify",&.{accepted_original_rows});const result=try s.object();try s.put(result,"actual",actual);try s.put(result,"acceptedOriginal",accepted_original_rows);try s.put(result,"matched",c.JS_NewBool(engine.context,s.equal(actual_text,source_text)));return c.JS_DupValue(engine.context,result);
}
fn afterRealExec(engine:*v.em.Engine,_:c.JSValue,args:[]const c.JSValue,_:[]const c.JSValue)!c.JSValue{
    const value=c.JS_DupValue(engine.context,args[0]);
    if(c.JS_ToBool(engine.context,args[1])!=0)_ = engine.throwNativeOutOfMemory()else _ = c.JS_Throw(engine.context,c.JS_DupValue(engine.context,args[2]));
    return value;
}
/// Additional prepared native policy control. A real SQL exec must complete
/// first; this only injects its native success-with-pending event afterward.
/// The real capability and an owned nonmutating query are mandatory. A fresh
/// realm owner tears down immediately after the trusted fatal profile.
pub fn verifyPendingOnActualStorage(engine:*v.em.Engine,actual_storage:c.JSValue,owned_select_query:c.JSValue,fresh:bool)!void{
    var s:v.Scope=.{.engine=engine};defer s.deinit();const exports=try s.own(try adapter.create(engine));const event=try s.own(try h.functions.createArrow(engine,"",3,afterRealExec,&.{}));
    const observer=try s.own(try engine.evalModule(
        \\export default async function(exports,storage,sql,event,fresh){let calls=0,coercions=0;const reason={toString(){coercions++;throw Error('must not format')}};const binding=storage.sql;
        \\const observedSql=new Proxy(binding,{get(target,key){const method=Reflect.get(target,key,target);if(key!=='exec')return method;return function(...args){const cursor=Reflect.apply(method,target,args);calls++;return event(cursor,fresh,reason)}}});
        \\const observed=new Proxy(storage,{get(target,key){if(key==='sql')return observedSql;return Reflect.get(target,key,target)}});const database=new exports.DurableObjectSqliteDatabase(observed);let caught;try{await database.exec(sql)}catch(error){caught=error}return {same:caught===reason,calls,coercions};}
    ,"cloudflare-c268-real-exec-pending.mjs"));const function=try s.get(observer,"default");const generation=engine.native_allocation_generation;
    const promise=v.js.call(engine,function,c.pi_js_undefined(),&.{exports,actual_storage,owned_select_query,event,c.JS_NewBool(engine.context,fresh)}) catch|err|{
        if(!fresh or err!=error.JavaScriptException)return err;return verifyFreshPending(engine,generation);
    };defer engine.freeValue(promise);
    const result=engine.awaitValue(promise) catch|err|{if(!fresh or err!=error.JavaScriptException)return err;return verifyFreshPending(engine,generation);};defer engine.freeValue(result);
    if(fresh)return error.TrustedCloudflarePendingWasSwallowed;
    try std.testing.expect(s.truthy(try s.get(result,"same")));try std.testing.expect(s.equal(try s.get(result,"calls"),c.JS_NewInt32(engine.context,1)));try std.testing.expect(s.equal(try s.get(result,"coercions"),c.JS_NewInt32(engine.context,0)));try std.testing.expect(engine.captured_exception==null);try std.testing.expectEqual(@as(usize,0),engine.native_exception_diagnostics_suppressed);
}
fn verifyFreshPending(engine:*v.em.Engine,generation:u64)!void{
    const reason=engine.captured_exception orelse return error.MissingCloudflarePendingReason;try std.testing.expect(c.JS_IsStrictEqual(engine.context,reason,engine.native_allocation_exception.?));try std.testing.expect(c.JS_IsUncatchableError(reason));try std.testing.expectEqual(generation+%1,engine.native_allocation_generation);try std.testing.expectEqual(@as(usize,0),engine.native_exception_diagnostics_suppressed);
}
test "Cloudflare c268 actual carrier exports only the database class and preserves inheritance"{
    const engine=try v.em.Engine.init(std.testing.allocator,.{});defer engine.deinit();var s:v.Scope=.{.engine=engine};defer s.deinit();const exports=try s.own(try adapter.create(engine));const global=try s.own(try engine.checked(c.JS_GetGlobalObject(engine.context)));try s.put(global,"ActualCloudflareSQLite",exports);
    const checked=try engine.evalModule(
        \\const exports=ActualCloudflareSQLite,Database=exports.DurableObjectSqliteDatabase,base=Object.getPrototypeOf(Database.prototype);
        \\if(Object.keys(exports).join()!=='DurableObjectSqliteDatabase'||Database.name!=='DurableObjectSqliteDatabase'||Database.length!==1||Database.prototype.constructor!==Database||Object.getPrototypeOf(Database)!==base.constructor||base.constructor.name!=='DurableObjectSqliteExecutor')throw Error('actual class graph');
        \\for(const name of ['exec','run','get','all']){const ordinary=Database.prototype[name],async=base[name];if(ordinary.constructor===async.constructor||ordinary.length!==1||async.length!==1||Object.hasOwn(ordinary,'prototype')||Object.hasOwn(async,'prototype'))throw Error('real ordinary/async method role');const d=Object.getOwnPropertyDescriptor(Database.prototype,name);if(d.enumerable||!d.writable||!d.configurable)throw Error('class method descriptor')}
    ,"cloudflare-c268-class-roles.mjs");engine.freeValue(checked);
}
test "Cloudflare c268 class call without new rejects before any storage capability is required"{
    const engine=try v.em.Engine.init(std.testing.allocator,.{});defer engine.deinit();var s:v.Scope=.{.engine=engine};defer s.deinit();const exports=try s.own(try adapter.create(engine));const constructor=try s.get(exports,"DurableObjectSqliteDatabase");
    try std.testing.expectError(error.JavaScriptException,v.js.call(engine,constructor,c.pi_js_undefined(),&.{}));try std.testing.expect(c.JS_IsError(engine.captured_exception.?));try std.testing.expectEqual(@as(usize,0),engine.native_exception_diagnostics_suppressed);
}
fn constructorPending(context:?*c.JSContext,_:c.JSValue,_:c_int,_:[*c]c.JSValue)callconv(.c)c.JSValue{
    const engine=v.em.Engine.fromContext(context.?);const global=c.JS_GetGlobalObject(context);defer engine.freeValue(global);
    const value=c.JS_GetPropertyStr(context,global,"ConstructorPendingPrototype");if(c.JS_IsException(value))return value;
    const fresh=c.JS_GetPropertyStr(context,global,"ConstructorPendingFresh");defer engine.freeValue(fresh);
    const reason=if(c.JS_ToBool(context,fresh)!=0)blk:{_ = engine.throwNativeOutOfMemory();break :blk c.JS_GetException(context);}else c.JS_GetPropertyStr(context,global,"ConstructorPendingReason");
    if(c.JS_SetPropertyStr(context,global,"ConstructorPendingOriginal",c.JS_DupValue(context,reason))<0){engine.freeValue(value);engine.freeValue(reason);return c.pi_js_exception();}
    _ = c.JS_Throw(context,reason);
    // Allocation denial starts only AFTER the exact pending event exists. The
    // corrected class must transfer it without allocating a replacement object.
    c.JS_SetMemoryLimit(engine.runtime,1);return value;
}
test "Cloudflare c268 newTarget pending prototype is transferred before allocation"{
    for([_]bool{false,true})|fresh|{
        const engine=try v.em.Engine.init(std.testing.allocator,.{});defer engine.deinit();var s:v.Scope=.{.engine=engine};defer s.deinit();
        try engine.bindFunction("ConstructorPendingEvent",constructorPending,0);const exports=try s.own(try adapter.create(engine));const database=try s.get(exports,"DurableObjectSqliteDatabase");const executor=try s.own(try engine.checked(c.JS_GetPrototype(engine.context,database)));
        const initialized=try engine.eval("globalThis.ConstructorPendingPrototype={};globalThis.ConstructorPendingReason={toString(){globalThis.ConstructorPendingCoercions++;throw Error('must not format')}};globalThis.ConstructorPendingCoercions=0;globalThis.ConstructorPendingOriginal=undefined;globalThis.ConstructorPendingTarget=new Proxy(function(){},{get(target,key,receiver){if(key==='prototype')return ConstructorPendingEvent();return Reflect.get(target,key,receiver)}});","cloudflare-pending-newtarget-setup.js",c.JS_EVAL_TYPE_GLOBAL);engine.freeValue(initialized);
        const global=try s.own(try engine.checked(c.JS_GetGlobalObject(engine.context)));try s.put(global,"ConstructorPendingFresh",c.JS_NewBool(engine.context,fresh));const target=try s.global("ConstructorPendingTarget");const generation=engine.native_allocation_generation;
        const raw=c.JS_CallConstructor2(engine.context,executor,target,0,null);
        // Restore outside the VM before ANY host formatting/property/expect
        // operation. No guest recovery/restore is run under pending/fatal state.
        c.JS_SetMemoryLimit(engine.runtime,engine.options.memory_limit);defer c.JS_SetMemoryLimit(engine.runtime,engine.options.memory_limit);
        try std.testing.expect(c.JS_IsException(raw));try std.testing.expect(c.JS_HasException(engine.context));const reason=c.JS_GetException(engine.context);defer engine.freeValue(reason);
        const original=try s.global("ConstructorPendingOriginal");try std.testing.expect(s.equal(reason,original));try std.testing.expect(engine.captured_exception==null);
        try std.testing.expect(s.equal(try s.global("ConstructorPendingCoercions"),c.JS_NewInt32(engine.context,0)));try std.testing.expectEqual(@as(usize,0),engine.native_exception_diagnostics_suppressed);
        if(fresh){try std.testing.expect(c.JS_IsUncatchableError(reason));try std.testing.expectEqual(generation+%1,engine.native_allocation_generation);}else try std.testing.expectEqual(generation,engine.native_allocation_generation);
    }
}
pub const TransactionFailure=enum{old_flagged_rejected_data,same_object_actual_throw,fresh_native_event};
fn captureTransaction(engine:*v.em.Engine,_:c.JSValue,args:[]const c.JSValue,roots:[]const c.JSValue)!c.JSValue{
    try h.field(engine,roots[0],"handle",args[0]);
    if(c.JS_ToBool(engine.context,args[1])!=0){_ = try engine.checked(engine.throwNativeOutOfMemory());unreachable;}
    return c.pi_js_undefined();
}
/// Prepared causal transaction profiles require real storage.transaction and
/// its real commit/rollback. Rejected DATA flags never identify current events.
/// Host assertions inspect only retained own data after a trusted fatal; the
/// fresh realm owner must tear down immediately afterward, without guest work.
pub fn verifyTransactionFailureOnActualStorage(engine:*v.em.Engine,actual_storage:c.JSValue,profile:TransactionFailure)!void{
    var s:v.Scope=.{.engine=engine};defer s.deinit();const exports=try s.own(try adapter.create(engine));const constructor=try s.get(exports,"DurableObjectSqliteDatabase");const database=try s.own(try h.new(engine,constructor,&.{actual_storage}));
    const owner=try s.own(try engine.checked(c.JS_NewObjectProto(engine.context,c.pi_js_null())));try h.field(engine,owner,"handle",c.pi_js_undefined());
    const reason=try s.own(try v.js.builtin(engine,"Error",&.{try s.text("old flagged transaction control")}));c.JS_SetUncatchableError(engine.context,reason);defer c.JS_ClearUncatchableError(engine.context,reason);
    const capture=try s.own(try h.functions.createArrow(engine,"",2,captureTransaction,&.{owner}));
    const fixture=try s.own(try engine.evalModule(
        \\export default function(reason,capture,profile){return function(transaction){capture(transaction,profile===2);if(profile===1)throw reason;return Promise.reject(reason)}}
    ,"cloudflare-transaction-rejected-data-control.mjs"));const make=try s.get(fixture,"default");const callback=try s.call(make,c.pi_js_undefined(),&.{reason,capture,c.JS_NewInt32(engine.context,@intFromEnum(profile))});const generation=engine.native_allocation_generation;
    const pending=v.js.invoke(engine,database,"transaction",&.{callback}) catch|err|{if(err!=error.JavaScriptException)return err;return verifyTransactionFailure(engine,owner,reason,profile,generation);};defer engine.freeValue(pending);
    const settled=engine.awaitValue(pending) catch|err|{if(err!=error.JavaScriptException)return err;return verifyTransactionFailure(engine,owner,reason,profile,generation);};engine.freeValue(settled);return error.TransactionFailureWasSwallowed;
}
fn verifyTransactionFailure(engine:*v.em.Engine,owner:c.JSValue,old:c.JSValue,profile:TransactionFailure,generation:u64)!void{
    const captured=engine.captured_exception orelse return error.MissingTransactionFailure;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context,captured,if(profile==.fresh_native_event)engine.native_allocation_exception.?else old));
    // These are known private own data fields. Do not call guest getters or
    // reporters after a trusted actual throw/event has aborted the invocation.
    const handle=c.JS_GetPropertyStr(engine.context,owner,"handle");defer engine.freeValue(handle);try std.testing.expect(c.JS_IsObject(handle));const active=c.JS_GetPropertyStr(engine.context,handle,"active");defer engine.freeValue(active);
    try std.testing.expectEqual(profile!=.old_flagged_rejected_data,c.JS_ToBool(engine.context,active)!=0);
    if(profile==.fresh_native_event){try std.testing.expect(c.JS_IsUncatchableError(captured));try std.testing.expectEqual(generation+%1,engine.native_allocation_generation);}else try std.testing.expectEqual(generation,engine.native_allocation_generation);
}
