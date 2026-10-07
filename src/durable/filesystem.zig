//! Durable local readers; every operation uses explicit native I/O.
const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const decode = @import("decode.zig");
const scan = @import("line_scan.zig");
const paths = @import("path.zig");
const watching = @import("watch.zig");
const temp_resources = @import("temporary.zig");
pub const Context = types.Context;
pub const Result = types.Result;
pub const OpenBinaryOptions = struct { noFollow: bool = false };
pub const CreateDirOptions = struct { recursive: bool = true };
pub const RemoveOptions = struct { recursive: bool = false, force: bool = false };
pub const TempFileOptions = struct { prefix: []const u8 = "", suffix: []const u8 = "" };
pub fn freeTextLines(gpa: std.mem.Allocator, lines: [][]u8) void {
    for (lines) |line| gpa.free(line);
    gpa.free(lines);
}
pub fn appendWindows(file: std.Io.File, bytes: []const u8) !void {
    const windows = std.os.windows;
    var index: usize = 0;
    while (index < bytes.len) {
        var status_block: windows.IO_STATUS_BLOCK = undefined;
        var offset: windows.LARGE_INTEGER = -1;
        const size: windows.ULONG = @intCast(@min(bytes.len - index, std.math.maxInt(windows.ULONG)));
        // Zig 0.16's unsigned positional API rejects this signed NT sentinel.
        // The opened handle is synchronous, so completion owns status_block
        // before returning and no asynchronous callback retains its address.
        switch (windows.ntdll.NtWriteFile(file.handle, null, null, null, &status_block, @constCast(bytes[index..].ptr), size, &offset, null)) {
            .SUCCESS => {},
            .ACCESS_DENIED => return error.AccessDenied,
            .DISK_FULL => return error.NoSpaceLeft,
            .QUOTA_EXCEEDED => return error.DiskQuota,
            .INVALID_PARAMETER => return error.InvalidArgument,
            .FILE_IS_A_DIRECTORY => return error.IsDir,
            else => return error.Unexpected,
        }
        const count = status_block.Information;
        if (count == 0 or count > size) return error.NoWriteProgress;
        index += count;
    }
}

/// POSIX opens must be nonblocking even for a FIFO that is rejected by fstat.
/// std.Io.Dir.openFile does not expose O_NONBLOCK for this operation.
pub fn openWindowsNoFollow(io: std.Io, gpa: std.mem.Allocator, path: []const u8, access: u32) !std.Io.File {
    const windows = std.os.windows;
    const Native = struct {
        extern "kernel32" fn CreateFileW(path: [*:0]const u16, access: windows.DWORD, share: windows.DWORD, security: ?*const anyopaque, disposition: windows.DWORD, attributes: windows.DWORD, template: ?windows.HANDLE) callconv(.winapi) windows.HANDLE;
    };
    const absolute = try paths.absoluteCwd(gpa, io, path);
    defer gpa.free(absolute);
    for (absolute) |*byte| if (byte.* == '/') {
        byte.* = '\\';
    };
    const prefixed = if (std.mem.startsWith(u8, absolute, "\\\\?\\") or std.mem.startsWith(u8, absolute, "\\\\.\\"))
        try gpa.dupe(u8, absolute)
    else if (std.mem.startsWith(u8, absolute, "\\\\"))
        try std.fmt.allocPrint(gpa, "\\\\?\\UNC\\{s}", .{absolute[2..]})
    else
        try std.fmt.allocPrint(gpa, "\\\\?\\{s}", .{absolute});
    defer gpa.free(prefixed);
    const wide = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, prefixed);
    defer gpa.free(wide);
    // No FILE_FLAG_OVERLAPPED: the returned handle is synchronous. Opening
    // the reparse point and allowing directories preserves the subsequent
    // regular-file check without traversing a final symlink or junction.
    const handle = Native.CreateFileW(wide.ptr, access, 0x7, null, 3, 0x00200000 | 0x02000000, null);
    if (handle == windows.INVALID_HANDLE_VALUE) return switch (windows.GetLastError()) {
        .FILE_NOT_FOUND, .PATH_NOT_FOUND => error.FileNotFound,
        .ACCESS_DENIED => error.AccessDenied,
        .SHARING_VIOLATION => error.FileBusy,
        .DIRECTORY => error.NotDir,
        .INVALID_NAME, .INVALID_PARAMETER => error.InvalidArgument,
        else => error.Unexpected,
    };
    return .{ .handle = handle, .flags = .{ .nonblocking = false } };
}
pub fn openRegular(io: std.Io, gpa: std.mem.Allocator, path: []const u8, options: OpenBinaryOptions) !std.Io.File {
    const file = if (builtin.os.tag == .windows and options.noFollow) try openWindowsNoFollow(io, gpa, path, 0x80000000) else if (builtin.os.tag == .windows or builtin.os.tag == .wasi) try std.Io.Dir.cwd().openFile(io, path, .{ .follow_symlinks = !options.noFollow, .allow_directory = options.noFollow }) else posix: {
        const terminated = try gpa.dupeZ(u8, path);
        defer gpa.free(terminated);
        var flags: std.posix.O = .{ .ACCMODE = .RDONLY, .NONBLOCK = true, .NOFOLLOW = options.noFollow };
        if (@hasField(std.posix.O, "CLOEXEC")) flags.CLOEXEC = true;
        if (@hasField(std.posix.O, "LARGEFILE")) flags.LARGEFILE = true;
        if (@hasField(std.posix.O, "NOCTTY")) flags.NOCTTY = true;
        const fd = fd: while (true) {
            const rc = std.posix.system.openat(std.posix.AT.FDCWD, terminated.ptr, flags, @as(std.posix.mode_t, 0));
            switch (std.posix.errno(rc)) {
                .SUCCESS => break :fd @as(std.posix.fd_t, @intCast(rc)),
                .INTR => continue,
                .NOENT => return error.FileNotFound,
                .ACCES => return error.AccessDenied,
                .PERM => return error.PermissionDenied,
                .NOTDIR => return error.NotDir,
                .ISDIR => return error.IsDir,
                .LOOP => return error.SymLinkLoop,
                .INVAL => return error.InvalidArgument,
                .NAMETOOLONG => return error.NameTooLong,
                .MFILE, .NFILE, .NOMEM => return error.SystemResources,
                else => return error.Unexpected,
            }
        };
        break :posix std.Io.File{ .handle = fd, .flags = .{ .nonblocking = true } };
    };
    errdefer file.close(io);
    const info = try file.stat(io);
    if (info.kind == .directory) return error.IsDir;
    if (info.kind != .file) return error.InvalidArgument;
    return file;
}

