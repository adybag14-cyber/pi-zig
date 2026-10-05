//! Complete native loopback retry policy and live RPC settings reload fixture.
const std = @import("std");
const builtin = @import("builtin");
const http = @import("test_support/http_fixture.zig");
const pty = @import("test_support/pty.zig");
const rpc = @import("test_support/rpc_process.zig");
const Io = std.Io;

const success_sse = "data: {\"id\":\"chatcmpl-163\",\"choices\":[{\"delta\":{\"content\":\"provider-retry-ok\"}}]}\n\n" ++
    "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2}}\n\n" ++
    "data: [DONE]\n\n";
const success: http.Response = .{ .headers = "content-type: text/event-stream", .body = success_sse };
// Current upstream catalogs route openai/gpt-4o through the Responses API.
// Keep the model and every reload assertion; provide its actual SSE contract.
const responses_success_sse =
    "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp-163\",\"model\":\"gpt-4o\",\"status\":\"in_progress\",\"output\":[]}}\n\n" ++
    "data: {\"type\":\"response.output_text.delta\",\"output_index\":0,\"delta\":\"provider-retry-ok\"}\n\n" ++
    "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp-163\",\"model\":\"gpt-4o\",\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"id\":\"msg-163\",\"role\":\"assistant\",\"status\":\"completed\",\"content\":[{\"type\":\"output_text\",\"text\":\"provider-retry-ok\",\"annotations\":[]}]}],\"usage\":{\"input_tokens\":1,\"output_tokens\":1,\"total_tokens\":2}}}\n\n";
const ReloadPlan = struct {
    index: usize = 0,
    fn route(raw: ?*anyopaque, request: http.Request, _: []u8) !http.Response {
        const self: *ReloadPlan = @ptrCast(@alignCast(raw.?));
        defer self.index += 1;
        return switch (self.index) {
            0 => .{ .status = 503, .body = "{\"error\":{\"message\":\"before reload\"}}" },
            1 => .{ .status = 503, .headers = "retry-after-ms: 20", .body = "{\"error\":{\"message\":\"after reload\"}}" },
            2 => .{ .headers = "content-type: text/event-stream", .body = if (std.mem.endsWith(u8, request.path, "/responses")) responses_success_sse else success_sse },
            else => return error.ProviderRetryUnexpectedRequest,
        };
    }
};
const Count = struct { requests: usize, elapsedMs: i64 };
const Reload = struct { requestsBefore: usize = 1, requestsAfter: usize = 2, stderrBytes: usize = 0 };
const Report = struct { retryAfterMs: Count, forcedRetry: Count, deniedRetry: Count, delayCap: Count, inheritedTimeout: Count, timeout: Count, liveReload: Reload };

fn clock(io: Io) i64 {
    return Io.Clock.awake.now(io).toMilliseconds();
}

fn policy(gpa: std.mem.Allocator, timeout_ms: u32, max_retries: u32, max_delay_ms: u32) ![]u8 {
    return std.fmt.allocPrint(gpa, "{{\"retry\":{{\"enabled\":false,\"provider\":{{\"timeoutMs\":{d},\"maxRetries\":{d},\"maxRetryDelayMs\":{d}}}}}}}", .{ timeout_ms, max_retries, max_delay_ms });
}

const Outcome = struct { output: []u8, elapsed_ms: i64 };

fn runPrint(gpa: std.mem.Allocator, io: Io, binary: []const u8, server: *http.Server, settings: []const u8) !Outcome {
    var scratch = try pty.Scratch.init(gpa, io, "provider-retry");
    defer scratch.deinit();
    try scratch.dir.createDir(io, "agent", .default_dir);
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = settings });
    var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environment.deinit();
    const agent_dir = try std.fs.path.join(gpa, &.{ scratch.path, "agent" });
    defer gpa.free(agent_dir);
    try environment.put("PI_AGENT_DIR", agent_dir);
    const base_url = try std.fmt.allocPrint(gpa, "http://127.0.0.1:{d}/v1", .{server.port});
    defer gpa.free(base_url);
    const errors_file = try scratch.dir.createFile(io, "stderr.log", .{});
    defer errors_file.close(io);
    const started = clock(io);
    var child = try rpc.Process.spawn(gpa, io, .{
        .argv = &.{ binary, "--provider", "openai", "--model", "checkpoint-163", "--base-url", base_url, "--api-key", "test-key", "--mode", "json", "--print", "--no-session", "--no-tools", "provider retry e2e" },
        .environ_map = &environment,
        .stdin = .ignore,
        .stderr = .{ .file = errors_file },
    }, 20_000);
    defer child.deinit();
    const term = try child.wait(20_000);
    const elapsed_ms = clock(io) - started;
    const errors = try scratch.dir.readFileAlloc(io, "stderr.log", gpa, .limited(1024 * 1024));
    defer gpa.free(errors);
    if (term != .exited or term.exited != 0 or errors.len != 0) {
        std.debug.print("Provider fixture failed: {any}; stderr={s}\n", .{ term, errors });
        return error.ProviderRetryProcessFailed;
    }
    return .{ .output = try gpa.dupe(u8, child.output.items), .elapsed_ms = elapsed_ms };
}

