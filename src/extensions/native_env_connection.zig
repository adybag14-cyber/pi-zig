//! Guest Connection owns its native process/session; all guest callbacks run through the Env owner pump.
const std = @import("std");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const classes = @import("native_class.zig");
const awaiting = @import("native_durable_await.zig");
const io_owner = @import("native_env_io.zig");
const native = @import("../env/connection.zig");
const wire = @import("../env/frame.zig");
const c = js.c;
const Method = enum(c_int) { info, session, request, close, kill };
const Stage = enum(c_int) { command, info, session, request, reset };
const State = struct {
    engine: *js.Engine,
    hub: ?*io_owner.Hub,
    options: c.JSValue,
    bindings: c.JSValue,
    ready: c.JSValue,
    owner_lease: ?c.JSValue = null,
    inner: ?*native.Connection = null,
    closed: bool = false,
    session: u64 = 0,
    next_id: u32 = 1,
    log_offset: usize = 0,
    close_reason: ?c.JSValue = null,
    jobs: std.ArrayList(*Job) = .empty,
    fn stop(raw: *anyopaque) void {
        const self: *State = @ptrCast(@alignCast(raw));
        self.closed = true;
        self.hub = null;
        if (self.inner) |client| client.fail(error.ConnectionClosed);
        for (self.jobs.items) |job| Job.cancel(&job.task);
    }
    fn stopped(raw: *anyopaque) void {
        const self: *State = @ptrCast(@alignCast(raw));
        if (self.inner) |client| {
            client.deinit();
            self.inner = null;
        }
        if (self.owner_lease) |value| {
            self.owner_lease = null;
            self.engine.freeValue(value);
        }
    }
};
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn state(engine: *js.Engine, receiver: c.JSValue) !*State {
    return @ptrCast(@alignCast(c.JS_GetOpaque2(engine.context, receiver, engine.native_env_connection_class) orelse return js.capture(engine)));
}
fn finalize(runtime: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
    const engine: *js.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(object, engine.native_env_connection_class) orelse return));
    if (self.hub) |hub| hub.removeResource(self);
    if (self.inner) |client| client.deinit();
    c.JS_FreeValueRT(runtime, self.options);
    c.JS_FreeValueRT(runtime, self.bindings);
    c.JS_FreeValueRT(runtime, self.ready);
    if (self.close_reason) |reason| c.JS_FreeValueRT(runtime, reason);
    self.jobs.deinit(engine.gpa);
    engine.gpa.destroy(self);
}
fn mark(runtime: ?*c.JSRuntime, object: c.JSValue, visitor: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine: *js.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(object, engine.native_env_connection_class) orelse return));
    c.JS_MarkValue(runtime, self.options, visitor);
    c.JS_MarkValue(runtime, self.bindings, visitor);
    c.JS_MarkValue(runtime, self.ready, visitor);
    if (self.close_reason) |reason| c.JS_MarkValue(runtime, reason, visitor);
    // owner_lease belongs to the live process/hub, not to the object's private JS graph.
}
fn errorObject(scope: *Scope, bindings: c.JSValue, code: []const u8, message: c.JSValue, lost: bool) !c.JSValue {
    const fields = try scope.object();
    try scope.put(fields, "code", try scope.text(code));
    try scope.put(fields, "message", message);
    if (lost) try scope.put(fields, "lost", c.pi_js_bool(scope.engine.context, 1));
    const constructor = try scope.get(bindings, "RemoteError");
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, 1, @constCast(&fields))));
}
fn throwError(scope: *Scope, bindings: c.JSValue, message: []const u8, lost: bool) anyerror {
    const error_value = errorObject(scope, bindings, "unknown", scope.text(message) catch |err| return err, lost) catch |err| return err;
    _ = c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, error_value));
    return js.capture(scope.engine);
}
fn intrinsic(scope: *Scope, bindings: c.JSValue) !awaiting.Intrinsics {
    return .{ .constructor = try scope.get(bindings, "promise_constructor"), .resolve = try scope.get(bindings, "promise_resolve"), .then_function = try scope.get(bindings, "promise_then") };
}
fn wait(scope: *Scope, captures: c.JSValue, pending: c.JSValue, stage: Stage) !c.JSValue {
    var promise = try intrinsic(scope, try scope.get(captures, "bindings"));
    return scope.own(try awaiting.continueWith(advance, scope.engine, &promise, captures, pending, @intFromEnum(stage)));
}
fn record(scope: *Scope, self: c.JSValue, bindings: c.JSValue) !c.JSValue {
    const object = try scope.object();
    try scope.put(object, "self", self);
    try scope.put(object, "bindings", bindings);
    return object;
}
const Job = struct {
    task: io_owner.Task,
    connection: *State,
    receiver: c.JSValue,
    request_options: c.JSValue,
    callback_receiver: c.JSValue,
    signal: c.JSValue,
    abort_listener: c.JSValue,
    argv: [][]u8 = &.{},
    json: []u8 = &.{},
    payload: []u8 = &.{},
    spawn: bool,
    session: u64,
    ticket: ?native.Ticket = null,
    client_address: std.atomic.Value(usize) = .init(0),
    abort_requested: std.atomic.Value(bool) = .init(false),
    kill_requested: std.atomic.Value(bool) = .init(false),
    event_mutex: std.Io.Mutex = .init,
    events: std.ArrayList(wire.Frame) = .empty,
    reply: ?wire.Frame = null,
    failure: ?anyerror = null,
    terminal_settled: bool = false,
    lease: c.JSValue,
    starting: bool = false,
    fn client(self: *Job) ?*native.Connection {
        const address = self.client_address.load(.acquire);
        return if (address == 0) null else @ptrFromInt(address);
    }
    fn run(task: *io_owner.Task) void {
        const self: *Job = @fieldParentPtr("task", task);
        self.execute() catch |err| {
            self.failure = err;
        };
        task.finish();
    }
    fn execute(self: *Job) !void {
        const io = self.task.hub.io;
        const deadline = std.Io.Clock.awake.now(io).addDuration(.fromSeconds(60));
        if (self.spawn) {
            if (self.abort_requested.load(.acquire)) return error.ConnectionClosed;
            const client_ptr = try native.Connection.start(self.connection.engine.gpa, io, self.argv, self.session);
            client_ptr.next_id = self.connection.next_id;
            self.client_address.store(@intFromPtr(client_ptr), .release);
            if (self.abort_requested.load(.acquire)) {
                client_ptr.fail(error.ConnectionClosed);
                return error.ConnectionClosed;
            }
            self.ticket = try client_ptr.begin(.{ .op = "hello", .protocol = 1 }, "", null);
        } else {
            const parsed = try std.json.parseFromSlice(std.json.Value, self.connection.engine.gpa, self.json, .{});
            defer parsed.deinit();
            try self.client().?.transmit(self.ticket.?, parsed.value, self.payload);
        }
        var canceled = false;
        var killed = false;
        while (true) {
            if (!canceled and self.abort_requested.load(.acquire)) {
                try self.ticket.?.cancel(false);
                canceled = true;
            }
            if (!killed and self.kill_requested.load(.acquire)) {
                try self.ticket.?.cancel(true);
                killed = true;
            }
            var reply = self.ticket.?.next(50) catch |err| {
                if (err == error.Timeout and (!self.spawn or std.Io.Clock.awake.now(io).nanoseconds < deadline.nanoseconds)) continue;
                return err;
            };
            if (reply.kind == .event) {
                self.event_mutex.lockUncancelable(io);
                self.events.append(self.connection.engine.gpa, reply) catch |err| {
                    self.event_mutex.unlock(io);
                    reply.deinit();
                    return err;
                };
                self.event_mutex.unlock(io);
                js.Engine.notifyOwner(self.connection.engine);
                continue;
            }
            self.reply = reply;
            return;
        }
    }
    fn cancel(task: *io_owner.Task) void {
        const self: *Job = @fieldParentPtr("task", task);
        self.abort_requested.store(true, .release);
        if (self.client()) |client_ptr| if (self.connection.closed) client_ptr.fail(error.ConnectionClosed);
    }
    fn poll(task: *io_owner.Task) anyerror!bool {
        const self: *Job = @fieldParentPtr("task", task);
        const engine = self.connection.engine;
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        if (self.connection.closed) return false;
        var events: std.ArrayList(wire.Frame) = .empty;
        self.event_mutex.lockUncancelable(task.hub.io);
        std.mem.swap(std.ArrayList(wire.Frame), &events, &self.events);
        self.event_mutex.unlock(task.hub.io);
        defer {
            for (events.items) |*event| event.deinit();
            events.deinit(engine.gpa);
        }
        const callback = try scope.get(self.callback_receiver, "onEvent");
        if (!c.JS_IsUndefined(callback) and !c.JS_IsNull(callback)) for (events.items) |event| {
            const json = try scope.own(try engine.fromJsonValue(event.json.value));
            const payload = try bytesValue(&scope, event.payload);
            _ = try scope.call(callback, self.callback_receiver, &.{ json, payload });
        };
        if (self.client()) |client_ptr| {
            const log = try client_ptr.diagnosticSnapshot(engine.gpa);
            defer engine.gpa.free(log);
            if (log.len > self.connection.log_offset) {
                const bytes = log[self.connection.log_offset..];
                self.connection.log_offset = log.len;
                const callback_log = try scope.get(self.connection.options, "onLog");
                if (!c.JS_IsUndefined(callback_log) and !c.JS_IsNull(callback_log)) {
                    const text = try scope.own(try engine.checked(c.JS_NewStringLen(engine.context, bytes.ptr, bytes.len)));
                    _ = try scope.call(callback_log, self.connection.options, &.{text});
                }
            }
        }
        return events.items.len > 0;
    }
    fn complete(task: *io_owner.Task) anyerror!void {
        const self: *Job = @fieldParentPtr("task", task);
        const engine = self.connection.engine;
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        if (self.terminal_settled) return;
        if (!c.JS_IsUndefined(self.lease)) try leaseState(engine, self.lease).detach();
        if (self.connection.closed) {
            const reason = if (self.connection.close_reason) |value| value else try errorObject(&scope, self.connection.bindings, "unknown", try scope.text("Connection closed"), false);
            try task.settled(true, reason);
            return;
        }
        if (self.failure) |failure| {
            if (failure == error.OutOfMemory) return failure;
            const reason = try errorObject(&scope, self.connection.bindings, if (self.spawn and self.client() == null) "spawn_error" else "unknown", try scope.text(if (self.spawn and self.client() == null) @errorName(failure) else if (self.spawn and failure == error.Timeout) "pi-env did not answer within 60 s" else "pi-env connection lost"), true);
            try task.settled(true, reason);
            return;
        }
        const reply = self.reply.?;
        if (reply.json.value != .object) {
            try task.settled(true, try errorObject(&scope, self.connection.bindings, "unknown", try scope.text("Corrupt frame from pi-env"), true));
            return;
        }
        const json = try scope.own(try engine.fromJsonValue(reply.json.value));
        if (reply.kind == .remote_error) {
            const constructor = try scope.get(self.connection.bindings, "RemoteError");
            const reason = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, @constCast(&json))));
            try task.settled(true, reason);
            return;
        }
        const result = try scope.object();
        if (self.spawn) {
            const protocol = try scope.get(json, "protocol");
            if (!c.JS_IsStrictEqual(engine.context, protocol, c.JS_NewInt32(engine.context, 1))) {
                const value = try engine.toString(protocol);
                defer engine.gpa.free(value);
                const message = try std.fmt.allocPrint(engine.gpa, "Unsupported protocol {s}", .{value});
                defer engine.gpa.free(message);
                try task.settled(true, try errorObject(&scope, self.connection.bindings, "unknown", try scope.text(message), true));
                return;
            }
            self.connection.inner = self.client().?;
            self.connection.next_id = self.connection.inner.?.next_id;
            self.client_address.store(0, .release);
            try scope.put(result, "info", json);
        } else {
            try scope.put(result, "json", json);
            try scope.put(result, "payload", try bytesValue(&scope, reply.payload));
        }
        try scope.put(result, "session", c.JS_NewFloat64(engine.context, @floatFromInt(self.session)));
        try task.settled(false, result);
    }
    fn destroy(task: *io_owner.Task) void {
        const self: *Job = @fieldParentPtr("task", task);
        const owner = self.connection;
        const engine = owner.engine;
        for (owner.jobs.items, 0..) |job, index| if (job == self) {
            _ = owner.jobs.orderedRemove(index);
            break;
        };
        if (!c.JS_IsUndefined(self.lease)) {
            const lease = leaseState(engine, self.lease);
            lease.job = null;
            if (!task.hub.stopping) lease.detach() catch {};
        }
        if (self.ticket) |*ticket| ticket.deinit();
        if (self.spawn) if (self.client()) |client_ptr| client_ptr.deinit();
        if (self.reply) |*reply| reply.deinit();
        for (self.events.items) |*event| event.deinit();
        self.events.deinit(engine.gpa);
        for (self.argv) |argument| engine.gpa.free(argument);
        engine.gpa.free(self.argv);
        engine.gpa.free(self.json);
        engine.gpa.free(self.payload);
        engine.freeValue(self.request_options);
        engine.freeValue(self.callback_receiver);
        engine.freeValue(self.signal);
        engine.freeValue(self.abort_listener);
        engine.freeValue(self.lease);
        task.releaseFunctions();
        const receiver = self.receiver;
        const stopping = task.hub.stopping;
        engine.gpa.destroy(self);
        if (!stopping and owner.jobs.items.len == 0 and (owner.closed or owner.inner == null)) {
            if (owner.inner) |client_ptr| {
                client_ptr.deinit();
                owner.inner = null;
            }
            if (owner.owner_lease) |value| {
                owner.owner_lease = null;
                engine.freeValue(value);
            }
        }
        engine.freeValue(receiver);
    }
};
const Lease = struct {
    engine: *js.Engine,
    job: ?*Job,
    self: c.JSValue,
    options: c.JSValue,
    resolve: c.JSValue,
    reject: c.JSValue,
    listener: c.JSValue,
    detached: bool = false,
    fn detach(self: *Lease) !void {
        if (self.detached) return;
        self.detached = true;
        var scope: Scope = .{ .engine = self.engine };
        defer scope.deinit();
        const signal = try scope.get(self.options, "signal");
        if (!c.JS_IsUndefined(signal) and !c.JS_IsNull(signal) and !c.JS_IsUndefined(self.listener)) _ = try scope.invoke(signal, "removeEventListener", &.{ try scope.text("abort"), self.listener });
    }
};
fn leaseState(engine: *js.Engine, value: c.JSValue) *Lease {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_env_signal_lease_class).?));
}
fn leaseFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const engine: *js.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self = leaseState(engine, value);
    inline for (.{ "self", "options", "resolve", "reject", "listener" }) |key| c.JS_FreeValueRT(runtime, @field(self, key));
    engine.gpa.destroy(self);
}
fn leaseMark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine: *js.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self = leaseState(engine, value);
    inline for (.{ "self", "options", "resolve", "reject", "listener" }) |key| c.JS_MarkValue(runtime, @field(self, key), marker);
}
fn leaseInvoke(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const lease = leaseState(engine, data[0]);
    if (raw == 0) {
        if (lease.job) |job| job.abort_requested.store(true, .release);
        return c.pi_js_undefined();
    }
    lease.detach() catch |err| return @import("native_durable.zig").reject(engine, err);
    if (lease.job) |job| job.terminal_settled = true;
    return js.call(engine, if (raw == 1) lease.resolve else lease.reject, c.pi_js_undefined(), &.{if (argc > 0) argv[0] else c.pi_js_undefined()}) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn bytesValue(scope: *Scope, bytes: []const u8) !c.JSValue {
    const backing = try scope.own(try scope.engine.checked(c.JS_NewArrayBufferCopy(scope.engine.context, bytes.ptr, bytes.len)));
    return scope.own(try js.builtin(scope.engine, "Uint8Array", &.{backing}));
}
const PendingJob = struct { job: *Job, promise: c.JSValue };
fn newJob(scope: *Scope, receiver: c.JSValue, options: c.JSValue, spawn: bool) !PendingJob {
    const engine = scope.engine;
    const owner = try state(engine, receiver);
    const hub = owner.hub orelse return error.NativeEnvClosed;
    var functions: [2]c.JSValue = undefined;
    const promise = try scope.own(try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions)));
    var transferred = false;
    errdefer if (!transferred) {
        engine.freeValue(functions[0]);
        engine.freeValue(functions[1]);
    };
    const job = try engine.gpa.create(Job);
    job.* = .{ .task = .{ .hub = hub, .work = Job.run, .complete = Job.complete, .destroy = Job.destroy, .cancel = Job.cancel, .poll = Job.poll, .resolve = functions[0], .reject = functions[1] }, .connection = owner, .receiver = c.JS_DupValue(engine.context, receiver), .request_options = c.JS_DupValue(engine.context, options), .callback_receiver = c.pi_js_undefined(), .signal = c.pi_js_undefined(), .abort_listener = c.pi_js_undefined(), .spawn = spawn, .session = owner.session, .lease = c.pi_js_undefined() };
    transferred = true;
    errdefer Job.destroy(&job.task);
    const lease_value = try scope.own(try engine.checked(c.JS_NewObjectClass(engine.context, engine.native_env_signal_lease_class)));
    const lease = try engine.gpa.create(Lease);
    lease.* = .{ .engine = engine, .job = job, .self = c.JS_DupValue(engine.context, receiver), .options = c.JS_DupValue(engine.context, options), .resolve = c.JS_DupValue(engine.context, functions[0]), .reject = c.JS_DupValue(engine.context, functions[1]), .listener = c.pi_js_undefined() };
    _ = c.JS_SetOpaque(lease_value, lease);
    job.lease = c.JS_DupValue(engine.context, lease_value);
    const callback_receiver = try scope.object();
    var captures = [_]c.JSValue{lease_value};
    inline for (.{ "resolve", "reject" }, 1..) |key, kind| {
        const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, leaseInvoke, key, 1, @intCast(kind), captures.len, &captures)));
        try scope.put(callback_receiver, key, callback);
    }
    const on_event = try scope.get(options, "onEvent");
    if (scope.truthy(on_event)) try scope.put(callback_receiver, "onEvent", try scope.get(options, "onEvent"));
    job.callback_receiver = c.JS_DupValue(engine.context, callback_receiver);
    const listener = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, leaseInvoke, "onAbort", 0, 0, captures.len, &captures)));
    lease.listener = c.JS_DupValue(engine.context, listener);
    job.abort_listener = c.JS_DupValue(engine.context, listener);
    try owner.jobs.append(engine.gpa, job);
    if (owner.owner_lease == null) owner.owner_lease = c.JS_DupValue(engine.context, receiver);
    return .{ .job = job, .promise = promise };
}
fn commandJob(scope: *Scope, receiver: c.JSValue, command: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const owner = try state(engine, receiver);
    if (owner.closed) return throwError(scope, owner.bindings, "Connection closed", false);
    const symbol = try scope.get(try scope.global("Symbol"), "iterator");
    var iterator = try js.Iterator.init(engine, command, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var argv: std.ArrayList([]u8) = .empty;
    var transferred = false;
    defer if (!transferred) {
        for (argv.items) |item| engine.gpa.free(item);
        argv.deinit(engine.gpa);
    };
    while (try iterator.next()) |item| {
        defer engine.freeValue(item);
        if (argv.items.len == 0 and c.JS_IsUndefined(item)) break;
        if (argv.items.len == 0 and !c.JS_IsString(item)) return js.typeError(engine, "The file argument must be of type string");
        const string = try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{item});
        const formed = try scope.invoke(string, "toWellFormed", &.{});
        const text = try engine.toString(formed);
        errdefer engine.gpa.free(text);
        try argv.append(engine.gpa, text);
    }
    if (argv.items.len == 0) {
        const reason = try errorObject(scope, owner.bindings, "spawn_error", try scope.text("No daemon command"), false);
        _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
        return js.capture(engine);
    }
    if (argv.items[0].len == 0) return js.typeError(engine, "The argument 'file' cannot be empty. Received ''");
    owner.session += 1;
    const created = try newJob(scope, receiver, try scope.object(), true);
    errdefer Job.destroy(&created.job.task);
    created.job.session = owner.session;
    created.job.argv = try argv.toOwnedSlice(engine.gpa);
    transferred = true;
    try created.job.task.hub.submit(&created.job.task);
    return created.promise;
}
fn ensureReady(scope: *Scope, receiver: c.JSValue, owner: *State) !c.JSValue {
    if (owner.closed) return throwError(scope, owner.bindings, "Connection closed", false);
    if (!c.JS_IsUndefined(owner.ready)) return owner.ready;
    const captures = try record(scope, receiver, owner.bindings);
    const pending = startReady(scope, receiver, owner, captures) catch |err| try scope.own(try scope.engine.checked(@import("native_durable.zig").rejectedPromise(scope.engine, err)));
    owner.ready = c.JS_DupValue(scope.engine.context, pending);
    try scope.put(captures, "ready", pending);
    _ = try wait(scope, captures, pending, .reset);
    return owner.ready;
}
fn startReady(scope: *Scope, receiver: c.JSValue, owner: *State, captures: c.JSValue) !c.JSValue {
    const option = scope.get(owner.options, "command") catch |err| {
        if (err != error.JavaScriptException) return err;
        return commandFailure(scope, owner.bindings, try scope.own(c.JS_DupValue(scope.engine.context, scope.engine.captured_exception.?)));
    };
    return if (c.JS_IsFunction(scope.engine.context, option)) called: {
        const value = scope.call(option, c.pi_js_undefined(), &.{}) catch |err| {
            if (err != error.JavaScriptException) return err;
            return commandFailure(scope, owner.bindings, try scope.own(c.JS_DupValue(scope.engine.context, scope.engine.captured_exception.?)));
        };
        break :called try wait(scope, captures, value, .command);
    } else try commandJob(scope, receiver, option);
}
fn commandFailure(scope: *Scope, bindings: c.JSValue, failure: c.JSValue) anyerror {
    const base = scope.global("Error") catch |err| return err;
    const instance = c.JS_IsInstanceOf(scope.engine.context, failure, base);
    if (instance < 0) return js.capture(scope.engine);
    const message = if (instance != 0) scope.get(failure, "message") catch |err| return err else scope.call(scope.global("String") catch |err| return err, c.pi_js_undefined(), &.{failure}) catch |err| return err;
    const reason = errorObject(scope, bindings, "spawn_error", message, true) catch |err| return err;
    _ = c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason));
    return js.capture(scope.engine);
}
fn wellFormed(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const value = if (argc > 1) argv[1] else c.pi_js_undefined();
    if (!c.JS_IsString(value)) return c.JS_DupValue(engine.context, value);
    return js.invoke(engine, value, "toWellFormed", &.{}) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn requestJob(scope: *Scope, receiver: c.JSValue, op: c.JSValue, json: c.JSValue, options: c.JSValue, expected_session: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const owner = try state(engine, receiver);
    const client = owner.inner orelse return throwError(scope, owner.bindings, "pi-env connection lost", true);
    client.mutex.lockUncancelable(client.io);
    const live = client.live;
    client.mutex.unlock(client.io);
    if (!live or (!c.JS_IsUndefined(expected_session) and !c.JS_IsStrictEqual(engine.context, expected_session, c.JS_NewFloat64(engine.context, @floatFromInt(client.session))))) return throwError(scope, owner.bindings, "pi-env connection lost", true);
    const created = try newJob(scope, receiver, options, false);
    const job = created.job;
    errdefer Job.destroy(&job.task);
    job.ticket = try client.reserve(client.session);
    owner.next_id = client.next_id;
    job.client_address.store(@intFromPtr(client), .release);
    const signal = try scope.get(options, "signal");
    if (!c.JS_IsUndefined(signal) and !c.JS_IsNull(signal)) {
        job.signal = c.JS_DupValue(engine.context, signal);
        const once = try scope.object();
        try scope.put(once, "once", c.pi_js_bool(engine.context, 1));
        _ = try scope.invoke(signal, "addEventListener", &.{ try scope.text("abort"), job.abort_listener, once });
    }
    const on_start = try scope.get(options, "onStart");
    job.starting = true;
    defer job.starting = false;
    if (!c.JS_IsUndefined(on_start) and !c.JS_IsNull(on_start)) _ = try scope.call(on_start, options, &.{ c.JS_NewInt64(engine.context, job.ticket.?.id), c.JS_NewFloat64(engine.context, @floatFromInt(job.ticket.?.session)) });
    const object = try scope.own(try js.spread(engine, json));
    try scope.put(object, "op", op);
    const replacer = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, wellFormed, "wellFormed", 2)));
    const encoded = try scope.invoke(try scope.global("JSON"), "stringify", &.{ object, replacer });
    job.json = try engine.toString(encoded);
    const given_payload = try scope.get(options, "payload");
    if (!c.JS_IsUndefined(given_payload)) {
        var offset: usize = 0;
        var length: usize = 0;
        var element: usize = 0;
        var backing_length: usize = 0;
        const backing = try scope.own(try engine.checked(c.JS_GetTypedArrayBuffer(engine.context, given_payload, &offset, &length, &element)));
        const bytes = c.JS_GetArrayBuffer(engine.context, &backing_length, backing);
        if (element != 1 or offset > backing_length or length > backing_length - offset) return js.typeError(engine, "Invalid request payload");
        job.payload = try engine.gpa.dupe(u8, if (length == 0) &.{} else bytes[offset..][0..length]);
    }
    const after_signal = try scope.get(options, "signal");
    if (!c.JS_IsUndefined(after_signal) and !c.JS_IsNull(after_signal) and scope.truthy(try scope.get(after_signal, "aborted"))) job.abort_requested.store(true, .release);
    if (owner.closed) {
        Job.destroy(&job.task);
        return created.promise;
    }
    // Every fallible owner-side getter completes before transferring the task to a worker.
    try job.task.hub.submit(&job.task);
    return created.promise;
}

