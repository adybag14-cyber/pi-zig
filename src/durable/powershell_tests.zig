const std = @import("std");
const builtin = @import("builtin");
const json = @import("backend/json.zig");
const types = @import("types.zig");
const shell = @import("shell.zig");
const tools = @import("tools.zig");
const execution_env = @import("execution_env.zig");
const registry = @import("harness/registry.zig");
const invoke = @import("harness/invoke.zig");
const builtins = @import("harness/builtins.zig");
const gpa = std.testing.allocator;
const io = std.testing.io;
const Trace = struct {
    actual: *execution_env.ExecutionEnv,
    owned: json.Owned,
    commands: json.Value,
    fn init(actual: *execution_env.ExecutionEnv) !Trace {
        const owned = try json.Owned.empty(gpa);
        return .{ .actual = actual, .owned = owned, .commands = .{ .array = .init(owned.arena.allocator()) } };
    }
    fn deinit(self: *@This()) void {
        self.owned.deinit();
    }
    pub fn cwd(self: *@This()) []const u8 {
        return self.actual.cwd();
    }
    pub fn exec(self: *@This(), command: shell.Command, options: shell.Options, context: types.Context) !shell.Result {
        const a = self.owned.arena.allocator();
        var recorded: json.Value = .{ .object = .empty };
        var argv: json.Value = .{ .array = .init(a) };
        if (command != .argv) return error.ExpectedDirectArgv;
        for (command.argv) |arg| try argv.array.append(.{ .string = try a.dupe(u8, arg) });
        try recorded.object.put(a, "command", argv);
        try recorded.object.put(a, "cwd", .{ .string = "<cwd>" });
        var environment: json.Value = .{ .object = .empty };
        if (options.env) |map| for (map.array_hash_map.keys(), map.array_hash_map.values()) |key, value| try environment.object.put(a, try a.dupe(u8, key), .{ .string = try a.dupe(u8, value) });
        try recorded.object.put(a, "env", environment);
        try recorded.object.put(a, "inheritEnv", .{ .bool = options.inheritEnv });
        if (options.timeout) |timeout| try recorded.object.put(a, "timeout", .{ .float = timeout });
        var spill: json.Value = .{ .object = .empty };
        try spill.object.put(a, "afterBytes", .{ .integer = @intCast(options.spill.?.afterBytes) });
        try spill.object.put(a, "afterLines", .{ .integer = @intCast(options.spill.?.afterLines) });
        try recorded.object.put(a, "spill", spill);
        try self.commands.array.append(recorded);
        return self.actual.exec(command, options, context);
    }
};
const Capture = struct {
    text: std.ArrayList(u8) = .empty,
    bytes: u64 = 0,
    fail: bool = false,
    fn deinit(self: *@This()) void {
        self.text.deinit(gpa);
    }
    fn output(raw: ?*anyopaque, text: []const u8, _: types.Context, info: shell.OutputInfo) !void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        if (self.fail) return error.OriginalPowerShellCallback;
        self.bytes += text.len;
        if (info.skipped) |skip| self.bytes += skip.bytes;
        try self.text.appendSlice(gpa, text);
    }
};
fn field(value: json.Value, name: []const u8) !json.Value {
    return json.required(value, name);
}
fn string(value: json.Value, name: []const u8) ![]const u8 {
    return json.asString(try field(value, name));
}
fn number(value: json.Value, name: []const u8) !?f64 {
    return if (json.get(value, name)) |v| try json.asNumber(v) else null;
}

