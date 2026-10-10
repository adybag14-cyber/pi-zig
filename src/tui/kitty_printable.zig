//! Source decodeKittyPrintable, separate from generic modifyOtherKeys decoding.
const std = @import("std");
fn digits(text: []const u8, at: *usize) []const u8 {
    const start = at.*;
    while (at.* < text.len and std.ascii.isDigit(text[at.*])) : (at.* += 1) {}
    return text[start..at.*];
}
fn number(text: []const u8) f64 {
    return std.fmt.parseFloat(f64, text) catch std.math.inf(f64);
}
pub fn decode(data: []const u8) ?u21 {
    if (!std.mem.startsWith(u8, data, "\x1b[") or !std.mem.endsWith(u8, data, "u")) return null;
    const text = data[2 .. data.len - 1];
    var at: usize = 0;
    const raw_code = digits(text, &at);
    if (raw_code.len == 0) return null;
    var shifted: ?[]const u8 = null;
    var modifier: ?[]const u8 = null;
    if (at < text.len and text[at] == ':') {
        at += 1;
        shifted = digits(text, &at);
    }
    if (at < text.len and text[at] == ':') {
        at += 1;
        if (digits(text, &at).len == 0) return null; // alternate base layout
    }
    if (at < text.len and text[at] == ';') {
        at += 1;
        modifier = digits(text, &at);
        if (modifier.?.len == 0) return null;
    }
    if (at < text.len and text[at] == ':') {
        at += 1;
        if (digits(text, &at).len == 0) return null; // event is matched but ignored
    }
    if (at != text.len) return null;
    const code = number(raw_code);
    if (!std.math.isFinite(code)) return null;
    const raw_modifier = if (modifier) |value| number(value) else 1;
    // Source bitwise operators apply ToInt32 after Number.parseInt rounding.
    const bits: u32 = if (std.math.isFinite(raw_modifier)) @intFromFloat(@mod(raw_modifier - 1, 4294967296.0)) else 0;
    if ((bits & ~@as(u32, 1 + 64 + 128)) != 0) return null;
    const effective = if ((bits & 1) != 0 and shifted != null and shifted.?.len != 0) number(shifted.?) else code;
    if (!std.math.isFinite(effective) or effective < 32 or effective > 0x10ffff) return null;
    const cp: u21 = @intFromFloat(effective);
    return switch (cp) {
        57399...57408 => 48 + (cp - 57399),
        57409 => '.',
        57410 => '/',
        57411 => '*',
        57412 => '-',
        57413 => '+',
        57415 => '=',
        57416 => ',',
        57417...57426 => null,
        else => cp,
    };
}
test "Source6fb public Input CSI-u decoder preserves original printable modifier and event behavior" {
    const fixture = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("fixtures/kitty-printable-original-6fb.json"), .{});
    defer fixture.deinit();
    for (fixture.value.object.get("cases").?.array.items) |item| {
        const value = item.object.get("codepoint").?;
        const wanted: ?u21 = if (value == .null) null else @intCast(value.integer);
        std.testing.expectEqual(wanted, decode(item.object.get("data").?.string)) catch |err| {
            std.debug.print("Kitty printable mismatch {s}\n", .{item.object.get("data").?.string});
            return err;
        };
    }
}
