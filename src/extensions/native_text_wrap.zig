//! Byte-backed component adapter to the shared Source UTF16 wrapping engine.
const std = @import("std");
const Engine = @import("engine.zig").Engine;
pub fn wrap(engine: *Engine, source: []const u8, width: usize) ![][]u8 {
    const units = try std.unicode.wtf8ToWtf16LeAlloc(engine.gpa, source);
    defer engine.gpa.free(units);
    const wrapped = try @import("native_utf16_wrap.zig").wrap(engine, units, @floatFromInt(width));
    defer {
        for (wrapped) |line| engine.gpa.free(line);
        engine.gpa.free(wrapped);
    }
    var lines: std.ArrayList([]u8) = .empty;
    errdefer {
        for (lines.items) |line| engine.gpa.free(line);
        lines.deinit(engine.gpa);
    }
    for (wrapped) |line| {
        const owned = try std.unicode.wtf16LeToWtf8Alloc(engine.gpa, line);
        errdefer engine.gpa.free(owned);
        try lines.append(engine.gpa, owned);
    }
    return lines.toOwnedSlice(engine.gpa);
}
