//! Smoke tests for monorepo-scale catalog surface (shipped generated modules).
const std = @import("std");
const generated = @import("generated_root.zig");

test "catalog shard 0 findById and cost estimate" {
    const first = generated.catalog_shard_0.get(0).?;
    try std.testing.expect(generated.catalog_shard_0.findById(first.id) != null);
    const cost = generated.catalog_shard_0.estimateCostUsd(first.id, 1000, 500);
    try std.testing.expect(cost != null);
    try std.testing.expect(cost.? >= 0);
}

test "catalog provider base url known" {
    try std.testing.expect(generated.catalog_shard_0.providerBaseUrl("openai") != null);
    try std.testing.expectEqualStrings("https://api.openai.com/v1", generated.catalog_shard_0.providerBaseUrl("openai").?);
}

test "aggregate catalog shards present" {
    try std.testing.expect(generated.catalog_shard_0.count() > 0);
    try std.testing.expect(generated.catalog_shard_39.count() > 0);
}
