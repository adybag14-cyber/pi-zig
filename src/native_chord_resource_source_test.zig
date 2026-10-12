const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const resources = @import("extensions/native_chord_resources.zig");
const c = em.c;
fn setup(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 5000 });
    errdefer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/abort_signal.zig").install(engine);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "nativeResourceApi", try resources.exports(engine));
    return engine;
}
test "native Chord Resource actual19cb lifecycle Host-derived facade and error identity replay" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const original = @embedFile("extensions/fixtures/chord-resource-original-19cb.json");
    try js.define(engine, root, "resourceSource", try engine.checked(c.JS_ParseJSON(engine.context, original.ptr, original.len, "chord-resource-original-19cb.json")));
    const result = engine.evalModule("const api=nativeResourceApi;\n" ++ @embedFile("extensions/fixtures/chord-resource-original-19cb.input.txt") ++
        "\nif(chordResourceCases.length!==resourceSource.cases.length)throw Error('Chord Resource Source case count');for(let i=0;i<chordResourceCases.length;i++)if(JSON.stringify(chordResourceCases[i])!==JSON.stringify(resourceSource.cases[i]))throw Error(JSON.stringify({case:i,actual:chordResourceCases[i],expected:resourceSource.cases[i]}));", "chord-resource-source.mjs") catch |err| {
        std.debug.print("Native Chord Resource Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
test "native Chord Resource pending open and late close retain owner roots through collection" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const initial = try engine.evalModule(
        \\const{ResourceImpl,ResourceFacade}=nativeResourceApi;let release;const gate=new Promise(resolve=>release=resolve),value={alive:31},controller=new AbortController(),order=[];
        \\const resource=new ResourceImpl('retained',{open(){return gate},close(given){if(given!==value)throw Error('value identity lost')}},[]),facade=new ResourceFacade(resource,{inFactory:0});
        \\globalThis.resourcePending={release,facade,order,value,promise:resource.open(controller.signal,order)};
    , "chord-resource-gc-start.mjs");
    engine.freeValue(initial);
    c.JS_RunGC(engine.runtime);
    const completed = try engine.evalModule(
        \\const p=resourcePending;p.release(p.value);await p.promise;if(p.facade.value!==p.value||p.order.length!==1)throw Error('pending native resource roots lost');await p.order[0].close(p.order);if(p.order.length)throw Error('resource close did not retire acquisition');delete globalThis.resourcePending;
    , "chord-resource-gc-complete.mjs");
    engine.freeValue(completed);
    c.JS_RunGC(engine.runtime);
}
test "native Chord Resource class error and async owners release every induced allocation failure" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try setup(gpa);
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            const result = engine.evalModule(
                \\const{ResourceImpl,ResourceFacade,ChordError,isChordError}=nativeResourceApi;const r=new ResourceImpl('owned',{open(){return{v:1}},close(){}},[]),order=[],f=new ResourceFacade(r,{inFactory:0});
                \\try{f.value}catch(error){if(!isChordError(error,'not_ready'))throw error}await r.open(new AbortController().signal,order);if(f.value.v!==1)throw Error('resource changed');await r.close(order);const error=new ChordError('invalid','checked',{details:{n:1}});if(error.details.n!==1)throw Error('error detail lost');
            , "chord-resource-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
