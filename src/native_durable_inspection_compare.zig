//! Test-only comparison of actual wall-time observations; product clocks remain real.
const std = @import("std");
const json = @import("durable/backend/json.zig");
pub fn normalize(actual: *json.Value, expected: *json.Value, began: i64, ended: i64) !void {
    var timestamps: std.AutoHashMap(u64, i64) = .init(std.testing.allocator);
    defer timestamps.deinit();
    const actual_rows = (try json.required(actual.*, "rows")).array.items;
    const expected_rows = (try json.required(expected.*, "rows")).array.items;
    try std.testing.expectEqual(expected_rows.len, actual_rows.len);
    for (actual_rows, expected_rows, 0..) |*row, *source_row, index| {
        // Rows 0..2 share one real Harness. Each later row opens a new one.
        if (index >= 3) timestamps.clearRetainingCapacity();
        for ([_][]const u8{ "invocation", "inspection" }) |name| {
            const view = row.object.getPtr(name) orelse continue;
            const source_view = source_row.object.getPtr(name) orelse return error.SourceInspectionFieldMissing;
            const records = (try json.required(view.*, "tasks")).array.items;
            const source_records = (try json.required(source_view.*, "tasks")).array.items;
            try std.testing.expectEqual(source_records.len, records.len);
            for (records, source_records) |*item, *source_item| {
                const record = item.object.getPtr("record") orelse return error.InspectionRecordMissing;
                const source_record = source_item.object.getPtr("record") orelse return error.SourceInspectionRecordMissing;
                const timestamp = record.object.getPtr("startedAt") orelse continue;
                const source_timestamp = source_record.object.getPtr("startedAt") orelse return error.SourceInspectionTimeMissing;
                // Owned JSON represents JavaScript Numbers as f64 even when
                // integral. Validate number semantics, not the parser's tag.
                const milliseconds: i64 = @intCast(json.asInteger(timestamp.*) catch return error.InspectionTimeNotInteger);
                _ = json.asInteger(source_timestamp.*) catch return error.InspectionTimeNotInteger;
                if (milliseconds < began or milliseconds > ended) return error.InspectionTimeOutsideExecution;
                const id = try json.asInteger(try json.required(record.*, "id"));
                const known = try timestamps.getOrPut(id);
                if (known.found_existing) {
                    if (known.value_ptr.* != milliseconds) return error.InspectionTimeChanged;
                } else known.value_ptr.* = milliseconds;
                timestamp.* = .null;
                source_timestamp.* = .null;
            }
        }
    }
}

fn verify(actual: *json.Value, expected: *json.Value, began: i64, ended: i64) !void {
    try normalize(actual, expected, began, ended);
    if (!json.equal(actual.*, expected.*)) return error.SourceInspectionContractMismatch;
}
fn recordAt(value: *json.Value, row: usize) *json.Value {
    return value.object.getPtr("rows").?.array.items[row].object.getPtr("inspection").?.object.getPtr("tasks").?.array.items[0].object.getPtr("record").?;
}
test "native durable inspection timestamp comparison rejects invalid wall observations" {
    // Pure comparator inputs, never a replacement product clock or Source
    // capture. Read the real clock and test both sides of its accepted bounds.
    const now = std.Io.Clock.real.now(std.testing.io).toMilliseconds();
    const fixture = "{\"rows\":[{\"inspection\":{\"tasks\":[{\"record\":{\"id\":7,\"startedAt\":42}}]}},{\"inspection\":{\"tasks\":[{\"record\":{\"id\":7,\"startedAt\":42}}]}}]}";
    const Modes = enum { valid, valid_float, missing, wrong_type, fractional, nan, infinity, before, after, unstable, source_missing, other_field };
    inline for (std.meta.tags(Modes)) |mode| {
        var actual = try json.Owned.parse(std.testing.allocator, fixture);
        defer actual.deinit();
        var expected = try json.Owned.parse(std.testing.allocator, fixture);
        defer expected.deinit();
        for (0..2) |row| recordAt(&actual.value, row).object.getPtr("startedAt").?.* = .{ .integer = now };
        switch (mode) {
            .valid => {},
            .valid_float => for (0..2) |row| {
                recordAt(&actual.value, row).object.getPtr("startedAt").?.* = .{ .float = @floatFromInt(now) };
            },
            .missing => {
                _ = recordAt(&actual.value, 0).object.swapRemove("startedAt");
            },
            .wrong_type => recordAt(&actual.value, 0).object.getPtr("startedAt").?.* = .{ .string = "not a time" },
            .fractional => recordAt(&actual.value, 0).object.getPtr("startedAt").?.* = .{ .float = @as(f64, @floatFromInt(now)) + 0.5 },
            .nan => recordAt(&actual.value, 0).object.getPtr("startedAt").?.* = .{ .float = std.math.nan(f64) },
            .infinity => recordAt(&actual.value, 0).object.getPtr("startedAt").?.* = .{ .float = std.math.inf(f64) },
            .before => recordAt(&actual.value, 0).object.getPtr("startedAt").?.* = .{ .integer = now - 1 },
            .after => recordAt(&actual.value, 0).object.getPtr("startedAt").?.* = .{ .integer = now + 2 },
            .unstable => recordAt(&actual.value, 1).object.getPtr("startedAt").?.* = .{ .integer = now + 1 },
            .source_missing => {
                _ = recordAt(&expected.value, 0).object.swapRemove("startedAt");
            },
            .other_field => recordAt(&actual.value, 1).object.getPtr("id").?.* = .{ .integer = 8 },
        }
        switch (mode) {
            .valid, .valid_float => try verify(&actual.value, &expected.value, now, now + 1),
            .missing, .other_field => try std.testing.expectError(error.SourceInspectionContractMismatch, verify(&actual.value, &expected.value, now, now + 1)),
            .wrong_type, .fractional, .nan, .infinity => try std.testing.expectError(error.InspectionTimeNotInteger, verify(&actual.value, &expected.value, now, now + 1)),
            .before, .after => try std.testing.expectError(error.InspectionTimeOutsideExecution, verify(&actual.value, &expected.value, now, now + 1)),
            .unstable => try std.testing.expectError(error.InspectionTimeChanged, verify(&actual.value, &expected.value, now, now + 1)),
            .source_missing => try std.testing.expectError(error.SourceInspectionTimeMissing, verify(&actual.value, &expected.value, now, now + 1)),
        }
    }
}