fn advance(engine: *js.Engine, captures: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(captures, "self");
    const owner = try state(engine, receiver);
    const stage: Stage = @enumFromInt(raw);
    if (stage == .reset) {
        if (rejected and c.JS_IsStrictEqual(engine.context, owner.ready, try scope.get(captures, "ready"))) {
            engine.freeValue(owner.ready);
            owner.ready = c.pi_js_undefined();
        }
        return c.pi_js_undefined();
    }
    if (rejected) {
        if (stage == .command) return commandFailure(&scope, owner.bindings, value);
        _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value));
        return js.capture(engine);
    }
    const result = switch (stage) {
        .command => try commandJob(&scope, receiver, value),
        .info => try scope.get(value, "info"),
        .session => try scope.get(value, "session"),
        .request => try requestJob(&scope, receiver, try scope.get(captures, "op"), try scope.get(captures, "json"), try scope.get(captures, "options"), try scope.get(value, "session")),
        .reset => unreachable,
    };
    return c.JS_DupValue(engine.context, result);
}
fn close(scope: *Scope, owner: *State) !void {
    owner.closed = true;
    if (owner.close_reason == null) owner.close_reason = c.JS_DupValue(scope.engine.context, try errorObject(scope, owner.bindings, "unknown", try scope.text("Connection closed"), false));
    for (owner.jobs.items) |job| {
        if (!job.terminal_settled) {
            if (!c.JS_IsUndefined(job.lease)) try leaseState(scope.engine, job.lease).detach();
            try job.task.settled(true, owner.close_reason.?);
            job.terminal_settled = true;
        }
        Job.cancel(&job.task);
    }
    if (owner.inner) |client| client.stop();
    if (owner.jobs.items.len == 0) {
        if (owner.inner) |client| {
            client.deinit();
            owner.inner = null;
        }
        if (owner.owner_lease) |value| {
            owner.owner_lease = null;
            scope.engine.freeValue(value);
        }
    }
}
fn invoke(engine: *js.Engine, receiver: c.JSValue, args: []const c.JSValue, method: Method) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try state(engine, receiver);
    if (method == .close) {
        try close(&scope, owner);
        return c.pi_js_undefined();
    }
    if (method == .kill) {
        if (owner.inner) |client| {
            if (c.JS_IsStrictEqual(engine.context, arg(args, 1), c.JS_NewFloat64(engine.context, @floatFromInt(client.session)))) {
                for (owner.jobs.items) |job| if (job.ticket) |ticket| {
                    if (ticket.connection == client and c.JS_IsStrictEqual(engine.context, arg(args, 0), c.JS_NewInt64(engine.context, ticket.id)) and !job.starting) job.kill_requested.store(true, .release);
                };
            }
        }
        return c.pi_js_undefined();
    }
    const captures = try record(&scope, receiver, owner.bindings);
    if (method == .request) {
        const options = if (c.JS_IsUndefined(arg(args, 2))) try scope.object() else arg(args, 2);
        const expected = try scope.get(options, "session");
        if (!c.JS_IsUndefined(expected)) return c.JS_DupValue(engine.context, try requestJob(&scope, receiver, arg(args, 0), arg(args, 1), options, try scope.get(options, "session")));
        try scope.put(captures, "op", arg(args, 0));
        try scope.put(captures, "json", arg(args, 1));
        try scope.put(captures, "options", options);
    }
    return c.JS_DupValue(engine.context, try wait(&scope, captures, try ensureReady(&scope, receiver, owner), switch (method) {
        .info => .info,
        .session => .session,
        .request => .request,
        else => unreachable,
    }));
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const method: Method = @enumFromInt(raw);
    const result = invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, method) catch |err| {
        return if (method == .close or method == .kill) @import("native_durable.zig").reject(engine, err) else @import("native_durable.zig").rejectedPromise(engine, err);
    };
    return if (method == .close or method == .kill) result else resolved: {
        defer engine.freeValue(result);
        break :resolved @import("native_durable.zig").resolvedPromise(engine, result) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
    };
}
fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.get(target, "prototype");
    const object = try scope.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, if (c.JS_IsObject(prototype)) prototype else c.pi_js_null(), engine.native_env_connection_class)));
    const hub = try io_owner.get(engine);
    const owner = try engine.gpa.create(State);
    owner.* = .{ .engine = engine, .hub = null, .options = c.JS_DupValue(engine.context, arg(args, 0)), .bindings = c.JS_DupValue(engine.context, captures[0]), .ready = c.pi_js_undefined() };
    _ = c.JS_SetOpaque(object, owner);
    try hub.addResource(.{ .raw = owner, .stop = State.stop, .stopped = State.stopped });
    owner.hub = hub;
    return c.JS_DupValue(engine.context, object);
}
pub fn create(engine: *js.Engine, shared: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (engine.native_env_connection_class == 0) {
        _ = c.JS_NewClassID(engine.runtime, &engine.native_env_connection_class);
        const definition: c.JSClassDef = .{ .class_name = "Connection", .finalizer = finalize, .gc_mark = mark };
        if (c.JS_NewClass(engine.runtime, engine.native_env_connection_class, &definition) < 0) return error.OutOfMemory;
    }
    if (engine.native_env_signal_lease_class == 0) {
        _ = c.JS_NewClassID(engine.runtime, &engine.native_env_signal_lease_class);
        const definition: c.JSClassDef = .{ .class_name = "Env Request Lease", .finalizer = leaseFinalizer, .gc_mark = leaseMark };
        if (c.JS_NewClass(engine.runtime, engine.native_env_signal_lease_class, &definition) < 0) return error.OutOfMemory;
    }
    const bindings = try scope.object();
    try scope.put(bindings, "RemoteError", try scope.get(shared, "RemoteError"));
    var promises = try awaiting.Intrinsics.init(engine);
    defer promises.deinit(engine);
    try scope.put(bindings, "promise_constructor", promises.constructor);
    try scope.put(bindings, "promise_resolve", promises.resolve);
    try scope.put(bindings, "promise_then", promises.then_function);
    const prototype = try scope.object();
    inline for (std.meta.fields(Method)) |field| {
        const method: Method = @enumFromInt(field.value);
        const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, if (method == .request or method == .kill) 2 else 0, @intCast(field.value), 0, null)));
        if (method == .info or method == .session or method == .request) {
            const async_prototype = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
            if (c.JS_SetPrototype(engine.context, function, async_prototype) < 0) return js.capture(engine);
        }
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    return classes.constructor(engine, "Connection", 1, prototype, construct, &.{bindings});
}
