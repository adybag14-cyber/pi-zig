//! Trusted configured MCP catalogs, model declarations and retained native connections.
const std = @import("std");
const builtin = @import("builtin");
const protocol = @import("protocol.zig");
const json = protocol.json;
const Value = protocol.Value;
const config = @import("config.zig");
const connection = @import("connection.zig");
const session = @import("session.zig");
const capabilities = @import("capabilities.zig");
const stdio = @import("stdio_transport.zig");
const http = @import("http_transport.zig");
const projection = @import("agent_tools.zig");
const resource_tools = @import("resource_tools.zig");
const tool_names = @import("tool_names.zig");
const agent = @import("../agent/loop.zig");
const tools = @import("../agent/tools.zig");
const startup = @import("../durable/startup.zig");
const Resolver = @import("../coding_agent/config_value.zig").Resolver;
const tool_search = @import("tool_search.zig");
const startup_pool = @import("configured_startup.zig");
const oauth_store = @import("oauth_store.zig");
const oauth_provider = @import("oauth_provider.zig");
const oauth_authorize = @import("oauth_authorize.zig");
const oauth_signin = @import("oauth_signin.zig");
const oauth_challenge = @import("oauth_challenge.zig");

pub const Options = struct { agent_dir: []const u8, cwd: []const u8, project_trusted: bool = false, environ: *const std.process.Environ.Map, reserved_names: []const []const u8 = &.{}, output_root: ?[]const u8 = null, max_servers: usize = 64, provider_token_context: ?*anyopaque = null, provider_token: ?*const fn (?*anyopaque, std.mem.Allocator, []const u8) anyerror!?[]u8 = null, management_all: bool = false };
pub const ParameterIdentity = enum { remote_json, resource_list, resource_read };
const CatalogStorage = struct {
    owned: json.Owned,
    references: usize = 1,
    fn release(self: *CatalogStorage, gpa: std.mem.Allocator) void {
        std.debug.assert(self.references > 0);
        self.references -= 1;
        if (self.references != 0) return;
        self.owned.deinit();
        gpa.destroy(self);
    }
};
pub const Descriptor = struct { server: *Server, raw_name: []const u8, name: []const u8, schema: Value, codemode_metadata: ?Value = null, exposure: config.Exposure = .direct, loaded: bool = false, resource: bool = false, definition_id: u64, parameter_id: u64 = 0, parameter_body_id: u64 = 0, raw_parameters: ?Value = null, namespace_id: u64 = 0, storage: ?*CatalogStorage = null, parameter_identity: ParameterIdentity = .remote_json };
pub const Server = struct {
    owner: *Service,
    name: []const u8,
    config: Value,
    connection: connection.Connection,
    timeout_ms: f64,
    auth_provider: ?oauth_provider.Provider = null,
    auth_arena: std.heap.ArenaAllocator,
    challenge: ?[]u8 = null,
    challenge_mutex: std.Io.Mutex = .init,
    sign_in_mutex: std.Io.Mutex = .init,
    sign_in_changed: std.Io.Condition = .init,
    sign_in_active: bool = false,
    sign_in_aborted: bool = false,
    lifecycle_mutex: std.Io.Mutex = .init,
    lifecycle_changed: std.Io.Condition = .init,
    reconnect_active: bool = false,
    reconnect_callers: usize = 0,
    has_resources: bool = false,
    resources_count: usize = 0,
    resource_templates_count: usize = 0,
    discovery: ?json.Owned = null,
    refresh_mutex: std.Io.Mutex = .init,
    refresh_group: std.Io.Group = .init,
    fn notified(raw: ?*anyopaque, client: *session.Client, method: []const u8, _: ?Value) !void {
        const self: *Server = @ptrCast(@alignCast(raw.?));
        const kind: enum { tools, resources } = if (std.mem.eql(u8, method, "notifications/tools/list_changed")) .tools else if (std.mem.eql(u8, method, "notifications/resources/list_changed")) .resources else return;
        self.refresh_mutex.lockUncancelable(self.owner.io);
        defer self.refresh_mutex.unlock(self.owner.io);
        if (self.owner.closing.load(.acquire) or !self.connection.isCurrent(client)) return;
        const borrow = self.connection.pinCallbackClient(client) orelse return;
        self.refresh_group.concurrent(self.owner.io, refresh, .{ self, borrow, kind == .resources }) catch |err| {
            borrow.release();
            return err;
        };
    }
    fn refresh(self: *Server, borrow: connection.Borrow, resources: bool) void {
        defer borrow.release();
        self.refreshInner(borrow.client, resources) catch |err| {
            if (self.owner.closing.load(.acquire) or err == error.Canceled) return;
            self.owner.catalog_mutex.lockUncancelable(self.owner.io);
            defer self.owner.catalog_mutex.unlock(self.owner.io);
            if (!self.connection.isCurrent(borrow.client)) return;
            self.owner.diagnostic(self.name, @errorName(err)) catch {};
        };
    }
    fn refreshInner(self: *Server, client: *session.Client, resources: bool) !void {
        const service = self.owner;
        var candidate = try json.Owned.empty(service.gpa);
        defer candidate.deinit();
        {
            service.catalog_mutex.lockUncancelable(service.io);
            defer service.catalog_mutex.unlock(service.io);
            if (service.closing.load(.acquire) or !self.connection.isCurrent(client)) return;
            const previous = self.discovery orelse return;
            candidate.value = try json.clone(candidate.arena.allocator(), previous.value);
        }
        const a = candidate.arena.allocator();
        if (resources) {
            const counts = try Service.resourceCounts(self);
            try candidate.value.object.put(a, "resourcesCount", .{ .integer = @intCast(counts.resources) });
            try candidate.value.object.put(a, "resourceTemplatesCount", .{ .integer = @intCast(counts.templates) });
        } else {
            var listed = try capabilities.listAll(client, .tools, .{ .timeout_ms = self.timeout_ms });
            defer listed.deinit();
            try candidate.value.object.put(a, "tools", try json.clone(a, listed.value));
        }
        service.catalog_mutex.lockUncancelable(service.io);
        defer service.catalog_mutex.unlock(service.io);
        if (service.closing.load(.acquire) or !self.connection.isCurrent(client)) return;
        // Resource and tool notifications can finish in either order. Update
        // only the field this request fetched before rebuilding definitions.
        if (self.discovery) |current| {
            inline for (.{ "tools", "resourcesCount", "resourceTemplatesCount" }) |key| {
                const fetched = if (comptime std.mem.eql(u8, key, "tools")) !resources else resources;
                if (!fetched) try candidate.value.object.put(a, key, try json.clone(a, try protocol.field(current.value, key)));
            }
        }
        try service.publishDiscoveryWithBodies(self, candidate.value, resources);
    }
    fn authToken(raw: ?*anyopaque, gpa: std.mem.Allocator, _: ?*bool) !?[]u8 {
        const self: *Server = @ptrCast(@alignCast(raw.?));
        if (self.auth_provider) |*provider| return provider.token();
        if (json.get(self.config, "auth")) |auth| {
            const resolve = self.owner.provider_token orelse return error.McpProviderTokenUnavailable;
            return resolve(self.owner.provider_token_context, gpa, try protocol.text(auth, "provider"));
        }
        return null;
    }
    fn unauthorized(raw: ?*anyopaque, token: ?[]const u8, challenge: ?[]const u8) !void {
        const self: *Server = @ptrCast(@alignCast(raw.?));
        const retained = if (challenge) |value| try self.owner.gpa.dupe(u8, value) else null;
        self.challenge_mutex.lockUncancelable(self.owner.io);
        if (self.challenge) |previous| self.owner.gpa.free(previous);
        self.challenge = retained;
        self.challenge_mutex.unlock(self.owner.io);
        if (self.auth_provider) |*provider| return provider.unauthorizedChallenge(token, challenge);
        return error.McpOAuthAuthorizationRequired;
    }
    fn unusedTokenOptions(_: ?*anyopaque, _: Value) !@import("oauth_flow.zig").TokenOptions {
        return error.McpOAuthFlowRequired;
    }
    fn resolveFlow(raw: ?*anyopaque, state: Value, challenge_header: ?[]const u8) !oauth_authorize.Options {
        const self: *Server = @ptrCast(@alignCast(raw.?));
        _ = self.auth_arena.reset(.retain_capacity);
        const a = self.auth_arena.allocator();
        return self.flowOptions(a, state, challenge_header);
    }
    fn flowOptions(self: *Server, a: std.mem.Allocator, state: Value, challenge_header: ?[]const u8) !oauth_authorize.Options {
        const oauth = json.get(self.config, "oauth") orelse Value{ .object = .empty };
        var resolver = Resolver.init(a, self.owner.io, &self.owner.environment);
        defer resolver.deinit();
        const client_secret = if (json.get(oauth, "clientSecret")) |value| try resolver.resolve(try json.asString(value)) orelse return error.UnresolvedMcpConfigValue else null;
        var redirect: []const u8 = if (json.get(oauth, "callbackUrl")) |value| try json.asString(value) else "http://127.0.0.1/callback";
        if (json.get(oauth, "callbackPort")) |value| {
            var record = try @import("../extensions/url_parser.zig").parse(a, redirect, null);
            record.port = @intCast(try json.asInteger(value));
            redirect = try @import("../extensions/url_parser.zig").serialize(a, record);
        } else if (json.get(state, "clientInformation")) |information| if (json.get(information, "redirect_uris")) |uris| if (uris == .array and uris.array.items.len != 0) {
            redirect = try json.asString(uris.array.items[0]);
        };
        var challenge = try oauth_challenge.parse(a, challenge_header);
        defer challenge.deinit();
        var metadata: Value = .{ .object = .empty };
        try metadata.object.put(a, "client_name", json.get(oauth, "clientName") orelse .{ .string = "pi" });
        var uris = std.json.Array.init(a);
        try uris.append(.{ .string = try a.dupe(u8, redirect) });
        try metadata.object.put(a, "redirect_uris", .{ .array = uris });
        var grants = std.json.Array.init(a);
        try grants.append(.{ .string = "authorization_code" });
        try grants.append(.{ .string = "refresh_token" });
        try metadata.object.put(a, "grant_types", .{ .array = grants });
        var responses = std.json.Array.init(a);
        try responses.append(.{ .string = "code" });
        try metadata.object.put(a, "response_types", .{ .array = responses });
        try metadata.object.put(a, "token_endpoint_auth_method", .{ .string = if (client_secret != null and client_secret.?.len != 0) "client_secret_post" else "none" });
        return .{
            .name = self.name,
            .server_url = try protocol.text(self.config, "url"),
            .redirect_uri = try a.dupe(u8, redirect),
            .client_metadata = metadata,
            .client_id = if (json.get(oauth, "clientId")) |value| try json.asString(value) else null,
            .client_secret = client_secret,
            .cimd = if (json.get(oauth, "clientRegistration")) |value| value == .string and std.mem.eql(u8, value.string, "cimd") else false,
            .scope = if (json.get(challenge.value, "scope")) |value| try a.dupe(u8, try json.asString(value)) else if (json.get(oauth, "scope")) |value| try json.asString(value) else null,
            .resource_metadata_url = if (json.get(challenge.value, "resourceMetadataUrl")) |value| try a.dupe(u8, try json.asString(value)) else null,
            .authorization_metadata_url = if (json.get(oauth, "authServerMetadataUrl")) |value| try json.asString(value) else null,
        };
    }
    fn createTransport(raw: ?*anyopaque, gpa: std.mem.Allocator, io: std.Io, _: usize) !connection.Lease {
        const self: *Server = @ptrCast(@alignCast(raw.?));
        const owner = self.owner;
        var resolver = Resolver.init(gpa, io, &owner.environment);
        defer resolver.deinit();
        if (json.get(self.config, "url")) |value| {
            var headers: std.ArrayList(std.http.Header) = .empty;
            defer {
                for (headers.items) |header| {
                    gpa.free(header.name);
                    gpa.free(header.value);
                }
                headers.deinit(gpa);
            }
            if (json.get(self.config, "headers")) |map| {
                var iterator = map.object.iterator();
                while (iterator.next()) |entry| {
                    const resolved = try resolver.resolve(try json.asString(entry.value_ptr.*)) orelse return error.UnresolvedMcpConfigValue;
                    errdefer gpa.free(resolved);
                    const name = try gpa.dupe(u8, entry.key_ptr.*);
                    errdefer gpa.free(name);
                    try headers.append(gpa, .{ .name = name, .value = resolved });
                }
            }
            const auth_enabled = self.auth_provider != null or json.get(self.config, "auth") != null;
            const transport = try http.Http.create(gpa, io, .{ .url = try json.asString(value), .headers = headers.items, .auth_context = self, .auth_token = if (auth_enabled) authToken else null, .on_unauthorized = if (auth_enabled) unauthorized else null });
            return .{ .transport = transport.transport(), .context = transport, .destroy = destroyHttp };
        }
        var environment = try owner.environment.clone(gpa);
        defer environment.deinit();
        if (json.get(self.config, "env")) |map| {
            var iterator = map.object.iterator();
            while (iterator.next()) |entry| {
                const value = try resolver.resolve(try json.asString(entry.value_ptr.*)) orelse return error.UnresolvedMcpConfigValue;
                defer gpa.free(value);
                try environment.put(entry.key_ptr.*, value);
            }
        }
        var argv: std.ArrayList([]const u8) = .empty;
        defer {
            for (argv.items) |item| gpa.free(item);
            argv.deinit(gpa);
        }
        const command = try expandHome(gpa, &owner.environment, try protocol.text(self.config, "command"));
        argv.append(gpa, command) catch |cause| {
            gpa.free(command);
            return cause;
        };
        if (json.get(self.config, "args")) |items| for (items.array.items) |item| {
            const value = try expandHome(gpa, &owner.environment, try json.asString(item));
            errdefer gpa.free(value);
            try argv.append(gpa, value);
        };
        const relative = try expandHome(gpa, &owner.environment, if (json.get(self.config, "cwd")) |value| try json.asString(value) else ".");
        defer gpa.free(relative);
        const cwd = try std.fs.path.resolve(gpa, &.{ owner.cwd, relative });
        defer gpa.free(cwd);
        const transport = try stdio.Stdio.create(gpa, io, .{ .argv = argv.items, .cwd = cwd, .environ = &environment });
        return .{ .transport = transport.transport(), .context = transport, .destroy = destroyStdio };
    }
    fn destroyHttp(raw: *anyopaque) void {
        const value: *http.Http = @ptrCast(@alignCast(raw));
        value.deinit();
    }
    fn destroyStdio(raw: *anyopaque) void {
        const value: *stdio.Stdio = @ptrCast(@alignCast(raw));
        value.deinit();
    }
};

