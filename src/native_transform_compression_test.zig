//! Genuine Node24 comparison. This imports the real shared Body/Response graph;
//! the owning leaves must be integrated before a native qualification build.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const c = em.c;
fn install(engine: *em.Engine) !void {
    engine.native_io = std.testing.io;
    try @import("extensions/native_transform_stream.zig").install(engine);
    try @import("extensions/native_compression_stream.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const interfaces = try @import("extensions/native_web_platform.zig").prepare(&scope);
    try @import("extensions/native_web_response.zig").install(engine, interfaces);
    try @import("extensions/text_encoding.zig").install(engine);
}
test "native Transform and compression streams compare genuine Node24 standard graph and Chord browser pipeline" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const expected = @embedFile("extensions/fixtures/web-transform-compression-node24.json");
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "actual-node24-transform-compression.json"));
    defer engine.freeValue(source);
    const vectors = try engine.checked(c.JS_GetPropertyStr(engine.context, source, "vectors"));
    try sdk.put(engine, global, "codecVectors", vectors);
    try sdk.put(engine, global, "transformSource", c.JS_DupValue(engine.context, source));
    const result = engine.evalModule(@embedFile("extensions/fixtures/web-transform-compression-node24.input.txt") ++
        "\nif(transformSource.actualNode.version!=='v24.14.0'||transformSource.builtinCount!==368||webTransformCompressionRows.length!==66||transformSource.rows.length!==66)throw Error('Genuine actual Node24 Source66 required');for(let i=0;i<66;i++)if(JSON.stringify(webTransformCompressionRows[i])!==JSON.stringify(transformSource.rows[i]))throw Error(JSON.stringify({case:i,native:webTransformCompressionRows[i],source:transformSource.rows[i]}));", "native-transform-compression-node24.mjs") catch |err| {
        std.debug.print("Transform/Compression: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    const release = try engine.eval("delete globalThis.transformSource;delete globalThis.codecVectors;delete globalThis.webTransformCompressionRows;", "transform-release.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(release);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
test "native Transform retained controller and pending writes survive collector" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try @import("extensions/native_transform_stream.zig").install(engine);
    const prepared = try engine.evalModule("globalThis.keptTransform=new TransformStream({start(c){globalThis.keptController=c}});globalThis.keptWriter=keptTransform.writable.getWriter();globalThis.keptReader=keptTransform.readable.getReader();keptWriter.closed.catch(()=>{});keptReader.closed.catch(()=>{});globalThis.keptValue={id:42};globalThis.keptWrite=keptWriter.write(keptValue);export const ready=true;", "transform-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const done = try engine.evalModule("const first=await keptReader.read();await keptWrite;if(first.value!==keptValue)throw Error('Raw retained value identity');const closing=keptWriter.close();if(!(await keptReader.read()).done)throw Error('Actual readable close');await closing;for(const name of ['keptTransform','keptController','keptWriter','keptReader','keptValue','keptWrite'])delete globalThis[name];export const done=true;", "transform-gc-complete.mjs");
    engine.freeValue(done);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
