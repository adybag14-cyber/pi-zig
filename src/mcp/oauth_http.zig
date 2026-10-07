//! MCP OAuth metadata and token HTTP lifecycle. Every request joins caller
//! cancellation; refresh/discovery must never continue after sign-in closes.
const std = @import("std");
const protocol = @import("protocol.zig");
const json = protocol.json;
const url = @import("../extensions/url_parser.zig");
const fetch = @import("../ai/http_fetch.zig");
const oauth = @import("oauth.zig");
const metadata = @import("oauth_metadata.zig");
pub const Reply = struct {
    status: u16,
    body: []u8,
    fn deinit(self: *Reply, gpa: std.mem.Allocator) void {
        gpa.free(self.body);
    }
};
pub const Client = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    abort_flag: ?*bool = null,
    timeout_ms: ?u64 = null,
    protocol_version: []const u8 = "2025-11-25",
    request_headers: []const std.http.Header = &.{},
    /// Caller cancellation applies to sign-in. A connection's refresh may
    /// deliberately clear abort_flag and retain a bounded timeout while its
    /// rotation-safe credential transaction saves the server's answer.
    pub fn rotationSafe(self: Client) Client {
        var result = self;
        result.abort_flag = null;
        result.timeout_ms = self.timeout_ms orelse 15_000;
        return result;
    }
    fn request(self: Client, location: []const u8, method: std.http.Method, payload: ?[]const u8, content_type: []const u8) !Reply {
        if (self.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.Canceled;
        var http: std.http.Client = .{ .allocator = self.gpa, .io = self.io };
        defer http.deinit();
        var body: std.Io.Writer.Allocating = .init(self.gpa);
        defer body.deinit();
        var headers: std.ArrayList(std.http.Header) = .empty;
        defer headers.deinit(self.gpa);
        try headers.appendSlice(self.gpa, &.{ .{ .name = "accept", .value = "application/json" }, .{ .name = "MCP-Protocol-Version", .value = self.protocol_version }, .{ .name = "content-type", .value = content_type } });
        try headers.appendSlice(self.gpa, self.request_headers);
        const result = try fetch.fetchControlled(&http, .{ .location = .{ .url = location }, .method = method, .payload = payload, .keep_alive = false, .extra_headers = headers.items, .response_writer = &body.writer }, self.timeout_ms, self.abort_flag);
        return .{ .status = result.status, .body = try body.toOwnedSlice() };
    }
    pub fn protectedMetadata(self: Client, server_url: []const u8, explicit_url: ?[]const u8) !json.Owned {
        var server = try url.parse(self.gpa, server_url, null);
        defer server.deinit(self.gpa);
        const origin = try url.origin(self.gpa, server);
        defer self.gpa.free(origin);
        const suffix = std.mem.trimEnd(u8, server.path, "/");
        const first = if (explicit_url) |location| try self.gpa.dupe(u8, location) else try std.fmt.allocPrint(self.gpa, "{s}/.well-known/oauth-protected-resource{s}", .{ origin, if (std.mem.eql(u8, suffix, "/")) "" else suffix });
        defer self.gpa.free(first);
        var response = try self.request(first, .GET, null, "application/json");
        defer response.deinit(self.gpa);
        if (explicit_url == null and suffix.len != 0 and discoveryMiss(response.status)) {
            const root = try std.fmt.allocPrint(self.gpa, "{s}/.well-known/oauth-protected-resource", .{origin});
            defer self.gpa.free(root);
            const replacement = try self.request(root, .GET, null, "application/json");
            response.deinit(self.gpa);
            response = replacement;
        }
        if (response.status < 200 or response.status >= 300) return error.OAuthProtectedMetadataHttpError;
        return metadata.protected(self.gpa, response.body);
    }
    pub fn authorizationMetadata(self: Client, issuer_url: []const u8, skip_issuer_validation: bool) !?json.Owned {
        const candidates = try discoveryUrls(self.gpa, issuer_url);
        defer {
            for (candidates) |candidate| self.gpa.free(candidate);
            self.gpa.free(candidates);
        }
        for (candidates) |candidate| {
            var response = try self.request(candidate, .GET, null, "application/json");
            defer response.deinit(self.gpa);
            if (discoveryMiss(response.status)) continue;
            if (response.status < 200 or response.status >= 300) return error.OAuthAuthorizationMetadataHttpError;
            var parsed = try metadata.authorization(self.gpa, response.body);
            errdefer parsed.deinit();
            if (parsed.value != .object) return error.InvalidOAuthAuthorizationMetadata;
            if (!skip_issuer_validation) try oauth.validateDiscoveryIssuer(issuer_url, try protocol.text(parsed.value, "issuer"));
            return parsed;
        }
        return null;
    }
    pub fn tokenRequest(self: Client, endpoint: []const u8, form: []const u8) !json.Owned {
        try metadata.endpoint(self.gpa, endpoint);
        var response = try self.request(endpoint, .POST, form, "application/x-www-form-urlencoded");
        defer response.deinit(self.gpa);
        if (response.status < 200 or response.status >= 300) return error.OAuthTokenHttpError;
        var parsed_tokens = try oauth.parseTokens(self.gpa, response.body);
        defer parsed_tokens.deinit();
        var parsed = try json.Owned.empty(self.gpa);
        errdefer parsed.deinit();
        parsed.value = .{ .object = .empty };
        const a = parsed.arena.allocator();
        try parsed.value.object.put(a, "access_token", .{ .string = try a.dupe(u8, parsed_tokens.tokens.access_token) });
        try parsed.value.object.put(a, "token_type", .{ .string = try a.dupe(u8, parsed_tokens.tokens.token_type) });
        if (parsed_tokens.tokens.expires_in) |expires| try parsed.value.object.put(a, "expires_in", .{ .float = expires });
        if (parsed_tokens.tokens.scope) |scope| try parsed.value.object.put(a, "scope", .{ .string = try a.dupe(u8, scope) });
        if (parsed_tokens.tokens.refresh_token) |refresh_token| try parsed.value.object.put(a, "refresh_token", .{ .string = try a.dupe(u8, refresh_token) });
        if (parsed_tokens.tokens.id_token) |id_token| try parsed.value.object.put(a, "id_token", .{ .string = try a.dupe(u8, id_token) });
        return parsed;
    }
};
fn discoveryMiss(status: u16) bool {
    return status == 404 or status == 405;
}
pub fn discoveryUrls(gpa: std.mem.Allocator, issuer_url: []const u8) ![][]u8 {
    var issuer = try url.parse(gpa, issuer_url, null);
    defer issuer.deinit(gpa);
    const origin = try url.origin(gpa, issuer);
    defer gpa.free(origin);
    const path = std.mem.trimEnd(u8, issuer.path, "/");
    const suffix = if (std.mem.eql(u8, path, "/")) "" else path;
    const result = try gpa.alloc([]u8, if (suffix.len == 0) 2 else 3);
    var admitted: usize = 0;
    errdefer {
        for (result[0..admitted]) |value| gpa.free(value);
        gpa.free(result);
    }
    result[0] = try std.fmt.allocPrint(gpa, "{s}/.well-known/oauth-authorization-server{s}", .{ origin, suffix });
    admitted += 1;
    result[1] = try std.fmt.allocPrint(gpa, "{s}/.well-known/openid-configuration{s}", .{ origin, suffix });
    admitted += 1;
    if (result.len == 3) {
        result[2] = try std.fmt.allocPrint(gpa, "{s}{s}/.well-known/openid-configuration", .{ origin, suffix });
        admitted += 1;
    }
    return result;
}
test "mcp.runtime OAuth discovery path ordering follows source issuer path conventions" {
    const gpa = std.testing.allocator;
    const paths = try discoveryUrls(gpa, "https://issuer.example/tenant/");
    defer {
        for (paths) |path| gpa.free(path);
        gpa.free(paths);
    }
    try std.testing.expectEqualStrings("https://issuer.example/.well-known/oauth-authorization-server/tenant", paths[0]);
    try std.testing.expectEqualStrings("https://issuer.example/.well-known/openid-configuration/tenant", paths[1]);
    try std.testing.expectEqualStrings("https://issuer.example/tenant/.well-known/openid-configuration", paths[2]);
}

