//! Source RemoteExecutionEnv.exec callbacks, running-command ownership and result precedence.
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const Scope = h.Scope;
const c = js.c;
const Stage = enum(c_int) { cwd, reply };
const Callback = enum(c_int) { abort, start, event };
fn errorValue(scope: *Scope, captures: c.JSValue, code: c.JSValue, message: c.JSValue, cause: c.JSValue) !c.JSValue {
    const args = [_]c.JSValue{ code, message, cause };
    const constructor = try scope.get(try scope.get(captures, "bindings"), "ExecutionError");
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, @constCast(&args))));
}
fn failure(scope: *Scope, captures: c.JSValue, code: []const u8, message: []const u8) !c.JSValue {
    return h.values.result(scope, false, try errorValue(scope, captures, try scope.text(code), try scope.text(message), c.pi_js_undefined()));
}
fn toCause(scope: *Scope, value: c.JSValue) !c.JSValue {
    const base = try scope.global("Error");
    const instance = c.JS_IsInstanceOf(scope.engine.context, value, base);
    if (instance < 0) return js.capture(scope.engine);
    return if (instance != 0) value else scope.own(try js.builtin(scope.engine, "Error", &.{try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{value})}));
}
fn unknown(scope: *Scope, captures: c.JSValue, value: c.JSValue) !c.JSValue {
    const base = try scope.global("Error");
    const instance = c.JS_IsInstanceOf(scope.engine.context, value, base);
    if (instance < 0) return js.capture(scope.engine);
    const message = if (instance != 0) try scope.get(value, "message") else try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{value});
    return h.values.result(scope, false, try errorValue(scope, captures, try scope.text("unknown"), message, c.pi_js_undefined()));
}
fn finish(scope: *Scope, captures: c.JSValue, value: c.JSValue) !c.JSValue {
    try scope.put(captures, "settled", c.pi_js_bool(scope.engine.context, 1));
    const signal = try scope.get(captures, "signal");
    if (!h.nullish(signal)) _ = try scope.invoke(signal, "removeEventListener", &.{ try scope.text("abort"), try scope.get(captures, "onAbort") });
    const running = try scope.get(captures, "running");
    if (!c.JS_IsUndefined(running)) _ = try scope.invoke(try scope.get(try scope.get(captures, "private"), "running"), "delete", &.{running});
    return value;
}
fn callback(scope: *Scope, captures: c.JSValue, args: []const c.JSValue, kind: Callback) !c.JSValue {
    if (kind == .abort) return scope.invoke(try scope.get(captures, "controller"), "abort", &.{});
    if (kind == .start) {
        try scope.put(captures, "running", h.arg(args, 0));
        _ = try scope.invoke(try scope.get(try scope.get(captures, "private"), "running"), "set", &.{ h.arg(args, 0), h.arg(args, 1) });
        return c.pi_js_undefined();
    }
    if (scope.truthy(try scope.get(captures, "settled")) or !c.JS_IsUndefined(try scope.get(captures, "callbackError"))) return c.pi_js_undefined();
    const event = h.arg(args, 0);
    if (!scope.equal(try scope.get(event, "kind"), try scope.text("output"))) return c.pi_js_undefined();
    const payload = h.arg(args, 1);
    const bytes = try scope.invoke(try scope.global("Buffer"), "from", &.{ try scope.get(payload, "buffer"), try scope.get(payload, "byteOffset"), try scope.get(payload, "length") });
    const text = try scope.invoke(bytes, "toString", &.{try scope.text("utf8")});
    const options = try scope.get(captures, "options");
    if (scope.equal(text, try scope.text("")) or c.JS_IsUndefined(try h.optional(scope, options, "onOutput"))) return c.pi_js_undefined();
    const info = try scope.object();
    try scope.put(info, "stream", try scope.text(if (scope.equal(try scope.get(event, "stream"), try scope.text("stderr"))) "stderr" else "stdout"));
    if (!c.JS_IsUndefined(try scope.get(event, "skipped"))) try scope.put(info, "skipped", try scope.get(event, "skipped"));
    _ = scope.call(try scope.get(options, "onOutput"), options, &.{ text, try scope.get(captures, "context"), info }) catch |err| {
        if (err != error.JavaScriptException) return err;
        const cause = try toCause(scope, try h.errors.captured(scope));
        try scope.put(captures, "callbackError", try errorValue(scope, captures, try scope.text("callback_error"), try scope.get(cause, "message"), cause));
        _ = try scope.invoke(try scope.get(captures, "controller"), "abort", &.{});
        return c.pi_js_undefined();
    };
    return c.pi_js_undefined();
}
fn callbackInvoke(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = callback(&scope, data[0], if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(raw)) catch |err| return @import("native_durable.zig").reject(engine, err);
    return c.JS_DupValue(engine.context, value);
}
fn start(scope: *Scope, captures: c.JSValue, cwd: c.JSValue) !c.JSValue {
    const signal = try scope.get(captures, "signal");
    if (!h.nullish(signal) and scope.truthy(try scope.get(signal, "aborted"))) return failure(scope, captures, "aborted", "aborted");
    const options = try scope.get(captures, "options");
    const inherit = try scope.get(captures, "inheritEnv");
    const private = try scope.get(captures, "private");
    const given = try h.optional(scope, options, "env");
    const combined = if (scope.truthy(inherit)) try scope.own(try js.spread(scope.engine, try scope.get(private, "shellEnv"))) else try scope.object();
    const extra = try scope.own(try js.spread(scope.engine, given));
    // Object spread uses data properties, including a literal __proto__ key.
    const assign = try scope.get(try scope.global("Object"), "defineProperties");
    const descriptors = try scope.invoke(try scope.global("Object"), "getOwnPropertyDescriptors", &.{extra});
    _ = try scope.call(assign, try scope.global("Object"), &.{ combined, descriptors });
    const entries = try scope.invoke(try scope.global("Object"), "entries", &.{combined});
    const env = try scope.object();
    var iterator = try js.Iterator.init(scope.engine, entries, try scope.get(try scope.global("Symbol"), "iterator"));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        _ = try scope.own(entry);
        const value = try scope.own(try js.getKey(scope.engine, entry, c.JS_NewInt32(scope.engine.context, 1)));
        if (c.JS_IsUndefined(value)) continue;
        const key = try scope.own(try js.getKey(scope.engine, entry, c.JS_NewInt32(scope.engine.context, 0)));
        const formed = try scope.invoke(key, "toWellFormed", &.{});
        const atom = try js.atom(scope.engine, formed);
        defer c.JS_FreeAtom(scope.engine.context, atom);
        if (c.JS_SetProperty(scope.engine.context, env, atom, c.JS_DupValue(scope.engine.context, value)) < 0) return js.capture(scope.engine);
    }
    try scope.put(captures, "settled", c.pi_js_bool(scope.engine.context, 0));
    try scope.put(captures, "callbackError", c.pi_js_undefined());
    try scope.put(captures, "running", c.pi_js_undefined());
    if (scope.engine.abort_controller_class == 0) try @import("abort_signal.zig").install(scope.engine);
    const controller = try scope.own(try js.builtin(scope.engine, "AbortController", &.{}));
    try scope.put(captures, "controller", controller);
    var data = [_]c.JSValue{captures};
    inline for (.{ .{ "onAbort", Callback.abort }, .{ "onStart", Callback.start }, .{ "onEvent", Callback.event } }) |entry| {
        const function = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callbackInvoke, entry[0], if (entry[1] == .abort) 0 else 2, @intFromEnum(entry[1]), 1, &data)));
        try scope.put(captures, entry[0], function);
    }
    if (!h.nullish(signal)) {
        const once = try scope.object();
        try scope.put(once, "once", c.pi_js_bool(scope.engine.context, 1));
        _ = try scope.invoke(signal, "addEventListener", &.{ try scope.text("abort"), try scope.get(captures, "onAbort"), once });
    }
    const json = try scope.object();
    const command = try scope.get(captures, "input");
    if (c.JS_IsString(command)) try scope.put(json, "command", command) else {
        const argv = try scope.array();
        var args = try js.Iterator.init(scope.engine, command, try scope.get(try scope.global("Symbol"), "iterator"));
        defer args.deinit();
        errdefer args.closePreserving();
        while (try args.next()) |item| {
            _ = try scope.own(item);
            _ = try scope.invoke(argv, "push", &.{item});
        }
        try scope.put(json, "argv", argv);
    }
    try scope.put(json, "cwd", cwd);
    try scope.put(json, "env", env);
    try scope.put(json, "inheritEnv", inherit);
    const shell = try scope.get(private, "shellPath");
    if (!c.JS_IsUndefined(shell)) try scope.put(json, "shellPath", shell);
    const timeout = try scope.get(captures, "timeout");
    if (!c.JS_IsUndefined(timeout)) try scope.put(json, "timeoutMs", try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 2, timeout, c.JS_NewInt32(scope.engine.context, 1000)))));
    inline for (.{ "spill", "window" }) |key| if (!c.JS_IsUndefined(try h.optional(scope, options, key))) try scope.put(json, key, try scope.get(options, key));
    const request_options = try scope.object();
    try scope.put(request_options, "signal", try scope.get(controller, "signal"));
    inline for (.{ "onStart", "onEvent" }) |key| try scope.put(request_options, key, try scope.get(captures, key));
    const pending = h.request(scope, try scope.get(captures, "self"), "exec", json, request_options) catch |err| try h.rejected(scope, err);
    return h.wait(advance, scope, captures, pending, Stage.reply);
}
fn refused(scope: *Scope, captures: c.JSValue, reason: c.JSValue) !c.JSValue {
    const callback_error = try scope.get(captures, "callbackError");
    if (!c.JS_IsUndefined(callback_error)) return h.values.result(scope, false, callback_error);
    const remote = try scope.get(try scope.get(captures, "bindings"), "RemoteError");
    const instance = c.JS_IsInstanceOf(scope.engine.context, reason, remote);
    if (instance < 0) return js.capture(scope.engine);
    if (instance == 0) return unknown(scope, captures, reason);
    const code = try scope.get(reason, "code");
    var kind: c.JSValue = try scope.text("unknown");
    var message = try scope.get(reason, "message");
    if (scope.equal(code, try scope.text("timeout"))) {
        kind = try scope.text("timeout");
        message = try scope.concat(try scope.text("timeout:"), try scope.get(captures, "timeout"));
    } else if (scope.equal(code, try scope.text("aborted"))) {
        kind = try scope.text("aborted");
        message = try scope.text("aborted");
    } else if (scope.equal(code, try scope.text("shell_unavailable")) or scope.equal(code, try scope.text("spawn_error"))) kind = code;
    const value = try errorValue(scope, captures, kind, message, c.pi_js_undefined());
    const spill = try scope.get(try scope.get(reason, "fields"), "spillPath");
    if (c.JS_IsString(spill)) try scope.set(value, "spillPath", try scope.get(try scope.get(reason, "fields"), "spillPath"));
    return h.values.result(scope, false, value);
}
fn advance(engine: *js.Engine, captures: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(raw);
    if (stage == .cwd) return c.JS_DupValue(engine.context, if (rejected) try unknown(&scope, captures, value) else try start(&scope, captures, value));
    const outcome = if (rejected) try refused(&scope, captures, value) else success: {
        const callback_error = try scope.get(captures, "callbackError");
        if (!c.JS_IsUndefined(callback_error)) break :success try h.values.result(&scope, false, callback_error);
        const json = try scope.get(value, "json");
        const result_value = try scope.object();
        try scope.put(result_value, "exitCode", try scope.get(json, "exitCode"));
        if (c.JS_IsString(try scope.get(json, "spillPath"))) try scope.put(result_value, "spillPath", try scope.get(json, "spillPath"));
        break :success try h.values.result(&scope, true, result_value);
    };
    return c.JS_DupValue(engine.context, try finish(&scope, captures, outcome));
}
pub fn invoke(scope: *Scope, captures: c.JSValue, kind: anytype, args: []const c.JSValue) !c.JSValue {
    if (kind == .cleanup) {
        const running = try scope.get(try scope.get(captures, "private"), "running");
        var iterator = try js.Iterator.init(scope.engine, running, try scope.get(try scope.global("Symbol"), "iterator"));
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |entry| {
            _ = try scope.own(entry);
            _ = try scope.invoke(try scope.get(try scope.get(captures, "self"), "connection"), "kill", &.{ try scope.own(try js.getKey(scope.engine, entry, c.JS_NewInt32(scope.engine.context, 0))), try scope.own(try js.getKey(scope.engine, entry, c.JS_NewInt32(scope.engine.context, 1))) });
        }
        _ = try scope.invoke(running, "clear", &.{});
        return h.resolved(scope, c.pi_js_undefined());
    }
    _ = args;
    const signal = try scope.get(try scope.get(captures, "context"), "abortSignal");
    try scope.put(captures, "signal", signal);
    if (!h.nullish(signal) and scope.truthy(try scope.get(signal, "aborted"))) return h.resolved(scope, try failure(scope, captures, "aborted", "aborted"));
    const options = try scope.get(captures, "options");
    const timeout = try h.optional(scope, options, "timeout");
    try scope.put(captures, "timeout", timeout);
    if (!c.JS_IsUndefined(timeout)) {
        const finite = scope.truthy(try scope.invoke(try scope.global("Number"), "isFinite", &.{timeout}));
        if (!finite or scope.truthy(try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 5, timeout, c.JS_NewInt32(scope.engine.context, 0)))))) return h.resolved(scope, try failure(scope, captures, "timeout", "Invalid timeout: must be a finite number of seconds"));
        const ms = try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 2, timeout, c.JS_NewInt32(scope.engine.context, 1000))));
        if (scope.truthy(try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 6, ms, c.JS_NewInt32(scope.engine.context, 2_147_483_647)))))) return h.resolved(scope, try failure(scope, captures, "timeout", "Invalid timeout: maximum is 2147483.647 seconds"));
    }
    const inherit = try h.optional(scope, options, "inheritEnv");
    try scope.put(captures, "inheritEnv", if (h.nullish(inherit)) c.pi_js_bool(scope.engine.context, 1) else inherit);
    const given_cwd = try h.optional(scope, options, "cwd");
    if (scope.truthy(given_cwd)) return h.wait(advance, scope, captures, h.path.resolve(scope, try scope.get(captures, "bindings"), try scope.get(captures, "self"), try scope.get(options, "cwd")) catch |err| try h.rejected(scope, err), Stage.cwd);
    return h.resolved(scope, try start(scope, captures, try scope.get(try scope.get(captures, "self"), "cwd")));
}
