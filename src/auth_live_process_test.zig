//! Real loopback requests prove interactive credential rebinding and fallback.
const std = @import("std");
const builtin = @import("builtin");
const pty = @import("test_support/pty.zig");
const http = @import("test_support/http_fixture.zig");
const fixture = @import("test_support/settings_fixture.zig");
const Io = std.Io;

const Plan = struct {
    count: usize = 0,
    fn reply(raw: ?*anyopaque, request: http.Request, buffer: []u8) !http.Response {
        const self: *Plan = @ptrCast(@alignCast(raw.?));
        if (!std.mem.eql(u8, request.method, "POST")) return error.UnexpectedAuthLiveMethod;
        self.count += 1;
        return .{ .headers = "content-type: text/event-stream\r\n", .body = try std.fmt.bufPrint(buffer, "data: {{\"id\":\"chatcmpl-auth-{d}\",\"choices\":[{{\"delta\":{{\"content\":\"auth-live-{d}-177\"}}}}]}}\n\n" ++
            "data: {{\"choices\":[{{\"delta\":{{}},\"finish_reason\":\"stop\"}}],\"usage\":{{\"prompt_tokens\":2,\"completion_tokens\":1,\"total_tokens\":3}}}}\n\n" ++
            "data: [DONE]\n\n", .{ self.count, self.count }) };
    }
};

fn contains(bytes: []const u8, marker: []const u8) bool {
    return std.mem.indexOf(u8, bytes, marker) != null;
}

const report =
    \\{
    \\  "activeProvider": "corp177/fast",
    \\  "exit": 0,
    \\  "firstAuthorization": "interactive key",
    \\  "interactiveKeyStored": true,
    \\  "loginReboundActiveClient": true,
    \\  "logoutReloadedConfiguredCredential": true,
    \\  "logoutRemovedStoredCredential": true,
    \\  "providerRequests": 2,
    \\  "secondAuthorization": "models.json key",
    \\  "secretAbsentFromTerminal": true,
    \\  "stderrBytes": 0
    \\}
    \\
;

