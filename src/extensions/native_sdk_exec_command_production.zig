//! Actual core/exec.ts executable/argv facade. Source-only until real-child gates.
//! All guest roots live in a marked JS owner graph. Workers own bytes and a
//! retained direct-child handle; no worker reads a guest value or enters the VM.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const flow = @import("native_agent_async.zig");
const hub = @import("native_env_io.zig");
const transport = @import("native_sdk_exec_command_process.zig");
const Charged = @import("native_env_charged_allocator.zig").ChargedAllocator;
const functions = @import("native_node_function.zig");
const registry_key = "\x00native-core-exec-command";
const OwnedControl = struct { allocator: std.mem.Allocator, value: transport.Control = .{} };
fn nullish(value: c.JSValue) bool {
    return c.JS_IsNull(value) or c.JS_IsUndefined(value);
}
fn option(s: *Scope, options: c.JSValue, key: [*:0]const u8) !c.JSValue {
    return if (nullish(options)) c.pi_js_undefined() else s.get(options, key);
}
fn control(owner: c.JSValue) *transport.Control {
    const owned: *OwnedControl = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)).?));
    return &owned.value;
}
fn finalize(_: ?*c.JSRuntime, owner: c.JSValue) callconv(.c) void {
    const raw = c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return;
    const owned: *OwnedControl = @ptrCast(@alignCast(raw));
    owned.allocator.destroy(owned);
}
fn ownerObject(s: *Scope) !c.JSValue {
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(s.engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Owned core execCommand", .finalizer = finalize };
    if (c.JS_NewClass(s.engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const owner = try s.own(try s.engine.checked(c.JS_NewObjectClass(s.engine.context, class)));
    const state = try s.engine.gpa.create(OwnedControl);
    state.* = .{ .allocator = s.engine.gpa };
    _ = c.JS_SetOpaque(owner, state);
    return owner;
}
fn retireRoot(engine: *js.Engine, array: c.JSValue, position: u32) void {
    const atom = c.JS_NewAtomUInt32(engine.context, position);
    if (atom == c.JS_ATOM_NULL) return;
    defer c.JS_FreeAtom(engine.context, atom);
    _ = c.JS_DeleteProperty(engine.context, array, atom, 0);
}
fn roots(s: *Scope) !c.JSValue {
    if (s.engine.native_module_values.get(registry_key)) |array| return array;
    const array = try s.array();
    const retained = c.JS_DupValue(s.engine.context, array);
    s.engine.native_module_values.put(s.engine.gpa, registry_key, retained) catch |err| {
        s.engine.freeValue(retained);
        return err;
    };
    return array;
}
pub fn create(engine: *js.Engine) !c.JSValue {
    const function = try functions.createMethod(engine, "execCommand", 4, called, &.{});
    errdefer engine.freeValue(function);
    const prototype = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(prototype);
    if (c.JS_SetPrototype(engine.context, function, prototype) < 0) return js.capture(engine);
    return function;
}
fn called(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const outer = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(outer.owner);
    errdefer engine.freeValue(outer.promise);
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    defer engine.freeValue(pending.promise);
    begin(&s, pending.owner, args) catch |err| try flow.rejectError(engine, pending.owner, err);
    // Source is async and returns a new Promise. Resolving the outer capability
    // with that inner promise preserves actual Promise assimilation jobs.
    try flow.settle(engine, outer.owner, false, pending.promise);
    return outer.promise;
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn invalid(s: *Scope, message: []const u8, code: []const u8) anyerror!void {
    const value = try s.own(try js.builtin(s.engine, "TypeError", &.{try s.text(message)}));
    try s.put(value, "code", try s.text(code));
    _ = c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, value));
    return js.capture(s.engine);
}
fn environment(s: *Scope) !std.process.Environ.Map {
    var env: std.process.Environ.Map = .init(s.engine.gpa);
    errdefer env.deinit();
    const object = try s.get(try s.global("process"), "env");
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(s.engine.context, &names, &count, object, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return js.capture(s.engine);
    defer c.JS_FreePropertyEnum(s.engine.context, names, count);
    for (0..count) |index| {
        const key = try s.own(try s.engine.checked(c.JS_AtomToValue(s.engine.context, names[index].atom)));
        const value = try s.own(try js.getKey(s.engine, object, key));
        if (c.JS_IsUndefined(value)) continue;
        const name = try s.engine.toString(key);
        defer s.engine.gpa.free(name);
        const text = try s.engine.toString(value);
        defer s.engine.gpa.free(text);
        try env.put(name, text);
    }
    return env;
}
fn begin(s: *Scope, pending: c.JSValue, args: []const c.JSValue) !void {
    const command = arg(args, 0);
    if (!c.JS_IsString(command)) return invalid(s, "The \"file\" argument must be of type string", "ERR_INVALID_ARG_TYPE");
    const program = try s.engine.toString(command);
    defer s.engine.gpa.free(program);
    if (program.len == 0) return invalid(s, "The argument 'file' cannot be empty. Received ''", "ERR_INVALID_ARG_VALUE");
    if (std.mem.indexOfScalar(u8, program, 0) != null) return invalid(s, "The argument 'file' must be a string without null bytes", "ERR_INVALID_ARG_VALUE");
    var arguments: std.ArrayList([]const u8) = .empty;
    defer {
        for (arguments.items) |item| s.engine.gpa.free(item);
        arguments.deinit(s.engine.gpa);
    }
    try arguments.append(s.engine.gpa, try s.engine.gpa.dupe(u8, program));
    const provided = arg(args, 1);
    if (!nullish(provided)) {
        if (!c.JS_IsArray(provided)) return invalid(s, "The \"args\" argument must be of type object", "ERR_INVALID_ARG_TYPE");
        var count: u32 = 0;
        if (c.JS_ToUint32(s.engine.context, &count, try s.get(provided, "length")) < 0) return js.capture(s.engine);
        for (0..count) |index| {
            const value = try s.own(try s.engine.checked(c.JS_GetPropertyUint32(s.engine.context, provided, @intCast(index))));
            const text = try s.engine.toString(value);
            errdefer s.engine.gpa.free(text);
            if (std.mem.indexOfScalar(u8, text, 0) != null) return invalid(s, "The argument 'args' must be a string without null bytes", "ERR_INVALID_ARG_VALUE");
            try arguments.append(s.engine.gpa, text);
        }
    }
    const directory = arg(args, 2);
    const cwd = if (nullish(directory)) null else try s.engine.toString(directory);
    defer if (cwd) |path| s.engine.gpa.free(path);
    var env = try environment(s);
    defer env.deinit();
    const io_owner = try hub.get(s.engine);
    const owner = try ownerObject(s);
    try s.put(owner, "options", arg(args, 3));
    try s.put(owner, "pending", pending);
    try s.put(owner, "stdout", try s.text(""));
    try s.put(owner, "stderr", try s.text(""));
    try s.put(owner, "killed", c.pi_js_bool(s.engine.context, 0));
    const wait = try flow.create(s.engine, owner);
    defer s.engine.freeValue(wait.owner);
    defer s.engine.freeValue(wait.promise);
    try s.put(owner, "waitOwner", wait.owner);
    const array = try roots(s);
    var length: u32 = 0;
    if (c.JS_ToUint32(s.engine.context, &length, try s.get(array, "length")) < 0) return js.capture(s.engine);
    var position: u32 = 0;
    while (position < length) : (position += 1) {
        if (c.JS_IsUndefined(try s.own(try s.engine.checked(c.JS_GetPropertyUint32(s.engine.context, array, position))))) break;
    }
    try s.index(array, position, owner);
    var submitted = false;
    errdefer if (!submitted) retireRoot(s.engine, array, position);
    var process = transport.Process.spawn(io_owner.io, arguments.items, cwd, &env) catch |err| {
        if (err == error.OutOfMemory) return err;
        // Node spawn's asynchronous error is consumed by waitForChildProcess;
        // core's catch resolves code1 and does not surface the spawn Error.
        const reason = try s.own(flow.reason(s.engine, err));
        try setup(s, owner, wait.promise);
        try flow.settle(s.engine, wait.owner, true, reason);
        retireRoot(s.engine, array, position);
        return;
    };
    var transferred = false;
    errdefer if (!transferred) process.deinit(io_owner.io);
    const task = try s.engine.gpa.create(Task);
    task.* = .{
        .task = .{ .hub = io_owner, .work = Task.work, .complete = Task.complete, .destroy = Task.destroy, .cancel = Task.cancel, .poll = Task.poll, .resolve = c.JS_DupValue(s.engine.context, try s.get(wait.owner, "resolve")), .reject = c.JS_DupValue(s.engine.context, try s.get(wait.owner, "reject")) },
        .owner = c.JS_DupValue(s.engine.context, owner),
        .process = process,
        .budget = Charged.init(s.engine),
        .position = position,
        .control = control(owner),
    };
    transferred = true;
    errdefer if (!submitted) {
        task.process.deinit(io_owner.io);
        Task.destroy(&task.task);
    };
    // Spawn precedes observable signal/timeout getters, as in the real Source.
    setup(s, owner, wait.promise) catch |err| {
        task.capture.store(false, .release);
        try io_owner.submit(&task.task);
        submitted = true;
        return err;
    };
    try io_owner.submit(&task.task);
    submitted = true;
}
fn setup(s: *Scope, owner: c.JSValue, wait: c.JSValue) !void {
    const options = try s.get(owner, "options");
    const kill = try s.own(try functions.createArrow(s.engine, "killProcess", 0, killProcess, &.{owner}));
    try s.put(owner, "kill", kill);
    if (s.truthy(try option(s, options, "signal"))) {
        if (s.truthy(try s.get(try s.get(options, "signal"), "aborted"))) {
            _ = try s.call(kill, c.pi_js_undefined(), &.{});
        } else {
            const signal = try s.get(options, "signal");
            const once = try s.object();
            try s.put(once, "once", c.pi_js_bool(s.engine.context, 1));
            _ = try s.invoke(signal, "addEventListener", &.{ try s.text("abort"), kill, once });
        }
    }
    if (s.truthy(try option(s, options, "timeout")) and try s.positive(try s.get(options, "timeout"))) {
        const timer = try s.call(try s.global("setTimeout"), c.pi_js_undefined(), &.{ kill, try s.get(options, "timeout") });
        try s.put(owner, "timeout", timer);
    }
    const then = try s.own(try functions.createArrow(s.engine, "", 1, fulfilled, &.{owner}));
    const failed = try s.own(try functions.createArrow(s.engine, "", 1, rejected, &.{owner}));
    _ = try s.invoke(try s.invoke(wait, "then", &.{then}), "catch", &.{failed});
}
fn killProcess(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const owner = captures[0];
    if (!s.truthy(try s.get(owner, "killed"))) {
        try s.set(owner, "killed", c.pi_js_bool(engine.context, 1));
        control(owner).terminate.store(true, .release);
        const force = try s.own(try functions.createArrow(engine, "", 0, forceKill, &.{owner}));
        _ = try s.call(try s.global("setTimeout"), c.pi_js_undefined(), &.{ force, c.JS_NewInt32(engine.context, 5000) });
    }
    return c.pi_js_undefined();
}
fn forceKill(_: *js.Engine, _: c.JSValue, _: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    const state = control(captures[0]);
    if (!state.signal_sent.load(.acquire)) state.force.store(true, .release);
    return c.pi_js_undefined();
}
fn resolved(engine: *js.Engine, owner: c.JSValue, code: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const timeout = try s.get(owner, "timeout");
    if (s.truthy(timeout)) _ = try s.call(try s.global("clearTimeout"), c.pi_js_undefined(), &.{timeout});
    const options = try s.get(owner, "options");
    if (s.truthy(try option(&s, options, "signal"))) _ = try s.invoke(try s.get(options, "signal"), "removeEventListener", &.{ try s.text("abort"), try s.get(owner, "kill") });
    const result = try s.object();
    try s.put(result, "stdout", try s.get(owner, "stdout"));
    try s.put(result, "stderr", try s.get(owner, "stderr"));
    try s.put(result, "code", if (nullish(code)) c.JS_NewInt32(engine.context, 0) else code);
    try s.put(result, "killed", try s.get(owner, "killed"));
    try flow.settle(engine, try s.get(owner, "pending"), false, result);
    return c.pi_js_undefined();
}
fn fulfilled(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    return resolved(engine, captures[0], arg(args, 0));
}
fn rejected(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    return resolved(engine, captures[0], c.JS_NewInt32(engine.context, 1));
}
const Event = struct { stream: transport.Stream, bytes: []u8 };
const Task = struct {
    task: hub.Task,
    owner: c.JSValue,
    process: transport.Process,
    control: *transport.Control,
    budget: Charged,
    position: u32,
    capture: std.atomic.Value(bool) = .init(true),
    gate: std.Io.Mutex = .init,
    event: ?Event = null,
    epoch: std.atomic.Value(u32) = .init(0),
    acknowledged: std.atomic.Value(bool) = .init(false),
    result: ?transport.Result = null,
    failure: ?anyerror = null,
    fn wake(self: *Task) void {
        _ = self.epoch.fetchAdd(1, .release);
        self.task.hub.io.futexWake(u32, &self.epoch.raw, std.math.maxInt(u32));
        js.Engine.notifyOwner(self.task.hub.engine);
    }
    fn chunk(raw: *anyopaque, stream: transport.Stream, bytes: []const u8) !void {
        const self: *Task = @ptrCast(@alignCast(raw));
        if (!self.capture.load(.acquire)) return;
        const copy = try self.budget.allocator().dupe(u8, bytes);
        self.gate.lockUncancelable(self.task.hub.io);
        self.event = .{ .stream = stream, .bytes = copy };
        self.acknowledged.store(false, .release);
        self.gate.unlock(self.task.hub.io);
        self.wake();
        while (!self.acknowledged.load(.acquire)) {
            if (self.control.shutdown.load(.acquire)) return error.Canceled;
            const observed = self.epoch.load(.acquire);
            if (!self.acknowledged.load(.acquire)) try self.task.hub.io.futexWait(u32, &self.epoch.raw, observed);
        }
    }
    fn work(base: *hub.Task) void {
        const self: *Task = @alignCast(@fieldParentPtr("task", base));
        self.result = self.process.run(base.hub.io, self.control, .{ .context = self, .write = chunk }) catch |err| failure: {
            self.failure = err;
            break :failure null;
        };
        base.finish();
    }
    fn poll(base: *hub.Task) !bool {
        const self: *Task = @alignCast(@fieldParentPtr("task", base));
        self.gate.lockUncancelable(base.hub.io);
        const event = self.event;
        self.event = null;
        self.gate.unlock(base.hub.io);
        const item = event orelse return false;
        defer self.budget.allocator().free(item.bytes);
        defer {
            self.acknowledged.store(true, .release);
            self.wake();
        }
        if (!self.capture.load(.acquire)) return true;
        var s: Scope = .{ .engine = base.hub.engine };
        defer s.deinit();
        const buffer = try s.own(try @import("node_buffer.zig").fromBytes(s.engine, item.bytes));
        const text = try s.invoke(buffer, "toString", &.{});
        const key: [*:0]const u8 = if (item.stream == .stdout) "stdout" else "stderr";
        try s.set(self.owner, key, try s.concat(try s.get(self.owner, key), text));
        return true;
    }
    fn complete(base: *hub.Task) !void {
        const self: *Task = @alignCast(@fieldParentPtr("task", base));
        if (self.failure) |err| {
            if (err == error.OutOfMemory) return err;
            const reason = flow.reason(base.hub.engine, err);
            defer base.hub.engine.freeValue(reason);
            return base.settled(true, reason);
        }
        const result = self.result orelse return error.NativeExecMissingResult;
        try base.settled(false, if (result.signal != null) c.pi_js_null() else c.JS_NewInt32(base.hub.engine.context, result.code));
    }
    fn cancel(base: *hub.Task) void {
        const self: *Task = @alignCast(@fieldParentPtr("task", base));
        self.control.shutdown.store(true, .release);
        self.wake();
    }
    fn destroy(base: *hub.Task) void {
        const self: *Task = @alignCast(@fieldParentPtr("task", base));
        const engine = base.hub.engine;
        if (self.event) |event| self.budget.allocator().free(event.bytes);
        self.budget.deinit();
        if (engine.native_module_values.get(registry_key)) |array| retireRoot(engine, array, self.position);
        engine.freeValue(self.owner);
        base.releaseFunctions();
        engine.gpa.destroy(self);
    }
};
