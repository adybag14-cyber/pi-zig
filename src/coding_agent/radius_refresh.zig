//! Explicit Radius dynamic-model network refresh.
//! Startup restoration stays offline; callers opt into this primitive.
const std = @import("std");
const radius_config = @import("../ai/radius_config.zig");
const bootstrap_http = @import("../ai/bootstrap_http.zig");
const radius_catalog = @import("radius_catalog.zig");
const radius_store = @import("radius_models_store.zig");

pub fn networkEnabled(environ: *const std.process.Environ.Map) bool {
    return environ.get("PI_OFFLINE") == null;
}

/// Persist a parsed gateway configuration and return an independently owned catalog.
pub fn persistConfig(
    gpa: std.mem.Allocator,
    io: std.Io,
    agent_dir: []const u8,
    provider_id: []const u8,
    config: *const radius_config.GatewayConfig,
) !radius_catalog.Catalog {
    var catalog = try radius_catalog.fromGatewayConfig(gpa, provider_id, config);
    errdefer catalog.deinit(gpa);
    const checked_at = std.Io.Clock.real.now(io).toMilliseconds();
    try radius_store.save(gpa, io, agent_dir, provider_id, &catalog, checked_at);
    return catalog;
}

/// Fetch `/v1/config` from a Radius gateway, persist it, and return the refreshed catalog.
/// `PI_OFFLINE` is a hard network gate and is checked before URL or HTTP work.
pub fn refresh(
    gpa: std.mem.Allocator,
    io: std.Io,
    environ: *const std.process.Environ.Map,
    agent_dir: []const u8,
    provider_id: []const u8,
    gateway: []const u8,
    api_key: ?[]const u8,
) !radius_catalog.Catalog {
    return refreshWithOptions(gpa, io, environ, agent_dir, provider_id, gateway, api_key, .{});
}

pub fn refreshWithOptions(
    gpa: std.mem.Allocator,
    io: std.Io,
    environ: *const std.process.Environ.Map,
    agent_dir: []const u8,
    provider_id: []const u8,
    gateway: []const u8,
    api_key: ?[]const u8,
    options: bootstrap_http.Options,
) !radius_catalog.Catalog {
    if (!networkEnabled(environ)) return error.ModelNetworkDisabled;
    var config = try radius_config.loadGatewayConfigWithOptions(gpa, io, gateway, api_key, options);
    defer config.deinit(gpa);
    return persistConfig(gpa, io, agent_dir, provider_id, &config);
}

test "Radius refresh honors PI_OFFLINE before network work" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("PI_OFFLINE", "1");
    try std.testing.expect(!networkEnabled(&env));
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(std.testing.io, &buf);
    try std.testing.expectError(error.ModelNetworkDisabled, refresh(gpa, std.testing.io, &env, buf[0..n], "radius", "not-a-real-host.invalid", null));
}

test "Radius persistConfig creates reloadable models-store entry" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &buf);
    const root = buf[0..n];
    var config = try radius_config.parseGatewayConfig(gpa, "{\"baseUrl\":\"https://radius.example/v1\",\"models\":[{\"id\":\"m1\",\"name\":\"M1\",\"reasoning\":true,\"input\":[\"text\"],\"cost\":{},\"contextWindow\":8000,\"maxTokens\":1000}]}");
    defer config.deinit(gpa);
    var catalog = try persistConfig(gpa, io, root, "radius-dev", &config);
    defer catalog.deinit(gpa);
    var stored = (try radius_store.load(gpa, io, root, "radius-dev")).?;
    defer stored.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), stored.catalog.entries.len);
    try std.testing.expectEqualStrings("m1", stored.catalog.entries[0].info.id);
    try std.testing.expect(stored.checked_at_ms != null);
}
