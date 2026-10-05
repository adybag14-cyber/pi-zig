//! Actual keyboard paste with native clipboard helper and owned temp cleanup.
const std = @import("std");
const builtin = @import("builtin");
const pty = @import("test_support/pty.zig");
const fixture = @import("test_support/settings_fixture.zig");
const json = @import("test_support/json_fixture.zig");
const Io = std.Io;
// Original structurally valid3x2 RGBA input, including original compressed bytes.
const png = "iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAYAAACddGYaAAAAI0lEQVR4nGMQkeP6HyVn/n+BXMp/BpEK8/9RFSn/F1RM/A8AgGILqoxnU7EAAAAASUVORK5CYII=";
test "native clipboard image and sanitized text paste preserve history and remove owned temp files" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = try pty.Scratch.init(gpa, io, "clipboard-paste");
    defer scratch.deinit();
    for ([_][]const u8{ "agent", "sessions", "home", "work", "bin", "tmp" }) |dir| try scratch.dir.createDir(io, dir, .default_dir);
    const image = try gpa.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(png));
    defer gpa.free(image);
    try std.base64.standard.Decoder.decode(image, png);
    try std.testing.expectEqual(@as(usize, 92), image.len);
    try scratch.dir.writeFile(io, .{ .sub_path = "clipboard.png", .data = image });
    try scratch.dir.writeFile(io, .{ .sub_path = "clipboard-mode", .data = "image" });
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = "{\"tuiMode\":\"regular\",\"quietStartup\":true,\"enableInstallTelemetry\":false,\"collapseChangelog\":true}" });
    try scratch.dir.writeFile(io, .{ .sub_path = "mock.json", .data = "[{\"content\":\"clipboard-image-ok-175\",\"tool_calls\":[]},{\"content\":\"clipboard-text-ok-175\",\"tool_calls\":[]}]" });
    const agent = try std.fs.path.join(gpa, &.{ scratch.path, "agent" });
    defer gpa.free(agent);
    const sessions = try std.fs.path.join(gpa, &.{ scratch.path, "sessions" });
    defer gpa.free(sessions);
    const home = try std.fs.path.join(gpa, &.{ scratch.path, "home" });
    defer gpa.free(home);
    const work = try std.fs.path.join(gpa, &.{ scratch.path, "work" });
    defer gpa.free(work);
    const bin = try std.fs.path.join(gpa, &.{ scratch.path, "bin" });
    defer gpa.free(bin);
    const temp = try std.fs.path.join(gpa, &.{ scratch.path, "tmp" });
    defer gpa.free(temp);
    const mock = try std.fs.path.join(gpa, &.{ scratch.path, "mock.json" });
    defer gpa.free(mock);
    const mode = try std.fs.path.join(gpa, &.{ scratch.path, "clipboard-mode" });
    defer gpa.free(mode);
    const image_path = try std.fs.path.join(gpa, &.{ scratch.path, "clipboard.png" });
    defer gpa.free(image_path);
    var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environment.deinit();
    const binary = try pty.executablePath(gpa, io, environment.get("PI_TEST_BINARY") orelse "zig-out/bin/pi");
    defer gpa.free(binary);
    const helper = try pty.executablePath(gpa, io, environment.get("PI_CLIPBOARD_TEST_HELPER") orelse "zig-out/bin/pi-clipboard-fixture");
    defer gpa.free(helper);
    try scratch.dir.symLink(io, helper, "bin/wl-paste", .{});
    try environment.put("PI_AGENT_DIR", agent);
    try environment.put("PI_SKIP_VERSION_CHECK", "1");
    try environment.put("PI_TELEMETRY", "0");
    try environment.put("PI_CLIPBOARD_E2E_MODE", mode);
    try environment.put("PI_CLIPBOARD_E2E_IMAGE", image_path);
    try environment.put("PI_CLIPBOARD_E2E_TEXT", "clipboard\r\ntext\t175\x01");
    try environment.put("WAYLAND_DISPLAY", "wayland-175");
    try environment.put("XDG_SESSION_TYPE", "wayland");
    try environment.put("TERM", "xterm-256color");
    try environment.put("NO_COLOR", "1");
    try environment.put("HOME", home);
    try environment.put("TMPDIR", temp);
    const path = try std.fmt.allocPrint(gpa, "{s}:{s}", .{ bin, environment.get("PATH") orelse "/usr/bin:/bin" });
    defer gpa.free(path);
    try environment.put("PATH", path);
    const errors_file = try scratch.dir.createFile(io, "stderr.log", .{});
    defer errors_file.close(io);
    var session = try pty.Session.spawn(gpa, io, .{ .argv = &.{ binary, "--offline", "--mock-script", mock, "--session-dir", sessions, "--session-id", "clipboard-175", "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--no-extensions", "--approve" }, .cwd = .{ .path = work }, .environ_map = &environment, .stderr = .{ .file = errors_file } }, 150_000);
    defer session.deinit();
    var pos = try session.waitFor("> ", 0, 30_000);
    try session.send("\x16\r");
    pos = try session.waitFor("clipboard-image-ok-175", pos, 30_000);
    pos = try session.waitFor("> ", pos, 30_000);
    // Verify the process actually staged one private clipboard image before
    // proving shutdown removes it. All paths stay beneath this owned root.
    const temp_dir = try scratch.dir.openDir(io, "tmp", .{ .iterate = true });
    defer temp_dir.close(io);
    var it = temp_dir.iterate();
    var staged: usize = 0;
    while (try it.next(io)) |entry| {
        if (!std.mem.startsWith(u8, entry.name, "pi-clipboard-")) continue;
        staged += 1;
        const staged_image = try temp_dir.readFileAlloc(io, entry.name, gpa, .limited(65536));
        defer gpa.free(staged_image);
        try std.testing.expectEqualSlices(u8, image, staged_image);
        const stat = try temp_dir.statFile(io, entry.name, .{});
        try std.testing.expectEqual(@as(u32, 0o600), @as(u32, @intCast(@intFromEnum(stat.permissions))) & 0o777);
    }
    try std.testing.expectEqual(@as(usize, 1), staged);
    try scratch.dir.writeFile(io, .{ .sub_path = "clipboard-mode", .data = "text" });
    try session.send("\x16\r");
    pos = try session.waitFor("clipboard-text-ok-175", pos, 30_000);
    _ = try session.waitFor("> ", pos, 30_000);
    try session.send("/quit\r");
    try fixture.cleanExit(&scratch, &session, "stderr.log");
    const durable = try scratch.dir.readFileAlloc(io, "sessions/clipboard-175.jsonl", gpa, .limited(1024 * 1024));
    defer gpa.free(durable);
    var lines = std.mem.splitScalar(u8, durable, '\n');
    var users: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const record = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer record.deinit();
        if (!json.kind(record.value, "message")) continue;
        const message = try json.field(record.value, "message");
        const role = try json.field(message, "role");
        if (role != .string or !std.mem.eql(u8, role.string, "user")) continue;
        users += 1;
        const content = try json.field(message, "content");
        if (users == 1) {
            try std.testing.expect(content == .array);
            var images: usize = 0;
            for (content.array.items) |block| {
                if (!json.kind(block, "image")) continue;
                images += 1;
                try json.text(try json.field(block, "mimeType"), "image/png");
                try json.text(try json.field(block, "data"), png);
            }
            try std.testing.expectEqual(@as(usize, 1), images);
        } else if (users == 2) {
            var text: std.ArrayList(u8) = .empty;
            defer text.deinit(gpa);
            if (content == .string) try text.appendSlice(gpa, content.string) else {
                try std.testing.expect(content == .array);
                for (content.array.items) |block| if (json.kind(block, "text")) try text.appendSlice(gpa, (try json.field(block, "text")).string);
            }
            try std.testing.expectEqualStrings("clipboard\ntext    175", text.items);
        }
    }
    try std.testing.expectEqual(@as(usize, 2), users);
    it = temp_dir.iterate();
    try std.testing.expect(try it.next(io) == null);
    const report = "{\"imagePaste\":true,\"imageMime\":\"image/png\",\"imageBytes\":92,\"textFallback\":\"clipboard\\ntext    175\",\"textSanitized\":true,\"userMessages\":2,\"temporaryFilesRemaining\":0,\"exit\":0,\"stderrBytes\":0}\n";
    if (environment.get("PI_CLIPBOARD_PASTE_REPORT")) |report_path| {
        const file = try Io.Dir.createFileAbsolute(io, report_path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, report);
    }
    std.debug.print("CLIPBOARD_PASTE_E2E_175=PASS\n{s}", .{report});
}
