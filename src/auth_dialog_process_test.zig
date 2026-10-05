//! Native browser/device OAuth dialog parity with auth_dialog_e2e.py.
const std = @import("std");
const builtin = @import("builtin");
const pty = @import("test_support/pty.zig");
const http = @import("test_support/http_fixture.zig");

const OAuth = struct {
    port: u16 = 0,
    fn route(raw: ?*anyopaque, request: http.Request, buffer: []u8) !http.Response {
        const self: *OAuth = @ptrCast(@alignCast(raw.?));
        if (std.mem.eql(u8, request.method, "GET")) {
            if (std.mem.eql(u8, request.path, "/v1/oauth")) return .{ .body = try std.fmt.bufPrint(buffer, "{{\"authorizationEndpoint\":\"http://127.0.0.1:{d}/authorize\"}}", .{self.port}) };
            if (std.mem.eql(u8, request.path, "/v1/config")) return .{ .body = try std.fmt.bufPrint(buffer, "{{\"baseUrl\":\"http://127.0.0.1:{d}/v1\",\"models\":[{{\"id\":\"fast\",\"name\":\"Fast 179\",\"reasoning\":false,\"input\":[\"text\"],\"cost\":{{}},\"contextWindow\":4096,\"maxTokens\":512}}]}}", .{self.port}) };
            if (std.mem.startsWith(u8, request.path, "/authorize")) return .{ .body = "{\"ok\":true}" };
        } else if (std.mem.eql(u8, request.method, "POST")) {
            if (std.mem.eql(u8, request.path, "/v1/oauth/device")) return .{ .body = try std.fmt.bufPrint(buffer, "{{\"device_code\":\"device-179\",\"user_code\":\"CODE-179\",\"verification_uri\":\"http://127.0.0.1:{d}/device\",\"expires_in\":600,\"interval\":1}}", .{self.port}) };
            if (std.mem.eql(u8, request.path, "/v1/oauth/token")) {
                if (std.mem.indexOf(u8, request.body, "device_code") != null) return .{ .status = 400, .body = "{\"error\":\"authorization_pending\"}" };
                return .{ .body = "{\"access_token\":\"access-179\",\"refresh_token\":\"refresh-179\",\"expires_in\":3600,\"scope\":\"gateway offline_access\"}" };
            }
        }
        return .{ .status = 404, .body = "{\"error\":\"not_found\"}" };
    }
};

const report =
    \\{
    \\  "browserDialog": true,
    \\  "callbackCompletion": true,
    \\  "cooperativeCancellation": true,
    \\  "credentialPersisted": true,
    \\  "deviceCodeDialog": true,
    \\  "exit": 0,
    \\  "osc8Hyperlink": true,
    \\  "stderrBytes": 0,
    \\  "terminalRestored": true
    \\}
    \\
;

fn openedUrl(scratch: *pty.Scratch) ![]u8 {
    const end = std.Io.Clock.awake.now(scratch.io).toMilliseconds() + 10_000;
    while (std.Io.Clock.awake.now(scratch.io).toMilliseconds() < end) {
        const url = scratch.dir.readFileAlloc(scratch.io, "opened-url.txt", scratch.gpa, .limited(65536)) catch |err| switch (err) {
            error.FileNotFound => {
                try scratch.io.sleep(.fromMilliseconds(50), .awake);
                continue;
            },
            else => return err,
        };
        if (url.len > 0) return url;
        scratch.gpa.free(url);
        try scratch.io.sleep(.fromMilliseconds(50), .awake);
    }
    return error.BrowserOpenerDidNotReceiveUrl;
}

fn stateFromUrl(url: []const u8) ![]const u8 {
    const query_start = std.mem.indexOfScalar(u8, url, '?') orelse return error.MissingBrowserOAuthState;
    var pairs = std.mem.splitScalar(u8, url[query_start + 1 ..], '&');
    while (pairs.next()) |pair| {
        if (std.mem.startsWith(u8, pair, "state=")) {
            if (pair.len == 6) return error.MissingBrowserOAuthState;
            // Retain the URL's encoded spelling for the callback query so it
            // decodes to the identical state on the actual OAuth listener.
            return pair[6..];
        }
    }
    return error.MissingBrowserOAuthState;
}

