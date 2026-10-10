const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const group_mod = @import("extensions/native_group.zig");
const json = @import("mcp/protocol.zig").json;
fn exercise(gpa: std.mem.Allocator, comptime fixture: []const u8, variable: []const u8, allocation_probe: bool) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-session-usage-root");
    try root.installSchemas();
    const module = engine.evalModule(@embedFile("extensions/fixtures/sdk-session-usage" ++ fixture ++ "-6fb2e78.txt"), "sdk-session-usage.mjs") catch |err| {
        if (!allocation_probe) if (engine.captured_exception) |exception| {
            const detail = try engine.toString(exception);
            defer engine.gpa.free(detail);
            std.debug.print("Session usage {s} failed: {s}\n", .{ fixture, detail });
        };
        return err;
    };
    defer engine.freeValue(module);
    if (allocation_probe) {
        const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
        if (failing.has_induced_failure) return error.OutOfMemory;
    }
    const value = try engine.eval(variable, "sdk-session-usage-result.js", engine_mod.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(value);
    const raw = try engine.stringify(value);
    defer engine.gpa.free(raw);
    var actual = try json.Owned.parse(engine.gpa, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(engine.gpa, @embedFile("extensions/fixtures/sdk-session-usage" ++ fixture ++ "-6fb2e78.json"));
    defer expected.deinit();
    if (!json.equal(expected.value, actual.value)) std.debug.print("Session usage {s} actual={s}\n", .{ fixture, raw });
    try std.testing.expect(json.equal(expected.value, actual.value));
}
fn replay(comptime fixture: []const u8, variable: []const u8) !void {
    try exercise(std.testing.allocator, fixture, variable, false);
}
test "native SDK session usage billed totals current context refresh and retained stats match Source" {
    try replay("", "sdkUsageResult");
}
test "native SDK session usage estimates edits compaction branch totals images and UTF16 match Source" {
    try replay("-matrix", "sdkUsageMatrix");
}
test "native SDK session usage system replay virtual routed physical limits and error exclusion match Source" {
    try replay("-routing", "sdkUsageRouting");
}
test "native SDK session usage retained event context reads live actual session and rejects stale lease" {
    try replay("-context", "sdkUsageContext");
}
fn usageAllocation(gpa: std.mem.Allocator) !void {
    exercise(gpa, "-matrix", "sdkUsageMatrix", true) catch |err| {
        const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
        if (err == error.JavaScriptException and failing.has_induced_failure) return error.OutOfMemory;
        return err;
    };
}
test "native SDK session usage every host allocation releases projected messages totals and retained session" {
    try @import("test_support/sdk_allocation_shards.zig").check("session-usage", usageAllocation, .{});
}