pub const BinaryReader = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    path: []u8,
    file: ?std.Io.File,
    pub fn close(self: *BinaryReader, _: Context) void {
        if (self.file) |file| file.close(self.io);
        self.file = null;
    }
    pub fn deinit(self: *BinaryReader) void {
        self.close(.{});
        self.gpa.free(self.path);
        self.* = undefined;
    }
    pub fn info(self: *BinaryReader, context: Context) !Result(types.FileInfo) {
        if (context.aborted()) return types.failure(types.FileInfo, self.gpa, .aborted, self.path, null, "aborted");
        const file = self.file orelse return types.failure(types.FileInfo, self.gpa, .invalid, self.path, null, "Binary reader is closed");
        const stat = file.stat(self.io) catch |err| return types.fromError(types.FileInfo, self.gpa, err, self.path);
        return .{ .value = (try types.fileInfo(self.gpa, self.path, stat)) orelse return types.failure(types.FileInfo, self.gpa, .invalid, self.path, null, "Unsupported file type") };
    }
    pub fn read(self: *BinaryReader, offset: u64, length: u64, context: Context) !Result([]u8) {
        if (context.aborted()) return types.failure([]u8, self.gpa, .aborted, self.path, null, "aborted");
        const file = self.file orelse return types.failure([]u8, self.gpa, .invalid, self.path, null, "Binary reader is closed");
        if (offset > scan.max_safe_integer or length > scan.max_safe_integer) return types.failure([]u8, self.gpa, .invalid, self.path, null, "Offset and length must be non-negative safe integers");
        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(self.gpa);
        var buffer: [64 * 1024]u8 = undefined;
        while (output.items.len < length) {
            const size: usize = @intCast(@min(length - output.items.len, buffer.len));
            var slices = [_][]u8{buffer[0..size]};
            const position = std.math.add(u64, offset, output.items.len) catch return types.failure([]u8, self.gpa, .invalid, self.path, null, "Offset overflow");
            const count = file.readPositional(self.io, &slices, position) catch |err| return types.fromError([]u8, self.gpa, err, self.path);
            if (context.aborted()) return types.failure([]u8, self.gpa, .aborted, self.path, null, "aborted");
            if (count == 0) break;
            try output.appendSlice(self.gpa, buffer[0..count]);
        }
        return .{ .value = try output.toOwnedSlice(self.gpa) };
    }
    pub fn scanLines(self: *BinaryReader, options: scan.Options, context: Context) !Result(scan.LineScan) {
        if (context.aborted()) return types.failure(scan.LineScan, self.gpa, .aborted, self.path, null, "aborted");
        const file = self.file orelse return types.failure(scan.LineScan, self.gpa, .invalid, self.path, null, "Binary reader is closed");
        var scanner = scan.LineScanner.init(options) catch return types.failure(scan.LineScan, self.gpa, .invalid, self.path, null, "Invalid line range");
        var chunk: [64 * 1024]u8 = undefined;
        var position: u64 = 0;
        while (true) {
            var slices = [_][]u8{&chunk};
            const size = file.readPositional(self.io, &slices, position) catch |err| return types.fromError(scan.LineScan, self.gpa, err, self.path);
            if (context.aborted()) return types.failure(scan.LineScan, self.gpa, .aborted, self.path, null, "aborted");
            if (size == 0) return .{ .value = try scanner.finish() };
            try scanner.push(chunk[0..size]);
            position = std.math.add(u64, position, size) catch return error.LineScanSizeOverflow;
        }
    }
};
test "durable noFollow regular reader uses compatible positional I/O and line scans" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "regular.txt", .data = "alpha\nbeta\n" });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    var filesystem = try FileSystem.init(gpa, io, buffer[0..length], null);
    defer filesystem.deinit();
    var opened = try filesystem.openBinaryReader("regular.txt", .{ .noFollow = true }, .{});
    if (opened == .failure) {
        defer opened.failure.deinit(gpa);
        return error.NoFollowRegularOpenFailed;
    }
    var reader = opened.value;
    defer reader.deinit();
    for (0..32) |_| {
        var bytes = try reader.read(0, 6, .{});
        if (bytes == .failure) {
            defer bytes.failure.deinit(gpa);
            return error.NoFollowRegularReadFailed;
        }
        defer gpa.free(bytes.value);
        try std.testing.expectEqualStrings("alpha\n", bytes.value);
        var scanned = try reader.scanLines(.{ .startLine = 0, .endLine = 1 }, .{});
        if (scanned == .failure) {
            defer scanned.failure.deinit(gpa);
            return error.NoFollowRegularScanFailed;
        }
        try std.testing.expectEqual(@as(u64, 2), scanned.value.newlines);
        try std.testing.expectEqual(@as(u64, 5), scanned.value.selectedBytes);
    }
    var directory = try filesystem.openBinaryReader(buffer[0..length], .{ .noFollow = true }, .{});
    try std.testing.expect(directory == .failure);
    defer directory.failure.deinit(gpa);
    try std.testing.expectEqual(types.FileErrorCode.is_directory, directory.failure.code);
}

pub const TextLineReader = struct {
    binary: BinaryReader,
    decoder: decode.Decoder = decode.streamDecoder(),
    byte_offset: u64 = 0,
    buffer: std.ArrayList(u8) = .empty,
    ended: bool = false,
    pub fn close(self: *TextLineReader, context: Context) void {
        self.binary.close(context);
        self.buffer.clearRetainingCapacity();
    }
    pub fn deinit(self: *TextLineReader) void {
        self.buffer.deinit(self.binary.gpa);
        self.binary.deinit();
        self.* = undefined;
    }
    pub fn readLine(self: *TextLineReader, context: Context) !Result(?types.TextLine) {
        const gpa = self.binary.gpa;
        if (context.aborted()) return types.failure(?types.TextLine, gpa, .aborted, self.binary.path, null, "aborted");
        const file = self.binary.file orelse return types.failure(?types.TextLine, gpa, .invalid, self.binary.path, null, "Text line reader is closed");
        while (true) {
            if (std.mem.indexOfScalar(u8, self.buffer.items, '\n')) |index| {
                const text = try gpa.dupe(u8, self.buffer.items[0..index]);
                const tail = self.buffer.items[index + 1 ..];
                @memmove(self.buffer.items[0..tail.len], tail);
                self.buffer.items.len = tail.len;
                return .{ .value = .{ .text = text, .terminated = true } };
            }
            if (self.ended) {
                if (self.buffer.items.len == 0) return .{ .value = null };
                return .{ .value = .{ .text = try self.buffer.toOwnedSlice(gpa), .terminated = false } };
            }
            var bytes: [64 * 1024]u8 = undefined;
            var slices = [_][]u8{&bytes};
            const count = file.readPositional(self.binary.io, &slices, self.byte_offset) catch |err| return types.fromError(?types.TextLine, gpa, err, self.binary.path);
            if (context.aborted()) return types.failure(?types.TextLine, gpa, .aborted, self.binary.path, null, "aborted");
            // Stage decoding so an allocation failure can be retried without
            // consuming bytes or partially changing the decoder.
            var decoder = self.decoder;
            var staged: std.ArrayList(u8) = .empty;
            defer staged.deinit(gpa);
            const sink: decode.Text = .{ .gpa = gpa, .output = &staged };
            if (count == 0) try decoder.finish(sink) else try decoder.push(bytes[0..count], sink);
            try self.buffer.appendSlice(gpa, staged.items);
            self.decoder = decoder;
            self.byte_offset += count;
            if (count == 0) self.ended = true;
        }
    }
};

