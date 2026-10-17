//! Worker-only bounded filesystem primitives. Never called on the timing thread.
const std = @import("std");
const w = @import("win32.zig");
pub const container = "C:\\Users\\adyba\\pi-zig";
pub const Hash = [32]u8;

pub fn contained(path: []const u8, root: []const u8) !void {
    try absolute(path);
    try absolute(root);
    if (path.len <= root.len or path[root.len] != '\\' or
        !std.ascii.eqlIgnoreCase(path[0..root.len], root)) return error.PathOutsideReviewedRoot;
}
pub fn absolute(path: []const u8) !void {
    if (path.len < 4 or !std.ascii.isAlphabetic(path[0]) or path[1] != ':' or path[2] != '\\' or
        std.mem.indexOfAny(u8, path[3..], ":/\x00") != null) return error.InvalidAbsolutePath;
    var pieces = std.mem.splitScalar(u8, path[3..], '\\');
    while (pieces.next()) |piece| {
        if (piece.len == 0 or std.mem.eql(u8, piece, ".") or std.mem.eql(u8, piece, "..") or
            piece[piece.len - 1] == '.' or piece[piece.len - 1] == ' ') return error.AmbiguousPathComponent;
    }
}
pub fn relative(path: []const u8) !void {
    if (path.len == 0 or std.mem.indexOfAny(u8, path, ":/\x00") != null) return error.InvalidRelativePath;
    var pieces = std.mem.splitScalar(u8, path, '\\');
    while (pieces.next()) |piece| {
        if (piece.len == 0 or std.mem.eql(u8, piece, ".") or std.mem.eql(u8, piece, "..") or
            piece[piece.len - 1] == '.' or piece[piece.len - 1] == ' ') return error.AmbiguousPathComponent;
    }
}
pub fn join(allocator: std.mem.Allocator, root: []const u8, rel: []const u8) ![]u8 {
    try relative(rel);
    const path = try std.fmt.allocPrint(allocator, "{s}\\{s}", .{ root, rel });
    errdefer allocator.free(path);
    try contained(path, root);
    return path;
}
fn wide(allocator: std.mem.Allocator, path: []const u8) ![:0]u16 {
    try absolute(path);
    const long = try std.fmt.allocPrint(allocator, "\\\\?\\{s}", .{path});
    defer allocator.free(long);
    return std.unicode.utf8ToUtf16LeAllocZ(allocator, long);
}
pub fn openLeaf(allocator: std.mem.Allocator, path: []const u8, access: u32, creation: u32, flags: u32) !w.H {
    const name = try wide(allocator, path);
    defer allocator.free(name);
    const handle = w.CreateFileW(name.ptr, access, w.share_read, null, creation,
        flags | w.file_flag_open_reparse_point, null);
    if (handle == w.invalid) return error.FileOpenFailed;
    return handle;
}
pub fn requirePhysical(handle: w.H) !w.AttributeTag {
    var tag: w.AttributeTag = undefined;
    if (w.GetFileInformationByHandleEx(handle, 9, &tag, @sizeOf(w.AttributeTag)) == 0)
        return error.FileAttributesUnverifiable;
    if (tag.attributes & w.file_attribute_reparse_point != 0) return error.UnapprovedReparsePoint;
    return tag;
}
pub fn requirePhysicalAncestors(allocator: std.mem.Allocator, path: []const u8) !void {
    try absolute(path);
    var end: usize = 3;
    while (end < path.len) {
        const next = std.mem.indexOfScalarPos(u8, path, end, '\\') orelse break;
        const handle = try openLeaf(allocator, path[0..next], w.generic_read, w.open_existing, w.file_flag_backup_semantics);
        defer _ = w.CloseHandle(handle);
        const tag = try requirePhysical(handle);
        if (tag.attributes & w.file_attribute_directory == 0) return error.ParentNotDirectory;
        end = next + 1;
    }
}

