//! Source-only Node24 FileHandle byte-stream method. No public installation.
//! A genuine native ReadableStream/controller and its private cancel intrinsic
//! must be supplied by the complete stream graph; no guest/mock fallback exists.
const std = @import("std");
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const lifecycle = @import("native_env_node_file_lifecycle.zig");
const async_value = @import("native_agent_async.zig");
const events = @import("node_events.zig");
const c = js.c;
const Scope = h.Scope;
const Operation = enum(c_int) { pull, cancel };
const Stage = enum(c_int) { read, done, canceled };

fn invalidType(scope: *Scope, name: []const u8, expected: []const u8, value: c.JSValue) anyerror {
    const received = try events.description(scope.engine, value);
    defer scope.engine.gpa.free(received);
    const message = try std.fmt.allocPrint(scope.engine.gpa, "The \"{s}\" {s} must be of type {s}. Received {s}", .{ name, if (std.mem.indexOfScalar(u8, name, '.') != null) "property" else "argument", expected, received });
    defer scope.engine.gpa.free(message);
    return events.codedError(scope.engine, "TypeError", "ERR_INVALID_ARG_TYPE", message);
}
fn invalidState(scope: *Scope, message: []const u8) anyerror {
    const formatted = try std.fmt.allocPrint(scope.engine.gpa, "Invalid state: {s}", .{message});
    defer scope.engine.gpa.free(formatted);
    return events.codedError(scope.engine, "Error", "ERR_INVALID_STATE", formatted);
}
fn done(scope: *Scope, owner: c.JSValue, stage: Stage) !void {
    const saved = try scope.get(owner, "saved");
    const bindings = try scope.get(saved, "bindings");
    const receiver = try scope.get(saved, "self");
    _ = try lifecycle.invokeSymbol(scope, bindings, receiver, .unref_method);
    // Node unrefs before calling the mutable public close method. A canceled
    // stream and EOF share this exact ownership route.
    const pending = if (scope.truthy(try scope.get(saved, "autoClose"))) try scope.invoke(receiver, "close", &.{}) else c.pi_js_undefined();
    try async_value.wait(continued, scope.engine, owner, pending, @intFromEnum(stage));
}
fn respond(scope: *Scope, owner: c.JSValue, count: c.JSValue) !void {
    const controller = try scope.get(owner, "controller");
    // Refetch after await/close, as the actual controller may replace or
    // invalidate its BYOB request during cancellation or EOF processing.
    _ = try scope.invoke(try scope.get(controller, "byobRequest"), "respond", &.{count});
    try async_value.settle(scope.engine, owner, false, c.pi_js_undefined());
}
fn continued(engine: *js.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    if (rejected) return async_value.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (@as(Stage, @enumFromInt(raw))) {
        .read => {
            const count = try scope.get(value, "bytesRead");
            if (scope.equal(count, c.JS_NewInt32(engine.context, 0))) {
                _ = try scope.invoke(try scope.get(owner, "controller"), "close", &.{});
                try scope.put(owner, "count", count);
                return done(&scope, owner, .done);
            }
            try respond(&scope, owner, count);
        },
        .done => try respond(&scope, owner, try scope.get(owner, "count")),
        .canceled => try async_value.settle(engine, owner, false, c.pi_js_undefined()),
    }
}
fn begin(scope: *Scope, owner: c.JSValue, saved: c.JSValue, args: []const c.JSValue, operation: Operation) !void {
    try scope.put(owner, "saved", saved);
    if (operation == .cancel) return done(scope, owner, .canceled);
    const controller = h.arg(args, 0);
    try scope.put(owner, "controller", controller);
    const view = try scope.get(try scope.get(controller, "byobRequest"), "view");
    // Preserve Source's byteOffset argument rather than silently changing its
    // observable read call for a BYOB view with a nonzero underlying offset.
    const pending = try scope.call(try scope.get(saved, "read"), try scope.get(saved, "self"), &.{ view, try scope.get(view, "byteOffset"), try scope.get(view, "byteLength") });
    try async_value.wait(continued, scope.engine, owner, pending, @intFromEnum(Stage.read));
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = async_value.create(engine, roots[0]) catch |err| return @import("native_durable.zig").rejectedPromise(engine, err);
    defer engine.freeValue(pending.owner);
    begin(&scope, pending.owner, roots[0], if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(raw)) catch |err| {
        async_value.rejectError(engine, pending.owner, err) catch |failure| {
            engine.freeValue(pending.promise);
            return @import("native_durable.zig").reject(engine, failure);
        };
    };
    return pending.promise;
}
fn closed(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return js.call(engine, roots[0], c.pi_js_undefined(), &.{roots[1]}) catch |err| @import("native_durable.zig").reject(engine, err);
}

