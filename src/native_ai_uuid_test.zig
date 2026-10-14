const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;
fn setup(engine: *em.Engine) !void {
    try @import("extensions/native_bigint_host.zig").install(engine);
    // Caller-owned deterministic WebCrypto dependency. Qualification of the
    // production global Crypto host is separate from this original UUID body.
    const prepared = try engine.eval("globalThis.crypto={getRandomValues(bytes){for(let i=0;i<bytes.length;i++)bytes[i]=i*17&255;return bytes;}}", "uuid-caller-random.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(prepared);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "uuidAPI", try @import("extensions/native_ai_uuid.zig").create(engine));
}
test "native AI UUID matches26 original timestamp sequence hooks coercion and function observations" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try setup(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/ai-uuid-1692.json");
    try sdk.put(engine, global, "uuidSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "ai-uuid-1692.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/ai-uuid-1692.input.txt") ++
        "\nif(uuidRows.length!==26||uuidSource.rows.length!==26)throw Error('all26 required');for(let i=0;i<26;i++)if(JSON.stringify(uuidRows[i])!==JSON.stringify(uuidSource.rows[i]))throw Error(JSON.stringify({case:i,actual:uuidRows[i],expected:uuidSource.rows[i]}));", "native-ai-uuid-source.mjs") catch |err| {
        std.debug.print("UUID Source: {s}\n", .{engine.last_error orelse "none"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native AI UUID retained module state survives collection and remains independent of another module" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try setup(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "uuidOther", try @import("extensions/native_ai_uuid.zig").create(engine));
    const prepared = try engine.evalModule(
        \\globalThis.uuidKept=uuidAPI;delete globalThis.uuidAPI;globalThis.uuidBefore=uuidKept(100);export const prepared=true;
    , "native-ai-uuid-gc-prepare.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\const after=uuidKept(100),other=uuidOther(1);if(!(uuidBefore<after)||other.slice(0,13)!=='00000000-0001'||after[14]!=='7'||!['8','9','a','b'].includes(after[19]))throw Error('UUID module state');delete globalThis.uuidKept;delete globalThis.uuidBefore;delete globalThis.uuidOther;export const completed=true;
    , "native-ai-uuid-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native AI UUID every host allocation failure releases module state typed bytes callbacks and format roots" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            setup(engine) catch |err| return engine.nativeAllocationError(err, generation);
            const result = engine.evalModule(
                \\const a=uuidAPI(100),b=uuidAPI(100),c=uuidAPI(0xffffffffffff);if(!(a<b)||!c.startsWith('ffffffff-ffff-7')||a.length!==36)throw Error('UUID complete graph');export const proof=true;
            , "native-ai-uuid-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
