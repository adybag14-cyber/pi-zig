//! Generated TUI layout/widget helpers shard 8 (tui).
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

pub const Widget_8_0 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_0",
};

pub fn layout_widget_8_0(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_0(gpa: std.mem.Allocator, w: Widget_8_0) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_0(w: *Widget_8_0, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_0() Color {
    return .{ .r = 24, .g = 40, .b = 56 };
}

pub const Widget_8_1 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_1",
};

pub fn layout_widget_8_1(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_1(gpa: std.mem.Allocator, w: Widget_8_1) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_1(w: *Widget_8_1, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_1() Color {
    return .{ .r = 41, .g = 69, .b = 99 };
}

pub const Widget_8_2 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_2",
};

pub fn layout_widget_8_2(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_2(gpa: std.mem.Allocator, w: Widget_8_2) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_2(w: *Widget_8_2, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_2() Color {
    return .{ .r = 58, .g = 98, .b = 142 };
}

pub const Widget_8_3 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_3",
};

pub fn layout_widget_8_3(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_3(gpa: std.mem.Allocator, w: Widget_8_3) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_3(w: *Widget_8_3, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_3() Color {
    return .{ .r = 75, .g = 127, .b = 185 };
}

pub const Widget_8_4 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_4",
};

pub fn layout_widget_8_4(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_4(gpa: std.mem.Allocator, w: Widget_8_4) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_4(w: *Widget_8_4, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_4() Color {
    return .{ .r = 92, .g = 156, .b = 228 };
}

pub const Widget_8_5 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_5",
};

pub fn layout_widget_8_5(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_5(gpa: std.mem.Allocator, w: Widget_8_5) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_5(w: *Widget_8_5, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_5() Color {
    return .{ .r = 109, .g = 185, .b = 15 };
}

pub const Widget_8_6 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_6",
};

pub fn layout_widget_8_6(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_6(gpa: std.mem.Allocator, w: Widget_8_6) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_6(w: *Widget_8_6, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_6() Color {
    return .{ .r = 126, .g = 214, .b = 58 };
}

pub const Widget_8_7 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_7",
};

pub fn layout_widget_8_7(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_7(gpa: std.mem.Allocator, w: Widget_8_7) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_7(w: *Widget_8_7, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_7() Color {
    return .{ .r = 143, .g = 243, .b = 101 };
}

pub const Widget_8_8 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_8",
};

pub fn layout_widget_8_8(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_8(gpa: std.mem.Allocator, w: Widget_8_8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_8(w: *Widget_8_8, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_8() Color {
    return .{ .r = 160, .g = 16, .b = 144 };
}

pub const Widget_8_9 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_9",
};

pub fn layout_widget_8_9(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_9(gpa: std.mem.Allocator, w: Widget_8_9) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_9(w: *Widget_8_9, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_9() Color {
    return .{ .r = 177, .g = 45, .b = 187 };
}

pub const Widget_8_10 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_10",
};

pub fn layout_widget_8_10(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_10(gpa: std.mem.Allocator, w: Widget_8_10) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_10(w: *Widget_8_10, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_10() Color {
    return .{ .r = 194, .g = 74, .b = 230 };
}

pub const Widget_8_11 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_11",
};

pub fn layout_widget_8_11(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_11(gpa: std.mem.Allocator, w: Widget_8_11) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_11(w: *Widget_8_11, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_11() Color {
    return .{ .r = 211, .g = 103, .b = 17 };
}

pub const Widget_8_12 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_12",
};

pub fn layout_widget_8_12(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_12(gpa: std.mem.Allocator, w: Widget_8_12) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_12(w: *Widget_8_12, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_12() Color {
    return .{ .r = 228, .g = 132, .b = 60 };
}

pub const Widget_8_13 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_13",
};

pub fn layout_widget_8_13(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_13(gpa: std.mem.Allocator, w: Widget_8_13) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_13(w: *Widget_8_13, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_13() Color {
    return .{ .r = 245, .g = 161, .b = 103 };
}

pub const Widget_8_14 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_14",
};

pub fn layout_widget_8_14(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_14(gpa: std.mem.Allocator, w: Widget_8_14) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_14(w: *Widget_8_14, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_14() Color {
    return .{ .r = 6, .g = 190, .b = 146 };
}

pub const Widget_8_15 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_15",
};

pub fn layout_widget_8_15(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_15(gpa: std.mem.Allocator, w: Widget_8_15) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_15(w: *Widget_8_15, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_15() Color {
    return .{ .r = 23, .g = 219, .b = 189 };
}

pub const Widget_8_16 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_16",
};

pub fn layout_widget_8_16(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_16(gpa: std.mem.Allocator, w: Widget_8_16) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_16(w: *Widget_8_16, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_16() Color {
    return .{ .r = 40, .g = 248, .b = 232 };
}

pub const Widget_8_17 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_17",
};

pub fn layout_widget_8_17(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_17(gpa: std.mem.Allocator, w: Widget_8_17) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_17(w: *Widget_8_17, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_17() Color {
    return .{ .r = 57, .g = 21, .b = 19 };
}

pub const Widget_8_18 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_18",
};

pub fn layout_widget_8_18(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_18(gpa: std.mem.Allocator, w: Widget_8_18) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_18(w: *Widget_8_18, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_18() Color {
    return .{ .r = 74, .g = 50, .b = 62 };
}

pub const Widget_8_19 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_19",
};

pub fn layout_widget_8_19(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_19(gpa: std.mem.Allocator, w: Widget_8_19) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_19(w: *Widget_8_19, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_19() Color {
    return .{ .r = 91, .g = 79, .b = 105 };
}

pub const Widget_8_20 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_20",
};

pub fn layout_widget_8_20(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_20(gpa: std.mem.Allocator, w: Widget_8_20) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_20(w: *Widget_8_20, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_20() Color {
    return .{ .r = 108, .g = 108, .b = 148 };
}

pub const Widget_8_21 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_21",
};

pub fn layout_widget_8_21(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_21(gpa: std.mem.Allocator, w: Widget_8_21) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_21(w: *Widget_8_21, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_21() Color {
    return .{ .r = 125, .g = 137, .b = 191 };
}

pub const Widget_8_22 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_22",
};

pub fn layout_widget_8_22(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_22(gpa: std.mem.Allocator, w: Widget_8_22) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_22(w: *Widget_8_22, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_22() Color {
    return .{ .r = 142, .g = 166, .b = 234 };
}

pub const Widget_8_23 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_23",
};

pub fn layout_widget_8_23(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_23(gpa: std.mem.Allocator, w: Widget_8_23) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_23(w: *Widget_8_23, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_23() Color {
    return .{ .r = 159, .g = 195, .b = 21 };
}

pub const Widget_8_24 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_24",
};

pub fn layout_widget_8_24(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_24(gpa: std.mem.Allocator, w: Widget_8_24) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_24(w: *Widget_8_24, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_24() Color {
    return .{ .r = 176, .g = 224, .b = 64 };
}

pub const Widget_8_25 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_25",
};

pub fn layout_widget_8_25(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_25(gpa: std.mem.Allocator, w: Widget_8_25) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_25(w: *Widget_8_25, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_25() Color {
    return .{ .r = 193, .g = 253, .b = 107 };
}

pub const Widget_8_26 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_26",
};

pub fn layout_widget_8_26(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_26(gpa: std.mem.Allocator, w: Widget_8_26) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_26(w: *Widget_8_26, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_26() Color {
    return .{ .r = 210, .g = 26, .b = 150 };
}

pub const Widget_8_27 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_27",
};

pub fn layout_widget_8_27(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_27(gpa: std.mem.Allocator, w: Widget_8_27) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_27(w: *Widget_8_27, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_27() Color {
    return .{ .r = 227, .g = 55, .b = 193 };
}

pub const Widget_8_28 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_28",
};

pub fn layout_widget_8_28(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_28(gpa: std.mem.Allocator, w: Widget_8_28) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_28(w: *Widget_8_28, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_28() Color {
    return .{ .r = 244, .g = 84, .b = 236 };
}

pub const Widget_8_29 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_29",
};

pub fn layout_widget_8_29(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_29(gpa: std.mem.Allocator, w: Widget_8_29) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_29(w: *Widget_8_29, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_29() Color {
    return .{ .r = 5, .g = 113, .b = 23 };
}

pub const Widget_8_30 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_30",
};

pub fn layout_widget_8_30(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_30(gpa: std.mem.Allocator, w: Widget_8_30) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_30(w: *Widget_8_30, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_30() Color {
    return .{ .r = 22, .g = 142, .b = 66 };
}

pub const Widget_8_31 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_31",
};

pub fn layout_widget_8_31(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_31(gpa: std.mem.Allocator, w: Widget_8_31) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_31(w: *Widget_8_31, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_31() Color {
    return .{ .r = 39, .g = 171, .b = 109 };
}

pub const Widget_8_32 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_32",
};

pub fn layout_widget_8_32(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_32(gpa: std.mem.Allocator, w: Widget_8_32) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_32(w: *Widget_8_32, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_32() Color {
    return .{ .r = 56, .g = 200, .b = 152 };
}

pub const Widget_8_33 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_33",
};

pub fn layout_widget_8_33(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_33(gpa: std.mem.Allocator, w: Widget_8_33) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_33(w: *Widget_8_33, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_33() Color {
    return .{ .r = 73, .g = 229, .b = 195 };
}

pub const Widget_8_34 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_34",
};

pub fn layout_widget_8_34(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_34(gpa: std.mem.Allocator, w: Widget_8_34) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_34(w: *Widget_8_34, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_34() Color {
    return .{ .r = 90, .g = 2, .b = 238 };
}

pub const Widget_8_35 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_35",
};

pub fn layout_widget_8_35(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_35(gpa: std.mem.Allocator, w: Widget_8_35) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_35(w: *Widget_8_35, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_35() Color {
    return .{ .r = 107, .g = 31, .b = 25 };
}

pub const Widget_8_36 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_36",
};

pub fn layout_widget_8_36(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_36(gpa: std.mem.Allocator, w: Widget_8_36) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_36(w: *Widget_8_36, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_36() Color {
    return .{ .r = 124, .g = 60, .b = 68 };
}

pub const Widget_8_37 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_37",
};

pub fn layout_widget_8_37(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_37(gpa: std.mem.Allocator, w: Widget_8_37) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_37(w: *Widget_8_37, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_37() Color {
    return .{ .r = 141, .g = 89, .b = 111 };
}

pub const Widget_8_38 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_38",
};

pub fn layout_widget_8_38(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_38(gpa: std.mem.Allocator, w: Widget_8_38) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_38(w: *Widget_8_38, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_38() Color {
    return .{ .r = 158, .g = 118, .b = 154 };
}

pub const Widget_8_39 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_8_39",
};

pub fn layout_widget_8_39(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_8_39(gpa: std.mem.Allocator, w: Widget_8_39) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_8_39(w: *Widget_8_39, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_8_39() Color {
    return .{ .r = 175, .g = 147, .b = 197 };
}

test "tui shard 8 layout" {
    const parent = Rect{ .x = 0, .y = 0, .w = 80, .h = 24 };
    const r = layout_widget_8_0(parent, 0, 3);
    try std.testing.expect(r.w == 80);
    try std.testing.expect(rectContains(parent, 1, 1));
    const gpa = std.testing.allocator;
    var w = Widget_8_0{ .bounds = r };
    handle_key_8_0(&w, 'j');
    try std.testing.expect(w.scroll == 1);
    const painted = try paint_widget_8_0(gpa, w);
    defer gpa.free(painted);
    try std.testing.expect(painted.len > 0);
}

