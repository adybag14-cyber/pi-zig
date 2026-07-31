//! Generated TUI layout/widget helpers shard 10 (tui).
const std = @import("std");

pub const Rect = struct { x: u16, y: u16, w: u16, h: u16 };
pub const Color = struct { r: u8, g: u8, b: u8 };

pub fn clampU16(v: i32, lo: u16, hi: u16) u16 {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return @intCast(v);
}

pub fn rectIntersect(a: Rect, b: Rect) ?Rect {
    const x1 = @max(a.x, b.x);
    const y1 = @max(a.y, b.y);
    const x2 = @min(a.x + a.w, b.x + b.w);
    const y2 = @min(a.y + a.h, b.y + b.h);
    if (x2 <= x1 or y2 <= y1) return null;
    return .{ .x = x1, .y = y1, .w = x2 - x1, .h = y2 - y1 };
}

pub fn rectContains(r: Rect, px: u16, py: u16) bool {
    return px >= r.x and py >= r.y and px < r.x + r.w and py < r.y + r.h;
}

pub fn ansiFgRgb(gpa: std.mem.Allocator, c: Color, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[38;2;{d};{d};{d}m{s}\x1b[0m", .{ c.r, c.g, c.b, text });
}

pub fn ansiBgRgb(gpa: std.mem.Allocator, c: Color, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[48;2;{d};{d};{d}m{s}\x1b[0m", .{ c.r, c.g, c.b, text });
}

pub const Widget_10_0 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_0",
};

pub fn layout_widget_10_0(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_0(gpa: std.mem.Allocator, w: Widget_10_0) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_0(w: *Widget_10_0, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_0() Color {
    return .{ .r = 30, .g = 50, .b = 70 };
}

pub const Widget_10_1 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_1",
};

pub fn layout_widget_10_1(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_1(gpa: std.mem.Allocator, w: Widget_10_1) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_1(w: *Widget_10_1, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_1() Color {
    return .{ .r = 47, .g = 79, .b = 113 };
}

pub const Widget_10_2 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_2",
};

pub fn layout_widget_10_2(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_2(gpa: std.mem.Allocator, w: Widget_10_2) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_2(w: *Widget_10_2, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_2() Color {
    return .{ .r = 64, .g = 108, .b = 156 };
}

pub const Widget_10_3 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_3",
};

pub fn layout_widget_10_3(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_3(gpa: std.mem.Allocator, w: Widget_10_3) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_3(w: *Widget_10_3, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_3() Color {
    return .{ .r = 81, .g = 137, .b = 199 };
}

pub const Widget_10_4 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_4",
};

pub fn layout_widget_10_4(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_4(gpa: std.mem.Allocator, w: Widget_10_4) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_4(w: *Widget_10_4, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_4() Color {
    return .{ .r = 98, .g = 166, .b = 242 };
}

pub const Widget_10_5 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_5",
};

pub fn layout_widget_10_5(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_5(gpa: std.mem.Allocator, w: Widget_10_5) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_5(w: *Widget_10_5, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_5() Color {
    return .{ .r = 115, .g = 195, .b = 29 };
}

pub const Widget_10_6 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_6",
};

pub fn layout_widget_10_6(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_6(gpa: std.mem.Allocator, w: Widget_10_6) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_6(w: *Widget_10_6, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_6() Color {
    return .{ .r = 132, .g = 224, .b = 72 };
}

pub const Widget_10_7 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_7",
};

pub fn layout_widget_10_7(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_7(gpa: std.mem.Allocator, w: Widget_10_7) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_7(w: *Widget_10_7, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_7() Color {
    return .{ .r = 149, .g = 253, .b = 115 };
}

pub const Widget_10_8 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_8",
};

pub fn layout_widget_10_8(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_8(gpa: std.mem.Allocator, w: Widget_10_8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_8(w: *Widget_10_8, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_8() Color {
    return .{ .r = 166, .g = 26, .b = 158 };
}

pub const Widget_10_9 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_9",
};

pub fn layout_widget_10_9(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_9(gpa: std.mem.Allocator, w: Widget_10_9) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_9(w: *Widget_10_9, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_9() Color {
    return .{ .r = 183, .g = 55, .b = 201 };
}

pub const Widget_10_10 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_10",
};

pub fn layout_widget_10_10(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_10(gpa: std.mem.Allocator, w: Widget_10_10) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_10(w: *Widget_10_10, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_10() Color {
    return .{ .r = 200, .g = 84, .b = 244 };
}

pub const Widget_10_11 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_11",
};

pub fn layout_widget_10_11(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_11(gpa: std.mem.Allocator, w: Widget_10_11) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_11(w: *Widget_10_11, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_11() Color {
    return .{ .r = 217, .g = 113, .b = 31 };
}

pub const Widget_10_12 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_12",
};

pub fn layout_widget_10_12(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_12(gpa: std.mem.Allocator, w: Widget_10_12) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_12(w: *Widget_10_12, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_12() Color {
    return .{ .r = 234, .g = 142, .b = 74 };
}

pub const Widget_10_13 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_13",
};

pub fn layout_widget_10_13(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_13(gpa: std.mem.Allocator, w: Widget_10_13) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_13(w: *Widget_10_13, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_13() Color {
    return .{ .r = 251, .g = 171, .b = 117 };
}

pub const Widget_10_14 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_14",
};

pub fn layout_widget_10_14(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_14(gpa: std.mem.Allocator, w: Widget_10_14) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_14(w: *Widget_10_14, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_14() Color {
    return .{ .r = 12, .g = 200, .b = 160 };
}

pub const Widget_10_15 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_15",
};

pub fn layout_widget_10_15(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_15(gpa: std.mem.Allocator, w: Widget_10_15) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_15(w: *Widget_10_15, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_15() Color {
    return .{ .r = 29, .g = 229, .b = 203 };
}

pub const Widget_10_16 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_16",
};

pub fn layout_widget_10_16(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_16(gpa: std.mem.Allocator, w: Widget_10_16) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_16(w: *Widget_10_16, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_16() Color {
    return .{ .r = 46, .g = 2, .b = 246 };
}

pub const Widget_10_17 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_17",
};

pub fn layout_widget_10_17(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_17(gpa: std.mem.Allocator, w: Widget_10_17) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_17(w: *Widget_10_17, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_17() Color {
    return .{ .r = 63, .g = 31, .b = 33 };
}

pub const Widget_10_18 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_18",
};

pub fn layout_widget_10_18(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_18(gpa: std.mem.Allocator, w: Widget_10_18) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_18(w: *Widget_10_18, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_18() Color {
    return .{ .r = 80, .g = 60, .b = 76 };
}

pub const Widget_10_19 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_19",
};

pub fn layout_widget_10_19(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_19(gpa: std.mem.Allocator, w: Widget_10_19) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_19(w: *Widget_10_19, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_19() Color {
    return .{ .r = 97, .g = 89, .b = 119 };
}

pub const Widget_10_20 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_20",
};

pub fn layout_widget_10_20(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_20(gpa: std.mem.Allocator, w: Widget_10_20) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_20(w: *Widget_10_20, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_20() Color {
    return .{ .r = 114, .g = 118, .b = 162 };
}

pub const Widget_10_21 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_21",
};

pub fn layout_widget_10_21(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_21(gpa: std.mem.Allocator, w: Widget_10_21) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_21(w: *Widget_10_21, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_21() Color {
    return .{ .r = 131, .g = 147, .b = 205 };
}

pub const Widget_10_22 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_22",
};

pub fn layout_widget_10_22(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_22(gpa: std.mem.Allocator, w: Widget_10_22) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_22(w: *Widget_10_22, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_22() Color {
    return .{ .r = 148, .g = 176, .b = 248 };
}

pub const Widget_10_23 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_23",
};

pub fn layout_widget_10_23(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_23(gpa: std.mem.Allocator, w: Widget_10_23) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_23(w: *Widget_10_23, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_23() Color {
    return .{ .r = 165, .g = 205, .b = 35 };
}

pub const Widget_10_24 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_24",
};

pub fn layout_widget_10_24(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_24(gpa: std.mem.Allocator, w: Widget_10_24) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_24(w: *Widget_10_24, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_24() Color {
    return .{ .r = 182, .g = 234, .b = 78 };
}

pub const Widget_10_25 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_25",
};

pub fn layout_widget_10_25(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_25(gpa: std.mem.Allocator, w: Widget_10_25) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_25(w: *Widget_10_25, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_25() Color {
    return .{ .r = 199, .g = 7, .b = 121 };
}

pub const Widget_10_26 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_26",
};

pub fn layout_widget_10_26(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_26(gpa: std.mem.Allocator, w: Widget_10_26) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_26(w: *Widget_10_26, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_26() Color {
    return .{ .r = 216, .g = 36, .b = 164 };
}

pub const Widget_10_27 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_27",
};

pub fn layout_widget_10_27(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_27(gpa: std.mem.Allocator, w: Widget_10_27) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_27(w: *Widget_10_27, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_27() Color {
    return .{ .r = 233, .g = 65, .b = 207 };
}

pub const Widget_10_28 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_28",
};

pub fn layout_widget_10_28(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_28(gpa: std.mem.Allocator, w: Widget_10_28) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_28(w: *Widget_10_28, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_28() Color {
    return .{ .r = 250, .g = 94, .b = 250 };
}

pub const Widget_10_29 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_29",
};

pub fn layout_widget_10_29(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_29(gpa: std.mem.Allocator, w: Widget_10_29) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_29(w: *Widget_10_29, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_29() Color {
    return .{ .r = 11, .g = 123, .b = 37 };
}

pub const Widget_10_30 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_30",
};

pub fn layout_widget_10_30(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_30(gpa: std.mem.Allocator, w: Widget_10_30) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_30(w: *Widget_10_30, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_30() Color {
    return .{ .r = 28, .g = 152, .b = 80 };
}

pub const Widget_10_31 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_31",
};

pub fn layout_widget_10_31(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_31(gpa: std.mem.Allocator, w: Widget_10_31) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_31(w: *Widget_10_31, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_31() Color {
    return .{ .r = 45, .g = 181, .b = 123 };
}

pub const Widget_10_32 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_32",
};

pub fn layout_widget_10_32(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_32(gpa: std.mem.Allocator, w: Widget_10_32) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_32(w: *Widget_10_32, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_32() Color {
    return .{ .r = 62, .g = 210, .b = 166 };
}

pub const Widget_10_33 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_33",
};

pub fn layout_widget_10_33(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_33(gpa: std.mem.Allocator, w: Widget_10_33) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_33(w: *Widget_10_33, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_33() Color {
    return .{ .r = 79, .g = 239, .b = 209 };
}

pub const Widget_10_34 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_34",
};

pub fn layout_widget_10_34(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_34(gpa: std.mem.Allocator, w: Widget_10_34) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_34(w: *Widget_10_34, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_34() Color {
    return .{ .r = 96, .g = 12, .b = 252 };
}

pub const Widget_10_35 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_35",
};

pub fn layout_widget_10_35(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_35(gpa: std.mem.Allocator, w: Widget_10_35) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_35(w: *Widget_10_35, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_35() Color {
    return .{ .r = 113, .g = 41, .b = 39 };
}

pub const Widget_10_36 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_36",
};

pub fn layout_widget_10_36(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_36(gpa: std.mem.Allocator, w: Widget_10_36) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_36(w: *Widget_10_36, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_36() Color {
    return .{ .r = 130, .g = 70, .b = 82 };
}

pub const Widget_10_37 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_37",
};

pub fn layout_widget_10_37(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_37(gpa: std.mem.Allocator, w: Widget_10_37) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_37(w: *Widget_10_37, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_37() Color {
    return .{ .r = 147, .g = 99, .b = 125 };
}

pub const Widget_10_38 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_38",
};

pub fn layout_widget_10_38(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_38(gpa: std.mem.Allocator, w: Widget_10_38) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_38(w: *Widget_10_38, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_38() Color {
    return .{ .r = 164, .g = 128, .b = 168 };
}

pub const Widget_10_39 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_10_39",
};

pub fn layout_widget_10_39(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_10_39(gpa: std.mem.Allocator, w: Widget_10_39) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_10_39(w: *Widget_10_39, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_10_39() Color {
    return .{ .r = 181, .g = 157, .b = 211 };
}

test "tui shard 10 layout" {
    const parent = Rect{ .x = 0, .y = 0, .w = 80, .h = 24 };
    const r = layout_widget_10_0(parent, 0, 3);
    try std.testing.expect(r.w == 80);
    try std.testing.expect(rectContains(parent, 1, 1));
    const gpa = std.testing.allocator;
    var w = Widget_10_0{ .bounds = r };
    handle_key_10_0(&w, 'j');
    try std.testing.expect(w.scroll == 1);
    const painted = try paint_widget_10_0(gpa, w);
    defer gpa.free(painted);
    try std.testing.expect(painted.len > 0);
}

