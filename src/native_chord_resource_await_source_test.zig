const std = @import("std");
const latest = @import("native_chord_latest_source_test.zig");
const js = @import("extensions/native_js_values.zig");
test "native latest Chord1692 ResourceAwait compiled inventory" {
    try latest.inventory("CHORD_RESOURCE_AWAIT_COMPILED_INVENTORY");
}
const Probe = struct {
    fn run(gpa: std.mem.Allocator) !void {
        const engine = try latest.setup(gpa);
        defer engine.deinit();
        defer js.c.JS_RunGC(engine.runtime);
        const generation = engine.native_allocation_generation;
        const root = js.c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(root);
        const api = try js.get(engine, root, "nativeLatestChordApi");
        defer engine.freeValue(api);
        const bindings = try js.get(engine, root, "nativeLatestChordBindings");
        defer engine.freeValue(bindings);
        try js.define(engine, api, "ResourceImpl", try js.get(engine, bindings, "ResourceImpl"));
        engine.native_exception_diagnostics_suppressed += 1;
        defer engine.native_exception_diagnostics_suppressed -= 1;
        latest.replay(engine, "chord-resource-await-original-1692", "chordResourceAwaitCases") catch |err| {
            const mapped = engine.nativeAllocationError(err, generation);
            if (mapped != error.OutOfMemory) std.debug.print("ResourceAwait complete Source4 probe: {s}: {s}\n", .{ @errorName(mapped), engine.last_error orelse "no diagnostic" });
            return mapped;
        };
    }
};
test "native latest Chord1692 ResourceAwait actual Source4 intrinsic species own then abort cleanup and rejection identity with GC" {
    try Probe.run(std.testing.allocator);
}
test "native latest Chord1692 ResourceAwait complete actual Source4 factory and native GC teardown allocation sweep" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
