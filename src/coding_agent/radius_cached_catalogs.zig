//! Offline Radius catalog restoration for startup model composition.
const std = @import("std");
const providers = @import("../ai/providers.zig");
const models_file_mod = @import("models_file.zig");
const radius_catalog = @import("radius_catalog.zig");
const radius_store = @import("radius_models_store.zig");

pub const Set = struct {
    catalogs: []radius_catalog.Catalog = &.{},
    infos: []providers.ModelInfo = &.{},

    pub fn deinit(self: *Set, gpa: std.mem.Allocator) void {
        if (self.infos.len > 0) gpa.free(self.infos);
        for (self.catalogs) |*catalog| catalog.deinit(gpa);
        if (self.catalogs.len > 0) gpa.free(self.catalogs);
        self.* = undefined;
    }
};

fn appendProviderCatalog(
    gpa: std.mem.Allocator,
    io: std.Io,
    agent_dir: []const u8,
    provider_id: []const u8,
    catalogs: *std.ArrayList(radius_catalog.Catalog),
    infos: *std.ArrayList(providers.ModelInfo),
) !void {
    var catalog = (try radius_store.loadAvailableCatalog(gpa, io, agent_dir, provider_id)) orelse return;
    errdefer catalog.deinit(gpa);
    for (catalog.entries) |entry| try infos.append(gpa, entry.info);
    try catalogs.append(gpa, catalog);
}

/// Restore built-in Radius plus custom `oauth:"radius"` provider catalogs from
/// local storage only. No HTTP request is performed here.
pub fn load(gpa: std.mem.Allocator, io: std.Io, agent_dir: []const u8, models_file: *const models_file_mod.ModelsFile) !Set {
    var catalogs: std.ArrayList(radius_catalog.Catalog) = .empty;
    errdefer {
        for (catalogs.items) |*catalog| catalog.deinit(gpa);
        catalogs.deinit(gpa);
    }
    var infos: std.ArrayList(providers.ModelInfo) = .empty;
    errdefer infos.deinit(gpa);

    try appendProviderCatalog(gpa, io, agent_dir, "radius", &catalogs, &infos);
    for (models_file.providers) |provider| {
        if (provider.oauth != .radius or std.ascii.eqlIgnoreCase(provider.id, "radius")) continue;
        try appendProviderCatalog(gpa, io, agent_dir, provider.id, &catalogs, &infos);
    }
    return .{ .catalogs = try catalogs.toOwnedSlice(gpa), .infos = try infos.toOwnedSlice(gpa) };
}

test "offline Radius catalog set restores builtin and custom OAuth providers" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];
    const models_path = try std.fs.path.join(gpa, &.{ root, "models.json" });
    defer gpa.free(models_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = models_path, .data = "{\"providers\":{\"radius-dev\":{\"baseUrl\":\"http://dev\",\"oauth\":\"radius\"}}}" });
    var file = try models_file_mod.load(gpa, io, root);
    defer file.deinit();

    const store_path = try std.fs.path.join(gpa, &.{ root, "models-store.json" });
    defer gpa.free(store_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = store_path, .data = "{\"radius\":{\"models\":[{\"id\":\"auto\",\"name\":\"Cached Auto\",\"api\":\"pi-messages\",\"provider\":\"radius\",\"baseUrl\":\"https://radius.pi.dev/v1\",\"reasoning\":false,\"input\":[\"text\"],\"cost\":{},\"contextWindow\":1000,\"maxTokens\":100}]},\"radius-dev\":{\"models\":[{\"id\":\"dev-auto\",\"name\":\"Dev Auto\",\"api\":\"pi-messages\",\"provider\":\"radius-dev\",\"baseUrl\":\"http://dev/v1\",\"reasoning\":true,\"input\":[\"text\"],\"cost\":{},\"contextWindow\":2000,\"maxTokens\":200}]}}" });
    var set = try load(gpa, io, root, &file);
    defer set.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 2), set.infos.len);
    try std.testing.expectEqualStrings("radius", set.infos[0].providerName());
    try std.testing.expectEqualStrings("radius-dev", set.infos[1].providerName());
    try std.testing.expectEqualStrings("dev-auto", set.infos[1].id);
}
