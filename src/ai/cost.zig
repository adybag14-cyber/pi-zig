//! Pi-compatible token accounting and cost calculation.
const std = @import("std");
const providers = @import("providers.zig");

pub const Cost = struct {
    input: f64 = 0,
    output: f64 = 0,
    cache_read: f64 = 0,
    cache_write: f64 = 0,
    total: f64 = 0,
};

pub const Usage = struct {
    /// Uncached input tokens. Cached reads/writes are tracked separately.
    input: u64 = 0,
    output: u64 = 0,
    cache_read: u64 = 0,
    cache_write: u64 = 0,
    /// Anthropic-only subset of cache_write with one-hour retention.
    cache_write_1h: ?u64 = null,
    /// Provider-reported reasoning/thinking tokens, a subset of output.
    reasoning: ?u64 = null,
    total_tokens: u64 = 0,
    cost: Cost = .{},

    pub fn total(self: Usage) u64 {
        if (self.total_tokens > 0) return self.total_tokens;
        return self.input + self.output + self.cache_read + self.cache_write;
    }

    pub fn normalizeTotal(self: *Usage) void {
        self.total_tokens = self.input + self.output + self.cache_read + self.cache_write;
    }
};

/// Matches upstream packages/ai/src/models.ts calculateCost(): the highest
/// request-wide tier whose threshold is exceeded applies to the whole request.
pub fn calculate(model_cost: providers.ModelCost, usage: *Usage) Cost {
    const input_tokens = usage.input + usage.cache_read + usage.cache_write;
    var rates: providers.ModelCostRates = .{
        .input = model_cost.input,
        .output = model_cost.output,
        .cache_read = model_cost.cache_read,
        .cache_write = model_cost.cache_write,
    };
    var matched_threshold: i64 = -1;
    for (model_cost.tiers) |tier| {
        if (input_tokens > tier.input_tokens_above and @as(i64, @intCast(tier.input_tokens_above)) > matched_threshold) {
            rates = .{
                .input = tier.input,
                .output = tier.output,
                .cache_read = tier.cache_read,
                .cache_write = tier.cache_write,
            };
            matched_threshold = @intCast(tier.input_tokens_above);
        }
    }

    const long_write = usage.cache_write_1h orelse 0;
    const bounded_long = @min(long_write, usage.cache_write);
    const short_write = usage.cache_write - bounded_long;
    usage.cost.input = (rates.input / 1_000_000.0) * @as(f64, @floatFromInt(usage.input));
    usage.cost.output = (rates.output / 1_000_000.0) * @as(f64, @floatFromInt(usage.output));
    usage.cost.cache_read = (rates.cache_read / 1_000_000.0) * @as(f64, @floatFromInt(usage.cache_read));
    usage.cost.cache_write = (rates.cache_write * @as(f64, @floatFromInt(short_write)) + rates.input * 2.0 * @as(f64, @floatFromInt(bounded_long))) / 1_000_000.0;
    usage.cost.total = usage.cost.input + usage.cost.output + usage.cost.cache_read + usage.cost.cache_write;
    return usage.cost;
}

test "cost uses uncached/cache buckets and one-hour anthropic writes" {
    var usage: Usage = .{ .input = 70, .output = 30, .cache_read = 20, .cache_write = 10, .cache_write_1h = 4 };
    _ = calculate(.{ .input = 1, .output = 2, .cache_read = 0.1, .cache_write = 1.25 }, &usage);
    try std.testing.expectApproxEqAbs(@as(f64, 0.00007), usage.cost.input, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.00006), usage.cost.output, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.000002), usage.cost.cache_read, 1e-12);
    // 6 short writes at 1.25/M + 4 long writes at 2x input/M.
    try std.testing.expectApproxEqAbs(@as(f64, 0.0000155), usage.cost.cache_write, 1e-12);
}

test "highest matching request-wide pricing tier wins" {
    const tiers = [_]providers.ModelCostTier{
        .{ .input_tokens_above = 100, .input = 2, .output = 4, .cache_read = 0.2, .cache_write = 2.5 },
        .{ .input_tokens_above = 1000, .input = 3, .output = 6, .cache_read = 0.3, .cache_write = 3.75 },
    };
    var usage: Usage = .{ .input = 900, .cache_read = 200, .output = 10 };
    _ = calculate(.{ .input = 1, .output = 2, .cache_read = 0.1, .cache_write = 1.25, .tiers = &tiers }, &usage);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0027), usage.cost.input, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.00006), usage.cost.output, 1e-12);
}
