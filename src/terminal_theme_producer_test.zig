const std = @import("std");
const ui = @import("extensions/ui.zig");
const producer_mod = @import("extensions/terminal_theme_producer.zig");
test "native terminal report producer publishes cached colors retains selected resource and suppresses duplicate revisions" {
    const gpa = std.testing.allocator;
    var controller = try ui.Controller.init(gpa, std.testing.io, true, 100);
    defer controller.deinit();
    var producer = try producer_mod.Producer.init(gpa, std.testing.io, &controller, .truecolor, true);
    defer producer.deinit();
    try producer.select("{\"name\":\"selected\",\"colors\":{}}", "owned/source.json");
    try producer.begin();
    try std.testing.expect(try producer_mod.Producer.report(&producer, "\x1b]10;#aabbcc\x07"));
    try std.testing.expect(producer.colors.foreground == null);
    const before = producer.colors.revision;
    try std.testing.expect(try producer_mod.Producer.report(&producer, "\x1b]10;#aabbcc\x07"));
    try std.testing.expectEqual(before, producer.colors.revision);
    try std.testing.expect(try producer_mod.Producer.report(&producer, "\x1b[?997;2n"));
    try std.testing.expect(try producer_mod.Producer.report(&producer, "\x1b[?1;2c"));
    try std.testing.expect(!producer.colors.pending);
    const encoded = try controller.contextJson(gpa, .{ .mode = "tui", .cwd = ".", .session_id = "report" });
    defer gpa.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "owned/source.json") != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "\"foreground\":{\"r\":170,\"g\":187,\"b\":204}") != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "\"terminalColorScheme\":\"light\"") != null);
}
test "native terminal report producer follows original timeout and single late delivery boundary" {
    const gpa = std.testing.allocator;
    var controller = try ui.Controller.init(gpa, std.testing.io, true, 100);
    defer controller.deinit();
    var producer = try producer_mod.Producer.init(gpa, std.testing.io, &controller, .truecolor, true);
    defer producer.deinit();
    try producer.begin();
    _ = try producer_mod.Producer.report(&producer, "\x1b]10;#aabbcc\x07");
    try std.testing.expect(producer.colors.foreground == null);
    try producer.expire();
    try std.testing.expectEqual(@as(f64, 170), producer.colors.foreground.?.r);
    try std.testing.expect(!producer.colors.pending and producer.query_active);
    _ = try producer_mod.Producer.report(&producer, "\x1b]11;#010203\x07");
    try std.testing.expect(producer.colors.background == null);
    _ = try producer_mod.Producer.report(&producer, "\x1b[?1;2c");
    try std.testing.expectEqual(@as(f64, 1), producer.colors.background.?.r);
    try std.testing.expect(!producer.query_active);
    try std.testing.expect(!try producer_mod.Producer.report(&producer, "\x1b]10;#ffffff\x07"));
}

test "native terminal report overlapping queries retain oldest ownership until DA including completed reply sets" {
    const gpa = std.testing.allocator;
    var controller = try ui.Controller.init(gpa, std.testing.io, true, 100);
    defer controller.deinit();
    var producer = try producer_mod.Producer.init(gpa, std.testing.io, &controller, .truecolor, true);
    defer producer.deinit();
    try producer.begin();
    try producer.begin();
    _ = try producer_mod.Producer.report(&producer, "\x1b]10;#aabbcc\x07");
    try producer.expire();
    try std.testing.expectEqual(@as(f64, 170), producer.colors.foreground.?.r);
    _ = try producer_mod.Producer.report(&producer, "\x1b]11;#010203\x07");
    _ = try producer_mod.Producer.report(&producer, "\x1b[?1;2c");
    try std.testing.expectEqual(@as(usize, 1), producer.queries.items.len);
    try std.testing.expectEqual(@as(f64, 1), producer.colors.background.?.r);
    _ = try producer_mod.Producer.report(&producer, "\x1b]10;#ffffff\x07");
    _ = try producer_mod.Producer.report(&producer, "\x1b[?1;2c");
    try std.testing.expectEqual(@as(f64, 255), producer.colors.foreground.?.r);
    try std.testing.expect(!producer.query_active);
    try producer.begin();
    try producer.begin();
    _ = try producer_mod.Producer.report(&producer, "\x1b]10;#020202\x07");
    _ = try producer_mod.Producer.report(&producer, "\x1b]11;#030303\x07");
    for (0..16) |index| {
        const report = try std.fmt.allocPrint(gpa, "\x1b]4;{d};#040404\x07", .{index});
        defer gpa.free(report);
        _ = try producer_mod.Producer.report(&producer, report);
    }
    try std.testing.expectEqual(@as(usize, 2), producer.queries.items.len);
    _ = try producer_mod.Producer.report(&producer, "\x1b]10;#999999\x07");
    try std.testing.expectEqual(@as(f64, 2), producer.colors.foreground.?.r);
    _ = try producer_mod.Producer.report(&producer, "\x1b[?1;2c");
    _ = try producer_mod.Producer.report(&producer, "\x1b]10;#050505\x07");
    _ = try producer_mod.Producer.report(&producer, "\x1b[?1;2c");
    try std.testing.expectEqual(@as(f64, 5), producer.colors.foreground.?.r);
}

test "native terminal report query admission publication and late ownership survive allocation failures" {
    const Check = struct {
        fn run(gpa: std.mem.Allocator) !void {
            var controller = try ui.Controller.init(gpa, std.testing.io, true, 100);
            defer controller.deinit();
            var producer = try producer_mod.Producer.init(gpa, std.testing.io, &controller, .truecolor, true);
            defer producer.deinit();
            try producer.select("{\"name\":\"owned\"}", "owned.json");
            try producer.begin();
            try producer.begin();
            _ = try producer_mod.Producer.report(&producer, "\x1b]10;#aabbcc\x07");
            try producer.expire();
            _ = try producer_mod.Producer.report(&producer, "\x1b]11;#010203\x07");
            _ = try producer_mod.Producer.report(&producer, "\x1b[?1;2c");
            _ = try producer_mod.Producer.report(&producer, "\x1b]10;#ffffff\x07");
            _ = try producer_mod.Producer.report(&producer, "\x1b[?1;2c");
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Check.run, .{});
}
