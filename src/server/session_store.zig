//! Stateful Pi server session/attachment layer.
//! Mirrors the connection-relative attachment semantics in packages/server/src/sessions.ts.
const std = @import("std");
const Io = std.Io;
const protocol = @import("../protocol/root.zig");
const providers = @import("../ai/providers.zig");
const thinking = @import("../ai/thinking.zig");
const agent_session = @import("../agent/session.zig");

pub const Error = error{
    SessionNotFound,
    NotAttached,
    UnknownModel,
    Busy,
};

/// Backend-neutral durable storage hook for the live server. The default
/// server continues to use JSON files; linked companions can provide the
/// canonical SQLite repository without forcing a SQLite dependency into `pi`.
pub const PersistenceBackend = struct {
    context: *anyopaque,
    load_all_fn: *const fn (*anyopaque, *SessionStore, std.mem.Allocator, Io) anyerror!usize,
    save_session_fn: *const fn (*anyopaque, std.mem.Allocator, Io, *const Session) anyerror!void,
    claim_session_fn: ?*const fn (*anyopaque, []const u8) anyerror!void = null,
    release_session_fn: ?*const fn (*anyopaque, []const u8) void = null,

    pub fn loadAll(self: PersistenceBackend, store: *SessionStore, gpa: std.mem.Allocator, io: Io) !usize {
        return self.load_all_fn(self.context, store, gpa, io);
    }

    pub fn saveSession(self: PersistenceBackend, gpa: std.mem.Allocator, io: Io, session: *const Session) !void {
        return self.save_session_fn(self.context, gpa, io, session);
    }

    pub fn claimSession(self: PersistenceBackend, session_id: []const u8) !void {
        if (self.claim_session_fn) |func| try func(self.context, session_id);
    }

    pub fn releaseSession(self: PersistenceBackend, session_id: []const u8) void {
        if (self.release_session_fn) |func| func(self.context, session_id);
    }
};

pub const Session = struct {
    id: []u8,
    name: ?[]u8,
    cwd: []u8,
    created_at: u64,
    updated_at: u64,
    phase: protocol.messages.SessionPhase = .idle,
    model_provider: []u8,
    model_id: []u8,
    thinking_level: protocol.messages.ThinkingLevel = .off,
    revision: u64 = 0,
    /// Mirrors upstream live runtime ownership. A runtime can remain locked after
    /// its last connection disconnects while an operation is still active.
    runtime_live: bool = true,
    active_operations: usize = 0,
    attachments: std.ArrayList([]u8) = .empty,
    transcript: std.ArrayList(UserEntry) = .empty,
    /// Steering items queued while an active turn/tool is running.
    queued_steer: std.ArrayList(UserEntry) = .empty,
    /// Native agent history is authoritative for LLM/tool replay.
    native: agent_session.Session,
    /// Shared cancellation flag; all concurrent readers/writers use atomics.
    abort_flag: bool = false,

    pub const UserEntry = struct {
        id: []u8,
        text: []u8,
        timestamp: u64,
    };

    pub fn deinit(self: *Session, gpa: std.mem.Allocator) void {
        gpa.free(self.id);
        if (self.name) |name| gpa.free(name);
        gpa.free(self.cwd);
        gpa.free(self.model_provider);
        gpa.free(self.model_id);
        for (self.attachments.items) |id| gpa.free(id);
        self.attachments.deinit(gpa);
        for (self.transcript.items) |entry| {
            gpa.free(entry.id);
            gpa.free(entry.text);
        }
        self.transcript.deinit(gpa);
        for (self.queued_steer.items) |entry| {
            gpa.free(entry.id);
            gpa.free(entry.text);
        }
        self.queued_steer.deinit(gpa);
        self.native.deinit();
        gpa.destroy(self);
    }

    pub fn isAttachedTo(self: *const Session, connection_id: []const u8) bool {
        for (self.attachments.items) |id| if (std.mem.eql(u8, id, connection_id)) return true;
        return false;
    }

    pub fn locked(self: *const Session) bool {
        return self.runtime_live;
    }
};

