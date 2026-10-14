const std = @import("std");
const em = @import("extensions/engine.zig");
const h = @import("extensions/native_chord_host_values.zig");
const js = h.js;
const c = h.c;
fn setup(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    errdefer engine.deinit();
    engine.native_io = std.testing.io;
    var s: h.Scope = .{ .engine = engine };
    defer s.deinit();
    const bindings = try s.record();
    try h.field(&s, bindings, "classes", try s.record());
    try h.field(&s, bindings, "objectPrototype", try s.get(try s.keep(try js.global(engine, "Object")), "prototype"));
    const errors = try s.keep(try @import("extensions/native_chord_errors.zig").exports(engine));
    try h.field(&s, bindings, "errors", errors);
    try @import("extensions/native_chord_publish.zig").initialize(engine, bindings);
    try @import("extensions/native_chord_cells_v4.zig").install(engine, bindings);
    const api = try s.record();
    try js.spreadInto(engine, api, errors);
    inline for (.{ "Cell", "Derived", "HYDRATION", "hydrationOf", "unhydrated" }) |name| try h.field(&s, api, name, try s.get(bindings, name));
    try js.define(engine, api, "Type", try @import("extensions/typebox.zig").create(engine));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "nativeChordV4CellApi", c.JS_DupValue(engine.context, api));
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
        const golden = @embedFile("extensions/fixtures/chord-cell-hydration-original-b45.json");
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        try js.define(engine, global, "chordV4Original", try engine.checked(c.JS_ParseJSON(engine.context, golden.ptr, golden.len, "chord-cell-hydration-original-b45.json")));
        const result = engine.evalModule("const api=nativeChordV4CellApi;await(async()=>{\n" ++ @embedFile("extensions/fixtures/chord-cell-hydration-original-b45.input.txt") ++ "\n})();const actual=chordV4CellHydrationCases;if(actual.length!==chordV4Original.cases.length)throw Error('Source17 count');for(let i=0;i<actual.length;i++)if(JSON.stringify(actual[i])!==JSON.stringify(chordV4Original.cases[i]))throw Error(JSON.stringify({case:i,actual:actual[i],expected:chordV4Original.cases[i]}));", "chord-cell-hydration-b45-source.mjs") catch |err| {
            const mapped = engine.nativeAllocationError(err, generation);
            if (mapped != error.OutOfMemory) if (engine.captured_exception) |exception| {
                const message = c.JS_ToCString(engine.context, exception);
                if (message != null) {
                    defer c.JS_FreeCString(engine.context, message);
                    std.debug.print("V4 cells actual Source17: {s}\n", .{std.mem.span(message)});
                }
            };
            return mapped;
        };
        engine.freeValue(result);
    }
};
test "native Chordb45 cells compiled inventory" {
    const functions = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, functions.len);
    defer std.testing.allocator.free(names);
    for (functions, names) |function, *name| name.* = function.name;
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(encoded);
    std.debug.print("CHORD_V4_CELLS_COMPILED_INVENTORY={s}\n", .{encoded});
}
test "native Chordb45 cells actual Source17 deferred init silent publication hydration getter promises and raw identity with GC" {
    try Probe.run(std.testing.allocator);
}
test "native Chordb45 cells complete Source17 and native GC teardown every host allocation failure" {
    const AllocationProbe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
            defer if (failing.fail_index == std.math.maxInt(usize)) {
                std.debug.print("CHORD_V4_CELLS_GPA_BASELINE_ALLOCATIONS={d}\n", .{failing.alloc_index});
            };
            return Probe.run(gpa);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, AllocationProbe.run, .{});
}
