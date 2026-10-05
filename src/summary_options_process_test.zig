//! Summary transport options verified through actual HTTP, RPC and tree PTY.
const std = @import("std");
const builtin = @import("builtin");
const pty = @import("test_support/pty.zig");
const rpc = @import("test_support/rpc_process.zig");
const events = @import("test_support/rpc_events.zig");
const http = @import("test_support/http_fixture.zig");
const fixture = @import("test_support/settings_fixture.zig");
const Io = std.Io;

const Plan = struct {
    count: usize = 0,
    fn reply(raw: ?*anyopaque, request: http.Request, buffer: []u8) !http.Response {
        const self: *Plan = @ptrCast(@alignCast(raw.?));
        if (!std.mem.eql(u8, request.method, "POST")) return error.UnexpectedSummaryMethod;
        const body = try std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, request.body, .{});
        defer body.deinit();
        self.count += 1;
        if (body.value.object.get("stream")) |stream| if (stream == .bool and stream.bool) return .{ .headers = "content-type: text/event-stream\r\n", .body = try std.fmt.bufPrint(buffer, "data: {{\"id\":\"chatcmpl-167-{d}\",\"choices\":[{{\"delta\":{{\"content\":\"assistant-188-{d}\"}}}}]}}\n\n" ++
            "data: {{\"choices\":[{{\"delta\":{{}},\"finish_reason\":\"stop\"}}],\"usage\":{{\"prompt_tokens\":4,\"completion_tokens\":2,\"total_tokens\":6}}}}\n\n" ++
            "data: [DONE]\n\n", .{ self.count, self.count }) };
        return .{ .headers = "content-type: application/json\r\n", .body = "{\"id\":\"chatcmpl-summary-167\",\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"summary-cap-167\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":9,\"completion_tokens\":3,\"total_tokens\":12}}" };
    }
};