test "durable.powershell actual latest upstream 15 real PowerShell source captures argv output failures and inheritance" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var fixture = try json.Owned.parse(gpa, @embedFile("fixtures/powershell_98d2_windows.json"));
    defer fixture.deinit();
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    var inherited = try std.testing.environ.createMap(gpa);
    defer inherited.deinit();
    var env = try execution_env.ExecutionEnv.init(gpa, io, .{ .cwd = buffer[0..length], .environ = &inherited, .temp_dir = buffer[0..length], .shellPath = "pi-native-unavailable-text-shell-20261005" });
    defer env.deinit();
    var set: tools.ToolSet = .{ .gpa = gpa, .io = io };
    const Prepare = struct {
        environment: *std.process.Environ.Map,
        name: []const u8,
        fn apply(raw: ?*anyopaque, execution: *tools.BashExecution, _: types.Context) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (std.mem.eql(u8, self.name, "prepareFailure")) return error.OriginalPowerShellCallback;
            execution.inheritEnv = false;
            execution.env = self.environment;
            if (std.mem.eql(u8, self.name, "prepare")) execution.command = "[Console]::Write($env:PI_NATIVE_PREPARED)";
        }
    };
    const cases = (try field(fixture.value, "results")).array.items;
    try std.testing.expectEqual(@as(usize, 15), cases.len);
    for (cases) |row| {
        const name = try string(row, "name");
        var trace = try Trace.init(&env);
        defer trace.deinit();
        var capture: Capture = .{ .fail = std.mem.eql(u8, name, "callback") };
        defer capture.deinit();
        var options: tools.PowerShellOptions = .{ .onOutput = Capture.output, .output_context = &capture };
        var programs: std.ArrayList([]const u8) = .empty;
        defer programs.deinit(gpa);
        if (json.get(row, "programs")) |list| {
            for (list.array.items) |item| try programs.append(gpa, try json.asString(item));
            options.programs = programs.items;
        }
        if (json.get(row, "prefix")) |prefix| options.commandPrefix = try json.asString(prefix);
        var prepared: std.process.Environ.Map = .init(gpa);
        defer prepared.deinit();
        if (std.mem.eql(u8, name, "prepare")) try prepared.put("PI_NATIVE_PREPARED", "prepared");
        if (std.mem.eql(u8, name, "explicitEmptyPath")) try prepared.put("PATH", "");
        var prepare: Prepare = .{ .name = name, .environment = &prepared };
        if (std.mem.eql(u8, name, "prepare") or std.mem.eql(u8, name, "explicitEmptyPath") or std.mem.eql(u8, name, "prepareFailure")) {
            options.prepare = Prepare.apply;
            options.prepare_context = &prepare;
        }
        const input = try field(row, "input");
        var result = try set.powershell(&trace, .{ .command = try string(input, "command"), .timeout = try number(input, "timeout") }, options, .{});
        defer result.deinit(gpa);
        if (json.get(row, "error")) |failure| {
            if (result != .failure) {
                std.debug.print("PowerShell scenario {s} unexpectedly succeeded\n", .{name});
                return error.TestUnexpectedResult;
            }
            try std.testing.expectEqualStrings(try string(failure, "message"), result.failure.message);
            if (json.get(failure, "code")) |code| try std.testing.expectEqualStrings(try json.asString(code), @tagName(result.failure.execution.?.code));
            if ((try field(failure, "identity")).bool) try std.testing.expectEqual(error.OriginalPowerShellCallback, result.failure.cause.?);
        } else try std.testing.expect(result == .value);
        if (json.get(row, "output")) |expected| try std.testing.expectEqualStrings(try json.asString(expected), capture.text.items);
        try std.testing.expectEqual(try json.asInteger(try field(row, "outputBytes")), capture.bytes);
        try std.testing.expect(json.equal(try field(row, "commands"), trace.commands));
        const diagnostics = if (result == .value) result.value.diagnostics.items else result.failure.diagnostics.items;
        const expected_diagnostics = (try field(row, "diagnostics")).array.items;
        try std.testing.expectEqual(expected_diagnostics.len, diagnostics.len);
        if (json.get(row, "spillSize")) |size| {
            try std.testing.expectEqualStrings("full_output", diagnostics[0].code.?);
            const stat = try std.Io.Dir.cwd().statFile(io, diagnostics[0].message["Full output: ".len..], .{});
            try std.testing.expectEqual(try json.asInteger(size), stat.size);
        }
        try std.testing.expectEqual(@as(usize, 0), env.shell.active.items.len);
    }
}

