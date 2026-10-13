const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const c = js.c;
fn setup(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{});
    errdefer engine.deinit();
    engine.native_io = std.testing.io;
    const api = try js.object(engine);
    defer engine.freeValue(api);
    try js.define(engine, api, "diffRevisions", try @import("extensions/native_chord_delta_diff.zig").function(engine));
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    try js.define(engine, root, "nativeDeltaDiff", c.JS_DupValue(engine.context, api));
    return engine;
}
test "native Chord diff original Source identity UTF16 anchors overflow costs and trap failures" {
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const original = @embedFile("extensions/fixtures/chord-delta-diff-original-19cb.json");
    try js.define(engine, root, "diffSource", try engine.checked(c.JS_ParseJSON(engine.context, original.ptr, original.len, "chord-delta-diff-original-19cb.json")));
    const result = engine.evalModule("const api=nativeDeltaDiff;\n" ++ @embedFile("extensions/fixtures/chord-delta-diff-original-19cb.input.txt") ++
        "\nif(deltaDiffCases.length!==diffSource.cases.length)throw Error('case count');for(let i=0;i<deltaDiffCases.length;i++)if(JSON.stringify(deltaDiffCases[i])!==JSON.stringify(diffSource.cases[i]))throw Error(JSON.stringify({case:i,actual:deltaDiffCases[i],expected:diffSource.cases[i]}));", "chord-delta-diff-source.mjs") catch |err| {
        std.debug.print("Native Chord diff Source: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
test "native Chord diff all GPA failures preserve VM ownership" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try setup(gpa);
            defer engine.deinit();
            const generation = engine.native_allocation_generation;
            const result = engine.evalModule(
                \\const s={key:1};const r=nativeDeltaDiff.diffRevisions({a:[s,1,2],text:'abcxyz'},{a:[9,s,3,2],text:'xyzsuffix'});if(r.length===0)throw Error('empty diff');
            , "delta-diff-allocation.mjs") catch |err| return engine.nativeAllocationError(err, generation);
            engine.freeValue(result);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
