//! Repair incomplete replay transcripts before provider serialization.
//! Mirrors upstream transform-messages behavior for interrupted tool flows.
const std = @import("std");
const ai = @import("root.zig");

const PendingTool = struct {
    id: []const u8,
    name: []const u8,
};

pub const RepairedTranscript = struct {
    gpa: std.mem.Allocator,
    messages: std.ArrayList(ai.ChatMessage) = .empty,
    owned: std.ArrayList([]u8) = .empty,

    pub fn deinit(self: *RepairedTranscript) void {
        for (self.owned.items) |value| self.gpa.free(value);
        self.owned.deinit(self.gpa);
        self.messages.deinit(self.gpa);
        self.* = undefined;
    }

    fn own(self: *RepairedTranscript, value: []const u8) ![]const u8 {
        const copy = try self.gpa.dupe(u8, value);
        errdefer self.gpa.free(copy);
        try self.owned.append(self.gpa, copy);
        return copy;
    }
};

fn isTerminalInvalid(msg: ai.ChatMessage) bool {
    if (!std.mem.eql(u8, msg.role, "assistant")) return false;
    const reason = msg.stop_reason orelse return false;
    return std.mem.eql(u8, reason, "error") or std.mem.eql(u8, reason, "aborted");
}

fn containsId(ids: []const []const u8, id: []const u8) bool {
    for (ids) |existing| if (std.mem.eql(u8, existing, id)) return true;
    return false;
}

fn collectToolCalls(result: *RepairedTranscript, raw: []const u8, pending: *std.ArrayList(PendingTool)) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, result.gpa, raw, .{}) catch return;
    defer parsed.deinit();
    if (parsed.value != .array) return;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const id = item.object.get("id") orelse continue;
        if (id != .string or id.string.len == 0) continue;
        var name: ?[]const u8 = null;
        if (item.object.get("function")) |function| {
            if (function == .object) if (function.object.get("name")) |value| {
                if (value == .string) name = value.string;
            };
        }
        if (name == null) if (item.object.get("custom")) |custom| {
            if (custom == .object) if (custom.object.get("name")) |value| {
                if (value == .string) name = value.string;
            };
        };
        const tool_name = name orelse continue;
        const owned_id = try result.own(id.string);
        const owned_name = try result.own(tool_name);
        try pending.append(result.gpa, .{ .id = owned_id, .name = owned_name });
    }
}

fn flushMissing(
    result: *RepairedTranscript,
    pending: *std.ArrayList(PendingTool),
    existing: *std.ArrayList([]const u8),
) !void {
    for (pending.items) |tool| {
        if (containsId(existing.items, tool.id)) continue;
        try result.messages.append(result.gpa, .{
            .role = "tool",
            .content = "No result provided",
            .tool_call_id = tool.id,
            .tool_name = tool.name,
            .tool_is_error = true,
        });
    }
    pending.clearRetainingCapacity();
    existing.clearRetainingCapacity();
}

pub fn repair(gpa: std.mem.Allocator, messages: []const ai.ChatMessage) !RepairedTranscript {
    var result: RepairedTranscript = .{ .gpa = gpa };
    errdefer result.deinit();
    var pending: std.ArrayList(PendingTool) = .empty;
    defer pending.deinit(gpa);
    var existing: std.ArrayList([]const u8) = .empty;
    defer existing.deinit(gpa);

    for (messages) |msg| {
        if (std.mem.eql(u8, msg.role, "assistant")) {
            try flushMissing(&result, &pending, &existing);
            if (isTerminalInvalid(msg)) continue;
            try result.messages.append(gpa, msg);
            if (msg.tool_calls_json) |raw| try collectToolCalls(&result, raw, &pending);
        } else if (std.mem.eql(u8, msg.role, "tool")) {
            if (msg.tool_call_id) |id| try existing.append(gpa, id);
            try result.messages.append(gpa, msg);
        } else if (std.mem.eql(u8, msg.role, "user")) {
            try flushMissing(&result, &pending, &existing);
            try result.messages.append(gpa, msg);
        } else {
            try result.messages.append(gpa, msg);
        }
    }
    try flushMissing(&result, &pending, &existing);
    return result;
}

