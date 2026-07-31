//! Generated theme palettes shard 2.
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

pub fn palette_2_0() Palette {
    return .{ .name = "theme_2_0", .bg = "#000000", .fg = "#ffffff", .accent = "#ff5555", .error_c = "#50fa7b", .success = "#f1fa8c", .warning = "#bd93f9", .muted = "#ff79c6" };
}
pub fn palette_2_0_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_0();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_0_sgr_accent() []const u8 { return "38;2;0;0;0"; }
pub fn palette_2_0_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_0_sgr_accent(), text});
}

pub fn palette_2_1() Palette {
    return .{ .name = "theme_2_1", .bg = "#ffffff", .fg = "#ff5555", .accent = "#50fa7b", .error_c = "#f1fa8c", .success = "#bd93f9", .warning = "#ff79c6", .muted = "#8be9fd" };
}
pub fn palette_2_1_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_1();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_1_sgr_accent() []const u8 { return "38;2;40;70;110"; }
pub fn palette_2_1_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_1_sgr_accent(), text});
}

pub fn palette_2_2() Palette {
    return .{ .name = "theme_2_2", .bg = "#ff5555", .fg = "#50fa7b", .accent = "#f1fa8c", .error_c = "#bd93f9", .success = "#ff79c6", .warning = "#8be9fd", .muted = "#6272a4" };
}
pub fn palette_2_2_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_2();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_2_sgr_accent() []const u8 { return "38;2;80;140;220"; }
pub fn palette_2_2_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_2_sgr_accent(), text});
}

pub fn palette_2_3() Palette {
    return .{ .name = "theme_2_3", .bg = "#50fa7b", .fg = "#f1fa8c", .accent = "#bd93f9", .error_c = "#ff79c6", .success = "#8be9fd", .warning = "#6272a4", .muted = "#44475a" };
}
pub fn palette_2_3_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_3();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_3_sgr_accent() []const u8 { return "38;2;120;210;74"; }
pub fn palette_2_3_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_3_sgr_accent(), text});
}

pub fn palette_2_4() Palette {
    return .{ .name = "theme_2_4", .bg = "#f1fa8c", .fg = "#bd93f9", .accent = "#ff79c6", .error_c = "#8be9fd", .success = "#6272a4", .warning = "#44475a", .muted = "#000000" };
}
pub fn palette_2_4_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_4();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_4_sgr_accent() []const u8 { return "38;2;160;24;184"; }
pub fn palette_2_4_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_4_sgr_accent(), text});
}

pub fn palette_2_5() Palette {
    return .{ .name = "theme_2_5", .bg = "#bd93f9", .fg = "#ff79c6", .accent = "#8be9fd", .error_c = "#6272a4", .success = "#44475a", .warning = "#000000", .muted = "#ffffff" };
}
pub fn palette_2_5_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_5();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_5_sgr_accent() []const u8 { return "38;2;200;94;38"; }
pub fn palette_2_5_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_5_sgr_accent(), text});
}

pub fn palette_2_6() Palette {
    return .{ .name = "theme_2_6", .bg = "#ff79c6", .fg = "#8be9fd", .accent = "#6272a4", .error_c = "#44475a", .success = "#000000", .warning = "#ffffff", .muted = "#ff5555" };
}
pub fn palette_2_6_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_6();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_6_sgr_accent() []const u8 { return "38;2;240;164;148"; }
pub fn palette_2_6_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_6_sgr_accent(), text});
}

pub fn palette_2_7() Palette {
    return .{ .name = "theme_2_7", .bg = "#8be9fd", .fg = "#6272a4", .accent = "#44475a", .error_c = "#000000", .success = "#ffffff", .warning = "#ff5555", .muted = "#50fa7b" };
}
pub fn palette_2_7_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_7();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_7_sgr_accent() []const u8 { return "38;2;24;234;2"; }
pub fn palette_2_7_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_7_sgr_accent(), text});
}

