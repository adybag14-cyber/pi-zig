//! Real native Node child_process bootstrap closure. Synchronous pipe transport
//! and ignored-stdio ChildProcess events are concrete. Piped async spawning and
//! inherited frontend stdio stay explicit dependencies until real Node streams
//! and frontend routing are ported; no EventEmitter is relabelled as a stream.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const c = js.c;
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const functions = @import("native_node_function.zig");
const class = @import("native_class.zig");
const options = @import("native_child_process_options.zig");
const sync = @import("native_child_process_sync.zig");
const transport = @import("native_child_process_transport.zig");
const hub = @import("native_env_io.zig");
const State = struct { engine: *js.Engine, child: c.JSValue, task: ?*Task = null };
// Engine's module-value map is reachable through CommonJS, even for NUL keys.
// This cache contains only a selector for the two public namespaces. The known
// handle class ID lives solely in immutable native function captures below.
const namespace_cache_key = "\x00native-child-process-namespace-selector";
fn finalizer(runtime: ?*c.JSRuntime, holder_value: c.JSValue) callconv(.c) void {
    // This callback is invoked only by the class definition registered below;
    // public values never select the finalizer or its State representation.
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder_value, c.JS_GetClassID(holder_value)) orelse return));
    std.debug.assert(state.task == null);
    c.JS_FreeValueRT(runtime, state.child);
    state.engine.gpa.destroy(state);
}
fn marker(runtime: ?*c.JSRuntime, holder_value: c.JSValue, mark: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder_value, c.JS_GetClassID(holder_value)) orelse return));
    c.JS_MarkValue(runtime, state.child, mark);
}
fn registerHandleClass(engine: *js.Engine) !c.JSClassID {
    var id: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &id);
    const definition: c.JSClassDef = .{ .class_name = "Owned native ChildProcess handle", .finalizer = finalizer, .gc_mark = marker };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    return id;
}
fn capturedHandleClass(engine: *js.Engine, value: c.JSValue) !c.JSClassID {
    var id: u32 = 0;
    if (c.JS_ToUint32(engine.context, &id, value) < 0) return js.capture(engine);
    return id;
}
fn holder(scope: *Scope, child: c.JSValue, id: c.JSClassID) !c.JSValue {
    const value = try scope.own(try scope.engine.checked(c.JS_NewObjectClass(scope.engine.context, id)));
    const state = try scope.engine.gpa.create(State);
    state.* = .{ .engine = scope.engine, .child = c.JS_DupValue(scope.engine.context, child) };
    _ = c.JS_SetOpaque(value, state);
    return value;
}
fn getState(engine: *js.Engine, child: c.JSValue, expected: c.JSClassID) !?*State {
    const handle = try js.get(engine, child, "_handle"); defer engine.freeValue(handle);
    if (c.JS_IsNull(handle) or c.JS_IsUndefined(handle)) return null;
    if (!c.JS_IsObject(handle) or c.JS_GetClassID(handle) != expected) return js.typeError(engine, "ChildProcess _handle must retain its original owned native handle");
    const raw = c.JS_GetOpaque(handle, expected) orelse return js.typeError(engine, "Invalid owned ChildProcess handle");
    const state: *State = @ptrCast(@alignCast(raw));
    if (state.engine != engine or !c.JS_IsStrictEqual(engine.context, state.child, child)) return js.typeError(engine, "ChildProcess handle belongs to another owner");
    return state;
}
fn construct(engine: *js.Engine, target: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    const child = try scope.own(try class.object(engine, target));
    _ = try scope.call(roots[0], child, &.{});
    try scope.put(child, "_closesNeeded", c.JS_NewInt32(engine.context, 1));
    try scope.put(child, "_closesGot", c.JS_NewInt32(engine.context, 0));
    try scope.put(child, "connected", c.pi_js_bool(engine.context, 0));
    try scope.put(child, "signalCode", c.pi_js_null()); try scope.put(child, "exitCode", c.pi_js_null());
    try scope.put(child, "killed", c.pi_js_bool(engine.context, 0));
    try scope.put(child, "spawnfile", c.pi_js_null()); try scope.put(child, "_handle", try holder(&scope, child, try capturedHandleClass(engine, roots[1])));
    return c.JS_DupValue(engine.context, child);
}
fn kill(engine: *js.Engine, child: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const signal = options.arg(args, 0);
    var force = false;
    if (!c.JS_IsUndefined(signal)) {
        const name = try engine.toString(signal); defer engine.gpa.free(name);
        if (std.mem.eql(u8, name, "SIGKILL") or std.mem.eql(u8, name, "9")) force = true else if (!std.mem.eql(u8, name, "SIGTERM") and !std.mem.eql(u8, name, "15")) return error.UnsupportedNativeChildKillSignal;
    }
    const state = (try getState(engine, child, try capturedHandleClass(engine, roots[0]))) orelse return c.pi_js_bool(engine.context, 0);
    const task = state.task orelse return c.pi_js_bool(engine.context, 0);
    const sent = if (task.process) |*process| process.signal(force) else false;
    if (sent) { task.sent_signal = if (force) 9 else 15; try js.define(engine, child, "killed", c.pi_js_bool(engine.context, 1)); }
    return c.pi_js_bool(engine.context, @intFromBool(sent));
}
fn noop(_: *js.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return c.pi_js_undefined(); }
fn uncaught(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, options.arg(args, 0)))); }
const Task = struct {
    task: hub.Task,
    child: c.JSValue,
    handle: c.JSValue,
    state: *State,
    process: ?transport.Process,
    config: options.Config,
    control: transport.Control = .{},
    result: ?transport.Result = null,
    failure: ?anyerror = null,
    sent_signal: ?u32 = null,
    fn discard(_: *anyopaque, _: transport.Stream, _: []const u8) !void { return error.UnexpectedIgnoredChildPipe; }
    fn work(base: *hub.Task) void {
        const self: *Task = @alignCast(@fieldParentPtr("task", base));
        if (self.process) |*process| self.result = process.run(base.hub.io, &self.control, .{ .context = self, .write = discard }, self.config.input orelse &.{}) catch |err| failed: { self.failure = err; break :failed null; };
        base.finish();
    }
    fn complete(base: *hub.Task) !void {
        const self: *Task = @alignCast(@fieldParentPtr("task", base));
        const engine = base.hub.engine;
        self.state.task = null;
        var scope: Scope = .{ .engine = engine }; defer scope.deinit();
        try scope.set(self.child, "_handle", c.pi_js_null());
        if (self.failure) |err| {
            const reason = try sync.errorValue(&scope, err, &self.config, false);
            _ = try scope.invoke(self.child, "emit", &.{ try scope.text("error"), reason });
            _ = try scope.invoke(self.child, "emit", &.{ try scope.text("close"), c.pi_js_null(), c.pi_js_null() });
            return;
        }
        const result = self.result orelse return error.NativeChildMissingExit;
        const signal_number: ?u32 = result.signal orelse self.sent_signal orelse if (self.control.timed_out and self.control.signal_sent.load(.acquire)) @as(u32, if (self.config.kill_force) 9 else 15) else null;
        const signal = if (signal_number) |number| try scope.text(if (number == 9) "SIGKILL" else "SIGTERM") else c.pi_js_null();
        const status = if (signal_number != null) c.pi_js_null() else c.JS_NewInt64(engine.context, result.code);
        if (self.control.timed_out and signal_number != null) try scope.set(self.child, "killed", c.pi_js_bool(engine.context, 1));
        try scope.set(self.child, "exitCode", status); try scope.set(self.child, "signalCode", signal);
        _ = try scope.invoke(self.child, "emit", &.{ try scope.text("exit"), status, signal });
        _ = try scope.invoke(self.child, "emit", &.{ try scope.text("close"), status, signal });
    }
    fn cancel(base: *hub.Task) void { const self: *Task = @alignCast(@fieldParentPtr("task", base)); self.control.shutdown.store(true, .release); }
    fn destroy(base: *hub.Task) void {
        const self: *Task = @alignCast(@fieldParentPtr("task", base));
        self.state.task = null;
        self.config.deinit(); base.releaseFunctions();
        base.hub.engine.freeValue(self.child); base.hub.engine.freeValue(self.handle);
        base.hub.engine.gpa.destroy(self);
    }
};
fn spawn(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const cross = c.JS_ToBool(engine.context, roots[1]) == 1;
    var config = try options.normalize(engine, args, false, cross);
    var config_owned = true; defer if (config_owned) config.deinit();
    if (builtin.os.tag != .windows) _ = try config.environment.posixMap();
    // A real Node stream implementation must own async pipe objects. Frontend
    // EventEmitter records and WHATWG streams are not substitutes for it.
    for (config.options.stdio) |mode| if (mode != .ignore) return error.RequiredGenuineNativeNodeChildStreams;
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    const supplied_args = options.arg(args, 1);
    const supplied_options = if (!c.JS_IsUndefined(supplied_args) and !c.JS_IsNull(supplied_args) and !c.JS_IsArray(supplied_args)) supplied_args else options.arg(args, 2);
    if (!c.JS_IsUndefined(supplied_options) and !c.JS_IsNull(supplied_options)) {
        const signal = try scope.get(supplied_options, "signal");
        if (!c.JS_IsUndefined(signal) and !c.JS_IsNull(signal)) return error.NativeChildAbortIntegrationRequired;
    }
    const child = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, roots[0], 0, null)));
    const handle = try scope.get(child, "_handle");
    const state = (try getState(engine, child, try capturedHandleClass(engine, roots[2]))).?;
    try scope.put(child, "spawnfile", try scope.text(config.original_file));
    const arguments = try scope.array();
    for (config.argv.items, 0..) |value, index| try scope.index(arguments, @intCast(index), try scope.text(if (index == 0) config.original_file else value));
    try scope.put(child, "spawnargs", arguments);
    inline for (.{ "stdin", "stdout", "stderr" }) |name| try scope.put(child, name, c.pi_js_null());
    const stdio = try scope.array(); inline for (0..3) |index| try scope.index(stdio, index, c.pi_js_null()); try scope.put(child, "stdio", stdio);
    const owner = try hub.get(engine);
    var failure: ?anyerror = null;
    var process: ?transport.Process = transport.Process.spawn(owner.io, engine.gpa, config.argv.items, config.cwd, &config.environment, config.options) catch |err| failed: { if (err == error.OutOfMemory) return err; failure = err; break :failed null; };
    var process_owned = true; defer if (process_owned) if (process) |*value| value.deinit(owner.io);
    if (process) |value| try scope.put(child, "pid", c.JS_NewUint32(engine.context, value.identity.pid));
    const resolve = try scope.own(try functions.createArrow(engine, "", 1, noop, &.{}));
    const reject = try scope.own(try functions.createArrow(engine, "", 1, uncaught, &.{}));
    const task = try engine.gpa.create(Task);
    task.* = .{ .task = .{ .hub = owner, .work = Task.work, .complete = Task.complete, .destroy = Task.destroy, .cancel = Task.cancel, .resolve = c.JS_DupValue(engine.context, resolve), .reject = c.JS_DupValue(engine.context, reject) }, .child = c.JS_DupValue(engine.context, child), .handle = c.JS_DupValue(engine.context, handle), .state = state, .process = process, .config = config, .failure = failure, .control = .{ .timeout_ms = config.timeout_ms, .kill_force = config.kill_force } };
    config_owned = false; process_owned = false;
    errdefer { if (task.process) |*value| value.deinit(owner.io); Task.destroy(&task.task); }
    state.task = task;
    try owner.submit(&task.task);
    return c.JS_DupValue(engine.context, child);
}
pub fn spawnSync(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var config = try options.normalize(engine, args, false, c.JS_ToBool(engine.context, roots[0]) == 1);
    defer config.deinit();
    return sync.run(engine, &config);
}
pub fn execSync(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var config = try options.normalize(engine, args, true, false); defer config.deinit();
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    const result = try scope.own(try sync.run(engine, &config));
    const reason = try scope.get(result, "error");
    if (!c.JS_IsUndefined(reason)) { try js.spreadInto(engine, reason, result); return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason))); }
    if (!c.JS_IsStrictEqual(engine.context, try scope.get(result, "status"), c.JS_NewInt32(engine.context, 0))) {
        const stderr = try scope.get(result, "stderr");
        const detail = if (c.JS_IsNull(stderr)) try engine.gpa.dupe(u8, "") else try engine.toString(stderr); defer engine.gpa.free(detail);
        const message = try std.fmt.allocPrint(engine.gpa, "Command failed: {s}{s}{s}", .{ config.original_file, if (detail.len != 0) "\n" else "", detail }); defer engine.gpa.free(message);
        const error_value = try scope.own(try js.builtin(engine, "Error", &.{try scope.text(message)}));
        try js.spreadInto(engine, error_value, result);
        return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, error_value)));
    }
    return c.JS_DupValue(engine.context, try scope.get(result, "stdout"));
}
fn selectNamespace(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return c.JS_DupValue(engine.context, roots[if (c.JS_ToBool(engine.context, options.arg(args, 0)) == 1) @as(usize, 1) else 0]);
}
pub fn create(engine: *js.Engine, cross_spawn: bool) !c.JSValue {
    const selection = c.pi_js_bool(engine.context, @intFromBool(cross_spawn));
    if (engine.native_module_values.get(namespace_cache_key)) |selector| return engine.checked(c.JS_Call(engine.context, selector, c.pi_js_undefined(), 1, &.{selection}));
    try @import("node_events.zig").install(engine); try @import("node_buffer.zig").install(engine);
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    const known_class = c.JS_NewUint32(engine.context, try registerHandleClass(engine));
    const constructor = constructor: {
        const emitter = try scope.get(engine.native_module_values.get("node:events").?, "EventEmitter");
        const prototype = try scope.object();
        if (c.JS_SetPrototype(engine.context, prototype, try scope.get(emitter, "prototype")) < 0) return js.capture(engine);
        const value = try scope.own(try class.constructor(engine, "ChildProcess", 0, prototype, construct, &.{ emitter, known_class }));
        try scope.put(prototype, "kill", try scope.own(try functions.create(engine, "kill", 1, kill, &.{known_class})));
        break :constructor value;
    };
    const exec = try scope.own(try functions.create(engine, "execSync", 2, execSync, &.{}));
    var namespaces: [2]c.JSValue = undefined;
    for (&namespaces, 0..) |*namespace, index| {
        namespace.* = try scope.object();
        const flag = c.pi_js_bool(engine.context, @intFromBool(index == 1));
        try scope.put(namespace.*, "ChildProcess", constructor);
        try scope.put(namespace.*, "spawn", try scope.own(try functions.create(engine, "spawn", 3, spawn, &.{ constructor, flag, known_class })));
        try scope.put(namespace.*, "spawnSync", try scope.own(try functions.create(engine, "spawnSync", 3, spawnSync, &.{flag})));
        try scope.put(namespace.*, "execSync", exec);
    }
    const selector = try scope.own(try functions.createArrow(engine, "", 1, selectNamespace, &namespaces));
    // One publication after both namespaces are complete preserves shared
    // constructor/brand identity on retry after an allocation failure. Although
    // CommonJS can retrieve this callable, it exposes only public namespaces.
    const retained_selector = c.JS_DupValue(engine.context, selector);
    errdefer engine.freeValue(retained_selector);
    try engine.native_module_values.put(engine.gpa, namespace_cache_key, retained_selector);
    return c.JS_DupValue(engine.context, namespaces[@intFromBool(cross_spawn)]);
}
/// Deliberate application selection remains separate from constructing this
/// unqualified Source-only graph.
pub fn install(engine: *js.Engine) !void {
    const namespace = try create(engine, false); defer engine.freeValue(namespace);
    try engine.registerDefaultModule("node:child_process", namespace);
    try engine.registerDefaultModule("child_process", namespace);
}
