//! Cloudflare provider routing/auth compatibility shared by native transports.
const std = @import("std");
const metadata = @import("request_metadata.zig");

pub const workers_ai_base_url = "https://api.cloudflare.com/client/v4/accounts/{CLOUDFLARE_ACCOUNT_ID}/ai/v1";
pub const gateway_compat_base_url = "https://gateway.ai.cloudflare.com/v1/{CLOUDFLARE_ACCOUNT_ID}/{CLOUDFLARE_GATEWAY_ID}/compat";
pub const gateway_openai_base_url = "https://gateway.ai.cloudflare.com/v1/{CLOUDFLARE_ACCOUNT_ID}/{CLOUDFLARE_GATEWAY_ID}/openai";
pub const gateway_anthropic_base_url = "https://gateway.ai.cloudflare.com/v1/{CLOUDFLARE_ACCOUNT_ID}/{CLOUDFLARE_GATEWAY_ID}/anthropic";

pub fn isWorkersAI(provider_id: []const u8) bool {
    return std.ascii.eqlIgnoreCase(provider_id, "cloudflare-workers-ai");
}

pub fn isAIGateway(provider_id: []const u8) bool {
    return std.ascii.eqlIgnoreCase(provider_id, "cloudflare-ai-gateway");
}

pub fn isWorkersGatewayModel(provider_id: []const u8, model_id: []const u8) bool {
    return isAIGateway(provider_id) and std.mem.startsWith(u8, model_id, "workers-ai/");
}

/// Upstream applies conservative OpenAI-compatible defaults to Cloudflare's
/// unified /compat endpoint. Explicit model/provider compat remains strongest.
pub fn applyCompatDefaults(provider_id: []const u8, model_id: []const u8, explicit: metadata.Compat) metadata.Compat {
    var defaults: metadata.Compat = .{};
    if (isAIGateway(provider_id)) {
        defaults = .{
            .supports_store = false,
            .supports_developer_role = false,
            .supports_reasoning_effort = false,
            .supports_usage_in_streaming = true,
            .supports_finish_reason = true,
            .supports_strict_mode = false,
            .max_tokens_field = .max_tokens,
        };
    } else if (isWorkersAI(provider_id)) {
        defaults = .{
            .supports_store = false,
            .supports_developer_role = false,
            .supports_reasoning_effort = true,
            .supports_usage_in_streaming = true,
            .supports_finish_reason = true,
            .supports_strict_mode = true,
        };
    }
    if (isWorkersAI(provider_id) or isWorkersGatewayModel(provider_id, model_id)) {
        defaults.send_session_affinity_headers = true;
        defaults.session_affinity_format = .openai;
    }
    return metadata.Compat.merge(defaults, explicit);
}

test "gateway compat is conservative and explicit values win" {
    const got = applyCompatDefaults("cloudflare-ai-gateway", "workers-ai/@cf/test", .{ .supports_strict_mode = true });
    try std.testing.expectEqual(false, got.supports_store.?);
    try std.testing.expectEqual(false, got.supports_reasoning_effort.?);
    try std.testing.expectEqual(true, got.supports_strict_mode.?);
    try std.testing.expect(got.max_tokens_field.? == .max_tokens);
    try std.testing.expectEqual(true, got.send_session_affinity_headers.?);
}
