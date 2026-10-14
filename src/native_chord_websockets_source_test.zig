//! First semantic/functional diagnostic of actual acceptWebSockets over the v4 graph. Full GPA is
//! separately required after the real allocation baseline is measured.
const std = @import("std");
const em = @import("extensions/engine.zig");
const h = @import("extensions/native_chord_host_values.zig");
const js = h.js;
const c = h.c;
fn setup(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    errdefer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    var s: h.Scope = .{ .engine = engine };
    defer s.deinit();
    const classes = try @import("extensions/native_chord_full_v4.zig").classes(engine);
    _ = try s.keep(classes.exports);
    _ = try s.keep(classes.bindings);
    try js.define(engine, classes.exports, "Type", try @import("extensions/typebox.zig").create(engine));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "nativeChordWebSocketApi", c.JS_DupValue(engine.context, classes.exports));
    return engine;
}
const Probe = struct {
    fn run(gpa: std.mem.Allocator) !void {
        const engine = try setup(gpa);
        defer engine.deinit();
        defer c.JS_RunGC(engine.runtime);
        const generation = engine.native_allocation_generation;
        engine.native_exception_diagnostics_suppressed += 1;
        defer engine.native_exception_diagnostics_suppressed -= 1;
        const golden = @embedFile("extensions/fixtures/chord-accept-websockets-original-b45.json");
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        try js.define(engine, global, "chordV4Original", try engine.checked(c.JS_ParseJSON(engine.context, golden.ptr, golden.len, "chord-accept-websockets-original-b45.json")));
        const result = engine.evalModule("const api=nativeChordWebSocketApi;await(async()=>{\n" ++ @embedFile("extensions/fixtures/chord-accept-websockets-original-b45.input.txt") ++ "\n})();const actual=chordAcceptWebSocketCases;if(actual.length!==chordV4Original.cases.length)throw Error('Source13 count');for(let i=0;i<actual.length;i++)if(JSON.stringify(actual[i])!==JSON.stringify(chordV4Original.cases[i]))throw Error(JSON.stringify({case:i,actual:actual[i],expected:chordV4Original.cases[i]}));", "chord-accept-websockets-b45-source.mjs") catch |err| {
            const mapped = engine.nativeAllocationError(err, generation);
            if (mapped != error.OutOfMemory) if (engine.captured_exception) |exception| {
                const message = c.JS_ToCString(engine.context, exception);
                if (message != null) {
                    defer c.JS_FreeCString(engine.context, message);
                    std.debug.print("WebSocket actual Source13: {s}\n", .{std.mem.span(message)});
                    const stack = c.JS_GetPropertyStr(engine.context, exception, "stack");
                    defer engine.freeValue(stack);
                    if (!c.JS_IsException(stack)) {
                        const stack_text = c.JS_ToCString(engine.context, stack);
                        if (stack_text != null) {
                            defer c.JS_FreeCString(engine.context, stack_text);
                            std.debug.print("WebSocket actual JS stack: {s}\n", .{std.mem.span(stack_text)});
                        }
                    }
                }
            };
            return mapped;
        };
        engine.freeValue(result);
    }
};
test "native Chordb45 accept WebSockets diagnostic compiled inventory" {
    const functions = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, functions.len);
    defer std.testing.allocator.free(names);
    for (functions, names) |function, *name| name.* = function.name;
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(encoded);
    std.debug.print("CHORD_WEBSOCKETS_COMPILED_INVENTORY={s}\n", .{encoded});
}
test "native Chordb45 accept WebSockets actual Source13 authentication immediate wrapping live getters frames packing and close with GC" {
    try Probe.run(std.testing.allocator);
}
test "native Chordb45 accept WebSockets measured complete Source13 host allocation baseline diagnostic only" {
    var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{});
    try Probe.run(failing.allocator());
    std.debug.print("CHORD_WEBSOCKETS_HOST_BASELINE_ALLOCATIONS={d}\n", .{failing.alloc_index});
}
test "native Chordb45 accept WebSockets complete Source13 GC and teardown every host allocation failure" {
    var baseline: std.testing.FailingAllocator = .init(std.testing.allocator, .{});
    try Probe.run(baseline.allocator());
    try std.testing.expect(!baseline.has_induced_failure);
    try std.testing.expectEqual(baseline.allocated_bytes, baseline.freed_bytes);
    const total = baseline.alloc_index;
    try std.testing.expect(total > 0);
    if (@import("builtin").os.tag == .windows) try std.testing.expectEqual(@as(usize, 1585), total);
    std.debug.print("CHORD_WEBSOCKETS_GPA_BASELINE_ALLOCATIONS={d}\n", .{total});
    var completed: usize = 0;
    for (0..total) |index| {
        var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{ .fail_index = index });
        if (Probe.run(failing.allocator())) |_| {
            std.debug.print("WebSocket GPA index{d}/{d} unexpectedly succeeded induced={}\n", .{ index, total, failing.has_induced_failure });
            return if (failing.has_induced_failure) error.SwallowedOutOfMemoryError else error.NondeterministicMemoryUsage;
        } else |err| switch (err) {
            error.OutOfMemory => {
                if (!failing.has_induced_failure) return error.UnexpectedOutOfMemoryError;
                if (failing.allocated_bytes != failing.freed_bytes) {
                    std.debug.print("WebSocket GPA index{d}/{d} leaked allocated{d} freed{d}\n", .{ index, total, failing.allocated_bytes, failing.freed_bytes });
                    std.debug.dumpStackTrace(&.{ .return_addresses = &failing.stack_addresses, .skipped = .unknown });
                    return error.MemoryLeakDetected;
                }
            },
            else => {
                std.debug.print("WebSocket GPA index{d}/{d} unexpected {s}\n", .{ index, total, @errorName(err) });
                std.debug.dumpStackTrace(&.{ .return_addresses = &failing.stack_addresses, .skipped = .unknown });
                return err;
            },
        }
        completed += 1;
    }
    std.debug.print("CHORD_WEBSOCKETS_GPA_COMPLETE={{\"start\":0,\"end\":{d},\"baseline\":{d},\"completed\":{d},\"leaks\":0,\"unexpected_errors\":0}}\n", .{ total, total, completed });
}
