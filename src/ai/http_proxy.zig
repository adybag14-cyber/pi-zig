//! Environment and settings driven HTTP(S) proxy selection.
//!
//! The original Pi runtime installs one environment-aware HTTP dispatcher for
//! every provider. Zig's standard HTTP client has native HTTP CONNECT and TLS
//! proxy support, but it does not apply NO_PROXY and clients must explicitly
//! initialize proxy state. This module supplies the missing per-request bridge.
const std = @import("std");

pub const Config = struct {
    /// Process/provider environment. Lower-case variables outrank upper-case,
    /// matching the original provider environment resolver.
    environ: ?*const std.process.Environ.Map = null,
    /// Global settings.json `httpProxy`. It fills HTTP_PROXY/HTTPS_PROXY only
    /// when the corresponding environment variable is absent.
    setting: ?[]const u8 = null,
};

pub const Error = error{
    InvalidTargetUrl,
    UnsupportedTargetProtocol,
    InvalidProxyUrl,
    UnsupportedProxyProtocol,
    ProxyHostMissing,
};

pub const Source = enum { environment, setting, all_proxy };

pub const Resolved = struct {
    url: []const u8,
    source: Source,
    target_protocol: std.http.Client.Protocol,
};

/// Resolve the effective proxy for one target URL. Returned URL storage is
/// allocated from `arena` only when a scheme must be added.
pub fn resolve(
    arena: std.mem.Allocator,
    target_url: []const u8,
    config: Config,
) !?Resolved {
    const target_uri = std.Uri.parse(target_url) catch return Error.InvalidTargetUrl;
    const target_protocol = std.http.Client.Protocol.fromUri(target_uri) orelse return Error.UnsupportedTargetProtocol;
    const target_host = target_uri.getHostAlloc(arena) catch |err| switch (err) {
        error.UriMissingHost => return Error.InvalidTargetUrl,
        error.OutOfMemory => return error.OutOfMemory,
    };
    const target_port = target_uri.port orelse defaultPort(target_uri.scheme) orelse return Error.UnsupportedTargetProtocol;

    if (!shouldProxyHost(config.environ, target_host.bytes, target_port)) return null;

    const protocol_proxy = proxyEnvironment(config.environ, target_uri.scheme);
    const trimmed_setting = if (config.setting) |value| std.mem.trim(u8, value, " \t\r\n") else "";
    const selected: struct { value: []const u8, source: Source } = if (protocol_proxy) |value|
        .{ .value = value, .source = .environment }
    else if (trimmed_setting.len > 0 and (target_protocol == .plain or target_protocol == .tls))
        .{ .value = trimmed_setting, .source = .setting }
    else if (getProxyEnv(config.environ, "all_proxy", "ALL_PROXY")) |value|
        .{ .value = value, .source = .all_proxy }
    else
        return null;

    const raw = std.mem.trim(u8, selected.value, " \t\r\n");
    if (raw.len == 0) return null;
    const normalized = if (std.mem.indexOf(u8, raw, "://") == null)
        try std.fmt.allocPrint(arena, "{s}://{s}", .{ target_uri.scheme, raw })
    else
        raw;

    const proxy_uri = std.Uri.parse(normalized) catch return Error.InvalidProxyUrl;
    _ = std.http.Client.Protocol.fromUri(proxy_uri) orelse return Error.UnsupportedProxyProtocol;
    _ = proxy_uri.getHostAlloc(arena) catch |err| switch (err) {
        error.UriMissingHost => return Error.ProxyHostMissing,
        error.OutOfMemory => return error.OutOfMemory,
    };

    return .{ .url = normalized, .source = selected.source, .target_protocol = target_protocol };
}

/// Configure one freshly-created std.http.Client for `target_url`. The caller
/// must keep `arena` alive until after `client.deinit()`.
pub fn configureClient(
    client: *std.http.Client,
    arena: std.mem.Allocator,
    target_url: []const u8,
    config: Config,
) !bool {
    const selected = (try resolve(arena, target_url, config)) orelse return false;

    // Reuse Zig's proxy URI/auth parser and CONNECT implementation. A synthetic
    // map intentionally contains only the selected protocol so unrelated
    // traffic cannot accidentally inherit the wrong proxy.
    // The proxy parser may retain slices into this synthetic map. Both the map
    // backing storage and parsed proxy therefore deliberately live in `arena`.
    var map = std.process.Environ.Map.init(arena);
    switch (selected.target_protocol) {
        .plain => try map.put("http_proxy", selected.url),
        .tls => try map.put("https_proxy", selected.url),
    }
    try client.initDefaultProxies(arena, &map);
    return true;
}

/// Compatibility form used by raw secure transports. `managed_proxy` follows
/// the same fallback semantics as global settings.json `httpProxy`; callers
/// that need an explicit override pass a null environment.
pub fn configureClientForTarget(
    client: *std.http.Client,
    arena: std.mem.Allocator,
    target_url: []const u8,
    environ: ?*const std.process.Environ.Map,
    managed_proxy: ?[]const u8,
) !bool {
    return configureClient(client, arena, target_url, .{
        .environ = environ,
        .setting = managed_proxy,
    });
}

fn defaultPort(scheme: []const u8) ?u16 {
    if (std.ascii.eqlIgnoreCase(scheme, "http") or std.ascii.eqlIgnoreCase(scheme, "ws")) return 80;
    if (std.ascii.eqlIgnoreCase(scheme, "https") or std.ascii.eqlIgnoreCase(scheme, "wss")) return 443;
    if (std.ascii.eqlIgnoreCase(scheme, "ftp")) return 21;
    if (std.ascii.eqlIgnoreCase(scheme, "gopher")) return 70;
    return null;
}

