//! ChatGPT registration callback listener. No VM values cross the owned I/O tasks.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const sdk = @import("native_sdk.zig");
const parser = @import("url_parser.zig");
const params = @import("url_search_params.zig");
const c = v.c;
const a = std.heap.page_allocator;
pub const redirect_uri = "http://127.0.0.1:1455/auth/callback";
const Result = struct { code: []u8, client_id: []u8 };
const Worker = struct {
    io: std.Io,
    engine: *v.em.Engine,
    listener: std.Io.net.Server,
    state: []u8,
    future: ?std.Io.Future(void) = null,
    mutex: std.Io.Mutex = .init,
    result: ?Result = null,
    failure: ?[]u8 = null,
    settled: std.atomic.Value(bool) = .init(false),
    active_connections: std.atomic.Value(usize) = .init(0),
    fn destroy(self: *Worker) void {
        if (self.future) |*future| future.cancel(self.io);
        self.listener.deinit(self.io);
        a.free(self.state);
        if (self.result) |result| {
            a.free(result.code);
            a.free(result.client_id);
        }
        if (self.failure) |failure| a.free(failure);
        a.destroy(self);
    }
    fn fail(self: *Worker, message: []const u8) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.settled.load(.acquire)) return;
        self.failure = a.dupe(u8, message) catch return;
        self.settled.store(true, .release);
        v.em.Engine.notifyOwner(self.engine);
    }
    fn serve(self: *Worker) void {
        var group: std.Io.Group = .init;
        defer group.cancel(self.io);
        while (true) {
            const stream = self.listener.accept(self.io) catch |err| {
                if (err != error.Canceled) self.fail(@errorName(err));
                return;
            };
            if (self.active_connections.fetchAdd(1, .acq_rel) >= 32) {
                _ = self.active_connections.fetchSub(1, .acq_rel);
                stream.close(self.io);
                continue;
            }
            group.concurrent(self.io, handle, .{ self, stream }) catch |err| {
                _ = self.active_connections.fetchSub(1, .acq_rel);
                stream.close(self.io);
                self.fail(@errorName(err));
                return;
            };
        }
    }
    fn handle(self: *Worker, stream: std.Io.net.Stream) std.Io.Cancelable!void {
        defer _ = self.active_connections.fetchSub(1, .acq_rel);
        defer stream.close(self.io);
        var rb: [8192]u8 = undefined;
        var wb: [8192]u8 = undefined;
        var reader = stream.reader(self.io, &rb);
        var writer = stream.writer(self.io, &wb);
        var server = std.http.Server.init(&reader.interface, &writer.interface);
        var request = server.receiveHead() catch return;
        var base = parser.parse(a, redirect_uri, null) catch return;
        defer base.deinit(a);
        var url = parser.parse(a, request.head.target, &base) catch {
            respond(&request, .internal_server_error, false, "Internal error while processing the callback.", null) catch {};
            return;
        };
        defer url.deinit(a);
        if (!std.mem.eql(u8, url.path, "/auth/callback")) {
            respond(&request, .not_found, false, "Callback route not found.", null) catch {};
            return;
        }
        var query = params.parse(a, url.query orelse "") catch return;
        defer params.freePairs(a, &query);
        const oauth_error = get(query.items, "error");
        if (oauth_error.len != 0) {
            const details = std.fmt.allocPrint(a, "Error: {s}", .{oauth_error}) catch return;
            defer a.free(details);
            respond(&request, .bad_request, false, "ChatGPT was not connected.", details) catch {};
            const message = std.fmt.allocPrint(a, "ChatGPT authorization failed: {s}", .{oauth_error}) catch return;
            defer a.free(message);
            self.fail(message);
            return;
        }
        const code = get(query.items, "code");
        const state = get(query.items, "state");
        const client_id = trim(get(query.items, "client_id"));
        const invalid: ?[]const u8 = if (code.len == 0) "Missing authorization code" else if (state.len == 0) "Missing OAuth state" else if (!std.mem.eql(u8, state, self.state)) "OAuth state mismatch" else if (client_id.len == 0) "OpenAI OAuth registration callback did not contain an issued client ID" else null;
        if (invalid) |message| {
            respond(&request, .bad_request, false, message, null) catch {};
            return;
        }
        respond(&request, .ok, true, "ChatGPT authentication completed. You can close this window.", null) catch {};
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.settled.load(.acquire)) return;
        const owned_code = a.dupe(u8, code) catch return;
        const owned_id = a.dupe(u8, client_id) catch {
            a.free(owned_code);
            return;
        };
        self.result = .{ .code = owned_code, .client_id = owned_id };
        self.settled.store(true, .release);
        v.em.Engine.notifyOwner(self.engine);
    }
};
fn get(pairs: []const params.Pair, name: []const u8) []const u8 {
    for (pairs) |pair| if (std.mem.eql(u8, pair.name, name)) return pair.value;
    return "";
}
fn trim(value: []const u8) []const u8 {
    const view = std.unicode.Utf8View.init(value) catch return value;
    var iterator = view.iterator();
    var offset: usize = 0;
    var start: usize = value.len;
    var end: usize = 0;
    while (iterator.nextCodepointSlice()) |bytes| {
        const point = std.unicode.utf8Decode(bytes) catch unreachable;
        const white = switch (point) {
            0x09...0x0d, 0x20, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => true,
            else => false,
        };
        if (!white) {
            start = @min(start, offset);
            end = offset + bytes.len;
        }
        offset += bytes.len;
    }
    return if (start == value.len) value[0..0] else value[start..end];
}
fn escaped(value: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    for (value) |byte| try out.appendSlice(a, switch (byte) {
        '&' => "&amp;",
        '<' => "&lt;",
        '>' => "&gt;",
        '"' => "&quot;",
        '\'' => "&#39;",
        else => &.{byte},
    });
    return out.toOwnedSlice(a);
}
fn replace(input: []const u8, marker: []const u8, value: []const u8) ![]u8 {
    return std.mem.replaceOwned(u8, a, input, marker, value);
}
fn page(success: bool, message: []const u8, details: ?[]const u8) ![]u8 {
    const title = if (success) "Authentication successful" else "Authentication failed";
    const first = try replace(@embedFile("native_ai_oauth_chatgpt_page.html"), "@@TITLE@@", title);
    defer a.free(first);
    const safe_message = try escaped(message);
    defer a.free(safe_message);
    const second = try replace(first, "@@MESSAGE@@", safe_message);
    defer a.free(second);
    const safe_details = try escaped(details orelse "");
    defer a.free(safe_details);
    const detail_block = if (safe_details.len != 0) try std.fmt.allocPrint(a, "<div class=\"details\">{s}</div>", .{safe_details}) else try a.dupe(u8, "");
    defer a.free(detail_block);
    return replace(second, "@@DETAILS@@", detail_block);
}
fn respond(request: *std.http.Server.Request, status: std.http.Status, success: bool, message: []const u8, details: ?[]const u8) !void {
    const body = try page(success, message, details);
    defer a.free(body);
    try request.respond(body, .{ .status = status, .extra_headers = &.{.{ .name = "Content-Type", .value = "text/html; charset=utf-8" }}, .keep_alive = false });
}
const Entry = struct { id: u32, worker: *Worker, resolve: c.JSValue, reject: c.JSValue, reported: bool = false };
const State = struct { entries: std.ArrayList(Entry) = .empty, sequence: u32 = 0 };
fn stateFor(engine: *v.em.Engine) !*State {
    if (engine.native_ai_oauth_chatgpt_state) |state| return @ptrCast(@alignCast(state));
    const state = try engine.gpa.create(State);
    state.* = .{};
    engine.native_ai_oauth_chatgpt_state = state;
    engine.native_ai_oauth_chatgpt_pump = pump;
    engine.native_ai_oauth_chatgpt_pending = pending;
    engine.native_ai_oauth_chatgpt_cleanup = cleanup;
    return state;
}
pub fn pending(engine: *v.em.Engine) bool {
    const state: *State = @ptrCast(@alignCast(engine.native_ai_oauth_chatgpt_state orelse return false));
    return state.entries.items.len != 0;
}
pub fn cleanup(engine: *v.em.Engine) void {
    const state: *State = @ptrCast(@alignCast(engine.native_ai_oauth_chatgpt_state orelse return));
    for (state.entries.items) |entry| {
        entry.worker.destroy();
        engine.freeValue(entry.resolve);
        engine.freeValue(entry.reject);
    }
    state.entries.deinit(engine.gpa);
    engine.gpa.destroy(state);
    engine.native_ai_oauth_chatgpt_state = null;
}
fn close(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, id: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = v.em.Engine.fromContext(context.?);
    const state: *State = @ptrCast(@alignCast(engine.native_ai_oauth_chatgpt_state orelse return c.pi_js_undefined()));
    for (state.entries.items, 0..) |entry, index| if (entry.id == @as(u32, @bitCast(id))) {
        const removed = state.entries.swapRemove(index);
        removed.worker.destroy();
        engine.freeValue(removed.resolve);
        engine.freeValue(removed.reject);
        break;
    };
    return c.pi_js_undefined();
}
pub fn open(engine: *v.em.Engine, expected_state: []const u8, host: []const u8, port: u16) !c.JSValue {
    const io = engine.native_io orelse return error.NativeHttpIoRequired;
    const state = try stateFor(engine);
    if (state.entries.items.len >= 16) return error.OAuthCallbackLimit;
    try state.entries.ensureUnusedCapacity(engine.gpa, 1);
    const address = try std.Io.net.IpAddress.parse(if (std.ascii.eqlIgnoreCase(host, "localhost")) "127.0.0.1" else host, port);
    const worker = try a.create(Worker);
    errdefer a.destroy(worker);
    const owned_state = try a.dupe(u8, expected_state);
    errdefer a.free(owned_state);
    worker.* = .{ .io = io, .engine = engine, .state = owned_state, .listener = try address.listen(io, .{ .reuse_address = false }) };
    errdefer worker.listener.deinit(io);
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    var caps: [2]c.JSValue = undefined;
    const promise = try scope.own(try engine.checked(c.JS_NewPromiseCapability(engine.context, &caps)));
    errdefer for (caps) |value| engine.freeValue(value);
    const object = try scope.object();
    state.sequence +%= 1;
    try scope.put(object, "result", promise);
    try scope.put(object, "port", c.JS_NewInt32(engine.context, worker.listener.socket.address.getPort()));
    try scope.put(object, "close", try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, close, "close", 0, @bitCast(state.sequence), 0, null))));
    worker.future = try io.concurrent(Worker.serve, .{worker});
    state.entries.appendAssumeCapacity(.{ .id = state.sequence, .worker = worker, .resolve = caps[0], .reject = caps[1] });
    return c.JS_DupValue(engine.context, object);
}
pub fn pump(engine: *v.em.Engine) !bool {
    const state: *State = @ptrCast(@alignCast(engine.native_ai_oauth_chatgpt_state orelse return false));
    var progressed = false;
    for (state.entries.items) |*entry| {
        if (entry.reported or !entry.worker.settled.load(.acquire)) continue;
        var scope: v.Scope = .{ .engine = engine };
        defer scope.deinit();
        const value = if (entry.worker.failure) |message| try scope.own(try v.js.builtin(engine, "Error", &.{try scope.text(message)})) else result: {
            const output = try scope.object();
            try scope.put(output, "code", try scope.text(entry.worker.result.?.code));
            try scope.put(output, "clientId", try scope.text(entry.worker.result.?.client_id));
            break :result output;
        };
        entry.reported = true;
        _ = try scope.call(if (entry.worker.failure != null) entry.reject else entry.resolve, c.pi_js_undefined(), &.{value});
        progressed = true;
    }
    return progressed;
}
