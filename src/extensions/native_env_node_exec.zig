//! Source-only native process bridge. OS processes belong to durable.Shell's
//! exact handle/group controls; worker callbacks never enter QuickJS.
const std = @import("std");
const js = @import("native_js_values.zig");
const values = @import("native_env_values.zig");
const owner = @import("native_env_io.zig");
const paths = @import("native_env_node_path.zig");
const commands = @import("../durable/shell.zig");
const types = @import("../durable/types.zig");
const ChargedAllocator = @import("native_env_charged_allocator.zig").ChargedAllocator;
const c = js.c;
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
// Keep the local process adapter independent of remote readers and RPC helpers.
const h = struct {
    fn nullish(value: c.JSValue) bool {
        return c.JS_IsNull(value) or c.JS_IsUndefined(value);
    }
    fn optional(scope: *Scope, object: c.JSValue, key: [*:0]const u8) !c.JSValue {
        return if (nullish(object)) c.pi_js_undefined() else scope.get(object, key);
    }
    fn arg(args: []const c.JSValue, index: usize) c.JSValue {
        return if (index < args.len) args[index] else c.pi_js_undefined();
    }
    fn throw(scope: *Scope, reason: c.JSValue) anyerror {
        _ = c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason));
        return js.capture(scope.engine);
    }
};
pub const CallbackMode = enum { decoded, raw };
const Registry = struct { engine: *js.Engine, tasks: std.ArrayList(*Task) = .empty };
const Output = struct { bytes: []u8, stream: commands.Stream, skipped: ?@import("../durable/output_window.zig").ShellOutputSkip = null };
fn registryFinalize(runtime: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
    _ = runtime;
    const self: *Registry = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    std.debug.assert(self.tasks.items.len == 0);
    self.tasks.deinit(self.engine.gpa);
    self.engine.gpa.destroy(self);
}
fn registry(scope: *Scope, bindings: c.JSValue) !*Registry {
    const existing = try scope.get(bindings, "nativeExecRegistry");
    if (!c.JS_IsUndefined(existing)) return @ptrCast(@alignCast(c.JS_GetOpaque(existing, c.JS_GetClassID(existing)).?));
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(scope.engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Native owned Env processes", .finalizer = registryFinalize };
    if (c.JS_NewClass(scope.engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const object = try scope.own(try scope.engine.checked(c.JS_NewObjectClass(scope.engine.context, class)));
    const self = try scope.engine.gpa.create(Registry);
    self.* = .{ .engine = scope.engine };
    _ = c.JS_SetOpaque(object, self);
    try scope.put(bindings, "nativeExecRegistry", object);
    return self;
}
fn environment(scope: *Scope, object: c.JSValue) !std.process.Environ.Map {
    var map: std.process.Environ.Map = .init(scope.engine.gpa);
    errdefer map.deinit();
    if (h.nullish(object)) return map;
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(scope.engine.context, &names, &count, object, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return js.capture(scope.engine);
    defer c.JS_FreePropertyEnum(scope.engine.context, names, count);
    for (0..count) |index| {
        const key = try scope.own(try scope.engine.checked(c.JS_AtomToValue(scope.engine.context, names[index].atom)));
        const item = try scope.own(try js.getKey(scope.engine, object, key));
        if (c.JS_IsUndefined(item)) continue;
        const key_text = try scope.engine.toString(key);
        defer scope.engine.gpa.free(key_text);
        const text = try scope.engine.toString(item);
        defer scope.engine.gpa.free(text);
        try map.put(key_text, text);
    }
    return map;
}
fn executionError(scope: *Scope, bindings: c.JSValue, code: []const u8, message: c.JSValue, cause: c.JSValue, spill: ?[]const u8) !c.JSValue {
    const converted = if (c.JS_IsUndefined(cause)) cause else try scope.call(try scope.get(bindings, "toError"), c.pi_js_undefined(), &.{cause});
    var args = [_]c.JSValue{ try scope.text(code), message, converted };
    const error_value = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(bindings, "ExecutionError"), args.len, &args)));
    if (spill) |path| try scope.set(error_value, "spillPath", try scope.text(path));
    return error_value;
}
const Task = struct {
    task: owner.Task,
    registry: *Registry,
    receiver: c.JSValue,
    bindings: c.JSValue,
    options: c.JSValue,
    context: c.JSValue,
    signal_value: c.JSValue,
    callback_reason: c.JSValue,
    spawn_reason: c.JSValue,
    mode: CallbackMode,
    command: commands.Command,
    cwd: []u8,
    temporary: []u8,
    shell_path: ?[]u8,
    inherited: std.process.Environ.Map,
    base_env: std.process.Environ.Map,
    extra_env: std.process.Environ.Map,
    inherit: bool,
    timeout: ?f64,
    spill: ?commands.SpillOptions,
    budget: ChargedAllocator,
    native_shell: ?commands.Shell = null,
    shell_gate: std.Io.Mutex = .init,
    output_gate: std.Io.Mutex = .init,
    output: ?Output = null,
    output_ack: std.atomic.Value(bool) = .init(false),
    spawn_ack: std.atomic.Value(bool) = .init(false),
    pid: std.atomic.Value(u32) = .init(0),
    pid_published: bool = false,
    stopping: std.atomic.Value(bool) = .init(false),
    callback_failed: std.atomic.Value(bool) = .init(false),
    spawn_failed: std.atomic.Value(bool) = .init(false),
    allocation_failed: std.atomic.Value(bool) = .init(false),
    epoch: std.atomic.Value(u32) = .init(0),
    result: ?commands.Result = null,
    failure: ?anyerror = null,
    fn wake(self: *Task) void {
        _ = self.epoch.fetchAdd(1, .release);
        self.task.hub.io.futexWake(u32, &self.epoch.raw, std.math.maxInt(u32));
        js.Engine.notifyOwner(self.task.hub.engine);
    }
    fn wait(self: *Task, flag: *std.atomic.Value(bool)) !void {
        while (!flag.load(.acquire)) {
            const observed = self.epoch.load(.acquire);
            if (flag.load(.acquire)) break;
            try self.task.hub.io.futexWait(u32, &self.epoch.raw, observed);
        }
    }
    fn stop(raw: *anyopaque) void {
        const self: *Task = @ptrCast(@alignCast(raw));
        self.stopping.store(true, .release);
        self.spawn_ack.store(true, .release);
        self.output_ack.store(true, .release);
        self.shell_gate.lockUncancelable(self.task.hub.io);
        if (self.native_shell) |*shell| shell.cleanup(.{});
        self.shell_gate.unlock(self.task.hub.io);
        self.wake();
    }
    fn killOwned(self: *Task) void {
        // cleanup() terminates registered children without claiming that the
        // caller's AbortSignal was aborted. Only exact private controls act.
        self.shell_gate.lockUncancelable(self.task.hub.io);
        if (self.native_shell) |*shell| shell.cleanup(.{});
        self.shell_gate.unlock(self.task.hub.io);
    }
    fn stopped(_: *anyopaque) void {}
    fn cancel(task: *owner.Task) void {
        stop(@as(*Task, @alignCast(@fieldParentPtr("task", task))));
    }
    fn spawned(raw: ?*anyopaque, pid: u32) !void {
        const self: *Task = @ptrCast(@alignCast(raw.?));
        self.pid.store(pid, .release);
        self.wake();
        try self.wait(&self.spawn_ack);
        if (self.spawn_failed.load(.acquire)) return error.NativeSpawnPublicationFailed;
    }
    fn outputRaw(raw: ?*anyopaque, bytes: []const u8, _: types.Context, stream: commands.Stream) !void {
        const self: *Task = @ptrCast(@alignCast(raw.?));
        try self.queue(bytes, stream, null);
    }
    fn outputText(raw: ?*anyopaque, bytes: []const u8, _: types.Context, info: commands.OutputInfo) !void {
        const self: *Task = @ptrCast(@alignCast(raw.?));
        try self.queue(bytes, info.stream, info.skipped);
    }
    fn queue(self: *Task, bytes: []const u8, stream: commands.Stream, skipped: ?@import("../durable/output_window.zig").ShellOutputSkip) !void {
        if (self.stopping.load(.acquire)) return;
        const copied = self.budget.allocator().dupe(u8, bytes) catch |err| {
            self.allocation_failed.store(true, .release);
            return err;
        };
        self.output_gate.lockUncancelable(self.task.hub.io);
        std.debug.assert(self.output == null);
        self.output = .{ .bytes = copied, .stream = stream, .skipped = skipped };
        self.output_ack.store(false, .release);
        self.output_gate.unlock(self.task.hub.io);
        self.wake();
        try self.wait(&self.output_ack);
        if (self.callback_failed.load(.acquire)) return error.NativeGuestOutputCallbackFailure;
    }
    fn run(task: *owner.Task) void {
        const self: *Task = @alignCast(@fieldParentPtr("task", task));
        self.work() catch |err| {
            self.failure = err;
        };
        task.finish();
    }
    fn work(self: *Task) !void {
        const shell = try commands.Shell.init(self.budget.allocator(), self.task.hub.io, self.cwd, &self.inherited, &self.base_env, self.shell_path, self.temporary);
        self.shell_gate.lockUncancelable(self.task.hub.io);
        self.native_shell = shell;
        self.shell_gate.unlock(self.task.hub.io);
        defer {
            self.shell_gate.lockUncancelable(self.task.hub.io);
            self.native_shell.?.deinit();
            self.native_shell = null;
            self.shell_gate.unlock(self.task.hub.io);
        }
        self.result = try self.native_shell.?.exec(self.command, .{ .env = &self.extra_env, .inheritEnv = self.inherit, .timeout = self.timeout, .spill = self.spill, .onOutput = if (self.mode == .decoded) outputText else null, .output_context = self, .onRawOutput = if (self.mode == .raw) outputRaw else null, .raw_output_context = self, .onSpawn = spawned, .spawn_context = self }, .{ .abort_flag = &self.stopping });
    }
    fn publishPid(self: *Task, scope: *Scope) !void {
        if (self.pid_published or self.pid.load(.acquire) == 0) return;
        const set = try scope.get(self.receiver, "activeChildPids");
        if (!h.nullish(set)) _ = scope.invoke(set, "add", &.{c.JS_NewUint32(scope.engine.context, self.pid.load(.acquire))}) catch |err| {
            self.spawn_reason = @import("native_agent_async.zig").reason(scope.engine, err);
            self.spawn_failed.store(true, .release);
            stop(self);
            return;
        };
        self.pid_published = true;
        self.spawn_ack.store(true, .release);
        self.wake();
    }
    fn poll(task: *owner.Task) !bool {
        const self: *Task = @alignCast(@fieldParentPtr("task", task));
        var scope: Scope = .{ .engine = task.hub.engine };
        defer scope.deinit();
        scope.engine.native_exception_diagnostics_suppressed += 1;
        defer scope.engine.native_exception_diagnostics_suppressed -= 1;
        if (!h.nullish(self.signal_value) and scope.truthy(try scope.get(self.signal_value, "aborted"))) stop(self);
        try self.publishPid(&scope);
        self.output_gate.lockUncancelable(task.hub.io);
        const output = self.output;
        self.output = null;
        self.output_gate.unlock(task.hub.io);
        const event = output orelse return false;
        defer self.budget.allocator().free(event.bytes);
        defer {
            self.output_ack.store(true, .release);
            self.wake();
        }
        if (self.stopping.load(.acquire)) return true;
        const callback = try h.optional(&scope, self.options, if (self.mode == .raw) "onData" else "onOutput");
        if (c.JS_IsUndefined(callback)) return true;
        const actual_callback = try h.optional(&scope, self.options, if (self.mode == .raw) "onData" else "onOutput");
        const data = if (self.mode == .raw) try scope.own(try @import("node_buffer.zig").fromBytes(scope.engine, event.bytes)) else try scope.text(event.bytes);
        const info = try scope.object();
        try scope.put(info, "stream", try scope.text(@tagName(event.stream)));
        const generation = scope.engine.native_allocation_generation;
        _ = scope.call(actual_callback, self.options, if (self.mode == .raw) &.{data} else &.{ data, self.context, info }) catch |err| {
            if (scope.engine.nativeAllocationError(err, generation) == error.OutOfMemory) {
                self.allocation_failed.store(true, .release);
                stop(self);
                return error.OutOfMemory;
            }
            self.callback_reason = @import("native_agent_async.zig").reason(scope.engine, err);
            self.callback_failed.store(true, .release);
            stop(self);
            return true;
        };
        return true;
    }
    fn complete(task: *owner.Task) !void {
        const self: *Task = @alignCast(@fieldParentPtr("task", task));
        var scope: Scope = .{ .engine = task.hub.engine };
        defer scope.deinit();
        if (self.pid.load(.acquire) != 0) {
            const set = try scope.get(self.receiver, "activeChildPids");
            if (!h.nullish(set)) _ = try scope.invoke(set, "delete", &.{c.JS_NewUint32(scope.engine.context, self.pid.load(.acquire))});
        }
        if (self.allocation_failed.load(.acquire)) return error.OutOfMemory;
        if (self.failure) |failure| if (failure == error.OutOfMemory) return error.OutOfMemory;
        var returned: c.JSValue = undefined;
        var successful = false;
        if (!c.JS_IsUndefined(self.callback_reason) and self.mode == .raw) return task.settled(true, self.callback_reason);
        if (!c.JS_IsUndefined(self.spawn_reason)) {
            returned = try executionError(&scope, self.bindings, "spawn_error", try scope.get(try scope.call(try scope.get(self.bindings, "toError"), c.pi_js_undefined(), &.{self.spawn_reason}), "message"), self.spawn_reason, null);
        } else if (self.result) |result| {
            switch (result) {
                .value => |item| {
                    returned = try scope.object();
                    try scope.put(returned, "exitCode", c.JS_NewInt64(scope.engine.context, item.exitCode));
                    if (item.spillPath) |path| try scope.put(returned, "spillPath", try scope.text(path));
                    successful = true;
                },
                .failure => |failure| {
                    const cause = if (!c.JS_IsUndefined(self.callback_reason)) self.callback_reason else if (failure.cause) |native| try scope.own(@import("native_agent_async.zig").reason(scope.engine, native)) else c.pi_js_undefined();
                    const message = if (failure.code == .callback_error and !c.JS_IsUndefined(cause)) try scope.get(try scope.call(try scope.get(self.bindings, "toError"), c.pi_js_undefined(), &.{cause}), "message") else if (failure.code == .timeout) try scope.concat(try scope.text("timeout:"), try scope.stringify(try h.optional(&scope, self.options, "timeout"))) else try scope.text(failure.message);
                    returned = try executionError(&scope, self.bindings, @tagName(failure.code), message, cause, failure.spillPath);
                },
            }
        } else {
            const cause = try scope.own(@import("native_agent_async.zig").reason(scope.engine, self.failure orelse error.NativeExecMissingTerminalResult));
            returned = try executionError(&scope, self.bindings, "spawn_error", try scope.get(try scope.call(try scope.get(self.bindings, "toError"), c.pi_js_undefined(), &.{cause}), "message"), cause, null);
        }
        if (self.mode == .raw) return task.settled(!successful, returned);
        return task.settled(false, try values.result(&scope, successful, returned));
    }
    fn destroy(task: *owner.Task) void {
        const self: *Task = @alignCast(@fieldParentPtr("task", task));
        const engine = task.hub.engine;
        task.hub.removeResource(self);
        for (self.registry.tasks.items, 0..) |item, index| if (item == self) {
            _ = self.registry.tasks.swapRemove(index);
            break;
        };
        if (self.output) |event| self.budget.allocator().free(event.bytes);
        if (self.result) |*result| switch (result.*) {
            .value => |*item| item.deinit(self.budget.allocator()),
            .failure => |*item| item.deinit(self.budget.allocator()),
        };
        self.budget.deinit();
        switch (self.command) {
            .text => |text| engine.gpa.free(text),
            .argv => |arguments| {
                for (arguments) |argument| engine.gpa.free(argument);
                engine.gpa.free(arguments);
            },
        }
        engine.gpa.free(self.cwd);
        engine.gpa.free(self.temporary);
        if (self.shell_path) |path| engine.gpa.free(path);
        self.inherited.deinit();
        self.base_env.deinit();
        self.extra_env.deinit();
        inline for (.{ "receiver", "bindings", "options", "context", "signal_value", "callback_reason", "spawn_reason" }) |name| engine.freeValue(@field(self, name));
        task.releaseFunctions();
        engine.gpa.destroy(self);
    }
};
/// Raw mode is the actual local BashOperations transport: onData(Buffer),
/// options.signal, seconds timeout, plain exit result/rejection. Decoded mode
/// implements NodeExecutionEnv's per-stream text callback and Result envelope.
pub fn execWithMode(engine: *js.Engine, receiver: c.JSValue, args: []const c.JSValue, bindings: c.JSValue, callback_mode: CallbackMode) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const options = h.arg(args, 1);
    const context = h.arg(args, 2);
    const signal = try h.optional(&scope, if (callback_mode == .raw) options else context, if (callback_mode == .raw) "signal" else "abortSignal");
    if (!h.nullish(signal) and scope.truthy(try scope.get(signal, "aborted"))) {
        const failure = try executionError(&scope, bindings, "aborted", try scope.text("aborted"), c.pi_js_undefined(), null);
        if (callback_mode == .raw) return h.throw(&scope, failure);
        return c.JS_DupValue(engine.context, try values.result(&scope, false, failure));
    }
    const timeout_value = try h.optional(&scope, options, "timeout");
    var timeout: ?f64 = null;
    if (!c.JS_IsUndefined(timeout_value)) {
        var number: f64 = undefined;
        if (c.JS_IsNumber(timeout_value) and c.JS_ToFloat64(engine.context, &number, timeout_value) < 0) return js.capture(engine);
        const valid = c.JS_IsNumber(timeout_value) and std.math.isFinite(number) and number > 0;
        if (!valid or number * 1000 > 2147483647) {
            const failure = try executionError(&scope, bindings, "timeout", try scope.text(if (valid) "Invalid timeout: maximum is 2147483.647 seconds" else "Invalid timeout: must be a finite number of seconds"), c.pi_js_undefined(), null);
            if (callback_mode == .raw) return h.throw(&scope, failure);
            return c.JS_DupValue(engine.context, try values.result(&scope, false, failure));
        }
        timeout = number;
    }
    var command: commands.Command = undefined;
    const supplied = h.arg(args, 0);
    var transferred = false;
    if (c.JS_IsString(supplied)) {
        command = .{ .text = try engine.toString(supplied) };
    } else {
        var arguments: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (arguments.items) |argument| engine.gpa.free(argument);
            arguments.deinit(engine.gpa);
        }
        var iterator = try js.Iterator.init(engine, supplied, try scope.get(try scope.global("Symbol"), "iterator"));
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |argument| {
            const text = try engine.toString(try scope.own(argument));
            errdefer engine.gpa.free(text);
            try arguments.append(engine.gpa, text);
        }
        command = .{ .argv = try arguments.toOwnedSlice(engine.gpa) };
    }
    if (command == .argv and command.argv.len == 0) {
        engine.gpa.free(command.argv);
        const failure = try executionError(&scope, bindings, "spawn_error", try scope.text("Empty argv: no program to run"), c.pi_js_undefined(), null);
        if (callback_mode == .raw) return h.throw(&scope, failure);
        return c.JS_DupValue(engine.context, try values.result(&scope, false, failure));
    }
    errdefer if (!transferred) switch (command) {
        .text => |text| engine.gpa.free(text),
        .argv => |arguments| {
            for (arguments) |argument| engine.gpa.free(argument);
            engine.gpa.free(arguments);
        },
    };
    const cwd_value = try scope.get(receiver, "cwd");
    const explicit_cwd = try h.optional(&scope, options, "cwd");
    const cwd = try engine.toString(if (scope.truthy(explicit_cwd)) try paths.resolve(&scope, bindings, cwd_value, explicit_cwd) else cwd_value);
    errdefer if (!transferred) engine.gpa.free(cwd);
    const temporary = try engine.toString(try paths.temporary(&scope));
    errdefer if (!transferred) engine.gpa.free(temporary);
    const shell_value = try scope.get(receiver, "shellPath");
    const shell_path = if (c.JS_IsUndefined(shell_value)) null else try engine.toString(shell_value);
    errdefer if (!transferred) if (shell_path) |path| engine.gpa.free(path);
    var inherited = try environment(&scope, try scope.get(try scope.global("process"), "env"));
    errdefer if (!transferred) inherited.deinit();
    var base_env = try environment(&scope, try scope.get(receiver, "shellEnv"));
    errdefer if (!transferred) base_env.deinit();
    var extra_env = try environment(&scope, try h.optional(&scope, options, "env"));
    errdefer if (!transferred) extra_env.deinit();
    const inherit_value = try h.optional(&scope, options, "inheritEnv");
    const spill_value = try h.optional(&scope, options, "spill");
    var spill: ?commands.SpillOptions = null;
    if (!h.nullish(spill_value)) {
        var bytes: u64 = undefined;
        var lines: u64 = undefined;
        if (c.JS_ToIndex(engine.context, &bytes, try scope.get(spill_value, "afterBytes")) < 0 or c.JS_ToIndex(engine.context, &lines, try scope.get(spill_value, "afterLines")) < 0) return js.capture(engine);
        spill = .{ .afterBytes = bytes, .afterLines = lines };
    }
    var functions: [2]c.JSValue = undefined;
    const promise = try scope.own(try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions)));
    var functions_transferred = false;
    errdefer if (!functions_transferred) for (functions) |function| engine.freeValue(function);
    const shared = try registry(&scope, bindings);
    const hub = try owner.get(engine);
    const task = try engine.gpa.create(Task);
    task.* = .{ .task = .{ .hub = hub, .work = Task.run, .complete = Task.complete, .destroy = Task.destroy, .cancel = Task.cancel, .poll = Task.poll, .resolve = functions[0], .reject = functions[1] }, .registry = shared, .receiver = c.JS_DupValue(engine.context, receiver), .bindings = c.JS_DupValue(engine.context, bindings), .options = c.JS_DupValue(engine.context, options), .context = c.JS_DupValue(engine.context, context), .signal_value = c.JS_DupValue(engine.context, signal), .callback_reason = c.pi_js_undefined(), .spawn_reason = c.pi_js_undefined(), .mode = callback_mode, .command = command, .cwd = cwd, .temporary = temporary, .shell_path = shell_path, .inherited = inherited, .base_env = base_env, .extra_env = extra_env, .inherit = if (c.JS_IsUndefined(inherit_value)) true else scope.truthy(inherit_value), .timeout = timeout, .spill = spill, .budget = ChargedAllocator.init(engine) };
    transferred = true;
    functions_transferred = true;
    errdefer Task.destroy(&task.task);
    try shared.tasks.append(engine.gpa, task);
    try hub.addResource(.{ .raw = task, .stop = Task.stop, .stopped = Task.stopped });
    try hub.submit(&task.task);
    return c.JS_DupValue(engine.context, promise);
}
pub fn invoke(engine: *js.Engine, receiver: c.JSValue, args: []const c.JSValue, bindings: c.JSValue, method: @import("native_env_node_methods.zig").Method) !c.JSValue {
    if (method == .exec) return execWithMode(engine, receiver, args, bindings, .decoded);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const shared = try registry(&scope, bindings);
    for (shared.tasks.items) |task| if (scope.equal(task.receiver, receiver)) task.killOwned();
    const set = try scope.get(receiver, "activeChildPids");
    if (!h.nullish(set)) _ = try scope.invoke(set, "clear", &.{});
    return @import("native_durable.zig").resolvedPromise(engine, c.pi_js_undefined());
}
