//! Persistent Radius dynamic model catalog compatible with upstream models-store.json.
const std = @import("std");
const radius_config = @import("../ai/radius_config.zig");
const radius_catalog = @import("radius_catalog.zig");
const thinking = @import("../ai/thinking.zig");

pub const StoredCatalog = struct {
    catalog: radius_catalog.Catalog,
    checked_at_ms: ?i64 = null,

    pub fn deinit(self: *StoredCatalog, gpa: std.mem.Allocator) void {
        self.catalog.deinit(gpa);
        self.* = undefined;
    }
};

fn permissions0600() std.Io.File.Permissions {
    if (@hasDecl(std.Io.File.Permissions, "fromMode")) return std.Io.File.Permissions.fromMode(0o600);
    return .default_file;
}

fn readFileLocked(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !?[]u8 {
    const file = std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_only, .lock = .shared }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close(io);
    const len64 = try file.length(io);
    if (len64 > 16 * 1024 * 1024) return error.ModelsStoreTooLarge;
    const len: usize = @intCast(len64);
    const data = try gpa.alloc(u8, len);
    errdefer gpa.free(data);
    const got = try file.readPositionalAll(io, data, 0);
    if (got != len) return error.UnexpectedEndOfFile;
    return data;
}

pub fn parseProviderEntry(gpa: std.mem.Allocator, provider_id: []const u8, value: std.json.Value) !StoredCatalog {
    if (value != .object) return error.InvalidModelsStore;
    const models_value = value.object.get("models") orelse return error.InvalidModelsStore;
    if (models_value != .array) return error.InvalidModelsStore;
    var entries: std.ArrayList(radius_catalog.Entry) = .empty;
    errdefer {
        for (entries.items) |*entry| entry.deinit(gpa);
        entries.deinit(gpa);
    }
    for (models_value.array.items) |model_value| {
        if (model_value != .object) continue;
        const api_value = model_value.object.get("api") orelse continue;
        const provider_value = model_value.object.get("provider") orelse continue;
        const base_value = model_value.object.get("baseUrl") orelse continue;
        if (api_value != .string or provider_value != .string or base_value != .string) continue;
        if (!std.mem.eql(u8, api_value.string, "pi-messages") or !std.mem.eql(u8, provider_value.string, provider_id)) continue;
        var gateway_model = (try radius_config.parseGatewayModel(gpa, model_value)) orelse continue;
        defer gateway_model.deinit(gpa);
        try entries.append(gpa, try radius_catalog.entryFromGatewayModel(gpa, provider_id, base_value.string, &gateway_model));
    }
    const checked_at = if (value.object.get("checkedAt")) |v| switch (v) {
        .integer => |n| n,
        .float => |n| @as(i64, @intFromFloat(n)),
        else => null,
    } else null;
    return .{ .catalog = .{ .entries = try entries.toOwnedSlice(gpa) }, .checked_at_ms = checked_at };
}

pub fn load(gpa: std.mem.Allocator, io: std.Io, agent_dir: []const u8, provider_id: []const u8) !?StoredCatalog {
    const path = try std.fs.path.join(gpa, &.{ agent_dir, "models-store.json" });
    defer gpa.free(path);
    const raw = (try readFileLocked(gpa, io, path)) orelse return null;
    defer gpa.free(raw);
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return error.InvalidModelsStore;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidModelsStore;
    const entry = parsed.value.object.get(provider_id) orelse return null;
    return try parseProviderEntry(gpa, provider_id, entry);
}

fn writeMapEntry(w: *std.Io.Writer, name: []const u8, entry: thinking.MapEntry, first: *bool) !void {
    if (entry == .absent) return;
    if (!first.*) try w.writeByte(',');
    first.* = false;
    try std.json.Stringify.value(name, .{}, w);
    try w.writeByte(':');
    switch (entry) {
        .unsupported => try w.writeAll("null"),
        .mapped => |value| try std.json.Stringify.value(value, .{}, w),
        .absent => unreachable,
    }
}

