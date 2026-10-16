//! Prepared native ownership invariant, not registered/executed/qualified.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const lru = @import("native_hosted_git_lru.zig");
const c = em.c;
fn collect(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue { c.JS_RunGC(em.Engine.fromContext(context.?).runtime); return c.pi_js_undefined(); }
test "default LRU discards ignored clear and fill values before later callbacks" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const owner = try lru.create(engine); defer engine.freeValue(owner); const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try js.define(engine, global, "lruProbeMap", try js.get(engine, owner, "map")); try js.define(engine, global, "lruProbeValues", try js.get(engine, owner, "values")); try js.define(engine, global, "lruProbeKeys", try js.get(engine, owner, "keys")); try engine.bindFunction("nativeCollectLruProbe", collect, 0);
    const prepared = try engine.eval(
        \\globalThis.lruClearHolder={ignored:'clear'};globalThis.lruFillHolder={ignored:'fill'};
        \\globalThis.lruClearWeak=new WeakRef(lruClearHolder);globalThis.lruFillWeak=new WeakRef(lruFillHolder);globalThis.lruRetirementTrace=[];
        \\const originalClear=lruProbeMap.clear,originalValuesFill=lruProbeValues.fill,originalKeysFill=lruProbeKeys.fill;
        \\lruProbeMap.clear=function(){Reflect.apply(originalClear,this,arguments);const result=lruClearHolder;lruClearHolder=null;return result};
        \\lruProbeValues.fill=function(){nativeCollectLruProbe();if(lruClearWeak.deref()!==undefined)throw Error('ignored clear result retained');lruRetirementTrace.push('values');Reflect.apply(originalValuesFill,this,arguments);const result=lruFillHolder;lruFillHolder=null;return result};
        \\lruProbeKeys.fill=function(){nativeCollectLruProbe();if(lruFillWeak.deref()!==undefined)throw Error('ignored fill result retained');lruRetirementTrace.push('keys');return Reflect.apply(originalKeysFill,this,arguments)};
    , "lru-return-retirement-prepare.js", c.JS_EVAL_TYPE_GLOBAL); engine.freeValue(prepared);
    const key = try engine.checked(c.JS_NewString(engine.context, "owned-key")); defer engine.freeValue(key); const value = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(value); try lru.set(engine, owner, key, value);
    // End the preparation job's weak-kept objects before the operation. The
    // callback collector itself performs GC without clearing live-job keeps.
    c.JS_ClearKeptObjects(engine.runtime); c.JS_RunGC(engine.runtime);
    try lru.set(engine, owner, key, c.pi_js_undefined());
    const verified = try engine.eval("if(lruRetirementTrace.join(',')!=='values,keys')throw Error('retirement callbacks incomplete')", "lru-return-retirement-complete.js", c.JS_EVAL_TYPE_GLOBAL); engine.freeValue(verified);
}
