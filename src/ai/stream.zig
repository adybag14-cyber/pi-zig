//! Streaming parsers for OpenAI SSE and Anthropic Messages stream events.
//! Pure string fixtures — no network required for unit tests.
const std = @import("std");
const ai = @import("root.zig");

pub const StreamDeltaKind = enum {
    text_delta,
    tool_call_delta, // partial tool call (id/name/args fragments)
    done,
    err,
};

pub const StreamDelta = struct {
    kind: StreamDeltaKind,
    text: []const u8 = "",
    /// tool call id (owned by caller context, not this delta)
    tool_call_id: []const u8 = "",
    tool_name: []const u8 = "",
    /// JSON arguments fragment or full arguments so far
    tool_arguments: []const u8 = "",
};

pub const StreamHandler = *const fn (ctx: ?*anyopaque, delta: StreamDelta) void;

/// Accumulates stream deltas into a final ModelResponse.
pub const Accumulator = struct {
    gpa: std.mem.Allocator,
    text: std.ArrayList(u8) = .empty,
    /// tool_call_id -> building ToolCall
    tool_ids: std.ArrayList([]const u8) = .empty,
    tool_names: std.ArrayList([]const u8) = .empty,
    tool_args: std.ArrayList(std.ArrayList(u8)) = .empty,

    pub fn init(gpa: std.mem.Allocator) Accumulator {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Accumulator) void {
        self.text.deinit(self.gpa);
        for (self.tool_ids.items) |id| self.gpa.free(id);
        self.tool_ids.deinit(self.gpa);
        for (self.tool_names.items) |n| self.gpa.free(n);
        self.tool_names.deinit(self.gpa);
        for (self.tool_args.items) |*a| a.deinit(self.gpa);
        self.tool_args.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn onDelta(self: *Accumulator, delta: StreamDelta) !void {
        switch (delta.kind) {
            .text_delta => try self.text.appendSlice(self.gpa, delta.text),
            .tool_call_delta => {
                // Find or create tool call by id. Empty id continues the last open tool
                // (Anthropic input_json_delta streams without repeating id/name).
                var idx: ?usize = null;
                if (delta.tool_call_id.len > 0) {
                    for (self.tool_ids.items, 0..) |id, i| {
                        if (std.mem.eql(u8, id, delta.tool_call_id)) {
                            idx = i;
                            break;
                        }
                    }
                } else if (self.tool_ids.items.len > 0) {
                    idx = self.tool_ids.items.len - 1;
                }
                if (idx == null) {
                    try self.tool_ids.append(self.gpa, try self.gpa.dupe(u8, if (delta.tool_call_id.len > 0) delta.tool_call_id else "call_0"));
                    try self.tool_names.append(self.gpa, try self.gpa.dupe(u8, delta.tool_name));
                    try self.tool_args.append(self.gpa, .empty);
                    idx = self.tool_ids.items.len - 1;
                }
                const i = idx.?;
                if (delta.tool_name.len > 0 and self.tool_names.items[i].len == 0) {
                    self.gpa.free(self.tool_names.items[i]);
                    self.tool_names.items[i] = try self.gpa.dupe(u8, delta.tool_name);
                }
                if (delta.tool_arguments.len > 0) {
                    try self.tool_args.items[i].appendSlice(self.gpa, delta.tool_arguments);
                }
            },
            .done, .err => {},
        }
    }

    pub fn finish(self: *Accumulator) !ai.ModelResponse {
        var tcs = try self.gpa.alloc(ai.ToolCall, self.tool_ids.items.len);
        errdefer self.gpa.free(tcs);
        for (self.tool_ids.items, 0..) |id, i| {
            tcs[i] = .{
                .id = try self.gpa.dupe(u8, id),
                .name = try self.gpa.dupe(u8, self.tool_names.items[i]),
                .arguments = try self.gpa.dupe(u8, self.tool_args.items[i].items),
            };
        }
        return .{
            .content = try self.gpa.dupe(u8, self.text.items),
            .tool_calls = tcs,
        };
    }
};

/// Parse one OpenAI SSE data line body (content after "data: ").
/// Returns null for [DONE] or empty/ignore lines.
pub fn parseOpenAISseData(gpa: std.mem.Allocator, data: []const u8) !?StreamDelta {
    const trimmed = std.mem.trim(u8, data, " \t\r\n");
    if (trimmed.len == 0) return null;
    if (std.mem.eql(u8, trimmed, "[DONE]")) {
        return StreamDelta{ .kind = .done };
    }

    var parsed = std.json.parseFromSlice(std.json.Value, gpa, trimmed, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;

    const choices = parsed.value.object.get("choices") orelse return null;
    if (choices != .array or choices.array.items.len == 0) return null;
    const first = choices.array.items[0];
    if (first != .object) return null;

    if (first.object.get("delta")) |delta| {
        if (delta != .object) return null;
        if (delta.object.get("content")) |c| {
            if (c == .string and c.string.len > 0) {
                return StreamDelta{ .kind = .text_delta, .text = try gpa.dupe(u8, c.string) };
            }
        }
        if (delta.object.get("tool_calls")) |tcs| {
            if (tcs == .array and tcs.array.items.len > 0) {
                const tc = tcs.array.items[0];
                if (tc == .object) {
                    var id: []const u8 = "";
                    var name: []const u8 = "";
                    var args: []const u8 = "";
                    if (tc.object.get("id")) |v| {
                        if (v == .string) id = v.string;
                    }
                    if (tc.object.get("function")) |fn_obj| {
                        if (fn_obj == .object) {
                            if (fn_obj.object.get("name")) |n| {
                                if (n == .string) name = n.string;
                            }
                            if (fn_obj.object.get("arguments")) |a| {
                                if (a == .string) args = a.string;
                            }
                        }
                    }
                    return StreamDelta{
                        .kind = .tool_call_delta,
                        .tool_call_id = try gpa.dupe(u8, id),
                        .tool_name = try gpa.dupe(u8, name),
                        .tool_arguments = try gpa.dupe(u8, args),
                    };
                }
            }
        }
    }
    // finish_reason present
    if (first.object.get("finish_reason")) |fr| {
        if (fr == .string and fr.string.len > 0 and !std.mem.eql(u8, fr.string, "null")) {
            return StreamDelta{ .kind = .done };
        }
    }
    return null;
}

/// Free heap strings inside a StreamDelta allocated by parsers.
pub fn freeDelta(gpa: std.mem.Allocator, delta: StreamDelta) void {
    // Only free if we allocated (text_delta / tool fields from parsers)
    switch (delta.kind) {
        .text_delta => {
            if (delta.text.len > 0) gpa.free(delta.text);
        },
        .tool_call_delta => {
            if (delta.tool_call_id.len > 0) gpa.free(delta.tool_call_id);
            if (delta.tool_name.len > 0) gpa.free(delta.tool_name);
            if (delta.tool_arguments.len > 0) gpa.free(delta.tool_arguments);
        },
        else => {},
    }
}

/// Parse Anthropic SSE event: event name + data JSON.
pub fn parseAnthropicEvent(gpa: std.mem.Allocator, event_name: []const u8, data: []const u8) !?StreamDelta {
    const trimmed = std.mem.trim(u8, data, " \t\r\n");
    if (trimmed.len == 0) return null;

    if (std.mem.eql(u8, event_name, "message_stop") or std.mem.eql(u8, event_name, "content_block_stop")) {
        // content_block_stop is mid-stream; message_stop is done
        if (std.mem.eql(u8, event_name, "message_stop")) return StreamDelta{ .kind = .done };
        return null;
    }

    var parsed = std.json.parseFromSlice(std.json.Value, gpa, trimmed, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;

    if (std.mem.eql(u8, event_name, "content_block_delta")) {
        if (parsed.value.object.get("delta")) |d| {
            if (d == .object) {
                if (d.object.get("type")) |t| {
                    if (t == .string and std.mem.eql(u8, t.string, "text_delta")) {
                        if (d.object.get("text")) |tx| {
                            if (tx == .string) {
                                return StreamDelta{ .kind = .text_delta, .text = try gpa.dupe(u8, tx.string) };
                            }
                        }
                    }
                    if (t == .string and std.mem.eql(u8, t.string, "input_json_delta")) {
                        if (d.object.get("partial_json")) |pj| {
                            if (pj == .string) {
                                return StreamDelta{
                                    .kind = .tool_call_delta,
                                    .tool_arguments = try gpa.dupe(u8, pj.string),
                                };
                            }
                        }
                    }
                }
            }
        }
    }

    if (std.mem.eql(u8, event_name, "content_block_start")) {
        if (parsed.value.object.get("content_block")) |cb| {
            if (cb == .object) {
                if (cb.object.get("type")) |t| {
                    if (t == .string and std.mem.eql(u8, t.string, "tool_use")) {
                        const id = if (cb.object.get("id")) |v| (if (v == .string) v.string else "") else "";
                        const name = if (cb.object.get("name")) |v| (if (v == .string) v.string else "") else "";
                        return StreamDelta{
                            .kind = .tool_call_delta,
                            .tool_call_id = try gpa.dupe(u8, id),
                            .tool_name = try gpa.dupe(u8, name),
                        };
                    }
                }
            }
        }
    }

    return null;
}

/// Parse a multi-line OpenAI SSE fixture into accumulated ModelResponse.
pub fn consumeOpenAISseFixture(gpa: std.mem.Allocator, fixture: []const u8) !ai.ModelResponse {
    var acc = Accumulator.init(gpa);
    defer acc.deinit();

    var it = std.mem.splitScalar(u8, fixture, '\n');
    while (it.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, t, "data:")) {
            const data = std.mem.trim(u8, t["data:".len..], " \t");
            if (try parseOpenAISseData(gpa, data)) |delta| {
                defer freeDelta(gpa, delta);
                try acc.onDelta(delta);
            }
        }
    }
    return try acc.finish();
}

/// Parse Anthropic multi-event fixture (lines of "event: X" / "data: {...}").
pub fn consumeAnthropicSseFixture(gpa: std.mem.Allocator, fixture: []const u8) !ai.ModelResponse {
    var acc = Accumulator.init(gpa);
    defer acc.deinit();

    var current_event: []const u8 = "message";
    var event_owned: ?[]u8 = null;
    defer if (event_owned) |e| gpa.free(e);

    var it = std.mem.splitScalar(u8, fixture, '\n');
    while (it.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, t, "event:")) {
            if (event_owned) |e| gpa.free(e);
            event_owned = try gpa.dupe(u8, std.mem.trim(u8, t["event:".len..], " \t"));
            current_event = event_owned.?;
        } else if (std.mem.startsWith(u8, t, "data:")) {
            const data = std.mem.trim(u8, t["data:".len..], " \t");
            if (try parseAnthropicEvent(gpa, current_event, data)) |delta| {
                defer freeDelta(gpa, delta);
                try acc.onDelta(delta);
            }
        }
    }
    return try acc.finish();
}