pub fn palette_2_8() Palette {
    return .{ .name = "theme_2_8", .bg = "#6272a4", .fg = "#44475a", .accent = "#000000", .error_c = "#ffffff", .success = "#ff5555", .warning = "#50fa7b", .muted = "#f1fa8c" };
}
pub fn palette_2_8_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_8();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_8_sgr_accent() []const u8 { return "38;2;64;48;112"; }
pub fn palette_2_8_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_8_sgr_accent(), text});
}

pub fn palette_2_9() Palette {
    return .{ .name = "theme_2_9", .bg = "#44475a", .fg = "#000000", .accent = "#ffffff", .error_c = "#ff5555", .success = "#50fa7b", .warning = "#f1fa8c", .muted = "#bd93f9" };
}
pub fn palette_2_9_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_9();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_9_sgr_accent() []const u8 { return "38;2;104;118;222"; }
pub fn palette_2_9_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_9_sgr_accent(), text});
}

pub fn palette_2_10() Palette {
    return .{ .name = "theme_2_10", .bg = "#000000", .fg = "#ffffff", .accent = "#ff5555", .error_c = "#50fa7b", .success = "#f1fa8c", .warning = "#bd93f9", .muted = "#ff79c6" };
}
pub fn palette_2_10_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_10();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_10_sgr_accent() []const u8 { return "38;2;144;188;76"; }
pub fn palette_2_10_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_10_sgr_accent(), text});
}

pub fn palette_2_11() Palette {
    return .{ .name = "theme_2_11", .bg = "#ffffff", .fg = "#ff5555", .accent = "#50fa7b", .error_c = "#f1fa8c", .success = "#bd93f9", .warning = "#ff79c6", .muted = "#8be9fd" };
}
pub fn palette_2_11_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_11();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_11_sgr_accent() []const u8 { return "38;2;184;2;186"; }
pub fn palette_2_11_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_11_sgr_accent(), text});
}

pub fn palette_2_12() Palette {
    return .{ .name = "theme_2_12", .bg = "#ff5555", .fg = "#50fa7b", .accent = "#f1fa8c", .error_c = "#bd93f9", .success = "#ff79c6", .warning = "#8be9fd", .muted = "#6272a4" };
}
pub fn palette_2_12_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_12();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_12_sgr_accent() []const u8 { return "38;2;224;72;40"; }
pub fn palette_2_12_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_12_sgr_accent(), text});
}

pub fn palette_2_13() Palette {
    return .{ .name = "theme_2_13", .bg = "#50fa7b", .fg = "#f1fa8c", .accent = "#bd93f9", .error_c = "#ff79c6", .success = "#8be9fd", .warning = "#6272a4", .muted = "#44475a" };
}
pub fn palette_2_13_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_13();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_13_sgr_accent() []const u8 { return "38;2;8;142;150"; }
pub fn palette_2_13_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_13_sgr_accent(), text});
}

pub fn palette_2_14() Palette {
    return .{ .name = "theme_2_14", .bg = "#f1fa8c", .fg = "#bd93f9", .accent = "#ff79c6", .error_c = "#8be9fd", .success = "#6272a4", .warning = "#44475a", .muted = "#000000" };
}
pub fn palette_2_14_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_14();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_14_sgr_accent() []const u8 { return "38;2;48;212;4"; }
pub fn palette_2_14_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_14_sgr_accent(), text});
}

pub fn palette_2_15() Palette {
    return .{ .name = "theme_2_15", .bg = "#bd93f9", .fg = "#ff79c6", .accent = "#8be9fd", .error_c = "#6272a4", .success = "#44475a", .warning = "#000000", .muted = "#ffffff" };
}
pub fn palette_2_15_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_15();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_15_sgr_accent() []const u8 { return "38;2;88;26;114"; }
pub fn palette_2_15_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_15_sgr_accent(), text});
}

pub fn palette_2_16() Palette {
    return .{ .name = "theme_2_16", .bg = "#ff79c6", .fg = "#8be9fd", .accent = "#6272a4", .error_c = "#44475a", .success = "#000000", .warning = "#ffffff", .muted = "#ff5555" };
}
pub fn palette_2_16_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_16();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_16_sgr_accent() []const u8 { return "38;2;128;96;224"; }
pub fn palette_2_16_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_16_sgr_accent(), text});
}

