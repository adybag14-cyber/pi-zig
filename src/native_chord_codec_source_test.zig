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
    const root = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "nativeCodecApi", try js.get(engine, classes.bindings, "DeltaCodec"));
    return engine;
}
test "native Chord codec genuine Source41cases including37negative dictionary and wire transactions" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const original = @embedFile("extensions/fixtures/chord-codec-original-e622.json");
    const root = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "codecSource", try engine.checked(em.c.JS_ParseJSON(engine.context, original.ptr, original.len, "codec-original.json")));
    const result = engine.evalModule("const api=nativeCodecApi;\n" ++ @embedFile("extensions/fixtures/chord-codec-original-e622.input.txt") ++ "\nconst actual=chordCodecCases;if(actual.length!==codecSource.cases.length)throw Error('codec Source count');for(let i=0;i<actual.length;i++)if(JSON.stringify(actual[i])!==JSON.stringify(codecSource.cases[i]))throw Error(JSON.stringify({case:i,actual:actual[i],expected:codecSource.cases[i]}));", "chord-codec-source.mjs") catch |err| {
        std.debug.print("Native Chord codec Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
test "native Chord codec stream dictionaries retain path identities through explicit GC" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const started = try engine.evalModule(
        \\const api=nativeCodecApi,encoder=api.encoder(),decoder=api.decoder(),path=['n'];decoder.decode(encoder.encode([['s',path,1]]));decoder.decode(encoder.encode([['s',path,2]]));globalThis.pendingCodec={encoder,decoder,path};
    , "chord-codec-gc-start.mjs");
    engine.freeValue(started);
    em.c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\const p=pendingCodec,wire=p.encoder.encode([['s',p.path,3]]),decoded=p.decoder.decode(wire);if(JSON.stringify(wire)!=='[["s",0,3]]'||decoded[0][1]!==p.path||decoded[0][2]!==3)throw Error('codec graph lost');delete globalThis.pendingCodec;
    , "chord-codec-gc-finish.mjs");
    engine.freeValue(completed);
    em.c.JS_RunGC(engine.runtime);
}
test "native Chord codec constructors validation errors and streams release every induced allocation failure" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try setup(gpa);
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            const result = engine.evalModule(
                \\const api=nativeCodecApi,encoder=api.encoder(),decoder=api.decoder(),first=decoder.decode(encoder.encode([['s',['n'],1],['t',['n'],0]])),second=decoder.decode(encoder.encode([['s',['n'],2]]));if(first[0][1]!==first[1][1]||second[0][2]!==2)throw Error('codec allocation changed');let error;try{decoder.decode([['s',['__proto__'],true]])}catch(value){error=value}if(!(error instanceof api.UnsafePathError)||error.segment!=='__proto__')throw error??Error('missing path error');
            , "chord-codec-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
