//! Conservative context-token estimation and output-budget clamping.
const std = @import("std");
const ai = @import("root.zig");

pub const Estimate = struct {
    tokens: u64,
    usage_tokens: u64,
    trailing_tokens: u64,
    last_usage_index: ?usize,
};

const ESTIMATED_IMAGE_CHARS: u64 = 4800;
pub const CONTEXT_SAFETY_TOKENS: u64 = 4096;

fn estimateChars(chars: u64) u64 {
    // Exact ceil(chars / 3.5), without floating rounding or u64 overflow.
    return @intCast((@as(u128, chars) * 2 + 6) / 7);
}

fn utf16Length(text: []const u8) u64 {
    const view = std.unicode.Utf8View.init(text) catch return @intCast(text.len);
    var iterator = view.iterator();
    var count: u64 = 0;
    while (iterator.nextCodepoint()) |point| count += if (point > 0xffff) @as(u64, 2) else 1;
    return count;
}

fn stringifiedValueChars(value: std.json.Value) u64 {
    const alloc = std.heap.page_allocator;
    var out: std.Io.Writer.Allocating = .init(alloc);
    defer out.deinit();
    std.json.Stringify.value(value, .{}, &out.writer) catch return 0;
    return utf16Length(out.written());
}

/// Return the compact JSON length used by JavaScript's `JSON.stringify`.
/// Valid runtime schemas always reach this path; malformed compatibility input
/// falls back to its raw byte length rather than undercounting context.
pub fn canonicalJsonChars(raw: []const u8) u64 {
    if (raw.len == 0) return 0;
    const alloc = std.heap.page_allocator;
    var parsed = std.json.parseFromSlice(std.json.Value, alloc, raw, .{}) catch return utf16Length(raw);
    defer parsed.deinit();
    const chars = stringifiedValueChars(parsed.value);
    return if (chars == 0) utf16Length(raw) else chars;
}

fn argumentChars(value: std.json.Value) u64 {
    if (value == .string) {
        const alloc = std.heap.page_allocator;
        var parsed = std.json.parseFromSlice(std.json.Value, alloc, value.string, .{}) catch return stringifiedValueChars(value);
        defer parsed.deinit();
        const chars = stringifiedValueChars(parsed.value);
        return if (chars == 0) stringifiedValueChars(value) else chars;
    }
    return stringifiedValueChars(value);
}

/// Pi's assistant estimator charges only each tool-call name plus the compact
/// JSON arguments. Transport wrappers (`id`, `type`, `function`) are not part
/// of the model-content estimate.
pub fn estimateToolCallsChars(raw: []const u8) u64 {
    if (raw.len == 0) return 0;
    const alloc = std.heap.page_allocator;
    var parsed = std.json.parseFromSlice(std.json.Value, alloc, raw, .{}) catch return utf16Length(raw);
    defer parsed.deinit();
    if (parsed.value != .array) return utf16Length(raw);

    var chars: u64 = 0;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const function = item.object.get("function") orelse item;
        if (function != .object) continue;
        const name = function.object.get("name") orelse continue;
        if (name != .string) continue;
        chars +|= utf16Length(name.string);
        if (function.object.get("arguments")) |arguments| {
            chars +|= argumentChars(arguments);
        } else {
            // JavaScript's safeJsonStringify(undefined) fallback.
            chars +|= "undefined".len;
        }
    }
    return chars;
}

pub fn calculateContextTokens(usage: ai.Usage) u64 {
    if (usage.total_tokens > 0) return usage.total_tokens;
    return usage.input + usage.output + usage.cache_read + usage.cache_write;
}

pub fn estimateMessageTokens(message: ai.ChatMessage) u64 {
    var chars: u64 = utf16Length(message.content);
    chars += @as(u64, @intCast(message.imageCount())) * ESTIMATED_IMAGE_CHARS;
    if (std.mem.eql(u8, message.role, "assistant")) {
        if (message.thinking) |thinking| chars += utf16Length(thinking);
        if (message.tool_calls_json) |calls| chars +|= estimateToolCallsChars(calls);
    }
    return estimateChars(chars);
}

fn timestampAtLeast(candidate: ?[]const u8, latest: ?[]const u8) bool {
    const latest_value = latest orelse return true;
    const candidate_value = candidate orelse return false;
    return std.mem.order(u8, candidate_value, latest_value) != .lt;
}

