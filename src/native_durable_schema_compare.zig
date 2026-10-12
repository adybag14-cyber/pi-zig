//! Preserve both raw traces. Only the sixteen known, top-level executed nested
//! result durations are independent measurements; all other JSON stays exact.
const std = @import("std");
const json = @import("durable/backend/json.zig");
const modes = [_][]const u8{
    "nested-error-text",   "nested-thrown",         "nested-invalid-structured", "nested-error-structured", "nested-success-structured", "model-error-text",
    "nested-unavailable",  "nested-explained",      "nested-warn-text",          "nested-empty-text",       "nested-image-only",         "nested-mixed-output",
    "nested-bounded-text", "nested-reported-error", "nested-no-schema-error",    "nested-truthy-error",     "nested-after-hook-error",   "nested-after-hook-explained",
};
pub const Attempt = struct { generation: u64, task_id: u64, elapsed_ms: u64 };
pub const Bounds = struct { native_attempts: []const Attempt, source_elapsed_ms: u64, precision_ms: u64 = 1 };
fn nativeElapsed(attempts: []const Attempt, generation: u64, task_id: u64) !u64 {
    var found: ?u64 = null;
    for (attempts) |attempt| if (attempt.generation == generation and attempt.task_id == task_id) {
        if (found != null) return error.DuplicateAttemptMeasurement;
        found = attempt.elapsed_ms;
    };
    return found orelse error.MissingAttemptMeasurement;
}
fn numeric(value: json.Value, elapsed: u64, precision: u64) !void {
    const number: f64 = switch (value) {
        .integer => |integer| @floatFromInt(integer),
        .float => |number| number,
        else => return error.DurationType,
    };
    if (!std.math.isFinite(number) or number < 0 or @floor(number) != number) return error.InvalidDuration;
    if (number > @as(f64, @floatFromInt(elapsed)) + @as(f64, @floatFromInt(precision))) return error.DurationOutsideAttempt;
}
fn exact(actual: json.Value, expected: json.Value) !void {
    if (!json.equal(actual, expected)) return error.SourceSchemaTraceMismatch;
}
/// Returns the number of explicitly whitelisted measurement paths. Neither
/// argument is mutated, cloned, stripped, rounded, or filled with fake zeros.
pub fn compare(actual: json.Value, expected: json.Value, bounds: Bounds) !usize {
    if (actual != .object or expected != .object or actual.object.count() != expected.object.count()) return error.SourceSchemaTraceMismatch;
    var top = expected.object.iterator();
    while (top.next()) |field| if (!std.mem.eql(u8, field.key_ptr.*, "rows")) try exact(json.get(actual, field.key_ptr.*) orelse return error.SourceSchemaTraceMismatch, field.value_ptr.*);
    const rows = json.get(actual, "rows") orelse return error.SourceSchemaTraceMismatch;
    const originals = json.get(expected, "rows") orelse return error.SourceSchemaTraceMismatch;
    if (rows != .array or originals != .array or rows.array.items.len != modes.len or originals.array.items.len != modes.len) return error.SourceSchemaTraceMismatch;
    var measurements: usize = 0;
    for (rows.array.items, originals.array.items, modes, 0..) |row, original, mode, row_index| {
        if (row != .object or original != .object or row.object.count() != original.object.count()) return error.SourceSchemaTraceMismatch;
        const original_mode = json.get(original, "mode") orelse return error.SourceSchemaTraceMismatch;
        if (original_mode != .string or !std.mem.eql(u8, original_mode.string, mode)) return error.SourceSchemaTraceMismatch;
        var fields = original.object.iterator();
        while (fields.next()) |field| if (!std.mem.eql(u8, field.key_ptr.*, "nested")) try exact(json.get(row, field.key_ptr.*) orelse return error.SourceSchemaTraceMismatch, field.value_ptr.*);
        const nested = json.get(row, "nested") orelse return error.SourceSchemaTraceMismatch;
        const source = json.get(original, "nested") orelse return error.SourceSchemaTraceMismatch;
        const has_result = !std.mem.eql(u8, mode, "model-error-text");
        if (nested != .array or source != .array or nested.array.items.len != @intFromBool(has_result) or source.array.items.len != @intFromBool(has_result)) return error.SourceSchemaTraceMismatch;
        if (!has_result) continue;
        const result = nested.array.items[0];
        const original_result = source.array.items[0];
        if (std.mem.eql(u8, mode, "nested-unavailable")) {
            try exact(result, original_result);
            continue;
        }
        if (result != .object or original_result != .object) return error.SourceSchemaTraceMismatch;
        const duration = json.get(result, "durationMs") orelse return error.MissingDuration;
        const original_duration = json.get(original_result, "durationMs") orelse return error.MissingSourceDuration;
        if (result.object.count() != original_result.object.count()) return error.SourceSchemaTraceMismatch;
        var values = original_result.object.iterator();
        while (values.next()) |field| if (!std.mem.eql(u8, field.key_ptr.*, "durationMs")) try exact(json.get(result, field.key_ptr.*) orelse return error.SourceSchemaTraceMismatch, field.value_ptr.*);
        const task_id = try json.asInteger(json.get(result, "taskId") orelse return error.SourceSchemaTraceMismatch);
        try numeric(duration, try nativeElapsed(bounds.native_attempts, row_index + 1, task_id), bounds.precision_ms);
        try numeric(original_duration, bounds.source_elapsed_ms, bounds.precision_ms);
        measurements += 1;
    }
    return measurements;
}

