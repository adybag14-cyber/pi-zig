//! Adapter between Radius `/v1/config` catalogs and coding-agent model/runtime metadata.
const std = @import("std");
const providers = @import("../ai/providers.zig");
const radius_config = @import("../ai/radius_config.zig");
const thinking = @import("../ai/thinking.zig");

pub const Entry = struct {
    info: providers.ModelInfo,
    base_url: []u8,

    pub fn deinit(self: *Entry, gpa: std.mem.Allocator) void {
        gpa.free(@constCast(self.info.provider_id.?));
        gpa.free(@constCast(self.info.id));
        gpa.free(@constCast(self.info.display));
        gpa.free(self.base_url);
        if (self.info.thinking_level_map) |map| freeThinkingMap(gpa, map);
        self.* = undefined;
    }
};

pub const Catalog = struct {
    entries: []Entry,

    pub fn deinit(self: *Catalog, gpa: std.mem.Allocator) void {
        for (self.entries) |*entry| entry.deinit(gpa);
        gpa.free(self.entries);
        self.* = undefined;
    }

    pub fn infos(self: *const Catalog, gpa: std.mem.Allocator) ![]providers.ModelInfo {
        const out = try gpa.alloc(providers.ModelInfo, self.entries.len);
        for (self.entries, 0..) |entry, i| out[i] = entry.info;
        return out;
    }
};

fn cloneEntry(gpa: std.mem.Allocator, entry: thinking.MapEntry) !thinking.MapEntry {
    return switch (entry) {
        .mapped => |value| .{ .mapped = try gpa.dupe(u8, value) },
        .unsupported => .unsupported,
        .absent => .absent,
    };
}

fn cloneThinkingMap(gpa: std.mem.Allocator, map: thinking.ThinkingLevelMap) !thinking.ThinkingLevelMap {
    var out: thinking.ThinkingLevelMap = .{};
    errdefer freeThinkingMap(gpa, out);
    out.off = try cloneEntry(gpa, map.off);
    out.minimal = try cloneEntry(gpa, map.minimal);
    out.low = try cloneEntry(gpa, map.low);
    out.medium = try cloneEntry(gpa, map.medium);
    out.high = try cloneEntry(gpa, map.high);
    out.xhigh = try cloneEntry(gpa, map.xhigh);
    out.max = try cloneEntry(gpa, map.max);
    return out;
}

fn freeMapEntry(gpa: std.mem.Allocator, entry: thinking.MapEntry) void {
    switch (entry) {
        .mapped => |value| gpa.free(value),
        else => {},
    }
}
fn freeThinkingMap(gpa: std.mem.Allocator, map: thinking.ThinkingLevelMap) void {
    freeMapEntry(gpa, map.off);
    freeMapEntry(gpa, map.minimal);
    freeMapEntry(gpa, map.low);
    freeMapEntry(gpa, map.medium);
    freeMapEntry(gpa, map.high);
    freeMapEntry(gpa, map.xhigh);
    freeMapEntry(gpa, map.max);
}

pub fn entryFromGatewayModel(gpa: std.mem.Allocator, provider_id: []const u8, base_url_value: []const u8, model: *const radius_config.GatewayModel) !Entry {
    const pid = try gpa.dupe(u8, provider_id);
    errdefer gpa.free(pid);
    const id = try gpa.dupe(u8, model.id);
    errdefer gpa.free(id);
    const display = try gpa.dupe(u8, model.name);
    errdefer gpa.free(display);
    const base_url = try gpa.dupe(u8, base_url_value);
    errdefer gpa.free(base_url);
    const map = if (model.thinking_level_map) |source| try cloneThinkingMap(gpa, source) else null;
    errdefer if (map) |m| freeThinkingMap(gpa, m);
    return .{
        .info = .{
            .provider = .radius,
            .provider_id = pid,
            .api = .pi_messages,
            .id = id,
            .display = display,
            .reasoning = model.reasoning,
            .thinking_level_map = map,
            .input_text = model.input_text,
            .input_image = model.input_image,
            .context_window = model.context_window,
            .max_tokens = model.max_tokens,
            .cost = model.cost,
        },
        .base_url = base_url,
    };
}

pub fn fromGatewayConfig(gpa: std.mem.Allocator, provider_id: []const u8, config: *const radius_config.GatewayConfig) !Catalog {
    var entries: std.ArrayList(Entry) = .empty;
    errdefer {
        for (entries.items) |*entry| entry.deinit(gpa);
        entries.deinit(gpa);
    }
    for (config.models) |*model| {
        try entries.append(gpa, try entryFromGatewayModel(gpa, provider_id, config.base_url, model));
    }
    return .{ .entries = try entries.toOwnedSlice(gpa) };
}

test "Radius gateway catalog preserves custom identity runtime metadata and API base" {
    const gpa = std.testing.allocator;
    var config = try radius_config.parseGatewayConfig(gpa,
        \\{"baseUrl":"http://localhost:8788/v1","models":[{"id":"auto","name":"Radius Auto","reasoning":true,"thinkingLevelMap":{"high":"hard"},"input":["text","image"],"cost":{"input":1,"output":2,"cacheRead":0.1,"cacheWrite":0.2},"contextWindow":128000,"maxTokens":16384}]}
    );
    defer config.deinit(gpa);
    var catalog = try fromGatewayConfig(gpa, "radius-dev", &config);
    defer catalog.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), catalog.entries.len);
    const entry = catalog.entries[0];
    try std.testing.expectEqualStrings("radius-dev", entry.info.providerName());
    try std.testing.expect(entry.info.provider == .radius and entry.info.apiKind() == .pi_messages);
    try std.testing.expect(entry.info.input_image and entry.info.reasoning);
    try std.testing.expectEqualStrings("hard", entry.info.thinking_level_map.?.high.mapped);
    try std.testing.expectEqualStrings("http://localhost:8788/v1", entry.base_url);
}
