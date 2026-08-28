//! Theme JSON parsing and ANSI color resolution.
//!
//! The original Pi theme schema stores colors under `colors` and permits values
//! to be true-color hex strings, 256-color indices, or references into `vars`.
//! This native subset owns every parsed string and resolves the core colors used
//! by the Zig terminal renderer. The legacy flat color keys remain accepted for
//! checkpoint compatibility.
const std = @import("std");
const Io = std.Io;

pub const Theme = struct {
    name: []const u8 = "default",
    accent: []const u8 = "cyan",
    error_color: []const u8 = "red",
    success_color: []const u8 = "green",
    muted: []const u8 = "brightBlack",
    /// ANSI SGR parameter strings, without CSI or trailing `m`.
    accent_sgr: []const u8 = "36",
    error_sgr: []const u8 = "31",
    success_sgr: []const u8 = "32",
    muted_sgr: []const u8 = "90",
    owned: bool = false,

    pub fn deinit(self: *Theme, gpa: std.mem.Allocator) void {
        if (self.owned) {
            gpa.free(self.name);
            gpa.free(self.accent);
            gpa.free(self.error_color);
            gpa.free(self.success_color);
            gpa.free(self.muted);
            gpa.free(self.accent_sgr);
            gpa.free(self.error_sgr);
            gpa.free(self.success_sgr);
            gpa.free(self.muted_sgr);
        }
        self.* = undefined;
    }
};

const ResolvedColor = struct {
    label: []u8,
    sgr: []u8,

    fn deinit(self: *ResolvedColor, gpa: std.mem.Allocator) void {
        gpa.free(self.label);
        gpa.free(self.sgr);
        self.* = undefined;
    }
};

fn namedColorSgr(name: []const u8) ?[]const u8 {
    const names = [_]struct { []const u8, []const u8 }{
        .{ "black", "30" },       .{ "red", "31" },
        .{ "green", "32" },       .{ "yellow", "33" },
        .{ "blue", "34" },        .{ "magenta", "35" },
        .{ "cyan", "36" },        .{ "white", "37" },
        .{ "gray", "90" },        .{ "grey", "90" },
        .{ "brightBlack", "90" }, .{ "brightRed", "91" },
        .{ "brightGreen", "92" }, .{ "brightYellow", "93" },
        .{ "brightBlue", "94" },  .{ "brightMagenta", "95" },
        .{ "brightCyan", "96" },  .{ "brightWhite", "97" },
        .{ "default", "39" },
    };
    for (names) |entry| {
        if (std.ascii.eqlIgnoreCase(name, entry[0])) return entry[1];
    }
    return null;
}

fn parseHexByte(raw: []const u8) !u8 {
    if (raw.len != 2) return error.InvalidThemeColor;
    return std.fmt.parseInt(u8, raw, 16) catch return error.InvalidThemeColor;
}

fn colorFromScalar(gpa: std.mem.Allocator, value: std.json.Value) !ResolvedColor {
    switch (value) {
        .integer => |number| {
            if (number < 0 or number > 255) return error.InvalidThemeColor;
            return .{
                .label = try std.fmt.allocPrint(gpa, "{d}", .{number}),
                .sgr = try std.fmt.allocPrint(gpa, "38;5;{d}", .{number}),
            };
        },
        .string => |raw| {
            if (raw.len == 0) {
                return .{ .label = try gpa.dupe(u8, raw), .sgr = try gpa.dupe(u8, "39") };
            }
            if (raw.len == 7 and raw[0] == '#') {
                const r = try parseHexByte(raw[1..3]);
                const g = try parseHexByte(raw[3..5]);
                const b = try parseHexByte(raw[5..7]);
                return .{
                    .label = try gpa.dupe(u8, raw),
                    .sgr = try std.fmt.allocPrint(gpa, "38;2;{d};{d};{d}", .{ r, g, b }),
                };
            }
            if (namedColorSgr(raw)) |sgr| {
                return .{ .label = try gpa.dupe(u8, raw), .sgr = try gpa.dupe(u8, sgr) };
            }
            return error.UnresolvedThemeVariable;
        },
        else => return error.InvalidThemeColor,
    }
}

fn resolveColor(
    gpa: std.mem.Allocator,
    value: std.json.Value,
    vars: ?*const std.json.ObjectMap,
    stack: *std.ArrayList([]const u8),
) !ResolvedColor {
    if (value != .string) return colorFromScalar(gpa, value);
    const raw = value.string;
    if (raw.len == 0 or raw[0] == '#' or namedColorSgr(raw) != null) return colorFromScalar(gpa, value);
    const vars_map = vars orelse return error.UnresolvedThemeVariable;
    for (stack.items) |name| {
        if (std.mem.eql(u8, name, raw)) return error.CircularThemeVariable;
    }
    if (stack.items.len >= 64) return error.CircularThemeVariable;
    const referenced = vars_map.get(raw) orelse return error.UnresolvedThemeVariable;
    try stack.append(gpa, raw);
    defer _ = stack.pop();
    return resolveColor(gpa, referenced, vars, stack);
}

