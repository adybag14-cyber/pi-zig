//! Actual public spawn/ChildProcess assembly over owned native Driver + Socket.
//! Construction is separate from application selection; no Module._load shim.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const c = js.c;
const frontier = @import("native_child_process_scope.zig");
const Scope = frontier.Scope;
const fnc = @import("native_child_process_function.zig");
const options = @import("native_child_process_options.zig");
const driver_api = if (builtin.os.tag == .linux) @import("native_child_process_public_linux_driver.zig") else @import("native_child_process_scheduler.zig");
const pipes = if (builtin.os.tag == .linux) @import("native_child_process_socket_owner_linux.zig") else @import("native_child_process_socket_owner.zig");
const FailedOwner = if (builtin.os.tag == .linux) pipes.Owner else @import("native_child_process_failed_socket_owner.zig").Owner;
const socket = @import("native_node_net_socket.zig");
const canonical = @import("native_node_net_socket_provider.zig");
const publication = @import("native_child_process_builtin_publication.zig");
const legacy = @import("native_node_child_process.zig");
const async_events = @import("node_events_async.zig");
const vm_options = @import("native_child_process_vm_options.zig");
const stdio_vm = @import("native_child_process_stdio_vm.zig");
const vm_binding = @import("native_child_process_vm_binding.zig");
const pipe_record = @import("native_child_process_pipe_record.zig");
const process_handle = @import("native_child_process_public_handle.zig");
const completions = @import("native_child_process_completion_queue.zig");
const cache_key = "\x00native-public-child-process-selector";
const Entry = struct { engine: *js.Engine, previous: ?*Entry };
threadlocal var initializing: ?*Entry = null;
pub const Inputs = struct {
    streams: c.JSValue, process: c.JSValue, signals: c.JSValue,
    // Actual bootstrap-captured primordial, not a later mutable Array.slice.
    array_prototype_slice: c.JSValue,
    string_prototype_to_upper_case: c.JSValue,
    timers: c.JSValue,
    // Actual ErrnoException constructor from the embedding's util authority.
    errno_exception: c.JSValue,
    primordials: vm_options.Primordials,
    array_prototype_reduce: c.JSValue, array_buffer_is_view: c.JSValue,
    permission: vm_options.Permission,
    inherited_environment: ?*const fn (*js.Engine) anyerror!@import("native_child_process_environment.zig").Environment = null,
    // One canonical net identity shared with genuine tty_wrap adoption.
    socket_provider: ?*const socket.Provider = null,
    linux_handshake_budget_ms: u32 = 10_000,
    linux_stdio: ?@import("native_child_process_stdio_linux.zig").Map = null,
    windows_stdio: ?@import("native_child_process_stdio_windows.zig").Map = null,
    stdio_source: ?@import("native_process_streams.zig").Lease = null,
};
pub const Bundle = struct {
    node: c.JSValue, cross_spawn: c.JSValue, net: c.JSValue,
    context: *Module,
    pub fn deinit(self: Bundle, engine: *js.Engine) void { engine.freeValue(self.node); engine.freeValue(self.cross_spawn); engine.freeValue(self.net); }
};
const Module = struct {
    engine: *js.Engine, sockets: socket.Provider,
    net: c.JSValue,
    publication: publication.State = .{},
    process: c.JSValue, signals: c.JSValue, emitter: c.JSValue, events: c.JSValue, array_slice: c.JSValue,
    set_timeout: c.JSValue, clear_timeout: c.JSValue, signal_upper: c.JSValue, errno_exception: c.JSValue,
    tick_helpers: [3]c.JSValue,
    children: c.JSValue, constructor: c.JSValue, dispose_symbol: c.JSValue,
    child_brand: c.JSClassID,
    pipe_records: pipe_record.Provider,
    primordials: vm_options.Primordials, normalizer: vm_options.State = .{},
    array_reduce: c.JSValue, is_view: c.JSValue,
    permission: vm_options.Permission,
    inherited_environment: ?*const fn (*js.Engine) anyerror!@import("native_child_process_environment.zig").Environment,
    linux_handshake_budget_ms: u32,
    linux_stdio: ?@import("native_child_process_stdio_linux.zig").Map,
    windows_stdio: ?@import("native_child_process_stdio_windows.zig").Map,
    stdio_source: ?@import("native_process_streams.zig").Lease,
};
const Child = struct {
    engine: *js.Engine, module: *Module,
    child: c.JSValue, module_holder: c.JSValue,
    holder: c.JSValue, // borrowed self; only Native Driver entitlement duplicates it
    signal: c.JSValue, disposable: c.JSValue, spawn_failure: c.JSValue, kill_argument: c.JSValue, timer: c.JSValue,
    original_emit: c.JSValue, original_command: c.JSValue, original_args: c.JSValue,
    driver: ?*driver_api.OwnerBridge = null, owner: ?*pipes.Owner = null,
    failed_owner: ?*FailedOwner = null,
    native_cleanup_failure: ?anyerror = null,
    started: bool = false, exited: bool = false, close_emitted: bool = false,
    retire_requested: bool = false, sent_signal: ?i32 = null, kill_signal: i32 = 15,
    spawn_errno: i32 = 0,
    cross_missing: bool = false,
    normalized_options: c.JSValue,
    native_ticket: ?process_handle.Ticket = null,
    handle_closed: bool = false,
    fn set(self: *Child, field: *c.JSValue, value: c.JSValue) void { const copy = c.JS_DupValue(self.engine.context, value); self.engine.freeValue(field.*); field.* = copy; }
};
// Error mapping has native-only lifetime, independent of child/Socket GC graph.
// It never retains a child/module JS root through the Socket's native hook.
const ErrorContext = struct {
    allocator: std.mem.Allocator, references: usize = 1,
    fn retain(raw: *anyopaque) void { const self: *@This() = @ptrCast(@alignCast(raw)); self.references += 1; }
    fn release(raw: *anyopaque) void { const self: *@This() = @ptrCast(@alignCast(raw)); self.references -= 1; if (self.references == 0) self.allocator.destroy(self); }
    fn value(_: *anyopaque, engine: *js.Engine, failure: anyerror) !c.JSValue {
        if (failure == error.OutOfMemory) return @as(anyerror!c.JSValue, failure);
        return switch (failure) {
            error.BrokenPipe => systemError(engine, "EPIPE", if (builtin.os.tag == .windows) -4047 else -32, "write", null, &.{}),
            error.NativeStdinOperationAborted, error.NativeChildInputClosed => systemError(engine, "ECANCELED", if (builtin.os.tag == .windows) -4081 else -125, "write", null, &.{}),
            // Unknown private kernel/ownership failures cannot invent Node EIO.
            else => failure,
        };
    }
};
fn moduleFinalizer(runtime: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
    const self: *Module = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    inline for (.{ "process", "signals", "emitter", "events", "children", "constructor", "dispose_symbol", "array_slice", "set_timeout", "clear_timeout", "signal_upper", "errno_exception", "array_reduce", "is_view" }) |field| c.JS_FreeValueRT(runtime, @field(self, field));
    inline for (std.meta.fields(vm_options.Primordials)) |field| c.JS_FreeValueRT(runtime, @field(self.primordials, field.name));
    c.JS_FreeValueRT(runtime, self.pipe_records.constructor);
    for (self.tick_helpers) |helper| c.JS_FreeValueRT(runtime, helper);
    self.publication.deinit(runtime); c.JS_FreeValueRT(runtime, self.net);
    c.JS_FreeValueRT(runtime, self.sockets.constructor); c.JS_FreeValueRT(runtime, self.sockets.states);
    const engine = self.engine; engine.gpa.destroy(self); c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Module));
}
fn moduleMark(runtime: ?*c.JSRuntime, holder: c.JSValue, mark: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *Module = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    inline for (.{ "process", "signals", "emitter", "events", "children", "constructor", "dispose_symbol", "array_slice", "set_timeout", "clear_timeout", "signal_upper", "errno_exception", "array_reduce", "is_view" }) |field| c.JS_MarkValue(runtime, @field(self, field), mark);
    inline for (std.meta.fields(vm_options.Primordials)) |field| c.JS_MarkValue(runtime, @field(self.primordials, field.name), mark);
    c.JS_MarkValue(runtime, self.pipe_records.constructor, mark);
    c.JS_MarkValue(runtime, self.sockets.constructor, mark); c.JS_MarkValue(runtime, self.sockets.states, mark);
    for (self.tick_helpers) |helper| c.JS_MarkValue(runtime, helper, mark);
    self.publication.mark(runtime, mark); c.JS_MarkValue(runtime, self.net, mark);
}
fn childFinalizer(runtime: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
    const self: *Child = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    // Actual Driver roots holder until release; no finalizer signals a child.
    std.debug.assert(self.driver == null and self.failed_owner == null);
    if (self.native_ticket) |ticket| process_handle.close(ticket) catch {};
    inline for (.{ "child", "module_holder", "signal", "disposable", "spawn_failure", "original_emit", "original_command", "original_args", "kill_argument", "timer", "normalized_options" }) |field| c.JS_FreeValueRT(runtime, @field(self, field));
    const engine = self.engine; engine.gpa.destroy(self); c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Child));
}
fn childMark(runtime: ?*c.JSRuntime, holder: c.JSValue, mark: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *Child = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    inline for (.{ "child", "module_holder", "signal", "disposable", "spawn_failure", "original_emit", "original_command", "original_args", "kill_argument", "timer", "normalized_options" }) |field| c.JS_MarkValue(runtime, @field(self, field), mark);
}
fn register(engine: *js.Engine, name: [*:0]const u8, comptime finalizer: anytype, comptime mark: anytype) !c.JSClassID {
    var id: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &id);
    const definition: c.JSClassDef = .{ .class_name = name, .finalizer = finalizer, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory; return id;
}
fn capturedModule(engine: *js.Engine, roots: []const c.JSValue) !*Module {
    var id: u32 = 0; if (c.JS_ToUint32(engine.context, &id, roots[1]) < 0) return @as(anyerror!*Module, js.capture(engine));
    const self: *Module = @ptrCast(@alignCast(c.JS_GetOpaque(roots[0], id) orelse return error.NativeChildModuleBrand));
    if (self.engine != engine) return error.NativeChildModuleOwner; return self;
}
fn getChild(scope: *Scope, module: *Module, child: c.JSValue) !*Child {
    const holder = try scope.invoke(module.children, "get", &.{child});
    const self: *Child = @ptrCast(@alignCast(c.JS_GetOpaque(holder, module.child_brand) orelse return error.NativeChildIncompatibleReceiver));
    if (self.engine != scope.engine or self.module != module or !scope.equal(self.child, child)) return error.NativeChildIncompatibleReceiver; return self;
}
fn capturedChild(engine: *js.Engine, roots: []const c.JSValue) !*Child {
    var id: u32 = 0; if (c.JS_ToUint32(engine.context, &id, roots[1]) < 0) return @as(anyerror!*Child, js.capture(engine));
    const self: *Child = @ptrCast(@alignCast(c.JS_GetOpaque(roots[0], id) orelse return error.NativeChildIncompatibleReceiver));
    if (self.engine != engine) return error.NativeChildIncompatibleReceiver; return self;
}
fn emit(scope: *Scope, child: c.JSValue, name: []const u8, args: []const c.JSValue) !void {
    const all = try scope.engine.gpa.alloc(c.JSValue, args.len + 1); defer scope.engine.gpa.free(all);
    all[0] = try scope.text(name); @memcpy(all[1..], args); _ = try scope.invoke(child, "emit", all);
}
const Tick = enum(usize) { spawn, failure, flush };
fn tick(self: *Child, kind: Tick) !void {
    var scope: Scope = .{ .engine = self.engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const function = self.module.tick_helpers[@intFromEnum(kind)];
    if (kind == .failure) _ = try scope.invoke(self.module.process, "nextTick", &.{ function, self.child, c.JS_NewInt32(self.engine.context, self.spawn_errno) })
    else _ = try scope.invoke(self.module.process, "nextTick", &.{ function, self.child });
}
fn construct(engine: *js.Engine, child: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err); const module = try capturedModule(engine, roots);
    _ = try scope.call(module.emitter, child, &.{});
    const holder = try scope.own(try engine.checked(c.JS_NewObjectClass(engine.context, module.child_brand)));
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(Child)) == 0) return error.OutOfMemory;
    var attached = false; errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Child));
    const self = try engine.gpa.create(Child);
    self.* = .{ .engine = engine, .module = module, .child = c.JS_DupValue(engine.context, child), .module_holder = c.JS_DupValue(engine.context, roots[0]), .holder = holder, .signal = c.pi_js_undefined(), .disposable = c.pi_js_undefined(), .spawn_failure = c.pi_js_undefined(), .kill_argument = c.pi_js_undefined(), .timer = c.pi_js_undefined(), .original_emit = c.pi_js_undefined(), .original_command = c.pi_js_undefined(), .original_args = c.pi_js_undefined(), .normalized_options = c.pi_js_undefined() };
    _ = c.JS_SetOpaque(holder, self); attached = true;
    _ = try scope.invoke(module.children, "set", &.{ child, holder });
    try scope.set(child, "_closesNeeded", c.JS_NewInt32(engine.context, 1)); try scope.set(child, "_closesGot", c.JS_NewInt32(engine.context, 0));
    try scope.set(child, "connected", c.pi_js_bool(engine.context, 0));
    inline for (.{ "signalCode", "exitCode" }) |field| try scope.set(child, field, c.pi_js_null());
    try scope.set(child, "killed", c.pi_js_bool(engine.context, 0)); try scope.set(child, "spawnfile", c.pi_js_null());
    try scope.set(child, "_handle", holder);
    try scope.put(holder, "spawn", try scope.own(try fnc.create(engine, "spawn", 0, nativeSpawn, &.{holder, c.JS_NewUint32(engine.context, module.child_brand)})));
    const handle_roots = [_]c.JSValue{holder, c.JS_NewUint32(engine.context, module.child_brand)};
    try scope.put(holder, "close", try scope.own(try fnc.create(engine, "close", 0, nativeClose, &handle_roots)));
    try scope.put(holder, "kill", try scope.own(try fnc.create(engine, "kill", 0, nativeKill, &handle_roots)));
    inline for (.{"ref", "unref"}, .{true, false}) |name, value| try scope.put(holder, name, try scope.own(try fnc.create(engine, name, 0, nativeReference, &.{handle_roots[0], handle_roots[1], c.pi_js_bool(engine.context, @intFromBool(value))})));
    try scope.put(holder, "onexit", try scope.own(try fnc.createArrow(engine, "", 2, onExit, &handle_roots)));
    return c.pi_js_undefined();
}
fn rawError(scope: *Scope, message: []const u8) !c.JSValue {
    const value = try scope.own(try scope.engine.checked(c.JS_NewError(scope.engine.context)));
    if (c.JS_DefinePropertyValueStr(scope.engine.context, value, "message", c.JS_DupValue(scope.engine.context, try scope.text(message)), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return @as(anyerror!c.JSValue, js.capture(scope.engine));
    return value;
}
fn systemError(engine: *js.Engine, code: []const u8, errno: i32, syscall: []const u8, path: ?[]const u8, args: []const []const u8) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const message = try std.fmt.allocPrint(engine.gpa, "{s} {s}", .{syscall, code}); defer engine.gpa.free(message);
    const value = try rawError(&scope, message); try scope.put(value, "code", try scope.text(code)); try scope.put(value, "errno", c.JS_NewInt32(engine.context, errno)); try scope.put(value, "syscall", try scope.text(syscall));
    if (path) |file| {
        try scope.put(value, "path", try scope.text(file)); const argv = try scope.array();
        for (args, 0..) |arg, index| try scope.index(argv, @intCast(index), try scope.text(arg)); try scope.put(value, "spawnargs", argv);
    }
    return c.JS_DupValue(engine.context, value);
}
fn spawnError(engine: *js.Engine, failure: anyerror, file: []const u8, args: []const []const u8) !struct { value: c.JSValue, errno: i32, asynchronous: bool } {
    const selected: struct { code: []const u8, errno: i32, asynchronous: bool } = switch (failure) {
        error.FileNotFound => .{ .code = "ENOENT", .errno = if (builtin.os.tag == .windows) -4058 else -2, .asynchronous = true },
        error.AccessDenied => if (builtin.os.tag == .windows) .{ .code = "EPERM", .errno = -4048, .asynchronous = false } else .{ .code = "EACCES", .errno = -13, .asynchronous = true },
        error.PermissionDenied => .{ .code = "EPERM", .errno = if (builtin.os.tag == .windows) -4048 else -1, .asynchronous = false },
        error.InvalidExe => .{ .code = if (builtin.os.tag == .windows) "EFTYPE" else "ENOEXEC", .errno = if (builtin.os.tag == .windows) -4028 else -8, .asynchronous = false },
        else => return failure, // no fabricated EIO for missing native support
    };
    const syscall = try std.fmt.allocPrint(engine.gpa, "spawn {s}", .{file}); defer engine.gpa.free(syscall);
    return .{ .value = try systemError(engine, selected.code, selected.errno, syscall, file, args), .errno = selected.errno, .asynchronous = selected.asynchronous };
}
fn closeCount(self: *Child) !void {
    var scope: Scope = .{ .engine = self.engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const previous = try scope.get(self.child, "_closesGot");
    const incremented = try frontier.increment(&scope, previous);
    try scope.set(self.child, "_closesGot", incremented);
    if (scope.equal(try scope.get(self.child, "_closesGot"), try scope.get(self.child, "_closesNeeded"))) {
        self.close_emitted = true;
        defer if (self.failed_owner) |owner| { owner.requestRetire() catch {}; };
        try emit(&scope, self.child, "close", &.{ try scope.get(self.child, "exitCode"), try scope.get(self.child, "signalCode") });
        if (self.driver) |driver| try requestCheckpoint(driver);
    }
}
fn pipeClosed(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { try closeCount(try capturedChild(engine, roots)); return c.pi_js_undefined(); }
fn flushInterrupt(engine: *js.Engine) !void {
    engine.interrupts += 1;
    if (!engine.cancelled.load(.acquire) and engine.interrupts <= engine.options.interrupt_budget) return;
    _ = c.JS_ThrowInternalError(engine.context, "interrupted");
    const reason = c.JS_GetException(engine.context);
    c.JS_SetUncatchableError(engine.context, reason);
    _ = try engine.checked(c.JS_Throw(engine.context, reason));
}
fn flushTick(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const stdio = try scope.get(options.arg(args, 0), "stdio"); if (c.JS_IsNull(stdio) or c.JS_IsUndefined(stdio)) return c.pi_js_undefined();
    var index: f64 = 0;
    while (true) : (index += 1) {
        var iteration: Scope = .{ .engine = engine }; defer iteration.deinit(); errdefer |err| iteration.captureUnwind(err);
        const length = try iteration.get(stdio, "length");
        const more = try frontier.binary(&iteration, 4, c.JS_NewFloat64(engine.context, index), length);
        if (!iteration.truthy(more)) break;
        // Native loops must honor the actual VM owner budget too. This bounds
        // hostile infinite lengths without truncating Source numeric coercion.
        try flushInterrupt(engine);
        const stream = try frontier.getKey(&iteration, stdio, c.JS_NewFloat64(engine.context, index));
        if (!iteration.truthy(stream)) continue;
        if (iteration.truthy(try iteration.get(stream, "readable"))) _ = try iteration.invoke(stream, "resume", &.{});
    }
    return c.pi_js_undefined();
}
fn spawnTick(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    try emit(&scope, options.arg(args, 0), "spawn", &.{}); return c.pi_js_undefined();
}
fn failureTick(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const self = try getChild(&scope, try capturedModule(engine, roots), options.arg(args, 0));
    defer if (self.failed_owner) |owner| { owner.enable() catch {}; };
    _ = try scope.invoke(try scope.get(self.child, "_handle"), "onexit", &.{options.arg(args, 1)});
    return c.pi_js_undefined();
}
fn driverStop(raw: *anyopaque) void { const self: *Child = @ptrCast(@alignCast(raw)); self.driver = null; self.owner = null; self.failed_owner = null; }
fn failedReleased(engine: *js.Engine, raw: *anyopaque) void {
    const self: *Child = @ptrCast(@alignCast(raw)); self.failed_owner = null;
    engine.freeValue(self.holder);
}
fn driverRelease(engine: *js.Engine, raw: *anyopaque) void {
    const self: *Child = @ptrCast(@alignCast(raw)); self.driver = null; self.owner = null; self.failed_owner = null;
    if (self.native_ticket) |ticket| { self.native_ticket = null; process_handle.close(ticket) catch {}; }
    // Explicit Driver entitlement; actual JS holder owns all VM references.
    engine.freeValue(self.holder);
}
fn driverPoll(_: *js.Engine, raw: *anyopaque, driver: *driver_api.OwnerBridge) !bool {
    const self: *Child = @ptrCast(@alignCast(raw));
    if ((self.close_emitted or (self.handle_closed and driverExited(driver))) and !self.retire_requested) { try driver.requestRetire(); self.retire_requested = true; }
    return false;
}
fn driverPid(driver: *driver_api.OwnerBridge) u32 {
    return if (builtin.os.tag == .linux) @intCast(driver.transport.process.ticket.watch.pid) else driver.transport.process.identity.pid;
}
fn driverExited(driver: *driver_api.OwnerBridge) bool { return if (builtin.os.tag == .linux) driver.transport.process.exited != null else driver.transport.process.exited; }
fn requestCheckpoint(driver: *driver_api.OwnerBridge) !void {
    if (builtin.os.tag == .linux) @import("native_child_process_epoll_linux.zig").requestStep(driver.lease) else try driver.requestOwnerCheckpoint();
}
fn driverEvent(engine: *js.Engine, raw: *anyopaque, driver: *driver_api.OwnerBridge, event: driver_api.Event) !void {
    const self: *Child = @ptrCast(@alignCast(raw)); var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    switch (event) {
        .exit => |result| {
            const signal = if (result.signal) |value| @as(?i32, @intCast(value)) else if (builtin.os.tag == .windows) self.sent_signal else null;
            const name = if (signal) |value| try signalName(&scope, self.module, value) else c.pi_js_null();
            if (!self.handle_closed) _ = try scope.invoke(self.holder, "onexit", &.{c.JS_NewInt64(engine.context, result.code), name});
        },
        .failure => |failure| return failure, // private ownership failure, not false Node EIO
        else => {},
    }
    if (builtin.os.tag != .linux) switch (event) {
        .timeout_signal => |sent| if (sent) { self.sent_signal = self.kill_signal; try scope.set(self.child, "killed", c.pi_js_bool(engine.context, 1)); },
        .timeout_failure => |failure| {
            if (failure != error.UnsupportedNativeChildKillSignal) return @as(anyerror!void, failure);
            const reason = try scope.own(try systemError(engine, "ENOSYS", if (builtin.os.tag == .windows) -4054 else -38, "kill", null, &.{}));
            try emit(&scope, self.child, "error", &.{reason});
        },
        else => {},
    };
    _ = driver;
}
fn signalNumber(scope: *Scope, module: *Module, value: c.JSValue) !i32 {
    if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) return 15;
    if (c.JS_IsNumber(value)) {
        var number: f64 = 0; if (c.JS_ToFloat64(scope.engine.context, &number, value) < 0) return @as(anyerror!i32, js.capture(scope.engine));
        if (number == 0) return 0;
        const values = try scope.own(try js.objectMethod(scope.engine, "values", module.signals));
        var count: u32 = 0; if (c.JS_ToUint32(scope.engine.context, &count, try scope.get(values, "length")) < 0) return @as(anyerror!i32, js.capture(scope.engine));
        for (0..count) |index| { const entry = try scope.getIndex(values, @intCast(index)); if (scope.equal(entry, value)) { var result: i32 = 0; if (c.JS_ToInt32(scope.engine.context, &result, entry) < 0) return @as(anyerror!i32, js.capture(scope.engine)); return result; } }
    } else if (c.JS_IsString(value)) {
        const name = try scope.call(module.signal_upper, value, &.{}); const selected = try frontier.getKey(scope, module.signals, name);
        if (!c.JS_IsUndefined(selected)) { var result: i32 = 0; if (c.JS_ToInt32(scope.engine.context, &result, selected) < 0) return @as(anyerror!i32, js.capture(scope.engine)); return result; }
    }
    return @import("node_events.zig").codedError(scope.engine, "TypeError", "ERR_UNKNOWN_SIGNAL", "Unknown signal");
}
fn signalName(scope: *Scope, module: *Module, number: i32) !c.JSValue {
    const keys = try scope.own(try js.objectMethod(scope.engine, "keys", module.signals));
    var count: u32 = 0; if (c.JS_ToUint32(scope.engine.context, &count, try scope.get(keys, "length")) < 0) return @as(anyerror!c.JSValue, js.capture(scope.engine));
    for (0..count) |index| {
        const key = try scope.getIndex(keys, @intCast(index));
        if (scope.equal(try frontier.getKey(scope, module.signals, key), c.JS_NewInt32(scope.engine.context, number))) return key;
    }
    return error.NativeChildUnknownKernelSignal;
}
fn kill(engine: *js.Engine, child: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err); const module = try capturedModule(engine, roots);
    const requested = options.arg(args, 0);
    if (c.JS_IsNull(requested)) return @import("node_events.zig").codedError(engine, "TypeError", "ERR_UNKNOWN_SIGNAL", "Unknown signal");
    const number = try signalNumber(&scope, module, requested);
    if (scope.truthy(try scope.get(child, "_handle"))) {
        const result = try scope.invoke(try scope.get(child, "_handle"), "kill", &.{c.JS_NewInt32(engine.context, number)});
        if (scope.equal(result, c.JS_NewInt32(engine.context, 0))) { try scope.set(child, "killed", c.pi_js_bool(engine.context, 1)); return c.pi_js_bool(engine.context, 1); }
        if (!scope.equal(result, c.JS_NewInt32(engine.context, if (builtin.os.tag == .windows) -4040 else -3))) {
            var parameters = [_]c.JSValue{result, try scope.text("kill")};
            const reason = try scope.construct(module.errno_exception, &parameters);
            if (scope.equal(result, c.JS_NewInt32(engine.context, if (builtin.os.tag == .windows) -4071 else -22)) or scope.equal(result, c.JS_NewInt32(engine.context, if (builtin.os.tag == .windows) -4054 else -38))) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
            try emit(&scope, child, "error", &.{reason});
        }
    }
    return c.pi_js_bool(engine.context, 0);
}
fn reference(engine: *js.Engine, child: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    if (scope.truthy(try scope.get(child, "_handle"))) _ = try scope.invoke(try scope.get(child, "_handle"), if (c.JS_ToBool(engine.context, roots[2]) == 1) "ref" else "unref", &.{});
    return c.pi_js_undefined();
}
fn dispose(engine: *js.Engine, child: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    if (!scope.truthy(try scope.get(child, "killed"))) _ = try scope.invoke(child, "kill", &.{});
    return c.pi_js_undefined();
}
fn abortAttempt(self: *Child, name: c.JSValue, cause: c.JSValue) !void {
    var scope: Scope = .{ .engine = self.engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    if (scope.truthy(try scope.invoke(self.child, "kill", &.{name}))) {
        const reason = try rawError(&scope, "The operation was aborted");
        try scope.put(reason, "name", try scope.text("AbortError")); try scope.put(reason, "code", try scope.text("ABORT_ERR"));
        if (c.JS_DefinePropertyValueStr(self.engine.context, reason, "cause", c.JS_DupValue(self.engine.context, cause), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return @as(anyerror!void, js.capture(self.engine));
        try emit(&scope, self.child, "error", &.{reason});
    }
}
fn abortTick(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const self = try capturedChild(engine, roots); var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    // onAbortListener evaluates reason before entering abortChildProcess's try.
    const cause = try scope.get(if (c.JS_IsUndefined(self.normalized_options)) self.signal else try scope.get(self.normalized_options, "signal"), "reason");
    const generation = engine.native_allocation_generation;
    abortAttempt(self, self.kill_argument, cause) catch |err| {
        if (err != error.JavaScriptException) return @as(anyerror!c.JSValue, err);
        const reason = engine.captured_exception orelse return @as(anyerror!c.JSValue, err);
        if (fnc.freshAllocation(engine, reason, generation)) { c.JS_SetUncatchableError(engine.context, reason); return @as(anyerror!c.JSValue, err); }
        if (c.JS_IsUncatchableError(reason)) return @as(anyerror!c.JSValue, err);
        // A handled ordinary kill exception transfers its one captured root.
        // Clear before emit: a new exception from emit owns a different exit.
        engine.captured_exception = null;
        const retained = try scope.own(reason); try emit(&scope, self.child, "error", &.{retained}); return c.pi_js_undefined();
    };
    return c.pi_js_undefined();
}
fn onExit(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const self = try capturedChild(engine, roots); var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const exit_code = options.arg(args, 0); const signal_code = options.arg(args, 1);
    self.exited = true;
    if (scope.truthy(signal_code)) try scope.set(self.child, "signalCode", signal_code) else try scope.set(self.child, "exitCode", exit_code);
    if (scope.truthy(try scope.get(self.child, "stdin"))) _ = try scope.invoke(try scope.get(self.child, "stdin"), "destroy", &.{});
    _ = try scope.invoke(try scope.get(self.child, "_handle"), "close", &.{});
    try scope.set(self.child, "_handle", c.pi_js_null());
    const negative = try frontier.binary(&scope, 4, exit_code, c.JS_NewInt32(engine.context, 0));
    if (scope.truthy(negative)) {
        const syscall = if (scope.truthy(try scope.get(self.child, "spawnfile"))) try scope.concat(try scope.text("spawn "), try scope.get(self.child, "spawnfile")) else try scope.text("spawn");
        var parameters = [_]c.JSValue{exit_code, syscall};
        const reason = try scope.construct(self.module.errno_exception, &parameters);
        if (scope.truthy(try scope.get(self.child, "spawnfile"))) try scope.set(reason, "path", try scope.get(self.child, "spawnfile"));
        try scope.set(reason, "spawnargs", try scope.call(self.module.primordials.array_slice, try scope.get(self.child, "spawnargs"), &.{c.JS_NewInt32(engine.context, 1)}));
        try emit(&scope, self.child, "error", &.{reason});
    } else try emit(&scope, self.child, "exit", &.{try scope.get(self.child, "exitCode"), try scope.get(self.child, "signalCode")});
    try tick(self, .flush); try closeCount(self);
    return c.pi_js_undefined();
}
fn nativeClose(engine: *js.Engine, handle: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const self = try capturedChild(engine, roots);
    if (!c.JS_IsStrictEqual(engine.context, handle, self.holder)) return error.NativeChildHandleOwnerMismatch;
    if (self.handle_closed) return c.pi_js_undefined();
    const callback = options.arg(args, 0);
    if (!c.JS_IsUndefined(callback) and !c.JS_IsFunction(engine.context, callback)) return @as(anyerror!c.JSValue, js.typeError(engine, "Process close callback must be a function"));
    // No worker/wait array borrows the public duplicate. Physical close is
    // observed here; Driver retains its independent actual wait/reap identity.
    self.handle_closed = true;
    if (self.native_ticket) |ticket| { self.native_ticket = null; try process_handle.close(ticket); }
    if (self.owner) |owner| try owner.referenceProcess(false);
    if (!c.JS_IsUndefined(callback)) try completions.enqueue(engine, callback, handle, &.{});
    if (self.driver) |driver| try requestCheckpoint(driver);
    return c.pi_js_undefined();
}
fn nativeKill(engine: *js.Engine, handle: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const self = try capturedChild(engine, roots);
    if (!c.JS_IsStrictEqual(engine.context, handle, self.holder)) return error.NativeChildHandleOwnerMismatch;
    const esrch: i32 = if (builtin.os.tag == .windows) -4040 else -3;
    if (self.handle_closed) return c.JS_NewInt32(engine.context, esrch);
    const driver = self.driver orelse return c.JS_NewInt32(engine.context, esrch);
    var number: i32 = 0; if (c.JS_ToInt32(engine.context, &number, options.arg(args, 0)) < 0) return @as(anyerror!c.JSValue, js.capture(engine));
    const sent = driver.signalNumber(number) catch |failure| return switch (failure) {
        error.PermissionDenied => c.JS_NewInt32(engine.context, if (builtin.os.tag == .windows) -4048 else -1),
        error.UnsupportedNativeChildKillSignal => c.JS_NewInt32(engine.context, if (builtin.os.tag == .windows) -4054 else -38),
        else => failure,
    };
    if (sent) self.sent_signal = if (number == 0) null else number;
    return c.JS_NewInt32(engine.context, if (sent) 0 else esrch);
}
fn nativeReference(engine: *js.Engine, handle: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const self = try capturedChild(engine, roots);
    if (!c.JS_IsStrictEqual(engine.context, handle, self.holder)) return error.NativeChildHandleOwnerMismatch;
    if (!self.handle_closed) if (self.owner) |owner| try owner.referenceProcess(c.JS_ToBool(engine.context, roots[2]) == 1);
    return c.pi_js_undefined();
}
fn timeoutAttempt(self: *Child) !void {
    var scope: Scope = .{ .engine = self.engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    _ = try scope.invoke(self.child, "kill", &.{self.kill_argument});
}
fn timeoutTick(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const self = try capturedChild(engine, roots); var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    if (!scope.truthy(self.timer)) return c.pi_js_undefined();
    const generation = engine.native_allocation_generation;
    timeoutAttempt(self) catch |err| {
        if (err != error.JavaScriptException) return @as(anyerror!c.JSValue, err);
        const reason = engine.captured_exception orelse return @as(anyerror!c.JSValue, err);
        if (fnc.freshAllocation(engine, reason, generation)) { c.JS_SetUncatchableError(engine.context, reason); return @as(anyerror!c.JSValue, err); }
        if (c.JS_IsUncatchableError(reason)) return @as(anyerror!c.JSValue, err);
        engine.captured_exception = null;
        const retained = try scope.own(reason); try emit(&scope, self.child, "error", &.{retained});
    };
    self.set(&self.timer, c.pi_js_null());
    return c.pi_js_undefined();
}
fn clearTimeoutTick(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const self = try capturedChild(engine, roots); var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    if (scope.truthy(self.timer)) {
        _ = try scope.call(self.module.clear_timeout, c.pi_js_undefined(), &.{self.timer});
        self.set(&self.timer, c.pi_js_null());
    }
    return c.pi_js_undefined();
}
fn installTimeout(self: *Child, milliseconds: ?u64) !void {
    const duration = milliseconds orelse return;
    return installTimeoutValue(self, c.JS_NewFloat64(self.engine.context, @floatFromInt(duration)));
}
fn installTimeoutValue(self: *Child, duration: c.JSValue) !void {
    var scope: Scope = .{ .engine = self.engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const roots = [_]c.JSValue{ self.holder, c.JS_NewUint32(self.engine.context, self.module.child_brand) };
    const callback = try scope.own(try fnc.createArrow(self.engine, "", 0, timeoutTick, &roots));
    const timer = try scope.call(self.module.set_timeout, c.pi_js_undefined(), &.{ callback, duration });
    self.set(&self.timer, timer);
    const clear = try scope.own(try fnc.createArrow(self.engine, "", 0, clearTimeoutTick, &roots));
    _ = try scope.invoke(self.child, "once", &.{ try scope.text("exit"), clear });
}
fn crossEmit(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const self = try capturedChild(engine, roots); var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    if (self.cross_missing and scope.equal(options.arg(args, 0), try scope.text("exit")) and scope.equal(options.arg(args, 1), c.JS_NewInt32(engine.context, 1))) {
        const file = try engine.toString(self.original_command); defer engine.gpa.free(file);
        const syscall = try std.fmt.allocPrint(engine.gpa, "spawn {s}", .{file}); defer engine.gpa.free(syscall);
        const reason = try scope.own(try systemError(engine, "ENOENT", 0, syscall, file, &.{}));
        // cross-spawn7.0.6 uses STRING errno and its actual original args array.
        try scope.set(reason, "errno", try scope.text("ENOENT")); try scope.set(reason, "spawnargs", self.original_args);
        return c.JS_DupValue(engine.context, try scope.call(self.original_emit, self.child, &.{ try scope.text("error"), reason }));
    }
    return c.JS_DupValue(engine.context, try scope.call(self.original_emit, self.child, args));
}
fn installAbort(self: *Child, signal: c.JSValue) !void {
    if (c.JS_IsUndefined(signal)) return;
    return installAbortActual(self, signal);
}
fn installAbortActual(self: *Child, signal: c.JSValue) !void {
    self.set(&self.signal, signal); var scope: Scope = .{ .engine = self.engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const listener = try scope.own(try fnc.create(self.engine, "onAbortListener", 0, abortTick, &.{ self.holder, c.JS_NewUint32(self.engine.context, self.module.child_brand) }));
    if (scope.truthy(try scope.get(signal, "aborted"))) { _ = try scope.invoke(self.module.process, "nextTick", &.{listener}); return; }
    const disposable = try scope.invoke(self.module.events, "addAbortListener", &.{ signal, listener }); self.set(&self.disposable, disposable);
    const dispose_callback = try frontier.getKey(&scope, disposable, self.module.dispose_symbol);
    _ = try scope.invoke(self.child, "once", &.{ try scope.text("exit"), dispose_callback });
}
const PlatformAttempt = if (builtin.os.tag == .linux) driver_api.Attempt else driver_api.OwnerBridge.Attempt;
fn launchAttempt(self: *Child, config: options.Config, hooks: driver_api.Hooks) !PlatformAttempt {
    if (builtin.os.tag == .linux) {
        const borrow = @import("native_child_process_public_handle_linux.zig").borrowParentRecovery(self.native_ticket.?) catch |failure| { var cleanup = config; cleanup.deinit(); return @as(anyerror!PlatformAttempt, failure); };
        defer borrow.release() catch @panic("native public parent recovery borrow lost ownership");
        return driver_api.startAttempt(self.engine, config, hooks, &.{self.holder}, borrow.recovery, self.module.linux_handshake_budget_ms);
    } else return driver_api.OwnerBridge.startAttempt(self.engine, config, hooks, &.{self.holder});
}
fn bindPublicHandle(self: *Child, driver: *driver_api.OwnerBridge) !void {
    if (builtin.os.tag == .linux) try process_handle.bind(self.native_ticket.?, &driver.transport.process.ticket)
    else try process_handle.bind(self.native_ticket.?, driver.transport.process.child.id.?);
}
fn spawnInto(self: *Child, owned: options.Config, signal: c.JSValue, native_phase: bool, records: ?*[3]?pipe_record.Owned) !void {
    var config = owned; var config_owned = true; defer if (config_owned) config.deinit();
    try frontier.pending(self.engine);
    if (self.started) return error.NativeChildAlreadySpawned;
    if (self.handle_closed) return error.NativePublicProcessHandleClosed;
    if (builtin.os.tag != .windows and builtin.os.tag != .linux) return error.RequiredNativePosixChildReadiness;
    self.native_ticket = try process_handle.reserve();
    var scope: Scope = .{ .engine = self.engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err); self.started = true;
    self.kill_signal = config.kill_number;
    if (!native_phase) try async_events.validateSignal(self.engine, signal, "options.signal");
    const spawn_file = config.spawn_file orelse config.argv.items[0];
    if (!native_phase) {
        try scope.set(self.child, "spawnfile", try scope.text(spawn_file));
        const argv = try scope.array(); for (config.argv.items, 0..) |value, index| try scope.index(argv, @intCast(index), try scope.text(value)); try scope.set(self.child, "spawnargs", argv);
    }
    const stdio_modes = config.options.stdio;
    const file = try self.engine.gpa.dupe(u8, spawn_file); defer self.engine.gpa.free(file);
    self.cross_missing = config.cross_missing;
    if (config.cross_hook) {
        self.set(&self.original_command, try scope.text(config.original_file));
    }
    var original_args: std.ArrayList([]const u8) = .empty; defer { for (original_args.items) |value| self.engine.gpa.free(value); original_args.deinit(self.engine.gpa); }
    for (config.argv.items[1..]) |value| { const copy = try self.engine.gpa.dupe(u8, value); original_args.append(self.engine.gpa, copy) catch |err| { self.engine.gpa.free(copy); return @as(anyerror!void, err); }; }
    // Capture before reserving the external Driver entitlement or transferring
    // Config. No fallible VM operation remains between that transfer and launch.
    try frontier.pending(self.engine);
    const mapper = try self.engine.gpa.create(ErrorContext); mapper.* = .{ .allocator = self.engine.gpa }; defer ErrorContext.release(mapper);
    _ = c.JS_DupValue(self.engine.context, self.holder); // external Driver context entitlement
    const owner = pipes.Owner.create(self.engine.gpa, .{ .context = self, .deliver = driverEvent, .poll = driverPoll, .stop = driverStop, .release = driverRelease }, .{ .context = mapper, .retain = ErrorContext.retain, .release = ErrorContext.release, .value = ErrorContext.value }) catch |err| { self.engine.freeValue(self.holder); return @as(anyerror!void, err); };
    self.owner = owner;
    config_owned = false;
    const native_generation = self.engine.native_allocation_generation;
    const attempt = launchAttempt(self, config, owner.hooks()) catch |err| {
        owner.releaseUnstarted(self.engine);
        const failure = try spawnError(self.engine, err, file, original_args.items); defer self.engine.freeValue(failure.value);
        if (failure.asynchronous) return error.NativeLaunchFailureWithoutRetainedEndpoints;
        try scope.set(self.child, "_handle", c.pi_js_null()); _ = try self.engine.checked(c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, failure.value))); return;
    };
    const driver = if (builtin.os.tag == .linux) switch (attempt) {
        .ready => |admitted| running: { self.spawn_errno = admitted.errno; break :running admitted.driver; },
        .host_failure => |failure| {
            if (failure.driver) |actual| { self.driver = actual; try owner.adoptDriver(actual); }
            else owner.releaseUnstarted(self.engine);
            _ = driver_api.retireHostFailure(failure) catch |cleanup_failure| failed: { self.native_cleanup_failure = cleanup_failure; break :failed null; };
            try driver_api.throwHostFailure(self.engine, native_generation);
            unreachable;
        },
    } else switch (attempt) {
        .running => |running| running,
        .failed => |admission| {
            var retained = admission; var admission_owned = true;
            defer if (admission_owned) retained.releaseUnattached(self.engine);
            owner.releaseUnstarted(self.engine);
            const failure = try spawnError(self.engine, retained.endpoints.failure, file, original_args.items); defer self.engine.freeValue(failure.value);
            if (!failure.asynchronous) { try scope.set(self.child, "_handle", c.pi_js_null()); _ = try self.engine.checked(c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, failure.value))); return; }
            self.spawn_errno = failure.errno; self.set(&self.spawn_failure, failure.value);
            _ = c.JS_DupValue(self.engine.context, self.holder); // failed owner context entitlement
            admission_owned = false;
            const endpoint_owner = if (native_phase)
                try FailedOwner.createBoundRecords(self.engine, retained, .{ .context = mapper, .retain = ErrorContext.retain, .release = ErrorContext.release, .value = ErrorContext.value }, .{ .context = self, .release = failedReleased }, records)
            else try FailedOwner.create(self.engine, retained, &self.module.sockets, .{ .context = mapper, .retain = ErrorContext.retain, .release = ErrorContext.release, .value = ErrorContext.value }, .{ .context = self, .release = failedReleased });
            self.failed_owner = endpoint_owner;
            errdefer endpoint_owner.abortAssembly();
            if (native_phase) { try scope.set(self.holder, "pid", c.pi_js_undefined()); return; }
            const stdio = try scope.array(); var closes: i32 = 1;
            for (stdio_modes, 0..) |_, index| {
                const stream = if (endpoint_owner.pipe(index)) |value| try scope.own(value) else c.pi_js_null();
                try scope.index(stdio, @intCast(index), stream); try scope.set(self.child, ([_][*:0]const u8{ "stdin", "stdout", "stderr" })[index], stream);
                if (index > 0 and scope.truthy(stream)) {
                    closes += 1; const listener = try scope.own(try fnc.createArrow(self.engine, "", 0, pipeClosed, &.{ self.holder, c.JS_NewUint32(self.engine.context, self.module.child_brand) }));
                    _ = try scope.invoke(stream, "on", &.{ try scope.text("close"), listener });
                }
            }
            try scope.set(self.child, "_closesNeeded", c.JS_NewInt32(self.engine.context, closes));
            try scope.set(self.child, "stdio", stdio); try scope.set(self.child, "pid", c.pi_js_undefined());
            try tick(self, .failure); return;
        },
    };
    self.driver = driver;
    errdefer owner.abortAssembly();
    if (builtin.os.tag == .linux) {
        try owner.adoptDriver(driver);
        if (self.spawn_errno != 0) self.failed_owner = owner;
    }
    if (native_phase) {
        try owner.bindRecords(driver, stdio_modes, records);
        if (self.spawn_errno == 0) try bindPublicHandle(self, driver);
        try scope.set(self.holder, "pid", if (self.spawn_errno == 0) c.JS_NewUint32(self.engine.context, driverPid(driver)) else c.pi_js_undefined()); return;
    }
    try owner.attach(driver, &self.module.sockets, stdio_modes);
    if (self.spawn_errno == 0) try bindPublicHandle(self, driver);
    const stdio = try scope.array(); var closes: i32 = 1;
    for (stdio_modes, 0..) |_, index| {
        const stream = if (owner.pipe(index)) |value| try scope.own(value) else c.pi_js_null();
        try scope.index(stdio, @intCast(index), stream); try scope.set(self.child, ([_][*:0]const u8{ "stdin", "stdout", "stderr" })[index], stream);
        if (index > 0 and scope.truthy(stream)) {
            closes += 1; const listener = try scope.own(try fnc.createArrow(self.engine, "", 0, pipeClosed, &.{ self.holder, c.JS_NewUint32(self.engine.context, self.module.child_brand) }));
            _ = try scope.invoke(stream, "on", &.{ try scope.text("close"), listener });
        }
    }
    try scope.set(self.child, "_closesNeeded", c.JS_NewInt32(self.engine.context, closes)); try scope.set(self.child, "stdio", stdio);
    try scope.set(self.child, "pid", if (self.spawn_errno == 0) c.JS_NewUint32(self.engine.context, driverPid(driver)) else c.pi_js_undefined());
    try tick(self, if (self.spawn_errno == 0) .spawn else .failure);
}
fn spawnCrossLegacy(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err); const module = try capturedModule(engine, roots);
    const normalized = try options.normalizePublic(engine, args, c.JS_ToBool(engine.context, roots[2]) == 1, module.process, module.array_slice);
    defer { engine.freeValue(normalized.signal); engine.freeValue(normalized.kill_signal); engine.freeValue(normalized.original_args); }
    var config = normalized.config;
    var transferred = false; defer if (!transferred) { var cleanup = config; cleanup.deinit(); };
    const signal = normalized.signal;
    try async_events.validateSignal(engine, signal, "options.signal");
    config.kill_number = try signalNumber(&scope, module, normalized.kill_signal); config.kill_force = config.kill_number == 9;
    const child = try scope.construct(module.constructor, &.{});
    const self = try getChild(&scope, module, child); self.set(&self.original_args, normalized.original_args);
    self.set(&self.kill_argument, if (c.JS_IsNull(normalized.kill_signal) or c.JS_IsUndefined(normalized.kill_signal)) c.pi_js_undefined() else c.JS_NewInt32(engine.context, config.kill_number));
    const timeout_ms = config.timeout_ms;
    config.timeout_ms = null; // Public policy invokes live child.kill via timer.
    const cross_hook = config.cross_hook;
    transferred = true; try spawnInto(self, config, signal, false, null);
    try installTimeout(self, timeout_ms); try installAbort(self, signal);
    // cross-spawn installs its own emit on every Windows child after the real
    // spawn call returns, even for found executables and explicit shell mode.
    if (cross_hook) {
        self.set(&self.original_emit, try scope.get(child, "emit"));
        const hook = try scope.own(try fnc.create(engine, "", 2, crossEmit, &.{ self.holder, c.JS_NewUint32(engine.context, module.child_brand) }));
        try scope.set(child, "emit", hook);
    }
    return c.JS_DupValue(engine.context, child);
}
fn validateTimeout(engine: *js.Engine, value: c.JSValue) !void {
    if (c.JS_IsNull(value) or c.JS_IsUndefined(value)) return;
    var number: f64 = 0;
    if (!c.JS_IsNumber(value)) return @import("node_events.zig").codedError(engine, "RangeError", "ERR_OUT_OF_RANGE", "The timeout must be an unsigned integer");
    if (c.JS_ToFloat64(engine.context, &number, value) < 0) return @as(anyerror!void, js.capture(engine));
    if (!std.math.isFinite(number) or number < 0 or @trunc(number) != number) return @import("node_events.zig").codedError(engine, "RangeError", "ERR_OUT_OF_RANGE", "The timeout must be an unsigned integer");
}
fn spawn(engine: *js.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    // The historical cross parser remains a separate unqualified boundary. The
    // genuine Node public path below never uses its typed normalization result.
    if (c.JS_ToBool(engine.context, roots[2]) == 1) return spawnCrossLegacy(engine, receiver, args, roots);
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const module = try capturedModule(engine, roots);
    const actual = try scope.own(try vm_options.normalize(engine, args, .{ .process = module.process, .primordials = module.primordials, .permission = module.permission }, &module.normalizer));
    try validateTimeout(engine, try scope.get(actual, "timeout"));
    try async_events.validateSignal(engine, try scope.get(actual, "signal"), "options.signal");
    const requested_signal = try scope.get(actual, "killSignal");
    if (!c.JS_IsNull(requested_signal) and !c.JS_IsUndefined(requested_signal) and !c.JS_IsString(requested_signal) and !c.JS_IsNumber(requested_signal)) return @import("node_events.zig").codedError(engine, "TypeError", "ERR_INVALID_ARG_TYPE", "The options.killSignal must be a string or number");
    // sanitizeKillSignal uses convertToValidSignal; only prototype.kill has the
    // separate successful-probe special case for numeric zero.
    if (c.JS_IsNumber(requested_signal) and scope.equal(requested_signal, c.JS_NewInt32(engine.context, 0))) return @import("node_events.zig").codedError(engine, "TypeError", "ERR_UNKNOWN_SIGNAL", "Unknown signal");
    const kill_number = try signalNumber(&scope, module, requested_signal);
    const kill_argument = if (c.JS_IsNull(requested_signal) or c.JS_IsUndefined(requested_signal)) c.pi_js_undefined() else c.JS_NewInt32(engine.context, kill_number);
    const child = try scope.construct(module.constructor, &.{});
    const self = try getChild(&scope, module, child);
    self.set(&self.kill_argument, kill_argument); self.kill_signal = kill_number;
    // Live lookup, actual receiver and ACTUAL normalized VM object. No native
    // launch occurs if the guest overrides this method and returns normally.
    _ = try scope.invoke(child, "spawn", &.{actual});
    const positive = try frontier.binary(&scope, 4, c.JS_NewInt32(engine.context, 0), try scope.get(actual, "timeout"));
    if (scope.truthy(positive)) try installTimeoutValue(self, try scope.get(actual, "timeout"));
    if (scope.truthy(try scope.get(actual, "signal"))) {
        self.set(&self.normalized_options, actual);
        try installAbortActual(self, try scope.get(actual, "signal"));
    }
    return c.JS_DupValue(engine.context, child);
}
/// Actual private Process.spawn callback: consumes current VM fields only here,
/// binds real endpoints and returns before the prototype constructs Sockets.
fn nativeSpawn(engine: *js.Engine, handle: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const self = try capturedChild(engine, roots);
    if (!c.JS_IsStrictEqual(engine.context, handle, self.holder)) return error.NativeChildHandleOwnerMismatch;
    var native = try vm_binding.consume(engine, options.arg(args, 0), .{ .pipes = &self.module.pipe_records, .inherited_environment = self.module.inherited_environment, .linux_stdio = self.module.linux_stdio, .windows_stdio = self.module.windows_stdio, .stdio_source = self.module.stdio_source });
    var config_owned = true;
    defer {
        for (&native.records) |*record| if (record.*) |*actual| { actual.deinit(); record.* = null; };
        if (config_owned) native.config.deinit();
    }
    native.config.timeout_ms = null;
    config_owned = false;
    try spawnInto(self, native.config, c.pi_js_undefined(), true, &native.records);
    return c.JS_NewInt32(engine.context, self.spawn_errno);
}
fn spawnInstance(engine: *js.Engine, child: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const module = try capturedModule(engine, roots); const self = try getChild(&scope, module, child);
    const supplied = options.arg(args, 0);
    if (!c.JS_IsObject(supplied) or c.JS_IsNull(supplied) or c.JS_IsArray(supplied) or c.JS_IsFunction(engine.context, supplied)) return @as(anyerror!c.JSValue, js.typeError(engine, "ChildProcess spawn options must be an object"));
    const requested = try scope.get(supplied, "stdio");
    const normalized = try scope.own(try stdio_vm.normalize(engine, if (scope.truthy(requested)) requested else try scope.text("pipe"), .{ .pipes = &module.pipe_records, .array_push = module.primordials.array_push, .array_reduce = module.array_reduce, .is_view = module.is_view }));
    const ipc = try scope.get(normalized, "ipc"); _ = try scope.get(normalized, "ipcFd");
    const descriptors = try scope.get(normalized, "stdio");
    try scope.set(supplied, "stdio", descriptors);
    const serialization = try scope.get(supplied, "serialization");
    if (!c.JS_IsUndefined(serialization) and !scope.equal(serialization, try scope.text("json")) and !scope.equal(serialization, try scope.text("advanced"))) return @import("node_events.zig").codedError(engine, "TypeError", "ERR_INVALID_ARG_VALUE", "The options.serialization must be json or advanced");
    // Source initializes its local serialization even without an IPC channel.
    _ = try scope.get(supplied, "serialization");
    if (!c.JS_IsUndefined(ipc)) return error.RequiredGenuineNativeIpcPipeProvider;
    if (!c.JS_IsString(try scope.get(supplied, "file"))) return @as(anyerror!c.JSValue, js.typeError(engine, "The options.file must be a string"));
    try scope.set(child, "spawnfile", try scope.get(supplied, "file"));
    if (c.JS_IsUndefined(try scope.get(supplied, "args"))) try scope.set(child, "spawnargs", try scope.array()) else {
        if (!c.JS_IsArray(try scope.get(supplied, "args"))) return @as(anyerror!c.JSValue, js.typeError(engine, "The options.args must be an Array"));
        try scope.set(child, "spawnargs", try scope.get(supplied, "args"));
    }
    const result = try scope.invoke(try scope.get(child, "_handle"), "spawn", &.{supplied});
    const asynchronous = scope.equal(result, c.JS_NewInt32(engine.context, if (builtin.os.tag == .windows) -4058 else -2)) or scope.equal(result, c.JS_NewInt32(engine.context, if (builtin.os.tag == .windows) -4092 else -13)) or scope.equal(result, c.JS_NewInt32(engine.context, if (builtin.os.tag == .windows) -4088 else -11)) or scope.equal(result, c.JS_NewInt32(engine.context, if (builtin.os.tag == .windows) -4066 else -24)) or scope.equal(result, c.JS_NewInt32(engine.context, if (builtin.os.tag == .windows) -4061 else -23));
    if (asynchronous) {
        // Pass actual returned errno; a wrapper can return a different value.
        _ = try scope.invoke(module.process, "nextTick", &.{ module.tick_helpers[1], child, result });
        if (scope.equal(result, c.JS_NewInt32(engine.context, if (builtin.os.tag == .windows) -4066 else -24)) or scope.equal(result, c.JS_NewInt32(engine.context, if (builtin.os.tag == .windows) -4061 else -23))) return c.JS_DupValue(engine.context, result);
    } else if (scope.truthy(result)) {
        var index: f64 = 0;
        while (true) : (index += 1) {
            var row: Scope = .{ .engine = engine }; defer row.deinit(); errdefer |err| row.captureUnwind(err);
            if (!row.truthy(try frontier.binary(&row, 4, c.JS_NewFloat64(engine.context, index), try row.get(descriptors, "length")))) break;
            try flushInterrupt(engine);
            const descriptor = try frontier.getKey(&row, descriptors, c.JS_NewFloat64(engine.context, index));
            if (row.equal(try row.get(descriptor, "type"), try row.text("pipe"))) _ = try row.invoke(try row.get(descriptor, "handle"), "close", &.{});
        }
        _ = try scope.invoke(try scope.get(child, "_handle"), "close", &.{}); try scope.set(child, "_handle", c.pi_js_null());
        var parameters = [_]c.JSValue{result, try scope.text("spawn")};
        const reason = try scope.construct(module.errno_exception, &parameters);
        return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
    } else try tick(self, .spawn);
    try scope.set(child, "pid", try scope.get(try scope.get(child, "_handle"), "pid"));
    // This is the actual Source descriptor array, re-read live after the native
    // callback. Pipe handles choose their own owner subscriber, never an index
    // recovered from a stale Config sidecar.
    var index: f64 = 0;
    while (true) : (index += 1) {
        var row: Scope = .{ .engine = engine }; defer row.deinit(); errdefer |err| row.captureUnwind(err);
        if (!row.truthy(try frontier.binary(&row, 4, c.JS_NewFloat64(engine.context, index), try row.get(descriptors, "length")))) break;
        try flushInterrupt(engine);
        const descriptor = try frontier.getKey(&row, descriptors, c.JS_NewFloat64(engine.context, index));
        if (row.equal(try row.get(descriptor, "type"), try row.text("ignore"))) continue;
        if (row.truthy(try row.get(descriptor, "ipc"))) return error.RequiredGenuineNativeIpcPipeProvider;
        if (row.equal(try row.get(descriptor, "type"), try row.text("wrap"))) return error.RequiredActualWrappedEndpointDuplication;
        if (row.truthy(try row.get(descriptor, "handle"))) {
            const handle = if (!row.equal(try row.get(child, "pid"), c.JS_NewInt32(engine.context, 0))) try row.get(descriptor, "handle") else c.pi_js_null();
            const socket_constructor = try row.get(module.net, "Socket");
            const settings = try row.object();
            try row.put(settings, "handle", handle); try row.put(settings, "readable", c.pi_js_bool(engine.context, @intFromBool(index > 0)));
            const current_socket = try row.call(socket_constructor, module.net, &.{settings});
            var actual = try module.sockets.own(current_socket); defer actual.deinit();
            try frontier.pending(engine);
            if (c.JS_GetOpaque(handle, module.pipe_records.brand) != null) try module.pipe_records.attachSocket(handle, &actual);
            try row.set(descriptor, "socket", actual.socket);
            if (index > 0 and !row.equal(try row.get(child, "pid"), c.JS_NewInt32(engine.context, 0))) {
                const old = try row.get(child, "_closesNeeded");
                try row.set(child, "_closesNeeded", try frontier.increment(&row, old));
                const listener = try row.own(try fnc.createArrow(engine, "", 0, pipeClosed, &.{self.holder, c.JS_NewUint32(engine.context, module.child_brand)}));
                _ = try row.invoke(try row.get(descriptor, "socket"), "on", &.{try row.text("close"), listener});
            }
        }
    }
    inline for (.{"stdin", "stdout", "stderr"}, 0..) |name, slot| {
        const enough = try frontier.binary(&scope, 7, try scope.get(descriptors, "length"), c.JS_NewInt32(engine.context, slot + 1));
        var value = c.pi_js_null();
        if (scope.truthy(enough)) {
            const entry = try scope.getIndex(descriptors, slot);
            if (!c.JS_IsUndefined(try scope.get(entry, "socket"))) value = try scope.get(entry, "socket");
        }
        try scope.set(child, name, value);
    }
    try scope.set(child, "stdio", try scope.array());
    index = 0;
    while (true) : (index += 1) {
        var row: Scope = .{ .engine = engine }; defer row.deinit(); errdefer |err| row.captureUnwind(err);
        if (!row.truthy(try frontier.binary(&row, 4, c.JS_NewFloat64(engine.context, index), try row.get(descriptors, "length")))) break;
        try flushInterrupt(engine);
        const entry = try frontier.getKey(&row, descriptors, c.JS_NewFloat64(engine.context, index));
        const value = if (c.JS_IsUndefined(try row.get(entry, "socket"))) c.pi_js_null() else try row.get(entry, "socket");
        _ = try row.call(module.primordials.array_push, try row.get(child, "stdio"), &.{value});
    }
    return c.JS_DupValue(engine.context, result);
}
fn select(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var index: u32 = 0; if (c.JS_ToUint32(engine.context, &index, options.arg(args, 0)) < 0) return @as(anyerror!c.JSValue, js.capture(engine));
    if (index >= roots.len) return error.NativeChildNamespaceSelection; return c.JS_DupValue(engine.context, roots[index]);
}
pub fn create(engine: *js.Engine, inputs: Inputs) !Bundle {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    try frontier.pending(engine);
    var invocation: js.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    const result = createInner(engine, inputs) catch |err| {
        const failure = fnc.directFailure(engine, err, generation);
        _ = engine.checked(engine.leaveNativeInvocation(&invocation, c.pi_js_undefined())) catch |actual| return @as(anyerror!Bundle, actual);
        return @as(anyerror!Bundle, failure);
    };
    _ = engine.checked(engine.leaveNativeInvocation(&invocation, c.pi_js_undefined())) catch |actual| { result.deinit(engine); return @as(anyerror!Bundle, actual); };
    return result;
}
fn createInner(engine: *js.Engine, inputs: Inputs) !Bundle {
    // Even cached public calls must validate the same genuine process/stream
    // graph. No fallback constructor/carrier can diverge from TTY's provider.
    const shared = try canonical.acquire(engine, inputs.streams, inputs.process);
    try frontier.pending(engine);
    if (inputs.socket_provider) |provided| {
        if (provided.engine != engine or provided.adopters != shared.provider.adopters or
            !c.JS_IsStrictEqual(engine.context, provided.constructor, shared.provider.constructor) or
            !c.JS_IsStrictEqual(engine.context, provided.states, shared.provider.states)) return error.NativeChildCanonicalSocketMismatch;
    }
    if (engine.native_module_values.get(cache_key)) |selector| {
        var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
        var values: [4]c.JSValue = undefined; var count: usize = 0;
        errdefer for (values[0..count]) |value| engine.freeValue(value);
        for (&values, 0..) |*value, index| { value.* = c.JS_DupValue(engine.context, try scope.call(selector, c.pi_js_undefined(), &.{c.JS_NewInt32(engine.context, @intCast(index))})); count += 1; }
        const context: *Module = @ptrCast(@alignCast(c.JS_GetOpaque(values[3], c.JS_GetClassID(values[3])) orelse return error.NativeChildModuleBrand));
        if (context.engine != engine or !c.JS_IsStrictEqual(engine.context, values[2], shared.net)) return error.NativeChildCanonicalSocketMismatch;
        engine.freeValue(values[3]); count = 3;
        return .{ .node = values[0], .cross_spawn = values[1], .net = values[2], .context = context };
    }
    var cursor = initializing; while (cursor) |prior| : (cursor = prior.previous) if (prior.engine == engine) return error.NativeChildInitializationInProgress;
    var entry: Entry = .{ .engine = engine, .previous = initializing }; initializing = &entry; defer initializing = entry.previous;
    try @import("node_events.zig").install(engine);
    try frontier.pending(engine);
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const module_brand = try register(engine, "Native child module context", moduleFinalizer, moduleMark);
    const child_brand = try register(engine, "Owned native ChildProcess", childFinalizer, childMark);
    const holder = try scope.own(try engine.checked(c.JS_NewObjectClass(engine.context, module_brand)));
    var sockets = try shared.provider.clone(engine);
    var sockets_owned = true; defer if (sockets_owned) sockets.deinit();
    errdefer |err| scope.captureUnwind(err);
    try frontier.pending(engine);
    var pipe_records = try pipe_record.createProvider(engine); var pipe_records_owned = true; defer if (pipe_records_owned) pipe_records.deinit();
    try frontier.pending(engine);
    var primordials = inputs.primordials;
    inline for (std.meta.fields(vm_options.Primordials)) |field| @field(primordials, field.name) = c.JS_DupValue(engine.context, @field(inputs.primordials, field.name));
    var primordials_owned = true;
    defer if (primordials_owned) { inline for (std.meta.fields(vm_options.Primordials)) |field| engine.freeValue(@field(primordials, field.name)); };
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(Module)) == 0) return error.OutOfMemory;
    var module_attached = false; errdefer if (!module_attached) c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Module));
    const module = try engine.gpa.create(Module);
    const events = engine.native_module_values.get("node:events").?;
    module.* = .{ .engine = engine, .sockets = sockets, .net = c.JS_DupValue(engine.context, shared.net), .process = c.JS_DupValue(engine.context, inputs.process), .signals = c.JS_DupValue(engine.context, inputs.signals), .events = c.JS_DupValue(engine.context, events), .array_slice = c.JS_DupValue(engine.context, inputs.array_prototype_slice), .signal_upper = c.JS_DupValue(engine.context, inputs.string_prototype_to_upper_case), .set_timeout = c.pi_js_undefined(), .clear_timeout = c.pi_js_undefined(), .emitter = c.pi_js_undefined(), .children = c.pi_js_undefined(), .constructor = c.pi_js_undefined(), .dispose_symbol = c.pi_js_undefined(), .child_brand = child_brand, .pipe_records = pipe_records, .primordials = primordials, .permission = inputs.permission, .array_reduce = c.JS_DupValue(engine.context, inputs.array_prototype_reduce), .is_view = c.JS_DupValue(engine.context, inputs.array_buffer_is_view), .errno_exception = c.JS_DupValue(engine.context, inputs.errno_exception), .inherited_environment = inputs.inherited_environment, .linux_handshake_budget_ms = inputs.linux_handshake_budget_ms, .linux_stdio = inputs.linux_stdio, .windows_stdio = inputs.windows_stdio, .stdio_source = inputs.stdio_source, .tick_helpers = .{ c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined() } };
    _ = c.JS_SetOpaque(holder, module); module_attached = true; sockets_owned = false; pipe_records_owned = false; primordials_owned = false;
    module.set_timeout = c.JS_DupValue(engine.context, try scope.get(inputs.timers, "setTimeout")); module.clear_timeout = c.JS_DupValue(engine.context, try scope.get(inputs.timers, "clearTimeout"));
    module.emitter = c.JS_DupValue(engine.context, try scope.get(events, "EventEmitter"));
    const weak_map = try scope.global("WeakMap");
    module.children = c.JS_DupValue(engine.context, try scope.construct(weak_map, &.{}));
    module.dispose_symbol = c.JS_DupValue(engine.context, try scope.get(try scope.global("Symbol"), "dispose"));
    const roots = [_]c.JSValue{ holder, c.JS_NewUint32(engine.context, module_brand) };
    module.tick_helpers[0] = try fnc.create(engine, "onSpawnNT", 1, spawnTick, &roots);
    module.tick_helpers[1] = try fnc.create(engine, "onErrorNT", 2, failureTick, &roots);
    module.tick_helpers[2] = try fnc.create(engine, "flushStdio", 1, flushTick, &roots);
    const constructor = try scope.own(try fnc.create(engine, "ChildProcess", 0, construct, &roots));
    module.constructor = c.JS_DupValue(engine.context, constructor);
    const prototype = try scope.get(constructor, "prototype");
    if (c.JS_SetPrototype(engine.context, constructor, module.emitter) < 0 or c.JS_SetPrototype(engine.context, prototype, try scope.get(module.emitter, "prototype")) < 0) return @as(anyerror!Bundle, js.capture(engine));
    try scope.put(prototype, "kill", try scope.own(try fnc.create(engine, "kill", 1, kill, &roots)));
    try scope.put(prototype, "spawn", try scope.own(try fnc.create(engine, "spawn", 1, spawnInstance, &roots)));
    inline for (.{ "ref", "unref" }, .{ true, false }) |name, value| try scope.put(prototype, name, try scope.own(try fnc.create(engine, name, 0, reference, &.{ roots[0], roots[1], c.pi_js_bool(engine.context, @intFromBool(value)) })));
    try js.setKey(engine, prototype, module.dispose_symbol, try scope.own(try fnc.create(engine, "", 0, dispose, &.{})));
    var namespaces: [4]c.JSValue = undefined;
    for (0..2) |index| {
        const flag = c.pi_js_bool(engine.context, @intFromBool(index == 1));
        const spawn_function = try scope.own(try fnc.create(engine, "spawn", 3, spawn, &.{ roots[0], roots[1], flag }));
        const namespace = if (index == 1) spawn_function else try scope.object(); namespaces[index] = namespace;
        try scope.put(namespace, "ChildProcess", constructor); try scope.put(namespace, "spawn", spawn_function);
        try scope.put(namespace, "spawnSync", try scope.own(try fnc.create(engine, "spawnSync", 3, legacy.spawnSync, &.{flag})));
        try scope.put(namespace, "execSync", try scope.own(try fnc.create(engine, "execSync", 2, legacy.execSync, &.{})));
        if (index == 1) try scope.put(namespace, "sync", try scope.get(namespace, "spawnSync"));
    }
    namespaces[2] = shared.net; namespaces[3] = holder;
    const selector = try scope.own(try fnc.createArrow(engine, "", 1, select, &namespaces));
    var commit: Scope = .{ .engine = engine }; defer commit.deinit(); errdefer |err| commit.captureUnwind(err);
    const retained = try commit.own(c.JS_DupValue(engine.context, selector));
    // Retire EVERY fallible/guest temporary before the last adopter commit.
    // retained owns the real selector graph while those roots are released.
    scope.deinit(); scope = .{ .engine = engine }; try frontier.pending(engine);
    const cached = c.JS_DupValue(engine.context, retained);
    engine.native_module_values.put(engine.gpa, cache_key, cached) catch |err| { engine.freeValue(cached); return @as(anyerror!Bundle, err); };
    errdefer { if (engine.native_module_values.fetchRemove(cache_key)) |removed| engine.freeValue(removed.value); }
    errdefer |err| commit.captureUnwind(err);
    // Native-only atomic admission: no callback/allocation/VM call after this.
    try module.pipe_records.registerWithSocket(&module.sockets, holder);
    return .{ .node = c.JS_DupValue(engine.context, namespaces[0]), .cross_spawn = c.JS_DupValue(engine.context, namespaces[1]), .net = c.JS_DupValue(engine.context, shared.net), .context = module };
}
/// Explicit, unselected registration seam. Caller must provide genuine stream,
/// process and platform signal namespaces and qualify the complete graph first.
pub fn install(engine: *js.Engine, inputs: Inputs) !void {
    const bundle = try create(engine, inputs); defer bundle.deinit(engine);
    try publication.install(engine, &bundle.context.publication, bundle.node, bundle.net);
}

test "direct public create owns incoming pending completion before reading inputs" {
    const engine = try js.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const reason = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(reason);
    engine.captured_exception = c.JS_NewInt32(engine.context, 41);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
    // Inputs must remain unread: this entry already has a real pending reason.
    try std.testing.expectError(error.JavaScriptException, create(engine, undefined));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, reason));
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    const captured = engine.captured_exception.?; engine.captured_exception = null; engine.freeValue(captured);
}