pub const ToolIdMode = enum { none, sanitize64 };

pub const PrepareOptions = struct {
    supports_images: bool = true,
    target_provider: ?[]const u8 = null,
    target_api: ?[]const u8 = null,
    target_model: ?[]const u8 = null,
    tool_id_mode: ToolIdMode = .none,
};

const USER_IMAGE_OMITTED = "(image omitted: model does not support images)";
const TOOL_IMAGE_OMITTED = "(tool image omitted: model does not support images)";

fn appendPlaceholder(result: *RepairedTranscript, content: []const u8, placeholder: []const u8) ![]const u8 {
    if (std.mem.indexOf(u8, content, placeholder) != null) return content;
    if (content.len == 0) return try result.own(placeholder);
    const joined = try std.fmt.allocPrint(result.gpa, "{s}\n{s}", .{ content, placeholder });
    errdefer result.gpa.free(joined);
    try result.owned.append(result.gpa, joined);
    return joined;
}

fn sameTargetIdentity(msg: ai.ChatMessage, options: PrepareOptions) bool {
    const provider = options.target_provider orelse return true;
    const api = options.target_api orelse return true;
    const model = options.target_model orelse return true;
    return msg.provider != null and msg.api != null and msg.model != null and
        std.ascii.eqlIgnoreCase(msg.provider.?, provider) and
        std.ascii.eqlIgnoreCase(msg.api.?, api) and
        std.mem.eql(u8, msg.model.?, model);
}

fn stripToolThoughtSignatures(result: *RepairedTranscript, raw: []const u8) ![]const u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, result.gpa, raw, .{}) catch return raw;
    defer parsed.deinit();
    if (parsed.value != .array) return raw;
    var changed = false;
    for (parsed.value.array.items) |*item| {
        if (item.* != .object) continue;
        if (item.object.orderedRemove("thoughtSignature")) changed = true;
    }
    if (!changed) return raw;
    var out: std.Io.Writer.Allocating = .init(result.gpa);
    errdefer out.deinit();
    try std.json.Stringify.value(parsed.value, .{}, &out.writer);
    const owned = try out.toOwnedSlice();
    errdefer result.gpa.free(owned);
    try result.owned.append(result.gpa, owned);
    return owned;
}

fn downgradeCrossModelAssistant(result: *RepairedTranscript, msg: *ai.ChatMessage, options: PrepareOptions) !void {
    if (!std.mem.eql(u8, msg.role, "assistant") or sameTargetIdentity(msg.*, options)) return;
    if (msg.thinking) |thought| {
        if (std.mem.trim(u8, thought, " \t\r\n").len > 0) {
            if (msg.content.len == 0) {
                msg.content = try result.own(thought);
            } else {
                const joined = try std.fmt.allocPrint(result.gpa, "{s}\n{s}", .{ thought, msg.content });
                errdefer result.gpa.free(joined);
                try result.owned.append(result.gpa, joined);
                msg.content = joined;
            }
        }
        msg.thinking = null;
        msg.thinking_signature = null;
    } else if (msg.thinking_signature != null) {
        msg.thinking_signature = null;
    }
    if (msg.tool_calls_json) |raw| msg.tool_calls_json = try stripToolThoughtSignatures(result, raw);
}

fn sanitizeToolId64(result: *RepairedTranscript, raw: []const u8) ![]const u8 {
    const n = @min(raw.len, 64);
    var changed = raw.len > 64;
    const out = try result.gpa.alloc(u8, n);
    errdefer result.gpa.free(out);
    for (raw[0..n], 0..) |c, i| {
        const next = if (std.ascii.isAlphanumeric(c) or c == '_' or c == '-') c else '_';
        if (next != c) changed = true;
        out[i] = next;
    }
    if (!changed) {
        result.gpa.free(out);
        return raw;
    }
    try result.owned.append(result.gpa, out);
    return out;
}

