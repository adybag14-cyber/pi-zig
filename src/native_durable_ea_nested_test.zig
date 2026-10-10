const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const durable = @import("extensions/native_durable.zig");
const sdk = @import("extensions/native_sdk.zig");
const json = @import("durable/backend/json.zig");
const c = engine_mod.c;

fn normalizeDurations(value: *json.Value) !void {
    switch (value.*) {
        .object => |*object| {
            var fields = object.iterator();
            while (fields.next()) |field| {
                if (std.mem.eql(u8, field.key_ptr.*, "durationMs")) {
                    const number: f64 = switch (field.value_ptr.*) {
                        .integer => |n| @floatFromInt(n),
                        .float => |n| n,
                        else => return error.InvalidToolDuration,
                    };
                    if (!std.math.isFinite(number) or number < 0 or number != @trunc(number)) return error.InvalidToolDuration;
                    // Performance durations differ across hosts. Preserve the
                    // actual Source field and numeric contract; no clock calls
                    // or call counts are changed by this comparison.
                    field.value_ptr.* = .{ .integer = 0 };
                } else try normalizeDurations(field.value_ptr);
            }
        },
        .array => |array| for (array.items) |*item| try normalizeDurations(item),
        else => {},
    }
}

test "native durable ea nested calls use one keyed document and carry results through actual Harness events" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/text_decoder.zig").install(engine);
    const result = engine.evalModule(@embedFile("durable/fixtures/durable-ea-nested-call-program.txt"), "actual-ea-nested-call-workflow") catch |err| {
        std.debug.print("Actual ea nested call {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "no VM diagnostic" });
        return err;
    };
    engine.freeValue(result);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const trace = try sdk.get(engine, global, "eaNestedTrace");
    defer engine.freeValue(trace);
    var actual = try durable.owned(engine, trace);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-ea-nested-call.json"));
    defer expected.deinit();
    try normalizeDurations(&actual.value);
    try normalizeDurations(&expected.value);
    if (!json.equal(actual.value, expected.value)) {
        const encoded = try json.stringify(std.testing.allocator, actual.value);
        defer std.testing.allocator.free(encoded);
        std.debug.print("Actual ea nested trace: {s}\n", .{encoded});
        return error.SourceNestedCallWorkflowMismatch;
    }
}
