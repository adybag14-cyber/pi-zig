const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const c = em.c;
fn setup(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{});
    errdefer engine.deinit();
    engine.native_io = std.testing.io;
    const api = try @import("extensions/native_chord_normalization.zig").exports(engine);
    defer engine.freeValue(api);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "nativeChordEvaluatorApi", c.JS_DupValue(engine.context, api));
    return engine;
}
test "native Chord evaluator original625 Compare Narrow pairs preserve TypeBox algebra modifiers and aliases" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const original = @embedFile("extensions/fixtures/chord-evaluate-original-19cb.json");
    try js.define(engine, root, "evaluatorSource", try engine.checked(c.JS_ParseJSON(engine.context, original.ptr, original.len, "chord-evaluate-original-19cb.json")));
    const result = engine.evalModule("const api=nativeChordEvaluatorApi;\n" ++ @embedFile("extensions/fixtures/chord-evaluate-original-19cb.input.txt") ++
        "\nif(JSON.stringify(chordEvaluateAxes)!==JSON.stringify(evaluatorSource.axes))throw Error(JSON.stringify({axes:chordEvaluateAxes,expected:evaluatorSource.axes}));if(chordEvaluateCases.length!==evaluatorSource.cases.length)throw Error('evaluator Source case count');for(let i=0;i<chordEvaluateCases.length;i++)if(JSON.stringify(chordEvaluateCases[i])!==JSON.stringify(evaluatorSource.cases[i]))throw Error(JSON.stringify({case:i,actual:chordEvaluateCases[i],expected:evaluatorSource.cases[i]}));", "chord-evaluator-source.mjs") catch |err| {
        std.debug.print("Native Chord evaluator Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
test "native Chord evaluator original11 normalization Intersect deferred Pick Required Partial Record and strict inputs" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const original = @embedFile("extensions/fixtures/chord-normalization-workers-original-19cb.json");
    try js.define(engine, root, "normalizationEvaluatorSource", try engine.checked(c.JS_ParseJSON(engine.context, original.ptr, original.len, "chord-normalization-workers-original-19cb.json")));
    const result = engine.evalModule("const api=nativeChordEvaluatorApi;\n" ++ @embedFile("extensions/fixtures/chord-normalization-evaluator-original-19cb.input.txt") ++
        "\nconst expected=normalizationEvaluatorSource.evaluator_cases;if(chordNormalizationEvaluatorCases.length!==expected.length)throw Error('normalization evaluator Source case count');for(let i=0;i<chordNormalizationEvaluatorCases.length;i++)if(JSON.stringify(chordNormalizationEvaluatorCases[i])!==JSON.stringify(expected[i]))throw Error(JSON.stringify({case:i,actual:chordNormalizationEvaluatorCases[i],expected:expected[i]}));", "chord-normalization-evaluator-source.mjs") catch |err| {
        std.debug.print("Native Chord normalization evaluator Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
test "native Chord evaluator actual deferred schema remains live across owner collection" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const prepared = try engine.evalModule(
        \\const{Type:T}=nativeChordEvaluatorApi;globalThis.evaluatorRetained={context:{Base:T.Object({x:T.Number({default:4})})},schema:T.Intersect([T.PickDeferred(T.Ref('Base'),T.Literal('x')),T.Object({y:T.String({default:'y'})})])};
    , "chord-evaluator-gc-start.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const checked = try engine.evalModule(
        \\const r=evaluatorRetained,value=nativeChordEvaluatorApi.Default(r.context,r.schema,{});if(JSON.stringify(value)!=='{"x":4,"y":"y"}')throw Error('evaluator retained context/schema');delete globalThis.evaluatorRetained;
    , "chord-evaluator-gc-end.mjs");
    engine.freeValue(checked);
    c.JS_RunGC(engine.runtime);
}
test "native Chord evaluator allocations unwind real deferred instantiation composite default and preprocessing" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try setup(gpa);
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            const result = engine.evalModule(
                \\const{Type:T,Default,Clean}=nativeChordEvaluatorApi,context={Base:T.Object({x:T.Number({default:4})})},schema=T.Intersect([T.PickDeferred(T.Ref('Base'),T.Literal('x')),T.Object({y:T.String({default:'y'})})]),value=Clean(context,schema,Default(context,schema,{}));if(JSON.stringify(value)!=='{"x":4,"y":"y"}')throw Error('evaluator allocation result');
            , "chord-evaluator-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
