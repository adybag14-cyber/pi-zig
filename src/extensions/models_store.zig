//! Locked, atomic persistence for extension-owned dynamic model catalogs.
//!
//! The file format is upstream-compatible `models-store.json`: a JSON object
//! keyed by provider ID whose values are `ModelsStoreEntry` objects. A sidecar
//! advisory lock survives atomic replacement of the data file, so cooperating
//! readers and writers never observe a torn read/modify/write transaction.
const std = @import("std");
const Io = std.Io;

const max_store_bytes: usize = 16 * 1024 * 1024;

fn ensureNotAborted(abort_flag: ?*const bool) !void {
    if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.Canceled;
}

fn permissions0600() std.Io.File.Permissions {
    if (@hasDecl(std.Io.File.Permissions, "fromMode")) return std.Io.File.Permissions.fromMode(0o600);
    return .default_file;
}

fn validateTimestamp(value: std.json.Value) !void {
    switch (value) {
        .integer, .float => {},
        else => return error.InvalidModelsStoreEntry,
    }
}

/// Validate the storage envelope. Model-specific semantic validation is also
/// performed by provider_registry against the effective provider config before
/// a write or catalog publication is accepted.
pub fn validateEntryValue(value: std.json.Value) !void {
    if (value != .object) return error.InvalidModelsStoreEntry;
    const models = value.object.get("models") orelse return error.InvalidModelsStoreEntry;
    if (models != .array) return error.InvalidModelsStoreEntry;
    for (models.array.items) |model| if (model != .object) return error.InvalidModelsStoreEntry;
    if (value.object.get("lastModified")) |timestamp| try validateTimestamp(timestamp);
    if (value.object.get("checkedAt")) |timestamp| try validateTimestamp(timestamp);
    if (value.object.get("etag")) |etag| if (etag != .string) return error.InvalidModelsStoreEntry;
}

pub fn validateEntryJson(gpa: std.mem.Allocator, raw: []const u8) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return error.InvalidModelsStoreEntry;
    defer parsed.deinit();
    try validateEntryValue(parsed.value);
}