pub fn palette_2_17() Palette {
    return .{ .name = "theme_2_17", .bg = "#8be9fd", .fg = "#6272a4", .accent = "#44475a", .error_c = "#000000", .success = "#ffffff", .warning = "#ff5555", .muted = "#50fa7b" };
}
pub fn palette_2_17_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_17();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_17_sgr_accent() []const u8 { return "38;2;168;166;78"; }
pub fn palette_2_17_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_17_sgr_accent(), text});
}

pub fn palette_2_18() Palette {
    return .{ .name = "theme_2_18", .bg = "#6272a4", .fg = "#44475a", .accent = "#000000", .error_c = "#ffffff", .success = "#ff5555", .warning = "#50fa7b", .muted = "#f1fa8c" };
}
pub fn palette_2_18_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_18();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_18_sgr_accent() []const u8 { return "38;2;208;236;188"; }
pub fn palette_2_18_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_18_sgr_accent(), text});
}

pub fn palette_2_19() Palette {
    return .{ .name = "theme_2_19", .bg = "#44475a", .fg = "#000000", .accent = "#ffffff", .error_c = "#ff5555", .success = "#50fa7b", .warning = "#f1fa8c", .muted = "#bd93f9" };
}
pub fn palette_2_19_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_19();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_19_sgr_accent() []const u8 { return "38;2;248;50;42"; }
pub fn palette_2_19_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_19_sgr_accent(), text});
}

pub fn palette_2_20() Palette {
    return .{ .name = "theme_2_20", .bg = "#000000", .fg = "#ffffff", .accent = "#ff5555", .error_c = "#50fa7b", .success = "#f1fa8c", .warning = "#bd93f9", .muted = "#ff79c6" };
}
pub fn palette_2_20_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_20();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_20_sgr_accent() []const u8 { return "38;2;32;120;152"; }
pub fn palette_2_20_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_20_sgr_accent(), text});
}

pub fn palette_2_21() Palette {
    return .{ .name = "theme_2_21", .bg = "#ffffff", .fg = "#ff5555", .accent = "#50fa7b", .error_c = "#f1fa8c", .success = "#bd93f9", .warning = "#ff79c6", .muted = "#8be9fd" };
}
pub fn palette_2_21_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_21();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_21_sgr_accent() []const u8 { return "38;2;72;190;6"; }
pub fn palette_2_21_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_21_sgr_accent(), text});
}

pub fn palette_2_22() Palette {
    return .{ .name = "theme_2_22", .bg = "#ff5555", .fg = "#50fa7b", .accent = "#f1fa8c", .error_c = "#bd93f9", .success = "#ff79c6", .warning = "#8be9fd", .muted = "#6272a4" };
}
pub fn palette_2_22_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_22();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_22_sgr_accent() []const u8 { return "38;2;112;4;116"; }
pub fn palette_2_22_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_22_sgr_accent(), text});
}

pub fn palette_2_23() Palette {
    return .{ .name = "theme_2_23", .bg = "#50fa7b", .fg = "#f1fa8c", .accent = "#bd93f9", .error_c = "#ff79c6", .success = "#8be9fd", .warning = "#6272a4", .muted = "#44475a" };
}
pub fn palette_2_23_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_23();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_23_sgr_accent() []const u8 { return "38;2;152;74;226"; }
pub fn palette_2_23_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_23_sgr_accent(), text});
}

pub fn palette_2_24() Palette {
    return .{ .name = "theme_2_24", .bg = "#f1fa8c", .fg = "#bd93f9", .accent = "#ff79c6", .error_c = "#8be9fd", .success = "#6272a4", .warning = "#44475a", .muted = "#000000" };
}
pub fn palette_2_24_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_24();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_24_sgr_accent() []const u8 { return "38;2;192;144;80"; }
pub fn palette_2_24_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_24_sgr_accent(), text});
}

