//! Owner-thread promises and session sockets for native Codex. The RFC6455
//! worker owns network state; all guest values and callbacks remain here.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const raw = @import("native_ai_codex_socket_worker.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const Waiter = struct { resolve: c.JSValue, reject: c.JSValue };
const Connection = struct {
    id: u64,
    worker: *raw.Worker,
    meta: c.JSValue,
    signal: c.JSValue,
    ready: ?Waiter,
    send_waiter: ?Waiter = null,
    read_waiter: ?Waiter = null,
    connected: bool = false,
    closed: bool = false,
    busy: bool = true,
    cached: bool = false,
    cache_current: bool = false,
    fn freeWaiter(engine: *v.em.Engine, waiter: ?Waiter) void {
        if (waiter) |w| {
            engine.freeValue(w.resolve);
            engine.freeValue(w.reject);
        }
    }
    fn destroy(self: *Connection, engine: *v.em.Engine) void {
        self.worker.destroy();
        engine.freeValue(self.meta);
        engine.freeValue(self.signal);
        freeWaiter(engine, self.ready);
        freeWaiter(engine, self.send_waiter);
        freeWaiter(engine, self.read_waiter);
        engine.gpa.destroy(self);
    }
};
const State = struct { connections: std.ArrayList(*Connection) = .empty, next_id: u64 = 0, pumping: bool = false };
fn stateFor(engine: *v.em.Engine) !*State {
    if (engine.native_ai_codex_socket_state) |ptr| return @ptrCast(@alignCast(ptr));
    const state = try engine.gpa.create(State);
    state.* = .{};
    engine.native_ai_codex_socket_state = state;
    engine.native_ai_codex_socket_cleanup = deinit;
    engine.native_ai_codex_socket_pump = pump;
    engine.native_ai_codex_socket_pending = pending;
    return state;
}
fn stateMaybe(engine: *v.em.Engine) ?*State {
    return if (engine.native_ai_codex_socket_state) |ptr| @ptrCast(@alignCast(ptr)) else null;
}
fn find(engine: *v.em.Engine, id: u64) ?*Connection {
    const state = stateMaybe(engine) orelse return null;
    for (state.connections.items) |connection| if (connection.id == id) return connection;
    return null;
}
pub fn pending(engine: *v.em.Engine) bool {
    const state = stateMaybe(engine) orelse return false;
    for (state.connections.items) |connection| if ((connection.busy and !connection.closed) or connection.ready != null or connection.send_waiter != null or connection.read_waiter != null) return true;
    return false;
}
pub fn deinit(engine: *v.em.Engine) void {
    const state = stateMaybe(engine) orelse return;
    engine.native_ai_codex_socket_state = null;
    engine.native_ai_codex_socket_cleanup = null;
    engine.native_ai_codex_socket_pump = null;
    engine.native_ai_codex_socket_pending = null;
    for (state.connections.items) |connection| connection.worker.cancel();
    for (state.connections.items) |connection| connection.destroy(engine);
    state.connections.deinit(engine.gpa);
    engine.gpa.destroy(state);
}
fn promise(scope: *Scope) !struct { value: c.JSValue, waiter: Waiter } {
    var caps: [2]c.JSValue = undefined;
    const raw_value = try scope.engine.checked(c.JS_NewPromiseCapability(scope.engine.context, &caps));
    errdefer for (caps) |cap| scope.engine.freeValue(cap);
    const value = try scope.own(raw_value);
    return .{ .value = value, .waiter = .{ .resolve = caps[0], .reject = caps[1] } };
}
fn settle(scope: *Scope, waiter: Waiter, value: c.JSValue, rejected: bool) !void {
    defer Connection.freeWaiter(scope.engine, waiter);
    _ = try scope.call(if (rejected) waiter.reject else waiter.resolve, c.pi_js_undefined(), &.{value});
}
fn result(scope: *Scope, value: c.JSValue, done: bool) !c.JSValue {
    const object = try scope.object();
    try scope.put(object, "value", value);
    try scope.put(object, "done", c.pi_js_bool(scope.engine.context, @intFromBool(done)));
    return object;
}
fn failure(scope: *Scope, err: anyerror) !c.JSValue {
    const object = try scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.text(@errorName(err))}));
    try scope.put(object, "name", try scope.text("NativeWebSocketError"));
    try scope.put(object, "message", try scope.text(@errorName(err)));
    try scope.put(object, "code", try scope.text(@errorName(err)));
    return object;
}
const Method = enum { send, next, release, close, expiry };
fn function(scope: *Scope, id: c.JSValue, comptime method: Method) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            var number: u64 = 0;
            if (c.JS_ToBigUint64(engine.context, &number, roots[0]) < 0) return v.js.capture(engine);
            return operation(&row, find(engine, number), method, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return scope.own(try @import("native_node_function.zig").create(scope.engine, @tagName(method), if (method == .send or method == .release) 1 else 0, Adapter.call, &.{id}));
}
fn clearIdleTimer(scope: *Scope, connection: *Connection) !void {
    const timer = try scope.get(connection.meta, "idleTimer");
    if (scope.truthy(timer)) {
        _ = try scope.call(try scope.global("clearTimeout"), c.pi_js_undefined(), &.{timer});
        try scope.put(connection.meta, "idleTimer", c.pi_js_undefined());
    }
}
fn scheduleExpiry(scope: *Scope, connection: *Connection) !void {
    try clearIdleTimer(scope, connection);
    const id = try scope.own(try scope.engine.checked(c.JS_NewBigUint64(scope.engine.context, connection.id)));
    const timeout = try scope.call(try scope.global("setTimeout"), c.pi_js_undefined(), &.{ try function(scope, id, .expiry), c.JS_NewInt32(scope.engine.context, 5 * 60 * 1000) });
    try scope.put(connection.meta, "idleTimer", timeout);
}
fn operation(scope: *Scope, maybe: ?*Connection, method: Method, argument: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const connection = maybe orelse {
        if (method == .next) return engine.checked(c.JS_PiPromiseResolve(engine.context, try result(scope, c.pi_js_undefined(), true)));
        if (method == .send) return error.NativeWebSocketClosed;
        return c.pi_js_undefined();
    };
    if (method == .close or method == .expiry or (method == .release and (!scope.truthy(argument) or !connection.cached))) {
        if (method == .expiry and connection.busy) return c.pi_js_undefined();
        try clearIdleTimer(scope, connection);
        connection.closed = true;
        connection.busy = false;
        connection.worker.cancel();
        return c.pi_js_undefined();
    }
    if (method == .release) {
        connection.busy = false;
        engine.freeValue(connection.signal);
        connection.signal = c.pi_js_undefined();
        try scheduleExpiry(scope, connection);
        return c.pi_js_undefined();
    }
    const created = try promise(scope);
    errdefer Connection.freeWaiter(engine, created.waiter);
    if (method == .send) {
        if (connection.send_waiter != null) return error.NativeWebSocketSendPending;
        const payload = try engine.toString(argument);
        defer engine.gpa.free(payload);
        try connection.worker.send(payload);
        connection.send_waiter = created.waiter;
    } else {
        if (connection.read_waiter != null) return error.NativeWebSocketReadPending;
        var milliseconds: i64 = 0;
        const configured = try scope.get(connection.meta, "readTimeoutMs");
        if (!v.nullish(configured) and c.JS_ToInt64(engine.context, &milliseconds, configured) < 0) return v.js.capture(engine);
        try connection.worker.read(@intCast(@max(0, milliseconds)));
        connection.read_waiter = created.waiter;
    }
    return c.JS_DupValue(engine.context, created.value);
}
pub fn acquire(engine: *v.em.Engine, input: raw.Input, session: c.JSValue, account: c.JSValue, signal: c.JSValue, read_timeout: c.JSValue) !c.JSValue {
    const state = try stateFor(engine);
    const io = engine.native_io orelse return error.NativeWebSocketIoRequired;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var connection: ?*Connection = null;
    if (scope.truthy(session)) for (state.connections.items) |candidate| {
        if (!candidate.cache_current or candidate.closed or !scope.equal(try scope.get(candidate.meta, "sessionId"), session) or !scope.equal(try scope.get(candidate.meta, "accountId"), account)) continue;
        try clearIdleTimer(&scope, candidate);
        if (!candidate.busy and !candidate.worker.finished.load(.acquire)) {
            const now = try scope.invoke(try scope.global("Date"), "now", &.{});
            const age = try scope.own(try arithmetic.binary(engine, .subtract, now, try scope.get(candidate.meta, "createdAt")));
            if (try arithmetic.compare(engine, .greater_equal, age, c.JS_NewInt32(engine.context, 55 * 60 * 1000))) {
                candidate.closed = true;
                candidate.worker.cancel();
                continue;
            }
            connection = candidate;
        }
        break;
    };
    if (connection) |existing| {
        errdefer {
            existing.closed = true;
            existing.busy = false;
            existing.worker.cancel();
        }
        const ready = try scope.own(try engine.checked(c.JS_PiPromiseResolve(engine.context, c.pi_js_undefined())));
        const output = try createOutput(&scope, existing.id, existing.meta, ready, existing.cached, true);
        try scope.put(existing.meta, "readTimeoutMs", read_timeout);
        existing.busy = true;
        engine.freeValue(existing.signal);
        existing.signal = c.JS_DupValue(engine.context, signal);
        return c.JS_DupValue(engine.context, output);
    } else {
        try state.connections.ensureUnusedCapacity(engine.gpa, 1);
        const meta = try scope.object();
        try scope.put(meta, "createdAt", c.pi_js_undefined());
        try scope.put(meta, "sessionId", session);
        try scope.put(meta, "accountId", account);
        try scope.put(meta, "readTimeoutMs", read_timeout);
        const created = try promise(&scope);
        errdefer Connection.freeWaiter(engine, created.waiter);
        const fresh = try engine.gpa.create(Connection);
        errdefer engine.gpa.destroy(fresh);
        var cached = scope.truthy(session);
        if (cached) for (state.connections.items) |entry| if (entry.cache_current and !entry.closed and scope.equal(try scope.get(entry.meta, "sessionId"), session) and scope.equal(try scope.get(entry.meta, "accountId"), account)) {
            cached = false;
            break;
        };
        state.next_id +%= 1;
        if (state.next_id == 0) state.next_id = 1;
        // Finish every fallible owner/VM allocation before starting network I/O.
        const output = try createOutput(&scope, state.next_id, meta, created.value, cached, false);
        const worker = try raw.Worker.create(io, input, engine, v.em.Engine.notifyOwner);
        fresh.* = .{ .id = state.next_id, .worker = worker, .meta = c.JS_DupValue(engine.context, meta), .signal = c.JS_DupValue(engine.context, signal), .ready = created.waiter, .cached = cached };
        state.connections.appendAssumeCapacity(fresh);
        return c.JS_DupValue(engine.context, output);
    }
}
fn createOutput(scope: *Scope, connection_id: u64, meta: c.JSValue, ready: c.JSValue, cached: bool, reused: bool) !c.JSValue {
    const engine = scope.engine;
    const id = try scope.own(try engine.checked(c.JS_NewBigUint64(engine.context, connection_id)));
    const output = try scope.object();
    const iterator = try scope.object();
    try scope.put(iterator, "next", try function(scope, id, .next));
    try scope.put(output, "ready", ready);
    try scope.put(output, "events", iterator);
    try scope.put(output, "meta", meta);
    try scope.put(output, "cached", c.pi_js_bool(engine.context, @intFromBool(cached)));
    try scope.put(output, "reused", c.pi_js_bool(engine.context, @intFromBool(reused)));
    inline for (.{ .send, .release, .close }) |method| try scope.put(output, @tagName(method), try function(scope, id, method));
    return output;
}
pub fn pump(engine: *v.em.Engine) !bool {
    const state = stateMaybe(engine) orelse return false;
    if (state.pumping) return false;
    state.pumping = true;
    defer state.pumping = false;
    var progressed = false;
    var index: usize = 0;
    while (index < state.connections.items.len) {
        const connection = state.connections.items[index];
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        if (connection.busy and scope.truthy(try v.optional(&scope, connection.signal, "aborted"))) {
            connection.closed = true;
            connection.worker.cancel();
        }
        while (connection.worker.pop()) |event| {
            defer event.deinit();
            progressed = true;
            switch (event) {
                .connected => {
                    connection.connected = true;
                    if (connection.cached) {
                        try scope.put(connection.meta, "createdAt", try scope.invoke(try scope.global("Date"), "now", &.{}));
                        // Source publishes the cache entry only after connect.
                        // Simultaneous initial connects can both own entries;
                        // retain both workers even when the later entry replaces
                        // the map selection so cleanup cannot leak either one.
                        const session = try scope.get(connection.meta, "sessionId");
                        const account = try scope.get(connection.meta, "accountId");
                        for (state.connections.items) |other| if (other.cache_current and scope.equal(try scope.get(other.meta, "sessionId"), session) and scope.equal(try scope.get(other.meta, "accountId"), account)) {
                            other.cache_current = false;
                        };
                        connection.cache_current = true;
                    }
                    if (connection.ready) |waiter| {
                        connection.ready = null;
                        try settle(&scope, waiter, c.pi_js_undefined(), false);
                    }
                },
                .sent => if (connection.send_waiter) |waiter| {
                    connection.send_waiter = null;
                    try settle(&scope, waiter, c.pi_js_undefined(), false);
                },
                .message => |bytes| if (connection.read_waiter) |waiter| {
                    connection.read_waiter = null;
                    try settle(&scope, waiter, try result(&scope, try scope.text(bytes), false), false);
                },
            }
        }
        if (connection.worker.finished.load(.acquire)) {
            const reason = try failure(&scope, connection.worker.failure orelse error.NativeWebSocketClosed);
            inline for (.{ "ready", "send_waiter", "read_waiter" }) |field| if (@field(connection, field)) |waiter| {
                @field(connection, field) = null;
                try settle(&scope, waiter, reason, true);
            };
            _ = state.connections.orderedRemove(index);
            connection.destroy(engine);
            progressed = true;
        } else index += 1;
    }
    return progressed;
}
pub fn closeSession(engine: *v.em.Engine, session: c.JSValue) !void {
    const state = stateMaybe(engine) orelse return;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    for (state.connections.items) |connection| if (v.nullish(session) or scope.equal(try scope.get(connection.meta, "sessionId"), session)) {
        try clearIdleTimer(&scope, connection);
        connection.closed = true;
        connection.busy = false;
        connection.worker.cancel();
    };
}