pub const SessionStore = struct {
    sessions: std.ArrayList(*Session) = .empty,
    server_revision: u64 = 0,
    logical_clock: u64 = 1_720_000_000_000,

    pub fn deinit(self: *SessionStore, gpa: std.mem.Allocator) void {
        for (self.sessions.items) |session| session.deinit(gpa);
        self.sessions.deinit(gpa);
        self.* = .{};
    }

    fn now(self: *SessionStore, io: Io) u64 {
        const ns = std.Io.Clock.real.now(io).nanoseconds;
        if (ns > 0) {
            const ms: u64 = @intCast(@divTrunc(ns, std.time.ns_per_ms));
            if (ms > self.logical_clock) self.logical_clock = ms;
        }
        self.logical_clock += 1;
        return self.logical_clock;
    }

    pub fn find(self: *SessionStore, session_id: []const u8) ?*Session {
        for (self.sessions.items) |session| if (std.mem.eql(u8, session.id, session_id)) return session;
        return null;
    }

    pub fn create(
        self: *SessionStore,
        gpa: std.mem.Allocator,
        io: Io,
        connection_id: []const u8,
        cwd: []const u8,
        name: ?[]const u8,
        model: providers.ModelInfo,
        requested_thinking: thinking.ThinkingLevel,
    ) !*Session {
        const session = try gpa.create(Session);
        errdefer gpa.destroy(session);
        const id = try uuid(gpa, io);
        errdefer gpa.free(id);
        const cwd_owned = try gpa.dupe(u8, cwd);
        errdefer gpa.free(cwd_owned);
        const provider_owned = try gpa.dupe(u8, model.providerName());
        errdefer gpa.free(provider_owned);
        const model_owned = try gpa.dupe(u8, model.id);
        errdefer gpa.free(model_owned);
        const name_owned = if (name) |n| try gpa.dupe(u8, n) else null;
        errdefer if (name_owned) |n| gpa.free(n);
        var native = try agent_session.Session.init(gpa, id, cwd);
        errdefer native.deinit();
        if (name) |n| try native.setName(n);
        const ts = self.now(io);
        session.* = .{
            .id = id,
            .name = name_owned,
            .cwd = cwd_owned,
            .created_at = ts,
            .updated_at = ts,
            .model_provider = provider_owned,
            .model_id = model_owned,
            .thinking_level = toProtocolThinking(model.clampThinkingLevel(requested_thinking)),
            .native = native,
        };
        errdefer session.deinit(gpa);
        try self.sessions.append(gpa, session);
        errdefer _ = self.sessions.pop();
        _ = try self.attach(gpa, connection_id, session.id);
        return session;
    }

    pub fn attach(self: *SessionStore, gpa: std.mem.Allocator, connection_id: []const u8, session_id: []const u8) !*Session {
        const session = self.find(session_id) orelse return Error.SessionNotFound;
        session.runtime_live = true;
        if (!session.isAttachedTo(connection_id)) {
            try session.attachments.append(gpa, try gpa.dupe(u8, connection_id));
        }
        return session;
    }

    pub fn detach(self: *SessionStore, gpa: std.mem.Allocator, connection_id: []const u8, session_id: []const u8) void {
        const session = self.find(session_id) orelse return;
        var i: usize = 0;
        while (i < session.attachments.items.len) : (i += 1) {
            if (std.mem.eql(u8, session.attachments.items[i], connection_id)) {
                gpa.free(session.attachments.items[i]);
                _ = session.attachments.orderedRemove(i);
                maybeDispose(session);
                return;
            }
        }
    }

    /// Disconnect cleanup is deliberately all-sessions, matching upstream.
    pub fn disconnect(self: *SessionStore, gpa: std.mem.Allocator, connection_id: []const u8) usize {
        var removed: usize = 0;
        for (self.sessions.items) |session| {
            var i: usize = 0;
            while (i < session.attachments.items.len) {
                if (std.mem.eql(u8, session.attachments.items[i], connection_id)) {
                    gpa.free(session.attachments.items[i]);
                    _ = session.attachments.orderedRemove(i);
                    removed += 1;
                } else {
                    i += 1;
                }
            }
            maybeDispose(session);
        }
        return removed;
    }

    fn maybeDispose(session: *Session) void {
        if (session.attachments.items.len == 0 and session.active_operations == 0 and session.phase == .idle) {
            session.runtime_live = false;
        }
    }

    pub fn beginOperation(self: *SessionStore, connection_id: []const u8, session_id: []const u8, phase: protocol.messages.SessionPhase) !*Session {
        const session = try self.requireAttached(connection_id, session_id);
        if (session.active_operations > 0 or session.phase != .idle) return Error.Busy;
        session.runtime_live = true;
        session.active_operations = 1;
        session.phase = phase;
        session.revision += 1;
        return session;
    }

    pub fn endOperation(self: *SessionStore, io: Io, session_id: []const u8) !*Session {
        const session = self.find(session_id) orelse return Error.SessionNotFound;
        if (session.active_operations > 0) session.active_operations -= 1;
        if (session.active_operations == 0) session.phase = .idle;
        session.updated_at = self.now(io);
        session.revision += 1;
        maybeDispose(session);
        return session;
    }

    pub fn requireAttached(self: *SessionStore, connection_id: []const u8, session_id: []const u8) !*Session {
        const session = self.find(session_id) orelse return Error.SessionNotFound;
        if (!session.isAttachedTo(connection_id)) return Error.NotAttached;
        return session;
    }

    pub fn setThinking(
        self: *SessionStore,
        io: Io,
        connection_id: []const u8,
        session_id: []const u8,
        requested: thinking.ThinkingLevel,
        catalog: []const providers.ModelInfo,
    ) !*Session {
        const session = try self.requireAttached(connection_id, session_id);
        if (session.active_operations > 0 or session.phase != .idle) return Error.Busy;
        const model = findModel(catalog, session.model_provider, session.model_id) orelse return Error.UnknownModel;
        const effective = toProtocolThinking(model.clampThinkingLevel(requested));
        if (session.thinking_level != effective) {
            session.thinking_level = effective;
            session.updated_at = self.now(io);
            session.revision += 1;
        }
        return session;
    }

    pub fn setModel(
        self: *SessionStore,
        gpa: std.mem.Allocator,
        io: Io,
        connection_id: []const u8,
        session_id: []const u8,
        provider_id: []const u8,
        model_id: []const u8,
        catalog: []const providers.ModelInfo,
    ) !*Session {
        const session = try self.requireAttached(connection_id, session_id);
        if (session.active_operations > 0 or session.phase != .idle) return Error.Busy;
        const model = findModel(catalog, provider_id, model_id) orelse return Error.UnknownModel;
        const new_provider = try gpa.dupe(u8, model.providerName());
        errdefer gpa.free(new_provider);
        const new_model = try gpa.dupe(u8, model.id);
        errdefer gpa.free(new_model);
        gpa.free(session.model_provider);
        gpa.free(session.model_id);
        session.model_provider = new_provider;
        session.model_id = new_model;
        const current_thinking = fromProtocolThinking(session.thinking_level);
        session.thinking_level = toProtocolThinking(model.clampThinkingLevel(current_thinking));
        session.updated_at = self.now(io);
        session.revision += 1;
        return session;
    }

    pub fn steer(self: *SessionStore, gpa: std.mem.Allocator, io: Io, connection_id: []const u8, session_id: []const u8, text: []const u8) !*Session {
        const session = try self.requireAttached(connection_id, session_id);
        if (session.phase == .idle or session.active_operations == 0) return Error.Busy;
        const ts = self.now(io);
        const id = try std.fmt.allocPrint(gpa, "steer-{d}", .{session.revision + 1});
        errdefer gpa.free(id);
        const copied = try gpa.dupe(u8, text);
        errdefer gpa.free(copied);
        try session.queued_steer.append(gpa, .{ .id = id, .text = copied, .timestamp = ts });
        session.updated_at = ts;
        session.revision += 1;
        return session;
    }

    /// Remove and transfer ownership of one queued steering message. Caller owns text.
    pub fn takeSteer(self: *SessionStore, gpa: std.mem.Allocator, io: Io, session_id: []const u8) !?[]u8 {
        const session = self.find(session_id) orelse return Error.SessionNotFound;
        if (session.queued_steer.items.len == 0) return null;
        const entry = session.queued_steer.orderedRemove(0);
        gpa.free(entry.id);
        session.updated_at = self.now(io);
        session.revision += 1;
        return entry.text;
    }

    pub fn abort(self: *SessionStore, connection_id: []const u8, session_id: []const u8) !*Session {
        const session = try self.requireAttached(connection_id, session_id);
        if (session.phase == .idle or session.active_operations == 0) return Error.Busy;
        @atomicStore(bool, &session.abort_flag, true, .release);
        return session;
    }

    pub fn appendPrompt(self: *SessionStore, gpa: std.mem.Allocator, io: Io, connection_id: []const u8, session_id: []const u8, text: []const u8) !*Session {
        const session = try self.requireAttached(connection_id, session_id);
        const ts = self.now(io);
        const id = try std.fmt.allocPrint(gpa, "user-{d}", .{session.revision + 1});
        errdefer gpa.free(id);
        const copied = try gpa.dupe(u8, text);
        errdefer gpa.free(copied);
        try session.transcript.append(gpa, .{ .id = id, .text = copied, .timestamp = ts });
        _ = try session.native.appendMessage(session.native.lastEntryId(), "user", text, null, null);
        session.updated_at = ts;
        session.revision += 1;
        return session;
    }
};

