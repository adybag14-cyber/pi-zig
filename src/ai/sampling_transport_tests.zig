//! Pi 1.0.2 sampling contracts verified through real native HTTP requests.
const std = @import("std");
const ai = @import("root.zig");
const metadata = @import("request_metadata.zig");
const fixture = @import("http_fixture.zig");

fn levels() metadata.SamplingParamsByThinkingLevel {
    var result: metadata.SamplingParamsByThinkingLevel = .{};
    result.levels[@intFromEnum(ai.ThinkingLevel.high)].base = &.{
        .{ .name = "temperature", .value_json = "0.6" },
        .{ .name = "top_k", .value_json = "64" },
        .{ .name = "vendor", .value_json = "{\"nested\":[false,null]}" },
    };
    result.levels[0].base = &.{.{ .name = "temperature", .value_json = "0.1" }};
    return result;
}

const defaults = [_]metadata.SamplingParam{
    .{ .name = "temperature", .value_json = "1" },
    .{ .name = "top_p", .value_json = "0.95" },
};
const requested = [_]metadata.SamplingParam{.{ .name = "top_p", .value_json = "0.5" }};

fn checkPayload(gpa: std.mem.Allocator, raw: []const u8, enabled: bool) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    const object = parsed.value.object;
    try std.testing.expectEqual(@as(f64, if (enabled) 0.6 else 0.1), object.get("temperature").?.float);
    try std.testing.expectEqual(@as(f64, 0.5), object.get("top_p").?.float);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, raw, "\"temperature\":"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, raw, "\"top_p\":"));
    if (enabled) {
        try std.testing.expectEqual(@as(i64, 64), object.get("top_k").?.integer);
        const nested = object.get("vendor").?.object.get("nested").?.array.items;
        try std.testing.expect(!nested[0].bool and nested[1] == .null);
    } else try std.testing.expect(object.get("top_k") == null);
}

test "native chat transport resolves clamped thinking defaults on every request" {
    const gpa = std.testing.allocator;
    const response = "{\"choices\":[{\"finish_reason\":\"stop\",\"message\":{\"role\":\"assistant\",\"content\":\"ok\"}}]}";
    const server = try fixture.PlanServer.init(gpa, std.testing.io, &.{
        .{ .path = "/v1/chat/completions", .body = response },
        .{ .path = "/v1/chat/completions", .body = response },
    });
    defer server.deinit();
    const url = try server.url(gpa, "/v1");
    defer gpa.free(url);
    var env: std.process.Environ.Map = .init(gpa);
    defer env.deinit();
    var client: ai.openai.OpenAIClient = .{
        .gpa = gpa,
        .io = std.testing.io,
        .environ = &env,
        .api_key = "offline",
        .base_url = url,
        .model = "m",
        .reasoning = true,
        .thinking = .low,
        .thinking_level_map = .{ .low = .unsupported, .medium = .unsupported },
        .sampling_params = &defaults,
        .sampling_params_by_thinking_level = levels(),
    };
    const messages = [_]ai.ChatMessage{.{ .role = "user", .content = "hello" }};
    var first = try client.client().completeWithOptions(gpa, &messages, "[]", .{ .sampling_params = &requested });
    defer first.deinit(gpa);
    try std.testing.expectEqualStrings("ok", first.content);
    client.reasoning = false;
    var second = try client.client().completeWithOptions(gpa, &messages, "[]", .{ .sampling_params = &requested });
    defer second.deinit(gpa);
    try server.finish();
    try checkPayload(gpa, server.captured.items[0].payload, true);
    try checkPayload(gpa, server.captured.items[1].payload, false);
}

test "native Responses and Azure transports retain thinking sampling and request precedence" {
    const gpa = std.testing.allocator;
    const response = "{\"id\":\"resp_offline\",\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"ok\"}]}]}";
    const server = try fixture.PlanServer.init(gpa, std.testing.io, &.{
        .{ .path = "/v1/responses", .body = response },
        .{ .path = "/v1/responses?api-version=2025-04-01-preview", .body = response },
    });
    defer server.deinit();
    const url = try server.url(gpa, "/v1");
    defer gpa.free(url);
    var env: std.process.Environ.Map = .init(gpa);
    defer env.deinit();
    var client: ai.openai_responses.ResponsesClient = .{
        .gpa = gpa,
        .io = std.testing.io,
        .environ = &env,
        .api_key = "offline",
        .base_url = url,
        .model = "m",
        .reasoning = true,
        .thinking = .max,
        .sampling_params = &defaults,
        .sampling_params_by_thinking_level = levels(),
    };
    defer client.deinit();
    const messages = [_]ai.ChatMessage{.{ .role = "user", .content = "hello" }};
    var first = try client.client().completeWithOptions(gpa, &messages, "[]", .{ .sampling_params = &requested });
    defer first.deinit(gpa);
    try std.testing.expectEqualStrings("ok", first.content);
    client.protocol_mode = .azure;
    client.auth_mode = .azure_api_key;
    client.api_version = "2025-04-01-preview";
    var second = try client.client().completeWithOptions(gpa, &messages, "[]", .{ .sampling_params = &requested });
    defer second.deinit(gpa);
    try server.finish();
    try checkPayload(gpa, server.captured.items[0].payload, true);
    try checkPayload(gpa, server.captured.items[1].payload, true);
    try std.testing.expectEqualStrings("azure-openai-responses", second.api);
}
