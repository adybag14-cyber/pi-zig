//! Actual startup/live resume isolation and task-owned package-manager updates.
const std = @import("std");
const builtin = @import("builtin");
const pty = @import("test_support/pty.zig");
const rpc = @import("test_support/rpc_process.zig");
const http = @import("test_support/http_fixture.zig");
const fixture = @import("test_support/settings_fixture.zig");
const sessions_fixture = @import("test_support/session_fixture.zig");
const Io = std.Io;
fn run(gpa: std.mem.Allocator, io: Io, scratch: *pty.Scratch, argv: []const []const u8, environment: *const std.process.Environ.Map, cwd: []const u8) ![]u8 {
    const errors_file = try scratch.dir.createFile(io, "capture.stderr", .{});
    defer errors_file.close(io);
    var child = try rpc.Process.spawn(gpa, io, .{ .argv = argv, .cwd = .{ .path = cwd }, .environ_map = environment, .stdin = .ignore, .stderr = .{ .file = errors_file } }, 90_000);
    defer child.deinit();
    const term = try child.wait(90_000);
    const errors = try scratch.dir.readFileAlloc(io, "capture.stderr", gpa, .limited(65536));
    defer gpa.free(errors);
    if (term != .exited or term.exited != 0 or errors.len != 0) {
        std.debug.print("Session/update child {any}: {s}\n{s}\n", .{ term, errors, child.output.items });
        return error.SessionUpdateChildFailed;
    }
    return gpa.dupe(u8, child.output.items);
}
fn object(gpa: std.mem.Allocator, bytes: []const u8) !std.json.Parsed(std.json.Value) {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r\t");
        if (trimmed.len > 0 and trimmed[0] == '{') return std.json.parseFromSlice(std.json.Value, gpa, trimmed, .{ .allocate = .alloc_always });
    }
    return error.UpdateJsonMissing;
}
fn contains(bytes: []const u8, wanted: []const u8) bool {
    return std.mem.indexOf(u8, bytes, wanted) != null;
}
test "native startup and live resume preserve source isolation and managed self update boundaries" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = try pty.Scratch.init(gpa, io, "session-update");
    defer scratch.deinit();
    for ([_][]const u8{ "agent", "sessions", "workspace", "home" }) |dir| try scratch.dir.createDir(io, dir, .default_dir);
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = "{\"tuiMode\":\"regular\",\"enableInstallTelemetry\":false}" });
    try scratch.dir.writeFile(io, .{ .sub_path = "mock.json", .data = "[{\"content\":\"mock-answer-170\"},{\"content\":\"second-answer-170\"}]" });
    const agent = try std.fs.path.join(gpa, &.{ scratch.path, "agent" });
    defer gpa.free(agent);
    const sessions = try std.fs.path.join(gpa, &.{ scratch.path, "sessions" });
    defer gpa.free(sessions);
    const work = try std.fs.path.join(gpa, &.{ scratch.path, "workspace" });
    defer gpa.free(work);
    const home = try std.fs.path.join(gpa, &.{ scratch.path, "home" });
    defer gpa.free(home);
    const mock = try std.fs.path.join(gpa, &.{ scratch.path, "mock.json" });
    defer gpa.free(mock);
    var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environment.deinit();
    const binary = try pty.executablePath(gpa, io, environment.get("PI_TEST_BINARY") orelse "zig-out/bin/pi");
    defer gpa.free(binary);
    const helper = try pty.executablePath(gpa, io, environment.get("PI_TOOL_TEST_HELPER") orelse "zig-out/bin/pi-tool-fixture");
    defer gpa.free(helper);
    try environment.put("PI_AGENT_DIR", agent);
    try environment.put("PI_SKIP_VERSION_CHECK", "1");
    try environment.put("PI_TELEMETRY", "0");
    try environment.put("HOME", home);
    try environment.put("TERM", "xterm-256color");
    try environment.put("NO_COLOR", "1");
    const common = [_][]const u8{ binary, "--mock-script", mock, "--session-dir", sessions, "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--no-extensions", "--no-tools", "--approve" };
    for ([_][2][]const u8{ .{ "source-170", "Source Session 170" }, .{ "target-170", "Target Session 170" } }) |item| {
        const output = try run(gpa, io, &scratch, &(common ++ [_][]const u8{ "-p", "--session-id", item[0], "--name", item[1], "seed-session" }), &environment, work);
        defer gpa.free(output);
    }
    const source = try std.fs.path.join(gpa, &.{ sessions, "source-170.jsonl" });
    defer gpa.free(source);
    const target = try std.fs.path.join(gpa, &.{ sessions, "target-170.jsonl" });
    defer gpa.free(target);
    const startup_errors = try scratch.dir.createFile(io, "startup.stderr", .{});
    defer startup_errors.close(io);
    var startup = try pty.Session.spawn(gpa, io, .{ .argv = &(common ++ [_][]const u8{"--resume"}), .cwd = .{ .path = work }, .environ_map = &environment, .stderr = .{ .file = startup_errors } }, 150_000);
    defer startup.deinit();
    var pos = try startup.waitFor("Resume Session", 0, 30_000);
    try startup.send("Target Session 170");
    pos = try startup.waitFor("Target Session 170_", pos, 30_000);
    try startup.send("\r");
    pos = try startup.waitFor("Type a prompt", pos, 30_000);
    pos = try startup.waitFor("> ", pos, 30_000);
    try startup.send("/name Startup Renamed 170\r");
    pos = try startup.waitFor("Session named.", pos, 30_000);
    _ = try startup.waitFor("> ", pos, 30_000);
    try startup.send("/quit\r");
    try fixture.cleanExit(&scratch, &startup, "startup.stderr");
    const first_source = try Io.Dir.cwd().readFileAlloc(io, source, gpa, .limited(1024 * 1024));
    defer gpa.free(first_source);
    const first_target = try Io.Dir.cwd().readFileAlloc(io, target, gpa, .limited(1024 * 1024));
    defer gpa.free(first_target);
    try std.testing.expect(!contains(first_source, "Startup Renamed 170"));
    try std.testing.expect(contains(first_target, "Startup Renamed 170"));
    const renamed_records = try sessions_fixture.load(gpa, io, target);
    defer renamed_records.deinit();
    var rename_entry = false;
    for (renamed_records.value.array.items) |record| {
        if (record != .object) continue;
        const kind = record.object.get("type") orelse continue;
        const name = record.object.get("name") orelse continue;
        if (kind == .string and name == .string and std.mem.eql(u8, kind.string, "session_info") and std.mem.eql(u8, name.string, "Startup Renamed 170")) rename_entry = true;
    }
    try std.testing.expect(rename_entry);
    const live_errors = try scratch.dir.createFile(io, "live.stderr", .{});
    defer live_errors.close(io);
    var live = try pty.Session.spawn(gpa, io, .{ .argv = &(common ++ [_][]const u8{ "--session", source }), .cwd = .{ .path = work }, .environ_map = &environment, .stderr = .{ .file = live_errors } }, 150_000);
    defer live.deinit();
    pos = try live.waitFor("Type a prompt", 0, 30_000);
    pos = try live.waitFor("> ", pos, 30_000);
    try live.send("/resume Startup Renamed 170\r");
    pos = try live.waitFor("Resume Session", pos, 30_000);
    pos = try live.waitFor("Startup Renamed 170_", pos, 30_000);
    try live.send("\r");
    pos = try live.waitFor("Resumed session target-170", pos, 30_000);
    pos = try live.waitFor("> ", pos, 30_000);
    try live.send("after-live-resume-170\r");
    pos = try live.waitFor("mock-answer-170", pos, 30_000);
    _ = try live.waitFor("> ", pos, 30_000);
    try live.send("/quit\r");
    try fixture.cleanExit(&scratch, &live, "live.stderr");
    const final_source = try Io.Dir.cwd().readFileAlloc(io, source, gpa, .limited(1024 * 1024));
    defer gpa.free(final_source);
    const final_target = try Io.Dir.cwd().readFileAlloc(io, target, gpa, .limited(1024 * 1024));
    defer gpa.free(final_target);
    try std.testing.expect(!contains(final_source, "after-live-resume-170"));
    try std.testing.expect(contains(final_target, "after-live-resume-170") and contains(final_target, "mock-answer-170"));
    const managed_relative = "prefix/lib/node_modules/@earendil-works/pi-coding-agent/bin/pi";
    try scratch.dir.createDirPath(io, "prefix/lib/node_modules/@earendil-works/pi-coding-agent/bin");
    try Io.Dir.cwd().copyFile(binary, scratch.dir, managed_relative, io, .{ .permissions = @enumFromInt(0o755) });
    const managed = try std.fs.path.join(gpa, &.{ scratch.path, managed_relative });
    defer gpa.free(managed);
    const manager_log = try std.fs.path.join(gpa, &.{ scratch.path, "manager.log" });
    defer gpa.free(manager_log);
    try environment.put("PI_MANAGER_FIXTURE_LOG", manager_log);
    const settings = try std.json.Stringify.valueAlloc(gpa, .{ .npmCommand = [_][]const u8{helper} }, .{});
    defer gpa.free(settings);
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = settings });
    const latest: http.Response = .{ .headers = "content-type: application/json\r\n", .body = "{\"version\":\"0.85.0\",\"packageName\":\"@earendil-works/pi-coding-agent-next\",\"note\":\"checkpoint-170-self-update\"}" };
    const server = try http.Server.startScripted(gpa, io, &.{ latest, latest, latest });
    defer server.deinit();
    const latest_url = try std.fmt.allocPrint(gpa, "http://127.0.0.1:{d}/latest", .{server.port});
    defer gpa.free(latest_url);
    try environment.put("PI_LATEST_VERSION_URL", latest_url);
    const check = try run(gpa, io, &scratch, &.{ managed, "update", "--self", "--check", "--json", "--approve" }, &environment, work);
    defer gpa.free(check);
    const check_json = try object(gpa, check);
    defer check_json.deinit();
    try std.testing.expectEqual(std.json.Value{ .bool = true }, check_json.value.object.get("canSelfUpdate").?);
    try std.testing.expect(contains(check_json.value.object.get("command").?.string, " && "));
    try std.testing.expectError(error.FileNotFound, scratch.dir.statFile(io, "manager.log", .{}));
    const unsafe = try run(gpa, io, &scratch, &.{ binary, "update", "--self", "--check", "--json", "--approve" }, &environment, work);
    defer gpa.free(unsafe);
    const unsafe_json = try object(gpa, unsafe);
    defer unsafe_json.deinit();
    try std.testing.expectEqual(std.json.Value{ .bool = false }, unsafe_json.value.object.get("canSelfUpdate").?);
    const update = try run(gpa, io, &scratch, &.{ managed, "update", "--self", "--force", "--json", "--approve" }, &environment, work);
    defer gpa.free(update);
    var update_lines = std.mem.splitScalar(u8, update, '\n');
    var success = false;
    while (update_lines.next()) |line| {
        if (line.len == 0 or line[0] != '{') continue;
        const value = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer value.deinit();
        if (value.value != .object) continue;
        const target_value = value.value.object.get("target") orelse continue;
        if (target_value == .string and std.mem.eql(u8, target_value.string, "self")) {
            const status = value.value.object.get("success") orelse continue;
            if (status == .bool and status.bool) success = true;
        }
    }
    try std.testing.expect(success);
    const logged = try scratch.dir.readFileAlloc(io, "manager.log", gpa, .limited(65536));
    defer gpa.free(logged);
    var manager_lines = std.mem.tokenizeScalar(u8, logged, '\n');
    const uninstall = manager_lines.next() orelse return error.ManagerUninstallMissing;
    const install = manager_lines.next() orelse return error.ManagerInstallMissing;
    try std.testing.expect(manager_lines.next() == null);
    try std.testing.expect(contains(uninstall, "uninstall -g @earendil-works/pi-coding-agent"));
    try std.testing.expect(contains(install, "install -g --ignore-scripts --min-release-age=0 @earendil-works/pi-coding-agent-next@0.85.0"));
    try server.finish();
    const requests = try server.snapshotRequests(gpa);
    defer http.freeRequests(gpa, requests);
    try std.testing.expectEqual(@as(usize, 3), requests.len);
    for (requests) |request| try std.testing.expectEqualStrings("/latest", request.path);
    const report = "{\"startupResume\":true,\"startupRenamePersistence\":true,\"liveResume\":true,\"sourceTargetIsolation\":true,\"selfUpdateCheckPlan\":true,\"unsafeSourceRejected\":true,\"selfUpdateMigration\":true,\"latestRequests\":3,\"managerSteps\":2,\"stderrBytes\":0}\n";
    if (environment.get("PI_SESSION_UPDATE_REPORT")) |path| {
        const file = try Io.Dir.createFileAbsolute(io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, report);
    }
    std.debug.print("SESSION_UPDATE_E2E_188=PASS\n{s}", .{report});
}