fn normalizeCrossModelToolIds(result: *RepairedTranscript, options: PrepareOptions) !void {
    if (options.tool_id_mode == .none) return;
    var map = std.StringHashMap([]const u8).init(result.gpa);
    defer map.deinit();

    for (result.messages.items) |*msg| {
        if (std.mem.eql(u8, msg.role, "assistant") and !sameTargetIdentity(msg.*, options)) {
            const raw = msg.tool_calls_json orelse continue;
            var parsed = std.json.parseFromSlice(std.json.Value, result.gpa, raw, .{}) catch continue;
            defer parsed.deinit();
            if (parsed.value != .array) continue;
            var changed = false;
            for (parsed.value.array.items) |*item| {
                if (item.* != .object) continue;
                const idv = item.object.getPtr("id") orelse continue;
                if (idv.* != .string) continue;
                const original = idv.string;
                const normalized = switch (options.tool_id_mode) {
                    .none => original,
                    .sanitize64 => try sanitizeToolId64(result, original),
                };
                if (!std.mem.eql(u8, original, normalized)) {
                    const key = try result.own(original);
                    try map.put(key, normalized);
                    idv.* = .{ .string = normalized };
                    changed = true;
                }
            }
            if (changed) {
                var out: std.Io.Writer.Allocating = .init(result.gpa);
                errdefer out.deinit();
                try std.json.Stringify.value(parsed.value, .{}, &out.writer);
                const owned = try out.toOwnedSlice();
                errdefer result.gpa.free(owned);
                try result.owned.append(result.gpa, owned);
                msg.tool_calls_json = owned;
            }
        } else if (std.mem.eql(u8, msg.role, "tool")) {
            if (msg.tool_call_id) |raw_id| {
                if (map.get(raw_id)) |normalized| msg.tool_call_id = normalized;
            }
        }
    }
}

/// Repair replay invariants and adapt media to the selected model capability.
/// Unsupported images become explicit text rather than invalid wire payloads or
/// silently disappearing from context.
pub fn prepare(gpa: std.mem.Allocator, messages: []const ai.ChatMessage, options: PrepareOptions) !RepairedTranscript {
    var result = try repair(gpa, messages);
    errdefer result.deinit();
    for (result.messages.items) |*msg| {
        try downgradeCrossModelAssistant(&result, msg, options);
        if (options.supports_images or !msg.hasImages()) continue;
        const placeholder: ?[]const u8 = if (std.mem.eql(u8, msg.role, "tool")) TOOL_IMAGE_OMITTED else if (std.mem.eql(u8, msg.role, "user")) USER_IMAGE_OMITTED else null;
        if (placeholder) |text| {
            msg.content = try appendPlaceholder(&result, msg.content, text);
            msg.image_b64 = null;
            msg.image_mime = null;
            msg.images = &.{};
        }
    }
    try normalizeCrossModelToolIds(&result, options);
    return result;
}

test "repair drops aborted assistants and fills orphan tool results" {
    const calls =
        \\[{"id":"c1","type":"function","function":{"name":"read","arguments":"{}"}},{"id":"c2","type":"function","function":{"name":"write","arguments":"{}"}}]
    ;
    const input = [_]ai.ChatMessage{
        .{ .role = "user", .content = "go" },
        .{ .role = "assistant", .content = "", .tool_calls_json = calls, .stop_reason = "toolUse" },
        .{ .role = "tool", .content = "ok", .tool_call_id = "c1", .tool_name = "read" },
        .{ .role = "assistant", .content = "partial", .stop_reason = "aborted" },
        .{ .role = "user", .content = "continue" },
    };
    var fixed = try repair(std.testing.allocator, &input);
    defer fixed.deinit();
    try std.testing.expectEqual(@as(usize, 5), fixed.messages.items.len);
    try std.testing.expectEqualStrings("tool", fixed.messages.items[3].role);
    try std.testing.expectEqualStrings("c2", fixed.messages.items[3].tool_call_id.?);
    try std.testing.expect(fixed.messages.items[3].tool_is_error);
    try std.testing.expectEqualStrings("continue", fixed.messages.items[4].content);
}

