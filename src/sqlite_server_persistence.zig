//! Canonical SQLite persistence adapter for the native Pi protocol server.
//!
//! The server keeps active runtimes in memory. This adapter persists durable,
//! append-only snapshots into the canonical session repository and restores
//! them on startup. Writer leases fence concurrent servers without adding a
//! SQLite dependency to the ordinary `pi` executable.
const std = @import("std");
const Io = std.Io;
const pi_zig = @import("pi_zig");
const repository_mod = pi_zig.storage.sqlite.repository;
const types = pi_zig.storage.sqlite.types;
const session_store = pi_zig.server.session_store;
const agent_session = pi_zig.agent.session;

pub const SNAPSHOT_CUSTOM_TYPE = "pi.server.snapshot";
pub const SNAPSHOT_VERSION: i64 = 1;
pub const DEFAULT_LEASE_TTL_MS: i64 = 60_000;

pub const Error = error{
    SessionLocked,
    InvalidSnapshot,
    SnapshotIdentityMismatch,
};

pub const ImportReport = struct {
    loaded: usize = 0,
    imported: usize = 0,
    unchanged: usize = 0,
};

pub const Adapter = struct {
    gpa: std.mem.Allocator,
    io: Io,
    repo: repository_mod.Repository,
    owner_id: []u8,
    lease_ttl_ms: i64,
    leases: std.StringHashMap(types.WriterLease),

    pub fn init(gpa: std.mem.Allocator, io: Io, path: []const u8) !Adapter {
        return initWithLeaseTtl(gpa, io, path, DEFAULT_LEASE_TTL_MS);
    }

    pub fn initWithLeaseTtl(gpa: std.mem.Allocator, io: Io, path: []const u8, lease_ttl_ms: i64) !Adapter {
        if (lease_ttl_ms <= 0) return error.InvalidLeaseTtl;
        var repo = try repository_mod.Repository.open(gpa, io, path);
        errdefer repo.deinit();
        var random: [16]u8 = undefined;
        try std.Io.randomSecure(io, &random);
        const hex = std.fmt.bytesToHex(random, .lower);
        const owner_id = try std.fmt.allocPrint(gpa, "pi-zig-server-{s}", .{hex});
        return .{
            .gpa = gpa,
            .io = io,
            .repo = repo,
            .owner_id = owner_id,
            .lease_ttl_ms = lease_ttl_ms,
            .leases = std.StringHashMap(types.WriterLease).init(gpa),
        };
    }

    pub fn deinit(self: *Adapter) void {
        var iterator = self.leases.iterator();
        while (iterator.next()) |entry| {
            _ = self.repo.releaseWriterLease(entry.value_ptr) catch false;
            entry.value_ptr.deinit(self.gpa);
        }
        self.leases.deinit();
        self.repo.deinit();
        self.gpa.free(self.owner_id);
        self.* = undefined;
    }

    pub fn backend(self: *Adapter) session_store.PersistenceBackend {
        return .{
            .context = self,
            .load_all_fn = loadAllOpaque,
            .save_session_fn = saveOpaque,
            .claim_session_fn = claimOpaque,
            .release_session_fn = releaseOpaque,
        };
    }

    fn loadAllOpaque(context: *anyopaque, store: *session_store.SessionStore, gpa: std.mem.Allocator, io: Io) !usize {
        const self: *Adapter = @ptrCast(@alignCast(context));
        _ = gpa;
        _ = io;
        return self.loadAll(store);
    }

    fn saveOpaque(context: *anyopaque, gpa: std.mem.Allocator, io: Io, session: *const session_store.Session) !void {
        const self: *Adapter = @ptrCast(@alignCast(context));
        _ = gpa;
        _ = io;
        return self.saveSession(session);
    }

    fn claimOpaque(context: *anyopaque, session_id: []const u8) !void {
        const self: *Adapter = @ptrCast(@alignCast(context));
        _ = try self.ensureLease(session_id);
    }

    fn releaseOpaque(context: *anyopaque, session_id: []const u8) void {
        const self: *Adapter = @ptrCast(@alignCast(context));
        self.releaseSession(session_id);
    }

    fn nowMs(self: *Adapter) i64 {
        return @max(std.Io.Clock.real.now(self.io).toMilliseconds(), 1_720_000_000_000);
    }

    fn ensureLease(self: *Adapter, session_id: []const u8) !*types.WriterLease {
        const now = self.nowMs();
        if (self.leases.getPtr(session_id)) |lease| {
            // Renew in the final third of the lease. Frequent token/progress
            // events therefore cost only an in-memory hash lookup.
            const renew_at = lease.expires_at_ms - @divTrunc(self.lease_ttl_ms, 3);
            if (now < renew_at) return lease;
            if (try self.repo.renewWriterLease(lease, now, self.lease_ttl_ms)) return lease;
            const removed = self.leases.fetchRemove(session_id).?;
            var stale = removed.value;
            stale.deinit(self.gpa);
        }

        var claim = (try self.repo.acquireWriterLease(session_id, self.owner_id, now, self.lease_ttl_ms)) orelse return Error.SessionLocked;
        errdefer {
            _ = self.repo.releaseWriterLease(&claim) catch false;
            claim.deinit(self.gpa);
        }
        const key = claim.session_id;
        try self.leases.put(key, claim);
        return self.leases.getPtr(session_id).?;
    }

    pub fn releaseSession(self: *Adapter, session_id: []const u8) void {
        const removed = self.leases.fetchRemove(session_id) orelse return;
        var lease = removed.value;
        _ = self.repo.releaseWriterLease(&lease) catch false;
        lease.deinit(self.gpa);
    }

    fn ensureRepositorySession(self: *Adapter, session: *const session_store.Session) !void {
        var existing = self.repo.getSession(session.id) catch |err| switch (err) {
            error.SessionNotFound => null,
            else => return err,
        };
        if (existing) |*metadata| {
            metadata.deinit(self.gpa);
            return;
        }

        var metadata = self.repo.createSession(.{
            .id = session.id,
            .created_at_ms = @intCast(session.created_at),
            .cwd = session.cwd,
            .metadata_json = "{\"kind\":\"pi-server-session\",\"version\":1}",
        }) catch |err| switch (err) {
            error.SessionAlreadyExists => return,
            else => return err,
        };
        metadata.deinit(self.gpa);
    }

    pub fn saveSession(self: *Adapter, session: *const session_store.Session) !void {
        try self.ensureRepositorySession(session);
        const lease = try self.ensureLease(session.id);
        const payload = try encodeSnapshot(self.gpa, session);
        defer self.gpa.free(payload);

        const previous = try self.repo.findEntries(session.id, .{
            .custom_type = SNAPSHOT_CUSTOM_TYPE,
            .order = .newest_first,
            .limit = 1,
        });
        defer freeEntries(self.gpa, previous);
        if (previous.len > 0 and std.mem.eql(u8, previous[0].payload_json, payload)) return;

        const current_name = try self.repo.getName(session.id);
        defer if (current_name) |value| self.gpa.free(value);
        const wanted_name: ?[]const u8 = if (session.name) |value| value else null;
        if (!optionalTextEqual(current_name, wanted_name)) {
            try self.repo.setName(session.id, wanted_name, lease);
        }

        var entry = try self.repo.appendEntry(session.id, "main", .{
            .entry_type = .custom,
            .timestamp_ms = @intCast(session.updated_at),
            .payload_json = payload,
            .custom_type = SNAPSHOT_CUSTOM_TYPE,
        }, lease);
        entry.deinit(self.gpa);
    }

    pub fn loadAll(self: *Adapter, store: *session_store.SessionStore) !usize {
        const metadata = try self.repo.listSessions(null);
        defer {
            for (metadata) |*item| item.deinit(self.gpa);
            self.gpa.free(metadata);
        }
        var loaded: usize = 0;
        for (metadata) |item| {
            if (store.find(item.id) != null) continue;
            const entries = self.repo.findEntries(item.id, .{
                .custom_type = SNAPSHOT_CUSTOM_TYPE,
                .order = .newest_first,
                .limit = 1,
            }) catch continue;
            defer freeEntries(self.gpa, entries);
            if (entries.len == 0) continue;
            const restored = decodeSnapshot(self.gpa, entries[0].payload_json) catch continue;
            if (!std.mem.eql(u8, restored.id, item.id)) {
                restored.deinit(self.gpa);
                continue;
            }
            try store.sessions.append(self.gpa, restored);
            loaded += 1;
            if (restored.updated_at > store.logical_clock) store.logical_clock = restored.updated_at;
        }
        return loaded;
    }

    /// Imports the existing JSON-file server backend into the canonical SQLite
    /// repository. Re-running is idempotent because identical latest snapshots
    /// are detected before an append.
    pub fn importJsonDirectory(self: *Adapter, dir_path: []const u8) !ImportReport {
        var source: session_store.SessionStore = .{};
        defer source.deinit(self.gpa);
        var report = ImportReport{};
        report.loaded = try session_store.loadAll(&source, self.gpa, self.io, dir_path);
        for (source.sessions.items) |session| {
            const payload = try encodeSnapshot(self.gpa, session);
            defer self.gpa.free(payload);
            try self.ensureRepositorySession(session);
            const previous = try self.repo.findEntries(session.id, .{
                .custom_type = SNAPSHOT_CUSTOM_TYPE,
                .order = .newest_first,
                .limit = 1,
            });
            defer freeEntries(self.gpa, previous);
            if (previous.len > 0 and std.mem.eql(u8, previous[0].payload_json, payload)) {
                report.unchanged += 1;
                continue;
            }
            try self.saveSession(session);
            report.imported += 1;
        }
        return report;
    }
};

