//! Complete immutable genuine Node24 Body176 packet over the real native graph.
//! This is an independent next target; no component success substitutes for it.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const c = em.c;
var gc_calls: usize = 0;
fn collect(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(em.Engine.fromContext(context.?).runtime);
    gc_calls += 1;
    return c.pi_js_undefined();
}
test "Web Body176 complete genuine constructors descriptors consumers streams signals and real GC" {
    gc_calls = 0;
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10_000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("timers.zig").install(engine, std.testing.io);
    try @import("native_web_fetch.zig").install(engine);
    try engine.bindFunction("nativeCollectFullBodyFixture", collect, 0);
    const initialized = try engine.eval(
        \\globalThis.collectWebBodyGarbage=async()=>{for(let i=0;i<3;i++){await new Promise(resolve=>setTimeout(resolve,0));nativeCollectFullBodyFixture()}await new Promise(resolve=>setTimeout(resolve,0))};
    , "full-body-actual-native-gc-adapter.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(initialized);
    const original = @embedFile("fixtures/web-body-node24.json");
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "originalFullBodyPacket", try engine.checked(c.JS_ParseJSON(engine.context, original.ptr, original.len, "genuine-node24-Body176.json")));
    const pending = engine.evalModule(@embedFile("fixtures/web-body-node24.input.txt") ++
        \\
        \\if(originalFullBodyPacket.rows.length!==176||webBodyRows.length!==176||new Set(webBodyRows.map(row=>row.name)).size!==176)throw Error('Complete Body176 inventory mismatch');
        \\const mismatches=[];for(let i=0;i<176;i++){const actual=webBodyRows[i],expected=originalFullBodyPacket.rows[i];if(JSON.stringify(actual)!==JSON.stringify(expected))mismatches.push({index:i,actual,expected})}
        \\if(mismatches.length)throw Error(JSON.stringify({mapped:176,mismatches}));
    , "genuine-Body176-complete-native-projection.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Full Body176: {s}\n", .{message});
        return err;
    };
    defer engine.freeValue(pending);
    const settled = engine.awaitValue(pending) catch |err| {
        if (engine.last_error) |message| std.debug.print("Full Body176: {s}\n", .{message});
        return err;
    };
    engine.freeValue(settled);
    try std.testing.expectEqual(@as(usize, 6), gc_calls);
    c.JS_RunGC(engine.runtime);
}
