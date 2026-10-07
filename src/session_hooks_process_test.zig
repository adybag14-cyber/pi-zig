//! Real session-hook replacement, cancellation actions and tree persistence.
const std = @import("std");
const builtin = @import("builtin");
const pty = @import("test_support/pty.zig");
const rpc = @import("test_support/rpc_process.zig");
const events = @import("test_support/rpc_events.zig");
const json = @import("test_support/json_fixture.zig");
const sessions = @import("test_support/session_fixture.zig");
const fixture = @import("test_support/settings_fixture.zig");
const extension = @import("test_support/session_hooks_extension_fixture.zig");
const Io = std.Io;
fn request(gpa: std.mem.Allocator, child: *rpc.Process, command: []const u8, id: []const u8) !std.json.Parsed(std.json.Value) {
    try child.send(command);
    return events.response(gpa, child, id);
}
fn entries(value: std.json.Value) ![]const std.json.Value {
    return (try json.field(try json.field(value, "data"), "entries")).array.items;
}
fn validate(items: []const std.json.Value, tree: bool) !std.json.Value {
    const kind = if (tree) "branch_summary" else "compaction";
    var found: ?std.json.Value = null;
    for (items) |item| if (json.kind(item, kind)) {
        try std.testing.expect(found == null);
        found = item;
    };
    const result = found orelse return error.HookBoundaryMissing;
    try json.text(try json.field(result, "summary"), if (tree) "extension tree summary 164" else "extension compact summary 164");
    try std.testing.expectEqual(std.json.Value{ .bool = true }, try json.field(result, "fromHook"));
    try json.text(try json.field(try json.field(result, "details"), "source"), if (tree) "tree-extension-164" else "extension-164");
    const usage = try json.field(result, "usage");
    try std.testing.expectEqual(std.json.Value{ .integer = if (tree) 21 else 11 }, try json.field(usage, "input"));
    try std.testing.expectEqual(std.json.Value{ .integer = if (tree) 22 else 12 }, try json.field(usage, "output"));
    try std.testing.expectEqual(std.json.Value{ .integer = if (tree) 90 else 50 }, try json.field(usage, "totalTokens"));
    if (!tree) {
        const cost = try json.field(try json.field(usage, "cost"), "total");
        const actual: f64 = if (cost == .float) cost.float else @floatFromInt(cost.integer);
        try std.testing.expectApproxEqAbs(@as(f64, 0.5), actual, 1e-9);
    }
    if (tree) {
        var labelled = false;
        for (items) |item| if (json.kind(item, "label")) {
            const label = try json.field(item, "label");
            const target_id = try json.field(item, "targetId");
            const summary_id = try json.field(result, "id");
            if (label == .string and target_id == .string and summary_id == .string and std.mem.eql(u8, label.string, "tree-label-164") and std.mem.eql(u8, target_id.string, summary_id.string)) labelled = true;
        };
        try std.testing.expect(labelled);
    }
    return result;
}

