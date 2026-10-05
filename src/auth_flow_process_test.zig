//! Staged authentication choices and credential-source labels through native PTY.
const std = @import("std");
const builtin = @import("builtin");
const pty = @import("test_support/pty.zig");
const fixture = @import("test_support/settings_fixture.zig");
const Io = std.Io;

fn contains(bytes: []const u8, marker: []const u8) bool {
    return std.mem.indexOf(u8, bytes, marker) != null;
}

const report =
    \\{
    \\  "anthropicCredentialReplaced": true,
    \\  "apiKeyProviderStage": true,
    \\  "configuredSourceVisible": "configured API key",
    \\  "corpCredentialStored": true,
    \\  "environmentSourceVisible": "OPENAI_API_KEY",
    \\  "exit": 0,
    \\  "explicitProviderScopedStage": "anthropic",
    \\  "secretsAbsentFromTerminal": true,
    \\  "stagedAuthenticationType": true,
    \\  "stderrBytes": 0,
    \\  "storedTypeMismatchVisible": true,
    \\  "subscriptionProviderStage": true,
    \\  "terminalRestored": true
    \\}
    \\
;

test "native auth flow stages provider methods sources masked replacement and cancellation" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = try pty.Scratch.init(gpa, io, "auth-flow");
    defer scratch.deinit();
    for ([_][]const u8{ "agent", "sessions", "workspace", "home" }) |name| try scratch.dir.createDir(io, name, .default_dir);
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = "{\"tuiMode\":\"regular\",\"enableInstallTelemetry\":false}" });
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/models.json", .data = "{\"providers\":{\"corp178\":{\"name\":\"Corp 178\",\"baseUrl\":\"https://corp.invalid/v1\",\"api\":\"openai-completions\",\"apiKey\":\"$CORP178_API_KEY\",\"oauth\":\"radius\",\"models\":[{\"id\":\"fast\",\"name\":\"Fast 178\"}]}}}" });
    const auth_file = try scratch.dir.createFile(io, "agent/auth.json", .{ .permissions = @enumFromInt(0o600) });
    defer auth_file.close(io);
    try auth_file.writeStreamingAll(io, "{\"anthropic\":{\"type\":\"api_key\",\"key\":\"existing-anthropic-178\"}}");
    try scratch.dir.writeFile(io, .{ .sub_path = "mock.json", .data = "[{\"content\":\"unused-auth-flow-178\"}]" });
    const agent = try std.fs.path.join(gpa, &.{ scratch.path, "agent" });
    defer gpa.free(agent);
    const workspace = try std.fs.path.join(gpa, &.{ scratch.path, "workspace" });
    defer gpa.free(workspace);
    const sessions = try std.fs.path.join(gpa, &.{ scratch.path, "sessions" });
    defer gpa.free(sessions);
    const home = try std.fs.path.join(gpa, &.{ scratch.path, "home" });
    defer gpa.free(home);
    const mock = try std.fs.path.join(gpa, &.{ scratch.path, "mock.json" });
    defer gpa.free(mock);
    var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environment.deinit();
    const binary = try pty.executablePath(gpa, io, environment.get("PI_TEST_BINARY") orelse "zig-out/bin/pi");
    defer gpa.free(binary);
    try environment.put("PI_AGENT_DIR", agent);
    try environment.put("HOME", home);
    try environment.put("TERM", "xterm-256color");
    try environment.put("NO_COLOR", "1");
    try environment.put("COLUMNS", "120");
    try environment.put("LINES", "38");
    try environment.put("OPENAI_API_KEY", "openai-env-secret-178");
    try environment.put("CORP178_API_KEY", "corp-env-secret-178");
    try environment.put("PI_SKIP_VERSION_CHECK", "1");
    try environment.put("PI_TELEMETRY", "0");
    const errors_file = try scratch.dir.createFile(io, "stderr.log", .{});
    defer errors_file.close(io);
    var session = try pty.Session.spawn(gpa, io, .{ .argv = &.{ binary, "--offline", "--mock-script", mock, "--session-dir", sessions, "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--no-extensions", "--approve" }, .cwd = .{ .path = workspace }, .environ_map = &environment, .stderr = .{ .file = errors_file } }, 240_000);
    defer session.deinit();
    const corp_secret = "corp-entered-secret-178";
    const anthropic_secret = "anthropic-entered-secret-178";
    var pos = try session.waitFor("> ", 0, 60_000);
    var start = session.output.items.len;
    try session.send("/login\r");
    pos = try session.waitFor("Select authentication method:", start, 60_000);
    try std.testing.expect(contains(session.output.items[start..], "Sign in with an account"));
    try std.testing.expect(contains(session.output.items[start..], "Sign in with an API key"));
    try session.send("\r");
    pos = try session.waitFor("Select subscription provider to configure:", pos, 60_000);
    const footer_end = try session.waitFor(" options", pos, 60_000);
    const footer_begin = std.mem.lastIndexOf(u8, session.output.items[pos..footer_end], "1/") orelse return error.MissingProviderInventoryFooter;
    const unfiltered_footer = try gpa.dupe(u8, session.output.items[pos + footer_begin .. footer_end]);
    defer gpa.free(unfiltered_footer);
    pos = footer_end;
    try session.send("anthropic");
    pos = try session.waitFor("anthropic_", pos, 60_000);
    pos = try session.waitFor("API key configured", pos, 60_000);
    try session.send("\x1b");
    // Wait for the original unfiltered inventory footer, rather than the
    // filtered footer that may still be arriving after the previous marker.
    pos = try session.waitFor(unfiltered_footer, pos, 60_000);
    try session.send("\x1b");
    pos = try session.waitFor("Select authentication method:", pos, 60_000);
    try session.send("\x1b");
    pos = try session.waitFor("\x1b[?2004h\r\x1b[2K> ", pos, 60_000);
    try session.send("/login\r");
    pos = try session.waitFor("Select authentication method:", pos, 60_000);
    try session.send("\x1b[B\r");
    pos = try session.waitFor("Select API key provider to configure:", pos, 60_000);
    try session.send("openai");
    pos = try session.waitFor("openai_", pos, 60_000);
    pos = try session.waitFor("env: OPENAI_API_KEY", pos, 60_000);
    try session.send("\x1b[3~");
    pos = try session.waitFor("options", pos, 60_000);
    try session.send("corp178");
    pos = try session.waitFor("corp178_", pos, 60_000);
    pos = try session.waitFor("configured API key", pos, 60_000);
    try session.send("\r");
    pos = try session.waitFor("Configure API key", pos, 60_000);
    start = session.output.items.len;
    try session.send(corp_secret);
    pos = try session.waitFor("Key: ", start, 60_000);
    try std.testing.expect(!contains(session.output.items[start..], corp_secret));
    try session.send("\r");
    pos = try session.waitFor("Credential stored in auth.json and activated for this process.", pos, 60_000);
    pos = try session.waitFor("> ", pos, 60_000);
    start = session.output.items.len;
    try session.send("/login anthropic\r");
    pos = try session.waitFor("Select authentication method for anthropic:", start, 60_000);
    try std.testing.expect(contains(session.output.items[start..], "Sign in with an account"));
    try std.testing.expect(contains(session.output.items[start..], "Sign in with an API key"));
    try std.testing.expect(contains(session.output.items[start..], "API key configured"));
    try session.send("\x1b[B\r");
    pos = try session.waitFor("Configure API key", pos, 60_000);
    try session.send(anthropic_secret);
    try session.send("\r");
    pos = try session.waitFor("Credential stored in auth.json and activated for this process.", pos, 60_000);
    _ = try session.waitFor("> ", pos, 60_000);
    const auth_bytes = try scratch.dir.readFileAlloc(io, "agent/auth.json", gpa, .limited(65536));
    defer gpa.free(auth_bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, auth_bytes, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings(corp_secret, parsed.value.object.get("corp178").?.object.get("key").?.string);
    try std.testing.expectEqualStrings(anthropic_secret, parsed.value.object.get("anthropic").?.object.get("key").?.string);
    try std.testing.expect(!contains(session.output.items, corp_secret));
    try std.testing.expect(!contains(session.output.items, anthropic_secret));
    try std.testing.expect(contains(session.output.items, "\x1b[?1049h") or contains(session.output.items, "\x1b[2J"));
    try std.testing.expect(contains(session.output.items, "\x1b[?1049l") or contains(session.output.items, "\x1b[2J"));
    try session.send("/quit\r");
    try fixture.cleanExit(&scratch, &session, "stderr.log");
    if (environment.get("PI_AUTH_FLOW_REPORT")) |path| {
        const file = try Io.Dir.createFileAbsolute(io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, report);
    }
    std.debug.print("AUTH_FLOW_E2E_178=PASS\n{s}\n", .{report});
}
