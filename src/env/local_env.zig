//! Local native environment with daemon-backed listFiles; its connection is borrowed.
const std = @import("std");
const native = @import("../durable/execution_env.zig");
const types = @import("../durable/types.zig");
const filesystem = @import("../durable/filesystem.zig");
const commands = @import("../durable/shell.zig");
const watching = @import("../durable/watch.zig");
const remote = @import("remote_env.zig");
pub const Options = struct { node: native.Options, connection: remote.Transport };
pub const LocalExecutionEnv = struct {
    node: native.ExecutionEnv,
    connection: remote.Transport,
    gpa: std.mem.Allocator,
    pub fn init(gpa: std.mem.Allocator, io_value: std.Io, options: Options) !LocalExecutionEnv {
        return .{ .node = try native.ExecutionEnv.init(gpa, io_value, options.node), .connection = options.connection, .gpa = gpa };
    }
    pub fn io(self: *const LocalExecutionEnv) std.Io {
        return self.node.fs.io;
    }
    pub fn setCwd(self: *LocalExecutionEnv, path: []const u8) !void {
        return self.node.setCwd(path);
    }
    pub fn deinit(self: *LocalExecutionEnv) void {
        self.node.deinit();
        self.* = undefined;
    }
    pub fn cleanup(self: *LocalExecutionEnv, context: types.Context) void {
        self.node.cleanup(context);
    }
    pub fn listFiles(self: *const LocalExecutionEnv, path: []const u8, options: filesystem.ListFilesOptions, context: types.Context) !types.Result(filesystem.FileListing) {
        const resolved = @import("../durable/path.zig").resolveListing(self.gpa, self.node.fs.cwd, path, self.node.fs.home) catch |err| return types.fromError(filesystem.FileListing, self.gpa, err, path);
        defer self.gpa.free(resolved);
        var adapter = try remote.RemoteExecutionEnv.init(self.gpa, .{ .connection = self.connection, .id = self.id(), .cwd = self.cwd() });
        defer adapter.deinit();
        return adapter.listFilesOver(resolved, options, context);
    }
    pub fn id(self: *const LocalExecutionEnv) []const u8 {
        return self.node.id();
    }
    pub fn cwd(self: *const LocalExecutionEnv) []const u8 {
        return self.node.cwd();
    }
    pub fn exec(self: *LocalExecutionEnv, command: commands.Command, options: commands.Options, context: types.Context) !commands.Result {
        return self.node.exec(command, options, context);
    }
    pub fn watch(self: *LocalExecutionEnv, targets: []const watching.Target, callback: watching.Callback, callback_context: ?*anyopaque, context: types.Context) !types.Result(*watching.Watcher) {
        return self.node.watch(targets, callback, callback_context, context);
    }
    pub fn absolutePath(self: *const LocalExecutionEnv, path: []const u8, context: types.Context) !types.Result([]u8) {
        return self.node.absolutePath(path, context);
    }
    pub fn joinPath(self: *const LocalExecutionEnv, parts: []const []const u8, context: types.Context) !types.Result([]u8) {
        return self.node.joinPath(parts, context);
    }
    pub fn readTextFile(self: *const LocalExecutionEnv, path: []const u8, context: types.Context) !types.Result([]u8) {
        return self.node.readTextFile(path, context);
    }
    pub fn readBinaryFile(self: *const LocalExecutionEnv, path: []const u8, context: types.Context) !types.Result([]u8) {
        return self.node.readBinaryFile(path, context);
    }
    pub fn readTextLines(self: *const LocalExecutionEnv, path: []const u8, max_lines: ?u64, context: types.Context) !types.Result([][]u8) {
        return self.node.readTextLines(path, max_lines, context);
    }
    pub fn openTextLineReader(self: *const LocalExecutionEnv, path: []const u8, context: types.Context) !types.Result(filesystem.TextLineReader) {
        return self.node.openTextLineReader(path, context);
    }
    pub fn openBinaryReader(self: *const LocalExecutionEnv, path: []const u8, options: filesystem.OpenBinaryOptions, context: types.Context) !types.Result(filesystem.BinaryReader) {
        return self.node.openBinaryReader(path, options, context);
    }
    pub fn openDirReader(self: *const LocalExecutionEnv, path: []const u8, context: types.Context) !types.Result(filesystem.DirReader) {
        return self.node.openDirReader(path, context);
    }
    pub fn writeFile(self: *const LocalExecutionEnv, path: []const u8, content: []const u8, context: types.Context) !types.Result(void) {
        return self.node.writeFile(path, content, context);
    }
    pub fn appendFile(self: *const LocalExecutionEnv, path: []const u8, content: []const u8, context: types.Context) !types.Result(void) {
        return self.node.appendFile(path, content, context);
    }
    pub fn truncateFile(self: *const LocalExecutionEnv, path: []const u8, size: u64, context: types.Context) !types.Result(void) {
        return self.node.truncateFile(path, size, context);
    }
    pub fn flushFile(self: *const LocalExecutionEnv, path: []const u8, context: types.Context) !types.Result(void) {
        return self.node.flushFile(path, context);
    }
    pub fn renameFile(self: *const LocalExecutionEnv, source: []const u8, destination: []const u8, context: types.Context) !types.Result(void) {
        return self.node.renameFile(source, destination, context);
    }
    pub fn fileInfo(self: *const LocalExecutionEnv, path: []const u8, context: types.Context) !types.Result(types.FileInfo) {
        return self.node.fileInfo(path, context);
    }
    pub fn listDir(self: *const LocalExecutionEnv, path: []const u8, context: types.Context) !types.Result([]types.FileInfo) {
        return self.node.listDir(path, context);
    }
    pub fn canonicalPath(self: *const LocalExecutionEnv, path: []const u8, context: types.Context) !types.Result([]u8) {
        return self.node.canonicalPath(path, context);
    }
    pub fn exists(self: *const LocalExecutionEnv, path: []const u8, context: types.Context) !types.Result(bool) {
        return self.node.exists(path, context);
    }
    pub fn createDir(self: *const LocalExecutionEnv, path: []const u8, options: filesystem.CreateDirOptions, context: types.Context) !types.Result(void) {
        return self.node.createDir(path, options, context);
    }
    pub fn remove(self: *const LocalExecutionEnv, path: []const u8, options: filesystem.RemoveOptions, context: types.Context) !types.Result(void) {
        return self.node.remove(path, options, context);
    }
    pub fn createTempDir(self: *const LocalExecutionEnv, prefix: ?[]const u8, context: types.Context) !types.Result([]u8) {
        return self.node.createTempDir(prefix, context);
    }
    pub fn createTempFile(self: *const LocalExecutionEnv, options: filesystem.TempFileOptions, context: types.Context) !types.Result([]u8) {
        return self.node.createTempFile(options, context);
    }
};
