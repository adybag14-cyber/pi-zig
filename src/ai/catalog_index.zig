//! Product-facing catalog index over all generated model shards.
//! Used by CLI `--list-models`, model resolution, and cost helpers.
const std = @import("std");
const g = @import("generated_root.zig");

pub const ListedModel = struct {
    id: []const u8,
    provider: []const u8,
    display: []const u8,
    context_window: u32,
    supports_tools: bool,
    family: []const u8,
};

/// Total models across every catalog shard (shipped surface, not the static 40-row bootstrap list).
pub fn totalCount() usize {
    var n: usize = 0;
    n += g.catalog_shard_0.count();
    n += g.catalog_shard_1.count();
    n += g.catalog_shard_2.count();
    n += g.catalog_shard_3.count();
    n += g.catalog_shard_4.count();
    n += g.catalog_shard_5.count();
    n += g.catalog_shard_6.count();
    n += g.catalog_shard_7.count();
    n += g.catalog_shard_8.count();
    n += g.catalog_shard_9.count();
    n += g.catalog_shard_10.count();
    n += g.catalog_shard_11.count();
    n += g.catalog_shard_12.count();
    n += g.catalog_shard_13.count();
    n += g.catalog_shard_14.count();
    n += g.catalog_shard_15.count();
    n += g.catalog_shard_16.count();
    n += g.catalog_shard_17.count();
    n += g.catalog_shard_18.count();
    n += g.catalog_shard_19.count();
    n += g.catalog_shard_20.count();
    n += g.catalog_shard_21.count();
    n += g.catalog_shard_22.count();
    n += g.catalog_shard_23.count();
    n += g.catalog_shard_24.count();
    n += g.catalog_shard_25.count();
    n += g.catalog_shard_26.count();
    n += g.catalog_shard_27.count();
    n += g.catalog_shard_28.count();
    n += g.catalog_shard_29.count();
    n += g.catalog_shard_30.count();
    n += g.catalog_shard_31.count();
    n += g.catalog_shard_32.count();
    n += g.catalog_shard_33.count();
    n += g.catalog_shard_34.count();
    n += g.catalog_shard_35.count();
    n += g.catalog_shard_36.count();
    n += g.catalog_shard_37.count();
    n += g.catalog_shard_38.count();
    n += g.catalog_shard_39.count();
    return n;
}

fn pushFromShard(comptime models: anytype, query: ?[]const u8, out: *std.ArrayList(ListedModel), gpa: std.mem.Allocator) !void {
    for (models) |m| {
        if (query) |q| {
            if (std.mem.indexOf(u8, m.id, q) == null and
                std.mem.indexOf(u8, m.display, q) == null and
                std.mem.indexOf(u8, m.provider, q) == null and
                std.mem.indexOf(u8, m.family, q) == null) continue;
        }
        try out.append(gpa, .{
            .id = m.id,
            .provider = m.provider,
            .display = m.display,
            .context_window = m.context_window,
            .supports_tools = m.supports_tools,
            .family = m.family,
        });
    }
}

/// Collect models matching optional query (substring on id/display/provider/family).
/// Caller owns the slice (not the string fields — those are static).
pub fn listModels(gpa: std.mem.Allocator, query: ?[]const u8) ![]ListedModel {
    var out: std.ArrayList(ListedModel) = .empty;
    errdefer out.deinit(gpa);
    try pushFromShard(g.catalog_shard_0.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_1.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_2.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_3.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_4.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_5.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_6.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_7.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_8.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_9.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_10.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_11.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_12.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_13.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_14.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_15.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_16.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_17.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_18.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_19.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_20.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_21.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_22.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_23.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_24.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_25.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_26.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_27.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_28.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_29.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_30.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_31.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_32.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_33.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_34.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_35.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_36.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_37.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_38.models, query, &out, gpa);
    try pushFromShard(g.catalog_shard_39.models, query, &out, gpa);
    return try out.toOwnedSlice(gpa);
}

