//! Generated TUI layout/widget helpers shard 4 (tui).
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

pub const Widget_4_0 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_0",
};

pub fn layout_widget_4_0(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_0(gpa: std.mem.Allocator, w: Widget_4_0) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_0(w: *Widget_4_0, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_0() Color {
    return .{ .r = 12, .g = 20, .b = 28 };
}

pub const Widget_4_1 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_1",
};

pub fn layout_widget_4_1(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_1(gpa: std.mem.Allocator, w: Widget_4_1) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_1(w: *Widget_4_1, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_1() Color {
    return .{ .r = 29, .g = 49, .b = 71 };
}

pub const Widget_4_2 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_2",
};

pub fn layout_widget_4_2(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_2(gpa: std.mem.Allocator, w: Widget_4_2) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_2(w: *Widget_4_2, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_2() Color {
    return .{ .r = 46, .g = 78, .b = 114 };
}

pub const Widget_4_3 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_3",
};

pub fn layout_widget_4_3(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_3(gpa: std.mem.Allocator, w: Widget_4_3) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_3(w: *Widget_4_3, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_3() Color {
    return .{ .r = 63, .g = 107, .b = 157 };
}

pub const Widget_4_4 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_4",
};

pub fn layout_widget_4_4(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_4(gpa: std.mem.Allocator, w: Widget_4_4) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_4(w: *Widget_4_4, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_4() Color {
    return .{ .r = 80, .g = 136, .b = 200 };
}

pub const Widget_4_5 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_5",
};

pub fn layout_widget_4_5(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_5(gpa: std.mem.Allocator, w: Widget_4_5) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_5(w: *Widget_4_5, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_5() Color {
    return .{ .r = 97, .g = 165, .b = 243 };
}

pub const Widget_4_6 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_6",
};

pub fn layout_widget_4_6(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_6(gpa: std.mem.Allocator, w: Widget_4_6) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_6(w: *Widget_4_6, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_6() Color {
    return .{ .r = 114, .g = 194, .b = 30 };
}

pub const Widget_4_7 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_7",
};

pub fn layout_widget_4_7(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_7(gpa: std.mem.Allocator, w: Widget_4_7) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_7(w: *Widget_4_7, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_7() Color {
    return .{ .r = 131, .g = 223, .b = 73 };
}

pub const Widget_4_8 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_8",
};

pub fn layout_widget_4_8(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_8(gpa: std.mem.Allocator, w: Widget_4_8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_8(w: *Widget_4_8, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_8() Color {
    return .{ .r = 148, .g = 252, .b = 116 };
}

pub const Widget_4_9 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_9",
};

pub fn layout_widget_4_9(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_9(gpa: std.mem.Allocator, w: Widget_4_9) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_9(w: *Widget_4_9, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_9() Color {
    return .{ .r = 165, .g = 25, .b = 159 };
}

pub const Widget_4_10 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_10",
};

pub fn layout_widget_4_10(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_10(gpa: std.mem.Allocator, w: Widget_4_10) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_10(w: *Widget_4_10, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_10() Color {
    return .{ .r = 182, .g = 54, .b = 202 };
}

pub const Widget_4_11 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_11",
};

pub fn layout_widget_4_11(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_11(gpa: std.mem.Allocator, w: Widget_4_11) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_11(w: *Widget_4_11, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_11() Color {
    return .{ .r = 199, .g = 83, .b = 245 };
}

pub const Widget_4_12 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_12",
};

pub fn layout_widget_4_12(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_12(gpa: std.mem.Allocator, w: Widget_4_12) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_12(w: *Widget_4_12, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_12() Color {
    return .{ .r = 216, .g = 112, .b = 32 };
}

pub const Widget_4_13 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_13",
};

pub fn layout_widget_4_13(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_13(gpa: std.mem.Allocator, w: Widget_4_13) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_13(w: *Widget_4_13, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_13() Color {
    return .{ .r = 233, .g = 141, .b = 75 };
}

pub const Widget_4_14 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_14",
};

pub fn layout_widget_4_14(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_14(gpa: std.mem.Allocator, w: Widget_4_14) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_14(w: *Widget_4_14, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_14() Color {
    return .{ .r = 250, .g = 170, .b = 118 };
}

pub const Widget_4_15 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_15",
};

pub fn layout_widget_4_15(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_15(gpa: std.mem.Allocator, w: Widget_4_15) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_15(w: *Widget_4_15, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_15() Color {
    return .{ .r = 11, .g = 199, .b = 161 };
}

pub const Widget_4_16 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_16",
};

pub fn layout_widget_4_16(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_16(gpa: std.mem.Allocator, w: Widget_4_16) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_16(w: *Widget_4_16, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_16() Color {
    return .{ .r = 28, .g = 228, .b = 204 };
}

pub const Widget_4_17 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_17",
};

pub fn layout_widget_4_17(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_17(gpa: std.mem.Allocator, w: Widget_4_17) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_17(w: *Widget_4_17, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_17() Color {
    return .{ .r = 45, .g = 1, .b = 247 };
}

pub const Widget_4_18 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_18",
};

pub fn layout_widget_4_18(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_18(gpa: std.mem.Allocator, w: Widget_4_18) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_18(w: *Widget_4_18, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_18() Color {
    return .{ .r = 62, .g = 30, .b = 34 };
}

pub const Widget_4_19 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_19",
};

pub fn layout_widget_4_19(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_19(gpa: std.mem.Allocator, w: Widget_4_19) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_19(w: *Widget_4_19, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_19() Color {
    return .{ .r = 79, .g = 59, .b = 77 };
}

pub const Widget_4_20 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_20",
};

pub fn layout_widget_4_20(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_20(gpa: std.mem.Allocator, w: Widget_4_20) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_20(w: *Widget_4_20, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_20() Color {
    return .{ .r = 96, .g = 88, .b = 120 };
}

pub const Widget_4_21 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_21",
};

pub fn layout_widget_4_21(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_21(gpa: std.mem.Allocator, w: Widget_4_21) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_21(w: *Widget_4_21, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_21() Color {
    return .{ .r = 113, .g = 117, .b = 163 };
}

pub const Widget_4_22 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_22",
};

pub fn layout_widget_4_22(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_22(gpa: std.mem.Allocator, w: Widget_4_22) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_22(w: *Widget_4_22, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_22() Color {
    return .{ .r = 130, .g = 146, .b = 206 };
}

pub const Widget_4_23 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_23",
};

pub fn layout_widget_4_23(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_23(gpa: std.mem.Allocator, w: Widget_4_23) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_23(w: *Widget_4_23, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_23() Color {
    return .{ .r = 147, .g = 175, .b = 249 };
}

pub const Widget_4_24 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_24",
};

pub fn layout_widget_4_24(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_24(gpa: std.mem.Allocator, w: Widget_4_24) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_24(w: *Widget_4_24, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_24() Color {
    return .{ .r = 164, .g = 204, .b = 36 };
}

pub const Widget_4_25 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_25",
};

pub fn layout_widget_4_25(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_25(gpa: std.mem.Allocator, w: Widget_4_25) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_25(w: *Widget_4_25, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_25() Color {
    return .{ .r = 181, .g = 233, .b = 79 };
}

pub const Widget_4_26 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_26",
};

pub fn layout_widget_4_26(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_26(gpa: std.mem.Allocator, w: Widget_4_26) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_26(w: *Widget_4_26, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_26() Color {
    return .{ .r = 198, .g = 6, .b = 122 };
}

pub const Widget_4_27 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_27",
};

pub fn layout_widget_4_27(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_27(gpa: std.mem.Allocator, w: Widget_4_27) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_27(w: *Widget_4_27, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_27() Color {
    return .{ .r = 215, .g = 35, .b = 165 };
}

pub const Widget_4_28 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_28",
};

pub fn layout_widget_4_28(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_28(gpa: std.mem.Allocator, w: Widget_4_28) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_28(w: *Widget_4_28, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_28() Color {
    return .{ .r = 232, .g = 64, .b = 208 };
}

pub const Widget_4_29 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_29",
};

pub fn layout_widget_4_29(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_29(gpa: std.mem.Allocator, w: Widget_4_29) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_29(w: *Widget_4_29, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_29() Color {
    return .{ .r = 249, .g = 93, .b = 251 };
}

pub const Widget_4_30 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_30",
};

pub fn layout_widget_4_30(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_30(gpa: std.mem.Allocator, w: Widget_4_30) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_30(w: *Widget_4_30, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_30() Color {
    return .{ .r = 10, .g = 122, .b = 38 };
}

pub const Widget_4_31 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_31",
};

pub fn layout_widget_4_31(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_31(gpa: std.mem.Allocator, w: Widget_4_31) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_31(w: *Widget_4_31, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_31() Color {
    return .{ .r = 27, .g = 151, .b = 81 };
}

pub const Widget_4_32 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_32",
};

pub fn layout_widget_4_32(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_32(gpa: std.mem.Allocator, w: Widget_4_32) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_32(w: *Widget_4_32, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_32() Color {
    return .{ .r = 44, .g = 180, .b = 124 };
}

pub const Widget_4_33 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_33",
};

pub fn layout_widget_4_33(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_33(gpa: std.mem.Allocator, w: Widget_4_33) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_33(w: *Widget_4_33, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_33() Color {
    return .{ .r = 61, .g = 209, .b = 167 };
}

pub const Widget_4_34 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_34",
};

pub fn layout_widget_4_34(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_34(gpa: std.mem.Allocator, w: Widget_4_34) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_34(w: *Widget_4_34, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_34() Color {
    return .{ .r = 78, .g = 238, .b = 210 };
}

pub const Widget_4_35 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_35",
};

pub fn layout_widget_4_35(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_35(gpa: std.mem.Allocator, w: Widget_4_35) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_35(w: *Widget_4_35, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_35() Color {
    return .{ .r = 95, .g = 11, .b = 253 };
}

pub const Widget_4_36 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_36",
};

pub fn layout_widget_4_36(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_36(gpa: std.mem.Allocator, w: Widget_4_36) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_36(w: *Widget_4_36, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_36() Color {
    return .{ .r = 112, .g = 40, .b = 40 };
}

pub const Widget_4_37 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_37",
};

pub fn layout_widget_4_37(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_37(gpa: std.mem.Allocator, w: Widget_4_37) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_37(w: *Widget_4_37, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_37() Color {
    return .{ .r = 129, .g = 69, .b = 83 };
}

pub const Widget_4_38 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_38",
};

pub fn layout_widget_4_38(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_38(gpa: std.mem.Allocator, w: Widget_4_38) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_38(w: *Widget_4_38, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_38() Color {
    return .{ .r = 146, .g = 98, .b = 126 };
}

pub const Widget_4_39 = struct {
    bounds: Rect,
    focused: bool = false,
    scroll: u32 = 0,
    label: []const u8 = "widget_4_39",
};

pub fn layout_widget_4_39(parent: Rect, index: u16, total: u16) Rect {
    if (total == 0) return parent;
    const h: u16 = if (parent.h / total == 0) 1 else parent.h / total;
    const y: u16 = parent.y +% index *% h;
    return .{ .x = parent.x, .y = y, .w = parent.w, .h = h };
}

pub fn paint_widget_4_39(gpa: std.mem.Allocator, w: Widget_4_39) ![]u8 {
    return try std.fmt.allocPrint(gpa, "[{s} focus={} scroll={d} @{d},{d} {d}x{d}]", .{
        w.label, w.focused, w.scroll, w.bounds.x, w.bounds.y, w.bounds.w, w.bounds.h,
    });
}

pub fn handle_key_4_39(w: *Widget_4_39, key: u8) void {
    if (key == 'j') w.scroll +%= 1;
    if (key == 'k' and w.scroll > 0) w.scroll -%= 1;
    if (key == '\t') w.focused = !w.focused;
}

pub fn color_theme_4_39() Color {
    return .{ .r = 163, .g = 127, .b = 169 };
}

test "tui shard 4 layout" {
    const parent = Rect{ .x = 0, .y = 0, .w = 80, .h = 24 };
    const r = layout_widget_4_0(parent, 0, 3);
    try std.testing.expect(r.w == 80);
    try std.testing.expect(rectContains(parent, 1, 1));
    const gpa = std.testing.allocator;
    var w = Widget_4_0{ .bounds = r };
    handle_key_4_0(&w, 'j');
    try std.testing.expect(w.scroll == 1);
    const painted = try paint_widget_4_0(gpa, w);
    defer gpa.free(painted);
    try std.testing.expect(painted.len > 0);
}

