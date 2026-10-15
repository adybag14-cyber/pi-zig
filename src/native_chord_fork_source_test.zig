//! Authored actual native guest/facade observations. Genuine latest Source
//! comparison and complete failure qualification are separate required gates.
const std = @import("std");
const h = @import("extensions/native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const configuration = @import("chord_fork_fixture_options");
const processes = @import("extensions/native_chord_process_runtime.zig");
const Probe = struct {
    fn run(gpa: std.mem.Allocator, emit: bool) !void {
        var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
        defer environment.deinit();
        const engine = try h.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
        defer engine.deinit();
        engine.native_io = std.testing.io;
        try @import("extensions/timers.zig").install(engine, std.testing.io);
        try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{ "native-chord-fork-parent", "actual-parent.mjs" });
        try @import("extensions/native_durable_context.zig").installContextOnly(engine);
        var s: h.Scope = .{ .engine = engine };
        defer s.deinit();
        const classes = try @import("extensions/native_chord_full_v4.zig").classes(engine);
        _ = try s.keep(classes.exports);
        _ = try s.keep(classes.bindings);
        try engine.registerValueModule("@earendil-works/chord", classes.exports);
        const runtime = try processes.Runtime.install(engine, .{ .guest_executable = configuration.guest_executable });
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        try js.define(engine, global, "api", try @import("extensions/native_chord_node_api.zig").exports(engine, classes.bindings));
        try h.field(&s, global, "guestPath", try s.text(configuration.guest_entry));
        try h.field(&s, global, "guestNodeSpecifier", try s.text("@earendil-works/chord/node"));
        const generation = engine.native_allocation_generation;
        const result = engine.evalModule("await(async()=>{\n" ++ @embedFile("extensions/fixtures/chord-fork-driver-5ab7fe7.input.txt") ++ "\n})();if(chordForkDriverCases.length!==2)throw Error('Fork2 count');globalThis.chordForkObserved=JSON.stringify(chordForkDriverCases);", "chord-fork-driver-5ab7fe7.mjs") catch |err| return engine.nativeAllocationError(err, generation);
        defer engine.freeValue(result);
        // Exit settlement and final pipe EOF are distinct. Reconcile both
        // before accepting native owner retirement, then inspect real state.
        var attempts: usize = 0;
        while (runtime.hasPending() and attempts < 100) : (attempts += 1) {
            const observed = engine.native_owner_signal.observe();
            _ = try engine.pumpControls();
            _ = try engine.drainReadyJobs();
            if (runtime.hasPending()) _ = try engine.native_owner_signal.waitAfter(std.testing.io, observed, .{ .duration = .{ .raw = .fromMilliseconds(10), .clock = .awake } });
        }
        try std.testing.expect(!runtime.hasPending());
        if (emit) {
            const json = try engine.toString(try s.get(global, "chordForkObserved"));
            defer engine.gpa.free(json);
            std.debug.print("CHORD_FORK_OBSERVED_CASES={s}\n", .{json});
        }
    }
};
test "native Chord5ab7fe7 fork actual guest diagnostic compiled inventory" {
    const functions = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, functions.len);
    defer std.testing.allocator.free(names);
    for (functions, names) |function, *name| name.* = function.name;
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(encoded);
    std.debug.print("CHORD_FORK_COMPILED_INVENTORY={s}\n", .{encoded});
}
test "native Chord5ab7fe7 fork actual guest control lock metadata mirrored output manager exit and retirement observations" {
    try Probe.run(std.testing.allocator, true);
}
test "native Chord5ab7fe7 fork measured actual guest caller host allocation baseline diagnostic only" {
    var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{});
    try Probe.run(failing.allocator(), false);
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    std.debug.print("CHORD_FORK_HOST_BASELINE_ALLOCATIONS={d}\n", .{failing.alloc_index});
}
