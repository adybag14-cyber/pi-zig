const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const sdk = @import("extensions/native_sdk.zig");
const native = @import("extensions/native_node_function.zig");
const c = em.c;
fn read(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return js.get(engine, if (args.len > 0) args[0] else c.pi_js_undefined(), "field");
}
test "native node function preserves caught getter exception without diagnostic coercion" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "nativeRead", try native.createArrow(engine, "nativeRead", 1, read, &.{}));
    const result = try engine.evalModule(
        \\let coerced=0;const reason={toString(){coerced++;throw Error('diagnostic must not run before guest catch')}};const input={get field(){throw reason}};let caught;try{nativeRead(input)}catch(error){caught=error}if(caught!==reason||coerced!==0)throw Error('guest exception was coerced');export const done=true;
    , "native-function-raw-getter.mjs");
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
fn methodResult(engine: *em.Engine, receiver: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "receiver", c.JS_DupValue(engine.context, receiver));
    return result;
}
test "native node method retains receiver metadata and creation realm across foreign calls" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const other = c.JS_NewContext(engine.runtime) orelse return error.OutOfMemory;
    defer c.JS_FreeContext(other);
    const method = try native.createMethod(engine, "method", 0, methodResult, &.{});
    defer engine.freeValue(method);
    const receiver = try sdk.object(engine);
    defer engine.freeValue(receiver);
    const result = try engine.checked(c.JS_Call(other, method, receiver, 0, null));
    defer engine.freeValue(result);
    const actual_receiver = try js.get(engine, result, "receiver");
    defer engine.freeValue(actual_receiver);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, receiver, actual_receiver));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const object = try js.get(engine, global, "Object");
    defer engine.freeValue(object);
    const expected = try js.get(engine, object, "prototype");
    defer engine.freeValue(expected);
    const actual = try engine.checked(c.JS_GetPrototype(other, result));
    defer engine.freeValue(actual);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, expected));
    try sdk.put(engine, global, "nativeMethod", c.JS_DupValue(engine.context, method));
    const checked = try engine.evalModule("if(nativeMethod.name!=='method'||nativeMethod.length!==0||Object.hasOwn(nativeMethod,'prototype'))throw Error('method metadata');let caught;try{Reflect.construct(nativeMethod,[])}catch(error){caught=error}if(!(caught instanceof TypeError))throw Error('method constructible');export const done=true;", "native-method-metadata.mjs");
    engine.freeValue(checked);
    c.JS_RunGC(engine.runtime);
}
