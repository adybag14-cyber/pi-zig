//! Radius gateway discovery/configuration.
//!
//! Radius exposes its model catalog at `/v1/config`.  This module mirrors the
//! upstream sanitizer while keeping all returned strings owned by the caller.
const std = @import("std");
const bootstrap_http = @import("bootstrap_http.zig");
const providers = @import("providers.zig");
const thinking = @import("thinking.zig");

pub const DEFAULT_GATEWAY = "https://radius.pi.dev";

pub const GatewayModel = struct {
    id: []u8,
    name: []u8,
    reasoning: bool,
    thinking_level_map: ?thinking.ThinkingLevelMap = null,
    input_text: bool = false,
    input_image: bool = false,
    cost: providers.ModelCost = .{},
    context_window: u64,
    max_tokens: u64,

    pub fn deinit(self: *GatewayModel, gpa: std.mem.Allocator) void {
        gpa.free(self.id);
        gpa.free(self.name);
        if (self.thinking_level_map) |map| freeThinkingMap(gpa, map);
        self.* = undefined;
    }
};

pub const GatewayConfig = struct {
    base_url: []u8,
    models: []GatewayModel,

    pub fn deinit(self: *GatewayConfig, gpa: std.mem.Allocator) void {
        gpa.free(self.base_url);
        for (self.models) |*model| model.deinit(gpa);
        gpa.free(self.models);
        self.* = undefined;
    }
};

fn freeEntry(gpa: std.mem.Allocator, entry: thinking.MapEntry) void {
    switch (entry) {
        .mapped => |value| gpa.free(value),
        else => {},
    }
}

fn freeThinkingMap(gpa: std.mem.Allocator, map: thinking.ThinkingLevelMap) void {
    freeEntry(gpa, map.off);
    freeEntry(gpa, map.minimal);
    freeEntry(gpa, map.low);
    freeEntry(gpa, map.medium);
    freeEntry(gpa, map.high);
    freeEntry(gpa, map.xhigh);
    freeEntry(gpa, map.max);
}

fn parseMapEntry(gpa: std.mem.Allocator, object: std.json.ObjectMap, name: []const u8) !thinking.MapEntry {
    const value = object.get(name) orelse return .absent;
    return switch (value) {
        .null => .unsupported,
        .string => |s| if (s.len == 0) .unsupported else .{ .mapped = try gpa.dupe(u8, s) },
        else => .absent,
    };
}

fn parseThinkingMap(gpa: std.mem.Allocator, value: std.json.Value) !?thinking.ThinkingLevelMap {
    if (value != .object) return null;
    var map: thinking.ThinkingLevelMap = .{};
    errdefer freeThinkingMap(gpa, map);
    map.off = try parseMapEntry(gpa, value.object, "off");
    map.minimal = try parseMapEntry(gpa, value.object, "minimal");
    map.low = try parseMapEntry(gpa, value.object, "low");
    map.medium = try parseMapEntry(gpa, value.object, "medium");
    map.high = try parseMapEntry(gpa, value.object, "high");
    map.xhigh = try parseMapEntry(gpa, value.object, "xhigh");
    map.max = try parseMapEntry(gpa, value.object, "max");
    return map;
}

fn numberToU64(value: std.json.Value) ?u64 {
    return switch (value) {
        .integer => |n| if (n >= 0) @intCast(n) else null,
        .float => |n| if (n >= 0 and std.math.isFinite(n)) @intFromFloat(n) else null,
        else => null,
    };
}

fn numberToF64(value: std.json.Value) ?f64 {
    return switch (value) {
        .integer => |n| @floatFromInt(n),
        .float => |n| if (std.math.isFinite(n)) n else null,
        else => null,
    };
}

fn parseCost(object: std.json.ObjectMap) providers.ModelCost {
    var out: providers.ModelCost = .{};
    if (object.get("input")) |v| out.input = numberToF64(v) orelse 0;
    if (object.get("output")) |v| out.output = numberToF64(v) orelse 0;
    if (object.get("cacheRead")) |v| out.cache_read = numberToF64(v) orelse 0;
    if (object.get("cacheWrite")) |v| out.cache_write = numberToF64(v) orelse 0;
    return out;
}

