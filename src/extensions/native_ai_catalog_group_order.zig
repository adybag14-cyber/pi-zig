//! Declaration order of API groups in the unchanged original provider data.
//! flattenModelCatalog visits these groups before their already ordered rows.
//! These are data labels; operation dispatch remains the actual API module map.
const std = @import("std");
// Refreshing either normalized data or its original-file manifest requires a
// new reviewed group census. Stale declarations fail before publication.
pub const normalized_source_sha256 = "ae489e497f78c88566dc7fd50bb5ae34a359550c3ba81d50d0d3b2e3a11852db";
pub const builtin_manifest_sha256 = "05a7f9b7d8fc9a28018f38c6ebb4b0321e3c3685fd6bed191730d5b32d9e60af";
pub const source_provider_count: usize = 42;
pub const source_model_count: usize = 1705;
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
pub fn requireDeclaredApi(provider: []const u8, api: []const u8) !void {
    for (entries) |entry| {
        if (!std.mem.eql(u8, provider, entry.provider)) continue;
        for (entry.apis) |declared| if (std.mem.eql(u8, api, declared)) return;
        return error.CanonicalCatalogApiGroupOrderMissing;
    }
}
pub fn validateAuthority(source: []const u8, manifest: []const u8) !void {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(source, &digest, .{});
    const source_hex = std.fmt.bytesToHex(digest, .lower);
    if (!std.mem.eql(u8, &source_hex, normalized_source_sha256)) return error.CatalogGroupOrderSourceChanged;
    std.crypto.hash.sha2.Sha256.hash(manifest, &digest, .{});
    const manifest_hex = std.fmt.bytesToHex(digest, .lower);
    if (!std.mem.eql(u8, &manifest_hex, builtin_manifest_sha256)) return error.CatalogGroupOrderManifestChanged;
}
test "catalog group order rejects new API labels instead of dropping models" {
    try requireDeclaredApi("azure", "azure-openai-responses");
    try requireDeclaredApi("azure", "openai-completions");
    try std.testing.expectError(error.CanonicalCatalogApiGroupOrderMissing, requireDeclaredApi("azure", "future-api"));
    try std.testing.expectError(error.CatalogGroupOrderSourceChanged, validateAuthority("changed input", "changed manifest"));
}