fn optionalTextEqual(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}

fn freeEntries(gpa: std.mem.Allocator, entries: []types.Entry) void {
    for (entries) |*entry| entry.deinit(gpa);
    gpa.free(entries);
}

fn encodeSnapshot(gpa: std.mem.Allocator, session: *const session_store.Session) ![]u8 {
    const native_jsonl = try session.native.toJsonl(gpa);
    defer gpa.free(native_jsonl);
    var out: Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"customType\":\"");
    try out.writer.writeAll(SNAPSHOT_CUSTOM_TYPE);
    try out.writer.print("\",\"version\":{d},\"server\":{{\"id\":", .{SNAPSHOT_VERSION});
    try std.json.Stringify.value(session.id, .{}, &out.writer);
    try out.writer.writeAll(",\"name\":");
    if (session.name) |name| try std.json.Stringify.value(name, .{}, &out.writer) else try out.writer.writeAll("null");
    try out.writer.writeAll(",\"cwd\":");
    try std.json.Stringify.value(session.cwd, .{}, &out.writer);
    try out.writer.print(",\"createdAt\":{d},\"updatedAt\":{d},\"model\":{{\"provider\":", .{ session.created_at, session.updated_at });
    try std.json.Stringify.value(session.model_provider, .{}, &out.writer);
    try out.writer.writeAll(",\"id\":");
    try std.json.Stringify.value(session.model_id, .{}, &out.writer);
    try out.writer.writeAll("},\"thinkingLevel\":");
    try std.json.Stringify.value(@tagName(session.thinking_level), .{}, &out.writer);
    try out.writer.print(",\"revision\":{d},\"transcript\":[", .{session.revision});
    for (session.transcript.items, 0..) |entry, index| {
        if (index > 0) try out.writer.writeByte(',');
        try out.writer.writeAll("{\"id\":");
        try std.json.Stringify.value(entry.id, .{}, &out.writer);
        try out.writer.writeAll(",\"text\":");
        try std.json.Stringify.value(entry.text, .{}, &out.writer);
        try out.writer.print(",\"timestamp\":{d}}}", .{entry.timestamp});
    }
    try out.writer.writeAll("],\"nativeJsonl\":");
    try std.json.Stringify.value(native_jsonl, .{}, &out.writer);
    try out.writer.writeAll("}}");
    return out.toOwnedSlice();
}

