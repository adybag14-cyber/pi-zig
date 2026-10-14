//! A retained native directory cursor. Enumeration never enters QuickJS from a worker.
const std = @import("std");
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const owner = @import("native_env_io.zig");
const errors = @import("native_env_node_errors.zig");
const c = js.c;
const uv = @import("native_uv_api").c;
const State = struct {
    engine: *js.Engine,
    dir: ?*uv.uv_dir_t,
    mutex: std.Io.Mutex = .init,
    closed: bool = false,
};
fn state(engine: *js.Engine, receiver: c.JSValue) !*State {
    const raw = c.JS_GetOpaque2(engine.context, receiver, engine.native_env_node_dir_class) orelse return js.capture(engine);
    return @ptrCast(@alignCast(raw));
}
fn finalize(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    if (self.dir) |dir| closeNative(dir);
    self.engine.gpa.destroy(self);
}
fn closedError(scope: *h.Scope) !c.JSValue {
    const result = try scope.own(try js.builtin(scope.engine, "Error", &.{try scope.text("Directory handle was closed")}));
    try scope.put(result, "code", try scope.text("ERR_DIR_CLOSED"));
    return result;
}
const Job = struct {
    task: owner.Task,
    self: *State,
    receiver: c.JSValue,
    close: bool,
    entry: ?[]u8 = null,
    failure: ?anyerror = null,
    native_status: c_int = 0,
    fn run(task: *owner.Task) void {
        const self: *Job = @alignCast(@fieldParentPtr("task", task));
        self.execute() catch |err| {
            self.failure = err;
        };
        task.finish();
    }
    fn execute(self: *Job) !void {
        const io = self.task.hub.io;
        try self.self.mutex.lock(io);
        defer self.self.mutex.unlock(io);
        const dir = self.self.dir orelse return error.NativeDirectoryClosed;
        var request: uv.uv_fs_t = undefined;
        defer uv.uv_fs_req_cleanup(&request);
        if (self.close) {
            self.native_status = uv.uv_fs_closedir(null, &request, dir, null);
            self.self.dir = null;
        } else {
            var entry: uv.uv_dirent_t = undefined;
            dir.dirents = &entry;
            dir.nentries = 1;
            const result = uv.uv_fs_readdir(null, &request, dir, null);
            if (result < 0) self.native_status = result else if (result != 0) self.entry = try self.self.engine.gpa.dupe(u8, std.mem.span(entry.name));
        }
    }
    fn cancel(_: *owner.Task) void {}
    fn complete(task: *owner.Task) anyerror!void {
        const self: *Job = @alignCast(@fieldParentPtr("task", task));
        var scope: h.Scope = .{ .engine = self.self.engine };
        defer scope.deinit();
        if (self.native_status < 0) return task.settled(true, try errors.systemError(&scope, .{ .code = std.mem.span(uv.uv_err_name(self.native_status)), .description = std.mem.span(uv.uv_strerror(self.native_status)), .errno = self.native_status, .syscall = if (self.close) "closedir" else "readdir" }));
        if (self.failure) |failure| {
            if (failure == error.OutOfMemory) return failure;
            if (failure == error.NativeDirectoryClosed) return task.settled(true, try closedError(&scope));
            return failure;
        }
        const value = if (self.entry) |name| entry: {
            const result = try scope.object();
            try scope.put(result, "name", try scope.text(name));
            break :entry result;
        } else if (self.close) c.pi_js_undefined() else c.pi_js_null();
        try task.settled(false, value);
    }
    fn destroy(task: *owner.Task) void {
        const self: *Job = @alignCast(@fieldParentPtr("task", task));
        const engine = self.self.engine;
        if (self.entry) |entry| engine.gpa.free(entry);
        engine.freeValue(self.receiver);
        task.releaseFunctions();
        engine.gpa.destroy(self);
    }
};
fn invoke(engine: *js.Engine, receiver: c.JSValue, close: bool) !c.JSValue {
    const self = try state(engine, receiver);
    var scope: h.Scope = .{ .engine = engine };
    defer scope.deinit();
    if (self.closed) return h.throw(&scope, try closedError(&scope));
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
    job.* = .{ .task = .{ .hub = hub, .work = Job.run, .complete = Job.complete, .cancel = Job.cancel, .destroy = Job.destroy, .resolve = functions[0], .reject = functions[1] }, .self = self, .receiver = c.JS_DupValue(engine.context, receiver), .close = close };
    transferred = true;
    errdefer Job.destroy(&job.task);
    try hub.submit(&job.task);
    if (close) self.closed = true;
    return c.JS_DupValue(engine.context, promise);
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue, close: c_int) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return invoke(engine, receiver, close != 0) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
pub fn create(scope: *h.Scope, dir: *uv.uv_dir_t, path: []const u8) !c.JSValue {
    const engine = scope.engine;
    var transferred = false;
    defer if (!transferred) closeNative(dir);
    if (engine.native_env_node_dir_class == 0) {
        _ = c.JS_NewClassID(engine.runtime, &engine.native_env_node_dir_class);
        const definition: c.JSClassDef = .{ .class_name = "Dir", .finalizer = finalize };
        if (c.JS_NewClass(engine.runtime, engine.native_env_node_dir_class, &definition) < 0) return error.OutOfMemory;
    }
    const prototype = try scope.object();
    const value = try scope.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, prototype, engine.native_env_node_dir_class)));
    const self = try engine.gpa.create(State);
    self.* = .{ .engine = engine, .dir = dir };
    _ = c.JS_SetOpaque(value, self);
    transferred = true;
    try scope.put(value, "path", try scope.text(path));
    inline for (.{ "read", "close" }, 0..) |name, index| {
        const function = try scope.own(try engine.checked(c.JS_NewCFunctionMagic(engine.context, dispatch, name, 0, c.JS_CFUNC_generic_magic, @intCast(index))));
        try scope.put(prototype, name, function);
    }
    return c.JS_DupValue(engine.context, value);
}

fn closeNative(dir: *uv.uv_dir_t) void {
    var request: uv.uv_fs_t = undefined;
    _ = uv.uv_fs_closedir(null, &request, dir, null);
    uv.uv_fs_req_cleanup(&request);
}
