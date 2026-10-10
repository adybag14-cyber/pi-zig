//! Bounded ECMA Unicode regexp matching through the pinned C implementation.
const std = @import("std");
const builtin = @import("builtin");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;

pub fn matches(gpa: std.mem.Allocator, pattern: []const u8, text: []const u8) !bool {
    const engine = try engine_mod.Engine.init(gpa, .{ .memory_limit = 8 * 1024 * 1024, .interrupt_budget = 2000 });
    defer engine.deinit();
    var length: c_int = 0;
    var message: [256]u8 = undefined;
    const terminated = try gpa.dupeZ(u8, pattern);
    defer gpa.free(terminated);
    const bytecode = c.lre_compile(&length, &message, message.len, terminated.ptr, pattern.len, c.LRE_FLAG_UNICODE, engine.context) orelse return error.InvalidSchemaPattern;
    defer c.js_free(engine.context, bytecode);
    const utf16 = try std.unicode.utf8ToUtf16LeAlloc(gpa, text);
    defer gpa.free(utf16);
    if (builtin.cpu.arch.endian() == .big) for (utf16) |*unit| {
        unit.* = @byteSwap(unit.*);
    };
    const count = c.lre_get_capture_count(bytecode);
    if (count <= 0) return error.InvalidSchemaPattern;
    const captures = try gpa.alloc([*c]u8, @as(usize, @intCast(count)) * 2);
    defer gpa.free(captures);
    @memset(captures, null);
    const result = c.lre_exec(captures.ptr, bytecode, @ptrCast(utf16.ptr), 0, std.math.cast(c_int, utf16.len) orelse return error.SchemaPatternInputTooLarge, 1, engine.context);
    return switch (result) {
        0 => false,
        1 => true,
        c.LRE_RET_TIMEOUT => error.SchemaPatternTimeout,
        c.LRE_RET_MEMORY_ERROR => error.OutOfMemory,
        else => error.InvalidSchemaPatternBytecode,
    };
}

test "native Unicode schema regexp matches alternation astral text and rejects malformed patterns" {
    const slice = "^abc$unrelated-backing-bytes";
    try std.testing.expect(try matches(std.testing.allocator, slice[0..5], "abc"));
    try std.testing.expect(try matches(std.testing.allocator, "^(left|right)_[0-9]+$", "left_42"));
    try std.testing.expect(!try matches(std.testing.allocator, "^(left|right)_[0-9]+$", "other_42"));
    try std.testing.expect(try matches(std.testing.allocator, "^.$", "🌍"));
    try std.testing.expectError(error.InvalidSchemaPattern, matches(std.testing.allocator, "[", "value"));
}
