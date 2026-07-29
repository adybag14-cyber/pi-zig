//! JSONL tree session: header + messages, fork, branch tip, auto-save dir.
const std = @import("std");
const Io = std.Io;

pub const SessionEntry = struct {
    id: []const u8,
    parent_id: ?[]const u8,
    role: []const u8,
    content: []const u8,
    tool_call_id: ?[]const u8 = null,
    tool_calls_json: ?[]const u8 = null,

    pub fn deinit(self: *SessionEntry, gpa: std.mem.Allocator) void {
        gpa.free(self.id);
        if (self.parent_id) |p| gpa.free(p);
        gpa.free(self.role);
        gpa.free(self.content);
        if (self.tool_call_id) |t| gpa.free(t);
        if (self.tool_calls_json) |t| gpa.free(t);
        self.* = undefined;
    }
};

pub const SessionInfo = struct {
    path: []const u8,
    id: []const u8,
    name: []const u8,
    mtime_hint: []const u8 = "",

    pub fn deinit(self: *SessionInfo, gpa: std.mem.Allocator) void {
        gpa.free(self.path);
        gpa.free(self.id);
        gpa.free(self.name);
        if (self.mtime_hint.len > 0) gpa.free(self.mtime_hint);
        self.* = undefined;
    }
};

pub const Session = struct {
    gpa: std.mem.Allocator,
    id: []const u8,
    cwd: []const u8,
    name: []const u8,
    /// Active leaf tip for tree navigation (entry id).
    tip_id: ?[]const u8 = null,
    entries: std.ArrayList(SessionEntry),
    next_seq: u64 = 1,

    pub fn init(gpa: std.mem.Allocator, id: []const u8, cwd: []const u8) !Session {
        return .{
            .gpa = gpa,
            .id = try gpa.dupe(u8, id),
            .cwd = try gpa.dupe(u8, cwd),
            .name = try gpa.dupe(u8, ""),
            .tip_id = null,
            .entries = .empty,
            .next_seq = 1,
        };
    }

    pub fn deinit(self: *Session) void {
        for (self.entries.items) |*e| e.deinit(self.gpa);
        self.entries.deinit(self.gpa);
        self.gpa.free(self.id);
        self.gpa.free(self.cwd);
        self.gpa.free(self.name);
        if (self.tip_id) |t| self.gpa.free(t);
        self.* = undefined;
    }

    pub fn setName(self: *Session, name: []const u8) !void {
        self.gpa.free(self.name);
        self.name = try self.gpa.dupe(u8, name);
    }

    pub fn setTip(self: *Session, entry_id: []const u8) !void {
        // Verify entry exists
        var found = false;
        for (self.entries.items) |e| {
            if (std.mem.eql(u8, e.id, entry_id)) {
                found = true;
                break;
            }
        }
        if (!found) return error.UnknownEntry;
        if (self.tip_id) |t| self.gpa.free(t);
        self.tip_id = try self.gpa.dupe(u8, entry_id);
    }

    pub fn appendMessage(
        self: *Session,
        parent_id: ?[]const u8,
        role: []const u8,
        content: []const u8,
        tool_call_id: ?[]const u8,
        tool_calls_json: ?[]const u8,
    ) ![]const u8 {
        const id = try std.fmt.allocPrint(self.gpa, "m{d}", .{self.next_seq});
        self.next_seq += 1;
        errdefer self.gpa.free(id);

        try self.entries.append(self.gpa, .{
            .id = id,
            .parent_id = if (parent_id) |p| try self.gpa.dupe(u8, p) else null,
            .role = try self.gpa.dupe(u8, role),
            .content = try self.gpa.dupe(u8, content),
            .tool_call_id = if (tool_call_id) |t| try self.gpa.dupe(u8, t) else null,
            .tool_calls_json = if (tool_calls_json) |t| try self.gpa.dupe(u8, t) else null,
        });
        if (self.tip_id) |t| self.gpa.free(t);
        self.tip_id = try self.gpa.dupe(u8, id);
        return id;
    }

    pub fn lastEntryId(self: *const Session) ?[]const u8 {
        if (self.tip_id) |t| return t;
        if (self.entries.items.len == 0) return null;
        return self.entries.items[self.entries.items.len - 1].id;
    }

    /// Entries on the active branch (from root to tip).
    pub fn branchEntries(self: *const Session, gpa: std.mem.Allocator) ![]const *const SessionEntry {
        const tip = self.lastEntryId() orelse return try gpa.alloc(*const SessionEntry, 0);
        var chain: std.ArrayList(*const SessionEntry) = .empty;
        errdefer chain.deinit(gpa);

        var current: ?[]const u8 = tip;
        while (current) |cid| {
            var found: ?*const SessionEntry = null;
            for (self.entries.items) |*e| {
                if (std.mem.eql(u8, e.id, cid)) {
                    found = e;
                    break;
                }
            }
            const e = found orelse break;
            try chain.append(gpa, e);
            current = e.parent_id;
        }
        // reverse to root→tip
        std.mem.reverse(*const SessionEntry, chain.items);
        return try chain.toOwnedSlice(gpa);
    }

    pub fn toJsonl(self: *const Session, gpa: std.mem.Allocator) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);

        {
            var line: std.Io.Writer.Allocating = .init(gpa);
            defer line.deinit();
            try line.writer.writeAll("{\"type\":\"header\",\"id\":");
            try std.json.Stringify.value(self.id, .{}, &line.writer);
            try line.writer.writeAll(",\"cwd\":");
            try std.json.Stringify.value(self.cwd, .{}, &line.writer);
            try line.writer.writeAll(",\"name\":");
            try std.json.Stringify.value(self.name, .{}, &line.writer);
            try line.writer.writeAll(",\"next_seq\":");
            try line.writer.print("{d}", .{self.next_seq});
            if (self.tip_id) |t| {
                try line.writer.writeAll(",\"tipId\":");
                try std.json.Stringify.value(t, .{}, &line.writer);
            }
            try line.writer.writeAll("}");
            try out.appendSlice(gpa, line.written());
            try out.append(gpa, '\n');
        }

        for (self.entries.items) |e| {
            var line: std.Io.Writer.Allocating = .init(gpa);
            defer line.deinit();
            try line.writer.writeAll("{\"type\":\"message\",\"id\":");
            try std.json.Stringify.value(e.id, .{}, &line.writer);
            try line.writer.writeAll(",\"parentId\":");
            if (e.parent_id) |p| {
                try std.json.Stringify.value(p, .{}, &line.writer);
            } else {
                try line.writer.writeAll("null");
            }
            try line.writer.writeAll(",\"role\":");
            try std.json.Stringify.value(e.role, .{}, &line.writer);
            try line.writer.writeAll(",\"content\":");
            try std.json.Stringify.value(e.content, .{}, &line.writer);
            if (e.tool_call_id) |tid| {
                try line.writer.writeAll(",\"toolCallId\":");
                try std.json.Stringify.value(tid, .{}, &line.writer);
            }
            if (e.tool_calls_json) |tcj| {
                try line.writer.writeAll(",\"toolCalls\":");
                try line.writer.writeAll(tcj);
            }
            try line.writer.writeAll("}");
            try out.appendSlice(gpa, line.written());
            try out.append(gpa, '\n');
        }

        return try out.toOwnedSlice(gpa);
    }

    pub fn save(self: *const Session, io: Io, path: []const u8) !void {
        const data = try self.toJsonl(self.gpa);
        defer self.gpa.free(data);
        if (std.fs.path.dirname(path)) |parent| {
            if (parent.len > 0) try std.Io.Dir.cwd().createDirPath(io, parent);
        }
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = data });
    }

    pub fn load(gpa: std.mem.Allocator, io: Io, path: []const u8) !Session {
        const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(32 * 1024 * 1024));
        defer gpa.free(raw);
        return try parseJsonl(gpa, raw);
    }

    pub fn parseJsonl(gpa: std.mem.Allocator, raw: []const u8) !Session {
        var session: ?Session = null;
        errdefer if (session) |*s| s.deinit();

        var it = std.mem.splitScalar(u8, raw, '\n');
        while (it.next()) |line| {
            if (line.len == 0) continue;
            var parsed = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
            defer parsed.deinit();
            if (parsed.value != .object) return error.InvalidSession;

            const typ = parsed.value.object.get("type") orelse return error.InvalidSession;
            if (typ != .string) return error.InvalidSession;

            if (std.mem.eql(u8, typ.string, "header")) {
                const id = parsed.value.object.get("id") orelse return error.InvalidSession;
                const cwd = parsed.value.object.get("cwd") orelse return error.InvalidSession;
                if (id != .string or cwd != .string) return error.InvalidSession;
                var s = try Session.init(gpa, id.string, cwd.string);
                if (parsed.value.object.get("name")) |nm| {
                    if (nm == .string) {
                        gpa.free(s.name);
                        s.name = try gpa.dupe(u8, nm.string);
                    }
                }
                if (parsed.value.object.get("next_seq")) |ns| {
                    if (ns == .integer) s.next_seq = @intCast(ns.integer);
                }
                if (parsed.value.object.get("tipId")) |tip| {
                    if (tip == .string) s.tip_id = try gpa.dupe(u8, tip.string);
                }
                session = s;
            } else if (std.mem.eql(u8, typ.string, "message")) {
                const s = &(session orelse return error.InvalidSession);
                const id = parsed.value.object.get("id") orelse return error.InvalidSession;
                const role = parsed.value.object.get("role") orelse return error.InvalidSession;
                const content = parsed.value.object.get("content") orelse return error.InvalidSession;
                if (id != .string or role != .string or content != .string) return error.InvalidSession;

                var parent_id: ?[]const u8 = null;
                if (parsed.value.object.get("parentId")) |p| {
                    if (p == .string) parent_id = p.string;
                }
                var tool_call_id: ?[]const u8 = null;
                if (parsed.value.object.get("toolCallId")) |t| {
                    if (t == .string) tool_call_id = t.string;
                }
                var tool_calls_json: ?[]u8 = null;
                if (parsed.value.object.get("toolCalls")) |tc| {
                    var aw: std.Io.Writer.Allocating = .init(gpa);
                    defer aw.deinit();
                    try std.json.Stringify.value(tc, .{}, &aw.writer);
                    tool_calls_json = try aw.toOwnedSlice();
                }
                defer if (tool_calls_json) |t| gpa.free(t);

                try s.entries.append(gpa, .{
                    .id = try gpa.dupe(u8, id.string),
                    .parent_id = if (parent_id) |p| try gpa.dupe(u8, p) else null,
                    .role = try gpa.dupe(u8, role.string),
                    .content = try gpa.dupe(u8, content.string),
                    .tool_call_id = if (tool_call_id) |t| try gpa.dupe(u8, t) else null,
                    .tool_calls_json = if (tool_calls_json) |t| try gpa.dupe(u8, t) else null,
                });
            }
        }

        return session orelse error.InvalidSession;
    }

    /// Deep-copy session as a new fork with new id.
    pub fn fork(self: *const Session, gpa: std.mem.Allocator, new_id: []const u8) !Session {
        var s = try Session.init(gpa, new_id, self.cwd);
        errdefer s.deinit();
        try s.setName(self.name);
        s.next_seq = self.next_seq;
        for (self.entries.items) |e| {
            try s.entries.append(gpa, .{
                .id = try gpa.dupe(u8, e.id),
                .parent_id = if (e.parent_id) |p| try gpa.dupe(u8, p) else null,
                .role = try gpa.dupe(u8, e.role),
                .content = try gpa.dupe(u8, e.content),
                .tool_call_id = if (e.tool_call_id) |t| try gpa.dupe(u8, t) else null,
                .tool_calls_json = if (e.tool_calls_json) |t| try gpa.dupe(u8, t) else null,
            });
        }
        if (self.tip_id) |t| s.tip_id = try gpa.dupe(u8, t);
        return s;
    }

    pub fn lastAssistantText(self: *const Session) ?[]const u8 {
        var i = self.entries.items.len;
        while (i > 0) {
            i -= 1;
            const e = self.entries.items[i];
            if (std.mem.eql(u8, e.role, "assistant") and e.content.len > 0) return e.content;
        }
        return null;
    }

    /// Tree summary for /tree (caller frees).
    pub fn treeSummary(self: *const Session, gpa: std.mem.Allocator) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);
        const tip = self.lastEntryId();
        for (self.entries.items) |e| {
            const mark: []const u8 = if (tip != null and std.mem.eql(u8, e.id, tip.?)) " *" else "";
            const line = try std.fmt.allocPrint(gpa, "{s} <- {s} [{s}] {s}{s}\n", .{
                e.id,
                e.parent_id orelse "null",
                e.role,
                truncate(e.content, 40),
                mark,
            });
            defer gpa.free(line);
            try out.appendSlice(gpa, line);
        }
        return try out.toOwnedSlice(gpa);
    }
};

