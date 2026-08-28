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
