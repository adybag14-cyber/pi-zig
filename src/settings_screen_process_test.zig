//! Real settings-screen transactions, reload, tree filter and quiet startup.
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
    \\  "exit": 0,
    \\  "followUpMode": "all",
    \\  "fullscreen": true,
    \\  "liveReload": true,
    \\  "liveTreeFilter": true,
    \\  "nestedProviderPreserved": true,
    \\  "quietStartup": true,
    \\  "retryEnabled": false,
    \\  "retryMaxRetries": 5,
    \\  "stderrBytes": 0,
    \\  "steeringMode": "all",
    \\  "terminalRestored": true,
    \\  "treeFilterMode": "no-tools",
    \\  "unrelatedSettingPreserved": true
    \\}
    \\
;

test "native settings screen preserves nested retries live tree filters and quiet startup" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = try pty.Scratch.init(gpa, io, "settings-screen");
    defer scratch.deinit();
    for ([_][]const u8{ "agent", "sessions", "workspace", "home" }) |name| try scratch.dir.createDir(io, name, .default_dir);
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = "{\"tuiMode\":\"regular\",\"customMarker\":\"preserve-171\",\"collapseChangelog\":true,\"retry\":{\"enabled\":true,\"maxRetries\":4,\"baseDelayMs\":17,\"provider\":{\"timeoutMs\":321,\"maxRetries\":2,\"maxRetryDelayMs\":654}}}" });
    try scratch.dir.writeFile(io, .{ .sub_path = "mock.json", .data = "[{\"content\":\"unused-171\"}]" });
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
    const argv = &.{ binary, "--offline", "--mock-script", mock, "--session-dir", sessions, "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--approve" };
    {
        const errors_file = try scratch.dir.createFile(io, "stderr-main.log", .{});
        defer errors_file.close(io);
        var session = try pty.Session.spawn(gpa, io, .{ .argv = argv, .cwd = .{ .path = workspace }, .environ_map = &environment, .stderr = .{ .file = errors_file } }, 240_000);
        defer session.deinit();
        var pos = try session.waitFor("> ", 0, 30_000);
        try session.send("/settings\r");
        pos = try session.waitFor("Settings", pos, 30_000);
        try std.testing.expect(contains(session.output.items, "\x1b[?1049h") or contains(session.output.items, "\x1b[2J"));
        try fixture.choose(&session, "automatic retry", "Automatic retry");
        try fixture.choose(&session, "assistant retry attempts", "Assistant retry attempts");
        try fixture.choose(&session, "steering mode", "Steering mode");
        try fixture.choose(&session, "follow-up mode", "Follow-up mode");
        try fixture.choose(&session, "tree filter mode", "Tree filter mode");
        try fixture.choose(&session, "quiet startup", "Quiet startup");
        const start = session.output.items.len;
        try session.send("\x1b");
        pos = try session.waitFor("Reloaded:", start, 45_000);
        pos = try session.waitFor("> ", pos, 30_000);
        try session.send("hello-171\r");
        pos = try session.waitFor("unused-171", pos, 30_000);
        pos = try session.waitFor("> ", pos, 30_000);
        try session.send("/tree\r");
        pos = try session.waitFor("Session Tree", pos, 30_000);
        pos = try session.waitFor("no tools", pos, 30_000);
        try session.send("\x1b");
        pos = try session.waitFor("Tree navigation cancelled.", pos, 30_000);
        _ = try session.waitFor("> ", pos, 30_000);
        try session.send("/quit\r");
        try fixture.cleanExit(&scratch, &session, "stderr-main.log");
        try std.testing.expect(contains(session.output.items, "\x1b[?1049l") or contains(session.output.items, "\x1b[2J"));
        try std.testing.expect(contains(session.output.items, "no tools"));
    }
    const bytes = try scratch.dir.readFileAlloc(io, "agent/settings.json", gpa, .limited(65536));
    defer gpa.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, bytes, .{});
    defer parsed.deinit();
    const persisted = parsed.value.object;
    const retry = persisted.get("retry").?.object;
    try std.testing.expect(!retry.get("enabled").?.bool);
    try std.testing.expectEqual(@as(i64, 5), retry.get("maxRetries").?.integer);
    try std.testing.expectEqual(@as(i64, 17), retry.get("baseDelayMs").?.integer);
    const provider = retry.get("provider").?.object;
    try std.testing.expectEqual(@as(usize, 3), provider.count());
    try std.testing.expectEqual(@as(i64, 321), provider.get("timeoutMs").?.integer);
    try std.testing.expectEqual(@as(i64, 2), provider.get("maxRetries").?.integer);
    try std.testing.expectEqual(@as(i64, 654), provider.get("maxRetryDelayMs").?.integer);
    try std.testing.expectEqualStrings("preserve-171", persisted.get("customMarker").?.string);
    try std.testing.expect(persisted.get("collapseChangelog").?.bool);
    try std.testing.expectEqualStrings("all", persisted.get("steeringMode").?.string);
    try std.testing.expectEqualStrings("all", persisted.get("followUpMode").?.string);
    try std.testing.expectEqualStrings("no-tools", persisted.get("treeFilterMode").?.string);
    try std.testing.expect(persisted.get("quietStartup").?.bool);
    {
        const errors_file = try scratch.dir.createFile(io, "stderr-quiet.log", .{});
        defer errors_file.close(io);
        var session = try pty.Session.spawn(gpa, io, .{ .argv = argv, .cwd = .{ .path = workspace }, .environ_map = &environment, .stderr = .{ .file = errors_file } }, 120_000);
        defer session.deinit();
        const pos = try session.waitFor("> ", 0, 30_000);
        try std.testing.expect(!contains(session.output.items[0..pos], "pi (pi-zig)"));
        try session.send("/quit\r");
        try fixture.cleanExit(&scratch, &session, "stderr-quiet.log");
    }
    if (environment.get("PI_SETTINGS_SCREEN_REPORT")) |path| {
        const file = try Io.Dir.createFileAbsolute(io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, report);
    }
    std.debug.print("SETTINGS_SCREEN_E2E_188=PASS\n{s}\n", .{report});
}