pub const DirReader = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    path: []u8,
    directory: ?std.Io.Dir,
    iterator: std.Io.Dir.Iterator,
    done: bool = false,
    pub fn close(self: *DirReader, _: Context) void {
        if (self.directory) |directory| directory.close(self.io);
        self.directory = null;
    }
    pub fn deinit(self: *DirReader) void {
        self.close(.{});
        self.gpa.free(self.path);
        self.* = undefined;
    }
    pub fn next(self: *DirReader, max_entries: u64, context: Context) !Result(types.DirPage) {
        if (context.aborted()) return types.failure(types.DirPage, self.gpa, .aborted, self.path, null, "aborted");
        if (self.directory == null) return types.failure(types.DirPage, self.gpa, .invalid, self.path, null, "Directory reader is closed");
        if (max_entries == 0 or max_entries > scan.max_safe_integer) return types.failure(types.DirPage, self.gpa, .invalid, self.path, null, "maxEntries must be a positive safe integer");
        var entries: std.ArrayList(types.FileInfo) = .empty;
        defer entries.deinit(self.gpa);
        var transferred = false;
        defer if (!transferred) for (entries.items) |*entry| entry.deinit(self.gpa);
        while (!self.done and entries.items.len < max_entries) {
            const entry = (self.iterator.next(self.io) catch |err| return types.fromError(types.DirPage, self.gpa, err, self.path)) orelse {
                self.done = true;
                break;
            };
            if (context.aborted()) return types.failure(types.DirPage, self.gpa, .aborted, self.path, null, "aborted");
            const path = try std.fs.path.join(self.gpa, &.{ self.path, entry.name });
            defer self.gpa.free(path);
            const stat = std.Io.Dir.cwd().statFile(self.io, path, .{ .follow_symlinks = false }) catch |err| {
                if (err == error.FileNotFound) continue;
                return types.fromError(types.DirPage, self.gpa, err, path);
            };
            var info = (try types.fileInfo(self.gpa, path, stat)) orelse continue;
            errdefer info.deinit(self.gpa);
            try entries.append(self.gpa, info);
        }
        const result = try entries.toOwnedSlice(self.gpa);
        transferred = true;
        return .{ .value = .{ .entries = result, .done = self.done } };
    }
};

