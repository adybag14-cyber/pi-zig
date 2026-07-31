//! Lightweight session index store (sqlite-package stand-in without C deps).
//! JSONL index file mapping session id → path, name, mtime, message count.
const std = @import("std");
const Io = std.Io;

pub const IndexEntry = struct {
    id: []const u8,
    path: []const u8,
    name: []const u8,
    message_count: u64 = 0,
    mtime_iso: []const u8 = "",

    pub fn deinit(self: *IndexEntry, gpa: std.mem.Allocator) void {
        gpa.free(self.id);
        gpa.free(self.path);
        gpa.free(self.name);
        if (self.mtime_iso.len > 0) gpa.free(self.mtime_iso);
        self.* = undefined;
    }
};

pub const SessionIndex = struct {
    gpa: std.mem.Allocator,
    io: Io,
    path: []const u8,
    entries: std.ArrayList(IndexEntry) = .empty,

    pub fn deinit(self: *SessionIndex) void {
        for (self.entries.items) |*e| e.deinit(self.gpa);
        self.entries.deinit(self.gpa);
        self.gpa.free(self.path);
        self.* = undefined;
    }

    pub fn open(gpa: std.mem.Allocator, io: Io, index_path: []const u8) !SessionIndex {
        var idx = SessionIndex{
            .gpa = gpa,
            .io = io,
            .path = try gpa.dupe(u8, index_path),
        };
        const raw = std.Io.Dir.cwd().readFileAlloc(io, index_path, gpa, .limited(8 * 1024 * 1024)) catch {
            return idx;
        };
        defer gpa.free(raw);
        var it = std.mem.splitScalar(u8, raw, '\n');
        while (it.next()) |line| {
            const t = std.mem.trim(u8, line, " \t\r");
            if (t.len == 0) continue;
            var parsed = std.json.parseFromSlice(std.json.Value, gpa, t, .{}) catch continue;
            defer parsed.deinit();
            if (parsed.value != .object) continue;
            const id = if (parsed.value.object.get("id")) |v| (if (v == .string) v.string else continue) else continue;
            const path = if (parsed.value.object.get("path")) |v| (if (v == .string) v.string else continue) else continue;
            const name = if (parsed.value.object.get("name")) |v| (if (v == .string) v.string else "") else "";
            var mc: u64 = 0;
            if (parsed.value.object.get("messageCount")) |v| {
                if (v == .integer) mc = @intCast(v.integer);
            }
            const mt = if (parsed.value.object.get("mtime")) |v| (if (v == .string) v.string else "") else "";
            try idx.entries.append(gpa, .{
                .id = try gpa.dupe(u8, id),
                .path = try gpa.dupe(u8, path),
                .name = try gpa.dupe(u8, name),
                .message_count = mc,
                .mtime_iso = if (mt.len > 0) try gpa.dupe(u8, mt) else "",
            });
        }
        return idx;
    }

    pub fn upsert(self: *SessionIndex, id: []const u8, path: []const u8, name: []const u8, message_count: u64, mtime_iso: []const u8) !void {
        for (self.entries.items) |*e| {
            if (std.mem.eql(u8, e.id, id)) {
                self.gpa.free(e.path);
                self.gpa.free(e.name);
                if (e.mtime_iso.len > 0) self.gpa.free(e.mtime_iso);
                e.path = try self.gpa.dupe(u8, path);
                e.name = try self.gpa.dupe(u8, name);
                e.message_count = message_count;
                e.mtime_iso = if (mtime_iso.len > 0) try self.gpa.dupe(u8, mtime_iso) else "";
                return;
            }
        }
        try self.entries.append(self.gpa, .{
            .id = try self.gpa.dupe(u8, id),
            .path = try self.gpa.dupe(u8, path),
            .name = try self.gpa.dupe(u8, name),
            .message_count = message_count,
            .mtime_iso = if (mtime_iso.len > 0) try self.gpa.dupe(u8, mtime_iso) else "",
        });
    }

    pub fn save(self: *const SessionIndex) !void {
        var aw: std.Io.Writer.Allocating = .init(self.gpa);
        defer aw.deinit();
        for (self.entries.items) |e| {
            try aw.writer.writeAll("{\"id\":");
            try std.json.Stringify.value(e.id, .{}, &aw.writer);
            try aw.writer.writeAll(",\"path\":");
            try std.json.Stringify.value(e.path, .{}, &aw.writer);
            try aw.writer.writeAll(",\"name\":");
            try std.json.Stringify.value(e.name, .{}, &aw.writer);
            try aw.writer.writeAll(",\"messageCount\":");
            try aw.writer.print("{d}", .{e.message_count});
            if (e.mtime_iso.len > 0) {
                try aw.writer.writeAll(",\"mtime\":");
                try std.json.Stringify.value(e.mtime_iso, .{}, &aw.writer);
            }
            try aw.writer.writeAll("}\n");
        }
        if (std.fs.path.dirname(self.path)) |parent| {
            if (parent.len > 0) try std.Io.Dir.cwd().createDirPath(self.io, parent);
        }
        try std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = self.path, .data = aw.written() });
    }
};

test "session index upsert save load" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const dir = path_buf[0..n];
    const ipath = try std.fs.path.join(gpa, &.{ dir, "index.jsonl" });
    defer gpa.free(ipath);

    var idx = try SessionIndex.open(gpa, io, ipath);
    defer idx.deinit();
    try idx.upsert("s1", "/tmp/a.jsonl", "alpha", 3, "2024-01-01T00:00:00.000Z");
    try idx.save();

    var idx2 = try SessionIndex.open(gpa, io, ipath);
    defer idx2.deinit();
    try std.testing.expectEqual(@as(usize, 1), idx2.entries.items.len);
    try std.testing.expectEqualStrings("s1", idx2.entries.items[0].id);
    try std.testing.expectEqual(@as(u64, 3), idx2.entries.items[0].message_count);
}
