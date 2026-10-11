const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const c = em.c;
fn valueCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    if (argc < 1) return c.JS_ThrowTypeError(context, "Expected one borrowed operand");
    return switch (magic) {
        0 => c.JS_PiPromiseResolve(context, argv[0]),
        1 => c.JS_PiToNumeric(context, argv[0]),
        else => c.JS_PiIncrement(context, argv[0]),
    };
}
fn thenCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    if (argc < 3) return c.JS_ThrowTypeError(context, "Expected promise and two reactions");
    return c.JS_PromiseThen(context, argv[0], argv[1], argv[2]);
}
fn install(engine: *em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    inline for (.{ "nativeIntrinsicResolve", "nativeToNumeric", "nativeIncrement" }, 0..) |name, index| try js.define(engine, global, name, try engine.checked(c.pi_js_function_magic(engine.context, valueCall, name, 1, @intCast(index))));
    try js.define(engine, global, "nativeIntrinsicThen", try engine.checked(c.JS_NewCFunction(engine.context, thenCall, "nativeIntrinsicThen", 3)));
}
test "native SDK await primitives preserve actual constructor then and borrowed promise identity" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const output = try engine.evalModule(@embedFile("extensions/fixtures/sdk-await-primitives-reference.input.txt"), "sdk-await-primitives-reference.mjs");
    engine.freeValue(output);
}
test "native SDK await primitives preserve old ToNumeric BigInt signed zero hints and raw exceptions" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    const output = try engine.eval(
        \\for(const input of [0,-0,NaN,Infinity,-Infinity,'2','bad',2n,9007199254740993n,undefined,null,true,false,Symbol('numeric')]){let value=input,expected,actual,firstError,secondError;try{expected=value++}catch(error){firstError=error}try{actual=nativeToNumeric(input)}catch(error){secondError=error}if(!!firstError!==!!secondError||firstError&&firstError.name!==secondError.name||!firstError&&!Object.is(expected,actual))throw Error('old ToNumeric mismatch');if(!firstError&&!Object.is(nativeIncrement(actual),value))throw Error('incremented numeric mismatch')}
        \\for(const primitive of [0,-0,2n,9007199254740993n]){const trace=[],first={[Symbol.toPrimitive](hint){trace.push(hint);return primitive}},second={[Symbol.toPrimitive](hint){trace.push(hint);return primitive}};let value=first;const expected=value++,before=trace.splice(0),actual=nativeToNumeric(second);if(!Object.is(expected,actual)||JSON.stringify(trace)!==JSON.stringify(before)||trace[0]!=='number')throw Error('numeric hint/order');const count=trace.length;if(!Object.is(nativeIncrement(actual),value)||trace.length!==count)throw Error('second observable coercion');if(typeof second[Symbol.toPrimitive]!=='function')throw Error('borrowed numeric input released')}
        \\let converted=0;const reason={toString(){converted++;return'forbidden diagnostic'}},original={[Symbol.toPrimitive](){throw reason}};try{nativeToNumeric(original);throw Error('missing original numeric error')}catch(error){if(error!==reason)throw error}if(converted!==0||typeof original[Symbol.toPrimitive]!=='function')throw Error('numeric exception identity/lifetime');
    , "sdk-old-numeric-reference", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(output);
    c.JS_RunGC(engine.runtime);
}
