//! Product TUI surface: layout/paint across ALL widget_shard_*.
const std = @import("std");
const g = @import("generated_root.zig");
const diff = @import("diff.zig");

pub fn widgetShardCount() usize { return 20; }

pub fn layoutDemo(gpa: std.mem.Allocator, width: u16, height: u16) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    {
        const parent = g.widget_shard_0.Rect{ .x = 0, .y = 0, .w = width, .h = height };
        const r = g.widget_shard_0.layout_widget_0_0(parent, @intCast(0 % 8), 8);
        var w = g.widget_shard_0.Widget_0_0{ .bounds = r, .focused = (0 == 0) };
        g.widget_shard_0.handle_key_0_0(&w, 'j');
        const painted = try g.widget_shard_0.paint_widget_0_0(gpa, w);
        defer gpa.free(painted);
        try aw.writer.print("shard0:{s}\n", .{painted});
    }
    {
        const parent = g.widget_shard_1.Rect{ .x = 0, .y = 0, .w = width, .h = height };
        const r = g.widget_shard_1.layout_widget_1_0(parent, @intCast(1 % 8), 8);
        var w = g.widget_shard_1.Widget_1_0{ .bounds = r, .focused = (1 == 0) };
        g.widget_shard_1.handle_key_1_0(&w, 'j');
        const painted = try g.widget_shard_1.paint_widget_1_0(gpa, w);
        defer gpa.free(painted);
        try aw.writer.print("shard1:{s}\n", .{painted});
    }
    {
        const parent = g.widget_shard_2.Rect{ .x = 0, .y = 0, .w = width, .h = height };
        const r = g.widget_shard_2.layout_widget_2_0(parent, @intCast(2 % 8), 8);
        var w = g.widget_shard_2.Widget_2_0{ .bounds = r, .focused = (2 == 0) };
        g.widget_shard_2.handle_key_2_0(&w, 'j');
        const painted = try g.widget_shard_2.paint_widget_2_0(gpa, w);
        defer gpa.free(painted);
        try aw.writer.print("shard2:{s}\n", .{painted});
    }
    {
        const parent = g.widget_shard_3.Rect{ .x = 0, .y = 0, .w = width, .h = height };
        const r = g.widget_shard_3.layout_widget_3_0(parent, @intCast(3 % 8), 8);
        var w = g.widget_shard_3.Widget_3_0{ .bounds = r, .focused = (3 == 0) };
        g.widget_shard_3.handle_key_3_0(&w, 'j');
        const painted = try g.widget_shard_3.paint_widget_3_0(gpa, w);
        defer gpa.free(painted);
        try aw.writer.print("shard3:{s}\n", .{painted});
    }
    {
        const parent = g.widget_shard_4.Rect{ .x = 0, .y = 0, .w = width, .h = height };
        const r = g.widget_shard_4.layout_widget_4_0(parent, @intCast(4 % 8), 8);
        var w = g.widget_shard_4.Widget_4_0{ .bounds = r, .focused = (4 == 0) };
        g.widget_shard_4.handle_key_4_0(&w, 'j');
        const painted = try g.widget_shard_4.paint_widget_4_0(gpa, w);
        defer gpa.free(painted);
        try aw.writer.print("shard4:{s}\n", .{painted});
    }
    {
        const parent = g.widget_shard_5.Rect{ .x = 0, .y = 0, .w = width, .h = height };
        const r = g.widget_shard_5.layout_widget_5_0(parent, @intCast(5 % 8), 8);
        var w = g.widget_shard_5.Widget_5_0{ .bounds = r, .focused = (5 == 0) };
        g.widget_shard_5.handle_key_5_0(&w, 'j');
        const painted = try g.widget_shard_5.paint_widget_5_0(gpa, w);
        defer gpa.free(painted);
        try aw.writer.print("shard5:{s}\n", .{painted});
    }
    {
        const parent = g.widget_shard_6.Rect{ .x = 0, .y = 0, .w = width, .h = height };
        const r = g.widget_shard_6.layout_widget_6_0(parent, @intCast(6 % 8), 8);
        var w = g.widget_shard_6.Widget_6_0{ .bounds = r, .focused = (6 == 0) };
        g.widget_shard_6.handle_key_6_0(&w, 'j');
        const painted = try g.widget_shard_6.paint_widget_6_0(gpa, w);
        defer gpa.free(painted);
        try aw.writer.print("shard6:{s}\n", .{painted});
    }
    {
        const parent = g.widget_shard_7.Rect{ .x = 0, .y = 0, .w = width, .h = height };
        const r = g.widget_shard_7.layout_widget_7_0(parent, @intCast(7 % 8), 8);
        var w = g.widget_shard_7.Widget_7_0{ .bounds = r, .focused = (7 == 0) };
        g.widget_shard_7.handle_key_7_0(&w, 'j');
        const painted = try g.widget_shard_7.paint_widget_7_0(gpa, w);
        defer gpa.free(painted);
        try aw.writer.print("shard7:{s}\n", .{painted});
    }
    {
        const parent = g.widget_shard_8.Rect{ .x = 0, .y = 0, .w = width, .h = height };
        const r = g.widget_shard_8.layout_widget_8_0(parent, @intCast(8 % 8), 8);
        var w = g.widget_shard_8.Widget_8_0{ .bounds = r, .focused = (8 == 0) };
        g.widget_shard_8.handle_key_8_0(&w, 'j');
        const painted = try g.widget_shard_8.paint_widget_8_0(gpa, w);
        defer gpa.free(painted);
        try aw.writer.print("shard8:{s}\n", .{painted});
    }
    {
        const parent = g.widget_shard_9.Rect{ .x = 0, .y = 0, .w = width, .h = height };
        const r = g.widget_shard_9.layout_widget_9_0(parent, @intCast(9 % 8), 8);
        var w = g.widget_shard_9.Widget_9_0{ .bounds = r, .focused = (9 == 0) };
        g.widget_shard_9.handle_key_9_0(&w, 'j');
        const painted = try g.widget_shard_9.paint_widget_9_0(gpa, w);
        defer gpa.free(painted);
        try aw.writer.print("shard9:{s}\n", .{painted});
    }
    {
        const parent = g.widget_shard_10.Rect{ .x = 0, .y = 0, .w = width, .h = height };
        const r = g.widget_shard_10.layout_widget_10_0(parent, @intCast(10 % 8), 8);
        var w = g.widget_shard_10.Widget_10_0{ .bounds = r, .focused = (10 == 0) };
        g.widget_shard_10.handle_key_10_0(&w, 'j');
        const painted = try g.widget_shard_10.paint_widget_10_0(gpa, w);
        defer gpa.free(painted);
        try aw.writer.print("shard10:{s}\n", .{painted});
    }
    {
        const parent = g.widget_shard_11.Rect{ .x = 0, .y = 0, .w = width, .h = height };
        const r = g.widget_shard_11.layout_widget_11_0(parent, @intCast(11 % 8), 8);
        var w = g.widget_shard_11.Widget_11_0{ .bounds = r, .focused = (11 == 0) };
        g.widget_shard_11.handle_key_11_0(&w, 'j');
        const painted = try g.widget_shard_11.paint_widget_11_0(gpa, w);
        defer gpa.free(painted);
        try aw.writer.print("shard11:{s}\n", .{painted});
    }
    {
        const parent = g.widget_shard_12.Rect{ .x = 0, .y = 0, .w = width, .h = height };
        const r = g.widget_shard_12.layout_widget_12_0(parent, @intCast(12 % 8), 8);
        var w = g.widget_shard_12.Widget_12_0{ .bounds = r, .focused = (12 == 0) };
        g.widget_shard_12.handle_key_12_0(&w, 'j');
        const painted = try g.widget_shard_12.paint_widget_12_0(gpa, w);
        defer gpa.free(painted);
        try aw.writer.print("shard12:{s}\n", .{painted});
    }
    {
        const parent = g.widget_shard_13.Rect{ .x = 0, .y = 0, .w = width, .h = height };
        const r = g.widget_shard_13.layout_widget_13_0(parent, @intCast(13 % 8), 8);
        var w = g.widget_shard_13.Widget_13_0{ .bounds = r, .focused = (13 == 0) };
        g.widget_shard_13.handle_key_13_0(&w, 'j');
        const painted = try g.widget_shard_13.paint_widget_13_0(gpa, w);
        defer gpa.free(painted);
        try aw.writer.print("shard13:{s}\n", .{painted});
    }
    {
        const parent = g.widget_shard_14.Rect{ .x = 0, .y = 0, .w = width, .h = height };
        const r = g.widget_shard_14.layout_widget_14_0(parent, @intCast(14 % 8), 8);
        var w = g.widget_shard_14.Widget_14_0{ .bounds = r, .focused = (14 == 0) };
        g.widget_shard_14.handle_key_14_0(&w, 'j');
        const painted = try g.widget_shard_14.paint_widget_14_0(gpa, w);
        defer gpa.free(painted);
        try aw.writer.print("shard14:{s}\n", .{painted});
    }
    {
        const parent = g.widget_shard_15.Rect{ .x = 0, .y = 0, .w = width, .h = height };
        const r = g.widget_shard_15.layout_widget_15_0(parent, @intCast(15 % 8), 8);
        var w = g.widget_shard_15.Widget_15_0{ .bounds = r, .focused = (15 == 0) };
        g.widget_shard_15.handle_key_15_0(&w, 'j');
        const painted = try g.widget_shard_15.paint_widget_15_0(gpa, w);
        defer gpa.free(painted);
        try aw.writer.print("shard15:{s}\n", .{painted});
    }
    {
        const parent = g.widget_shard_16.Rect{ .x = 0, .y = 0, .w = width, .h = height };
        const r = g.widget_shard_16.layout_widget_16_0(parent, @intCast(16 % 8), 8);
        var w = g.widget_shard_16.Widget_16_0{ .bounds = r, .focused = (16 == 0) };
        g.widget_shard_16.handle_key_16_0(&w, 'j');
        const painted = try g.widget_shard_16.paint_widget_16_0(gpa, w);
        defer gpa.free(painted);
        try aw.writer.print("shard16:{s}\n", .{painted});
    }
    {
        const parent = g.widget_shard_17.Rect{ .x = 0, .y = 0, .w = width, .h = height };
        const r = g.widget_shard_17.layout_widget_17_0(parent, @intCast(17 % 8), 8);
        var w = g.widget_shard_17.Widget_17_0{ .bounds = r, .focused = (17 == 0) };
        g.widget_shard_17.handle_key_17_0(&w, 'j');
        const painted = try g.widget_shard_17.paint_widget_17_0(gpa, w);
        defer gpa.free(painted);
        try aw.writer.print("shard17:{s}\n", .{painted});
    }
    {
        const parent = g.widget_shard_18.Rect{ .x = 0, .y = 0, .w = width, .h = height };
        const r = g.widget_shard_18.layout_widget_18_0(parent, @intCast(18 % 8), 8);
        var w = g.widget_shard_18.Widget_18_0{ .bounds = r, .focused = (18 == 0) };
        g.widget_shard_18.handle_key_18_0(&w, 'j');
        const painted = try g.widget_shard_18.paint_widget_18_0(gpa, w);
        defer gpa.free(painted);
        try aw.writer.print("shard18:{s}\n", .{painted});
    }
    {
        const parent = g.widget_shard_19.Rect{ .x = 0, .y = 0, .w = width, .h = height };
        const r = g.widget_shard_19.layout_widget_19_0(parent, @intCast(19 % 8), 8);
        var w = g.widget_shard_19.Widget_19_0{ .bounds = r, .focused = (19 == 0) };
        g.widget_shard_19.handle_key_19_0(&w, 'j');
        const painted = try g.widget_shard_19.paint_widget_19_0(gpa, w);
        defer gpa.free(painted);
        try aw.writer.print("shard19:{s}\n", .{painted});
    }
    return try aw.toOwnedSlice();
}

