const std = @import("std");
const builtin = @import("builtin");
const adapter = @import("remote_env.zig");
const connection = @import("connection.zig");
const lazy = @import("lazy_connection.zig");
const watching = @import("../durable/watch.zig");
extern "kernel32" fn DefineDosDeviceW(u32, [*:0]const u16, ?[*:0]const u16) callconv(.winapi) i32;
extern "kernel32" fn QueryDosDeviceW(?[*:0]const u16, [*]u16, u32) callconv(.winapi) u32;
extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) u32;
// An unpredictable user-session device alias bounds the fixture's lexical
// ancestor subscriptions to its own temporary tree. It is neither a drive
// letter nor a broadcast mount; exact target matching preserves other routes.
const OwnedNamespace = struct {
    gpa: std.mem.Allocator,
    path: []u8,
    name: ?[:0]u16 = null,
    target: ?[:0]u16 = null,
    fn init(gpa: std.mem.Allocator, physical: []const u8) !OwnedNamespace {
        if (builtin.os.tag != .windows) return .{ .gpa = gpa, .path = try gpa.dupe(u8, physical) };
        const name = try std.fmt.allocPrint(gpa, "PI_ENV_WATCH_{d}_{s}", .{ GetCurrentProcessId(), std.fs.path.basename(physical) });
        defer gpa.free(name);
        const name_w = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, name);
        errdefer gpa.free(name_w);
        const target = try std.fmt.allocPrint(gpa, "\\??\\{s}", .{physical});
        defer gpa.free(target);
        const target_w = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, target);
        errdefer gpa.free(target_w);
        const path = try std.fmt.allocPrint(gpa, "\\\\.\\{s}\\", .{name});
        errdefer gpa.free(path);
        var query: [std.Io.Dir.max_path_bytes]u16 = undefined;
        if (QueryDosDeviceW(name_w, &query, query.len) != 0) return error.WatchNamespaceAlreadyOwned;
        if (DefineDosDeviceW(1 | 8, name_w, target_w) == 0) return error.WatchNamespaceCreationFailed;
        return .{ .gpa = gpa, .path = path, .name = name_w, .target = target_w };
    }
    fn deinit(self: *OwnedNamespace) void {
        if (builtin.os.tag == .windows) if (self.name) |name| {
            std.debug.assert(DefineDosDeviceW(1 | 2 | 4 | 8, name, self.target.?) != 0);
            var query: [std.Io.Dir.max_path_bytes]u16 = undefined;
            std.debug.assert(QueryDosDeviceW(name, &query, query.len) == 0);
            self.gpa.free(name);
            self.gpa.free(self.target.?);
        };
        self.gpa.free(self.path);
    }
};
const Capture = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    paths: std.ArrayList([]u8) = .empty,
    overflows: usize = 0,
    errors: usize = 0,
    fn deinit(self: *Capture) void {
        for (self.paths.items) |path| self.gpa.free(path);
        self.paths.deinit(self.gpa);
    }
    fn callback(raw: ?*anyopaque, change: watching.Change) !void {
        const self: *Capture = @ptrCast(@alignCast(raw.?));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        switch (change) {
            .paths => |paths| for (paths) |path| {
                const owned = try self.gpa.dupe(u8, path);
                errdefer self.gpa.free(owned);
                try self.paths.append(self.gpa, owned);
            },
            .overflow => self.overflows += 1,
            .@"error" => self.errors += 1,
        }
        // A throwing user callback never closes the subscription.
        return error.UserCallbackProof;
    }
    fn has(self: *Capture, path: []const u8) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (self.paths.items) |value| if (std.mem.eql(u8, value, path)) return true;
        return false;
    }
    fn count(self: *Capture) usize {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.paths.items.len;
    }
    fn clear(self: *Capture) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (self.paths.items) |path| self.gpa.free(path);
        self.paths.clearRetainingCapacity();
    }
    fn overflowCount(self: *Capture) usize {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.overflows;
    }
    fn wait(self: *Capture, path: []const u8) !void {
        const until = std.Io.Clock.awake.now(self.io).toMilliseconds() + 3000;
        while (std.Io.Clock.awake.now(self.io).toMilliseconds() < until) {
            if (self.has(path)) return;
            try self.io.sleep(.fromMilliseconds(10), .awake);
        }
        return error.WatchPathMissing;
    }
};
test "remote watcher proves real native events reads excluded paths recursive creation rename and post-close silence" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const program = environ.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    const client = try connection.Connection.start(gpa, io, &.{program}, 89);
    defer client.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "watched/sub");
    try tmp.dir.writeFile(io, .{ .sub_path = "watched/initial", .data = "initial" });
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &root_buffer);
    var env = try adapter.RemoteExecutionEnv.init(gpa, .{ .connection = .{ .native = client }, .id = "watch-proof", .cwd = root_buffer[0..length], .watch = .{ .mode = if (builtin.os.tag == .linux) .native else .polling, .pollIntervalMs = 20 } });
    defer env.deinit();
    var capture: Capture = .{ .gpa = gpa, .io = io };
    defer capture.deinit();
    const opened = try env.watch(&.{.{ .path = "watched", .recursive = true, .exclude = .{ .hidden = true, .names = &.{"ignored"} } }}, Capture.callback, &capture, .{});
    try std.testing.expect(opened == .value);
    const watcher = opened.value;
    defer watcher.deinit();
    try std.testing.expectEqual(if (builtin.os.tag == .linux) watching.Mode.native else watching.Mode.polling, watcher.mode.load(.acquire));
    const read = try env.readBinaryFile("watched/initial", .{});
    try std.testing.expect(read == .value);
    defer gpa.free(read.value);
    try io.sleep(.fromMilliseconds(150), .awake);
    try std.testing.expectEqual(@as(usize, 0), capture.count());
    try tmp.dir.writeFile(io, .{ .sub_path = "watched/.hidden", .data = "ignored" });
    try tmp.dir.writeFile(io, .{ .sub_path = "watched/ignored", .data = "ignored" });
    try tmp.dir.writeFile(io, .{ .sub_path = "sibling", .data = "unrelated" });
    try tmp.dir.writeFile(io, .{ .sub_path = "watched/sub/new-Ω🦊", .data = "visible" });
    const nested = try env.resolvePath("watched/sub/new-Ω🦊");
    defer gpa.free(nested);
    try capture.wait(nested);
    const hidden = try env.resolvePath("watched/.hidden");
    defer gpa.free(hidden);
    const ignored = try env.resolvePath("watched/ignored");
    defer gpa.free(ignored);
    const sibling = try env.resolvePath("sibling");
    defer gpa.free(sibling);
    try std.testing.expect(!capture.has(hidden) and !capture.has(ignored) and !capture.has(sibling));
    try tmp.dir.createDirPath(io, "watched/fresh/deep");
    try tmp.dir.writeFile(io, .{ .sub_path = "watched/fresh/deep/file", .data = "written-before-install" });
    const new_file = try env.resolvePath("watched/fresh/deep/file");
    defer gpa.free(new_file);
    try capture.wait(new_file);
    try tmp.dir.rename("watched", tmp.dir, "moved", io);
    const original = try env.resolvePath("watched");
    defer gpa.free(original);
    try capture.wait(original);
    watcher.close(.{});
    watcher.close(.{});
    const before = capture.count();
    try tmp.dir.createDirPath(io, "watched");
    try tmp.dir.writeFile(io, .{ .sub_path = "watched/after-close", .data = "silent" });
    try io.sleep(.fromMilliseconds(150), .awake);
    try std.testing.expectEqual(before, capture.count());
}
test "remote lazy watcher reconnects after actual owned daemon loss and reports uncertain coverage once" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const program = environ.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    const Prepare = struct {
        program: []const u8,
        attempts: usize = 0,
        fn start(raw: ?*anyopaque, allocator: std.mem.Allocator, _: std.Io) !lazy.Command {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.attempts += 1;
            return lazy.Command.init(allocator, &.{self.program});
        }
    };
    var preparation: Prepare = .{ .program = program };
    var client = lazy.Connection.init(gpa, io, Prepare.start, &preparation);
    defer client.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &root_buffer);
    var env = try adapter.RemoteExecutionEnv.init(gpa, .{ .connection = .{ .lazy = &client }, .id = "watch-reconnect", .cwd = root_buffer[0..length], .watch = .{ .mode = .polling, .pollIntervalMs = 20 } });
    defer env.deinit();
    var capture: Capture = .{ .gpa = gpa, .io = io };
    defer capture.deinit();
    const opened = try env.watch(&.{.{ .path = "created" }}, Capture.callback, &capture, .{});
    try std.testing.expect(opened == .value);
    const watcher = opened.value;
    defer watcher.deinit();
    const old_session = client.session;
    client.current.?.stop();
    const until = std.Io.Clock.awake.now(io).toMilliseconds() + 5000;
    while (capture.overflowCount() == 0 and std.Io.Clock.awake.now(io).toMilliseconds() < until) try io.sleep(.fromMilliseconds(10), .awake);
    try std.testing.expectEqual(@as(usize, 1), capture.overflowCount());
    try std.testing.expect(client.session != old_session);
    try tmp.dir.writeFile(io, .{ .sub_path = "created", .data = "after-reconnect" });
    const path = try env.resolvePath("created");
    defer gpa.free(path);
    try capture.wait(path);
    watcher.close(.{});
    try std.testing.expectEqual(@as(usize, 2), preparation.attempts);
}
fn allocationProbe(gpa: std.mem.Allocator, client: *connection.Connection, cwd: []const u8) !void {
    var env = try adapter.RemoteExecutionEnv.init(gpa, .{ .connection = .{ .native = client }, .id = "watch-allocation", .cwd = cwd, .watch = .{ .mode = .polling } });
    defer env.deinit();
    const Null = struct {
        fn callback(_: ?*anyopaque, _: watching.Change) !void {}
    };
    const result = try env.watch(&.{.{ .path = ".", .recursive = true, .exclude = .{ .names = &.{ "one", "other" } } }}, Null.callback, null, .{});
    if (result == .failure) {
        var failure = result.failure;
        defer failure.deinit(gpa);
        return error.UnexpectedWatchFailure;
    }
    result.value.deinit();
}
test "remote watch constructor releases every target ticket and thread at each induced allocation failure" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const program = environ.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    const client = try connection.Connection.start(gpa, io, &.{program}, 94);
    defer client.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &root_buffer);
    try std.testing.checkAllAllocationFailures(gpa, allocationProbe, .{ client, root_buffer[0..length] });
    try std.testing.expectEqual(@as(u32, 0), client.pending.count());
}

