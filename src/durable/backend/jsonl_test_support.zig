//! Actual filesystem calls with test-only failures at source publication points.
const std = @import("std");
const capability = @import("../env_capability.zig");
const types = @import("../types.zig");
const fs = @import("../filesystem.zig");
const watching = @import("../watch.zig");
pub const Operation = enum { append, flush, write, rename, remove };
pub const Mode = enum { before, after, short };
pub const Fault = struct { operation: Operation, call: usize, mode: Mode };
pub const Observed = struct {
    actual: capability.FileSystem,
    gpa: std.mem.Allocator,
    io: std.Io,
    operations: std.ArrayList([]u8) = .empty,
    counts: [5]usize = .{0} ** 5,
    fault: ?Fault = null,
    pub fn init(provider: anytype) Observed {
        const actual = capability.FileSystem.from(provider);
        return .{ .actual = actual, .gpa = actual.gpa, .io = actual.io };
    }
    pub fn deinit(self: *Observed) void {
        self.clear();
        self.operations.deinit(self.gpa);
    }
    pub fn clear(self: *Observed) void {
        for (self.operations.items) |value| self.gpa.free(value);
        self.operations.clearRetainingCapacity();
        self.counts = .{0} ** 5;
        self.fault = null;
    }
    fn before(self: *Observed, operation: Operation, path: []const u8) !?Mode {
        const message = try std.fmt.allocPrint(self.gpa, "{s}:{s}", .{ @tagName(operation), std.fs.path.basename(path) });
        errdefer self.gpa.free(message);
        try self.operations.append(self.gpa, message);
        const index = @intFromEnum(operation);
        self.counts[index] += 1;
        const fault = self.fault orelse return null;
        return if (fault.operation == operation and fault.call == self.counts[index]) fault.mode else null;
    }
    fn failure(self: *Observed, path: []const u8, mode: Mode) !types.Result(void) {
        return types.failure(void, self.gpa, .unknown, path, null, switch (mode) {
            .before => "injected-before",
            .after => "injected-after",
            .short => "injected-short",
        });
    }
    pub fn id(self: *Observed) []const u8 {
        return self.actual.id();
    }
    pub fn cwd(self: *Observed) []const u8 {
        return self.actual.cwd();
    }
    pub fn setCwd(self: *Observed, path: []const u8) !void {
        return self.actual.setCwd(path);
    }
    pub fn absolutePath(self: *Observed, path: []const u8, context: types.Context) !types.Result([]u8) {
        return self.actual.absolutePath(path, context);
    }
    pub fn joinPath(self: *Observed, parts: []const []const u8, context: types.Context) !types.Result([]u8) {
        return self.actual.joinPath(parts, context);
    }
    pub fn readTextFile(self: *Observed, path: []const u8, context: types.Context) !types.Result([]u8) {
        return self.actual.readTextFile(path, context);
    }
    pub fn readBinaryFile(self: *Observed, path: []const u8, context: types.Context) !types.Result([]u8) {
        return self.actual.readBinaryFile(path, context);
    }
    pub fn readTextLines(self: *Observed, path: []const u8, max: ?u64, context: types.Context) !types.Result([][]u8) {
        return self.actual.readTextLines(path, max, context);
    }
    pub fn openBinaryReader(self: *Observed, path: []const u8, options: fs.OpenBinaryOptions, context: types.Context) !types.Result(capability.BinaryReader) {
        return self.actual.openBinaryReader(path, options, context);
    }
    pub fn openTextLineReader(self: *Observed, path: []const u8, context: types.Context) !types.Result(capability.TextLineReader) {
        return self.actual.openTextLineReader(path, context);
    }
    pub fn openDirReader(self: *Observed, path: []const u8, context: types.Context) !types.Result(capability.DirReader) {
        return self.actual.openDirReader(path, context);
    }
    pub fn fileInfo(self: *Observed, path: []const u8, context: types.Context) !types.Result(types.FileInfo) {
        return self.actual.fileInfo(path, context);
    }
    pub fn listDir(self: *Observed, path: []const u8, context: types.Context) !types.Result([]types.FileInfo) {
        return self.actual.listDir(path, context);
    }
    pub fn canonicalPath(self: *Observed, path: []const u8, context: types.Context) !types.Result([]u8) {
        return self.actual.canonicalPath(path, context);
    }
    pub fn exists(self: *Observed, path: []const u8, context: types.Context) !types.Result(bool) {
        return self.actual.exists(path, context);
    }
    pub fn createDir(self: *Observed, path: []const u8, options: fs.CreateDirOptions, context: types.Context) !types.Result(void) {
        return self.actual.createDir(path, options, context);
    }
    pub fn createTempDir(self: *Observed, prefix: ?[]const u8, context: types.Context) !types.Result([]u8) {
        return self.actual.createTempDir(prefix, context);
    }
    pub fn createTempFile(self: *Observed, options: fs.TempFileOptions, context: types.Context) !types.Result([]u8) {
        return self.actual.createTempFile(options, context);
    }
    pub fn truncateFile(self: *Observed, path: []const u8, size: u64, context: types.Context) !types.Result(void) {
        return self.actual.truncateFile(path, size, context);
    }
    pub fn appendFile(self: *Observed, path: []const u8, bytes: []const u8, context: types.Context) !types.Result(void) {
        const mode = try self.before(.append, path);
        if (mode == .before) return self.failure(path, .before);
        if (mode == .short) {
            const first = if (std.mem.indexOfScalar(u8, bytes, '\n')) |index| index + 1 else 0;
            const partial = try self.actual.appendFile(path, bytes[0..@min(bytes.len, @max(first + 1, bytes.len * 3 / 5))], context);
            if (partial == .failure) return partial;
            return self.failure(path, .short);
        }
        const result = try self.actual.appendFile(path, bytes, context);
        if (result == .failure) return result;
        if (mode == .after) return self.failure(path, .after);
        return result;
    }
    pub fn flushFile(self: *Observed, path: []const u8, context: types.Context) !types.Result(void) {
        const mode = try self.before(.flush, path);
        if (mode == .before) return self.failure(path, .before);
        const result = try self.actual.flushFile(path, context);
        if (result == .failure) return result;
        return if (mode == .after) self.failure(path, .after) else result;
    }
    pub fn writeFile(self: *Observed, path: []const u8, bytes: []const u8, context: types.Context) !types.Result(void) {
        const mode = try self.before(.write, path);
        if (mode == .before) return self.failure(path, .before);
        const result = try self.actual.writeFile(path, bytes, context);
        if (result == .failure) return result;
        return if (mode == .after) self.failure(path, .after) else result;
    }
    pub fn renameFile(self: *Observed, source: []const u8, destination: []const u8, context: types.Context) !types.Result(void) {
        const mode = try self.before(.rename, source);
        if (mode == .before) return self.failure(source, .before);
        const result = try self.actual.renameFile(source, destination, context);
        if (result == .failure) return result;
        return if (mode == .after) self.failure(source, .after) else result;
    }
    pub fn remove(self: *Observed, path: []const u8, options: fs.RemoveOptions, context: types.Context) !types.Result(void) {
        const mode = try self.before(.remove, path);
        if (mode == .before) return self.failure(path, .before);
        const result = try self.actual.remove(path, options, context);
        if (result == .failure) return result;
        return if (mode == .after) self.failure(path, .after) else result;
    }
    pub fn watch(self: *Observed, targets: []const watching.Target, callback: watching.Callback, state: ?*anyopaque, context: types.Context) !types.Result(*capability.FileWatcher) {
        return self.actual.watch(targets, callback, state, context);
    }
    pub fn cleanup(self: *Observed, context: types.Context) void {
        self.actual.cleanup(context);
    }
};
