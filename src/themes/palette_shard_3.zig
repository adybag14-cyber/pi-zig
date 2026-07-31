//! Generated theme palettes shard 3.
const std = @import("std");

pub const Palette = struct {
    name: []const u8,
    bg: []const u8,
    fg: []const u8,
    accent: []const u8,
    error_c: []const u8,
    success: []const u8,
    warning: []const u8,
    muted: []const u8,
};

pub fn palette_3_0() Palette {
    return .{ .name = "theme_3_0", .bg = "#000000", .fg = "#ffffff", .accent = "#ff5555", .error_c = "#50fa7b", .success = "#f1fa8c", .warning = "#bd93f9", .muted = "#ff79c6" };
}
pub fn palette_3_0_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_0();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_0_sgr_accent() []const u8 { return "38;2;0;0;0"; }
pub fn palette_3_0_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_0_sgr_accent(), text});
}

pub fn palette_3_1() Palette {
    return .{ .name = "theme_3_1", .bg = "#ffffff", .fg = "#ff5555", .accent = "#50fa7b", .error_c = "#f1fa8c", .success = "#bd93f9", .warning = "#ff79c6", .muted = "#8be9fd" };
}
pub fn palette_3_1_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_1();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_1_sgr_accent() []const u8 { return "38;2;40;70;110"; }
pub fn palette_3_1_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_1_sgr_accent(), text});
}

pub fn palette_3_2() Palette {
    return .{ .name = "theme_3_2", .bg = "#ff5555", .fg = "#50fa7b", .accent = "#f1fa8c", .error_c = "#bd93f9", .success = "#ff79c6", .warning = "#8be9fd", .muted = "#6272a4" };
}
pub fn palette_3_2_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_2();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_2_sgr_accent() []const u8 { return "38;2;80;140;220"; }
pub fn palette_3_2_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_2_sgr_accent(), text});
}

pub fn palette_3_3() Palette {
    return .{ .name = "theme_3_3", .bg = "#50fa7b", .fg = "#f1fa8c", .accent = "#bd93f9", .error_c = "#ff79c6", .success = "#8be9fd", .warning = "#6272a4", .muted = "#44475a" };
}
pub fn palette_3_3_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_3();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_3_sgr_accent() []const u8 { return "38;2;120;210;74"; }
pub fn palette_3_3_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_3_sgr_accent(), text});
}

pub fn palette_3_4() Palette {
    return .{ .name = "theme_3_4", .bg = "#f1fa8c", .fg = "#bd93f9", .accent = "#ff79c6", .error_c = "#8be9fd", .success = "#6272a4", .warning = "#44475a", .muted = "#000000" };
}
pub fn palette_3_4_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_4();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_4_sgr_accent() []const u8 { return "38;2;160;24;184"; }
pub fn palette_3_4_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_4_sgr_accent(), text});
}

pub fn palette_3_5() Palette {
    return .{ .name = "theme_3_5", .bg = "#bd93f9", .fg = "#ff79c6", .accent = "#8be9fd", .error_c = "#6272a4", .success = "#44475a", .warning = "#000000", .muted = "#ffffff" };
}
pub fn palette_3_5_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_5();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_5_sgr_accent() []const u8 { return "38;2;200;94;38"; }
pub fn palette_3_5_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_5_sgr_accent(), text});
}

pub fn palette_3_6() Palette {
    return .{ .name = "theme_3_6", .bg = "#ff79c6", .fg = "#8be9fd", .accent = "#6272a4", .error_c = "#44475a", .success = "#000000", .warning = "#ffffff", .muted = "#ff5555" };
}
pub fn palette_3_6_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_6();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_6_sgr_accent() []const u8 { return "38;2;240;164;148"; }
pub fn palette_3_6_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_6_sgr_accent(), text});
}

pub fn palette_3_7() Palette {
    return .{ .name = "theme_3_7", .bg = "#8be9fd", .fg = "#6272a4", .accent = "#44475a", .error_c = "#000000", .success = "#ffffff", .warning = "#ff5555", .muted = "#50fa7b" };
}
pub fn palette_3_7_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_7();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_7_sgr_accent() []const u8 { return "38;2;24;234;2"; }
pub fn palette_3_7_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_7_sgr_accent(), text});
}