fn writeThinkingMap(w: *std.Io.Writer, map: thinking.ThinkingLevelMap) !void {
    try w.writeByte('{');
    var first = true;
    try writeMapEntry(w, "off", map.off, &first);
    try writeMapEntry(w, "minimal", map.minimal, &first);
    try writeMapEntry(w, "low", map.low, &first);
    try writeMapEntry(w, "medium", map.medium, &first);
    try writeMapEntry(w, "high", map.high, &first);
    try writeMapEntry(w, "xhigh", map.xhigh, &first);
    try writeMapEntry(w, "max", map.max, &first);
    try w.writeByte('}');
}

fn writeCatalogEntry(w: *std.Io.Writer, entry: radius_catalog.Entry) !void {
    const m = entry.info;
    try w.writeAll("{\"id\":");
    try std.json.Stringify.value(m.id, .{}, w);
    try w.writeAll(",\"name\":");
    try std.json.Stringify.value(m.display, .{}, w);
    try w.writeAll(",\"api\":\"pi-messages\",\"provider\":");
    try std.json.Stringify.value(m.providerName(), .{}, w);
    try w.writeAll(",\"baseUrl\":");
    try std.json.Stringify.value(entry.base_url, .{}, w);
    try w.print(",\"reasoning\":{s}", .{if (m.reasoning) "true" else "false"});
    if (m.thinking_level_map) |map| {
        try w.writeAll(",\"thinkingLevelMap\":");
        try writeThinkingMap(w, map);
    }
    try w.writeAll(",\"input\":[");
    var input_first = true;
    if (m.input_text) {
        try w.writeAll("\"text\"");
        input_first = false;
    }
    if (m.input_image) {
        if (!input_first) try w.writeByte(',');
        try w.writeAll("\"image\"");
    }
    try w.print("],\"cost\":{{\"input\":{d},\"output\":{d},\"cacheRead\":{d},\"cacheWrite\":{d}}},\"contextWindow\":{d},\"maxTokens\":{d}}}", .{ m.cost.input, m.cost.output, m.cost.cache_read, m.cost.cache_write, m.context_window, m.max_tokens });
}

pub fn save(gpa: std.mem.Allocator, io: std.Io, agent_dir: []const u8, provider_id: []const u8, catalog: *const radius_catalog.Catalog, checked_at_ms: i64) !void {
    const path = try std.fs.path.join(gpa, &.{ agent_dir, "models-store.json" });
    defer gpa.free(path);
    if (std.fs.path.dirname(path)) |parent| try std.Io.Dir.cwd().createDirPath(io, parent);
    const file = try std.Io.Dir.cwd().createFile(io, path, .{ .read = true, .truncate = false, .lock = .exclusive, .permissions = permissions0600() });
    defer file.close(io);
    const len64 = try file.length(io);
    if (len64 > 16 * 1024 * 1024) return error.ModelsStoreTooLarge;
    const len: usize = @intCast(len64);
    const raw = try gpa.alloc(u8, len);
    defer gpa.free(raw);
    if (len > 0) _ = try file.readPositionalAll(io, raw, 0);
    var parsed = if (raw.len == 0) try std.json.parseFromSlice(std.json.Value, gpa, "{}", .{}) else std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return error.InvalidModelsStore;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidModelsStore;

    // Serialize the new provider entry to JSON, parse it into the existing arena,
    // then stringify the full root so unrelated providers remain untouched.
    var entry_json: std.Io.Writer.Allocating = .init(gpa);
    defer entry_json.deinit();
    try entry_json.writer.writeAll("{\"models\":[");
    for (catalog.entries, 0..) |entry, i| {
        if (i > 0) try entry_json.writer.writeByte(',');
        try writeCatalogEntry(&entry_json.writer, entry);
    }
    try entry_json.writer.print("],\"checkedAt\":{d}}}", .{checked_at_ms});
    var entry_parsed = try std.json.parseFromSlice(std.json.Value, gpa, entry_json.written(), .{});
    defer entry_parsed.deinit();

    // Deep-copy through stringify/parse is simplest here because ObjectMap values
    // must live in the root arena. Recompose a new root writer instead of borrowing
    // from entry_parsed after deinit.
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try out.writer.writeByte('{');
    var first = true;
    var it = parsed.value.object.iterator();
    while (it.next()) |kv| {
        if (std.mem.eql(u8, kv.key_ptr.*, provider_id)) continue;
        if (!first) try out.writer.writeByte(',');
        first = false;
        try std.json.Stringify.value(kv.key_ptr.*, .{}, &out.writer);
        try out.writer.writeByte(':');
        try std.json.Stringify.value(kv.value_ptr.*, .{}, &out.writer);
    }
    if (!first) try out.writer.writeByte(',');
    try std.json.Stringify.value(provider_id, .{}, &out.writer);
    try out.writer.writeByte(':');
    try out.writer.writeAll(entry_json.written());
    try out.writer.writeByte('}');
    try file.setLength(io, 0);
    try file.writePositionalAll(io, out.written(), 0);
}