/// Resolve model id across the full shard catalog (provider/id or bare id).
pub fn findById(id: []const u8) ?ListedModel {
    // Strip provider/ prefix if present for bare-id match later
    const bare = if (std.mem.indexOfScalar(u8, id, '/')) |s| id[s + 1 ..] else id;
    inline for (.{
        g.catalog_shard_0,  g.catalog_shard_1,  g.catalog_shard_2,  g.catalog_shard_3,
        g.catalog_shard_4,  g.catalog_shard_5,  g.catalog_shard_6,  g.catalog_shard_7,
        g.catalog_shard_8,  g.catalog_shard_9,  g.catalog_shard_10, g.catalog_shard_11,
        g.catalog_shard_12, g.catalog_shard_13, g.catalog_shard_14, g.catalog_shard_15,
        g.catalog_shard_16, g.catalog_shard_17, g.catalog_shard_18, g.catalog_shard_19,
        g.catalog_shard_20, g.catalog_shard_21, g.catalog_shard_22, g.catalog_shard_23,
        g.catalog_shard_24, g.catalog_shard_25, g.catalog_shard_26, g.catalog_shard_27,
        g.catalog_shard_28, g.catalog_shard_29, g.catalog_shard_30, g.catalog_shard_31,
        g.catalog_shard_32, g.catalog_shard_33, g.catalog_shard_34, g.catalog_shard_35,
        g.catalog_shard_36, g.catalog_shard_37, g.catalog_shard_38, g.catalog_shard_39,
    }) |shard| {
        for (shard.models) |m| {
            if (std.mem.eql(u8, m.id, id) or std.mem.eql(u8, m.id, bare)) {
                return .{
                    .id = m.id,
                    .provider = m.provider,
                    .display = m.display,
                    .context_window = m.context_window,
                    .supports_tools = m.supports_tools,
                    .family = m.family,
                };
            }
        }
    }
    return null;
}

pub fn estimateCostUsd(id: []const u8, input_tokens: u64, output_tokens: u64) ?f64 {
    inline for (.{
        g.catalog_shard_0,  g.catalog_shard_1,  g.catalog_shard_2,  g.catalog_shard_3,
        g.catalog_shard_4,  g.catalog_shard_5,  g.catalog_shard_6,  g.catalog_shard_7,
        g.catalog_shard_8,  g.catalog_shard_9,  g.catalog_shard_10, g.catalog_shard_11,
        g.catalog_shard_12, g.catalog_shard_13, g.catalog_shard_14, g.catalog_shard_15,
        g.catalog_shard_16, g.catalog_shard_17, g.catalog_shard_18, g.catalog_shard_19,
        g.catalog_shard_20, g.catalog_shard_21, g.catalog_shard_22, g.catalog_shard_23,
        g.catalog_shard_24, g.catalog_shard_25, g.catalog_shard_26, g.catalog_shard_27,
        g.catalog_shard_28, g.catalog_shard_29, g.catalog_shard_30, g.catalog_shard_31,
        g.catalog_shard_32, g.catalog_shard_33, g.catalog_shard_34, g.catalog_shard_35,
        g.catalog_shard_36, g.catalog_shard_37, g.catalog_shard_38, g.catalog_shard_39,
    }) |shard| {
        if (shard.estimateCostUsd(id, input_tokens, output_tokens)) |c| return c;
    }
    return null;
}

pub fn providerBaseUrl(provider: []const u8) ?[]const u8 {
    return g.catalog_shard_0.providerBaseUrl(provider);
}

test "catalog index totalCount uses all shards" {
    // 40 shards × 100 models
    try std.testing.expectEqual(@as(usize, 4000), totalCount());
}

test "catalog index findById and listModels product path" {
    const gpa = std.testing.allocator;
    const first = g.catalog_shard_0.models[0];
    const found = findById(first.id);
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings(first.id, found.?.id);

    const listed = try listModels(gpa, "openai");
    defer gpa.free(listed);
    try std.testing.expect(listed.len > 0);
    // Every hit must mention openai in id or provider
    for (listed) |m| {
        const ok = std.mem.indexOf(u8, m.id, "openai") != null or std.mem.eql(u8, m.provider, "openai");
        try std.testing.expect(ok);
    }
}

test "catalog index estimateCostUsd on real shard id" {
    const id = g.catalog_shard_0.models[0].id;
    const c = estimateCostUsd(id, 1_000_000, 1_000_000);
    try std.testing.expect(c != null);
    try std.testing.expect(c.? > 0);
}