fn proxyEnvironment(environ: ?*const std.process.Environ.Map, scheme: []const u8) ?[]const u8 {
    if (std.ascii.eqlIgnoreCase(scheme, "http")) return getProxyEnv(environ, "http_proxy", "HTTP_PROXY");
    if (std.ascii.eqlIgnoreCase(scheme, "https")) return getProxyEnv(environ, "https_proxy", "HTTPS_PROXY");
    if (std.ascii.eqlIgnoreCase(scheme, "ws")) return getProxyEnv(environ, "ws_proxy", "WS_PROXY");
    if (std.ascii.eqlIgnoreCase(scheme, "wss")) return getProxyEnv(environ, "wss_proxy", "WSS_PROXY");
    return null;
}

fn getProxyEnv(environ: ?*const std.process.Environ.Map, lower: []const u8, upper: []const u8) ?[]const u8 {
    const map = environ orelse return null;
    if (map.get(lower)) |value| if (std.mem.trim(u8, value, " \t\r\n").len > 0) return value;
    if (map.get(upper)) |value| if (std.mem.trim(u8, value, " \t\r\n").len > 0) return value;
    return null;
}

pub fn shouldProxyHost(environ: ?*const std.process.Environ.Map, hostname: []const u8, port: u16) bool {
    const raw = getProxyEnv(environ, "no_proxy", "NO_PROXY") orelse return true;
    const no_proxy = std.mem.trim(u8, raw, " \t\r\n");
    if (no_proxy.len == 0) return true;
    if (std.mem.eql(u8, no_proxy, "*")) return false;

    var entries = std.mem.tokenizeAny(u8, no_proxy, ", \t\r\n");
    while (entries.next()) |entry_raw| {
        var entry = entry_raw;
        var entry_port: ?u16 = null;

        // Preserve bracketed IPv6 and only interpret the final colon as a port
        // when its suffix is a valid decimal u16.
        if (std.mem.lastIndexOfScalar(u8, entry, ':')) |colon| {
            if (colon + 1 < entry.len) {
                if (std.fmt.parseUnsigned(u16, entry[colon + 1 ..], 10)) |parsed_port| {
                    entry_port = parsed_port;
                    entry = entry[0..colon];
                } else |_| {}
            }
        }
        if (entry_port) |required| if (required != port) continue;
        if (entry.len >= 2 and entry[0] == '[' and entry[entry.len - 1] == ']') entry = entry[1 .. entry.len - 1];
        if (entry.len == 0) continue;

        if (entry[0] != '.' and entry[0] != '*') {
            if (std.ascii.eqlIgnoreCase(hostname, entry)) return false;
            continue;
        }
        if (entry[0] == '*') entry = entry[1..];
        if (entry.len == 0) return false;
        if (asciiEndsWithIgnoreCase(hostname, entry)) return false;
    }
    return true;
}

fn asciiEndsWithIgnoreCase(haystack: []const u8, suffix: []const u8) bool {
    if (suffix.len > haystack.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[haystack.len - suffix.len ..], suffix);
}

test "proxy resolution matches environment precedence settings and no_proxy" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("HTTPS_PROXY", "http://env-proxy.example:8080");
    try env.put("ALL_PROXY", "http://all-proxy.example:9000");

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const selected = (try resolve(arena, "https://api.example.com/v1", .{
        .environ = &env,
        .setting = "http://settings-proxy.example:7890",
    })).?;
    try std.testing.expectEqual(Source.environment, selected.source);
    try std.testing.expectEqualStrings("http://env-proxy.example:8080", selected.url);

    try env.put("NO_PROXY", "api.example.com, .internal.example:443");
    try std.testing.expect((try resolve(arena, "https://api.example.com/v1", .{ .environ = &env, .setting = "http://settings" })) == null);
    try std.testing.expect((try resolve(arena, "https://node.internal.example/v1", .{ .environ = &env })) == null);
    try std.testing.expect((try resolve(arena, "https://node.internal.example:444/v1", .{ .environ = &env })) != null);
}

test "settings proxy fills protocol environment before all_proxy and accepts credentials" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("ALL_PROXY", "http://all.example:9000");

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const selected = (try resolve(arena, "https://api.example/v1", .{
        .environ = &env,
        .setting = "proxy-user:proxy-pass@settings.example:7890",
    })).?;
    try std.testing.expectEqual(Source.setting, selected.source);
    try std.testing.expectEqualStrings("https://proxy-user:proxy-pass@settings.example:7890", selected.url);

    var client: std.http.Client = .{ .allocator = gpa, .io = std.testing.io };
    defer client.deinit();
    try std.testing.expect(try configureClient(&client, arena, "https://api.example/v1", .{
        .setting = "http://proxy-user:proxy-pass@settings.example:7890",
    }));
    const proxy = client.https_proxy.?;
    try std.testing.expectEqualStrings("settings.example", proxy.host.bytes);
    try std.testing.expectEqual(@as(u16, 7890), proxy.port);
    try std.testing.expect(proxy.authorization != null);
    try std.testing.expect(std.mem.startsWith(u8, proxy.authorization.?, "Basic "));
}

test "unsupported proxy schemes are rejected" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    try std.testing.expectError(Error.UnsupportedProxyProtocol, resolve(
        arena_state.allocator(),
        "https://api.example/v1",
        .{ .setting = "socks5://127.0.0.1:1080" },
    ));
}
