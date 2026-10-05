//! Real RPC-created history and PTY tree edits, including remote OSC 52 copy.
const std = @import("std");
const builtin = @import("builtin");
const pty = @import("test_support/pty.zig");
const rpc = @import("test_support/rpc_process.zig");
const events = @import("test_support/rpc_events.zig");
const fixture = @import("test_support/settings_fixture.zig");
const Io = std.Io;

fn messageMatches(value: std.json.Value, wanted: []const u8) bool {
    if (value != .object) return false;
    const content = value.object.get("content") orelse return false;
    if (content == .string) return std.mem.eql(u8, content.string, wanted);
    if (content != .array) return false;
    var offset: usize = 0;
    for (content.array.items) |block| {
        if (block != .object) continue;
        const kind = block.object.get("type") orelse continue;
        if (kind != .string or !std.mem.eql(u8, kind.string, "text")) continue;
        const text = block.object.get("text") orelse return false;
        if (text != .string or !std.mem.startsWith(u8, wanted[offset..], text.string)) return false;
        offset += text.string.len;
    }
    return offset == wanted.len;
}

test "native tree controls preserve durable selected labels and OSC 52 clipboard payload" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = try pty.Scratch.init(gpa, io, "tree-controls");
    defer scratch.deinit();
    for ([_][]const u8{ "agent", "sessions", "home" }) |dir| try scratch.dir.createDir(io, dir, .default_dir);
    try scratch.dir.writeFile(io, .{ .sub_path = "mock.json", .data = "[{\"content\":\"tree-answer-168-1\",\"stream_chunks\":[\"tree-answer-\",\"168-1\"]},{\"content\":\"tree-answer-168-2\"},{\"content\":\"tree-answer-168-3\"}]" });
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = "{\"retry\":{\"enabled\":false},\"enableInstallTelemetry\":false}" });
    const agent = try std.fs.path.join(gpa, &.{ scratch.path, "agent" });
    defer gpa.free(agent);
    const sessions = try std.fs.path.join(gpa, &.{ scratch.path, "sessions" });
    defer gpa.free(sessions);
    const mock = try std.fs.path.join(gpa, &.{ scratch.path, "mock.json" });
    defer gpa.free(mock);
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
    // OSC 52 is the remote fallback. Desktop clipboard availability must not
    // make this fixture dependent on the machine's installed clipboard tools.
    try environment.put("SSH_CONNECTION", "192.0.2.1 1234 192.0.2.2 22");
    const common = [_][]const u8{ binary, "--mock-script", mock, "--session-dir", sessions, "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--no-tools", "--approve" };
    const rpc_errors = try scratch.dir.createFile(io, "rpc.stderr", .{});
    defer rpc_errors.close(io);
    var child = try rpc.Process.spawn(gpa, io, .{ .argv = &(common ++ [_][]const u8{ "--mode", "rpc" }), .cwd = .{ .path = scratch.path }, .environ_map = &environment, .stdin = .pipe, .stderr = .{ .file = rpc_errors } }, 150_000);
    defer child.deinit();
    for (1..4) |index| {
        const command = try std.fmt.allocPrint(gpa, "{{\"id\":\"p{d}\",\"type\":\"prompt\",\"message\":\"tree-user-168-{d}\"}}\n", .{ index, index });
        defer gpa.free(command);
        const id = try std.fmt.allocPrint(gpa, "p{d}", .{index});
        defer gpa.free(id);
        try child.send(command);
        const ack = try events.response(gpa, &child, id);
        ack.deinit();
        const ended = try events.event(gpa, &child, "agent_end", null);
        ended.deinit();
    }
    try child.send("{\"id\":\"state\",\"type\":\"get_state\"}\n");
    const state = try events.response(gpa, &child, "state");
    defer state.deinit();
    const session_file = state.value.object.get("data").?.object.get("sessionFile").?.string;
    try child.send("{\"id\":\"quit\",\"type\":\"quit\"}\n");
    const quit = try events.response(gpa, &child, "quit");
    quit.deinit();
    child.closeInput();
    const term = try child.wait(20_000);
    try std.testing.expect(term == .exited and term.exited == 0);
    const rpc_stderr = try scratch.dir.readFileAlloc(io, "rpc.stderr", gpa, .limited(65536));
    defer gpa.free(rpc_stderr);
    try std.testing.expectEqualStrings("", rpc_stderr);
    const pty_errors = try scratch.dir.createFile(io, "pty.stderr", .{});
    defer pty_errors.close(io);
    var session = try pty.Session.spawn(gpa, io, .{ .argv = &(common ++ [_][]const u8{ "--session", session_file }), .cwd = .{ .path = scratch.path }, .environ_map = &environment, .stderr = .{ .file = pty_errors } }, 150_000);
    defer session.deinit();
    var pos = try session.waitFor("> ", 0, 30_000);
    try session.send("/tree\r");
    pos = try session.waitFor("Session Tree", pos, 30_000);
    try session.send("tree-answer-168-1");
    pos = try session.waitFor("tree-answer-168-1_", pos, 30_000);
    try io.sleep(.fromMilliseconds(200), .awake);
    try session.drain();
    try session.send("\x1b[108;2u");
    pos = try session.waitFor("Editing label", pos, 30_000);
    try session.send("checkpoint-168\r");
    pos = try session.waitFor("Label saved", pos, 30_000);
    try session.send("\x18");
    pos = try session.waitFor("copied to clipboard", pos, 30_000);
    try session.send("\x1b[116;2u");
    pos = try session.waitFor("Label timestamps shown", pos, 30_000);
    try session.send("\x0c");
    pos = try session.waitFor("Filter: ", pos, 30_000);
    pos = try session.waitFor("labeled", pos, 30_000);
    try session.send("\x1b");
    pos = try session.waitFor("Search cleared", pos, 30_000);
    try session.send("\x1b");
    _ = try session.waitFor("> ", pos, 30_000);
    try session.send("/quit\r");
    try fixture.cleanExit(&scratch, &session, "pty.stderr");
    const prefix = "\x1b]52;c;";
    const start = std.mem.lastIndexOf(u8, session.output.items, prefix) orelse return error.TreeClipboardMissing;
    const payload_start = start + prefix.len;
    const end = std.mem.indexOfScalarPos(u8, session.output.items, payload_start, 7) orelse return error.TreeClipboardTerminatorMissing;
    const payload = session.output.items[payload_start..end];
    const decoded = try gpa.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(payload));
    defer gpa.free(decoded);
    try std.base64.standard.Decoder.decode(decoded, payload);
    try std.testing.expectEqualStrings("tree-answer-168-1", decoded);
    try std.testing.expect(std.mem.indexOf(u8, session.output.items, "\x1b[?1049h") != null);
    try std.testing.expect(std.mem.indexOf(u8, session.output.items, "\x1b[?1049l") != null);
    const durable = try Io.Dir.cwd().readFileAlloc(io, session_file, gpa, .limited(1024 * 1024));
    defer gpa.free(durable);
    var lines = std.mem.splitScalar(u8, durable, '\n');
    var labels: usize = 0;
    var target: ?[]u8 = null;
    defer if (target) |v| gpa.free(v);
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const record = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer record.deinit();
        if (record.value != .object) continue;
        const kind = record.value.object.get("type") orelse continue;
        if (kind != .string or !std.mem.eql(u8, kind.string, "label")) continue;
        const label = record.value.object.get("label") orelse continue;
        if (label != .string or !std.mem.eql(u8, label.string, "checkpoint-168")) continue;
        labels += 1;
        const id = record.value.object.get("targetId") orelse record.value.object.get("target_id") orelse return error.TreeLabelTargetMissing;
        try std.testing.expect(id == .string and id.string.len > 0);
        if (target) |v| gpa.free(v);
        target = try gpa.dupe(u8, id.string);
    }
    try std.testing.expectEqual(@as(usize, 1), labels);
    var matched: bool = false;
    lines.reset();
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const record = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer record.deinit();
        if (record.value != .object) continue;
        const id = record.value.object.get("id") orelse continue;
        if (id != .string or !std.mem.eql(u8, id.string, target.?)) continue;
        const message = record.value.object.get("message") orelse continue;
        if (message != .object) continue;
        const role = message.object.get("role") orelse continue;
        if (role == .string and std.mem.eql(u8, role.string, "assistant") and messageMatches(message, "tree-answer-168-1")) matched = true;
    }
    try std.testing.expect(matched);
    const report = try std.json.Stringify.valueAlloc(gpa, .{ .rpcExit = 0, .ptyExit = 0, .fullscreenTreeSelector = true, .searchSelected = "tree-answer-168-1", .durableLabel = "checkpoint-168", .labelTarget = target.?, .osc52Payload = decoded, .labelTimestamps = true, .labeledOnlyFilter = true, .stderrBytes = 0 }, .{ .whitespace = .indent_2 });
    defer gpa.free(report);
    if (environment.get("PI_TREE_CONTROLS_REPORT")) |path| {
        const file = try Io.Dir.createFileAbsolute(io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, report);
        try file.writeStreamingAll(io, "\n");
    }
    std.debug.print("TREE_CONTROLS_E2E_168=PASS\n{s}\n", .{report});
}
