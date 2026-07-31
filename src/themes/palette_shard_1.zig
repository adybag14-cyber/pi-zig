//! Generated theme palettes shard 1.
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

pub fn palette_1_0() Palette {
    return .{ .name = "theme_1_0", .bg = "#000000", .fg = "#ffffff", .accent = "#ff5555", .error_c = "#50fa7b", .success = "#f1fa8c", .warning = "#bd93f9", .muted = "#ff79c6" };
}
pub fn palette_1_0_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_0();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_0_sgr_accent() []const u8 { return "38;2;0;0;0"; }
pub fn palette_1_0_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_0_sgr_accent(), text});
}

pub fn palette_1_1() Palette {
    return .{ .name = "theme_1_1", .bg = "#ffffff", .fg = "#ff5555", .accent = "#50fa7b", .error_c = "#f1fa8c", .success = "#bd93f9", .warning = "#ff79c6", .muted = "#8be9fd" };
}
pub fn palette_1_1_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_1();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_1_sgr_accent() []const u8 { return "38;2;40;70;110"; }
pub fn palette_1_1_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_1_sgr_accent(), text});
}

pub fn palette_1_2() Palette {
    return .{ .name = "theme_1_2", .bg = "#ff5555", .fg = "#50fa7b", .accent = "#f1fa8c", .error_c = "#bd93f9", .success = "#ff79c6", .warning = "#8be9fd", .muted = "#6272a4" };
}
pub fn palette_1_2_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_2();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_2_sgr_accent() []const u8 { return "38;2;80;140;220"; }
pub fn palette_1_2_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_2_sgr_accent(), text});
}

pub fn palette_1_3() Palette {
    return .{ .name = "theme_1_3", .bg = "#50fa7b", .fg = "#f1fa8c", .accent = "#bd93f9", .error_c = "#ff79c6", .success = "#8be9fd", .warning = "#6272a4", .muted = "#44475a" };
}
pub fn palette_1_3_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_3();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_3_sgr_accent() []const u8 { return "38;2;120;210;74"; }
pub fn palette_1_3_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_3_sgr_accent(), text});
}

pub fn palette_1_4() Palette {
    return .{ .name = "theme_1_4", .bg = "#f1fa8c", .fg = "#bd93f9", .accent = "#ff79c6", .error_c = "#8be9fd", .success = "#6272a4", .warning = "#44475a", .muted = "#000000" };
}
pub fn palette_1_4_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_4();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_4_sgr_accent() []const u8 { return "38;2;160;24;184"; }
pub fn palette_1_4_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_4_sgr_accent(), text});
}

pub fn palette_1_5() Palette {
    return .{ .name = "theme_1_5", .bg = "#bd93f9", .fg = "#ff79c6", .accent = "#8be9fd", .error_c = "#6272a4", .success = "#44475a", .warning = "#000000", .muted = "#ffffff" };
}
pub fn palette_1_5_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_5();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_5_sgr_accent() []const u8 { return "38;2;200;94;38"; }
pub fn palette_1_5_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_5_sgr_accent(), text});
}

pub fn palette_1_6() Palette {
    return .{ .name = "theme_1_6", .bg = "#ff79c6", .fg = "#8be9fd", .accent = "#6272a4", .error_c = "#44475a", .success = "#000000", .warning = "#ffffff", .muted = "#ff5555" };
}
pub fn palette_1_6_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_6();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_6_sgr_accent() []const u8 { return "38;2;240;164;148"; }
pub fn palette_1_6_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_6_sgr_accent(), text});
}

pub fn palette_1_7() Palette {
    return .{ .name = "theme_1_7", .bg = "#8be9fd", .fg = "#6272a4", .accent = "#44475a", .error_c = "#000000", .success = "#ffffff", .warning = "#ff5555", .muted = "#50fa7b" };
}
pub fn palette_1_7_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_7();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_7_sgr_accent() []const u8 { return "38;2;24;234;2"; }
pub fn palette_1_7_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_7_sgr_accent(), text});
}