/// Import the pre-models-store Radius `gatewayConfig` cached inside auth.json.
pub fn loadLegacyAuthCatalog(gpa: std.mem.Allocator, io: std.Io, agent_dir: []const u8, provider_id: []const u8) !?radius_catalog.Catalog {
    const path = try std.fs.path.join(gpa, &.{ agent_dir, "auth.json" });
    defer gpa.free(path);
    const raw = (try readFileLocked(gpa, io, path)) orelse return null;
    defer gpa.free(raw);
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return error.InvalidAuthJson;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidAuthJson;
    const credential = parsed.value.object.get(provider_id) orelse return null;
    if (credential != .object) return null;
    const type_value = credential.object.get("type") orelse return null;
    if (type_value != .string or !std.mem.eql(u8, type_value.string, "oauth")) return null;
    const gateway_value = credential.object.get("gatewayConfig") orelse return null;
    var buf: std.Io.Writer.Allocating = .init(gpa);
    defer buf.deinit();
    try std.json.Stringify.value(gateway_value, .{}, &buf.writer);
    var gateway = radius_config.parseGatewayConfig(gpa, buf.written()) catch return null;
    defer gateway.deinit(gpa);
    return try radius_catalog.fromGatewayConfig(gpa, provider_id, &gateway);
}

/// Restore the latest locally available Radius catalog without network access.
/// Upstream prefers models-store.json and imports the pre-store OAuth gatewayConfig
/// only when no stored catalog exists. Legacy import is persisted best-effort.
pub fn loadAvailableCatalog(gpa: std.mem.Allocator, io: std.Io, agent_dir: []const u8, provider_id: []const u8) !?radius_catalog.Catalog {
    // These files are optional caches. A partial write, stale schema, or empty legacy
    // auth file must not make the coding agent unusable. Valid entries still win in
    // normal precedence order; malformed cache data is treated as unavailable.
    if (load(gpa, io, agent_dir, provider_id) catch null) |stored| {
        return stored.catalog;
    }
    var legacy = (loadLegacyAuthCatalog(gpa, io, agent_dir, provider_id) catch null) orelse return null;
    const now_ms = std.Io.Clock.real.now(io).toMilliseconds();
    save(gpa, io, agent_dir, provider_id, &legacy, now_ms) catch {};
    return legacy;
}

