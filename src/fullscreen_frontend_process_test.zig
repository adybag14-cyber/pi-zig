//! Persistent fullscreen behavior observed in real offline CLI PTY screens.
const std = @import("std");
const builtin = @import("builtin");
const pty = @import("test_support/pty.zig");
const vt = @import("test_support/terminal_screen.zig");
const Io = std.Io;

const Fixture = struct {
    scratch: pty.Scratch,
    environment: std.process.Environ.Map,
    binary: []u8,
    mock: []u8,
    history: []u8,
    fn init(mode: []const u8) !Fixture {
        const gpa = std.testing.allocator;
        const io = std.testing.io;
        var scratch = try pty.Scratch.init(gpa, io, "fullscreen");
        errdefer scratch.deinit();
        for ([_][]const u8{ "agent", "sessions", "home" }) |name| try scratch.dir.createDir(io, name, .default_dir);
        const settings = try std.fmt.allocPrint(gpa, "{{\"tuiMode\":\"{s}\",\"quietStartup\":true,\"enableInstallTelemetry\":false,\"retry\":{{\"enabled\":false}}}}", .{mode});
        defer gpa.free(settings);
        try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = settings });
        try scratch.dir.writeFile(io, .{ .sub_path = "mock.json", .data = "[{\"content\":\"stream-first\\nstream-second\\nstream-final\",\"stream_chunks\":[\"stream-first\\n\",\"stream-second\\n\",\"stream-final\"],\"stream_chunk_delay_ms\":400},{\"content\":\"second-first\\nsecond-final\",\"stream_chunks\":[\"second-first\\n\",\"second-final\"],\"stream_chunk_delay_ms\":1000}]" });
        var json: Io.Writer.Allocating = .init(gpa);
        defer json.deinit();
        try json.writer.writeAll("{\"type\":\"session\",\"version\":3,\"id\":\"fullscreen-history\",\"timestamp\":\"2026-10-05T00:00:00.000Z\",\"cwd\":\"/tmp\",\"tipId\":\"entry59\"}\n");
        for (0..60) |index| {
            try json.writer.print("{{\"type\":\"message\",\"id\":\"entry{d}\",\"parentId\":", .{index});
            if (index == 0) try json.writer.writeAll("null") else try json.writer.print("\"entry{d}\"", .{index - 1});
            try json.writer.print(",\"timestamp\":\"2026-10-05T00:00:00.000Z\",\"message\":{{\"role\":\"user\",\"content\":[{{\"type\":\"text\",\"text\":\"history-row-{d:0>3}\"}}]}}}}\n", .{index});
        }
        // This inactive sibling must never appear in the active transcript.
        try json.writer.writeAll("{\"type\":\"message\",\"id\":\"inactive\",\"parentId\":\"entry0\",\"timestamp\":\"2026-10-05T00:00:00.000Z\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"inactive-history-forbidden\"}]}}\n");
        try scratch.dir.writeFile(io, .{ .sub_path = "history.jsonl", .data = json.written() });
        var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
        errdefer environment.deinit();
        const binary = try pty.executablePath(gpa, io, environment.get("PI_TEST_BINARY") orelse "zig-out/bin/pi");
        errdefer gpa.free(binary);
        const mock = try std.fs.path.join(gpa, &.{ scratch.path, "mock.json" });
        errdefer gpa.free(mock);
        const history = try std.fs.path.join(gpa, &.{ scratch.path, "history.jsonl" });
        errdefer gpa.free(history);
        const agent = try std.fs.path.join(gpa, &.{ scratch.path, "agent" });
        defer gpa.free(agent);
        const home = try std.fs.path.join(gpa, &.{ scratch.path, "home" });
        defer gpa.free(home);
        try environment.put("PI_AGENT_DIR", agent);
        try environment.put("HOME", home);
        try environment.put("TERM", "xterm-256color");
        try environment.put("NO_COLOR", "1");
        try environment.put("PI_SKIP_VERSION_CHECK", "1");
        try environment.put("PI_TELEMETRY", "0");
        // Actual offline frontend must start and work with no Node on PATH.
        try environment.put("PATH", "/nonexistent-fullscreen-fixture-path");
        return .{ .scratch = scratch, .environment = environment, .binary = binary, .mock = mock, .history = history };
    }
    fn deinit(self: *Fixture) void {
        const gpa = std.testing.allocator;
        gpa.free(self.binary);
        gpa.free(self.mock);
        gpa.free(self.history);
        self.environment.deinit();
        self.scratch.deinit();
    }
    fn spawn(self: *Fixture, errors: Io.File) !pty.Session {
        return pty.Session.spawn(std.testing.allocator, std.testing.io, .{
            .argv = &.{ self.binary, "--offline", "--mock-script", self.mock, "--session", self.history, "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--no-extensions", "--no-tools", "--approve" },
            .cwd = .{ .path = self.scratch.path },
            .environ_map = &self.environment,
            .stderr = .{ .file = errors },
        }, 90_000);
    }
};
const Observer = struct {
    screen: vt.Screen,
    consumed: usize = 0,
    fn init() !Observer {
        return .{ .screen = try vt.Screen.init(std.testing.allocator, 100, 40) };
    }
    fn deinit(self: *Observer) void {
        self.screen.deinit();
    }
    fn drain(self: *Observer, child: *pty.Session) !void {
        try child.drain();
        try self.screen.feed(child.output.items[self.consumed..]);
        self.consumed = child.output.items.len;
    }
    fn wait(self: *Observer, child: *pty.Session, marker: []const u8, after_frame: usize) !void {
        const end = Io.Clock.awake.now(child.io).toMilliseconds() + 5000;
        while (Io.Clock.awake.now(child.io).toMilliseconds() < end) {
            try self.drain(child);
            if (self.screen.frames > after_frame and try self.screen.contains(marker)) return;
            if (try child.exited()) break;
            try child.io.sleep(.fromMilliseconds(10), .awake);
        }
        const text = try self.screen.textAlloc(std.testing.allocator);
        defer std.testing.allocator.free(text);
        std.debug.print("Fullscreen cells missing {s}; frames={d}; cells:\n{s}\n", .{ marker, self.screen.frames, text });
        return error.FullscreenCellAssertionFailed;
    }
    fn send(self: *Observer, child: *pty.Session, input: []const u8, marker: []const u8) !void {
        const frame = self.screen.frames;
        try child.send(input);
        try self.wait(child, marker, frame);
    }
};