pub fn estimateMessages(messages: []const ai.ChatMessage) Estimate {
    var latest_prefix_timestamp: ?[]const u8 = null;
    var last_usage_index: ?usize = null;
    var last_usage_tokens: u64 = 0;

    for (messages, 0..) |message, i| {
        if (std.mem.eql(u8, message.role, "assistant")) {
            const reason = message.stop_reason orelse "";
            const usage_tokens = calculateContextTokens(message.usage);
            if (timestampAtLeast(message.timestamp, latest_prefix_timestamp) and
                !std.mem.eql(u8, reason, "aborted") and
                !std.mem.eql(u8, reason, "error") and usage_tokens > 0)
            {
                last_usage_index = i;
                last_usage_tokens = usage_tokens;
            }
        }
        if (message.timestamp) |timestamp| {
            if (latest_prefix_timestamp == null or std.mem.order(u8, timestamp, latest_prefix_timestamp.?) == .gt)
                latest_prefix_timestamp = timestamp;
        }
    }

    if (last_usage_index) |index| {
        var trailing: u64 = 0;
        for (messages[index + 1 ..]) |message| trailing += estimateMessageTokens(message);
        return .{ .tokens = last_usage_tokens + trailing, .usage_tokens = last_usage_tokens, .trailing_tokens = trailing, .last_usage_index = index };
    }

    var total: u64 = 0;
    for (messages) |message| total += estimateMessageTokens(message);
    return .{ .tokens = total, .usage_tokens = 0, .trailing_tokens = total, .last_usage_index = null };
}

fn toolName(value: std.json.Value) ?[]const u8 {
    if (value != .object) return null;
    const function = value.object.get("function") orelse return null;
    if (function != .object) return null;
    const name = function.object.get("name") orelse return null;
    return if (name == .string) name.string else null;
}

fn nameWasAdded(messages: []const ai.ChatMessage, start: usize, name: []const u8) bool {
    for (messages[start..]) |message| {
        if (!std.mem.eql(u8, message.role, "tool")) continue;
        for (message.added_tool_names) |added| if (std.mem.eql(u8, added, name)) return true;
    }
    return false;
}

/// Estimate only definitions loaded after a trusted usage snapshot. This mirrors
/// upstream Pi's deferred-tool accounting without charging the entire current
/// catalog a second time.
fn estimateAddedToolsTokens(tools_json: []const u8, messages: []const ai.ChatMessage, start: usize) u64 {
    if (tools_json.len <= 2 or start >= messages.len) return 0;
    const alloc = std.heap.page_allocator;
    var parsed = std.json.parseFromSlice(std.json.Value, alloc, tools_json, .{}) catch return 0;
    defer parsed.deinit();
    if (parsed.value != .array) return 0;

    var out: std.Io.Writer.Allocating = .init(alloc);
    defer out.deinit();
    out.writer.writeAll("[") catch return 0;
    var first = true;
    for (parsed.value.array.items) |item| {
        const name = toolName(item) orelse continue;
        if (!nameWasAdded(messages, start, name)) continue;
        if (!first) out.writer.writeAll(",") catch return 0;
        first = false;
        std.json.Stringify.value(item, .{}, &out.writer) catch return 0;
    }
    out.writer.writeAll("]") catch return 0;
    return if (first) 0 else estimateChars(utf16Length(out.written()));
}

pub fn estimateContext(messages: []const ai.ChatMessage, tools_json: []const u8) Estimate {
    var estimate = estimateMessages(messages);
    if (estimate.last_usage_index) |index| {
        const added_tool_tokens = estimateAddedToolsTokens(tools_json, messages, index + 1);
        estimate.tokens += added_tool_tokens;
        estimate.trailing_tokens += added_tool_tokens;
    } else if (tools_json.len > 2) {
        const tool_tokens = estimateChars(canonicalJsonChars(tools_json));
        estimate.tokens += tool_tokens;
        estimate.trailing_tokens += tool_tokens;
    }
    return estimate;
}

pub fn clampMaxTokens(context_window: u64, configured_max: u64, messages: []const ai.ChatMessage, tools_json: []const u8) u64 {
    if (context_window == 0) return @max(@as(u64, 1), configured_max);
    const used = estimateContext(messages, tools_json).tokens;
    const reserved = std.math.add(u64, used, CONTEXT_SAFETY_TOKENS) catch std.math.maxInt(u64);
    const available: u64 = if (context_window > reserved) context_window - reserved else 1;
    return @min(configured_max, @max(@as(u64, 1), available));
}

test "tool-call estimation ignores transport wrappers and compacts arguments" {
    const calls = "[{\"id\":\"call_with_large_wrapper\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{ \\\"path\\\" : \\\"a.txt\\\" }\"}}]";
    // "read" (4) + compact {"path":"a.txt"} (16) = 20 chars = 6 tokens.
    const message = ai.ChatMessage{ .role = "assistant", .content = "", .tool_calls_json = calls };
    try std.testing.expectEqual(@as(u64, 20), estimateToolCallsChars(calls));
    try std.testing.expectEqual(@as(u64, 6), estimateMessageTokens(message));
}