pub fn palette_2_25() Palette {
    return .{ .name = "theme_2_25", .bg = "#bd93f9", .fg = "#ff79c6", .accent = "#8be9fd", .error_c = "#6272a4", .success = "#44475a", .warning = "#000000", .muted = "#ffffff" };
}
pub fn palette_2_25_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_25();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_25_sgr_accent() []const u8 { return "38;2;232;214;190"; }
pub fn palette_2_25_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_25_sgr_accent(), text});
}

pub fn palette_2_26() Palette {
    return .{ .name = "theme_2_26", .bg = "#ff79c6", .fg = "#8be9fd", .accent = "#6272a4", .error_c = "#44475a", .success = "#000000", .warning = "#ffffff", .muted = "#ff5555" };
}
pub fn palette_2_26_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_26();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_26_sgr_accent() []const u8 { return "38;2;16;28;44"; }
pub fn palette_2_26_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_26_sgr_accent(), text});
}

pub fn palette_2_27() Palette {
    return .{ .name = "theme_2_27", .bg = "#8be9fd", .fg = "#6272a4", .accent = "#44475a", .error_c = "#000000", .success = "#ffffff", .warning = "#ff5555", .muted = "#50fa7b" };
}
pub fn palette_2_27_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_27();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_27_sgr_accent() []const u8 { return "38;2;56;98;154"; }
pub fn palette_2_27_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_27_sgr_accent(), text});
}

pub fn palette_2_28() Palette {
    return .{ .name = "theme_2_28", .bg = "#6272a4", .fg = "#44475a", .accent = "#000000", .error_c = "#ffffff", .success = "#ff5555", .warning = "#50fa7b", .muted = "#f1fa8c" };
}
pub fn palette_2_28_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_28();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_28_sgr_accent() []const u8 { return "38;2;96;168;8"; }
pub fn palette_2_28_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_28_sgr_accent(), text});
}

pub fn palette_2_29() Palette {
    return .{ .name = "theme_2_29", .bg = "#44475a", .fg = "#000000", .accent = "#ffffff", .error_c = "#ff5555", .success = "#50fa7b", .warning = "#f1fa8c", .muted = "#bd93f9" };
}
pub fn palette_2_29_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_29();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_29_sgr_accent() []const u8 { return "38;2;136;238;118"; }
pub fn palette_2_29_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_29_sgr_accent(), text});
}

pub fn palette_2_30() Palette {
    return .{ .name = "theme_2_30", .bg = "#000000", .fg = "#ffffff", .accent = "#ff5555", .error_c = "#50fa7b", .success = "#f1fa8c", .warning = "#bd93f9", .muted = "#ff79c6" };
}
pub fn palette_2_30_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_30();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_30_sgr_accent() []const u8 { return "38;2;176;52;228"; }
pub fn palette_2_30_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_30_sgr_accent(), text});
}

pub fn palette_2_31() Palette {
    return .{ .name = "theme_2_31", .bg = "#ffffff", .fg = "#ff5555", .accent = "#50fa7b", .error_c = "#f1fa8c", .success = "#bd93f9", .warning = "#ff79c6", .muted = "#8be9fd" };
}
pub fn palette_2_31_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_31();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_31_sgr_accent() []const u8 { return "38;2;216;122;82"; }
pub fn palette_2_31_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_31_sgr_accent(), text});
}

pub fn palette_2_32() Palette {
    return .{ .name = "theme_2_32", .bg = "#ff5555", .fg = "#50fa7b", .accent = "#f1fa8c", .error_c = "#bd93f9", .success = "#ff79c6", .warning = "#8be9fd", .muted = "#6272a4" };
}
pub fn palette_2_32_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_32();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_32_sgr_accent() []const u8 { return "38;2;0;192;192"; }
pub fn palette_2_32_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_32_sgr_accent(), text});
}

pub fn palette_2_33() Palette {
    return .{ .name = "theme_2_33", .bg = "#50fa7b", .fg = "#f1fa8c", .accent = "#bd93f9", .error_c = "#ff79c6", .success = "#8be9fd", .warning = "#6272a4", .muted = "#44475a" };
}
pub fn palette_2_33_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_33();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_33_sgr_accent() []const u8 { return "38;2;40;6;46"; }
pub fn palette_2_33_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_33_sgr_accent(), text});
}