fn scenario(gpa: std.mem.Allocator, io: Io, binary: []const u8, settings: []const u8, responses: []const http.Response, expected_requests: usize, marker: []const u8, min_retry_ms: i64, max_elapsed_ms: ?i64) !Count {
    const server = try http.Server.startScripted(gpa, io, responses);
    defer server.deinit();
    const result = try runPrint(gpa, io, binary, server, settings);
    defer gpa.free(result.output);
    try server.finish();
    const requests = try server.snapshotRequests(gpa);
    defer http.freeRequests(gpa, requests);
    try std.testing.expectEqual(expected_requests, requests.len);
    if (std.mem.indexOf(u8, result.output, marker) == null) {
        std.debug.print("Provider retry missing {s}: {s}\n", .{ marker, result.output });
        return error.ProviderRetryMarkerMissing;
    }
    if (min_retry_ms > 0) try std.testing.expect(requests[1].arrival_ms - requests[0].arrival_ms >= min_retry_ms);
    if (max_elapsed_ms) |limit| try std.testing.expect(result.elapsed_ms < limit);
    return .{ .requests = requests.len, .elapsedMs = result.elapsed_ms };
}

fn waitEvent(gpa: std.mem.Allocator, io: Io, process: *rpc.Process, kind: []const u8, id: ?[]const u8) !std.json.Parsed(std.json.Value) {
    const end = clock(io) + 15_000;
    while (clock(io) < end) {
        const line = try process.line(@intCast(@max(1, end - clock(io))));
        defer gpa.free(line);
        const item = std.json.parseFromSlice(std.json.Value, gpa, line, .{ .allocate = .alloc_always }) catch continue;
        if (item.value == .object) {
            const actual_kind = item.value.object.get("type");
            const actual_id = item.value.object.get("id");
            const kind_matches = if (actual_kind) |value| value == .string and std.mem.eql(u8, value.string, kind) else false;
            const id_matches = if (id) |wanted| if (actual_id) |value| value == .string and std.mem.eql(u8, value.string, wanted) else false else true;
            if (kind_matches and id_matches) return item;
        }
        item.deinit();
    }
    std.debug.print("RPC retry missing {s}; raw={s}\n", .{ kind, process.output.items });
    return error.ProviderRetryRpcEventTimeout;
}

fn eventContains(gpa: std.mem.Allocator, item: std.json.Value, marker: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(gpa, item, .{});
    defer gpa.free(encoded);
    if (std.mem.indexOf(u8, encoded, marker) == null) std.debug.print("RPC provider retry missing {s}: {s}\n", .{ marker, encoded });
    try std.testing.expect(std.mem.indexOf(u8, encoded, marker) != null);
}

