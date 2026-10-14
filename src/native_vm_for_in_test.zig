//! Additive owned VM ABI qualification, separate from Original Node inheritance.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const js = @import("extensions/native_js_values.zig");
const enumeration = @import("extensions/native_for_in.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
fn recordCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return record(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn record(engine: *em.Engine, source: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const output = try scope.array();
    var iterator = try enumeration.Iterator.init(engine, source);
    defer iterator.deinit();
    while (try iterator.next()) |key| {
        defer engine.freeValue(key);
        var frame: Scope = .{ .engine = engine };
        defer frame.deinit();
        const pair = try frame.array();
        try frame.index(pair, 0, key);
        try frame.index(pair, 1, try frame.own(try js.getKey(engine, source, key)));
        _ = try frame.invoke(output, "push", &.{pair});
    }
    return c.JS_DupValue(engine.context, output);
}
fn exercise(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "nativeForIn", try engine.checked(c.JS_NewCFunction(engine.context, recordCall, "nativeForIn", 1)));
    const result = engine.eval(
        \\const cases=[
        \\()=>({value:undefined,log:[]}),()=>({value:null,log:[]}),()=>({value:'a界😀\ud800',log:[]}),
        \\()=>({value:Object.assign(Object.create({parent:3}),{a:1,b:2}),log:[]}),
        \\()=>{const v=Object.create({hidden:1,parent:2});Object.defineProperty(v,'hidden',{value:3});v.a=4;return{value:v,log:[]}},
        \\()=>({value:[,1,,3],log:[]}),
        \\()=>{const v={get a(){delete v.b;return 1},b:2,c:3};return{value:v,log:[]}},
        \\()=>{const log=[],v=new Proxy({a:1,b:2},{ownKeys(o){log.push('keys');return Reflect.ownKeys(o)},getPrototypeOf(o){log.push('proto');return Reflect.getPrototypeOf(o)},getOwnPropertyDescriptor(o,k){log.push(['desc',k]);return Reflect.getOwnPropertyDescriptor(o,k)},get(o,k,r){log.push(['get',k]);return Reflect.get(o,k,r)}});return{value:v,log}},
        \\()=>{const error={},log=[],v=new Proxy({},{ownKeys(){log.push('keys');throw error}});return{value:v,log,error}},
        \\()=>{const error={},log=[],v={get a(){log.push('get');throw error}};return{value:v,log,error}},
        \\()=>{const error={},log=[],p=new Proxy({a:1},{has(){log.push('has');throw error}});return{value:Object.create(p),log,error}}
        \\];
        \\function guest(value){const result=[];for(const key in value)result.push([key,value[key]]);return result}
        \\function run(factory,fn){const c=factory();try{return{result:fn(c.value),log:c.log}}catch(e){if(e!==c.error)throw e;return{same:true,name:e.name,log:c.log}}}
        \\for(const[i,factory]of cases.entries()){const a=run(factory,nativeForIn),b=run(factory,guest);if(JSON.stringify(a)!==JSON.stringify(b))throw Error(JSON.stringify({i,a,b}))}
        \\delete globalThis.nativeForIn;
    , "vm-for-in-guest-comparison.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    const source = try engine.eval("globalThis.forInSource={a:1};globalThis.forInWeak=new WeakRef(forInSource);forInSource", "vm-for-in-gc-setup.js", c.JS_EVAL_TYPE_GLOBAL);
    var iterator = enumeration.Iterator.init(engine, source) catch |err| {
        engine.freeValue(source);
        return err;
    };
    engine.freeValue(source);
    var held = true;
    defer if (held) iterator.deinit();
    const removed = try engine.eval("delete globalThis.forInSource", "vm-for-in-release-global.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(removed);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const alive = try engine.eval("forInWeak.deref()!==undefined", "vm-for-in-retained.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(alive);
    if (c.JS_ToBool(engine.context, alive) != 1) return error.ForInSourceReleasedEarly;
    iterator.deinit();
    held = false;
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const collected = try engine.eval("forInWeak.deref()===undefined", "vm-for-in-collected.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(collected);
    if (c.JS_ToBool(engine.context, collected) != 1) return error.ForInSourceRetained;
}
test "native VM for-in owned ABI agrees with real guest enumeration errors mutations and GC" {
    try exercise(std.testing.allocator);
}
test "native VM for-in owned ABI releases every host allocation failure" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "vm-for-in", exercise, .{});
}
test "native VM for-in owned iterator honors existing cancellation without a new enumeration limit" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var iterator = try enumeration.Iterator.init(engine, c.pi_js_undefined());
    defer iterator.deinit();
    engine.cancelled.store(true, .release);
    defer engine.cancelled.store(false, .release);
    try std.testing.expectError(error.JavaScriptException, iterator.next());
}