test "Radius models store round trips upstream model entry and preserves other providers" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &buf);
    const root = buf[0..n];
    const path = try std.fs.path.join(gpa, &.{ root, "models-store.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "{\"other\":{\"models\":[],\"checkedAt\":1}}" });
    var gateway = try radius_config.parseGatewayConfig(gpa, "{\"baseUrl\":\"https://radius.example/v1\",\"models\":[{\"id\":\"auto\",\"name\":\"Auto\",\"reasoning\":true,\"input\":[\"text\",\"image\"],\"cost\":{\"input\":1,\"output\":2,\"cacheRead\":0.1,\"cacheWrite\":0.2},\"contextWindow\":128000,\"maxTokens\":16384}]}");
    defer gateway.deinit(gpa);
    var catalog = try radius_catalog.fromGatewayConfig(gpa, "radius-dev", &gateway);
    defer catalog.deinit(gpa);
    try save(gpa, io, root, "radius-dev", &catalog, 1234);
    var loaded = (try load(gpa, io, root, "radius-dev")).?;
    defer loaded.deinit(gpa);
    try std.testing.expectEqual(@as(?i64, 1234), loaded.checked_at_ms);
    try std.testing.expectEqual(@as(usize, 1), loaded.catalog.entries.len);
    try std.testing.expectEqualStrings("https://radius.example/v1", loaded.catalog.entries[0].base_url);
    const saved = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024));
    defer gpa.free(saved);
    try std.testing.expect(std.mem.indexOf(u8, saved, "\"other\"") != null);
}

test "Radius legacy OAuth gatewayConfig imports offline" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &buf);
    const root = buf[0..n];
    const path = try std.fs.path.join(gpa, &.{ root, "auth.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "{\"radius\":{\"type\":\"oauth\",\"access\":\"a\",\"refresh\":\"r\",\"expires\":999,\"gatewayConfig\":{\"baseUrl\":\"https://legacy/v1\",\"models\":[{\"id\":\"auto\",\"name\":\"Auto\",\"reasoning\":false,\"input\":[\"text\"],\"cost\":{},\"contextWindow\":1000,\"maxTokens\":100}]}}}" });
    var catalog = (try loadLegacyAuthCatalog(gpa, io, root, "radius")).?;
    defer catalog.deinit(gpa);
    try std.testing.expectEqualStrings("https://legacy/v1", catalog.entries[0].base_url);
}

test "Radius available catalog tolerates empty legacy auth cache" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &buf);
    const root = buf[0..n];
    const path = try std.fs.path.join(gpa, &.{ root, "auth.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "" });
    try std.testing.expect((try loadAvailableCatalog(gpa, io, root, "radius")) == null);
}

test "Radius available catalog falls back from corrupt store to valid legacy auth" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &buf);
    const root = buf[0..n];
    const store_path = try std.fs.path.join(gpa, &.{ root, "models-store.json" });
    defer gpa.free(store_path);
    const auth_path = try std.fs.path.join(gpa, &.{ root, "auth.json" });
    defer gpa.free(auth_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = store_path, .data = "{not-json" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = auth_path, .data = "{\"radius\":{\"type\":\"oauth\",\"gatewayConfig\":{\"baseUrl\":\"https://legacy.example/v1\",\"models\":[{\"id\":\"auto\",\"name\":\"Auto\",\"reasoning\":false,\"input\":[\"text\"],\"cost\":{},\"contextWindow\":1000,\"maxTokens\":100}]}}}" });
    var catalog = (try loadAvailableCatalog(gpa, io, root, "radius")).?;
    defer catalog.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), catalog.entries.len);
    try std.testing.expectEqualStrings("https://legacy.example/v1", catalog.entries[0].base_url);
}

test "Radius available catalog tolerates corrupt store and corrupt auth" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &buf);
    const root = buf[0..n];
    const store_path = try std.fs.path.join(gpa, &.{ root, "models-store.json" });
    defer gpa.free(store_path);
    const auth_path = try std.fs.path.join(gpa, &.{ root, "auth.json" });
    defer gpa.free(auth_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = store_path, .data = "[]" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = auth_path, .data = "{" });
    try std.testing.expect((try loadAvailableCatalog(gpa, io, root, "radius")) == null);
}
