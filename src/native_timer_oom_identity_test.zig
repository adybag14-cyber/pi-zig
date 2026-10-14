const std = @import("std");
const em = @import("extensions/engine.zig");
const timers = @import("extensions/timers.zig");
const c = em.c;

fn exercise(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    timers.install(engine, std.testing.io) catch |err| return engine.nativeAllocationError(err, generation);
    const result = engine.evalModule(
        "globalThis.timerOomWeak=(()=>{const held={owned:'timer'};" ++
            "const timeout=setTimeout(value=>value,100000,held);if(typeof timeout!=='object'||!timeout.hasRef())throw Error('real timeout handle absent');clearTimeout(timeout);" ++
            "const interval=setInterval(()=>held,100000);if(typeof interval!=='object'||!interval.hasRef())throw Error('real interval handle absent');clearInterval(interval);" ++
            "return new WeakRef(held)})();" ++
            "const observed=await new Promise(resolve=>setTimeout((left,right)=>resolve(left+right),0,20,22));" ++
            "if(observed!==42)throw Error('real native timer callback arguments/promise lost');export const proof=true;",
        "native-timer-oom-identity.mjs",
    ) catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const released = engine.eval(
        "if(timerOomWeak.deref()!==undefined)throw Error('cleared native timer retained callback roots');delete globalThis.timerOomWeak;",
        "native-timer-oom-released.js",
        c.JS_EVAL_TYPE_GLOBAL,
    ) catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(released);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}

test "native timer OOM identity preserves real timeout interval callback arguments promise and GC release" {
    try exercise(std.testing.allocator);
}

test "native timer OOM identity releases every allocation failure through exact fresh VM exception tags" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "native-timer-oom-identity", exercise, .{});
}
