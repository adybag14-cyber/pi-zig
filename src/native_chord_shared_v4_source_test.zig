//! First semantic/functional diagnostic of the actual v4 graph. Full GPA is
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
    try js.define(engine, global, "nativeChordV4SharedApi", c.JS_DupValue(engine.context, classes.exports));
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
        const golden = @embedFile("extensions/fixtures/chord-shared-graph-original-b45.json");
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        try js.define(engine, global, "chordV4Original", try engine.checked(c.JS_ParseJSON(engine.context, golden.ptr, golden.len, "chord-shared-graph-original-b45.json")));
        const result = engine.evalModule("const api=nativeChordV4SharedApi;await(async()=>{\n" ++ @embedFile("extensions/fixtures/chord-shared-graph-original-b45.input.txt") ++ "\n})();const actual=chordV4SharedGraphCases;if(actual.length!==chordV4Original.cases.length)throw Error('Source21 count');for(let i=0;i<actual.length;i++)if(JSON.stringify(actual[i])!==JSON.stringify(chordV4Original.cases[i]))throw Error(JSON.stringify({case:i,actual:actual[i],expected:chordV4Original.cases[i]}));", "chord-shared-graph-b45-source.mjs") catch |err| {
            const mapped = engine.nativeAllocationError(err, generation);
            if (mapped != error.OutOfMemory) if (engine.captured_exception) |exception| {
                const message = c.JS_ToCString(engine.context, exception);
                if (message != null) {
                    defer c.JS_FreeCString(engine.context, message);
                    std.debug.print("V4 shared actual Source21: {s}\n", .{std.mem.span(message)});
                    const stack = c.JS_GetPropertyStr(engine.context, exception, "stack");
                    defer engine.freeValue(stack);
                    if (!c.JS_IsException(stack)) {
                        const stack_text = c.JS_ToCString(engine.context, stack);
                        if (stack_text != null) {
                            defer c.JS_FreeCString(engine.context, stack_text);
                            std.debug.print("V4 shared actual JS stack: {s}\n", .{std.mem.span(stack_text)});
                        }
                    }
                }
            };
            return mapped;
        };
        engine.freeValue(result);
    }
};
test "native Chordb45 shared graph diagnostic compiled inventory" {
    const functions = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, functions.len);
    defer std.testing.allocator.free(names);
    for (functions, names) |function, *name| name.* = function.name;
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(encoded);
    std.debug.print("CHORD_V4_SHARED_COMPILED_INVENTORY={s}\n", .{encoded});
}
test "native Chordb45 shared graph actual Source21 host initializer identity remote binding state demand and release with GC" {
    try Probe.run(std.testing.allocator);
}
test "native Chordb45 shared graph measured complete Source21 host allocation baseline diagnostic only" {
    var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{});
    try Probe.run(failing.allocator());
    std.debug.print("CHORD_V4_SHARED_HOST_BASELINE_ALLOCATIONS={d}\n", .{failing.alloc_index});
}
