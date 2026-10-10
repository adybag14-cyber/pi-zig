//! Pinned native Unicode tables, with allocations routed through the caller.
const std = @import("std");
const c = @cImport({
    @cInclude("libunicode.h");
});
const decode = @import("decode.zig");
const Allocation = struct { gpa: std.mem.Allocator, buffer: ?*anyopaque = null };
fn realloc(allocator_context: ?*anyopaque, ptr: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque {
    const state: *Allocation = @ptrCast(@alignCast(allocator_context.?));
    const allocator = state.gpa;
    const old: ?[*]u64 = if (ptr) |pointer| @ptrFromInt(@intFromPtr(pointer) - @sizeOf(u64)) else null;
    if (size == 0) {
        if (old) |block| allocator.free(block[0..block[0]]);
        state.buffer = null;
        return null;
    }
    const count = std.math.add(usize, size, 15) catch return null;
    const block = allocator.alloc(u64, count / 8) catch return null;
    block[0] = block.len;
    const bytes = std.mem.sliceAsBytes(block[1..]);
    if (old) |previous| {
        const previous_bytes = std.mem.sliceAsBytes(previous[1..previous[0]]);
        @memcpy(bytes[0..@min(size, previous_bytes.len)], previous_bytes[0..@min(size, previous_bytes.len)]);
        allocator.free(previous[0..previous[0]]);
    }
    state.buffer = bytes.ptr;
    return state.buffer;
}
pub const Form = enum { nfd, nfkc };
pub fn normalize(gpa: std.mem.Allocator, text: []const u8, form: Form) ![]u8 {
    const valid = try decode.decode(gpa, text, true);
    defer gpa.free(valid);
    const view = try std.unicode.Utf8View.init(valid);
    var points: std.ArrayList(u32) = .empty;
    defer points.deinit(gpa);
    var iterator = view.iterator();
    while (iterator.nextCodepoint()) |point| try points.append(gpa, point);
    if (points.items.len > std.math.maxInt(c_int)) return error.TextTooLarge;
    var allocation: Allocation = .{ .gpa = gpa };
    defer _ = realloc(&allocation, allocation.buffer, 0);
    var result: [*c]u32 = null;
    const length = c.unicode_normalize(&result, points.items.ptr, @intCast(points.items.len), if (form == .nfd) c.UNICODE_NFD else c.UNICODE_NFKC, &allocation, realloc);
    if (length < 0) return error.OutOfMemory;
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    var bytes: [4]u8 = undefined;
    for (result[0..@intCast(length)]) |point| {
        const count = try std.unicode.utf8Encode(@intCast(point), &bytes);
        try output.appendSlice(gpa, bytes[0..count]);
    }
    return output.toOwnedSlice(gpa);
}
pub fn lf(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    var index: usize = 0;
    while (index < text.len) : (index += 1) {
        if (text[index] == '\r') {
            try output.append(gpa, '\n');
            if (index + 1 < text.len and text[index + 1] == '\n') index += 1;
        } else try output.append(gpa, text[index]);
    }
    return output.toOwnedSlice(gpa);
}
fn whitespace(point: u21) bool {
    return switch (point) {
        9...13, 32, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => true,
        else => false,
    };
}
pub fn fuzzy(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    const normalized = try normalize(gpa, input, .nfkc);
    defer gpa.free(normalized);
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    var iterator = (try std.unicode.Utf8View.init(normalized)).iterator();
    var trim: usize = 0;
    var bytes: [4]u8 = undefined;
    while (iterator.nextCodepoint()) |point| {
        if (point == '\n') {
            output.items.len = trim;
            try output.append(gpa, '\n');
            trim = output.items.len;
            continue;
        }
        const mapped: u21 = switch (point) {
            0x2018...0x201b => '\'',
            0x201c...0x201f => '"',
            0x2010...0x2015, 0x2212 => '-',
            0xa0, 0x2002...0x200a, 0x202f, 0x205f, 0x3000 => ' ',
            else => point,
        };
        const count = try std.unicode.utf8Encode(mapped, &bytes);
        try output.appendSlice(gpa, bytes[0..count]);
        if (!whitespace(point)) trim = output.items.len;
    }
    output.items.len = trim;
    return output.toOwnedSlice(gpa);
}
pub fn toolPath(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    const valid = try decode.decode(gpa, input, true);
    defer gpa.free(valid);
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    var iterator = (try std.unicode.Utf8View.init(valid)).iterator();
    var bytes: [4]u8 = undefined;
    var first = true;
    while (iterator.nextCodepoint()) |point| {
        if (first and point == '@') {
            first = false;
            continue;
        }
        first = false;
        const mapped: u21 = switch (point) {
            0xa0, 0x2000...0x200a, 0x202f, 0x205f, 0x3000 => ' ',
            else => point,
        };
        const count = try std.unicode.utf8Encode(mapped, &bytes);
        try output.appendSlice(gpa, bytes[0..count]);
    }
    return output.toOwnedSlice(gpa);
}
pub fn curly(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    for (input) |byte| if (byte == '\'') {
        try output.appendSlice(gpa, "\xe2\x80\x99");
    } else try output.append(gpa, byte);
    return output.toOwnedSlice(gpa);
}
pub fn screenshot(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    var index: usize = 0;
    while (index < input.len) : (index += 1) {
        if (input[index] == ' ' and index + 4 <= input.len and (std.ascii.eqlIgnoreCase(input[index + 1 ..][0..3], "AM.") or std.ascii.eqlIgnoreCase(input[index + 1 ..][0..3], "PM."))) try output.appendSlice(gpa, "\xe2\x80\xaf") else try output.append(gpa, input[index]);
    }
    return output.toOwnedSlice(gpa);
}

test "durable native Unicode normalization owns and cleans each allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(gpa: std.mem.Allocator) !void {
            const value = try fuzzy(gpa, "ﬁ ‘quoted’ — é   \nkeep  ");
            defer gpa.free(value);
            try std.testing.expectEqualStrings("fi 'quoted' - é\nkeep", value);
            const nfd = try normalize(gpa, "é", .nfd);
            defer gpa.free(nfd);
            try std.testing.expectEqualStrings("e\xcc\x81", nfd);
        }
    }.run, .{});
}