fn truncate(s: []const u8, max: usize) []const u8 {
    if (s.len <= max) return s;
    return s[0..max];
}

/// List session JSONL files in a directory.
pub fn listSessions(gpa: std.mem.Allocator, io: Io, dir_path: []const u8) ![]SessionInfo {
    var list: std.ArrayList(SessionInfo) = .empty;
    errdefer {
        for (list.items) |*s| s.deinit(gpa);
        list.deinit(gpa);
    }

    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch {
        return try list.toOwnedSlice(gpa);
    };
    defer dir.close(io);

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".jsonl")) continue;
        const full = try std.fs.path.join(gpa, &.{ dir_path, entry.name });
        errdefer gpa.free(full);

        // Peek header for id/name
        const raw = std.Io.Dir.cwd().readFileAlloc(io, full, gpa, .limited(64 * 1024)) catch {
            gpa.free(full);
            continue;
        };
        defer gpa.free(raw);

        var id_owned = try gpa.dupe(u8, entry.name);
        errdefer gpa.free(id_owned);
        var name_owned = try gpa.dupe(u8, "");
        errdefer gpa.free(name_owned);
        if (std.mem.indexOfScalar(u8, raw, '\n')) |nl| {
            var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw[0..nl], .{}) catch {
                try list.append(gpa, .{
                    .path = full,
                    .id = id_owned,
                    .name = name_owned,
                });
                continue;
            };
            defer parsed.deinit();
            if (parsed.value == .object) {
                if (parsed.value.object.get("id")) |v| {
                    if (v == .string) {
                        gpa.free(id_owned);
                        id_owned = try gpa.dupe(u8, v.string);
                    }
                }
                if (parsed.value.object.get("name")) |v| {
                    if (v == .string) {
                        gpa.free(name_owned);
                        name_owned = try gpa.dupe(u8, v.string);
                    }
                }
            }
        }
        try list.append(gpa, .{
            .path = full,
            .id = id_owned,
            .name = name_owned,
        });
    }
    return try list.toOwnedSlice(gpa);
}

