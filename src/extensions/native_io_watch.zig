//! Owner-thread delivery of existing native directory event backends.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const Engine = js.Engine;
const c = js.c;
const native = if (builtin.os.tag == .windows) @import("../durable/watch_windows.zig") else if (builtin.os.tag == .macos) @import("../durable/watch_macos.zig") else @import("../durable/watch_linux.zig");
const State = struct {
    engine: *Engine,
    backend: native.Backend,
    directory: []u8,
    callback: c.JSValue,
    error_callback: c.JSValue,
    timer: c.JSValue,
    startup_paths: std.ArrayList([]u8) = .empty,
    startup_bytes: usize = 0,
    startup_overflow: bool = false,
    closed: bool = false,
    draining: bool = false,
    retired: bool = false,
    fn retire(self: *State) void {
        if (self.retired or self.draining) return;
        self.retired = true;
        if (builtin.os.tag == .macos) self.backend.retireOnOwnerThread();
        self.backend.deinit();
        for (self.startup_paths.items) |path| self.engine.gpa.free(path);
        self.startup_paths.deinit(self.engine.gpa);
        self.startup_paths = .empty;
        self.startup_bytes = 0;
    }
    fn close(self: *State) !void {
        self.closed = true;
        defer self.retire();
        const timer = self.timer;
        self.timer = c.pi_js_undefined();
        defer self.engine.freeValue(timer);
        if (!c.JS_IsUndefined(timer)) {
            const ignored = try js.invoke(self.engine, timer, "close", &.{});
            self.engine.freeValue(ignored);
        }
    }
};
fn state(value: c.JSValue) ?*State {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value))));
}
pub fn closed(value: c.JSValue) bool {
    return if (state(value)) |owned| owned.closed else true;
}
pub fn deliver(engine: *Engine, holder: c.JSValue, filename: c.JSValue) !void {
    const owned = state(holder) orelse return error.InvalidNativeWatchHolder;
    if (owned.closed) return;
    const event_name = try engine.checked(c.JS_NewString(engine.context, "change"));
    defer engine.freeValue(event_name);
    const result = try js.call(engine, owned.callback, c.pi_js_undefined(), &.{ event_name, filename });
    engine.freeValue(result);
}
pub fn deliverError(engine: *Engine, holder: c.JSValue) !void {
    const owned = state(holder) orelse return error.InvalidNativeWatchHolder;
    const result = try js.call(engine, owned.error_callback, c.pi_js_undefined(), &.{});
    engine.freeValue(result);
}
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const owned = state(value) orelse return;
    owned.closed = true;
    owned.retire();
    c.JS_FreeValueRT(runtime, owned.callback);
    c.JS_FreeValueRT(runtime, owned.error_callback);
    c.JS_FreeValueRT(runtime, owned.timer);
    owned.engine.gpa.free(owned.directory);
    owned.engine.gpa.destroy(owned);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const owned = state(value) orelse return;
    c.JS_MarkValue(runtime, owned.callback, marker);
    c.JS_MarkValue(runtime, owned.error_callback, marker);
    c.JS_MarkValue(runtime, owned.timer, marker);
}
fn failure(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowInternalError(engine.context, "Native watch: %s", @as([*:0]const u8, @errorName(err)));
}
fn closeCall(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const owned = state(receiver) orelse return c.JS_ThrowTypeError(context, "Invalid native watch receiver");
    owned.close() catch |err| return failure(engine, err);
    return c.pi_js_undefined();
}
const Sink = struct {
    owned: *State,
    fn deliver(self: Sink, filename: c.JSValue) !void {
        if (self.owned.closed) return;
        const engine = self.owned.engine;
        const event_name = try engine.checked(c.JS_NewString(engine.context, "change"));
        defer engine.freeValue(event_name);
        const result = try js.call(engine, self.owned.callback, c.pi_js_undefined(), &.{ event_name, filename });
        engine.freeValue(result);
    }
    pub fn event(self: Sink, path: []const u8) !void {
        if (self.owned.closed) return;
        if (std.mem.eql(u8, path, self.owned.directory)) return self.deliver(c.pi_js_undefined());
        const engine = self.owned.engine;
        const filename = try engine.checked(c.JS_NewStringLen(engine.context, std.fs.path.basename(path).ptr, std.fs.path.basename(path).len));
        defer engine.freeValue(filename);
        try self.deliver(filename);
    }
    pub fn overflow(self: Sink) !void {
        try self.deliver(c.pi_js_undefined());
    }
};
const StartupSink = struct {
    owned: *State,
    pub fn event(self: StartupSink, path: []const u8) !void {
        if (self.owned.startup_overflow) return;
        if (self.owned.startup_paths.items.len >= 128 or path.len > 8 * 1024 * 1024 - self.owned.startup_bytes) return self.overflow();
        const copy = try self.owned.engine.gpa.dupe(u8, path);
        errdefer self.owned.engine.gpa.free(copy);
        try self.owned.startup_paths.append(self.owned.engine.gpa, copy);
        self.owned.startup_bytes += copy.len;
    }
    pub fn overflow(self: StartupSink) !void {
        self.owned.startup_overflow = true;
    }
};
fn drain(owned: *State) !void {
    const sink: Sink = .{ .owned = owned };
    if (owned.startup_overflow) {
        owned.startup_overflow = false;
        try sink.overflow();
    }
    var pending = owned.startup_paths;
    owned.startup_paths = .empty;
    owned.startup_bytes = 0;
    defer {
        for (pending.items) |path| owned.engine.gpa.free(path);
        pending.deinit(owned.engine.gpa);
    }
    for (pending.items) |path| try sink.event(path);
    if (!owned.closed) try owned.backend.drain(sink);
}
fn schedule(engine: *Engine, holder: c.JSValue, owned: *State) !void {
    var data = [_]c.JSValue{holder};
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, tick, "native watch delivery", 0, 0, 1, &data));
    defer engine.freeValue(callback);
    const timer = try @import("timers.zig").scheduleOnce(engine, callback, 10);
    engine.freeValue(owned.timer);
    owned.timer = timer;
}
fn tick(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const owned = state(data[0]) orelse return c.pi_js_undefined();
    engine.freeValue(owned.timer);
    owned.timer = c.pi_js_undefined();
    if (owned.closed) return c.pi_js_undefined();
    owned.draining = true;
    const result = drain(owned);
    owned.draining = false;
    if (owned.closed) owned.retire();
    result catch |err| {
        if (err == error.JavaScriptException or err == error.OutOfMemory) return failure(engine, err);
        const ignored = js.call(engine, owned.error_callback, c.pi_js_undefined(), &.{}) catch |cause| return failure(engine, cause);
        engine.freeValue(ignored);
        return c.pi_js_undefined();
    };
    if (!owned.closed) schedule(engine, data[0], owned) catch |err| return failure(engine, err);
    return c.pi_js_undefined();
}
pub fn install(engine: *Engine, module: c.JSValue) !void {
    var class_id: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class_id);
    const definition: c.JSClassDef = .{ .class_name = "Native Directory Watch", .finalizer = finalize, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, class_id, &definition) < 0) return error.NativeWatchClassUnavailable;
    try js.define(engine, module, "nativeWatchClassId", c.JS_NewUint32(engine.context, class_id));
}
pub fn open(engine: *Engine, module: c.JSValue, directory: []const u8, callback: c.JSValue, error_callback: c.JSValue) !c.JSValue {
    const io = engine.native_io orelse return error.NativeWatchIoUnavailable;
    if (builtin.os.tag != .windows and builtin.os.tag != .linux and builtin.os.tag != .macos) return error.NativeWatchUnsupported;
    if (!engine.native_module_names.contains("node:timers")) try @import("timers.zig").install(engine, io);
    var backend = try native.Backend.init(engine.gpa);
    var transferred = false;
    errdefer if (!transferred) {
        if (builtin.os.tag == .macos) backend.retireOnOwnerThread();
        backend.deinit();
    };
    if (!try backend.add(directory, 0, 0)) return error.NativeWatchUnavailable;
    const stored_class = try js.get(engine, module, "nativeWatchClassId");
    defer engine.freeValue(stored_class);
    var class_id: u32 = undefined;
    if (c.JS_ToUint32(engine.context, &class_id, stored_class) < 0) return js.capture(engine);
    if (class_id == 0) return error.NativeWatchClassUnavailable;
    const holder = try engine.checked(c.JS_NewObjectClass(engine.context, @intCast(class_id)));
    errdefer engine.freeValue(holder);
    const owned = try engine.gpa.create(State);
    errdefer if (!transferred) engine.gpa.destroy(owned);
    const directory_copy = try engine.gpa.dupe(u8, directory);
    owned.* = .{ .engine = engine, .backend = backend, .directory = directory_copy, .callback = c.JS_DupValue(engine.context, callback), .error_callback = c.JS_DupValue(engine.context, error_callback), .timer = c.pi_js_undefined() };
    _ = c.JS_SetOpaque(holder, owned);
    transferred = true;
    try js.define(engine, holder, "close", try engine.checked(c.JS_NewCFunction(engine.context, closeCall, "close", 0)));
    // Darwin does not subscribe until its stream starts on a run loop. Arm it
    // before returning so a caller's immediate write is observed. Buffer any
    // already delivered paths; extension callbacks remain asynchronous.
    if (builtin.os.tag == .macos) try owned.backend.drain(StartupSink{ .owned = owned });
    try schedule(engine, holder, owned);
    return holder;
}
fn noOp(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn allocationProbe(gpa: std.mem.Allocator, directory: []const u8) !void {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("timers.zig").install(engine, std.testing.io);
    const module = try js.object(engine);
    defer engine.freeValue(module);
    try install(engine, module);
    const callback = try engine.checked(c.JS_NewCFunction(engine.context, noOp, "watch allocation callback", 0));
    defer engine.freeValue(callback);
    const original_allocator = engine.gpa;
    engine.gpa = gpa;
    defer engine.gpa = original_allocator;
    defer engine.beginInvocation();
    const holder = open(engine, module, directory, callback, callback) catch |err| return @import("native_text_component.zig").allocationError(engine, err);
    defer engine.freeValue(holder);
    const ignored = js.invoke(engine, holder, "close", &.{}) catch |err| return @import("native_text_component.zig").allocationError(engine, err);
    engine.freeValue(ignored);
    try std.testing.expect(closed(holder));
    try std.testing.expectEqual(@as(?i64, null), try @import("timers.zig").nextDeadline(engine));
}
test "Source6fb Theme watcher all native event holder allocations release kernel operations callback roots and timers" {
    if (builtin.os.tag != .windows and builtin.os.tag != .linux and builtin.os.tag != .macos) return error.SkipZigTest;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary.dir.realPath(std.testing.io, &buffer);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{buffer[0..length]});
    for (0..100) |_| try allocationProbe(std.testing.allocator, buffer[0..length]);
}