pub fn palette_3_8() Palette {
    return .{ .name = "theme_3_8", .bg = "#6272a4", .fg = "#44475a", .accent = "#000000", .error_c = "#ffffff", .success = "#ff5555", .warning = "#50fa7b", .muted = "#f1fa8c" };
}
pub fn palette_3_8_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_8();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_8_sgr_accent() []const u8 { return "38;2;64;48;112"; }
pub fn palette_3_8_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_8_sgr_accent(), text});
}

pub fn palette_3_9() Palette {
    return .{ .name = "theme_3_9", .bg = "#44475a", .fg = "#000000", .accent = "#ffffff", .error_c = "#ff5555", .success = "#50fa7b", .warning = "#f1fa8c", .muted = "#bd93f9" };
}
pub fn palette_3_9_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_9();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_9_sgr_accent() []const u8 { return "38;2;104;118;222"; }
pub fn palette_3_9_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_9_sgr_accent(), text});
}

pub fn palette_3_10() Palette {
    return .{ .name = "theme_3_10", .bg = "#000000", .fg = "#ffffff", .accent = "#ff5555", .error_c = "#50fa7b", .success = "#f1fa8c", .warning = "#bd93f9", .muted = "#ff79c6" };
}
pub fn palette_3_10_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_10();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_10_sgr_accent() []const u8 { return "38;2;144;188;76"; }
pub fn palette_3_10_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_10_sgr_accent(), text});
}

pub fn palette_3_11() Palette {
    return .{ .name = "theme_3_11", .bg = "#ffffff", .fg = "#ff5555", .accent = "#50fa7b", .error_c = "#f1fa8c", .success = "#bd93f9", .warning = "#ff79c6", .muted = "#8be9fd" };
}
pub fn palette_3_11_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_11();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_11_sgr_accent() []const u8 { return "38;2;184;2;186"; }
pub fn palette_3_11_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_11_sgr_accent(), text});
}

pub fn palette_3_12() Palette {
    return .{ .name = "theme_3_12", .bg = "#ff5555", .fg = "#50fa7b", .accent = "#f1fa8c", .error_c = "#bd93f9", .success = "#ff79c6", .warning = "#8be9fd", .muted = "#6272a4" };
}
pub fn palette_3_12_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_12();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_12_sgr_accent() []const u8 { return "38;2;224;72;40"; }
pub fn palette_3_12_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_12_sgr_accent(), text});
}

pub fn palette_3_13() Palette {
    return .{ .name = "theme_3_13", .bg = "#50fa7b", .fg = "#f1fa8c", .accent = "#bd93f9", .error_c = "#ff79c6", .success = "#8be9fd", .warning = "#6272a4", .muted = "#44475a" };
}
pub fn palette_3_13_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_13();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_13_sgr_accent() []const u8 { return "38;2;8;142;150"; }
pub fn palette_3_13_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_13_sgr_accent(), text});
}

pub fn palette_3_14() Palette {
    return .{ .name = "theme_3_14", .bg = "#f1fa8c", .fg = "#bd93f9", .accent = "#ff79c6", .error_c = "#8be9fd", .success = "#6272a4", .warning = "#44475a", .muted = "#000000" };
}
pub fn palette_3_14_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_14();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_14_sgr_accent() []const u8 { return "38;2;48;212;4"; }
pub fn palette_3_14_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_14_sgr_accent(), text});
}

pub fn palette_3_15() Palette {
    return .{ .name = "theme_3_15", .bg = "#bd93f9", .fg = "#ff79c6", .accent = "#8be9fd", .error_c = "#6272a4", .success = "#44475a", .warning = "#000000", .muted = "#ffffff" };
}
pub fn palette_3_15_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_15();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_15_sgr_accent() []const u8 { return "38;2;88;26;114"; }
pub fn palette_3_15_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_15_sgr_accent(), text});
}

