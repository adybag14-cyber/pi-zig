//! Generated TUI layout/widget helpers shard 3 (tui).
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

pub const Widget_3_0 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_0",
};

pub fn layout_widget_3_0(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_0(gpa: std.mem.Allocator, w: Widget_3_0) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_0(w: *Widget_3_0, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_0() Color {
    return .{ .r = 9, .g = 15, .b = 21 };
}

pub const Widget_3_1 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_1",
};

pub fn layout_widget_3_1(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_1(gpa: std.mem.Allocator, w: Widget_3_1) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_1(w: *Widget_3_1, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_1() Color {
    return .{ .r = 26, .g = 44, .b = 64 };
}

pub const Widget_3_2 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_2",
};

pub fn layout_widget_3_2(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_2(gpa: std.mem.Allocator, w: Widget_3_2) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_2(w: *Widget_3_2, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_2() Color {
    return .{ .r = 43, .g = 73, .b = 107 };
}

pub const Widget_3_3 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_3",
};

pub fn layout_widget_3_3(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_3(gpa: std.mem.Allocator, w: Widget_3_3) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_3(w: *Widget_3_3, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_3() Color {
    return .{ .r = 60, .g = 102, .b = 150 };
}

pub const Widget_3_4 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_4",
};

pub fn layout_widget_3_4(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_4(gpa: std.mem.Allocator, w: Widget_3_4) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_4(w: *Widget_3_4, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_4() Color {
    return .{ .r = 77, .g = 131, .b = 193 };
}

pub const Widget_3_5 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_5",
};

pub fn layout_widget_3_5(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_5(gpa: std.mem.Allocator, w: Widget_3_5) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_5(w: *Widget_3_5, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_5() Color {
    return .{ .r = 94, .g = 160, .b = 236 };
}

pub const Widget_3_6 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_6",
};

pub fn layout_widget_3_6(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_6(gpa: std.mem.Allocator, w: Widget_3_6) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_6(w: *Widget_3_6, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_6() Color {
    return .{ .r = 111, .g = 189, .b = 23 };
}

pub const Widget_3_7 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_7",
};

pub fn layout_widget_3_7(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_7(gpa: std.mem.Allocator, w: Widget_3_7) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_7(w: *Widget_3_7, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_7() Color {
    return .{ .r = 128, .g = 218, .b = 66 };
}

pub const Widget_3_8 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_8",
};

pub fn layout_widget_3_8(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_8(gpa: std.mem.Allocator, w: Widget_3_8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_8(w: *Widget_3_8, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_8() Color {
    return .{ .r = 145, .g = 247, .b = 109 };
}

pub const Widget_3_9 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_9",
};

pub fn layout_widget_3_9(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_9(gpa: std.mem.Allocator, w: Widget_3_9) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_9(w: *Widget_3_9, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_9() Color {
    return .{ .r = 162, .g = 20, .b = 152 };
}

pub const Widget_3_10 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_10",
};

pub fn layout_widget_3_10(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_10(gpa: std.mem.Allocator, w: Widget_3_10) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_10(w: *Widget_3_10, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_10() Color {
    return .{ .r = 179, .g = 49, .b = 195 };
}

pub const Widget_3_11 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_11",
};

pub fn layout_widget_3_11(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_11(gpa: std.mem.Allocator, w: Widget_3_11) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_11(w: *Widget_3_11, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_11() Color {
    return .{ .r = 196, .g = 78, .b = 238 };
}

pub const Widget_3_12 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_12",
};

pub fn layout_widget_3_12(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_12(gpa: std.mem.Allocator, w: Widget_3_12) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_12(w: *Widget_3_12, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_12() Color {
    return .{ .r = 213, .g = 107, .b = 25 };
}

pub const Widget_3_13 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_13",
};

pub fn layout_widget_3_13(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_13(gpa: std.mem.Allocator, w: Widget_3_13) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_13(w: *Widget_3_13, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_13() Color {
    return .{ .r = 230, .g = 136, .b = 68 };
}

pub const Widget_3_14 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_14",
};

pub fn layout_widget_3_14(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_14(gpa: std.mem.Allocator, w: Widget_3_14) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_14(w: *Widget_3_14, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_14() Color {
    return .{ .r = 247, .g = 165, .b = 111 };
}

pub const Widget_3_15 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_15",
};

pub fn layout_widget_3_15(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_15(gpa: std.mem.Allocator, w: Widget_3_15) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_15(w: *Widget_3_15, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_15() Color {
    return .{ .r = 8, .g = 194, .b = 154 };
}

pub const Widget_3_16 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_16",
};

pub fn layout_widget_3_16(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_16(gpa: std.mem.Allocator, w: Widget_3_16) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_16(w: *Widget_3_16, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_16() Color {
    return .{ .r = 25, .g = 223, .b = 197 };
}

pub const Widget_3_17 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_17",
};

pub fn layout_widget_3_17(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_17(gpa: std.mem.Allocator, w: Widget_3_17) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_17(w: *Widget_3_17, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_17() Color {
    return .{ .r = 42, .g = 252, .b = 240 };
}

pub const Widget_3_18 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_18",
};

pub fn layout_widget_3_18(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_18(gpa: std.mem.Allocator, w: Widget_3_18) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_18(w: *Widget_3_18, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_18() Color {
    return .{ .r = 59, .g = 25, .b = 27 };
}

pub const Widget_3_19 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_19",
};

pub fn layout_widget_3_19(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_19(gpa: std.mem.Allocator, w: Widget_3_19) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_19(w: *Widget_3_19, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_19() Color {
    return .{ .r = 76, .g = 54, .b = 70 };
}

pub const Widget_3_20 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_20",
};

pub fn layout_widget_3_20(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_20(gpa: std.mem.Allocator, w: Widget_3_20) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_20(w: *Widget_3_20, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_20() Color {
    return .{ .r = 93, .g = 83, .b = 113 };
}

pub const Widget_3_21 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_21",
};

pub fn layout_widget_3_21(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_21(gpa: std.mem.Allocator, w: Widget_3_21) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_21(w: *Widget_3_21, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_21() Color {
    return .{ .r = 110, .g = 112, .b = 156 };
}

pub const Widget_3_22 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_22",
};

pub fn layout_widget_3_22(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_22(gpa: std.mem.Allocator, w: Widget_3_22) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_22(w: *Widget_3_22, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_22() Color {
    return .{ .r = 127, .g = 141, .b = 199 };
}

pub const Widget_3_23 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_23",
};

pub fn layout_widget_3_23(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_23(gpa: std.mem.Allocator, w: Widget_3_23) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_23(w: *Widget_3_23, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_23() Color {
    return .{ .r = 144, .g = 170, .b = 242 };
}

pub const Widget_3_24 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_24",
};

pub fn layout_widget_3_24(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_24(gpa: std.mem.Allocator, w: Widget_3_24) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_24(w: *Widget_3_24, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_24() Color {
    return .{ .r = 161, .g = 199, .b = 29 };
}

pub const Widget_3_25 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_25",
};

pub fn layout_widget_3_25(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_25(gpa: std.mem.Allocator, w: Widget_3_25) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_25(w: *Widget_3_25, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_25() Color {
    return .{ .r = 178, .g = 228, .b = 72 };
}

pub const Widget_3_26 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_26",
};

pub fn layout_widget_3_26(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_26(gpa: std.mem.Allocator, w: Widget_3_26) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_26(w: *Widget_3_26, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_26() Color {
    return .{ .r = 195, .g = 1, .b = 115 };
}

pub const Widget_3_27 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_27",
};

pub fn layout_widget_3_27(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_27(gpa: std.mem.Allocator, w: Widget_3_27) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_27(w: *Widget_3_27, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_27() Color {
    return .{ .r = 212, .g = 30, .b = 158 };
}

pub const Widget_3_28 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_28",
};

pub fn layout_widget_3_28(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_28(gpa: std.mem.Allocator, w: Widget_3_28) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_28(w: *Widget_3_28, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_28() Color {
    return .{ .r = 229, .g = 59, .b = 201 };
}

pub const Widget_3_29 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_29",
};

pub fn layout_widget_3_29(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_29(gpa: std.mem.Allocator, w: Widget_3_29) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_29(w: *Widget_3_29, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_29() Color {
    return .{ .r = 246, .g = 88, .b = 244 };
}

pub const Widget_3_30 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_30",
};

pub fn layout_widget_3_30(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_30(gpa: std.mem.Allocator, w: Widget_3_30) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_30(w: *Widget_3_30, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_30() Color {
    return .{ .r = 7, .g = 117, .b = 31 };
}

pub const Widget_3_31 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_31",
};

pub fn layout_widget_3_31(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_31(gpa: std.mem.Allocator, w: Widget_3_31) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_31(w: *Widget_3_31, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_31() Color {
    return .{ .r = 24, .g = 146, .b = 74 };
}

pub const Widget_3_32 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_32",
};

pub fn layout_widget_3_32(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_32(gpa: std.mem.Allocator, w: Widget_3_32) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_32(w: *Widget_3_32, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_32() Color {
    return .{ .r = 41, .g = 175, .b = 117 };
}

pub const Widget_3_33 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_33",
};

pub fn layout_widget_3_33(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_33(gpa: std.mem.Allocator, w: Widget_3_33) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_33(w: *Widget_3_33, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_33() Color {
    return .{ .r = 58, .g = 204, .b = 160 };
}

pub const Widget_3_34 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_34",
};

pub fn layout_widget_3_34(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_34(gpa: std.mem.Allocator, w: Widget_3_34) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_34(w: *Widget_3_34, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_34() Color {
    return .{ .r = 75, .g = 233, .b = 203 };
}

pub const Widget_3_35 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_35",
};

pub fn layout_widget_3_35(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_35(gpa: std.mem.Allocator, w: Widget_3_35) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_35(w: *Widget_3_35, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_35() Color {
    return .{ .r = 92, .g = 6, .b = 246 };
}

pub const Widget_3_36 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_36",
};

pub fn layout_widget_3_36(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_36(gpa: std.mem.Allocator, w: Widget_3_36) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_36(w: *Widget_3_36, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_36() Color {
    return .{ .r = 109, .g = 35, .b = 33 };
}

pub const Widget_3_37 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_37",
};

pub fn layout_widget_3_37(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_37(gpa: std.mem.Allocator, w: Widget_3_37) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_37(w: *Widget_3_37, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_37() Color {
    return .{ .r = 126, .g = 64, .b = 76 };
}

pub const Widget_3_38 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_38",
};

pub fn layout_widget_3_38(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_38(gpa: std.mem.Allocator, w: Widget_3_38) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_38(w: *Widget_3_38, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_38() Color {
    return .{ .r = 143, .g = 93, .b = 119 };
}

pub const Widget_3_39 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_3_39",
};

pub fn layout_widget_3_39(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_3_39(gpa: std.mem.Allocator, w: Widget_3_39) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_3_39(w: *Widget_3_39, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_3_39() Color {
    return .{ .r = 160, .g = 122, .b = 162 };
}

test "tui shard 3 layout" {
    const parent = Rect{ .x = 0, .y = 0, .w = 80, .h = 24 };
    const r = layout_widget_3_0(parent, 0, 3);
    try std.testing.expect(r.w == 80);
    try std.testing.expect(rectContains(parent, 1, 1));
    const gpa = std.testing.allocator;
    var w = Widget_3_0{ .bounds = r };
    handle_key_3_0(&w, 'j');
    try std.testing.expect(w.scroll == 1);
    const painted = try paint_widget_3_0(gpa, w);
    defer gpa.free(painted);
    try std.testing.expect(painted.len > 0);
}