test "durable.powershell explicit native registry registration preserves default four tools and executes real UTF8" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    var inherited = try std.testing.environ.createMap(gpa);
    defer inherited.deinit();
    var env = try execution_env.ExecutionEnv.init(gpa, io, .{ .cwd = buffer[0..length], .environ = &inherited, .temp_dir = buffer[0..length] });
    defer env.deinit();
    var owner = try registry.Registry.init(gpa, io);
    defer owner.deinit();
    const defaults = try builtins.Bindings.create(gpa, &env);
    defer defaults.drop();
    try defaults.install(&owner);
    {
        const snapshot = owner.snapshot();
        defer snapshot.release();
        try std.testing.expectEqual(@as(usize, 4), snapshot.getExtension("pi.tools").?.tools.len);
        try std.testing.expect(snapshot.findTool("powershell", null) == null);
    }
    const binding = try builtins.createPowerShellTool(gpa, &env, .{});
    defer binding.drop();
    try binding.install(&owner);
    const snapshot = owner.snapshot();
    defer snapshot.release();
    try std.testing.expectEqual(@as(usize, 4), snapshot.getExtension("pi.tools").?.tools.len);
    try std.testing.expectEqual(@as(usize, 1), snapshot.getExtension("pi.tools.powershell").?.tools.len);
    try std.testing.expectEqual(@import("output_window.zig").Retention.tail, snapshot.findTool("powershell", null).?.tool.limits.retain);
    var args = try json.Owned.parse(gpa, "{\"command\":\"[Console]::Write('héllo😀')\"}");
    defer args.deinit();
    var result = try invoke.invoke(gpa, snapshot, "powershell", args.value, .{}, .{});
    defer result.deinit();
    if (json.get(result.value.value, "isError")) |value| try std.testing.expect(!value.bool);
    const content = (try field(result.value.value, "content")).array.items;
    try std.testing.expectEqualStrings("héllo😀", try string(content[0], "text"));
}

test "durable.powershell portable real argv records prologue literal script cwd environment and startup fallback" {
    var parent = try std.testing.environ.createMap(gpa);
    defer parent.deinit();
    const program = parent.get("PI_DURABLE_COMMAND_FIXTURE") orelse return error.SkipZigTest;
    try parent.put("PI_NATIVE_PARENT_MARKER", "parent");
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    try scratch.dir.createDir(io, "prepared", .default_dir);
    const requested_cwd = try std.fs.path.join(gpa, &.{ buffer[0..length], "prepared" });
    defer gpa.free(requested_cwd);
    var env = try execution_env.ExecutionEnv.init(gpa, io, .{ .cwd = buffer[0..length], .environ = &parent, .temp_dir = buffer[0..length], .shellPath = "pi-argv-proves-no-shell-20261005" });
    defer env.deinit();
    var overlay: std.process.Environ.Map = .init(gpa);
    defer overlay.deinit();
    try overlay.put("PI_NATIVE_ARG_MARKER", "héllo😀");
    const Prepare = struct {
        seen: bool = false,
        cwd: []const u8,
        fn apply(raw: ?*anyopaque, execution: *tools.BashExecution, _: types.Context) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            try std.testing.expectEqualStrings("prefix\nliteral '&|;$()' 😀\nsecond", execution.command);
            self.seen = true;
            execution.cwd = self.cwd;
        }
    };
    var prepare: Prepare = .{ .cwd = requested_cwd };
    var trace = try Trace.init(&env);
    defer trace.deinit();
    var capture: Capture = .{};
    defer capture.deinit();
    var set: tools.ToolSet = .{ .gpa = gpa, .io = io };
    var result = try set.powershell(&trace, .{ .command = "literal '&|;$()' 😀\nsecond" }, .{ .programs = &.{ "pi-native-missing-argv-program-20261005", program }, .commandPrefix = "prefix", .prepare = Prepare.apply, .prepare_context = &prepare, .env = &overlay, .inheritEnv = false, .onOutput = Capture.output, .output_context = &capture }, .{});
    defer result.deinit(gpa);
    try std.testing.expect(result == .value);
    try std.testing.expect(prepare.seen);
    try std.testing.expectEqual(@as(usize, 2), trace.commands.array.items.len);
    var response = try json.Owned.parse(gpa, capture.text.items);
    defer response.deinit();
    const argv = (try field(response.value, "argv")).array.items;
    try std.testing.expectEqual(@as(usize, 6), argv.len);
    for (@import("tool_bash.zig").powershell_arguments, argv[0..5]) |expected, actual| try std.testing.expectEqualStrings(expected, try json.asString(actual));
    try std.testing.expectEqualStrings(@import("tool_bash.zig").utf8_output ++ "\nprefix\nliteral '&|;$()' 😀\nsecond", try json.asString(argv[5]));
    try std.testing.expectEqualStrings(requested_cwd, try string(response.value, "cwd"));
    try std.testing.expectEqualStrings("héllo😀", try string(response.value, "marker"));
    try std.testing.expect((try field(response.value, "inherited")) == .null);
    try std.testing.expectEqual(@as(usize, 0), env.shell.active.items.len);
}