pub const Store = struct {
    gpa: std.mem.Allocator,
    io: Io,
    path: []u8,
    lock_path: []u8,

    pub fn init(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8) !Store {
        const path = try std.fs.path.join(gpa, &.{ agent_dir, "models-store.json" });
        errdefer gpa.free(path);
        const lock_path = try std.fmt.allocPrint(gpa, "{s}.lock", .{path});
        return .{ .gpa = gpa, .io = io, .path = path, .lock_path = lock_path };
    }

    pub fn initPath(gpa: std.mem.Allocator, io: Io, owned_path: []u8) !Store {
        const lock_path = try std.fmt.allocPrint(gpa, "{s}.lock", .{owned_path});
        return .{ .gpa = gpa, .io = io, .path = owned_path, .lock_path = lock_path };
    }

    pub fn deinit(self: *Store) void {
        self.gpa.free(self.path);
        self.gpa.free(self.lock_path);
        self.* = undefined;
    }

    fn ensureParent(self: *const Store) !void {
        if (std.fs.path.dirname(self.path)) |parent| try std.Io.Dir.cwd().createDirPath(self.io, parent);
    }

    fn openLock(self: *const Store, lock: std.Io.File.Lock) !std.Io.File {
        try self.ensureParent();
        const file = try std.Io.Dir.cwd().createFile(self.io, self.lock_path, .{
            .read = true,
            .truncate = false,
            .lock = lock,
            .permissions = permissions0600(),
        });
        file.setPermissions(self.io, permissions0600()) catch {};
        return file;
    }

    fn readRootAlloc(self: *const Store) !?[]u8 {
        const file = std.Io.Dir.cwd().openFile(self.io, self.path, .{ .mode = .read_only }) catch |err| switch (err) {
            error.FileNotFound => return null,
            else => return err,
        };
        defer file.close(self.io);
        const len64 = try file.length(self.io);
        if (len64 > max_store_bytes) return error.ModelsStoreTooLarge;
        const len: usize = @intCast(len64);
        const raw = try self.gpa.alloc(u8, len);
        errdefer self.gpa.free(raw);
        if (len > 0) {
            const got = try file.readPositionalAll(self.io, raw, 0);
            if (got != len) return error.UnexpectedEndOfFile;
        }
        return raw;
    }

    fn parseRoot(self: *const Store, raw: ?[]const u8) !std.json.Parsed(std.json.Value) {
        const input = if (raw) |value| if (value.len == 0) "{}" else value else "{}";
        var parsed = std.json.parseFromSlice(std.json.Value, self.gpa, input, .{}) catch return error.InvalidModelsStore;
        errdefer parsed.deinit();
        if (parsed.value != .object) return error.InvalidModelsStore;
        return parsed;
    }

    fn writeAtomic(self: *const Store, raw: []const u8, abort_flag: ?*const bool) !void {
        if (raw.len > max_store_bytes) return error.ModelsStoreTooLarge;
        try ensureNotAborted(abort_flag);
        var atomic = try std.Io.Dir.cwd().createFileAtomic(self.io, self.path, .{
            .permissions = permissions0600(),
            .make_path = true,
            .replace = true,
        });
        defer atomic.deinit(self.io);
        try atomic.file.writePositionalAll(self.io, raw, 0);
        atomic.file.setPermissions(self.io, permissions0600()) catch {};
        try atomic.file.sync(self.io);
        // A canceled generation may prepare a temporary file, but it must never
        // make that file authoritative after cancellation becomes observable.
        try ensureNotAborted(abort_flag);
        try atomic.replace(self.io);
    }

    fn composeRoot(
        self: *const Store,
        root: std.json.Value,
        provider_id: []const u8,
        replacement_json: ?[]const u8,
    ) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(self.gpa);
        errdefer out.deinit();
        try out.writer.writeByte('{');
        var first = true;
        var iterator = root.object.iterator();
        while (iterator.next()) |entry| {
            if (std.mem.eql(u8, entry.key_ptr.*, provider_id)) continue;
            if (!first) try out.writer.writeByte(',');
            first = false;
            try std.json.Stringify.value(entry.key_ptr.*, .{}, &out.writer);
            try out.writer.writeByte(':');
            try std.json.Stringify.value(entry.value_ptr.*, .{}, &out.writer);
        }
        if (replacement_json) |replacement| {
            if (!first) try out.writer.writeByte(',');
            try std.json.Stringify.value(provider_id, .{}, &out.writer);
            try out.writer.writeByte(':');
            try out.writer.writeAll(replacement);
        }
        try out.writer.writeAll("}\n");
        return out.toOwnedSlice();
    }

    /// Return an owned immutable-snapshot JSON object for one provider.
    pub fn read(self: *const Store, provider_id: []const u8) !?[]u8 {
        const lock = try self.openLock(.shared);
        defer lock.close(self.io);
        const raw = (try self.readRootAlloc()) orelse return null;
        defer self.gpa.free(raw);
        var parsed = try self.parseRoot(raw);
        defer parsed.deinit();
        const value = parsed.value.object.get(provider_id) orelse return null;
        try validateEntryValue(value);
        var out: std.Io.Writer.Allocating = .init(self.gpa);
        errdefer out.deinit();
        try std.json.Stringify.value(value, .{}, &out.writer);
        return @as(?[]u8, try out.toOwnedSlice());
    }

    /// Atomically replace one provider entry while preserving unrelated providers.
    pub fn write(self: *const Store, provider_id: []const u8, entry_json: []const u8) !void {
        return self.writeAbortable(provider_id, entry_json, null);
    }

    pub fn writeAbortable(
        self: *const Store,
        provider_id: []const u8,
        entry_json: []const u8,
        abort_flag: ?*const bool,
    ) !void {
        try ensureNotAborted(abort_flag);
        try validateEntryJson(self.gpa, entry_json);
        const lock = try self.openLock(.exclusive);
        defer lock.close(self.io);
        try ensureNotAborted(abort_flag);
        const raw = try self.readRootAlloc();
        defer if (raw) |value| self.gpa.free(value);
        var parsed = try self.parseRoot(raw);
        defer parsed.deinit();
        const next = try self.composeRoot(parsed.value, provider_id, entry_json);
        defer self.gpa.free(next);
        try self.writeAtomic(next, abort_flag);
    }

    /// Atomically delete one provider entry. Missing entries leave the file untouched.
    pub fn delete(self: *const Store, provider_id: []const u8) !void {
        return self.deleteAbortable(provider_id, null);
    }

    pub fn deleteAbortable(self: *const Store, provider_id: []const u8, abort_flag: ?*const bool) !void {
        try ensureNotAborted(abort_flag);
        const lock = try self.openLock(.exclusive);
        defer lock.close(self.io);
        try ensureNotAborted(abort_flag);
        const raw = (try self.readRootAlloc()) orelse return;
        defer self.gpa.free(raw);
        var parsed = try self.parseRoot(raw);
        defer parsed.deinit();
        if (parsed.value.object.get(provider_id) == null) return;
        const next = try self.composeRoot(parsed.value, provider_id, null);
        defer self.gpa.free(next);
        try self.writeAtomic(next, abort_flag);
    }
};

test "extension models store writes deletes and preserves unrelated entries atomically" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const path = try std.fs.path.join(gpa, &.{ root_buf[0..root_len], "models-store.json" });
    var store = try Store.initPath(gpa, io, path);
    defer store.deinit();

    try store.write("other", "{\"models\":[],\"checkedAt\":1}");
    try store.write("dynamic", "{\"models\":[{\"id\":\"one\"}],\"etag\":\"\\\"v1\\\"\"}");
    const entry = (try store.read("dynamic")).?;
    defer gpa.free(entry);
    try std.testing.expect(std.mem.indexOf(u8, entry, "\\\"v1\\\"") != null);
    try store.delete("dynamic");
    try std.testing.expect((try store.read("dynamic")) == null);
    const other = (try store.read("other")).?;
    defer gpa.free(other);
    try std.testing.expect(std.mem.indexOf(u8, other, "\"checkedAt\":1") != null);
}

test "extension models store rejects invalid entry without replacing committed data" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    var store = try Store.init(gpa, io, root_buf[0..root_len]);
    defer store.deinit();
    try store.write("dynamic", "{\"models\":[],\"checkedAt\":7}");
    try std.testing.expectError(error.InvalidModelsStoreEntry, store.write("dynamic", "{\"models\":{}}"));
    var canceled = true;
    try std.testing.expectError(error.Canceled, store.writeAbortable("dynamic", "{\"models\":[],\"checkedAt\":8}", &canceled));
    try std.testing.expectError(error.Canceled, store.deleteAbortable("dynamic", &canceled));
    const entry = (try store.read("dynamic")).?;
    defer gpa.free(entry);
    try std.testing.expect(std.mem.indexOf(u8, entry, "\"checkedAt\":7") != null);
}
