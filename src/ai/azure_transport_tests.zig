//! Azure contracts verified on actual loopback HTTP requests, without an SDK.
const std = @import("std");
const ai = @import("root.zig");
const fixture = @import("http_fixture.zig");

fn model(provider_id: []const u8, id: []const u8) !ai.providers.ModelInfo {
    for (ai.providers.known_models) |row| {
        if (std.mem.eql(u8, row.providerName(), provider_id) and std.mem.eql(u8, row.id, id)) return row;
    }
    return error.MissingAzureFixtureModel;
}

const HookState = struct { seen: bool = false };
fn payloadHook(context: ?*anyopaque, gpa: std.mem.Allocator, payload: []const u8, identity: ai.PayloadModel) !?[]u8 {
    const state: *HookState = @ptrCast(@alignCast(context.?));
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, payload, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("my-deepseek", parsed.value.object.get("model").?.string);
    try std.testing.expectEqualStrings("deepseek-v4-pro", identity.id);
    try std.testing.expectEqualStrings("azure", identity.provider);
    try std.testing.expectEqualStrings("openai-completions", identity.api);
    state.seen = true;
    try parsed.value.object.put(parsed.arena.allocator(), "temperature", .{ .float = 0.1 });
    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();
    try std.json.Stringify.value(parsed.value, .{}, &output.writer);
    return try output.toOwnedSlice();
}

test "Azure Chat Completions sends deployment before caller payload hook with native headers and canonical identity" {
    const gpa = std.testing.allocator;
    const row = try model("azure", "deepseek-v4-pro");
    try std.testing.expectEqual(ai.api.Api.openai_completions, row.apiKind());
    const response = "{\"model\":\"backend-deployment\",\"choices\":[{\"finish_reason\":\"stop\",\"message\":{\"role\":\"assistant\",\"content\":\"ok\"}}]}";
    const server = try fixture.PlanServer.init(gpa, std.testing.io, &.{
        .{ .path = "/azure/v1/chat/completions?tenant=test", .body = response, .expected_request_headers = &.{ .{ .name = "authorization", .value = "Bearer test-key" }, .{ .name = "x-layer", .value = "request" } } },
        .{ .path = "/azure/v1/chat/completions?tenant=test", .body = response, .expected_request_headers = &.{.{ .name = "authorization", .value = "Bearer test-key" }} },
    });
    defer server.deinit();
    const url = try server.url(gpa, "/azure/v1?tenant=test");
    defer gpa.free(url);
    var environ: std.process.Environ.Map = .init(gpa);
    defer environ.deinit();
    try environ.put("AZURE_OPENAI_BASE_URL", url);
    try environ.put("AZURE_OPENAI_DEPLOYMENT_NAME_MAP", "deepseek-v4-pro=my-deepseek");
    try environ.put("PI_CACHE_RETENTION", "long");
    var client: ai.openai.OpenAIClient = .{
        .gpa = gpa,
        .io = std.testing.io,
        .environ = &environ,
        .api_key = "test-key",
        .base_url = "",
        .provider_id = "azure",
        .model = row.id,
        .thinking = .max,
        .reasoning = row.reasoning,
        .thinking_level_map = row.thinking_level_map,
        .compat = row.compat,
        .session_id = "session-env",
        .cache_retention = .long,
        .custom_headers = &.{.{ .name = "X-Layer", .value = "model" }},
        .provider_retry = .{ .max_retries = 0, .timeout_ms = 5000 },
    };
    const messages = [_]ai.ChatMessage{
        .{ .role = "system", .content = "sys" },                                                                                                                     .{ .role = "user", .content = "hi" },
        .{ .role = "assistant", .content = "previous answer", .thinking = "internal reasoning", .provider = "azure", .api = "openai-completions", .model = row.id }, .{ .role = "system", .content = "late instruction" },
        .{ .role = "user", .content = "next" },
    };
    var hook: HookState = .{};
    var first = try client.client().completeWithOptions(gpa, &messages, "[]", .{ .on_payload = payloadHook, .on_payload_ctx = &hook, .headers = &.{.{ .name = "x-layer", .value = "request" }} });
    defer first.deinit(gpa);
    try std.testing.expect(hook.seen);
    try std.testing.expectEqualStrings(row.id, first.model);
    try std.testing.expectEqualStrings("azure", first.provider);
    try std.testing.expectEqualStrings("openai-completions", first.api);
    try std.testing.expectEqualStrings("backend-deployment", first.response_model);
    client.thinking = .off;
    var second = try client.client().complete(gpa, &messages, "[]");
    defer second.deinit(gpa);
    try server.finish();
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, server.captured.items[0].payload, .{});
    defer parsed.deinit();
    const payload = parsed.value.object;
    try std.testing.expectEqualStrings("my-deepseek", payload.get("model").?.string);
    try std.testing.expectEqualStrings("high", payload.get("reasoning_effort").?.string);
    try std.testing.expect(payload.get("thinking") == null and payload.get("prompt_cache_key") == null and payload.get("prompt_cache_retention") == null);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1), payload.get("temperature").?.float, 0.00001);
    const sent = payload.get("messages").?.array.items;
    try std.testing.expectEqualStrings("system", sent[0].object.get("role").?.string);
    try std.testing.expectEqualStrings("internal reasoning", sent[2].object.get("reasoning_content").?.string);
    try std.testing.expectEqualStrings("late instruction", sent[3].object.get("content").?.string);
    var disabled = try std.json.parseFromSlice(std.json.Value, gpa, server.captured.items[1].payload, .{});
    defer disabled.deinit();
    try std.testing.expect(disabled.value.object.get("reasoning_effort") == null and disabled.value.object.get("thinking") == null);
    try std.testing.expectEqualStrings(row.id, client.model);
}