pub fn parseGatewayModel(gpa: std.mem.Allocator, value: std.json.Value) !?GatewayModel {
    if (value != .object) return null;
    const obj = value.object;
    const id_value = obj.get("id") orelse return null;
    const name_value = obj.get("name") orelse return null;
    const reasoning_value = obj.get("reasoning") orelse return null;
    const input_value = obj.get("input") orelse return null;
    const cost_value = obj.get("cost") orelse return null;
    const context_value = obj.get("contextWindow") orelse return null;
    const max_value = obj.get("maxTokens") orelse return null;
    if (id_value != .string or name_value != .string or reasoning_value != .bool or input_value != .array or cost_value != .object) return null;
    const context_window = numberToU64(context_value) orelse return null;
    const max_tokens = numberToU64(max_value) orelse return null;

    var result: GatewayModel = .{
        .id = try gpa.dupe(u8, id_value.string),
        .name = try gpa.dupe(u8, name_value.string),
        .reasoning = reasoning_value.bool,
        .cost = parseCost(cost_value.object),
        .context_window = context_window,
        .max_tokens = max_tokens,
    };
    errdefer result.deinit(gpa);
    for (input_value.array.items) |input| {
        if (input != .string) continue;
        if (std.mem.eql(u8, input.string, "text")) result.input_text = true;
        if (std.mem.eql(u8, input.string, "image")) result.input_image = true;
    }
    if (obj.get("thinkingLevelMap")) |map_value| result.thinking_level_map = try parseThinkingMap(gpa, map_value);
    return result;
}

/// Upstream-style config sanitizer: top-level shape is strict, malformed model
/// records are filtered rather than invalidating otherwise usable models.
pub fn parseGatewayConfig(gpa: std.mem.Allocator, raw: []const u8) !GatewayConfig {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidRadiusGatewayConfig;
    const base_value = parsed.value.object.get("baseUrl") orelse return error.InvalidRadiusGatewayConfig;
    const models_value = parsed.value.object.get("models") orelse return error.InvalidRadiusGatewayConfig;
    if (base_value != .string or models_value != .array) return error.InvalidRadiusGatewayConfig;

    var models: std.ArrayList(GatewayModel) = .empty;
    errdefer {
        for (models.items) |*model| model.deinit(gpa);
        models.deinit(gpa);
    }
    for (models_value.array.items) |value| {
        if (try parseGatewayModel(gpa, value)) |model| try models.append(gpa, model);
    }
    return .{ .base_url = try gpa.dupe(u8, base_value.string), .models = try models.toOwnedSlice(gpa) };
}

/// Add HTTPS when no HTTP(S) scheme is present and strip trailing slashes.
pub fn normalizeGatewayUrl(gpa: std.mem.Allocator, value: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidRadiusGatewayUrl;
    const has_scheme = std.ascii.startsWithIgnoreCase(trimmed, "http://") or std.ascii.startsWithIgnoreCase(trimmed, "https://");
    var end = trimmed.len;
    while (end > 0 and trimmed[end - 1] == '/') end -= 1;
    if (end == 0) return error.InvalidRadiusGatewayUrl;
    if (has_scheme) return gpa.dupe(u8, trimmed[0..end]);
    return std.fmt.allocPrint(gpa, "https://{s}", .{trimmed[0..end]});
}

/// Resolve a root-relative Radius endpoint like WHATWG `new URL(path,gateway)`.
pub fn endpointUrl(gpa: std.mem.Allocator, gateway: []const u8, path: []const u8) ![]u8 {
    const normalized = try normalizeGatewayUrl(gpa, gateway);
    defer gpa.free(normalized);
    const scheme_end = std.mem.indexOf(u8, normalized, "://") orelse return error.InvalidRadiusGatewayUrl;
    const authority_start = scheme_end + 3;
    const slash = std.mem.indexOfScalarPos(u8, normalized, authority_start, '/') orelse normalized.len;
    if (slash == authority_start) return error.InvalidRadiusGatewayUrl;
    if (path.len == 0) return gpa.dupe(u8, normalized[0..slash]);
    return std.fmt.allocPrint(gpa, "{s}{s}{s}", .{ normalized[0..slash], if (path[0] == '/') "" else "/", path });
}

