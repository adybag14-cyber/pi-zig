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

test "latest pinned Pi ae7 FFA3 catalog retains cardinality schema provenance and all model metadata" {
    const generated = @import("catalog_generated.zig");
    const gpa = std.testing.allocator;
    const source = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("catalog_source.json"), .{});
    defer source.deinit();
    const root = source.value.object;
    try std.testing.expectEqual(@as(i64, 2), root.get("schemaVersion").?.integer);
    try std.testing.expectEqualStrings("ae7b16d43b7c78c5b6fa3213fdd1215bb339729d", generated.upstream_commit);
    try std.testing.expectEqualStrings("1.3.0", generated.upstream_version);
    try std.testing.expectEqualStrings("ffa3e98626230f378f80200debb736c4a2238b5f2ba246a92cfc7d8e19604678", generated.catalog_sha256);
    try std.testing.expectEqualStrings("cc12deecb13cc85cc52ce19806bd45bd6264911e3bb2bf7add5775e09a18ef37", generated.upstream_source_archive_sha256);
    try std.testing.expectEqual(@as(usize, 1705), generated.all_model_count);
    try std.testing.expectEqual(@as(usize, 1608), generated.model_count);
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
    try std.testing.expectEqual(@as(usize, 1608), chat);
    try std.testing.expectEqual(@as(usize, 59), image);
    try std.testing.expectEqual(@as(usize, 38), classifier);
}

test "latest pinned Pi ae7 FFA3 model lookup includes additions removes retired entries and updates pricing" {
    const resolver = @import("../coding_agent/model_resolver.zig");
    for ([_][]const u8{
        "anthropic/claude-haiku-5-5",
        "amazon-bedrock/anthropic.claude-haiku-5-5",
        "github-copilot/claude-haiku-5.5",
        "google/gemini-4-argon",
        "opencode/cat-jam-free",
        "opencode-go/grok-4.6",
        "opencode-go/minimax-m2.7",
        "openrouter/unbiased/pareto-26.10-preview",
    }) |reference| try std.testing.expect(resolver.findExactModelReferenceMatch(reference, &models) != null);
    for ([_][]const u8{
        "google-vertex/gemini-flash-latest",
        "nvidia/moonshotai/kimi-k3",
        "opencode/fledge-alpha-free",
        "openrouter/anthropic/claude-sonnet-4",
        "nvidia/nvidia/nemotron-3.5-super-vl-120b-a12b",
        "opencode/nemotron-3.5-super-vl-free",
        "openrouter/nvidia/nemotron-3.5-super-vl:free",
    }) |reference| try std.testing.expect(resolver.findExactModelReferenceMatch(reference, &models) == null);

    const free = resolver.findExactModelReferenceMatch("opencode/cat-jam-free", &models).?;
    try std.testing.expectEqualStrings("opencode", free.providerName());
    try std.testing.expect(free.reasoning and !free.input_image);
    try std.testing.expectEqual(@as(u64, 262_144), free.context_window);
    try std.testing.expectEqual(@as(u64, 131_072), free.max_tokens);
    try std.testing.expectEqual(@as(f64, 0), free.cost.input);
    try std.testing.expectEqual(@as(f64, 0), free.cost.output);
    try std.testing.expect(free.thinking_level_map.?.off == .unsupported);
    const sonnet = resolver.findExactModelReferenceMatch("anthropic/claude-sonnet-5-5", &models).?;
    try std.testing.expectApproxEqAbs(@as(f64, 0.1), sonnet.cost.cache_read, 0.000001);

    // The newly named classifier belongs to the operation catalog, while
    // ordinary CLI model resolution continues to use the chat catalog.
    try std.testing.expect(resolver.findExactModelReferenceMatch("openrouter/~perplexity/pplx-decider-latest", &models) == null);
    var decision: ?ModelInfo = null;
    for (providers.all_models) |model| {
        if (std.mem.eql(u8, model.providerName(), "openrouter") and std.mem.eql(u8, model.id, "~perplexity/pplx-decider-latest")) decision = model;
    }
    try std.testing.expect(decision != null);
    try std.testing.expectEqual(providers.ModelType.classifier, decision.?.kind);
    try std.testing.expectEqualStrings("typesafe-system-one", decision.?.apiName());
    try std.testing.expectEqual(@as(u64, 262_144), decision.?.context_window);
    try std.testing.expectApproxEqAbs(@as(f64, 0.02), decision.?.cost.input, 0.000001);
}