fn decodeSnapshot(gpa: std.mem.Allocator, raw: []const u8) !*session_store.Session {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return Error.InvalidSnapshot;
    const root = parsed.value.object;
    const custom = root.get("customType") orelse return Error.InvalidSnapshot;
    const version = root.get("version") orelse return Error.InvalidSnapshot;
    const server_value = root.get("server") orelse return Error.InvalidSnapshot;
    if (custom != .string or !std.mem.eql(u8, custom.string, SNAPSHOT_CUSTOM_TYPE) or version != .integer or version.integer != SNAPSHOT_VERSION or server_value != .object) return Error.InvalidSnapshot;
    const server = server_value.object;

    const id = try requiredString(server, "id");
    const cwd = try requiredString(server, "cwd");
    const created = try requiredUnsigned(server, "createdAt");
    const updated = try requiredUnsigned(server, "updatedAt");
    const revision = try requiredUnsigned(server, "revision");
    const thinking_raw = try requiredString(server, "thinkingLevel");
    const thinking_level = pi_zig.protocol.messages.parseThinkingLevel(thinking_raw) orelse return Error.InvalidSnapshot;
    const model_value = server.get("model") orelse return Error.InvalidSnapshot;
    if (model_value != .object) return Error.InvalidSnapshot;
    const provider = try requiredString(model_value.object, "provider");
    const model_id = try requiredString(model_value.object, "id");
    const native_raw = try requiredString(server, "nativeJsonl");

    var native = try agent_session.Session.parseJsonl(gpa, native_raw);
    errdefer native.deinit();
    if (!std.mem.eql(u8, native.id, id) or !std.mem.eql(u8, native.cwd, cwd)) return Error.SnapshotIdentityMismatch;

    var transcript: std.ArrayList(session_store.Session.UserEntry) = .empty;
    errdefer deinitTranscript(gpa, &transcript);
    if (server.get("transcript")) |value| {
        if (value != .array) return Error.InvalidSnapshot;
        for (value.array.items) |item| {
            if (item != .object) return Error.InvalidSnapshot;
            try appendDecodedTranscriptEntry(gpa, &transcript, item.object);
        }
    }

    const id_owned = try gpa.dupe(u8, id);
    errdefer gpa.free(id_owned);
    const cwd_owned = try gpa.dupe(u8, cwd);
    errdefer gpa.free(cwd_owned);
    const provider_owned = try gpa.dupe(u8, provider);
    errdefer gpa.free(provider_owned);
    const model_owned = try gpa.dupe(u8, model_id);
    errdefer gpa.free(model_owned);
    var name_owned: ?[]u8 = null;
    if (server.get("name")) |name| switch (name) {
        .null => {},
        .string => |value| name_owned = try gpa.dupe(u8, value),
        else => return Error.InvalidSnapshot,
    };
    errdefer if (name_owned) |name| gpa.free(name);

    // Allocate the outer object last. After the assignment below no fallible
    // operation remains, so every preceding errdefer transfers ownership
    // exactly once instead of overlapping with Session.deinit().
    const result = try gpa.create(session_store.Session);
    result.* = .{
        .id = id_owned,
        .name = name_owned,
        .cwd = cwd_owned,
        .created_at = created,
        .updated_at = updated,
        .model_provider = provider_owned,
        .model_id = model_owned,
        .thinking_level = thinking_level,
        .revision = revision,
        .runtime_live = false,
        .transcript = transcript,
        .native = native,
    };
    return result;
}

