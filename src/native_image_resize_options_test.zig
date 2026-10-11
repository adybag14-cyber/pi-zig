const std = @import("std");
const js = @import("extensions/native_js_values.zig");
const c = js.c;
const options = @import("extensions/native_image_resize_options.zig");
test "native image worker serialized options retain independent cycles and undefined values" {
    const source = try js.Engine.init(std.testing.allocator, .{});
    defer source.deinit();
    const target = try js.Engine.init(std.testing.allocator, .{});
    defer target.deinit();
    const value = try source.eval("(()=>{const value={maxWidth:undefined,nested:{value:4}};value.self=value;return value})()", "image-options-source", c.JS_EVAL_TYPE_GLOBAL);
    defer source.freeValue(value);
    var serialized = try options.serializeForWorker(source, value);
    defer serialized.deinit(std.testing.allocator);
    const cloned = try serialized.read(target);
    defer target.freeValue(cloned);
    const global = c.JS_GetGlobalObject(target.context);
    defer target.freeValue(global);
    try js.define(target, global, "clonedOptions", c.JS_DupValue(target.context, cloned));
    const result = try target.eval("if(clonedOptions.self!==clonedOptions||!Object.hasOwn(clonedOptions,'maxWidth')||clonedOptions.maxWidth!==undefined||clonedOptions.nested.value!==4)throw Error('worker option graph');clonedOptions.nested.value=9", "image-options-target", c.JS_EVAL_TYPE_GLOBAL);
    target.freeValue(result);
    const nested = try js.get(source, value, "nested");
    defer source.freeValue(nested);
    const original = try js.get(source, nested, "value");
    defer source.freeValue(original);
    var number: i32 = 0;
    if (c.JS_ToInt32(source.context, &number, original) < 0) return js.capture(source);
    try std.testing.expectEqual(@as(i32, 4), number);
}
fn spread(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return options.spreadDefaults(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        return engine.throwNativeOutOfMemory();
    };
}
fn clone(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return options.cloneForWorker(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        return engine.throwNativeOutOfMemory();
    };
}
test "native image worker option clone and fallback preserve actual getter order and undefined" {
    const engine = try js.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "nativeImageSpread", try engine.checked(c.JS_NewCFunction(engine.context, spread, "nativeImageSpread", 1)));
    try js.define(engine, global, "nativeImageClone", try engine.checked(c.JS_NewCFunction(engine.context, clone, "nativeImageClone", 1)));
    const result = try engine.eval(
        \\const calls=[];const original={get maxWidth(){calls.push('maxWidth');return 4},get maxHeight(){calls.push('maxHeight');return 3}};
        \\const copied=nativeImageClone(original),merged=nativeImageSpread(copied);
        \\if(JSON.stringify(calls)!=='["maxWidth","maxHeight"]'||merged.maxWidth!==4||merged.maxHeight!==3||merged.maxBytes!==4718592||merged.jpegQuality!==80)throw Error('clone option order');
        \\const own=nativeImageSpread({maxWidth:undefined});if(!Object.hasOwn(own,'maxWidth')||own.maxWidth!==undefined)throw Error('undefined replaced by default');
        \\const cause={original:true},failures=[];const rejected={get maxWidth(){failures.push('maxWidth');throw cause}};
        \\try{nativeImageClone(rejected)}catch(error){if(error!==cause)throw Error('clone cause identity');try{nativeImageSpread(rejected)}catch(fallback){if(fallback!==cause)throw Error('fallback cause identity')}}
        \\if(JSON.stringify(failures)!=='["maxWidth","maxWidth"]')throw Error('fallback getter count');
    , "native-image-options", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
}
