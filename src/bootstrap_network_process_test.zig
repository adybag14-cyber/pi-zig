//! Real CLI bootstrap HTTP gates, ported from bootstrap_network_e2e.py.
const std = @import("std");
const builtin = @import("builtin");
const http = @import("test_support/http_fixture.zig");
const pty = @import("test_support/pty.zig");
const Io = std.Io;
const token_body = "{\"access_token\":\"bootstrap-access-168\",\"refresh_token\":\"bootstrap-refresh-168\",\"expires_in\":3600,\"scope\":\"gateway offline_access\"}";

const Policy = struct { timeout_ms: u64 = 1000, max_retries: u32 = 2, max_delay_ms: u64 = 1000, proxy: ?[]const u8 = null };

fn contains(bytes: []const u8, marker: []const u8) bool {
    return std.mem.indexOf(u8, bytes, marker) != null;
}

fn endpoint(gpa: std.mem.Allocator, server: *http.Server) ![]u8 {
    return std.fmt.allocPrint(gpa, "http://127.0.0.1:{d}", .{server.port});
}

fn proxyToken(_: ?*anyopaque, request: http.Request, _: []u8) !http.Response {
    // The former HTTPServer also rejects CONNECT before its POST handler.
    // Exercise the production client's fallback to an absolute-URI request.
    if (std.mem.eql(u8, request.method, "CONNECT")) return .{ .status = 501, .body = "" };
    if (!std.mem.eql(u8, request.method, "POST")) return .{ .status = 405, .body = "" };
    return .{ .body = token_body };
}

fn writeAgent(gpa: std.mem.Allocator, io: Io, scratch: *pty.Scratch, base_url: []const u8, policy: Policy) !void {
    try scratch.dir.createDir(io, "agent", .default_dir);
    var output: Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    try output.writer.writeAll("{\"providers\":{\"radius-bootstrap-168\":{\"name\":\"Radius Bootstrap 168\",\"baseUrl\":");
    try std.json.Stringify.value(base_url, .{}, &output.writer);
    try output.writer.writeAll(",\"oauth\":\"radius\"}}}");
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/models.json", .data = output.written() });
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/auth.json", .data = "{\"radius-bootstrap-168\":{\"type\":\"oauth\",\"refresh\":\"old-refresh-168\",\"access\":\"old-access-168\",\"expires\":0}}" });
    output.clearRetainingCapacity();
    try output.writer.print("{{\"retry\":{{\"provider\":{{\"timeoutMs\":{d},\"maxRetries\":{d},\"maxRetryDelayMs\":{d}}}}}", .{ policy.timeout_ms, policy.max_retries, policy.max_delay_ms });
    if (policy.proxy) |proxy| {
        try output.writer.writeAll(",\"httpProxy\":");
        try std.json.Stringify.value(proxy, .{}, &output.writer);
    }
    try output.writer.writeByte('}');
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = output.written() });
}

