//! Complete local environment capability; storage and Harness use this boundary.
const std = @import("std");
const types = @import("types.zig");
const filesystem = @import("filesystem.zig");
const commands = @import("shell.zig");
const startup = @import("startup.zig");
const watching = @import("watch.zig");
pub const Options = struct {
    cwd: []const u8,
    environ: *const std.process.Environ.Map,
    home: ?[]const u8 = null,
    temp_dir: ?[]const u8 = null,
    shellPath: ?[]const u8 = null,
    shellEnv: ?*const std.process.Environ.Map = null,
    watch: watching.Options = .{},
};
pub const ExecutionEnv = struct {
    fs: filesystem.FileSystem,
    shell: commands.Shell,
    watch_options: watching.Options,
    pub fn id(self: *const ExecutionEnv) []const u8 {
        return self.fs.id;
    }
    pub fn cwd(self: *const ExecutionEnv) []const u8 {
        return self.fs.cwd;
    }
    pub fn setCwd(self: *ExecutionEnv, input: []const u8) !void {
        const path = try self.fs.resolvePath(input);
        errdefer self.fs.gpa.free(path);
        const shell_path = try self.fs.gpa.dupe(u8, path);
        self.fs.gpa.free(self.fs.cwd);
        self.shell.gpa.free(self.shell.cwd);
        self.fs.cwd = path;
        self.shell.cwd = shell_path;
    }
    pub fn init(gpa: std.mem.Allocator, io: std.Io, options: Options) !ExecutionEnv {
        var fs = try filesystem.FileSystem.init(gpa, io, options.cwd, options.home orelse startup.home(options.environ));
        errdefer fs.deinit();
        const generated_temp = if (options.temp_dir == null) try startup.tempDirectory(gpa, options.environ) else null;
        defer if (generated_temp) |path| gpa.free(path);
        const temp = options.temp_dir orelse generated_temp.?;
        try fs.setTempDirectory(temp);
        const shell = try commands.Shell.init(gpa, io, fs.cwd, options.environ, options.shellEnv, options.shellPath, fs.temp_dir.?);
        return .{ .fs = fs, .shell = shell, .watch_options = options.watch };
    }
    pub fn deinit(self: *ExecutionEnv) void {
        self.shell.deinit();
        self.fs.deinit();
        self.* = undefined;
    }
    pub fn cleanup(self: *ExecutionEnv, context: types.Context) void {
        self.shell.cleanup(context);
    }
    pub fn exec(self: *ExecutionEnv, command: commands.Command, options: commands.Options, context: types.Context) !commands.Result {
        return self.shell.exec(command, options, context);
    }
    pub fn watch(self: *ExecutionEnv, targets: []const watching.Target, callback: watching.Callback, callback_context: ?*anyopaque, context: types.Context) !types.Result(*watching.Watcher) {
        return self.fs.watch(targets, self.watch_options, callback, callback_context, context);
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
    pub fn readTextLines(self: *const ExecutionEnv, path: []const u8, max_lines: ?u64, context: types.Context) !types.Result([][]u8) {
        return self.fs.readTextLines(path, max_lines, context);
    }
    pub fn openTextLineReader(self: *const ExecutionEnv, path: []const u8, context: types.Context) !types.Result(filesystem.TextLineReader) {
        return self.fs.openTextLineReader(path, context);
    }
    pub fn openBinaryReader(self: *const ExecutionEnv, path: []const u8, options: filesystem.OpenBinaryOptions, context: types.Context) !types.Result(filesystem.BinaryReader) {
        return self.fs.openBinaryReader(path, options, context);
    }
    pub fn openDirReader(self: *const ExecutionEnv, path: []const u8, context: types.Context) !types.Result(filesystem.DirReader) {
        return self.fs.openDirReader(path, context);
    }
    pub fn writeFile(self: *const ExecutionEnv, path: []const u8, content: []const u8, context: types.Context) !types.Result(void) {
        return self.fs.writeFile(path, content, context);
    }
    pub fn appendFile(self: *const ExecutionEnv, path: []const u8, content: []const u8, context: types.Context) !types.Result(void) {
        return self.fs.appendFile(path, content, context);
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
};

test "durable ExecutionEnv forwards real capabilities and cwd changes atomically" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    var environ: std.process.Environ.Map = .init(gpa);
    defer environ.deinit();
    var env = try ExecutionEnv.init(gpa, io, .{ .cwd = buffer[0..length], .environ = &environ, .temp_dir = buffer[0..length] });
    defer env.deinit();
    try std.testing.expectEqualStrings("native:local", env.id());
    const created = try env.createDir("sub", .{}, .{});
    try std.testing.expect(created == .value);
    try env.setCwd("sub");
    try std.testing.expectEqualStrings(env.fs.cwd, env.shell.cwd);
    const written = try env.writeFile("file", "local-env", .{});
    try std.testing.expect(written == .value);
    const read = try env.readTextFile("file", .{});
    try std.testing.expect(read == .value);
    defer gpa.free(read.value);
    try std.testing.expectEqualStrings("local-env", read.value);
    env.cleanup(.{});
}
