const std = @import("std");
const engine_mod = @import("engine.zig");
const durable = @import("native_durable.zig");
const sdk = @import("native_sdk.zig");
const json = @import("../durable/backend/json.zig");
const c = engine_mod.c;
fn exercise(program: []const u8, fixture: []const u8, require_drain: bool) !void {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 5000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const value = engine.evalModule(program, "actual-storage-context-protocol") catch |err| {
        std.debug.print("Actual Storage context protocol: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(value);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const trace = try sdk.get(engine, global, "storageContextTrace");
    defer engine.freeValue(trace);
    if (require_drain) {
        const harness = try sdk.get(engine, global, "storageContextLastHarness");
        defer engine.freeValue(harness);
        const owner = try @import("native_durable_harness.zig").state(engine, harness);
        const native = try durable.state(engine, owner.session);
        const drain = native.storage_drain orelse return error.StorageDrainWasNotPrepared;
        // A never-used preallocated drain remains pending. Fulfillment proves
        // close actually waited through the nonblocking owner continuation.
        try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, drain.promise));
    }
    var actual = try durable.owned(engine, trace);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, fixture);
    defer expected.deinit();
    if (!json.equal(expected.value, actual.value)) {
        const encoded = try json.stringify(std.testing.allocator, actual.value);
        defer std.testing.allocator.free(encoded);
        std.debug.print("Actual Storage context trace: {s}\n", .{encoded});
        return error.SourceContextProtocolMismatch;
    }
}
test "native durable VM actual Storage context requests exact Source bounds and range with original contexts" {
    try exercise(@embedFile("../durable/fixtures/durable-custom-storage-source14-program.txt"), @embedFile("../durable/fixtures/durable-custom-storage-source14.json"), false);
}
test "native durable VM actual Storage context preabort and admitted read across close preserve Source values" {
    try exercise(@embedFile("../durable/fixtures/durable-custom-storage-source15-program.txt"), @embedFile("../durable/fixtures/durable-custom-storage-source15.json"), true);
}
