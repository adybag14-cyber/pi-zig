//! Source listFilesOver as native guest continuations; Connection calls stay virtual and asynchronous.
const std = @import("std");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const awaiting = @import("native_durable_await.zig");
const values = @import("native_env_values.zig");
const c = js.c;
const Stage = enum(c_int) { info, listing };
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn nullish(value: c.JSValue) bool {
    return c.JS_IsNull(value) or c.JS_IsUndefined(value);
}
fn optional(scope: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (nullish(object)) c.pi_js_undefined() else scope.get(object, name);
}
fn instance(scope: *Scope, object: c.JSValue, constructor: c.JSValue) !bool {
    const result = c.JS_IsInstanceOf(scope.engine.context, object, constructor);
    if (result < 0) return js.capture(scope.engine);
    return result != 0;
}
pub fn errorResult(scope: *Scope, state: c.JSValue, code: c.JSValue, message: c.JSValue, path: c.JSValue, cause: c.JSValue) !c.JSValue {
    const constructor = try scope.get(try scope.get(state, "bindings"), "FileError");
    const args = [_]c.JSValue{ code, message, path, cause };
    const failure = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, @constCast(&args))));
    return values.result(scope, false, failure);
}
pub fn aborted(scope: *Scope, state: c.JSValue) !?c.JSValue {
    const signal = try scope.get(try scope.get(state, "context"), "abortSignal");
    if (nullish(signal) or !scope.truthy(try scope.get(signal, "aborted"))) return null;
    return try errorResult(scope, state, try scope.text("aborted"), try scope.text("aborted"), try scope.get(state, "path"), c.pi_js_undefined());
}
pub fn mapError(scope: *Scope, state: c.JSValue, failure: c.JSValue) !c.JSValue {
    const bindings = try scope.get(state, "bindings");
    if (try instance(scope, failure, try scope.get(bindings, "FileError"))) return values.result(scope, false, failure);
    const remote = try scope.get(bindings, "RemoteError");
    if (!c.JS_IsUndefined(remote) and try instance(scope, failure, remote)) {
        const given = try scope.get(failure, "path");
        const path = if (nullish(given)) try scope.get(state, "path") else given;
        const raw = try scope.get(failure, "code");
        var code: []const u8 = "unknown";
        inline for (.{ .{ "aborted", "aborted" }, .{ "ENOENT", "not_found" }, .{ "EACCES", "permission_denied" }, .{ "EPERM", "permission_denied" }, .{ "ENOTDIR", "not_directory" }, .{ "EISDIR", "is_directory" }, .{ "EINVAL", "invalid" }, .{ "SYMLINK", "invalid" }, .{ "NOT_REGULAR", "invalid" } }) |mapping| {
            if (c.JS_IsStrictEqual(scope.engine.context, raw, try scope.text(mapping[0]))) code = mapping[1];
        }
        return errorResult(scope, state, try scope.text(code), try scope.get(failure, "message"), path, failure);
    }
    const base = try scope.global("Error");
    const cause = if (try instance(scope, failure, base)) failure else converted: {
        const string = try scope.global("String");
        const message = try scope.call(string, c.pi_js_undefined(), &.{failure});
        break :converted try scope.own(try js.builtin(scope.engine, "Error", &.{message}));
    };
    return errorResult(scope, state, try scope.text("unknown"), try scope.get(cause, "message"), try scope.get(state, "path"), cause);
}
pub fn captured(scope: *Scope) !c.JSValue {
    const reason = scope.engine.captured_exception orelse return error.MissingCapturedException;
    return scope.own(c.JS_DupValue(scope.engine.context, reason));
}
pub fn intrinsics(scope: *Scope, state: c.JSValue) !awaiting.Intrinsics {
    const bindings = try scope.get(state, "bindings");
    return .{ .constructor = try scope.get(bindings, "promise_constructor"), .resolve = try scope.get(bindings, "promise_resolve"), .then_function = try scope.get(bindings, "promise_then") };
}
fn wait(scope: *Scope, state: c.JSValue, pending: c.JSValue, stage: Stage) !c.JSValue {
    var intrinsic = try intrinsics(scope, state);
    return scope.own(try awaiting.continueWith(advance, scope.engine, &intrinsic, state, pending, @intFromEnum(stage)));
}
fn listing(scope: *Scope, state: c.JSValue, reply: c.JSValue) !c.JSValue {
    const json = try scope.get(reply, "json");
    const payload = try scope.get(reply, "payload");
    if (try aborted(scope, state)) |result| return result;
    const entries = try scope.array();
    const buffer = try scope.global("Buffer");
    const from = try scope.get(buffer, "from");
    const backing = try scope.get(payload, "buffer");
    const offset = try scope.get(payload, "byteOffset");
    const length = try scope.get(payload, "length");
    const bytes = try scope.call(from, buffer, &.{ backing, offset, length });
    const kinds = try scope.get(try scope.get(state, "bindings"), "kinds");
    var start = c.JS_NewInt32(scope.engine.context, 0);
    defer scope.engine.freeValue(start);
    while (true) {
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const remaining = try row.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 4, start, try row.get(bytes, "length"))));
        if (!row.truthy(remaining)) break;
        const end = try row.invoke(bytes, "indexOf", &.{ c.JS_NewInt32(scope.engine.context, 0), start });
        if (c.JS_IsStrictEqual(scope.engine.context, end, c.JS_NewInt32(scope.engine.context, -1))) break;
        const byte = try row.own(try js.getKey(scope.engine, bytes, start));
        const kind = try row.own(try js.getKey(scope.engine, kinds, byte));
        if (!c.JS_IsUndefined(kind)) {
            const object = try row.object();
            const decode = try row.get(bytes, "toString");
            const from_index = try row.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 0, start, c.JS_NewInt32(scope.engine.context, 1))));
            try row.put(object, "path", try row.call(decode, bytes, &.{ try row.text("utf8"), from_index, end }));
            try row.put(object, "kind", kind);
            _ = try row.invoke(entries, "push", &.{object});
        }
        const next = try row.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 0, end, c.JS_NewInt32(scope.engine.context, 1))));
        scope.engine.freeValue(start);
        start = c.JS_DupValue(scope.engine.context, next);
    }
    const result = try scope.object();
    try scope.put(result, "entries", entries);
    try scope.put(result, "truncated", c.pi_js_bool(scope.engine.context, @intFromBool(c.JS_IsStrictEqual(scope.engine.context, try scope.get(json, "truncated"), c.pi_js_bool(scope.engine.context, 1)))));
    return values.result(scope, true, result);
}
fn continueInfo(scope: *Scope, state: c.JSValue, info: c.JSValue) !c.JSValue {
    const features = try scope.get(info, "features");
    const supported = if (nullish(features)) false else scope.truthy(try scope.invoke(features, "includes", &.{try scope.text("listFiles")}));
    if (!supported) return errorResult(scope, state, try scope.text("not_supported"), try scope.text("The pi-env daemon does not list files; update it"), try scope.get(state, "path"), c.pi_js_undefined());
    const connection = try scope.get(state, "connection");
    const request = try scope.get(connection, "request");
    const fields = try scope.object();
    try scope.put(fields, "path", try scope.get(state, "path"));
    const options = try scope.get(state, "options");
    inline for (.{ "hidden", "gitignore", "exclude", "maxEntries", "maxBytes", "timeoutMs" }) |key| try scope.put(fields, key, try optional(scope, options, key));
    const context = try scope.get(state, "context");
    const request_options = try scope.object();
    if (scope.truthy(try scope.get(context, "abortSignal"))) try scope.put(request_options, "signal", try scope.get(context, "abortSignal"));
    const pending = try scope.call(request, connection, &.{ try scope.text("listFiles"), fields, request_options });
    return wait(scope, state, pending, .listing);
}
fn advance(engine: *js.Engine, state: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) return c.JS_DupValue(engine.context, try mapError(&scope, state, value));
    const next = (switch (@as(Stage, @enumFromInt(raw))) {
        .info => continueInfo(&scope, state, value),
        .listing => listing(&scope, state, value),
    }) catch |err| {
        if (err != error.JavaScriptException) return err;
        return c.JS_DupValue(engine.context, try mapError(&scope, state, try captured(&scope)));
    };
    return c.JS_DupValue(engine.context, next);
}
fn invokeListing(engine: *js.Engine, args: []const c.JSValue, bindings: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.object();
    try scope.put(state, "bindings", bindings);
    inline for (.{ "connection", "path", "options", "context" }, 0..) |key, index| try scope.put(state, key, arg(args, index));
    inline for (.{ "maxEntries", "maxBytes", "timeoutMs" }) |key| {
        const value = try optional(&scope, arg(args, 2), key);
        if (!c.JS_IsUndefined(value)) {
            const number = try scope.global("Number");
            const safe = scope.truthy(try scope.invoke(number, "isSafeInteger", &.{value}));
            const invalid = !safe or scope.truthy(try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 4, value, c.JS_NewInt32(engine.context, 0)))));
            if (invalid) return @import("native_durable.zig").resolvedPromise(engine, try errorResult(&scope, state, try scope.text("invalid"), try scope.text(key ++ " must be a non-negative safe integer"), arg(args, 1), c.pi_js_undefined()));
        }
    }
    if (try aborted(&scope, state)) |result| return @import("native_durable.zig").resolvedPromise(engine, result);
    const result = prepared: {
        const info = scope.invoke(arg(args, 0), "info", &.{}) catch |err| {
            if (err != error.JavaScriptException) return err;
            break :prepared try scope.own(try @import("native_durable.zig").resolvedPromise(engine, try mapError(&scope, state, try captured(&scope))));
        };
        break :prepared awaitingInfo: {
            const pending = wait(&scope, state, info, .info) catch |err| {
                if (err != error.JavaScriptException) return err;
                break :awaitingInfo try scope.own(try @import("native_durable.zig").resolvedPromise(engine, try mapError(&scope, state, try captured(&scope))));
            };
            break :awaitingInfo pending;
        };
    };
    return c.JS_DupValue(engine.context, result);
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return invokeListing(engine, if (argc > 0) argv[0..@intCast(argc)] else &.{}, data[0]) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
pub fn create(engine: *js.Engine, shared: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = try scope.object();
    inline for (.{ "FileError", "RemoteError" }) |key| try scope.put(bindings, key, try scope.get(shared, key));
    var intrinsic = try awaiting.Intrinsics.init(engine);
    defer intrinsic.deinit(engine);
    try scope.put(bindings, "promise_constructor", intrinsic.constructor);
    try scope.put(bindings, "promise_resolve", intrinsic.resolve);
    try scope.put(bindings, "promise_then", intrinsic.then_function);
    const kinds = try scope.object();
    try scope.put(kinds, "102", try scope.text("file"));
    try scope.put(kinds, "100", try scope.text("directory"));
    try scope.put(kinds, "108", try scope.text("symlink"));
    try scope.put(bindings, "kinds", kinds);
    var captures = [_]c.JSValue{bindings};
    const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "listFilesOver", 4, 0, captures.len, &captures)));
    const prototype = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
    if (c.JS_SetPrototype(engine.context, function, prototype) < 0) return js.capture(engine);
    return c.JS_DupValue(engine.context, function);
}
