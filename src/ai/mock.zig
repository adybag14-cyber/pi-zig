//! Scripted mock model from JSON file.
const std = @import("std");
const ai = @import("root.zig");

pub const MockModel = struct {
    responses: []ai.ModelResponse,
    index: usize = 0,

    pub fn client(self: *MockModel) ai.ModelClient {
        return .{
            .ptr = self,
            .completeFn = completeImpl,
        };
    }

    fn completeImpl(ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8) anyerror!ai.ModelResponse {
        _ = messages;
        _ = tools_json;
        const self: *MockModel = @ptrCast(@alignCast(ptr));
        if (self.index >= self.responses.len) {
            return .{
                .content = try gpa.dupe(u8, "(mock exhausted)"),
                .tool_calls = try gpa.alloc(ai.ToolCall, 0),
            };
        }
        const src = self.responses[self.index];
        self.index += 1;
        var tcs = try gpa.alloc(ai.ToolCall, src.tool_calls.len);
        errdefer {
            for (tcs[0..]) |*tc| tc.deinit(gpa);
            gpa.free(tcs);
        }
        for (src.tool_calls, 0..) |tc, i| {
            tcs[i] = .{
                .id = try gpa.dupe(u8, tc.id),
                .name = try gpa.dupe(u8, tc.name),
                .arguments = try gpa.dupe(u8, tc.arguments),
            };
        }
        return .{
            .content = try gpa.dupe(u8, src.content),
            .tool_calls = tcs,
        };
    }

    pub fn deinit(self: *MockModel, gpa: std.mem.Allocator) void {
        for (self.responses) |*r| r.deinit(gpa);
        gpa.free(self.responses);
        self.* = undefined;
    }

    /// Format: [{"content":"...","tool_calls":[{"id":"...","name":"...","arguments":"{...}"}]}]
    pub fn loadFromJson(gpa: std.mem.Allocator, json_text: []const u8) !MockModel {
        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, json_text, .{});
        defer parsed.deinit();
        if (parsed.value != .array) return error.InvalidMockScript;

        var list: std.ArrayList(ai.ModelResponse) = .empty;
        errdefer {
            for (list.items) |*r| r.deinit(gpa);
            list.deinit(gpa);
        }

        for (parsed.value.array.items) |item| {
            if (item != .object) return error.InvalidMockScript;
            const content_v = item.object.get("content") orelse return error.InvalidMockScript;
            if (content_v != .string) return error.InvalidMockScript;

            var tcs: std.ArrayList(ai.ToolCall) = .empty;
            errdefer {
                for (tcs.items) |*tc| tc.deinit(gpa);
                tcs.deinit(gpa);
            }

            if (item.object.get("tool_calls")) |tc_val| {
                if (tc_val == .array) {
                    for (tc_val.array.items) |tc_item| {
                        if (tc_item != .object) return error.InvalidMockScript;
                        const id = tc_item.object.get("id") orelse return error.InvalidMockScript;
                        const name = tc_item.object.get("name") orelse return error.InvalidMockScript;
                        const args = tc_item.object.get("arguments") orelse return error.InvalidMockScript;
                        if (id != .string or name != .string or args != .string) return error.InvalidMockScript;
                        try tcs.append(gpa, .{
                            .id = try gpa.dupe(u8, id.string),
                            .name = try gpa.dupe(u8, name.string),
                            .arguments = try gpa.dupe(u8, args.string),
                        });
                    }
                }
            }

            try list.append(gpa, .{
                .content = try gpa.dupe(u8, content_v.string),
                .tool_calls = try tcs.toOwnedSlice(gpa),
            });
        }

        return .{
            .responses = try list.toOwnedSlice(gpa),
            .index = 0,
        };
    }
};

test "mock model returns scripted tool call then final" {
    const gpa = std.testing.allocator;
    const script =
        \\[
        \\  {"content":"calling write","tool_calls":[{"id":"c1","name":"write","arguments":"{\"path\":\"a.txt\",\"content\":\"x\"}"}]},
        \\  {"content":"all done","tool_calls":[]}
        \\]
    ;
    var m = try MockModel.loadFromJson(gpa, script);
    defer m.deinit(gpa);
    const c = m.client();

    var r1 = try c.complete(gpa, &.{}, "[]");
    defer r1.deinit(gpa);
    try std.testing.expectEqualStrings("calling write", r1.content);
    try std.testing.expectEqual(@as(usize, 1), r1.tool_calls.len);
    try std.testing.expectEqualStrings("write", r1.tool_calls[0].name);

    var r2 = try c.complete(gpa, &.{}, "[]");
    defer r2.deinit(gpa);
    try std.testing.expectEqualStrings("all done", r2.content);
    try std.testing.expectEqual(@as(usize, 0), r2.tool_calls.len);
}
