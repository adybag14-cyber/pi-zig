//! Focused retained-identity/GC control for the complete real stream assembler.
//! Authored only; requires the actual Readable/Writable leaves and zlib link.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const transform = @import("extensions/native_transform_stream.zig");
const compression = @import("extensions/native_compression_stream.zig");
const c = em.c;
test "native stream captured constructor exports survive globals prototype mutation and collection" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try compression.install(engine);
    const prepared = try engine.evalModule(
        \\globalThis.originalStreamConstructors=[TransformStream,TransformStreamDefaultController,CompressionStream,DecompressionStream];TransformStreamDefaultController.prototype.constructor=function guestController(){};globalThis.TransformStream=function guestTransform(){};globalThis.TransformStreamDefaultController=function guestControllerGlobal(){};globalThis.CompressionStream=function guestCompression(){};globalThis.DecompressionStream=function guestDecompression(){};export const ready=true;
    , "stream-exports-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "capturedTransform", try transform.exports(engine));
    try sdk.put(engine, global, "capturedCompression", try compression.exports(engine));
    try sdk.put(engine, global, "nativeIdentityTransform", try transform.createIdentityNative(engine));
    const checked = try engine.evalModule(
        \\const actual=[capturedTransform.TransformStream,capturedTransform.TransformStreamDefaultController,capturedCompression.CompressionStream,capturedCompression.DecompressionStream];if(actual.some((v,i)=>v!==originalStreamConstructors[i]))throw Error('Original captured constructor identity lost');const marker={id:42},t=nativeIdentityTransform,reader=t.readable.getReader(),writer=t.writable.getWriter();reader.closed.catch(()=>{});writer.closed.catch(()=>{});const pending=reader.read();await writer.write(marker);if((await pending).value!==marker)throw Error('Identity transform changed raw value');const closing=writer.close();if(!(await reader.read()).done)throw Error('Identity stream close');await closing;for(const name of ['originalStreamConstructors','capturedTransform','capturedCompression','nativeIdentityTransform'])delete globalThis[name];export const done=true;
    , "stream-exports-gc-complete.mjs");
    engine.freeValue(checked);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
