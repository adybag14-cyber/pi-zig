//! Prepared genuine original58 comparison and native ownership controls.
//! Expected JSON is deliberately absent until an authorized original capture.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const crypto = @import("extensions/native_node_crypto_hash.zig");
const c = em.c;
fn install(engine: *em.Engine) !void {
    try @import("extensions/node_buffer.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "nativeNodeCryptoSubject", try crypto.create(engine));
}
test "native node crypto SHA256 replays actual original58 observations" {
    const expected = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "src/extensions/fixtures/node-crypto-sha256-package.json", std.testing.allocator, .limited(2 * 1024 * 1024));
    defer std.testing.allocator.free(expected);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const terminated = try engine.gpa.dupeZ(u8, expected);
    defer engine.gpa.free(terminated);
    try js.define(engine, global, "originalCryptoExpected", try engine.checked(c.JS_ParseJSON(engine.context, terminated.ptr, expected.len, "actual-node24-crypto-sha256.json")));
    const input = @embedFile("extensions/fixtures/node-crypto-sha256-package.input.txt");
    var hash: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input, &hash, .{});
    const hex = std.fmt.bytesToHex(hash, .lower);
    try js.define(engine, global, "ownedCryptoInputSha256", try engine.checked(c.JS_NewStringLen(engine.context, &hex, hex.len)));
    const result = engine.evalModule(input ++
        \\if(originalCryptoExpected.runtime.version!=='v24.14.0'||originalCryptoExpected.runtime.executableSha256!=='63c259c81e5d472b5f11c8d506070130cb04a1ecf84b80377a34ed6ec9048088'||originalCryptoExpected.inputSha256!==ownedCryptoInputSha256||originalCryptoExpected.count!==58||nativeNodeCryptoObservation.count!==58)throw Error('Exact original Node/input/census authority required');
        \\for(let i=0;i<58;i++)if(JSON.stringify(nativeNodeCryptoObservation.rows[i])!==JSON.stringify(originalCryptoExpected.rows[i]))throw Error(JSON.stringify({index:i,actual:nativeNodeCryptoObservation.rows[i],original:originalCryptoExpected.rows[i]}));
    , "native-node-crypto-sha256-original-comparison.mjs") catch |err| { std.debug.print("SHA256 original comparison: {s}\n", .{engine.last_error orelse "no diagnostic"}); return err; };
    engine.freeValue(result);
}
test "native node crypto SHA256 retains independent opaque state and module roots through GC" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const prepared = try engine.evalModule(
        \\globalThis.keptNativeHash=nativeNodeCryptoSubject.createHash('sha256').update('a');globalThis.keptNativeUpdate=keptNativeHash.update;delete globalThis.nativeNodeCryptoSubject;
    , "native-node-crypto-sha256-retain-before-gc.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\if(keptNativeUpdate.call(keptNativeHash,'bc')!==keptNativeHash)throw Error('retained receiver identity');const hex=keptNativeHash.digest('hex');if(hex!=='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')throw Error('SHA256 abc standard vector/retained state');delete globalThis.keptNativeUpdate;delete globalThis.keptNativeHash;
    , "native-node-crypto-sha256-retain-after-gc.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native node crypto SHA256 explicitly rejects algorithms and options beyond package usage" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const result = try engine.evalModule(
        \\for(const [args,code] of [[['md5'],'PI_UNSUPPORTED_CRYPTO_ALGORITHM'],[['sha256',{}],'PI_UNSUPPORTED_CRYPTO_OPTIONS'],[['sha256',null],'PI_UNSUPPORTED_CRYPTO_OPTIONS']]){let rejected=false;try{nativeNodeCryptoSubject.createHash(...args)}catch(error){rejected=error.code===code}if(!rejected)throw Error('unsupported SHA256 contract accepted')}
    , "native-node-crypto-sha256-explicit-scope.mjs");
    engine.freeValue(result);
}
test "native node crypto SHA256 every Zig allocation releases partial owner hash byte and encoding roots" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            install(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const a=nativeNodeCryptoSubject.createHash('sha256').update('abc'),b=nativeNodeCryptoSubject.createHash('sha256').update(new DataView(new Uint8Array([97,98,99]).buffer));if(a.digest('hex')!==b.digest('hex'))throw Error('real byte/string hash states');nativeNodeCryptoSubject.createHash('sha256').update('é🌍').digest();
            , "native-node-crypto-sha256-zig-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}

fn throwOwnedAllocation(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemory();
    const reason = c.JS_GetException(context);
    const global = c.JS_GetGlobalObject(context);
    defer engine.freeValue(global);
    if (c.JS_DefinePropertyValueStr(context, global, "ownedCryptoFatalReason", c.JS_DupValue(context, reason), c.JS_PROP_C_W_E) < 0) {
        engine.freeValue(reason);
        return c.JS_Throw(context, c.JS_GetException(context));
    }
    return c.JS_Throw(context, reason);
}
test "native node crypto SHA256 retains exact fresh native allocation identity through digest coercion" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "raiseOwnedCryptoAllocation", try engine.checked(c.JS_NewCFunction(engine.context, throwOwnedAllocation, "raiseOwnedCryptoAllocation", 0)));
    try std.testing.expectError(error.JavaScriptException, engine.evalModule(
        \\globalThis.cryptoGuestCaught=false;const hash=nativeNodeCryptoSubject.createHash('sha256');try{hash.digest({toString:raiseOwnedCryptoAllocation})}catch{globalThis.cryptoGuestCaught=true}
    , "native-node-crypto-sha256-fresh-allocation-identity.mjs"));
    const original = try js.get(engine, global, "ownedCryptoFatalReason");
    defer engine.freeValue(original);
    const actual = engine.captured_exception orelse return error.MissingNativeCryptoAllocationReason;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, actual));
    try std.testing.expect(c.JS_IsUncatchableError(actual));
    const caught = try js.get(engine, global, "cryptoGuestCaught");
    defer engine.freeValue(caught);
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToBool(engine.context, caught));
}
