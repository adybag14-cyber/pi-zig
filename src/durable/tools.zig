//! Native durable tool execution. The CLI formatter remains a separate adapter.
const std = @import("std");
const types = @import("types.zig");
pub const values = @import("tool_types.zig");
pub const read = @import("tool_read.zig");
pub const text_utils = @import("text.zig");
pub const edit_match = @import("tool_edit.zig");
pub const diff = @import("tool_diff.zig");
const shell = @import("shell.zig");
const output = @import("output_window.zig");
// A single bounded lock also covers tools constructed separately for one env.
// This preserves mutation ordering; independent paths currently serialize too.
var file_mutations: std.Io.Mutex = .init;
pub const bash_runner = @import("tool_bash.zig");
pub const powershell_runner = @import("tool_powershell.zig");
pub const BashInput = bash_runner.Input;
pub const BashExecution = bash_runner.Execution;
pub const BashPrepare = bash_runner.Prepare;
pub const BashOptions = bash_runner.Options;
pub const PowerShellInput = powershell_runner.Input;
pub const PowerShellOptions = powershell_runner.Options;
/// A capability owner shares this set between invocations. Mutations are
/// serialized without retaining caller arguments or changing the environment.
pub const ToolSet = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    pub fn edit(self: *ToolSet, env: anytype, path: []const u8, edits: []const edit_match.Edit, context: types.Context) !values.Result {
        if (edits.len == 0) return values.messageFailure(self.gpa, "Edit tool input is invalid. edits must contain at least one replacement.", null);
        const normalized_path = try text_utils.toolPath(self.gpa, path);
        defer self.gpa.free(normalized_path);
        const absolute = try env.absolutePath(normalized_path, context);
        if (absolute == .failure) return values.fileFailure(self.gpa, absolute.failure);
        defer self.gpa.free(absolute.value);
        try file_mutations.lock(self.io);
        defer file_mutations.unlock(self.io);
        if (context.aborted()) return values.messageFailure(self.gpa, "Operation aborted", error.Canceled);
        const found = try env.fileInfo(absolute.value, context);
        if (found == .failure) return editAccessFailure(self.gpa, path, found.failure);
        var info = found.value;
        defer info.deinit(self.gpa);
        if (info.kind != .file and info.kind != .symlink) return .{ .failure = .{ .message = try std.fmt.allocPrint(self.gpa, "Could not edit file: {s}. Path is not a file.", .{path}) } };
        const read_result = try env.readTextFile(absolute.value, context);
        if (read_result == .failure) return editAccessFailure(self.gpa, path, read_result.failure);
        const original = read_result.value;
        defer self.gpa.free(original);
        if (context.aborted()) return values.messageFailure(self.gpa, "Operation aborted", error.Canceled);
        const content = if (std.mem.startsWith(u8, original, "\xef\xbb\xbf")) original[3..] else original;
        var applied_result = try edit_match.apply(self.gpa, content, edits, path);
        if (applied_result == .failure) return .{ .failure = .{ .message = applied_result.failure } };
        defer applied_result.value.deinit(self.gpa);
        const applied = applied_result.value;
        const final = try edit_match.restore(self.gpa, applied.newContent, original);
        defer self.gpa.free(final);
        var result: values.ToolResult = .{};
        var transferred = false;
        defer if (!transferred) result.deinit(self.gpa);
        result.details = .{ .edit = try diff.generate(self.gpa, path, applied.baseContent, applied.newContent) };
        result.text = try std.fmt.allocPrint(self.gpa, "Successfully replaced {d} block(s) in {s}.", .{ edits.len, path });
        if (context.aborted()) {
            return values.messageFailure(self.gpa, "Operation aborted", error.Canceled);
        }
        const written = try env.writeFile(absolute.value, final, context);
        if (written == .failure) {
            return editAccessFailure(self.gpa, path, written.failure);
        }
        transferred = true;
        return .{ .value = result };
    }
    pub fn write(self: *ToolSet, env: anytype, path: []const u8, content: []const u8, context: types.Context) !values.Result {
        const normalized = try text_utils.toolPath(self.gpa, path);
        defer self.gpa.free(normalized);
        const absolute = try env.absolutePath(normalized, context);
        if (absolute == .failure) return values.fileFailure(self.gpa, absolute.failure);
        defer self.gpa.free(absolute.value);
        try file_mutations.lock(self.io);
        defer file_mutations.unlock(self.io);
        const written = try env.writeFile(absolute.value, content, context);
        if (written == .failure) return values.fileFailure(self.gpa, written.failure);
        return .{ .value = .{ .text = try std.fmt.allocPrint(self.gpa, "Successfully wrote to {s}", .{path}) } };
    }
    pub fn bash(self: *ToolSet, env: anytype, input: BashInput, options: BashOptions, context: types.Context) !values.Result {
        return bash_runner.execute(self.gpa, env, input, options, null, context);
    }
    pub fn powershell(self: *ToolSet, env: anytype, input: PowerShellInput, options: PowerShellOptions, context: types.Context) !values.Result {
        return powershell_runner.execute(self.gpa, env, input, options, context);
    }
};
fn editAccessFailure(gpa: std.mem.Allocator, path: []const u8, failure: types.FileError) !values.Result {
    var owned = failure;
    errdefer owned.deinit(gpa);
    return .{ .failure = .{ .message = try std.fmt.allocPrint(gpa, "Could not edit file: {s}. Error code: {s}.", .{ path, @tagName(failure.code) }), .cause = failure.cause, .file = failure } };
}