fn firstResult(value: *json.Value) *json.Value {
    const rows = value.object.getPtr("rows").?;
    const nested = rows.array.items[0].object.getPtr("nested").?;
    return &nested.array.items[0];
}
const fixture_attempts = blk: {
    var attempts: [modes.len]Attempt = undefined;
    for (&attempts, 0..) |*attempt, index| attempt.* = .{ .generation = index + 1, .task_id = 14, .elapsed_ms = 100 };
    break :blk attempts;
};
test "native schema duration measurements preserve raw values and compare every other field" {
    const raw = @embedFile("durable/fixtures/durable-243-schema-tool-source.json");
    var source = try json.Owned.parse(std.testing.allocator, raw);
    defer source.deinit();
    var actual = try json.Owned.parse(std.testing.allocator, raw);
    defer actual.deinit();
    firstResult(&actual.value).object.getPtr("durationMs").?.* = .{ .integer = 1 };
    try std.testing.expectEqual(@as(usize, 16), try compare(actual.value, source.value, .{ .native_attempts = &fixture_attempts, .source_elapsed_ms = 100 }));
    try std.testing.expectEqual(@as(f64, 1), try json.asNumber(firstResult(&actual.value).object.get("durationMs").?));
    try std.testing.expectEqual(@as(f64, 0), try json.asNumber(firstResult(&source.value).object.get("durationMs").?));
    firstResult(&actual.value).object.getPtr("taskId").?.* = .{ .integer = 999 };
    try std.testing.expectError(error.SourceSchemaTraceMismatch, compare(actual.value, source.value, .{ .native_attempts = &fixture_attempts, .source_elapsed_ms = 100 }));
}
test "native schema duration measurements reject invalid missing and out of bounds observations" {
    const raw = @embedFile("durable/fixtures/durable-243-schema-tool-source.json");
    var source = try json.Owned.parse(std.testing.allocator, raw);
    defer source.deinit();
    const invalid = [_]json.Value{ .{ .integer = -1 }, .{ .float = std.math.nan(f64) }, .{ .float = std.math.inf(f64) }, .{ .float = 0.5 }, .{ .string = "0" }, .null, .{ .integer = 102 } };
    for (invalid, 0..) |value, index| {
        var actual = try json.Owned.parse(std.testing.allocator, raw);
        defer actual.deinit();
        firstResult(&actual.value).object.getPtr("durationMs").?.* = value;
        const outcome = compare(actual.value, source.value, .{ .native_attempts = &fixture_attempts, .source_elapsed_ms = 100 });
        if (index < 4) try std.testing.expectError(error.InvalidDuration, outcome) else if (index < 6) try std.testing.expectError(error.DurationType, outcome) else try std.testing.expectError(error.DurationOutsideAttempt, outcome);
    }
    var missing = try json.Owned.parse(std.testing.allocator, raw);
    defer missing.deinit();
    _ = firstResult(&missing.value).object.swapRemove("durationMs");
    try std.testing.expectError(error.MissingDuration, compare(missing.value, source.value, .{ .native_attempts = &fixture_attempts, .source_elapsed_ms = 100 }));
    try std.testing.expectError(error.MissingSourceDuration, compare(source.value, missing.value, .{ .native_attempts = &fixture_attempts, .source_elapsed_ms = 100 }));
    var bad_source = try json.Owned.parse(std.testing.allocator, raw);
    defer bad_source.deinit();
    firstResult(&bad_source.value).object.getPtr("durationMs").?.* = .{ .integer = -1 };
    try std.testing.expectError(error.InvalidDuration, compare(source.value, bad_source.value, .{ .native_attempts = &fixture_attempts, .source_elapsed_ms = 100 }));
    firstResult(&bad_source.value).object.getPtr("durationMs").?.* = .{ .integer = 102 };
    try std.testing.expectError(error.DurationOutsideAttempt, compare(source.value, bad_source.value, .{ .native_attempts = &fixture_attempts, .source_elapsed_ms = 100 }));
}
test "native schema duration measurements reject extra paths rows and altered diagnostics" {
    const raw = @embedFile("durable/fixtures/durable-243-schema-tool-source.json");
    var source = try json.Owned.parse(std.testing.allocator, raw);
    defer source.deinit();
    for (0..4) |mode| {
        var actual = try json.Owned.parse(std.testing.allocator, raw);
        defer actual.deinit();
        const a = actual.arena.allocator();
        switch (mode) {
            0 => try actual.value.object.put(a, "durationMs", .{ .integer = 0 }),
            1 => {
                var details: json.Value = .{ .object = .empty };
                try details.object.put(a, "durationMs", .{ .integer = 0 });
                try firstResult(&actual.value).object.put(a, "details", details);
            },
            2 => {
                const nested = actual.value.object.getPtr("rows").?.array.items[0].object.getPtr("nested").?;
                try nested.array.append(try json.clone(a, nested.array.items[0]));
            },
            3 => firstResult(&actual.value).object.getPtr("diagnostics").?.array.items[0].object.getPtr("message").?.* = .{ .string = "changed" },
            else => unreachable,
        }
        try std.testing.expectError(error.SourceSchemaTraceMismatch, compare(actual.value, source.value, .{ .native_attempts = &fixture_attempts, .source_elapsed_ms = 100 }));
    }
}
test "native schema duration measurements require a unique genuine attempt identity" {
    const raw = @embedFile("durable/fixtures/durable-243-schema-tool-source.json");
    var source = try json.Owned.parse(std.testing.allocator, raw);
    defer source.deinit();
    try std.testing.expectError(error.MissingAttemptMeasurement, compare(source.value, source.value, .{ .native_attempts = &.{}, .source_elapsed_ms = 100 }));
    var duplicate: [modes.len + 1]Attempt = undefined;
    @memcpy(duplicate[0..modes.len], &fixture_attempts);
    duplicate[modes.len] = fixture_attempts[0];
    try std.testing.expectError(error.DuplicateAttemptMeasurement, compare(source.value, source.value, .{ .native_attempts = &duplicate, .source_elapsed_ms = 100 }));
}