fn cleanExit(fixture: *Fixture, child: *pty.Session, observed: *Observer) !void {
    try child.send("\x15/quit\r");
    const term = try child.wait(5000);
    try observed.drain(child);
    try std.testing.expect(term == .exited and term.exited == 0);
    try std.testing.expect(!observed.screen.in_alternate);
    const errors = try fixture.scratch.dir.readFileAlloc(std.testing.io, "stderr.log", std.testing.allocator, .limited(65536));
    defer std.testing.allocator.free(errors);
    try std.testing.expectEqualStrings("", errors);
}

test "real fullscreen CLI keeps Home End in editor and Ctrl Home End pages in retained branch viewport" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawn(errors);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.wait(&child, "history-row-059", 0);
    try std.testing.expect(observed.screen.in_alternate);
    try std.testing.expect(!try observed.screen.contains("inactive-history-forbidden"));
    try observed.send(&child, "draft", "> draft");
    try observed.send(&child, "\x1b[HX", "> Xdraft");
    try std.testing.expect(try observed.screen.contains("history-row-059"));
    try observed.send(&child, "\x1b[FY", "> XdraftY");
    try std.testing.expect(try observed.screen.contains("history-row-059"));
    try observed.send(&child, "\x1b[1;5H", "history-row-000");
    try std.testing.expect(!try observed.screen.contains("history-row-059"));
    try observed.send(&child, "\x1b[H\x1b[F", "> XdraftY");
    try std.testing.expect(try observed.screen.contains("history-row-000"));
    try observed.send(&child, "\x1b[6~", "history-row-030");
    try std.testing.expect(!try observed.screen.contains("history-row-000"));
    try observed.send(&child, "\x1b[5~", "history-row-000");
    try observed.send(&child, "\x1b[1;5F", "history-row-059");
    const resize_frame = observed.screen.frames;
    try observed.screen.resize(70, 22);
    try child.resize(70, 22);
    try observed.wait(&child, "history-row-059", resize_frame);
    try std.testing.expect(try observed.screen.contains("> XdraftY"));
    try observed.send(&child, "\x1b[200~\nsecond-line Ω\x1b[201~", "second-line Ω");
    try child.send("\x15\x7f\x15/quit\r");
    const term = try child.wait(5000);
    try std.testing.expect(term == .exited and term.exited == 0);
    try observed.drain(&child);
    try std.testing.expect(!observed.screen.in_alternate);
    const stderr = try fixture.scratch.dir.readFileAlloc(std.testing.io, "stderr.log", std.testing.allocator, .limited(65536));
    defer std.testing.allocator.free(stderr);
    try std.testing.expectEqualStrings("", stderr);
}

test "real fullscreen CLI routes remapped viewport keys and ignores Kitty releases while accepting repeats" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    try fixture.scratch.dir.writeFile(std.testing.io, .{ .sub_path = "agent/keybindings.json", .data = "{\"tui.altScreen.top\":[\"alt+home\"],\"tui.altScreen.bottom\":[\"alt+end\"]}" });
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawn(errors);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.wait(&child, "history-row-059", 0);
    try observed.send(&child, "\x1b[1;5Htext", "> text");
    try std.testing.expect(try observed.screen.contains("history-row-059"));
    try observed.send(&child, "\x1b[57423;3:3u!", "> text!");
    try std.testing.expect(try observed.screen.contains("history-row-059"));
    try observed.send(&child, "\x1b[57423;3:2u", "history-row-000");
    try observed.send(&child, "\x1b[57424;3:3u!", "> text!!");
    try std.testing.expect(try observed.screen.contains("history-row-000"));
    try observed.send(&child, "\x1b[57424;3:2u", "history-row-059");
    try cleanExit(&fixture, &child, &observed);
}