test "remote forced native watcher observes recursive UTF8 writes excludes reads and releases handles before ordinary RPC" {
    if (builtin.os.tag != .windows and builtin.os.tag != .linux and builtin.os.tag != .macos) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const program = environ.get("PI_TEST_ENV_NATIVE_WATCH_REFERENCE") orelse environ.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    const client = try connection.Connection.start(gpa, io, &.{program}, 113);
    defer client.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "watched");
    try tmp.dir.writeFile(io, .{ .sub_path = "watched/file", .data = "initial" });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    var namespace = try OwnedNamespace.init(gpa, buffer[0..length]);
    defer namespace.deinit();
    var env = try adapter.RemoteExecutionEnv.init(gpa, .{ .connection = .{ .native = client }, .id = "forced-native-watch", .cwd = namespace.path, .watch = .{ .mode = .native } });
    defer env.deinit();
    var capture: Capture = .{ .gpa = gpa, .io = io };
    defer capture.deinit();
    var opened = try env.watch(&.{ .{ .path = "watched", .recursive = true, .exclude = .{ .hidden = true, .names = &.{"ignored"} } }, .{ .path = "parent-observer-ready" } }, Capture.callback, &capture, .{});
    if (opened == .failure) {
        defer opened.failure.deinit(gpa);
        std.debug.print("Forced native watch failed: {s}\n", .{opened.failure.message});
        return error.ForcedNativeWatchFailed;
    }
    const watcher = opened.value;
    defer watcher.deinit();
    try std.testing.expectEqual(watching.Mode.native, watcher.mode.load(.acquire));
    // An observed file event acknowledges coverage and drains startup traffic
    // through the same debounce/publication path used by actual changes.
    try tmp.dir.writeFile(io, .{ .sub_path = "watched/observer-ready", .data = "acknowledge-initial-coverage" });
    const acknowledged = try env.resolvePath("watched/observer-ready");
    defer gpa.free(acknowledged);
    try capture.wait(acknowledged);
    try tmp.dir.writeFile(io, .{ .sub_path = "parent-observer-ready", .data = "acknowledge-ancestor-coverage" });
    const parent_acknowledged = try env.resolvePath("parent-observer-ready");
    defer gpa.free(parent_acknowledged);
    try capture.wait(parent_acknowledged);
    capture.clear();
    var read = try env.readBinaryFile("watched/file", .{});
    if (read == .failure) {
        defer read.failure.deinit(gpa);
        return error.NativeWatchReadFailed;
    }
    defer gpa.free(read.value);
    try io.sleep(.fromMilliseconds(150), .awake);
    if (capture.count() != 0) {
        capture.mutex.lockUncancelable(io);
        defer capture.mutex.unlock(io);
        for (capture.paths.items) |path| std.debug.print("Forced native read-period path: {s}\n", .{path});
        const diagnostic = try client.diagnosticSnapshot(gpa);
        defer gpa.free(diagnostic);
        std.debug.print("Owned native watch diagnostics: {s}\n", .{diagnostic});
    }
    try std.testing.expectEqual(@as(usize, 0), capture.count());
    try tmp.dir.writeFile(io, .{ .sub_path = "watched/.hidden", .data = "ignored" });
    try tmp.dir.writeFile(io, .{ .sub_path = "watched/ignored", .data = "ignored" });
    try tmp.dir.createDirPath(io, "watched/sub");
    try tmp.dir.writeFile(io, .{ .sub_path = "watched/sub/Ω🦊", .data = "created-before-child-watch" });
    const nested = try env.resolvePath("watched/sub/Ω🦊");
    defer gpa.free(nested);
    try capture.wait(nested);
    try io.sleep(.fromMilliseconds(100), .awake);
    try tmp.dir.writeFile(io, .{ .sub_path = "watched/sub/second", .data = "covered-by-child-watch" });
    const second = try env.resolvePath("watched/sub/second");
    defer gpa.free(second);
    try capture.wait(second);
    const hidden = try env.resolvePath("watched/.hidden");
    defer gpa.free(hidden);
    const ignored = try env.resolvePath("watched/ignored");
    defer gpa.free(ignored);
    try std.testing.expect(!capture.has(hidden) and !capture.has(ignored));
    try std.testing.expectEqual(watching.Mode.native, watcher.mode.load(.acquire));
    try std.testing.expectEqual(@as(usize, 0), capture.overflowCount());
    watcher.close(.{});
    watcher.close(.{});
    // Close settles owned directory requests before releasing their buffers.
    try tmp.dir.rename("watched", tmp.dir, "moved", io);
    var exists = try env.exists("moved/sub/second", .{});
    if (exists == .failure) {
        std.debug.print("Post-close alias RPC failure {s}: {s}, cwd={s}\n", .{ @tagName(exists.failure.code), exists.failure.message, env.cwd });
        defer exists.failure.deinit(gpa);
        return error.NativeWatchCloseRpcFailed;
    }
    try std.testing.expect(exists.value);
    const count = capture.count();
    try tmp.dir.writeFile(io, .{ .sub_path = "moved/sub/second", .data = "after-close" });
    try io.sleep(.fromMilliseconds(100), .awake);
    try std.testing.expectEqual(count, capture.count());
    try std.testing.expectEqual(@as(usize, 0), capture.errors);
    try std.testing.expectEqual(@as(u32, 0), client.pending.count());
}
test "remote watch close keeps the same daemon alive for ordinary RPC and repeated subscriptions" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const program = environ.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    const client = try connection.Connection.start(gpa, io, &.{program}, 96);
    defer client.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &root_buffer);
    var env = try adapter.RemoteExecutionEnv.init(gpa, .{ .connection = .{ .native = client }, .id = "watch-close-lifetime", .cwd = root_buffer[0..length], .watch = .{ .mode = .polling, .pollIntervalMs = 20 } });
    defer env.deinit();
    const Callback = struct {
        fn accept(_: ?*anyopaque, _: watching.Change) !void {}
    };
    for (0..12) |_| {
        const opened = try env.watch(&.{.{ .path = "." }}, Callback.accept, null, .{});
        try std.testing.expect(opened == .value);
        opened.value.deinit();
        // Do not tear down the transport: wait past daemon task retirement,
        // then prove that the very same session still handles ordinary I/O.
        try io.sleep(.fromMilliseconds(10), .awake);
        var absent = try env.exists("must-stay-absent", .{});
        if (absent == .failure) {
            defer absent.failure.deinit(gpa);
            const diagnostic = try client.diagnosticSnapshot(gpa);
            defer gpa.free(diagnostic);
            std.debug.print("After-close RPC failed: {s}; owned daemon diagnostics: {s}\n", .{ absent.failure.message, diagnostic });
            return error.WatchCloseKilledDaemon;
        }
        try std.testing.expect(absent == .value and !absent.value);
        try std.testing.expectEqual(@as(u64, 96), client.session);
    }
    try std.testing.expectEqual(@as(u32, 0), client.pending.count());
}