test "durable structured read preserves slice semantics and keeps diagnostics out of content" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    var environ: std.process.Environ.Map = .init(gpa);
    defer environ.deinit();
    var env = try @import("execution_env.zig").ExecutionEnv.init(gpa, io, .{ .cwd = buffer[0..length], .environ = &environ, .temp_dir = buffer[0..length] });
    defer env.deinit();
    var set: ToolSet = .{ .gpa = gpa, .io = io };
    var written = try set.write(&env, "nested/file", "\xef\xbb\xbfa\nb\nc\nd", .{});
    defer written.deinit(gpa);
    try std.testing.expectEqualStrings("Successfully wrote to nested/file", written.value.text.?);
    const cases = [_]struct { offset: ?f64, limit: ?f64, text: ?[]const u8, notice: ?[]const u8 }{
        .{ .offset = null, .limit = null, .text = "a\nb\nc\nd", .notice = null },
        .{ .offset = 2, .limit = 1, .text = "b", .notice = "2 more lines in file. Use offset=3 to continue." },
        .{ .offset = 1.5, .limit = 1.5, .text = "a\nb", .notice = "2 more lines in file. Use offset=3 to continue." },
        .{ .offset = null, .limit = -1, .text = "a\nb\nc", .notice = "5 more lines in file. Use offset=0 to continue." },
        .{ .offset = null, .limit = 0, .text = null, .notice = "4 more lines in file. Use offset=1 to continue." },
        .{ .offset = std.math.nan(f64), .limit = std.math.nan(f64), .text = null, .notice = null },
    };
    for (cases) |row| {
        var result = try read.execute(&env, .{ .path = "nested/file", .offset = row.offset, .limit = row.limit }, .{});
        defer result.deinit(gpa);
        try std.testing.expect(result == .value);
        if (row.text) |text| try std.testing.expectEqualStrings(text, result.value.text.?) else try std.testing.expect(result.value.text == null);
        try std.testing.expectEqual(@as(usize, if (row.notice == null) 0 else 1), result.value.diagnostics.items.len);
        if (row.notice) |notice| try std.testing.expectEqualStrings(notice, result.value.diagnostics.items[0].message);
    }
    var beyond = try read.execute(&env, .{ .path = "nested/file", .offset = std.math.inf(f64) }, .{});
    defer beyond.deinit(gpa);
    try std.testing.expect(beyond == .failure);
    var image_write = try set.write(&env, "image", "GIF89a", .{});
    defer image_write.deinit(gpa);
    var image_read = try read.execute(&env, .{ .path = "image" }, .{});
    defer image_read.deinit(gpa);
    try std.testing.expect(image_read.value.isError);
    try std.testing.expectEqualStrings("unsupported_image", image_read.value.diagnostics.items[0].code.?);
}