pub const FileSystem = struct {
    /// Local environments share a namespace regardless of their cwd.
    id: []const u8 = "native:local",
    gpa: std.mem.Allocator,
    io: std.Io,
    cwd: []u8,
    home: ?[]u8,
    temp_dir: ?[]u8 = null,
    pub fn init(gpa: std.mem.Allocator, io: std.Io, cwd: []const u8, home: ?[]const u8) !FileSystem {
        const owned = try paths.absoluteCwd(gpa, io, cwd);
        errdefer gpa.free(owned);
        return .{ .gpa = gpa, .io = io, .cwd = owned, .home = if (home) |value| try gpa.dupe(u8, value) else null };
    }
    pub fn deinit(self: *FileSystem) void {
        self.gpa.free(self.cwd);
        if (self.home) |home| self.gpa.free(home);
        if (self.temp_dir) |directory| self.gpa.free(directory);
        self.* = undefined;
    }
    pub fn resolvePath(self: *const FileSystem, input: []const u8) ![]u8 {
        return paths.resolve(self.gpa, self.cwd, input, self.home);
    }
    pub fn absolutePath(self: *const FileSystem, input: []const u8, _: Context) !Result([]u8) {
        const path = self.resolvePath(input) catch |err| return types.fromError([]u8, self.gpa, err, input);
        return .{ .value = path };
    }
    pub fn setTempDirectory(self: *FileSystem, input: []const u8) !void {
        const directory = try paths.absoluteCwd(self.gpa, self.io, input);
        if (self.temp_dir) |old| self.gpa.free(old);
        self.temp_dir = directory;
    }
    pub fn joinPath(self: *const FileSystem, parts: []const []const u8, _: Context) !Result([]u8) {
        const joined = try std.fs.path.join(self.gpa, parts);
        defer self.gpa.free(joined);
        if (joined.len == 0) return .{ .value = try self.gpa.dupe(u8, ".") };
        const normalized = try std.fs.path.resolve(self.gpa, &.{joined});
        if (normalized.len != 0 and std.fs.path.isSep(joined[joined.len - 1]) and !std.fs.path.isSep(normalized[normalized.len - 1])) {
            defer self.gpa.free(normalized);
            return .{ .value = try std.fmt.allocPrint(self.gpa, "{s}{c}", .{ normalized, std.fs.path.sep }) };
        }
        return .{ .value = normalized };
    }
    pub fn readBinaryFile(self: *const FileSystem, input: []const u8, context: Context) !Result([]u8) {
        const opened = try self.openBinaryReader(input, .{}, context);
        if (opened == .failure) return .{ .failure = opened.failure };
        var reader = opened.value;
        defer reader.deinit();
        return reader.read(0, scan.max_safe_integer, context);
    }
    pub fn readTextFile(self: *const FileSystem, input: []const u8, context: Context) !Result([]u8) {
        const bytes = try self.readBinaryFile(input, context);
        if (bytes == .failure) return .{ .failure = bytes.failure };
        defer self.gpa.free(bytes.value);
        return .{ .value = try decode.decode(self.gpa, bytes.value, true) };
    }
    pub fn readTextLines(self: *const FileSystem, input: []const u8, max_lines: ?u64, context: Context) !Result([][]u8) {
        if (max_lines == 0) return .{ .value = try self.gpa.alloc([]u8, 0) };
        const opened = try self.openTextLineReader(input, context);
        if (opened == .failure) return .{ .failure = opened.failure };
        var reader = opened.value;
        defer reader.deinit();
        var lines: std.ArrayList([]u8) = .empty;
        defer lines.deinit(self.gpa);
        var transferred = false;
        defer if (!transferred) for (lines.items) |line| self.gpa.free(line);
        while (max_lines == null or lines.items.len < max_lines.?) {
            const next = try reader.readLine(context);
            if (next == .failure) return .{ .failure = next.failure };
            const line = next.value orelse break;
            errdefer self.gpa.free(line.text);
            try lines.append(self.gpa, line.text);
        }
        const result = try lines.toOwnedSlice(self.gpa);
        transferred = true;
        return .{ .value = result };
    }
    fn resolved(self: *const FileSystem, input: []const u8, context: Context) !Result([]u8) {
        const path = self.resolvePath(input) catch |err| return types.fromError([]u8, self.gpa, err, input);
        if (context.aborted()) {
            defer self.gpa.free(path);
            return types.failure([]u8, self.gpa, .aborted, path, null, "aborted");
        }
        return .{ .value = path };
    }
    pub fn writeFile(self: *const FileSystem, input: []const u8, bytes: []const u8, context: Context) !Result(void) {
        return self.writeOrAppend(input, bytes, false, context);
    }
    pub fn appendFile(self: *const FileSystem, input: []const u8, bytes: []const u8, context: Context) !Result(void) {
        return self.writeOrAppend(input, bytes, true, context);
    }
    fn writeOrAppend(self: *const FileSystem, input: []const u8, bytes: []const u8, append: bool, context: Context) !Result(void) {
        const location = try self.resolved(input, context);
        if (location == .failure) return .{ .failure = location.failure };
        const path = location.value;
        defer self.gpa.free(path);
        if (std.fs.path.dirname(path)) |parent| std.Io.Dir.cwd().createDirPath(self.io, parent) catch |err| return types.fromError(void, self.gpa, err, path);
        if (context.aborted()) return types.failure(void, self.gpa, .aborted, path, null, "aborted");
        const file = std.Io.Dir.cwd().createFile(self.io, path, .{ .truncate = !append }) catch |err| return types.fromError(void, self.gpa, err, path);
        defer file.close(self.io);
        if (append and builtin.os.tag != .windows) {
            const flags = std.posix.system.fcntl(file.handle, std.posix.F.GETFL, @as(usize, 0));
            if (std.posix.errno(flags) != .SUCCESS) return types.failure(void, self.gpa, .unknown, path, error.AppendFlagsFailed, "Cannot enable append mode");
            const mask: u32 = @bitCast(std.posix.O{ .APPEND = true });
            if (std.posix.errno(std.posix.system.fcntl(file.handle, std.posix.F.SETFL, @as(usize, @intCast(flags)) | mask)) != .SUCCESS) return types.failure(void, self.gpa, .unknown, path, error.AppendFlagsFailed, "Cannot enable append mode");
        }
        if (append and builtin.os.tag == .windows) {
            // NtWriteFile's FILE_WRITE_TO_END_OF_FILE offset provides an
            // atomic seek-and-write; do not compute EOF then race another appender.
            appendWindows(file, bytes) catch |err| return types.fromError(void, self.gpa, err, path);
        } else file.writeStreamingAll(self.io, bytes) catch |err| return types.fromError(void, self.gpa, err, path);
        if (context.aborted()) return types.failure(void, self.gpa, .aborted, path, null, "aborted");
        return .{ .value = {} };
    }
    pub fn truncateFile(self: *const FileSystem, input: []const u8, size: u64, context: Context) !Result(void) {
        const location = try self.resolved(input, context);
        if (location == .failure) return .{ .failure = location.failure };
        const path = location.value;
        defer self.gpa.free(path);
        if (size > scan.max_safe_integer) return types.failure(void, self.gpa, .invalid, path, null, "File size must be a non-negative safe integer");
        const file = std.Io.Dir.cwd().openFile(self.io, path, .{ .mode = .read_write, .allow_directory = false }) catch |err| return types.fromError(void, self.gpa, err, path);
        defer file.close(self.io);
        file.setLength(self.io, size) catch |err| return types.fromError(void, self.gpa, err, path);
        if (context.aborted()) return types.failure(void, self.gpa, .aborted, path, null, "aborted");
        return .{ .value = {} };
    }
    pub fn flushFile(self: *const FileSystem, input: []const u8, context: Context) !Result(void) {
        const location = try self.resolved(input, context);
        if (location == .failure) return .{ .failure = location.failure };
        const path = location.value;
        defer self.gpa.free(path);
        const file = std.Io.Dir.cwd().openFile(self.io, path, .{ .mode = .read_write, .allow_directory = false }) catch |err| return types.fromError(void, self.gpa, err, path);
        defer file.close(self.io);
        file.sync(self.io) catch |err| return types.fromError(void, self.gpa, err, path);
        if (context.aborted()) return types.failure(void, self.gpa, .aborted, path, null, "aborted");
        return .{ .value = {} };
    }
    pub fn renameFile(self: *const FileSystem, source: []const u8, destination: []const u8, context: Context) !Result(void) {
        const source_path = self.resolvePath(source) catch |err| return types.fromError(void, self.gpa, err, source);
        defer self.gpa.free(source_path);
        const location = try self.resolved(destination, context);
        if (location == .failure) return .{ .failure = location.failure };
        const destination_path = location.value;
        defer self.gpa.free(destination_path);
        std.Io.Dir.cwd().rename(source_path, std.Io.Dir.cwd(), destination_path, self.io) catch |err| return types.fromError(void, self.gpa, err, source_path);
        return .{ .value = {} };
    }
    pub fn exists(self: *const FileSystem, input: []const u8, context: Context) !Result(bool) {
        var result = try self.fileInfo(input, context);
        if (result == .value) {
            result.value.deinit(self.gpa);
            return .{ .value = true };
        }
        if (result.failure.code == .not_found) {
            result.failure.deinit(self.gpa);
            return .{ .value = false };
        }
        return .{ .failure = result.failure };
    }
    pub fn canonicalPath(self: *const FileSystem, input: []const u8, context: Context) !Result([]u8) {
        const location = try self.resolved(input, context);
        if (location == .failure) return .{ .failure = location.failure };
        const path = location.value;
        defer self.gpa.free(path);
        const canonical = std.Io.Dir.cwd().realPathFileAlloc(self.io, path, self.gpa) catch |err| return types.fromError([]u8, self.gpa, err, path);
        defer self.gpa.free(canonical);
        return .{ .value = try self.gpa.dupe(u8, canonical) };
    }
    pub fn listDir(self: *const FileSystem, input: []const u8, context: Context) !Result([]types.FileInfo) {
        const location = try self.resolved(input, context);
        if (location == .failure) return .{ .failure = location.failure };
        const path = location.value;
        defer self.gpa.free(path);
        const directory = std.Io.Dir.cwd().openDir(self.io, path, .{ .iterate = true }) catch |err| return types.fromError([]types.FileInfo, self.gpa, err, path);
        defer directory.close(self.io);
        var entries: std.ArrayList(types.FileInfo) = .empty;
        defer entries.deinit(self.gpa);
        var transferred = false;
        defer if (!transferred) for (entries.items) |*entry| entry.deinit(self.gpa);
        var iterator = directory.iterate();
        while (iterator.next(self.io) catch |err| return types.fromError([]types.FileInfo, self.gpa, err, path)) |entry| {
            if (context.aborted()) return types.failure([]types.FileInfo, self.gpa, .aborted, path, null, "aborted");
            const entry_path = try std.fs.path.join(self.gpa, &.{ path, entry.name });
            defer self.gpa.free(entry_path);
            const stat = std.Io.Dir.cwd().statFile(self.io, entry_path, .{ .follow_symlinks = false }) catch |err| return types.fromError([]types.FileInfo, self.gpa, err, entry_path);
            var info = (try types.fileInfo(self.gpa, entry_path, stat)) orelse continue;
            errdefer info.deinit(self.gpa);
            try entries.append(self.gpa, info);
        }
        if (builtin.os.tag != .windows) std.mem.sort(types.FileInfo, entries.items, {}, struct {
            fn less(_: void, lhs: types.FileInfo, rhs: types.FileInfo) bool {
                return std.mem.lessThan(u8, lhs.name, rhs.name);
            }
        }.less);
        const result = try entries.toOwnedSlice(self.gpa);
        transferred = true;
        return .{ .value = result };
    }
    pub fn createDir(self: *const FileSystem, input: []const u8, options: CreateDirOptions, context: Context) !Result(void) {
        const location = try self.resolved(input, context);
        if (location == .failure) return .{ .failure = location.failure };
        defer self.gpa.free(location.value);
        if (options.recursive) std.Io.Dir.cwd().createDirPath(self.io, location.value) catch |err| return types.fromError(void, self.gpa, err, location.value) else std.Io.Dir.cwd().createDir(self.io, location.value, .default_dir) catch |err| return types.fromError(void, self.gpa, err, location.value);
        return .{ .value = {} };
    }
    pub fn remove(self: *const FileSystem, input: []const u8, options: RemoveOptions, context: Context) !Result(void) {
        const location = try self.resolved(input, context);
        if (location == .failure) return .{ .failure = location.failure };
        const path = location.value;
        defer self.gpa.free(path);
        // resolvePath produces the absolute path explicitly named by this
        // operation; recursive deletion never receives an unchecked computed root.
        if (!std.fs.path.isAbsolute(path)) return types.failure(void, self.gpa, .invalid, path, null, "Removal path must be absolute");
        const stat = std.Io.Dir.cwd().statFile(self.io, path, .{ .follow_symlinks = false }) catch |err| {
            if (options.force and err == error.FileNotFound) return .{ .value = {} };
            return types.fromError(void, self.gpa, err, path);
        };
        if (stat.kind == .directory and !options.recursive) return types.failure(void, self.gpa, .unknown, path, error.IsDir, "ERR_FS_EISDIR");
        if (stat.kind == .directory) std.Io.Dir.cwd().deleteTree(self.io, path) catch |err| return types.fromError(void, self.gpa, err, path) else std.Io.Dir.cwd().deleteFile(self.io, path) catch |err| {
            if (options.force and err == error.FileNotFound) return .{ .value = {} };
            return types.fromError(void, self.gpa, err, path);
        };
        return .{ .value = {} };
    }
    pub fn createTempDir(self: *const FileSystem, prefix: ?[]const u8, context: Context) !Result([]u8) {
        if (context.aborted()) return types.failure([]u8, self.gpa, .aborted, null, null, "aborted");
        const root = self.temp_dir orelse return types.failure([]u8, self.gpa, .not_supported, null, null, "Temporary directory is not configured");
        const path = temp_resources.directory(self.gpa, self.io, root, prefix orelse "tmp-") catch |err| return types.fromError([]u8, self.gpa, err, null);
        return .{ .value = path };
    }
    pub fn createTempFile(self: *const FileSystem, options: TempFileOptions, context: Context) !Result([]u8) {
        if (context.aborted()) return types.failure([]u8, self.gpa, .aborted, null, null, "aborted");
        const root = self.temp_dir orelse return types.failure([]u8, self.gpa, .not_supported, null, null, "Temporary directory is not configured");
        const created = temp_resources.file(self.gpa, self.io, root, options.prefix, options.suffix) catch |err| return types.fromError([]u8, self.gpa, err, null);
        created.file.close(self.io);
        return .{ .value = created.path };
    }
    pub fn openBinaryReader(self: *const FileSystem, input: []const u8, options: OpenBinaryOptions, context: Context) !Result(BinaryReader) {
        const path = self.resolvePath(input) catch |err| return types.fromError(BinaryReader, self.gpa, err, input);
        var transferred = false;
        defer if (!transferred) self.gpa.free(path);
        if (context.aborted()) return types.failure(BinaryReader, self.gpa, .aborted, path, null, "aborted");
        const file = openRegular(self.io, self.gpa, path, options) catch |err| {
            if (options.noFollow and err == error.SymLinkLoop) return types.failure(BinaryReader, self.gpa, .invalid, path, err, "Refusing to follow a symbolic link");
            return types.fromError(BinaryReader, self.gpa, err, path);
        };
        if (context.aborted()) {
            file.close(self.io);
            return types.failure(BinaryReader, self.gpa, .aborted, path, null, "aborted");
        }
        transferred = true;
        return .{ .value = .{ .gpa = self.gpa, .io = self.io, .path = path, .file = file } };
    }
    pub fn openTextLineReader(self: *const FileSystem, input: []const u8, context: Context) !Result(TextLineReader) {
        return switch (try self.openBinaryReader(input, .{}, context)) {
            .failure => |err| .{ .failure = err },
            .value => |reader| .{ .value = .{ .binary = reader } },
        };
    }
    pub fn openDirReader(self: *const FileSystem, input: []const u8, context: Context) !Result(DirReader) {
        const path = self.resolvePath(input) catch |err| return types.fromError(DirReader, self.gpa, err, input);
        var transferred = false;
        defer if (!transferred) self.gpa.free(path);
        if (context.aborted()) return types.failure(DirReader, self.gpa, .aborted, path, null, "aborted");
        const directory = std.Io.Dir.cwd().openDir(self.io, path, .{ .iterate = true }) catch |err| return types.fromError(DirReader, self.gpa, err, path);
        if (context.aborted()) {
            directory.close(self.io);
            return types.failure(DirReader, self.gpa, .aborted, path, null, "aborted");
        }
        transferred = true;
        return .{ .value = .{ .gpa = self.gpa, .io = self.io, .path = path, .directory = directory, .iterator = directory.iterate() } };
    }
    pub fn fileInfo(self: *const FileSystem, input: []const u8, context: Context) !Result(types.FileInfo) {
        const path = self.resolvePath(input) catch |err| return types.fromError(types.FileInfo, self.gpa, err, input);
        defer self.gpa.free(path);
        if (context.aborted()) return types.failure(types.FileInfo, self.gpa, .aborted, path, null, "aborted");
        const stat = std.Io.Dir.cwd().statFile(self.io, path, .{ .follow_symlinks = false }) catch |err| return types.fromError(types.FileInfo, self.gpa, err, path);
        return .{ .value = (try types.fileInfo(self.gpa, path, stat)) orelse return types.failure(types.FileInfo, self.gpa, .invalid, path, null, "Unsupported file type") };
    }
    pub fn watch(self: *const FileSystem, targets: []const watching.Target, options: watching.Options, callback: watching.Callback, callback_context: ?*anyopaque, context: Context) !Result(*watching.Watcher) {
        return watching.Watcher.open(self, targets, options, callback, callback_context, context);
    }
};