fn check(gpa: std.mem.Allocator, io: Io, scratch: *pty.Scratch, no_proxy: ?[]const u8, expect_ready: bool) !i64 {
    var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environment.deinit();
    const binary = try pty.executablePath(gpa, io, environment.get("PI_TEST_BINARY") orelse "zig-out/bin/pi");
    defer gpa.free(binary);
    const agent_dir = try std.fs.path.join(gpa, &.{ scratch.path, "agent" });
    defer gpa.free(agent_dir);
    try environment.put("PI_AGENT_DIR", agent_dir);
    for ([_][]const u8{ "http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY", "all_proxy", "ALL_PROXY", "no_proxy", "NO_PROXY" }) |name| _ = environment.swapRemove(name);
    if (no_proxy) |value| {
        try environment.put("NO_PROXY", value);
        try environment.put("no_proxy", value);
    }
    const start = Io.Clock.awake.now(io).toMilliseconds();
    const result = try std.process.run(gpa, io, .{
        .argv = &.{ binary, "auth", "check", "--provider", "radius-bootstrap-168", "--json", "--credentials" },
        .environ_map = &environment,
        .stdout_limit = .limited(65536),
        .stderr_limit = .limited(65536),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(15), .clock = .awake } },
    });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    const elapsed = Io.Clock.awake.now(io).toMilliseconds() - start;
    if (result.term != .exited or result.term.exited != @as(u8, if (expect_ready) 0 else 2) or result.stderr.len != 0) {
        std.debug.print("Bootstrap CLI failed: {any}, stdout={s}, stderr={s}\n", .{ result.term, result.stdout, result.stderr });
        return error.BootstrapCliFailed;
    }
    const payload = try std.json.parseFromSlice(std.json.Value, gpa, result.stdout, .{});
    defer payload.deinit();
    try std.testing.expectEqualStrings(if (expect_ready) "ready" else "invalid", payload.value.object.get("status").?.string);
    if (expect_ready) {
        try std.testing.expectEqualStrings("bootstrap-access-168", payload.value.object.get("credentials").?.string);
        const bytes = try scratch.dir.readFileAlloc(io, "agent/auth.json", gpa, .limited(65536));
        defer gpa.free(bytes);
        const auth = try std.json.parseFromSlice(std.json.Value, gpa, bytes, .{});
        defer auth.deinit();
        const stored = auth.value.object.get("radius-bootstrap-168").?.object;
        try std.testing.expectEqualStrings("bootstrap-access-168", stored.get("access").?.string);
        try std.testing.expectEqualStrings("bootstrap-refresh-168", stored.get("refresh").?.string);
        try std.testing.expectEqualStrings("gateway offline_access", stored.get("scope").?.string);
        try std.testing.expect(stored.get("expires").?.integer > Io.Clock.real.now(io).toMilliseconds());
    }
    return elapsed;
}

