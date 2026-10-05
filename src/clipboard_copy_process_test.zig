//! Real local/remote clipboard copy and extension compatibility export.
const std = @import("std");
const builtin = @import("builtin");
const pty = @import("test_support/pty.zig");
const fixture = @import("test_support/settings_fixture.zig");
const Io = std.Io;
const UserExtension =
    \\import { copyToClipboard } from '@mariozechner/pi-coding-agent';
    \\export default function(pi: any) {
    \\  pi.registerCommand('extension-copy', {
    \\    description: 'copy through compatibility export',
    \\    handler: async () => {
    \\      await copyToClipboard('extension-copy-176');
    \\      return { message: 'extension-copy-done-176' };
    \\    },
    \\  });
    \\}
;
const Report = struct { remote: bool, answer: []const u8, nativeCalls: usize = 1, nativeBytes: usize, osc52: bool, assistantOccurrences: usize = 1, exit: u8 = 0, stderrBytes: usize = 0 };
const ExtensionReport = struct { nativeCalls: usize = 1, copied: bool = true, exit: u8 = 0, stderrBytes: usize = 0 };
fn scenario(gpa: std.mem.Allocator, io: Io, binary: []const u8, helper: []const u8, remote: bool, with_extension: bool) !Report {
    var scratch = try pty.Scratch.init(gpa, io, "clipboard-copy");
    defer scratch.deinit();
    for ([_][]const u8{ "agent", "home", "work", "bin" }) |dir| try scratch.dir.createDir(io, dir, .default_dir);
    try scratch.dir.symLink(io, helper, "bin/wl-copy", .{});
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = "{\"tuiMode\":\"regular\",\"quietStartup\":true,\"enableInstallTelemetry\":false,\"collapseChangelog\":true}" });
    const answer = if (with_extension) "extension-copy-176" else if (remote) "remote-copy-answer-176" else "local-copy-answer-176";
    const mock_data = try std.fmt.allocPrint(gpa, "[{{\"content\":\"{s}\",\"tool_calls\":[]}}]", .{if (with_extension) "unused" else answer});
    defer gpa.free(mock_data);
    try scratch.dir.writeFile(io, .{ .sub_path = "mock.json", .data = mock_data });
    try scratch.dir.writeFile(io, .{ .sub_path = "copy-extension.ts", .data = UserExtension });
    const agent = try std.fs.path.join(gpa, &.{ scratch.path, "agent" });
    defer gpa.free(agent);
    const home = try std.fs.path.join(gpa, &.{ scratch.path, "home" });
    defer gpa.free(home);
    const work = try std.fs.path.join(gpa, &.{ scratch.path, "work" });
    defer gpa.free(work);
    const bin = try std.fs.path.join(gpa, &.{ scratch.path, "bin" });
    defer gpa.free(bin);
    const mock = try std.fs.path.join(gpa, &.{ scratch.path, "mock.json" });
    defer gpa.free(mock);
    const extension_path = try std.fs.path.join(gpa, &.{ scratch.path, "copy-extension.ts" });
    defer gpa.free(extension_path);
    const captured = try std.fs.path.join(gpa, &.{ scratch.path, "clipboard.txt" });
    defer gpa.free(captured);
    const calls = try std.fs.path.join(gpa, &.{ scratch.path, "calls.txt" });
    defer gpa.free(calls);
    var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environment.deinit();
    try environment.put("PI_AGENT_DIR", agent);
    try environment.put("PI_SKIP_VERSION_CHECK", "1");
    try environment.put("PI_TELEMETRY", "0");
    try environment.put("PI_COPY_E2E_OUTPUT", captured);
    try environment.put("PI_COPY_E2E_CALLS", calls);
    try environment.put("WAYLAND_DISPLAY", "wayland-176");
    try environment.put("XDG_SESSION_TYPE", "wayland");
    try environment.put("TERM", "xterm-256color");
    try environment.put("NO_COLOR", "1");
    try environment.put("HOME", home);
    const path = try std.fmt.allocPrint(gpa, "{s}:{s}", .{ bin, environment.get("PATH") orelse "/usr/bin:/bin" });
    defer gpa.free(path);
    try environment.put("PATH", path);
    for ([_][]const u8{ "SSH_CONNECTION", "SSH_CLIENT", "MOSH_CONNECTION" }) |name| _ = environment.swapRemove(name);
    if (remote) try environment.put("SSH_CONNECTION", "127.0.0.1 1 127.0.0.1 2");
    const stderr = try scratch.dir.createFile(io, "stderr.log", .{});
    defer stderr.close(io);
    const common = [_][]const u8{ binary, "--offline", "--mock-script", mock, "--no-session", "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--approve" };
    const extension_argv = common ++ [_][]const u8{ "--extension", extension_path };
    const plain_argv = common ++ [_][]const u8{"--no-extensions"};
    var session = try pty.Session.spawn(gpa, io, .{ .argv = if (with_extension) &extension_argv else &plain_argv, .cwd = .{ .path = work }, .environ_map = &environment, .stderr = .{ .file = stderr } }, 150_000);
    defer session.deinit();
    var pos = try session.waitFor("> ", 0, 30_000);
    if (with_extension) {
        try session.send("/extension-copy\r");
        pos = try session.waitFor("extension-copy-done-176", pos, 30_000);
    } else {
        try session.send("question\r");
        pos = try session.waitFor(answer, pos, 30_000);
        pos = try session.waitFor("> ", pos, 30_000);
        try session.send("/copy\r");
        pos = try session.waitFor("Copied last agent message to clipboard", pos, 30_000);
    }
    _ = try session.waitFor("> ", pos, 30_000);
    try session.send("/quit\r");
    try fixture.cleanExit(&scratch, &session, "stderr.log");
    const copied = try scratch.dir.readFileAlloc(io, "clipboard.txt", gpa, .limited(65536));
    defer gpa.free(copied);
    try std.testing.expectEqualStrings(answer, copied);
    const call_log = try scratch.dir.readFileAlloc(io, "calls.txt", gpa, .limited(65536));
    defer gpa.free(call_log);
    try std.testing.expectEqualStrings("call\n", call_log);
    if (!with_extension) {
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, session.output.items, answer));
        const encoded = try gpa.alloc(u8, std.base64.standard.Encoder.calcSize(answer.len));
        defer gpa.free(encoded);
        _ = std.base64.standard.Encoder.encode(encoded, answer);
        const osc = try std.fmt.allocPrint(gpa, "\x1b]52;c;{s}\x07", .{encoded});
        defer gpa.free(osc);
        if (remote) try std.testing.expect(std.mem.indexOf(u8, session.output.items, osc) != null) else try std.testing.expect(std.mem.indexOf(u8, session.output.items, "\x1b]52;c;") == null);
    }
    return .{ .remote = remote, .answer = answer, .nativeBytes = answer.len, .osc52 = remote };
}
test "native clipboard copies once locally and remotely without reprinting assistant output" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environment.deinit();
    const binary = try pty.executablePath(gpa, io, environment.get("PI_TEST_BINARY") orelse "zig-out/bin/pi");
    defer gpa.free(binary);
    const helper = try pty.executablePath(gpa, io, environment.get("PI_CLIPBOARD_TEST_HELPER") orelse "zig-out/bin/pi-clipboard-fixture");
    defer gpa.free(helper);
    const local = try scenario(gpa, io, binary, helper, false, false);
    const remote = try scenario(gpa, io, binary, helper, true, false);
    _ = try scenario(gpa, io, binary, helper, false, true);
    const report = try std.json.Stringify.valueAlloc(gpa, .{ .local = local, .remote = remote, .extension = ExtensionReport{} }, .{ .whitespace = .indent_2 });
    defer gpa.free(report);
    if (environment.get("PI_CLIPBOARD_COPY_REPORT")) |path| {
        const file = try Io.Dir.createFileAbsolute(io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, report);
        try file.writeStreamingAll(io, "\n");
    }
    std.debug.print("CLIPBOARD_COPY_E2E_176=PASS\n{s}\n", .{report});
}
