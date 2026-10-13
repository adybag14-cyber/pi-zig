//! Native FileHandle operations used by the Node readers. Workers never enter the VM.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const errors = @import("native_env_node_errors.zig");
const owner = @import("native_env_io.zig");
const c = js.c;
const Method = enum(c_int) { read, stat, truncate, sync, close };
const Native = struct {
    extern "c" fn _open_osfhandle(isize, c_int) c_int;
    extern "c" fn _close(c_int) c_int;
};
const State = struct {
    engine: *js.Engine,
    file: ?std.Io.File,
    fd: isize,
    writable: bool,
    bindings: c.JSValue,
    close_promise: c.JSValue,
    closing: bool = false,
    closed: std.atomic.Value(bool) = .init(false),
    mutex: std.Io.Mutex = .init,
    active: std.atomic.Value(u32) = .init(0),
    epoch: std.atomic.Value(u32) = .init(0),
    fn closeNative(self: *State) void {
        const file = self.file orelse return;
        if (builtin.os.tag == .windows) {
            _ = Native._close(@intCast(self.fd));
        } else file.close(self.engine.native_io.?);
        self.file = null;
    }
};
fn state(engine: *js.Engine, receiver: c.JSValue) !*State {
    const result = c.JS_GetOpaque2(engine.context, receiver, engine.native_env_node_file_class) orelse return js.capture(engine);
    return @ptrCast(@alignCast(result));
}
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    // Every pending task roots its receiver. Hub teardown joins workers before releasing those roots.
    self.closeNative();
    c.JS_FreeValueRT(runtime, self.bindings);
    c.JS_FreeValueRT(runtime, self.close_promise);
    self.engine.gpa.destroy(self);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visitor: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, self.bindings, visitor);
    c.JS_MarkValue(runtime, self.close_promise, visitor);
}
fn syscall(method: Method) []const u8 {
    return switch (method) {
        .read => "read",
        .stat => "fstat",
        .truncate => "ftruncate",
        .sync => "fsync",
        .close => "close",
    };
}
fn closedError(scope: *h.Scope, method: Method) !c.JSValue {
    const result = try scope.own(try js.builtin(scope.engine, "Error", &.{try scope.text("file closed")}));
    try scope.put(result, "code", try scope.text("EBADF"));
    try scope.put(result, "syscall", try scope.text(syscall(method)));
    return result;
}
fn systemFailure(scope: *h.Scope, method: Method, failure: anyerror) !c.JSValue {
    const windows = builtin.os.tag == .windows;
    const fields: errors.SystemFailure = switch (failure) {
        error.FileNotFound => .{ .code = "ENOENT", .description = "no such file or directory", .errno = if (windows) -4058 else -2, .syscall = syscall(method) },
        error.IsDir => .{ .code = "EISDIR", .description = "illegal operation on a directory", .errno = if (windows) -4068 else -21, .syscall = syscall(method) },
        error.PermissionDenied => .{ .code = "EPERM", .description = "operation not permitted", .errno = if (windows) -4048 else -1, .syscall = syscall(method) },
        error.AccessDenied => .{ .code = "EACCES", .description = "permission denied", .errno = if (windows) -4092 else -13, .syscall = syscall(method) },
        error.InvalidArgument => .{ .code = "EINVAL", .description = "invalid argument", .errno = if (windows) -4071 else -22, .syscall = syscall(method) },
        else => return error.UnclassifiedNativeNodeFileFailure,
    };
    return errors.systemError(scope, fields);
}
pub fn statsValue(scope: *h.Scope, info: std.Io.File.Stat) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "size", c.JS_NewFloat64(scope.engine.context, @floatFromInt(info.size)));
    try scope.put(result, "mtimeMs", c.JS_NewFloat64(scope.engine.context, @as(f64, @floatFromInt(info.mtime.nanoseconds)) / std.time.ns_per_ms));
    var data = [_]c.JSValue{c.JS_NewInt32(scope.engine.context, @intFromEnum(info.kind))};
    inline for (.{ .{ "isFile", std.Io.File.Kind.file }, .{ "isDirectory", std.Io.File.Kind.directory }, .{ "isSymbolicLink", std.Io.File.Kind.sym_link } }) |entry| {
        const function = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, statKind, entry[0], 0, @intFromEnum(entry[1]), 1, &data)));
        try scope.put(result, entry[0], function);
    }
    return result;
}
fn statKind(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, expected: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    var actual: i32 = undefined;
    if (c.JS_ToInt32(context, &actual, data[0]) < 0) return c.JS_Throw(context, c.JS_GetException(context));
    return c.pi_js_bool(context, @intFromBool(actual == expected));
}
const Job = struct {
    task: owner.Task,
    self: *State,
    receiver: c.JSValue,
    target: c.JSValue,
    method: Method,
    bytes: []u8 = &.{},
    count: usize = 0,
    from: usize = 0,
    position: ?u64 = null,
    size: u64 = 0,
    stat: ?std.Io.File.Stat = null,
    failure: ?anyerror = null,
    aborted: std.atomic.Value(bool) = .init(false),
    has_reference: bool = false,
    fn run(task: *owner.Task) void {
        const self: *Job = @alignCast(@fieldParentPtr("task", task));
        self.execute() catch |err| {
            self.failure = err;
        };
        task.finish();
    }
    fn releaseReference(self: *Job) void {
        if (!self.has_reference) return;
        self.has_reference = false;
        const before = self.self.active.fetchSub(1, .release);
        if (before == 1 and self.self.closing) self.self.closed.store(true, .release);
        _ = self.self.epoch.fetchAdd(1, .release);
        self.task.hub.io.futexWake(u32, &self.self.epoch.raw, std.math.maxInt(u32));
    }
    fn execute(self: *Job) !void {
        const io = self.task.hub.io;
        if (self.method == .close) while (true) {
            const observed = self.self.epoch.load(.acquire);
            if (self.self.active.load(.acquire) == 0) break;
            try io.futexWait(u32, &self.self.epoch.raw, observed);
        };
        if (self.aborted.load(.acquire)) return error.Canceled;
        try self.self.mutex.lock(io);
        defer self.self.mutex.unlock(io);
        const file = self.self.file orelse return error.NativeFileClosed;
        switch (self.method) {
            .close => self.self.closeNative(),
            .stat => self.stat = try file.stat(io),
            .truncate, .sync => {
                if (builtin.os.tag == .windows and !self.self.writable) return error.PermissionDenied;
                if (self.method == .truncate) try file.setLength(io, self.size) else try file.sync(io);
            },
            .read => {
                if ((try file.stat(io)).kind == .directory) return error.IsDir;
                var slices = [_][]u8{self.bytes};
                self.count = if (self.position) |at| try file.readPositional(io, &slices, at) else try file.readStreaming(io, &slices);
            },
        }
    }
    fn cancel(task: *owner.Task) void {
        const self: *Job = @alignCast(@fieldParentPtr("task", task));
        self.aborted.store(true, .release);
    }
    fn complete(task: *owner.Task) anyerror!void {
        const self: *Job = @alignCast(@fieldParentPtr("task", task));
        const engine = self.self.engine;
        var scope: h.Scope = .{ .engine = engine };
        defer scope.deinit();
        defer self.releaseReference();
        if (self.failure) |failure| {
            if (failure == error.OutOfMemory) return failure;
            const reason = if (failure == error.NativeFileClosed) try closedError(&scope, self.method) else try systemFailure(&scope, self.method, failure);
            self.releaseReference();
            return task.settled(true, reason);
        }
        const result = switch (self.method) {
            .stat => try statsValue(&scope, self.stat.?),
            .read => read: {
                var offset: usize = undefined;
                var length: usize = undefined;
                var element: usize = undefined;
                const backing = try scope.own(try engine.checked(c.JS_GetTypedArrayBuffer(engine.context, self.target, &offset, &length, &element)));
                var total: usize = undefined;
                const data = c.JS_GetArrayBuffer(engine.context, &total, backing);
                if ((data == null and self.count != 0) or offset > total or length > total - offset or self.from > length or self.count > length - self.from) return error.NativeReadDestinationDetached;
                if (self.count != 0) @memcpy(data[offset + self.from ..][0..self.count], self.bytes[0..self.count]);
                const object = try scope.object();
                try scope.put(object, "bytesRead", c.JS_NewFloat64(engine.context, @floatFromInt(self.count)));
                try scope.put(object, "buffer", self.target);
                break :read object;
            },
            else => c.pi_js_undefined(),
        };
        self.releaseReference();
        try task.settled(false, result);
    }
    fn destroy(task: *owner.Task) void {
        const self: *Job = @alignCast(@fieldParentPtr("task", task));
        const engine = self.self.engine;
        self.releaseReference();
        engine.gpa.free(self.bytes);
        engine.freeValue(self.target);
        engine.freeValue(self.receiver);
        task.releaseFunctions();
        engine.gpa.destroy(self);
    }
};
fn number(engine: *js.Engine, value: c.JSValue) !f64 {
    var result: f64 = undefined;
    if (c.JS_ToFloat64(engine.context, &result, value) < 0) return js.capture(engine);
    return result;
}
fn invoke(engine: *js.Engine, receiver: c.JSValue, args: []const c.JSValue, method: Method) !c.JSValue {
    const self = try state(engine, receiver);
    var scope: h.Scope = .{ .engine = engine };
    defer scope.deinit();
    if (self.closed.load(.acquire)) {
        if (method == .close) return c.JS_DupValue(engine.context, self.close_promise);
        return h.throw(&scope, try closedError(&scope, method));
    }
    if (method == .close and self.closing) return c.JS_DupValue(engine.context, self.close_promise);
    var functions: [2]c.JSValue = undefined;
    const promise = try scope.own(try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions)));
    var transferred = false;
    errdefer if (!transferred) {
        engine.freeValue(functions[0]);
        engine.freeValue(functions[1]);
    };
    const hub = try owner.get(engine);
    const job = try engine.gpa.create(Job);
    job.* = .{ .task = .{ .hub = hub, .work = Job.run, .complete = Job.complete, .destroy = Job.destroy, .cancel = Job.cancel, .resolve = functions[0], .reject = functions[1] }, .self = self, .receiver = c.JS_DupValue(engine.context, receiver), .target = c.pi_js_undefined(), .method = method };
    transferred = true;
    errdefer Job.destroy(&job.task);
    if (method == .read) {
        const target = h.arg(args, 0);
        var offset: usize = undefined;
        var length: usize = undefined;
        var element: usize = undefined;
        const backing = try scope.own(try engine.checked(c.JS_GetTypedArrayBuffer(engine.context, target, &offset, &length, &element)));
        _ = backing;
        const from = try number(engine, h.arg(args, 1));
        const count = try number(engine, h.arg(args, 2));
        if (!std.math.isFinite(from) or from < 0 or from > @as(f64, @floatFromInt(length)) or @trunc(from) != from or !std.math.isFinite(count) or count < 0 or count > @as(f64, @floatFromInt(length)) - from or @trunc(count) != count) return error.InvalidNativeReadRange;
        job.from = @intFromFloat(from);
        job.bytes = try engine.gpa.alloc(u8, @intFromFloat(count));
        job.target = c.JS_DupValue(engine.context, target);
        const position = h.arg(args, 3);
        if (!h.nullish(position)) {
            const at = try number(engine, position);
            if (std.math.isFinite(at) and at >= 0 and at <= 9007199254740991 and @trunc(at) == at) job.position = @intFromFloat(at);
        }
    } else if (method == .truncate) job.size = @intFromFloat(try number(engine, h.arg(args, 0)));
    if (method == .close) {
        self.closing = true;
        if (self.active.load(.acquire) == 0) self.closed.store(true, .release);
    } else {
        _ = self.active.fetchAdd(1, .release);
        job.has_reference = true;
    }
    job.task.hub.submit(&job.task) catch |err| {
        if (method == .close) {
            self.closing = false;
            self.closed.store(false, .release);
        }
        return err;
    };
    if (method == .close) self.close_promise = c.JS_DupValue(engine.context, promise);
    return c.JS_DupValue(engine.context, promise);
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(raw)) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn fdValue(context: ?*c.JSContext, receiver: c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const self = state(engine, receiver) catch |err| return @import("native_durable.zig").reject(engine, err);
    return c.JS_NewInt64(engine.context, if (self.closed.load(.acquire)) -1 else self.fd);
}
pub fn create(scope: *h.Scope, file: std.Io.File, writable: bool, bindings: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    // This function consumes the native file on every outcome.
    var transferred = false;
    defer if (!transferred) file.close(engine.native_io.?);
    if (engine.native_env_node_file_class == 0) {
        _ = c.JS_NewClassID(engine.runtime, &engine.native_env_node_file_class);
        const definition: c.JSClassDef = .{ .class_name = "FileHandle", .finalizer = finalize, .gc_mark = mark };
        if (c.JS_NewClass(engine.runtime, engine.native_env_node_file_class, &definition) < 0) return error.OutOfMemory;
    }
    const prototype = try scope.object();
    const value = try scope.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, prototype, engine.native_env_node_file_class)));
    const self = try engine.gpa.create(State);
    errdefer if (!transferred) engine.gpa.destroy(self);
    const fd: isize = if (builtin.os.tag == .windows) Native._open_osfhandle(@intCast(@intFromPtr(file.handle)), 0x8000 | @as(c_int, if (writable) 2 else 0)) else file.handle;
    if (fd < 0) return error.NativeFileDescriptorAdmissionFailed;
    self.* = .{ .engine = engine, .file = file, .fd = fd, .writable = writable, .bindings = c.JS_DupValue(engine.context, bindings), .close_promise = c.pi_js_undefined() };
    _ = c.JS_SetOpaque(value, self);
    transferred = true;
    const atom = c.JS_NewAtom(engine.context, "fd");
    defer c.JS_FreeAtom(engine.context, atom);
    const getter = try engine.checked(c.JS_NewCFunction2(engine.context, @ptrCast(&fdValue), "get fd", 0, c.JS_CFUNC_getter, 0));
    if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    inline for (std.meta.fields(Method)) |field| {
        const function = try engine.checked(c.JS_NewCFunctionMagic(engine.context, dispatch, field.name, if (field.value == @intFromEnum(Method.read)) 4 else if (field.value == @intFromEnum(Method.truncate)) 1 else 0, c.JS_CFUNC_generic_magic, @intCast(field.value)));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    return c.JS_DupValue(engine.context, value);
}
