//! Full file inventory equality. No output subset or assertion filter.
const std = @import("std");
const w = @import("win32.zig");
const files = @import("files.zig");
const Deadline = @import("deadline.zig").Deadline;
const Row = struct { path: []const u8, sha256: []const u8 };
const RelativeRow = struct { relative: []const u8, sha256: []const u8 };
pub const Expected = struct { sha256: files.Hash, seen: bool = false };
pub const Manifest = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMapUnmanaged(Expected) = .empty,

    pub fn loadAbsolute(allocator: std.mem.Allocator, path: []const u8, prefix: []const u8, count: usize) !Manifest {
        const bytes = try files.readBounded(allocator, path, 32 * 1024 * 1024);
        defer allocator.free(bytes);
        const parsed = try std.json.parseFromSlice([]Row, allocator, bytes, .{});
        defer parsed.deinit();
        if (parsed.value.len != count or count > 40000) return error.ManifestCountMismatch;
        var self: Manifest = .{ .allocator = allocator };
        errdefer self.deinit();
        for (parsed.value) |row| {
            if (!std.mem.startsWith(u8, row.path, prefix)) return error.ManifestPrefixMismatch;
            try self.add(row.path[prefix.len..], row.sha256);
        }
        return self;
    }
    pub fn loadJsonl(allocator: std.mem.Allocator, path: []const u8, count: usize) !Manifest {
        const bytes = try files.readBounded(allocator, path, 32 * 1024 * 1024);
        defer allocator.free(bytes);
        var self: Manifest = .{ .allocator = allocator };
        errdefer self.deinit();
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            if (line.len > 262144) return error.ManifestLineLimit;
            const parsed = try std.json.parseFromSlice(RelativeRow, allocator, line, .{ .ignore_unknown_fields = true });
            defer parsed.deinit();
            try self.add(parsed.value.relative, parsed.value.sha256);
            if (self.entries.count() > 40000) return error.ManifestEntryLimit;
        }
        if (self.entries.count() != count) return error.ManifestCountMismatch;
        return self;
    }
    /// Call only with rows from an already control-hashed immutable manifest.
    pub fn add(self: *Manifest, relative: []const u8, sha: []const u8) !void {
        try files.relative(relative);
        if (sha.len != 64) return error.InvalidManifestHash;
        var hash: files.Hash = undefined;
        _ = try std.fmt.hexToBytes(&hash, sha);
        const key = try self.allocator.dupe(u8, relative);
        errdefer self.allocator.free(key);
        const entry = try self.entries.getOrPut(self.allocator, key);
        if (entry.found_existing) return error.DuplicateManifestPath;
        entry.value_ptr.* = .{ .sha256 = hash };
    }
    pub fn remove(self: *Manifest, relative: []const u8) !void {
        const removed = self.entries.fetchRemove(relative) orelse return error.ManifestProjectionMissing;
        self.allocator.free(removed.key);
    }
    pub fn deinit(self: *Manifest) void {
        var keys = self.entries.keyIterator();
        while (keys.next()) |key| self.allocator.free(key.*);
        self.entries.deinit(self.allocator);
        self.* = undefined;
    }
};

pub const Record = union(enum) {
    file: struct { relative: []const u8, sha256: files.Hash, expected: ?files.Hash },
    reparse: struct { relative: []const u8, tag: u32 },
    missing: struct { relative: []const u8, expected: files.Hash },
};
pub const Sink = struct {
    context: *anyopaque,
    write_fn: *const fn (*anyopaque, Record) anyerror!void,
    pub fn write(self: Sink, record: Record) !void { try self.write_fn(self.context, record); }
};
pub const Report = struct {
    required: usize,
    actual: usize = 0,
    matching: usize = 0,
    drift: usize = 0,
    extras: usize = 0,
    missing: usize = 0,
    reparse_points: usize = 0,
    inventory_complete: bool = false,
    pub fn requireExact(self: Report, expected_links: usize) !void {
        if (!self.inventory_complete or self.actual != self.required or self.matching != self.required or
            self.drift != 0 or self.extras != 0 or self.missing != 0 or self.reparse_points != expected_links)
            return error.FullInventoryComparisonNegative;
    }
};

pub fn checkTree(allocator: std.mem.Allocator, root: []const u8, expected: *Manifest,
    deadline: Deadline, sink: Sink) !Report
{
    try files.absolute(root);
    try files.requirePhysicalAncestors(allocator, root);
    const root_handle = try files.openLeaf(allocator, root, w.generic_read, w.open_existing, w.file_flag_backup_semantics);
    defer _ = w.CloseHandle(root_handle);
    const root_tag = try files.requirePhysical(root_handle);
    if (root_tag.attributes & w.file_attribute_directory == 0) return error.InventoryRootNotDirectory;
    var entries = expected.entries.valueIterator();
    while (entries.next()) |entry| entry.seen = false;
    var result: Report = .{ .required = expected.entries.count() };
    var stack: std.ArrayList([]u8) = .empty;
    defer {
        for (stack.items) |item| allocator.free(item);
        stack.deinit(allocator);
    }
    try stack.append(allocator, try allocator.dupe(u8, root));
    while (stack.pop()) |directory| {
        defer allocator.free(directory);
        try deadline.normal();
        var walk = try files.Walk.open(allocator, directory);
        defer walk.close() catch {};
        while (try walk.next()) |entry| {
            try deadline.normal();
            const units = std.mem.indexOfScalar(u16, &entry.name, 0) orelse return error.UnterminatedFilename;
            const name = try std.unicode.utf16LeToUtf8Alloc(allocator, entry.name[0..units]);
            defer allocator.free(name);
            const path = try files.join(allocator, directory, name);
            defer allocator.free(path);
            try files.contained(path, root);
            const relative = path[root.len + 1..];
            if (entry.attributes & w.file_attribute_reparse_point != 0) {
                result.reparse_points += 1;
                try sink.write(.{ .reparse = .{ .relative = relative, .tag = entry.reserved0 } });
                continue; // Never traverse an unreviewed link.
            }
            if (entry.attributes & w.file_attribute_directory != 0) {
                if (stack.items.len >= 65536) return error.DirectoryStackLimit;
                try stack.append(allocator, try allocator.dupe(u8, path));
                continue;
            }
            if (result.actual >= 65536) return error.InventoryFileLimit;
            const digest = try files.hash(allocator, path);
            result.actual += 1;
            var expected_digest: ?files.Hash = null;
            if (expected.entries.getPtr(relative)) |wanted| {
                if (wanted.seen) return error.DuplicateActualInventoryPath;
                wanted.seen = true;
                expected_digest = wanted.sha256;
                if (std.mem.eql(u8, &digest, &wanted.sha256)) result.matching += 1 else result.drift += 1;
            } else result.extras += 1;
            try sink.write(.{ .file = .{ .relative = relative, .sha256 = digest, .expected = expected_digest } });
        }
    }
    var all = expected.entries.iterator();
    while (all.next()) |entry| {
        if (!entry.value_ptr.seen) {
            result.missing += 1;
            try sink.write(.{ .missing = .{ .relative = entry.key_ptr.*, .expected = entry.value_ptr.sha256 } });
        }
    }
    result.inventory_complete = true;
    return result;
}
