const std = @import("std");
const protocol = @import("protocol.zig");
const session = @import("session.zig");
const stdio = @import("stdio_transport.zig");
const sse = @import("sse.zig");
const http = @import("http_transport.zig");
const connection = @import("connection.zig");
const config = @import("config.zig");
const content = @import("content.zig");
const capabilities = @import("capabilities.zig");
const json = protocol.json;
const gpa = std.testing.allocator;
const io = std.testing.io;
test "mcp.runtime actual upstream captured config errors aliases exposure and content projection" {
    var fixture = try json.Owned.parse(gpa, @embedFile("fixtures/contracts_031b.json"));
    defer fixture.deinit();
    const configs = (try protocol.field(fixture.value, "configs")).array.items;
    for (configs) |row| {
        var result = try config.validate(gpa, try protocol.text(row, "name"), try protocol.field(row, "input"));
        defer result.deinit(gpa);
        const expected = try protocol.field(row, "result");
        switch (result) {
            .invalid => |message| {
                try std.testing.expect(expected == .string);
                try std.testing.expectEqualStrings(expected.string, message);
            },
            .valid => |value| try std.testing.expect(json.equal(expected, value.value)),
        }
    }
    for ((try protocol.field(fixture.value, "content")).array.items) |row| {
        var result = try content.toLlmContent(gpa, try protocol.field(row, "input"));
        defer result.deinit();
        try std.testing.expect(json.equal(try protocol.field(row, "result"), result.value));
    }
    const exposure_config = try protocol.field(fixture.value, "exposureConfig");
    for ((try protocol.field(fixture.value, "exposures")).array.items) |row| try std.testing.expectEqualStrings(try protocol.text(row, "result"), @tagName(try config.toolExposure(exposure_config, try protocol.text(row, "name"))));
    const namespace = try config.namespace(gpa, "server-a");
    defer gpa.free(namespace);
    try std.testing.expectEqualStrings(try protocol.text(fixture.value, "namespace"), namespace);
}
test "mcp.runtime actual upstream captured SSE parser chunk-by-byte final CR and event limits" {
    var fixture = try json.Owned.parse(gpa, @embedFile("fixtures/contracts_031b.json"));
    defer fixture.deinit();
    const Capture = struct {
        owned: json.Owned,
        events: protocol.Value,
        ids: protocol.Value,
        retries: protocol.Value,
        fn init() !@This() {
            const owned = try json.Owned.empty(gpa);
            const a = owned.arena.allocator();
            return .{ .owned = owned, .events = .{ .array = .init(a) }, .ids = .{ .array = .init(a) }, .retries = .{ .array = .init(a) } };
        }
        fn event(raw: ?*anyopaque, value: sse.Event) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const a = self.owned.arena.allocator();
            var item: protocol.Value = .{ .object = .empty };
            try item.object.put(a, "data", .{ .string = try a.dupe(u8, value.data) });
            if (value.event) |name| try item.object.put(a, "event", .{ .string = try a.dupe(u8, name) });
            if (value.id) |event_id| try item.object.put(a, "id", .{ .string = try a.dupe(u8, event_id) });
            try self.events.array.append(item);
        }
        fn id(raw: ?*anyopaque, value: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            try self.ids.array.append(.{ .string = try self.owned.arena.allocator().dupe(u8, value) });
        }
        fn retry(raw: ?*anyopaque, value: f64) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            try self.retries.array.append(.{ .float = value });
        }
    };
    for ((try protocol.field(fixture.value, "sse")).array.items) |row| {
        var capture = try Capture.init();
        defer capture.owned.deinit();
        const limit = try json.asInteger(try protocol.field(row, "maxEventBytes"));
        var parser = sse.Parser.init(gpa, .{ .max_event_bytes = @intCast(limit), .context = &capture, .on_event = Capture.event, .on_id = Capture.id, .on_retry = Capture.retry });
        defer parser.deinit();
        const encoded = try protocol.text(row, "input");
        const bytes = try gpa.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(encoded));
        defer gpa.free(bytes);
        try std.base64.standard.Decoder.decode(bytes, encoded);
        var cause: ?anyerror = null;
        for (bytes) |byte| {
            parser.push(&.{byte}) catch |failure| {
                cause = failure;
                break;
            };
        }
        if (cause == null) parser.finish() catch |failure| {
            cause = failure;
        };
        if (json.get(row, "error") != null) try std.testing.expectEqual(error.McpSseEventTooLarge, cause.?) else try std.testing.expect(cause == null);
        try std.testing.expect(json.equal(try protocol.field(row, "events"), capture.events));
        try std.testing.expect(json.equal(try protocol.field(row, "ids"), capture.ids));
        try std.testing.expect(json.equal(try protocol.field(row, "retries"), capture.retries));
    }
}
test "mcp.runtime real stdio capabilities match actual original network client captured results and remote data" {
    var environment = try std.testing.environ.createMap(gpa);
    defer environment.deinit();
    const program = environment.get("PI_MCP_RUNTIME_FIXTURE") orelse return error.SkipZigTest;
    var oracle = try json.Owned.parse(gpa, @embedFile("fixtures/client_031b.json"));
    defer oracle.deinit();
    const transport = try stdio.Stdio.create(gpa, io, .{ .argv = &.{program}, .environ = &environment, .close_timeout_ms = 20 });
    defer transport.deinit();
    const Capture = struct {
        errors: std.atomic.Value(usize) = .init(0),
        progress: std.atomic.Value(usize) = .init(0),
        elapsed_ms: std.atomic.Value(i64) = .init(0),
        remote: ?json.Owned = null,
        canceled: std.atomic.Value(usize) = .init(0),
        fn errorListener(raw: ?*anyopaque, cause: anyerror) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (cause == error.OriginalMcpProgress) _ = self.errors.fetchAdd(1, .acq_rel);
        }
        fn progressListener(raw: ?*anyopaque, _: protocol.Value) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            _ = self.progress.fetchAdd(1, .acq_rel);
            _ = self.elapsed_ms.fetchAdd(25, .acq_rel);
            return error.OriginalMcpProgress;
        }
        fn clock(raw: ?*anyopaque, _: std.Io) i64 {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            return self.elapsed_ms.load(.acquire);
        }
        fn remoteListener(raw: ?*anyopaque, value: protocol.Value) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            var owned = try json.Owned.empty(gpa);
            errdefer owned.deinit();
            owned.value = try json.clone(owned.arena.allocator(), value);
            self.remote = owned;
        }
        fn notification(raw: ?*anyopaque, method: []const u8, _: ?protocol.Value) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (std.mem.eql(u8, method, "notifications/message")) _ = self.canceled.fetchAdd(1, .acq_rel);
        }
    };
    var capture: Capture = .{};
    defer if (capture.remote) |*remote| remote.deinit();
    const client = try session.Client.create(gpa, io, transport.transport(), .{ .context = &capture, .on_error = Capture.errorListener, .on_notification = Capture.notification, .clock_context = &capture, .clock_now_ms = Capture.clock });
    defer client.deinit();
    var initialized = try client.connect();
    defer initialized.deinit();
    var tools_list = try capabilities.listAll(client, .tools, .{});
    defer tools_list.deinit();
    try std.testing.expect(json.equal(try protocol.field(oracle.value, "tools"), tools_list.value));
    var resources = try capabilities.listAll(client, .resources, .{});
    defer resources.deinit();
    try std.testing.expect(json.equal(try protocol.field(oracle.value, "resources"), resources.value));
    var templates = try capabilities.listAll(client, .resource_templates, .{});
    defer templates.deinit();
    try std.testing.expect(json.equal(try protocol.field(oracle.value, "templates"), templates.value));
    var resource = try capabilities.readResource(client, "file:///resource", .{});
    defer resource.deinit();
    try std.testing.expect(json.equal(try protocol.field(oracle.value, "resource"), resource.value));
    const arguments: protocol.Value = .{ .object = .empty };
    var tool = try capabilities.callTool(client, "first", arguments, .{});
    defer tool.deinit();
    try std.testing.expect(json.equal(try protocol.field(oracle.value, "tool"), tool.value));
    var progress = client.request("progress", arguments, .{ .timeout_ms = 60, .on_progress = Capture.progressListener, .progress_context = &capture }) catch |cause| {
        std.debug.print("MCP progress request failed: {s}; received_frames={d}; original_callback_errors={d}; timeout_ms=60; fixture_interval_ms=25; expected_frames=5\n", .{ @errorName(cause), capture.progress.load(.acquire), capture.errors.load(.acquire) });
        return cause;
    };
    defer progress.deinit();
    try std.testing.expect(json.equal(try protocol.field(oracle.value, "result"), progress.value));
    try std.testing.expectEqual(@as(usize, 5), capture.progress.load(.acquire));
    // The real child/reader/callback path crosses 125 logical milliseconds with
    // a 60ms reset budget. Host CPU scheduling cannot advance this policy clock.
    try std.testing.expectEqual(@as(i64, 125), capture.elapsed_ms.load(.acquire));
    try std.testing.expectEqual(@as(usize, 5), capture.errors.load(.acquire));
    // The previous request has retired and joined its watcher/callbacks.
    // Subsequent failure, genuine timeout and abort checks use production time.
    client.options.clock_now_ms = null;
    try std.testing.expectError(error.McpRemoteError, client.request("failure", null, .{ .on_remote_error = Capture.remoteListener, .remote_error_context = &capture }));
    const expected = try protocol.field(oracle.value, "remote");
    try std.testing.expect(json.equal(try protocol.field(expected, "code"), try protocol.field(capture.remote.?.value, "code")));
    try std.testing.expectEqualStrings(try protocol.text(expected, "message"), try protocol.text(capture.remote.?.value, "message"));
    try std.testing.expect(json.equal(try protocol.field(expected, "data"), try protocol.field(capture.remote.?.value, "data")));
    try std.testing.expectError(error.McpTimeout, client.request("never", null, .{ .timeout_ms = 15 }));
    for (0..100) |_| {
        if (capture.canceled.load(.acquire) > 0) break;
        try io.sleep(.fromMilliseconds(1), .awake);
    }
    try std.testing.expect(capture.canceled.load(.acquire) > 0);
    var flag = true;
    try std.testing.expectError(error.McpRequestAborted, client.request("never", null, .{ .context = .{ .abort_flag = &flag } }));
    var prompts = try capabilities.listAll(client, .prompts, .{});
    defer prompts.deinit();
    try std.testing.expectEqualStrings("welcome", try protocol.text(prompts.value.array.items[0], "name"));
    var prompt = try capabilities.getPrompt(client, "welcome", null, .{});
    defer prompt.deinit();
    try std.testing.expectEqual(@as(usize, 1), (try protocol.field(prompt.value, "messages")).array.items.len);
    try client.close();
    try std.testing.expectEqual(@as(usize, 0), client.pendingCount());
}
test "mcp.runtime config real global project files preserve trust override credentials and namespace collisions" {
    var oracle = try json.Owned.parse(gpa, @embedFile("fixtures/config_load_031b.json"));
    defer oracle.deinit();
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    const global_path = try std.fs.path.join(gpa, &.{ buffer[0..length], "global.json" });
    defer gpa.free(global_path);
    const project_path = try std.fs.path.join(gpa, &.{ buffer[0..length], "project.json" });
    defer gpa.free(project_path);
    const global = try json.stringify(gpa, try protocol.field(oracle.value, "global"));
    defer gpa.free(global);
    const project = try json.stringify(gpa, try protocol.field(oracle.value, "project"));
    defer gpa.free(project);
    try scratch.dir.writeFile(io, .{ .sub_path = "global.json", .data = global });
    try scratch.dir.writeFile(io, .{ .sub_path = "project.json", .data = project });
    for ([_]bool{ false, true }) |trusted| {
        var loaded = try config.load(gpa, io, .{ .global_path = global_path, .project_path = project_path, .project_trusted = trusted });
        defer loaded.deinit();
        const expected = try protocol.field(oracle.value, if (trusted) "trusted" else "untrusted");
        const actual_servers = (try protocol.field(loaded.value, "servers")).array.items;
        const expected_servers = (try protocol.field(expected, "servers")).array.items;
        try std.testing.expectEqual(expected_servers.len, actual_servers.len);
        for (actual_servers, expected_servers) |actual, reference| {
            try std.testing.expectEqualStrings(try protocol.text(reference, "name"), try protocol.text(actual, "name"));
            try std.testing.expect(json.equal(try protocol.field(reference, "config"), try protocol.field(actual, "config")));
            try std.testing.expectEqualStrings(try protocol.text(reference, "scope"), try protocol.text(actual, "scope"));
            try std.testing.expectEqual(json.get(reference, "override") != null, json.get(actual, "override") != null);
        }
        const errors = (try protocol.field(loaded.value, "errors")).array.items;
        const expected_errors = (try protocol.field(expected, "errors")).array.items;
        try std.testing.expectEqual(expected_errors.len, errors.len);
        for (errors, expected_errors) |actual, reference| {
            const suffix = std.mem.indexOf(u8, reference.string, ": ").?;
            try std.testing.expect(std.mem.endsWith(u8, actual.string, reference.string[suffix..]));
        }
        try std.testing.expect(json.equal(try protocol.field(expected, "autoEnableCodemode"), try protocol.field(loaded.value, "autoEnableCodemode")));
    }
}
test "mcp.runtime real HTTP session headers JSON handshake tool request and bounded DELETE" {
    const fixture = @import("../ai/http_fixture.zig");
    const server = try fixture.PlanServer.init(gpa, io, &.{
        .{ .path = "/mcp", .body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"loopback\",\"version\":\"1\"}}}", .headers = &.{ .{ .name = "content-type", .value = "application/json" }, .{ .name = "mcp-session-id", .value = "native-session" } }, .payload_contains = "initialize" },
        .{ .path = "/mcp", .body = "", .status = .accepted, .payload_contains = "notifications/initialized", .expected_request_headers = &.{ .{ .name = "mcp-session-id", .value = "native-session" }, .{ .name = "mcp-protocol-version", .value = "2025-11-25" } } },
        .{ .path = "/mcp", .body = "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"content\":[],\"structuredContent\":{\"ok\":true}}}", .headers = &.{.{ .name = "content-type", .value = "application/json" }}, .payload_contains = "tools/call" },
        .{ .path = "/mcp", .body = "", .status = .no_content, .expected_request_headers = &.{.{ .name = "mcp-session-id", .value = "native-session" }} },
    });
    defer server.deinit();
    const url = try server.url(gpa, "/mcp");
    defer gpa.free(url);
    const transport = try http.Http.create(gpa, io, .{ .url = url, .open_get_stream = false });
    defer transport.deinit();
    const client = try session.Client.create(gpa, io, transport.transport(), .{});
    defer client.deinit();
    var initialized = try client.connect();
    defer initialized.deinit();
    var reply = try client.request("tools/call", null, .{});
    defer reply.deinit();
    try std.testing.expect((try protocol.field(reply.value, "structuredContent")) == .object);
    try client.close();
    try server.finish();
}
test "mcp.runtime HTTP close reuses last bearer token without refreshing after lifetime cancellation" {
    const fixture = @import("../ai/http_fixture.zig");
    const server = try fixture.PlanServer.init(gpa, io, &.{
        .{ .path = "/mcp", .body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{},\"serverInfo\":{\"name\":\"token\",\"version\":\"1\"}}}", .headers = &.{ .{ .name = "content-type", .value = "application/json" }, .{ .name = "mcp-session-id", .value = "token-session" } }, .expected_request_headers = &.{.{ .name = "authorization", .value = "Bearer retained-token" }} },
        .{ .path = "/mcp", .body = "", .status = .accepted, .expected_request_headers = &.{.{ .name = "authorization", .value = "Bearer retained-token" }} },
        .{ .path = "/mcp", .body = "", .status = .no_content, .expected_request_headers = &.{ .{ .name = "authorization", .value = "Bearer retained-token" }, .{ .name = "mcp-session-id", .value = "token-session" } } },
    });
    defer server.deinit();
    const Token = struct {
        calls: usize = 0,
        fn resolve(raw: ?*anyopaque, allocator: std.mem.Allocator, flag: ?*bool) !?[]u8 {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            if (@atomicLoad(bool, flag.?, .acquire)) return error.AuthProviderCalledAfterClose;
            return try allocator.dupe(u8, "retained-token");
        }
    };
    var token: Token = .{};
    const url = try server.url(gpa, "/mcp");
    defer gpa.free(url);
    const transport = try http.Http.create(gpa, io, .{ .url = url, .open_get_stream = false, .auth_context = &token, .auth_token = Token.resolve });
    defer transport.deinit();
    const client = try session.Client.create(gpa, io, transport.transport(), .{});
    defer client.deinit();
    var initialized = try client.connect();
    defer initialized.deinit();
    const before_close = token.calls;
    try std.testing.expect(before_close > 0);
    try client.close();
    try std.testing.expectEqual(before_close, token.calls);
    try server.finish();
}

