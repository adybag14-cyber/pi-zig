const std = @import("std");
const ui = @import("extensions/ui.zig");
const state_mod = @import("extensions/theme_state.zig");
test "Controller cached theme state preserves snapshot ownership and failed replacement without terminal queries" {
    var controller = try ui.Controller.init(std.testing.allocator, std.testing.io, true, 100);
    defer controller.deinit();
    const options: ui.ContextOptions = .{ .mode = "interactive", .cwd = ".", .session_id = "theme-dto" };
    const unbound = try controller.contextJson(std.testing.allocator, options);
    defer std.testing.allocator.free(unbound);
    try std.testing.expect(std.mem.indexOf(u8, unbound, "\"themeState\"") == null);
    var input = try std.testing.allocator.dupe(u8, "{\"name\":\"owned\",\"colors\":{}}");
    defer std.testing.allocator.free(input);
    try controller.setThemeState(.{ .revision = 7, .color_mode = .truecolor, .stdout_is_tty = true, .resource_json = input, .resource_identity = "loader-3/theme-1" });
    input[9] = 'X';
    const first = try controller.contextJson(std.testing.allocator, options);
    defer std.testing.allocator.free(first);
    try std.testing.expect(std.mem.indexOf(u8, first, "\"name\":\"owned\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "\"terminalColors\":{}") != null);
    try std.testing.expectError(error.InvalidThemeStatePalette, controller.setThemeState(.{ .revision = 8, .color_mode = .@"256color", .stdout_is_tty = false, .terminal_colors = .{ .palette = &.{.{ .r = 0, .g = 0, .b = 0 }} } }));
    const after_failure = try controller.contextJson(std.testing.allocator, options);
    defer std.testing.allocator.free(after_failure);
    try std.testing.expectEqualStrings(first, after_failure);
    const reset = try controller.contextJson(std.testing.allocator, .{ .mode = "interactive", .cwd = ".", .session_id = "theme-dto", .theme_state = .{ .revision = 9, .color_mode = .@"256color", .stdout_is_tty = false } });
    defer std.testing.allocator.free(reset);
    try std.testing.expect(std.mem.indexOf(u8, reset, "\"revision\":\"9\"") != null);
    try controller.setThemeState(null);
    const rebound = try controller.contextJson(std.testing.allocator, options);
    defer std.testing.allocator.free(rebound);
    try std.testing.expectEqualStrings(unbound, rebound);
}
test {
    _ = state_mod;
}

fn controllerAllocationProbe(gpa: std.mem.Allocator) !void {
    var controller = try ui.Controller.init(gpa, std.testing.io, true, 100);
    defer controller.deinit();
    try controller.setThemeState(.{ .revision = 1, .color_mode = .truecolor, .stdout_is_tty = true, .resource_identity = "old-resource", .resource_json = "{\"colors\":{}}" });
    const first = controller.contextJson(gpa, .{ .mode = "interactive", .cwd = ".", .session_id = "owned" }) catch |err| return if (err == error.WriteFailed) error.OutOfMemory else err;
    defer gpa.free(first);
    controller.setThemeState(.{ .revision = 2, .color_mode = .@"256color", .stdout_is_tty = false, .resource_identity = "new-resource", .resource_json = "{\"colors\":{\"accent\":\"#abc\"}}" }) catch |err| {
        try std.testing.expect(std.mem.indexOf(u8, controller.theme_state_json.?, "old-resource") != null);
        return err;
    };
    const after = controller.contextJson(gpa, .{ .mode = "interactive", .cwd = ".", .session_id = "owned" }) catch |err| return if (err == error.WriteFailed) error.OutOfMemory else err;
    defer gpa.free(after);
}
test "Controller cached theme state retains preceding DTO under every replacement allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, controllerAllocationProbe, .{});
}
