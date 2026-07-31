//! Generated TUI layout/widget helpers shard 6 (tui).
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

pub const Widget_6_0 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_0",
};

pub fn layout_widget_6_0(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_0(gpa: std.mem.Allocator, w: Widget_6_0) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_0(w: *Widget_6_0, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_0() Color {
    return .{ .r = 18, .g = 30, .b = 42 };
}

pub const Widget_6_1 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_1",
};

pub fn layout_widget_6_1(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_1(gpa: std.mem.Allocator, w: Widget_6_1) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_1(w: *Widget_6_1, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_1() Color {
    return .{ .r = 35, .g = 59, .b = 85 };
}

pub const Widget_6_2 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_2",
};

pub fn layout_widget_6_2(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_2(gpa: std.mem.Allocator, w: Widget_6_2) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_2(w: *Widget_6_2, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_2() Color {
    return .{ .r = 52, .g = 88, .b = 128 };
}

pub const Widget_6_3 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_3",
};

pub fn layout_widget_6_3(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_3(gpa: std.mem.Allocator, w: Widget_6_3) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_3(w: *Widget_6_3, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_3() Color {
    return .{ .r = 69, .g = 117, .b = 171 };
}

pub const Widget_6_4 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_4",
};

pub fn layout_widget_6_4(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_4(gpa: std.mem.Allocator, w: Widget_6_4) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_4(w: *Widget_6_4, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_4() Color {
    return .{ .r = 86, .g = 146, .b = 214 };
}

pub const Widget_6_5 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_5",
};

pub fn layout_widget_6_5(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_5(gpa: std.mem.Allocator, w: Widget_6_5) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_5(w: *Widget_6_5, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_5() Color {
    return .{ .r = 103, .g = 175, .b = 1 };
}

pub const Widget_6_6 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_6",
};

pub fn layout_widget_6_6(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_6(gpa: std.mem.Allocator, w: Widget_6_6) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_6(w: *Widget_6_6, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_6() Color {
    return .{ .r = 120, .g = 204, .b = 44 };
}

pub const Widget_6_7 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_7",
};

pub fn layout_widget_6_7(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_7(gpa: std.mem.Allocator, w: Widget_6_7) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_7(w: *Widget_6_7, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_7() Color {
    return .{ .r = 137, .g = 233, .b = 87 };
}

pub const Widget_6_8 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_8",
};

pub fn layout_widget_6_8(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_8(gpa: std.mem.Allocator, w: Widget_6_8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_8(w: *Widget_6_8, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_8() Color {
    return .{ .r = 154, .g = 6, .b = 130 };
}

pub const Widget_6_9 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_9",
};

pub fn layout_widget_6_9(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_9(gpa: std.mem.Allocator, w: Widget_6_9) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_9(w: *Widget_6_9, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_9() Color {
    return .{ .r = 171, .g = 35, .b = 173 };
}

pub const Widget_6_10 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_10",
};

pub fn layout_widget_6_10(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_10(gpa: std.mem.Allocator, w: Widget_6_10) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_10(w: *Widget_6_10, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_10() Color {
    return .{ .r = 188, .g = 64, .b = 216 };
}

pub const Widget_6_11 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_11",
};

pub fn layout_widget_6_11(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_11(gpa: std.mem.Allocator, w: Widget_6_11) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_11(w: *Widget_6_11, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_11() Color {
    return .{ .r = 205, .g = 93, .b = 3 };
}

pub const Widget_6_12 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_12",
};

pub fn layout_widget_6_12(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_12(gpa: std.mem.Allocator, w: Widget_6_12) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_12(w: *Widget_6_12, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_12() Color {
    return .{ .r = 222, .g = 122, .b = 46 };
}

pub const Widget_6_13 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_13",
};

pub fn layout_widget_6_13(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_13(gpa: std.mem.Allocator, w: Widget_6_13) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_13(w: *Widget_6_13, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_13() Color {
    return .{ .r = 239, .g = 151, .b = 89 };
}

pub const Widget_6_14 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_14",
};

pub fn layout_widget_6_14(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_14(gpa: std.mem.Allocator, w: Widget_6_14) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_14(w: *Widget_6_14, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_14() Color {
    return .{ .r = 0, .g = 180, .b = 132 };
}

pub const Widget_6_15 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_15",
};

pub fn layout_widget_6_15(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_15(gpa: std.mem.Allocator, w: Widget_6_15) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_15(w: *Widget_6_15, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_15() Color {
    return .{ .r = 17, .g = 209, .b = 175 };
}

pub const Widget_6_16 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_16",
};

pub fn layout_widget_6_16(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_16(gpa: std.mem.Allocator, w: Widget_6_16) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_16(w: *Widget_6_16, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_16() Color {
    return .{ .r = 34, .g = 238, .b = 218 };
}

pub const Widget_6_17 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_17",
};

pub fn layout_widget_6_17(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_17(gpa: std.mem.Allocator, w: Widget_6_17) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_17(w: *Widget_6_17, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_17() Color {
    return .{ .r = 51, .g = 11, .b = 5 };
}

pub const Widget_6_18 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_18",
};

pub fn layout_widget_6_18(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_18(gpa: std.mem.Allocator, w: Widget_6_18) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_18(w: *Widget_6_18, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_18() Color {
    return .{ .r = 68, .g = 40, .b = 48 };
}

pub const Widget_6_19 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_19",
};

pub fn layout_widget_6_19(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_19(gpa: std.mem.Allocator, w: Widget_6_19) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_19(w: *Widget_6_19, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_19() Color {
    return .{ .r = 85, .g = 69, .b = 91 };
}

pub const Widget_6_20 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_20",
};

pub fn layout_widget_6_20(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_20(gpa: std.mem.Allocator, w: Widget_6_20) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_20(w: *Widget_6_20, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_20() Color {
    return .{ .r = 102, .g = 98, .b = 134 };
}

pub const Widget_6_21 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_21",
};

pub fn layout_widget_6_21(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_21(gpa: std.mem.Allocator, w: Widget_6_21) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_21(w: *Widget_6_21, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_21() Color {
    return .{ .r = 119, .g = 127, .b = 177 };
}

pub const Widget_6_22 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_22",
};

pub fn layout_widget_6_22(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_22(gpa: std.mem.Allocator, w: Widget_6_22) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_22(w: *Widget_6_22, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_22() Color {
    return .{ .r = 136, .g = 156, .b = 220 };
}

pub const Widget_6_23 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_23",
};

pub fn layout_widget_6_23(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_23(gpa: std.mem.Allocator, w: Widget_6_23) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_23(w: *Widget_6_23, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_23() Color {
    return .{ .r = 153, .g = 185, .b = 7 };
}

pub const Widget_6_24 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_24",
};

pub fn layout_widget_6_24(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_24(gpa: std.mem.Allocator, w: Widget_6_24) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_24(w: *Widget_6_24, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_24() Color {
    return .{ .r = 170, .g = 214, .b = 50 };
}

pub const Widget_6_25 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_25",
};

pub fn layout_widget_6_25(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_25(gpa: std.mem.Allocator, w: Widget_6_25) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_25(w: *Widget_6_25, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_25() Color {
    return .{ .r = 187, .g = 243, .b = 93 };
}

pub const Widget_6_26 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_26",
};

pub fn layout_widget_6_26(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_26(gpa: std.mem.Allocator, w: Widget_6_26) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_26(w: *Widget_6_26, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_26() Color {
    return .{ .r = 204, .g = 16, .b = 136 };
}

pub const Widget_6_27 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_27",
};

pub fn layout_widget_6_27(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_27(gpa: std.mem.Allocator, w: Widget_6_27) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_27(w: *Widget_6_27, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_27() Color {
    return .{ .r = 221, .g = 45, .b = 179 };
}

pub const Widget_6_28 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_28",
};

pub fn layout_widget_6_28(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_28(gpa: std.mem.Allocator, w: Widget_6_28) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_28(w: *Widget_6_28, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_28() Color {
    return .{ .r = 238, .g = 74, .b = 222 };
}

pub const Widget_6_29 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_29",
};

pub fn layout_widget_6_29(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_29(gpa: std.mem.Allocator, w: Widget_6_29) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_29(w: *Widget_6_29, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_29() Color {
    return .{ .r = 255, .g = 103, .b = 9 };
}

pub const Widget_6_30 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_30",
};

pub fn layout_widget_6_30(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_30(gpa: std.mem.Allocator, w: Widget_6_30) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_30(w: *Widget_6_30, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_30() Color {
    return .{ .r = 16, .g = 132, .b = 52 };
}

pub const Widget_6_31 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_31",
};

pub fn layout_widget_6_31(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_31(gpa: std.mem.Allocator, w: Widget_6_31) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_31(w: *Widget_6_31, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_31() Color {
    return .{ .r = 33, .g = 161, .b = 95 };
}

pub const Widget_6_32 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_32",
};

pub fn layout_widget_6_32(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_32(gpa: std.mem.Allocator, w: Widget_6_32) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_32(w: *Widget_6_32, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_32() Color {
    return .{ .r = 50, .g = 190, .b = 138 };
}

pub const Widget_6_33 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_33",
};

pub fn layout_widget_6_33(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_33(gpa: std.mem.Allocator, w: Widget_6_33) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_33(w: *Widget_6_33, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_33() Color {
    return .{ .r = 67, .g = 219, .b = 181 };
}

pub const Widget_6_34 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_34",
};

pub fn layout_widget_6_34(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_34(gpa: std.mem.Allocator, w: Widget_6_34) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_34(w: *Widget_6_34, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_34() Color {
    return .{ .r = 84, .g = 248, .b = 224 };
}

pub const Widget_6_35 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_35",
};

pub fn layout_widget_6_35(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_35(gpa: std.mem.Allocator, w: Widget_6_35) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_35(w: *Widget_6_35, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_35() Color {
    return .{ .r = 101, .g = 21, .b = 11 };
}

pub const Widget_6_36 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_36",
};

pub fn layout_widget_6_36(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_36(gpa: std.mem.Allocator, w: Widget_6_36) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_36(w: *Widget_6_36, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_36() Color {
    return .{ .r = 118, .g = 50, .b = 54 };
}

pub const Widget_6_37 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_37",
};

pub fn layout_widget_6_37(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_37(gpa: std.mem.Allocator, w: Widget_6_37) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_37(w: *Widget_6_37, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_37() Color {
    return .{ .r = 135, .g = 79, .b = 97 };
}

pub const Widget_6_38 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_38",
};

pub fn layout_widget_6_38(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_38(gpa: std.mem.Allocator, w: Widget_6_38) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_38(w: *Widget_6_38, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_38() Color {
    return .{ .r = 152, .g = 108, .b = 140 };
}

pub const Widget_6_39 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_6_39",
};

pub fn layout_widget_6_39(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_6_39(gpa: std.mem.Allocator, w: Widget_6_39) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_6_39(w: *Widget_6_39, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_6_39() Color {
    return .{ .r = 169, .g = 137, .b = 183 };
}

test "tui shard 6 layout" {
    const parent = Rect{ .x = 0, .y = 0, .w = 80, .h = 24 };
    const r = layout_widget_6_0(parent, 0, 3);
    try std.testing.expect(r.w == 80);
    try std.testing.expect(rectContains(parent, 1, 1));
    const gpa = std.testing.allocator;
    var w = Widget_6_0{ .bounds = r };
    handle_key_6_0(&w, 'j');
    try std.testing.expect(w.scroll == 1);
    const painted = try paint_widget_6_0(gpa, w);
    defer gpa.free(painted);
    try std.testing.expect(painted.len > 0);
}