test "native session replacement cancels before teardown then retires old context before new start" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = try pty.Scratch.init(gpa, io, "session-context-lifetime");
    defer scratch.deinit();
    for ([_][]const u8{ "agent", "sessions" }) |dir| try scratch.dir.createDir(io, dir, .default_dir);
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = "{\"enableInstallTelemetry\":false}" });
    try scratch.dir.writeFile(io, .{ .sub_path = "mock.json", .data = "[]" });
    try scratch.dir.writeFile(io, .{ .sub_path = "lifetime.js", .data =
        \\export default pi => {
        \\  let old, starts=0, decisions=0, shutdowns=0;
        \\  pi.on('session_start', (_event,ctx) => {
        \\    starts++;
        \\    if (old) {
        \\      let message='';try { old.ui.getEditorText(); } catch(error) { message=error.message; }
        \\      if (!message.includes('This extension ctx is stale')) throw Error('old ctx was usable');
        \\      if(shutdowns!==1) throw Error('shutdown did not settle');
        \\      pi.setSessionName('replacement-context-qualified');
        \\    }
        \\    old=ctx;
        \\  });
        \\  pi.on('session_before_switch', (_event,ctx) => {
        \\    old.ui.getEditorText();ctx.ui.getEditorText();
        \\    decisions++;return {cancel:decisions===1};
        \\  });
        \\  pi.on('session_shutdown', async () => {old.ui.getEditorText();await Promise.resolve();shutdowns++;});
        \\};
    });
    var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environment.deinit();
    const binary = try pty.executablePath(gpa, io, environment.get("PI_TEST_BINARY") orelse "zig-out/bin/pi");
    defer gpa.free(binary);
    const agent_dir = try std.fs.path.join(gpa, &.{ scratch.path, "agent" });
    defer gpa.free(agent_dir);
    const session_dir = try std.fs.path.join(gpa, &.{ scratch.path, "sessions" });
    defer gpa.free(session_dir);
    const extension_path = try std.fs.path.join(gpa, &.{ scratch.path, "lifetime.js" });
    defer gpa.free(extension_path);
    const mock = try std.fs.path.join(gpa, &.{ scratch.path, "mock.json" });
    defer gpa.free(mock);
    try environment.put("PI_AGENT_DIR", agent_dir);
    try environment.put("PI_EXTENSION_BACKEND", "native");
    try environment.put("PI_SKIP_VERSION_CHECK", "1");
    try environment.put("PI_TELEMETRY", "0");
    const stderr = try scratch.dir.createFile(io, "rpc.stderr", .{});
    defer stderr.close(io);
    var child = try rpc.Process.spawn(gpa, io, .{ .argv = &.{ binary, "--offline", "--mock-script", mock, "--extension", extension_path, "--session-dir", session_dir, "--mode", "rpc", "--no-context-files", "--no-skills", "--approve" }, .cwd = .{ .path = scratch.path }, .environ_map = &environment, .stdin = .pipe, .stderr = .{ .file = stderr } }, 60_000);
    defer child.deinit();
    var cancelled = try request(gpa, &child, "{\"id\":\"cancel\",\"type\":\"new_session\"}\n", "cancel");
    defer cancelled.deinit();
    try std.testing.expect((try json.field(try json.field(cancelled.value, "data"), "cancelled")).bool);
    var replaced = try request(gpa, &child, "{\"id\":\"replace\",\"type\":\"new_session\"}\n", "replace");
    defer replaced.deinit();
    try std.testing.expect(!(try json.field(try json.field(replaced.value, "data"), "cancelled")).bool);
    var state = try request(gpa, &child, "{\"id\":\"state\",\"type\":\"get_state\"}\n", "state");
    defer state.deinit();
    try json.text(try json.field(try json.field(state.value, "data"), "sessionName"), "replacement-context-qualified");
    var quit = try request(gpa, &child, "{\"id\":\"quit\",\"type\":\"quit\"}\n", "quit");
    quit.deinit();
    child.closeInput();
    const term = try child.wait(10_000);
    try std.testing.expect(term == .exited and term.exited == 0);
    const errors = try scratch.dir.readFileAlloc(io, "rpc.stderr", gpa, .limited(65536));
    defer gpa.free(errors);
    try std.testing.expectEqualStrings("", errors);
}
test "native session hooks preserve replacement usage immediate cancel actions and tree lifecycle" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = try pty.Scratch.init(gpa, io, "session-hooks");
    defer scratch.deinit();
    for ([_][]const u8{ "agent", "sessions", "home" }) |dir| try scratch.dir.createDir(io, dir, .default_dir);
    // A small explicit recent-token budget makes the tiny fixture compactable;
    // the production default20000 budget retains the entire short history.
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = "{\"tuiMode\":\"regular\",\"compaction\":{\"enabled\":true,\"reserveTokens\":123,\"keepRecentTokens\":20},\"enableInstallTelemetry\":false}" });
    try scratch.dir.writeFile(io, .{ .sub_path = "hooks.ts", .data = extension.source });
    try scratch.dir.writeFile(io, .{ .sub_path = "mock.json", .data = "[{\"content\":\"assistant-response-1\"},{\"content\":\"assistant-response-2\"},{\"content\":\"assistant-response-3\"},{\"content\":\"assistant-response-4\"},{\"content\":\"assistant-response-5\"},{\"content\":\"assistant-response-6\"},{\"content\":\"assistant-response-7\"},{\"content\":\"assistant-response-8\"},{\"content\":\"assistant-response-9\"}]" });
    const agent = try std.fs.path.join(gpa, &.{ scratch.path, "agent" });
    defer gpa.free(agent);
    const session_dir = try std.fs.path.join(gpa, &.{ scratch.path, "sessions" });
    defer gpa.free(session_dir);
    const extension_path = try std.fs.path.join(gpa, &.{ scratch.path, "hooks.ts" });
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
    const common = [_][]const u8{ binary, "--offline", "--mock-script", mock, "--extension", extension_path, "--session-dir", session_dir, "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--approve" };
    const stderr = try scratch.dir.createFile(io, "rpc.stderr", .{});
    defer stderr.close(io);
    var child = try rpc.Process.spawn(gpa, io, .{ .argv = &(common ++ [_][]const u8{ "--mode", "rpc" }), .cwd = .{ .path = scratch.path }, .environ_map = &environment, .stdin = .pipe, .stderr = .{ .file = stderr } }, 150_000);
    defer child.deinit();
    for (1..5) |index| {
        const command = try std.fmt.allocPrint(gpa, "{{\"id\":\"p{d}\",\"type\":\"prompt\",\"message\":\"user-message-{d}\"}}\n", .{ index, index });
        defer gpa.free(command);
        const id = try std.fmt.allocPrint(gpa, "p{d}", .{index});
        defer gpa.free(id);
        const ack = try request(gpa, &child, command, id);
        ack.deinit();
        const ended = try events.event(gpa, &child, "agent_end", null);
        defer ended.deinit();
        const encoded = try std.json.Stringify.valueAlloc(gpa, ended.value, .{});
        defer gpa.free(encoded);
        const marker = try std.fmt.allocPrint(gpa, "assistant-response-{d}", .{index});
        defer gpa.free(marker);
        try std.testing.expect(std.mem.indexOf(u8, encoded, marker) != null);
    }
    const before = try request(gpa, &child, "{\"id\":\"before\",\"type\":\"get_entries\"}\n", "before");
    defer before.deinit();
    const before_entries = try entries(before.value);
    try std.testing.expect(before_entries.len >= 8);
    var target: ?[]const u8 = null;
    for (before_entries) |item| {
        if (!json.kind(item, "message")) continue;
        const message = try json.field(item, "message");
        const role = try json.field(message, "role");
        if (role == .string and std.mem.eql(u8, role.string, "assistant")) {
            target = (try json.field(item, "id")).string;
            break;
        }
    }
    try std.testing.expect(target != null and target.?.len > 0);
    const compact = try request(gpa, &child, "{\"id\":\"compact\",\"type\":\"compact\",\"customInstructions\":\"focus-164\"}\n", "compact");
    defer compact.deinit();
    const compact_data = try json.field(compact.value, "data");
    try json.text(try json.field(compact_data, "summary"), "extension compact summary 164");
    try json.text(try json.field(try json.field(compact_data, "details"), "source"), "extension-164");
    const compact_state = try request(gpa, &child, "{\"id\":\"compact-state\",\"type\":\"get_state\"}\n", "compact-state");
    defer compact_state.deinit();
    const state_data = try json.field(compact_state.value, "data");
    try json.text(try json.field(state_data, "sessionName"), "compact-hooked-164");
    const session_file = (try json.field(state_data, "sessionFile")).string;
    const after = try request(gpa, &child, "{\"id\":\"after\",\"type\":\"get_entries\"}\n", "after");
    defer after.deinit();
    const after_entries = try entries(after.value);
    try std.testing.expect(sessions.countCustom(after_entries, "after-compact-164") > 0);
    _ = try validate(after_entries, false);
    try child.send("{\"id\":\"cancel\",\"type\":\"compact\",\"customInstructions\":\"cancel-164\"}\n");
    const cancel = try events.event(gpa, &child, "response", "cancel");
    defer cancel.deinit();
    try std.testing.expectEqual(std.json.Value{ .bool = false }, try json.field(cancel.value, "success"));
    try json.text(try json.field(try json.field(cancel.value, "data"), "error"), "Compaction cancelled");
    const cancel_state = try request(gpa, &child, "{\"id\":\"cancel-state\",\"type\":\"get_state\"}\n", "cancel-state");
    defer cancel_state.deinit();
    try json.text(try json.field(try json.field(cancel_state.value, "data"), "sessionName"), "cancel-hooked-164");
    const cancel_entries = try request(gpa, &child, "{\"id\":\"cancel-entries\",\"type\":\"get_entries\"}\n", "cancel-entries");
    defer cancel_entries.deinit();
    const cancelled_items = try entries(cancel_entries.value);
    try std.testing.expect(sessions.countCustom(cancelled_items, "cancel-compact-164") > 0);
    _ = try validate(cancelled_items, false);
    const quit = try request(gpa, &child, "{\"id\":\"quit\",\"type\":\"quit\"}\n", "quit");
    quit.deinit();
    child.closeInput();
    const term = try child.wait(20_000);
    try std.testing.expect(term == .exited and term.exited == 0);
    const errors = try scratch.dir.readFileAlloc(io, "rpc.stderr", gpa, .limited(65536));
    defer gpa.free(errors);
    try std.testing.expectEqualStrings("", errors);
    const first_records = try sessions.load(gpa, io, session_file);
    defer first_records.deinit();
    _ = try validate(first_records.value.array.items, false);
    try std.testing.expectEqualStrings("cancel-hooked-164", sessions.lastName(first_records.value.array.items).?);
    const interactive_stderr = try scratch.dir.createFile(io, "pty.stderr", .{});
    defer interactive_stderr.close(io);
    var interactive = try pty.Session.spawn(gpa, io, .{ .argv = &(common ++ [_][]const u8{ "--session", session_file }), .cwd = .{ .path = scratch.path }, .environ_map = &environment, .stderr = .{ .file = interactive_stderr } }, 90_000);
    defer interactive.deinit();
    var pos = try interactive.waitFor("> ", 0, 30_000);
    const tree_command = try std.fmt.allocPrint(gpa, "/tree {s} --summary tree-focus-164\r", .{target.?});
    defer gpa.free(tree_command);
    try interactive.send(tree_command);
    pos = try interactive.waitFor("Summarized", pos, 30_000);
    _ = try interactive.waitFor("> ", pos, 30_000);
    try interactive.send("/quit\r");
    try fixture.cleanExit(&scratch, &interactive, "pty.stderr");
    const final_records = try sessions.load(gpa, io, session_file);
    defer final_records.deinit();
    const records = final_records.value.array.items;
    const boundary = try validate(records, false);
    const tree = try validate(records, true);
    for ([_][]const u8{ "after-compact-164", "cancel-compact-164", "after-tree-164" }) |name| try std.testing.expectEqual(@as(usize, 1), sessions.countCustom(records, name));
    try std.testing.expectEqualStrings("tree-hooked-164", sessions.lastName(records).?);
    const report = try std.json.Stringify.valueAlloc(gpa, .{ .rpcPrompts = 4, .rpcCompactReplacement = true, .rpcCompactSummary = (try json.field(boundary, "summary")).string, .rpcCompactFromHook = true, .rpcAfterHookActionsImmediate = true, .rpcCancellation = true, .rpcCancellationActionsImmediate = true, .durableCompactionUsageTotal = 50, .treeTargetId = target.?, .treeSummary = (try json.field(tree, "summary")).string, .treeFromHook = true, .treeLabel = "tree-label-164", .durableTreeUsageTotal = 90, .finalSessionName = sessions.lastName(records).?, .rpcExit = 0, .interactiveExit = 0, .stderrBytes = 0, .finalJsonlRecords = records.len }, .{ .whitespace = .indent_2 });
    defer gpa.free(report);
    if (environment.get("PI_SESSION_HOOKS_REPORT")) |path| {
        const file = try Io.Dir.createFileAbsolute(io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, report);
        try file.writeStreamingAll(io, "\n");
    }
    std.debug.print("SESSION_HOOKS_E2E_164=PASS\n{s}\n", .{report});
}