pub fn findModel(catalog: []const providers.ModelInfo, provider_id: []const u8, model_id: []const u8) ?providers.ModelInfo {
    for (catalog) |model| {
        if (std.ascii.eqlIgnoreCase(model.providerName(), provider_id) and std.mem.eql(u8, model.id, model_id)) return model;
    }
    return null;
}

pub fn toProtocolThinking(level: thinking.ThinkingLevel) protocol.messages.ThinkingLevel {
    return switch (level) {
        .off => .off,
        .minimal => .minimal,
        .low => .low,
        .medium => .medium,
        .high => .high,
        .xhigh => .xhigh,
        .max => .max,
    };
}

pub fn fromProtocolThinking(level: protocol.messages.ThinkingLevel) thinking.ThinkingLevel {
    return switch (level) {
        .off => .off,
        .minimal => .minimal,
        .low => .low,
        .medium => .medium,
        .high => .high,
        .xhigh => .xhigh,
        .max => .max,
    };
}

fn uuid(gpa: std.mem.Allocator, io: Io) ![]u8 {
    var bytes: [16]u8 = undefined;
    try std.Io.randomSecure(io, &bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const out = try gpa.alloc(u8, 36);
    const hex = "0123456789abcdef";
    var oi: usize = 0;
    for (bytes, 0..) |b, i| {
        if (i == 4 or i == 6 or i == 8 or i == 10) {
            out[oi] = '-';
            oi += 1;
        }
        out[oi] = hex[b >> 4];
        out[oi + 1] = hex[b & 0x0f];
        oi += 2;
    }
    return out;
}

const test_catalog = [_]providers.ModelInfo{
    .{ .provider = .openai, .id = "plain", .display = "Plain", .reasoning = false },
    .{ .provider = .openai, .id = "reason", .display = "Reason", .reasoning = true, .thinking_level_map = .{ .minimal = .unsupported, .xhigh = .{ .mapped = "xhigh" } } },
};

test "connection-relative attachments and disconnect cleanup" {
    const gpa = std.testing.allocator;
    var store = SessionStore{};
    defer store.deinit(gpa);
    const s1 = try store.create(gpa, std.testing.io, "c1", "/tmp/a", null, test_catalog[0], .high);
    const s2 = try store.create(gpa, std.testing.io, "c1", "/tmp/b", "B", test_catalog[1], .minimal);
    try std.testing.expect(s1.isAttachedTo("c1"));
    try std.testing.expect(s2.isAttachedTo("c1"));
    try std.testing.expect(s1.locked() and s2.locked());
    _ = try store.attach(gpa, "c2", s1.id);
    store.detach(gpa, "c1", s1.id);
    try std.testing.expect(!s1.isAttachedTo("c1"));
    try std.testing.expect(s1.isAttachedTo("c2"));
    try std.testing.expect(s1.locked());
    try std.testing.expectEqual(@as(usize, 1), store.disconnect(gpa, "c1"));
    try std.testing.expect(!s2.locked());
    try std.testing.expectEqual(@as(usize, 1), store.disconnect(gpa, "c2"));
    try std.testing.expect(!s1.locked());
}

test "set thinking clamps to selected model capability and model switch reclamps" {
    const gpa = std.testing.allocator;
    var store = SessionStore{};
    defer store.deinit(gpa);
    const session = try store.create(gpa, std.testing.io, "c", "/tmp", null, test_catalog[1], .minimal);
    // minimal is explicitly unsupported, upstream searches upward and lands on low.
    try std.testing.expectEqual(protocol.messages.ThinkingLevel.low, session.thinking_level);
    _ = try store.setThinking(std.testing.io, "c", session.id, .max, &test_catalog);
    // max is not opt-in; xhigh is, so max clamps downward to xhigh.
    try std.testing.expectEqual(protocol.messages.ThinkingLevel.xhigh, session.thinking_level);
    _ = try store.setModel(gpa, std.testing.io, "c", session.id, "openai", "plain", &test_catalog);
    try std.testing.expectEqual(protocol.messages.ThinkingLevel.off, session.thinking_level);
}

test "operations require the requesting connection to be attached" {
    const gpa = std.testing.allocator;
    var store = SessionStore{};
    defer store.deinit(gpa);
    const session = try store.create(gpa, std.testing.io, "owner", "/tmp", null, test_catalog[0], .off);
    try std.testing.expectError(Error.NotAttached, store.appendPrompt(gpa, std.testing.io, "other", session.id, "x"));
    _ = try store.appendPrompt(gpa, std.testing.io, "owner", session.id, "");
    try std.testing.expectEqual(@as(usize, 1), session.transcript.items.len);
    try std.testing.expectEqualStrings("", session.transcript.items[0].text);
}

test "disconnect during active operation stays locked until idle" {
    const gpa = std.testing.allocator;
    var store = SessionStore{};
    defer store.deinit(gpa);
    const session = try store.create(gpa, std.testing.io, "c", "/tmp", null, test_catalog[0], .off);
    _ = try store.beginOperation("c", session.id, .turn);
    try std.testing.expect(session.locked());
    try std.testing.expectEqual(@as(usize, 1), store.disconnect(gpa, "c"));
    try std.testing.expect(!session.isAttachedTo("c"));
    try std.testing.expect(session.locked());
    try std.testing.expectEqual(protocol.messages.SessionPhase.turn, session.phase);
    _ = try store.endOperation(std.testing.io, session.id);
    try std.testing.expectEqual(protocol.messages.SessionPhase.idle, session.phase);
    try std.testing.expect(!session.locked());
}

fn permissions0600() std.Io.File.Permissions {
    if (@hasDecl(std.Io.File.Permissions, "fromMode")) return std.Io.File.Permissions.fromMode(0o600);
    return .default_file;
}

/// Persist authoritative session state. Attachments/runtime locks are intentionally omitted.
pub fn saveSession(gpa: std.mem.Allocator, io: Io, dir_path: []const u8, session: *const Session) !void {
    try std.Io.Dir.cwd().createDirPath(io, dir_path);
    const file_name = try std.fmt.allocPrint(gpa, "{s}.json", .{session.id});
    defer gpa.free(file_name);
    const path = try std.fs.path.join(gpa, &.{ dir_path, file_name });
    defer gpa.free(path);

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try out.writer.writeAll("{\"version\":1,\"id\":");
    try std.json.Stringify.value(session.id, .{}, &out.writer);
    if (session.name) |name| {
        try out.writer.writeAll(",\"name\":");
        try std.json.Stringify.value(name, .{}, &out.writer);
    }
    try out.writer.writeAll(",\"cwd\":");
    try std.json.Stringify.value(session.cwd, .{}, &out.writer);
    try out.writer.print(",\"createdAt\":{d},\"updatedAt\":{d},\"model\":{{\"provider\":", .{ session.created_at, session.updated_at });
    try std.json.Stringify.value(session.model_provider, .{}, &out.writer);
    try out.writer.writeAll(",\"id\":");
    try std.json.Stringify.value(session.model_id, .{}, &out.writer);
    try out.writer.writeAll("},\"thinkingLevel\":");
    try std.json.Stringify.value(@tagName(session.thinking_level), .{}, &out.writer);
    try out.writer.print(",\"revision\":{d},\"transcript\":[", .{session.revision});
    for (session.transcript.items, 0..) |entry, i| {
        if (i > 0) try out.writer.writeByte(',');
        try out.writer.writeAll("{\"id\":");
        try std.json.Stringify.value(entry.id, .{}, &out.writer);
        try out.writer.writeAll(",\"text\":");
        try std.json.Stringify.value(entry.text, .{}, &out.writer);
        try out.writer.print(",\"timestamp\":{d}}}", .{entry.timestamp});
    }
    try out.writer.writeAll("]}\n");

    var atomic = try std.Io.Dir.cwd().createFileAtomic(io, path, .{
        .permissions = permissions0600(),
        .make_path = true,
        .replace = true,
    });
    defer atomic.deinit(io);
    try atomic.file.writePositionalAll(io, out.written(), 0);
    atomic.file.setPermissions(io, permissions0600()) catch {};
    try atomic.replace(io);

    const native_path = try std.fmt.allocPrint(gpa, "{s}/{s}.agent.jsonl", .{ dir_path, session.id });
    defer gpa.free(native_path);
    const native_data = try session.native.toJsonl(gpa);
    defer gpa.free(native_data);
    var native_atomic = try std.Io.Dir.cwd().createFileAtomic(io, native_path, .{
        .permissions = permissions0600(),
        .make_path = true,
        .replace = true,
    });
    defer native_atomic.deinit(io);
    try native_atomic.file.writePositionalAll(io, native_data, 0);
    native_atomic.file.setPermissions(io, permissions0600()) catch {};
    try native_atomic.replace(io);
}

pub fn loadAll(store: *SessionStore, gpa: std.mem.Allocator, io: Io, dir_path: []const u8) !usize {
    try std.Io.Dir.cwd().createDirPath(io, dir_path);
    var dir = try std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true });
    defer dir.close(io);
    var iterator = dir.iterate();
    var loaded: usize = 0;
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".json")) continue;
        const path = try std.fs.path.join(gpa, &.{ dir_path, entry.name });
        defer gpa.free(path);
        const raw = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(8 * 1024 * 1024)) catch continue;
        defer gpa.free(raw);
        var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch continue;
        defer parsed.deinit();
        if (parsed.value != .object) continue;
        const o = parsed.value.object;
        const idv = o.get("id") orelse continue;
        const cwdv = o.get("cwd") orelse continue;
        const cav = o.get("createdAt") orelse continue;
        const uav = o.get("updatedAt") orelse continue;
        const mv = o.get("model") orelse continue;
        const tv = o.get("thinkingLevel") orelse continue;
        if (idv != .string or idv.string.len == 0 or cwdv != .string or cwdv.string.len == 0 or cav != .integer or uav != .integer or mv != .object or tv != .string) continue;
        const pv = mv.object.get("provider") orelse continue;
        const midv = mv.object.get("id") orelse continue;
        if (pv != .string or pv.string.len == 0 or midv != .string or midv.string.len == 0) continue;
        if (store.find(idv.string) != null) continue;
        const tl = protocol.messages.parseThinkingLevel(tv.string) orelse continue;

        const session = try gpa.create(Session);
        errdefer gpa.destroy(session);
        const id = try gpa.dupe(u8, idv.string);
        errdefer gpa.free(id);
        const cwd = try gpa.dupe(u8, cwdv.string);
        errdefer gpa.free(cwd);
        const provider = try gpa.dupe(u8, pv.string);
        errdefer gpa.free(provider);
        const model_id = try gpa.dupe(u8, midv.string);
        errdefer gpa.free(model_id);
        var name: ?[]u8 = null;
        if (o.get("name")) |nv| {
            if (nv == .string) name = try gpa.dupe(u8, nv.string);
        }
        errdefer if (name) |n| gpa.free(n);
        const native_path = try std.fmt.allocPrint(gpa, "{s}/{s}.agent.jsonl", .{ dir_path, idv.string });
        defer gpa.free(native_path);
        var native = agent_session.Session.load(gpa, io, native_path) catch try agent_session.Session.init(gpa, idv.string, cwdv.string);
        errdefer native.deinit();
        if (name) |n| native.setName(n) catch {};
        session.* = .{
            .id = id,
            .name = name,
            .cwd = cwd,
            .created_at = @intCast(cav.integer),
            .updated_at = @intCast(uav.integer),
            .model_provider = provider,
            .model_id = model_id,
            .thinking_level = tl,
            .revision = if (o.get("revision")) |rv| if (rv == .integer and rv.integer >= 0) @intCast(rv.integer) else 0 else 0,
            .runtime_live = false,
            .native = native,
        };
        errdefer session.deinit(gpa);

        if (o.get("transcript")) |transcript| {
            if (transcript == .array) for (transcript.array.items) |item| {
                if (item != .object) continue;
                const e_id = item.object.get("id") orelse continue;
                const e_text = item.object.get("text") orelse continue;
                const e_ts = item.object.get("timestamp") orelse continue;
                if (e_id != .string or e_text != .string or e_ts != .integer or e_ts.integer < 0) continue;
                try session.transcript.append(gpa, .{
                    .id = try gpa.dupe(u8, e_id.string),
                    .text = try gpa.dupe(u8, e_text.string),
                    .timestamp = @intCast(e_ts.integer),
                });
            };
        }
        if (session.native.entries.items.len == 0) {
            for (session.transcript.items) |legacy_entry| {
                _ = session.native.appendMessage(session.native.lastEntryId(), "user", legacy_entry.text, null, null) catch {};
            }
        }
        try store.sessions.append(gpa, session);
        loaded += 1;
        if (session.updated_at > store.logical_clock) store.logical_clock = session.updated_at;
    }
    return loaded;
}

