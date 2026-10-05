//! Owned durable values; expected operation failures are explicit results.
const std = @import("std");
pub const FileKind = enum { file, directory, symlink };
pub const FileErrorCode = enum { aborted, not_found, permission_denied, not_directory, is_directory, invalid, not_supported, unknown };
pub const FileError = struct {
    code: FileErrorCode,
    message: []const u8,
    path: ?[]u8 = null,
    cause: ?anyerror = null,
    pub fn deinit(self: *FileError, gpa: std.mem.Allocator) void {
        if (self.path) |path| gpa.free(path);
        self.* = undefined;
    }
};
pub fn Result(comptime T: type) type {
    return union(enum) { value: T, failure: FileError };
}
pub fn failure(comptime T: type, gpa: std.mem.Allocator, code: FileErrorCode, path: ?[]const u8, cause: ?anyerror, message: []const u8) !Result(T) {
    return .{ .failure = .{ .code = code, .path = if (path) |value| try gpa.dupe(u8, value) else null, .cause = cause, .message = message } };
}
pub fn fromError(comptime T: type, gpa: std.mem.Allocator, err: anyerror, path: ?[]const u8) !Result(T) {
    if (err == error.OutOfMemory) return err;
    const code: FileErrorCode = switch (err) {
        error.Canceled => .aborted,
        error.FileNotFound => .not_found,
        error.AccessDenied, error.PermissionDenied => .permission_denied,
        error.NotDir => .not_directory,
        error.IsDir => .is_directory,
        error.InvalidArgument, error.BadPathName, error.InvalidPath => .invalid,
        error.OperationUnsupported => .not_supported,
        else => .unknown,
    };
    return failure(T, gpa, code, path, err, @errorName(err));
}
pub const Context = struct {
    abort_flag: ?*const std.atomic.Value(bool) = null,
    pub fn aborted(self: Context) bool {
        return if (self.abort_flag) |flag| flag.load(.acquire) else false;
    }
};
pub const FileInfo = struct {
    name: []u8,
    path: []u8,
    kind: FileKind,
    size: u64,
    mtimeMs: f64,
    pub fn deinit(self: *FileInfo, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        gpa.free(self.path);
        self.* = undefined;
    }
};
pub fn fileInfo(gpa: std.mem.Allocator, path: []const u8, stat: std.Io.File.Stat) !?FileInfo {
    const kind: FileKind = switch (stat.kind) {
        .file => .file,
        .directory => .directory,
        .sym_link => .symlink,
        else => return null,
    };
    const name = try gpa.dupe(u8, std.fs.path.basename(path));
    errdefer gpa.free(name);
    const owned_path = try gpa.dupe(u8, path);
    return .{ .name = name, .path = owned_path, .kind = kind, .size = stat.size, .mtimeMs = @as(f64, @floatFromInt(stat.mtime.nanoseconds)) / std.time.ns_per_ms };
}
pub const TextLine = struct {
    text: []u8,
    terminated: bool,
    pub fn deinit(self: *TextLine, gpa: std.mem.Allocator) void {
        gpa.free(self.text);
        self.* = undefined;
    }
};
pub const DirPage = struct {
    entries: []FileInfo,
    done: bool,
    pub fn deinit(self: *DirPage, gpa: std.mem.Allocator) void {
        for (self.entries) |*entry| entry.deinit(gpa);
        gpa.free(self.entries);
        self.* = undefined;
    }
};
pub const ProgressPolicy = struct { partialIntervalMs: u64 = 100, outputIntervalMs: u64 = 100 };
