//! Global/project settings and live rendering through the real native PTY.
const std = @import("std");
const builtin = @import("builtin");
const pty = @import("test_support/pty.zig");
const vt = @import("test_support/terminal_screen.zig");
const Io = std.Io;
const settings_fixture = @import("test_support/settings_fixture.zig");
const choose = settings_fixture.choose;
const cleanExit = settings_fixture.cleanExit;

fn contains(bytes: []const u8, marker: []const u8) bool {
    return std.mem.indexOf(u8, bytes, marker) != null;
}

const report =
    \\{
    \\  "editorPadding": 1,
    \\  "globalEdit": true,
    \\  "maxTurnsProjectDefaultOverride": 16,
    \\  "outputPad": 0,
    \\  "projectClearAndRestore": true,
    \\  "projectScope": true,
    \\  "settingsDrivenFullscreen": true,
    \\  "stderrBytes": 0,
    \\  "terminalProgress": true,
    \\  "terminalRestored": true
    \\}
    \\
;

test "native project settings preserve scopes keys progress padding and fresh fullscreen startup" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = try pty.Scratch.init(gpa, io, "project-settings");
    defer scratch.deinit();
    try scratch.dir.createDirPath(io, "workspace/.pi");
    for ([_][]const u8{ "agent", "sessions", "home" }) |name| try scratch.dir.createDir(io, name, .default_dir);
    // Pi 1 defaults to fullscreen. Start this toggle fixture in regular mode
    // explicitly, preserving its project override and fresh-process assertions.
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = "{\"customMarker\":\"global-preserve-173\",\"maxTurns\":32,\"terminal\":{\"showTerminalProgress\":false},\"editorPaddingX\":0,\"outputPad\":1,\"tuiMode\":\"regular\"}" });
    try scratch.dir.writeFile(io, .{ .sub_path = "workspace/.pi/settings.json", .data = "{\"maxTurns\":16,\"projectMarker\":\"preserve-173\"}" });
    try scratch.dir.writeFile(io, .{ .sub_path = "mock.json", .data = "[{\"content\":\"assistant-project-173\"}]" });
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
        const stderr_file = try scratch.dir.createFile(io, "stderr-first.log", .{});
        defer stderr_file.close(io);
        var session = try pty.Session.spawn(gpa, io, .{ .argv = argv, .cwd = .{ .path = workspace }, .environ_map = &environment, .stderr = .{ .file = stderr_file } }, 240_000);
        defer session.deinit();
        var pos = try session.waitFor("> ", 0, 40_000);
        try session.send("/settings\r");
        pos = try session.waitFor("Settings", pos, 40_000);
        var start = session.output.items.len;
        try session.send("\t");
        _ = try session.waitFor("PROJECT", start, 40_000);
        try choose(&session, "terminal progress", "Terminal progress");
        start = session.output.items.len;
        try session.send("\x7f");
        _ = try session.waitFor("Project override cleared", start, 40_000);
        try session.send("\r");
        try io.sleep(.fromMilliseconds(120), .awake);
        try choose(&session, "editor padding", "Editor padding");
        try choose(&session, "output padding", "Output padding");
        try choose(&session, "tui mode", "TUI mode");
        start = session.output.items.len;
        try session.send("\t");
        _ = try session.waitFor("GLOBAL", start, 40_000);
        try choose(&session, "hide thinking", "Hide thinking block");
        start = session.output.items.len;
        try session.send("\x1b");
        pos = try session.waitFor("Reloaded:", start, 60_000);
        pos = try session.waitFor(" > ", pos, 40_000);
        start = session.output.items.len;
        try session.send("hello-173\r");
        _ = try session.waitFor("assistant-project-173", start, 40_000);
        try std.testing.expect(contains(session.output.items[start..], "\x1b]9;4;3\x07"));
        pos = try session.waitFor("\x1b]9;4;0\x07", start, 40_000);
        _ = try session.waitFor(" > ", pos, 40_000);
        try session.send("/quit\r");
        try cleanExit(&scratch, &session, "stderr-first.log");
    }
    const global_bytes = try scratch.dir.readFileAlloc(io, "agent/settings.json", gpa, .limited(65536));
    defer gpa.free(global_bytes);
    const project_bytes = try scratch.dir.readFileAlloc(io, "workspace/.pi/settings.json", gpa, .limited(65536));
    defer gpa.free(project_bytes);
    const global = try std.json.parseFromSlice(std.json.Value, gpa, global_bytes, .{});
    defer global.deinit();
    const project = try std.json.parseFromSlice(std.json.Value, gpa, project_bytes, .{});
    defer project.deinit();
    const global_settings = global.value.object;
    const project_settings = project.value.object;
    try std.testing.expect(global_settings.get("hideThinkingBlock").?.bool);
    try std.testing.expectEqualStrings("global-preserve-173", global_settings.get("customMarker").?.string);
    try std.testing.expectEqual(@as(i64, 16), project_settings.get("maxTurns").?.integer);
    try std.testing.expectEqualStrings("preserve-173", project_settings.get("projectMarker").?.string);
    try std.testing.expect(project_settings.get("terminal").?.object.get("showTerminalProgress").?.bool);
    try std.testing.expectEqual(@as(i64, 1), project_settings.get("editorPaddingX").?.integer);
    try std.testing.expectEqual(@as(i64, 0), project_settings.get("outputPad").?.integer);
    try std.testing.expectEqualStrings("fullscreen", project_settings.get("tuiMode").?.string);
    {
        const stderr_file = try scratch.dir.createFile(io, "stderr-second.log", .{});
        defer stderr_file.close(io);
        var session = try pty.Session.spawn(gpa, io, .{ .argv = argv, .cwd = .{ .path = workspace }, .environ_map = &environment, .stderr = .{ .file = stderr_file } }, 120_000);
        defer session.deinit();
        var screen = try vt.Screen.init(gpa, 100, 40);
        defer screen.deinit();
        var consumed: usize = 0;
        const deadline = Io.Clock.awake.now(io).toMilliseconds() + 40_000;
        var prompt_observed = false;
        while (Io.Clock.awake.now(io).toMilliseconds() < deadline) {
            try session.drain();
            try screen.feed(session.output.items[consumed..]);
            consumed = session.output.items.len;
            const row = screen.cells()[screen.row * screen.columns ..][0..screen.columns];
            if (screen.in_alternate and screen.column == 3 and row[0].scalar == ' ' and row[1].scalar == '>' and row[2].scalar == ' ') {
                prompt_observed = true;
                break;
            }
            if (try session.exited()) break;
            try io.sleep(.fromMilliseconds(10), .awake);
        }
        if (!prompt_observed) {
            const cells = try screen.textAlloc(gpa);
            defer gpa.free(cells);
            std.debug.print("Project fullscreen padding/cursor missing: row={d} column={d}\n{s}\n", .{ screen.row, screen.column, cells });
        }
        try std.testing.expect(prompt_observed);
        try std.testing.expect(contains(session.output.items, "\x1b[?1049h"));
        try session.send("/quit\r");
        try cleanExit(&scratch, &session, "stderr-second.log");
        try std.testing.expect(contains(session.output.items, "\x1b[?1049l"));
    }
    if (environment.get("PI_PROJECT_SETTINGS_REPORT")) |path| {
        const file = try Io.Dir.createFileAbsolute(io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, std.mem.trimEnd(u8, report, " "));
    }
    std.debug.print("PROJECT_SETTINGS_E2E_188=PASS\n{s}\n", .{report});
}