test "latest pinned Pi ae7 FFA3 catalog preserves disabled thinking and Kimi Chat Completions contracts" {
    const resolver = @import("../coding_agent/model_resolver.zig");
    // Upstream dc93991 permits disabled thinking for Haiku 5.5 and Opus 5.
    // Explicit null and omitted entries must remain distinct in native metadata.
    for ([_][]const u8{ "anthropic/claude-haiku-5-5", "anthropic/claude-opus-5" }) |reference| {
        const model = resolver.findExactModelReferenceMatch(reference, &models).?;
        try std.testing.expect(model.compat.supports_mid_convo_effort.?);
        try std.testing.expect(model.thinking_level_map.?.off == .absent);
    }
    for ([_][]const u8{ "anthropic/claude-opus-5-5", "anthropic/claude-sonnet-5-5" }) |reference| {
        const model = resolver.findExactModelReferenceMatch(reference, &models).?;
        try std.testing.expect(model.thinking_level_map.?.off == .unsupported);
    }
    for ([_][]const u8{ "k3", "k3-256k", "kimi-for-coding", "kimi-for-coding-highspeed" }) |id| {
        var model: ?ModelInfo = null;
        for (models) |candidate| if (std.mem.eql(u8, candidate.providerName(), "kimi-coding") and std.mem.eql(u8, candidate.id, id)) {
            model = candidate;
            break;
        };
        try std.testing.expectEqualStrings("openai-completions", model.?.apiName());
        try std.testing.expectEqualStrings("https://api.kimi.com/coding/v1", model.?.base_url.?);
        try std.testing.expect(model.?.compat.supports_mid_convo_system_messages.?);
        if (!std.mem.eql(u8, id, "kimi-for-coding-highspeed")) {
            try std.testing.expect(model.?.compat.requires_reasoning_content_on_assistant_messages.?);
            try std.testing.expect(model.?.compat.supports_mid_convo_tool_additions.?);
        }
    }
}

test "latest pinned Pi ae7 FFA3 full typed input metadata and official builtin manifest remain exact" {
    const gpa = std.testing.allocator;
    const typed = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("../../verification/upstream-ae7-ffa3-20261015/models.all.json"), .{});
    defer typed.deinit();
    var index: usize = 0;
    var api_names: std.StringHashMap(void) = .init(gpa);
    defer api_names.deinit();
    var entries = typed.value.object.iterator();
    try std.testing.expectEqual(@as(usize, 42), typed.value.object.count());
    while (entries.next()) |entry| {
        for (entry.value_ptr.array.items) |original| {
            const model = providers.all_models[index];
            const serialized = try std.json.Stringify.valueAlloc(gpa, original, .{});
            defer gpa.free(serialized);
            try std.testing.expectEqualStrings(serialized, model.source_metadata_json.?);
            try std.testing.expectEqualStrings(entry.key_ptr.*, model.providerName());
            if (model.kind == .chat) try api_names.put(model.apiName(), {});
            try std.testing.expect(!(std.mem.eql(u8, model.providerName(), "vercel-ai-gateway") and
                (std.mem.eql(u8, model.id, "typesafe-ai/jev-1.13.0") or std.mem.eql(u8, model.id, "typesafe-ai/jev-1.14.0"))));
            index += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1705), index);
    try std.testing.expectEqual(@as(usize, 10), api_names.count());
    const manifest = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("catalog_builtin_manifest.json"), .{});
    defer manifest.deinit();
    try std.testing.expectEqual(@as(i64, 6), manifest.value.object.get("schemaVersion").?.integer);
    try std.testing.expectEqualStrings("1970-01-01T00:00:00.000Z", manifest.value.object.get("generatedAt").?.string);
    try std.testing.expectEqualStrings("0269b76c00ffa005620a06979655e04f46c6fb9ab34b1b6f90a9323947eb0cff", manifest.value.object.get("structureHash").?.string);
    try std.testing.expectEqual(@as(usize, 42), manifest.value.object.get("files").?.object.count());
}