test "real fullscreen CLI exits quietly and joins its owner after actual PTY hangup" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawn(errors);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.wait(&child, "history-row-059", 0);
    child.hangup();
    const term = try child.wait(5000);
    // The established CLI dead-terminal contract is a quiet SIGHUP-style 129.
    try std.testing.expect(term == .exited and term.exited == 129);
    const stderr = try fixture.scratch.dir.readFileAlloc(std.testing.io, "stderr.log", std.testing.allocator, .limited(65536));
    defer std.testing.allocator.free(stderr);
    try std.testing.expectEqualStrings("", stderr);
}

test "real fullscreen CLI streams intermediate cells retains scroll anchor and draft through queued settings modal" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawn(errors);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.wait(&child, "history-row-059", 0);
    try observed.send(&child, "run\r", "stream-first");
    try std.testing.expect(!try observed.screen.contains("stream-final"));
    try observed.send(&child, "draft-survives", "> draft-survives");
    try observed.send(&child, "\x1b[1;5H", "history-row-000");
    try std.testing.io.sleep(.fromMilliseconds(950), .awake);
    try observed.drain(&child);
    try std.testing.expect(try observed.screen.contains("history-row-000"));
    try std.testing.expect(try observed.screen.contains("> draft-survives"));
    try std.testing.expect(!try observed.screen.contains("stream-final"));
    try observed.send(&child, "\x1b[1;5F", "stream-final");
    try std.testing.expect(try observed.screen.contains("> draft-survives"));
    const cells = try observed.screen.textAlloc(std.testing.allocator);
    defer std.testing.allocator.free(cells);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, cells, "stream-final"));
    // Queue a command while the next provider turn is running, then leave a
    // draft in the independent editor before the main owner opens the dialog.
    try observed.send(&child, "\x15/reload\r", "Reloaded:");
    try observed.send(&child, "run-again\r", "second-first");
    const modal_start = child.output.items.len;
    try observed.send(&child, "/settings\rpreserved-modal-draft", "> preserved-modal-draft");
    _ = try child.waitFor("Settings", modal_start, 5000);
    try observed.drain(&child);
    try std.testing.expect(try observed.screen.contains("Settings"));
    try child.send("\x1b");
    try observed.wait(&child, "> preserved-modal-draft", observed.screen.frames);
    try std.testing.expect(observed.screen.in_alternate);
    try cleanExit(&fixture, &child, &observed);
}

test "explicit regular CLI retains ordinary editor behavior and does not enter persistent alternate screen" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var fixture = try Fixture.init("regular");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawn(errors);
    defer child.deinit();
    _ = try child.waitFor("> ", 0, 5000);
    try child.send("draft\x1b[HX\x1b[FY");
    _ = try child.waitFor("XdraftY", 0, 5000);
    try std.testing.expect(std.mem.indexOf(u8, child.output.items, "\x1b[?1049h") == null);
    try child.send("\x15/quit\r");
    const term = try child.wait(5000);
    try std.testing.expect(term == .exited and term.exited == 0);
    const stderr = try fixture.scratch.dir.readFileAlloc(std.testing.io, "stderr.log", std.testing.allocator, .limited(65536));
    defer std.testing.allocator.free(stderr);
    try std.testing.expectEqualStrings("", stderr);
}

test "real fullscreen Escape aborts a live turn without clearing the independent draft and next turn works" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var fixture = try Fixture.init("fullscreen");
    defer fixture.deinit();
    const errors = try fixture.scratch.dir.createFile(std.testing.io, "stderr.log", .{});
    defer errors.close(std.testing.io);
    var child = try fixture.spawn(errors);
    defer child.deinit();
    var observed = try Observer.init();
    defer observed.deinit();
    try observed.wait(&child, "history-row-059", 0);
    try observed.send(&child, "run\r", "stream-first");
    try observed.send(&child, "abort-draft", "> abort-draft");
    try child.send("\x1b");
    const end = Io.Clock.awake.now(std.testing.io).toMilliseconds() + 3000;
    var aborted = false;
    while (Io.Clock.awake.now(std.testing.io).toMilliseconds() < end) {
        const durable = try Io.Dir.cwd().readFileAlloc(std.testing.io, fixture.history, std.testing.allocator, .limited(1024 * 1024));
        defer std.testing.allocator.free(durable);
        aborted = std.mem.indexOf(u8, durable, "\"stopReason\":\"aborted\"") != null;
        if (aborted) break;
        try std.testing.io.sleep(.fromMilliseconds(10), .awake);
    }
    try std.testing.expect(aborted);
    try observed.drain(&child);
    try std.testing.expect(try observed.screen.contains("> abort-draft"));
    try observed.send(&child, "\x15again\r", "second-first");
    try observed.wait(&child, "second-final", observed.screen.frames);
    try cleanExit(&fixture, &child, &observed);
}