pub fn palette_2_34() Palette {
    return .{ .name = "theme_2_34", .bg = "#f1fa8c", .fg = "#bd93f9", .accent = "#ff79c6", .error_c = "#8be9fd", .success = "#6272a4", .warning = "#44475a", .muted = "#000000" };
}
pub fn palette_2_34_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_34();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_34_sgr_accent() []const u8 { return "38;2;80;76;156"; }
pub fn palette_2_34_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_34_sgr_accent(), text});
}

pub fn palette_2_35() Palette {
    return .{ .name = "theme_2_35", .bg = "#bd93f9", .fg = "#ff79c6", .accent = "#8be9fd", .error_c = "#6272a4", .success = "#44475a", .warning = "#000000", .muted = "#ffffff" };
}
pub fn palette_2_35_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_35();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_35_sgr_accent() []const u8 { return "38;2;120;146;10"; }
pub fn palette_2_35_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_35_sgr_accent(), text});
}

pub fn palette_2_36() Palette {
    return .{ .name = "theme_2_36", .bg = "#ff79c6", .fg = "#8be9fd", .accent = "#6272a4", .error_c = "#44475a", .success = "#000000", .warning = "#ffffff", .muted = "#ff5555" };
}
pub fn palette_2_36_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_36();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_36_sgr_accent() []const u8 { return "38;2;160;216;120"; }
pub fn palette_2_36_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_36_sgr_accent(), text});
}

pub fn palette_2_37() Palette {
    return .{ .name = "theme_2_37", .bg = "#8be9fd", .fg = "#6272a4", .accent = "#44475a", .error_c = "#000000", .success = "#ffffff", .warning = "#ff5555", .muted = "#50fa7b" };
}
pub fn palette_2_37_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_37();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_37_sgr_accent() []const u8 { return "38;2;200;30;230"; }
pub fn palette_2_37_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_37_sgr_accent(), text});
}

pub fn palette_2_38() Palette {
    return .{ .name = "theme_2_38", .bg = "#6272a4", .fg = "#44475a", .accent = "#000000", .error_c = "#ffffff", .success = "#ff5555", .warning = "#50fa7b", .muted = "#f1fa8c" };
}
pub fn palette_2_38_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_38();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_38_sgr_accent() []const u8 { return "38;2;240;100;84"; }
pub fn palette_2_38_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_38_sgr_accent(), text});
}

pub fn palette_2_39() Palette {
    return .{ .name = "theme_2_39", .bg = "#44475a", .fg = "#000000", .accent = "#ffffff", .error_c = "#ff5555", .success = "#50fa7b", .warning = "#f1fa8c", .muted = "#bd93f9" };
}
pub fn palette_2_39_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_39();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_39_sgr_accent() []const u8 { return "38;2;24;170;194"; }
pub fn palette_2_39_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_39_sgr_accent(), text});
}

pub fn palette_2_40() Palette {
    return .{ .name = "theme_2_40", .bg = "#000000", .fg = "#ffffff", .accent = "#ff5555", .error_c = "#50fa7b", .success = "#f1fa8c", .warning = "#bd93f9", .muted = "#ff79c6" };
}
pub fn palette_2_40_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_40();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_40_sgr_accent() []const u8 { return "38;2;64;240;48"; }
pub fn palette_2_40_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_40_sgr_accent(), text});
}

pub fn palette_2_41() Palette {
    return .{ .name = "theme_2_41", .bg = "#ffffff", .fg = "#ff5555", .accent = "#50fa7b", .error_c = "#f1fa8c", .success = "#bd93f9", .warning = "#ff79c6", .muted = "#8be9fd" };
}
pub fn palette_2_41_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_41();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_41_sgr_accent() []const u8 { return "38;2;104;54;158"; }
pub fn palette_2_41_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_41_sgr_accent(), text});
}