/// Most recently modified-looking session path (last in list for simplicity; name order).
pub fn mostRecentSessionPath(gpa: std.mem.Allocator, io: Io, dir_path: []const u8) !?[]u8 {
    const sessions = try listSessions(gpa, io, dir_path);
    defer {
        for (sessions) |*s| {
            var mut = s.*;
            mut.deinit(gpa);
        }
        gpa.free(sessions);
    }
    if (sessions.len == 0) return null;
    // Pick last by path name (sessions are often timestamp-named)
    return try gpa.dupe(u8, sessions[sessions.len - 1].path);
}

pub fn newSessionPath(gpa: std.mem.Allocator, session_dir: []const u8, id: []const u8) ![]u8 {
    const file = try std.fmt.allocPrint(gpa, "{s}.jsonl", .{id});
    defer gpa.free(file);
    return try std.fs.path.join(gpa, &.{ session_dir, file });
}

var session_id_counter: u64 = 1;

pub fn generateSessionId(gpa: std.mem.Allocator) ![]u8 {
    // Unique-enough id without depending on wall clock API.
    const n = session_id_counter;
    session_id_counter +%= 1;
    const mix: u64 = n *% 0x9e3779b97f4a7c15;
    return try std.fmt.allocPrint(gpa, "s{d}-{x}", .{ n, mix });
}

