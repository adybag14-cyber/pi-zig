const std = @import("std");
const capability = @import("durable/env_capability.zig");
const local = @import("durable/execution_env.zig");
const remote = @import("env/remote_env.zig");
const connection = @import("env/connection.zig");
const tools = @import("durable/tools.zig");
const registry = @import("durable/harness/registry.zig");
const invoke = @import("durable/harness/invoke.zig");
const builtins = @import("durable/harness/builtins.zig");
const types = @import("durable/types.zig");
const watching = @import("durable/watch.zig");
fn exercise(provider: anytype, cwd: []const u8) !void {
    const gpa = std.testing.allocator;
    var env = capability.ExecutionEnv.from(provider);
    try std.testing.expectEqualStrings(cwd, env.cwd());
    try std.testing.expect((try env.createDir("capability", .{}, .{})) == .value);
    try std.testing.expect((try env.writeFile("capability/retained", "\xef\xbb\xbfA\r\nΩ🦊\nlast", .{})) == .value);
    const opened = try env.openBinaryReader("capability/retained", .{}, .{});
    try std.testing.expect(opened == .value);
    var reader = opened.value;
    defer reader.deinit();
    try std.testing.expect((try env.renameFile("capability/retained", "capability/moved", .{})) == .value);
    try std.testing.expect((try env.writeFile("capability/retained", "replacement", .{})) == .value);
    const text = try reader.read(0, 100, .{});
    try std.testing.expect(text == .value);
    defer gpa.free(text.value);
    try std.testing.expectEqualStrings("\xef\xbb\xbfA\r\nΩ🦊\nlast", text.value);
    const scanned = try reader.scanLines(.{ .startLine = 0 }, .{});
    try std.testing.expect(scanned == .value);
    try std.testing.expectEqual(@as(u64, 2), scanned.value.newlines);
    // DrvFS/9P may expose the replacement through both path names while the
    // retained descriptor still reads the original, as the original Node env
    // does. Keep descriptor identity proof above and use a separate file for
    // path-based bounded/line selection proof on every filesystem.
    try std.testing.expect((try env.writeFile("capability/selection", "\xef\xbb\xbfA\r\nΩ🦊\nlast", .{})) == .value);
    var result = try tools.read.execute(&env, .{ .path = "capability/selection", .offset = 2, .limit = 1 }, .{});
    defer result.deinit(gpa);
    try std.testing.expect(result == .value);
    try std.testing.expectEqualStrings("Ω🦊", result.value.text.?);
    const lines = try env.openTextLineReader("capability/selection", .{});
    try std.testing.expect(lines == .value);
    var line_reader = lines.value;
    defer line_reader.deinit();
    var line = try line_reader.readLine(.{});
    try std.testing.expect(line == .value and line.value != null);
    defer line.value.?.deinit(gpa);
    try std.testing.expectEqualStrings("A\r", line.value.?.text);
    const directory = try env.openDirReader("capability", .{});
    try std.testing.expect(directory == .value);
    var dir = directory.value;
    defer dir.deinit();
    var page = try dir.next(20, .{});
    try std.testing.expect(page == .value and page.value.entries.len == 3);
    defer page.value.deinit(gpa);
    const Watch = struct {
        fn callback(_: ?*anyopaque, _: watching.Change) !void {}
    };
    const subscribed = try env.watch(&.{.{ .path = "capability" }}, Watch.callback, null, .{});
    try std.testing.expect(subscribed == .value);
    const watcher = subscribed.value;
    defer watcher.deinit();
    _ = watcher.mode();
    watcher.close(.{});
    watcher.close(.{});
    var owner = try registry.Registry.init(gpa, env.fs.io);
    defer owner.deinit();
    const bindings = try builtins.Bindings.create(gpa, &env);
    try bindings.install(&owner);
    bindings.drop();
    const snapshot = owner.snapshot();
    defer snapshot.release();
    const rows = [_]struct { name: []const u8, args: []const u8, expected: []const u8 }{
        .{ .name = "write", .args = "{\"path\":\"capability/tool\",\"content\":\"first\\nsecond\"}", .expected = "Successfully wrote to capability/tool" },
        .{ .name = "edit", .args = "{\"path\":\"capability/tool\",\"oldText\":\"second\",\"newText\":\"SECOND\"}", .expected = "Successfully replaced 1 block(s) in capability/tool." },
        .{ .name = "read", .args = "{\"path\":\"capability/tool\",\"offset\":2}", .expected = "SECOND" },
        .{ .name = "bash", .args = "{\"command\":\"printf 'capability-output'\"}", .expected = "capability-output" },
    };
    for (rows) |row| {
        var args = try registry.json.Owned.parse(gpa, row.args);
        defer args.deinit();
        var invoked = try invoke.invoke(gpa, snapshot, row.name, args.value, .{}, .{});
        defer invoked.deinit();
        if (registry.json.get(invoked.value.value, "isError")) |failure| {
            if (failure.bool) {
                const diagnostic = try std.json.Stringify.valueAlloc(gpa, invoked.value.value, .{});
                defer gpa.free(diagnostic);
                std.debug.print("Capability Harness {s} failed: {s}\n", .{ row.name, diagnostic });
                if (@hasField(@typeInfo(@TypeOf(provider)).pointer.child, "connection")) {
                    const client = provider.connection.native;
                    const log = try client.diagnosticSnapshot(gpa);
                    defer gpa.free(log);
                    std.debug.print("Owned remote daemon diagnostics: {s}\n", .{log});
                }
            }
            try std.testing.expect(!failure.bool);
        }
        const content = try registry.json.required(invoked.value.value, "content");
        try std.testing.expectEqualStrings(row.expected, try registry.json.asString(try registry.json.required(content.array.items[0], "text")));
    }
    const namespace = env.id();
    try env.setCwd("capability");
    try std.testing.expectEqualStrings(namespace, env.id());
    const relative = try env.readTextFile("tool", .{});
    try std.testing.expect(relative == .value);
    defer gpa.free(relative.value);
    try std.testing.expectEqualStrings("first\nSECOND", relative.value);
    try env.setCwd(cwd);
}
test "env capability local and remote share complete durable reader watcher and retained Harness bindings" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const program = environ.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    var local_env = try local.ExecutionEnv.init(gpa, io, .{ .cwd = buffer[0..length], .environ = &environ, .temp_dir = buffer[0..length], .watch = .{ .mode = .polling, .pollIntervalMs = 20 } });
    defer local_env.deinit();
    try exercise(&local_env, buffer[0..length]);
    try std.testing.expect((try local_env.remove("capability", .{ .recursive = true }, .{})) == .value);
    const client = try connection.Connection.start(gpa, io, &.{program}, 99);
    defer client.deinit();
    var remote_env = try remote.RemoteExecutionEnv.init(gpa, .{ .connection = .{ .native = client }, .id = "pi-env:capability", .cwd = buffer[0..length], .watch = .{ .mode = .polling, .pollIntervalMs = 20 } });
    defer remote_env.deinit();
    try exercise(&remote_env, buffer[0..length]);
    var fs = capability.FileSystem.from(&remote_env);
    try std.testing.expectEqualStrings("pi-env:capability", fs.id());
    var absent = try fs.readBinaryFile("absent", .{});
    try std.testing.expect(absent == .failure);
    defer absent.failure.deinit(gpa);
    try std.testing.expectEqual(types.FileErrorCode.not_found, absent.failure.code);
    try std.testing.expect(absent.failure.message_owned);
}
fn capabilityAllocation(gpa: std.mem.Allocator, client: *connection.Connection, cwd: []const u8) !void {
    var owner = try remote.RemoteExecutionEnv.init(gpa, .{ .connection = .{ .native = client }, .id = "allocation-capability", .cwd = cwd, .watch = .{ .mode = .polling } });
    defer owner.deinit();
    var env = capability.ExecutionEnv.from(&owner);
    const binary = try env.openBinaryReader("input", .{}, .{});
    if (binary == .failure) {
        var failure = binary.failure;
        defer failure.deinit(gpa);
        return error.UnexpectedCapabilityFailure;
    }
    var reader = binary.value;
    defer reader.deinit();
    const line = try env.openTextLineReader("input", .{});
    if (line == .failure) {
        var failure = line.failure;
        defer failure.deinit(gpa);
        return error.UnexpectedCapabilityFailure;
    }
    var line_reader = line.value;
    defer line_reader.deinit();
    const directory = try env.openDirReader(".", .{});
    if (directory == .failure) {
        var failure = directory.failure;
        defer failure.deinit(gpa);
        return error.UnexpectedCapabilityFailure;
    }
    var dir = directory.value;
    defer dir.deinit();
    const Callback = struct {
        fn accept(_: ?*anyopaque, _: watching.Change) !void {}
    };
    const watched = try env.watch(&.{.{ .path = "input" }}, Callback.accept, null, .{});
    if (watched == .failure) {
        var failure = watched.failure;
        defer failure.deinit(gpa);
        return error.UnexpectedCapabilityFailure;
    }
    watched.value.deinit();
}
test "env capability every induced box and provider allocation failure releases actual remote handles and subscriptions" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const program = environ.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    const client = try connection.Connection.start(gpa, io, &.{program}, 101);
    defer client.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "input", .data = "allocation-resource" });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    try std.testing.checkAllAllocationFailures(gpa, capabilityAllocation, .{ client, buffer[0..length] });
    try std.testing.expectEqual(@as(u32, 0), client.pending.count());
    var hello = try client.begin(.{ .op = "hello", .protocol = 1 }, "", 101);
    defer hello.deinit();
    var alive = try hello.next(2000);
    defer alive.deinit();
    try std.testing.expectEqual(@as(i64, 1), alive.json.value.object.get("protocol").?.integer);
}
