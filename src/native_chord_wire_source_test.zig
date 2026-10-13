const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
fn setup(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    errdefer engine.deinit();
    engine.native_io = std.testing.io;
    const classes = try @import("extensions/native_chord_host.zig").classes(engine);
    defer engine.freeValue(classes.bindings);
    defer engine.freeValue(classes.exports);
    const api = try js.get(engine, classes.bindings, "Wire");
    defer engine.freeValue(api);
    try js.define(engine, api, "ChordError", try js.get(engine, classes.exports, "ChordError"));
    const root = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "nativeWireApi", em.c.JS_DupValue(engine.context, api));
    return engine;
}
test "native Chord wire genuine Source frame schemas error vocabulary and metadata" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const original = @embedFile("extensions/fixtures/chord-wire-original-e622.json");
    const root = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "wireSource", try engine.checked(em.c.JS_ParseJSON(engine.context, original.ptr, original.len, "wire-original.json")));
    const result = engine.evalModule("const api=nativeWireApi;\n" ++ @embedFile("extensions/fixtures/chord-wire-original-e622.input.txt") ++ "\nconst actual=chordWireCases;if(actual.length!==wireSource.cases.length)throw Error('wire Source count');for(let i=0;i<actual.length;i++)if(JSON.stringify(actual[i])!==JSON.stringify(wireSource.cases[i]))throw Error(JSON.stringify({case:i,actual:actual[i],expected:wireSource.cases[i]}));", "chord-wire-source.mjs") catch |err| {
        std.debug.print("Native Chord wire Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    em.c.JS_RunGC(engine.runtime);
}
test "native Chord wire actual schema error graph every induced allocation failure" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try setup(gpa);
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            const result = engine.evalModule(
                \\const api=nativeWireApi,error=new api.ChordError('invalid','bad',{reason:'state'}),wire=api.toWireError(error),round=api.fromWireError(wire);if(!api.isFrame({t:'gone',id:1,error:wire})||api.isFrame({t:'retire',epoch:0})||round.message!=='invalid/state: bad'||!(round instanceof api.ChordError))throw Error('wire allocation changed');
            , "chord-wire-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
            em.c.JS_RunGC(engine.runtime);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
