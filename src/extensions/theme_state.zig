//! Cached host presentation state. Serialization performs no terminal I/O.
const std = @import("std");
const colors = @import("../tui/colors.zig");
const system = @import("../themes/system_theme.zig");
pub const Rgb = colors.Rgb;
pub const ColorMode = colors.ColorMode;
pub const Appearance = system.Appearance;
pub const TerminalColors = struct {
    foreground: ?Rgb = null,
    background: ?Rgb = null,
    /// Empty means no complete palette was reported; only all sixteen slots bind.
    palette: []const Rgb = &.{},
};
pub const State = struct {
    /// Increment on actual report, selection, scheme or capability changes.
    /// Repeated snapshot reads keep this revision and object identities stable.
    revision: u64,
    color_mode: ColorMode,
    stdout_is_tty: bool,
    terminal_colors: TerminalColors = .{},
    terminal_colors_pending: bool = false,
    terminal_color_scheme: ?Appearance = null,
    /// Null selects the generated system theme. A present JSON document selects
    /// that resource, with a stable identity supplied by its actual owner.
    resource_json: ?[]const u8 = null,
    resource_identity: ?[]const u8 = null,
};
fn validRgb(rgb: Rgb) !void {
    for ([_]f64{ rgb.r, rgb.g, rgb.b }) |channel| if (!std.math.isFinite(channel) or channel < 0 or channel > 255) return error.InvalidThemeStateColor;
}
pub fn validate(gpa: std.mem.Allocator, state: State) !void {
    if (state.terminal_colors.foreground) |rgb| try validRgb(rgb);
    if (state.terminal_colors.background) |rgb| try validRgb(rgb);
    if (state.terminal_colors.palette.len != 0 and state.terminal_colors.palette.len != 16) return error.InvalidThemeStatePalette;
    for (state.terminal_colors.palette) |rgb| try validRgb(rgb);
    if (state.resource_json) |resource| {
        if (resource.len > 4 * 1024 * 1024) return error.ThemeStateResourceLimit;
        const parsed = std.json.parseFromSlice(std.json.Value, gpa, resource, .{}) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => return error.InvalidThemeStateResource,
        };
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidThemeStateResource;
    }
    if (state.resource_identity) |identity| if (identity.len > 65536) return error.ThemeStateIdentityLimit;
}
pub fn write(writer: *std.Io.Writer, state: State) !void {
    try writer.print("{{\"revision\":\"{d}\",\"colorMode\":", .{state.revision});
    try std.json.Stringify.value(@tagName(state.color_mode), .{}, writer);
    try writer.print(",\"stdoutIsTTY\":{},\"terminalColorsPending\":{},\"terminalColorScheme\":", .{ state.stdout_is_tty, state.terminal_colors_pending });
    if (state.terminal_color_scheme) |scheme| try std.json.Stringify.value(@tagName(scheme), .{}, writer) else try writer.writeAll("null");
    try writer.writeAll(",\"terminalColors\":{");
    var comma = false;
    if (state.terminal_colors.foreground) |rgb| {
        try writer.writeAll("\"foreground\":");
        try std.json.Stringify.value(rgb, .{}, writer);
        comma = true;
    }
    if (state.terminal_colors.background) |rgb| {
        if (comma) try writer.writeByte(',');
        try writer.writeAll("\"background\":");
        try std.json.Stringify.value(rgb, .{}, writer);
        comma = true;
    }
    if (state.terminal_colors.palette.len != 0) {
        if (comma) try writer.writeByte(',');
        try writer.writeAll("\"palette\":");
        try std.json.Stringify.value(state.terminal_colors.palette, .{}, writer);
    }
    try writer.writeAll("},\"resourceIdentity\":");
    try std.json.Stringify.value(state.resource_identity, .{}, writer);
    try writer.writeAll(",\"resource\":");
    if (state.resource_json) |resource| try writer.writeAll(resource) else try writer.writeAll("null");
    try writer.writeByte('}');
}
pub fn encode(gpa: std.mem.Allocator, state: State) ![]u8 {
    try validate(gpa, state);
    var buffer: std.Io.Writer.Allocating = .init(gpa);
    errdefer buffer.deinit();
    // The allocating writer's only write failure is buffer allocation failure.
    write(&buffer.writer, state) catch return error.OutOfMemory;
    return buffer.toOwnedSlice();
}
test "cached theme DTO keeps empty reports distinct from unbound and uses exact uint64 identity" {
    const encoded = try encode(std.testing.allocator, .{ .revision = std.math.maxInt(u64), .color_mode = .@"256color", .stdout_is_tty = false });
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings("{\"revision\":\"18446744073709551615\",\"colorMode\":\"256color\",\"stdoutIsTTY\":false,\"terminalColorsPending\":false,\"terminalColorScheme\":null,\"terminalColors\":{},\"resourceIdentity\":null,\"resource\":null}", encoded);
    try std.testing.expectError(error.InvalidThemeStateColor, encode(std.testing.allocator, .{ .revision = 1, .color_mode = .truecolor, .stdout_is_tty = true, .terminal_colors = .{ .foreground = .{ .r = std.math.nan(f64), .g = 0, .b = 0 } } }));
}
