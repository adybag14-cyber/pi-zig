//! Exact original 4954 shared default map, and its real existing fallback consumer.
//! No provider/runtime stand-in is published; test model rows are caller data.
const std = @import("std");
const h = @import("extensions/native_sdk_session_locals.zig");
const v = h.v;
const c = h.c;
const factory = @import("extensions/native_sdk_factory_model.zig");
const reference = @import("extensions/native_sdk_model_reference_live.zig");
const original_map = @embedFile("extensions/fixtures/sdk-default-model-map-4954-source.mjs");
const original_fallback = @embedFile("extensions/fixtures/sdk-default-model-fallback-4954-source.mjs");
fn publish(s: *h.Scope, name: [*:0]const u8, value: c.JSValue) !void {
    try v.put(s, try v.own(s, c.JS_GetGlobalObject(s.engine.context)), name, value);
}
fn mapCall(engine: *h.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return factory.defaultModelPerProvider(engine);
}
fn fallbackCall(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return reference.fallback(engine, roots[0], v.arg(args, 0), v.arg(args, 1));
}
fn prepareBody(s: *h.Scope, cold: bool) !void {
    const map_factory = try v.own(s, try s.engine.eval(original_map, "original-default-map.js", c.JS_EVAL_TYPE_GLOBAL));
    try publish(s, "originalMapFactory", map_factory);
    try publish(s, "nativeMapFactory", try v.ordinary(s, "actualDefaultModelMap", 0, mapCall, &.{}));
    if (cold) return;
    const expected = try v.call(s, map_factory, c.pi_js_undefined(), &.{});
    const native = try v.own(s, try factory.defaultModelPerProvider(s.engine));
    const repeated = try v.own(s, try factory.defaultModelPerProvider(s.engine));
    try std.testing.expect(v.equal(s, native, repeated));
    try publish(s, "sourceMap", expected);
    try publish(s, "nativeMap", native);
    const fallback_factory = try v.own(s, try s.engine.eval(original_fallback, "original-default-fallback.js", c.JS_EVAL_TYPE_GLOBAL));
    try publish(s, "sourceFallback", try v.call(s, fallback_factory, c.pi_js_undefined(), &.{expected}));
    try publish(s, "nativeFallback", try v.ordinary(s, "actualExistingFallback", 2, fallbackCall, &.{native}));
}
fn run(source: []const u8, cold: bool) !void {
    const engine = try h.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try h.statement(engine, prepareBody, .{cold});
    const result = try engine.evalModule(source, "actual-original-default-map-control.mjs");
    defer engine.freeValue(result);
    engine.freeValue(try engine.awaitValue(result));
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try std.testing.expect(engine.native_fatal_invocation == null);
}
const assertions =
    \\function assert(value,message){if(!value)throw new Error(message);}
    \\function same(a,b,message){assert(JSON.stringify(a)===JSON.stringify(b),message);}
