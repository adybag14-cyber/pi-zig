const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const attribution = @import("extensions/native_provider_attribution.zig");
const c = em.c;
fn setup(engine: *em.Engine, env: *std.process.Environ.Map) !void {
    engine.native_io = std.testing.io;
    try @import("extensions/native_process.zig").install(engine, std.testing.io, env, &.{"native-provider-attribution"});
    try @import("extensions/native_url.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "mergeProviderAttributionHeaders", try attribution.create(engine));
    try sdk.put(engine, global, "isInstallTelemetryEnabled", try attribution.createTelemetry(engine));
}
test "native SDK provider attribution matches96 genuine latest Source telemetry header merging host and getter cases" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var env: std.process.Environ.Map = .init(std.testing.allocator);
    defer env.deinit();
    try setup(engine, &env);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const source = @embedFile("extensions/fixtures/sdk-provider-attribution-e622.json");
    try sdk.put(engine, global, "attributionSource", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "sdk-provider-attribution-e622.json")));
    const observed = engine.evalModule(@embedFile("extensions/fixtures/sdk-provider-attribution-e622.input.txt") ++
        "\nif(attributionRows.length!==96||attributionSource.rows.length!==96)throw Error('96 original Source cases required');for(let i=0;i<96;i++)if(JSON.stringify(attributionRows[i])!==JSON.stringify(attributionSource.rows[i]))throw Error(JSON.stringify({case:i,actual:attributionRows[i],expected:attributionSource.rows[i]}));", "native-attribution-source.mjs") catch |err| {
        std.debug.print("Provider attribution Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(observed);
    c.JS_RunGC(engine.runtime);
}
test "native SDK provider attribution guest URL failures preserve original best effort behavior" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var env: std.process.Environ.Map = .init(std.testing.allocator);
    defer env.deinit();
    try setup(engine, &env);
    const generation = engine.native_allocation_generation;
    const result = try engine.evalModule(
        \\const original=globalThis.URL,marker=new InternalError('out of memory');marker.native_allocation_generation=99;globalThis.URL=function(){throw marker};try{const result=mergeProviderAttributionHeaders({provider:'custom',baseUrl:'https://other.invalid'},{getEnableInstallTelemetry:()=>true},'session');if(result!==undefined)throw Error('guest URL error did not retain Source fallback')}finally{globalThis.URL=original}export const proof=true;
    , "native-attribution-guest-error.mjs");
    engine.freeValue(result);
    try std.testing.expectEqual(generation, engine.native_allocation_generation);
}
test "native SDK provider attribution every native allocation failure remains fatal and releases header owner graph" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{});
            defer engine.deinit();
            var env: std.process.Environ.Map = .init(gpa);
            defer env.deinit();
            try setup(engine, &env);
            const generation = engine.native_allocation_generation;
            const result = engine.evalModule(
                \\const headers=mergeProviderAttributionHeaders({provider:'custom',baseUrl:'https://api.cloudflare.com/client/v4'},{getEnableInstallTelemetry:()=>true},'session',{x:'first'},{x:'second'});if(headers['User-Agent']!=='pi-coding-agent'||headers.x!=='second')throw Error('merged headers');const session=mergeProviderAttributionHeaders({provider:'opencode',baseUrl:'https://other.invalid'},{getEnableInstallTelemetry:()=>false},'fixture');if(session['x-opencode-session']!=='fixture')throw Error('session headers');export const proof=true;
            , "native-attribution-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