/// Bindings must retain the genuine native byte-stream constructor and cancel
/// intrinsic. This function neither installs globals nor manufactures a
/// controller, a BYOB request, a result packet, or expected Source output.
pub fn create(scope: *Scope, bindings: c.JSValue, receiver: c.JSValue, argument: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    if (scope.equal(try lifecycle.get(scope, bindings, receiver, .fd), c.JS_NewInt32(engine.context, -1))) return invalidState(scope, "The FileHandle is closed");
    if (scope.truthy(try lifecycle.get(scope, bindings, receiver, .close_promise))) return invalidState(scope, "The FileHandle is closing");
    if (scope.truthy(try lifecycle.get(scope, bindings, receiver, .locked))) return invalidState(scope, "The FileHandle is locked");
    // This Source transition intentionally precedes validation. An invalid
    // options call leaves the handle locked; do not add a rollback here.
    try lifecycle.set(scope, bindings, receiver, .locked, c.pi_js_bool(engine.context, 1));
    const options = if (c.JS_IsUndefined(argument)) try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()))) else argument;
    if (!c.JS_IsObject(options) or c.JS_IsArray(options) or c.JS_IsFunction(engine.context, options)) return invalidType(scope, "options", "object", options);
    const type_value = try scope.get(options, "type");
    const auto_close_value = try scope.get(options, "autoClose");
    const auto_close = if (c.JS_IsUndefined(auto_close_value)) c.pi_js_bool(engine.context, 0) else auto_close_value;
    if (!c.JS_IsBool(auto_close)) return invalidType(scope, "options.autoClose", "boolean", auto_close);
    if (!c.JS_IsUndefined(type_value) and !scope.equal(type_value, try scope.text("bytes"))) {
        _ = try scope.invoke(try scope.get(bindings, "process"), "emitWarning", &.{ try scope.text("A non-\"bytes\" options.type has no effect. A byte-oriented steam is always created."), try scope.text("ExperimentalWarning") });
    }
    const saved = try scope.object();
    try scope.put(saved, "bindings", bindings);
    try scope.put(saved, "self", receiver);
    try scope.put(saved, "autoClose", auto_close);
    try scope.put(saved, "read", try scope.get(receiver, "read"));
    const constructor = try scope.get(bindings, "fileHandleReadableStream");
    const cancel = try scope.get(bindings, "fileHandleReadableStreamCancel");
    if (!c.JS_IsFunction(engine.context, constructor) or !c.JS_IsFunction(engine.context, cancel)) return error.NativeFileHandleByteStreamDependencyMissing;
    const source = try scope.object();
    try scope.put(source, "type", try scope.text("bytes"));
    try scope.put(source, "autoAllocateChunkSize", c.JS_NewInt32(engine.context, 16384));
    var roots = [_]c.JSValue{saved};
    inline for (std.meta.fields(Operation)) |field| {
        const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, if (field.value == 0) 1 else 0, @intCast(field.value), roots.len, &roots)));
        try scope.put(source, field.name, function);
    }
    var args = [_]c.JSValue{source};
    const readable = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args)));
    _ = try lifecycle.invokeSymbol(scope, bindings, receiver, .ref_method);
    var close_roots = [_]c.JSValue{ cancel, readable };
    const listener = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, closed, "", 0, 0, close_roots.len, &close_roots)));
    _ = try scope.invoke(receiver, "once", &.{ try scope.text("close"), listener });
    return c.JS_DupValue(engine.context, readable);
}