pub fn palette_1_8() Palette {
    return .{ .name = "theme_1_8", .bg = "#6272a4", .fg = "#44475a", .accent = "#000000", .error_c = "#ffffff", .success = "#ff5555", .warning = "#50fa7b", .muted = "#f1fa8c" };
}
pub fn palette_1_8_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_8();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_8_sgr_accent() []const u8 { return "38;2;64;48;112"; }
pub fn palette_1_8_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_8_sgr_accent(), text});
}

pub fn palette_1_9() Palette {
    return .{ .name = "theme_1_9", .bg = "#44475a", .fg = "#000000", .accent = "#ffffff", .error_c = "#ff5555", .success = "#50fa7b", .warning = "#f1fa8c", .muted = "#bd93f9" };
}
pub fn palette_1_9_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_9();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_9_sgr_accent() []const u8 { return "38;2;104;118;222"; }
pub fn palette_1_9_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_9_sgr_accent(), text});
}

pub fn palette_1_10() Palette {
    return .{ .name = "theme_1_10", .bg = "#000000", .fg = "#ffffff", .accent = "#ff5555", .error_c = "#50fa7b", .success = "#f1fa8c", .warning = "#bd93f9", .muted = "#ff79c6" };
}
pub fn palette_1_10_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_10();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_10_sgr_accent() []const u8 { return "38;2;144;188;76"; }
pub fn palette_1_10_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_10_sgr_accent(), text});
}

pub fn palette_1_11() Palette {
    return .{ .name = "theme_1_11", .bg = "#ffffff", .fg = "#ff5555", .accent = "#50fa7b", .error_c = "#f1fa8c", .success = "#bd93f9", .warning = "#ff79c6", .muted = "#8be9fd" };
}
pub fn palette_1_11_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_11();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_11_sgr_accent() []const u8 { return "38;2;184;2;186"; }
pub fn palette_1_11_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_11_sgr_accent(), text});
}

pub fn palette_1_12() Palette {
    return .{ .name = "theme_1_12", .bg = "#ff5555", .fg = "#50fa7b", .accent = "#f1fa8c", .error_c = "#bd93f9", .success = "#ff79c6", .warning = "#8be9fd", .muted = "#6272a4" };
}
pub fn palette_1_12_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_12();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_12_sgr_accent() []const u8 { return "38;2;224;72;40"; }
pub fn palette_1_12_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_12_sgr_accent(), text});
}

pub fn palette_1_13() Palette {
    return .{ .name = "theme_1_13", .bg = "#50fa7b", .fg = "#f1fa8c", .accent = "#bd93f9", .error_c = "#ff79c6", .success = "#8be9fd", .warning = "#6272a4", .muted = "#44475a" };
}
pub fn palette_1_13_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_13();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_13_sgr_accent() []const u8 { return "38;2;8;142;150"; }
pub fn palette_1_13_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_13_sgr_accent(), text});
}

pub fn palette_1_14() Palette {
    return .{ .name = "theme_1_14", .bg = "#f1fa8c", .fg = "#bd93f9", .accent = "#ff79c6", .error_c = "#8be9fd", .success = "#6272a4", .warning = "#44475a", .muted = "#000000" };
}
pub fn palette_1_14_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_14();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_14_sgr_accent() []const u8 { return "38;2;48;212;4"; }
pub fn palette_1_14_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_14_sgr_accent(), text});
}

pub fn palette_1_15() Palette {
    return .{ .name = "theme_1_15", .bg = "#bd93f9", .fg = "#ff79c6", .accent = "#8be9fd", .error_c = "#6272a4", .success = "#44475a", .warning = "#000000", .muted = "#ffffff" };
}
pub fn palette_1_15_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_15();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_15_sgr_accent() []const u8 { return "38;2;88;26;114"; }
pub fn palette_1_15_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_15_sgr_accent(), text});
}

pub fn palette_1_16() Palette {
    return .{ .name = "theme_1_16", .bg = "#ff79c6", .fg = "#8be9fd", .accent = "#6272a4", .error_c = "#44475a", .success = "#000000", .warning = "#ffffff", .muted = "#ff5555" };
}
pub fn palette_1_16_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_16();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_16_sgr_accent() []const u8 { return "38;2;128;96;224"; }
pub fn palette_1_16_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_16_sgr_accent(), text});
}

