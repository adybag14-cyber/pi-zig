//! Browser callback and pasted-redirect race, with joined cancellation cleanup.
const std = @import("std");
const urls = @import("../extensions/url_parser.zig");
const parameters = @import("../extensions/url_search_params.zig");
const callback = @import("oauth_callback.zig");
const callback_server = @import("oauth_callback_server.zig");
const authorize_mod = @import("oauth_authorize.zig");
const http = @import("oauth_http.zig");
const Store = @import("oauth_store.zig").Store;
const json = @import("protocol.zig").json;
pub const Prompt = struct {
    context: ?*anyopaque,
    show: *const fn (?*anyopaque, []const u8) anyerror!void,
    /// Implementations must observe this flag and settle before returning.
    read: *const fn (?*anyopaque, std.mem.Allocator, *bool) anyerror!?[]u8,
};
pub const Options = struct {
    flow: authorize_mod.Options,
    callback_url: ?[]const u8 = null,
    callback_port: ?u16 = null,
    prompt: Prompt,
    abort_flag: ?*bool = null,
    timeout_ms: u64 = 300_000,
};
fn first(pairs: []const parameters.Pair, key: []const u8) ?[]const u8 {
    for (pairs) |pair| if (std.mem.eql(u8, pair.name, key)) return pair.value;
    return null;
}
const Wait = struct {
    server: *callback_server.Server,
    state: []const u8,
    path: []const u8,
    redirect_uri: []const u8,
    prompt: Prompt,
    abort_flag: ?*bool,
    prompt_aborted: bool = false,
    deadline: i64,
    fn browser(self: *Wait) !callback.Response {
        return self.server.wait(self.state, self.path, self.abort_flag);
    }
    fn user(self: *Wait) !callback.Response {
        const input = try self.prompt.read(self.prompt.context, self.server.gpa, &self.prompt_aborted);
        defer if (input) |value| self.server.gpa.free(value);
        const value = input orelse return error.McpSignInCancelled;
        if (std.mem.trim(u8, value, " \t\r\n").len == 0) return error.McpSignInCancelled;
        return callback.parsePasted(self.server.gpa, value, self.state, self.redirect_uri);
    }
    fn canceled(self: *Wait) !void {
        while (true) {
            if (self.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.McpSignInCancelled;
            if (std.Io.Clock.awake.now(self.server.io).toMilliseconds() >= self.deadline) return error.OAuthSignInTimeout;
            try self.server.io.sleep(.fromMilliseconds(5), .awake);
        }
    }
    fn run(self: *Wait) !callback.Response {
        const Race = union(enum) { browser: anyerror!callback.Response, user: anyerror!callback.Response, canceled: anyerror!void };
        var queue: [3]Race = undefined;
        var race = std.Io.Select(Race).init(self.server.io, &queue);
        defer {
            @atomicStore(bool, &self.prompt_aborted, true, .release);
            while (race.cancel()) |pending| switch (pending) {
                .browser, .user => |result| if (result) |value| {
                    var response = value;
                    response.deinit(self.server.gpa);
                } else |_| {},
                .canceled => {},
            };
        }
        try race.concurrent(.browser, browser, .{self});
        try race.concurrent(.user, user, .{self});
        try race.concurrent(.canceled, canceled, .{self});
        return switch (try race.await()) {
            .browser, .user => |result| result,
            .canceled => |result| blk: {
                try result;
                break :blk error.McpSignInCancelled;
            },
        };
    }
};
pub fn signIn(client: http.Client, store: Store, options: Options) !void {
    if (options.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.McpSignInCancelled;
    const Work = struct {
        client: http.Client,
        store: Store,
        options: Options,
        aborted: bool = false,
        fn run(self: *@This()) !void {
            var configured = self.options;
            configured.abort_flag = &self.aborted;
            return signInInner(self.client, self.store, configured);
        }
        fn canceled(self: *@This()) !void {
            const deadline = std.Io.Clock.awake.now(self.store.io).toMilliseconds() +| @as(i64, @intCast(@min(self.options.timeout_ms, std.math.maxInt(i64))));
            while (true) {
                if (self.options.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.McpSignInCancelled;
                if (std.Io.Clock.awake.now(self.store.io).toMilliseconds() >= deadline) return error.OAuthSignInTimeout;
                try self.store.io.sleep(.fromMilliseconds(5), .awake);
            }
        }
    };
    var work: Work = .{ .client = client, .store = store, .options = options };
    const Race = union(enum) { result: anyerror!void, canceled: anyerror!void };
    var queue: [2]Race = undefined;
    var race = std.Io.Select(Race).init(store.io, &queue);
    defer {
        @atomicStore(bool, &work.aborted, true, .release);
        while (race.cancel()) |_| {}
    }
    try race.concurrent(.result, Work.run, .{&work});
    try race.concurrent(.canceled, Work.canceled, .{&work});
    switch (try race.await()) {
        .result => |result| {
            if (options.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.McpSignInCancelled;
            try result;
        },
        .canceled => |result| {
            @atomicStore(bool, &work.aborted, true, .release);
            try result;
            return error.McpSignInCancelled;
        },
    }
}
fn signInInner(client: http.Client, store: Store, options: Options) !void {
    if (options.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.McpSignInCancelled;
    const started = std.Io.Clock.awake.now(store.io).toMilliseconds();
    const deadline = started +| @as(i64, @intCast(@min(options.timeout_ms, std.math.maxInt(i64))));
    var configured = client;
    configured.abort_flag = options.abort_flag;
    configured.timeout_ms = client.timeout_ms orelse 15_000;
    var callback_settings = try urls.parse(store.gpa, options.callback_url orelse "http://127.0.0.1/callback", null);
    defer callback_settings.deinit(store.gpa);
    const redirect_host = std.mem.trim(u8, callback_settings.host orelse return error.InvalidOAuthCallbackHost, "[]");
    const listen_host = if (std.mem.eql(u8, redirect_host, "localhost")) "127.0.0.1" else redirect_host;
    const required_port = callback_settings.port orelse options.callback_port;
    var stored = try store.load(options.flow.name, options.flow.server_url, null);
    defer if (stored) |*value| value.deinit();
    var preferred_port: u16 = required_port orelse 0;
    if (required_port == null) if (stored) |value| if (json.get(value.value, "clientInformation")) |information| if (json.get(information, "redirect_uris")) |redirects| if (redirects == .array and redirects.array.items.len != 0) {
        var registered = try urls.parse(store.gpa, try json.asString(redirects.array.items[0]), null);
        defer registered.deinit(store.gpa);
        preferred_port = registered.port orelse 0;
    };
    var cimd_path: ?[]u8 = null;
    defer if (cimd_path) |value| store.gpa.free(value);
    var extra: [1][]const u8 = undefined;
    if (options.flow.cimd) {
        const id = try callback.callbackId(store.gpa, options.flow.server_url);
        defer store.gpa.free(id);
        cimd_path = try std.fmt.allocPrint(store.gpa, "/callback/{s}", .{id});
        extra[0] = cimd_path.?;
    }
    const listener_options: callback_server.Options = .{ .host = listen_host, .redirect_host = redirect_host, .port = preferred_port, .path = callback_settings.path, .extra_paths = if (cimd_path != null) &extra else &.{}, .timeout_ms = options.timeout_ms };
    const server = callback_server.Server.listen(store.gpa, store.io, listener_options) catch |cause| blk: {
        if (required_port != null or preferred_port == 0) return cause;
        var fallback = listener_options;
        fallback.port = 0;
        break :blk try callback_server.Server.listen(store.gpa, store.io, fallback);
    };
    defer server.deinit();
    const fixed = if (callback_settings.port != null) options.callback_url else null;
    var fixed_port_uri: ?[]u8 = null;
    defer if (fixed_port_uri) |value| store.gpa.free(value);
    if (fixed == null and options.callback_port != null) {
        callback_settings.port = options.callback_port;
        fixed_port_uri = try urls.serialize(store.gpa, callback_settings);
    }
    const redirect_uri = fixed orelse fixed_port_uri orelse server.redirect_uri;
    if (stored) |*value| {
        _ = value.value.object.orderedRemove("oauthState");
        var keep_client = options.flow.client_id != null;
        const information = json.get(value.value, "clientInformation");
        if (!keep_client) {
            if (options.flow.cimd) keep_client = information == null else if (information) |info| if (json.get(info, "redirect_uris")) |redirects| if (redirects == .array) for (redirects.array.items) |item| {
                if (item == .string and std.mem.eql(u8, item.string, redirect_uri)) keep_client = true;
            };
        }
        if (!keep_client) for ([_][]const u8{ "clientInformation", "tokens", "tokensExpireAt" }) |field| {
            _ = value.value.object.orderedRemove(field);
        };
        try store.save(options.flow.name, options.flow.server_url, value.value, null);
    }
    var flow_options = options.flow;
    flow_options.redirect_uri = redirect_uri;
    var metadata = try json.Owned.empty(store.gpa);
    defer metadata.deinit();
    const a = metadata.arena.allocator();
    metadata.value = try json.clone(a, flow_options.client_metadata);
    if (metadata.value != .object) return error.InvalidOAuthClientMetadata;
    if (json.get(metadata.value, "redirect_uris") == null) {
        var redirects = std.json.Array.init(a);
        try redirects.append(.{ .string = try a.dupe(u8, redirect_uri) });
        try metadata.value.object.put(a, "redirect_uris", .{ .array = redirects });
    }
    for ([_]struct { key: []const u8, items: []const []const u8 }{ .{ .key = "grant_types", .items = &.{ "authorization_code", "refresh_token" } }, .{ .key = "response_types", .items = &.{"code"} } }) |defaults| if (json.get(metadata.value, defaults.key) == null) {
        var values = std.json.Array.init(a);
        for (defaults.items) |value| try values.append(.{ .string = value });
        try metadata.value.object.put(a, defaults.key, .{ .array = values });
    };
    if (json.get(metadata.value, "token_endpoint_auth_method") == null) try metadata.value.object.put(a, "token_endpoint_auth_method", .{ .string = if (flow_options.client_secret != null and flow_options.client_secret.?.len != 0) "client_secret_post" else "none" });
    flow_options.client_metadata = metadata.value;
    var outcome = try authorize_mod.authorize(configured, store, flow_options);
    defer outcome.deinit(store.gpa);
    if (outcome == .authorized) return;
    var authorization_url = try urls.parse(store.gpa, outcome.redirect.url, null);
    defer authorization_url.deinit(store.gpa);
    var pairs = try parameters.parse(store.gpa, authorization_url.query orelse "");
    defer parameters.freePairs(store.gpa, &pairs);
    const state = first(pairs.items, "state") orelse return error.OAuthStateMissing;
    const authorization_redirect = first(pairs.items, "redirect_uri") orelse redirect_uri;
    var actual_redirect = try urls.parse(store.gpa, authorization_redirect, null);
    defer actual_redirect.deinit(store.gpa);
    try options.prompt.show(options.prompt.context, outcome.redirect.url);
    var waiter: Wait = .{ .server = server, .state = state, .path = actual_redirect.path, .redirect_uri = authorization_redirect, .prompt = options.prompt, .abort_flag = options.abort_flag, .deadline = deadline };
    var response = try waiter.run();
    defer response.deinit(store.gpa);
    if (response.rejection != null) return error.OAuthAuthorizationDenied;
    flow_options.authorization_code = response.code;
    flow_options.response_issuer = response.issuer;
    var completed = try authorize_mod.authorize(configured, store, flow_options);
    defer completed.deinit(store.gpa);
    if (completed != .authorized) return error.OAuthAuthorizationNotCompleted;
}

test "mcp.runtime native MCP sign-in pasted redirect wins and joins browser loser before closing" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &buffer);
    var store = try Store.init(gpa, io, buffer[0..count]);
    defer store.deinit();
    const server = try @import("../ai/http_fixture.zig").PlanServer.init(gpa, io, &.{.{ .path = "/token", .body = "{\"access_token\":\"signed-in\",\"token_type\":\"Bearer\"}", .payload_contains = "code=pasted-code" }});
    defer server.deinit();
    const issuer = try server.url(gpa, "/authorize");
    defer gpa.free(issuer);
    const endpoint = try server.url(gpa, "/token");
    defer gpa.free(endpoint);
    const state_bytes = try std.json.Stringify.valueAlloc(gpa, .{
        .clientInformation = .{ .client_id = "client", .redirect_uris = [_][]const u8{"http://127.0.0.1/callback"} },
        .discovery = .{ .authorizationServerUrl = issuer, .authorizationServerMetadata = .{ .issuer = issuer, .authorization_endpoint = issuer, .token_endpoint = endpoint, .response_types_supported = [_][]const u8{"code"}, .token_endpoint_auth_methods_supported = [_][]const u8{"none"} } },
    }, .{});
    defer gpa.free(state_bytes);
    var state = try json.Owned.parse(gpa, state_bytes);
    defer state.deinit();
    try store.save("server", "https://service.example/mcp", state.value, null);
    const Reader = struct {
        gpa: std.mem.Allocator,
        input: ?[]u8 = null,
        shown: bool = false,
        fn show(raw: ?*anyopaque, location: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.shown = true;
            var url = try urls.parse(self.gpa, location, null);
            defer url.deinit(self.gpa);
            var pairs = try parameters.parse(self.gpa, url.query.?);
            defer parameters.freePairs(self.gpa, &pairs);
            const redirect = first(pairs.items, "redirect_uri").?;
            self.input = try std.fmt.allocPrint(self.gpa, "{s}?state={s}&code=pasted-code", .{ redirect, first(pairs.items, "state").? });
        }
        fn read(raw: ?*anyopaque, allocator: std.mem.Allocator, _: *bool) !?[]u8 {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            return try allocator.dupe(u8, self.input.?);
        }
    };
    var reader: Reader = .{ .gpa = gpa };
    defer if (reader.input) |value| gpa.free(value);
    try signIn(.{ .gpa = gpa, .io = io }, store, .{ .flow = .{ .name = "server", .server_url = "https://service.example/mcp", .redirect_uri = "http://127.0.0.1/callback", .client_id = "client", .client_metadata = .{ .object = .empty } }, .prompt = .{ .context = &reader, .show = Reader.show, .read = Reader.read } });
    try std.testing.expect(reader.shown);
    var saved = (try store.load("server", "https://service.example/mcp", null)).?;
    defer saved.deinit();
    try std.testing.expectEqualStrings("signed-in", try @import("protocol.zig").text(json.get(saved.value, "tokens").?, "access_token"));
    try server.finish();
}

test "mcp.runtime sign-in whole deadline and cancellation stop stalled discovery and join listener cleanup" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    for ([_]bool{ false, true }) |cancel| {
        var scratch = std.testing.tmpDir(.{});
        defer scratch.cleanup();
        var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const count = try scratch.dir.realPath(io, &buffer);
        var store = try Store.init(gpa, io, buffer[0..count]);
        defer store.deinit();
        var observed: std.Io.Event = .unset;
        var release: std.Io.Event = .unset;
        const server = try @import("../ai/http_fixture.zig").PlanServer.init(gpa, io, &.{.{ .path = "/.well-known/oauth-protected-resource/mcp", .body = "{}", .request_observed = &observed, .response_release = &release }});
        defer server.deinit();
        const location = try server.url(gpa, "/mcp");
        defer gpa.free(location);
        const Dummy = struct {
            fn show(_: ?*anyopaque, _: []const u8) !void {
                return error.UnexpectedSignInPrompt;
            }
            fn read(_: ?*anyopaque, _: std.mem.Allocator, _: *bool) !?[]u8 {
                return error.UnexpectedSignInPrompt;
            }
        };
        var aborted = false;
        const Work = struct {
            store: Store,
            location: []const u8,
            flag: *bool,
            cancel: bool,
            fn run(self: *@This()) !void {
                try signIn(.{ .gpa = self.store.gpa, .io = self.store.io }, self.store, .{
                    .flow = .{ .name = "server", .server_url = self.location, .redirect_uri = "http://127.0.0.1/callback", .client_metadata = .{ .object = .empty } },
                    .prompt = .{ .context = null, .show = Dummy.show, .read = Dummy.read },
                    .abort_flag = self.flag,
                    .timeout_ms = if (self.cancel) 5000 else 300,
                });
            }
        };
        var work: Work = .{ .store = store, .location = location, .flag = &aborted, .cancel = cancel };
        var future = try io.concurrent(Work.run, .{&work});
        var joined = false;
        defer if (!joined) {
            @atomicStore(bool, &aborted, true, .release);
            release.set(io);
            future.cancel(io) catch {};
        };
        try observed.wait(io);
        const started = std.Io.Clock.awake.now(io).toMilliseconds();
        if (cancel) @atomicStore(bool, &aborted, true, .release);
        const result = future.await(io);
        joined = true;
        try std.testing.expectError(if (cancel) error.McpSignInCancelled else error.OAuthSignInTimeout, result);
        try std.testing.expect(std.Io.Clock.awake.now(io).toMilliseconds() - started < 1000);
        release.set(io);
    }
}