pub const Pinned = struct {
    handle: ?w.H,
    id: w.FileId,
    size: u64,
    digest_attempted: bool = false,
    pub fn open(allocator: std.mem.Allocator, path: []const u8) !Pinned {
        try requirePhysicalAncestors(allocator, path);
        const handle = try openLeaf(allocator, path, w.generic_read, w.open_existing, 0);
        errdefer _ = w.CloseHandle(handle);
        const tag = try requirePhysical(handle);
        if (tag.attributes & w.file_attribute_directory != 0) return error.ExpectedRegularFile;
        var id: w.FileId = undefined;
        if (w.GetFileInformationByHandleEx(handle, 18, &id, @sizeOf(w.FileId)) == 0) return error.FileIdUnverifiable;
        var size: i64 = 0;
        if (w.GetFileSizeEx(handle, &size) == 0 or size < 0) return error.FileSizeUnverifiable;
        return .{ .handle = handle, .id = id, .size = @intCast(size) };
    }
    /// One shot: ReadFile consumes the synchronous pointer. Retain the pin for
    /// identity/locking, or open a new verified pin for another digest.
    pub fn digest(self: *Pinned, comptime Hasher: type) ![Hasher.digest_length]u8 {
        const handle = self.handle orelse return error.PinnedFileClosed;
        if (self.digest_attempted) return error.PinnedDigestAlreadyAttempted;
        self.digest_attempted = true;
        var state = Hasher.init(.{});
        var buffer: [65536]u8 = undefined;
        var total: u64 = 0;
        while (true) {
            var count: u32 = 0;
            if (w.ReadFile(handle, &buffer, buffer.len, &count, null) == 0) return error.FileHashReadFailed;
            if (count == 0) break;
            if (count > buffer.len or total + count > self.size) return error.FileSizeChanged;
            state.update(buffer[0..count]);
            total += count;
        }
        if (total != self.size) return error.FileSizeChanged;
        var result: [Hasher.digest_length]u8 = undefined;
        state.final(&result);
        return result;
    }
    pub fn close(self: *Pinned) !void {
        if (self.handle) |handle| {
            if (w.CloseHandle(handle) == 0) return error.PinnedFileCloseFailed;
            self.handle = null;
        }
    }
};
pub fn hash(allocator: std.mem.Allocator, path: []const u8) !Hash {
    var pinned = try Pinned.open(allocator, path);
    defer pinned.close() catch {};
    return pinned.digest(std.crypto.hash.sha2.Sha256);
}
pub fn hash512(allocator: std.mem.Allocator, path: []const u8) ![64]u8 {
    var pinned = try Pinned.open(allocator, path);
    defer pinned.close() catch {};
    return pinned.digest(std.crypto.hash.sha2.Sha512);
}
pub fn readBounded(allocator: std.mem.Allocator, path: []const u8, limit: usize) ![]u8 {
    var pinned = try Pinned.open(allocator, path);
    defer pinned.close() catch {};
    if (pinned.size > limit) return error.InputFileLimit;
    const bytes = try allocator.alloc(u8, @intCast(pinned.size));
    errdefer allocator.free(bytes);
    var offset: usize = 0;
    while (offset < bytes.len) {
        var count: u32 = 0;
        const amount: u32 = @intCast(@min(bytes.len - offset, 65536));
        if (w.ReadFile(pinned.handle.?, bytes[offset..].ptr, amount, &count, null) == 0 or count == 0 or count > amount)
            return error.InputReadFailed;
        offset += count;
    }
    return bytes;
}

pub const Walk = struct {
    search: ?w.H = null,
    current: w.FindData = undefined,
    first: bool = true,
    pub fn open(allocator: std.mem.Allocator, dir: []const u8) !Walk {
        // Callers have already rejected/recorded the directory's reparse status.
        const pattern = try std.fmt.allocPrint(allocator, "\\\\?\\{s}\\*", .{dir});
        defer allocator.free(pattern);
        const name = try std.unicode.utf8ToUtf16LeAllocZ(allocator, pattern);
        defer allocator.free(name);
        var result: Walk = .{};
        const handle = w.FindFirstFileW(name.ptr, &result.current);
        if (handle == w.invalid) return error.DirectoryEnumerationFailed;
        result.search = handle;
        return result;
    }
    pub fn next(self: *Walk) !?*const w.FindData {
        while (true) {
            if (self.first) self.first = false else {
                if (w.FindNextFileW(self.search orelse return error.DirectoryWalkClosed, &self.current) == 0) {
                    if (w.GetLastError() == 18) return null; // ERROR_NO_MORE_FILES
                    return error.DirectoryEnumerationFailed;
                }
            }
            const zero = std.mem.indexOfScalar(u16, &self.current.name, 0) orelse return error.UnterminatedFilename;
            const name = self.current.name[0..zero];
            if (std.mem.eql(u16, name, &.{'.'}) or std.mem.eql(u16, name, &.{ '.', '.' })) continue;
            return &self.current;
        }
    }
    pub fn close(self: *Walk) !void {
        if (self.search) |search| {
            if (w.FindClose(search) == 0) return error.DirectoryWalkCloseFailed;
            self.search = null;
        }
    }
};
