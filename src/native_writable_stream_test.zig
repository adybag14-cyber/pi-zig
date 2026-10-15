//! Genuine Node24 public writable stream state-machine differential.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const writable = @import("extensions/native_writable_stream.zig");
const c = em.c;
fn gc(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    c.JS_RunGC(engine.runtime);
    return c.pi_js_undefined();
}
test "native WritableStream actual Node24 sink queues writers promises abort close backpressure and GC" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try writable.install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "gc", try engine.checked(c.JS_NewCFunction(engine.context, gc, "gc", 0)));
    const source = @embedFile("extensions/fixtures/writable-stream-node24.json");
    try sdk.put(engine, global, "writableStreamSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "writable-stream-node24.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/writable-stream-node24.input.txt") ++
        "\nif(writableStreamSource.nodeVersion!=='v24.14.0'||writableStreamSource.cases!==56||writableStreamRows.length!==56)throw Error('Genuine Node24 Source56 required');for(let i=0;i<writableStreamRows.length;i++)if(JSON.stringify(writableStreamRows[i])!==JSON.stringify(writableStreamSource.rows[i]))throw Error(JSON.stringify({case:i,actual:writableStreamRows[i],expected:writableStreamSource.rows[i]}));", "native-writable-stream-node24.mjs") catch |err| {
        std.debug.print("WritableStream: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    const released = try engine.eval("delete globalThis.writableStreamRows;delete globalThis.writableStreamSource;delete globalThis.gc;", "writable-stream-release.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(released);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
