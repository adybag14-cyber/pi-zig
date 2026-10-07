//! Per-server MCP state ownership and legacy migration under a native file lock.
const std = @import("std");
const json = @import("protocol.zig").json;
const oauth = @import("oauth.zig");
const urls = @import("../extensions/url_parser.zig");
const permissions = @import("../file_permissions.zig");
const lock = @import("oauth_lock.zig");
pub const Store = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    path: []u8,
    pub fn init(gpa: std.mem.Allocator, io: std.Io, agent_dir: []const u8) !Store {
        return .{ .gpa = gpa, .io = io, .path = try std.fs.path.join(gpa, &.{ agent_dir, "mcp-auth.json" }) };
    }
    pub fn deinit(self: *Store) void {
        self.gpa.free(self.path);
    }
    pub fn refreshLease(self: Store, name: []const u8, server_url: []const u8, abort_flag: ?*bool) !*lock.Lease {
        var record = try urls.parse(self.gpa, server_url, null);
        defer record.deinit(self.gpa);
        const normalized = try urls.serialize(self.gpa, record);
        defer self.gpa.free(normalized);
        const key = try oauth.credentialKeyForNormalizedUrl(self.gpa, name, normalized);
        defer self.gpa.free(key);
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(key, &digest, .{});
        const hex = std.fmt.bytesToHex(digest, .lower);
        const filename = try std.fmt.allocPrint(self.gpa, "mcp-auth-refresh-{s}", .{hex[0..16]});
        defer self.gpa.free(filename);
        const path = try std.fs.path.join(self.gpa, &.{ std.fs.path.dirname(self.path) orelse ".", filename });
        defer self.gpa.free(path);
        return lock.Lease.acquire(self.gpa, self.io, path, .{}, abort_flag);
    }
    const LockedFile = struct {
        file: std.Io.File,
        lease: *lock.Lease,
        fn close(self: LockedFile, io: std.Io) void {
            self.file.close(io);
            self.lease.close(io);
        }
    };
    fn open(self: Store, abort_flag: ?*bool) !LockedFile {
        if (std.fs.path.dirname(self.path)) |parent| try std.Io.Dir.cwd().createDirPath(self.io, parent);
        const lease = try lock.Lease.acquire(self.gpa, self.io, self.path, .{ .stale_ms = 10_000, .wait_ms = 10_000, .heartbeat_ms = 2_500 }, abort_flag);
        errdefer lease.close(self.io);
        const file = try std.Io.Dir.cwd().createFile(self.io, self.path, .{ .read = true, .truncate = false, .permissions = permissions.privateFile() });
        errdefer file.close(self.io);
        while (true) {
            if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.Canceled;
            if (try file.tryLock(self.io, .exclusive)) break;
            try self.io.sleep(.fromMilliseconds(10), .awake);
        }
        return .{ .file = file, .lease = lease };
    }
    fn read(self: Store, file: std.Io.File) !json.Owned {
        const length = try file.length(self.io);
        if (length > 4 * 1024 * 1024) return error.McpOAuthStateTooLarge;
        if (length == 0) return json.Owned.parse(self.gpa, "{}");
        const bytes = try self.gpa.alloc(u8, @intCast(length));
        defer self.gpa.free(bytes);
        if (try file.readPositionalAll(self.io, bytes, 0) != bytes.len) return error.UnexpectedEndOfFile;
        if (std.mem.trim(u8, bytes, " \t\r\n").len == 0) return json.Owned.parse(self.gpa, "{}");
        var result = try json.Owned.parse(self.gpa, bytes);
        errdefer result.deinit();
        if (result.value != .object) result.value = .{ .object = .empty };
        return result;
    }
    fn write(self: Store, file: std.Io.File, root: json.Value) !void {
        const bytes = try json.stringify(self.gpa, root);
        defer self.gpa.free(bytes);
        try file.setLength(self.io, 0);
        try file.writePositionalAll(self.io, bytes, 0);
        try file.sync(self.io);
    }
    pub fn load(self: Store, name: []const u8, server_url: []const u8, abort_flag: ?*bool) !?json.Owned {
        var record = try urls.parse(self.gpa, server_url, null);
        defer record.deinit(self.gpa);
        const normalized = try urls.serialize(self.gpa, record);
        defer self.gpa.free(normalized);
        const key = try oauth.credentialKeyForNormalizedUrl(self.gpa, name, normalized);
        defer self.gpa.free(key);
        const file = try self.open(abort_flag);
        defer file.close(self.io);
        var states = try self.read(file.file);
        defer states.deinit();
        var value = states.value.object.get(key);
        if (value == null) if (states.value.object.get(normalized)) |legacy| {
            try states.value.object.put(states.arena.allocator(), try states.arena.allocator().dupe(u8, key), legacy);
            _ = states.value.object.orderedRemove(normalized);
            try self.write(file.file, states.value);
            value = legacy;
        };
        const state = value orelse return null;
        if (state != .object) return null;
        const owned_url = state.object.get("serverUrl") orelse return null;
        if (owned_url != .string or !std.mem.eql(u8, owned_url.string, normalized)) return null;
        var result = try json.Owned.empty(self.gpa);
        errdefer result.deinit();
        result.value = try json.clone(result.arena.allocator(), state);
        return result;
    }
    pub fn save(self: Store, name: []const u8, server_url: []const u8, state: json.Value, abort_flag: ?*bool) !void {
        var record = try urls.parse(self.gpa, server_url, null);
        defer record.deinit(self.gpa);
        const normalized = try urls.serialize(self.gpa, record);
        defer self.gpa.free(normalized);
        const key = try oauth.credentialKeyForNormalizedUrl(self.gpa, name, normalized);
        defer self.gpa.free(key);
        if (state != .object) return error.InvalidMcpOAuthState;
        const file = try self.open(abort_flag);
        defer file.close(self.io);
        var states = try self.read(file.file);
        defer states.deinit();
        const a = states.arena.allocator();
        var owned = try json.clone(a, state);
        try owned.object.put(a, "serverUrl", .{ .string = try a.dupe(u8, normalized) });
        try states.value.object.put(a, try a.dupe(u8, key), owned);
        if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.Canceled;
        try self.write(file.file, states.value);
    }
    /// Observe a sign-in from another process without taking over its legacy key.
    pub fn tokens(self: Store, name: []const u8, server_url: []const u8, abort_flag: ?*bool) !?json.Owned {
        var record = try urls.parse(self.gpa, server_url, null);
        defer record.deinit(self.gpa);
        const normalized = try urls.serialize(self.gpa, record);
        defer self.gpa.free(normalized);
        const key = try oauth.credentialKeyForNormalizedUrl(self.gpa, name, normalized);
        defer self.gpa.free(key);
        const file = try self.open(abort_flag);
        defer file.close(self.io);
        var states = try self.read(file.file);
        defer states.deinit();
        const state = states.value.object.get(key) orelse states.value.object.get(normalized) orelse return null;
        const value = json.get(state, "tokens") orelse return null;
        var result = try json.Owned.empty(self.gpa);
        errdefer result.deinit();
        result.value = try json.clone(result.arena.allocator(), value);
        return result;
    }
    pub fn remove(self: Store, name: []const u8, server_url: []const u8, abort_flag: ?*bool) !bool {
        var record = try urls.parse(self.gpa, server_url, null);
        defer record.deinit(self.gpa);
        const normalized = try urls.serialize(self.gpa, record);
        defer self.gpa.free(normalized);
        const key = try oauth.credentialKeyForNormalizedUrl(self.gpa, name, normalized);
        defer self.gpa.free(key);
        const file = try self.open(abort_flag);
        defer file.close(self.io);
        var states = try self.read(file.file);
        defer states.deinit();
        const stored = if (states.value.object.contains(key)) key else if (states.value.object.contains(normalized)) normalized else return false;
        _ = states.value.object.orderedRemove(stored);
        try self.write(file.file, states.value);
        return true;
    }
};