test "mcp.runtime OAuth discovery and token requests join cancellation during live network I/O" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const fixture = @import("../ai/http_fixture.zig");
    for ([_]bool{ false, true }) |token_request| {
        var observed: std.Io.Event = .unset;
        var release: std.Io.Event = .unset;
        const path = if (token_request) "/token" else "/.well-known/oauth-protected-resource/mcp";
        const server = try fixture.PlanServer.init(gpa, io, &.{.{ .path = path, .body = "{}", .request_observed = &observed, .response_release = &release }});
        defer server.deinit();
        const location = try server.url(gpa, if (token_request) "/token" else "/mcp");
        defer gpa.free(location);
        var aborted = false;
        const Work = struct {
            client: Client,
            location: []const u8,
            token_request: bool,
            fn run(self: *@This()) anyerror!json.Owned {
                return if (self.token_request) self.client.tokenRequest(self.location, "grant_type=refresh_token&refresh_token=fixture") else self.client.protectedMetadata(self.location, null);
            }
        };
        var work: Work = .{ .client = .{ .gpa = gpa, .io = io, .abort_flag = &aborted }, .location = location, .token_request = token_request };
        var future = try io.concurrent(Work.run, .{&work});
        var joined = false;
        defer {
            @atomicStore(bool, &aborted, true, .release);
            release.set(io);
            if (!joined) if (future.cancel(io)) |reply| {
                var owned = reply;
                owned.deinit();
            } else |_| {};
        }
        try observed.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } });
        @atomicStore(bool, &aborted, true, .release);
        const response = future.await(io);
        joined = true;
        if (response) |reply| {
            var owned = reply;
            owned.deinit();
            return error.OAuthCancellationWasIgnored;
        } else |cause| try std.testing.expect(cause == error.Canceled or cause == error.ProviderRequestAborted);
        release.set(io);
        server.finish() catch |cause| switch (cause) {
            error.ConnectionResetByPeer, error.BrokenPipe => {},
            else => return cause,
        };
    }
}
