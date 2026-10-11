const std = @import("std");
const js = @import("extensions/native_js_values.zig");
const c = js.c;
const image_math = @import("extensions/native_image_arithmetic.zig");
fn invoke(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    if (argc != 3) return c.JS_ThrowTypeError(context, "Expected operation and two operands");
    var operation: i32 = 0;
    if (c.JS_ToInt32(context, &operation, argv[0]) < 0) return c.JS_Throw(context, c.JS_GetException(context));
    return c.JS_PiBinaryOperator(context, operation, argv[1], argv[2]);
}
fn increment(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_PiIncrement(context, if (argc > 0) argv[0] else c.pi_js_undefined());
}
test "native binary operators preserve guest coercion BigInt exception and borrowed identity" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "nativeBinary", try engine.checked(c.JS_NewCFunction(engine.context, invoke, "nativeBinary", 3)));
    try js.define(engine, global, "nativeIncrement", try engine.checked(c.JS_NewCFunction(engine.context, increment, "nativeIncrement", 1)));
    const result = try engine.eval(
        \\const operators=[(a,b)=>a+b,(a,b)=>a-b,(a,b)=>a*b,(a,b)=>a/b,(a,b)=>a<b,(a,b)=>a<=b,(a,b)=>a>b,(a,b)=>a>=b];
        \\const pairs=[[1,2],[-0,0],[NaN,1],[Infinity,2],['2',3],['10','2'],[2n,3n],[2n,3],[undefined,null],[true,false]];
        \\for(let op=0;op<operators.length;op++)for(const [left,right]of pairs){let a,b,ea,eb;try{a=operators[op](left,right)}catch(e){ea=e}try{b=nativeBinary(op,left,right)}catch(e){eb=e}if(!!ea!==!!eb||ea&&ea.name!==eb.name||!ea&&!Object.is(a,b))throw Error('native operator mismatch '+op)}
        \\for(let op=0;op<8;op++){const trace=[];const left={[Symbol.toPrimitive](hint){trace.push('left:'+hint);return 6}},right={[Symbol.toPrimitive](hint){trace.push('right:'+hint);return 2}};const expected=operators[op](left,right),before=trace.splice(0);const actual=nativeBinary(op,left,right);if(!Object.is(actual,expected)||JSON.stringify(trace)!==JSON.stringify(before))throw Error('operator hint/order');if(typeof left[Symbol.toPrimitive]!=='function')throw Error('borrowed operand released')}
        \\const cause={original:true};try{nativeBinary(2,{valueOf(){throw cause}},2);throw Error('missing original exception')}catch(error){if(error!==cause)throw error}
        \\for(const input of [0,-0,NaN,Infinity,'11',undefined,null,2n,9007199254740993n]){let value=input;const expected=++value;if(!Object.is(expected,nativeIncrement(input)))throw Error('native increment mismatch')}
    , "native-binary-operators", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    const dimension = c.JS_NewInt32(engine.context, 5);
    const limit = c.JS_NewInt32(engine.context, 4);
    const divisor = c.JS_NewInt32(engine.context, 8);
    const scaled = try image_math.scaleDimension(engine, dimension, limit, divisor);
    defer engine.freeValue(scaled);
    var numeric: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &numeric, scaled) < 0) return js.capture(engine);
    try std.testing.expectEqual(@as(f64, 3), numeric);
    const options = try engine.eval("({maxWidth:'4',maxHeight:3,maxBytes:5})", "image-dimension-options", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(options);
    var dimensions = try image_math.initialDimensions(engine, c.JS_NewInt32(engine.context, 8), c.JS_NewInt32(engine.context, 5), options);
    defer dimensions.deinit(engine);
    try std.testing.expect(c.JS_IsString(dimensions.width));
    if (c.JS_ToFloat64(engine.context, &numeric, dimensions.height) < 0) return js.capture(engine);
    try std.testing.expectEqual(@as(f64, 3), numeric);
    const quality_options = try engine.eval("({jpegQuality:85})", "image-quality-options", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(quality_options);
    const qualities = try image_math.qualitySteps(engine, quality_options);
    defer engine.freeValue(qualities);
    const encoded = try js.invoke(engine, qualities, "join", &.{});
    defer engine.freeValue(encoded);
    const text = try engine.toString(encoded);
    defer engine.gpa.free(text);
    try std.testing.expectEqualStrings("85,70,55,40", text);
    try std.testing.expect(try image_math.fitsEncodedSize(engine, 4, options));
    try std.testing.expectEqual(@as(u32, 4), try image_math.wasmDimension(engine, dimensions.width));
}