fn oracleNumber(value: std.json.Value) ?f64 {
    return switch (value) {
        .integer => |number| @floatFromInt(number),
        .float => |number| number,
        .number_string => |number| std.fmt.parseFloat(f64, number) catch unreachable,
        .string => |string| if (std.mem.eql(u8, string, "undefined")) null else if (std.mem.eql(u8, string, "NaN")) std.math.nan(f64) else if (std.mem.eql(u8, string, "Infinity")) std.math.inf(f64) else -std.math.inf(f64),
        else => unreachable,
    };
}
test "durable structured read matches 386 captured upstream differential results" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const fixture = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), @embedFile("fixtures/read_b78.json"), .{});
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    var environ: std.process.Environ.Map = .init(gpa);
    defer environ.deinit();
    var env = try @import("execution_env.zig").ExecutionEnv.init(gpa, io, .{ .cwd = buffer[0..length], .environ = &environ, .temp_dir = buffer[0..length] });
    defer env.deinit();
    const cases = fixture.object.get("cases").?.array.items;
    try std.testing.expectEqual(@as(usize, 386), cases.len);
    for (cases) |row| {
        const input = row.object.get("input").?.string;
        const bytes = try gpa.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(input));
        defer gpa.free(bytes);
        try std.base64.standard.Decoder.decode(bytes, input);
        const write = try env.writeFile("fixture", bytes, .{});
        try std.testing.expect(write == .value);
        var actual = try read.execute(&env, .{ .path = "fixture", .offset = oracleNumber(row.object.get("offset").?), .limit = oracleNumber(row.object.get("limit").?) }, .{});
        defer actual.deinit(gpa);
        const expected = row.object.get("result").?.object;
        compareRead(actual, expected) catch |err| {
            std.debug.print("Structured read oracle seed {d}: actual {s}\n", .{ row.object.get("seed").?.integer, if (actual == .failure) actual.failure.message else actual.value.text orelse "<empty>" });
            return err;
        };
    }
}
fn compareRead(actual: values.Result, expected: std.json.ObjectMap) !void {
    if (expected.get("error")) |message| {
        try std.testing.expect(actual == .failure);
        try std.testing.expectEqualStrings(message.string, actual.failure.message);
        return;
    }
    try std.testing.expect(actual == .value);
    const result = actual.value;
    const content = expected.get("content").?.array.items;
    if (content.len == 0) try std.testing.expect(result.text == null) else try std.testing.expectEqualStrings(content[0].object.get("text").?.string, result.text.?);
    const diagnostics = expected.get("diagnostics").?.array.items;
    try std.testing.expectEqual(diagnostics.len, result.diagnostics.items.len);
    for (diagnostics, result.diagnostics.items) |diagnostic, item| {
        try std.testing.expectEqualStrings(diagnostic.object.get("message").?.string, item.message);
        const severity = diagnostic.object.get("severity").?.string;
        try std.testing.expectEqualStrings(severity, if (item.severity == .err) "error" else @tagName(item.severity));
        if (diagnostic.object.get("code")) |code| try std.testing.expectEqualStrings(code.string, item.code.?) else try std.testing.expect(item.code == null);
    }
    if (expected.get("details")) |details| {
        const truncation = details.object.get("truncation").?.object;
        const actual_details = result.details.?.truncation;
        inline for (std.meta.fields(@TypeOf(actual_details))) |field| {
            const value = truncation.get(field.name).?;
            if (field.type == bool) try std.testing.expectEqual(value.bool, @field(actual_details, field.name)) else if (field.type == u64) try std.testing.expectEqual(@as(u64, @intCast(value.integer)), @field(actual_details, field.name)) else if (value == .null) try std.testing.expect(@field(actual_details, field.name) == null) else try std.testing.expectEqualStrings(value.string, @tagName(@field(actual_details, field.name).?));
        }
    } else try std.testing.expect(result.details == null);
}