fn appendDecodedTranscriptEntry(
    gpa: std.mem.Allocator,
    transcript: *std.ArrayList(session_store.Session.UserEntry),
    object: std.json.ObjectMap,
) !void {
    const id = try requiredString(object, "id");
    const text = try requiredString(object, "text");
    const timestamp = try requiredUnsigned(object, "timestamp");
    const id_owned = try gpa.dupe(u8, id);
    errdefer gpa.free(id_owned);
    const text_owned = try gpa.dupe(u8, text);
    errdefer gpa.free(text_owned);
    try transcript.append(gpa, .{ .id = id_owned, .text = text_owned, .timestamp = timestamp });
}

fn deinitTranscript(gpa: std.mem.Allocator, transcript: *std.ArrayList(session_store.Session.UserEntry)) void {
    for (transcript.items) |entry| {
        gpa.free(entry.id);
        gpa.free(entry.text);
    }
    transcript.deinit(gpa);
}

fn requiredString(object: std.json.ObjectMap, key: []const u8) ![]const u8 {
    const value = object.get(key) orelse return Error.InvalidSnapshot;
    if (value != .string) return Error.InvalidSnapshot;
    return value.string;
}

fn requiredUnsigned(object: std.json.ObjectMap, key: []const u8) !u64 {
    const value = object.get(key) orelse return Error.InvalidSnapshot;
    if (value != .integer or value.integer < 0) return Error.InvalidSnapshot;
    return @intCast(value.integer);
}

