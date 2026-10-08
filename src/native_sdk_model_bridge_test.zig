const std = @import("std");
const sdk = @import("extensions/native_sdk.zig");
const bridge = @import("extensions/native_sdk_model_bridge.zig");
const engine_mod = @import("extensions/engine.zig");
const c = engine_mod.c;
const Input = struct { schemaVersion: u32, sourceCommit: []const u8, inputSha256: []const u8, input: []const u8 };
fn equal(expected: std.json.Value, actual: std.json.Value) anyerror!void {
    try std.testing.expectEqual(@as(std.meta.Tag(std.json.Value), expected), @as(std.meta.Tag(std.json.Value), actual));
    switch (expected) {
        .object => |object| {
            try std.testing.expectEqual(object.count(), actual.object.count());
            var entries = object.iterator();
            while (entries.next()) |entry| try equal(entry.value_ptr.*, actual.object.get(entry.key_ptr.*) orelse return error.MissingSDKBridgeField);
        },
        .array => |array| {
            try std.testing.expectEqual(array.items.len, actual.array.items.len);
            for (array.items, actual.array.items) |a, b| try equal(a, b);
        },
        .string => |text| try std.testing.expectEqualStrings(text, actual.string),
        .integer => |value| try std.testing.expectEqual(value, actual.integer),
        .float => |value| try std.testing.expectEqual(value, actual.float),
        .bool => |value| try std.testing.expectEqual(value, actual.bool),
        .null => {},
        else => return error.InvalidSDKBridgeValue,
    }
}
fn induced(gpa: std.mem.Allocator, allocation_probe: bool) !void {
    if (!allocation_probe) return;
    const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
    // Source best-effort refresh/error results can observe an OOM rather than
    // rejecting it. Stop after observing that point; all owner teardown still
    // runs under the testing allocator's leak and double-free checks.
    if (failing.has_induced_failure) return error.OutOfMemory;
}
fn result(gpa: std.mem.Allocator, bytes: []const u8, expected: std.json.Value, status: []const u8, allocation_probe: bool) !void {
    try induced(gpa, allocation_probe);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, bytes, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings(status, parsed.value.object.get("status").?.string);
    if (std.mem.eql(u8, status, "complete")) try equal(expected, parsed.value.object.get("result").?);
}
const Interruption = struct {
    flag: *std.atomic.Value(bool),
    lease: ?bridge.Lease = null,
    fired: bool = false,
    fn pump(engine: *engine_mod.Engine) !bool {
        const self: *@This() = @ptrCast(@alignCast(engine.host_control_context.?));
        if (self.fired) return false;
        self.fired = true;
        if (self.lease) |lease| try bridge.retire(engine, lease) else self.flag.store(true, .release);
        return true;
    }
};
fn exercise(gpa: std.mem.Allocator, allocation_probe: bool) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("extensions/native_stream.zig").install(engine);
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    try sdk.install(engine, exports);
    try engine.registerValueModule("@earendil-works/pi-coding-agent", exports);
    var input = try std.json.parseFromSlice(Input, gpa, @embedFile("extensions/fixtures/sdk-model-bridge-6fb2e78.input.json"), .{});
    defer input.deinit();
    try std.testing.expectEqual(@as(u32, 1), input.value.schemaVersion);
    try std.testing.expectEqualStrings("6fb2e7815167e6b19006fc526d1a5d0f5f998787", input.value.sourceCommit);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input.value.input, &digest, .{});
    try std.testing.expectEqualStrings(&std.fmt.bytesToHex(digest, .lower), input.value.inputSha256);
    const evaluation = try engine.evalModule(input.value.input, "sdk-model-bridge-source.mjs");
    defer engine.freeValue(evaluation);
    const settled = try engine.awaitValue(evaluation);
    defer engine.freeValue(settled);
    try induced(gpa, allocation_probe);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const runtime = try sdk.get(engine, global, "bridgeRuntime");
    defer engine.freeValue(runtime);
    const lease = try bridge.admit(engine, runtime, 41);
    try std.testing.expectEqual(lease, try bridge.admit(engine, runtime, 41));
    var expected = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("extensions/fixtures/sdk-model-bridge-6fb2e78.json"), .{});
    defer expected.deinit();
    var flag: std.atomic.Value(bool) = .init(false);
    const control: bridge.Control = .{ .request_id = 7, .abort_flag = &flag };
    const cases = [_]struct { operation: bridge.Operation, request: []const u8, field: []const u8 }{
        .{ .operation = .query, .request = "{\"method\":\"getAllModels\",\"args\":[\"bridge\"]}", .field = "all" },
        .{ .operation = .query, .request = "{\"method\":\"getModel\",\"args\":[\"router\",\"virtual\"]}", .field = "virtual" },
        .{ .operation = .classify, .request = "{\"model\":{\"provider\":\"bridge\",\"id\":\"classifier\"},\"context\":{\"state\":{},\"questions\":{\"q\":{\"type\":\"bool\",\"instructions\":\"q\",\"criteria\":{\"true\":\"yes\",\"false\":\"no\"}}}}}", .field = "classified" },
        .{ .operation = .generate_images, .request = "{\"model\":{\"provider\":\"bridge\",\"id\":\"image\"},\"context\":{\"input\":[{\"type\":\"text\",\"text\":\"fixture\"}]}}", .field = "generated" },
    };
    for (cases) |case| {
        const bytes = try bridge.dispatchJson(engine, gpa, lease, case.operation, case.request, control);
        defer gpa.free(bytes);
        try result(gpa, bytes, expected.value.object.get(case.field).?, "complete", allocation_probe);
    }
    flag.store(true, .release);
    const aborted = try bridge.dispatchJson(engine, gpa, lease, .query, "{}", control);
    defer gpa.free(aborted);
    try result(gpa, aborted, .null, "aborted", allocation_probe);
    flag.store(false, .release);
    const expired = try bridge.dispatchJson(engine, gpa, lease, .query, "{}", .{ .request_id = 8, .abort_flag = &flag, .deadline_ms = 0 });
    defer gpa.free(expired);
    try result(gpa, expired, .null, "timed_out", allocation_probe);
    var interruption: Interruption = .{ .flag = &flag };
    engine.host_control_context = &interruption;
    engine.host_control_pump = Interruption.pump;
    const cancelled = try bridge.dispatchJson(engine, gpa, lease, .classify, "{\"model\":{\"provider\":\"bridge\",\"id\":\"classifier\"},\"context\":{\"block\":true,\"state\":{},\"questions\":{}}}", control);
    defer gpa.free(cancelled);
    try result(gpa, cancelled, .null, "aborted", allocation_probe);
    try std.testing.expect(engine.host_control_context == @as(?*anyopaque, &interruption) and engine.host_control_pump == @as(?*const fn (*engine_mod.Engine) anyerror!bool, Interruption.pump));
    flag.store(false, .release);
    interruption = .{ .flag = &flag, .lease = lease };
    const retired = try bridge.dispatchJson(engine, gpa, lease, .query, "{\"method\":\"getAvailable\",\"args\":[\"bridge\"]}", control);
    defer gpa.free(retired);
    try result(gpa, retired, .null, "retired", allocation_probe);
    engine.host_control_context = null;
    engine.host_control_pump = null;
    _ = bridge.dispatchJson(engine, gpa, lease, .query, "{}", control) catch |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.RetiredNativeSDKModelLease, err);
        try induced(gpa, allocation_probe);
        const next = try bridge.admit(engine, runtime, 42);
        try bridge.retire(engine, next);
        c.JS_RunGC(engine.runtime);
        return;
    };
    return error.RetiredSDKBridgeAccepted;
}
test "SDK model bridge exact Source catalog virtual classifier and image results remain owner bound" {
    try exercise(std.testing.allocator, false);
}
test "SDK model bridge allocation failure cancellation generation retirement and GC release ownership" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            exercise(gpa, true) catch |err| {
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                if (failing.has_induced_failure and (err == error.OutOfMemory or err == error.JavaScriptException)) return error.OutOfMemory;
                return err;
            };
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