test "durable.powershell portable real nonzero timeout callback failure never falls back after startup" {
    var parent = try std.testing.environ.createMap(gpa);
    defer parent.deinit();
    const program = parent.get("PI_DURABLE_COMMAND_FIXTURE") orelse return error.SkipZigTest;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    var env = try execution_env.ExecutionEnv.init(gpa, io, .{ .cwd = buffer[0..length], .environ = &parent, .temp_dir = buffer[0..length] });
    defer env.deinit();
    var set: tools.ToolSet = .{ .gpa = gpa, .io = io };
    for ([_][]const u8{ "nonzero", "timeout", "callback" }) |mode| {
        var overlay: std.process.Environ.Map = .init(gpa);
        defer overlay.deinit();
        try overlay.put("PI_COMMAND_FIXTURE_MODE", if (std.mem.eql(u8, mode, "timeout")) "sleep" else "output");
        if (std.mem.eql(u8, mode, "nonzero")) try overlay.put("PI_COMMAND_FIXTURE_EXIT", "3");
        var trace = try Trace.init(&env);
        defer trace.deinit();
        var capture: Capture = .{ .fail = std.mem.eql(u8, mode, "callback") };
        defer capture.deinit();
        var result = try set.powershell(&trace, .{ .command = "untouched script", .timeout = if (std.mem.eql(u8, mode, "timeout")) 0.05 else null }, .{ .programs = &.{ program, "pi-native-never-start-20261005" }, .env = &overlay, .onOutput = Capture.output, .output_context = &capture }, .{});
        defer result.deinit(gpa);
        try std.testing.expect(result == .failure);
        try std.testing.expectEqual(@as(usize, 1), trace.commands.array.items.len);
        if (std.mem.eql(u8, mode, "nonzero")) {
            try std.testing.expectEqualStrings("Command exited with code 3", result.failure.message);
            try std.testing.expectEqualStrings("native-output", capture.text.items);
        } else if (std.mem.eql(u8, mode, "timeout")) {
            try std.testing.expectEqualStrings("Command timed out after 0.05 seconds", result.failure.message);
            try std.testing.expectEqual(shell.ExecutionErrorCode.timeout, result.failure.execution.?.code);
        } else {
            try std.testing.expectEqual(error.OriginalPowerShellCallback, result.failure.cause.?);
            try std.testing.expectEqual(shell.ExecutionErrorCode.callback_error, result.failure.execution.?.code);
        }
        try std.testing.expectEqual(@as(usize, 0), env.shell.active.items.len);
    }
}

