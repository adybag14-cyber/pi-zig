//! Borrowed environment capabilities; opened readers/watchers own their leases.
const std = @import("std");
const types = @import("types.zig");
const filesystem = @import("filesystem.zig");
const scan = @import("line_scan.zig");
const watching = @import("watch.zig");
const shell = @import("shell.zig");
fn Provider(comptime T: type) type {
    return @typeInfo(T).pointer.child;
}
fn allocatorOf(provider: anytype) std.mem.Allocator {
    return if (@hasField(Provider(@TypeOf(provider)), "gpa")) provider.gpa else provider.fs.gpa;
}
fn ioOf(provider: anytype) std.Io {
    return if (@hasDecl(Provider(@TypeOf(provider)), "io")) provider.io() else if (@hasField(Provider(@TypeOf(provider)), "io")) provider.io else provider.fs.io;
}
fn pathOf(reader: anytype) []const u8 {
    return if (@hasField(@TypeOf(reader), "handle")) reader.handle.path else reader.path;
}
pub const BinaryReader = struct {
    gpa: std.mem.Allocator,
    path: []const u8,
    context: ?*anyopaque,
    vtable: *const VTable,
    const VTable = struct {
        info: *const fn (*anyopaque, types.Context) anyerror!types.Result(types.FileInfo),
        read: *const fn (*anyopaque, u64, u64, types.Context) anyerror!types.Result([]u8),
        scanLines: *const fn (*anyopaque, scan.Options, types.Context) anyerror!types.Result(scan.LineScan),
        close: *const fn (*anyopaque, types.Context) void,
        destroy: *const fn (*anyopaque, std.mem.Allocator) void,
    };
    pub fn fromOwned(gpa: std.mem.Allocator, reader: anytype) !BinaryReader {
        const T = @TypeOf(reader);
        const owned = gpa.create(T) catch |err| {
            var released = reader;
            released.deinit();
            return err;
        };
        owned.* = reader;
        const Methods = struct {
            fn cast(raw: *anyopaque) *T {
                return @ptrCast(@alignCast(raw));
            }
            fn info(raw: *anyopaque, context: types.Context) !types.Result(types.FileInfo) {
                return cast(raw).info(context);
            }
            fn read(raw: *anyopaque, offset: u64, length: u64, context: types.Context) !types.Result([]u8) {
                return cast(raw).read(offset, length, context);
            }
            fn scanLines(raw: *anyopaque, options: scan.Options, context: types.Context) !types.Result(scan.LineScan) {
                return cast(raw).scanLines(options, context);
            }
            fn close(raw: *anyopaque, context: types.Context) void {
                cast(raw).close(context);
            }
            fn destroy(raw: *anyopaque, allocator: std.mem.Allocator) void {
                const value = cast(raw);
                value.deinit();
                allocator.destroy(value);
            }
            const table: VTable = .{ .info = @This().info, .read = @This().read, .scanLines = @This().scanLines, .close = @This().close, .destroy = @This().destroy };
        };
        return .{ .gpa = gpa, .path = pathOf(reader), .context = owned, .vtable = &Methods.table };
    }
    pub fn info(self: *BinaryReader, context: types.Context) !types.Result(types.FileInfo) {
        return self.vtable.info(self.context.?, context);
    }
    pub fn read(self: *BinaryReader, offset: u64, length: u64, context: types.Context) !types.Result([]u8) {
        return self.vtable.read(self.context.?, offset, length, context);
    }
    pub fn scanLines(self: *BinaryReader, options: scan.Options, context: types.Context) !types.Result(scan.LineScan) {
        return self.vtable.scanLines(self.context.?, options, context);
    }
    pub fn close(self: *BinaryReader, context: types.Context) void {
        if (self.context) |raw| self.vtable.close(raw, context);
    }
    pub fn deinit(self: *BinaryReader) void {
        if (self.context) |raw| self.vtable.destroy(raw, self.gpa);
        self.context = null;
        self.path = "";
    }
};
pub const TextLineReader = struct {
    gpa: std.mem.Allocator,
    context: ?*anyopaque,
    vtable: *const VTable,
    const VTable = struct {
        readLine: *const fn (*anyopaque, types.Context) anyerror!types.Result(?types.TextLine),
        close: *const fn (*anyopaque, types.Context) void,
        destroy: *const fn (*anyopaque, std.mem.Allocator) void,
    };
    pub fn fromOwned(gpa: std.mem.Allocator, reader: anytype) !TextLineReader {
        const T = @TypeOf(reader);
        const owned = gpa.create(T) catch |err| {
            var released = reader;
            released.deinit();
            return err;
        };
        owned.* = reader;
        const Methods = struct {
            fn cast(raw: *anyopaque) *T {
                return @ptrCast(@alignCast(raw));
            }
            fn readLine(raw: *anyopaque, context: types.Context) !types.Result(?types.TextLine) {
                return cast(raw).readLine(context);
            }
            fn close(raw: *anyopaque, context: types.Context) void {
                cast(raw).close(context);
            }
            fn destroy(raw: *anyopaque, allocator: std.mem.Allocator) void {
                const value = cast(raw);
                value.deinit();
                allocator.destroy(value);
            }
            const table: VTable = .{ .readLine = @This().readLine, .close = @This().close, .destroy = @This().destroy };
        };
        return .{ .gpa = gpa, .context = owned, .vtable = &Methods.table };
    }
    pub fn readLine(self: *TextLineReader, context: types.Context) !types.Result(?types.TextLine) {
        return self.vtable.readLine(self.context.?, context);
    }
    pub fn close(self: *TextLineReader, context: types.Context) void {
        if (self.context) |raw| self.vtable.close(raw, context);
    }
    pub fn deinit(self: *TextLineReader) void {
        if (self.context) |raw| self.vtable.destroy(raw, self.gpa);
        self.context = null;
    }
};
pub const DirReader = struct {
    gpa: std.mem.Allocator,
    context: ?*anyopaque,
    vtable: *const VTable,
    const VTable = struct {
        next: *const fn (*anyopaque, u64, types.Context) anyerror!types.Result(types.DirPage),
        close: *const fn (*anyopaque, types.Context) void,
        destroy: *const fn (*anyopaque, std.mem.Allocator) void,
    };
    pub fn fromOwned(gpa: std.mem.Allocator, reader: anytype) !DirReader {
        const T = @TypeOf(reader);
        const owned = gpa.create(T) catch |err| {
            var released = reader;
            released.deinit();
            return err;
        };
        owned.* = reader;
        const Methods = struct {
            fn cast(raw: *anyopaque) *T {
                return @ptrCast(@alignCast(raw));
            }
            fn next(raw: *anyopaque, max: u64, context: types.Context) !types.Result(types.DirPage) {
                return cast(raw).next(max, context);
            }
            fn close(raw: *anyopaque, context: types.Context) void {
                cast(raw).close(context);
            }
            fn destroy(raw: *anyopaque, allocator: std.mem.Allocator) void {
                const value = cast(raw);
                value.deinit();
                allocator.destroy(value);
            }
            const table: VTable = .{ .next = @This().next, .close = @This().close, .destroy = @This().destroy };
        };
        return .{ .gpa = gpa, .context = owned, .vtable = &Methods.table };
    }
    pub fn next(self: *DirReader, max: u64, context: types.Context) !types.Result(types.DirPage) {
        return self.vtable.next(self.context.?, max, context);
    }
    pub fn close(self: *DirReader, context: types.Context) void {
        if (self.context) |raw| self.vtable.close(raw, context);
    }
    pub fn deinit(self: *DirReader) void {
        if (self.context) |raw| self.vtable.destroy(raw, self.gpa);
        self.context = null;
    }
};
pub const FileWatcher = struct {
    gpa: std.mem.Allocator,
    context: ?*anyopaque,
    vtable: *const VTable,
    const VTable = struct { mode: *const fn (*anyopaque) watching.Mode, close: *const fn (*anyopaque, types.Context) void, destroy: *const fn (*anyopaque) void };
    pub fn fromOwned(gpa: std.mem.Allocator, watcher: anytype) !*FileWatcher {
        const T = Provider(@TypeOf(watcher));
        const owned = gpa.create(FileWatcher) catch |err| {
            watcher.deinit();
            return err;
        };
        const Methods = struct {
            fn cast(raw: *anyopaque) *T {
                return @ptrCast(@alignCast(raw));
            }
            fn mode(raw: *anyopaque) watching.Mode {
                return cast(raw).mode.load(.acquire);
            }
            fn close(raw: *anyopaque, context: types.Context) void {
                cast(raw).close(context);
            }
            fn destroy(raw: *anyopaque) void {
                cast(raw).deinit();
            }
            const table: VTable = .{ .mode = @This().mode, .close = @This().close, .destroy = @This().destroy };
        };
        owned.* = .{ .gpa = gpa, .context = watcher, .vtable = &Methods.table };
        return owned;
    }
    pub fn mode(self: *const FileWatcher) watching.Mode {
        return self.vtable.mode(self.context.?);
    }
    pub fn close(self: *FileWatcher, context: types.Context) void {
        if (self.context) |raw| self.vtable.close(raw, context);
    }
    pub fn deinit(self: *FileWatcher) void {
        if (self.context) |raw| self.vtable.destroy(raw);
        self.gpa.destroy(self);
    }
};
pub const FileSystem = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    context: *anyopaque,
    vtable: *const VTable,
    const VTable = struct {
        id: *const fn (*anyopaque) []const u8,
        cwd: *const fn (*anyopaque) []const u8,
        setCwd: *const fn (*anyopaque, []const u8) anyerror!void,
        absolutePath: *const fn (*anyopaque, []const u8, types.Context) anyerror!types.Result([]u8),
        joinPath: *const fn (*anyopaque, []const []const u8, types.Context) anyerror!types.Result([]u8),
        readTextFile: *const fn (*anyopaque, []const u8, types.Context) anyerror!types.Result([]u8),
        readBinaryFile: *const fn (*anyopaque, []const u8, types.Context) anyerror!types.Result([]u8),
        readTextLines: *const fn (*anyopaque, []const u8, ?u64, types.Context) anyerror!types.Result([][]u8),
        openBinaryReader: *const fn (*anyopaque, []const u8, filesystem.OpenBinaryOptions, types.Context) anyerror!types.Result(BinaryReader),
        openTextLineReader: *const fn (*anyopaque, []const u8, types.Context) anyerror!types.Result(TextLineReader),
        openDirReader: *const fn (*anyopaque, []const u8, types.Context) anyerror!types.Result(DirReader),
        writeFile: *const fn (*anyopaque, []const u8, []const u8, types.Context) anyerror!types.Result(void),
        appendFile: *const fn (*anyopaque, []const u8, []const u8, types.Context) anyerror!types.Result(void),
        truncateFile: *const fn (*anyopaque, []const u8, u64, types.Context) anyerror!types.Result(void),
        flushFile: *const fn (*anyopaque, []const u8, types.Context) anyerror!types.Result(void),
        renameFile: *const fn (*anyopaque, []const u8, []const u8, types.Context) anyerror!types.Result(void),
        fileInfo: *const fn (*anyopaque, []const u8, types.Context) anyerror!types.Result(types.FileInfo),
        listDir: *const fn (*anyopaque, []const u8, types.Context) anyerror!types.Result([]types.FileInfo),
        canonicalPath: *const fn (*anyopaque, []const u8, types.Context) anyerror!types.Result([]u8),
        exists: *const fn (*anyopaque, []const u8, types.Context) anyerror!types.Result(bool),
        createDir: *const fn (*anyopaque, []const u8, filesystem.CreateDirOptions, types.Context) anyerror!types.Result(void),
        remove: *const fn (*anyopaque, []const u8, filesystem.RemoveOptions, types.Context) anyerror!types.Result(void),
        createTempDir: *const fn (*anyopaque, ?[]const u8, types.Context) anyerror!types.Result([]u8),
        createTempFile: *const fn (*anyopaque, filesystem.TempFileOptions, types.Context) anyerror!types.Result([]u8),
        watch: *const fn (*anyopaque, []const watching.Target, watching.Callback, ?*anyopaque, types.Context) anyerror!types.Result(*FileWatcher),
        cleanup: *const fn (*anyopaque, types.Context) void,
    };
    /// The provider and its allocator/I/O must outlive this borrowed capability
    /// and every reader/watcher it opens. Returned operation values are owned.
    pub fn from(provider: anytype) FileSystem {
        if (@TypeOf(provider) == FileSystem) return provider;
        if (@TypeOf(provider) == *FileSystem or @TypeOf(provider) == *const FileSystem) return provider.*;
        if (@TypeOf(provider) == ExecutionEnv) return provider.fs;
        if (@TypeOf(provider) == *ExecutionEnv or @TypeOf(provider) == *const ExecutionEnv) return provider.fs;
        const T = Provider(@TypeOf(provider));
        const Methods = struct {
            fn cast(raw: *anyopaque) *T {
                return @ptrCast(@alignCast(raw));
            }
            fn id(raw: *anyopaque) []const u8 {
                const owner = cast(raw);
                return if (@hasDecl(T, "id")) owner.id() else owner.id;
            }
            fn cwd(raw: *anyopaque) []const u8 {
                const owner = cast(raw);
                return if (@hasDecl(T, "cwd")) owner.cwd() else owner.cwd;
            }
            fn setCwd(raw: *anyopaque, path: []const u8) !void {
                if (@hasDecl(T, "setCwd")) return cast(raw).setCwd(path);
                return error.CwdMutationUnsupported;
            }
            fn absolutePath(raw: *anyopaque, path: []const u8, context: types.Context) !types.Result([]u8) {
                return cast(raw).absolutePath(path, context);
            }
            fn joinPath(raw: *anyopaque, parts: []const []const u8, context: types.Context) !types.Result([]u8) {
                return cast(raw).joinPath(parts, context);
            }
            fn readTextFile(raw: *anyopaque, path: []const u8, context: types.Context) !types.Result([]u8) {
                return cast(raw).readTextFile(path, context);
            }
            fn readBinaryFile(raw: *anyopaque, path: []const u8, context: types.Context) !types.Result([]u8) {
                return cast(raw).readBinaryFile(path, context);
            }
            fn readTextLines(raw: *anyopaque, path: []const u8, max: ?u64, context: types.Context) !types.Result([][]u8) {
                return cast(raw).readTextLines(path, max, context);
            }
            fn openBinaryReader(raw: *anyopaque, path: []const u8, options: filesystem.OpenBinaryOptions, context: types.Context) !types.Result(BinaryReader) {
                const owner = cast(raw);
                const result = try owner.openBinaryReader(path, options, context);
                return if (result == .failure) .{ .failure = result.failure } else .{ .value = try BinaryReader.fromOwned(allocatorOf(owner), result.value) };
            }
            fn openTextLineReader(raw: *anyopaque, path: []const u8, context: types.Context) !types.Result(TextLineReader) {
                const owner = cast(raw);
                const result = try owner.openTextLineReader(path, context);
                return if (result == .failure) .{ .failure = result.failure } else .{ .value = try TextLineReader.fromOwned(allocatorOf(owner), result.value) };
            }
            fn openDirReader(raw: *anyopaque, path: []const u8, context: types.Context) !types.Result(DirReader) {
                const owner = cast(raw);
                const result = try owner.openDirReader(path, context);
                return if (result == .failure) .{ .failure = result.failure } else .{ .value = try DirReader.fromOwned(allocatorOf(owner), result.value) };
            }
            fn writeFile(raw: *anyopaque, path: []const u8, bytes: []const u8, context: types.Context) !types.Result(void) {
                return cast(raw).writeFile(path, bytes, context);
            }
            fn appendFile(raw: *anyopaque, path: []const u8, bytes: []const u8, context: types.Context) !types.Result(void) {
                return cast(raw).appendFile(path, bytes, context);
            }
            fn truncateFile(raw: *anyopaque, path: []const u8, size: u64, context: types.Context) !types.Result(void) {
                return cast(raw).truncateFile(path, size, context);
            }
            fn flushFile(raw: *anyopaque, path: []const u8, context: types.Context) !types.Result(void) {
                return cast(raw).flushFile(path, context);
            }
            fn renameFile(raw: *anyopaque, source: []const u8, destination: []const u8, context: types.Context) !types.Result(void) {
                return cast(raw).renameFile(source, destination, context);
            }
            fn fileInfo(raw: *anyopaque, path: []const u8, context: types.Context) !types.Result(types.FileInfo) {
                return cast(raw).fileInfo(path, context);
            }
            fn listDir(raw: *anyopaque, path: []const u8, context: types.Context) !types.Result([]types.FileInfo) {
                return cast(raw).listDir(path, context);
            }
            fn canonicalPath(raw: *anyopaque, path: []const u8, context: types.Context) !types.Result([]u8) {
                return cast(raw).canonicalPath(path, context);
            }
            fn exists(raw: *anyopaque, path: []const u8, context: types.Context) !types.Result(bool) {
                return cast(raw).exists(path, context);
            }
            fn createDir(raw: *anyopaque, path: []const u8, options: filesystem.CreateDirOptions, context: types.Context) !types.Result(void) {
                return cast(raw).createDir(path, options, context);
            }
            fn remove(raw: *anyopaque, path: []const u8, options: filesystem.RemoveOptions, context: types.Context) !types.Result(void) {
                return cast(raw).remove(path, options, context);
            }
            fn createTempDir(raw: *anyopaque, prefix: ?[]const u8, context: types.Context) !types.Result([]u8) {
                return cast(raw).createTempDir(prefix, context);
            }
            fn createTempFile(raw: *anyopaque, options: filesystem.TempFileOptions, context: types.Context) !types.Result([]u8) {
                return cast(raw).createTempFile(options, context);
            }
            fn watch(raw: *anyopaque, targets: []const watching.Target, callback: watching.Callback, state: ?*anyopaque, context: types.Context) !types.Result(*FileWatcher) {
                const owner = cast(raw);
                const result = if (@typeInfo(@TypeOf(T.watch)).@"fn".params.len == 6) try owner.watch(targets, .{}, callback, state, context) else try owner.watch(targets, callback, state, context);
                return if (result == .failure) .{ .failure = result.failure } else .{ .value = try FileWatcher.fromOwned(allocatorOf(owner), result.value) };
            }
            fn cleanup(raw: *anyopaque, context: types.Context) void {
                if (@hasDecl(T, "cleanup")) cast(raw).cleanup(context);
            }
            const table: VTable = .{ .id = @This().id, .cwd = @This().cwd, .setCwd = @This().setCwd, .absolutePath = @This().absolutePath, .joinPath = @This().joinPath, .readTextFile = @This().readTextFile, .readBinaryFile = @This().readBinaryFile, .readTextLines = @This().readTextLines, .openBinaryReader = @This().openBinaryReader, .openTextLineReader = @This().openTextLineReader, .openDirReader = @This().openDirReader, .writeFile = @This().writeFile, .appendFile = @This().appendFile, .truncateFile = @This().truncateFile, .flushFile = @This().flushFile, .renameFile = @This().renameFile, .fileInfo = @This().fileInfo, .listDir = @This().listDir, .canonicalPath = @This().canonicalPath, .exists = @This().exists, .createDir = @This().createDir, .remove = @This().remove, .createTempDir = @This().createTempDir, .createTempFile = @This().createTempFile, .watch = @This().watch, .cleanup = @This().cleanup };
        };
        return .{ .gpa = allocatorOf(provider), .io = ioOf(provider), .context = provider, .vtable = &Methods.table };
    }
    pub fn id(self: *const FileSystem) []const u8 {
        return self.vtable.id(self.context);
    }
    pub fn cwd(self: *const FileSystem) []const u8 {
        return self.vtable.cwd(self.context);
    }
    pub fn setCwd(self: *const FileSystem, path: []const u8) !void {
        return self.vtable.setCwd(self.context, path);
    }
    pub fn absolutePath(self: *const FileSystem, path: []const u8, context: types.Context) !types.Result([]u8) {
        return self.vtable.absolutePath(self.context, path, context);
    }
    pub fn joinPath(self: *const FileSystem, parts: []const []const u8, context: types.Context) !types.Result([]u8) {
        return self.vtable.joinPath(self.context, parts, context);
    }
    pub fn readTextFile(self: *const FileSystem, path: []const u8, context: types.Context) !types.Result([]u8) {
        return self.vtable.readTextFile(self.context, path, context);
    }
    pub fn readBinaryFile(self: *const FileSystem, path: []const u8, context: types.Context) !types.Result([]u8) {
        return self.vtable.readBinaryFile(self.context, path, context);
    }
    pub fn readTextLines(self: *const FileSystem, path: []const u8, max: ?u64, context: types.Context) !types.Result([][]u8) {
        return self.vtable.readTextLines(self.context, path, max, context);
    }
    pub fn openBinaryReader(self: *const FileSystem, path: []const u8, options: filesystem.OpenBinaryOptions, context: types.Context) !types.Result(BinaryReader) {
        return self.vtable.openBinaryReader(self.context, path, options, context);
    }
    pub fn openTextLineReader(self: *const FileSystem, path: []const u8, context: types.Context) !types.Result(TextLineReader) {
        return self.vtable.openTextLineReader(self.context, path, context);
    }
    pub fn openDirReader(self: *const FileSystem, path: []const u8, context: types.Context) !types.Result(DirReader) {
        return self.vtable.openDirReader(self.context, path, context);
    }
    pub fn writeFile(self: *const FileSystem, path: []const u8, bytes: []const u8, context: types.Context) !types.Result(void) {
        return self.vtable.writeFile(self.context, path, bytes, context);
    }
    pub fn appendFile(self: *const FileSystem, path: []const u8, bytes: []const u8, context: types.Context) !types.Result(void) {
        return self.vtable.appendFile(self.context, path, bytes, context);
    }
    pub fn truncateFile(self: *const FileSystem, path: []const u8, size: u64, context: types.Context) !types.Result(void) {
        return self.vtable.truncateFile(self.context, path, size, context);
    }
    pub fn flushFile(self: *const FileSystem, path: []const u8, context: types.Context) !types.Result(void) {
        return self.vtable.flushFile(self.context, path, context);
    }
    pub fn renameFile(self: *const FileSystem, source: []const u8, destination: []const u8, context: types.Context) !types.Result(void) {
        return self.vtable.renameFile(self.context, source, destination, context);
    }
    pub fn fileInfo(self: *const FileSystem, path: []const u8, context: types.Context) !types.Result(types.FileInfo) {
        return self.vtable.fileInfo(self.context, path, context);
    }
    pub fn listDir(self: *const FileSystem, path: []const u8, context: types.Context) !types.Result([]types.FileInfo) {
        return self.vtable.listDir(self.context, path, context);
    }
    pub fn canonicalPath(self: *const FileSystem, path: []const u8, context: types.Context) !types.Result([]u8) {
        return self.vtable.canonicalPath(self.context, path, context);
    }
    pub fn exists(self: *const FileSystem, path: []const u8, context: types.Context) !types.Result(bool) {
        return self.vtable.exists(self.context, path, context);
    }
    pub fn createDir(self: *const FileSystem, path: []const u8, options: filesystem.CreateDirOptions, context: types.Context) !types.Result(void) {
        return self.vtable.createDir(self.context, path, options, context);
    }
    pub fn remove(self: *const FileSystem, path: []const u8, options: filesystem.RemoveOptions, context: types.Context) !types.Result(void) {
        return self.vtable.remove(self.context, path, options, context);
    }
    pub fn createTempDir(self: *const FileSystem, prefix: ?[]const u8, context: types.Context) !types.Result([]u8) {
        return self.vtable.createTempDir(self.context, prefix, context);
    }
    pub fn createTempFile(self: *const FileSystem, options: filesystem.TempFileOptions, context: types.Context) !types.Result([]u8) {
        return self.vtable.createTempFile(self.context, options, context);
    }
    pub fn watch(self: *const FileSystem, targets: []const watching.Target, callback: watching.Callback, state: ?*anyopaque, context: types.Context) !types.Result(*FileWatcher) {
        return self.vtable.watch(self.context, targets, callback, state, context);
    }
    pub fn cleanup(self: *const FileSystem, context: types.Context) void {
        self.vtable.cleanup(self.context, context);
    }
};
pub const ExecutionEnv = struct {
    fs: FileSystem,
    execute: *const fn (*anyopaque, shell.Command, shell.Options, types.Context) anyerror!shell.Result,
    pub fn from(provider: anytype) ExecutionEnv {
        if (@TypeOf(provider) == ExecutionEnv) return provider;
        if (@TypeOf(provider) == *ExecutionEnv or @TypeOf(provider) == *const ExecutionEnv) return provider.*;
        const T = Provider(@TypeOf(provider));
        const Methods = struct {
            fn exec(raw: *anyopaque, command: shell.Command, options: shell.Options, context: types.Context) !shell.Result {
                const owner: *T = @ptrCast(@alignCast(raw));
                return owner.exec(command, options, context);
            }
        };
        return .{ .fs = FileSystem.from(provider), .execute = Methods.exec };
    }
    pub fn id(self: *const ExecutionEnv) []const u8 {
        return self.fs.id();
    }
    pub fn cwd(self: *const ExecutionEnv) []const u8 {
        return self.fs.cwd();
    }
    pub fn setCwd(self: *const ExecutionEnv, path: []const u8) !void {
        return self.fs.setCwd(path);
    }
    pub fn cleanup(self: *const ExecutionEnv, context: types.Context) void {
        self.fs.cleanup(context);
    }
    pub fn exec(self: *const ExecutionEnv, command: shell.Command, options: shell.Options, context: types.Context) !shell.Result {
        return self.execute(self.fs.context, command, options, context);
    }
    pub fn absolutePath(self: *const ExecutionEnv, path: []const u8, context: types.Context) !types.Result([]u8) {
        return self.fs.absolutePath(path, context);
    }
    pub fn joinPath(self: *const ExecutionEnv, parts: []const []const u8, context: types.Context) !types.Result([]u8) {
        return self.fs.joinPath(parts, context);
    }
    pub fn readTextFile(self: *const ExecutionEnv, path: []const u8, context: types.Context) !types.Result([]u8) {
        return self.fs.readTextFile(path, context);
    }
    pub fn readBinaryFile(self: *const ExecutionEnv, path: []const u8, context: types.Context) !types.Result([]u8) {
        return self.fs.readBinaryFile(path, context);
    }
    pub fn readTextLines(self: *const ExecutionEnv, path: []const u8, max: ?u64, context: types.Context) !types.Result([][]u8) {
        return self.fs.readTextLines(path, max, context);
    }
    pub fn openBinaryReader(self: *const ExecutionEnv, path: []const u8, options: filesystem.OpenBinaryOptions, context: types.Context) !types.Result(BinaryReader) {
        return self.fs.openBinaryReader(path, options, context);
    }
    pub fn openTextLineReader(self: *const ExecutionEnv, path: []const u8, context: types.Context) !types.Result(TextLineReader) {
        return self.fs.openTextLineReader(path, context);
    }
    pub fn openDirReader(self: *const ExecutionEnv, path: []const u8, context: types.Context) !types.Result(DirReader) {
        return self.fs.openDirReader(path, context);
    }
    pub fn writeFile(self: *const ExecutionEnv, path: []const u8, bytes: []const u8, context: types.Context) !types.Result(void) {
        return self.fs.writeFile(path, bytes, context);
    }
    pub fn appendFile(self: *const ExecutionEnv, path: []const u8, bytes: []const u8, context: types.Context) !types.Result(void) {
        return self.fs.appendFile(path, bytes, context);
    }
    pub fn truncateFile(self: *const ExecutionEnv, path: []const u8, size: u64, context: types.Context) !types.Result(void) {
        return self.fs.truncateFile(path, size, context);
    }
    pub fn flushFile(self: *const ExecutionEnv, path: []const u8, context: types.Context) !types.Result(void) {
        return self.fs.flushFile(path, context);
    }
    pub fn renameFile(self: *const ExecutionEnv, source: []const u8, destination: []const u8, context: types.Context) !types.Result(void) {
        return self.fs.renameFile(source, destination, context);
    }
    pub fn fileInfo(self: *const ExecutionEnv, path: []const u8, context: types.Context) !types.Result(types.FileInfo) {
        return self.fs.fileInfo(path, context);
    }
    pub fn listDir(self: *const ExecutionEnv, path: []const u8, context: types.Context) !types.Result([]types.FileInfo) {
        return self.fs.listDir(path, context);
    }
    pub fn canonicalPath(self: *const ExecutionEnv, path: []const u8, context: types.Context) !types.Result([]u8) {
        return self.fs.canonicalPath(path, context);
    }
    pub fn exists(self: *const ExecutionEnv, path: []const u8, context: types.Context) !types.Result(bool) {
        return self.fs.exists(path, context);
    }
    pub fn createDir(self: *const ExecutionEnv, path: []const u8, options: filesystem.CreateDirOptions, context: types.Context) !types.Result(void) {
        return self.fs.createDir(path, options, context);
    }
    pub fn remove(self: *const ExecutionEnv, path: []const u8, options: filesystem.RemoveOptions, context: types.Context) !types.Result(void) {
        return self.fs.remove(path, options, context);
    }
    pub fn createTempDir(self: *const ExecutionEnv, prefix: ?[]const u8, context: types.Context) !types.Result([]u8) {
        return self.fs.createTempDir(prefix, context);
    }
    pub fn createTempFile(self: *const ExecutionEnv, options: filesystem.TempFileOptions, context: types.Context) !types.Result([]u8) {
        return self.fs.createTempFile(options, context);
    }
    pub fn watch(self: *const ExecutionEnv, targets: []const watching.Target, callback: watching.Callback, state: ?*anyopaque, context: types.Context) !types.Result(*FileWatcher) {
        return self.fs.watch(targets, callback, state, context);
    }
};
