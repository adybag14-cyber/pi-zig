//! Native libuv filesystem workers. Arguments and completion values belong to the VM owner.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const owner = @import("native_env_io.zig");
const errors = @import("native_env_node_errors.zig");
const files = @import("native_env_node_file_io.zig");
const uv = @import("native_uv_api").c;
const c = js.c;
const Method = enum(c_int) { open, lstat, readFile, writeFile, appendFile, mkdir, rename, realpath, readdir, opendir, rm, mkdtemp };
const Job = struct {
    task: owner.Task,
    method: Method,
    bindings: c.JSValue,
    path: [:0]u8,
    destination: ?[:0]u8 = null,
    result: std.ArrayList(u8) = .empty,
    flags: c_int = uv.UV_FS_O_RDONLY,
    recursive: bool = false,
    force: bool = false,
    fd: ?uv.uv_file = null,
    directory: ?*uv.uv_dir_t = null,
    entries: std.ArrayList([]u8) = .empty,
    info: ?uv.uv_stat_t = null,
    native_status: c_int = 0,
    failure: ?anyerror = null,
    phase: []const u8,
    aborted: std.atomic.Value(bool) = .init(false),
    fn run(task: *owner.Task) void {
        const self: *Job = @alignCast(@fieldParentPtr("task", task));
        self.execute() catch |err| {
            self.failure = err;
        };
        task.finish();
    }
    fn mkdirRecursive(self: *Job, path: [:0]const u8) !c_int {
        var request: uv.uv_fs_t = std.mem.zeroes(uv.uv_fs_t);
        defer uv.uv_fs_req_cleanup(&request);
        const result = uv.uv_fs_mkdir(null, &request, path, 0o777, null);
        if (result == uv.UV_ENOENT) {
            const parent = std.fs.path.dirname(path) orelse return result;
            if (std.mem.eql(u8, parent, path)) return result;
            const terminated = try self.task.hub.engine.gpa.dupeZ(u8, parent);
            defer self.task.hub.engine.gpa.free(terminated);
            const made = try self.mkdirRecursive(terminated);
            if (made < 0) return made;
            uv.uv_fs_req_cleanup(&request);
            return uv.uv_fs_mkdir(null, &request, path, 0o777, null);
        }
        if (result == uv.UV_EEXIST) {
            uv.uv_fs_req_cleanup(&request);
            if (uv.uv_fs_stat(null, &request, path, null) == 0 and (request.statbuf.st_mode & 0o170000) == 0o040000) return 0;
        }
        return result;
    }
    fn removeRecursive(self: *Job, path: [:0]const u8) !c_int {
        if (self.aborted.load(.acquire)) return error.Canceled;
        var request: uv.uv_fs_t = std.mem.zeroes(uv.uv_fs_t);
        defer uv.uv_fs_req_cleanup(&request);
        var status = uv.uv_fs_lstat(null, &request, path, null);
        if (status < 0) return if (status == uv.UV_ENOENT and self.force) 0 else status;
        if ((request.statbuf.st_mode & 0o170000) != 0o040000) {
            uv.uv_fs_req_cleanup(&request);
            return uv.uv_fs_unlink(null, &request, path, null);
        }
        if (!self.recursive) return error.NodeRmDirectory;
        uv.uv_fs_req_cleanup(&request);
        status = uv.uv_fs_scandir(null, &request, path, 0, null);
        if (status < 0) return status;
        var entry: uv.uv_dirent_t = undefined;
        while (uv.uv_fs_scandir_next(&request, &entry) == 0) {
            const child = try std.fs.path.join(self.task.hub.engine.gpa, &.{ path, std.mem.span(entry.name) });
            defer self.task.hub.engine.gpa.free(child);
            const terminated = try self.task.hub.engine.gpa.dupeZ(u8, child);
            defer self.task.hub.engine.gpa.free(terminated);
            status = try self.removeRecursive(terminated);
            if (status < 0) return status;
        }
        uv.uv_fs_req_cleanup(&request);
        return uv.uv_fs_rmdir(null, &request, path, null);
    }
    fn execute(self: *Job) !void {
        const gpa = self.task.hub.engine.gpa;
        if (self.aborted.load(.acquire)) return error.Canceled;
        var request: uv.uv_fs_t = std.mem.zeroes(uv.uv_fs_t);
        defer uv.uv_fs_req_cleanup(&request);
        const status = switch (self.method) {
            .open => uv.uv_fs_open(null, &request, self.path, self.flags, 0o666, null),
            .lstat => uv.uv_fs_lstat(null, &request, self.path, null),
            .mkdir => if (self.recursive) try self.mkdirRecursive(self.path) else uv.uv_fs_mkdir(null, &request, self.path, 0o777, null),
            .rename => uv.uv_fs_rename(null, &request, self.path, self.destination.?, null),
            .realpath => uv.uv_fs_realpath(null, &request, self.path, null),
            .opendir => uv.uv_fs_opendir(null, &request, self.path, null),
            .readdir => uv.uv_fs_scandir(null, &request, self.path, 0, null),
            .rm => try self.removeRecursive(self.path),
            .mkdtemp => temp: {
                const template = try std.fmt.allocPrintSentinel(gpa, "{s}XXXXXX", .{self.path}, 0);
                defer gpa.free(template);
                break :temp uv.uv_fs_mkdtemp(null, &request, template, null);
            },
            .readFile, .writeFile, .appendFile => unreachable, // These use owner-side open/stat/chunk/close continuations.
        };
        if (status < 0) {
            self.native_status = status;
            return;
        }
        switch (self.method) {
            .open => self.fd = status,
            .lstat => self.info = request.statbuf,
            .realpath => try self.result.appendSlice(gpa, std.mem.span(@as([*:0]const u8, @ptrCast(request.ptr)))),
            .mkdtemp => try self.result.appendSlice(gpa, std.mem.span(request.path)),
            .opendir => self.directory = @ptrCast(@alignCast(request.ptr)),
            .readdir => {
                var entry: uv.uv_dirent_t = undefined;
                while (uv.uv_fs_scandir_next(&request, &entry) == 0) {
                    const copy = try gpa.dupe(u8, std.mem.span(entry.name));
                    self.entries.append(gpa, copy) catch |err| {
                        gpa.free(copy);
                        return err;
                    };
                }
            },
            else => {},
        }
    }
    fn cancel(task: *owner.Task) void {
        const self: *Job = @alignCast(@fieldParentPtr("task", task));
        self.aborted.store(true, .release);
    }
    fn complete(task: *owner.Task) anyerror!void {
        const self: *Job = @alignCast(@fieldParentPtr("task", task));
        const engine = task.hub.engine;
        var scope: h.Scope = .{ .engine = engine };
        defer scope.deinit();
        if (self.failure) |failure| {
            if (failure == error.NodeRmDirectory) return task.settled(true, try errors.removeDirectoryError(&scope, self.path));
            return failure;
        }
        if (self.native_status < 0) return task.settled(true, try errors.systemError(&scope, .{ .code = std.mem.span(uv.uv_err_name(self.native_status)), .description = std.mem.span(uv.uv_strerror(self.native_status)), .errno = self.native_status, .syscall = self.phase, .path = self.path, .destination = self.destination }));
        const result = switch (self.method) {
            .open => opened: {
                const fd = self.fd.?;
                self.fd = null;
                break :opened try scope.own(try files.createDescriptor(&scope, fd, (self.flags & (uv.UV_FS_O_WRONLY | uv.UV_FS_O_RDWR)) != 0, self.bindings));
            },
            .opendir => opened: {
                const dir = self.directory.?;
                self.directory = null;
                break :opened try scope.own(try @import("native_env_node_dir_io.zig").create(&scope, dir, self.path));
            },
            .readdir => entries: {
                const array = try scope.array();
                for (self.entries.items, 0..) |name, index| {
                    const entry = try scope.object();
                    try scope.put(entry, "name", try scope.text(name));
                    try scope.index(array, @intCast(index), entry);
                }
                break :entries array;
            },
            .lstat => try files.statsValue(&scope, self.info.?, self.bindings, false),
            .realpath, .mkdtemp => try scope.text(self.result.items),
            else => c.pi_js_undefined(),
        };
        try task.settled(false, result);
    }
    fn destroy(task: *owner.Task) void {
        const self: *Job = @alignCast(@fieldParentPtr("task", task));
        const engine = task.hub.engine;
        if (self.fd) |fd| {
            var request: uv.uv_fs_t = std.mem.zeroes(uv.uv_fs_t);
            _ = uv.uv_fs_close(null, &request, fd, null);
            uv.uv_fs_req_cleanup(&request);
        }
        if (self.directory) |dir| {
            var request: uv.uv_fs_t = std.mem.zeroes(uv.uv_fs_t);
            _ = uv.uv_fs_closedir(null, &request, dir, null);
            uv.uv_fs_req_cleanup(&request);
        }
        for (self.entries.items) |entry| engine.gpa.free(entry);
        self.entries.deinit(engine.gpa);
        engine.gpa.free(self.path);
        if (self.destination) |destination| engine.gpa.free(destination);
        self.result.deinit(engine.gpa);
        engine.freeValue(self.bindings);
        task.releaseFunctions();
        engine.gpa.destroy(self);
    }
};
fn submit(engine: *js.Engine, args: []const c.JSValue, bindings: c.JSValue, method: Method) !c.JSValue {
    var scope: h.Scope = .{ .engine = engine };
    defer scope.deinit();
    const input_path = try engine.toString(h.arg(args, 0));
    defer engine.gpa.free(input_path);
    if (std.mem.indexOfScalar(u8, input_path, 0) != null) return error.InvalidNativeNodePathValue;
    const path = try engine.gpa.dupeZ(u8, input_path);
    var path_transferred = false;
    defer if (!path_transferred) engine.gpa.free(path);
    const hub = try owner.get(engine);
    var functions: [2]c.JSValue = undefined;
    const new_promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    var transferred = false;
    errdefer if (!transferred) {
        engine.freeValue(functions[0]);
        engine.freeValue(functions[1]);
    };
    const promise = try scope.own(new_promise);
    const job = try engine.gpa.create(Job);
    job.* = .{ .task = .{ .hub = hub, .work = Job.run, .complete = Job.complete, .destroy = Job.destroy, .cancel = Job.cancel, .resolve = functions[0], .reject = functions[1] }, .method = method, .bindings = c.JS_DupValue(engine.context, bindings), .path = path, .phase = switch (method) {
        .open => "open",
        .lstat, .rm => "lstat",
        .mkdir => "mkdir",
        .rename => "rename",
        .realpath => "realpath",
        .readdir => "scandir",
        .opendir => "opendir",
        .mkdtemp => "mkdtemp",
        else => unreachable,
    } };
    transferred = true;
    path_transferred = true;
    errdefer Job.destroy(&job.task);
    switch (method) {
        .open => {
            const mode = h.arg(args, 1);
            if (scope.equal(mode, try scope.text("r+"))) job.flags = uv.UV_FS_O_RDWR else if (scope.equal(mode, try scope.text("w"))) job.flags = uv.UV_FS_O_WRONLY | uv.UV_FS_O_CREAT | uv.UV_FS_O_TRUNC else if (scope.equal(mode, try scope.text("a"))) job.flags = uv.UV_FS_O_WRONLY | uv.UV_FS_O_CREAT | uv.UV_FS_O_APPEND else if (!scope.equal(mode, try scope.text("r")) and !scope.equal(mode, c.JS_NewInt32(engine.context, 0))) return error.UnsupportedNativeNodeOpenMode;
            if (c.JS_IsNumber(mode) and builtin.os.tag != .windows) job.flags |= uv.UV_FS_O_NONBLOCK;
            if (scope.equal(try h.optional(&scope, h.arg(args, 2), "noFollow"), c.pi_js_bool(engine.context, 1))) job.flags |= uv.UV_FS_O_NOFOLLOW;
        },
        .rm => {
            job.recursive = scope.truthy(try h.optional(&scope, h.arg(args, 1), "recursive"));
            job.force = scope.truthy(try h.optional(&scope, h.arg(args, 1), "force"));
        },
        .mkdir => job.recursive = scope.truthy(try h.optional(&scope, h.arg(args, 1), "recursive")),
        .rename => {
            const destination = try engine.toString(h.arg(args, 1));
            defer engine.gpa.free(destination);
            job.destination = try engine.gpa.dupeZ(u8, destination);
        },
        else => {},
    }
    try hub.submit(&job.task);
    return c.JS_DupValue(engine.context, promise);
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const args = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    const method: Method = @enumFromInt(raw);
    return (if (method == .readFile or method == .writeFile or method == .appendFile) @import("native_env_node_fs_contents.zig").invoke(engine, data[0], args, method != .readFile, method == .appendFile) else submit(engine, args, data[0], method)) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
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
