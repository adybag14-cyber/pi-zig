//! Callback filesystem operations required by the real WriteStream producer.
//! Native packets run in existing Env IO workers; JS callbacks run once on the
//! VM owner after actual IO, with completed handles published before callbacks.
const std = @import("std");
const em = @import("engine.zig");
const c = em.c;
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const fnc = @import("native_node_function.zig");
const hub_mod = @import("native_env_io.zig");
const raw = @import("native_node_fs_write_io.zig");
const completion = @import("native_sdk_owned_completion.zig");
const wake = @import("native_owner_wake.zig");
const completion_wake = @import("native_owner_completion.zig");
const buffer = @import("native_node_string_decoder.zig");
const core = @import("native_node_stream.zig");
const key = "pi-native:node-write-filesystem-operations";
const Method = enum(c_int) { open, write, writev, fsync, close };
const Registry = struct {
    engine: *em.Engine,
    class_id: c.JSClassID,
    references: usize = 1, // private captured holder; tasks/files retain native ownership
    files: std.ArrayList(*OwnedFile) = .empty,
    fn retain(self: *Registry) void { self.references += 1; }
    fn release(self: *Registry) void {
        self.references -= 1;
        if (self.references != 0) return;
        std.debug.assert(self.files.items.len == 0);
        self.files.deinit(self.engine.gpa); self.engine.gpa.destroy(self);
    }
};
const OwnedFile = struct {
    registry: *Registry,
    hub: *hub_mod.Hub,
    file: ?raw.File,
    descriptor: u64,
    append: bool,
    references: usize = 2, // registry plus hub shutdown resource
    closing: bool = false,
    fn retain(self: *OwnedFile) void { self.references += 1; }
    fn release(self: *OwnedFile) void { self.references -= 1; if (self.references == 0) { const owner = self.registry; owner.engine.gpa.destroy(self); owner.release(); } }
    fn detachRegistry(self: *OwnedFile) void {
        for (self.registry.files.items, 0..) |file, i| if (file == self) { _ = self.registry.files.orderedRemove(i); self.release(); return; };
    }
    fn stop(pointer: *anyopaque) void { const self: *OwnedFile = @ptrCast(@alignCast(pointer)); self.closing = true; }
    fn stopped(pointer: *anyopaque) void {
        const self: *OwnedFile = @ptrCast(@alignCast(pointer));
        // Env Hub calls this only after all task workers have returned.
        if (self.file) |file| { self.file = null; file.close(self.hub.io); }
        self.detachRegistry(); self.release();
    }
    fn closed(self: *OwnedFile) void {
        self.hub.removeResource(self); self.detachRegistry(); self.release();
    }
};
fn registryFinalize(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const self: *Registry = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    self.release();
}
fn registry(scope: *Scope, holder: c.JSValue, expected: c.JSValue) !*Registry {
    // Both inputs are immutable native function captures. No guest-visible
    // module property participates in either brand selection or lifetime.
    var id: u32 = 0; if (c.JS_ToUint32(scope.engine.context, &id, expected) < 0) return js.capture(scope.engine);
    if (c.JS_GetClassID(holder) != id) return error.NativeFileRegistryRequired;
    const value: *Registry = @ptrCast(@alignCast(c.JS_GetOpaque(holder, id) orelse return error.NativeFileRegistryRequired));
    if (value.class_id != id or value.engine != scope.engine) return error.NativeFileRegistryRequired;
    return value;
}
fn descriptor(scope: *Scope, value: c.JSValue) !u64 {
    var number: f64 = 0; if (!c.JS_IsNumber(value) or c.JS_ToFloat64(scope.engine.context, &number, value) < 0 or !std.math.isFinite(number) or number < 0 or number != @floor(number) or number > 9007199254740991) return @import("node_events.zig").codedError(scope.engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The \"fd\" argument must be a native file descriptor");
    return @intFromFloat(number);
}
fn find(self: *Registry, fd: u64) ?*OwnedFile { for (self.files.items) |file| if (file.descriptor == fd and !file.closing) return file; return null; }
fn failure(scope: *Scope, err: anyerror, syscall: []const u8, path: c.JSValue) !c.JSValue {
    if (err == error.OutOfMemory) return err;
    const code: []const u8 = switch (err) { error.FileNotFound => "ENOENT", error.AccessDenied => "EACCES", error.PermissionDenied => "EPERM", error.PathAlreadyExists => "EEXIST", error.IsDir => "EISDIR", error.NotDir => "ENOTDIR", error.NoSpaceLeft => "ENOSPC", error.FileTooBig => "EFBIG", error.ReadOnlyFileSystem => "EROFS", error.BadFileDescriptor => "EBADF", error.WouldBlock => "EAGAIN", error.Canceled => "ECANCELED", else => "EIO" };
    const reason = try scope.own(try core.errorValue(scope, "Error", code, @errorName(err))); try scope.set(reason, "syscall", try scope.text(syscall));
    if (!core.nullish(path)) try scope.set(reason, "path", path);
    return c.JS_DupValue(scope.engine.context, reason);
}
const Task = struct {
    task: hub_mod.Task,
    registry: *Registry,
    method: Method,
    packet: raw.Packet,
    native_path: [:0]u8,
    reference: wake.Ref,
    retirement_error: ?anyerror = null,
    native_bytes: []u8,
    path: c.JSValue,
    returned_buffer: c.JSValue,
    file: ?*OwnedFile = null,
    fn work(base: *hub_mod.Task) void {
        const self: *Task = @fieldParentPtr("task", base);
        const reference = self.reference;
        self.packet.run();
        base.done.store(true, .release);
        // Owner completion may destroy the packet after done becomes visible.
        // This copied generation token does not dereference that packet.
        wake.notify(reference);
    }
    fn cancel(base: *hub_mod.Task) void {
        const self: *Task = @fieldParentPtr("task", base);
        self.packet.cancel();
    }
    fn destroy(base: *hub_mod.Task) void {
        const self: *Task = @fieldParentPtr("task", base); const engine = base.hub.engine;
        const incoming: anyerror!void = if (self.retirement_error) |err| err
            else if (self.packet.failure == error.OutOfMemory) error.OutOfMemory else {};
        var retiring = completion.Completion.initVoid(engine, incoming);
        // Hub joins real workers before abandoned packet destruction.
        self.packet.retireUnadopted(); if (self.file) |file| file.release();
        const path = self.path; self.path = c.pi_js_undefined();
        const returned_buffer = self.returned_buffer; self.returned_buffer = c.pi_js_undefined();
        const resolve = base.resolve; base.resolve = c.pi_js_undefined();
        const reject = base.reject; base.reject = c.pi_js_undefined();
        retiring.release(path); retiring.release(returned_buffer);
        retiring.release(resolve); retiring.release(reject);
        const owner = self.registry;
        const memory_owner = self.packet.memory_owner;
        wake.release(self.reference);
        engine.gpa.free(self.native_path); engine.gpa.free(self.native_bytes);
        engine.gpa.destroy(self); owner.release();
        c.pi_js_release_memory_owner(memory_owner);
        retiring.finishVoid() catch {};
    }
    fn complete(base: *hub_mod.Task) !void {
        const self: *Task = @fieldParentPtr("task", base);
        var scope: Scope = .{ .engine = base.hub.engine };
        return completion.finishVoid(&scope, self.completeBody(&scope));
    }
    fn completeBody(self: *Task, scope: *Scope) !void {
        const base = &self.task; const engine = base.hub.engine;
        try base.hub.assertOwner();
        try engine.checkNativeEntry();
        if (self.packet.failure == error.OutOfMemory) return error.OutOfMemory;
        self.packet.publishClose();
        var fd: u64 = 0;
        if (self.packet.opened) |file| {
            // Complete every fallible owner allocation before transferring the
            // opened file out of the packet's abandonment rollback.
            try self.registry.files.ensureUnusedCapacity(engine.gpa, 1);
            const owned = try engine.gpa.create(OwnedFile); errdefer engine.gpa.destroy(owned);
            owned.* = .{ .registry = self.registry, .hub = base.hub, .file = file, .descriptor = try raw.descriptor(file), .append = self.packet.append };
            try base.hub.addResource(.{ .raw = owned, .stop = OwnedFile.stop, .stopped = OwnedFile.stopped });
            self.registry.retain(); // survives holder collection until resource/task retirement
            self.registry.files.appendAssumeCapacity(owned); self.packet.opened = null; fd = owned.descriptor;
        }
        if (self.method == .close) if (self.file) |file| file.closed();
        const reason = if (self.packet.failure) |err|
            try completion.ownRoot(scope, try failure(scope, err, @tagName(self.method), self.path))
        else if (self.packet.uv_status < 0)
            try completion.ownRoot(scope, try @import("native_node_uv_exception.zig").create(engine, .{
                .code = self.packet.uv_status, .syscall = if (self.method == .writev) "write" else @tagName(self.method),
                .path = if (self.method == .open) self.native_path else null,
            }))
        else c.pi_js_null();
        // Consume the task-owned callback before entering guest code. Existing
        // Hub orderedRemove/defer destroy guarantees exactly one retirement,
        // including a thrown callback. There is no second rejection replay.
        const callback = try completion.ownRoot(scope, c.JS_DupValue(engine.context, base.resolve)); engine.freeValue(base.resolve); base.resolve = c.pi_js_undefined();
        const args: []const c.JSValue = switch (self.method) {
            .open => if (core.nullish(reason)) &.{ reason, c.JS_NewInt64(engine.context, @intCast(fd)) } else &.{reason},
            .write, .writev => &.{ reason, c.JS_NewInt64(engine.context, @intCast(self.packet.transferred)), self.returned_buffer },
            .fsync, .close => &.{reason},
        };
        _ = try scope.call(callback, c.pi_js_undefined(), args);
    }
};
fn makeTask(scope: *Scope, selected_registry: *Registry, method: Method, callback: c.JSValue) !*Task {
    if (!c.JS_IsFunction(scope.engine.context, callback)) return @as(anyerror!*Task, @import("node_events.zig").codedError(scope.engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The \"callback\" argument must be of type function"));
    const hub = try hub_mod.get(scope.engine);
    try hub.assertOwner();
    const reference = try completion_wake.acquireNativeWake(scope.engine);
    errdefer wake.release(reference);
    const self = try scope.engine.gpa.create(Task); errdefer scope.engine.gpa.destroy(self);
    const path = try scope.engine.gpa.dupeZ(u8, ""); errdefer scope.engine.gpa.free(path); const bytes = try scope.engine.gpa.alloc(u8, 0); errdefer scope.engine.gpa.free(bytes);
    c.pi_js_retain_memory_owner(scope.engine.native_memory_owner);
    self.* = .{ .reference = reference, .task = .{ .hub = hub, .work = Task.work, .complete = Task.complete, .destroy = Task.destroy, .cancel = Task.cancel, .resolve = c.JS_DupValue(scope.engine.context, callback), .reject = c.pi_js_undefined(), .propagate_completion_errors = true }, .registry = selected_registry, .method = method, .packet = .{ .io = hub.io, .memory_owner = scope.engine.native_memory_owner, .operation = switch (method) { .open => .open, .write, .writev => .write, .fsync => .sync, .close => .close } }, .native_path = path, .native_bytes = bytes, .path = c.pi_js_undefined(), .returned_buffer = c.pi_js_undefined() };
    selected_registry.retain(); return self;
}
fn nativePath(scope: *Scope, path: c.JSValue) ![]u8 {
    const url = @import("native_url.zig");
    if (url.isURL(scope.engine, path)) return url.filePath(scope.engine, path, @import("builtin").os.tag == .windows);
    if (c.JS_IsString(path)) return scope.engine.toString(path);
    const bytes = try buffer.bytes(scope, path); return scope.engine.gpa.dupe(u8, bytes);
}
fn dispatch(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    return completion.finishValue(&scope, dispatchBody(&scope, args, roots));
}
fn dispatchBody(scope: *Scope, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const engine = scope.engine;
    try engine.checkNativeEntry();
    var integer: i32 = 0; if (c.JS_ToInt32(engine.context, &integer, roots[1]) < 0) return @as(anyerror!c.JSValue, js.capture(engine)); const method: Method = @enumFromInt(integer);
    const callback = core.arg(args, switch (method) { .open => 3, .write => 5, .writev => 3, .fsync, .close => 1 });
    const task = try makeTask(scope, try registry(scope, roots[0], roots[2]), method, callback); var submitted = false; defer if (!submitted) Task.destroy(&task.task);
    errdefer |err| task.retirement_error = err;
    if (method == .open) {
        const path = core.arg(args, 0);
        const name = try nativePath(scope, path); defer engine.gpa.free(name);
        const terminated = try engine.gpa.dupeZ(u8, name);
        engine.gpa.free(task.native_path); task.native_path = terminated;
        if (std.mem.indexOfScalar(u8, name, 0) != null) return @as(anyerror!c.JSValue, @import("node_events.zig").codedError(engine, "TypeError", "ERR_INVALID_ARG_VALUE", "The argument 'path' must not contain null bytes"));
        task.path = c.JS_DupValue(engine.context, path); task.packet.path = terminated; task.packet.windows_path = terminated;
        const flags = try engine.toString(core.arg(args, 1)); defer engine.gpa.free(flags);
        if (std.mem.eql(u8, flags, "w") or std.mem.eql(u8, flags, "wx")) task.packet.create_options.exclusive = std.mem.eql(u8, flags, "wx")
        else if (std.mem.eql(u8, flags, "a") or std.mem.eql(u8, flags, "ax")) { task.packet.append = true; task.packet.create_options.truncate = false; task.packet.create_options.exclusive = std.mem.eql(u8, flags, "ax"); }
        else return @as(anyerror!c.JSValue, @import("node_events.zig").codedError(engine, "TypeError", "ERR_INVALID_ARG_VALUE", "Unsupported native WriteStream file flag"));
        var mode: u32 = 0; if (c.JS_ToUint32(engine.context, &mode, core.arg(args, 2)) < 0) return @as(anyerror!c.JSValue, js.capture(engine));
        task.packet.mode = mode;
        task.packet.create_options.permissions = if (@import("builtin").os.tag == .windows) std.Io.File.Permissions.default_file.setReadOnly(mode & 0o222 == 0) else .fromMode(@intCast(mode));
    } else {
        const fd = try descriptor(scope, core.arg(args, 0)); const owned = find(task.registry, fd);
        if (@import("builtin").os.tag == .windows and fd <= std.math.maxInt(c_int)) task.packet.descriptor_value = @intCast(fd);
        if (owned) |file| { file.retain(); task.file = file; task.packet.file = if (method == .close) file.file else if (file.file) |selected| raw.retainFile(selected) else null; task.packet.append = file.append; } else task.packet.failure = error.BadFileDescriptor;
        if (method == .write or method == .writev) {
            const source = core.arg(args, 1); var data: std.ArrayList(u8) = .empty; defer data.deinit(engine.gpa);
            if (method == .write) {
                var offset: u64 = 0; var length: u64 = 0;
                if (c.JS_ToIndex(engine.context, &offset, core.arg(args, 2)) < 0 or c.JS_ToIndex(engine.context, &length, core.arg(args, 3)) < 0) return @as(anyerror!c.JSValue, js.capture(engine));
                // Complete every potentially guest-authored coercion before
                // borrowing a typed view; no detach hook runs before copy.
                const input = try buffer.bytes(scope, source);
                if (offset > input.len or length > input.len - offset) return @as(anyerror!c.JSValue, @import("node_events.zig").codedError(engine, "RangeError", "ERR_OUT_OF_RANGE", "The write offset or length is out of range"));
                try data.appendSlice(engine.gpa, input[@intCast(offset)..][0..@intCast(length)]);
            } else {
                var length: u64 = 0; if (c.JS_ToIndex(engine.context, &length, try scope.get(source, "length")) < 0) return @as(anyerror!c.JSValue, js.capture(engine));
                for (0..@as(usize, @intCast(length))) |i| { const item = try completion.ownRoot(scope, try engine.checked(c.JS_GetPropertyUint32(engine.context, source, @intCast(i)))); try data.appendSlice(engine.gpa, try buffer.bytes(scope, item)); }
            }
            const copied_bytes = try data.toOwnedSlice(engine.gpa);
            const previous_bytes = task.native_bytes; task.native_bytes = copied_bytes; engine.gpa.free(previous_bytes);
            task.packet.bytes = task.native_bytes; task.returned_buffer = c.JS_DupValue(engine.context, source);
            const position = core.arg(args, if (method == .write) 4 else 2);
            if (c.JS_IsNumber(position)) { var value: f64 = 0; if (c.JS_ToFloat64(engine.context, &value, position) < 0) return @as(anyerror!c.JSValue, js.capture(engine)); if (std.math.isFinite(value) and value >= 0 and value <= 9007199254740991 and value == @floor(value)) task.packet.position = @intFromFloat(value); }
        }
        if (method == .close) if (owned) |file| { file.closing = true; file.file = null; };
    }
    // Invalid descriptors still complete asynchronously on a real native task.
    // Packet.run must preserve the already-classified failure without touching IO.
    task.task.hub.submit(&task.task) catch |err| {
        if (method == .close) if (task.file) |file| { file.closing = false; file.file = task.packet.file; task.packet.file = null; };
        return err;
    };
    submitted = true; return c.pi_js_undefined();
}
pub fn install(engine: *em.Engine, fs: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    return completion.finishVoid(&scope, installBody(&scope, fs));
}
fn installBody(scope: *Scope, fs: c.JSValue) !void {
    const engine = scope.engine;
    try engine.checkNativeEntry();
    var module = engine.native_module_values.get(key) orelse c.pi_js_undefined();
    if (c.JS_IsUndefined(module)) {
        module = try completion.ownRoot(scope, try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
        var id: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &id); const definition: c.JSClassDef = .{ .class_name = "Native owned WriteStream files", .finalizer = registryFinalize };
        if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
        const holder = try completion.ownRoot(scope, try engine.checked(c.JS_NewObjectClass(engine.context, id))); const state = try engine.gpa.create(Registry); state.* = .{ .engine = engine, .class_id = id }; _ = c.JS_SetOpaque(holder, state);
        inline for (.{ "open", "write", "writev", "fsync", "close" }, .{ Method.open, Method.write, Method.writev, Method.fsync, Method.close }, .{ 4, 6, 4, 2, 2 }) |name, method, length| try scope.put(module, name, try completion.ownRoot(scope, try fnc.create(engine, name, length, dispatch, &.{ holder, c.JS_NewInt32(engine.context, @intFromEnum(method)), c.JS_NewUint32(engine.context, id) })));
        try engine.registerValueModule(key, module);
    }
    inline for (.{ "open", "write", "writev", "fsync", "close" }) |name| try scope.put(fs, name, try scope.get(module, name));
}
