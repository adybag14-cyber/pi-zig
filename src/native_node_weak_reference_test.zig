//! Actual-VM controls for the complete internal/util WeakReference leaf.
//! Source-only packet: Root owns compilation, metadata and execution.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const weak = @import("extensions/native_node_weak_reference.zig");
const js = @import("extensions/native_js_values.zig");

fn expose(engine: *em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (c.JS_DefinePropertyValueStr(engine.context, global, name,
        c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E) < 0)
        return js.capture(engine);
}
fn install(engine: *em.Engine, name: [*:0]const u8) !void {
    const constructor_value = try weak.create(engine);
    defer engine.freeValue(constructor_value);
    try expose(engine, name, constructor_value);
}
fn start() !*em.Engine {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    errdefer engine.deinit();
    try install(engine, "NativeWeakReference");
    return engine;
}
fn evaluate(engine: *em.Engine, source: []const u8) !c.JSValue {
    return engine.eval(source, "native-node-weak-reference.js", c.JS_EVAL_TYPE_GLOBAL);
}
fn run(engine: *em.Engine, source: []const u8) !void {
    engine.freeValue(try evaluate(engine, source));
}
fn check(engine: *em.Engine, source: []const u8) !void {
    const value = try evaluate(engine, source);
    defer engine.freeValue(value);
    try std.testing.expect(c.JS_IsStrictEqual(
        engine.context, value, c.JS_NewBool(engine.context, true)));
}
fn method(engine: *em.Engine, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return engine.checked(c.JS_GetPropertyStr(engine.context, receiver, name));
}
fn call(engine: *em.Engine, function: c.JSValue, receiver: c.JSValue) !c.JSValue {
    return engine.checked(c.JS_Call(engine.context, function, receiver, 0, null));
}
fn number(engine: *em.Engine, value: c.JSValue) !f64 {
    var result: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &result, value) < 0) return js.capture(engine);
    return result;
}
fn collect(engine: *em.Engine) void {
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
fn nestedCollect(context: ?*c.JSContext, _: c.JSValue, _: c_int,
    _: [*c]c.JSValue) callconv(.c) c.JSValue
{
    const engine = em.Engine.fromContext(context.?);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    return c.pi_js_undefined();
}

test "native WeakReference original class metadata and private instance surface" {
    const engine = try start(); defer engine.deinit();
    try check(engine,
        \\(()=>{const C=NativeWeakReference,p=C.prototype,r=new C({});
        \\const cp=Object.getOwnPropertyDescriptor(C,"prototype");
        \\if(C.name!=="WeakReference"||C.length!==1||Object.getPrototypeOf(C)!==Function.prototype||
        \\   cp.writable||cp.enumerable||cp.configurable||Object.getPrototypeOf(p)!==Object.prototype)return false;
        \\if(Reflect.ownKeys(p).join("|")!=="constructor|incRef|decRef|get")return false;
        \\for(const name of ["incRef","decRef","get"]){const d=Object.getOwnPropertyDescriptor(p,name);
        \\ if(!d.writable||d.enumerable||!d.configurable||d.value.name!==name||d.value.length!==0||
        \\    Object.hasOwn(d.value,"prototype"))return false}
        \\return Object.getPrototypeOf(r)===p&&Reflect.ownKeys(r).length===0&&
        \\ Object.getOwnPropertySymbols(r).length===0&&Object.prototype.toString.call(r)==="[object Object]"})()
    );
}
test "native WeakReference increments and decrements original Number counter" {
    const engine = try start(); defer engine.deinit();
    try check(engine,
        \\(()=>{const target={},r=new NativeWeakReference(target);
        \\return r.get()===target&&r.incRef()===1&&r.incRef()===2&&r.decRef()===1&&
        \\r.get()===target&&r.decRef()===0&&r.incRef()===1&&r.decRef()===0})()
    );
}
test "native WeakReference negative refcounts are preserved rather than clamped" {
    const engine = try start(); defer engine.deinit();
    try check(engine,
        \\(()=>{const r=new NativeWeakReference({});
        \\return r.decRef()===-1&&r.decRef()===-2&&r.incRef()===-1&&r.incRef()===0&&
        \\r.incRef()===1&&r.decRef()===0&&r.decRef()===-1})()
    );
}
test "native WeakReference distinct instances retain independent state and identity" {
    const engine = try start(); defer engine.deinit();
    try check(engine,
        \\(()=>{const a={},b={},ra=new NativeWeakReference(a),rb=new NativeWeakReference(b);
        \\return ra!==rb&&ra.get()===a&&rb.get()===b&&ra.incRef()===1&&
        \\rb.decRef()===-1&&ra.incRef()===2&&rb.incRef()===0})()
    );
}
test "native WeakReference rejects invalid targets through the genuine WeakRef constructor" {
    const engine = try start(); defer engine.deinit();
    try check(engine,
        \\(()=>{for(const value of [undefined,null,true,0,"x",1n,Symbol.for("registered")]){
        \\let rejected=false;try{new NativeWeakReference(value)}catch(error){rejected=error instanceof TypeError}
        \\if(!rejected)return false}return true})()
    );
}
test "native WeakReference preserves unique symbol and callable targets" {
    const engine = try start(); defer engine.deinit();
    try check(engine,
        \\(()=>{const symbol=Symbol("actual"),fn=()=>1,a=new NativeWeakReference(symbol),b=new NativeWeakReference(fn);
        \\return a.get()===symbol&&a.incRef()===1&&a.decRef()===0&&b.get()===fn})()
    );
}
test "native WeakReference captures pristine WeakRef even after public replacement" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try run(engine,
        \\globalThis.publicCalls=0;
        \\WeakRef.prototype.deref=function(){publicCalls++;throw Error("public deref")};
        \\globalThis.WeakRef=function(){publicCalls++;throw Error("public WeakRef")};
    );
    try install(engine, "NativeWeakReference");
    try check(engine,
        \\(()=>{const target={},r=new NativeWeakReference(target);
        \\return r.get()===target&&r.incRef()===1&&r.get()===target&&r.decRef()===0&&publicCalls===0})()
    );
}
test "native WeakReference requires new and every prototype method is nonconstructible" {
    const engine = try start(); defer engine.deinit();
    try check(engine,
        \\(()=>{let count=0;try{NativeWeakReference({})}catch(error){if(error instanceof TypeError)count++}
        \\for(const name of ["incRef","decRef","get"]){try{Reflect.construct(NativeWeakReference.prototype[name],[])}
        \\catch(error){if(error instanceof TypeError)count++}}return count===4})()
    );
}
test "native WeakReference brands reject forged primitive and proxy receivers without traps" {
    const engine = try start(); defer engine.deinit();
    try check(engine,
        \\(()=>{let traps=0;const real=new NativeWeakReference({});
        \\const proxy=new Proxy(real,{get(){traps++;throw Error("get")}});
        \\const revoked=Proxy.revocable(real,{});revoked.revoke();
        \\for(const name of ["incRef","decRef","get"])
        \\for(const receiver of [undefined,null,1,"x",{},Object.create(NativeWeakReference.prototype),proxy,revoked.proxy]){
        \\let rejected=false;try{Reflect.apply(NativeWeakReference.prototype[name],receiver,[])}
        \\catch(error){rejected=error instanceof TypeError}if(!rejected)return false}
        \\return traps===0&&real.incRef()===1})()
    );
}
test "native WeakReference separate class evaluations use separate private brands" {
    const engine = try start(); defer engine.deinit();
    try install(engine, "SecondWeakReference");
    try check(engine,
        \\(()=>{const first=new NativeWeakReference({}),second=new SecondWeakReference({});
        \\for(const name of ["incRef","decRef","get"]){let rejected=false;
        \\try{Reflect.apply(NativeWeakReference.prototype[name],second,[])}catch(error){rejected=error instanceof TypeError}
        \\if(!rejected)return false}return first.incRef()===1&&second.incRef()===1})()
    );
}
test "native WeakReference ignores method arguments and frozen instances keep private slots" {
    const engine = try start(); defer engine.deinit();
    try check(engine,
        \\(()=>{let touches=0;const extra=new Proxy({},{get(){touches++;throw Error("unused")}});
        \\const target={},r=Object.freeze(new NativeWeakReference(target));
        \\return r.incRef(extra)===1&&r.get(extra)===target&&r.decRef(extra)===0&&
        \\touches===0&&!Object.isExtensible(r)&&Reflect.ownKeys(r).length===0})()
    );
}
test "native WeakReference derived new target prototype and brand are genuine" {
    const engine = try start(); defer engine.deinit();
    try check(engine,
        \\(()=>{class Child extends NativeWeakReference{};const target={},child=new Child(target);
        \\let reads=0;const prototype={},N=new Proxy(function(){},{get(t,k,r){
        \\ if(k==="prototype"){reads++;return prototype}return Reflect.get(t,k,r)}});
        \\const alternate=Reflect.construct(NativeWeakReference,[target],N);
        \\const fallback=function(){};fallback.prototype=3;
        \\const plain=Reflect.construct(NativeWeakReference,[target],fallback);
        \\return child instanceof Child&&child instanceof NativeWeakReference&&child.get()===target&&
        \\reads===1&&Object.getPrototypeOf(alternate)===prototype&&
        \\NativeWeakReference.prototype.get.call(alternate)===target&&
        \\Object.getPrototypeOf(plain)===Object.prototype&&NativeWeakReference.prototype.incRef.call(plain)===1})()
    );
}
test "native WeakReference new target prototype throw precedes invalid weak target" {
    const engine = try start(); defer engine.deinit();
    try check(engine,
        \\(()=>{const reason={};let reads=0;const N=new Proxy(function(){},{get(t,k,r){
        \\if(k==="prototype"){reads++;throw reason}return Reflect.get(t,k,r)}});
        \\try{Reflect.construct(NativeWeakReference,[null],N)}catch(error){return error===reason&&reads===1}
        \\return false})()
    );
}
test "native WeakReference constructor and get keep referent through nested current job collection" {
    const engine = try start(); defer engine.deinit();
    const gc_function = try engine.checked(c.JS_NewCFunction(
        engine.context, nestedCollect, "nestedWeakCollect", 0));
    defer engine.freeValue(gc_function);
    try expose(engine, "nestedWeakCollect", gc_function);
    try check(engine,
        \\(()=>{globalThis.reference=(()=>{const target={marker:37};target.self=target;
        \\return new NativeWeakReference(target)})();nestedWeakCollect();
        \\return reference.get().marker===37})()
    );
    collect(engine);
    try check(engine, "reference.get()===undefined");
}
test "native WeakReference get adds a real kept root without permanently strengthening it" {
    const engine = try start(); defer engine.deinit();
    try run(engine, "globalThis.target={marker:41};target.self=target;globalThis.reference=new NativeWeakReference(target)");
    collect(engine);
    try run(engine, "reference.get();target=null");
    c.JS_RunGC(engine.runtime);
    try check(engine, "reference.get().marker===41");
    collect(engine);
    try check(engine, "reference.get()===undefined");
}
test "native WeakReference strong root is traced until exact zero transition" {
    const engine = try start(); defer engine.deinit();
    try run(engine,
        \\globalThis.reference=(()=>{const target={marker:43};target.self=target;
        \\const r=new NativeWeakReference(target);r.incRef();r.incRef();return r})();
    );
    collect(engine);
    try check(engine, "reference.get().marker===43&&reference.decRef()===1");
    collect(engine);
    try check(engine, "reference.get().marker===43&&reference.decRef()===0");
    collect(engine);
    try check(engine, "reference.get()===undefined");
}
test "native WeakReference collected target stays absent through later positive transitions" {
    const engine = try start(); defer engine.deinit();
    try run(engine, "globalThis.reference=new NativeWeakReference({})");
    collect(engine);
    try check(engine,
        \\reference.get()===undefined&&reference.incRef()===1&&reference.get()===undefined&&
        \\reference.decRef()===0&&reference.incRef()===1&&reference.get()===undefined
    );
}
test "native WeakReference pending factory entry wins before any allocation" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try em.Engine.init(failing.allocator(), .{}); defer engine.deinit();
    const reason = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(reason);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
    const index = failing.alloc_index;
    failing.fail_index = index;
    const result = weak.create(engine);
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expectError(error.JavaScriptException, result);
    try std.testing.expectEqual(index, failing.alloc_index);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception.?));
    try std.testing.expect(engine.native_fatal_invocation == null);
}
test "native WeakReference pending callback entry prevents counter mutation" {
    const engine = try start(); defer engine.deinit();
    const reference = try evaluate(engine, "new NativeWeakReference({})"); defer engine.freeValue(reference);
    const increment = try method(engine, reference, "incRef"); defer engine.freeValue(increment);
    const reason = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(reason);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
    try std.testing.expectError(error.JavaScriptException, call(engine, increment, reference));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception.?));
    const first = try call(engine, increment, reference); defer engine.freeValue(first);
    try std.testing.expectEqual(@as(f64, 1), try number(engine, first));
}
test "native WeakReference failed charged instance allocation preserves fatal and reusable class" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try em.Engine.init(failing.allocator(), .{}); defer engine.deinit();
    const constructor_value = try weak.create(engine); defer engine.freeValue(constructor_value);
    const target = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(target);
    const args = [_]c.JSValue{target};
    failing.fail_index = failing.alloc_index;
    const raw = c.JS_CallConstructor(engine.context, constructor_value, 1, @constCast(&args));
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expect(c.JS_IsException(raw) and c.JS_HasException(engine.context));
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    c.JS_ClearUncatchableError(engine.context, reason);
    try std.testing.expect(engine.native_fatal_invocation == null);
    const reference = try engine.checked(c.JS_CallConstructor(
        engine.context, constructor_value, 1, @constCast(&args)));
    defer engine.freeValue(reference);
    const getter = try method(engine, reference, "get"); defer engine.freeValue(getter);
    const found = try call(engine, getter, reference); defer engine.freeValue(found);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, target, found));
}

