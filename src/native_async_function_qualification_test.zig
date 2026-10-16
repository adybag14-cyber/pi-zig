//! Qualification-only composition; actual C and adapters are unchanged.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const c = em.c;
comptime {
    _ = @import("native_async_function_body_test.zig");
    _ = @import("native_async_generator_test.zig");
}
fn viewSpan(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return viewSpanBody(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
        return c.JS_ThrowInternalError(context, "Native span regression: %s", @as([*:0]const u8, @errorName(err)));
    };
}
fn viewSpanBody(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var offset: usize = 0;
    var length: usize = 0;
    var width: usize = 0;
    const backing = try scope.own(try engine.checked(c.JS_PiGetArrayBufferViewBuffer(engine.context, value, &offset, &length, &width)));
    const output = try scope.object();
    try scope.put(output, "backing", backing);
    try scope.put(output, "offset", c.JS_NewInt32(engine.context, @intCast(offset)));
    try scope.put(output, "length", c.JS_NewInt32(engine.context, @intCast(length)));
    try scope.put(output, "width", c.JS_NewInt32(engine.context, @intCast(width)));
    return c.JS_DupValue(engine.context, output);
}
fn gc(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(c.JS_GetRuntime(context));
    return c.pi_js_undefined();
}
test "native borrowed view span retains backing and tracks DataView typed RAB detach and brand" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bindFunction("borrowedViewSpan", viewSpan, 1);
    try engine.bindFunction("spanGC", gc, 0);
    const result = try engine.evalModule(
        \\const same=(span,backing,offset,length,width)=>{if(span.backing!==backing||span.offset!==offset||span.length!==length||span.width!==width)throw Error(JSON.stringify({offset:span.offset,length:span.length,width:span.width}))};const buffer=new ArrayBuffer(16);same(borrowedViewSpan(new Uint16Array(buffer,4,3)),buffer,4,6,2);same(borrowedViewSpan(new DataView(buffer,3,7)),buffer,3,7,1);let view=new Uint8Array(buffer,2,5);const retained=borrowedViewSpan(view);view=null;spanGC();new Uint8Array(retained.backing)[2]=19;if(new Uint8Array(buffer)[2]!==19)throw Error('backing detached or copied');const rab=new ArrayBuffer(16,{maxByteLength:32}),typed=new Uint16Array(rab,4),tracking=new DataView(rab,3),fixed=new DataView(rab,8,8);same(borrowedViewSpan(typed),rab,4,12,2);rab.resize(24);same(borrowedViewSpan(typed),rab,4,20,2);same(borrowedViewSpan(tracking),rab,3,21,1);rab.resize(6);let oob=false;try{borrowedViewSpan(fixed)}catch(e){oob=e instanceof TypeError}if(!oob)throw Error('OOB DataView accepted');let reads=0;for(const value of[{},new Proxy(new DataView(buffer),{get(){reads++;throw Error('proxy read')}})]){let rejected=false;try{borrowedViewSpan(value)}catch(e){rejected=e instanceof TypeError}if(!rejected)throw Error('counterfeit view accepted')}if(reads!==0)throw Error('proxy trap');const detached=new Uint8Array(new ArrayBuffer(4));detached.buffer.transfer();let rejected=false;try{borrowedViewSpan(detached)}catch(e){rejected=e instanceof TypeError}if(!rejected)throw Error('detached view accepted');export const done=true;
    , "native-async-qualification-borrowed-view-span.mjs");
    engine.freeValue(result);
}