const test_catalog = [_]pi_zig.ai.providers.ModelInfo{
    .{ .provider = .mock, .id = "mock-a", .display = "Mock A", .reasoning = true },
    .{ .provider = .openai, .id = "reason", .display = "Reason", .reasoning = true },
};

test "SQLite server persistence round-trips complete native sessions" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var adapter = try Adapter.init(gpa, io, ":memory:");
    defer adapter.deinit();

    var first: session_store.SessionStore = .{};
    defer first.deinit(gpa);
    const session = try first.create(gpa, io, "connection", "/workspace", "Durable", test_catalog[0], .high);
    _ = try first.appendPrompt(gpa, io, "connection", session.id, "hello sqlite server");
    _ = try session.native.appendMessage(session.native.lastEntryId(), "assistant", "durable answer", null, null);
    session.updated_at += 5;
    session.revision += 1;
    try adapter.saveSession(session);
    // Identical saves are idempotent and do not append another snapshot.
    try adapter.saveSession(session);
    const snapshots = try adapter.repo.findEntries(session.id, .{ .custom_type = SNAPSHOT_CUSTOM_TYPE });
    defer freeEntries(gpa, snapshots);
    try std.testing.expectEqual(@as(usize, 1), snapshots.len);

    adapter.releaseSession(session.id);
    var second: session_store.SessionStore = .{};
    defer second.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), try adapter.loadAll(&second));
    const restored = second.find(session.id).?;
    try std.testing.expectEqualStrings("Durable", restored.name.?);
    try std.testing.expectEqualStrings("hello sqlite server", restored.transcript.items[0].text);
    try std.testing.expectEqual(@as(usize, 2), restored.native.entries.items.len);
    try std.testing.expectEqualStrings("durable answer", restored.native.entries.items[1].content);
    try std.testing.expect(!restored.locked());
}

test "SQLite server persistence fences concurrent writers" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const db_path = try std.fmt.allocPrint(gpa, "{s}/sessions.db", .{path_buf[0..n]});
    defer gpa.free(db_path);

    var first = try Adapter.init(gpa, io, db_path);
    defer first.deinit();
    var store: session_store.SessionStore = .{};
    defer store.deinit(gpa);
    const session = try store.create(gpa, io, "c", "/", null, test_catalog[0], .off);
    try first.saveSession(session);

    var second = try Adapter.init(gpa, io, db_path);
    defer second.deinit();
    try std.testing.expectError(Error.SessionLocked, second.saveSession(session));
    first.releaseSession(session.id);
    try second.saveSession(session);
}