test "latest estimator matches actual upstream UTF16 and 3.5 character oracle" {
    const gpa = std.testing.allocator;
    const captured = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/context-estimate-7fb.json"), .{});
    defer captured.deinit();
    for (captured.value.object.get("texts").?.array.items) |row| {
        const message: ai.ChatMessage = .{ .role = "user", .content = row.object.get("text").?.string };
        try std.testing.expectEqual(@as(u64, @intCast(row.object.get("tokens").?.integer)), estimateMessageTokens(message));
    }
    const text = [_]u8{'x'} ** 3500;
    const messages = [_]ai.ChatMessage{
        .{ .role = "assistant", .content = "kept", .timestamp = "2026-01-01T00:00:00Z", .stop_reason = "stop", .usage = .{ .total_tokens = 2000 } },
        .{ .role = "user", .content = &text, .timestamp = "2026-01-01T00:00:01Z" },
    };
    const result = estimateMessages(&messages);
    const expected = captured.value.object.get("context").?.object;
    try std.testing.expectEqual(@as(u64, @intCast(expected.get("tokens").?.integer)), result.tokens);
    try std.testing.expectEqual(@as(u64, @intCast(expected.get("trailingTokens").?.integer)), result.trailing_tokens);
    try std.testing.expectEqual(@as(u64, 5270498306774157605), estimateChars(std.math.maxInt(u64)));
}

test "tool catalog estimation uses compact JSON and no-context clamp keeps one token" {
    const pretty = "[ { \"type\" : \"function\", \"function\" : { \"name\" : \"x\" } } ]";
    const compact = "[{\"type\":\"function\",\"function\":{\"name\":\"x\"}}]";
    try std.testing.expectEqual(@as(u64, compact.len), canonicalJsonChars(pretty));
    try std.testing.expectEqual(@as(u64, 1), clampMaxTokens(0, 0, &.{}, "[]"));
    try std.testing.expectEqual(@as(u64, 7), clampMaxTokens(0, 7, &.{}, "[]"));
    try std.testing.expectEqual(@as(u64, 0), clampMaxTokens(8_000, 0, &.{}, "[]"));
}

test "latest valid assistant usage plus trailing estimate drives clamp" {
    const messages = [_]ai.ChatMessage{
        .{ .role = "user", .content = "old", .timestamp = "2026-01-01T00:00:00Z" },
        .{ .role = "assistant", .content = "answer", .timestamp = "2026-01-01T00:00:01Z", .stop_reason = "stop", .usage = .{ .total_tokens = 6000 } },
        .{ .role = "user", .content = "12345678", .timestamp = "2026-01-01T00:00:02Z" },
    };
    const estimate = estimateContext(&messages, "[]");
    try std.testing.expectEqual(@as(u64, 6003), estimate.tokens);
    try std.testing.expectEqual(@as(u64, 3), estimate.trailing_tokens);
    try std.testing.expectEqual(@as(u64, 1901), clampMaxTokens(12_000, 4_000, &messages, "[]"));
}

test "newer inserted prefix timestamp invalidates stale assistant usage" {
    const messages = [_]ai.ChatMessage{
        .{ .role = "system", .content = "summary", .timestamp = "2026-01-02T00:00:00Z" },
        .{ .role = "assistant", .content = "old", .timestamp = "2026-01-01T00:00:00Z", .stop_reason = "stop", .usage = .{ .total_tokens = 9000 } },
    };
    const estimate = estimateMessages(&messages);
    try std.testing.expect(estimate.last_usage_index == null);
    try std.testing.expect(estimate.tokens < 100);
}

test "trusted usage counts only trailing deferred tool definitions" {
    const tools =
        \\[{"type":"function","function":{"name":"old_tool","description":"already counted in usage","parameters":{"type":"object"}}},{"type":"function","function":{"name":"late_tool","description":"newly loaded after snapshot","parameters":{"type":"object"}}}]
    ;
    const added = [_][]const u8{"late_tool"};
    const messages = [_]ai.ChatMessage{
        .{ .role = "assistant", .content = "done", .timestamp = "2026-01-01T00:00:00Z", .stop_reason = "stop", .usage = .{ .total_tokens = 1000 } },
        .{ .role = "tool", .content = "ok", .timestamp = "2026-01-01T00:00:01Z", .added_tool_names = &added },
    };
    const with_added = estimateContext(&messages, tools);
    const no_added_messages = [_]ai.ChatMessage{
        messages[0],
        .{ .role = "tool", .content = "ok", .timestamp = "2026-01-01T00:00:01Z" },
    };
    const without_added = estimateContext(&no_added_messages, tools);
    try std.testing.expect(with_added.tokens > without_added.tokens);
    const full_catalog_tokens = estimateChars(tools.len);
    try std.testing.expect(with_added.tokens - without_added.tokens < full_catalog_tokens);
}