pub fn palette_1_17() Palette {
    return .{ .name = "theme_1_17", .bg = "#8be9fd", .fg = "#6272a4", .accent = "#44475a", .error_c = "#000000", .success = "#ffffff", .warning = "#ff5555", .muted = "#50fa7b" };
}
pub fn palette_1_17_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_17();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_17_sgr_accent() []const u8 { return "38;2;168;166;78"; }
pub fn palette_1_17_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_17_sgr_accent(), text});
}

pub fn palette_1_18() Palette {
    return .{ .name = "theme_1_18", .bg = "#6272a4", .fg = "#44475a", .accent = "#000000", .error_c = "#ffffff", .success = "#ff5555", .warning = "#50fa7b", .muted = "#f1fa8c" };
}
pub fn palette_1_18_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_18();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_18_sgr_accent() []const u8 { return "38;2;208;236;188"; }
pub fn palette_1_18_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_18_sgr_accent(), text});
}

pub fn palette_1_19() Palette {
    return .{ .name = "theme_1_19", .bg = "#44475a", .fg = "#000000", .accent = "#ffffff", .error_c = "#ff5555", .success = "#50fa7b", .warning = "#f1fa8c", .muted = "#bd93f9" };
}
pub fn palette_1_19_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_19();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_19_sgr_accent() []const u8 { return "38;2;248;50;42"; }
pub fn palette_1_19_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_19_sgr_accent(), text});
}

pub fn palette_1_20() Palette {
    return .{ .name = "theme_1_20", .bg = "#000000", .fg = "#ffffff", .accent = "#ff5555", .error_c = "#50fa7b", .success = "#f1fa8c", .warning = "#bd93f9", .muted = "#ff79c6" };
}
pub fn palette_1_20_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_20();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_20_sgr_accent() []const u8 { return "38;2;32;120;152"; }
pub fn palette_1_20_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_20_sgr_accent(), text});
}

pub fn palette_1_21() Palette {
    return .{ .name = "theme_1_21", .bg = "#ffffff", .fg = "#ff5555", .accent = "#50fa7b", .error_c = "#f1fa8c", .success = "#bd93f9", .warning = "#ff79c6", .muted = "#8be9fd" };
}
pub fn palette_1_21_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_21();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_21_sgr_accent() []const u8 { return "38;2;72;190;6"; }
pub fn palette_1_21_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_21_sgr_accent(), text});
}

pub fn palette_1_22() Palette {
    return .{ .name = "theme_1_22", .bg = "#ff5555", .fg = "#50fa7b", .accent = "#f1fa8c", .error_c = "#bd93f9", .success = "#ff79c6", .warning = "#8be9fd", .muted = "#6272a4" };
}
pub fn palette_1_22_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_22();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_22_sgr_accent() []const u8 { return "38;2;112;4;116"; }
pub fn palette_1_22_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_22_sgr_accent(), text});
}

pub fn palette_1_23() Palette {
    return .{ .name = "theme_1_23", .bg = "#50fa7b", .fg = "#f1fa8c", .accent = "#bd93f9", .error_c = "#ff79c6", .success = "#8be9fd", .warning = "#6272a4", .muted = "#44475a" };
}
pub fn palette_1_23_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_23();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_23_sgr_accent() []const u8 { return "38;2;152;74;226"; }
pub fn palette_1_23_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_23_sgr_accent(), text});
}

pub fn palette_1_24() Palette {
    return .{ .name = "theme_1_24", .bg = "#f1fa8c", .fg = "#bd93f9", .accent = "#ff79c6", .error_c = "#8be9fd", .success = "#6272a4", .warning = "#44475a", .muted = "#000000" };
}
pub fn palette_1_24_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_24();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_24_sgr_accent() []const u8 { return "38;2;192;144;80"; }
pub fn palette_1_24_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_24_sgr_accent(), text});
}

