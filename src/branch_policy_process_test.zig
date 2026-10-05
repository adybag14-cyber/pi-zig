//! Real custom branch summary and skip-prompt policy over RPC-created history.
const std = @import("std");
const builtin = @import("builtin");
const pty = @import("test_support/pty.zig");
const rpc = @import("test_support/rpc_process.zig");
const events = @import("test_support/rpc_events.zig");
const json = @import("test_support/json_fixture.zig");
const fixture = @import("test_support/settings_fixture.zig");
const extension = @import("test_support/branch_extension_fixture.zig");
const Io = std.Io;
fn request(gpa: std.mem.Allocator, child: *rpc.Process, command: []const u8, id: []const u8) !std.json.Parsed(std.json.Value) {
    try child.send(command);
    return events.response(gpa, child, id);
}
fn inspectSettings(session: *pty.Session, skip: bool) !usize {
    var pos = try session.waitFor("> ", 0, 30_000);
    try session.send("/settings\r");
    pos = try session.waitFor("Settings", pos, 30_000);
    pos = try session.waitFor("mouse wheel/click supported", pos, 30_000);
    const output = session.output.items;
    const footer = std.mem.lastIndexOf(u8, output[0..pos], " settings") orelse return error.BranchSettingsFooterMissing;
    var count_start = footer;
    while (count_start > 0 and std.ascii.isDigit(output[count_start - 1])) count_start -= 1;
    try std.testing.expect(count_start < footer and count_start > 0 and output[count_start - 1] == '/');
    const total = try std.fmt.parseInt(usize, output[count_start..footer], 10);
    const unfiltered = try std.fmt.allocPrint(session.gpa, "/{d} settings", .{total});
    defer session.gpa.free(unfiltered);
    if (!skip) {
        try session.send("Branch-summary reserve");
        pos = try session.waitFor("Branch-summary reserve_", pos, 30_000);
        pos = try session.waitFor("77", pos, 30_000);
        try session.send("\x1b");
        pos = try session.waitFor(unfiltered, pos, 30_000);
    }
    try session.send("Skip branch-summary prompt");
    pos = try session.waitFor("Skip branch-summary prompt_", pos, 30_000);
    pos = try session.waitFor(if (skip) "true" else "false", pos, 30_000);
    try session.send("\x1b");
    pos = try session.waitFor(unfiltered, pos, 30_000);
    try session.send("\x1b");
    return session.waitFor("> ", pos, 30_000);
}
fn settings(scratch: *pty.Scratch, skip: bool) !void {
    const data = try std.fmt.allocPrint(scratch.gpa, "{{\"tuiMode\":\"regular\",\"theme\":\"night\",\"branchSummary\":{{\"reserveTokens\":77,\"skipPrompt\":{s}}},\"enableInstallTelemetry\":false}}", .{if (skip) "true" else "false"});
    defer scratch.gpa.free(data);
    try scratch.dir.writeFile(scratch.io, .{ .sub_path = "agent/settings.json", .data = data });
}
test "native branch policy preserves custom summary usage labels and skip-prompt actions" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = try pty.Scratch.init(gpa, io, "branch-policy");
    defer scratch.deinit();
    for ([_][]const u8{ "agent", "sessions", "home" }) |dir| try scratch.dir.createDir(io, dir, .default_dir);
    try settings(&scratch, false);
    try scratch.dir.writeFile(io, .{ .sub_path = "branch-policy.ts", .data = extension.source });
    try scratch.dir.writeFile(io, .{ .sub_path = "mock.json", .data = "[{\"content\":\"assistant-166-1\"},{\"content\":\"assistant-166-2\"},{\"content\":\"assistant-166-3\"},{\"content\":\"assistant-166-4\"},{\"content\":\"assistant-166-5\"},{\"content\":\"assistant-166-6\"},{\"content\":\"assistant-166-7\"},{\"content\":\"assistant-166-8\"}]" });
    const agent = try std.fs.path.join(gpa, &.{ scratch.path, "agent" });
    defer gpa.free(agent);
    const sessions = try std.fs.path.join(gpa, &.{ scratch.path, "sessions" });
    defer gpa.free(sessions);
    const extension_path = try std.fs.path.join(gpa, &.{ scratch.path, "branch-policy.ts" });
    defer gpa.free(extension_path);
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
    const common = [_][]const u8{ binary, "--offline", "--mock-script", mock, "--extension", extension_path, "--session-dir", sessions, "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--approve" };
    const rpc_errors = try scratch.dir.createFile(io, "rpc.stderr", .{});
    defer rpc_errors.close(io);
    var child = try rpc.Process.spawn(gpa, io, .{ .argv = &(common ++ [_][]const u8{ "--mode", "rpc" }), .cwd = .{ .path = scratch.path }, .environ_map = &environment, .stdin = .pipe, .stderr = .{ .file = rpc_errors } }, 150_000);
    defer child.deinit();
    for (1..5) |index| {
        const command = try std.fmt.allocPrint(gpa, "{{\"id\":\"p{d}\",\"type\":\"prompt\",\"message\":\"user-166-{d}\"}}\n", .{ index, index });
        defer gpa.free(command);
        const id = try std.fmt.allocPrint(gpa, "p{d}", .{index});
        defer gpa.free(id);
        const ack = try request(gpa, &child, command, id);
        ack.deinit();
        const ended = try events.event(gpa, &child, "agent_end", null);
        ended.deinit();
    }
    const entries = try request(gpa, &child, "{\"id\":\"entries\",\"type\":\"get_entries\"}\n", "entries");
    defer entries.deinit();
    const items = (try json.field(try json.field(entries.value, "data"), "entries")).array.items;
    var target: ?[]const u8 = null;
    var old_leaf: ?[]const u8 = null;
    var assistants: usize = 0;
    for (items) |item| {
        if (!json.kind(item, "message")) continue;
        const message = try json.field(item, "message");
        const role = try json.field(message, "role");
        if (role == .string and std.mem.eql(u8, role.string, "assistant")) {
            const id = (try json.field(item, "id")).string;
            if (target == null) target = id;
            old_leaf = id;
            assistants += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 4), assistants);
    const state = try request(gpa, &child, "{\"id\":\"state\",\"type\":\"get_state\"}\n", "state");
    defer state.deinit();
    const session_file = (try json.field(try json.field(state.value, "data"), "sessionFile")).string;
    const quit = try request(gpa, &child, "{\"id\":\"quit\",\"type\":\"quit\"}\n", "quit");
    quit.deinit();
    child.closeInput();
    const term = try child.wait(20_000);
    try std.testing.expect(term == .exited and term.exited == 0);
    const errors = try scratch.dir.readFileAlloc(io, "rpc.stderr", gpa, .limited(65536));
    defer gpa.free(errors);
    try std.testing.expectEqualStrings("", errors);
    const interactive = common ++ [_][]const u8{ "--session", session_file };
    const first_errors = try scratch.dir.createFile(io, "first.stderr", .{});
    defer first_errors.close(io);
    var first = try pty.Session.spawn(gpa, io, .{ .argv = &interactive, .cwd = .{ .path = scratch.path }, .environ_map = &environment, .stderr = .{ .file = first_errors } }, 150_000);
    defer first.deinit();
    var pos = try inspectSettings(&first, false);
    const tree_command = try std.fmt.allocPrint(gpa, "/tree {s}\r", .{target.?});
    defer gpa.free(tree_command);
    try first.send(tree_command);
    pos = try first.waitFor("Summarize branch?", pos, 30_000);
    pos = try first.waitFor("Choice [n]: ", pos, 30_000);
    try first.send("c\r");
    pos = try first.waitFor("Custom summarization instructions: ", pos, 30_000);
    try first.send("focus-166\r");
    pos = try first.waitFor("Summarized", pos, 30_000);
    _ = try first.waitFor("> ", pos, 30_000);
    try first.send("/quit\r");
    try fixture.cleanExit(&scratch, &first, "first.stderr");
    const first_durable = try Io.Dir.cwd().readFileAlloc(io, session_file, gpa, .limited(1024 * 1024));
    defer gpa.free(first_durable);
    var lines = std.mem.splitScalar(u8, first_durable, '\n');
    var summary_id: ?[]u8 = null;
    defer if (summary_id) |id| gpa.free(id);
    var summaries: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const record = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer record.deinit();
        if (!json.kind(record.value, "branch_summary")) continue;
        summaries += 1;
        try json.text(try json.field(record.value, "summary"), "extension branch summary 166");
        try std.testing.expectEqual(std.json.Value{ .bool = true }, try json.field(record.value, "fromHook"));
        try json.text(try json.field(try json.field(record.value, "details"), "instructions"), "focus-166");
        try std.testing.expectEqual(std.json.Value{ .integer = 130 }, try json.field(try json.field(record.value, "usage"), "totalTokens"));
        summary_id = try gpa.dupe(u8, (try json.field(record.value, "id")).string);
    }
    try std.testing.expectEqual(@as(usize, 1), summaries);
    lines.reset();
    var label_matched = false;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const record = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer record.deinit();
        if (!json.kind(record.value, "label")) continue;
        const id = try json.field(record.value, "targetId");
        const label = try json.field(record.value, "label");
        if (id == .string and label == .string and std.mem.eql(u8, id.string, summary_id.?) and std.mem.eql(u8, label.string, "branch-label-166")) label_matched = true;
    }
    try std.testing.expect(label_matched);
    try settings(&scratch, true);
    const second_errors = try scratch.dir.createFile(io, "second.stderr", .{});
    defer second_errors.close(io);
    var second = try pty.Session.spawn(gpa, io, .{ .argv = &interactive, .cwd = .{ .path = scratch.path }, .environ_map = &environment, .stderr = .{ .file = second_errors } }, 150_000);
    defer second.deinit();
    pos = try inspectSettings(&second, true);
    const command_start = second.output.items.len;
    const old_command = try std.fmt.allocPrint(gpa, "/tree {s}\r", .{old_leaf.?});
    defer gpa.free(old_command);
    try second.send(old_command);
    pos = try second.waitFor("Tip set to", pos, 30_000);
    _ = try second.waitFor("> ", pos, 30_000);
    try second.send("/quit\r");
    try fixture.cleanExit(&scratch, &second, "second.stderr");
    const tail = second.output.items[command_start..];
    try std.testing.expect(std.mem.indexOf(u8, tail, "Summarize branch?") == null and std.mem.indexOf(u8, tail, "Choice [n]:") == null);
    const final_durable = try Io.Dir.cwd().readFileAlloc(io, session_file, gpa, .limited(1024 * 1024));
    defer gpa.free(final_durable);
    lines = std.mem.splitScalar(u8, final_durable, '\n');
    summaries = 0;
    var after_actions: usize = 0;
    var skip_action = false;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const record = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer record.deinit();
        if (json.kind(record.value, "branch_summary")) summaries += 1;
        if (json.kind(record.value, "custom")) {
            const name = try json.field(record.value, "customType");
            if (std.mem.eql(u8, name.string, "skip-prompt-tree-166")) skip_action = true;
            if (std.mem.eql(u8, name.string, "after-tree-166")) after_actions += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), summaries);
    try std.testing.expect(skip_action);
    try std.testing.expectEqual(@as(usize, 2), after_actions);
    const report = "{\"rpcPrompts\":4,\"reserveTokens\":77,\"interactivePrompt\":true,\"customPrompt\":\"focus-166\",\"summaryFromHook\":true,\"summaryUsageTotal\":130,\"summaryLabel\":\"branch-label-166\",\"skipPrompt\":true,\"skipPromptDialogSuppressed\":true,\"summaryCountAfterSkip\":1,\"rpcExit\":0,\"firstInteractiveExit\":0,\"secondInteractiveExit\":0,\"stderrBytes\":0}\n";
    if (environment.get("PI_BRANCH_POLICY_REPORT")) |path| {
        const file = try Io.Dir.createFileAbsolute(io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, report);
    }
    std.debug.print("BRANCH_SUMMARY_POLICY_E2E_166=PASS\n{s}", .{report});
}
