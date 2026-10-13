const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
fn setup(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    errdefer engine.deinit();
    engine.native_io = std.testing.io;
    const root = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const classes = try @import("extensions/native_chord_host.zig").classes(engine);
    defer engine.freeValue(classes.bindings);
    defer engine.freeValue(classes.exports);
    const api = try js.object(engine);
    defer engine.freeValue(api);
    try js.spreadInto(engine, api, classes.exports);
    inline for (.{ "Source", "Cell", "Derived", "isSource", "notReady" }) |name| try js.define(engine, api, name, try js.get(engine, classes.bindings, name));
    try js.define(engine, root, "nativeCellsApi", em.c.JS_DupValue(engine.context, api));
    return engine;
}
test "native Chord cells replay genuine latest Source full graph and negatives" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const original = @embedFile("extensions/fixtures/chord-cells-original-e622.json");
    const root = em.c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "cellsSource", try engine.checked(em.c.JS_ParseJSON(engine.context, original.ptr, original.len, "cells-original.json")));
    const result = engine.evalModule("const api=nativeCellsApi;\n" ++ @embedFile("extensions/fixtures/chord-cells-original-e622.input.txt") ++ "\nconst actual=chordCellsCases;if(actual.length!==cellsSource.cases.length)throw Error('Cell Source count');for(let i=0;i<actual.length;i++)if(JSON.stringify(actual[i])!==JSON.stringify(cellsSource.cases[i]))throw Error(JSON.stringify({case:i,actual:actual[i],expected:cellsSource.cases[i]}));", "chord-cells-source.mjs") catch |err| {
        std.debug.print("Native Chord cells Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
test "native Chord cells actual dependency callbacks survive explicit collection" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const started = try engine.evalModule(
        \\const api=nativeCellsApi,options={dev:true,report(error){throw error}},cell=new api.Cell('gc',{type:'object'},{n:1},()=>{},options),derived=new api.Derived('gc-derived',[cell],v=>v.n*3,options);derived.attach();const log=[];derived.subscribe(v=>log.push(v));globalThis.cellsPending={cell,derived,log};
    , "chord-cells-gc-start.mjs");
    engine.freeValue(started);
    em.c.JS_RunGC(engine.runtime);
    const finished = try engine.evalModule(
        \\const p=cellsPending;p.cell.change(null,d=>{d.n=2});if(p.derived.value!==6||JSON.stringify(p.log)!=='[3,6]')throw Error('lost dependency callback');p.derived.detach();delete globalThis.cellsPending;
    , "chord-cells-gc-finish.mjs");
    engine.freeValue(finished);
    em.c.JS_RunGC(engine.runtime);
}
test "native Chord cells construction atomic write and graph disposal all allocation failures" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try setup(gpa);
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            const result = engine.evalModule(
                \\const api=nativeCellsApi,options={dev:true,report(){}},cell=new api.Cell('allocation',{type:'object'},{n:1},()=>{},options),derived=new api.Derived('allocation-derived',[cell],v=>v.n*2,options);derived.attach();const values=[];derived.subscribe(v=>values.push(v));cell.change(null,d=>{d.n=2});if(cell.value.n!==2||derived.value!==4||JSON.stringify(values)!=='[2,4]')throw Error('allocation graph changed');derived.detach();
            , "chord-cells-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
