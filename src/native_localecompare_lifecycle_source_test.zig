const std = @import("std");
const js = @import("extensions/native_js_values.zig");
const c = js.c;
const binding = @import("extensions/native_localecompare_binding.zig");
fn runGc(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(c.JS_GetRuntime(ctx));
    return c.pi_js_undefined();
}
fn setup(gpa: std.mem.Allocator) !*js.Engine {
    const engine = try js.Engine.init(gpa, .{ .memory_limit = 64 * 1024 * 1024 });
    errdefer engine.deinit();
    // Engine.init installs native localeCompare before guest code.
    try engine.bindFunction("nativeRunGc", runGc, 0);
    return engine;
}
test "Native localeCompare Lifecycle Source original12 retained functions prototype mutation forced GC and exception identity" {
    const before = binding.ownerCountsForTest();
    const engine = try setup(std.testing.allocator);
    defer engine.deinit();
    const installed = binding.ownerCountsForTest();
    try std.testing.expectEqual(before.created + 1, installed.created);
    try std.testing.expectEqual(before.finalized, installed.finalized);
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const source = @embedFile("extensions/fixtures/localecompare-node24-lifecycle.json");
    try js.define(engine, root, "localeCompareOriginal", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "localecompare-lifecycle-source.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/localecompare-node24-lifecycle.input.txt") ++
        "\nif(lifecycleCases.length!==12)throw Error('actual lifecycle Source count');for(let index=0;index<lifecycleCases.length;index++){if(JSON.stringify(lifecycleCases[index])!==JSON.stringify(localeCompareOriginal.cases[index]))throw Error(JSON.stringify({index,actual:lifecycleCases[index],expected:localeCompareOriginal.cases[index]}));}", "native-localecompare-lifecycle-source.mjs") catch |err| {
        if (engine.last_error) |message| std.debug.print("Native localeCompare lifecycle Source failure: {s}\n", .{message});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
    // The restored String prototype still owns this function after every guest
    // mutation and forced GC; the temporary retained closures have returned.
    try std.testing.expectEqual(before.finalized, binding.ownerCountsForTest().finalized);
    const released = try engine.eval("delete String.prototype.localeCompare;nativeRunGc();", "native-localecompare-owner-release.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(released);
    c.JS_RunGC(engine.runtime);
    try std.testing.expectEqual(before.created + 1, binding.ownerCountsForTest().created);
    try std.testing.expectEqual(before.finalized + 1, binding.ownerCountsForTest().finalized);
    c.JS_RunGC(engine.runtime);
    try std.testing.expectEqual(before.finalized + 1, binding.ownerCountsForTest().finalized);
    std.debug.print("NATIVE_LOCALECOMPARE_LIFECYCLE SourceCases=12 retainedAcrossGC=true ownerFinalizedExactlyOnce=true\n", .{});
}
fn allocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try setup(gpa);
    defer engine.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const source = @embedFile("extensions/fixtures/localecompare-node24-typed.json");
    try js.define(engine, root, "localeCompareOriginal", try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "localecompare-allocation-source.json")));
    const generation = engine.native_allocation_generation;
    const result = engine.evalModule(
        \\const retained=String.prototype.localeCompare;
        \\String.prototype.localeCompare=()=>999;
        \\nativeRunGc();
        \\for(const index of [0,137,1469,2099]){
        \\ const expected=localeCompareOriginal.cases[index],wire=expected.options,options={sensitivity:wire.sensitivity};
        \\ if(wire.numeric!==null)options.numeric=wire.numeric;
        \\ if(wire.case_first!==null)options.caseFirst=wire.case_first;
        \\ if(wire.ignore_punctuation!==null)options.ignorePunctuation=wire.ignore_punctuation;
        \\ const left=String.fromCharCode(...expected.left),right=String.fromCharCode(...expected.right);
        \\ const actual=Math.sign(Reflect.apply(retained,left,[right,expected.locale,options]));
        \\ if(actual!==expected.result)throw Error(JSON.stringify({index,actual,expected}));
        \\ nativeRunGc();
        \\}
        \\delete String.prototype.localeCompare;
    , "native-localecompare-allocation-source.mjs") catch |err| {
        const actual = engine.nativeAllocationError(err, generation);
        if (actual != error.OutOfMemory) {
            std.debug.print("Native localeCompare GPA unexpected {s} generation={d}->{d}\n", .{ @errorName(actual), generation, engine.native_allocation_generation });
            if (engine.last_error) |message| std.debug.print("Original exception: {s}\n", .{message});
        }
        return actual;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "Native localeCompare Lifecycle Source every host allocation failure in initialization four actual comparisons retained function and cleanup" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}