test "mcp.runtime OAuth store migrates legacy URL once and separates same URL server accounts" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &buffer);
    var store = try Store.init(gpa, io, buffer[0..count]);
    defer store.deinit();
    var capture = try json.Owned.parse(gpa, @embedFile("fixtures/oauth-store-7fb.json"));
    defer capture.deinit();
    try scratch.dir.writeFile(io, .{ .sub_path = "mcp-auth.json", .data = "{\"https://service.example/mcp\":{\"serverUrl\":\"https://service.example/mcp\",\"tokens\":{\"access_token\":\"legacy\"}}}" });
    var first = (try store.load("first", "https://service.example/mcp", null)).?;
    defer first.deinit();
    try std.testing.expectEqualStrings("legacy", first.value.object.get("tokens").?.object.get("access_token").?.string);
    try std.testing.expect(json.equal(capture.value.object.get("first").?, first.value));
    try std.testing.expect(try store.load("second", "https://service.example/mcp", null) == null);
    var state = try json.Owned.parse(gpa, "{\"tokens\":{\"access_token\":\"second\"},\"extension\":true}");
    defer state.deinit();
    try store.save("second", "https://service.example/mcp", state.value, null);
    var second = (try store.load("second", "https://service.example/mcp", null)).?;
    defer second.deinit();
    try std.testing.expectEqualStrings("second", second.value.object.get("tokens").?.object.get("access_token").?.string);
    try std.testing.expect(second.value.object.get("extension").?.bool);
    try std.testing.expect(json.equal(capture.value.object.get("second").?, second.value));
    var reloaded = (try store.load("first", "https://service.example/mcp", null)).?;
    defer reloaded.deinit();
    try std.testing.expectEqualStrings("legacy", reloaded.value.object.get("tokens").?.object.get("access_token").?.string);
    const persisted_bytes = try scratch.dir.readFileAlloc(io, "mcp-auth.json", gpa, .limited(1024 * 1024));
    defer gpa.free(persisted_bytes);
    var persisted = try json.Owned.parse(gpa, persisted_bytes);
    defer persisted.deinit();
    try std.testing.expect(json.equal(capture.value.object.get("persisted").?, persisted.value));
}