test "native OAuth browser callback hyperlink persistence device dialog and cooperative cancellation" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var oauth: OAuth = .{};
    const server = try http.Server.start(gpa, io, &oauth, OAuth.route);
    defer server.deinit();
    oauth.port = server.port;
    var scratch = try pty.Scratch.init(gpa, io, "auth-dialog");
    defer scratch.deinit();
    for ([_][]const u8{ "agent", "sessions", "work", "home", "bin" }) |name| try scratch.dir.createDir(io, name, .default_dir);
    var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environment.deinit();
    const binary = try std.fs.path.resolve(gpa, &.{environment.get("PI_TEST_BINARY") orelse "zig-out/bin/pi"});
    defer gpa.free(binary);
    const opener = try std.fs.path.resolve(gpa, &.{environment.get("PI_TEST_AUTH_OPENER_BINARY") orelse "zig-out/bin/pi-auth-opener"});
    defer gpa.free(opener);
    try scratch.dir.symLink(io, opener, "bin/xdg-open", .{});
    const models = try std.fmt.allocPrint(gpa, "{{\"providers\":{{\"corp179\":{{\"name\":\"Corp 179\",\"baseUrl\":\"http://127.0.0.1:{d}/v1\",\"api\":\"pi-messages\",\"oauth\":\"radius\",\"models\":[{{\"id\":\"fast\",\"name\":\"Fast 179\",\"contextWindow\":4096,\"maxTokens\":512}}]}}}}}}", .{server.port});
    defer gpa.free(models);
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/models.json", .data = models });
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = "{\"quietStartup\":true,\"enableInstallTelemetry\":false,\"collapseChangelog\":true}" });
    try scratch.dir.writeFile(io, .{ .sub_path = "mock.json", .data = "[{\"content\":\"unused-179\"}]" });
    const work = try std.fs.path.join(gpa, &.{ scratch.path, "work" });
    defer gpa.free(work);
    const sessions = try std.fs.path.join(gpa, &.{ scratch.path, "sessions" });
    defer gpa.free(sessions);
    const mock = try std.fs.path.join(gpa, &.{ scratch.path, "mock.json" });
    defer gpa.free(mock);
    for ([_][2][]const u8{ .{ "PI_AGENT_DIR", "agent" }, .{ "HOME", "home" }, .{ "PI_AUTH_OPENED_URL", "opened-url.txt" } }) |entry| {
        const path = try std.fs.path.join(gpa, &.{ scratch.path, entry[1] });
        defer gpa.free(path);
        try environment.put(entry[0], path);
    }
    const path = try std.fmt.allocPrint(gpa, "{s}/bin:{s}", .{ scratch.path, environment.get("PATH") orelse "" });
    defer gpa.free(path);
    try environment.put("PATH", path);
    for ([_][2][]const u8{ .{ "TERM", "xterm-256color" }, .{ "COLUMNS", "120" }, .{ "LINES", "38" }, .{ "NO_COLOR", "1" }, .{ "PI_SKIP_VERSION_CHECK", "1" }, .{ "PI_TELEMETRY", "0" } }) |entry| try environment.put(entry[0], entry[1]);
    const errors_file = try scratch.dir.createFile(io, "stderr.log", .{});
    defer errors_file.close(io);
    var session = try pty.Session.spawn(gpa, io, .{
        .argv = &.{ binary, "--mock-script", mock, "--session-dir", sessions, "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--no-extensions", "--approve" },
        .cwd = .{ .path = work },
        .environ_map = &environment,
        .stderr = .{ .file = errors_file },
    }, 240_000);
    defer session.deinit();
    var pos = try session.waitFor("> ", 0, 45_000);
    const browser_start = session.output.items.len;
    try session.send("/login corp179 browser\r");
    pos = try session.waitFor("Open this link to continue:", browser_start, 45_000);
    const url = try openedUrl(&scratch);
    defer gpa.free(url);
    const state = try stateFromUrl(url);
    // The title and hyperlink may arrive in different PTY chunks. Preserve
    // the hyperlink gate while waiting for its actual bytes, not a timing race.
    _ = try session.waitFor("\x1b]8;;http://127.0.0.1:", browser_start, 45_000);
    try std.testing.expect(std.mem.indexOf(u8, session.output.items[browser_start..], "\x1b]8;;http://127.0.0.1:") != null);
    const callback = try std.fmt.allocPrint(gpa, "/oauth/callback?code=browser-code-179&state={s}", .{state});
    defer gpa.free(callback);
    try std.testing.expectEqual(@as(u16, 200), try http.get(io, 1456, callback));
    pos = try session.waitFor("Radius OAuth credential stored", pos, 60_000);
    pos = try session.waitFor("> ", pos, 45_000);
    const stored_text = try scratch.dir.readFileAlloc(io, "agent/auth.json", gpa, .limited(1024 * 1024));
    defer gpa.free(stored_text);
    const stored = try std.json.parseFromSlice(std.json.Value, gpa, stored_text, .{});
    defer stored.deinit();
    try std.testing.expectEqualStrings("access-179", stored.value.object.get("corp179").?.object.get("access").?.string);
    const device_start = session.output.items.len;
    try session.send("/login corp179 device-code\r");
    pos = try session.waitFor("CODE-179", device_start, 30_000);
    try std.testing.expect(std.mem.indexOf(u8, session.output.items[device_start..], "Authorize this device:") != null);
    try session.send("\x1b");
    pos = try session.waitFor("Login cancelled.", pos, 30_000);
    _ = try session.waitFor("> ", pos, 45_000);
    try std.testing.expect(std.mem.indexOf(u8, session.output.items, "\x1b[?1049l") != null or std.mem.indexOf(u8, session.output.items, "\x1b[2J") != null);
    try session.send("/quit\r");
    const term = try session.wait(20_000);
    const errors = try scratch.dir.readFileAlloc(io, "stderr.log", gpa, .limited(1024 * 1024));
    defer gpa.free(errors);
    if (term != .exited or term.exited != 0 or errors.len != 0) {
        std.debug.print("Auth dialog failed {any}: {s}\n", .{ term, errors });
        return error.AuthDialogProcessFailed;
    }
    try server.finish();
    if (environment.get("PI_AUTH_DIALOG_REPORT")) |report_path| {
        const file = try std.Io.Dir.createFileAbsolute(io, report_path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, report);
    }
    std.debug.print("AUTH_DIALOG_E2E_179=PASS\nbrowserDialog=true\nosc8Hyperlink=true\ncallbackCompletion=true\ncredentialPersisted=true\ndeviceCodeDialog=true\ncooperativeCancellation=true\nterminalRestored=true\nexit=0\nstderrBytes=0\n", .{});
}