fn expectValue(comptime T: type, gpa: std.mem.Allocator, result: Result(T)) !T {
    return switch (result) {
        .value => |value| value,
        .failure => |err| {
            var owned = err;
            defer owned.deinit(gpa);
            std.debug.print("Durable file error {s}: {s} ({s})\n", .{ @tagName(err.code), err.message, err.path orelse "" });
            return error.UnexpectedFileFailure;
        },
    };
}
fn expectFailure(comptime T: type, gpa: std.mem.Allocator, result: Result(T), code: types.FileErrorCode) !void {
    switch (result) {
        .value => return error.ExpectedFileFailure,
        .failure => |err| {
            var owned = err;
            defer owned.deinit(gpa);
            try std.testing.expectEqual(code, err.code);
        },
    }
}

test "durable binary reader bounded huge requests retain opened file info across path replacement and close" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(io, .{ .sub_path = "original.txt", .data = "first\nsecond\nlast" });
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_length = try temporary.dir.realPath(io, &path_buffer);
    var fs = try FileSystem.init(gpa, io, path_buffer[0..path_length], null);
    defer fs.deinit();
    var reader = try expectValue(BinaryReader, gpa, try fs.openBinaryReader("original.txt", .{}, .{}));
    defer reader.deinit();
    try temporary.dir.rename("original.txt", temporary.dir, "renamed.txt", io);
    try temporary.dir.writeFile(io, .{ .sub_path = "original.txt", .data = "replacement is different" });
    var info = try expectValue(types.FileInfo, gpa, try reader.info(.{}));
    defer info.deinit(gpa);
    try std.testing.expectEqualStrings("original.txt", info.name);
    try std.testing.expectEqual(@as(u64, 17), info.size);
    const bytes = try expectValue([]u8, gpa, try reader.read(6, scan.max_safe_integer, .{}));
    defer gpa.free(bytes);
    try std.testing.expectEqualStrings("second\nlast", bytes);
    const metadata = try expectValue(scan.LineScan, gpa, try reader.scanLines(.{ .startLine = 1, .endLine = 2 }, .{}));
    try std.testing.expectEqualDeep(scan.LineScan{ .newlines = 2, .start = 6, .end = 12, .firstLineEnd = 12, .lastLineStart = 6, .selectedBytes = 6, .firstLineBytes = 6 }, metadata);
    const empty = try expectValue([]u8, gpa, try reader.read(1000, scan.max_safe_integer, .{}));
    defer gpa.free(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
    try expectFailure([]u8, gpa, try reader.read(scan.max_safe_integer + 1, 0, .{}), .invalid);
    reader.close(.{});
    reader.close(.{});
    try expectFailure([]u8, gpa, try reader.read(0, 1, .{}), .invalid);
    var cancelled: std.atomic.Value(bool) = .init(true);
    try expectFailure([]u8, gpa, try reader.read(0, 1, .{ .abort_flag = &cancelled }), .aborted);
    try expectFailure(BinaryReader, gpa, try fs.openBinaryReader(".", .{}, .{}), .is_directory);
    try expectFailure(BinaryReader, gpa, try fs.openBinaryReader("missing.txt", .{}, .{}), .not_found);
}