pub fn colorAccentCount() usize { return 20; }

pub fn paintDiffSample(gpa: std.mem.Allocator, io: std.Io) !usize {
    var db = diff.DiffBuffer{ .gpa = gpa, .io = io };
    defer db.deinit();
    _ = try db.setRow(0, "pi-zig tui product");
    _ = try db.setRow(1, "widget_0_0");
    _ = g.widget_shard_0.color_theme_0_0();
    _ = try db.setRow(2, "widget_1_0");
    _ = g.widget_shard_1.color_theme_1_0();
    _ = try db.setRow(3, "widget_2_0");
    _ = g.widget_shard_2.color_theme_2_0();
    _ = try db.setRow(4, "widget_3_0");
    _ = g.widget_shard_3.color_theme_3_0();
    _ = try db.setRow(5, "widget_4_0");
    _ = g.widget_shard_4.color_theme_4_0();
    _ = try db.setRow(6, "widget_5_0");
    _ = g.widget_shard_5.color_theme_5_0();
    _ = try db.setRow(7, "widget_6_0");
    _ = g.widget_shard_6.color_theme_6_0();
    _ = try db.setRow(8, "widget_7_0");
    _ = g.widget_shard_7.color_theme_7_0();
    _ = try db.setRow(9, "widget_8_0");
    _ = g.widget_shard_8.color_theme_8_0();
    _ = try db.setRow(10, "widget_9_0");
    _ = g.widget_shard_9.color_theme_9_0();
    _ = try db.setRow(11, "widget_10_0");
    _ = g.widget_shard_10.color_theme_10_0();
    _ = try db.setRow(12, "widget_11_0");
    _ = g.widget_shard_11.color_theme_11_0();
    _ = try db.setRow(13, "widget_12_0");
    _ = g.widget_shard_12.color_theme_12_0();
    _ = try db.setRow(14, "widget_13_0");
    _ = g.widget_shard_13.color_theme_13_0();
    _ = try db.setRow(15, "widget_14_0");
    _ = g.widget_shard_14.color_theme_14_0();
    _ = try db.setRow(16, "widget_15_0");
    _ = g.widget_shard_15.color_theme_15_0();
    _ = try db.setRow(17, "widget_16_0");
    _ = g.widget_shard_16.color_theme_16_0();
    _ = try db.setRow(18, "widget_17_0");
    _ = g.widget_shard_17.color_theme_17_0();
    _ = try db.setRow(19, "widget_18_0");
    _ = g.widget_shard_18.color_theme_18_0();
    _ = try db.setRow(20, "widget_19_0");
    _ = g.widget_shard_19.color_theme_19_0();
    return db.rows.items.len;
}

test "tui product uses all widget shards" {
    const gpa = std.testing.allocator;
    const demo = try layoutDemo(gpa, 80, 24);
    defer gpa.free(demo);
    try std.testing.expect(std.mem.indexOf(u8, demo, "shard0:") != null);
    try std.testing.expect(std.mem.indexOf(u8, demo, "shard19:") != null);
    const n = try paintDiffSample(gpa, std.testing.io);
    try std.testing.expect(n >= 21);
}

