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
    try js.define(engine, root, "nativeApplyApi", try js.get(engine, classes.bindings, "DeltaCodec"));
    return engine;
}
test "native Chord apply genuine Source34cases including23negative path and descriptor transactions" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const original = @embedFile("extensions/fixtures/chord-apply-original-e622.json");
    const root = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "applySource", try engine.checked(em.c.JS_ParseJSON(engine.context, original.ptr, original.len, "apply-original.json")));
    const result = engine.evalModule("const api=nativeApplyApi;\n" ++ @embedFile("extensions/fixtures/chord-apply-original-e622.input.txt") ++ "\nconst actual=chordApplyCases;if(actual.length!==applySource.cases.length)throw Error('apply Source count');for(let i=0;i<actual.length;i++)if(JSON.stringify(actual[i])!==JSON.stringify(applySource.cases[i]))throw Error(JSON.stringify({case:i,actual:actual[i],expected:applySource.cases[i]}));", "chord-apply-source.mjs") catch |err| {
        std.debug.print("Native Chord apply Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
test "native Chord apply retained immutable revisions preserve transferred paths through GC" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const started = try engine.evalModule(
        \\const api=nativeApplyApi,base={xs:[{n:1}],keep:{n:2}},item={n:3},next=api.applyImmutable(base,[['p',['xs'],1,0,[item]],['s',['xs',0,'n'],4]]);globalThis.pendingApply={base,item,next};
    , "chord-apply-gc-start.mjs");
    engine.freeValue(started);
    em.c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\const p=pendingApply;if(p.base.xs[0].n!==1||p.next.xs[0].n!==4||p.next.xs[1]!==p.item||p.next.keep!==p.base.keep)throw Error('apply graph lost');delete globalThis.pendingApply;
    , "chord-apply-gc-finish.mjs");
    engine.freeValue(completed);
    em.c.JS_RunGC(engine.runtime);
}
test "native Chord apply immutable mutable error and descriptor graph every induced allocation failure" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try setup(gpa);
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            const result = engine.evalModule(
                \\const api=nativeApplyApi,base={xs:[{n:1}],keep:{n:2}},item={n:3},next=api.applyImmutableBatches(base,[[['p',['xs'],1,0,[item]]],[['s',['xs',0,'n'],4],['s',['other'],true]]]);if(base.xs[0].n!==1||next.xs[0].n!==4||next.xs[1]!==item||next.keep!==base.keep)throw Error('apply allocation changed');api.apply(next,[['d',['xs',0]]]);if(next.xs[0]!==item)throw Error('mutable allocation changed');let error;try{api.applyImmutable({},[['s',['missing','n'],1]])}catch(value){error=value}if(!(error instanceof api.PathError)||JSON.stringify(error.path)!=='["missing"]')throw error??Error('path error absent');
            , "chord-apply-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
