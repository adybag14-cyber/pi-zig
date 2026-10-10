//! Model selector lifecycle and real managed-tool download/cache boundaries.
const std = @import("std");
const builtin = @import("builtin");
const pty = @import("test_support/pty.zig");
const rpc = @import("test_support/rpc_process.zig");
const http = @import("test_support/http_fixture.zig");
const fixture = @import("test_support/settings_fixture.zig");
const sessions = @import("test_support/session_fixture.zig");
const json = @import("test_support/json_fixture.zig");
const Io = std.Io;
const Plan = struct {
    archive: []const u8,
    fn reply(raw: ?*anyopaque, request: http.Request, _: []u8) !http.Response {
        const self: *Plan = @ptrCast(@alignCast(raw.?));
        if (std.mem.eql(u8, request.path, "/latest")) return .{ .headers = "content-type: application/json\r\n", .body = "{\"version\":\"0.85.0\",\"packageName\":\"@earendil-works/pi-coding-agent\",\"note\":\"checkpoint-188-update-note\"}" };
        if (std.mem.startsWith(u8, request.path, "/report?")) return .{ .status = 204, .body = "" };
        if (std.mem.eql(u8, request.path, "/rg-release")) return .{ .headers = "content-type: application/json\r\n", .body = "{\"tag_name\":\"v14.1.1\"}" };
        if (std.mem.eql(u8, request.path, "/rg-download")) return .{ .headers = "content-type: application/gzip\r\n", .body = self.archive };
        return error.UnexpectedModelUpdatePath;
    }
};
fn contains(bytes: []const u8, marker: []const u8) bool {
    return std.mem.indexOf(u8, bytes, marker) != null;
}
fn captured(gpa: std.mem.Allocator, io: Io, scratch: *pty.Scratch, argv: []const []const u8, env: *const std.process.Environ.Map, cwd: []const u8) ![]u8 {
    const errors_file = try scratch.dir.createFile(io, "capture.stderr", .{});
    defer errors_file.close(io);
    var child = try rpc.Process.spawn(gpa, io, .{ .argv = argv, .cwd = .{ .path = cwd }, .environ_map = env, .stdin = .ignore, .stderr = .{ .file = errors_file } }, 60_000);
    defer child.deinit();
    const term = try child.wait(60_000);
    const errors = try scratch.dir.readFileAlloc(io, "capture.stderr", gpa, .limited(65536));
    defer gpa.free(errors);
    if (term != .exited or term.exited != 0 or errors.len != 0) {
        std.debug.print("Managedtool child {any}: {s}\n{s}\n", .{ term, errors, child.output.items });
        return error.ManagedToolChildFailed;
    }
    return gpa.dupe(u8, child.output.items);
}
test "native model update lifecycle retains durable selection and installs a native managed tool only once" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = try pty.Scratch.init(gpa, io, "model-update");
    defer scratch.deinit();
    for ([_][]const u8{ "agent", "sessions", "home", "workspace", "tool-path" }) |dir| try scratch.dir.createDir(io, dir, .default_dir);
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = "{\"tuiMode\":\"regular\",\"lastChangelogVersion\":\"0.84.0\",\"collapseChangelog\":true,\"enableInstallTelemetry\":true,\"retry\":{\"enabled\":false}}" });
    try scratch.dir.writeFile(io, .{ .sub_path = "mock.json", .data = "[{\"content\":\"unused-188\"}]" });
    const agent = try std.fs.path.join(gpa, &.{ scratch.path, "agent" });
    defer gpa.free(agent);
    const session_dir = try std.fs.path.join(gpa, &.{ scratch.path, "sessions" });
    defer gpa.free(session_dir);
    const home = try std.fs.path.join(gpa, &.{ scratch.path, "home" });
    defer gpa.free(home);
    const work = try std.fs.path.join(gpa, &.{ scratch.path, "workspace" });
    defer gpa.free(work);
    const mock = try std.fs.path.join(gpa, &.{ scratch.path, "mock.json" });
    defer gpa.free(mock);
    var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environment.deinit();
    const binary = try pty.executablePath(gpa, io, environment.get("PI_TEST_BINARY") orelse "zig-out/bin/pi");
    defer gpa.free(binary);
    const helper = try pty.executablePath(gpa, io, environment.get("PI_TOOL_TEST_HELPER") orelse "zig-out/bin/pi-tool-fixture");
    defer gpa.free(helper);
    const archive_root = "ripgrep-14.1.1-x86_64-unknown-linux-musl";
    try scratch.dir.createDir(io, archive_root, .default_dir);
    try Io.Dir.cwd().copyFile(helper, scratch.dir, archive_root ++ "/rg", io, .{ .permissions = @enumFromInt(0o755) });
    const archive_path = try std.fs.path.join(gpa, &.{ scratch.path, "rg.tar.gz" });
    defer gpa.free(archive_path);
    const archived = try std.process.run(gpa, io, .{ .argv = &.{ "/usr/bin/tar", "-czf", archive_path, "-C", scratch.path, archive_root }, .stdout_limit = .limited(8192), .stderr_limit = .limited(8192), .timeout = .{ .duration = .{ .raw = .fromSeconds(30), .clock = .real } } });
    defer gpa.free(archived.stdout);
    defer gpa.free(archived.stderr);
    try std.testing.expect(archived.term == .exited and archived.term.exited == 0 and archived.stderr.len == 0);
    const archive = try scratch.dir.readFileAlloc(io, "rg.tar.gz", gpa, .limited(16 * 1024 * 1024));
    defer gpa.free(archive);
    var plan: Plan = .{ .archive = archive };
    const server = try http.Server.start(gpa, io, &plan, Plan.reply);
    defer server.deinit();
    const latest = try std.fmt.allocPrint(gpa, "http://127.0.0.1:{d}/latest", .{server.port});
    defer gpa.free(latest);
    const report_url = try std.fmt.allocPrint(gpa, "http://127.0.0.1:{d}/report", .{server.port});
    defer gpa.free(report_url);
    try environment.put("PI_AGENT_DIR", agent);
    try environment.put("HOME", home);
    try environment.put("PI_LATEST_VERSION_URL", latest);
    try environment.put("PI_REPORT_INSTALL_URL", report_url);
    try environment.put("OPENAI_API_KEY", "checkpoint-188-test-key");
    try environment.put("TERM", "xterm-256color");
    try environment.put("NO_COLOR", "1");
    _ = environment.swapRemove("PI_SKIP_VERSION_CHECK");
    _ = environment.swapRemove("PI_TELEMETRY");
    const errors_file = try scratch.dir.createFile(io, "pty.stderr", .{});
    defer errors_file.close(io);
    var session = try pty.Session.spawn(gpa, io, .{ .argv = &.{ binary, "--mock-script", mock, "--session-dir", session_dir, "--session-id", "model-188", "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--no-tools", "--approve" }, .cwd = .{ .path = work }, .environ_map = &environment, .stderr = .{ .file = errors_file } }, 120_000);
    defer session.deinit();
    var pos = try session.waitFor("Type a prompt", 0, 30_000);
    pos = try session.waitFor("> ", pos, 30_000);
    try session.send("/model openai/gpt-4.1-mini\r");
    pos = try session.waitFor("Select Model", pos, 30_000);
    pos = try session.waitFor("openai/gpt-4.1-mini", pos, 30_000);
    try session.send("\r");
    pos = try session.waitFor("Model switched to openai/gpt-4.1-mini.", pos, 30_000);
    _ = try session.waitFor("> ", pos, 30_000);
    // Observe the actual detached telemetry request instead of sleeping a
    // guessed amount and assuming the request has arrived.
    const report_deadline = Io.Clock.awake.now(io).toMilliseconds() + 5000;
    var reported = false;
    while (Io.Clock.awake.now(io).toMilliseconds() < report_deadline) {
        const observed = try server.snapshotRequests(gpa);
        defer http.freeRequests(gpa, observed);
        for (observed) |request| if (std.mem.startsWith(u8, request.path, "/report?")) {
            reported = true;
        };
        if (reported) break;
        try io.sleep(.fromMilliseconds(10), .awake);
    }
    try std.testing.expect(reported);
    try session.send("/quit\r");
    try fixture.cleanExit(&scratch, &session, "pty.stderr");
    try std.testing.expect(contains(session.output.items, "Updated to upstream Pi v0.84.4"));
    try std.testing.expect(contains(session.output.items, "Upstream Pi update available: v0.85.0"));
    try std.testing.expect(contains(session.output.items, "checkpoint-188-update-note"));
    const settings_bytes = try scratch.dir.readFileAlloc(io, "agent/settings.json", gpa, .limited(65536));
    defer gpa.free(settings_bytes);
    const settings = try std.json.parseFromSlice(std.json.Value, gpa, settings_bytes, .{});
    defer settings.deinit();
    try json.text(try json.field(settings.value, "lastChangelogVersion"), "0.84.4");
    try std.testing.expectEqual(std.json.Value{ .bool = true }, try json.field(settings.value, "collapseChangelog"));
    const session_path = try std.fs.path.join(gpa, &.{ session_dir, "model-188.jsonl" });
    defer gpa.free(session_path);
    const records = try sessions.load(gpa, io, session_path);
    defer records.deinit();
    var changes: usize = 0;
    for (records.value.array.items) |record| if (json.kind(record, "model_change")) {
        changes += 1;
        try json.text(try json.field(record, "provider"), "openai");
        try json.text(try json.field(record, "modelId"), "gpt-4.1-mini");
    };
    try std.testing.expectEqual(@as(usize, 1), changes);
    try scratch.dir.symLink(io, "/usr/bin/tar", "tool-path/tar", .{});
    try scratch.dir.symLink(io, "/usr/bin/gzip", "tool-path/gzip", .{});
    const tool_path = try std.fs.path.join(gpa, &.{ scratch.path, "tool-path" });
    defer gpa.free(tool_path);
    try environment.put("PATH", tool_path);
    try environment.put("PI_SKIP_VERSION_CHECK", "1");
    try environment.put("PI_TELEMETRY", "0");
    const release = try std.fmt.allocPrint(gpa, "http://127.0.0.1:{d}/rg-release", .{server.port});
    defer gpa.free(release);
    const download = try std.fmt.allocPrint(gpa, "http://127.0.0.1:{d}/rg-download", .{server.port});
    defer gpa.free(download);
    try environment.put("PI_TOOL_RG_RELEASE_URL", release);
    try environment.put("PI_TOOL_RG_DOWNLOAD_URL", download);
    try scratch.dir.writeFile(io, .{ .sub_path = "workspace/fixture.txt", .data = "needle-188\n" });
    try scratch.dir.writeFile(io, .{ .sub_path = "managed-rg-mock.json", .data = "[{\"content\":\"running managed grep\",\"tool_calls\":[{\"id\":\"managed-rg-call-188\",\"name\":\"grep\",\"arguments\":\"{\\\"pattern\\\":\\\"needle-188\\\",\\\"path\\\":\\\".\\\"}\"}]},{\"content\":\"managed-tool-complete-188\",\"tool_calls\":[]}]" });
    const tool_mock = try std.fs.path.join(gpa, &.{ scratch.path, "managed-rg-mock.json" });
    defer gpa.free(tool_mock);
    const argv = [_][]const u8{ binary, "-p", "--mode", "json", "--mock-script", tool_mock, "--session-dir", session_dir, "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--no-extensions", "--tools", "grep", "--approve", "exercise managed grep" };
    for (0..2) |_| {
        const output = try captured(gpa, io, &scratch, &argv, &environment, work);
        defer gpa.free(output);
        try std.testing.expect(contains(output, "managed-rg-188:"));
        try std.testing.expect(contains(output, "managed-tool-complete-188"));
        const installed = try scratch.dir.statFile(io, "agent/bin/rg", .{});
        try std.testing.expect(installed.kind == .file and @intFromEnum(installed.permissions) & 0o111 != 0);
        const observed = try server.snapshotRequests(gpa);
        defer http.freeRequests(gpa, observed);
        var releases: usize = 0;
        var downloads: usize = 0;
        for (observed) |request| {
            if (std.mem.eql(u8, request.path, "/rg-release")) releases += 1;
            if (std.mem.eql(u8, request.path, "/rg-download")) downloads += 1;
        }
        try std.testing.expectEqual(@as(usize, 1), releases);
        try std.testing.expectEqual(@as(usize, 1), downloads);
    }
    try server.finish();
    const requests = try server.snapshotRequests(gpa);
    defer http.freeRequests(gpa, requests);
    var latest_count: usize = 0;
    var report_count: usize = 0;
    for (requests) |request| {
        if (std.mem.eql(u8, request.path, "/latest")) latest_count += 1;
        if (std.mem.startsWith(u8, request.path, "/report?")) {
            report_count += 1;
            try std.testing.expect(contains(request.path, "version=0.84.4"));
        }
    }
    try std.testing.expectEqual(@as(usize, 1), latest_count);
    try std.testing.expectEqual(@as(usize, 1), report_count);
    const report = "{\"exit\":0,\"latestRequests\":1,\"reportRequests\":1,\"lifecycleVersion\":\"0.84.4\",\"fullscreenModelSelector\":true,\"selectedModel\":\"openai/gpt-4.1-mini\",\"modelChangeEntries\":1,\"managedRgReleaseRequests\":1,\"managedRgDownloadRequests\":1,\"managedRgPath\":\"agent/bin/rg\",\"stderrBytes\":0}\n";
    if (environment.get("PI_MODEL_UPDATE_REPORT")) |path| {
        const file = try Io.Dir.createFileAbsolute(io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, report);
    }
    std.debug.print("MODEL_UPDATE_E2E_188=PASS\n{s}", .{report});
}
