//! Actual private output factory observations. Comparison with genuine latest
//! Source receipts is required externally; no uncaptured golden is invented.
const std = @import("std");
const h = @import("extensions/native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const Probe = struct {
    fn run(gpa: std.mem.Allocator, emit: bool) !void {
        const engine = try h.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
        defer engine.deinit();
        defer c.JS_RunGC(engine.runtime);
        engine.native_io = std.testing.io;
        try @import("extensions/timers.zig").install(engine, std.testing.io);
        var s: h.Scope = .{ .engine = engine };
        defer s.deinit();
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        try js.define(engine, global, "Buffer", c.pi_js_undefined());
        try js.define(engine, global, "apiFallback", try @import("extensions/native_chord_output.zig").exports(engine));
        try @import("extensions/node_buffer.zig").install(engine);
        try js.define(engine, global, "apiBuffer", try @import("extensions/native_chord_output.zig").exports(engine));
        const generation = engine.native_allocation_generation;
        const result = engine.evalModule("await(async()=>{\n" ++ @embedFile("extensions/fixtures/chord-output-5ab7fe7.input.txt") ++ "\n})();if(chordOutputCases.length!==14)throw Error('Output14 count');globalThis.chordOutputObserved=JSON.stringify(chordOutputCases);", "chord-output-5ab7fe7.mjs") catch |err| return engine.nativeAllocationError(err, generation);
        defer engine.freeValue(result);
        if (emit) {
            const json = try engine.toString(try s.get(global, "chordOutputObserved"));
            defer engine.gpa.free(json);
            std.debug.print("CHORD_OUTPUT_OBSERVED_CASES={s}\n", .{json});
        }
    }
};
test "native Chord5ab7fe7 output diagnostic compiled inventory" {
    const functions = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, functions.len);
    defer std.testing.allocator.free(names);
    for (functions, names) |function, *name| name.* = function.name;
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(encoded);
    std.debug.print("CHORD_OUTPUT_COMPILED_INVENTORY={s}\n", .{encoded});
}
test "native Chord5ab7fe7 output actual private factory observations with optional Buffer skips and serialized Progress GC" {
    try Probe.run(std.testing.allocator, true);
}
test "native Chord5ab7fe7 output measured complete caller host allocation baseline diagnostic only" {
    var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{});
    try Probe.run(failing.allocator(), false);
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    std.debug.print("CHORD_OUTPUT_HOST_BASELINE_ALLOCATIONS={d}\n", .{failing.alloc_index});
}