test "durable structured edit and native diff match pinned upstream captures" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const fixture = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), @embedFile("fixtures/edit_b78.json"), .{});
    for (fixture.object.get("cases").?.array.items) |row| {
        const input = row.object.get("edits").?.array.items;
        const edits = try gpa.alloc(edit_match.Edit, input.len);
        defer gpa.free(edits);
        for (edits, input) |*edit, value| edit.* = .{ .oldText = value.object.get("oldText").?.string, .newText = value.object.get("newText").?.string };
        var applied = try edit_match.apply(gpa, row.object.get("original").?.string, edits, "fixture");
        defer switch (applied) {
            .value => |*value| value.deinit(gpa),
            .failure => |message| gpa.free(message),
        };
        const expected = row.object.get("result").?.object;
        if (expected.get("error")) |message| {
            try std.testing.expect(applied == .failure);
            try std.testing.expectEqualStrings(message.string, applied.failure);
        } else {
            try std.testing.expect(applied == .value);
            try std.testing.expectEqualStrings(expected.get("baseContent").?.string, applied.value.baseContent);
            try std.testing.expectEqualStrings(expected.get("newContent").?.string, applied.value.newContent);
            const details = try diff.generate(gpa, "fixture", applied.value.baseContent, applied.value.newContent);
            defer {
                gpa.free(details.diff);
                gpa.free(details.patch);
            }
            compareDiff(details, expected) catch |err| {
                std.debug.print("Edit oracle seed {d}\n", .{row.object.get("seed").?.integer});
                return err;
            };
        }
    }
    for (fixture.object.get("diffCases").?.array.items) |row| {
        const details = try diff.generate(gpa, "fixture", row.object.get("original").?.string, row.object.get("changed").?.string);
        defer {
            gpa.free(details.diff);
            gpa.free(details.patch);
        }
        compareDiff(details, row.object.get("result").?.object) catch |err| {
            std.debug.print("Diff oracle seed {d} old {s} new {s}\n", .{ row.object.get("seed").?.integer, row.object.get("original").?.string, row.object.get("changed").?.string });
            return err;
        };
    }
}
fn compareDiff(details: values.EditDetails, expected: std.json.ObjectMap) !void {
    try std.testing.expectEqualStrings(expected.get("diff").?.string, details.diff);
    try std.testing.expectEqualStrings(expected.get("patch").?.string, details.patch);
    if (expected.get("firstChangedLine")) |line| try std.testing.expectEqual(@as(u64, @intCast(line.integer)), details.firstChangedLine.?) else try std.testing.expect(details.firstChangedLine == null);
}

test "durable edit matches against original file validates all edits before writing and preserves BOM CRLF" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    var environ: std.process.Environ.Map = .init(gpa);
    defer environ.deinit();
    var env = try @import("execution_env.zig").ExecutionEnv.init(gpa, io, .{ .cwd = buffer[0..length], .environ = &environ, .temp_dir = buffer[0..length] });
    defer env.deinit();
    var set: ToolSet = .{ .gpa = gpa, .io = io };
    const original = "\xef\xbb\xbfalpha\r\nbeta\r\ngamma";
    const created = try env.writeFile("fixture", original, .{});
    try std.testing.expect(created == .value);
    var invalid = try set.edit(&env, "fixture", &.{ .{ .oldText = "alpha", .newText = "A" }, .{ .oldText = "absent", .newText = "X" } }, .{});
    defer invalid.deinit(gpa);
    try std.testing.expect(invalid == .failure);
    const unchanged = try env.readTextFile("fixture", .{});
    defer gpa.free(unchanged.value);
    try std.testing.expectEqualStrings(original, unchanged.value);
    var changed = try set.edit(&env, "@fixture", &.{ .{ .oldText = "alpha", .newText = "A" }, .{ .oldText = "gamma", .newText = "G" } }, .{});
    defer changed.deinit(gpa);
    try std.testing.expect(changed == .value);
    const actual = try env.readTextFile("fixture", .{});
    defer gpa.free(actual.value);
    try std.testing.expectEqualStrings("\xef\xbb\xbfA\r\nbeta\r\nG", actual.value);
}

