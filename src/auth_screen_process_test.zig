//! Real Linux PTY authentication selector gates, ported from auth_screen_e2e.py.
const std = @import("std");
const builtin = @import("builtin");
const pty = @import("test_support/pty.zig");

fn contains(bytes: []const u8, marker: []const u8) bool {
    return std.mem.indexOf(u8, bytes, marker) != null;
}

fn fullscreen(bytes: []const u8) bool {
    return contains(bytes, "\x1b[?1049h") or contains(bytes, "\x1b[2J");
}

const report =
    \\{
    \\  "apiKeyStored": true,
    \\  "authPermissionsPrivate": true,
    \\  "credentialRemoved": true,
    \\  "exit": 0,
    \\  "loginFullscreen": true,
    \\  "logoutFullscreen": true,
    \\  "maskedSecret": true,
    \\  "secretAbsentFromTerminal": true,
    \\  "stderrBytes": 0,
    \\  "storedStatusVisible": true,
    \\  "terminalRestored": true
    \\}
    \\
;

test "native auth screen login logout masking storage permissions status and terminal restoration" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = try pty.Scratch.init(gpa, io, "auth-screen");
    defer scratch.deinit();
    for ([_][]const u8{ "agent", "sessions", "workspace", "home" }) |name| try scratch.dir.createDir(io, name, .default_dir);
    try scratch.dir.writeFile(io, .{ .sub_path = "mock.json", .data = "[{\"content\":\"unused-auth-177\"}]" });
    const agent_dir = try std.fs.path.join(gpa, &.{ scratch.path, "agent" });
    defer gpa.free(agent_dir);
    const sessions = try std.fs.path.join(gpa, &.{ scratch.path, "sessions" });
    defer gpa.free(sessions);
    const workspace = try std.fs.path.join(gpa, &.{ scratch.path, "workspace" });
    defer gpa.free(workspace);
    const home = try std.fs.path.join(gpa, &.{ scratch.path, "home" });
    defer gpa.free(home);
    const mock = try std.fs.path.join(gpa, &.{ scratch.path, "mock.json" });
    defer gpa.free(mock);
    var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environment.deinit();
    const binary = try pty.executablePath(gpa, io, environment.get("PI_TEST_BINARY") orelse "zig-out/bin/pi");
    defer gpa.free(binary);
    try environment.put("PI_AGENT_DIR", agent_dir);
    try environment.put("TERM", "xterm-256color");
    try environment.put("HOME", home);
    try environment.put("NO_COLOR", "1");
    try environment.put("PI_SKIP_VERSION_CHECK", "1");
    try environment.put("PI_TELEMETRY", "0");
    const errors_file = try scratch.dir.createFile(io, "stderr.log", .{});
    defer errors_file.close(io);
    var session = try pty.Session.spawn(gpa, io, .{
        .argv = &.{ binary, "--offline", "--mock-script", mock, "--session-dir", sessions, "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--no-extensions", "--approve" },
        .cwd = .{ .path = workspace },
        .environ_map = &environment,
        .stderr = .{ .file = errors_file },
    }, 240_000);
    defer session.deinit();
    const secret = "screen-secret-177";
    var pos = try session.waitFor("> ", 0, 45_000);
    const login_start = session.output.items.len;
    try session.send("/login\r");
    pos = try session.waitFor("Select authentication method:", login_start, 45_000);
    try std.testing.expect(fullscreen(session.output.items[login_start..]));
    try session.send("\x1b[B\r");
    pos = try session.waitFor("Select API key provider to configure:", pos, 45_000);
    try session.send("openai");
    pos = try session.waitFor("openai_", pos, 45_000);
    pos = try session.waitFor("OpenAI", pos, 45_000);
    try session.send("\r");
    pos = try session.waitFor("Configure API key", pos, 45_000);
    const masked_start = session.output.items.len;
    try session.send(secret);
    pos = try session.waitFor("Key: ", masked_start, 45_000);
    try std.testing.expect(!contains(session.output.items[masked_start..], secret));
    try session.send("\r");
    pos = try session.waitFor("Credential stored in auth.json and activated for this process.", pos, 45_000);
    pos = try session.waitFor("> ", pos, 45_000);
    const stored_text = try scratch.dir.readFileAlloc(io, "agent/auth.json", gpa, .limited(1024 * 1024));
    defer gpa.free(stored_text);
    const stored = try std.json.parseFromSlice(std.json.Value, gpa, stored_text, .{});
    defer stored.deinit();
    const openai = stored.value.object.get("openai") orelse return error.MissingStoredOpenAiCredential;
    try std.testing.expectEqualStrings("api_key", openai.object.get("type").?.string);
    try std.testing.expectEqualStrings(secret, openai.object.get("key").?.string);
    const auth_file = try scratch.dir.openFile(io, "agent/auth.json", .{});
    defer auth_file.close(io);
    const permissions = @intFromEnum((try auth_file.stat(io)).permissions);
    try std.testing.expectEqual(@as(@TypeOf(permissions), 0), permissions & 0o077);
    const logout_start = session.output.items.len;
    try session.send("/logout\r");
    pos = try session.waitFor("Select provider to logout:", logout_start, 45_000);
    try std.testing.expect(fullscreen(session.output.items[logout_start..]));
    try std.testing.expect(contains(session.output.items[logout_start..], "OpenAI"));
    try std.testing.expect(contains(session.output.items[logout_start..], "configured"));
    try session.send("\r");
    pos = try session.waitFor("Stored provider credential removed.", pos, 90_000);
    _ = try session.waitFor("> ", pos, 90_000);
    const after_text = scratch.dir.readFileAlloc(io, "agent/auth.json", gpa, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => try gpa.dupe(u8, "{}"),
        else => return err,
    };
    defer gpa.free(after_text);
    const after = try std.json.parseFromSlice(std.json.Value, gpa, after_text, .{});
    defer after.deinit();
    try std.testing.expect(!after.value.object.contains("openai"));
    try std.testing.expect(!contains(session.output.items, secret));
    try std.testing.expect(contains(session.output.items, "\x1b[?1049l") or contains(session.output.items, "\x1b[2J"));
    try session.send("/quit\r");
    const status = try session.wait(30_000);
    const errors = try scratch.dir.readFileAlloc(io, "stderr.log", gpa, .limited(1024 * 1024));
    defer gpa.free(errors);
    if (status != .exited or status.exited != 0 or errors.len != 0) {
        std.debug.print("Auth PTY failed: {any}, stderr={s}\n", .{ status, errors });
        return error.AuthScreenProcessFailed;
    }
    try std.testing.expect(!contains(session.output.items, secret));
    try std.testing.expectEqualStrings("", errors);
    if (environment.get("PI_AUTH_SCREEN_REPORT")) |report_path| {
        const report_file = try std.Io.Dir.createFileAbsolute(io, report_path, .{});
        defer report_file.close(io);
        try report_file.writeStreamingAll(io, report);
    }
    std.debug.print("AUTH_SCREEN_E2E_177=PASS\nloginFullscreen=true\nmaskedSecret=true\napiKeyStored=true\nauthPermissionsPrivate=true\nlogoutFullscreen=true\nstoredStatusVisible=true\ncredentialRemoved=true\nsecretAbsentFromTerminal=true\nterminalRestored=true\nexit=0\nstderrBytes=0\n", .{});
}
