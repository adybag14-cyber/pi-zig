//! Owned native frontend palette projected from the genuine cached ThemeState.
const std = @import("std");
const colors = @import("colors.zig");
const system = @import("../themes/system_theme.zig");
pub const Palette = struct {
    gpa: std.mem.Allocator,
    values: std.StringHashMapUnmanaged([]u8) = .empty,
    pub fn deinit(self: *Palette) void {
        var entries = self.values.iterator();
        while (entries.next()) |entry| {
            self.gpa.free(entry.key_ptr.*);
            self.gpa.free(entry.value_ptr.*);
        }
        self.values.deinit(self.gpa);
    }
    fn put(self: *Palette, name: []const u8, ansi: []u8) !void {
        errdefer self.gpa.free(ansi);
        const key = try self.gpa.dupe(u8, name);
        errdefer self.gpa.free(key);
        try self.values.put(self.gpa, key, ansi);
    }
    pub fn get(self: *const Palette, token: []const u8) []const u8 {
        return self.values.get(token) orelse "";
    }
    pub fn style(self: *const Palette, token: []const u8, text: []const u8) ![]u8 {
        const prefix = self.get(token);
        if (prefix.len == 0) return self.gpa.dupe(u8, text);
        return std.fmt.allocPrint(self.gpa, "{s}{s}\x1b[39m{s}", .{ prefix, text, if (std.mem.startsWith(u8, prefix, "\x1b[2m")) "\x1b[22m" else "" });
    }
    pub fn fromState(gpa: std.mem.Allocator, raw: []const u8) !Palette {
        var self: Palette = .{ .gpa = gpa };
        errdefer self.deinit();
        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidNativeThemePalette;
        const state = &parsed.value.object;
        const raw_mode = state.get("colorMode") orelse return error.InvalidNativeThemePalette;
        const mode = if (raw_mode == .string) std.meta.stringToEnum(colors.ColorMode, raw_mode.string) orelse return error.InvalidNativeThemePalette else return error.InvalidNativeThemePalette;
        const resource = state.get("resource") orelse .null;
        if (resource == .object) {
            const tokens = resource.object.get("colors") orelse return error.InvalidNativeThemePalette;
            if (tokens != .object) return error.InvalidNativeThemePalette;
            const variables = resource.object.get("vars") orelse std.json.Value{ .object = .empty };
            if (variables != .object) return error.InvalidNativeThemePalette;
            var entries = tokens.object.iterator();
            while (entries.next()) |entry| try self.put(entry.key_ptr.*, try resourceAnsi(gpa, entry.value_ptr.*, &variables.object, mode, 0));
            var descriptors = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("../themes/fixtures/theme-tokens-original-6fb.json"), .{});
            defer descriptors.deinit();
            var fallback = descriptors.value.object.iterator();
            while (fallback.next()) |entry| {
                if (self.values.contains(entry.key_ptr.*)) continue;
                const base = entry.value_ptr.object.get("fallback") orelse continue;
                if (base != .string) continue;
                if (self.values.get(base.string)) |ansi| try self.put(entry.key_ptr.*, try gpa.dupe(u8, ansi));
            }
        } else {
            const terminal = state.get("terminalColors") orelse std.json.Value{ .object = .empty };
            if (terminal != .object) return error.InvalidNativeThemePalette;
            const pending = state.get("terminalColorsPending") orelse std.json.Value{ .bool = false };
            var input: system.Input = .{ .saturation = if (pending == .bool and pending.bool) 0 else 1 };
            input.foreground = try readRgb(terminal.object.get("foreground"));
            input.background = try readRgb(terminal.object.get("background"));
            const hint = state.get("terminalColorScheme") orelse .null;
            if (hint == .string) input.appearance_hint = std.meta.stringToEnum(system.Appearance, hint.string);
            var palette: [16]colors.Rgb = undefined;
            if (terminal.object.get("palette")) |rows| if (rows == .array and rows.array.items.len == 16) {
                for (&palette, rows.array.items) |*target, row| target.* = (try readRgb(row)) orelse return error.InvalidNativeThemePalette;
                input.palette = &palette;
            };
            const generated = system.generate(input);
            for (system.recipe.tokens, 0..) |token, index| {
                const ansi = switch (generated.values[index]) {
                    .default => try gpa.dupe(u8, "\x1b[39m"),
                    .indexed => |value| try colors.colorAnsi(gpa, .{ .indexed = value }, mode, false),
                    .rgb => |value| try colors.colorAnsi(gpa, .{ .rgb = value }, mode, false),
                };
                if (generated.dim[index]) {
                    defer gpa.free(ansi);
                    try self.put(token.name, try std.fmt.allocPrint(gpa, "\x1b[2m{s}", .{ansi}));
                } else try self.put(token.name, ansi);
            }
        }
        return self;
    }
};
fn readRgb(raw: ?std.json.Value) !?colors.Rgb {
    const value = raw orelse return null;
    if (value == .null) return null;
    if (value != .object) return error.InvalidNativeThemePalette;
    var result: [3]f64 = undefined;
    inline for (.{ "r", "g", "b" }, 0..) |key, index| {
        const channel = value.object.get(key) orelse return error.InvalidNativeThemePalette;
        result[index] = switch (channel) {
            .float => channel.float,
            .integer => @floatFromInt(channel.integer),
            else => return error.InvalidNativeThemePalette,
        };
    }
    return (try colors.rgbColor(result[0], result[1], result[2])).rgb;
}
fn resourceAnsi(gpa: std.mem.Allocator, raw: std.json.Value, vars: *const std.json.ObjectMap, mode: colors.ColorMode, depth: usize) ![]u8 {
    if (depth >= 64) return error.InvalidNativeThemePalette;
    return switch (raw) {
        .integer => try colors.colorAnsi(gpa, try colors.indexedColor(@floatFromInt(raw.integer)), mode, false),
        .float => try colors.colorAnsi(gpa, try colors.indexedColor(raw.float), mode, false),
        .string => |value| if (value.len == 0) gpa.dupe(u8, "\x1b[39m") else if (vars.get(value)) |next| resourceAnsi(gpa, next, vars, mode, depth + 1) else colors.colorAnsi(gpa, try colors.parseColor(value), mode, false),
        else => error.InvalidNativeThemePalette,
    };
}
