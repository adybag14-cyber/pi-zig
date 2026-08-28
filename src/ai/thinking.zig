//! Thinking-level capability and clamping semantics ported from pi-ai models.ts.
const std = @import("std");

pub const ThinkingLevel = enum {
    off,
    minimal,
    low,
    medium,
    high,
    xhigh,
    max,

    pub fn parse(s: []const u8) ?ThinkingLevel {
        if (std.ascii.eqlIgnoreCase(s, "off") or std.ascii.eqlIgnoreCase(s, "none")) return .off;
        if (std.ascii.eqlIgnoreCase(s, "minimal")) return .minimal;
        if (std.ascii.eqlIgnoreCase(s, "low")) return .low;
        if (std.ascii.eqlIgnoreCase(s, "medium") or std.ascii.eqlIgnoreCase(s, "mid")) return .medium;
        if (std.ascii.eqlIgnoreCase(s, "high")) return .high;
        if (std.ascii.eqlIgnoreCase(s, "xhigh")) return .xhigh;
        if (std.ascii.eqlIgnoreCase(s, "max")) return .max;
        return null;
    }

    /// Compatibility helper for older callers that expected a non-optional parser.
    pub fn fromString(s: []const u8) ThinkingLevel {
        return parse(s) orelse .medium;
    }

    pub fn anthropicBudget(self: ThinkingLevel) ?u32 {
        return switch (self) {
            .off => null,
            .minimal => 512,
            .low => 1024,
            .medium => 4096,
            .high => 10_000,
            .xhigh => 32_000,
            .max => 64_000,
        };
    }

    pub fn openaiEffort(self: ThinkingLevel) ?[]const u8 {
        return switch (self) {
            .off => null,
            .minimal => "minimal",
            .low => "low",
            .medium => "medium",
            .high => "high",
            .xhigh => "xhigh",
            .max => "max",
        };
    }
};

/// A thinkingLevelMap entry distinguishes omitted from explicit null.
pub const MapEntry = union(enum) {
    absent,
    unsupported,
    mapped: []const u8,
};

pub const ThinkingLevelMap = struct {
    off: MapEntry = .absent,
    minimal: MapEntry = .absent,
    low: MapEntry = .absent,
    medium: MapEntry = .absent,
    high: MapEntry = .absent,
    xhigh: MapEntry = .absent,
    max: MapEntry = .absent,

    pub fn entry(self: ThinkingLevelMap, level: ThinkingLevel) MapEntry {
        return switch (level) {
            .off => self.off,
            .minimal => self.minimal,
            .low => self.low,
            .medium => self.medium,
            .high => self.high,
            .xhigh => self.xhigh,
            .max => self.max,
        };
    }
};

pub const extended_levels = [_]ThinkingLevel{ .off, .minimal, .low, .medium, .high, .xhigh, .max };

/// Exact upstream getSupportedThinkingLevels semantics.
pub fn supported(reasoning: bool, map: ?ThinkingLevelMap, out: *[7]ThinkingLevel) []const ThinkingLevel {
    if (!reasoning) {
        out[0] = .off;
        return out[0..1];
    }
    var n: usize = 0;
    for (extended_levels) |level| {
        const entry = if (map) |m| m.entry(level) else MapEntry.absent;
        if (entry == .unsupported) continue;
        if ((level == .xhigh or level == .max) and entry == .absent) continue;
        out[n] = level;
        n += 1;
    }
    return out[0..n];
}

/// Exact upstream clampThinkingLevel semantics: if unsupported, search upward
/// from the requested level first, then downward.
pub fn clamp(reasoning: bool, map: ?ThinkingLevelMap, requested: ThinkingLevel) ThinkingLevel {
    var buf: [7]ThinkingLevel = undefined;
    const levels = supported(reasoning, map, &buf);
    for (levels) |level| if (level == requested) return requested;

    var requested_index: ?usize = null;
    for (extended_levels, 0..) |level, i| if (level == requested) {
        requested_index = i;
        break;
    };
    const idx = requested_index orelse return if (levels.len > 0) levels[0] else .off;

    var i = idx;
    while (i < extended_levels.len) : (i += 1) {
        const candidate = extended_levels[i];
        for (levels) |available| if (available == candidate) return candidate;
    }
    i = idx;
    while (i > 0) {
        i -= 1;
        const candidate = extended_levels[i];
        for (levels) |available| if (available == candidate) return candidate;
    }
    return if (levels.len > 0) levels[0] else .off;
}

test "supported levels match upstream holes and opt-in xhigh/max" {
    var buf: [7]ThinkingLevel = undefined;
    var map = ThinkingLevelMap{};
    map.minimal = .unsupported;
    map.xhigh = .{ .mapped = "very_high" };
    map.max = .unsupported;
    const levels = supported(true, map, &buf);
    try std.testing.expectEqualSlices(ThinkingLevel, &.{ .off, .low, .medium, .high, .xhigh }, levels);
    const off_only = supported(false, map, &buf);
    try std.testing.expectEqualSlices(ThinkingLevel, &.{.off}, off_only);
}

test "clamp searches upward before downward like upstream" {
    var map = ThinkingLevelMap{};
    map.minimal = .unsupported;
    map.low = .unsupported;
    map.medium = .unsupported;
    map.xhigh = .{ .mapped = "xhigh" };
    map.max = .unsupported;
    try std.testing.expectEqual(ThinkingLevel.high, clamp(true, map, .minimal));
    try std.testing.expectEqual(ThinkingLevel.xhigh, clamp(true, map, .max));
    try std.testing.expectEqual(ThinkingLevel.off, clamp(false, null, .high));
}
