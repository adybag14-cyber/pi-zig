//! Authored latest-Source review regression; actual Source capture and native
//! qualification remain pending. No historical b45 golden is relabeled.
const std = @import("std");
const em = @import("extensions/engine.zig");
const h = @import("extensions/native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const Probe = struct {
    fn run(gpa: std.mem.Allocator, emit: bool) !void {
        const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
        defer engine.deinit();
        defer c.JS_RunGC(engine.runtime);
        engine.native_io = std.testing.io;
        try @import("extensions/timers.zig").install(engine, std.testing.io);
        var s: h.Scope = .{ .engine = engine };
        defer s.deinit();
        const classes = try @import("extensions/native_chord_full_v4.zig").classes(engine);
        _ = try s.keep(classes.exports);
        _ = try s.keep(classes.bindings);
        const api = try s.record();
        try js.spreadInto(engine, api, classes.exports);
        try js.define(engine, api, "Type", try @import("extensions/typebox.zig").create(engine));
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        try js.define(engine, global, "nativeChordForeignContextApi", c.JS_DupValue(engine.context, api));
        const generation = engine.native_allocation_generation;
        const result = engine.evalModule("const api=nativeChordForeignContextApi;await(async()=>{\n" ++ @embedFile("extensions/fixtures/chord-foreign-context-review-5ab7fe7.input.txt") ++ "\n})();if(chordForeignContextCases.length!==5)throw Error('Foreign5 count');globalThis.chordForeignContextObserved=JSON.stringify(chordForeignContextCases);", "chord-foreign-context-review-5ab7fe7.mjs") catch |err| return engine.nativeAllocationError(err, generation);
        defer engine.freeValue(result);
        if (emit) {
            const json = try engine.toString(try s.get(global, "chordForeignContextObserved"));
            defer engine.gpa.free(json);
            std.debug.print("CHORD_FOREIGN_CONTEXT_OBSERVED_CASES={s}\n", .{json});
        }
    }
};
test "native Chord5ab7fe7 foreign context review compiled inventory" {
    const functions = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, functions.len);
    defer std.testing.allocator.free(names);
    for (functions, names) |function, *name| name.* = function.name;
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(encoded);
    std.debug.print("CHORD_FOREIGN_CONTEXT_REVIEW_COMPILED_INVENTORY={s}\n", .{encoded});
}
test "native Chord5ab7fe7 foreign forged and null contexts reject before remote call while valid context calls with GC" {
    try Probe.run(std.testing.allocator, true);
}
test "native Chord5ab7fe7 foreign context review measured host allocation baseline diagnostic only" {
    var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{});
    try Probe.run(failing.allocator(), false);
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    std.debug.print("CHORD_FOREIGN_CONTEXT_REVIEW_HOST_BASELINE_ALLOCATIONS={d}\n", .{failing.alloc_index});
}