pub fn palette_2_42() Palette {
    return .{ .name = "theme_2_42", .bg = "#ff5555", .fg = "#50fa7b", .accent = "#f1fa8c", .error_c = "#bd93f9", .success = "#ff79c6", .warning = "#8be9fd", .muted = "#6272a4" };
}
pub fn palette_2_42_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_42();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_42_sgr_accent() []const u8 { return "38;2;144;124;12"; }
pub fn palette_2_42_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_42_sgr_accent(), text});
}

pub fn palette_2_43() Palette {
    return .{ .name = "theme_2_43", .bg = "#50fa7b", .fg = "#f1fa8c", .accent = "#bd93f9", .error_c = "#ff79c6", .success = "#8be9fd", .warning = "#6272a4", .muted = "#44475a" };
}
pub fn palette_2_43_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_43();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_43_sgr_accent() []const u8 { return "38;2;184;194;122"; }
pub fn palette_2_43_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_43_sgr_accent(), text});
}

pub fn palette_2_44() Palette {
    return .{ .name = "theme_2_44", .bg = "#f1fa8c", .fg = "#bd93f9", .accent = "#ff79c6", .error_c = "#8be9fd", .success = "#6272a4", .warning = "#44475a", .muted = "#000000" };
}
pub fn palette_2_44_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_44();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_44_sgr_accent() []const u8 { return "38;2;224;8;232"; }
pub fn palette_2_44_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_44_sgr_accent(), text});
}

pub fn palette_2_45() Palette {
    return .{ .name = "theme_2_45", .bg = "#bd93f9", .fg = "#ff79c6", .accent = "#8be9fd", .error_c = "#6272a4", .success = "#44475a", .warning = "#000000", .muted = "#ffffff" };
}
pub fn palette_2_45_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_45();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_45_sgr_accent() []const u8 { return "38;2;8;78;86"; }
pub fn palette_2_45_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_45_sgr_accent(), text});
}

pub fn palette_2_46() Palette {
    return .{ .name = "theme_2_46", .bg = "#ff79c6", .fg = "#8be9fd", .accent = "#6272a4", .error_c = "#44475a", .success = "#000000", .warning = "#ffffff", .muted = "#ff5555" };
}
pub fn palette_2_46_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_46();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_46_sgr_accent() []const u8 { return "38;2;48;148;196"; }
pub fn palette_2_46_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_46_sgr_accent(), text});
}

pub fn palette_2_47() Palette {
    return .{ .name = "theme_2_47", .bg = "#8be9fd", .fg = "#6272a4", .accent = "#44475a", .error_c = "#000000", .success = "#ffffff", .warning = "#ff5555", .muted = "#50fa7b" };
}
pub fn palette_2_47_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_47();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_47_sgr_accent() []const u8 { return "38;2;88;218;50"; }
pub fn palette_2_47_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_47_sgr_accent(), text});
}

pub fn palette_2_48() Palette {
    return .{ .name = "theme_2_48", .bg = "#6272a4", .fg = "#44475a", .accent = "#000000", .error_c = "#ffffff", .success = "#ff5555", .warning = "#50fa7b", .muted = "#f1fa8c" };
}
pub fn palette_2_48_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_48();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_48_sgr_accent() []const u8 { return "38;2;128;32;160"; }
pub fn palette_2_48_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_48_sgr_accent(), text});
}

pub fn palette_2_49() Palette {
    return .{ .name = "theme_2_49", .bg = "#44475a", .fg = "#000000", .accent = "#ffffff", .error_c = "#ff5555", .success = "#50fa7b", .warning = "#f1fa8c", .muted = "#bd93f9" };
}
pub fn palette_2_49_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_2_49();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_2_49_sgr_accent() []const u8 { return "38;2;168;102;14"; }
pub fn palette_2_49_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_2_49_sgr_accent(), text});
}

test "themes shard 2" {
    try std.testing.expectEqualStrings("theme_2_0", palette_2_0().name);
    const gpa = std.testing.allocator;
    const css = try palette_2_0_css(gpa);
    defer gpa.free(css);
    try std.testing.expect(css.len > 0);
}