test "durable structured matching diff and read clean every injected allocation failure" {
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    const file = try scratch.dir.createFile(io, "fixture", .{});
    defer file.close(io);
    try file.writeStreamingAll(io, "a\n“quoted”—ﬁ   \nkeep  \n");
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    var environ: std.process.Environ.Map = .init(std.testing.allocator);
    defer environ.deinit();
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(gpa: std.mem.Allocator, cwd: []const u8, parent: *const std.process.Environ.Map) !void {
            var env = try @import("execution_env.zig").ExecutionEnv.init(gpa, std.testing.io, .{ .cwd = cwd, .environ = parent, .temp_dir = cwd });
            defer env.deinit();
            var read_result = try read.execute(&env, .{ .path = "fixture", .limit = 1 }, .{});
            defer read_result.deinit(gpa);
            try std.testing.expect(read_result == .value);
            var applied = try edit_match.apply(gpa, "a\n“quoted”—ﬁ   \nkeep  \n", &.{.{ .oldText = "\"quoted\"-fi", .newText = "changed" }}, "fixture");
            defer switch (applied) {
                .value => |*value| value.deinit(gpa),
                .failure => |message| gpa.free(message),
            };
            try std.testing.expect(applied == .value);
            const details = try diff.generate(gpa, "fixture", applied.value.baseContent, applied.value.newContent);
            defer {
                gpa.free(details.diff);
                gpa.free(details.patch);
            }
            var missing = try read.execute(&env, .{ .path = "missing" }, .{});
            defer missing.deinit(gpa);
            try std.testing.expect(missing == .failure);
        }
    }.run, .{ buffer[0..length], &environ });
}