test "prepare downgrades unsupported user and tool images" {
    const input = [_]ai.ChatMessage{
        .{ .role = "user", .content = "look", .image_b64 = "AA==", .image_mime = "image/png" },
        .{ .role = "tool", .content = "captured", .tool_call_id = "c1", .tool_name = "shot", .image_b64 = "AQ==", .image_mime = "image/jpeg" },
    };
    var fixed = try prepare(std.testing.allocator, &input, .{ .supports_images = false });
    defer fixed.deinit();
    try std.testing.expectEqual(@as(usize, 2), fixed.messages.items.len);
    try std.testing.expect(fixed.messages.items[0].image_b64 == null);
    try std.testing.expect(std.mem.indexOf(u8, fixed.messages.items[0].content, USER_IMAGE_OMITTED) != null);
    try std.testing.expect(fixed.messages.items[1].image_b64 == null);
    try std.testing.expect(std.mem.indexOf(u8, fixed.messages.items[1].content, TOOL_IMAGE_OMITTED) != null);
}

test "prepare preserves images for vision models" {
    const input = [_]ai.ChatMessage{.{ .role = "user", .content = "look", .image_b64 = "AA==", .image_mime = "image/png" }};
    var fixed = try prepare(std.testing.allocator, &input, .{ .supports_images = true });
    defer fixed.deinit();
    try std.testing.expectEqualStrings("AA==", fixed.messages.items[0].image_b64.?);
    try std.testing.expectEqualStrings("look", fixed.messages.items[0].content);
}

test "prepare strips opaque thinking and tool signatures across model identity" {
    const calls = "[{\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{}\"},\"thoughtSignature\":\"opaque\"}]";
    const input = [_]ai.ChatMessage{.{
        .role = "assistant",
        .content = "answer",
        .provider = "google",
        .api = "google-generative-ai",
        .model = "gemini-old",
        .thinking = "private plan",
        .thinking_signature = "sig",
        .tool_calls_json = calls,
    }};
    var cross = try prepare(std.testing.allocator, &input, .{
        .target_provider = "anthropic",
        .target_api = "anthropic-messages",
        .target_model = "claude-new",
    });
    defer cross.deinit();
    const msg = cross.messages.items[0];
    try std.testing.expect(msg.thinking == null);
    try std.testing.expect(msg.thinking_signature == null);
    try std.testing.expect(std.mem.indexOf(u8, msg.content, "private plan") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg.tool_calls_json.?, "thoughtSignature") == null);

    var same = try prepare(std.testing.allocator, &input, .{
        .target_provider = "google",
        .target_api = "google-generative-ai",
        .target_model = "gemini-old",
    });
    defer same.deinit();
    try std.testing.expectEqualStrings("sig", same.messages.items[0].thinking_signature.?);
    try std.testing.expect(std.mem.indexOf(u8, same.messages.items[0].tool_calls_json.?, "thoughtSignature") != null);
}

test "prepare normalizes cross-model tool ids and matching results" {
    const raw_id = "call|foreign/+very-long-id-that-exceeds-anthropic-sixty-four-character-limit-1234567890";
    const calls = "[{\"id\":\"call|foreign/+very-long-id-that-exceeds-anthropic-sixty-four-character-limit-1234567890\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{}\"}}]";
    const input = [_]ai.ChatMessage{
        .{ .role = "assistant", .content = "", .provider = "openai", .api = "openai-responses", .model = "gpt-old", .tool_calls_json = calls },
        .{ .role = "tool", .content = "ok", .tool_call_id = raw_id, .tool_name = "read" },
    };
    var fixed = try prepare(std.testing.allocator, &input, .{
        .target_provider = "anthropic",
        .target_api = "anthropic-messages",
        .target_model = "claude-new",
        .tool_id_mode = .sanitize64,
    });
    defer fixed.deinit();
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, fixed.messages.items[0].tool_calls_json.?, .{});
    defer parsed.deinit();
    const normalized = parsed.value.array.items[0].object.get("id").?.string;
    try std.testing.expect(normalized.len <= 64);
    try std.testing.expect(std.mem.indexOfAny(u8, normalized, "|/+") == null);
    try std.testing.expectEqualStrings(normalized, fixed.messages.items[1].tool_call_id.?);
}
