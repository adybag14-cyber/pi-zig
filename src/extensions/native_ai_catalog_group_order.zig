//! Declaration order of API groups in the unchanged original provider data.
//! flattenModelCatalog visits these groups before their already ordered rows.
//! These are data labels; operation dispatch remains the actual API module map.
const std = @import("std");
pub const Entry = struct { provider: []const u8, apis: []const []const u8 };
pub const entries = [_]Entry{
    .{ .provider = "azure", .apis = &.{ "azure-openai-responses", "openai-completions" } },
    .{ .provider = "cloudflare-ai-gateway", .apis = &.{ "anthropic-messages", "openai-completions", "openai-responses" } },
    .{ .provider = "cloudflare-workers-ai", .apis = &.{ "cloudflare-workers-ai-system-one", "openai-completions" } },
    .{ .provider = "fireworks", .apis = &.{ "anthropic-messages", "openai-completions" } },
    .{ .provider = "github-copilot", .apis = &.{ "anthropic-messages", "openai-completions", "openai-responses" } },
    .{ .provider = "openai", .apis = &.{ "openai-decisions", "openai-responses" } },
    .{ .provider = "opencode-go", .apis = &.{ "anthropic-messages", "google-generative-ai", "openai-completions", "openai-responses" } },
    .{ .provider = "opencode", .apis = &.{ "anthropic-messages", "google-generative-ai", "openai-completions", "openai-responses", "typesafe-system-one" } },
    .{ .provider = "openrouter", .apis = &.{ "anthropic-messages", "openai-completions", "openrouter-images", "typesafe-system-one" } },
    .{ .provider = "vercel-ai-gateway", .apis = &.{ "anthropic-messages", "typesafe-system-one" } },
};
pub fn grouped(provider: []const u8) bool {
    for (entries) |entry| if (std.mem.eql(u8, provider, entry.provider)) return true;
    return false;
}
