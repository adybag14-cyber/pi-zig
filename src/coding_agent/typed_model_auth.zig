//! Private API-key request preparation for actual Main typed catalog rows.
//! It never enters the chat transport enum or chooses an SDK runtime.
const std = @import("std");
const providers = @import("../ai/providers.zig");
const json = @import("../mcp/protocol.zig").json;
const Value = json.Value;
fn get(value: Value, key: []const u8) ?Value {
    return if (value == .object) value.object.get(key) else null;
}
fn text(value: ?Value) ?[]const u8 {
    return if (value != null and value.? == .string) value.?.string else null;
}
fn whitespace(point: u21) bool {
    return switch (point) {
        0x9...0xd, 0x20, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => true,
        else => false,
    };
}
fn ambient(value: []const u8) bool {
    var it = std.unicode.Wtf8View.initUnchecked(value).iterator();
    while (it.nextCodepoint()) |point| if (!whitespace(point)) return true;
    return false;
}
fn ambientName(model: providers.ModelInfo) ?[]const u8 {
    const identity = model.providerName();
    if (std.mem.eql(u8, identity, "typesafe")) return "TYPESAFE_API_KEY";
    const provider = providers.Provider.fromString(identity) orelse return null;
    if (!std.mem.eql(u8, identity, provider.name())) return null;
    return providers.credentialEnvName(provider);
}
pub fn truthy(value: Value) bool {
    return switch (value) {
        .null => false,
        .bool => value.bool,
        .integer => value.integer != 0,
        .float => value.float != 0 and !std.math.isNan(value.float),
        .string => value.string.len > 0,
        .array, .object => true,
        .number_string => (std.fmt.parseFloat(f64, value.number_string) catch 0) != 0,
    };
}
/// Availability checks must not execute configured shell commands or resolve
/// request headers. A configured empty key is still provisionally configured.
pub fn checkConfigured(gpa: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map, model: providers.ModelInfo, provider_config: Value, extension: Value, stored: ?Value, explicit_key: ?[]const u8) !bool {
    const name = ambientName(model);
    if (explicit_key) |key| {
        if (key.len > 0) return true;
        return if (name) |env_name| if (environ.get(env_name)) |value| ambient(value) else false else false;
    }
    if (stored) |credential| {
        if (!std.mem.eql(u8, text(get(credential, "type")) orelse "", "api_key")) return false;
        if (text(get(credential, "key"))) |key| if (key.len > 0) return true;
        return if (name) |env_name| if (environ.get(env_name)) |value| ambient(value) else false else false;
    }
    if (text(get(extension, "apiKey")) orelse text(get(provider_config, "apiKey"))) |raw| {
        if (raw.len > 0 and raw[0] == '!') return true;
        var filtered: std.process.Environ.Map = .init(gpa);
        defer filtered.deinit();
        var fields = environ.iterator();
        while (fields.next()) |field| if (ambient(field.value_ptr.*)) try filtered.put(field.key_ptr.*, field.value_ptr.*);
        var resolver = @import("config_value.zig").Resolver.init(gpa, io, &filtered);
        defer resolver.deinit();
        const value = try resolver.resolve(raw);
        defer if (value) |bytes| gpa.free(bytes);
        return value != null;
    }
    return if (name) |env_name| if (environ.get(env_name)) |value| ambient(value) else false else false;
}
fn header(a: std.mem.Allocator, headers: *Value, name: []const u8, value: []const u8, fold: bool) !void {
    if (fold) {
        var index: usize = 0;
        while (index < headers.object.count()) {
            if (std.ascii.eqlIgnoreCase(headers.object.keys()[index], name)) {
                _ = headers.object.orderedRemove(headers.object.keys()[index]);
            } else index += 1;
        }
    }
    try headers.object.put(a, try a.dupe(u8, name), .{ .string = try a.dupe(u8, value) });
}
fn resolveHeaders(a: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, out: *Value, raw: Value, fold: bool) !void {
    if (raw != .object) return;
    var resolver = @import("config_value.zig").Resolver.init(a, io, env);
    defer resolver.deinit();
    var fields = raw.object.iterator();
    while (fields.next()) |entry| {
        if (entry.value_ptr.* != .string) return error.InvalidTypedModelHeader;
        const resolved = (try resolver.resolve(entry.value_ptr.string)) orelse return error.MissingHeaderConfigValue;
        try header(a, out, entry.key_ptr.*, resolved, fold);
    }
}
fn overlayEnv(env: *std.process.Environ.Map, value: Value) !void {
    if (value != .object) return;
    var fields = value.object.iterator();
    while (fields.next()) |field| if (field.value_ptr.* == .string) try env.put(field.key_ptr.*, field.value_ptr.string);
}
pub fn decorate(gpa: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map, model: providers.ModelInfo, provider_config: Value, extension: Value, credential: ?Value, resolution: Value) !json.Owned {
    var result = try json.Owned.empty(gpa);
    errdefer result.deinit();
    const a = result.arena.allocator();
    if (resolution == .null) {
        result.value = .null;
        return result;
    }
    result.value = try json.clone(a, resolution);
    const authentication = result.value.object.getPtr("auth") orelse return error.InvalidNativeProviderAuthResult;
    if (authentication.* != .object) return error.InvalidNativeProviderAuthResult;
    var root_env: std.process.Environ.Map = .init(a);
    defer root_env.deinit();
    var fields = environ.iterator();
    while (fields.next()) |field| try root_env.put(field.key_ptr.*, field.value_ptr.*);
    if (credential) |value| try overlayEnv(&root_env, get(value, "env") orelse .null);
    try overlayEnv(&root_env, get(result.value, "env") orelse .null);
    var model_env: std.process.Environ.Map = .init(a);
    defer model_env.deinit();
    fields = environ.iterator();
    while (fields.next()) |field| try model_env.put(field.key_ptr.*, field.value_ptr.*);
    try overlayEnv(&model_env, get(result.value, "env") orelse .null);
    const initial_headers = get(authentication.*, "headers");
    var headers: Value = if (initial_headers) |value| if (value == .object) try json.clone(a, value) else .{ .object = .empty } else .{ .object = .empty };
    try resolveHeaders(a, io, &root_env, &headers, get(provider_config, "headers") orelse .null, false);
    try resolveHeaders(a, io, &root_env, &headers, get(extension, "headers") orelse .null, false);
    const auth_header: Value = get(extension, "authHeader") orelse get(provider_config, "authHeader") orelse .{ .bool = false };
    if (auth_header == .bool and auth_header.bool) {
        const key = text(get(authentication.*, "apiKey")) orelse return error.AuthHeaderRequiresApiKey;
        if (key.len == 0) return error.AuthHeaderRequiresApiKey;
        try header(a, &headers, "Authorization", try std.fmt.allocPrint(a, "Bearer {s}", .{key}), false);
    }
    for (model.headers) |field| try header(a, &headers, field.name, field.value, true);
    if (get(extension, "models")) |definitions| if (definitions == .array) for (definitions.array.items) |definition| {
        if (!std.mem.eql(u8, text(get(definition, "type")) orelse "chat", @tagName(model.kind)) or !std.mem.eql(u8, text(get(definition, "id")) orelse "", model.id)) continue;
        try resolveHeaders(a, io, &model_env, &headers, get(definition, "headers") orelse .null, true);
        break;
    };
    if (headers.object.count() > 0 or initial_headers != null) try authentication.object.put(a, "headers", headers);
    return result;
}
pub fn resolve(
    gpa: std.mem.Allocator,
    io: std.Io,
    environ: *const std.process.Environ.Map,
    model: providers.ModelInfo,
    provider_config: Value,
    extension: Value,
    stored: ?Value,
    explicit_key: ?[]const u8,
) !json.Owned {
    if (model.kind == .chat) return error.TypedModelRequired;
    var result = try json.Owned.empty(gpa);
    errdefer result.deinit();
    const a = result.arena.allocator();
    result.value = .null;
    var env: std.process.Environ.Map = .init(a);
    defer env.deinit();
    var fields = environ.iterator();
    while (fields.next()) |field| try env.put(field.key_ptr.*, field.value_ptr.*);
    const credential = if (explicit_key != null) null else stored;
    if (credential) |value| {
        const typ = text(get(value, "type")) orelse return result;
        if (!std.mem.eql(u8, typ, "api_key")) return result;
        if (get(value, "env")) |overlay| if (overlay == .object) {
            var entries = overlay.object.iterator();
            while (entries.next()) |entry| if (entry.value_ptr.* == .string) try env.put(entry.key_ptr.*, entry.value_ptr.string);
        };
    }
    var key: ?[]const u8 = explicit_key;
    const ambient_name = ambientName(model);
    var source: []const u8 = "stored credential";
    if (key == null) if (credential) |value| {
        key = text(get(value, "key"));
    };
    if (key == null and credential == null) {
        if (text(get(extension, "apiKey")) orelse text(get(provider_config, "apiKey"))) |raw| {
            var resolver = @import("config_value.zig").Resolver.init(a, io, &env);
            defer resolver.deinit();
            key = (try resolver.resolve(raw)) orelse return error.MissingTypedModelApiKeyValue;
            source = if (ambient_name != null) "stored credential" else "configured API key";
        }
    }
    if (key == null or key.?.len == 0) {
        if (ambient_name) |env_name| {
            key = null;
            if (environ.get(env_name)) |value| if (ambient(value)) {
                key = value;
                source = env_name;
            };
        }
    }
    if (key == null) return result;
    var auth: Value = .{ .object = .empty };
    try auth.object.put(a, "apiKey", .{ .string = try a.dupe(u8, key.?) });
    var headers: Value = .{ .object = .empty };
    // Provider configuration spreads case-sensitively. The later model header
    // merge removes case-insensitive duplicates, as Models.getAuth does.
    try resolveHeaders(a, io, &env, &headers, get(provider_config, "headers") orelse .null, false);
    try resolveHeaders(a, io, &env, &headers, get(extension, "headers") orelse .null, false);
    const auth_header: Value = get(extension, "authHeader") orelse get(provider_config, "authHeader") orelse .{ .bool = false };
    if (auth_header == .bool and auth_header.bool) {
        if (key.?.len == 0) return error.AuthHeaderRequiresApiKey;
        try header(a, &headers, "Authorization", try std.fmt.allocPrint(a, "Bearer {s}", .{key.?}), false);
    }
    for (model.headers) |entry| try header(a, &headers, entry.name, entry.value, true);
    if (get(extension, "models")) |models| if (models == .array) for (models.array.items) |definition| {
        const kind = text(get(definition, "type")) orelse "chat";
        if (!std.mem.eql(u8, kind, @tagName(model.kind)) or !std.mem.eql(u8, text(get(definition, "id")) orelse "", model.id)) continue;
        try resolveHeaders(a, io, if (std.mem.eql(u8, source, "stored credential") and credential != null) &env else environ, &headers, get(definition, "headers") orelse .null, true);
        break;
    };
    if (headers.object.count() > 0) try auth.object.put(a, "headers", headers);
    result.value = .{ .object = .empty };
    try result.value.object.put(a, "auth", auth);
    try result.value.object.put(a, "source", .{ .string = try a.dupe(u8, source) });
    if (std.mem.eql(u8, source, "stored credential")) if (credential) |value| if (get(value, "env")) |overlay| {
        try result.value.object.put(a, "env", try json.clone(a, overlay));
    };
    return result;
}