pub fn palette_3_16() Palette {
    return .{ .name = "theme_3_16", .bg = "#ff79c6", .fg = "#8be9fd", .accent = "#6272a4", .error_c = "#44475a", .success = "#000000", .warning = "#ffffff", .muted = "#ff5555" };
}
pub fn palette_3_16_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_16();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_16_sgr_accent() []const u8 { return "38;2;128;96;224"; }
pub fn palette_3_16_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_16_sgr_accent(), text});
}

pub fn palette_3_17() Palette {
    return .{ .name = "theme_3_17", .bg = "#8be9fd", .fg = "#6272a4", .accent = "#44475a", .error_c = "#000000", .success = "#ffffff", .warning = "#ff5555", .muted = "#50fa7b" };
}
pub fn palette_3_17_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_17();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_17_sgr_accent() []const u8 { return "38;2;168;166;78"; }
pub fn palette_3_17_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_17_sgr_accent(), text});
}

pub fn palette_3_18() Palette {
    return .{ .name = "theme_3_18", .bg = "#6272a4", .fg = "#44475a", .accent = "#000000", .error_c = "#ffffff", .success = "#ff5555", .warning = "#50fa7b", .muted = "#f1fa8c" };
}
pub fn palette_3_18_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_18();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_18_sgr_accent() []const u8 { return "38;2;208;236;188"; }
pub fn palette_3_18_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_18_sgr_accent(), text});
}

pub fn palette_3_19() Palette {
    return .{ .name = "theme_3_19", .bg = "#44475a", .fg = "#000000", .accent = "#ffffff", .error_c = "#ff5555", .success = "#50fa7b", .warning = "#f1fa8c", .muted = "#bd93f9" };
}
pub fn palette_3_19_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_19();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_19_sgr_accent() []const u8 { return "38;2;248;50;42"; }
pub fn palette_3_19_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_19_sgr_accent(), text});
}

pub fn palette_3_20() Palette {
    return .{ .name = "theme_3_20", .bg = "#000000", .fg = "#ffffff", .accent = "#ff5555", .error_c = "#50fa7b", .success = "#f1fa8c", .warning = "#bd93f9", .muted = "#ff79c6" };
}
pub fn palette_3_20_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_20();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_20_sgr_accent() []const u8 { return "38;2;32;120;152"; }
pub fn palette_3_20_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_20_sgr_accent(), text});
}

pub fn palette_3_21() Palette {
    return .{ .name = "theme_3_21", .bg = "#ffffff", .fg = "#ff5555", .accent = "#50fa7b", .error_c = "#f1fa8c", .success = "#bd93f9", .warning = "#ff79c6", .muted = "#8be9fd" };
}
pub fn palette_3_21_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_21();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_21_sgr_accent() []const u8 { return "38;2;72;190;6"; }
pub fn palette_3_21_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_21_sgr_accent(), text});
}

pub fn palette_3_22() Palette {
    return .{ .name = "theme_3_22", .bg = "#ff5555", .fg = "#50fa7b", .accent = "#f1fa8c", .error_c = "#bd93f9", .success = "#ff79c6", .warning = "#8be9fd", .muted = "#6272a4" };
}
pub fn palette_3_22_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_22();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_22_sgr_accent() []const u8 { return "38;2;112;4;116"; }
pub fn palette_3_22_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_22_sgr_accent(), text});
}

pub fn palette_3_23() Palette {
    return .{ .name = "theme_3_23", .bg = "#50fa7b", .fg = "#f1fa8c", .accent = "#bd93f9", .error_c = "#ff79c6", .success = "#8be9fd", .warning = "#6272a4", .muted = "#44475a" };
}
pub fn palette_3_23_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_23();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_23_sgr_accent() []const u8 { return "38;2;152;74;226"; }
pub fn palette_3_23_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_23_sgr_accent(), text});
}

pub fn palette_3_24() Palette {
    return .{ .name = "theme_3_24", .bg = "#f1fa8c", .fg = "#bd93f9", .accent = "#ff79c6", .error_c = "#8be9fd", .success = "#6272a4", .warning = "#44475a", .muted = "#000000" };
}
pub fn palette_3_24_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_24();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_24_sgr_accent() []const u8 { return "38;2;192;144;80"; }
pub fn palette_3_24_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_24_sgr_accent(), text});
}

