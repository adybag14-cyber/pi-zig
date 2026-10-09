const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const group_mod = @import("extensions/native_group.zig");
const json = @import("mcp/protocol.zig").json;
fn exercise(gpa: std.mem.Allocator, comptime name: []const u8, allocation_probe: bool) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const root = try group.add("sdk-public-session-root");
    try root.installSchemas();
    const loaded = try engine.evalModule(@embedFile("extensions/fixtures/sdk-public-" ++ name ++ "-6fb2e78.txt"), "sdk-public-session.mjs");
    defer engine.freeValue(loaded);
    if (allocation_probe) {
        const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
        if (failing.has_induced_failure) return error.OutOfMemory;
    }
    const result = try engine.eval("sdkPublicResult", "sdk-public-result.js", engine_mod.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const raw = try engine.stringify(result);
    defer gpa.free(raw);
    var actual = try json.Owned.parse(gpa, raw);
    defer actual.deinit();
    var expected = try json.Owned.parse(gpa, @embedFile("extensions/fixtures/sdk-public-" ++ name ++ "-6fb2e78.json"));
    defer expected.deinit();
    if (!json.equal(expected.value, actual.value)) std.debug.print("SDK public {s} actual={s}\n", .{ name, raw });
    try std.testing.expect(json.equal(expected.value, actual.value));
    engine_mod.c.JS_RunGC(engine.runtime);
}
fn replay(comptime name: []const u8) !void {
    try exercise(std.testing.allocator, name, false);
}
fn probe(gpa: std.mem.Allocator, comptime name: []const u8) !void {
    exercise(gpa, name, true) catch |err| {
        const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
        // A native constructor may surface the induced host OOM as a VM
        // exception. Classify it only when this exact allocator induced OOM;
        // ordinary exceptions remain failures, and byte equality stays strict.
        if (err == error.JavaScriptException and failing.has_induced_failure) return error.OutOfMemory;
        return err;
    };
}
fn modelAllocation(gpa: std.mem.Allocator) !void {
    try probe(gpa, "model");
}
fn thenableAllocation(gpa: std.mem.Allocator) !void {
    try probe(gpa, "factory-thenable");
}
fn allocationSweep(comptime scenario: []const u8, comptime run: fn (std.mem.Allocator) anyerror!void) !void {
    if (@import("sdk_public_allocation_options").range) |range| {
        var baseline = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        try run(baseline.allocator());
        try std.testing.expectEqual(baseline.allocated_bytes, baseline.freed_bytes);
        var exercised: usize = 0;
        for (0..baseline.alloc_index) |index| {
            if (index % 8 != range) continue;
            var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = index });
            try std.testing.expectError(error.OutOfMemory, run(failing.allocator()));
            try std.testing.expect(failing.has_induced_failure);
            try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
            exercised += 1;
        }
        std.debug.print("SDK public {s} allocation range {d}/8 baseline {d} exercised {d}\n", .{ scenario, range, baseline.alloc_index, exercised });
    } else try std.testing.checkAllAllocationFailures(std.testing.allocator, run, .{});
}
test "native SDK public thinking levels persistence transcript and notifications match actual Source" {
    try replay("thinking");
}
test "native SDK public Pi mutations affect each actual session immediately inside and outside events" {
    try replay("effects");
}

test "native SDK public model mutation awaits auth preserves identity persists defaults and emits Source events" {
    try replay("model");
}

test "native SDK public model mutation holds auth boundary updates retained context scope and rejects missing credentials" {
    try replay("model-await");
}

test "native SDK public retained session mutations match Source while event context leases stay stale" {
    try replay("disposed");
}

test "native SDK public agent state aliases copy array assignments and expose scoped models last text and idle promises" {
    try replay("state");
}

test "native SDK public model and thinking setter failures preserve identity async contract and mutation ordering" {
    try replay("setter-errors");
}

test "native SDK public bound abort shutdown callbacks preserve receiver rebinding and stale lease fences" {
    try replay("context-actions");
}

test "native SDK public model getters follow Source mutation order without context JSON serialization" {
    try replay("model-getters");
}

test "native SDK public factory loading awaits genuine thenables without granting runtime admission" {
    try replay("factory-thenable");
}

test "native SDK public model mutation and native event allocation ownership is exhaustive" {
    try allocationSweep("model", modelAllocation);
}
test "native SDK public thenable factory allocation ownership is exhaustive" {
    try allocationSweep("thenable", thenableAllocation);
}
