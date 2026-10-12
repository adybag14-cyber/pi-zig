//! Model catalog for models actually represented by the native provider layer.
const std = @import("std");
const providers = @import("providers.zig");

pub const ModelInfo = providers.ModelInfo;
pub const models = providers.known_models;

pub fn count() usize {
    return models.len;
}

pub fn find(provider: providers.Provider, id: []const u8) ?ModelInfo {
    for (models) |m| if (m.provider == provider and std.mem.eql(u8, m.id, id)) return m;
    return null;
}

pub fn matches(m: ModelInfo, query: ?[]const u8) bool {
    const q = query orelse return true;
    return std.mem.indexOf(u8, m.id, q) != null or
        std.mem.indexOf(u8, m.display, q) != null or
        std.mem.indexOf(u8, m.providerName(), q) != null;
}

test "catalog contains only real provider entries" {
    try std.testing.expect(count() == providers.known_models.len);
    try std.testing.expect(find(.mock, "mock") != null);
}

test "latest pinned Pi 19cb catalog retains cardinality schema provenance and all model metadata" {
    const generated = @import("catalog_generated.zig");
    const gpa = std.testing.allocator;
    const source = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("catalog_source.json"), .{});
    defer source.deinit();
    const root = source.value.object;
    try std.testing.expectEqual(@as(i64, 2), root.get("schemaVersion").?.integer);
    try std.testing.expectEqualStrings("19cb534c3b6e3871458a8fa59e98f0312c50e995", generated.upstream_commit);
    try std.testing.expectEqualStrings("1.1.0", generated.upstream_version);
    try std.testing.expectEqualStrings("439c53478c84ed27a58f8b54e1c3bd45810e5a969515b4e3666a3898d51ee22f", generated.catalog_sha256);
    try std.testing.expectEqualStrings("5da1185d5c3bd4ba55618c38ee0524defd5cb0797c9aaa0ead7507387472f2f0", generated.upstream_source_archive_sha256);
    try std.testing.expectEqual(@as(usize, 1631), generated.all_model_count);
    try std.testing.expectEqual(@as(usize, 1544), generated.model_count);
    try std.testing.expectEqual(@as(usize, 42), generated.provider_count);

    var chat: usize = 0;
    var image: usize = 0;
    var classifier: usize = 0;
    const original_models = root.get("models").?.array.items;
    try std.testing.expectEqual(generated.all_model_count, original_models.len);
    for (original_models, providers.all_models[0..generated.all_model_count]) |original, model| {
        const serialized = try std.json.Stringify.valueAlloc(gpa, original, .{});
        defer gpa.free(serialized);
        try std.testing.expectEqualStrings(serialized, model.source_metadata_json.?);
        try std.testing.expectEqualStrings(original.object.get("provider").?.string, model.providerName());
        try std.testing.expectEqualStrings(original.object.get("id").?.string, model.id);
        switch (model.kind) {
            .chat => chat += 1,
            .image => image += 1,
            .classifier => classifier += 1,
        }
    }
    try std.testing.expectEqual(@as(usize, 1544), chat);
    try std.testing.expectEqual(@as(usize, 61), image);
    try std.testing.expectEqual(@as(usize, 26), classifier);
}

test "latest pinned Pi 19cb model lookup includes additions removes retired entries and updates pricing" {
    const resolver = @import("../coding_agent/model_resolver.zig");
    for ([_][]const u8{
        "opencode/fledge-alpha-free",
        "openrouter/inclusionai/ling-3.0-flash-sante:free",
        "openrouter/sao10k/l3.1-euryale-70b",
        "vercel-ai-gateway/deepseek/deepseek-v3.1-terminus",
        "vercel-ai-gateway/deepseek/deepseek-v4.1-flash-fast",
        "vercel-ai-gateway/moonshotai/kimi-k2-thinking",
        "vercel-ai-gateway/stepfun/step-3.5-flash",
    }) |reference| try std.testing.expect(resolver.findExactModelReferenceMatch(reference, &models) != null);
    for ([_][]const u8{
        "anthropic/claude-haiku-5-5",
        "mistral/codestral-2508",
        "opencode/step-5-preview-free",
        "openrouter/inclusionai/ling-3.0-flash-sante",
        "vercel-ai-gateway/stealth/glyph-cluster",
    }) |reference| try std.testing.expect(resolver.findExactModelReferenceMatch(reference, &models) == null);

    const free = resolver.findExactModelReferenceMatch("opencode/fledge-alpha-free", &models).?;
    try std.testing.expectEqualStrings("opencode", free.providerName());
    try std.testing.expect(free.reasoning and free.input_image);
    try std.testing.expectEqual(@as(u64, 1_048_576), free.context_window);
    try std.testing.expectEqual(@as(u64, 131_072), free.max_tokens);
    try std.testing.expectEqual(@as(f64, 0), free.cost.input);
    try std.testing.expectEqual(@as(f64, 0), free.cost.output);
    try std.testing.expect(free.thinking_level_map.?.off == .unsupported);
    const sonnet = resolver.findExactModelReferenceMatch("anthropic/claude-sonnet-5-5", &models).?;
    try std.testing.expectApproxEqAbs(@as(f64, 0.2), sonnet.cost.cache_read, 0.000001);

    // The newly named classifier belongs to the operation catalog, while
    // ordinary CLI model resolution continues to use the chat catalog.
    try std.testing.expect(resolver.findExactModelReferenceMatch("openrouter/perplexity/pplx-decider-v1-27b", &models) == null);
    var decision: ?ModelInfo = null;
    for (providers.all_models) |model| {
        if (std.mem.eql(u8, model.providerName(), "openrouter") and std.mem.eql(u8, model.id, "perplexity/pplx-decider-v1-27b")) decision = model;
    }
    try std.testing.expect(decision != null);
    try std.testing.expectEqual(providers.ModelType.classifier, decision.?.kind);
    try std.testing.expectEqualStrings("typesafe-system-one", decision.?.apiName());
    try std.testing.expectEqual(@as(u64, 262_144), decision.?.context_window);
    try std.testing.expectApproxEqAbs(@as(f64, 0.04), decision.?.cost.input, 0.000001);
}