pub fn palette_1_25() Palette {
    return .{ .name = "theme_1_25", .bg = "#bd93f9", .fg = "#ff79c6", .accent = "#8be9fd", .error_c = "#6272a4", .success = "#44475a", .warning = "#000000", .muted = "#ffffff" };
}
pub fn palette_1_25_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_25();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_25_sgr_accent() []const u8 { return "38;2;232;214;190"; }
pub fn palette_1_25_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_25_sgr_accent(), text});
}

pub fn palette_1_26() Palette {
    return .{ .name = "theme_1_26", .bg = "#ff79c6", .fg = "#8be9fd", .accent = "#6272a4", .error_c = "#44475a", .success = "#000000", .warning = "#ffffff", .muted = "#ff5555" };
}
pub fn palette_1_26_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_26();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_26_sgr_accent() []const u8 { return "38;2;16;28;44"; }
pub fn palette_1_26_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_26_sgr_accent(), text});
}

pub fn palette_1_27() Palette {
    return .{ .name = "theme_1_27", .bg = "#8be9fd", .fg = "#6272a4", .accent = "#44475a", .error_c = "#000000", .success = "#ffffff", .warning = "#ff5555", .muted = "#50fa7b" };
}
pub fn palette_1_27_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_27();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_27_sgr_accent() []const u8 { return "38;2;56;98;154"; }
pub fn palette_1_27_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_27_sgr_accent(), text});
}

pub fn palette_1_28() Palette {
    return .{ .name = "theme_1_28", .bg = "#6272a4", .fg = "#44475a", .accent = "#000000", .error_c = "#ffffff", .success = "#ff5555", .warning = "#50fa7b", .muted = "#f1fa8c" };
}
pub fn palette_1_28_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_28();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_28_sgr_accent() []const u8 { return "38;2;96;168;8"; }
pub fn palette_1_28_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_28_sgr_accent(), text});
}

pub fn palette_1_29() Palette {
    return .{ .name = "theme_1_29", .bg = "#44475a", .fg = "#000000", .accent = "#ffffff", .error_c = "#ff5555", .success = "#50fa7b", .warning = "#f1fa8c", .muted = "#bd93f9" };
}
pub fn palette_1_29_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_29();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_29_sgr_accent() []const u8 { return "38;2;136;238;118"; }
pub fn palette_1_29_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_29_sgr_accent(), text});
}

pub fn palette_1_30() Palette {
    return .{ .name = "theme_1_30", .bg = "#000000", .fg = "#ffffff", .accent = "#ff5555", .error_c = "#50fa7b", .success = "#f1fa8c", .warning = "#bd93f9", .muted = "#ff79c6" };
}
pub fn palette_1_30_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_30();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_30_sgr_accent() []const u8 { return "38;2;176;52;228"; }
pub fn palette_1_30_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_30_sgr_accent(), text});
}

pub fn palette_1_31() Palette {
    return .{ .name = "theme_1_31", .bg = "#ffffff", .fg = "#ff5555", .accent = "#50fa7b", .error_c = "#f1fa8c", .success = "#bd93f9", .warning = "#ff79c6", .muted = "#8be9fd" };
}
pub fn palette_1_31_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_31();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_31_sgr_accent() []const u8 { return "38;2;216;122;82"; }
pub fn palette_1_31_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_31_sgr_accent(), text});
}

pub fn palette_1_32() Palette {
    return .{ .name = "theme_1_32", .bg = "#ff5555", .fg = "#50fa7b", .accent = "#f1fa8c", .error_c = "#bd93f9", .success = "#ff79c6", .warning = "#8be9fd", .muted = "#6272a4" };
}
pub fn palette_1_32_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_32();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_32_sgr_accent() []const u8 { return "38;2;0;192;192"; }
pub fn palette_1_32_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_32_sgr_accent(), text});
}

pub fn palette_1_33() Palette {
    return .{ .name = "theme_1_33", .bg = "#50fa7b", .fg = "#f1fa8c", .accent = "#bd93f9", .error_c = "#ff79c6", .success = "#8be9fd", .warning = "#6272a4", .muted = "#44475a" };
}
pub fn palette_1_33_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_33();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_33_sgr_accent() []const u8 { return "38;2;40;6;46"; }
pub fn palette_1_33_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_33_sgr_accent(), text});
}