test "durable line reader decodes chunk-boundary BOM and malformed scalars without adding trailing empty line" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var content: std.ArrayList(u8) = .empty;
    defer content.deinit(gpa);
    try content.appendSlice(gpa, "\xef\xbb\xbf");
    try content.appendNTimes(gpa, 'a', 65532);
    try content.appendSlice(gpa, "\xe2\x82\xef\xbb\xbf\nlast\r\n");
    try temporary.dir.writeFile(io, .{ .sub_path = "lines.txt", .data = content.items });
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_length = try temporary.dir.realPath(io, &path_buffer);
    var fs = try FileSystem.init(gpa, io, path_buffer[0..path_length], null);
    defer fs.deinit();
    var reader = try expectValue(TextLineReader, gpa, try fs.openTextLineReader("lines.txt", .{}));
    defer reader.deinit();
    var first = (try expectValue(?types.TextLine, gpa, try reader.readLine(.{}))).?;
    defer first.deinit(gpa);
    try std.testing.expect(first.terminated);
    try std.testing.expectEqual(@as(usize, 65538), first.text.len);
    try std.testing.expect(std.mem.endsWith(u8, first.text, "\xef\xbf\xbd\xef\xbb\xbf"));
    var last = (try expectValue(?types.TextLine, gpa, try reader.readLine(.{}))).?;
    defer last.deinit(gpa);
    try std.testing.expectEqualStrings("last\r", last.text);
    try std.testing.expect(last.terminated);
    try std.testing.expect((try expectValue(?types.TextLine, gpa, try reader.readLine(.{}))) == null);
    reader.close(.{});
    try expectFailure(?types.TextLine, gpa, try reader.readLine(.{}), .invalid);
}

test "durable paged directory reader keeps continuation and reports owned metadata validation and abort" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(io, .{ .sub_path = "a", .data = "abc" });
    try temporary.dir.writeFile(io, .{ .sub_path = "b", .data = "five!" });
    try temporary.dir.createDir(io, "child", .default_dir);
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_length = try temporary.dir.realPath(io, &path_buffer);
    var fs = try FileSystem.init(gpa, io, path_buffer[0..path_length], null);
    defer fs.deinit();
    var reader = try expectValue(DirReader, gpa, try fs.openDirReader(".", .{}));
    defer reader.deinit();
    try expectFailure(types.DirPage, gpa, try reader.next(0, .{}), .invalid);
    var count: usize = 0;
    var seen: u3 = 0;
    while (true) {
        var page = try expectValue(types.DirPage, gpa, try reader.next(1, .{}));
        defer page.deinit(gpa);
        try std.testing.expect(page.entries.len <= 1);
        for (page.entries) |entry| {
            if (std.mem.eql(u8, entry.name, "a")) {
                try std.testing.expectEqual(types.FileKind.file, entry.kind);
                try std.testing.expectEqual(@as(u64, 3), entry.size);
                seen |= 1;
            } else if (std.mem.eql(u8, entry.name, "b")) seen |= 2 else if (std.mem.eql(u8, entry.name, "child")) {
                try std.testing.expectEqual(types.FileKind.directory, entry.kind);
                seen |= 4;
            } else return error.UnexpectedDirectoryEntry;
            count += 1;
        }
        if (page.done) break;
        try std.testing.expect(count <= 3);
    }
    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expectEqual(@as(u3, 7), seen);
    var empty = try expectValue(types.DirPage, gpa, try reader.next(1, .{}));
    defer empty.deinit(gpa);
    try std.testing.expect(empty.done and empty.entries.len == 0);
    reader.close(.{});
    reader.close(.{});
    try expectFailure(types.DirPage, gpa, try reader.next(1, .{}), .invalid);
    var aborted: std.atomic.Value(bool) = .init(true);
    try expectFailure(DirReader, gpa, try fs.openDirReader(".", .{ .abort_flag = &aborted }), .aborted);
}