const RetirementProbe = struct {
    engine: *em.Engine,
    calls: usize = 0,
    receiver: ?c.JSValue = null,
    increment: ?c.JSValue = null,
    observed: f64 = 0,
    failed: bool = false,
};
fn retireTarget(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const probe: *RetirementProbe = @ptrCast(@alignCast(
        c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    _ = c.JS_SetOpaque(value, null);
    probe.calls += 1;
    if (probe.increment) |increment| {
        const result = c.JS_Call(probe.engine.context, increment, probe.receiver.?, 0, null);
        defer c.JS_FreeValueRT(runtime, result);
        if (c.JS_IsException(result) or
            c.JS_ToFloat64(probe.engine.context, &probe.observed, result) < 0)
            probe.failed = true;
    }
}
fn nativeTarget(engine: *em.Engine, probe: *RetirementProbe) !c.JSValue {
    var id: c.JSClassID = 0;
    if (c.JS_NewClassID(engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{
        .class_name = "Actual WeakReference target retirement", .finalizer = retireTarget,
    };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const value = try engine.checked(c.JS_NewObjectClass(engine.context, id));
    _ = c.JS_SetOpaque(value, probe);
    return value;
}
test "native WeakReference strong root retirement publishes zero before actual finalizer reentry" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var probe: RetirementProbe = .{ .engine = engine };
    const constructor_value = try weak.create(engine); defer engine.freeValue(constructor_value);
    const target = try nativeTarget(engine, &probe);
    var target_owned = true; defer if (target_owned) engine.freeValue(target);
    const args = [_]c.JSValue{target};
    const reference = try engine.checked(c.JS_CallConstructor(
        engine.context, constructor_value, 1, @constCast(&args)));
    defer engine.freeValue(reference);
    const increment = try method(engine, reference, "incRef"); defer engine.freeValue(increment);
    const decrement = try method(engine, reference, "decRef"); defer engine.freeValue(decrement);
    const getter = try method(engine, reference, "get"); defer engine.freeValue(getter);
    const first = try call(engine, increment, reference); engine.freeValue(first);
    engine.freeValue(target); target_owned = false;
    collect(engine);
    try std.testing.expectEqual(@as(usize, 0), probe.calls);
    probe.receiver = reference;
    probe.increment = increment;
    const dropped = try call(engine, decrement, reference); engine.freeValue(dropped);
    // Native DECREF work can be queued. Inspect actual finalization only after
    // collection, without asserting an invented immediate finalizer ordering.
    collect(engine);
    probe.increment = null;
    try std.testing.expectEqual(@as(usize, 1), probe.calls);
    try std.testing.expect(!probe.failed);
    try std.testing.expectEqual(@as(f64, 1), probe.observed);
    const absent = try call(engine, getter, reference); defer engine.freeValue(absent);
    try std.testing.expect(c.JS_IsUndefined(absent));
    const balanced = try call(engine, decrement, reference); defer engine.freeValue(balanced);
    try std.testing.expectEqual(@as(f64, 0), try number(engine, balanced));
}
fn cycle(engine: *em.Engine) !void {
    try run(engine,
        \\globalThis.cycleReference=(()=>{const target={};const r=new NativeWeakReference(target);
        \\target.reference=r;r.incRef();return r})();globalThis.cycleReference=null;
    );
    collect(engine);
}
test "native WeakReference charged instance and strong referent cycle are reclaimed by real GC" {
    const engine = try start(); defer engine.deinit();
    try cycle(engine);
    const baseline = c.pi_js_native_memory_used(engine.native_memory_owner);
    try cycle(engine);
    try std.testing.expectEqual(baseline, c.pi_js_native_memory_used(engine.native_memory_owner));
}
