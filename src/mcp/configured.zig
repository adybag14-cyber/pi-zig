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
const agent = @import("../agent/loop.zig");
const tools = @import("../agent/tools.zig");
const startup = @import("../durable/startup.zig");
const Resolver = @import("../coding_agent/config_value.zig").Resolver;
const tool_search = @import("tool_search.zig");

pub const Options = struct { agent_dir: []const u8, cwd: []const u8, project_trusted: bool = false, environ: *const std.process.Environ.Map, reserved_names: []const []const u8 = &.{}, output_root: ?[]const u8 = null, max_servers: usize = 64 };
pub const Descriptor = struct { server: *Server, raw_name: []const u8, name: []const u8, schema: Value, exposure: config.Exposure = .direct, loaded: bool = false };
pub const Server = struct {
    owner: *Service,
    name: []const u8,
    config: Value,
    connection: connection.Connection,
    timeout_ms: f64,
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
            const transport = try http.Http.create(gpa, io, .{ .url = try json.asString(value), .headers = headers.items });
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
            var server: Server = .{ .owner = &service, .name = "fixture", .config = .null, .connection = undefined, .timeout_ms = 60_000 };
            try service.descriptors.append(a, .{ .server = &server, .raw_name = "double", .name = "mcp__fixture__double", .schema = schema.value, .exposure = .deferred });
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
fn unsupportedAuthentication(value: Value) bool {
    if (json.get(value, "auth") != null or json.get(value, "oauth") != null) return true;
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
    diagnostics: std.ArrayList([]const u8) = .empty,
    reserved: []const []const u8,
    closing: std.atomic.Value(bool) = .init(false),
    started: bool = false,
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
        errdefer {
            for (self.servers.items) |server| {
                server.connection.deinit();
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
            if (json.get(value, "enabled")) |enabled| if (!enabled.bool) continue;
            if (!callablePossible(value)) continue;
            if (unsupportedAuthentication(value)) {
                try self.diagnostic(name, "McpOAuthUnsupported: native configured HTTP requires an explicit static Authorization header; auth and oauth are not implemented");
                continue;
            }
            const timeout_ms = if (json.get(value, "timeout")) |seconds| (try json.asNumber(seconds)) * 1000 else 60_000;
            const server = try gpa.create(Server);
            errdefer gpa.destroy(server);
            server.* = .{ .owner = self, .name = name, .config = value, .timeout_ms = timeout_ms, .connection = undefined };
            server.connection = connection.Connection.init(gpa, io, .{ .factory = Server.createTransport, .factory_context = server, .client = .{ .version = "1.0.4", .request_timeout_ms = timeout_ms } });
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
    fn discover(self: *Service, server: *Server) !void {
        const borrow = try server.connection.acquire();
        defer borrow.release();
        const initialized = borrow.client.initialized.?.value;
        const offers = try protocol.field(initialized, "capabilities");
        if (json.get(offers, "tools") == null) return;
        var listed = try capabilities.listAll(borrow.client, .tools, .{ .timeout_ms = server.timeout_ms });
        defer listed.deinit();
        const a = self.loaded.arena.allocator();
        for (listed.value.array.items) |item| {
            const raw_name = try protocol.text(item, "name");
            const exposure = try config.toolExposure(server.config, raw_name);
            if (exposure == .hidden) continue;
            var duplicate = false;
            for (self.descriptors.items) |descriptor| if (descriptor.server == server and std.mem.eql(u8, descriptor.raw_name, raw_name)) {
                duplicate = true;
                break;
            };
            if (duplicate) continue;
            const base = try projection.toolName(self.gpa, server.name, raw_name, false);
            defer self.gpa.free(base);
            const name = try projection.toolName(self.gpa, server.name, raw_name, self.taken(base));
            defer self.gpa.free(name);
            if (self.taken(name)) return error.DuplicateMcpToolName;
            const schema = try projection.schema(a, server.name, name, item);
            try self.descriptors.append(self.gpa, .{ .server = server, .raw_name = try a.dupe(u8, raw_name), .name = try a.dupe(u8, name), .schema = schema, .exposure = exposure });
        }
    }
    fn taken(self: *Service, name: []const u8) bool {
        for (self.reserved) |existing| if (std.mem.eql(u8, existing, name)) return true;
        for (self.descriptors.items) |descriptor| if (std.mem.eql(u8, descriptor.name, name)) return true;
        return false;
    }
    pub fn schemasJson(self: *Service) ![]u8 {
        var owned = try json.Owned.empty(self.gpa);
        defer owned.deinit();
        owned.value = .{ .array = .init(owned.arena.allocator()) };
        for (self.descriptors.items) |descriptor| if (descriptor.exposure == .direct or descriptor.loaded) try owned.value.array.append(descriptor.schema);
        if (self.hasDeferred()) {
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
        for (self.descriptors.items) |descriptor| if (descriptor.exposure == .deferred) return true;
        return false;
    }
    pub fn dynamicSchemas(raw: ?*anyopaque, gpa: std.mem.Allocator) ![]u8 {
        const self: *Service = @ptrCast(@alignCast(raw.?));
        const bytes = try self.schemasJson();
        defer self.gpa.free(bytes);
        return gpa.dupe(u8, bytes);
    }
    /// The complete callable registry, separately from model declarations.
    pub fn registrySchemasJson(self: *Service) ![]u8 {
        var owned = try json.Owned.empty(self.gpa);
        defer owned.deinit();
        owned.value = .{ .array = .init(owned.arena.allocator()) };
        for (self.descriptors.items) |descriptor| try owned.value.array.append(descriptor.schema);
        return json.stringify(self.gpa, owned.value);
    }
    /// Returned array storage is owned; names borrow this Service. Allocation
    /// completes before loadout mutation, so failed searches activate nothing.
    pub fn searchAndLoad(self: *Service, query: []const u8, limit: usize) ![]const []const u8 {
        var documents: std.ArrayList(tool_search.Document) = .empty;
        defer {
            for (documents.items) |document| self.gpa.free(document.text);
            documents.deinit(self.gpa);
        }
        for (self.descriptors.items) |descriptor| {
            if (descriptor.loaded or descriptor.exposure == .direct) continue;
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
        const selected = try self.searchAndLoad(query, limit);
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
    pub fn owns(self: *Service, name: []const u8) bool {
        if (std.mem.eql(u8, name, "tool_search")) return self.hasDeferred();
        for (self.descriptors.items) |descriptor| if (std.mem.eql(u8, descriptor.name, name)) return true;
        return false;
    }
    pub fn exists(raw: ?*anyopaque, name: []const u8) bool {
        const self: *Service = @ptrCast(@alignCast(raw.?));
        return self.owns(name);
    }
    pub fn execute(raw: ?*anyopaque, gpa: std.mem.Allocator, _: []const u8, name: []const u8, arguments: []const u8, progress: agent.ExternalToolProgressFn, progress_context: ?*anyopaque, abort_flag: ?*bool) !?tools.ToolResult {
        const self: *Service = @ptrCast(@alignCast(raw.?));
        if (std.mem.eql(u8, name, "tool_search") and self.hasDeferred()) return try self.searchResult(gpa, arguments);
        for (self.descriptors.items) |descriptor| if (std.mem.eql(u8, descriptor.name, name)) {
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
            return try projection.convert(gpa, self.io, self.output_root, server.name, descriptor.raw_name, reply.value);
        };
        return null;
    }
    pub fn close(self: *Service) !void {
        for (self.servers.items) |server| {
            server.connection.mutex.lockUncancelable(self.io);
            const client = server.connection.opening_client orelse server.connection.client;
            const reentrant = if (client) |value| value.inCallback() else false;
            server.connection.mutex.unlock(self.io);
            if (reentrant) return error.ReentrantMcpConfiguredClose;
        }
        self.closing.store(true, .release);
        for (self.servers.items) |server| try server.connection.close();
    }
    pub fn deinit(self: *Service) void {
        self.close() catch return;
        for (self.servers.items) |server| {
            server.connection.deinit();
            self.gpa.destroy(server);
        }
        self.servers.deinit(self.gpa);
        self.descriptors.deinit(self.gpa);
        self.diagnostics.deinit(self.gpa);
        self.environment.deinit();
        self.loaded.deinit();
        self.gpa.destroy(self);
    }
};
