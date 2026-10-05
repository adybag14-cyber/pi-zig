//! Real compaction hooks, persistent policy, append-only history and projection.
const std = @import("std");
const builtin = @import("builtin");
const pty = @import("test_support/pty.zig");
const rpc = @import("test_support/rpc_process.zig");
const events = @import("test_support/rpc_events.zig");
const extension = @import("test_support/compaction_extension_fixture.zig");
const Io = std.Io;
const json = @import("test_support/json_fixture.zig");
const field = json.field;
const text = json.text;
const kind = json.kind;
fn countKind(items: []const std.json.Value, name: []const u8) usize {
    var count: usize = 0;
    for (items) |item| if (kind(item, name)) {
        count += 1;
    };
    return count;
}
fn request(gpa: std.mem.Allocator, child: *rpc.Process, command: []const u8, id: []const u8) !std.json.Parsed(std.json.Value) {
    try child.send(command);
    return events.response(gpa, child, id);
}
fn settingsCheck(gpa: std.mem.Allocator, io: Io, scratch: *pty.Scratch, enabled: bool) !void {
    const bytes = try scratch.dir.readFileAlloc(io, "agent/settings.json", gpa, .limited(65536));
    defer gpa.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, bytes, .{});
    defer parsed.deinit();
    const policy = try field(parsed.value, "compaction");
    try std.testing.expectEqual(std.json.Value{ .bool = enabled }, try field(policy, "enabled"));
    try std.testing.expectEqual(std.json.Value{ .integer = 123 }, try field(policy, "reserveTokens"));
    try std.testing.expectEqual(std.json.Value{ .integer = 20 }, try field(policy, "keepRecentTokens"));
    try text(try field(parsed.value, "theme"), "night");
}
test "native compaction fixture retains token policy hook actions and append-only history" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = try pty.Scratch.init(gpa, io, "compaction-policy");
    defer scratch.deinit();
    for ([_][]const u8{ "agent", "sessions", "home" }) |dir| try scratch.dir.createDir(io, dir, .default_dir);
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = "{\"theme\":\"night\",\"compaction\":{\"enabled\":true,\"reserveTokens\":123,\"keepRecentTokens\":20},\"enableInstallTelemetry\":false}" });
    try scratch.dir.writeFile(io, .{ .sub_path = "policy.ts", .data = extension.source });
    const answers = [_]u8{'A'} ** 120 ++ [_]u8{'B'} ** 120 ++ [_]u8{'C'} ** 120;
    const mock_data = try std.fmt.allocPrint(gpa, "[{{\"content\":\"{s}\"}},{{\"content\":\"{s}\"}},{{\"content\":\"{s}\"}}]", .{ answers[0..120], answers[120..240], answers[240..360] });
    defer gpa.free(mock_data);
    try scratch.dir.writeFile(io, .{ .sub_path = "mock.json", .data = mock_data });
    const agent = try std.fs.path.join(gpa, &.{ scratch.path, "agent" });
    defer gpa.free(agent);
    const sessions = try std.fs.path.join(gpa, &.{ scratch.path, "sessions" });
    defer gpa.free(sessions);
    const extension_path = try std.fs.path.join(gpa, &.{ scratch.path, "policy.ts" });
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
    try environment.put("NO_COLOR", "1");
    try environment.put("TERM", "xterm-256color");
    try environment.put("PI_SKIP_VERSION_CHECK", "1");
    try environment.put("PI_TELEMETRY", "0");
    const errors_file = try scratch.dir.createFile(io, "stderr.log", .{});
    defer errors_file.close(io);
    var child = try rpc.Process.spawn(gpa, io, .{ .argv = &.{ binary, "--offline", "--mock-script", mock, "--extension", extension_path, "--session-dir", sessions, "--mode", "rpc", "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--approve" }, .cwd = .{ .path = scratch.path }, .environ_map = &environment, .stdin = .pipe, .stderr = .{ .file = errors_file } }, 150_000);
    defer child.deinit();
    const initial = try request(gpa, &child, "{\"id\":\"initial\",\"type\":\"get_state\"}\n", "initial");
    defer initial.deinit();
    try std.testing.expectEqual(std.json.Value{ .bool = true }, try field(try field(initial.value, "data"), "autoCompactionEnabled"));
    const disabled = try request(gpa, &child, "{\"id\":\"disable\",\"type\":\"set_auto_compaction\",\"enabled\":false}\n", "disable");
    disabled.deinit();
    try settingsCheck(gpa, io, &scratch, false);
    const enabled = try request(gpa, &child, "{\"id\":\"enable\",\"type\":\"set_auto_compaction\",\"enabled\":true}\n", "enable");
    enabled.deinit();
    try settingsCheck(gpa, io, &scratch, true);
    for (1..4) |index| {
        const command = try std.fmt.allocPrint(gpa, "{{\"id\":\"p{d}\",\"type\":\"prompt\",\"message\":\"user-{d}\"}}\n", .{ index, index });
        defer gpa.free(command);
        const id = try std.fmt.allocPrint(gpa, "p{d}", .{index});
        defer gpa.free(id);
        const ack = try request(gpa, &child, command, id);
        ack.deinit();
        const end = try events.event(gpa, &child, "agent_end", null);
        defer end.deinit();
        const encoded = try std.json.Stringify.valueAlloc(gpa, end.value, .{});
        defer gpa.free(encoded);
        try std.testing.expect(std.mem.indexOf(u8, encoded, answers[(index - 1) * 120 .. (index - 1) * 120 + 40]) != null);
    }
    const before = try request(gpa, &child, "{\"id\":\"before\",\"type\":\"get_entries\"}\n", "before");
    defer before.deinit();
    const before_entries = try field(try field(before.value, "data"), "entries");
    try std.testing.expectEqual(@as(usize, 6), countKind(before_entries.array.items, "message"));
    const compact = try request(gpa, &child, "{\"id\":\"compact\",\"type\":\"compact\",\"customInstructions\":\"policy-165\"}\n", "compact");
    defer compact.deinit();
    const compact_data = try field(compact.value, "data");
    try text(try field(compact_data, "summary"), "token budget summary 165");
    const details = try field(compact_data, "details");
    try std.testing.expectEqual(std.json.Value{ .bool = true }, try field(details, "splitTurn"));
    try std.testing.expectEqual(std.json.Value{ .integer = 4 }, try field(details, "summarizedMessages"));
    try std.testing.expectEqual(std.json.Value{ .integer = 1 }, try field(details, "prefixMessages"));
    const after = try request(gpa, &child, "{\"id\":\"entries\",\"type\":\"get_entries\"}\n", "entries");
    defer after.deinit();
    const after_entries = (try field(try field(after.value, "data"), "entries")).array.items;
    try std.testing.expectEqual(@as(usize, 6), countKind(after_entries, "message"));
    try std.testing.expectEqual(@as(usize, 1), countKind(after_entries, "compaction"));
    var first_kept: ?[]const u8 = null;
    var before_actions: usize = 0;
    var after_actions: usize = 0;
    for (after_entries) |entry| {
        if (kind(entry, "compaction")) {
            try std.testing.expectEqual(std.json.Value{ .bool = true }, try field(entry, "fromHook"));
            first_kept = (try field(entry, "firstKeptEntryId")).string;
        }
        if (kind(entry, "custom")) {
            const name = try field(entry, "customType");
            if (std.mem.eql(u8, name.string, "policy-before-165")) before_actions += 1;
            if (std.mem.eql(u8, name.string, "policy-after-165")) after_actions += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), before_actions);
    try std.testing.expectEqual(@as(usize, 1), after_actions);
    try std.testing.expect(first_kept != null);
    var found_kept = false;
    for (after_entries) |entry| {
        const id = entry.object.get("id") orelse continue;
        if (id == .string and std.mem.eql(u8, id.string, first_kept.?)) {
            try text(try field(try field(entry, "message"), "role"), "assistant");
            found_kept = true;
        }
    }
    try std.testing.expect(found_kept);
    const messages = try request(gpa, &child, "{\"id\":\"messages\",\"type\":\"get_messages\"}\n", "messages");
    defer messages.deinit();
    const active = try field(try field(messages.value, "data"), "messages");
    try std.testing.expect(active.array.items.len > 0);
    try text(try field(active.array.items[0], "role"), "compactionSummary");
    try text(try field(active.array.items[0], "summary"), "token budget summary 165");
    const active_bytes = try std.json.Stringify.valueAlloc(gpa, active, .{});
    defer gpa.free(active_bytes);
    try std.testing.expect(std.mem.indexOf(u8, active_bytes, "user-1") == null and std.mem.indexOf(u8, active_bytes, "user-2") == null and std.mem.indexOf(u8, active_bytes, answers[240..280]) != null);
    const final = try request(gpa, &child, "{\"id\":\"final\",\"type\":\"get_state\"}\n", "final");
    defer final.deinit();
    const final_data = try field(final.value, "data");
    try std.testing.expectEqual(std.json.Value{ .bool = true }, try field(final_data, "autoCompactionEnabled"));
    try text(try field(final_data, "sessionName"), "token-budget-165");
    const session_file = try field(final_data, "sessionFile");
    const quit = try request(gpa, &child, "{\"id\":\"quit\",\"type\":\"quit\"}\n", "quit");
    quit.deinit();
    child.closeInput();
    const term = try child.wait(20_000);
    try std.testing.expect(term == .exited and term.exited == 0);
    const errors = try scratch.dir.readFileAlloc(io, "stderr.log", gpa, .limited(65536));
    defer gpa.free(errors);
    try std.testing.expectEqualStrings("", errors);
    const durable = try Io.Dir.cwd().readFileAlloc(io, session_file.string, gpa, .limited(1024 * 1024));
    defer gpa.free(durable);
    var lines = std.mem.splitScalar(u8, durable, '\n');
    var durable_messages: usize = 0;
    var durable_compactions: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const record = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer record.deinit();
        if (kind(record.value, "message")) durable_messages += 1;
        if (kind(record.value, "compaction")) durable_compactions += 1;
    }
    try std.testing.expectEqual(@as(usize, 6), durable_messages);
    try std.testing.expectEqual(@as(usize, 1), durable_compactions);
    const report = "{\"directRootPolicy\":\"token-budget\",\"reserveTokens\":123,\"keepRecentTokens\":20,\"settingsPersistence\":true,\"unrelatedSettingsPreserved\":true,\"splitTurn\":true,\"messagesToSummarize\":4,\"turnPrefixMessages\":1,\"durableMessagesBefore\":6,\"durableMessagesAfter\":6,\"firstKeptRole\":\"assistant\",\"activeContextStartsWith\":\"compactionSummary\",\"oldHistoryExcludedFromActiveContext\":true,\"beforeHookActionImmediate\":true,\"afterHookActionImmediate\":true,\"processExit\":0,\"stderrBytes\":0}\n";
    if (environment.get("PI_COMPACTION_POLICY_REPORT")) |path| {
        const file = try Io.Dir.createFileAbsolute(io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, report);
    }
    std.debug.print("COMPACTION_POLICY_E2E_165=PASS\n{s}", .{report});
}