test "session save then load roundtrip" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];
    const session_path = try std.fs.path.join(gpa, &.{ tmp_path, "session.jsonl" });
    defer gpa.free(session_path);

    var s = try Session.init(gpa, "sess-1", tmp_path);
    defer s.deinit();
    try s.setName("test");

    const user_id = try s.appendMessage(null, "user", "hello", null, null);
    _ = try s.appendMessage(user_id, "assistant", "hi there", null, null);

    try s.save(io, session_path);

    var loaded = try Session.load(gpa, io, session_path);
    defer loaded.deinit();

    try std.testing.expectEqualStrings("sess-1", loaded.id);
    try std.testing.expectEqualStrings("test", loaded.name);
    try std.testing.expectEqual(@as(usize, 2), loaded.entries.items.len);
    try std.testing.expectEqualStrings("user", loaded.entries.items[0].role);
    try std.testing.expectEqualStrings("hello", loaded.entries.items[0].content);
    try std.testing.expectEqualStrings("assistant", loaded.entries.items[1].role);
    try std.testing.expectEqualStrings(user_id, loaded.entries.items[1].parent_id.?);
}

test "session fork copies branch" {
    const gpa = std.testing.allocator;
    var s = try Session.init(gpa, "orig", "/tmp");
    defer s.deinit();
    const u = try s.appendMessage(null, "user", "hi", null, null);
    _ = try s.appendMessage(u, "assistant", "yo", null, null);

    var f = try s.fork(gpa, "forked");
    defer f.deinit();
    try std.testing.expectEqualStrings("forked", f.id);
    try std.testing.expectEqual(@as(usize, 2), f.entries.items.len);
    try std.testing.expectEqualStrings("hi", f.entries.items[0].content);
}

test "listSessions and mostRecentSessionPath" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const dir = path_buf[0..n];

    var s = try Session.init(gpa, "list-me", dir);
    defer s.deinit();
    _ = try s.appendMessage(null, "user", "x", null, null);
    const path = try newSessionPath(gpa, dir, "list-me");
    defer gpa.free(path);
    try s.save(io, path);

    const listed = try listSessions(gpa, io, dir);
    defer {
        for (listed) |*info| {
            var mut = info.*;
            mut.deinit(gpa);
        }
        gpa.free(listed);
    }
    try std.testing.expect(listed.len >= 1);
    try std.testing.expectEqualStrings("list-me", listed[0].id);

    const recent = try mostRecentSessionPath(gpa, io, dir);
    defer if (recent) |r| gpa.free(r);
    try std.testing.expect(recent != null);
    try std.testing.expect(std.mem.indexOf(u8, recent.?, "list-me") != null);
}