fn valueFor(root: *const std.json.ObjectMap, colors: ?*const std.json.ObjectMap, key: []const u8) ?std.json.Value {
    if (colors) |map| {
        if (map.get(key)) |value| return value;
    }
    return root.get(key);
}

fn defaultColor(gpa: std.mem.Allocator, label: []const u8, sgr: []const u8) !ResolvedColor {
    return .{ .label = try gpa.dupe(u8, label), .sgr = try gpa.dupe(u8, sgr) };
}

fn parseCoreColor(
    gpa: std.mem.Allocator,
    root: *const std.json.ObjectMap,
    colors: ?*const std.json.ObjectMap,
    vars: ?*const std.json.ObjectMap,
    key: []const u8,
    fallback_label: []const u8,
    fallback_sgr: []const u8,
) !ResolvedColor {
    const value = valueFor(root, colors, key) orelse return defaultColor(gpa, fallback_label, fallback_sgr);
    var stack: std.ArrayList([]const u8) = .empty;
    defer stack.deinit(gpa);
    return resolveColor(gpa, value, vars, &stack);
}

pub fn parse(gpa: std.mem.Allocator, raw: []const u8) !Theme {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return error.InvalidThemeJson;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidThemeJson;
    const root = &parsed.value.object;

    const colors: ?*const std.json.ObjectMap = if (root.get("colors")) |value| blk: {
        if (value != .object) return error.InvalidThemeJson;
        break :blk &value.object;
    } else null;
    const vars: ?*const std.json.ObjectMap = if (root.get("vars")) |value| blk: {
        if (value != .object) return error.InvalidThemeJson;
        break :blk &value.object;
    } else null;

    const raw_name = if (root.get("name")) |value| blk: {
        if (value != .string or value.string.len == 0) return error.InvalidThemeName;
        break :blk value.string;
    } else "default";

    var accent = try parseCoreColor(gpa, root, colors, vars, "accent", "cyan", "36");
    errdefer accent.deinit(gpa);
    var error_color = try parseCoreColor(gpa, root, colors, vars, "error", "red", "31");
    errdefer error_color.deinit(gpa);
    var success = try parseCoreColor(gpa, root, colors, vars, "success", "green", "32");
    errdefer success.deinit(gpa);
    var muted = try parseCoreColor(gpa, root, colors, vars, "muted", "brightBlack", "90");
    errdefer muted.deinit(gpa);

    return .{
        .name = try gpa.dupe(u8, raw_name),
        .accent = accent.label,
        .error_color = error_color.label,
        .success_color = success.label,
        .muted = muted.label,
        .accent_sgr = accent.sgr,
        .error_sgr = error_color.sgr,
        .success_sgr = success.sgr,
        .muted_sgr = muted.sgr,
        .owned = true,
    };
}

pub fn loadFile(gpa: std.mem.Allocator, io: Io, path: []const u8) !Theme {
    const raw = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024)) catch |err| switch (err) {
        error.StreamTooLong => return error.ThemeTooLarge,
        else => return err,
    };
    defer gpa.free(raw);
    return parse(gpa, raw);
}

pub fn wrap(sgr: []const u8, text: []const u8, gpa: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{ sgr, text });
}

test "parse legacy flat theme owns all strings" {
    const gpa = std.testing.allocator;
    var t = try parse(gpa,
        \\{"name":"dracula","accent":"magenta","error":"red","success":"green","muted":"gray"}
    );
    defer t.deinit(gpa);
    try std.testing.expectEqualStrings("dracula", t.name);
    try std.testing.expectEqualStrings("35", t.accent_sgr);
    try std.testing.expectEqualStrings("90", t.muted_sgr);
}

test "parse original nested theme resolves variables truecolor and 256 color" {
    const gpa = std.testing.allocator;
    var t = try parse(gpa,
        \\{
        \\  "name":"native",
        \\  "vars":{"primary":"#12aBcD","quiet":244},
        \\  "colors":{"accent":"primary","error":"#ff0000","success":34,"muted":"quiet"}
        \\}
    );
    defer t.deinit(gpa);
    try std.testing.expectEqualStrings("38;2;18;171;205", t.accent_sgr);
    try std.testing.expectEqualStrings("38;2;255;0;0", t.error_sgr);
    try std.testing.expectEqualStrings("38;5;34", t.success_sgr);
    try std.testing.expectEqualStrings("38;5;244", t.muted_sgr);
}

test "theme parser rejects circular variables" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.CircularThemeVariable, parse(gpa,
        \\{"name":"bad","vars":{"a":"b","b":"a"},"colors":{"accent":"a"}}
    ));
}

test "theme parser rejects dangling variables and malformed hex" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.UnresolvedThemeVariable, parse(gpa,
        \\{"name":"bad","colors":{"accent":"missing"}}
    ));
    try std.testing.expectError(error.InvalidThemeColor, parse(gpa,
        \\{"name":"bad","colors":{"accent":"#gg0000"}}
    ));
}