test "Azure Responses uses native api-key API version deployment and request header precedence" {
    const gpa = std.testing.allocator;
    const response = "{\"id\":\"resp_azure\",\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"ok\"}]}]}";
    const server = try fixture.PlanServer.init(gpa, std.testing.io, &.{
        .{ .path = "/gateway/v1/responses?tenant=test&api-version=env-version", .body = response, .expected_request_headers = &.{ .{ .name = "api-key", .value = "azure-key" }, .{ .name = "x-layer", .value = "request" } } },
    });
    defer server.deinit();
    const url = try server.url(gpa, "/gateway/v1?tenant=test");
    defer gpa.free(url);
    var environ: std.process.Environ.Map = .init(gpa);
    defer environ.deinit();
    try environ.put("AZURE_OPENAI_BASE_URL", url);
    try environ.put("AZURE_OPENAI_API_VERSION", "env-version");
    try environ.put("AZURE_OPENAI_DEPLOYMENT_NAME_MAP", "gpt-5.4=my-gpt");
    var client: ai.openai_responses.ResponsesClient = .{
        .gpa = gpa,
        .io = std.testing.io,
        .environ = &environ,
        .api_key = "azure-key",
        .base_url = "",
        .provider_id = "azure",
        .model = "gpt-5.4",
        .protocol_mode = .azure,
        .auth_mode = .azure_api_key,
        .custom_headers = &.{.{ .name = "X-Layer", .value = "model" }},
        .provider_retry = .{ .max_retries = 0, .timeout_ms = 5000 },
    };
    defer client.deinit();
    const messages = [_]ai.ChatMessage{.{ .role = "user", .content = "hello" }};
    var result = try client.client().completeWithOptions(gpa, &messages, "[]", .{ .headers = &.{.{ .name = "x-layer", .value = "request" }} });
    defer result.deinit(gpa);
    try server.finish();
    try std.testing.expectEqualStrings("gpt-5.4", result.model);
    try std.testing.expectEqualStrings("azure", result.provider);
    try std.testing.expectEqualStrings("azure-openai-responses", result.api);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, server.captured.items[0].payload, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("my-gpt", parsed.value.object.get("model").?.string);
    try std.testing.expect(!parsed.value.object.get("store").?.bool);
}

test "Azure configuration failures return native stream error events with stable catalog identities" {
    const gpa = std.testing.allocator;
    var environ: std.process.Environ.Map = .init(gpa);
    defer environ.deinit();
    var client: ai.openai.OpenAIClient = .{ .gpa = gpa, .io = std.testing.io, .environ = &environ, .api_key = "key", .base_url = "", .provider_id = "azure", .model = "deepseek-v4-pro" };
    const messages = [_]ai.ChatMessage{.{ .role = "user", .content = "hello" }};
    var result = try client.client().completeStreaming(gpa, &messages, "[]", null, null);
    defer result.deinit(gpa);
    try std.testing.expectEqualStrings("error", result.stop_reason);
    try std.testing.expectEqualStrings(client.model, result.model);
    try std.testing.expect(std.mem.indexOf(u8, result.error_message, "Azure OpenAI base URL is required") != null);
    try environ.put("AZURE_OPENAI_BASE_URL", "invalid-base-url");
    var invalid = try client.client().complete(gpa, &messages, "[]");
    defer invalid.deinit(gpa);
    try std.testing.expectEqualStrings("error", invalid.stop_reason);
    try std.testing.expect(std.mem.indexOf(u8, invalid.error_message, "Invalid Azure OpenAI base URL") != null);
}
