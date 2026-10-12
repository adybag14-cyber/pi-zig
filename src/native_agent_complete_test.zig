const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const groups = @import("extensions/native_group.zig");
const json = @import("mcp/protocol.zig").json;
const c = em.c;
fn exercise(gpa: std.mem.Allocator, comptime capture: []const u8, expected_rows: usize, allocation_probe: bool) !void {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"native-agent-complete"});
    const group = try groups.Group.init(engine);
    defer group.deinit();
    const root = try group.add("native-agent-complete-root");
    try root.installSchemas();
    const namespace = try sdk.object(engine);
    defer engine.freeValue(namespace);
    try @import("extensions/native_agent_complete.zig").install(engine, namespace);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "sdkAgentCompleteNative", c.JS_DupValue(engine.context, namespace));
    const loaded = engine.evalModule(@embedFile("extensions/fixtures/native-agent-complete-source-" ++ capture ++ ".input.txt"), "native-agent-complete" ++ capture ++ ".mjs") catch |err| {
        std.debug.print("Complete Agent Source{s}: {s}\n", .{ capture, engine.last_error orelse "no diagnostic" });
        return err;
    };
    defer engine.freeValue(loaded);
    if (allocation_probe) {
        const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
        if (failing.has_induced_failure) return error.OutOfMemory;
    }
    const result = try engine.eval("sdkAgentCompleteRows", "native-agent-complete641-result.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer gpa.free(raw);
    var actual = try json.Owned.parse(gpa, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(gpa, @embedFile("extensions/fixtures/native-agent-complete-source-" ++ capture ++ ".json"));
    defer expected.deinit();
    const rows = expected.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(expected_rows, rows.len);
    try std.testing.expectEqual(rows.len, actual.value.array.items.len);
    for (rows, actual.value.array.items) |source, native| {
        if (!json.equal(source, native)) std.debug.print("Complete Agent Source{s} complete actual={s}\n", .{ capture, raw });
        try std.testing.expect(json.equal(source, native));
    }
    const cleared = try engine.eval("delete globalThis.sdkAgentCompleteNative;delete globalThis.sdkAgentCompleteRows", "native-agent-complete641-clear.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(cleared);
    c.JS_RunGC(engine.runtime);
}
test "native Agent complete private actual Source641 twelve full prototype and lexical default fallback records" {
    try exercise(std.testing.allocator, "641", 12, false);
}
test "native Agent complete private actual Source643 sixteen real prompt continue queue failure abort and owned idle lifecycles" {
    try exercise(std.testing.allocator, "643", 16, false);
}
fn metadataAllocationProbe(gpa: std.mem.Allocator) !void {
    exercise(gpa, "641", 12, true) catch |err| {
        const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
        if (err == error.JavaScriptException and failing.has_induced_failure) return error.OutOfMemory;
        return err;
    };
}
fn runtimeAllocationProbe(gpa: std.mem.Allocator) !void {
    exercise(gpa, "643", 16, true) catch |err| {
        const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
        if (err == error.JavaScriptException and failing.has_induced_failure) return error.OutOfMemory;
        return err;
    };
}
test "native Agent complete metadata default setter constructor and callback roots release every induced native allocation" {
    try @import("test_support/sdk_allocation_shards.zig").check("agent-complete-metadata", metadataAllocationProbe, .{});
}
test "native Agent complete real loop queues abort failure and owned idle roots release every induced native allocation" {
    try @import("test_support/sdk_allocation_shards.zig").check("agent-complete-runtime", runtimeAllocationProbe, .{});
}