test "native bootstrap CLI retries rotates persists denies times out and respects target-aware proxies" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    {
        var scratch = try pty.Scratch.init(gpa, io, "bootstrap-retry");
        defer scratch.deinit();
        const server = try http.Server.startScripted(gpa, io, &.{ .{ .status = 503, .body = "{\"error\":\"temporary\"}", .headers = "Retry-After-Ms: 25\r\n" }, .{ .body = token_body } });
        defer server.deinit();
        const base = try endpoint(gpa, server);
        defer gpa.free(base);
        try writeAgent(gpa, io, &scratch, base, .{});
        const elapsed = try check(gpa, io, &scratch, "127.0.0.1,localhost", true);
        try server.finish();
        const requests = try server.snapshotRequests(gpa);
        defer http.freeRequests(gpa, requests);
        try std.testing.expectEqual(@as(usize, 2), requests.len);
        try std.testing.expect(requests[1].arrival_ms - requests[0].arrival_ms >= 20);
        try std.testing.expectEqualStrings("/v1/oauth/token", requests[0].path);
        try std.testing.expect(contains(requests[0].body, "refresh_token=old-refresh-168"));
        std.debug.print("retryAndPersistence requests=2 elapsedMs={d}\n", .{elapsed});
    }
    {
        var scratch = try pty.Scratch.init(gpa, io, "bootstrap-deny");
        defer scratch.deinit();
        const server = try http.Server.startScripted(gpa, io, &.{.{ .status = 503, .body = "{\"error\":\"terminal\"}", .headers = "X-Should-Retry: false\r\n" }});
        defer server.deinit();
        const base = try endpoint(gpa, server);
        defer gpa.free(base);
        try writeAgent(gpa, io, &scratch, base, .{ .max_retries = 4 });
        const elapsed = try check(gpa, io, &scratch, "127.0.0.1,localhost", false);
        try server.finish();
        const requests = try server.snapshotRequests(gpa);
        defer http.freeRequests(gpa, requests);
        try std.testing.expectEqual(@as(usize, 1), requests.len);
        std.debug.print("retryDenied requests=1 elapsedMs={d}\n", .{elapsed});
    }
    {
        var scratch = try pty.Scratch.init(gpa, io, "bootstrap-timeout");
        defer scratch.deinit();
        const server = try http.Server.startScripted(gpa, io, &.{.{ .body = token_body, .delay_ms = 350 }});
        defer server.deinit();
        const base = try endpoint(gpa, server);
        defer gpa.free(base);
        try writeAgent(gpa, io, &scratch, base, .{ .timeout_ms = 50, .max_retries = 0 });
        const elapsed = try check(gpa, io, &scratch, "127.0.0.1,localhost", false);
        try server.finish();
        const requests = try server.snapshotRequests(gpa);
        defer http.freeRequests(gpa, requests);
        try std.testing.expectEqual(@as(usize, 1), requests.len);
        try std.testing.expect(elapsed < 1500);
        std.debug.print("timeout requests=1 elapsedMs={d}\n", .{elapsed});
    }
    {
        var scratch = try pty.Scratch.init(gpa, io, "bootstrap-proxy");
        defer scratch.deinit();
        const proxy = try http.Server.start(gpa, io, null, proxyToken);
        defer proxy.deinit();
        const proxy_url = try endpoint(gpa, proxy);
        defer gpa.free(proxy_url);
        try writeAgent(gpa, io, &scratch, "http://radius-bootstrap.invalid:8123", .{ .proxy = proxy_url, .max_retries = 0 });
        const elapsed = check(gpa, io, &scratch, null, true) catch |err| {
            const observed = try proxy.snapshotRequests(gpa);
            defer http.freeRequests(gpa, observed);
            for (observed) |request| std.debug.print("Proxy observed {s} {s}: headers={s}, body={s}\n", .{ request.method, request.path, request.headers, request.body });
            return err;
        };
        try proxy.finish();
        const requests = try proxy.snapshotRequests(gpa);
        defer http.freeRequests(gpa, requests);
        var post_count: usize = 0;
        var token_request: ?http.CapturedRequest = null;
        for (requests) |request| {
            if (std.mem.eql(u8, request.method, "POST")) {
                post_count += 1;
                token_request = request;
            } else try std.testing.expectEqualStrings("CONNECT", request.method);
        }
        try std.testing.expectEqual(@as(usize, 1), post_count);
        const parsed = try std.Uri.parse(token_request.?.path);
        try std.testing.expectEqualStrings("radius-bootstrap.invalid", parsed.host.?.percent_encoded);
        try std.testing.expectEqualStrings("/v1/oauth/token", parsed.path.percent_encoded);
        std.debug.print("settingsProxy requests=1 absoluteUri={s} elapsedMs={d}\n", .{ token_request.?.path, elapsed });
    }
    {
        var scratch = try pty.Scratch.init(gpa, io, "bootstrap-no-proxy");
        defer scratch.deinit();
        const target = try http.Server.startScripted(gpa, io, &.{.{ .body = token_body }});
        defer target.deinit();
        const trap = try http.Server.startScripted(gpa, io, &.{.{ .status = 502, .body = "{\"error\":\"proxy should not be used\"}" }});
        defer trap.deinit();
        const target_url = try endpoint(gpa, target);
        defer gpa.free(target_url);
        const proxy_url = try endpoint(gpa, trap);
        defer gpa.free(proxy_url);
        try writeAgent(gpa, io, &scratch, target_url, .{ .proxy = proxy_url, .max_retries = 0 });
        const elapsed = try check(gpa, io, &scratch, "127.0.0.1", true);
        try target.finish();
        try trap.finish();
        const target_requests = try target.snapshotRequests(gpa);
        defer http.freeRequests(gpa, target_requests);
        const trap_requests = try trap.snapshotRequests(gpa);
        defer http.freeRequests(gpa, trap_requests);
        try std.testing.expectEqual(@as(usize, 1), target_requests.len);
        try std.testing.expectEqual(@as(usize, 0), trap_requests.len);
        std.debug.print("noProxyBypass targetRequests=1 proxyRequests=0 elapsedMs={d}\n", .{elapsed});
    }
    std.debug.print("BOOTSTRAP_NETWORK_E2E_168=PASS\n", .{});
}
