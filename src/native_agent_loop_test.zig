const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const groups = @import("extensions/native_group.zig");
const json = @import("mcp/protocol.zig").json;
const c = em.c;
var diagnose_owned_stream_allocation = false;
var diagnostic_fail_index: usize = 2631;
var diagnostic_requires_native_tag = true;
fn ownedAllocationError(engine: *em.Engine, gpa: std.mem.Allocator, err: anyerror, generation: u64) anyerror {
    if (err != error.JavaScriptPromiseUnsettled) return err;
    const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
    if (!failing.has_induced_failure or generation == engine.native_allocation_generation) return err;
    const fault = engine.native_allocation_exception orelse return err;
    const tagged = c.pi_js_native_allocation_error_generation(fault);
    const distance = tagged -% generation;
    if (tagged != 0 and distance != 0 and distance <= engine.native_allocation_generation -% generation) return error.OutOfMemory;
    return err;
}
fn loop(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, continuing: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var args = [_]c.JSValue{c.pi_js_undefined()} ** 6;
    for (0..@min(args.len, @as(usize, @intCast(argc)))) |index| args[index] = argv[index];
    return if (continuing != 0) @import("extensions/native_agent_loop.zig").run(engine, c.pi_js_undefined(), args[0], args[1], args[2], args[3], args[4], true) catch |err| sdk.fail(engine, err) else @import("extensions/native_agent_loop.zig").run(engine, args[0], args[1], args[2], args[3], args[4], args[5], false) catch |err| sdk.fail(engine, err);
}
fn clone(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return @import("extensions/native_structured_clone.zig").clone(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn exercise(gpa: std.mem.Allocator, comptime capture: []const u8, expected_rows: usize, allocation_probe: bool) !void {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-agent-loop"});
    const group = try groups.Group.init(engine);
    defer group.deinit();
    const root = try group.add("native-agent-loop-root");
    try root.installSchemas();
    const namespace = try sdk.object(engine);
    defer engine.freeValue(namespace);
    try sdk.put(engine, namespace, "agentLoop", try @import("extensions/native_agent_stream.zig").function(engine, false));
    try sdk.put(engine, namespace, "agentLoopContinue", try @import("extensions/native_agent_stream.zig").function(engine, true));
    inline for (.{ .{ "runAgentLoop", 6, 0 }, .{ "runAgentLoopContinue", 5, 1 } }) |entry| {
        const function = try engine.checked(c.pi_js_function_magic(engine.context, loop, entry[0], entry[1], entry[2]));
        defer engine.freeValue(function);
        const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
        defer engine.freeValue(parent);
        if (c.JS_SetPrototype(engine.context, function, parent) < 0) return @import("extensions/native_js_values.zig").capture(engine);
        try sdk.put(engine, namespace, entry[0], c.JS_DupValue(engine.context, function));
    }
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "sdkLoopNative", c.JS_DupValue(engine.context, namespace));
    try sdk.put(engine, global, "structuredClone", try engine.checked(c.JS_NewCFunction(engine.context, clone, "structuredClone", 1)));
    const allocation_generation = engine.native_allocation_generation;
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/native-agent-loop-source-" ++ capture ++ ".input.txt"), "native-agent-loop" ++ capture ++ ".mjs") catch |err| {
        std.debug.print("AgentLoop Source{s}: {s}\n", .{ capture, engine.last_error orelse "no diagnostic" });
        if (diagnose_owned_stream_allocation) {
            const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
            const tagged = if (engine.native_allocation_exception) |exception| c.pi_js_native_allocation_error_generation(exception) else 0;
            const captured_tag = if (engine.captured_exception) |exception| c.pi_js_native_allocation_error_generation(exception) else 0;
            std.debug.print("SDK_ALLOCATION_DIAGNOSTIC capture={s} error={s} induced={} alloc_index={d} fail_index={d} allocated={d} freed_before_deinit={d} generation_before={d} generation_after={d} native_exception_tag={d} captured_exception_tag={d} classifier={s}\n", .{ capture, @errorName(err), failing.has_induced_failure, failing.alloc_index, failing.fail_index, failing.allocated_bytes, failing.freed_bytes, allocation_generation, engine.native_allocation_generation, tagged, captured_tag, @errorName(engine.nativeAllocationError(err, allocation_generation)) });
            if (failing.has_induced_failure) {
                const stack = failing.getStackTrace();
                std.debug.dumpStackTrace(&stack);
            }
            try std.testing.expect(failing.has_induced_failure);
            try std.testing.expectEqual(diagnostic_fail_index, failing.alloc_index);
            if (diagnostic_requires_native_tag) {
                try std.testing.expect(engine.native_allocation_generation != allocation_generation);
                try std.testing.expectEqual(engine.native_allocation_generation, tagged);
                try std.testing.expectEqual(error.OutOfMemory, ownedAllocationError(engine, gpa, err, allocation_generation));
            }
            try std.testing.expectEqual(error.JavaScriptPromiseUnsettled, err);
            std.debug.print("SDK_ALLOCATION_DIAGNOSTIC_OWNED classifier={s} induced={} generation_before={d} generation_after={d} retained_tag={d} original_error={s}\n", .{ @errorName(ownedAllocationError(engine, gpa, err, allocation_generation)), failing.has_induced_failure, allocation_generation, engine.native_allocation_generation, tagged, @errorName(err) });
        }
        if (allocation_probe and !diagnose_owned_stream_allocation) return ownedAllocationError(engine, gpa, err, allocation_generation);
        return err;
    };
    defer engine.freeValue(loaded);
    if (allocation_probe) {
        const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
        if (failing.has_induced_failure) return error.OutOfMemory;
    }
    const observed = try engine.eval("sdkAgentLoopRows", "native-agent-loop623-result.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(observed);
    const raw = try engine.stringify(observed);
    defer gpa.free(raw);
    var actual = try json.Owned.parse(gpa, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(gpa, @embedFile("extensions/fixtures/native-agent-loop-source-" ++ capture ++ ".json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(expected_rows, rows.len);
    try std.testing.expectEqual(rows.len, actual.value.array.items.len);
    for (rows, actual.value.array.items) |source, native| {
        if (!json.equal(source, native)) std.debug.print("AgentLoop Source{s} complete actual={s}\n", .{ capture, raw });
        try std.testing.expect(json.equal(source, native));
    }
    const cleared = try engine.eval("delete globalThis.sdkLoopNative;delete globalThis.sdkAgentLoopRows", "native-agent-loop623-clear.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    c.JS_RunGC(engine.runtime);
}
test "native AgentLoop private real twelve original Source623 turn and assistant stream traces match whole records" {
    try exercise(std.testing.allocator, "623", 12, false);
}
test "native AgentLoop private real seventeen original Source629 sequential parallel validation and tool hook traces match whole records" {
    try exercise(std.testing.allocator, "629", 17, false);
}
test "native AgentLoop private real nineteen original Source632 failure iterator cleanup and queued turn traces match whole records" {
    try exercise(std.testing.allocator, "632", 19, false);
}
test "native AgentLoop private real eight original Source636 EventStream wrappers preserve raw cycles and caller toJSON identities" {
    try exercise(std.testing.allocator, "636", 8, false);
}
test "native AgentLoop private real three original Source639 generic queue and raw extractor failure records match" {
    try exercise(std.testing.allocator, "639", 3, false);
}
fn allocationExercise(gpa: std.mem.Allocator, comptime capture: []const u8, rows: usize) !void {
    exercise(gpa, capture, rows, true) catch |err| {
        const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
        if (err == error.JavaScriptException and failing.has_induced_failure) return error.OutOfMemory;
        return err;
    };
}
fn changesAllocationProbe(gpa: std.mem.Allocator) !void {
    try allocationExercise(gpa, "623", 12);
}
fn toolsAllocationProbe(gpa: std.mem.Allocator) !void {
    try allocationExercise(gpa, "629", 17);
}
fn streamAllocationProbe(gpa: std.mem.Allocator) !void {
    try allocationExercise(gpa, "632", 19);
    try allocationExercise(gpa, "636", 8);
    try allocationExercise(gpa, "639", 3);
}
test "native AgentLoop declaration deltas context copies and response roots release every induced native allocation" {
    try @import("test_support/sdk_allocation_shards.zig").check("agent-loop-changes", changesAllocationProbe, .{});
}
test "native AgentLoop sequential parallel validation hooks and update roots release every induced native allocation" {
    try @import("test_support/sdk_allocation_shards.zig").check("agent-loop-tools", toolsAllocationProbe, .{});
}
test "native AgentLoop sync async cleanup wrappers and raw queue roots release every induced native allocation" {
    try @import("test_support/sdk_allocation_shards.zig").check("agent-loop-owned-stream", streamAllocationProbe, .{});
}
test "SDK Agent allocation2631 original producer fault diagnostic" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 2631 });
    diagnose_owned_stream_allocation = true;
    defer diagnose_owned_stream_allocation = false;
    const observed = streamAllocationProbe(failing.allocator());
    if (observed) |_| return error.ExpectedOriginalUnsettledAllocationFailure else |err| {
        std.debug.print("SDK_ALLOCATION_DIAGNOSTIC_TERMINAL error={s} induced={} alloc_index={d} fail_index={d} allocated={d} freed={d}\n", .{ @errorName(err), failing.has_induced_failure, failing.alloc_index, failing.fail_index, failing.allocated_bytes, failing.freed_bytes });
        try std.testing.expectEqual(error.JavaScriptPromiseUnsettled, err);
    }
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 2631), failing.alloc_index);
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    diagnose_owned_stream_allocation = false;
    var classified = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 2631 });
    try std.testing.expectError(error.OutOfMemory, streamAllocationProbe(classified.allocator()));
    try std.testing.expect(classified.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 2631), classified.alloc_index);
    try std.testing.expectEqual(classified.allocated_bytes, classified.freed_bytes);
    std.debug.print("SDK_ALLOCATION_DIAGNOSTIC_CLASSIFIED error=OutOfMemory induced={} index={d} allocated={d} freed={d}\n", .{ classified.has_induced_failure, classified.alloc_index, classified.allocated_bytes, classified.freed_bytes });
    // An ordinary pending guest Promise has no induced native fault and
    // remains unsettled even if a real tagged fault predates this boundary.
    var ordinary = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try em.Engine.init(ordinary.allocator(), .{});
    defer engine.deinit();
    _ = engine.throwNativeOutOfMemory();
    engine.freeValue(c.JS_GetException(engine.context));
    const generation = engine.native_allocation_generation;
    const pending = engine.evalModule("await new Promise(() => {});", "ordinary-pending.mjs") catch |err| {
        try std.testing.expectEqual(error.JavaScriptPromiseUnsettled, err);
        try std.testing.expectEqual(err, ownedAllocationError(engine, ordinary.allocator(), err, generation));
        try std.testing.expect(!ordinary.has_induced_failure);
        return;
    };
    engine.freeValue(pending);
    return error.ExpectedOrdinaryPendingPromise;
}
test "SDK Agent allocation2654 original producer fault diagnostic" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 2654 });
    diagnose_owned_stream_allocation = true;
    diagnostic_fail_index = 2654;
    diagnostic_requires_native_tag = true;
    defer {
        diagnose_owned_stream_allocation = false;
        diagnostic_fail_index = 2631;
        diagnostic_requires_native_tag = true;
    }
    try std.testing.expectError(error.JavaScriptPromiseUnsettled, streamAllocationProbe(failing.allocator()));
    std.debug.print("SDK_ALLOCATION_DIAGNOSTIC2654_TERMINAL induced={} index={d} allocated={d} freed={d}\n", .{ failing.has_induced_failure, failing.alloc_index, failing.allocated_bytes, failing.freed_bytes });
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 2654), failing.alloc_index);
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}
