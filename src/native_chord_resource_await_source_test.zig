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
            if (mapped != error.OutOfMemory) {
                std.debug.print("ResourceAwait complete Source4 probe: {s}: {s}; pending_jobs={any} allocation_generation={d}\n", .{ @errorName(mapped), engine.last_error orelse "no diagnostic", js.c.JS_IsJobPending(engine.runtime), engine.native_allocation_generation });
                if (engine.captured_exception) |exception| {
                    std.debug.print("ResourceAwait actual captured tag={d} null={any} undefined={any} native_identity={any}\n", .{ js.c.pi_js_native_allocation_error_generation(exception), js.c.JS_IsNull(exception), js.c.JS_IsUndefined(exception), if (engine.native_allocation_exception) |native| js.c.JS_IsStrictEqual(engine.context, native, exception) else false });
                    const text = js.c.JS_ToCString(engine.context, exception);
                    if (text != null) {
                        defer js.c.JS_FreeCString(engine.context, text);
                        std.debug.print("ResourceAwait actual captured exception: {s}\n", .{std.mem.span(text)});
                    }
                }
            }
            return mapped;
        };
    }
};
test "native latest Chord1692 ResourceAwait actual Source4 intrinsic species own then abort cleanup and rejection identity with GC" {
    try Probe.run(std.testing.allocator);
}
test "native latest Chord1692 ResourceAwait complete actual Source4 factory and native GC teardown allocation sweep" {
    const AllocationProbe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
            defer if (failing.fail_index == std.math.maxInt(usize)) {
                std.debug.print("CHORD_RESOURCE_AWAIT_GPA_BASELINE_ALLOCATIONS={d}\n", .{failing.alloc_index});
            };
            Probe.run(gpa) catch |err| {
                if (err != error.OutOfMemory) std.debug.print("ResourceAwait failure index={d} allocations={d} induced={any} error={s}\n", .{ failing.fail_index, failing.alloc_index, failing.has_induced_failure, @errorName(err) });
                return err;
            };
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, AllocationProbe.run, .{});
}
