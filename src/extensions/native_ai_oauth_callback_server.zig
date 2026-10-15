//! Shared source-faithful OAuth callback server. Workers own only bytes and I/O;
//! request validation and complete(code) run exclusively on the VM owner.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const flow = @import("native_agent_async.zig");
const helpers = @import("native_ai_auth_helpers.zig");
const functions = @import("native_node_function.zig");
const c = v.c;
const a = std.heap.page_allocator;
const Request = struct {
    refs: std.atomic.Value(usize) = .init(2),
    method: []u8,
    target: []u8,
    ready: std.atomic.Value(bool) = .init(false),
    status: std.http.Status = .internal_server_error,
    body: ?[]u8 = null,
    fn release(self: *Request) void {
        if (self.refs.fetchSub(1, .acq_rel) != 1) return;
        a.free(self.method);
        a.free(self.target);
        if (self.body) |body| a.free(body);
        a.destroy(self);
    }
};
const Worker = struct {
    io: std.Io,
    engine: *v.em.Engine,
    listener: std.Io.net.Server,
    mutex: std.Io.Mutex = .init,
    queue: std.ArrayList(*Request) = .empty,
    future: ?std.Io.Future(void) = null,
    failure: ?[]u8 = null,
    active: std.atomic.Value(usize) = .init(0),
    closing: std.atomic.Value(bool) = .init(false),
    listener_owned: std.atomic.Value(bool) = .init(true),
    fn destroy(self: *Worker) void {
        if (self.future) |*future| future.cancel(self.io);
        self.closeListener();
        for (self.queue.items) |request| request.release();
        self.queue.deinit(a);
        if (self.failure) |message| a.free(message);
        a.destroy(self);
    }
    fn closeListener(self: *Worker) void {
        if (self.listener_owned.swap(false, .acq_rel)) self.listener.deinit(self.io);
    }
    fn stopAccept(self: *Worker) void {
        if (self.closing.swap(true, .acq_rel)) return;
        if (!self.listener_owned.load(.acquire)) return;
        const wake = self.listener.socket.address.connect(self.io, .{ .mode = .stream, .protocol = .tcp }) catch {
            if (self.future) |*future| future.cancel(self.io);
            return;
        };
        wake.close(self.io);
    }
    fn fail(self: *Worker, err: anyerror) void {
        if (err == error.Canceled) return;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.failure == null) self.failure = a.dupe(u8, @errorName(err)) catch return;
        v.em.Engine.notifyOwner(self.engine);
    }
    fn serve(self: *Worker) void {
        defer self.closeListener();
        var handlers: std.Io.Group = .init;
        defer handlers.cancel(self.io);
        while (true) {
            const stream = self.listener.accept(self.io) catch |err| {
                self.fail(err);
                return;
            };
            if (self.closing.load(.acquire)) {
                stream.close(self.io);
                self.closeListener();
                // Source server.close stops accepting while an already claimed
                // async complete may still send its final browser response.
                handlers.await(self.io) catch {};
                return;
            }
            if (self.active.fetchAdd(1, .acq_rel) >= 32) {
                _ = self.active.fetchSub(1, .acq_rel);
                stream.close(self.io);
                continue;
            }
            handlers.concurrent(self.io, handle, .{ self, stream }) catch |err| {
                _ = self.active.fetchSub(1, .acq_rel);
                stream.close(self.io);
                self.fail(err);
                return;
            };
        }
    }
    fn handle(self: *Worker, stream: std.Io.net.Stream) std.Io.Cancelable!void {
        defer stream.close(self.io);
        defer _ = self.active.fetchSub(1, .acq_rel);
        var rb: [8192]u8 = undefined;
        var wb: [8192]u8 = undefined;
        var reader = stream.reader(self.io, &rb);
        var writer = stream.writer(self.io, &wb);
        var server = std.http.Server.init(&reader.interface, &writer.interface);
        var incoming = server.receiveHead() catch return;
        const request = a.create(Request) catch return;
        const method = a.dupe(u8, @tagName(incoming.head.method)) catch {
            a.destroy(request);
            return;
        };
        const target = a.dupe(u8, incoming.head.target) catch {
            a.free(method);
            a.destroy(request);
            return;
        };
        request.* = .{ .method = method, .target = target };
        defer request.release();
        self.mutex.lockUncancelable(self.io);
        self.queue.append(a, request) catch {
            self.mutex.unlock(self.io);
            request.release();
            return;
        };
        self.mutex.unlock(self.io);
        v.em.Engine.notifyOwner(self.engine);
        while (!request.ready.load(.acquire)) try self.io.sleep(.fromMilliseconds(1), .awake);
        incoming.respond(request.body orelse "", .{ .status = request.status, .keep_alive = false, .extra_headers = &.{
            .{ .name = "content-type", .value = "text/html; charset=utf-8" },
            .{ .name = "cache-control", .value = "no-store" },
        } }) catch {};
    }
};
const Entry = struct {
    owner: c.JSValue,
    worker: ?*Worker,
    requests: std.AutoHashMapUnmanaged(u32, *Request) = .empty,
    next_request: u32 = 0,
};
const State = struct { entries: std.ArrayList(*Entry) = .empty };
fn stateFor(engine: *v.em.Engine) !*State {
    if (engine.native_ai_oauth_callback_state) |raw| return @ptrCast(@alignCast(raw));
    const state = try engine.gpa.create(State);
    state.* = .{};
    engine.native_ai_oauth_callback_state = state;
    engine.native_ai_oauth_callback_pump = pump;
    engine.native_ai_oauth_callback_pending = pending;
    engine.native_ai_oauth_callback_cleanup = cleanup;
    return state;
}
fn entryFor(engine: *v.em.Engine, owner: c.JSValue) ?*Entry {
    const state: *State = @ptrCast(@alignCast(engine.native_ai_oauth_callback_state orelse return null));
    for (state.entries.items) |entry| if (c.JS_IsStrictEqual(engine.context, entry.owner, owner)) return entry;
    return null;
}
pub fn pending(engine: *v.em.Engine) bool {
    const state: *State = @ptrCast(@alignCast(engine.native_ai_oauth_callback_state orelse return false));
    for (state.entries.items) |entry| if (entry.worker) |worker| if (!worker.closing.load(.acquire) or worker.active.load(.acquire) != 0) return true;
    return false;
}
pub fn cleanup(engine: *v.em.Engine) void {
    const state: *State = @ptrCast(@alignCast(engine.native_ai_oauth_callback_state orelse return));
    for (state.entries.items) |entry| {
        if (entry.worker) |worker| worker.destroy();
        var requests = entry.requests.valueIterator();
        while (requests.next()) |request| request.*.release();
        entry.requests.deinit(engine.gpa);
        engine.freeValue(entry.owner);
        engine.gpa.destroy(entry);
    }
    state.entries.deinit(engine.gpa);
    engine.gpa.destroy(state);
    engine.native_ai_oauth_callback_state = null;
}
fn errorValue(scope: *v.Scope, message: c.JSValue) !c.JSValue {
    return scope.own(try v.js.builtin(scope.engine, "Error", &.{message}));
}
fn normalizeError(scope: *v.Scope, value: c.JSValue) !c.JSValue {
    const is_error = c.JS_IsInstanceOf(scope.engine.context, value, try scope.global("Error"));
    if (is_error < 0) return v.js.capture(scope.engine);
    return if (is_error != 0) value else errorValue(scope, try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{value}));
}
fn finish(scope: *v.Scope, owner: c.JSValue, rejected: bool, value: c.JSValue) !void {
    if (scope.truthy(try scope.get(owner, "settled"))) return;
    try scope.put(owner, "settled", c.pi_js_bool(scope.engine.context, 1));
    const timer = try scope.get(owner, "timer");
    if (scope.truthy(timer)) _ = try scope.call(try scope.global("clearTimeout"), c.pi_js_undefined(), &.{timer});
    const signal = try scope.get(owner, "signal");
    if (!v.nullish(signal)) _ = try scope.invoke(signal, "removeEventListener", &.{ try scope.text("abort"), try scope.get(owner, "onAbort") });
    try flow.settle(scope.engine, owner, rejected, value);
}
fn waitMethod(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(engine.context, try scope.get(roots[0], "promise"));
}
fn cancelMethod(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!scope.truthy(try scope.get(roots[0], "claimed"))) try finish(&scope, roots[0], false, c.pi_js_undefined());
    return c.pi_js_undefined();
}
fn closeMethod(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    try finish(&scope, roots[0], true, try errorValue(&scope, try scope.text("OAuth callback server closed")));
    if (entryFor(engine, roots[0])) |entry| if (entry.worker) |worker| {
        worker.stopAccept();
    };
    return c.pi_js_undefined();
}
fn abortMethod(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    try finish(&scope, roots[0], true, try errorValue(&scope, try scope.text("Login cancelled")));
    return c.pi_js_undefined();
}
fn timerMethod(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    try finish(&scope, roots[0], true, try errorValue(&scope, try scope.concat(try scope.stringify(try scope.get(roots[0], "providerName")), try scope.text(" sign-in timed out"))));
    return c.pi_js_undefined();
}
pub fn start(engine: *v.em.Engine, options: c.JSValue) !c.JSValue {
    const result = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(result.owner);
    errdefer engine.freeValue(result.promise);
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    startBody(&scope, result.owner, options) catch |err| try flow.rejectError(engine, result.owner, err);
    return result.promise;
}
pub const startOAuthCallbackServer = start;
fn startBody(scope: *v.Scope, result: c.JSValue, options: c.JSValue) !void {
    const engine = scope.engine;
    const provider = try scope.get(options, "providerName");
    const signal = try scope.get(options, "signal");
    if (!v.nullish(signal) and scope.truthy(try scope.get(signal, "aborted"))) return v.errorText(scope, try scope.text("Login cancelled"));
    const wait = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(wait.owner);
    defer engine.freeValue(wait.promise);
    c.JS_PromiseMarkAsHandled(engine.context, wait.promise);
    try scope.put(wait.owner, "options", options);
    try scope.put(wait.owner, "providerName", provider);
    try scope.put(wait.owner, "signal", signal);
    try scope.put(wait.owner, "promise", wait.promise);
    const on_abort = try scope.own(try functions.createArrow(engine, "onAbort", 0, abortMethod, &.{wait.owner}));
    try scope.put(wait.owner, "onAbort", on_abort);
    const io = engine.native_io orelse return error.NativeHttpIoRequired;
    var port: u32 = 0;
    if (c.JS_ToUint32(engine.context, &port, try scope.get(options, "port")) < 0) return v.js.capture(engine);
    if (port > 65535) return error.InvalidPort;
    const host_value = try scope.get(options, "host");
    const host = try engine.toString(try scope.stringify(host_value));
    defer engine.gpa.free(host);
    const address = try std.Io.net.IpAddress.parse(if (std.ascii.eqlIgnoreCase(host, "localhost")) "127.0.0.1" else std.mem.trim(u8, host, "[]"), @intCast(port));
    const worker = try a.create(Worker);
    errdefer a.destroy(worker);
    worker.* = .{ .io = io, .engine = engine, .listener = try address.listen(io, .{ .reuse_address = false }) };
    errdefer worker.listener.deinit(io);
    const state = try stateFor(engine);
    const entry = try engine.gpa.create(Entry);
    errdefer engine.gpa.destroy(entry);
    entry.* = .{ .owner = c.JS_DupValue(engine.context, wait.owner), .worker = worker };
    errdefer engine.freeValue(entry.owner);
    try state.entries.ensureUnusedCapacity(engine.gpa, 1);
    if (!v.nullish(signal)) {
        const once = try scope.object();
        try scope.put(once, "once", c.pi_js_bool(engine.context, 1));
        _ = try scope.invoke(signal, "addEventListener", &.{ try scope.text("abort"), on_abort, once });
    }
    const timeout = try scope.get(options, "timeoutMs");
    if (!c.JS_IsUndefined(timeout)) try scope.put(wait.owner, "timer", try scope.call(try scope.global("setTimeout"), c.pi_js_undefined(), &.{ try scope.own(try functions.createArrow(engine, "", 0, timerMethod, &.{wait.owner})), try scope.get(options, "timeoutMs") }));
    var redirect = try scope.get(options, "redirectHost");
    if (v.nullish(redirect)) redirect = try scope.get(options, "host");
    const ipv6 = scope.truthy(try scope.invoke(redirect, "includes", &.{try scope.text(":")}));
    const redirect_text = try engine.toString(try scope.stringify(redirect));
    defer engine.gpa.free(redirect_text);
    const path = try engine.toString(try scope.stringify(try scope.get(options, "path")));
    defer engine.gpa.free(path);
    const uri = try std.fmt.allocPrint(engine.gpa, "http://{s}{s}{s}:{d}{s}", .{ if (ipv6) "[" else "", redirect_text, if (ipv6) "]" else "", worker.listener.socket.address.getPort(), path });
    defer engine.gpa.free(uri);
    const callback = try scope.object();
    try scope.put(callback, "redirectUri", try scope.text(uri));
    inline for (.{ "wait", "cancel", "close" }, .{ waitMethod, cancelMethod, closeMethod }) |name, method| try scope.put(callback, name, try scope.own(try functions.createArrow(engine, name, 0, method, &.{wait.owner})));
    worker.future = try io.concurrent(Worker.serve, .{worker});
    state.entries.appendAssumeCapacity(entry);
    try flow.settle(engine, result, false, callback);
}
fn escape(input: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    for (input) |byte| try out.appendSlice(a, switch (byte) {
        '&' => "&amp;",
        '<' => "&lt;",
        '>' => "&gt;",
        '"' => "&quot;",
        '\'' => "&#39;",
        else => &.{byte},
    });
    return out.toOwnedSlice(a);
}
fn page(success: bool, message: []const u8, details: ?[]const u8) ![]u8 {
    const title = if (success) "Authentication successful" else "Authentication failed";
    const first = try std.mem.replaceOwned(u8, a, @embedFile("native_ai_oauth_callback_page.html"), "@@TITLE@@", title);
    defer a.free(first);
    const safe = try escape(message);
    defer a.free(safe);
    const second = try std.mem.replaceOwned(u8, a, first, "@@MESSAGE@@", safe);
    defer a.free(second);
    const safe_detail = try escape(details orelse "");
    defer a.free(safe_detail);
    const detail = if (safe_detail.len != 0) try std.fmt.allocPrint(a, "<div class=\"details\">{s}</div>", .{safe_detail}) else try a.dupe(u8, "");
    defer a.free(detail);
    return std.mem.replaceOwned(u8, a, second, "@@DETAILS@@", detail);
}
fn respond(request: *Request, status: std.http.Status, success: bool, message: []const u8, detail: ?[]const u8) !void {
    request.body = try page(success, message, detail);
    request.status = status;
    request.ready.store(true, .release);
}
fn respondJS(scope: *v.Scope, request: *Request, status: std.http.Status, success: bool, message: c.JSValue, detail: ?c.JSValue) !void {
    const text = try scope.engine.toString(try scope.stringify(message));
    defer scope.engine.gpa.free(text);
    const details = if (detail) |value| try scope.engine.toString(try scope.stringify(value)) else null;
    defer if (details) |bytes| scope.engine.gpa.free(bytes);
    try respond(request, status, success, text, details);
}
pub fn pump(engine: *v.em.Engine) !bool {
    const state: *State = @ptrCast(@alignCast(engine.native_ai_oauth_callback_state orelse return false));
    var progressed = false;
    // Entry pointers are stable across callbacks creating more listeners.
    var index: usize = 0;
    while (index < state.entries.items.len) : (index += 1) {
        const entry = state.entries.items[index];
        while (entry.worker) |worker| {
            worker.mutex.lockUncancelable(worker.io);
            const request = if (worker.queue.items.len != 0) worker.queue.orderedRemove(0) else null;
            const failure = if (worker.failure) |message| a.dupe(u8, message) catch null else null;
            worker.mutex.unlock(worker.io);
            defer if (failure) |message| a.free(message);
            var scope: v.Scope = .{ .engine = engine };
            defer scope.deinit();
            if (failure) |message| try finish(&scope, entry.owner, true, try errorValue(&scope, try scope.text(message)));
            const incoming = request orelse break;
            progressed = true;
            dispatch(&scope, entry, incoming) catch |err| {
                const reason = try scope.own(flow.reason(engine, err));
                if (!incoming.ready.load(.acquire)) try respond(incoming, .internal_server_error, false, "Internal error while processing the callback.", null);
                try finish(&scope, entry.owner, true, reason);
                incoming.release();
            };
        }
    }
    return progressed;
}
fn dispatch(scope: *v.Scope, entry: *Entry, request: *Request) !void {
    const options = try scope.get(entry.owner, "options");
    const url = try scope.own(try v.js.builtin(scope.engine, "URL", &.{ try scope.text(request.target), try scope.text("http://localhost") }));
    if (!std.mem.eql(u8, request.method, "GET") or !scope.equal(try scope.get(url, "pathname"), try scope.get(options, "path"))) {
        try respond(request, .not_found, false, "Callback route not found.", null);
        request.release();
        return;
    }
    const query = try scope.get(url, "searchParams");
    if (!c.JS_IsUndefined(try scope.get(options, "state")) and !scope.equal(try scope.invoke(query, "get", &.{try scope.text("state")}), try scope.get(options, "state"))) {
        try respond(request, .bad_request, false, "State mismatch.", null);
        request.release();
        return;
    }
    if (scope.truthy(try scope.get(entry.owner, "claimed")) or scope.truthy(try scope.get(entry.owner, "settled"))) {
        try respond(request, .conflict, false, "This sign-in has already been handled.", null);
        request.release();
        return;
    }
    const failure = try scope.invoke(query, "get", &.{try scope.text("error")});
    if (scope.truthy(failure)) {
        var description = try scope.invoke(query, "get", &.{try scope.text("error_description")});
        if (v.nullish(description)) description = failure;
        const name = try scope.stringify(try scope.get(entry.owner, "providerName"));
        try respondJS(scope, request, .bad_request, false, try scope.concat(name, try scope.text(" authorization failed.")), description);
        try finish(scope, entry.owner, true, try errorValue(scope, try scope.concat(try scope.concat(name, try scope.text(" authorization failed: ")), description)));
        request.release();
        return;
    }
    const code = try scope.invoke(query, "get", &.{try scope.text("code")});
    if (!scope.truthy(code)) {
        try respond(request, .bad_request, false, "Missing authorization code.", null);
        request.release();
        return;
    }
    try scope.put(entry.owner, "claimed", c.pi_js_bool(scope.engine.context, 1));
    entry.next_request +%= 1;
    const token = try scope.object();
    try scope.put(token, "owner", entry.owner);
    try scope.put(token, "request", c.JS_NewUint32(scope.engine.context, entry.next_request));
    try entry.requests.put(scope.engine.gpa, entry.next_request, request);
    const completed = scope.invoke(options, "complete", &.{code}) catch |err| {
        const reason = try scope.own(flow.reason(scope.engine, err));
        return completedStep(scope.engine, token, reason, true, 0);
    };
    try flow.wait(completedStep, scope.engine, token, completed, 0);
}
fn completedStep(engine: *v.em.Engine, token: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.get(token, "owner");
    const entry = entryFor(engine, owner) orelse return;
    var id: u32 = 0;
    if (c.JS_ToUint32(engine.context, &id, try scope.get(token, "request")) < 0) return v.js.capture(engine);
    const item = entry.requests.fetchRemove(id) orelse return;
    const request = item.value;
    defer request.release();
    const name = try scope.stringify(try scope.get(owner, "providerName"));
    if (rejected) {
        const failure = try normalizeError(&scope, value);
        try respondJS(&scope, request, .bad_gateway, false, try scope.concat(name, try scope.text(" sign-in failed.")), try scope.get(failure, "message"));
        return finish(&scope, owner, true, failure);
    }
    try respondJS(&scope, request, .ok, true, try scope.concat(try scope.concat(try scope.text("Signed in to "), name), try scope.text(". You may now close this page.")), null);
    try finish(&scope, owner, false, value);
}
const ManualStage = enum(c_int) { prompt, callback, manual };
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
pub fn waitForCallbackOrManualInput(engine: *v.em.Engine, interaction: c.JSValue, callback: c.JSValue, prompt: c.JSValue) !c.JSValue {
    const pending_result = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending_result.owner);
    errdefer engine.freeValue(pending_result.promise);
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    manualStart(&scope, pending_result.owner, interaction, callback, prompt) catch |err| try flow.rejectError(engine, pending_result.owner, err);
    return pending_result.promise;
}
fn manualStart(scope: *v.Scope, owner: c.JSValue, interaction: c.JSValue, callback: c.JSValue, prompt: c.JSValue) !void {
    const controller = try scope.own(try v.js.builtin(scope.engine, "AbortController", &.{}));
    try scope.put(owner, "manualAbort", controller);
    try scope.put(owner, "callback", callback);
    const method = try scope.get(interaction, "prompt");
    const input = try scope.object();
    try scope.put(input, "type", try scope.text("manual_code"));
    try v.js.spreadInto(scope.engine, input, prompt);
    try scope.put(input, "signal", try scope.get(controller, "signal"));
    // .prompt(...).then(...).catch(...) is evaluated before try/finally in Source.
    const returned = try scope.call(method, interaction, &.{input});
    const then = try scope.get(returned, "then");
    const on_prompt = try scope.own(try functions.createArrow(scope.engine, "", 1, manualFulfilled, &.{owner}));
    const chained = try scope.call(then, returned, &.{on_prompt});
    try scope.put(owner, "manual", try scope.invoke(chained, "catch", &.{try scope.own(try functions.createArrow(scope.engine, "", 1, manualRejected, &.{owner}))}));
    const awaited = if (v.nullish(callback)) c.pi_js_undefined() else scope.invoke(callback, "wait", &.{}) catch |err| {
        try manualFinally(scope, owner);
        return err;
    };
    try flow.wait(manualContinued, scope.engine, owner, awaited, @intFromEnum(ManualStage.callback));
}
fn manualCancel(scope: *v.Scope, owner: c.JSValue) !void {
    const callback = try scope.get(owner, "callback");
    if (!v.nullish(callback)) _ = try scope.invoke(callback, "cancel", &.{});
}
fn manualFulfilled(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    try manualCancel(&scope, roots[0]);
    return c.JS_DupValue(engine.context, argument(args, 0));
}
fn manualRejected(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(roots[0], "manualError", try normalizeError(&scope, argument(args, 0)));
    try manualCancel(&scope, roots[0]);
    return c.pi_js_undefined();
}
fn manualFinally(scope: *v.Scope, owner: c.JSValue) !void {
    _ = try scope.invoke(try scope.get(owner, "manualAbort"), "abort", &.{});
}
fn manualContinued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: ManualStage = @enumFromInt(raw);
    if (!rejected and stage == .callback and !scope.truthy(try scope.get(owner, "manualError")) and c.JS_IsUndefined(value)) {
        return flow.wait(manualContinued, engine, owner, try scope.get(owner, "manual"), @intFromEnum(ManualStage.manual));
    }
    var output = value;
    var failed = rejected;
    if (!failed) {
        const manual_error = try scope.get(owner, "manualError");
        if (scope.truthy(manual_error)) {
            output = manual_error;
            failed = true;
        } else {
            output = try scope.object();
            try scope.put(output, "type", try scope.text(if (stage == .callback) "callback" else "manual"));
            if (stage == .callback) try scope.put(output, "value", value) else try scope.put(output, "input", if (v.nullish(value)) try scope.text("") else value);
        }
    }
    manualFinally(&scope, owner) catch |err| {
        return flow.rejectError(engine, owner, err);
    };
    return flow.settle(engine, owner, failed, output);
}
fn exportedStart(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return start(engine, argument(args, 0));
}
fn exportedManual(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return waitForCallbackOrManualInput(engine, argument(args, 0), argument(args, 1), argument(args, 2));
}
pub fn create(engine: *v.em.Engine) !c.JSValue {
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const exports = try scope.object();
    try scope.put(exports, "startOAuthCallbackServer", try scope.own(try helpers.asyncArrow(engine, "startOAuthCallbackServer", 1, exportedStart, &.{})));
    try scope.put(exports, "waitForCallbackOrManualInput", try scope.own(try helpers.asyncArrow(engine, "waitForCallbackOrManualInput", 3, exportedManual, &.{})));
    return c.JS_DupValue(engine.context, exports);
}