pub fn palette_3_25() Palette {
    return .{ .name = "theme_3_25", .bg = "#bd93f9", .fg = "#ff79c6", .accent = "#8be9fd", .error_c = "#6272a4", .success = "#44475a", .warning = "#000000", .muted = "#ffffff" };
}
pub fn palette_3_25_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_25();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_25_sgr_accent() []const u8 { return "38;2;232;214;190"; }
pub fn palette_3_25_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_25_sgr_accent(), text});
}

pub fn palette_3_26() Palette {
    return .{ .name = "theme_3_26", .bg = "#ff79c6", .fg = "#8be9fd", .accent = "#6272a4", .error_c = "#44475a", .success = "#000000", .warning = "#ffffff", .muted = "#ff5555" };
}
pub fn palette_3_26_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_26();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_26_sgr_accent() []const u8 { return "38;2;16;28;44"; }
pub fn palette_3_26_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_26_sgr_accent(), text});
}

pub fn palette_3_27() Palette {
    return .{ .name = "theme_3_27", .bg = "#8be9fd", .fg = "#6272a4", .accent = "#44475a", .error_c = "#000000", .success = "#ffffff", .warning = "#ff5555", .muted = "#50fa7b" };
}
pub fn palette_3_27_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_27();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_27_sgr_accent() []const u8 { return "38;2;56;98;154"; }
pub fn palette_3_27_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_27_sgr_accent(), text});
}

pub fn palette_3_28() Palette {
    return .{ .name = "theme_3_28", .bg = "#6272a4", .fg = "#44475a", .accent = "#000000", .error_c = "#ffffff", .success = "#ff5555", .warning = "#50fa7b", .muted = "#f1fa8c" };
}
pub fn palette_3_28_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_28();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_28_sgr_accent() []const u8 { return "38;2;96;168;8"; }
pub fn palette_3_28_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_28_sgr_accent(), text});
}

pub fn palette_3_29() Palette {
    return .{ .name = "theme_3_29", .bg = "#44475a", .fg = "#000000", .accent = "#ffffff", .error_c = "#ff5555", .success = "#50fa7b", .warning = "#f1fa8c", .muted = "#bd93f9" };
}
pub fn palette_3_29_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_29();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_29_sgr_accent() []const u8 { return "38;2;136;238;118"; }
pub fn palette_3_29_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_29_sgr_accent(), text});
}

pub fn palette_3_30() Palette {
    return .{ .name = "theme_3_30", .bg = "#000000", .fg = "#ffffff", .accent = "#ff5555", .error_c = "#50fa7b", .success = "#f1fa8c", .warning = "#bd93f9", .muted = "#ff79c6" };
}
pub fn palette_3_30_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_30();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_30_sgr_accent() []const u8 { return "38;2;176;52;228"; }
pub fn palette_3_30_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_30_sgr_accent(), text});
}

pub fn palette_3_31() Palette {
    return .{ .name = "theme_3_31", .bg = "#ffffff", .fg = "#ff5555", .accent = "#50fa7b", .error_c = "#f1fa8c", .success = "#bd93f9", .warning = "#ff79c6", .muted = "#8be9fd" };
}
pub fn palette_3_31_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_31();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_31_sgr_accent() []const u8 { return "38;2;216;122;82"; }
pub fn palette_3_31_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_31_sgr_accent(), text});
}

pub fn palette_3_32() Palette {
    return .{ .name = "theme_3_32", .bg = "#ff5555", .fg = "#50fa7b", .accent = "#f1fa8c", .error_c = "#bd93f9", .success = "#ff79c6", .warning = "#8be9fd", .muted = "#6272a4" };
}
pub fn palette_3_32_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_32();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_32_sgr_accent() []const u8 { return "38;2;0;192;192"; }
pub fn palette_3_32_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_32_sgr_accent(), text});
}