fn readerAllocationProbe(gpa: std.mem.Allocator, cwd: []const u8) !void {
    var fs = try FileSystem.init(gpa, std.testing.io, cwd, cwd);
    defer fs.deinit();
    var reader = try expectValue(BinaryReader, gpa, try fs.openBinaryReader("input.txt", .{}, .{}));
    defer reader.deinit();
    var info = try expectValue(types.FileInfo, gpa, try reader.info(.{}));
    defer info.deinit(gpa);
    const bytes = try expectValue([]u8, gpa, try reader.read(0, scan.max_safe_integer, .{}));
    defer gpa.free(bytes);
    try std.testing.expectEqualStrings("first\nlast", bytes);
    _ = try expectValue(scan.LineScan, gpa, try reader.scanLines(.{ .startLine = 0 }, .{}));
    var lines_reader = try expectValue(TextLineReader, gpa, try fs.openTextLineReader("input.txt", .{}));
    defer lines_reader.deinit();
    while (try expectValue(?types.TextLine, gpa, try lines_reader.readLine(.{}))) |line| {
        var owned = line;
        owned.deinit(gpa);
    }
    var directory = try expectValue(DirReader, gpa, try fs.openDirReader(".", .{}));
    defer directory.deinit();
    var page = try expectValue(types.DirPage, gpa, try directory.next(10, .{}));
    defer page.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), page.entries.len);
}
test "durable reader operations release every induced allocation failure and keep line retry state" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(io, .{ .sub_path = "input.txt", .data = "first\nlast" });
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary.dir.realPath(io, &path_buffer);
    try std.testing.checkAllAllocationFailures(gpa, readerAllocationProbe, .{path_buffer[0..length]});
    var failures: usize = 0;
    for (0..20) |offset| {
        var failing = std.testing.FailingAllocator.init(gpa, .{});
        const allocator = failing.allocator();
        var fs = try FileSystem.init(allocator, io, path_buffer[0..length], null);
        defer fs.deinit();
        var reader = try expectValue(TextLineReader, allocator, try fs.openTextLineReader("input.txt", .{}));
        defer reader.deinit();
        failing.fail_index = failing.alloc_index + offset;
        const result = reader.readLine(.{}) catch |err| {
            failing.fail_index = std.math.maxInt(usize);
            try std.testing.expectEqual(error.OutOfMemory, err);
            var first = (try expectValue(?types.TextLine, allocator, try reader.readLine(.{}))).?;
            defer first.deinit(allocator);
            try std.testing.expectEqualStrings("first", first.text);
            failures += 1;
            continue;
        };
        failing.fail_index = std.math.maxInt(usize);
        var first = (try expectValue(?types.TextLine, allocator, result)).?;
        first.deinit(allocator);
        break;
    }
    try std.testing.expect(failures > 0);
}
test "durable binary noFollow refuses file and directory symbolic links and follows them otherwise" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(io, .{ .sub_path = "input.txt", .data = "target" });
    try temporary.dir.createDir(io, "directory", .default_dir);
    temporary.dir.symLink(io, "input.txt", "file-link", .{}) catch |err| {
        if (builtin.os.tag == .windows and (err == error.AccessDenied or err == error.PermissionDenied)) return error.SkipZigTest;
        return err;
    };
    try temporary.dir.symLink(io, "directory", "dir-link", .{ .is_directory = true });
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary.dir.realPath(io, &path_buffer);
    var fs = try FileSystem.init(gpa, io, path_buffer[0..length], null);
    defer fs.deinit();
    try expectFailure(BinaryReader, gpa, try fs.openBinaryReader("file-link", .{ .noFollow = true }, .{}), .invalid);
    try expectFailure(BinaryReader, gpa, try fs.openBinaryReader("dir-link", .{ .noFollow = true }, .{}), .invalid);
    var reader = try expectValue(BinaryReader, gpa, try fs.openBinaryReader("file-link", .{}, .{}));
    defer reader.deinit();
    const bytes = try expectValue([]u8, gpa, try reader.read(0, 100, .{}));
    defer gpa.free(bytes);
    try std.testing.expectEqualStrings("target", bytes);
}

test "durable binary reader refuses a real FIFO without waiting for a writer" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const posix = struct {
        extern fn pi_durable_make_test_fifo(path: [*:0]const u8) callconv(.c) c_int;
    };
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary.dir.realPath(io, &path_buffer);
    var fs = try FileSystem.init(gpa, io, path_buffer[0..length], null);
    defer fs.deinit();
    const path = try fs.resolvePath("fifo");
    defer gpa.free(path);
    const terminated = try gpa.dupeZ(u8, path);
    defer gpa.free(terminated);
    try std.testing.expectEqual(@as(c_int, 0), posix.pi_durable_make_test_fifo(terminated));
    const started = std.Io.Clock.awake.now(io).toMilliseconds();
    try expectFailure(BinaryReader, gpa, try fs.openBinaryReader("fifo", .{}, .{}), .invalid);
    try std.testing.expect(std.Io.Clock.awake.now(io).toMilliseconds() - started < 1000);
}

