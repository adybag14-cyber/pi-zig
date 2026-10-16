//! Canonical scalar UTF8 for native glob paths, distinct from VM code-unit
//! transport. Unpaired surrogates and invalid native names are explicit gaps.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");

pub fn fromValue(engine: *v.em.Engine, value: v.c.JSValue) ![]u8 {
    var length: usize = 0;
    const units = v.c.JS_ToCStringLenUTF16(engine.context, &length, value);
    if (units == null) return v.js.capture(engine);
    defer v.c.JS_FreeCStringUTF16(engine.context, units);
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(engine.gpa);
    var index: usize = 0;
    while (index < length) : (index += 1) {
        const first = units[index];
        const scalar: u21 = if (first >= 0xd800 and first <= 0xdbff) pair: {
            if (index + 1 == length) return error.NodeGlobLoneSurrogateUnsupported;
            const second = units[index + 1];
            if (second < 0xdc00 or second > 0xdfff) return error.NodeGlobLoneSurrogateUnsupported;
            index += 1;
            break :pair 0x10000 + (@as(u21, first - 0xd800) << 10) + @as(u21, second - 0xdc00);
        } else if (first >= 0xdc00 and first <= 0xdfff)
            return error.NodeGlobLoneSurrogateUnsupported
        else first;
        var encoded: [4]u8 = undefined;
        const count = try std.unicode.utf8Encode(scalar, &encoded);
        try result.appendSlice(engine.gpa, encoded[0..count]);
    }
    return result.toOwnedSlice(engine.gpa);
}

pub fn validateNativeName(name: []const u8) !void {
    if (!std.unicode.utf8ValidateSlice(name)) return error.NodeGlobInvalidNativeNameUnsupported;
}
