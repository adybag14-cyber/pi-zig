//! Existing engine/legacy checks plus private thin-dispatch recovery controls.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
comptime {
    _ = @import("extensions/engine.zig");
    _ = @import("native_highlight_legacy32_function_test.zig");
}

test "native Root463 dispatch ordinary constructors bound calls raw errors and GC retain VM semantics" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const result = try engine.eval(
        \\const token={},reason={raw:true};function Subject(value){if(value==='throw')throw reason;this.value=value;return undefined}function Alternate(){}const bound=Subject.bind(null,token);const a=new bound;if(a.value!==token||Object.getPrototypeOf(a)!==Subject.prototype)throw Error('bound constructor');const b=Reflect.construct(Subject,[token],Alternate);if(b.value!==token||Object.getPrototypeOf(b)!==Alternate.prototype)throw Error('ordinary new.target');const receiver={};if(Subject.call(receiver,token)!==undefined||receiver.value!==token)throw Error('ordinary receiver');const applied={};Reflect.apply(Subject,applied,[token]);if(applied.value!==token)throw Error('ordinary apply');let seen;try{Subject.call({},'throw')}catch(error){seen=error}if(seen!==reason)throw Error('ordinary raw error');globalThis.dispatchHeld={a,b,token,Subject,Alternate};
    , "root463-ordinary-dispatch.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
    const retained = try engine.eval("if(dispatchHeld.a.value!==dispatchHeld.token||Object.getPrototypeOf(dispatchHeld.b)!==dispatchHeld.Alternate.prototype)throw Error('ordinary constructor GC');delete globalThis.dispatchHeld;", "root463-ordinary-dispatch-gc.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(retained);
}

test "native Root463 dispatch ordinary VM stack overflow preserves recovery" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000, .stack_limit = 256 * 1024, .interrupt_budget = 1_000_000 });
    defer engine.deinit();
    try std.testing.expectError(error.JavaScriptException, engine.eval("(function recurse(){return 1+recurse()})()", "root463-ordinary-stack-overflow.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expect(engine.interrupts < engine.options.interrupt_budget);
    const value = try engine.eval("(()=>{function add(a,b){return a+b}return Reflect.apply(add,null,[20,22])})()", "root463-post-stack-recovery.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(value);
    var number: i32 = 0;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(engine.context, &number, value));
    try std.testing.expectEqual(@as(i32, 42), number);
}