test "mcp.configured refresh every allocation failure preserves committed metadata and releases parsed generations" {
    const Sweep = struct {
        fn run(a: std.mem.Allocator) !void {
            var loaded = try json.Owned.empty(a);
            defer loaded.deinit();
            var environment: std.process.Environ.Map = .init(a);
            defer environment.deinit();
            var service: Service = .{ .gpa = a, .io = std.testing.io, .loaded = loaded, .environment = environment, .cwd = ".", .output_root = ".", .reserved = &.{} };
            defer {
                for (service.descriptors.items) |descriptor| if (descriptor.storage) |storage| storage.release(a);
                service.descriptors.deinit(a);
                service.servers.deinit(a);
                if (service.name_registry) |*registry| registry.deinit();
                if (service.resource_metadata) |*metadata| metadata.deinit();
            }
            var server: Server = .{ .owner = &service, .name = "native", .config = .{ .object = .empty }, .connection = undefined, .timeout_ms = 1000, .auth_arena = .init(a) };
            defer server.auth_arena.deinit();
            defer if (server.discovery) |*discovery| discovery.deinit();
            try service.servers.append(a, &server);
            var initial = try json.Owned.parse(a, "{\"initialized\":{\"capabilities\":{\"tools\":{}}},\"tools\":[{\"name\":\"old\",\"inputSchema\":{}},{\"name\":\"retained\",\"inputSchema\":{}}],\"resourcesCount\":0,\"resourceTemplatesCount\":0}");
            defer initial.deinit();
            var refreshed = try json.Owned.parse(a, "{\"initialized\":{\"capabilities\":{\"tools\":{}}},\"tools\":[{\"name\":\"retained\",\"inputSchema\":{}},{\"name\":\"new\",\"inputSchema\":{}}],\"resourcesCount\":0,\"resourceTemplatesCount\":0}");
            defer refreshed.deinit();
            try service.publishDiscovery(&server, initial.value);
            const old_parameter = service.descriptors.items[0].parameter_id;
            const retained_parameter = service.descriptors.items[1].parameter_id;
            service.publishDiscovery(&server, refreshed.value) catch |err| {
                try std.testing.expectEqual(@as(usize, 2), service.descriptors.items.len);
                try std.testing.expectEqual(old_parameter, service.descriptors.items[0].parameter_id);
                try std.testing.expectEqual(retained_parameter, service.descriptors.items[1].parameter_id);
                try std.testing.expect(service.descriptors.items[0].exposure != .hidden);
                return err;
            };
            try std.testing.expectEqual(@as(usize, 3), service.descriptors.items.len);
            try std.testing.expectEqual(old_parameter, service.descriptors.items[0].parameter_id);
            try std.testing.expect(service.descriptors.items[0].exposure == .hidden);
            try std.testing.expect(retained_parameter != service.descriptors.items[1].parameter_id);
            try std.testing.expectEqual(service.descriptors.items[1].namespace_id, service.descriptors.items[2].namespace_id);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Sweep.run, .{});
}

test "mcp.configured search allocation failures restore activation and release all owned result fields" {
    const Sweep = struct {
        fn run(a: std.mem.Allocator) !void {
            var loaded = try json.Owned.empty(a);
            defer loaded.deinit();
            var environment: std.process.Environ.Map = .init(a);
            defer environment.deinit();
            var schema = try json.Owned.parse(a, "{\"type\":\"function\",\"function\":{\"name\":\"mcp__fixture__double\",\"description\":\"Double a value\",\"parameters\":{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"number\"}}}}}");
            defer schema.deinit();
            var service: Service = .{ .gpa = a, .io = std.testing.io, .loaded = loaded, .environment = environment, .cwd = "", .output_root = "", .reserved = &.{} };
            defer service.descriptors.deinit(a);
            var server: Server = .{ .owner = &service, .name = "fixture", .config = .null, .connection = undefined, .timeout_ms = 60_000, .auth_arena = .init(a) };
            defer server.auth_arena.deinit();
            try service.descriptors.append(a, .{ .server = &server, .raw_name = "double", .name = "mcp__fixture__double", .schema = schema.value, .exposure = .deferred, .definition_id = 1 });
            var result = service.searchResult(a, "{\"query\":\"double value\"}") catch |err| {
                try std.testing.expect(!service.descriptors.items[0].loaded);
                const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(a.ptr));
                return if (err == error.WriteFailed and failing.has_induced_failure) error.OutOfMemory else err;
            };
            defer result.deinit(a);
            try std.testing.expect(service.descriptors.items[0].loaded);
            try std.testing.expectEqual(@as(usize, 1), result.added_tool_names.len);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Sweep.run, .{});
}
fn expandHome(gpa: std.mem.Allocator, environment: *const std.process.Environ.Map, value: []const u8) ![]u8 {
    if (std.mem.eql(u8, value, "~")) return gpa.dupe(u8, startup.home(environment) orelse return error.McpHomeUnavailable);
    if (std.mem.startsWith(u8, value, "~/") or (builtin.os.tag == .windows and std.mem.startsWith(u8, value, "~\\"))) return std.fs.path.join(gpa, &.{ startup.home(environment) orelse return error.McpHomeUnavailable, value[2..] });
    return gpa.dupe(u8, value);
}
fn callablePossible(value: Value) bool {
    if (json.get(value, "enabled")) |enabled| if (enabled == .bool and !enabled.bool) return false;
    if (json.get(value, "exposure")) |exposure| if (exposure == .string and !std.mem.eql(u8, exposure.string, "hidden")) return true;
    if (json.get(value, "toolExposure")) |map| {
        var iterator = map.object.iterator();
        while (iterator.next()) |entry| if (entry.value_ptr.* == .string and !std.mem.eql(u8, entry.value_ptr.string, "hidden")) return true;
    }
    return json.get(value, "exposure") == null;
}
pub fn usesOAuth(value: Value) bool {
    if (json.get(value, "auth") != null) return false;
    if (json.get(value, "url") == null) return false;
    if (json.get(value, "headers")) |map| {
        var iterator = map.object.iterator();
        while (iterator.next()) |entry| if (std.ascii.eqlIgnoreCase(entry.key_ptr.*, "authorization")) return false;
    }
    // Source HTTP defaults to OAuth even without an explicit oauth object.
    return true;
}
pub const Service = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    loaded: json.Owned,
    environment: std.process.Environ.Map,
    cwd: []const u8,
    output_root: []const u8,
    servers: std.ArrayList(*Server) = .empty,
    descriptors: std.ArrayList(Descriptor) = .empty,
    next_definition_id: u64 = 1,
    name_registry: ?tool_names.Registry = null,
    resource_metadata: ?json.Owned = null,
    call_mutex: std.Io.Mutex = .init,
    calls_retired: std.Io.Condition = .init,
    active_calls: usize = 0,
    diagnostics: std.ArrayList([]const u8) = .empty,
    reserved: []const []const u8,
    closing: std.atomic.Value(bool) = .init(false),
    started: bool = false,
    startup: ?*startup_pool.Pool = null,
    catalog_mutex: std.Io.Mutex = .init,
    catalog_changed_context: ?*anyopaque = null,
    catalog_changed_fn: ?*const fn (?*anyopaque) void = null,
    waited_for_direct_startup: bool = false,
    startup_wait_ms: i64 = 10_000,
    notice_context: ?*anyopaque = null,
    notice_fn: ?*const fn (?*anyopaque, []const u8, []const u8) anyerror!void = null,
    builtin_search_registered: bool = false,
    search_active_context: ?*anyopaque = null,
    search_active_fn: ?*const fn (?*anyopaque) bool = null,
    credentials: ?oauth_store.Store = null,
    provider_token_context: ?*anyopaque = null,
    provider_token: ?*const fn (?*anyopaque, std.mem.Allocator, []const u8) anyerror!?[]u8 = null,
    pub fn create(gpa: std.mem.Allocator, io: std.Io, options: Options) !*Service {
        const global = try std.fs.path.join(gpa, &.{ options.agent_dir, "mcp.json" });
        defer gpa.free(global);
        const project = try std.fs.path.join(gpa, &.{ options.cwd, ".pi", "mcp.json" });
        defer gpa.free(project);
        const self = try gpa.create(Service);
        errdefer gpa.destroy(self);
        var environment = try options.environ.clone(gpa);
        errdefer environment.deinit();
        var loaded = try config.load(gpa, io, .{ .global_path = global, .project_path = project, .project_trusted = options.project_trusted });
        errdefer loaded.deinit();
        self.* = .{ .gpa = gpa, .io = io, .loaded = loaded, .environment = environment, .cwd = options.cwd, .output_root = "", .reserved = &.{} };
        const a = self.loaded.arena.allocator();
        self.cwd = try a.dupe(u8, options.cwd);
        const root = if (options.output_root) |value| try gpa.dupe(u8, value) else try startup.tempDirectory(gpa, &self.environment);
        defer gpa.free(root);
        self.output_root = try a.dupe(u8, root);
        const reserved = try a.alloc([]const u8, options.reserved_names.len);
        for (reserved, options.reserved_names) |*target, value| target.* = try a.dupe(u8, value);
        self.reserved = reserved;
        self.credentials = try oauth_store.Store.init(gpa, io, options.agent_dir);
        self.provider_token_context = options.provider_token_context;
        self.provider_token = options.provider_token;
        errdefer if (self.credentials) |*credentials| credentials.deinit();
        errdefer {
            for (self.servers.items) |server| {
                server.connection.deinit();
                server.auth_arena.deinit();
                if (server.challenge) |challenge| gpa.free(challenge);
                gpa.destroy(server);
            }
            self.servers.deinit(gpa);
            self.descriptors.deinit(gpa);
            self.diagnostics.deinit(gpa);
        }
        const errors = try protocol.field(self.loaded.value, "errors");
        for (errors.array.items) |item| try self.diagnostics.append(gpa, try json.asString(item));
        const entries = try protocol.field(self.loaded.value, "servers");
        if (entries.array.items.len > options.max_servers) return error.TooManyMcpServers;
        for (entries.array.items) |entry| {
            const name = try protocol.text(entry, "name");
            const value = try protocol.field(entry, "config");
            if (!options.management_all) {
                if (json.get(value, "enabled")) |enabled| if (!enabled.bool) continue;
                if (!callablePossible(value)) continue;
            }
            const timeout_ms = if (json.get(value, "timeout")) |seconds| (try json.asNumber(seconds)) * 1000 else 60_000;
            const server = try gpa.create(Server);
            errdefer gpa.destroy(server);
            server.* = .{ .owner = self, .name = name, .config = value, .timeout_ms = timeout_ms, .connection = undefined, .auth_arena = .init(gpa) };
            errdefer server.auth_arena.deinit();
            if (usesOAuth(value)) server.auth_provider = .{ .store = self.credentials.?, .name = name, .server_url = try protocol.text(value, "url"), .client = .{ .gpa = gpa, .io = io, .timeout_ms = 15_000 }, .options_context = server, .resolve_options = Server.unusedTokenOptions, .resolve_flow = Server.resolveFlow };
            server.connection = connection.Connection.init(gpa, io, .{ .factory = Server.createTransport, .factory_context = server, .client = .{ .name = "pi", .version = @import("../config.zig").version, .request_timeout_ms = timeout_ms, .context = server, .on_client_notification = Server.notified } });
            errdefer server.connection.deinit();
            try self.servers.append(gpa, server);
        }
        return self;
    }
    fn diagnostic(self: *Service, name: []const u8, message: []const u8) !void {
        try self.diagnostics.append(self.gpa, try std.fmt.allocPrint(self.loaded.arena.allocator(), "MCP server \"{s}\": {s}", .{ name, message }));
    }
    pub fn start(self: *Service) !void {
        if (self.started) return error.McpConfiguredAlreadyStarted;
        self.started = true;
        for (self.servers.items) |server| {
            if (self.closing.load(.acquire)) return error.McpConnectionClosed;
            self.discover(server) catch |cause| {
                if (cause == error.OutOfMemory or cause == error.Canceled or self.closing.load(.acquire)) return cause;
                try self.diagnostic(server.name, @errorName(cause));
            };
        }
    }
    /// Connections begin immediately; their owned DTOs are promoted on the service line.
    pub fn startBackground(self: *Service) !void {
        if (self.started) return;
        const pool = try self.gpa.create(startup_pool.Pool);
        pool.* = .{ .gpa = self.gpa, .io = self.io, .ready_context = self, .on_ready = startupReady };
        self.startup = pool;
        self.started = true;
        for (self.servers.items) |server| {
            var direct = (try config.toolExposure(server.config, "")) == .direct;
            if (json.get(server.config, "toolExposure")) |overrides| if (overrides == .object) for (overrides.object.values()) |value| if (value == .string and std.mem.eql(u8, value.string, "direct")) {
                direct = true;
            };
            try pool.add(server, fetchDiscovery, direct);
        }
    }
    pub const ResourceCounts = struct { resources: usize = 0, templates: usize = 0 };
    pub fn resourceCounts(server: *Server) anyerror!ResourceCounts {
        const self = server.owner;
        const ResourceJob = struct {
            server: *Server,
            operation: resource_tools.Operation,
            reply: ?resource_tools.Reply = null,
            cause: ?anyerror = null,
            future: ?std.Io.Future(void) = null,
            fn run(job: *@This()) void {
                job.reply = invokeResource(job.server, job.server.owner.gpa, job.operation, null, null) catch |cause| {
                    job.cause = cause;
                    return;
                };
            }
            fn deinit(job: *@This(), operation_io: std.Io) void {
                if (job.future) |*future| future.cancel(operation_io);
                if (job.reply) |*reply| reply.value.deinit();
            }
            fn count(job: *@This()) !usize {
                if (job.cause) |cause| if (cause == error.OutOfMemory) return error.OutOfMemory;
                const reply = job.reply orelse return 0;
                if (reply.error_message != null) return 0;
                var count_value: usize = 0;
                for (reply.value.value.array.items) |item| if (!resource_tools.isApp(item)) {
                    count_value += 1;
                };
                return count_value;
            }
        };
        var resource_jobs = [_]ResourceJob{ .{ .server = server, .operation = .all_resources }, .{ .server = server, .operation = .all_templates } };
        defer for (&resource_jobs) |*job| job.deinit(self.io);
        for (&resource_jobs) |*job| {
            job.future = try self.io.concurrent(ResourceJob.run, .{job});
        }
        for (&resource_jobs) |*job| {
            job.future.?.await(self.io);
            job.future = null;
        }
        return .{ .resources = try resource_jobs[0].count(), .templates = try resource_jobs[1].count() };
    }
    fn fetchDiscovery(raw: *anyopaque) !json.Owned {
        const server: *Server = @ptrCast(@alignCast(raw));
        const self = server.owner;
        const borrow = try server.connection.acquire();
        defer borrow.release();
        var result = try json.Owned.empty(self.gpa);
        errdefer result.deinit();
        const a = result.arena.allocator();
        result.value = .{ .object = .empty };
        const initialized = borrow.client.initialized.?.value;
        try result.value.object.put(a, "initialized", try json.clone(a, initialized));
        const offers = try protocol.field(initialized, "capabilities");
        var counts_future: ?std.Io.Future(anyerror!ResourceCounts) = null;
        defer if (counts_future) |*future| {
            _ = future.cancel(self.io) catch {};
        };
        if (json.get(offers, "resources") != null) counts_future = try self.io.concurrent(resourceCounts, .{server});
        var listed: json.Value = .{ .array = .init(a) };
        if (capabilities.offersTools(offers)) {
            var found = try capabilities.listAll(borrow.client, .tools, .{ .timeout_ms = server.timeout_ms });
            defer found.deinit();
            listed = try json.clone(a, found.value);
        }
        try result.value.object.put(a, "tools", listed);
        const counts = if (counts_future) |*future| blk: {
            const fetched = future.await(self.io);
            counts_future = null;
            break :blk try fetched;
        } else ResourceCounts{};
        try result.value.object.put(a, "resourcesCount", .{ .integer = @intCast(counts.resources) });
        try result.value.object.put(a, "resourceTemplatesCount", .{ .integer = @intCast(counts.templates) });
        return result;
    }
    fn discover(self: *Service, server: *Server) !void {
        var result = try fetchDiscovery(server);
        defer result.deinit();
        self.catalog_mutex.lockUncancelable(self.io);
        defer self.catalog_mutex.unlock(self.io);
        try self.publishDiscovery(server, result.value);
    }
    fn publishDiscovery(self: *Service, server: *Server, result: json.Value) !void {
        return self.publishDiscoveryWithBodies(server, result, false);
    }
    fn publishDiscoveryWithBodies(self: *Service, server: *Server, result: json.Value, reuse_bodies: bool) !void {
        var discovery = try json.Owned.empty(self.gpa);
        errdefer discovery.deinit();
        discovery.value = try json.clone(discovery.arena.allocator(), result);
        const initialized = try protocol.field(result, "initialized");
        const has_resources = json.get(try protocol.field(initialized, "capabilities"), "resources") != null;
        const resources_count: usize = @intCast(try json.asInteger(try protocol.field(result, "resourcesCount")));
        const resource_templates_count: usize = @intCast(try json.asInteger(try protocol.field(result, "resourceTemplatesCount")));
        const listed = try protocol.field(result, "tools");
        if (self.name_registry == null) self.name_registry = try tool_names.Registry.init(self.gpa);
        const raw_names = try self.gpa.alloc([]const u8, listed.array.items.len);
        defer self.gpa.free(raw_names);
        for (listed.array.items, raw_names) |item, *raw| raw.* = try protocol.text(item, "name");
        var assigned = try self.name_registry.?.assign(server.name, raw_names);
        defer assigned.deinit();
        var replacement: std.ArrayList(Descriptor) = .empty;
        defer replacement.deinit(self.gpa);
        var created: std.ArrayList(*CatalogStorage) = .empty;
        defer created.deinit(self.gpa);
        var committed = false;
        defer if (!committed) for (created.items) |storage| storage.release(self.gpa);
        const namespace_id = try self.allocateDefinitionId();
        var offered: std.StringHashMapUnmanaged(void) = .empty;
        defer offered.deinit(self.gpa);
        for (listed.array.items, assigned.value.array.items) |item, assigned_name| {
            const raw_name = try protocol.text(item, "name");
            const exposure = try config.toolExposure(server.config, raw_name);
            var name = assigned_name.string;
            var name_taken = false;
            for (self.reserved) |reserved| if (std.mem.eql(u8, name, reserved)) {
                name_taken = true;
                break;
            };
            for (self.descriptors.items) |descriptor| if (descriptor.server != server and std.mem.eql(u8, descriptor.name, name)) {
                name_taken = true;
                break;
            };
            const collision_name = if (name_taken) try projection.toolName(self.gpa, server.name, raw_name, true) else null;
            defer if (collision_name) |value| self.gpa.free(value);
            if (collision_name) |value| name = value;
            if (offered.contains(name)) return error.DuplicateMcpToolName;
            const storage = try self.gpa.create(CatalogStorage);
            storage.* = .{ .owned = json.Owned.empty(self.gpa) catch |err| {
                self.gpa.destroy(storage);
                return err;
            } };
            created.append(self.gpa, storage) catch |err| {
                storage.release(self.gpa);
                return err;
            };
            const a = storage.owned.arena.allocator();
            const owned_name = try a.dupe(u8, name);
            try offered.put(self.gpa, owned_name, {});
            const schema = try projection.schema(a, server.name, name, item);
            const metadata = try projection.codemodeMetadata(a, server.name, server.config, initialized, item);
            var body_id: u64 = 0;
            if (reuse_bodies) for (self.descriptors.items) |previous| if (previous.server == server and std.mem.eql(u8, previous.name, name)) {
                body_id = previous.parameter_body_id;
                break;
            };
            if (body_id == 0) body_id = try self.allocateDefinitionId();
            try replacement.append(self.gpa, .{ .server = server, .raw_name = try a.dupe(u8, raw_name), .name = owned_name, .schema = schema, .codemode_metadata = metadata, .exposure = exposure, .definition_id = try self.allocateDefinitionId(), .parameter_id = try self.allocateDefinitionId(), .parameter_body_id = body_id, .raw_parameters = try json.clone(a, try protocol.field(item, "inputSchema")), .namespace_id = namespace_id, .storage = storage });
        }
        // Withdrawn definitions remain visible as hidden metadata and retain
        // their original parameter/namespace objects. Refreshing an offered
        // definition always gets fresh identities, even for equal schema JSON.
        for (self.descriptors.items) |descriptor| {
            if (descriptor.server == server and !descriptor.resource) {
                if (offered.contains(descriptor.name)) continue;
                var hidden = descriptor;
                if (hidden.exposure != .hidden) hidden.definition_id = try self.allocateDefinitionId();
                hidden.exposure = .hidden;
                hidden.loaded = false;
                try replacement.append(self.gpa, hidden);
            } else try replacement.append(self.gpa, descriptor);
        }
        var ordered: std.ArrayList(Descriptor) = .empty;
        defer ordered.deinit(self.gpa);
        try ordered.ensureTotalCapacity(self.gpa, replacement.items.len + 2);
        for (self.descriptors.items) |old| for (replacement.items) |fresh| if (old.server == fresh.server and old.resource == fresh.resource and std.mem.eql(u8, old.name, fresh.name)) {
            ordered.appendAssumeCapacity(fresh);
            break;
        };
        for (replacement.items) |fresh| {
            var existed = false;
            for (self.descriptors.items) |old| if (old.server == fresh.server and old.resource == fresh.resource and std.mem.eql(u8, old.name, fresh.name)) {
                existed = true;
                break;
            };
            if (!existed) ordered.appendAssumeCapacity(fresh);
        }
        const previous_resources = server.has_resources;
        const previous_count = server.resources_count;
        const previous_templates = server.resource_templates_count;
        server.has_resources = has_resources;
        server.resources_count = resources_count;
        server.resource_templates_count = resource_templates_count;
        self.syncResourceToolsInto(&ordered) catch |err| {
            server.has_resources = previous_resources;
            server.resources_count = previous_count;
            server.resource_templates_count = previous_templates;
            return err;
        };
        for (self.descriptors.items) |descriptor| if (descriptor.server == server and !descriptor.resource and offered.contains(descriptor.name)) if (descriptor.storage) |storage| storage.release(self.gpa);
        self.descriptors.deinit(self.gpa);
        self.descriptors = ordered;
        ordered = .empty;
        committed = true;
        if (server.discovery) |*previous| previous.deinit();
        server.discovery = discovery;
        self.signalCatalogChanged();
    }
    fn signalCatalogChanged(self: *Service) void {
        if (self.catalog_changed_fn) |notify| notify(self.catalog_changed_context);
    }
    fn startupReady(raw: ?*anyopaque) void {
        const self: *Service = @ptrCast(@alignCast(raw.?));
        self.signalCatalogChanged();
    }
    /// Runs on the catalog line, publishing the widest visible server exposure.
    fn syncResourceTools(self: *Service) !void {
        return self.syncResourceToolsInto(&self.descriptors);
    }
    fn syncResourceToolsInto(self: *Service, descriptors: *std.ArrayList(Descriptor)) !void {
        var selected: ?*Server = null;
        var exposure: config.Exposure = .hidden;
        for (self.servers.items) |server| {
            if (!server.has_resources) continue;
            const candidate = try config.serverExposure(server.config);
            if (candidate == .hidden) continue;
            if (selected == null or exposureRank(candidate) < exposureRank(exposure)) {
                selected = server;
                exposure = candidate;
            }
        }
        if (self.resource_metadata == null) self.resource_metadata = try json.Owned.parse(self.gpa, @embedFile("resource_tool_metadata.json"));
        const metadata = self.resource_metadata.?;
        const a = self.loaded.arena.allocator();
        for (metadata.value.array.items) |definition| {
            const name = try protocol.text(definition, "name");
            var existing: ?*Descriptor = null;
            for (descriptors.items) |*descriptor| if (descriptor.resource and std.mem.eql(u8, descriptor.name, name)) {
                existing = descriptor;
                break;
            };
            if (existing) |descriptor| {
                if (descriptor.exposure != exposure) descriptor.definition_id = try self.allocateDefinitionId();
                if (descriptor.exposure == .direct and exposure != .direct) descriptor.loaded = false;
                descriptor.exposure = exposure;
                if (selected) |server| descriptor.server = server;
                continue;
            }
            const server = selected orelse continue;
            if (self.taken(name)) continue;
            var item = try json.clone(a, definition);
            try item.object.put(a, "inputSchema", try protocol.field(item, "parameters"));
            const schema = try projection.schema(a, "", name, item);
            try descriptors.append(self.gpa, .{ .server = server, .raw_name = try a.dupe(u8, name), .name = try a.dupe(u8, name), .schema = schema, .exposure = exposure, .resource = true, .definition_id = try self.allocateDefinitionId(), .parameter_identity = if (std.mem.eql(u8, name, "read_mcp_resource")) .resource_read else .resource_list });
        }
    }
    fn allocateDefinitionId(self: *Service) !u64 {
        if (self.next_definition_id == std.math.maxInt(u64)) return error.McpDefinitionIdentityExhausted;
        const id = self.next_definition_id;
        self.next_definition_id += 1;
        return id;
    }
    fn exposureRank(exposure: config.Exposure) u8 {
        return switch (exposure) {
            .direct => 0,
            .codemode => 1,
            .deferred => 2,
            .hidden => 3,
        };
    }
    pub fn promoteReady(self: *Service) !void {
        const pool = self.startup orelse return;
        self.catalog_mutex.lockUncancelable(self.io);
        defer self.catalog_mutex.unlock(self.io);
        while (pool.takeReady()) |delivery| {
            var result = delivery.value;
            defer if (result) |*value| value.deinit();
            const server: *Server = @ptrCast(@alignCast(delivery.context));
            if (delivery.cause) |cause| {
                if (cause == error.OutOfMemory or cause == error.Canceled or self.closing.load(.acquire)) return cause;
                try self.diagnostic(server.name, @errorName(cause));
            } else try self.publishDiscovery(server, result.?.value);
        }
    }
    fn awaitStartupAbort(self: *Service, flag: ?*const bool) !void {
        if (self.startup) |pool| _ = try pool.waitAbort(flag);
        try self.promoteReady();
    }
    pub fn awaitStartup(self: *Service) !void {
        if (self.startup) |pool| _ = try pool.wait(false, .none);
        try self.promoteReady();
    }
    pub fn awaitForScript(self: *Service, code: []const u8, aborted: ?*const bool) !void {
        if (self.startup) |pool| for (self.servers.items) |server| {
            if (try startup_pool.scriptNeedsServer(self.gpa, code, server.name)) _ = try pool.waitContextAbort(server, aborted);
        };
        try self.promoteReady();
    }
    fn awaitDirectStartup(self: *Service) !void {
        self.catalog_mutex.lockUncancelable(self.io);
        const already = self.waited_for_direct_startup;
        self.waited_for_direct_startup = true;
        self.catalog_mutex.unlock(self.io);
        if (!already) {
            if (self.startup) |pool| {
                const ready = try pool.wait(true, .{ .duration = .{ .raw = .fromMilliseconds(self.startup_wait_ms), .clock = .awake } });
                if (!ready) if (self.notice_fn) |notice| try notice(self.notice_context, "notify", "{\"message\":\"MCP servers are still connecting; their tools become available once connected.\",\"type\":\"info\"}");
            }
        }
        try self.promoteReady();
    }
    pub fn exposureOf(self: *Service, name: []const u8) ?config.Exposure {
        self.catalog_mutex.lockUncancelable(self.io);
        defer self.catalog_mutex.unlock(self.io);
        for (self.descriptors.items) |descriptor| if (std.mem.eql(u8, descriptor.name, name)) return descriptor.exposure;
        return null;
    }
    fn taken(self: *Service, name: []const u8) bool {
        for (self.reserved) |existing| if (std.mem.eql(u8, existing, name)) return true;
        for (self.descriptors.items) |descriptor| if (std.mem.eql(u8, descriptor.name, name)) return true;
        return false;
    }
    pub fn schemasJson(self: *Service) ![]u8 {
        try self.promoteReady();
        self.catalog_mutex.lockUncancelable(self.io);
        defer self.catalog_mutex.unlock(self.io);
        var owned = try json.Owned.empty(self.gpa);
        defer owned.deinit();
        owned.value = .{ .array = .init(owned.arena.allocator()) };
        for (self.descriptors.items) |descriptor| if (descriptor.exposure != .hidden and (descriptor.exposure == .direct or descriptor.loaded)) try owned.value.array.append(descriptor.schema);
        if (self.hasDeferred() and (if (self.search_active_fn) |active| active(self.search_active_context) else true)) {
            var schema = try json.Owned.parse(self.gpa, "{\"type\":\"function\",\"function\":{\"name\":\"tool_search\",\"description\":\"Searches deferred tool metadata with BM25 and exposes matching tools for the next model call.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\"},\"limit\":{\"type\":\"number\"}},\"required\":[\"query\"]}}}");
            defer schema.deinit();
            const function = schema.value.object.getPtr("function").?;
            try function.object.put(schema.arena.allocator(), "description", .{ .string = tool_search.description });
            const parameters = function.object.getPtr("parameters").?;
            const properties = parameters.object.getPtr("properties").?;
            try properties.object.getPtr("query").?.object.put(schema.arena.allocator(), "description", .{ .string = "Search query for deferred tools." });
            try properties.object.getPtr("limit").?.object.put(schema.arena.allocator(), "description", .{ .string = "Maximum number of tools to return. Defaults to 8." });
            try owned.value.array.append(try json.clone(owned.arena.allocator(), schema.value));
        }
        return json.stringify(self.gpa, owned.value);
    }
    fn hasDeferred(self: *const Service) bool {
        if (self.builtin_search_registered) return true;
        for (self.descriptors.items) |descriptor| if (descriptor.exposure == .deferred) return true;
        return false;
    }
    pub fn dynamicSchemas(raw: ?*anyopaque, gpa: std.mem.Allocator) ![]u8 {
        const self: *Service = @ptrCast(@alignCast(raw.?));
        try self.awaitDirectStartup();
        const bytes = try self.schemasJson();
        defer self.gpa.free(bytes);
        return gpa.dupe(u8, bytes);
    }
    /// The complete callable registry, separately from model declarations.
    pub fn registrySchemasJson(self: *Service) ![]u8 {
        try self.promoteReady();
        self.catalog_mutex.lockUncancelable(self.io);
        defer self.catalog_mutex.unlock(self.io);
        var owned = try json.Owned.empty(self.gpa);
        defer owned.deinit();
        owned.value = .{ .array = .init(owned.arena.allocator()) };
        for (self.descriptors.items) |descriptor| if (descriptor.exposure != .hidden) try owned.value.array.append(descriptor.schema);
        return json.stringify(self.gpa, owned.value);
    }
    /// Each DTO owns schema and discovery metadata; no mutable catalog storage escapes.
    pub fn codemodeSchemasJson(self: *Service, wait_for_connections: bool) ![]u8 {
        if (wait_for_connections) try self.awaitStartup() else try self.promoteReady();
        self.catalog_mutex.lockUncancelable(self.io);
        defer self.catalog_mutex.unlock(self.io);
        var owned = try json.Owned.empty(self.gpa);
        defer owned.deinit();
        const a = owned.arena.allocator();
        owned.value = .{ .array = .init(a) };
        for (self.descriptors.items) |descriptor| {
            var entry: json.Value = .{ .object = .empty };
            try entry.object.put(a, "schema", try json.clone(a, descriptor.schema));
            try entry.object.put(a, "exposure", .{ .string = @tagName(descriptor.exposure) });
            if (descriptor.codemode_metadata) |metadata| try entry.object.put(a, "metadata", try json.clone(a, metadata));
            try owned.value.array.append(entry);
        }
        return json.stringify(self.gpa, owned.value);
    }
    /// Returned array storage is owned; names borrow this Service. Allocation
    /// completes before loadout mutation, so failed searches activate nothing.
    pub fn searchAndLoad(self: *Service, query: []const u8, limit: usize) ![]const []const u8 {
        try self.awaitStartup();
        self.catalog_mutex.lockUncancelable(self.io);
        defer self.catalog_mutex.unlock(self.io);
        return self.searchAndLoadLocked(query, limit);
    }
    fn searchAndLoadLocked(self: *Service, query: []const u8, limit: usize) ![]const []const u8 {
        var documents: std.ArrayList(tool_search.Document) = .empty;
        defer {
            for (documents.items) |document| self.gpa.free(document.text);
            documents.deinit(self.gpa);
        }
        for (self.descriptors.items) |descriptor| {
            if (descriptor.loaded or descriptor.exposure == .direct or descriptor.exposure == .hidden) continue;
            const function = try protocol.field(descriptor.schema, "function");
            const document = try tool_search.createDocument(self.gpa, .{ .name = descriptor.name, .description = try protocol.text(function, "description"), .parameters = try protocol.field(function, "parameters") }, .{ .name = descriptor.server.name });
            errdefer self.gpa.free(document.text);
            try documents.append(self.gpa, document);
        }
        const matches = try tool_search.rank(self.gpa, query, documents.items, limit, .{});
        defer self.gpa.free(matches);
        const names = try self.gpa.alloc([]const u8, matches.len);
        for (names, matches) |*name, match| name.* = match.name;
        for (self.descriptors.items) |*descriptor| for (names) |name| if (std.mem.eql(u8, name, descriptor.name)) {
            descriptor.loaded = true;
        };
        return names;
    }
    fn searchResult(self: *Service, gpa: std.mem.Allocator, arguments: []const u8) !tools.ToolResult {
        return self.searchResultAbort(gpa, arguments, null);
    }
    fn searchResultAbort(self: *Service, gpa: std.mem.Allocator, arguments: []const u8, aborted: ?*const bool) !tools.ToolResult {
        try self.awaitStartupAbort(aborted);
        self.catalog_mutex.lockUncancelable(self.io);
        defer self.catalog_mutex.unlock(self.io);
        var parsed = try json.Owned.parse(gpa, arguments);
        defer parsed.deinit();
        const query = try protocol.text(parsed.value, "query");
        if (tool_search.blank(query)) return .{ .content = try gpa.dupe(u8, "query must not be empty"), .is_error = true };
        var limit: usize = 8;
        if (json.get(parsed.value, "limit")) |value| {
            const number = try json.asNumber(value);
            if (!std.math.isFinite(number) or number <= 0 or @floor(number) != number) return .{ .content = try gpa.dupe(u8, "limit must be a positive integer"), .is_error = true };
            limit = @intFromFloat(@min(number, @as(f64, @floatFromInt(self.descriptors.items.len))));
        }
        const selected = try self.searchAndLoadLocked(query, limit);
        defer self.gpa.free(selected);
        errdefer for (self.descriptors.items) |*descriptor| for (selected) |name| if (std.mem.eql(u8, name, descriptor.name)) {
            descriptor.loaded = false;
        };
        const names = try gpa.alloc([]const u8, selected.len);
        var copied: usize = 0;
        errdefer {
            for (names[0..copied]) |name| gpa.free(name);
            gpa.free(names);
        }
        for (selected, names) |name, *target| {
            target.* = try gpa.dupe(u8, name);
            copied += 1;
        }
        var text: std.Io.Writer.Allocating = .init(gpa);
        defer text.deinit();
        if (selected.len == 0) try text.writer.writeAll("No matching tools found.") else {
            try text.writer.print("Loaded {d} tool{s}. They are available from your next call:", .{ selected.len, if (selected.len == 1) "" else "s" });
            for (selected) |name| {
                var description: []const u8 = "";
                for (self.descriptors.items) |descriptor| if (std.mem.eql(u8, descriptor.name, name)) {
                    description = try protocol.text(try protocol.field(descriptor.schema, "function"), "description");
                    break;
                };
                const trimmed = try projection.trimJs(description);
                const newline = std.mem.indexOfScalar(u8, trimmed, '\n') orelse trimmed.len;
                const first = if (newline > 0 and trimmed[newline - 1] == '\r') trimmed[0 .. newline - 1] else trimmed[0..newline];
                try text.writer.print("\n- {s}: {s}", .{ name, first });
            }
        }
        const details = try std.json.Stringify.valueAlloc(gpa, .{ .loaded = names }, .{});
        errdefer gpa.free(details);
        return .{ .content = try text.toOwnedSlice(), .is_error = false, .details_json = details, .added_tool_names = names };
    }
    fn descriptorForName(self: *Service, name: []const u8) !?Descriptor {
        try self.promoteReady();
        self.catalog_mutex.lockUncancelable(self.io);
        defer self.catalog_mutex.unlock(self.io);
        for (self.descriptors.items) |descriptor| if (descriptor.exposure != .hidden and std.mem.eql(u8, descriptor.name, name)) {
            if (descriptor.storage) |storage| storage.references += 1;
            return descriptor;
        };
        return null;
    }
    fn releaseDescriptor(self: *Service, descriptor: Descriptor) void {
        self.catalog_mutex.lockUncancelable(self.io);
        defer self.catalog_mutex.unlock(self.io);
        if (descriptor.storage) |storage| storage.release(self.gpa);
    }
    pub fn owns(self: *Service, name: []const u8) bool {
        self.catalog_mutex.lockUncancelable(self.io);
        defer self.catalog_mutex.unlock(self.io);
        if (std.mem.eql(u8, name, "tool_search")) return self.hasDeferred();
        for (self.descriptors.items) |descriptor| if (descriptor.exposure != .hidden and std.mem.eql(u8, descriptor.name, name)) return true;
        return false;
    }
    pub fn exists(raw: ?*anyopaque, name: []const u8) bool {
        const self: *Service = @ptrCast(@alignCast(raw.?));
        return self.owns(name);
    }
    fn invokeResource(raw: ?*anyopaque, gpa: std.mem.Allocator, operation: resource_tools.Operation, input: ?[]const u8, flag: ?*const bool) !resource_tools.Reply {
        const server: *Server = @ptrCast(@alignCast(raw.?));
        const borrow = try server.connection.acquire();
        defer borrow.release();
        const Remote = struct {
            gpa: std.mem.Allocator,
            value: ?json.Owned = null,
            fn retain(raw_error: ?*anyopaque, value: Value) !void {
                const self: *@This() = @ptrCast(@alignCast(raw_error.?));
                var owned = try json.Owned.empty(self.gpa);
                errdefer owned.deinit();
                owned.value = try json.clone(owned.arena.allocator(), value);
                if (self.value) |*old| old.deinit();
                self.value = owned;
            }
        };
        var remote: Remote = .{ .gpa = gpa };
        defer if (remote.value) |*value| value.deinit();
        const options: session.RequestOptions = .{ .context = .{ .abort_flag = if (flag) |value| @constCast(value) else null }, .timeout_ms = server.timeout_ms, .on_remote_error = Remote.retain, .remote_error_context = &remote };
        const templates = operation == .templates_page or operation == .all_templates;
        const requested = switch (operation) {
            .resources_page, .templates_page => capabilities.listPage(borrow.client, if (templates) .resource_templates else .resources, input, options),
            .all_resources, .all_templates => capabilities.listAll(borrow.client, if (templates) .resource_templates else .resources, options),
            .read => capabilities.readResource(borrow.client, input.?, options),
        };
        const value = requested catch |cause| {
            if (cause != error.McpRemoteError or remote.value == null) return cause;
            const code = json.get(remote.value.?.value, "code");
            if (templates and code != null and (try json.asNumber(code.?)) == -32601) {
                return .{ .value = try json.Owned.parse(gpa, if (operation == .all_templates) "[]" else "{\"resourceTemplates\":[]}") };
            }
            const message = try protocol.text(remote.value.?.value, "message");
            const retained = remote.value.?;
            remote.value = null;
            return .{ .value = retained, .error_message = message };
        };
        return .{ .value = value };
    }
    fn executeResource(self: *Service, gpa: std.mem.Allocator, name: []const u8, arguments: []const u8, flag: ?*bool) !tools.ToolResult {
        // Resource tools consult the current complete resource-server registry.
        try self.awaitStartupAbort(flag);
        var servers: std.ArrayList(resource_tools.Server) = .empty;
        defer servers.deinit(gpa);
        {
            self.catalog_mutex.lockUncancelable(self.io);
            defer self.catalog_mutex.unlock(self.io);
            for (self.servers.items) |server| {
                if (!server.has_resources or (try config.serverExposure(server.config)) == .hidden) continue;
                try servers.append(gpa, .{ .name = server.name, .timeout_ms = server.timeout_ms, .context = server, .invoke = invokeResource });
            }
        }
        var parsed = try json.Owned.parse(gpa, arguments);
        defer parsed.deinit();
        var result = try resource_tools.execute(gpa, self.io, servers.items, name, parsed.value, flag);
        defer result.value.deinit();
        return resource_tools.toToolResult(gpa, self.io, self.output_root, name, &result);
    }
    pub fn execute(raw: ?*anyopaque, gpa: std.mem.Allocator, _: []const u8, name: []const u8, arguments: []const u8, progress: agent.ExternalToolProgressFn, progress_context: ?*anyopaque, abort_flag: ?*bool) !?tools.ToolResult {
        const self: *Service = @ptrCast(@alignCast(raw.?));
        try self.call_mutex.lock(self.io);
        if (self.closing.load(.acquire)) {
            self.call_mutex.unlock(self.io);
            return error.McpConnectionClosed;
        }
        self.active_calls += 1;
        self.call_mutex.unlock(self.io);
        defer {
            self.call_mutex.lockUncancelable(self.io);
            self.active_calls -= 1;
            self.calls_retired.broadcast(self.io);
            self.call_mutex.unlock(self.io);
        }
        if (std.mem.eql(u8, name, "tool_search") and self.owns(name)) return try self.searchResultAbort(gpa, arguments, abort_flag);
        if (try self.descriptorForName(name)) |descriptor| {
            defer self.releaseDescriptor(descriptor);
            if (descriptor.resource) return try self.executeResource(gpa, name, arguments, abort_flag);
            const server = descriptor.server;
            const borrow = try server.connection.acquire();
            defer borrow.release();
            var parsed = try json.Owned.parse(gpa, arguments);
            defer parsed.deinit();
            if (parsed.value != .object) return error.InvalidMcpArguments;
            const Progress = struct {
                gpa: std.mem.Allocator,
                server: []const u8,
                tool: []const u8,
                callback: agent.ExternalToolProgressFn,
                context: ?*anyopaque,
                fn update(raw_progress: ?*anyopaque, value: Value) !void {
                    const target: *@This() = @ptrCast(@alignCast(raw_progress.?));
                    var owned = try json.Owned.empty(target.gpa);
                    defer owned.deinit();
                    const a = owned.arena.allocator();
                    const text = if (json.get(value, "message")) |message| try json.asString(message) else blk: {
                        const number = try protocol.field(value, "progress");
                        const current = try json.stringify(a, number);
                        const total = if (json.get(value, "total")) |item| try std.fmt.allocPrint(a, "/{s}", .{try json.stringify(a, item)}) else "";
                        break :blk try std.fmt.allocPrint(a, "Progress {s}{s}", .{ current, total });
                    };
                    var details: Value = .{ .object = .empty };
                    try details.object.put(a, "server", .{ .string = target.server });
                    try details.object.put(a, "tool", .{ .string = target.tool });
                    const details_json = try json.stringify(a, details);
                    target.callback(target.context, .{ .content = text, .details_json = details_json });
                }
            };
            var capture: Progress = .{ .gpa = gpa, .server = server.name, .tool = descriptor.raw_name, .callback = progress, .context = progress_context };
            const Remote = struct {
                gpa: std.mem.Allocator,
                value: ?json.Owned = null,
                fn retainError(raw_error: ?*anyopaque, value: Value) !void {
                    const target: *@This() = @ptrCast(@alignCast(raw_error.?));
                    var owned = try json.Owned.empty(target.gpa);
                    errdefer owned.deinit();
                    owned.value = try json.clone(owned.arena.allocator(), value);
                    target.value = owned;
                }
            };
            var remote: Remote = .{ .gpa = gpa };
            defer if (remote.value) |*value| value.deinit();
            var reply = capabilities.callTool(borrow.client, descriptor.raw_name, parsed.value, .{
                .context = .{ .abort_flag = abort_flag },
                .timeout_ms = server.timeout_ms,
                .on_progress = Progress.update,
                .progress_context = &capture,
                .on_remote_error = Remote.retainError,
                .remote_error_context = &remote,
            }) catch |cause| {
                if (cause != error.McpRemoteError or remote.value == null) return cause;
                const a = remote.value.?.arena.allocator();
                var details: Value = .{ .object = .empty };
                try details.object.put(a, "server", .{ .string = server.name });
                try details.object.put(a, "tool", .{ .string = descriptor.raw_name });
                try details.object.put(a, "remoteError", remote.value.?.value);
                const text = try gpa.dupe(u8, try protocol.text(remote.value.?.value, "message"));
                errdefer gpa.free(text);
                return .{ .content = text, .is_error = true, .details_json = try json.stringify(gpa, details) };
            };
            defer reply.deinit();
            return try projection.convertWithOptions(gpa, self.io, self.output_root, server.name, descriptor.raw_name, reply.value, server.has_resources);
        }
        return null;
    }
    pub fn close(self: *Service) !void {
        for (self.servers.items) |server| {
            if (server.connection.inOwnerCallback()) return error.ReentrantMcpConfiguredClose;
        }
        self.closing.store(true, .release);
        for (self.servers.items) |server| {
            server.refresh_mutex.lockUncancelable(self.io);
            server.refresh_mutex.unlock(self.io);
            server.refresh_group.cancel(self.io);
        }
        for (self.servers.items) |server| {
            @atomicStore(bool, &server.sign_in_aborted, true, .release);
            server.sign_in_mutex.lockUncancelable(self.io);
            while (server.sign_in_active) server.sign_in_changed.waitUncancelable(self.io, &server.sign_in_mutex);
            server.sign_in_mutex.unlock(self.io);
        }
        // Close the stable connection before waiting for discovery's lifecycle caller.
        if (self.startup) |pool| pool.close();
        for (self.servers.items) |server| try server.connection.close();
        for (self.servers.items) |server| {
            server.lifecycle_mutex.lockUncancelable(self.io);
            while (server.reconnect_callers != 0) server.lifecycle_changed.waitUncancelable(self.io, &server.lifecycle_mutex);
            server.lifecycle_mutex.unlock(self.io);
            if (server.auth_provider) |*provider| provider.close();
        }
        self.call_mutex.lockUncancelable(self.io);
        while (self.active_calls != 0) self.calls_retired.waitUncancelable(self.io, &self.call_mutex);
        self.call_mutex.unlock(self.io);
    }
    pub fn findServer(self: *Service, name: []const u8) ?*Server {
        for (self.servers.items) |server| if (std.mem.eql(u8, server.name, name)) return server;
        return null;
    }
    pub fn reconnect(self: *Service, name: []const u8) !void {
        const server = self.findServer(name) orelse return error.McpServerNotFound;
        try server.lifecycle_mutex.lock(self.io);
        if (self.closing.load(.acquire)) {
            server.lifecycle_mutex.unlock(self.io);
            return error.McpConnectionClosed;
        }
        server.reconnect_callers += 1;
        server.lifecycle_changed.broadcast(self.io);
        server.lifecycle_mutex.unlock(self.io);
        defer {
            server.lifecycle_mutex.lockUncancelable(self.io);
            server.reconnect_callers -= 1;
            server.lifecycle_changed.broadcast(self.io);
            server.lifecycle_mutex.unlock(self.io);
        }
        try server.lifecycle_mutex.lock(self.io);
        while (server.reconnect_active and !self.closing.load(.acquire)) server.lifecycle_changed.wait(self.io, &server.lifecycle_mutex) catch |cause| {
            server.lifecycle_mutex.unlock(self.io);
            return cause;
        };
        if (self.closing.load(.acquire)) {
            server.lifecycle_mutex.unlock(self.io);
            return error.McpConnectionClosed;
        }
        server.reconnect_active = true;
        server.lifecycle_mutex.unlock(self.io);
        defer {
            server.lifecycle_mutex.lockUncancelable(self.io);
            server.reconnect_active = false;
            server.lifecycle_changed.broadcast(self.io);
            server.lifecycle_mutex.unlock(self.io);
        }
        if (self.startup) |pool| pool.retireContext(server);
        const settings = server.connection.options;
        try server.connection.reset(settings, &self.closing);
        if (self.closing.load(.acquire)) return error.McpConnectionClosed;
        {
            self.catalog_mutex.lockUncancelable(self.io);
            defer self.catalog_mutex.unlock(self.io);
            for (self.descriptors.items) |*descriptor| if (descriptor.server == server and !descriptor.resource) {
                if (descriptor.exposure != .hidden) descriptor.definition_id = try self.allocateDefinitionId();
                descriptor.exposure = .hidden;
                descriptor.loaded = false;
            };
            server.has_resources = false;
            try self.syncResourceTools();
        }
        if (self.startup) |pool| {
            try pool.add(server, fetchDiscovery, (try config.toolExposure(server.config, "")) == .direct);
            _ = try pool.waitContext(server, .none);
            try self.promoteReady();
        } else try self.discover(server);
    }
    pub fn signIn(self: *Service, name: []const u8, prompt: oauth_signin.Prompt, flag: ?*bool, timeout_ms: u64) !void {
        const server = self.findServer(name) orelse return error.McpServerNotFound;
        if (server.auth_provider == null) return error.McpServerDoesNotUseOAuth;
        try server.sign_in_mutex.lock(self.io);
        if (self.closing.load(.acquire)) {
            server.sign_in_mutex.unlock(self.io);
            return error.McpConnectionClosed;
        }
        if (server.sign_in_active) {
            server.sign_in_mutex.unlock(self.io);
            return error.McpSignInAlreadyActive;
        }
        server.sign_in_active = true;
        @atomicStore(bool, &server.sign_in_aborted, false, .release);
        server.sign_in_mutex.unlock(self.io);
        defer {
            server.sign_in_mutex.lockUncancelable(self.io);
            server.sign_in_active = false;
            server.sign_in_changed.broadcast(self.io);
            server.sign_in_mutex.unlock(self.io);
        }
        var arena: std.heap.ArenaAllocator = .init(self.gpa);
        defer arena.deinit();
        const a = arena.allocator();
        var stored = try self.credentials.?.load(name, try protocol.text(server.config, "url"), null);
        defer if (stored) |*state| state.deinit();
        server.challenge_mutex.lockUncancelable(self.io);
        const challenge = if (server.challenge) |value| a.dupe(u8, value) catch |cause| {
            server.challenge_mutex.unlock(self.io);
            return cause;
        } else null;
        server.challenge_mutex.unlock(self.io);
        var options = try server.flowOptions(a, if (stored) |state| state.value else .{ .object = .empty }, challenge);
        var parsed_challenge = try oauth_challenge.parse(a, challenge);
        defer parsed_challenge.deinit();
        if (json.get(parsed_challenge.value, "error")) |value| if (value == .string and std.mem.eql(u8, value.string, "insufficient_scope")) {
            options.skip_refresh = true;
            const granted = if (stored) |state| if (json.get(state.value, "tokens")) |tokens| if (json.get(tokens, "scope")) |scope| try json.asString(scope) else null else null else null;
            const merged = try @import("oauth.zig").stepUpScope(a, granted, options.scope);
            if (merged) |scope| options.scope = scope;
        };
        const oauth = json.get(server.config, "oauth") orelse Value{ .object = .empty };
        const Work = struct {
            owner: *Service,
            server: *Server,
            options: oauth_authorize.Options,
            oauth: Value,
            prompt: oauth_signin.Prompt,
            external: ?*bool,
            timeout_ms: u64,
            fn run(work: *@This()) !void {
                try oauth_signin.signIn(.{ .gpa = work.owner.gpa, .io = work.owner.io }, work.owner.credentials.?, .{
                    .flow = work.options,
                    .callback_url = if (json.get(work.oauth, "callbackUrl")) |value| try json.asString(value) else null,
                    .callback_port = if (json.get(work.oauth, "callbackPort")) |value| @intCast(try json.asInteger(value)) else null,
                    .prompt = work.prompt,
                    .abort_flag = &work.server.sign_in_aborted,
                    .timeout_ms = work.timeout_ms,
                });
            }
            fn cancel(work: *@This()) !void {
                while (true) {
                    if (work.external) |external_flag| if (@atomicLoad(bool, external_flag, .acquire)) {
                        @atomicStore(bool, &work.server.sign_in_aborted, true, .release);
                        return error.McpSignInCancelled;
                    };
                    try work.owner.io.sleep(.fromMilliseconds(5), .awake);
                }
            }
        };
        var work: Work = .{ .owner = self, .server = server, .options = options, .oauth = oauth, .prompt = prompt, .external = flag, .timeout_ms = timeout_ms };
        const Race = union(enum) { result: anyerror!void, canceled: anyerror!void };
        var queue: [2]Race = undefined;
        var race = std.Io.Select(Race).init(self.io, &queue);
        defer {
            @atomicStore(bool, &server.sign_in_aborted, true, .release);
            while (race.cancel()) |_| {}
        }
        try race.concurrent(.result, Work.run, .{&work});
        try race.concurrent(.canceled, Work.cancel, .{&work});
        switch (try race.await()) {
            .result, .canceled => |result| try result,
        }
    }
    pub fn signOut(self: *Service, name: []const u8) !bool {
        const server = self.findServer(name) orelse return error.McpServerNotFound;
        if (server.auth_provider == null) return error.McpServerDoesNotUseOAuth;
        @atomicStore(bool, &server.sign_in_aborted, true, .release);
        server.sign_in_mutex.lockUncancelable(self.io);
        while (server.sign_in_active) server.sign_in_changed.waitUncancelable(self.io, &server.sign_in_mutex);
        server.sign_in_mutex.unlock(self.io);
        return server.auth_provider.?.removeCredentials();
    }
    pub fn deinit(self: *Service) void {
        self.close() catch return;
        if (self.startup) |pool| {
            pool.deinit();
            self.gpa.destroy(pool);
            self.startup = null;
        }
        for (self.servers.items) |server| {
            server.connection.deinit();
            if (server.discovery) |*discovery| discovery.deinit();
            server.auth_arena.deinit();
            if (server.challenge) |challenge| self.gpa.free(challenge);
            self.gpa.destroy(server);
        }
        self.servers.deinit(self.gpa);
        for (self.descriptors.items) |descriptor| if (descriptor.storage) |storage| storage.release(self.gpa);
        self.descriptors.deinit(self.gpa);
        if (self.name_registry) |*registry| registry.deinit();
        if (self.resource_metadata) |*metadata| metadata.deinit();
        self.diagnostics.deinit(self.gpa);
        self.environment.deinit();
        if (self.credentials) |*credentials| credentials.deinit();
        self.loaded.deinit();
        self.gpa.destroy(self);
    }
};
