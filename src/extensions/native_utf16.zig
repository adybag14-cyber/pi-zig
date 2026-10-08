//! Lossless JavaScript string storage for UTF16 component cursor semantics.
const std = @import("std");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
pub fn unitsAlloc(engine: *engine_mod.Engine, value: c.JSValue) ![]u16 {
    var length: usize = 0;
    const raw = c.JS_ToCStringLen2(engine.context, &length, value, true) orelse return @import("native_js_values.zig").capture(engine);
    defer c.JS_FreeCString(engine.context, raw);
    // CESU8 exposes the actual JS code units, including lone surrogates and
    // deliberately split pairs; normal UTF8 conversion loses that distinction.
    const result = try std.unicode.wtf8ToWtf16LeAlloc(engine.gpa, raw[0..length]);
    for (result) |*unit| unit.* = std.mem.littleToNative(u16, unit.*);
    return result;
}
pub fn string(engine: *engine_mod.Engine, units: []const u16) !c.JSValue {
    return engine.checked(c.JS_NewStringUTF16(engine.context, units.ptr, units.len));
}
test "native JS UTF16 preserves NUL lone surrogates and split pairs without UTF8 loss" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const expected = [_]u16{ 0, 'a', 0xd800, 'z', 0xdc00, 0xd83d, 0xde00, 0xffff };
    const value = try string(engine, &expected);
    defer engine.freeValue(value);
    const actual = try unitsAlloc(engine, value);
    defer engine.gpa.free(actual);
    try std.testing.expectEqualSlices(u16, &expected, actual);
}