test "durable.powershell allocation failures release copied configuration snapshots and environment" {
    const Allocate = struct {
        fn run(allocator: std.mem.Allocator) !void {
            var inherited: std.process.Environ.Map = .init(allocator);
            defer inherited.deinit();
            var env = try execution_env.ExecutionEnv.init(allocator, io, .{ .cwd = ".", .environ = &inherited, .temp_dir = "." });
            defer env.deinit();
            var options_environment: std.process.Environ.Map = .init(allocator);
            defer options_environment.deinit();
            try options_environment.put("KEY", "value");
            var owner = try registry.Registry.init(allocator, io);
            defer owner.deinit();
            const binding = try builtins.createPowerShellTool(allocator, &env, .{ .programs = &.{ "first", "second" }, .commandPrefix = "prefix", .env = &options_environment });
            defer binding.drop();
            try binding.install(&owner);
            const snapshot = owner.snapshot();
            defer snapshot.release();
            const tool = snapshot.findTool("powershell", null).?;
            try std.testing.expectEqualStrings("powershell", tool.tool.name);
            try owner.uninstall("pi.tools.powershell");
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, Allocate.run, .{});
}

test "durable.powershell portable real abort preserves cause and retained window skipped counts and spill" {
    var parent = try std.testing.environ.createMap(gpa);
    defer parent.deinit();
    const program = parent.get("PI_DURABLE_COMMAND_FIXTURE") orelse return error.SkipZigTest;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    var env = try execution_env.ExecutionEnv.init(gpa, io, .{ .cwd = buffer[0..length], .environ = &parent, .temp_dir = buffer[0..length] });
    defer env.deinit();
    var set: tools.ToolSet = .{ .gpa = gpa, .io = io };
    var overlay: std.process.Environ.Map = .init(gpa);
    defer overlay.deinit();
    try overlay.put("PI_COMMAND_FIXTURE_MODE", "output");
    const Abort = struct {
        flag: *std.atomic.Value(bool),
        fn output(raw: ?*anyopaque, _: []const u8, _: types.Context, _: shell.OutputInfo) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.flag.store(true, .release);
        }
    };
    var flag: std.atomic.Value(bool) = .init(false);
    var abort: Abort = .{ .flag = &flag };
    var stopped = try set.powershell(&env, .{ .command = "not interpreted by argument fixture" }, .{ .programs = &.{ program, "pi-native-never-start-20261005" }, .env = &overlay, .onOutput = Abort.output, .output_context = &abort }, .{ .abort_flag = &flag });
    defer stopped.deinit(gpa);
    try std.testing.expect(stopped == .failure);
    try std.testing.expectEqual(shell.ExecutionErrorCode.aborted, stopped.failure.execution.?.code);
    try overlay.put("PI_COMMAND_FIXTURE_MODE", "large");
    var capture: Capture = .{};
    defer capture.deinit();
    var bounded = try set.powershell(&env, .{ .command = "literal fixture payload" }, .{ .programs = &.{program}, .env = &overlay, .onOutput = Capture.output, .output_context = &capture, .outputWindow = .{ .maxBytes = 20, .maxLines = 3, .minIntervalMs = 100, .bytesPerSecond = 1024 } }, .{});
    defer bounded.deinit(gpa);
    try std.testing.expect(bounded == .value);
    try std.testing.expectEqual(@as(u64, 60000), capture.bytes);
    try std.testing.expect(capture.text.items.len <= 20);
    try std.testing.expectEqualStrings("full_output", bounded.value.diagnostics.items[0].code.?);
    const stat = try std.Io.Dir.cwd().statFile(io, bounded.value.diagnostics.items[0].message["Full output: ".len..], .{});
    try std.testing.expectEqual(@as(u64, 60000), stat.size);
    try std.testing.expectEqual(@as(usize, 0), env.shell.active.items.len);
}

test "durable.powershell native command allocation failures release exactly owned child pipes jobs and results" {
    var parent = try std.testing.environ.createMap(gpa);
    defer parent.deinit();
    const program = parent.get("PI_DURABLE_COMMAND_FIXTURE") orelse return error.SkipZigTest;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    const Allocate = struct {
        fn run(allocator: std.mem.Allocator, cwd: []const u8, executable: []const u8) !void {
            var inherited: std.process.Environ.Map = .init(allocator);
            defer inherited.deinit();
            try inherited.put("PI_COMMAND_FIXTURE_MODE", "output");
            var env = try execution_env.ExecutionEnv.init(allocator, io, .{ .cwd = cwd, .environ = &inherited, .temp_dir = cwd });
            defer env.deinit();
            var set: tools.ToolSet = .{ .gpa = allocator, .io = io };
            var result = try set.powershell(&env, .{ .command = "native literal" }, .{ .programs = &.{executable}, .commandPrefix = "prefix" }, .{});
            defer result.deinit(allocator);
            if (result == .failure and result.failure.cause != null and result.failure.cause.? == error.OutOfMemory) return error.OutOfMemory;
            try std.testing.expectEqual(@as(usize, 0), env.shell.active.items.len);
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, Allocate.run, .{ buffer[0..length], program });
}