pub fn palette_1_34() Palette {
    return .{ .name = "theme_1_34", .bg = "#f1fa8c", .fg = "#bd93f9", .accent = "#ff79c6", .error_c = "#8be9fd", .success = "#6272a4", .warning = "#44475a", .muted = "#000000" };
}
pub fn palette_1_34_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_34();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_34_sgr_accent() []const u8 { return "38;2;80;76;156"; }
pub fn palette_1_34_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_34_sgr_accent(), text});
}

pub fn palette_1_35() Palette {
    return .{ .name = "theme_1_35", .bg = "#bd93f9", .fg = "#ff79c6", .accent = "#8be9fd", .error_c = "#6272a4", .success = "#44475a", .warning = "#000000", .muted = "#ffffff" };
}
pub fn palette_1_35_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_35();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_35_sgr_accent() []const u8 { return "38;2;120;146;10"; }
pub fn palette_1_35_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_35_sgr_accent(), text});
}

pub fn palette_1_36() Palette {
    return .{ .name = "theme_1_36", .bg = "#ff79c6", .fg = "#8be9fd", .accent = "#6272a4", .error_c = "#44475a", .success = "#000000", .warning = "#ffffff", .muted = "#ff5555" };
}
pub fn palette_1_36_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_36();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_36_sgr_accent() []const u8 { return "38;2;160;216;120"; }
pub fn palette_1_36_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_36_sgr_accent(), text});
}

pub fn palette_1_37() Palette {
    return .{ .name = "theme_1_37", .bg = "#8be9fd", .fg = "#6272a4", .accent = "#44475a", .error_c = "#000000", .success = "#ffffff", .warning = "#ff5555", .muted = "#50fa7b" };
}
pub fn palette_1_37_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_37();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_37_sgr_accent() []const u8 { return "38;2;200;30;230"; }
pub fn palette_1_37_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_37_sgr_accent(), text});
}

pub fn palette_1_38() Palette {
    return .{ .name = "theme_1_38", .bg = "#6272a4", .fg = "#44475a", .accent = "#000000", .error_c = "#ffffff", .success = "#ff5555", .warning = "#50fa7b", .muted = "#f1fa8c" };
}
pub fn palette_1_38_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_38();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_38_sgr_accent() []const u8 { return "38;2;240;100;84"; }
pub fn palette_1_38_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_38_sgr_accent(), text});
}

pub fn palette_1_39() Palette {
    return .{ .name = "theme_1_39", .bg = "#44475a", .fg = "#000000", .accent = "#ffffff", .error_c = "#ff5555", .success = "#50fa7b", .warning = "#f1fa8c", .muted = "#bd93f9" };
}
pub fn palette_1_39_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_39();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_39_sgr_accent() []const u8 { return "38;2;24;170;194"; }
pub fn palette_1_39_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_39_sgr_accent(), text});
}

pub fn palette_1_40() Palette {
    return .{ .name = "theme_1_40", .bg = "#000000", .fg = "#ffffff", .accent = "#ff5555", .error_c = "#50fa7b", .success = "#f1fa8c", .warning = "#bd93f9", .muted = "#ff79c6" };
}
pub fn palette_1_40_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_40();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_40_sgr_accent() []const u8 { return "38;2;64;240;48"; }
pub fn palette_1_40_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_40_sgr_accent(), text});
}

pub fn palette_1_41() Palette {
    return .{ .name = "theme_1_41", .bg = "#ffffff", .fg = "#ff5555", .accent = "#50fa7b", .error_c = "#f1fa8c", .success = "#bd93f9", .warning = "#ff79c6", .muted = "#8be9fd" };
}
pub fn palette_1_41_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_41();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_41_sgr_accent() []const u8 { return "38;2;104;54;158"; }
pub fn palette_1_41_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_41_sgr_accent(), text});
}

pub fn palette_1_42() Palette {
    return .{ .name = "theme_1_42", .bg = "#ff5555", .fg = "#50fa7b", .accent = "#f1fa8c", .error_c = "#bd93f9", .success = "#ff79c6", .warning = "#8be9fd", .muted = "#6272a4" };
}
pub fn palette_1_42_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_42();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_42_sgr_accent() []const u8 { return "38;2;144;124;12"; }
pub fn palette_1_42_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_42_sgr_accent(), text});
}