test "durable session roundtrip excludes attachment locks" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const dir_path = path_buf[0..n];

    var a = SessionStore{};
    defer a.deinit(gpa);
    const s = try a.create(gpa, io, "c1", "/work", "Persisted", test_catalog[1], .high);
    _ = try a.appendPrompt(gpa, io, "c1", s.id, "hello durable");
    const id = try gpa.dupe(u8, s.id);
    defer gpa.free(id);
    try saveSession(gpa, io, dir_path, s);

    var b = SessionStore{};
    defer b.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), try loadAll(&b, gpa, io, dir_path));
    const restored = b.find(id).?;
    try std.testing.expectEqualStrings("/work", restored.cwd);
    try std.testing.expectEqualStrings("Persisted", restored.name.?);
    try std.testing.expectEqualStrings("reason", restored.model_id);
    try std.testing.expectEqual(protocol.messages.ThinkingLevel.high, restored.thinking_level);
    try std.testing.expectEqual(@as(usize, 1), restored.transcript.items.len);
    try std.testing.expectEqualStrings("hello durable", restored.transcript.items[0].text);
    try std.testing.expect(!restored.isAttachedTo("c1"));
    try std.testing.expect(!restored.locked());
}

test "busy prompt mutation and active steer abort semantics" {
    const gpa = std.testing.allocator;
    var store = SessionStore{};
    defer store.deinit(gpa);
    const session = try store.create(gpa, std.testing.io, "c", "/tmp", null, test_catalog[0], .off);

    try std.testing.expectError(Error.Busy, store.steer(gpa, std.testing.io, "c", session.id, "too early"));
    try std.testing.expectError(Error.Busy, store.abort("c", session.id));
    _ = try store.beginOperation("c", session.id, .turn);
    try std.testing.expectError(Error.Busy, store.beginOperation("c", session.id, .turn));
    try std.testing.expectError(Error.Busy, store.setThinking(std.testing.io, "c", session.id, .high, &test_catalog));
    try std.testing.expectError(Error.Busy, store.setModel(gpa, std.testing.io, "c", session.id, "openai", "plain", &test_catalog));

    _ = try store.steer(gpa, std.testing.io, "c", session.id, "during turn");
    try std.testing.expectEqual(@as(usize, 1), session.queued_steer.items.len);
    const msg = (try store.takeSteer(gpa, std.testing.io, session.id)).?;
    defer gpa.free(msg);
    try std.testing.expectEqualStrings("during turn", msg);
    try std.testing.expectEqual(@as(usize, 0), session.queued_steer.items.len);

    _ = try store.abort("c", session.id);
    try std.testing.expect(@atomicLoad(bool, &session.abort_flag, .acquire));
    _ = try store.endOperation(std.testing.io, session.id);
}
