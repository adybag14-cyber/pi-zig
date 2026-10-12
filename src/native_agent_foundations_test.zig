const std = @import("std");
const em = @import("extensions/engine.zig");
const groups = @import("extensions/native_group.zig");
const sdk = @import("extensions/native_sdk.zig");
const json = @import("mcp/protocol.zig").json;
const c = em.c;

fn configure(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    @import("extensions/native_agent_core.zig").installFoundations(engine, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| return sdk.fail(engine, err);
    return c.JS_DupValue(engine.context, roots[0]);
}

fn exercise(gpa: std.mem.Allocator, comptime capture: []const u8, expected_rows: usize, allocation_probe: bool) !void {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-agent-foundations"});
    const group = try groups.Group.init(engine);
    defer group.deinit();
    const root = try group.add("native-agent-foundations-root");
    try root.installSchemas();
    const namespace = try sdk.object(engine);
    defer engine.freeValue(namespace);
    var roots = [_]c.JSValue{namespace};
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, configure, "sdkNativeAgentConfigure", 1, 0, roots.len, &roots));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "sdkNativeAgentConfigure", callback);
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/native-agent-source-" ++ capture ++ ".input.txt"), "native-agent-foundations-" ++ capture ++ ".mjs") catch |err| {
        std.debug.print("Agent actual Source{s}: {s}\n", .{ capture, engine.last_error orelse "no diagnostic" });
        return err;
    };
    defer engine.freeValue(loaded);
    if (allocation_probe) {
        const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
        // Caller-owned Source fixtures catch some errors by design. Classify
        // a caught VM OOM only when this exact allocator actually induced it.
        if (failing.has_induced_failure) return error.OutOfMemory;
    }
    const result = try engine.eval("nativeAgentFoundationRows", "native-agent-foundations-result.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer gpa.free(raw);
    var actual = try json.Owned.parse(gpa, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(gpa, @embedFile("extensions/fixtures/native-agent-source-" ++ capture ++ ".json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(expected_rows, rows.len);
    try std.testing.expectEqual(rows.len, actual.value.array.items.len);
    for (rows, actual.value.array.items) |original, native| {
        if (!json.equal(original, native)) std.debug.print("Agent Source{s} complete actual={s}\n", .{ capture, raw });
        try std.testing.expect(json.equal(original, native));
    }
    const cleared = try engine.eval("delete globalThis.nativeAgentFoundationRows;delete globalThis.sdkNativeAgentConfigure", "native-agent-foundations-clear.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    c.JS_RunGC(engine.runtime);
}

fn compare(comptime capture: []const u8, expected_rows: usize) !void {
    try exercise(std.testing.allocator, capture, expected_rows, false);
}

fn allocationProbe(gpa: std.mem.Allocator) !void {
    // Source601 contains constructor/tool state, queue retention/reset, pending
    // abort/idle ownership, live listener iteration and four-event failures.
    // Keep the failure sweep on that one complete owned-lifecycle corpus;
    // the other three complete Source corpora remain strict normal tests.
    exercise(gpa, "601", 12, true) catch |err| {
        const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
        if (err == error.JavaScriptException and failing.has_induced_failure) return error.OutOfMemory;
        return err;
    };
}

test "native Agent foundations actual current Source601 twelve constructor queue state and owned executor lifecycle rows" {
    try compare("601", 12);
}
test "native Agent foundations actual current Source602 eight initial tool JSON callee and raw identity rows" {
    try compare("602", 8);
}
test "native Agent foundations actual current Source607 twenty prompt continue routing and normalization rows" {
    try compare("607", 20);
}
test "native Agent foundations actual current Source610 shared default converter identities descriptors constructibility and raw role getters" {
    try compare("610", 4);
}
test "native Agent foundations allocation failures across actual constructor queues lifecycle and callback roots release every owner" {
    try @import("test_support/sdk_allocation_shards.zig").check("agent-foundations", allocationProbe, .{});
}