test "native branch summaries bound output and omit normal session affinity and cache options" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var plan: Plan = .{};
    const server = try http.Server.start(gpa, io, &plan, Plan.reply);
    defer server.deinit();
    var scratch = try pty.Scratch.init(gpa, io, "summary-options");
    defer scratch.deinit();
    for ([_][]const u8{ "agent", "sessions", "home" }) |dir| try scratch.dir.createDir(io, dir, .default_dir);
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/settings.json", .data = "{\"tuiMode\":\"regular\",\"retry\":{\"enabled\":false,\"provider\":{\"maxRetries\":0}},\"branchSummary\":{\"reserveTokens\":64,\"skipPrompt\":false},\"enableInstallTelemetry\":false}" });
    const model = try std.fmt.allocPrint(gpa, "{{\"providers\":{{\"summary167\":{{\"baseUrl\":\"http://127.0.0.1:{d}/v1\",\"api\":\"openai-completions\",\"apiKey\":\"$SUMMARY167_KEY\",\"compat\":{{\"sendSessionAffinityHeaders\":true,\"sessionAffinityFormat\":\"openai\",\"supportsLongCacheRetention\":true}},\"models\":[{{\"id\":\"fast\",\"contextWindow\":128000,\"maxTokens\":4096}}]}}}}}}", .{server.port});
    defer gpa.free(model);
    try scratch.dir.writeFile(io, .{ .sub_path = "agent/models.json", .data = model });
    const agent = try std.fs.path.join(gpa, &.{ scratch.path, "agent" });
    defer gpa.free(agent);
    const sessions = try std.fs.path.join(gpa, &.{ scratch.path, "sessions" });
    defer gpa.free(sessions);
    const home = try std.fs.path.join(gpa, &.{ scratch.path, "home" });
    defer gpa.free(home);
    var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environment.deinit();
    const binary = try pty.executablePath(gpa, io, environment.get("PI_TEST_BINARY") orelse "zig-out/bin/pi");
    defer gpa.free(binary);
    try environment.put("PI_AGENT_DIR", agent);
    try environment.put("HOME", home);
    try environment.put("PI_CACHE_RETENTION", "long");
    try environment.put("SUMMARY167_KEY", "summary-key-167");
    try environment.put("TERM", "xterm-256color");
    try environment.put("NO_COLOR", "1");
    try environment.put("PI_SKIP_VERSION_CHECK", "1");
    try environment.put("PI_TELEMETRY", "0");
    const common = [_][]const u8{ binary, "--provider", "summary167", "--model", "fast", "--session-dir", sessions, "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-themes", "--no-tools", "--approve" };
    const rpc_errors = try scratch.dir.createFile(io, "rpc.stderr", .{});
    defer rpc_errors.close(io);
    var child = try rpc.Process.spawn(gpa, io, .{ .argv = &(common ++ [_][]const u8{ "--mode", "rpc" }), .cwd = .{ .path = scratch.path }, .environ_map = &environment, .stdin = .pipe, .stderr = .{ .file = rpc_errors } }, 150_000);
    defer child.deinit();
    for (1..4) |index| {
        const command = try std.fmt.allocPrint(gpa, "{{\"id\":\"p{d}\",\"type\":\"prompt\",\"message\":\"user-summary-167-{d}\"}}\n", .{ index, index });
        defer gpa.free(command);
        const id = try std.fmt.allocPrint(gpa, "p{d}", .{index});
        defer gpa.free(id);
        try child.send(command);
        const ack = try events.response(gpa, &child, id);
        ack.deinit();
        const ended = try events.event(gpa, &child, "agent_end", null);
        ended.deinit();
    }
    try child.send("{\"id\":\"entries\",\"type\":\"get_entries\"}\n");
    const entries = try events.response(gpa, &child, "entries");
    defer entries.deinit();
    var assistants: usize = 0;
    for (entries.value.object.get("data").?.object.get("entries").?.array.items) |entry| {
        const message = entry.object.get("message") orelse continue;
        const role = message.object.get("role") orelse continue;
        if (role == .string and std.mem.eql(u8, role.string, "assistant")) assistants += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), assistants);
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
    const errors = try scratch.dir.readFileAlloc(io, "rpc.stderr", gpa, .limited(65536));
    defer gpa.free(errors);
    try std.testing.expectEqualStrings("", errors);
    const pty_errors = try scratch.dir.createFile(io, "pty.stderr", .{});
    defer pty_errors.close(io);
    var session = try pty.Session.spawn(gpa, io, .{ .argv = &(common ++ [_][]const u8{ "--session", session_file }), .cwd = .{ .path = scratch.path }, .environ_map = &environment, .stderr = .{ .file = pty_errors } }, 150_000);
    defer session.deinit();
    var pos = try session.waitFor("> ", 0, 30_000);
    try session.send("/tree\r");
    pos = try session.waitFor("Session Tree", pos, 30_000);
    try session.send("assistant-188-1");
    pos = try session.waitFor("assistant-188-1_", pos, 30_000);
    pos = try session.waitFor("1/1 entries", pos, 30_000);
    try session.send("\r");
    pos = try session.waitFor("Summarize branch?", pos, 30_000);
    pos = try session.waitFor("Choice [n]: ", pos, 30_000);
    try session.send("s\r");
    pos = try session.waitFor("Summarized", pos, 30_000);
    _ = try session.waitFor("> ", pos, 30_000);
    try session.send("/quit\r");
    try fixture.cleanExit(&scratch, &session, "pty.stderr");
    try server.finish();
    const requests = try server.snapshotRequests(gpa);
    defer http.freeRequests(gpa, requests);
    try std.testing.expectEqual(@as(usize, 4), requests.len);
    const affinity = [_][]const u8{ "session-id", "session_id", "x-client-request-id", "x-session-id" };
    var normal_affinity: std.ArrayList([]const u8) = .empty;
    defer normal_affinity.deinit(gpa);
    for (affinity) |name| if (requests[0].header(name) != null) try normal_affinity.append(gpa, name);
    try std.testing.expect(normal_affinity.items.len > 0);
    for (requests[0..3]) |request| {
        const body = try std.json.parseFromSlice(std.json.Value, gpa, request.body, .{});
        defer body.deinit();
        try std.testing.expectEqual(std.json.Value{ .bool = true }, body.value.object.get("stream").?);
    }
    const summary = try std.json.parseFromSlice(std.json.Value, gpa, requests[3].body, .{});
    defer summary.deinit();
    if (summary.value.object.get("stream")) |stream| try std.testing.expectEqual(std.json.Value{ .bool = false }, stream);
    const cap = summary.value.object.get("max_completion_tokens") orelse summary.value.object.get("max_tokens") orelse return error.SummaryOutputCapMissing;
    try std.testing.expectEqual(std.json.Value{ .integer = 2048 }, cap);
    for (affinity) |name| try std.testing.expect(requests[3].header(name) == null);
    try std.testing.expect(!summary.value.object.contains("prompt_cache_key"));
    try std.testing.expect(!summary.value.object.contains("prompt_cache_retention"));
    const durable = try Io.Dir.cwd().readFileAlloc(io, session_file, gpa, .limited(1024 * 1024));
    defer gpa.free(durable);
    var lines = std.mem.splitScalar(u8, durable, '\n');
    var summaries: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const record = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
        defer record.deinit();
        const kind = record.value.object.get("type") orelse continue;
        if (kind != .string or !std.mem.eql(u8, kind.string, "branch_summary")) continue;
        summaries += 1;
        const content = record.value.object.get("summary").?;
        try std.testing.expect(content == .string and std.mem.endsWith(u8, content.string, "summary-cap-167"));
    }
    try std.testing.expectEqual(@as(usize, 1), summaries);
    const report = try std.json.Stringify.valueAlloc(gpa, .{ .normalRequests = 3, .summaryRequests = 1, .summaryMaxTokens = cap.integer, .normalAffinityHeaders = normal_affinity.items, .summaryAffinityHeaders = [_][]const u8{}, .summaryPromptCacheKey = @as(?bool, null), .summaryPromptCacheRetention = @as(?bool, null), .fullscreenTreeSelector = true, .searchSelected = "assistant-188-1", .summaryPersisted = true, .rpcExit = 0, .ptyExit = 0, .stderrBytes = 0 }, .{ .whitespace = .indent_2 });
    defer gpa.free(report);
    if (environment.get("PI_SUMMARY_OPTIONS_REPORT")) |path| {
        const file = try Io.Dir.createFileAbsolute(io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, report);
        try file.writeStreamingAll(io, "\n");
    }
    std.debug.print("SUMMARY_REQUEST_OPTIONS_E2E_188=PASS\n{s}\n", .{report});
}