test "OpenAI SSE fixture accumulates text and tool call" {
    const gpa = std.testing.allocator;
    const fixture =
        \\data: {"choices":[{"delta":{"content":"Hello "}}]}
        \\data: {"choices":[{"delta":{"content":"world"}}]}
        \\data: {"choices":[{"delta":{"tool_calls":[{"id":"c1","function":{"name":"read","arguments":"{\"p\""}}]}}]}
        \\data: {"choices":[{"delta":{"tool_calls":[{"id":"c1","function":{"arguments":":\"a\"}"}}]}}]}
        \\data: [DONE]
        \\
    ;
    var resp = try consumeOpenAISseFixture(gpa, fixture);
    defer resp.deinit(gpa);
    try std.testing.expectEqualStrings("Hello world", resp.content);
    try std.testing.expectEqual(@as(usize, 1), resp.tool_calls.len);
    try std.testing.expectEqualStrings("read", resp.tool_calls[0].name);
    try std.testing.expect(std.mem.indexOf(u8, resp.tool_calls[0].arguments, "a") != null);
}

test "Anthropic stream fixture accumulates text and tool_use" {
    const gpa = std.testing.allocator;
    const fixture =
        \\event: content_block_delta
        \\data: {"delta":{"type":"text_delta","text":"Using "}}
        \\event: content_block_delta
        \\data: {"delta":{"type":"text_delta","text":"tool"}}
        \\event: content_block_start
        \\data: {"content_block":{"type":"tool_use","id":"tu1","name":"bash"}}
        \\event: content_block_delta
        \\data: {"delta":{"type":"input_json_delta","partial_json":"{\"command\":"}}
        \\event: content_block_delta
        \\data: {"delta":{"type":"input_json_delta","partial_json":"\"echo hi\"}"}}
        \\event: message_stop
        \\data: {}
        \\
    ;
    var resp = try consumeAnthropicSseFixture(gpa, fixture);
    defer resp.deinit(gpa);
    try std.testing.expectEqualStrings("Using tool", resp.content);
    try std.testing.expectEqual(@as(usize, 1), resp.tool_calls.len);
    try std.testing.expectEqualStrings("bash", resp.tool_calls[0].name);
    try std.testing.expect(std.mem.indexOf(u8, resp.tool_calls[0].arguments, "echo hi") != null);
}
