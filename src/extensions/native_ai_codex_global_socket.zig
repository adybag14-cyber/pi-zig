//! Caller-global WebSocket adapter. Constructor, events, binary/blob values,
//! promises, signals and cache entries stay on the owner thread as VM values.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const errors = @import("native_ai_codex_errors.zig");
const math = @import("native_image_arithmetic.zig");
const Method = enum { open, connect_error, connect_close, connect_abort, connect_timeout, send, next, release, close, expiry, message, parse_error, parse_close, parse_abort, idle_timeout };
fn callback(scope: *Scope, owner: c.JSValue, comptime method: Method) !c.JSValue {
    const Adapter = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            return invoke(&row, roots[0], method, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return scope.own(try @import("native_node_function.zig").createArrow(scope.engine, switch (method) {
        .open => "onOpen",
        .connect_error, .parse_error => "onError",
        .connect_close, .parse_close => "onClose",
        .connect_abort, .parse_abort => "onAbort",
        .message => "onMessage",
        else => @tagName(method),
    }, switch (method) {
        .send, .release, .message, .connect_error, .connect_close, .parse_error, .parse_close => 1,
        else => 0,
    }, Adapter.call, &.{owner}));
}
fn plainError(scope: *Scope, text: []const u8) !c.JSValue {
    return scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.text(text)}));
}
fn closeSilently(scope: *Scope, socket: c.JSValue, reason: []const u8) !void {
    const generation = scope.engine.native_allocation_generation;
    _ = scope.invoke(socket, "close", &.{ c.JS_NewInt32(scope.engine.context, 1000), try scope.text(reason) }) catch |err| try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
}
fn reusable(scope: *Scope, socket: c.JSValue) !bool {
    const state = try scope.get(socket, "readyState");
    return !c.JS_IsNumber(state) or scope.equal(state, c.JS_NewInt32(scope.engine.context, 1));
}
fn clearTimer(scope: *Scope, owner: c.JSValue, key: [*:0]const u8) !void {
    const timer = try scope.get(owner, key);
    if (scope.truthy(timer)) {
        _ = try scope.call(try scope.global("clearTimeout"), c.pi_js_undefined(), &.{timer});
        try scope.put(owner, key, c.pi_js_undefined());
    }
}
fn stateFor(scope: *Scope, protocol: c.JSValue) !c.JSValue {
    const existing = try v.optional(scope, protocol, "globalSockets");
    if (!v.nullish(existing)) return existing;
    const state = try scope.object();
    try scope.put(state, "cache", try scope.own(try v.js.builtin(scope.engine, "Map", &.{})));
    try scope.put(state, "owned", try scope.array());
    try scope.put(state, "classes", try scope.get(protocol, "errors"));
    try scope.put(protocol, "globalSockets", state);
    try @import("native_ai_codex_socket.zig").retainGuestOwner(scope.engine, state, cleanupOwned);
    return state;
}
pub fn closeSession(scope: *Scope, protocol: c.JSValue, session: c.JSValue) !void {
    const state = try v.optional(scope, protocol, "globalSockets");
    if (v.nullish(state)) return;
    // All owned sockets are tracked separately from cache selection, including
    // failed pre-open sockets and simultaneous overwritten initial entries.
    const owned = try scope.get(state, "owned");
    const count = try v.length(scope, owned);
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        const entry = try v.at(scope, owned, index);
        if (scope.truthy(session) and !scope.equal(try scope.get(entry, "session"), session)) continue;
        try clearTimer(scope, entry, "idleTimer");
        try closeSilently(scope, try scope.get(entry, "socket"), "debug_close");
    }
    const cache = try scope.get(state, "cache");
    _ = try scope.invoke(cache, if (scope.truthy(session)) "delete" else "clear", if (scope.truthy(session)) &.{session} else &.{});
}
fn cleanupOwned(engine: *v.em.Engine, state: c.JSValue) void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owned = scope.get(state, "owned") catch return;
    const count = v.length(&scope, owned) catch return;
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        const entry = v.at(&scope, owned, index) catch continue;
        clearTimer(&scope, entry, "idleTimer") catch {};
        const turn = v.optional(&scope, entry, "turn") catch c.pi_js_undefined();
        if (!v.nullish(turn)) {
            clearTimer(&scope, turn, "timer") catch {};
            const parser = v.optional(&scope, turn, "parser") catch c.pi_js_undefined();
            if (!v.nullish(parser)) cleanupParser(&scope, parser) catch {};
        }
        const socket = scope.get(entry, "socket") catch continue;
        closeSilently(&scope, socket, "owned_cleanup") catch {};
    }
}
pub fn acquire(engine: *v.em.Engine, protocol: c.JSValue, constructor: c.JSValue, url: c.JSValue, headers: c.JSValue, session: c.JSValue, account: c.JSValue, signal: c.JSValue, connect_timeout: c.JSValue, idle_timeout: c.JSValue) !c.JSValue {
    if (@import("native_ai_codex_socket.zig").closing(engine)) return error.NativeWebSocketOwnerClosing;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try stateFor(&scope, protocol);
    const pending = try flow.create(engine, state);
    defer engine.freeValue(pending.owner);
    defer engine.freeValue(pending.promise);
    const turn = pending.owner;
    inline for (.{ "constructor", "url", "headers", "session", "account", "signal", "connectTimeout", "idleTimeout" }, .{ constructor, url, headers, session, account, signal, connect_timeout, idle_timeout }) |key, value| try scope.put(turn, key, value);
    try scope.put(turn, "settled", c.pi_js_bool(engine.context, 0));
    try scope.put(turn, "timer", c.pi_js_undefined());
    try scope.put(turn, "parser", c.pi_js_undefined());
    try scope.put(turn, "entry", c.pi_js_undefined());
    const output = try scope.object();
    const events = try scope.object();
    try scope.put(events, "next", try callback(&scope, turn, .next));
    try scope.put(output, "events", events);
    try scope.put(output, "ready", pending.promise);
    try scope.put(output, "parsedEvents", c.pi_js_bool(engine.context, 1));
    try scope.put(output, "synchronousSend", c.pi_js_bool(engine.context, 1));
    inline for (.{ Method.send, Method.release, Method.close }) |method| try scope.put(output, @tagName(method), try callback(&scope, turn, method));
    try scope.put(turn, "output", output);
    startAcquire(&scope, turn) catch |err| try flow.rejectError(engine, turn, err);
    return c.JS_DupValue(engine.context, output);
}
fn startAcquire(scope: *Scope, turn: c.JSValue) !void {
    const state = try scope.get(turn, "agent");
    const cache = try scope.get(state, "cache");
    const session = try scope.get(turn, "session");
    const account = try scope.get(turn, "account");
    const accounts = if (scope.truthy(session)) try scope.invoke(cache, "get", &.{session}) else c.pi_js_undefined();
    const cached = if (scope.truthy(accounts)) try scope.invoke(accounts, "get", &.{account}) else c.pi_js_undefined();
    var publish = scope.truthy(session);
    if (scope.truthy(cached)) {
        try clearTimer(scope, cached, "idleTimer");
        const socket = try scope.get(cached, "socket");
        if (!scope.truthy(try scope.get(cached, "busy"))) {
            const age = try scope.own(try math.binary(scope.engine, .subtract, try scope.invoke(try scope.global("Date"), "now", &.{}), try scope.get(cached, "createdAt")));
            if (try math.compare(scope.engine, .greater_equal, age, c.JS_NewInt32(scope.engine.context, 55 * 60 * 1000))) {
                try closeSilently(scope, socket, "connection_age_limit");
                _ = try scope.invoke(accounts, "delete", &.{account});
                if (scope.equal(try scope.get(accounts, "size"), c.JS_NewInt32(scope.engine.context, 0))) _ = try scope.invoke(cache, "delete", &.{session});
            } else if (try reusable(scope, socket)) {
                try scope.put(cached, "busy", c.pi_js_bool(scope.engine.context, 1));
                try scope.put(turn, "socket", socket);
                try scope.put(turn, "entry", cached);
                try scope.put(cached, "turn", turn);
                return completeAcquire(scope, turn, true);
            }
        }
        if (scope.truthy(try scope.get(cached, "busy"))) publish = false else if (!try reusable(scope, socket)) {
            try closeSilently(scope, socket, "done");
            _ = try scope.invoke(accounts, "delete", &.{account});
            if (scope.equal(try scope.get(accounts, "size"), c.JS_NewInt32(scope.engine.context, 0))) _ = try scope.invoke(cache, "delete", &.{session});
        }
    }
    try scope.put(turn, "publish", c.pi_js_bool(scope.engine.context, @intFromBool(publish)));
    const connecting = try flow.create(scope.engine, turn);
    defer scope.engine.freeValue(connecting.owner);
    const promise = try scope.own(connecting.promise);
    try scope.put(turn, "connectCompletion", connecting.owner);
    try flow.wait(publishConnected, scope.engine, turn, promise, 0);
    // This is Source's actual awaited getWebSocketConstructor boundary.
    try flow.wait(connectStart, scope.engine, turn, try scope.get(turn, "constructor"), 0);
}
fn connectStart(engine: *v.em.Engine, turn: c.JSValue, constructor: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        return flow.settle(engine, try scope.get(turn, "connectCompletion"), true, constructor);
    }
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    connect(&scope, turn, constructor) catch |err| {
        const original = try scope.own(flow.reason(engine, err));
        if (engine.captured_exception) |captured| {
            engine.captured_exception = null;
            engine.freeValue(captured);
        }
        const reason = try @import("native_ai_codex_http.zig").caught(&scope, original);
        try flow.settle(engine, try scope.get(turn, "connectCompletion"), true, reason);
    };
}
fn connect(scope: *Scope, turn: c.JSValue, constructor: c.JSValue) !void {
    const fields = try scope.invoke(try scope.global("Object"), "fromEntries", &.{try scope.invoke(try scope.get(turn, "headers"), "entries", &.{})});
    try v.remove(scope, fields, "OpenAI-Beta");
    const options = try scope.object();
    try scope.put(options, "headers", fields);
    var args = [_]c.JSValue{ try scope.get(turn, "url"), options };
    const socket = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, &args)));
    try scope.put(turn, "socket", socket);
    const owned = try scope.object();
    try scope.put(owned, "session", try scope.get(turn, "session"));
    try scope.put(owned, "socket", socket);
    try scope.put(owned, "idleTimer", c.pi_js_undefined());
    try scope.put(owned, "turn", turn);
    try scope.put(turn, "owned", owned);
    _ = try scope.invoke(try scope.get(try scope.get(turn, "agent"), "owned"), "push", &.{owned});
    inline for (.{ Method.open, Method.connect_error, Method.connect_close, Method.connect_abort }) |method| try scope.put(turn, @tagName(method), try callback(scope, turn, method));
    inline for (.{ .{ "open", "open" }, .{ "error", "connect_error" }, .{ "close", "connect_close" } }) |pair| _ = try scope.invoke(socket, "addEventListener", &.{ try scope.text(pair[0]), try scope.get(turn, pair[1]) });
    const signal = try scope.get(turn, "signal");
    if (!v.nullish(signal)) _ = try scope.invoke(signal, "addEventListener", &.{ try scope.text("abort"), try scope.get(turn, "connect_abort") });
    const supplied = try scope.get(turn, "connectTimeout");
    const timeout = if (c.JS_IsUndefined(supplied)) c.JS_NewInt32(scope.engine.context, 15000) else supplied;
    try scope.put(turn, "effectiveConnectTimeout", timeout);
    if (try math.compare(scope.engine, .greater, timeout, c.JS_NewInt32(scope.engine.context, 0))) try scope.put(turn, "timer", try scope.call(try scope.global("setTimeout"), c.pi_js_undefined(), &.{ try callback(scope, turn, .connect_timeout), timeout }));
    if (scope.truthy(try v.optional(scope, signal, "aborted"))) _ = try invoke(scope, turn, .connect_abort, c.pi_js_undefined());
}
fn cleanupConnect(scope: *Scope, turn: c.JSValue) !void {
    try clearTimer(scope, turn, "timer");
    const socket = try scope.get(turn, "socket");
    inline for (.{ .{ "open", "open" }, .{ "error", "connect_error" }, .{ "close", "connect_close" } }) |pair| _ = try scope.invoke(socket, "removeEventListener", &.{ try scope.text(pair[0]), try scope.get(turn, pair[1]) });
    const signal = try scope.get(turn, "signal");
    if (!v.nullish(signal)) _ = try scope.invoke(signal, "removeEventListener", &.{ try scope.text("abort"), try scope.get(turn, "connect_abort") });
}
fn completeAcquire(scope: *Scope, turn: c.JSValue, reused: bool) !void {
    const output = try scope.get(turn, "output");
    const entry = try scope.get(turn, "entry");
    try scope.put(output, "cached", c.pi_js_bool(scope.engine.context, @intFromBool(!v.nullish(entry))));
    try scope.put(output, "reused", c.pi_js_bool(scope.engine.context, @intFromBool(reused)));
    try scope.put(output, "meta", entry);
    try flow.settle(scope.engine, turn, false, c.pi_js_undefined());
}
fn publishConnected(engine: *v.em.Engine, turn: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, turn, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.truthy(try scope.get(turn, "publish"))) {
        const state = try scope.get(turn, "agent");
        const cache = try scope.get(state, "cache");
        const session = try scope.get(turn, "session");
        const entry = try scope.get(turn, "owned");
        try scope.put(entry, "state", state);
        try scope.put(entry, "account", try scope.get(turn, "account"));
        try scope.put(entry, "busy", c.pi_js_bool(engine.context, 1));
        try scope.put(entry, "createdAt", try scope.invoke(try scope.global("Date"), "now", &.{}));
        var accounts = try scope.invoke(cache, "get", &.{session});
        if (!scope.truthy(accounts)) {
            accounts = try scope.own(try v.js.builtin(engine, "Map", &.{}));
            _ = try scope.invoke(cache, "set", &.{ session, accounts });
        }
        _ = try scope.invoke(accounts, "set", &.{ try scope.get(turn, "account"), entry });
        try scope.put(turn, "entry", entry);
    }
    try completeAcquire(&scope, turn, false);
}
fn discardEntry(scope: *Scope, turn: c.JSValue, reason: []const u8) !void {
    const entry = try scope.get(turn, "entry");
    try closeSilently(scope, try scope.get(turn, "socket"), reason);
    if (v.nullish(entry)) return;
    try clearTimer(scope, entry, "idleTimer");
    const state = try scope.get(turn, "agent");
    const cache = try scope.get(state, "cache");
    const session = try scope.get(turn, "session");
    const account = try scope.get(turn, "account");
    const accounts = try scope.invoke(cache, "get", &.{session});
    if (scope.truthy(accounts)) {
        if (scope.equal(try scope.invoke(accounts, "get", &.{account}), entry)) _ = try scope.invoke(accounts, "delete", &.{account});
        if (scope.equal(try scope.get(accounts, "size"), c.JS_NewInt32(scope.engine.context, 0))) _ = try scope.invoke(cache, "delete", &.{session});
    }
}
fn result(scope: *Scope, value: c.JSValue, done: bool) !c.JSValue {
    const row = try scope.object();
    try scope.put(row, "value", value);
    try scope.put(row, "done", c.pi_js_bool(scope.engine.context, @intFromBool(done)));
    return row;
}
fn makeParser(scope: *Scope, turn: c.JSValue) !c.JSValue {
    const parser = try scope.object();
    try scope.put(parser, "turn", turn);
    try scope.put(parser, "queue", try scope.array());
    inline for (.{ "done", "sawCompletion", "closed" }) |key| try scope.put(parser, key, c.pi_js_bool(scope.engine.context, 0));
    inline for (.{ "failed", "pending", "timer" }) |key| try scope.put(parser, key, c.pi_js_null());
    inline for (.{ Method.message, Method.parse_error, Method.parse_close, Method.parse_abort }) |method| try scope.put(parser, @tagName(method), try callback(scope, parser, method));
    const socket = try scope.get(turn, "socket");
    inline for (.{ .{ "message", "message" }, .{ "error", "parse_error" }, .{ "close", "parse_close" } }) |pair| _ = try scope.invoke(socket, "addEventListener", &.{ try scope.text(pair[0]), try scope.get(parser, pair[1]) });
    const signal = try scope.get(turn, "signal");
    if (!v.nullish(signal)) _ = try scope.invoke(signal, "addEventListener", &.{ try scope.text("abort"), try scope.get(parser, "parse_abort") });
    try scope.put(turn, "parser", parser);
    return parser;
}
fn cleanupParser(scope: *Scope, parser: c.JSValue) !void {
    if (v.nullish(parser) or scope.truthy(try scope.get(parser, "closed"))) return;
    try scope.put(parser, "closed", c.pi_js_bool(scope.engine.context, 1));
    try clearTimer(scope, parser, "timer");
    const turn = try scope.get(parser, "turn");
    const socket = try scope.get(turn, "socket");
    inline for (.{ .{ "message", "message" }, .{ "error", "parse_error" }, .{ "close", "parse_close" } }) |pair| _ = try scope.invoke(socket, "removeEventListener", &.{ try scope.text(pair[0]), try scope.get(parser, pair[1]) });
    const signal = try scope.get(turn, "signal");
    if (!v.nullish(signal)) _ = try scope.invoke(signal, "removeEventListener", &.{ try scope.text("abort"), try scope.get(parser, "parse_abort") });
}
fn wake(scope: *Scope, parser: c.JSValue, rejected: bool, reason: c.JSValue) !void {
    const pending = try scope.get(parser, "pending");
    if (v.nullish(pending)) return;
    try scope.put(parser, "pending", c.pi_js_null());
    try flow.settle(scope.engine, pending, rejected, reason);
}
fn advanceNext(scope: *Scope, pending: c.JSValue) !void {
    const parser = try scope.get(pending, "agent");
    const turn = try scope.get(parser, "turn");
    const signal = try scope.get(turn, "signal");
    if (scope.truthy(try v.optional(scope, signal, "aborted"))) {
        try cleanupParser(scope, parser);
        return flow.settle(scope.engine, pending, true, try plainError(scope, "Request was aborted"));
    }
    const queue = try scope.get(parser, "queue");
    if (try v.length(scope, queue) > 0) return flow.settle(scope.engine, pending, false, try result(scope, try scope.invoke(queue, "shift", &.{}), false));
    if (scope.truthy(try scope.get(parser, "done"))) {
        try cleanupParser(scope, parser);
        const failed = try scope.get(parser, "failed");
        if (scope.truthy(failed)) return flow.settle(scope.engine, pending, true, failed);
        if (!scope.truthy(try scope.get(parser, "sawCompletion"))) return flow.settle(scope.engine, pending, true, try plainError(scope, "WebSocket stream closed before response.completed"));
        return flow.settle(scope.engine, pending, false, try result(scope, c.pi_js_undefined(), true));
    }
    const waiting = try flow.create(scope.engine, parser);
    defer scope.engine.freeValue(waiting.owner);
    const promise = try scope.own(waiting.promise);
    try scope.put(parser, "pending", waiting.owner);
    const timeout = try scope.get(turn, "idleTimeout");
    if (!c.JS_IsUndefined(timeout) and try math.compare(scope.engine, .greater, timeout, c.JS_NewInt32(scope.engine.context, 0))) try scope.put(parser, "timer", try scope.call(try scope.global("setTimeout"), c.pi_js_undefined(), &.{ try callback(scope, parser, .idle_timeout), timeout }));
    try flow.wait(nextAwake, scope.engine, pending, promise, 0);
}
fn nextAwake(engine: *v.em.Engine, pending: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const parser = try scope.get(pending, "agent");
    try clearTimer(&scope, parser, "timer");
    if (rejected) {
        try cleanupParser(&scope, parser);
        return flow.settle(engine, pending, true, value);
    }
    advanceNext(&scope, pending) catch |err| try flow.rejectError(engine, pending, err);
}
fn decode(scope: *Scope, data: c.JSValue) !c.JSValue {
    if (c.JS_IsString(data)) return scope.own(try scope.engine.checked(c.JS_PiPromiseResolve(scope.engine.context, data)));
    const array_buffer = try scope.global("ArrayBuffer");
    var view: c.JSValue = undefined;
    if (try errors.instance(scope, data, array_buffer)) view = try scope.own(try v.js.builtin(scope.engine, "Uint8Array", &.{data})) else if (scope.truthy(try scope.invoke(array_buffer, "isView", &.{data}))) {
        view = try scope.own(try v.js.builtin(scope.engine, "Uint8Array", &.{ try scope.get(data, "buffer"), try scope.get(data, "byteOffset"), try scope.get(data, "byteLength") }));
    } else if (scope.truthy(data) and c.JS_IsObject(data) and !c.JS_IsFunction(scope.engine.context, data) and try v.js.hasKey(scope.engine, data, try scope.text("arrayBuffer"))) {
        const pending = try flow.create(scope.engine, data);
        defer scope.engine.freeValue(pending.owner);
        const promise = try scope.own(pending.promise);
        try flow.wait(blobDecoded, scope.engine, pending.owner, try scope.invoke(data, "arrayBuffer", &.{}), 0);
        return promise;
    } else return scope.own(try scope.engine.checked(c.JS_PiPromiseResolve(scope.engine.context, c.pi_js_null())));
    const text = try scope.invoke(try scope.own(try v.js.builtin(scope.engine, "TextDecoder", &.{})), "decode", &.{view});
    return scope.own(try scope.engine.checked(c.JS_PiPromiseResolve(scope.engine.context, text)));
}
fn blobDecoded(engine: *v.em.Engine, pending: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, pending, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bytes = try scope.own(try v.js.builtin(engine, "Uint8Array", &.{value}));
    const text = try scope.invoke(try scope.own(try v.js.builtin(engine, "TextDecoder", &.{})), "decode", &.{bytes});
    try flow.settle(engine, pending, false, text);
}
fn messageFailed(scope: *Scope, parser: c.JSValue, cause: c.JSValue, text: c.JSValue) !void {
    const options = try scope.object();
    try scope.put(options, "cause", cause);
    try scope.put(options, "payload", text);
    const classes = try scope.get(try scope.get(try scope.get(parser, "turn"), "agent"), "classes");
    try scope.put(parser, "failed", try errors.construct(scope, classes, .protocol, try scope.concat(try scope.text("Invalid Codex WebSocket JSON: "), try errors.thrownText(scope, cause)), options));
    try scope.put(parser, "done", c.pi_js_bool(scope.engine.context, 1));
    try wake(scope, parser, false, c.pi_js_undefined());
}
fn messageDecoded(engine: *v.em.Engine, parser: c.JSValue, text: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) return messageFailed(&scope, parser, text, c.pi_js_null());
    if (!scope.truthy(text)) return;
    const generation = engine.native_allocation_generation;
    parseMessage(&scope, parser, text) catch |err| {
        if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return err;
        const reason = try scope.own(flow.reason(engine, err));
        if (engine.captured_exception) |captured| {
            engine.captured_exception = null;
            engine.freeValue(captured);
        }
        try messageFailed(&scope, parser, reason, text);
    };
}
fn parseMessage(scope: *Scope, parser: c.JSValue, text: c.JSValue) !void {
    var diagnostic = @import("native_ai_json_scope.zig").Guard.enter(scope.engine);
    defer diagnostic.deinit();
    const parsed = try scope.invoke(try scope.global("JSON"), "parse", &.{text});
    const typ = try scope.get(parsed, "type");
    if (c.JS_IsString(typ) and (try v.eq(scope, typ, "response.completed") or try v.eq(scope, typ, "response.done") or try v.eq(scope, typ, "response.incomplete"))) {
        try scope.put(parser, "sawCompletion", c.pi_js_bool(scope.engine.context, 1));
        try scope.put(parser, "done", c.pi_js_bool(scope.engine.context, 1));
    }
    _ = try scope.invoke(try scope.get(parser, "queue"), "push", &.{parsed});
    try wake(scope, parser, false, c.pi_js_undefined());
}
fn startMessage(scope: *Scope, parser: c.JSValue, event: c.JSValue) !void {
    if (!scope.truthy(event) or !c.JS_IsObject(event) or c.JS_IsFunction(scope.engine.context, event) or !try v.js.hasKey(scope.engine, event, try scope.text("data"))) return;
    const promise = try decode(scope, try scope.get(event, "data"));
    try flow.wait(messageDecoded, scope.engine, parser, promise, 0);
}
fn invoke(scope: *Scope, owner: c.JSValue, comptime method: Method, value: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    if (method == .send) {
        _ = try scope.invoke(try scope.get(owner, "socket"), "send", &.{value});
        return c.pi_js_undefined();
    }
    if (method == .next) {
        const existing = try scope.get(owner, "parser");
        const parser = if (v.nullish(existing)) try makeParser(scope, owner) else existing;
        const pending = try flow.create(engine, parser);
        defer engine.freeValue(pending.owner);
        errdefer engine.freeValue(pending.promise);
        advanceNext(scope, pending.owner) catch |err| try flow.rejectError(engine, pending.owner, err);
        return pending.promise;
    }
    if (method == .release or method == .close) {
        try cleanupParser(scope, try scope.get(owner, "parser"));
        try scope.put(owner, "parser", c.pi_js_undefined());
        try scope.put(owner, "signal", c.pi_js_undefined());
        const owned = try v.optional(scope, owner, "owned");
        if (!v.nullish(owned)) try scope.put(owned, "turn", c.pi_js_undefined());
        const entry = try scope.get(owner, "entry");
        if (!v.nullish(entry)) try scope.put(entry, "turn", c.pi_js_undefined());
        if (method == .close or !scope.truthy(value) or v.nullish(entry) or !try reusable(scope, try scope.get(owner, "socket"))) try discardEntry(scope, owner, "done") else {
            try scope.put(entry, "busy", c.pi_js_bool(engine.context, 0));
            try clearTimer(scope, entry, "idleTimer");
            const expiry = try scope.object();
            inline for (.{ "agent", "entry", "session", "account", "socket" }) |key| try scope.put(expiry, key, try scope.get(owner, key));
            try scope.put(entry, "idleTimer", try scope.call(try scope.global("setTimeout"), c.pi_js_undefined(), &.{ try callback(scope, expiry, .expiry), c.JS_NewInt32(engine.context, 5 * 60 * 1000) }));
        }
        return c.pi_js_undefined();
    }
    if (method == .expiry) {
        const entry = try scope.get(owner, "entry");
        if (!scope.truthy(try scope.get(entry, "busy"))) try discardEntry(scope, owner, "idle_timeout");
        return c.pi_js_undefined();
    }
    if (method == .message) {
        const generation = engine.native_allocation_generation;
        startMessage(scope, owner, value) catch |err| {
            if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) return err;
            const cause = try scope.own(flow.reason(engine, err));
            if (engine.captured_exception) |captured| {
                engine.captured_exception = null;
                engine.freeValue(captured);
            }
            try messageFailed(scope, owner, cause, c.pi_js_null());
        };
        return c.pi_js_undefined();
    }
    if (method == .parse_error or method == .parse_close or method == .parse_abort or method == .idle_timeout) {
        const turn = try scope.get(owner, "turn");
        const classes = try scope.get(try scope.get(turn, "agent"), "classes");
        if (method == .parse_close and scope.truthy(try scope.get(owner, "sawCompletion"))) {
            try scope.put(owner, "done", c.pi_js_bool(engine.context, 1));
            try wake(scope, owner, false, c.pi_js_undefined());
            return c.pi_js_undefined();
        }
        const reason = switch (method) {
            .parse_error => try errors.socketError(scope, value),
            .parse_close => if (scope.truthy(try scope.get(owner, "failed"))) try scope.get(owner, "failed") else try errors.socketClose(scope, classes, value),
            .parse_abort => try plainError(scope, "Request was aborted"),
            .idle_timeout => try scope.own(try v.js.builtin(engine, "Error", &.{try scope.concat(try scope.concat(try scope.text("WebSocket idle timeout after "), try scope.stringify(try scope.get(turn, "idleTimeout"))), try scope.text("ms"))})),
            else => unreachable,
        };
        try scope.put(owner, "failed", reason);
        try scope.put(owner, "done", c.pi_js_bool(engine.context, 1));
        if (method == .idle_timeout) try closeSilently(scope, try scope.get(turn, "socket"), "idle_timeout");
        try wake(scope, owner, method == .idle_timeout, if (method == .idle_timeout) reason else c.pi_js_undefined());
        return c.pi_js_undefined();
    }
    if (scope.truthy(try scope.get(owner, "settled"))) return c.pi_js_undefined();
    try scope.put(owner, "settled", c.pi_js_bool(engine.context, 1));
    try cleanupConnect(scope, owner);
    if (method == .open) {
        try flow.settle(engine, try scope.get(owner, "connectCompletion"), false, try scope.get(owner, "socket"));
    } else {
        const classes = try scope.get(try scope.get(owner, "agent"), "classes");
        const reason = switch (method) {
            .connect_error => try errors.socketError(scope, value),
            .connect_close => try errors.socketClose(scope, classes, value),
            .connect_abort => try plainError(scope, "Request was aborted"),
            .connect_timeout => try scope.own(try v.js.builtin(engine, "Error", &.{try scope.concat(try scope.concat(try scope.text("WebSocket connect timeout after "), try scope.stringify(try scope.get(owner, "effectiveConnectTimeout"))), try scope.text("ms"))})),
            else => unreachable,
        };
        if (method == .connect_abort or method == .connect_timeout) try closeSilently(scope, try scope.get(owner, "socket"), if (method == .connect_abort) "aborted" else "connect_timeout");
        try flow.settle(engine, try scope.get(owner, "connectCompletion"), true, reason);
    }
    return c.pi_js_undefined();
}
