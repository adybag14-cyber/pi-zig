const std = @import("std");
const engine_mod = @import("extensions/engine.zig");
const delta = @import("extensions/native_durable_view_delta.zig");
const vm = @import("extensions/native_values.zig");
const json = @import("durable/backend/json.zig");
const c = engine_mod.c;
fn exercise(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    return exerciseWithEngine(engine) catch |err| engine.nativeAllocationError(err, generation);
}
fn exerciseWithEngine(engine: *engine_mod.Engine) !void {
    const bytes = @embedFile("extensions/fixtures/durable-view-persistent-delta-original.json");
    const source = try engine.checked(c.JS_ParseJSON(engine.context, bytes.ptr, bytes.len, "actual-source-view-delta"));
    defer engine.freeValue(source);
    const rows = try vm.get(engine, source, "rows");
    defer engine.freeValue(rows);
    for (0..try vm.length(engine, rows)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        const base = try vm.get(engine, row, "base");
        defer engine.freeValue(base);
        const operations = try vm.get(engine, row, "ops");
        defer engine.freeValue(operations);
        const before = try engine.stringify(base);
        defer engine.gpa.free(before);
        const result = try delta.apply(engine, base, operations);
        defer engine.freeValue(result);
        const actual_text = try engine.stringify(result);
        defer engine.gpa.free(actual_text);
        const expected = try vm.get(engine, row, "result");
        defer engine.freeValue(expected);
        const expected_text = try engine.stringify(expected);
        defer engine.gpa.free(expected_text);
        var actual = try json.Owned.parse(engine.gpa, actual_text);
        defer actual.deinit();
        var wanted = try json.Owned.parse(engine.gpa, expected_text);
        defer wanted.deinit();
        try std.testing.expect(json.equal(wanted.value, actual.value));
        const after = try engine.stringify(base);
        defer engine.gpa.free(after);
        try std.testing.expectEqualStrings(before, after);
        inline for (.{ .{ "conversation", "conversationShared" }, .{ "entries", "entriesShared" } }) |field| {
            const original = try vm.get(engine, base, field[0]);
            defer engine.freeValue(original);
            const next = try vm.get(engine, result, field[0]);
            defer engine.freeValue(next);
            const shared = try vm.get(engine, row, field[1]);
            defer engine.freeValue(shared);
            try std.testing.expectEqual(c.JS_ToBool(engine.context, shared) != 0, c.JS_IsStrictEqual(engine.context, original, next));
        }
    }
}
test "native durable view persistent operations match actual Chord source and retain untouched references" {
    try exercise(std.testing.allocator);
}
test "native durable view persistent operation allocations roll back without leaks" {
    var baseline = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try exercise(baseline.allocator());
    for (0..baseline.alloc_index) |index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = index });
        exercise(failing.allocator()) catch |err| {
            if (!failing.has_induced_failure) return err;
        };
        if (failing.allocated_bytes != failing.freed_bytes) {
            std.debug.print("View delta allocation {d}/{d}: {d}/{d} bytes\n", .{ index, baseline.alloc_index, failing.allocated_bytes, failing.freed_bytes });
            return error.MemoryLeakDetected;
        }
    }
}

fn exerciseMount(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    return exerciseMountWithEngine(engine) catch |err| engine.nativeAllocationError(err, generation);
}
fn exerciseMountWithEngine(engine: *engine_mod.Engine) !void {
    try @import("extensions/abort_signal.zig").install(engine);
    const make = try engine.eval(@embedFile("extensions/fixtures/durable-view-advance-runtime.txt"), "actual-view-advance-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(make);
    var source = try json.Owned.parse(engine.gpa, @embedFile("extensions/fixtures/durable-view-advance-original.json"));
    defer source.deinit();
    for (source.value.object.get("rows").?.array.items) |row| {
        const scenario = row.object.get("scenario").?.string;
        const name = try engine.checked(c.JS_NewStringLen(engine.context, scenario.ptr, scenario.len));
        defer engine.freeValue(name);
        var arguments = [_]c.JSValue{name};
        const fixture = try engine.checked(c.JS_Call(engine.context, make, c.pi_js_undefined(), 1, &arguments));
        defer engine.freeValue(fixture);
        var values = [_]c.JSValue{c.pi_js_undefined()} ** 4;
        defer for (values) |value| engine.freeValue(value);
        inline for (.{ "mount", "event", "context", "report" }, 0..) |key, index| values[index] = try vm.get(engine, fixture, key);
        try @import("extensions/native_durable_view_mount.zig").advance(engine, c.JS_NewInt32(engine.context, 1), values[0], values[1], values[2], values[3]);
        const inspected = try vm.invoke(engine, fixture, "inspect", &.{});
        defer engine.freeValue(inspected);
        const text = try engine.stringify(inspected);
        defer engine.gpa.free(text);
        var actual = try json.Owned.parse(engine.gpa, text);
        defer actual.deinit();
        if (!json.equal(row, actual.value)) std.debug.print("View mount {s}: {s}\n", .{ scenario, text });
        try std.testing.expect(json.equal(row, actual.value));
    }
}
test "native durable view revisions match Source resets incarnation changes and observer isolation" {
    try exerciseMount(std.testing.allocator);
}
test "native durable view mount fan-out releases every failed allocation" {
    var baseline = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try exerciseMount(baseline.allocator());
    for (0..baseline.alloc_index) |index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = index });
        exerciseMount(failing.allocator()) catch |err| {
            if (!failing.has_induced_failure) return err;
        };
        if (failing.allocated_bytes != failing.freed_bytes) {
            std.debug.print("View mount allocation {d}/{d}: {d}/{d} bytes\n", .{ index, baseline.alloc_index, failing.allocated_bytes, failing.freed_bytes });
            return error.MemoryLeakDetected;
        }
    }
}
