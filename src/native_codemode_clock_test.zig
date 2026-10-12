//! Actual upstream WASM observations; this gate qualifies context clock/seed only.
const std = @import("std");
const em = @import("extensions/engine.zig");
const clock_mod = @import("mcp/codemode_clock.zig");
const json = @import("mcp/protocol.zig").json;
test "native CodeMode deterministic context inventory records every actual compiled test" {
    const functions = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, functions.len);
    defer std.testing.allocator.free(names);
    for (functions, names) |function, *name| name.* = function.name;
    const bytes = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(bytes);
    std.debug.print("CODEMODE_CLOCK_TEST_INVENTORY={s}\n", .{bytes});
}
test "native CodeMode deterministic context matches all 48 actual latest Source clock seed and UTC observations" {
    var source = try json.Owned.parse(std.testing.allocator, @embedFile("mcp/fixtures/codemode-clock-045-source.json"));
    defer source.deinit();
    const rows = source.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 48), rows.len);
    for (rows, 0..) |row, index| {
        var clock = try clock_mod.Clock.init(try json.asNumber(row.object.get("startedAt").?), try json.asNumber(row.object.get("seed").?));
        const engine = try em.Engine.init(std.testing.allocator, .{ .deterministic_clock = clock });
        defer engine.deinit();
        if (row.object.get("now")) |now| {
            try clock.advance(try json.asNumber(now));
            try std.testing.expectEqual(@as(c_int, 0), em.c.JS_PIAdvanceDeterministicTime(engine.runtime, clock.realtime(), clock.elapsed()));
        }
        const result = try engine.eval("[Date.now(),performance.now(),performance.timeOrigin,new Date().toISOString(),new Date(2026,0,15,10).toISOString(),new Date(0).getHours(),new Date(0).getTimezoneOffset(),Math.random(),Math.random()]", "actual-clock-context.js", em.c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(result);
        const encoded = try engine.stringify(result);
        defer std.testing.allocator.free(encoded);
        var actual = try json.Owned.parse(std.testing.allocator, encoded);
        defer actual.deinit();
        const expected = row.object.get("result").?.object.get("value").?;
        if (!json.equal(expected, actual.value)) std.debug.print("CodeMode clock Source case {d} actual={s}\n", .{ index, encoded });
        try std.testing.expect(json.equal(expected, actual.value));
    }
}

test "native CodeMode deterministic runtimes retain independent seed clock and genuine Date methods" {
    var first_clock = try clock_mod.Clock.init(1234.5, 1);
    const first = try em.Engine.init(std.testing.allocator, .{ .deterministic_clock = first_clock });
    defer first.deinit();
    const second = try em.Engine.init(std.testing.allocator, .{ .deterministic_clock = try clock_mod.Clock.init(100, 2) });
    defer second.deinit();
    try first_clock.advance(2345.5);
    try std.testing.expectEqual(@as(c_int, 0), em.c.JS_PIAdvanceDeterministicTime(first.runtime, first_clock.realtime(), first_clock.elapsed()));
    const a = try first.eval("Date.now()", "first-clock.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer first.freeValue(a);
    const b = try second.eval("Date.now()", "second-clock.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer second.freeValue(b);
    var one: f64 = 0;
    var two: f64 = 0;
    try std.testing.expectEqual(@as(c_int, 0), em.c.JS_ToFloat64(first.context, &one, a));
    try std.testing.expectEqual(@as(c_int, 0), em.c.JS_ToFloat64(second.context, &two, b));
    try std.testing.expectEqual(@as(f64, 2346), one);
    try std.testing.expectEqual(@as(f64, 100), two);
}

test "native CodeMode deterministic context rejects invalid host input and late reseeding without mutation" {
    try std.testing.expectError(error.InvalidStartedAt, em.Engine.init(std.testing.allocator, .{ .deterministic_clock = .{ .started_at = std.math.nan(f64), .now = 0, .seed = 0 } }));
    try std.testing.expectError(error.InvalidClock, em.Engine.init(std.testing.allocator, .{ .deterministic_clock = .{ .started_at = 1, .now = 0, .seed = 0 } }));
    const engine = try em.Engine.init(std.testing.allocator, .{ .deterministic_clock = try clock_mod.Clock.init(1234.5, 1) });
    defer engine.deinit();
    try std.testing.expectEqual(@as(c_int, -1), em.c.JS_PISetDeterministicTime(engine.runtime, 2, 0, 0));
    try std.testing.expectEqual(@as(c_int, -1), em.c.JS_PIAdvanceDeterministicTime(engine.runtime, std.math.nan(f64), 0));
    try std.testing.expectEqual(@as(c_int, -1), em.c.JS_PIAdvanceDeterministicTime(engine.runtime, 0, std.math.inf(f64)));
    const observed = try engine.eval("Date.now()", "invalid-clock-unchanged.js", em.c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(observed);
    var now: f64 = 0;
    try std.testing.expectEqual(@as(c_int, 0), em.c.JS_ToFloat64(engine.context, &now, observed));
    try std.testing.expectEqual(@as(f64, 1235), now);
    const ordinary = try em.Engine.init(std.testing.allocator, .{});
    defer ordinary.deinit();
    try std.testing.expectEqual(@as(c_int, -1), em.c.JS_PIAdvanceDeterministicTime(ordinary.runtime, 0, 0));
}

test "native CodeMode deterministic context releases every failed owner allocation" {
    const Probe = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const engine = try em.Engine.init(gpa, .{ .deterministic_clock = try clock_mod.Clock.init(1234.5, 1) });
            defer engine.deinit();
            const observed = try engine.eval("[Date.now(), Math.random(), new Date(0).getHours()]", "owned-clock.js", em.c.JS_EVAL_TYPE_GLOBAL);
            defer engine.freeValue(observed);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{});
}
