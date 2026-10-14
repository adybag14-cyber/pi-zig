//! Owner-thread VM half of raw HTTP transport. Worker storage contains no JS.
//! This internal transport does not claim any provider's request/event codec.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_models_stream_scope.zig");
const Scope = temp.Scope;
const raw = @import("native_ai_http_worker.zig");
const c = em.c;
pub const maximum_requests = 16;
const Waiter = struct { resolve: c.JSValue, reject: c.JSValue };
const Job = struct {
    id: u64,
    worker: *raw.Worker,
    signal: c.JSValue,
    ready_resolve: c.JSValue,
    ready_reject: c.JSValue,
    ready_settled: bool = false,
    closed: bool = false,
    waiters: std.ArrayList(Waiter) = .empty,
    fn destroy(self: *Job, engine: *em.Engine) void {
        self.worker.destroy();
        for ([_]c.JSValue{ self.signal, self.ready_resolve, self.ready_reject }) |value| engine.freeValue(value);
        for (self.waiters.items) |waiter| {
            engine.freeValue(waiter.resolve);
            engine.freeValue(waiter.reject);
        }
        self.waiters.deinit(engine.gpa);
        engine.gpa.destroy(self);
    }
};
const State = struct { jobs: std.ArrayList(*Job) = .empty, next_id: u64 = 0, pumping: bool = false };
fn stateFor(engine: *em.Engine) !*State {
    if (engine.native_ai_http_state) |value| return @ptrCast(@alignCast(value));
    const state = try engine.gpa.create(State);
    state.* = .{};
    engine.native_ai_http_state = state;
    engine.native_ai_http_pump = pump;
    engine.native_ai_http_pending = pending;
    engine.native_ai_http_cleanup = deinit;
    return state;
}
pub fn pending(engine: *em.Engine) bool {
    const state: *State = @ptrCast(@alignCast(engine.native_ai_http_state orelse return false));
    return state.jobs.items.len != 0;
}
pub fn deinit(engine: *em.Engine) void {
    const state: *State = @ptrCast(@alignCast(engine.native_ai_http_state orelse return));
    engine.native_ai_http_state = null;
    engine.native_ai_http_pump = null;
    engine.native_ai_http_pending = null;
    engine.native_ai_http_cleanup = null;
    // Cancel every producer, including ones blocked on a full queue, before
    // joining any worker. VM roots and Io outlive every join.
    for (state.jobs.items) |job| job.worker.cancel();
    for (state.jobs.items) |job| job.destroy(engine);
    state.jobs.deinit(engine.gpa);
    engine.gpa.destroy(state);
}
fn find(engine: *em.Engine, id: u64) ?*Job {
    const state: *State = @ptrCast(@alignCast(engine.native_ai_http_state orelse return null));
    for (state.jobs.items) |job| if (job.id == id) return job;
    return null;
}
fn call(scope: *Scope, callee: c.JSValue, value: c.JSValue) !void {
    _ = try scope.call(callee, c.pi_js_undefined(), &.{value});
}
fn result(scope: *Scope, value: c.JSValue, done: bool) !c.JSValue {
    const object = try scope.object();
    try scope.put(object, "value", value);
    try scope.put(object, "done", c.pi_js_bool(scope.engine.context, @intFromBool(done)));
    return object;
}
fn resolved(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    return engine.checked(c.JS_PiPromiseResolve(engine.context, value));
}
const Method = enum(c_int) { next, close, cancel, self };
fn callback(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue, method: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return operation(engine, receiver, @enumFromInt(method), roots[0]) catch |err| @import("native_sdk.zig").fail(engine, err);
}
fn function(scope: *Scope, id: c.JSValue, method: Method) !c.JSValue {
    var roots = [_]c.JSValue{id};
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callback, switch (method) {
        .next => "next",
        .close => "return",
        .cancel => "cancel",
        .self => "asyncIterator",
    }, 0, @intFromEnum(method), roots.len, &roots)));
}
pub fn open(engine: *em.Engine, input: raw.Input, signal: c.JSValue) !c.JSValue {
    const io = engine.native_io orelse return error.NativeHttpIoRequired;
    const state = try stateFor(engine);
    if (state.jobs.items.len == maximum_requests) return error.NativeHttpRequestLimit;
    try state.jobs.ensureUnusedCapacity(engine.gpa, 1);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    state.next_id +%= 1;
    if (state.next_id == 0) state.next_id = 1;
    const id = try scope.own(try engine.checked(c.JS_NewBigUint64(engine.context, state.next_id)));
    var caps: [2]c.JSValue = undefined;
    const ready = try scope.own(try engine.checked(c.JS_NewPromiseCapability(engine.context, &caps)));
    defer for (caps) |value| engine.freeValue(value);
    const output = try scope.object();
    const iterator = try scope.object();
    try scope.put(iterator, "next", try function(&scope, id, .next));
    try scope.put(iterator, "return", try function(&scope, id, .close));
    const symbol = try scope.own(try engine.checked(c.JS_GetAsyncIteratorSymbol(engine.context)));
    const atom = c.JS_ValueToAtom(engine.context, symbol);
    if (atom == c.JS_ATOM_NULL) return js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyValue(engine.context, iterator, atom, c.JS_DupValue(engine.context, try function(&scope, id, .self)), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    try scope.put(output, "ready", ready);
    try scope.put(output, "events", iterator);
    try scope.put(output, "cancel", try function(&scope, id, .cancel));
    if (!temp.nullish(signal) and scope.truthy(try scope.get(signal, "aborted"))) {
        try call(&scope, caps[1], try failureValue(&scope, error.ProviderRequestAborted));
        return c.JS_DupValue(engine.context, output);
    }
    const job = try engine.gpa.create(Job);
    errdefer engine.gpa.destroy(job);
    // All fallible VM/owner allocations finish before the worker can notify.
    const worker = try raw.Worker.create(io, input, engine, em.Engine.notifyOwner);
    job.* = .{ .id = state.next_id, .worker = worker, .signal = c.JS_DupValue(engine.context, signal), .ready_resolve = c.JS_DupValue(engine.context, caps[0]), .ready_reject = c.JS_DupValue(engine.context, caps[1]) };
    state.jobs.appendAssumeCapacity(job);
    return c.JS_DupValue(engine.context, output);
}
fn operation(engine: *em.Engine, receiver: c.JSValue, method: Method, id_value: c.JSValue) !c.JSValue {
    if (method == .self) return c.JS_DupValue(engine.context, receiver);
    var id: u64 = 0;
    if (c.JS_ToBigUint64(engine.context, &id, id_value) < 0) return js.capture(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const job = find(engine, id);
    if (method == .close or method == .cancel) {
        if (job) |value| {
            value.closed = true;
            value.worker.cancel();
        }
        return if (method == .close) resolved(engine, try result(&scope, c.pi_js_undefined(), true)) else c.pi_js_undefined();
    }
    if (job == null or job.?.closed) return resolved(engine, try result(&scope, c.pi_js_undefined(), true));
    var caps: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &caps));
    errdefer engine.freeValue(promise);
    var attached = false;
    errdefer if (!attached) for (caps) |value| engine.freeValue(value);
    try job.?.waiters.append(engine.gpa, .{ .resolve = caps[0], .reject = caps[1] });
    attached = true;
    return promise;
}
fn headValue(scope: *Scope, head: raw.Head) !c.JSValue {
    const value = try scope.object();
    const headers = try scope.object();
    try scope.put(value, "status", c.JS_NewInt32(scope.engine.context, head.status));
    for (head.headers) |entry| {
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const name = try scope.engine.gpa.dupe(u8, entry.name);
        defer scope.engine.gpa.free(name);
        for (name) |*byte| byte.* = std.ascii.toLower(byte.*);
        const key = try row.text(name);
        const text = try row.text(entry.value);
        const existing = try row.own(try js.getKey(scope.engine, headers, key));
        const combined = if (c.JS_IsUndefined(existing)) text else try row.concat(try row.concat(existing, try row.text(", ")), text);
        try js.setKey(scope.engine, headers, key, combined);
    }
    try scope.put(value, "headers", headers);
    return value;
}
fn frameValue(scope: *Scope, event: raw.Event) !c.JSValue {
    const value = try scope.object();
    switch (event) {
        .frame => |frame| {
            try scope.put(value, "type", try scope.text("frame"));
            try scope.put(value, "event", if (frame.event) |name| try scope.text(name) else c.pi_js_null());
            try scope.put(value, "data", try scope.text(frame.data));
        },
        .error_body => |body| {
            try scope.put(value, "type", try scope.text("error_body"));
            try scope.put(value, "body", try scope.text(body));
        },
        else => unreachable,
    }
    return value;
}
fn failureValue(scope: *Scope, failure: anyerror) !c.JSValue {
    // Provider-specific SDK error conversion belongs above this private raw
    // boundary. Guest replacements of Error must not strand an I/O waiter.
    const value = try scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, c.pi_js_null())));
    try scope.put(value, "name", try scope.text("NativeHttpError"));
    try scope.put(value, "message", try scope.text(@errorName(failure)));
    try scope.put(value, "code", try scope.text(@errorName(failure)));
    return value;
}
pub fn pump(engine: *em.Engine) !bool {
    const state: *State = @ptrCast(@alignCast(engine.native_ai_http_state orelse return false));
    if (state.pumping) return false;
    state.pumping = true;
    defer state.pumping = false;
    var progressed = false;
    var index: usize = 0;
    while (index < state.jobs.items.len) {
        const job = state.jobs.items[index];
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        if (!temp.nullish(job.signal) and scope.truthy(try scope.get(job.signal, "aborted"))) job.worker.cancel();
        while (job.worker.peek()) |kind| {
            if (kind != .head and job.waiters.items.len == 0 and !job.closed) break;
            const event = job.worker.pop() orelse break;
            defer event.deinit();
            progressed = true;
            if (job.closed) continue;
            if (kind == .head) {
                if (!job.ready_settled) {
                    const head = try headValue(&scope, event.head);
                    try call(&scope, job.ready_resolve, head);
                    job.ready_settled = true;
                }
            } else {
                const waiter = job.waiters.orderedRemove(0);
                defer engine.freeValue(waiter.resolve);
                defer engine.freeValue(waiter.reject);
                const value = try frameValue(&scope, event);
                try call(&scope, waiter.resolve, try result(&scope, value, false));
            }
        }
        if (job.worker.finished.load(.acquire) and job.worker.peek() == null) {
            const failure = job.worker.failure;
            const reason = if (failure) |err| try failureValue(&scope, err) else c.pi_js_undefined();
            if (!job.ready_settled) {
                try call(&scope, job.ready_reject, if (failure != null) reason else try failureValue(&scope, error.NativeHttpNoResponse));
                job.ready_settled = true;
            }
            while (job.waiters.items.len != 0) {
                const waiter = job.waiters.orderedRemove(0);
                defer engine.freeValue(waiter.resolve);
                defer engine.freeValue(waiter.reject);
                try call(&scope, if (failure != null and !job.closed) waiter.reject else waiter.resolve, if (failure != null and !job.closed) reason else try result(&scope, c.pi_js_undefined(), true));
            }
            _ = state.jobs.orderedRemove(index);
            job.destroy(engine);
            progressed = true;
        } else index += 1;
    }
    return progressed;
}