test "durable local filesystem mutation text binary listing canonical and temp contracts" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &path_buffer);
    var fs = try FileSystem.init(gpa, io, path_buffer[0..length], path_buffer[0..length]);
    defer fs.deinit();
    try fs.setTempDirectory(path_buffer[0..length]);
    _ = try expectValue(void, gpa, try fs.createDir("sub/child", .{}, .{}));
    _ = try expectValue(void, gpa, try fs.writeFile("sub/child/one", "\xef\xbb\xbfhello\nworld\r\n", .{}));
    _ = try expectValue(void, gpa, try fs.appendFile("sub/child/one", "tail", .{}));
    const text = try expectValue([]u8, gpa, try fs.readTextFile("sub/child/one", .{}));
    defer gpa.free(text);
    try std.testing.expectEqualStrings("\xef\xbb\xbfhello\nworld\r\ntail", text);
    const lines = try expectValue([][]u8, gpa, try fs.readTextLines("sub/child/one", null, .{}));
    defer freeTextLines(gpa, lines);
    try std.testing.expectEqual(@as(usize, 3), lines.len);
    try std.testing.expectEqualStrings("hello", lines[0]);
    try std.testing.expectEqualStrings("world\r", lines[1]);
    try std.testing.expectEqualStrings("tail", lines[2]);
    const empty = try expectValue([][]u8, gpa, try fs.readTextLines("missing", 0, .{}));
    defer freeTextLines(gpa, empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
    _ = try expectValue(void, gpa, try fs.truncateFile("sub/child/one", 5, .{}));
    _ = try expectValue(void, gpa, try fs.flushFile("sub/child/one", .{}));
    _ = try expectValue(void, gpa, try fs.truncateFile("sub/child/one", 8, .{}));
    const bytes = try expectValue([]u8, gpa, try fs.readBinaryFile("sub/child/one", .{}));
    defer gpa.free(bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0xef, 0xbb, 0xbf, 'h', 'e', 0, 0, 0 }, bytes);
    _ = try expectValue(void, gpa, try fs.renameFile("sub/child/one", "sub/child/two", .{}));
    try std.testing.expect(try expectValue(bool, gpa, try fs.exists("sub/child/two", .{})));
    try std.testing.expect(!try expectValue(bool, gpa, try fs.exists("sub/child/one", .{})));
    const canonical = try expectValue([]u8, gpa, try fs.canonicalPath("sub/child/../child/two", .{}));
    defer gpa.free(canonical);
    const expected_path = try fs.resolvePath("sub/child/two");
    defer gpa.free(expected_path);
    try std.testing.expectEqualStrings(expected_path, canonical);
    const entries = try expectValue([]types.FileInfo, gpa, try fs.listDir("sub/child", .{}));
    defer {
        for (entries) |*entry| entry.deinit(gpa);
        gpa.free(entries);
    }
    try std.testing.expectEqual(@as(usize, 1), entries.len);
    try std.testing.expectEqualStrings("two", entries[0].name);
    try expectFailure(void, gpa, try fs.remove("sub", .{}, .{}), .unknown);
    try expectFailure(void, gpa, try fs.flushFile("sub", .{}), .is_directory);
    try expectFailure(void, gpa, try fs.truncateFile("sub/child/two", scan.max_safe_integer + 1, .{}), .invalid);
    try expectFailure(void, gpa, try fs.remove("missing", .{}, .{}), .not_found);
    _ = try expectValue(void, gpa, try fs.remove("missing", .{ .force = true }, .{}));
    _ = try expectValue(void, gpa, try fs.remove("sub", .{ .recursive = true }, .{}));
    try std.testing.expect(!try expectValue(bool, gpa, try fs.exists("sub", .{})));
    const temp_dir = try expectValue([]u8, gpa, try fs.createTempDir("native-", .{}));
    defer gpa.free(temp_dir);
    try std.testing.expect(std.mem.startsWith(u8, std.fs.path.basename(temp_dir), "native-"));
    const temp_file = try expectValue([]u8, gpa, try fs.createTempFile(.{ .prefix = "p-", .suffix = ".log" }, .{}));
    defer gpa.free(temp_file);
    try std.testing.expect(std.mem.startsWith(u8, std.fs.path.basename(temp_file), "p-") and std.mem.endsWith(u8, temp_file, ".log"));
    const temp_bytes = try expectValue([]u8, gpa, try fs.readBinaryFile(temp_file, .{}));
    defer gpa.free(temp_bytes);
    try std.testing.expectEqual(@as(usize, 0), temp_bytes.len);
    const joined = try expectValue([]u8, gpa, try fs.joinPath(&.{ "a", "..", "b" }, .{}));
    defer gpa.free(joined);
    try std.testing.expectEqualStrings("b", joined);
}

test "durable append remains atomic between independent opened handles" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &path_buffer);
    var fs = try FileSystem.init(gpa, io, path_buffer[0..length], null);
    defer fs.deinit();
    _ = try expectValue(void, gpa, try fs.writeFile("append", "", .{}));
    const Writer = struct {
        fs: *const FileSystem,
        text: []const u8,
        failed: std.atomic.Value(bool) = .init(false),
        fn run(self: *@This()) void {
            for (0..100) |_| {
                var result = self.fs.appendFile("append", self.text, .{}) catch {
                    self.failed.store(true, .release);
                    return;
                };
                if (result == .failure) {
                    result.failure.deinit(self.fs.gpa);
                    self.failed.store(true, .release);
                    return;
                }
            }
        }
    };
    var a: Writer = .{ .fs = &fs, .text = "A\n" };
    var b: Writer = .{ .fs = &fs, .text = "B\n" };
    const first = try std.Thread.spawn(.{}, Writer.run, .{&a});
    const second = std.Thread.spawn(.{}, Writer.run, .{&b}) catch |err| {
        first.join();
        return err;
    };
    first.join();
    second.join();
    try std.testing.expect(!a.failed.load(.acquire) and !b.failed.load(.acquire));
    const bytes = try expectValue([]u8, gpa, try fs.readBinaryFile("append", .{}));
    defer gpa.free(bytes);
    try std.testing.expectEqual(@as(usize, 400), bytes.len);
    try std.testing.expectEqual(@as(usize, 100), std.mem.count(u8, bytes, "A\n"));
    try std.testing.expectEqual(@as(usize, 100), std.mem.count(u8, bytes, "B\n"));
}
fn facadeAllocationProbe(gpa: std.mem.Allocator, root: []const u8) !void {
    var fs = try FileSystem.init(gpa, std.testing.io, root, root);
    defer fs.deinit();
    try fs.setTempDirectory(root);
    _ = try expectValue(void, gpa, try fs.createDir("alloc", .{}, .{}));
    _ = try expectValue(void, gpa, try fs.writeFile("alloc/input", "line\n", .{}));
    _ = try expectValue(void, gpa, try fs.appendFile("alloc/input", "tail", .{}));
    const text = try expectValue([]u8, gpa, try fs.readTextFile("alloc/input", .{}));
    defer gpa.free(text);
    try std.testing.expectEqualStrings("line\ntail", text);
    const lines = try expectValue([][]u8, gpa, try fs.readTextLines("alloc/input", null, .{}));
    defer freeTextLines(gpa, lines);
    const canonical = try expectValue([]u8, gpa, try fs.canonicalPath("alloc/input", .{}));
    defer gpa.free(canonical);
    const entries = try expectValue([]types.FileInfo, gpa, try fs.listDir("alloc", .{}));
    defer {
        for (entries) |*entry| entry.deinit(gpa);
        gpa.free(entries);
    }
    _ = try expectValue(bool, gpa, try fs.exists("alloc/input", .{}));
    const temp = try expectValue([]u8, gpa, try fs.createTempFile(.{ .prefix = "alloc-", .suffix = ".tmp" }, .{}));
    defer gpa.free(temp);
}
test "durable filesystem facade every induced allocation failure releases returned values and temp rollback" {
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &path_buffer);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, facadeAllocationProbe, .{path_buffer[0..length]});
}