pub fn palette_3_33() Palette {
    return .{ .name = "theme_3_33", .bg = "#50fa7b", .fg = "#f1fa8c", .accent = "#bd93f9", .error_c = "#ff79c6", .success = "#8be9fd", .warning = "#6272a4", .muted = "#44475a" };
}
pub fn palette_3_33_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_33();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_33_sgr_accent() []const u8 { return "38;2;40;6;46"; }
pub fn palette_3_33_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_33_sgr_accent(), text});
}

pub fn palette_3_34() Palette {
    return .{ .name = "theme_3_34", .bg = "#f1fa8c", .fg = "#bd93f9", .accent = "#ff79c6", .error_c = "#8be9fd", .success = "#6272a4", .warning = "#44475a", .muted = "#000000" };
}
pub fn palette_3_34_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_34();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_34_sgr_accent() []const u8 { return "38;2;80;76;156"; }
pub fn palette_3_34_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_34_sgr_accent(), text});
}

pub fn palette_3_35() Palette {
    return .{ .name = "theme_3_35", .bg = "#bd93f9", .fg = "#ff79c6", .accent = "#8be9fd", .error_c = "#6272a4", .success = "#44475a", .warning = "#000000", .muted = "#ffffff" };
}
pub fn palette_3_35_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_35();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_35_sgr_accent() []const u8 { return "38;2;120;146;10"; }
pub fn palette_3_35_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_35_sgr_accent(), text});
}

pub fn palette_3_36() Palette {
    return .{ .name = "theme_3_36", .bg = "#ff79c6", .fg = "#8be9fd", .accent = "#6272a4", .error_c = "#44475a", .success = "#000000", .warning = "#ffffff", .muted = "#ff5555" };
}
pub fn palette_3_36_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_36();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_36_sgr_accent() []const u8 { return "38;2;160;216;120"; }
pub fn palette_3_36_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_36_sgr_accent(), text});
}

pub fn palette_3_37() Palette {
    return .{ .name = "theme_3_37", .bg = "#8be9fd", .fg = "#6272a4", .accent = "#44475a", .error_c = "#000000", .success = "#ffffff", .warning = "#ff5555", .muted = "#50fa7b" };
}
pub fn palette_3_37_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_37();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_37_sgr_accent() []const u8 { return "38;2;200;30;230"; }
pub fn palette_3_37_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_37_sgr_accent(), text});
}

pub fn palette_3_38() Palette {
    return .{ .name = "theme_3_38", .bg = "#6272a4", .fg = "#44475a", .accent = "#000000", .error_c = "#ffffff", .success = "#ff5555", .warning = "#50fa7b", .muted = "#f1fa8c" };
}
pub fn palette_3_38_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_38();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_38_sgr_accent() []const u8 { return "38;2;240;100;84"; }
pub fn palette_3_38_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_38_sgr_accent(), text});
}

pub fn palette_3_39() Palette {
    return .{ .name = "theme_3_39", .bg = "#44475a", .fg = "#000000", .accent = "#ffffff", .error_c = "#ff5555", .success = "#50fa7b", .warning = "#f1fa8c", .muted = "#bd93f9" };
}
pub fn palette_3_39_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_39();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_39_sgr_accent() []const u8 { return "38;2;24;170;194"; }
pub fn palette_3_39_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_39_sgr_accent(), text});
}

pub fn palette_3_40() Palette {
    return .{ .name = "theme_3_40", .bg = "#000000", .fg = "#ffffff", .accent = "#ff5555", .error_c = "#50fa7b", .success = "#f1fa8c", .warning = "#bd93f9", .muted = "#ff79c6" };
}
pub fn palette_3_40_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_40();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_40_sgr_accent() []const u8 { return "38;2;64;240;48"; }
pub fn palette_3_40_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_40_sgr_accent(), text});
}

pub fn palette_3_41() Palette {
    return .{ .name = "theme_3_41", .bg = "#ffffff", .fg = "#ff5555", .accent = "#50fa7b", .error_c = "#f1fa8c", .success = "#bd93f9", .warning = "#ff79c6", .muted = "#8be9fd" };
}
pub fn palette_3_41_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_41();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_41_sgr_accent() []const u8 { return "38;2;104;54;158"; }
pub fn palette_3_41_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_41_sgr_accent(), text});
}