test "mcp.runtime OAuth store waiting file lock observes cancellation without changing persisted state" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &buffer);
    var store = try Store.init(gpa, io, buffer[0..count]);
    defer store.deinit();
    const held = try std.Io.Dir.cwd().createFile(io, store.path, .{ .read = true, .truncate = false, .lock = .exclusive });
    defer held.close(io);
    var flag = true;
    try std.testing.expectError(error.Canceled, store.load("server", "https://service.example/mcp", &flag));
    try std.testing.expectEqual(@as(u64, 0), try held.length(io));
}

test "mcp.runtime OAuth refresh leases separate accounts and reject cancelled contended rotation" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &buffer);
    var store = try Store.init(gpa, io, buffer[0..count]);
    defer store.deinit();
    const first = try store.refreshLease("first", "https://service.example/mcp", null);
    defer first.close(io);
    const second = try store.refreshLease("second", "https://service.example/mcp", null);
    defer second.close(io);
    var cancelled = true;
    try std.testing.expectError(error.Canceled, store.refreshLease("first", "https://service.example/mcp", &cancelled));
}

test "mcp.runtime OAuth refresh waiting contender exits promptly on live cancellation" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &buffer);
    var store = try Store.init(gpa, io, buffer[0..count]);
    defer store.deinit();
    const held = try store.refreshLease("server", "https://service.example/mcp", null);
    defer held.close(io);
    var flag = false;
    const Waiter = struct {
        store: Store,
        flag: *bool,
        entered: std.Io.Event = .unset,
        fn run(self: *@This()) anyerror!*lock.Lease {
            self.entered.set(self.store.io);
            return self.store.refreshLease("server", "https://service.example/mcp", self.flag);
        }
    };
    var waiter: Waiter = .{ .store = store, .flag = &flag };
    var future = try io.concurrent(Waiter.run, .{&waiter});
    var joined = false;
    defer {
        @atomicStore(bool, &flag, true, .release);
        if (!joined) if (future.cancel(io)) |file| file.close(io) else |_| {};
    }
    try waiter.entered.wait(io);
    try io.sleep(.fromMilliseconds(150), .awake);
    const started = std.Io.Clock.awake.now(io).toMilliseconds();
    @atomicStore(bool, &flag, true, .release);
    const result = future.await(io);
    joined = true;
    try std.testing.expectError(error.Canceled, result);
    try std.testing.expect(std.Io.Clock.awake.now(io).toMilliseconds() - started < 1_000);
}

test "mcp.runtime OAuth token observation leaves legacy ownership intact and removal chooses canonical first" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &buffer);
    var store = try Store.init(gpa, io, buffer[0..count]);
    defer store.deinit();
    const initial = "{\"https://service.example/mcp\":{\"serverUrl\":\"https://service.example/mcp\",\"tokens\":{\"access_token\":\"legacy\"}}}";
    try scratch.dir.writeFile(io, .{ .sub_path = "mcp-auth.json", .data = initial });
    var observed = (try store.tokens("server", "https://service.example/mcp", null)).?;
    defer observed.deinit();
    try std.testing.expectEqualStrings("legacy", try @import("protocol.zig").text(observed.value, "access_token"));
    const unchanged = try scratch.dir.readFileAlloc(io, "mcp-auth.json", gpa, .limited(4096));
    defer gpa.free(unchanged);
    try std.testing.expectEqualStrings(initial, unchanged);
    var state = try json.Owned.parse(gpa, "{\"tokens\":{\"access_token\":\"current\"}}");
    defer state.deinit();
    try store.save("server", "https://service.example/mcp", state.value, null);
    try std.testing.expect(try store.remove("server", "https://service.example/mcp", null));
    var legacy = (try store.tokens("server", "https://service.example/mcp", null)).?;
    defer legacy.deinit();
    try std.testing.expectEqualStrings("legacy", try @import("protocol.zig").text(legacy.value, "access_token"));
    try std.testing.expect(try store.remove("server", "https://service.example/mcp", null));
    try std.testing.expect(!try store.remove("server", "https://service.example/mcp", null));
    for ([_][]const u8{ "[]", "null", "false", " \n " }) |content| {
        try scratch.dir.writeFile(io, .{ .sub_path = "mcp-auth.json", .data = content });
        try std.testing.expect(try store.tokens("server", "https://service.example/mcp", null) == null);
    }
}