/// Convert a Radius pi-messages API base back to its OAuth/config gateway.
/// Custom Radius providers conventionally expose model base URLs ending in
/// `/v1`, while the OAuth endpoints are rooted one level above it.
pub fn gatewayFromApiBase(gpa: std.mem.Allocator, base_url: []const u8) ![]u8 {
    const normalized = try normalizeGatewayUrl(gpa, base_url);
    errdefer gpa.free(normalized);
    if (std.mem.endsWith(u8, normalized, "/v1")) {
        const trimmed = try gpa.dupe(u8, normalized[0 .. normalized.len - 3]);
        gpa.free(normalized);
        return trimmed;
    }
    return normalized;
}

pub fn loadGatewayConfig(gpa: std.mem.Allocator, io: std.Io, gateway: []const u8, api_key: ?[]const u8) !GatewayConfig {
    return loadGatewayConfigWithOptions(gpa, io, gateway, api_key, .{});
}

pub fn loadGatewayConfigWithOptions(gpa: std.mem.Allocator, io: std.Io, gateway: []const u8, api_key: ?[]const u8, options: bootstrap_http.Options) !GatewayConfig {
    const url = try endpointUrl(gpa, gateway, "/v1/config");
    defer gpa.free(url);
    var headers: std.ArrayList(std.http.Header) = .empty;
    defer headers.deinit(gpa);
    try headers.append(gpa, .{ .name = "accept", .value = "application/json" });
    var authorization: ?[]u8 = null;
    defer if (authorization) |value| gpa.free(value);
    if (api_key) |key| {
        authorization = try std.fmt.allocPrint(gpa, "Bearer {s}", .{key});
        try headers.append(gpa, .{ .name = "authorization", .value = authorization.? });
    }
    var response = try bootstrap_http.request(gpa, io, .{
        .url = url,
        .method = .GET,
        .headers = headers.items,
        .options = options,
    });
    defer response.deinit(gpa);
    if (response.status < 200 or response.status >= 300) return error.RadiusGatewayConfigHttpError;
    return parseGatewayConfig(gpa, response.body);
}

test "Radius gateway URL normalization and endpoint resolution" {
    const gpa = std.testing.allocator;
    const a = try normalizeGatewayUrl(gpa, " radius.example.test/// ");
    defer gpa.free(a);
    try std.testing.expectEqualStrings("https://radius.example.test", a);
    const b = try endpointUrl(gpa, "https://radius.example.test/prefix///", "/v1/config");
    defer gpa.free(b);
    try std.testing.expectEqualStrings("https://radius.example.test/v1/config", b);
}

test "Radius gateway config filters malformed models and owns thinking map" {
    const gpa = std.testing.allocator;
    var config = try parseGatewayConfig(gpa,
        \\{"baseUrl":"https://radius.example/v1","models":[
        \\ {"id":"good","name":"Good","reasoning":true,"thinkingLevelMap":{"off":null,"high":"very_high"},"input":["text","image"],"cost":{"input":1.25,"output":2.5,"cacheRead":0.2,"cacheWrite":1.5},"contextWindow":128000,"maxTokens":16384},
        \\ {"id":"bad","name":"Bad","reasoning":"yes","input":[],"cost":{},"contextWindow":1,"maxTokens":1}
        \\]}
    );
    defer config.deinit(gpa);
    try std.testing.expectEqualStrings("https://radius.example/v1", config.base_url);
    try std.testing.expectEqual(@as(usize, 1), config.models.len);
    const model = config.models[0];
    try std.testing.expect(model.input_text and model.input_image and model.reasoning);
    try std.testing.expectApproxEqAbs(@as(f64, 1.25), model.cost.input, 1e-12);
    try std.testing.expect(model.thinking_level_map.?.off == .unsupported);
    try std.testing.expectEqualStrings("very_high", model.thinking_level_map.?.high.mapped);
}