test "mcp.runtime HTTP retries one unauthorized request with its exact stale token and owned challenge" {
    const fixture = @import("../ai/http_fixture.zig");
    const server = try fixture.PlanServer.init(gpa, io, &.{
        .{ .path = "/mcp", .status = .unauthorized, .body = "denied", .headers = &.{.{ .name = "www-authenticate", .value = "Bearer resource_metadata=\"https://metadata.example/mcp\"" }}, .expected_request_headers = &.{.{ .name = "authorization", .value = "Bearer old" }} },
        .{ .path = "/mcp", .body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{},\"serverInfo\":{\"name\":\"retry\",\"version\":\"1\"}}}", .headers = &.{.{ .name = "content-type", .value = "application/json" }}, .expected_request_headers = &.{.{ .name = "authorization", .value = "Bearer new" }} },
        .{ .path = "/mcp", .status = .accepted, .body = "", .expected_request_headers = &.{.{ .name = "authorization", .value = "Bearer new" }} },
    });
    defer server.deinit();
    const url = try server.url(gpa, "/mcp");
    defer gpa.free(url);
    const Auth = struct {
        replaced: bool = false,
        retries: usize = 0,
        fn token(raw: ?*anyopaque, allocator: std.mem.Allocator, _: ?*bool) !?[]u8 {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            return try allocator.dupe(u8, if (self.replaced) "new" else "old");
        }
        fn unauthorized(raw: ?*anyopaque, stale: ?[]const u8, challenge: ?[]const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            try std.testing.expectEqualStrings("old", stale.?);
            try std.testing.expectEqualStrings("Bearer resource_metadata=\"https://metadata.example/mcp\"", challenge.?);
            self.retries += 1;
            self.replaced = true;
        }
    };
    var auth: Auth = .{};
    const transport = try http.Http.create(gpa, io, .{ .url = url, .open_get_stream = false, .auth_context = &auth, .auth_token = Auth.token, .on_unauthorized = Auth.unauthorized });
    defer transport.deinit();
    const client = try session.Client.create(gpa, io, transport.transport(), .{ .request_timeout_ms = 2000 });
    defer client.deinit();
    var initialized = try client.connect();
    defer initialized.deinit();
    try std.testing.expectEqual(@as(usize, 1), auth.retries);
    try client.close();
    try server.finish();
}