;
test "native SDK original default model map complete forty-one keys values order and descriptors" {
    try run(assertions ++
        \\same(Reflect.ownKeys(nativeMap),Reflect.ownKeys(sourceMap),"complete original key order");
        \\assert(Reflect.ownKeys(nativeMap).length===41,"complete forty-one provider map");
        \\same(nativeMap,sourceMap,"all original provider values");
        \\assert(Object.getPrototypeOf(nativeMap)===Object.getPrototypeOf(sourceMap),"ordinary original object prototype");
        \\for(const key of Reflect.ownKeys(sourceMap))same(Object.getOwnPropertyDescriptor(nativeMap,key),Object.getOwnPropertyDescriptor(sourceMap,key),"original writable configurable enumerable property "+key);
    , false);
}
test "native SDK original default model map five corrected values feed actual fallback metadata" {
    try run(assertions ++
        \\const rows=[
        \\ ["nvidia","nvidia/nemotron-3.5-super-vl-120b-a12b","nvidia/nemotron-3-ultra-550b-a55b"],
        \\ ["xiaomi","mimo-v2.6-pro","mimo-v2.5-pro"],
        \\ ["xiaomi-token-plan-cn","mimo-v2.6-pro","mimo-v2.5-pro"],
        \\ ["xiaomi-token-plan-ams","mimo-v2.6-pro","mimo-v2.5-pro"],
        \\ ["xiaomi-token-plan-sgp","mimo-v2.6-pro","mimo-v2.5-pro"]
        \\];
        \\for(const [provider,previous,original] of rows){
        \\ const models=[{provider,id:previous,origin:"historical"},{provider,id:original,origin:"original",baseUrl:"https://original.invalid"}];
        \\ const expected=sourceFallback(models,"caller-model"),actual=nativeFallback(models,"caller-model");
        \\ same(actual,expected,"actual existing fallback consumes matched map "+provider);
        \\ assert(actual.origin==="original"&&actual.id==="caller-model"&&actual.name==="caller-model","original selected metadata "+provider);
        \\ assert(actual!==models[1],"original fallback object spread copy");
        \\}
    , false);
}
test "native SDK original default model map remains one live mutable import for real consumer" {
    try run(assertions ++
        \\assert(nativeMapFactory()===nativeMap,"warm owner identity");
        \\const models=[{provider:"nvidia",id:"first",selected:1},{provider:"nvidia",id:"later",selected:2}];
        \\for(const [map,fallback] of [[sourceMap,sourceFallback],[nativeMap,nativeFallback]]){
        \\ map.nvidia="later";assert(fallback(models,"custom").selected===2,"live mutation selects later");
        \\ map.nvidia="first";assert(fallback(models,"custom").selected===1,"same captured map sees replacement");
        \\}
        \\assert(nativeMapFactory().nvidia==="first","no fresh map replaces mutation");
    , false);
}
test "native SDK original default model map deletion and inherited value retain Source lookup" {
    try run(assertions ++
        \\const models=[{provider:"nvidia",id:"first",selected:1},{provider:"nvidia",id:"inherited",selected:2}];
        \\const traces=[];
        \\for(const [map,fallback] of [[sourceMap,sourceFallback],[nativeMap,nativeFallback]]){
        \\ const trace=[];delete map.nvidia;
        \\ assert(fallback(models,"custom").selected===1,"missing default takes first original row");
        \\ Object.setPrototypeOf(map,{get nvidia(){trace.push("get");return "inherited";}});
        \\ assert(fallback(models,"custom").selected===2,"ordinary inherited map Get");
        \\ traces.push(trace);
        \\}
        \\same(traces,[["get"],["get"]],"one inherited lookup per real fallback");
    , false);
}
test "native SDK original default model map literal ignores global Object and inherited setters" {
    try run(assertions ++
        \\const O=Object;let writes=0;
        \\O.defineProperty(O.prototype,"nvidia",{configurable:true,set(){writes++;}});
        \\globalThis.Object=function(){throw new Error("literal must not call Object");};
        \\try{
        \\ const source=originalMapFactory(),native=nativeMapFactory();
        \\ assert(writes===0&&O.hasOwn(source,"nvidia")&&O.hasOwn(native,"nvidia"),"own literal properties suppress inherited setter");
        \\ same(native,source,"complete genuine literal independent of global constructor");
        \\}finally{globalThis.Object=O;delete O.prototype.nvidia;}
    , true);
}
test "native SDK original default model map actual Engines retain independent shared owners" {
    try run(assertions ++
        \\nativeMap.nvidia="private-first-engine";
        \\assert(nativeMapFactory().nvidia==="private-first-engine","first Engine stable");
    , false);
    try run(assertions ++
        \\assert(nativeMap.nvidia==="nvidia/nemotron-3-ultra-550b-a55b","fresh Engine original default");
        \\same(nativeMap,sourceMap,"fresh Engine complete original object");
    , false);
}