test "durable bash forwards real output nonzero exits timeout spill and original callback cause" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var parent = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer parent.deinit();
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    var env = try @import("execution_env.zig").ExecutionEnv.init(gpa, io, .{ .cwd = buffer[0..length], .environ = &parent, .temp_dir = buffer[0..length] });
    defer env.deinit();
    var set: ToolSet = .{ .gpa = gpa, .io = io };
    const current = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(current);
    const fixture = try std.fs.path.resolve(gpa, &.{ current, parent.get("PI_DURABLE_FIXTURE") orelse if (@import("builtin").os.tag == .windows) "zig-out/bin/pi-durable-fixture.exe" else "zig-out/bin/pi-durable-fixture" });
    defer gpa.free(fixture);
    const shell_fixture = try gpa.dupe(u8, fixture);
    defer gpa.free(shell_fixture);
    if (@import("builtin").os.tag == .windows) std.mem.replaceScalar(u8, shell_fixture, '\\', '/');
    const Capture = struct {
        gpa: std.mem.Allocator,
        buffer: std.ArrayList(u8) = .empty,
        bytes: u64 = 0,
        fail: bool = false,
        bounded: bool = false,
        fn receive(state: ?*anyopaque, chunk: []const u8, _: types.Context, info: shell.OutputInfo) !void {
            const self: *@This() = @ptrCast(@alignCast(state.?));
            if (self.fail) return error.OriginalCallback;
            self.bytes += chunk.len;
            if (info.skipped) |skip| self.bytes += skip.bytes;
            if (!self.bounded) try self.buffer.appendSlice(self.gpa, chunk);
        }
    };
    for ([_][]const u8{ "args", "streams", "large", "timeout", "callback" }) |mode| {
        var capture: Capture = .{ .gpa = gpa, .fail = std.mem.eql(u8, mode, "callback"), .bounded = std.mem.eql(u8, mode, "large") };
        defer capture.buffer.deinit(gpa);
        const command = try std.fmt.allocPrint(gpa, "'{s}' {s}", .{ shell_fixture, if (std.mem.eql(u8, mode, "timeout")) "sleep" else if (capture.fail) "streams" else mode });
        defer gpa.free(command);
        var result = try set.bash(&env, .{ .command = command, .timeout = if (std.mem.eql(u8, mode, "timeout")) 0.2 else 5 }, .{ .onOutput = Capture.receive, .output_context = &capture }, .{});
        defer result.deinit(gpa);
        if (std.mem.eql(u8, mode, "args")) {
            try std.testing.expect(result == .value);
            try std.testing.expectEqualStrings("[]", capture.buffer.items);
        } else if (std.mem.eql(u8, mode, "streams")) {
            try std.testing.expectEqualStrings("Command exited with code 7", result.failure.message);
            try std.testing.expectEqualStrings("a😀\ne\xef\xbf\xbd\xef\xbb\xbf\n", capture.buffer.items);
        } else if (std.mem.eql(u8, mode, "timeout")) {
            try std.testing.expectEqualStrings("Command timed out after 0.2 seconds", result.failure.message);
            try std.testing.expectEqual(shell.ExecutionErrorCode.timeout, result.failure.execution.?.code);
        } else if (capture.fail) {
            try std.testing.expect(result == .failure);
            try std.testing.expectEqual(error.OriginalCallback, result.failure.cause.?);
            try std.testing.expectEqual(@as(u64, 0), capture.bytes);
        } else {
            try std.testing.expect(result == .value);
            try std.testing.expectEqual(@as(u64, 4 * 1024 * 1024), capture.bytes);
            try std.testing.expectEqualStrings("full_output", result.value.diagnostics.items[0].code.?);
            const spill_path = result.value.diagnostics.items[0].message["Full output: ".len..];
            const stat = try std.Io.Dir.cwd().statFile(io, spill_path, .{});
            try std.testing.expectEqual(@as(u64, 4 * 1024 * 1024), stat.size);
        }
        try std.testing.expectEqual(@as(usize, 0), env.shell.active.items.len);
    }
    for ([_]f64{ 0, -1, std.math.nan(f64), std.math.inf(f64), 2147483.648 }) |timeout| {
        var result = try set.bash(&env, .{ .command = "true", .timeout = timeout }, .{}, .{});
        defer result.deinit(gpa);
        try std.testing.expectEqualStrings(if (timeout > 2147483.647 and std.math.isFinite(timeout)) "Invalid timeout: maximum is 2147483.647 seconds" else "Invalid timeout: must be a finite number of seconds", result.failure.message);
    }
    const Prepare = struct {
        fn fail(_: ?*anyopaque, _: *BashExecution, _: types.Context) !void {
            return error.OriginalPrepare;
        }
    };
    var failed_prepare = try set.bash(&env, .{ .command = "true" }, .{ .prepare = Prepare.fail }, .{});
    defer failed_prepare.deinit(gpa);
    try std.testing.expectEqual(error.OriginalPrepare, failed_prepare.failure.cause.?);
}

test "durable read paths support actual NFD apostrophe screenshot and Unicode space filenames" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    var parent: std.process.Environ.Map = .init(gpa);
    defer parent.deinit();
    var env = try @import("execution_env.zig").ExecutionEnv.init(gpa, io, .{ .cwd = buffer[0..length], .environ = &parent, .temp_dir = buffer[0..length] });
    defer env.deinit();
    const cases = [_]struct { stored: []const u8, requested: []const u8 }{
        .{ .stored = "cafe\xcc\x81", .requested = "@café" },
        .{ .stored = "it’s a file", .requested = "it's a file" },
        .{ .stored = "Screen 10.30\xe2\x80\xafam.png", .requested = "Screen 10.30 am.png" },
        .{ .stored = "one two", .requested = "@one\xc2\xa0two" },
    };
    for (cases) |row| {
        const written = try env.writeFile(row.stored, "content", .{});
        try std.testing.expect(written == .value);
        var result = try read.execute(&env, .{ .path = row.requested }, .{});
        defer result.deinit(gpa);
        try std.testing.expect(result == .value);
        try std.testing.expectEqualStrings("content", result.value.text.?);
    }
}
