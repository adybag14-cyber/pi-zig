const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const crypto = @import("extensions/native_web_crypto.zig");
const c = em.c;
fn detachFixture(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    // Caller-owned fixture adapter creates the same detached input state as
    // Node structuredClone transfer; it does not qualify structuredClone.
    if (argc > 0) c.JS_DetachArrayBuffer(context, argv[0]);
    return c.pi_js_undefined();
}
fn install(engine: *em.Engine) !void {
    engine.native_io = std.testing.io;
    try crypto.install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "structuredClone", try engine.checked(c.JS_NewCFunction(engine.context, detachFixture, "structuredClone", 1)));
}
test "native WebCrypto actual Node24 digest random UUID brands descriptors getters and detached buffers" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const source = @embedFile("extensions/fixtures/web-crypto-node24.json");
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "webCryptoSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "web-crypto-node24.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/web-crypto-node24.input.txt") ++
        "\nif(webCryptoSource.nodeVersion!=='v24.14.0'||webCryptoRows.length!==webCryptoSource.rows.length)throw Error('genuine source observation count required');for(let i=0;i<webCryptoRows.length;i++)if(JSON.stringify(webCryptoRows[i])!==JSON.stringify(webCryptoSource.rows[i]))throw Error(JSON.stringify({case:i,actual:webCryptoRows[i],expected:webCryptoSource.rows[i]}));", "native-webcrypto-node24.mjs") catch |err| {
        std.debug.print("WebCrypto: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native WebCrypto retained digest and crypto survive GC and intrinsic Promise mutations" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const prepared = try engine.evalModule("globalThis.keptCrypto=crypto;globalThis.keptSubtle=crypto.subtle;globalThis.keptDigest=crypto.subtle.digest;delete globalThis.crypto;delete globalThis.Crypto;delete globalThis.SubtleCrypto;export const ready=true;", "native-webcrypto-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const result = try engine.evalModule(
        \\const original=Promise;globalThis.Promise=function(){throw Error('guest Promise')};const data=new Uint8Array([97,98,99]);const result=await keptDigest.call(keptSubtle,'SHA-256',data);if(Array.from(new Uint8Array(result),x=>x.toString(16).padStart(2,'0')).join('')!=='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')throw Error('retained digest');if(keptCrypto.getRandomValues(data)!==data)throw Error('retained random');globalThis.Promise=original;delete globalThis.keptCrypto;delete globalThis.keptSubtle;delete globalThis.keptDigest;export const done=true;
    , "native-webcrypto-gc-complete.mjs");
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