test "mcp.runtime real HTTP stalled initialize shutdown cancels socket before close returns" {
    const fixture = @import("../ai/http_fixture.zig");
    var observed: std.Io.Event = .unset;
    var release: std.Io.Event = .unset;
    const server = try fixture.PlanServer.init(gpa, io, &.{.{ .path = "/mcp", .body = "{}", .request_observed = &observed, .response_release = &release }});
    defer server.deinit();
    const url = try server.url(gpa, "/mcp");
    defer gpa.free(url);
    const transport = try http.Http.create(gpa, io, .{ .url = url, .open_get_stream = false });
    defer transport.deinit();
    const client = try session.Client.create(gpa, io, transport.transport(), .{});
    defer client.deinit();
    const Connect = struct {
        client: *session.Client,
        cause: ?anyerror = null,
        fn run(self: *@This()) void {
            var result = self.client.connect() catch |cause| {
                self.cause = cause;
                return;
            };
            result.deinit();
        }
    };
    var connect: Connect = .{ .client = client };
    const owner = try std.Thread.spawn(.{}, Connect.run, .{&connect});
    try observed.wait(io);
    const before = std.Io.Clock.awake.now(io).toMilliseconds();
    try client.close();
    owner.join();
    try std.testing.expectEqual(error.McpConnectionClosed, connect.cause.?);
    try std.testing.expect(std.Io.Clock.awake.now(io).toMilliseconds() - before < 1000);
    release.set(io);
}
test "mcp.runtime real HTTP GET SSE stream teardown and exactly once bounded session DELETE" {
    const fixture = @import("../ai/http_fixture.zig");
    var observed: std.Io.Event = .unset;
    var release: std.Io.Event = .unset;
    const server = try fixture.PlanServer.init(gpa, io, &.{
        .{ .path = "/mcp", .body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{},\"serverInfo\":{\"name\":\"get\",\"version\":\"1\"}}}", .headers = &.{ .{ .name = "content-type", .value = "application/json" }, .{ .name = "mcp-session-id", .value = "get-session" } } },
        .{ .path = "/mcp", .body = "", .status = .accepted },
        .{ .path = "/mcp", .body = "", .headers = &.{.{ .name = "content-type", .value = "text/event-stream" }}, .expected_request_headers = &.{.{ .name = "accept", .value = "text/event-stream" }}, .request_observed = &observed, .response_release = &release },
        .{ .path = "/mcp", .body = "", .status = .no_content, .expected_request_headers = &.{.{ .name = "mcp-session-id", .value = "get-session" }} },
    });
    defer server.deinit();
    const url = try server.url(gpa, "/mcp");
    defer gpa.free(url);
    const transport = try http.Http.create(gpa, io, .{ .url = url });
    defer transport.deinit();
    const client = try session.Client.create(gpa, io, transport.transport(), .{});
    defer client.deinit();
    var initialized = try client.connect();
    defer initialized.deinit();
    try observed.wait(io);
    const Close = struct {
        client: *session.Client,
        cause: ?anyerror = null,
        fn run(self: *@This()) void {
            self.client.close() catch |cause| {
                self.cause = cause;
            };
        }
    };
    var close: Close = .{ .client = client };
    const owner = try std.Thread.spawn(.{}, Close.run, .{&close});
    try io.sleep(.fromMilliseconds(20), .awake);
    release.set(io);
    owner.join();
    try std.testing.expect(close.cause == null);
    try std.testing.expect(transport.get_future == null);
    try client.close();
    try server.finish();
}
test "mcp.runtime real HTTP SSE progressive messages preserve result and protocol session" {
    const fixture = @import("../ai/http_fixture.zig");
    const server = try fixture.PlanServer.init(gpa, io, &.{
        .{ .path = "/mcp", .body = "id: first\ndata: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/message\",\"params\":{\"data\":\"hé😀\"}}\n\ndata: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{},\"serverInfo\":{\"name\":\"sse\",\"version\":\"1\"}}}\n\n", .headers = &.{.{ .name = "content-type", .value = "text/event-stream" }} },
        .{ .path = "/mcp", .body = "", .status = .accepted },
        .{ .path = "/mcp", .body = "data: {\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"content\":[]}}\n\n", .headers = &.{.{ .name = "content-type", .value = "text/event-stream" }} },
    });
    defer server.deinit();
    const url = try server.url(gpa, "/mcp");
    defer gpa.free(url);
    const Capture = struct {
        count: usize = 0,
        fn notification(raw: ?*anyopaque, method: []const u8, params: ?protocol.Value) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.count += 1;
            try std.testing.expectEqualStrings("notifications/message", method);
            try std.testing.expectEqualStrings("hé😀", try protocol.text(params.?, "data"));
        }
    };
    var capture: Capture = .{};
    const transport = try http.Http.create(gpa, io, .{ .url = url, .open_get_stream = false });
    defer transport.deinit();
    const client = try session.Client.create(gpa, io, transport.transport(), .{ .on_notification = Capture.notification, .context = &capture });
    defer client.deinit();
    var initialized = try client.connect();
    defer initialized.deinit();
    var reply = try client.request("tools/call", null, .{});
    defer reply.deinit();
    try std.testing.expectEqual(@as(usize, 1), capture.count);
    try server.finish();
}
test "mcp.runtime runtime connection closes retry wait without admitting another HTTP attempt" {
    const fixture = @import("../ai/http_fixture.zig");
    const server = try fixture.PlanServer.init(gpa, io, &.{.{ .path = "/mcp", .body = "unavailable", .status = .service_unavailable }});
    defer server.deinit();
    const url = try server.url(gpa, "/mcp");
    defer gpa.free(url);
    const Factory = struct {
        url: []const u8,
        fn create(raw: ?*anyopaque, allocator: std.mem.Allocator, input_io: std.Io, _: usize) !connection.Lease {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const transport = try http.Http.create(allocator, input_io, .{ .url = self.url, .open_get_stream = false });
            return .{ .transport = transport.transport(), .context = transport, .destroy = destroy };
        }
        fn destroy(raw: *anyopaque) void {
            const transport: *http.Http = @ptrCast(@alignCast(raw));
            transport.deinit();
        }
        fn transient(_: ?*anyopaque, cause: anyerror) bool {
            return cause == error.McpHttpError;
        }
    };
    var factory: Factory = .{ .url = url };
    var runtime = connection.Connection.init(gpa, io, .{ .factory = Factory.create, .factory_context = &factory, .is_transient = Factory.transient, .retry_delays_ms = &.{ 250, 1000 } });
    defer runtime.deinit();
    const Open = struct {
        runtime: *connection.Connection,
        cause: ?anyerror = null,
        fn run(self: *@This()) void {
            const borrow = self.runtime.acquire() catch |cause| {
                self.cause = cause;
                return;
            };
            borrow.release();
        }
    };
    var open: Open = .{ .runtime = &runtime };
    const owner = try std.Thread.spawn(.{}, Open.run, .{&open});
    for (0..2000) |_| {
        if (runtime.connectionState() == .failed) break;
        try io.sleep(.fromMilliseconds(1), .awake);
    }
    const before = std.Io.Clock.awake.now(io).toMilliseconds();
    try runtime.close();
    owner.join();
    try std.testing.expectEqual(error.McpHttpError, open.cause.?);
    try std.testing.expectEqual(@as(usize, 1), runtime.attempts);
    try std.testing.expect(std.Io.Clock.awake.now(io).toMilliseconds() - before < 100);
    try server.finish();
}
test "mcp.runtime native allocation failures release parser config and unopened client transport resources" {
    const Allocate = struct {
        fn run(allocator: std.mem.Allocator) !void {
            var raw = try json.Owned.parse(allocator, "{\"url\":\"http://127.0.0.1:1/mcp\",\"exposure\":\"codemode-deferred\",\"toolExposure\":{\"*\":\"hidden\",\"exact\":\"direct\"}}");
            defer raw.deinit();
            var validation = try config.validate(allocator, "native-test", raw.value);
            defer validation.deinit(allocator);
            const transport = try http.Http.create(allocator, io, .{ .url = "http://127.0.0.1:1/mcp", .headers = &.{.{ .name = "test", .value = "owned" }} });
            defer transport.deinit();
            const client = try session.Client.create(allocator, io, transport.transport(), .{ .capabilities = .{ .object = .empty }, .roots = .{ .array = .init(allocator) } });
            defer client.deinit();
            try client.close();
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, Allocate.run, .{});
}
test "mcp.runtime actual stdio initialize allocation failures join exactly owned reader process and child" {
    var environment = try std.testing.environ.createMap(gpa);
    defer environment.deinit();
    const program = environment.get("PI_MCP_RUNTIME_FIXTURE") orelse return error.SkipZigTest;
    const Allocate = struct {
        fn run(allocator: std.mem.Allocator, executable: []const u8) !void {
            var env: std.process.Environ.Map = .init(allocator);
            defer env.deinit();
            const transport = try stdio.Stdio.create(allocator, io, .{ .argv = &.{executable}, .environ = &env, .close_timeout_ms = 1 });
            defer transport.deinit();
            const client = try session.Client.create(allocator, io, transport.transport(), .{ .request_timeout_ms = 1000 });
            defer client.deinit();
            var initialized = try client.connect();
            defer initialized.deinit();
            try client.close();
            try std.testing.expectEqual(@as(usize, 0), client.pendingCount());
            try std.testing.expect(transport.child == null);
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, Allocate.run, .{program});
}
test "mcp.runtime SSE streamed UTF8 BOM field reset id retry final dispatch and bounds" {
    const Capture = struct {
        data: std.ArrayList(u8) = .empty,
        count: usize = 0,
        ids: usize = 0,
        retry_ms: f64 = 0,
        fn event(raw: ?*anyopaque, value: sse.Event) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.count += 1;
            try self.data.appendSlice(gpa, value.data);
            if (self.count == 1) {
                try std.testing.expectEqualStrings("message", value.event.?);
                try std.testing.expectEqualStrings("record", value.id.?);
            } else {
                try std.testing.expect(value.event == null and value.id == null);
            }
        }
        fn id(raw: ?*anyopaque, _: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.ids += 1;
        }
        fn retry(raw: ?*anyopaque, value: f64) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.retry_ms = value;
        }
    };
    var capture: Capture = .{};
    defer capture.data.deinit(gpa);
    var parser = sse.Parser.init(gpa, .{ .context = &capture, .on_event = Capture.event, .on_id = Capture.id, .on_retry = Capture.retry });
    defer parser.deinit();
    const bytes = "\xef\xbb\xbfid: initial\n\n: comment\nid: record\nevent: message\nretry: 0012\ndata: hé😀\ndata: next\r\n\ndata: final";
    for (bytes) |byte| try parser.push(&.{byte});
    try parser.finish();
    try parser.finish();
    try std.testing.expectEqual(@as(usize, 2), capture.count);
    try std.testing.expectEqual(@as(usize, 2), capture.ids);
    try std.testing.expectEqual(@as(f64, 12), capture.retry_ms);
    try std.testing.expectEqualStrings("hé😀\nnextfinal", capture.data.items);
    try std.testing.expectError(error.McpSseStreamEnded, parser.push("new"));
    var bounded = sse.Parser.init(gpa, .{ .max_event_bytes = 8, .context = &capture, .on_event = Capture.event });
    defer bounded.deinit();
    try bounded.push("data:a\n");
    try std.testing.expectError(error.McpSseEventTooLarge, bounded.push("data:aaaa\n"));
}
test "mcp.runtime real stdio pending initialize shutdown joins request transport and exact child" {
    var environment = try std.testing.environ.createMap(gpa);
    defer environment.deinit();
    const program = environment.get("PI_MCP_RUNTIME_FIXTURE") orelse return error.SkipZigTest;
    const transport = try stdio.Stdio.create(gpa, io, .{ .argv = &.{ program, "--stall" }, .environ = &environment, .close_timeout_ms = 20 });
    defer transport.deinit();
    const client = try session.Client.create(gpa, io, transport.transport(), .{});
    defer client.deinit();
    const Connect = struct {
        client: *session.Client,
        cause: ?anyerror = null,
        fn run(self: *@This()) void {
            var result = self.client.connect() catch |cause| {
                self.cause = cause;
                return;
            };
            result.deinit();
        }
    };
    var connect: Connect = .{ .client = client };
    const owner = try std.Thread.spawn(.{}, Connect.run, .{&connect});
    var pending = false;
    for (0..2000) |_| {
        if (client.pendingCount() > 0) {
            pending = true;
            break;
        }
        try io.sleep(.fromMilliseconds(1), .awake);
    }
    const before = std.Io.Clock.awake.now(io).toMilliseconds();
    try client.close();
    owner.join();
    try std.testing.expect(pending);
    try std.testing.expectEqual(error.McpConnectionClosed, connect.cause.?);
    try std.testing.expect(std.Io.Clock.awake.now(io).toMilliseconds() - before < 1000);
    try std.testing.expectEqual(session.State.closed, client.connectionState());
    try std.testing.expectEqual(@as(usize, 0), client.pendingCount());
    try std.testing.expect(transport.child == null);
    try client.close();
}
test "mcp.runtime real stdio initialize and concurrent request result ownership" {
    var environment = try std.testing.environ.createMap(gpa);
    defer environment.deinit();
    const program = environment.get("PI_MCP_RUNTIME_FIXTURE") orelse return error.SkipZigTest;
    const transport = try stdio.Stdio.create(gpa, io, .{ .argv = &.{program}, .environ = &environment, .close_timeout_ms = 100 });
    defer transport.deinit();
    const client = try session.Client.create(gpa, io, transport.transport(), .{});
    defer client.deinit();
    var initialized = try client.connect();
    defer initialized.deinit();
    try std.testing.expectEqual(session.State.connected, client.connectionState());
    const Request = struct {
        client: *session.Client,
        reply: ?json.Owned = null,
        cause: ?anyerror = null,
        fn run(self: *@This()) void {
            self.reply = self.client.request("tools/call", null, .{}) catch |cause| {
                self.cause = cause;
                return;
            };
        }
    };
    var requests = [_]Request{ .{ .client = client }, .{ .client = client }, .{ .client = client } };
    var owners: [3]std.Thread = undefined;
    for (&owners, &requests) |*owner, *request| owner.* = try std.Thread.spawn(.{}, Request.run, .{request});
    for (owners) |owner| owner.join();
    for (&requests) |*request| {
        if (request.reply) |*reply| {
            defer reply.deinit();
            try std.testing.expect((try protocol.field(reply.value, "structuredContent")) == .object);
        } else return request.cause.?;
    }
    try std.testing.expectEqual(@as(usize, 0), client.pendingCount());
    try client.close();
    try std.testing.expect(transport.child == null);
}
