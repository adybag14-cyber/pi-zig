const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const c = em.c;
fn setup(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{});
    errdefer engine.deinit();
    engine.native_io = std.testing.io;
    const api = try js.object(engine);
    defer engine.freeValue(api);
    try js.define(engine, api, "Clone", try @import("extensions/native_chord_clone.zig").function(engine));
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "nativeChordCloneApi", c.JS_DupValue(engine.context, api));
    return engine;
}
test "native Chord clone original TypeBox SystemClone values descriptors iterators and guards" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const original = @embedFile("extensions/fixtures/chord-clone-original-19cb.json");
    try js.define(engine, root, "cloneSource", try engine.checked(c.JS_ParseJSON(engine.context, original.ptr, original.len, "chord-clone-original-19cb.json")));
    const result = engine.evalModule("const api=nativeChordCloneApi;\n" ++ @embedFile("extensions/fixtures/chord-clone-original-19cb.input.txt") ++
        "\nif(chordCloneCases.length!==cloneSource.cases.length)throw Error('Chord clone Source case count');for(let i=0;i<chordCloneCases.length;i++)if(JSON.stringify(chordCloneCases[i])!==JSON.stringify(cloneSource.cases[i]))throw Error(JSON.stringify({case:i,actual:chordCloneCases[i],expected:cloneSource.cases[i]}));", "chord-clone-source.mjs") catch |err| {
        std.debug.print("Native Chord clone Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
test "native Chord clone retained descriptors and exotic containers survive callback collection" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const prepared = try engine.evalModule(
        \\const value={'~kind':'Object',map:new Map([[{key:1},new Set([{value:[1]}])]])};Object.defineProperty(value,'metadata',{value:{retained:true}});globalThis.cloneRetained=nativeChordCloneApi.Clone(value);
    , "chord-clone-gc-start.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const checked = try engine.evalModule(
        \\const r=cloneRetained,[[key,set]]=r.map,[value]=set;if(key.key!==1||value.value[0]!==1||r.metadata.retained!==true||Object.getOwnPropertyDescriptor(r,'metadata').enumerable)throw Error('clone ownership lost');delete globalThis.cloneRetained;
    , "chord-clone-gc-end.mjs");
    engine.freeValue(checked);
    c.JS_RunGC(engine.runtime);
}
test "native Chord clone every native allocation failure releases active traversals and iterators" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try setup(gpa);
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            const result = engine.evalModule(
                \\const value={'~kind':'Object',data:[{x:1},,new Uint8Array([1,2])],map:new Map([[{key:1},new Set([{value:2}])]]),regexp:/a/gi};Object.defineProperty(value,'hidden',{value:{h:1}});const result=nativeChordCloneApi.Clone(value);if(result===value||result.data[0]===value.data[0]||1 in result.data||result.hidden===value.hidden||result.map===value.map)throw Error('clone result changed');
            , "chord-clone-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
