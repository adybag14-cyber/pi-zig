const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const c = js.c;
const contracts = @import("extensions/native_chord_contracts_v4.zig");
const Scope = @import("extensions/native_chord_values.zig").Scope;
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn internal(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    var operation: i32 = undefined;
    if (c.JS_ToInt32(engine.context, &operation, values[1]) < 0) return js.capture(engine);
    return switch (operation) {
        0 => contracts.resolveHost(engine, values[0], arg(args, 0), arg(args, 1), arg(args, 2)),
        1 => c.pi_js_bool(engine.context, @intFromBool(try contracts.placedOn(engine, arg(args, 0), arg(args, 1)))),
        2 => contracts.placementText(engine, arg(args, 0)),
        else => contracts.contractFromDescription(engine, values[0], arg(args, 0)),
    };
}
fn arrow(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, values: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(ctx.?);
    return internal(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, &.{ values[0], c.JS_NewInt32(engine.context, magic) }) catch |err| @import("extensions/native_durable.zig").reject(engine, err);
}
fn setup(gpa: std.mem.Allocator) !*em.Engine {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    errdefer engine.deinit();
    engine.native_io = std.testing.io;
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const errors = try s.keep(try @import("extensions/native_chord_errors.zig").exports(engine));
    const chord_error = try s.get(errors, "ChordError");
    const api = try s.keep(try contracts.exports(engine, chord_error));
    try js.spreadInto(engine, api, errors);
    try js.define(engine, api, "Type", try @import("extensions/typebox.zig").create(engine));
    inline for (.{ .{ "resolveHost", 3 }, .{ "placedOn", 2 }, .{ "placementText", 1 }, .{ "contractFromDescription", 1 } }, 0..) |entry, operation| {
        const function = if (operation == 1 or operation == 2) blk: {
            var values = [_]c.JSValue{chord_error};
            break :blk try engine.checked(c.JS_NewCFunctionData2(engine.context, arrow, entry[0], entry[1], @intCast(operation), 1, &values));
        } else try @import("extensions/native_node_function.zig").create(engine, entry[0], entry[1], internal, &.{ chord_error, c.JS_NewInt32(engine.context, @intCast(operation)) });
        try js.define(engine, api, entry[0], function);
    }
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "nativeChordV4Api", c.JS_DupValue(engine.context, api));
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
        const golden = @embedFile("extensions/fixtures/chord-contract-placement-original-b45.json");
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        try js.define(engine, global, "chordV4Original", try engine.checked(c.JS_ParseJSON(engine.context, golden.ptr, golden.len, "chord-contract-placement-original-b45.json")));
        const result = engine.evalModule("const api=nativeChordV4Api;await(async()=>{\n" ++ @embedFile("extensions/fixtures/chord-contract-placement-original-b45.input.txt") ++ "\n})();const actual=chordV4ContractCases;if(actual.length!==chordV4Original.cases.length)throw Error('Source28 count');for(let i=0;i<actual.length;i++)if(JSON.stringify(actual[i])!==JSON.stringify(chordV4Original.cases[i]))throw Error(JSON.stringify({case:i,actual:actual[i],expected:chordV4Original.cases[i]}));", "chord-contract-placement-b45-source.mjs") catch |err| return engine.nativeAllocationError(err, generation);
        engine.freeValue(result);
    }
};
test "native Chordb45 contracts compiled inventory" {
    const functions = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, functions.len);
    defer std.testing.allocator.free(names);
    for (functions, names) |function, *name| name.* = function.name;
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(encoded);
    std.debug.print("CHORD_V4_CONTRACTS_COMPILED_INVENTORY={s}\n", .{encoded});
}
test "native Chordb45 contracts actual Source28 placement token fingerprints binding constructors and raw identity with GC" {
    try Probe.run(std.testing.allocator);
}
test "native Chordb45 contracts full Source28 and native GC teardown every host allocation failure" {
    const AllocationProbe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
            defer if (failing.fail_index == std.math.maxInt(usize)) {
                std.debug.print("CHORD_V4_CONTRACTS_GPA_BASELINE_ALLOCATIONS={d}\n", .{failing.alloc_index});
            };
            return Probe.run(gpa);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, AllocationProbe.run, .{});
}
