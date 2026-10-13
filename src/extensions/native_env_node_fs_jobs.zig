//! Local filesystem jobs snapshot guest arguments on the owner and perform native I/O off the VM.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const owner = @import("native_env_io.zig");
const errors = @import("native_env_node_errors.zig");
const files = @import("native_env_node_file_io.zig");
const c = js.c;
const Method = enum(c_int) { open, lstat, readFile, writeFile, appendFile, mkdir, rename, realpath };
const Job = struct {
    task: owner.Task,
    method: Method,
    bindings: c.JSValue,
    path: []u8,
    destination: []u8 = &.{},
    content: []u8 = &.{},
    result: std.ArrayList(u8) = .empty,
    mode: std.Io.File.OpenMode = .read_only,
    recursive: bool = false,
    file: ?std.Io.File = null,
    info: ?std.Io.File.Stat = null,
    failure: ?anyerror = null,
    phase: []const u8,
    include_path: bool = true,
    aborted: std.atomic.Value(bool) = .init(false),
    fn run(task: *owner.Task) void {
        const self: *Job = @alignCast(@fieldParentPtr("task", task));
        self.execute() catch |err| {
            self.failure = err;
        };
        task.finish();
    }
    fn execute(self: *Job) !void {
        const io = self.task.hub.io;
        const gpa = self.task.hub.engine.gpa;
        if (self.aborted.load(.acquire)) return error.Canceled;
        const cwd = std.Io.Dir.cwd();
        switch (self.method) {
            .open => self.file = try cwd.openFile(io, self.path, .{ .mode = self.mode, .allow_directory = true }),
            .lstat => self.info = try cwd.statFile(io, self.path, .{ .follow_symlinks = false }),
            .readFile => {
                const file = try cwd.openFile(io, self.path, .{ .allow_directory = true });
                defer file.close(io);
                self.phase = "read";
                self.include_path = false;
                if ((try file.stat(io)).kind == .directory) return error.IsDir;
                var chunk: [64 * 1024]u8 = undefined;
                while (true) {
                    if (self.aborted.load(.acquire)) return error.Canceled;
                    var buffers = [_][]u8{&chunk};
                    const count = try file.readStreaming(io, &buffers);
                    if (count == 0) break;
                    try self.result.appendSlice(gpa, chunk[0..count]);
                }
            },
            .writeFile => {
                const file = try cwd.createFile(io, self.path, .{});
                defer file.close(io);
                self.phase = "write";
                self.include_path = false;
                var position: usize = 0;
                while (position < self.content.len) {
                    if (self.aborted.load(.acquire)) return error.Canceled;
                    const end = @min(self.content.len, position + 512 * 1024);
                    try file.writeStreamingAll(io, self.content[position..end]);
                    position = end;
                }
            },
            .appendFile => {
                // Windows permits opening a directory here; its write reports EISDIR without a path.
                const file = cwd.openFile(io, self.path, .{ .mode = .write_only, .allow_directory = true }) catch |err| opened: {
                    if (err != error.FileNotFound) return err;
                    break :opened try cwd.createFile(io, self.path, .{ .truncate = false });
                };
                defer file.close(io);
                self.phase = "write";
                self.include_path = false;
                if ((try file.stat(io)).kind == .directory) return error.IsDir;
                if (builtin.os.tag == .windows) {
                    try @import("../durable/filesystem.zig").appendWindows(file, self.content);
                } else {
                    // Positional append is provisional here; atomic O_APPEND admission remains to qualify on POSIX.
                    const stat = try file.stat(io);
                    try file.writePositionalAll(io, self.content, stat.size);
                }
            },
            .mkdir => {
                if (self.recursive) try cwd.createDirPath(io, self.path) else try cwd.createDir(io, self.path, .default_dir);
            },
            .rename => try cwd.rename(self.path, cwd, self.destination, io),
            .realpath => {
                const value = try cwd.realPathFileAlloc(io, self.path, gpa);
                defer gpa.free(value);
                try self.result.appendSlice(gpa, value);
            },
        }
    }
    fn cancel(task: *owner.Task) void {
        const self: *Job = @alignCast(@fieldParentPtr("task", task));
        self.aborted.store(true, .release);
    }
    fn failureValue(self: *Job, scope: *h.Scope, failure: anyerror) !c.JSValue {
        const windows = builtin.os.tag == .windows;
        var fields: errors.SystemFailure = switch (failure) {
            error.FileNotFound => .{ .code = "ENOENT", .description = "no such file or directory", .errno = if (windows) -4058 else -2, .syscall = self.phase },
            error.NotDir => .{ .code = "ENOTDIR", .description = "not a directory", .errno = if (windows) -4052 else -20, .syscall = self.phase },
            error.IsDir => .{ .code = "EISDIR", .description = "illegal operation on a directory", .errno = if (windows) -4068 else -21, .syscall = self.phase },
            error.PathAlreadyExists => .{ .code = "EEXIST", .description = "file already exists", .errno = if (windows) -4075 else -17, .syscall = self.phase },
            error.AccessDenied => .{ .code = "EACCES", .description = "permission denied", .errno = if (windows) -4092 else -13, .syscall = self.phase },
            error.PermissionDenied => .{ .code = "EPERM", .description = "operation not permitted", .errno = if (windows) -4048 else -1, .syscall = self.phase },
            error.InvalidArgument => .{ .code = "EINVAL", .description = "invalid argument", .errno = if (windows) -4071 else -22, .syscall = self.phase },
            else => return error.UnclassifiedNativeNodeFilesystemFailure,
        };
        fields.path = if (self.include_path) self.path else null;
        if (self.method == .rename) fields.destination = self.destination;
        return errors.systemError(scope, fields);
    }
    fn complete(task: *owner.Task) anyerror!void {
        const self: *Job = @alignCast(@fieldParentPtr("task", task));
        const engine = task.hub.engine;
        var scope: h.Scope = .{ .engine = engine };
        defer scope.deinit();
        if (self.failure) |failure| {
            if (failure == error.OutOfMemory) return failure;
            return task.settled(true, try self.failureValue(&scope, failure));
        }
        const result = switch (self.method) {
            .open => opened: {
                const file = self.file.?;
                self.file = null;
                break :opened try scope.own(try files.create(&scope, file, self.mode != .read_only, self.bindings));
            },
            .lstat => try files.statsValue(&scope, self.info.?),
            .readFile => try scope.own(try @import("node_buffer.zig").fromBytes(engine, self.result.items)),
            .realpath => try scope.text(self.result.items),
            else => c.pi_js_undefined(),
        };
        try task.settled(false, result);
    }
    fn destroy(task: *owner.Task) void {
        const self: *Job = @alignCast(@fieldParentPtr("task", task));
        const engine = task.hub.engine;
        if (self.file) |file| file.close(task.hub.io);
        engine.gpa.free(self.path);
        engine.gpa.free(self.destination);
        engine.gpa.free(self.content);
        self.result.deinit(engine.gpa);
        engine.freeValue(self.bindings);
        task.releaseFunctions();
        engine.gpa.destroy(self);
    }
};
fn submit(engine: *js.Engine, args: []const c.JSValue, bindings: c.JSValue, method: Method) !c.JSValue {
    var scope: h.Scope = .{ .engine = engine };
    defer scope.deinit();
    const path = try engine.toString(h.arg(args, 0));
    var path_transferred = false;
    defer if (!path_transferred) engine.gpa.free(path);
    if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidNativeNodePathValue;
    const hub = try owner.get(engine);
    var functions: [2]c.JSValue = undefined;
    const promise = try scope.own(try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions)));
    var transferred = false;
    errdefer if (!transferred) {
        engine.freeValue(functions[0]);
        engine.freeValue(functions[1]);
    };
    const job = try engine.gpa.create(Job);
    job.* = .{ .task = .{ .hub = hub, .work = Job.run, .complete = Job.complete, .destroy = Job.destroy, .cancel = Job.cancel, .resolve = functions[0], .reject = functions[1] }, .method = method, .bindings = c.JS_DupValue(engine.context, bindings), .path = path, .phase = switch (method) {
        .open, .readFile, .writeFile, .appendFile => "open",
        .lstat => "lstat",
        .mkdir => "mkdir",
        .rename => "rename",
        .realpath => "realpath",
    } };
    transferred = true;
    path_transferred = true;
    errdefer Job.destroy(&job.task);
    switch (method) {
        .open => {
            const mode = h.arg(args, 1);
            if (scope.equal(mode, try scope.text("r+"))) job.mode = .read_write else if (!scope.equal(mode, try scope.text("r"))) return error.UnsupportedNativeNodeOpenMode;
        },
        .mkdir => job.recursive = scope.truthy(try h.optional(&scope, h.arg(args, 1), "recursive")),
        .rename => job.destination = try engine.toString(h.arg(args, 1)),
        .writeFile, .appendFile => {
            const content = h.arg(args, 1);
            if (c.JS_IsString(content)) job.content = try engine.toString(content) else {
                var offset: usize = undefined;
                var length: usize = undefined;
                var element: usize = undefined;
                const backing = try scope.own(try engine.checked(c.JS_GetTypedArrayBuffer(engine.context, content, &offset, &length, &element)));
                var total: usize = undefined;
                const data = c.JS_GetArrayBuffer(engine.context, &total, backing);
                if ((data == null and length != 0) or offset > total or length > total - offset) return error.InvalidNativeNodeContent;
                job.content = try engine.gpa.dupe(u8, if (length == 0) &.{} else data[offset..][0..length]);
            }
        },
        else => {},
    }
    try hub.submit(&job.task);
    return c.JS_DupValue(engine.context, promise);
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return submit(engine, if (argc > 0) argv[0..@intCast(argc)] else &.{}, data[0], @enumFromInt(raw)) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
pub fn create(scope: *h.Scope, bindings: c.JSValue) !c.JSValue {
    const object = try scope.object();
    var data = [_]c.JSValue{bindings};
    inline for (std.meta.fields(Method)) |field| {
        const function = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, dispatch, field.name, if (field.value == @intFromEnum(Method.lstat) or field.value == @intFromEnum(Method.readFile) or field.value == @intFromEnum(Method.realpath)) 1 else 2, @intCast(field.value), 1, &data)));
        try scope.put(object, field.name, function);
    }
    return c.JS_DupValue(scope.engine.context, object);
}