test "native live login rebinds requests and logout restores configured credentials" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var plan: Plan = .{};
    const server = try http.Server.start(gpa, io, &plan, Plan.reply);
    defer server.deinit();
    var scratch = try pty.Scratch.init(gpa, io, "auth-live");
    defer scratch.deinit();
    for ([_][]const u8{ "agent", "sessions", "workspace", "home" }) |name| try scratch.dir.createDir(io, name, .default_dir);
    const model_config = try std.fmt.allocPrint(gpa, "{{\"providers\":{{\"corp177\":{{\"name\":\"Corp 177\",\"baseUrl\":\"http://127.0.0.1:{d}/v1\",\"api\":\"openai-completions\",\"apiKey\":\"configured-old-177\",\"models\":[{{\"id\":\"fast\",\"name\":\"Fast 177\",\"contextWindow\":4096,\"maxTokens\":512}}]}}}}}}", .{server.port});
    defer gpa.free(model_config);
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/models.json", .data = model_config });
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = "{\"tuiMode\":\"regular\",\"quietStartup\":true,\"enableInstallTelemetry\":false,\"collapseChangelog\":true}" });
    const agent = try std.fs.path.join(gpa, &.{ scratch.path, "agent" });
    defer gpa.free(agent);
    const workspace = try std.fs.path.join(gpa, &.{ scratch.path, "workspace" });
    defer gpa.free(workspace);
    const sessions = try std.fs.path.join(gpa, &.{ scratch.path, "sessions" });
    defer gpa.free(sessions);
    const home = try std.fs.path.join(gpa, &.{ scratch.path, "home" });
    defer gpa.free(home);
    var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environment.deinit();
    const binary = try pty.executablePath(gpa, io, environment.get("PI_TEST_BINARY") orelse "zig-out/bin/pi");
    defer gpa.free(binary);
    try environment.put("PI_AGENT_DIR", agent);
    try environment.put("HOME", home);
    try environment.put("TERM", "xterm-256color");
    try environment.put("NO_COLOR", "1");
    try environment.put("PI_SKIP_VERSION_CHECK", "1");
    try environment.put("PI_TELEMETRY", "0");
    const errors_file = try scratch.dir.createFile(io, "stderr.log", .{});
    defer errors_file.close(io);
    var session = try pty.Session.spawn(gpa, io, .{ .argv = &.{ binary, "--provider", "corp177", "--model", "fast", "--session-dir", sessions, "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--no-extensions", "--no-tools", "--approve" }, .cwd = .{ .path = workspace }, .environ_map = &environment, .stderr = .{ .file = errors_file } }, 240_000);
    defer session.deinit();
    const new_key = "interactive-new-177";
    var pos = try session.waitFor("> ", 0, 60_000);
    try session.send("/login\r");
    pos = try session.waitFor("Select authentication method:", pos, 60_000);
    try session.send("\x1b[B\r");
    pos = try session.waitFor("Select API key provider to configure:", pos, 60_000);
    try session.send("corp177");
    pos = try session.waitFor("corp177_", pos, 60_000);
    try session.send("\r");
    pos = try session.waitFor("Configure API key", pos, 60_000);
    try session.send(new_key);
    try session.send("\r");
    pos = try session.waitFor("Credential stored in auth.json and activated for this process.", pos, 60_000);
    pos = try session.waitFor("> ", pos, 60_000);
    const stored_bytes = try scratch.dir.readFileAlloc(io, "agent/auth.json", gpa, .limited(65536));
    defer gpa.free(stored_bytes);
    const stored = try std.json.parseFromSlice(std.json.Value, gpa, stored_bytes, .{});
    defer stored.deinit();
    try std.testing.expectEqualStrings(new_key, stored.value.object.get("corp177").?.object.get("key").?.string);
    try session.send("first live auth request\r");
    pos = try session.waitFor("auth-live-1-177", pos, 60_000);
    pos = try session.waitFor("> ", pos, 60_000);
    try session.send("/logout\r");
    pos = try session.waitFor("Select provider to logout:", pos, 60_000);
    try session.send("\r");
    pos = try session.waitFor("Stored provider credential removed.", pos, 120_000);
    pos = try session.waitFor("> ", pos, 120_000);
    const removed_bytes = scratch.dir.readFileAlloc(io, "agent/auth.json", gpa, .limited(65536)) catch |err| switch (err) {
        error.FileNotFound => try gpa.dupe(u8, "{}"),
        else => return err,
    };
    defer gpa.free(removed_bytes);
    const removed = try std.json.parseFromSlice(std.json.Value, gpa, removed_bytes, .{});
    defer removed.deinit();
    try std.testing.expect(!removed.value.object.contains("corp177"));
    try session.send("second live auth request\r");
    pos = try session.waitFor("auth-live-2-177", pos, 60_000);
    _ = try session.waitFor("> ", pos, 60_000);
    try session.send("/quit\r");
    try fixture.cleanExit(&scratch, &session, "stderr.log");
    try std.testing.expect(!contains(session.output.items, new_key));
    try server.finish();
    const requests = try server.snapshotRequests(gpa);
    defer http.freeRequests(gpa, requests);
    try std.testing.expectEqual(@as(usize, 2), requests.len);
    try std.testing.expect(std.mem.endsWith(u8, requests[0].path, "/chat/completions"));
    try std.testing.expectEqualStrings("Bearer interactive-new-177", requests[0].header("authorization").?);
    try std.testing.expectEqualStrings("Bearer configured-old-177", requests[1].header("authorization").?);
    if (environment.get("PI_AUTH_LIVE_REPORT")) |path| {
        const file = try Io.Dir.createFileAbsolute(io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, report);
    }
    std.debug.print("AUTH_LIVE_E2E_177=PASS\n{s}\n", .{report});
}