pub fn palette_3_42() Palette {
    return .{ .name = "theme_3_42", .bg = "#ff5555", .fg = "#50fa7b", .accent = "#f1fa8c", .error_c = "#bd93f9", .success = "#ff79c6", .warning = "#8be9fd", .muted = "#6272a4" };
}
pub fn palette_3_42_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_42();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_42_sgr_accent() []const u8 { return "38;2;144;124;12"; }
pub fn palette_3_42_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_42_sgr_accent(), text});
}

pub fn palette_3_43() Palette {
    return .{ .name = "theme_3_43", .bg = "#50fa7b", .fg = "#f1fa8c", .accent = "#bd93f9", .error_c = "#ff79c6", .success = "#8be9fd", .warning = "#6272a4", .muted = "#44475a" };
}
pub fn palette_3_43_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_43();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_43_sgr_accent() []const u8 { return "38;2;184;194;122"; }
pub fn palette_3_43_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_43_sgr_accent(), text});
}

pub fn palette_3_44() Palette {
    return .{ .name = "theme_3_44", .bg = "#f1fa8c", .fg = "#bd93f9", .accent = "#ff79c6", .error_c = "#8be9fd", .success = "#6272a4", .warning = "#44475a", .muted = "#000000" };
}
pub fn palette_3_44_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_44();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_44_sgr_accent() []const u8 { return "38;2;224;8;232"; }
pub fn palette_3_44_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_44_sgr_accent(), text});
}

pub fn palette_3_45() Palette {
    return .{ .name = "theme_3_45", .bg = "#bd93f9", .fg = "#ff79c6", .accent = "#8be9fd", .error_c = "#6272a4", .success = "#44475a", .warning = "#000000", .muted = "#ffffff" };
}
pub fn palette_3_45_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_45();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_45_sgr_accent() []const u8 { return "38;2;8;78;86"; }
pub fn palette_3_45_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_45_sgr_accent(), text});
}

pub fn palette_3_46() Palette {
    return .{ .name = "theme_3_46", .bg = "#ff79c6", .fg = "#8be9fd", .accent = "#6272a4", .error_c = "#44475a", .success = "#000000", .warning = "#ffffff", .muted = "#ff5555" };
}
pub fn palette_3_46_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_46();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_46_sgr_accent() []const u8 { return "38;2;48;148;196"; }
pub fn palette_3_46_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_46_sgr_accent(), text});
}

pub fn palette_3_47() Palette {
    return .{ .name = "theme_3_47", .bg = "#8be9fd", .fg = "#6272a4", .accent = "#44475a", .error_c = "#000000", .success = "#ffffff", .warning = "#ff5555", .muted = "#50fa7b" };
}
pub fn palette_3_47_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_47();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_47_sgr_accent() []const u8 { return "38;2;88;218;50"; }
pub fn palette_3_47_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_47_sgr_accent(), text});
}

pub fn palette_3_48() Palette {
    return .{ .name = "theme_3_48", .bg = "#6272a4", .fg = "#44475a", .accent = "#000000", .error_c = "#ffffff", .success = "#ff5555", .warning = "#50fa7b", .muted = "#f1fa8c" };
}
pub fn palette_3_48_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_48();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_48_sgr_accent() []const u8 { return "38;2;128;32;160"; }
pub fn palette_3_48_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_48_sgr_accent(), text});
}

pub fn palette_3_49() Palette {
    return .{ .name = "theme_3_49", .bg = "#44475a", .fg = "#000000", .accent = "#ffffff", .error_c = "#ff5555", .success = "#50fa7b", .warning = "#f1fa8c", .muted = "#bd93f9" };
}
pub fn palette_3_49_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_3_49();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_3_49_sgr_accent() []const u8 { return "38;2;168;102;14"; }
pub fn palette_3_49_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_3_49_sgr_accent(), text});
}

test "themes shard 3" {
    try std.testing.expectEqualStrings("theme_3_0", palette_3_0().name);
    const gpa = std.testing.allocator;
    const css = try palette_3_0_css(gpa);
    defer gpa.free(css);
    try std.testing.expect(css.len > 0);
}

