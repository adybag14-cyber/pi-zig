const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const workers = @import("extensions/native_chord_normalization_workers.zig");
const c = em.c;
fn invoke(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    if (args.len != 2 and args.len != 3) {
        const message = try engine.checked(c.JS_NewString(engine.context, "Invalid Arguments"));
        defer engine.freeValue(message);
        const failure = try js.builtin(engine, "Error", &.{message});
        return engine.checked(c.JS_Throw(engine.context, failure));
    }
    var operation: i32 = undefined;
    if (c.JS_ToInt32(engine.context, &operation, values[0]) < 0) return js.capture(engine);
    const context = if (args.len == 3) c.JS_DupValue(engine.context, args[0]) else try js.object(engine);
    defer engine.freeValue(context);
    return if (operation == 0) @import("extensions/native_chord_normalization.zig").defaults(engine, context, args[args.len - 2], args[args.len - 1]) else @import("extensions/native_chord_normalization.zig").clean(engine, context, args[args.len - 2], args[args.len - 1]);
}
fn setup(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{});
    errdefer engine.deinit();
    engine.native_io = std.testing.io;
    const api = try js.object(engine);
    defer engine.freeValue(api);
    inline for (.{ "Default", "Clean" }, 0..) |name, index| try js.define(engine, api, name, try @import("extensions/native_node_function.zig").create(engine, name, 0, invoke, &.{c.JS_NewInt32(engine.context, @intCast(index))}));
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    // Test-only bindings: no public Value.Default/Clean or Chord normalize.
    try js.define(engine, root, "nativeChordNormalizationWorkers", c.JS_DupValue(engine.context, api));
    return engine;
}
test "native Chord normalization workers original structural defaults cleanup refs and union iterators" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const original = @embedFile("extensions/fixtures/chord-normalization-workers-original-19cb.json");
    try js.define(engine, root, "normalizationSource", try engine.checked(c.JS_ParseJSON(engine.context, original.ptr, original.len, "chord-normalization-workers-original-19cb.json")));
    const result = engine.evalModule("const api=nativeChordNormalizationWorkers;\n" ++ @embedFile("extensions/fixtures/chord-normalization-workers-original-19cb.input.txt") ++
        "\nif(chordNormalizationCases.length!==normalizationSource.cases.length)throw Error('Chord normalization worker Source case count');for(let i=0;i<chordNormalizationCases.length;i++)if(JSON.stringify(chordNormalizationCases[i])!==JSON.stringify(normalizationSource.cases[i]))throw Error(JSON.stringify({case:i,actual:chordNormalizationCases[i],expected:normalizationSource.cases[i]}));", "chord-normalization-workers-source.mjs") catch |err| {
        std.debug.print("Native Chord normalization workers Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
test "native Chord normalization workers array callback retains actual schema context after collection" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const prepared = try engine.evalModule(
        \\const kind=(k,v)=>Object.defineProperty(v,'~kind',{value:k}),context={X:kind('Object',{type:'object',properties:{x:kind('Number',{type:'number'})}})},schema=kind('Array',{type:'array',items:kind('Ref',{$ref:'X'})}),input=[];input.map=function(callback){globalThis.normalizationRetained=callback};nativeChordNormalizationWorkers.Clean(context,schema,input);
    , "chord-normalization-workers-gc-start.mjs");
    engine.freeValue(prepared);
    c.JS_RunGC(engine.runtime);
    const checked = try engine.evalModule(
        \\const value=normalizationRetained({x:1,extra:2});if(JSON.stringify(value)!=='{"x":1}')throw Error('normalization schema/context callback liveness');delete globalThis.normalizationRetained;
    , "chord-normalization-workers-gc-end.mjs");
    engine.freeValue(checked);
    c.JS_RunGC(engine.runtime);
}
test "native Chord normalization workers unwind every native allocation failure in clones checks and iterators" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try setup(gpa);
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            const result = engine.evalModule(
                \\const kind=(k,v)=>Object.defineProperty(v,'~kind',{value:k}),number=kind('Number',{type:'number',default:3}),object=kind('Object',{type:'object',properties:{x:number},required:['x']}),array=kind('Array',{type:'array',items:object}),union=kind('Union',{anyOf:[array,number]}),input=[{extra:1},{}];const defaults=nativeChordNormalizationWorkers.Default(union,input),result=nativeChordNormalizationWorkers.Clean(union,defaults);if(JSON.stringify(result)!=='[{"x":3},{"x":3}]'||JSON.stringify(input)!=='[{"extra":1},{}]')throw Error('normalization result changed');
            , "chord-normalization-workers-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
