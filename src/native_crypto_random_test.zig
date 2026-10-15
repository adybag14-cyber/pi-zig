const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const crypto = @import("extensions/native_crypto_random.zig");
const c = em.c;
fn detachFixture(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    // This caller-owned test adapter constructs the exact detached input state
    // observed after Node's structuredClone transfer. It does not measure or
    // claim qualification of a general structuredClone implementation.
    if (argc > 0) c.JS_DetachArrayBuffer(context, argv[0]);
    return c.pi_js_undefined();
}
fn install(engine: *em.Engine) !void {
    engine.native_io = std.testing.io;
    if (engine.dom_exception_class == 0) try @import("extensions/dom_exception.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "structuredClone", try engine.checked(c.JS_NewCFunction(engine.context, detachFixture, "structuredClone", 1)));
    try sdk.put(engine, global, "cryptoRandomAPI", try crypto.create(engine));
}
test "native secure Crypto matches33 original Node24 integer views diagnostics brand detach resize getters and shape observations" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/crypto-random-node24.json");
    try sdk.put(engine, global, "cryptoRandomSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "crypto-random-node24.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/crypto-random-node24.input.txt") ++
        "\nif(cryptoRandomRows.length!==33||cryptoRandomSource.rows.length!==33||cryptoRandomSource.nodeVersion!=='v24.14.0')throw Error('all33 pinned Node observations required');for(let i=0;i<33;i++)if(JSON.stringify(cryptoRandomRows[i])!==JSON.stringify(cryptoRandomSource.rows[i]))throw Error(JSON.stringify({case:i,actual:cryptoRandomRows[i],expected:cryptoRandomSource.rows[i]}));", "native-secure-crypto-node24-original.mjs") catch |err| {
        std.debug.print("Crypto Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native secure Crypto retained ordinary function rejects constructors and preserves thrown getter identity" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const prepared = try engine.evalModule("globalThis.keptRandom=cryptoRandomAPI.getRandomValues;globalThis.keptRandomHost=cryptoRandomAPI;delete globalThis.cryptoRandomAPI;export const ready=true;", "native-secure-crypto-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const result = try engine.evalModule(
        \\const bytes=new Uint8Array(32);if(keptRandom.call(keptRandomHost,bytes)!==bytes)throw Error('retained host');try{new keptRandom(bytes);throw Error('constructor accepted')}catch(e){if(e.code!=='ERR_INVALID_THIS')throw e;}const marker={},view=new Uint8Array(4);Object.defineProperty(view,'byteLength',{get(){throw marker}});try{keptRandom.call(keptRandomHost,view);throw Error('getter accepted')}catch(e){if(e!==marker)throw e;}delete globalThis.keptRandom;delete globalThis.keptRandomHost;export const done=true;
    , "native-secure-crypto-gc-complete.mjs");
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native secure Crypto every host allocation releases ordinary function native byte views and DOM error roots" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            install(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const a=new Uint8Array(32),b=new BigUint64Array(2);if(cryptoRandomAPI.getRandomValues(a)!==a||cryptoRandomAPI.getRandomValues(b)!==b)throw Error('secure ownership');export const proof=true;
            , "native-secure-crypto-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