test "SQLite server persistence ignores ordinary and corrupt repository sessions" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var adapter = try Adapter.init(gpa, io, ":memory:");
    defer adapter.deinit();
    var metadata = try adapter.repo.createSession(.{ .id = "ordinary", .cwd = "/" });
    defer metadata.deinit(gpa);
    var corrupt = try adapter.repo.createSession(.{ .id = "corrupt", .cwd = "/" });
    defer corrupt.deinit(gpa);
    var bad = try adapter.repo.appendEntry("corrupt", "main", .{
        .entry_type = .custom,
        .custom_type = SNAPSHOT_CUSTOM_TYPE,
        .payload_json = "{\"customType\":\"pi.server.snapshot\",\"version\":1}",
    }, null);
    defer bad.deinit(gpa);
    var store: session_store.SessionStore = .{};
    defer store.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 0), try adapter.loadAll(&store));
}

test "SQLite server persistence imports JSON sessions idempotently" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];
    const json_dir = try std.fmt.allocPrint(gpa, "{s}/json", .{root});
    defer gpa.free(json_dir);
    const db_path = try std.fmt.allocPrint(gpa, "{s}/sessions.db", .{root});
    defer gpa.free(db_path);

    var source: session_store.SessionStore = .{};
    defer source.deinit(gpa);
    const session = try source.create(gpa, io, "json-writer", "/migration", "Imported", test_catalog[0], .medium);
    _ = try source.appendPrompt(gpa, io, "json-writer", session.id, "migrate this durable prompt");
    _ = try session.native.appendMessage(session.native.lastEntryId(), "assistant", "migration complete", null, null);
    try session_store.saveSession(gpa, io, json_dir, session);

    var adapter = try Adapter.init(gpa, io, db_path);
    defer adapter.deinit();
    const first = try adapter.importJsonDirectory(json_dir);
    try std.testing.expectEqual(@as(usize, 1), first.loaded);
    try std.testing.expectEqual(@as(usize, 1), first.imported);
    try std.testing.expectEqual(@as(usize, 0), first.unchanged);
    adapter.releaseSession(session.id);

    const second = try adapter.importJsonDirectory(json_dir);
    try std.testing.expectEqual(@as(usize, 1), second.loaded);
    try std.testing.expectEqual(@as(usize, 0), second.imported);
    try std.testing.expectEqual(@as(usize, 1), second.unchanged);

    var restored: session_store.SessionStore = .{};
    defer restored.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), try adapter.loadAll(&restored));
    const loaded = restored.find(session.id).?;
    try std.testing.expectEqualStrings("Imported", loaded.name.?);
    try std.testing.expectEqualStrings("migrate this durable prompt", loaded.transcript.items[0].text);
    try std.testing.expectEqualStrings("migration complete", loaded.native.entries.items[1].content);
}

test "SQLite snapshot decoder releases partially decoded transcript ownership" {
    const gpa = std.testing.allocator;
    var native = try agent_session.Session.init(gpa, "decode-id", "/decode");
    defer native.deinit();
    const native_jsonl = try native.toJsonl(gpa);
    defer gpa.free(native_jsonl);
    var raw: std.Io.Writer.Allocating = .init(gpa);
    defer raw.deinit();
    try raw.writer.writeAll("{\"customType\":\"pi.server.snapshot\",\"version\":1,\"server\":{\"id\":\"decode-id\",\"name\":null,\"cwd\":\"/decode\",\"createdAt\":1,\"updatedAt\":2,\"model\":{\"provider\":\"mock\",\"id\":\"mock-a\"},\"thinkingLevel\":\"off\",\"revision\":0,\"transcript\":[{\"id\":\"ok\",\"text\":\"owned\",\"timestamp\":1},{\"id\":\"bad\",\"timestamp\":2}],\"nativeJsonl\":");
    try std.json.Stringify.value(native_jsonl, .{}, &raw.writer);
    try raw.writer.writeAll("}}");
    try std.testing.expectError(Error.InvalidSnapshot, decodeSnapshot(gpa, raw.written()));
}
