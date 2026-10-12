//! Actual CLI regressions for Pi 19cb534 text print truncation behavior.
const std = @import("std");
const Io = std.Io;

test "print mode final truncation preserves output sessions JSON and prompt sequencing" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environment = try std.testing.environ.createMap(gpa);
    defer environment.deinit();
    const binary = environment.get("PI_TEST_BINARY") orelse return error.MissingTestBinary;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const directory = buffer[0..try scratch.dir.realPath(io, &buffer)];
    try scratch.dir.createDir(io, "home", .default_dir);
    try scratch.dir.createDir(io, "agent", .default_dir);
    const home = try std.fs.path.join(gpa, &.{ directory, "home" });
    defer gpa.free(home);
    const agent_dir = try std.fs.path.join(gpa, &.{ directory, "agent" });
    defer gpa.free(agent_dir);
    try environment.put("HOME", home);
    try environment.put("USERPROFILE", home);
    try environment.put("PI_AGENT_DIR", agent_dir);
    try environment.put("PI_TELEMETRY", "0");
    try environment.put("PI_EXTENSION_BACKEND", "native");

    const Case = struct {
        name: []const u8,
        mock: []const u8,
        stdout: []const u8,
        exit_code: u8,
        two_prompts: bool = false,
        json: bool = false,
        verbose: bool = false,
    };
    const cases = [_]Case{
        .{ .name = "length", .mock = "[{\"content\":\"partial\",\"stop_reason\":\"length\"}]", .stdout = "partial\n", .exit_code = 1 },
        .{ .name = "empty-length", .mock = "[{\"content\":\"\",\"stop_reason\":\"length\"}]", .stdout = "\n", .exit_code = 1 },
        .{ .name = "stop", .mock = "[{\"content\":\"complete\",\"stop_reason\":\"stop\"}]", .stdout = "complete\n", .exit_code = 0 },
        .{ .name = "earlier-length-final-stop", .mock = "[{\"content\":\"partial\",\"stop_reason\":\"length\"},{\"content\":\"complete\",\"stop_reason\":\"stop\"}]", .stdout = "complete\n", .exit_code = 0, .two_prompts = true },
        .{ .name = "earlier-stop-final-length", .mock = "[{\"content\":\"complete\",\"stop_reason\":\"stop\"},{\"content\":\"partial\",\"stop_reason\":\"length\"}]", .stdout = "partial\n", .exit_code = 1, .two_prompts = true },
        .{ .name = "json-length", .mock = "[{\"content\":\"partial\",\"stop_reason\":\"length\"}]", .stdout = "partial", .exit_code = 0, .json = true },
        .{ .name = "verbose-length", .mock = "[{\"content\":\"partial\",\"stop_reason\":\"length\"}]", .stdout = "partial", .exit_code = 1, .verbose = true },
        .{ .name = "length-tool-call-then-stop", .mock = "[{\"content\":\"partial\",\"stop_reason\":\"length\",\"tool_calls\":[{\"id\":\"unfinished\",\"name\":\"bash\",\"arguments\":\"{}\"}]},{\"content\":\"complete\",\"stop_reason\":\"stop\"}]", .stdout = "complete\n", .exit_code = 0 },
    };
    const warning = "Response was truncated: the model reached its output token limit.\n";
    const original = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("coding_agent/fixtures/print-mode-original-19cb.json"), .{});
    defer original.deinit();
    for (cases) |case| {
        try scratch.dir.writeFile(io, .{ .sub_path = "mock.json", .data = case.mock });
        const session_name = try std.fmt.allocPrint(gpa, "{s}.jsonl", .{case.name});
        defer gpa.free(session_name);
        const session_path = try std.fs.path.join(gpa, &.{ directory, session_name });
        defer gpa.free(session_path);
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(gpa);
        try argv.appendSlice(gpa, &.{ binary, "-p", "--offline", "--mock-script", "mock.json", "--session", session_path, "--no-context-files", "--no-skills", "--no-themes", "--no-prompt-templates", "--no-extensions", "--no-tools", "--approve" });
        if (case.json) try argv.appendSlice(gpa, &.{ "--mode", "json" });
        if (case.verbose) try argv.append(gpa, "--verbose");
        try argv.append(gpa, "first");
        if (case.two_prompts) try argv.append(gpa, "second");
        const result = try std.process.run(gpa, io, .{ .argv = argv.items, .cwd = .{ .path = directory }, .environ_map = &environment, .stdout_limit = .limited(1024 * 1024), .stderr_limit = .limited(1024 * 1024), .timeout = .{ .duration = .{ .raw = .fromSeconds(30), .clock = .awake } } });
        defer gpa.free(result.stdout);
        defer gpa.free(result.stderr);
        if (result.term != .exited or result.term.exited != case.exit_code) std.debug.print("print case {s}: {any}\nstdout:{s}\nstderr:{s}\n", .{ case.name, result.term, result.stdout, result.stderr });
        try std.testing.expect(result.term == .exited);
        try std.testing.expectEqual(case.exit_code, result.term.exited);
        if (case.json or case.verbose)
            try std.testing.expect(std.mem.indexOf(u8, result.stdout, case.stdout) != null)
        else
            try std.testing.expectEqualStrings(case.stdout, result.stdout);
        try std.testing.expectEqualStrings(if (case.exit_code == 1) warning else "", result.stderr);
        for (original.value.object.get("rows").?.array.items) |row| {
            if (!std.mem.eql(u8, case.name, row.object.get("name").?.string)) continue;
            try std.testing.expectEqual(row.object.get("exitCode").?.integer, @as(i64, result.term.exited));
            try std.testing.expectEqualStrings(row.object.get("stderr").?.string, result.stderr);
            if (!case.json) try std.testing.expectEqualStrings(row.object.get("stdout").?.string, result.stdout);
        }
        const saved = try scratch.dir.readFileAlloc(io, session_name, gpa, .limited(1024 * 1024));
        defer gpa.free(saved);
        try std.testing.expect(std.mem.indexOf(u8, saved, "\"role\":\"assistant\"") != null);
        try std.testing.expect(std.mem.indexOf(u8, saved, if (case.exit_code == 1 or case.json) "\"stopReason\":\"length\"" else "\"stopReason\":\"stop\"") != null);
        if (case.two_prompts) try std.testing.expect(std.mem.indexOf(u8, saved, "second") != null);
    }
}
