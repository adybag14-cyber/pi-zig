//! Original-compatible initial CLI prompt composition.
//!
//! Piped stdin, processed `@file` text, and only the first positional CLI
//! message are concatenated without injected separators. Remaining positional
//! messages are follow-up turns and must be submitted individually.
const std = @import("std");

pub const Result = struct {
    message: ?[]u8,
    consumed_messages: usize,

    pub fn deinit(self: *Result, gpa: std.mem.Allocator) void {
        if (self.message) |message| gpa.free(message);
        self.* = undefined;
    }
};

pub fn build(
    gpa: std.mem.Allocator,
    stdin_content: ?[]const u8,
    file_text: []const u8,
    messages: []const []const u8,
) !Result {
    var total: usize = 0;
    if (stdin_content) |input| total = try checkedAdd(total, input.len);
    if (file_text.len > 0) total = try checkedAdd(total, file_text.len);
    const consumed: usize = @intFromBool(messages.len > 0);
    if (messages.len > 0) total = try checkedAdd(total, messages[0].len);
    if (total == 0) return .{ .message = null, .consumed_messages = consumed };

    const output = try gpa.alloc(u8, total);
    errdefer gpa.free(output);
    var at: usize = 0;
    if (stdin_content) |input| {
        @memcpy(output[at..][0..input.len], input);
        at += input.len;
    }
    if (file_text.len > 0) {
        @memcpy(output[at..][0..file_text.len], file_text);
        at += file_text.len;
    }
    if (messages.len > 0) {
        @memcpy(output[at..][0..messages[0].len], messages[0]);
        at += messages[0].len;
    }
    std.debug.assert(at == output.len);
    return .{ .message = output, .consumed_messages = consumed };
}

fn checkedAdd(a: usize, b: usize) !usize {
    return std.math.add(usize, a, b) catch error.InputTooLarge;
}

test "initial message matches stdin file and first-message concatenation" {
    const gpa = std.testing.allocator;
    const messages = [_][]const u8{ "first", "follow-up" };
    var result = try build(gpa, "stdin\n", "<file>x</file>\n", &messages);
    defer result.deinit(gpa);
    try std.testing.expectEqualStrings("stdin\n<file>x</file>\nfirst", result.message.?);
    try std.testing.expectEqual(@as(usize, 1), result.consumed_messages);
}

test "initial message retains explicit empty first message consumption" {
    const gpa = std.testing.allocator;
    var result = try build(gpa, null, "", &.{""});
    defer result.deinit(gpa);
    try std.testing.expect(result.message == null);
    try std.testing.expectEqual(@as(usize, 1), result.consumed_messages);
}

test "initial message does not consume follow-up turns" {
    const gpa = std.testing.allocator;
    const messages = [_][]const u8{ "one", "two", "three" };
    var result = try build(gpa, null, "", &messages);
    defer result.deinit(gpa);
    try std.testing.expectEqualStrings("one", result.message.?);
    try std.testing.expectEqual(@as(usize, 1), result.consumed_messages);
    try std.testing.expectEqualStrings("two", messages[result.consumed_messages]);
}

test "stdin presence preserves an empty stdin value but no message is synthesized" {
    const gpa = std.testing.allocator;
    var result = try build(gpa, "", "", &.{});
    defer result.deinit(gpa);
    try std.testing.expect(result.message == null);
    try std.testing.expectEqual(@as(usize, 0), result.consumed_messages);
}