pub fn palette_1_43() Palette {
    return .{ .name = "theme_1_43", .bg = "#50fa7b", .fg = "#f1fa8c", .accent = "#bd93f9", .error_c = "#ff79c6", .success = "#8be9fd", .warning = "#6272a4", .muted = "#44475a" };
}
pub fn palette_1_43_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_43();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_43_sgr_accent() []const u8 { return "38;2;184;194;122"; }
pub fn palette_1_43_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_43_sgr_accent(), text});
}

pub fn palette_1_44() Palette {
    return .{ .name = "theme_1_44", .bg = "#f1fa8c", .fg = "#bd93f9", .accent = "#ff79c6", .error_c = "#8be9fd", .success = "#6272a4", .warning = "#44475a", .muted = "#000000" };
}
pub fn palette_1_44_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_44();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_44_sgr_accent() []const u8 { return "38;2;224;8;232"; }
pub fn palette_1_44_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_44_sgr_accent(), text});
}

pub fn palette_1_45() Palette {
    return .{ .name = "theme_1_45", .bg = "#bd93f9", .fg = "#ff79c6", .accent = "#8be9fd", .error_c = "#6272a4", .success = "#44475a", .warning = "#000000", .muted = "#ffffff" };
}
pub fn palette_1_45_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_45();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_45_sgr_accent() []const u8 { return "38;2;8;78;86"; }
pub fn palette_1_45_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_45_sgr_accent(), text});
}

pub fn palette_1_46() Palette {
    return .{ .name = "theme_1_46", .bg = "#ff79c6", .fg = "#8be9fd", .accent = "#6272a4", .error_c = "#44475a", .success = "#000000", .warning = "#ffffff", .muted = "#ff5555" };
}
pub fn palette_1_46_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_46();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_46_sgr_accent() []const u8 { return "38;2;48;148;196"; }
pub fn palette_1_46_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_46_sgr_accent(), text});
}

pub fn palette_1_47() Palette {
    return .{ .name = "theme_1_47", .bg = "#8be9fd", .fg = "#6272a4", .accent = "#44475a", .error_c = "#000000", .success = "#ffffff", .warning = "#ff5555", .muted = "#50fa7b" };
}
pub fn palette_1_47_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_47();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_47_sgr_accent() []const u8 { return "38;2;88;218;50"; }
pub fn palette_1_47_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_47_sgr_accent(), text});
}

pub fn palette_1_48() Palette {
    return .{ .name = "theme_1_48", .bg = "#6272a4", .fg = "#44475a", .accent = "#000000", .error_c = "#ffffff", .success = "#ff5555", .warning = "#50fa7b", .muted = "#f1fa8c" };
}
pub fn palette_1_48_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_48();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_48_sgr_accent() []const u8 { return "38;2;128;32;160"; }
pub fn palette_1_48_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_48_sgr_accent(), text});
}

pub fn palette_1_49() Palette {
    return .{ .name = "theme_1_49", .bg = "#44475a", .fg = "#000000", .accent = "#ffffff", .error_c = "#ff5555", .success = "#50fa7b", .warning = "#f1fa8c", .muted = "#bd93f9" };
}
pub fn palette_1_49_css(gpa: std.mem.Allocator) ![]u8 {
    const p = palette_1_49();
    return try std.fmt.allocPrint(gpa, ":root {{ --bg: {s}; --fg: {s}; --accent: {s}; }} /* {s} */", .{ p.bg, p.fg, p.accent, p.name });
}
pub fn palette_1_49_sgr_accent() []const u8 { return "38;2;168;102;14"; }
pub fn palette_1_49_wrap(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{palette_1_49_sgr_accent(), text});
}

test "themes shard 1" {
    try std.testing.expectEqualStrings("theme_1_0", palette_1_0().name);
    const gpa = std.testing.allocator;
    const css = try palette_1_0_css(gpa);
    defer gpa.free(css);
    try std.testing.expect(css.len > 0);
}

