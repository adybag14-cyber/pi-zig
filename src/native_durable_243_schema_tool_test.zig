//! Latest actual Source schema-tool results, frozen before the native port.
const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const durable = @import("extensions/native_durable.zig");
const sdk = @import("extensions/native_sdk.zig");
const json = @import("durable/backend/json.zig");
const comparison = @import("native_durable_schema_compare.zig");
const c = engine_mod.c;
const Measurements = struct {
    attempts: [64]comparison.Attempt = undefined,
    count: usize = 0,
    overflow: bool = false,
    fn observe(raw: ?*anyopaque, generation: u64, task_id: u64, elapsed_ms: u64) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        if (self.count == self.attempts.len) {
            self.overflow = true;
            return;
        }
        self.attempts[self.count] = .{ .generation = generation, .task_id = task_id, .elapsed_ms = elapsed_ms };
        self.count += 1;
    }
};

test "native durable actual 243 schema tool error results preserve own values and bounded diagnostics" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    var measurements: Measurements = .{};
    engine.native_durable_duration_observer_context = &measurements;
    engine.native_durable_duration_observer = Measurements.observe;
    const began = std.Io.Clock.awake.now(std.testing.io).toMilliseconds();
    defer std.debug.print("Actual 243 native owner elapsedMs={d} waits={d} notifications={d} raced={d} timeouts={d}\n", .{ std.Io.Clock.awake.now(std.testing.io).toMilliseconds() - began, engine.native_owner_signal.waits, engine.native_owner_signal.observe(), engine.native_owner_signal.raced, engine.native_owner_signal.timeouts });
    try @import("extensions/native_stream.zig").install(engine);
    try durable.install(engine);
    try @import("extensions/text_decoder.zig").install(engine);
    const result = engine.evalModule(@embedFile("durable/fixtures/durable-243-schema-tool-program.txt"), "actual-243-schema-tools") catch |err| {
        std.debug.print("Actual 243 schema tools {s}: {s}\n", .{ @errorName(err), engine.last_error orelse "no VM diagnostic" });
        @import("extensions/native_durable_tasks.zig").printFailureDiagnostics(engine);
        if (engine.captured_exception) |reason| for ([_][:0]const u8{ "name", "message", "stack" }) |key| {
            // Failure-only reads never checked()/capture another exception.
            const value = c.JS_GetPropertyStr(engine.context, reason, key.ptr);
            if (c.JS_IsException(value)) {
                engine.freeValue(c.JS_GetException(engine.context));
                continue;
            }
            defer engine.freeValue(value);
            var length: usize = 0;
            if (c.JS_ToCStringLen(engine.context, &length, value)) |bytes| {
                defer c.JS_FreeCString(engine.context, bytes);
                std.debug.print("Actual 243 schema tools original {s}: {s}\n", .{ key, bytes[0..length] });
            } else engine.freeValue(c.JS_GetException(engine.context));
        };
        return err;
    };
    engine.freeValue(result);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const trace = try sdk.get(engine, global, "latestSchemaToolErrorTrace");
    defer engine.freeValue(trace);
    var actual = try durable.owned(engine, trace);
    defer actual.deinit();
    var expected = try json.Owned.parse(std.testing.allocator, @embedFile("durable/fixtures/durable-243-schema-tool-source.json"));
    defer expected.deinit();
    const encoded = try json.stringify(std.testing.allocator, actual.value);
    defer std.testing.allocator.free(encoded);
    std.debug.print("ACTUAL_243_SCHEMA_TOOL_RAW={s}\n", .{encoded});
    try std.testing.expect(!measurements.overflow);
    try std.testing.expectEqual(@as(usize, 34), measurements.count);
    // Genuine original Source PID45436 ran for 2011.726ms. Keep its raw trace;
    // only these sixteen measured fields vary between independent real runs.
    try std.testing.expectEqual(@as(usize, 16), try comparison.compare(actual.value, expected.value, .{ .native_attempts = measurements.attempts[0..measurements.count], .source_elapsed_ms = 2012 }));
    for (measurements.attempts[0..measurements.count]) |attempt| std.debug.print("ACTUAL_243_NATIVE_ATTEMPT generation={d} taskId={d} elapsedMs={d}\n", .{ attempt.generation, attempt.task_id, attempt.elapsed_ms });
    for ((try json.required(expected.value, "rows")).array.items, 0..) |row, index| {
        const nested = (try json.required(row, "nested")).array.items;
        if (nested.len != 0 and json.get(nested[0], "durationMs") != null) std.debug.print("ACTUAL_243_MEASUREMENT_PATH=rows[{d}].nested[0].durationMs\n", .{index});
    }
}