fn reloadScenario(gpa: std.mem.Allocator, io: Io, binary: []const u8) !Reload {
    var plan: ReloadPlan = .{};
    const server = try http.Server.start(gpa, io, &plan, ReloadPlan.route);
    defer server.deinit();
    var scratch = try pty.Scratch.init(gpa, io, "provider-reload");
    defer scratch.deinit();
    try scratch.dir.createDir(io, "agent", .default_dir);
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = "{\"retry\":{\"enabled\":false,\"provider\":{\"maxRetries\":0,\"maxRetryDelayMs\":1000}}}" });
    var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environment.deinit();
    const agent_dir = try std.fs.path.join(gpa, &.{ scratch.path, "agent" });
    defer gpa.free(agent_dir);
    try environment.put("PI_AGENT_DIR", agent_dir);
    const base_url = try std.fmt.allocPrint(gpa, "http://127.0.0.1:{d}/v1", .{server.port});
    defer gpa.free(base_url);
    const errors_file = try scratch.dir.createFile(io, "stderr.log", .{});
    defer errors_file.close(io);
    var child = try rpc.Process.spawn(gpa, io, .{
        .argv = &.{ binary, "--provider", "openai", "--model", "gpt-4o", "--base-url", base_url, "--api-key", "test-key", "--mode", "rpc", "--no-session", "--no-tools" },
        .environ_map = &environment,
        .stdin = .pipe,
        .stderr = .{ .file = errors_file },
    }, 90_000);
    defer child.deinit();
    try child.send("{\"id\":\"p1\",\"type\":\"prompt\",\"message\":\"before reload\"}\n");
    const first_ack = try waitEvent(gpa, io, &child, "response", "p1");
    first_ack.deinit();
    const first_end = try waitEvent(gpa, io, &child, "agent_end", null);
    defer first_end.deinit();
    const before = try server.snapshotRequests(gpa);
    defer http.freeRequests(gpa, before);
    try std.testing.expectEqual(@as(usize, 1), before.len);
    try eventContains(gpa, first_end.value, "HTTP 503");
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = "{\"retry\":{\"enabled\":false,\"provider\":{\"maxRetries\":1,\"maxRetryDelayMs\":1000}}}" });
    try child.send("{\"id\":\"r1\",\"type\":\"reload\"}\n");
    const reload_ack = try waitEvent(gpa, io, &child, "response", "r1");
    defer reload_ack.deinit();
    try std.testing.expectEqual(std.json.Value{ .bool = true }, reload_ack.value.object.get("success").?);
    try child.send("{\"id\":\"p2\",\"type\":\"prompt\",\"message\":\"after reload\"}\n");
    const second_ack = try waitEvent(gpa, io, &child, "response", "p2");
    second_ack.deinit();
    const second_end = try waitEvent(gpa, io, &child, "agent_end", null);
    defer second_end.deinit();
    const after = try server.snapshotRequests(gpa);
    defer http.freeRequests(gpa, after);
    try std.testing.expectEqual(@as(usize, 3), after.len);
    for (after) |request| try std.testing.expectEqualStrings("/v1/responses", request.path);
    try std.testing.expect(after[2].arrival_ms - after[1].arrival_ms >= 15);
    try eventContains(gpa, second_end.value, "provider-retry-ok");
    std.debug.print("PROVIDER_RETRY_RPC_WIRE=model:gpt-4o api:openai-responses path:{s}\n", .{after[2].path});
    try child.send("{\"id\":\"q1\",\"type\":\"quit\"}\n");
    const quit_ack = try waitEvent(gpa, io, &child, "response", "q1");
    quit_ack.deinit();
    child.closeInput();
    const term = try child.wait(10_000);
    const errors = try scratch.dir.readFileAlloc(io, "stderr.log", gpa, .limited(1024 * 1024));
    defer gpa.free(errors);
    try std.testing.expect(term == .exited and term.exited == 0);
    try std.testing.expectEqualStrings("", errors);
    try server.finish();
    return .{};
}

test "native provider retry preserves all seven network and live RPC reload scenarios" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environment.deinit();
    const binary = try std.fs.path.resolve(gpa, &.{environment.get("PI_TEST_BINARY") orelse "zig-out/bin/pi"});
    defer gpa.free(binary);
    const defaults = try policy(gpa, 3000, 1, 1000);
    defer gpa.free(defaults);
    const three_retries = try policy(gpa, 3000, 3, 1000);
    defer gpa.free(three_retries);
    const cap = try policy(gpa, 3000, 3, 100);
    defer gpa.free(cap);
    const timeout = try policy(gpa, 50, 1, 1000);
    defer gpa.free(timeout);
    var delayed_success = success;
    delayed_success.delay_ms = 350;
    const report: Report = .{
        .retryAfterMs = try scenario(gpa, io, binary, defaults, &.{ .{ .status = 429, .headers = "retry-after-ms: 60", .body = "{\"error\":{\"message\":\"slow down\"}}" }, success }, 2, "provider-retry-ok", 55, null),
        .forcedRetry = try scenario(gpa, io, binary, defaults, &.{ .{ .status = 400, .headers = "x-should-retry: true", .body = "{\"error\":{\"message\":\"explicit retry\"}}" }, success }, 2, "provider-retry-ok", 0, null),
        .deniedRetry = try scenario(gpa, io, binary, three_retries, &.{.{ .status = 503, .headers = "x-should-retry: false", .body = "{\"error\":{\"message\":\"unavailable\"}}" }}, 1, "HTTP 503", 0, null),
        .delayCap = try scenario(gpa, io, binary, cap, &.{.{ .status = 429, .headers = "retry-after-ms: 5000", .body = "{\"error\":{\"message\":\"wait\"}}" }}, 1, "ProviderRetryDelayExceeded", 0, null),
        .inheritedTimeout = try scenario(gpa, io, binary, "{\"httpIdleTimeoutMs\":50,\"retry\":{\"enabled\":false,\"provider\":{\"maxRetries\":0,\"maxRetryDelayMs\":1000}}}", &.{delayed_success}, 1, "ProviderRequestTimeout", 0, 2000),
        .timeout = try scenario(gpa, io, binary, timeout, &.{ delayed_success, delayed_success }, 2, "ProviderRequestTimeout", 0, 2500),
        .liveReload = try reloadScenario(gpa, io, binary),
    };
    const encoded = try std.json.Stringify.valueAlloc(gpa, report, .{});
    defer gpa.free(encoded);
    if (environment.get("PI_PROVIDER_RETRY_REPORT")) |report_path| {
        const file = try Io.Dir.createFileAbsolute(io, report_path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, encoded);
        try file.writeStreamingAll(io, "\n");
    }
    std.debug.print("PROVIDER_RETRY_E2E_163=PASS\n{s}\n", .{encoded});
}
