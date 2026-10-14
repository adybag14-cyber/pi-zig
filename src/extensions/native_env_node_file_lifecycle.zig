//! Node24 FileHandle's actual symbol/ref/close lifecycle, without a public class installation.
//! The complete method and stream graph must be assembled before this layer replaces the private C owner.
const js = @import("native_js_values.zig");
const std = @import("std");
const h = @import("native_env_remote_helpers.zig");
const c = js.c;
const Scope = h.Scope;
pub const Key = enum { handle, fd, refs, close_promise, close_reason, close_resolve, close_reject, locked, ref_method, unref_method, transfer_method, transfer_list_method, deserialize_method, async_dispose };
pub fn prepare(scope: *Scope, bindings: c.JSValue) !void {
    if (!c.JS_IsUndefined(try scope.get(bindings, "fileHandleSymbols"))) return;
    try @import("node_events.zig").install(scope.engine);
    if (scope.engine.dom_exception_class == 0) try @import("dom_exception.zig").install(scope.engine);
    const keys = try scope.object();
    inline for (.{
        .{ Key.handle, "kHandle" },                                  .{ Key.fd, "kFd" },                      .{ Key.refs, "kRefs" },                                .{ Key.close_promise, "kClosePromise" },
        .{ Key.close_reason, "kCloseReason" },                       .{ Key.close_resolve, "kCloseResolve" }, .{ Key.close_reject, "kCloseReject" },                 .{ Key.locked, "kLocked" },
        .{ Key.ref_method, "kRef" },                                 .{ Key.unref_method, "kUnref" },         .{ Key.transfer_method, "messaging_transfer_symbol" }, .{ Key.transfer_list_method, "messaging_transfer_list_symbol" },
        .{ Key.deserialize_method, "messaging_deserialize_symbol" },
    }) |entry| try scope.put(keys, @tagName(entry[0]), try scope.own(try scope.engine.checked(c.JS_NewSymbol(scope.engine.context, entry[1], false))));
    try scope.put(keys, @tagName(Key.async_dispose), try scope.own(try scope.engine.checked(c.JS_AtomToValue(scope.engine.context, c.JS_ATOM_Symbol_asyncDispose))));
    var intrinsic = try @import("native_durable_await.zig").Intrinsics.init(scope.engine);
    defer intrinsic.deinit(scope.engine);
    try scope.put(bindings, "promise_constructor", intrinsic.constructor);
    try scope.put(bindings, "promise_resolve", intrinsic.resolve);
    try scope.put(bindings, "promise_then", intrinsic.then_function);
    try scope.put(bindings, "safeFileHandlePromises", try scope.own(try @import("native_safe_promise.zig").create(scope.engine)));
    try scope.put(bindings, "fileHandleSymbols", keys);
}
pub fn symbol(scope: *Scope, bindings: c.JSValue, comptime name: Key) !c.JSValue {
    return scope.get(try scope.get(bindings, "fileHandleSymbols"), @tagName(name));
}
pub fn get(scope: *Scope, bindings: c.JSValue, receiver: c.JSValue, comptime name: Key) !c.JSValue {
    return scope.own(try js.getKey(scope.engine, receiver, try symbol(scope, bindings, name)));
}
pub fn set(scope: *Scope, bindings: c.JSValue, receiver: c.JSValue, comptime name: Key, value: c.JSValue) !void {
    try js.setKey(scope.engine, receiver, try symbol(scope, bindings, name), value);
}
pub fn invokeSymbol(scope: *Scope, bindings: c.JSValue, receiver: c.JSValue, comptime name: Key) !c.JSValue {
    return scope.call(try get(scope, bindings, receiver, name), receiver, &.{});
}
pub fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, constants: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = constants[0];
    const constructor = try scope.get(bindings, "FileHandle");
    const parent = try scope.own(try engine.checked(c.JS_GetPrototype(engine.context, constructor)));
    const receiver = try scope.own(try engine.checked(c.JS_CallConstructor2(engine.context, parent, target, 0, null)));
    var captures = [_]c.JSValue{ bindings, receiver };
    // Class fields define an own property; inherited setters must not receive the close field.
    try scope.put(receiver, "close", try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, boundClose, "close", 0, 0, captures.len, &captures))));
    const handle = h.arg(args, 0);
    try set(&scope, bindings, receiver, .handle, handle);
    try set(&scope, bindings, receiver, .fd, if (scope.truthy(handle)) try scope.get(handle, "fd") else c.JS_NewInt32(engine.context, -1));
    try set(&scope, bindings, receiver, .refs, c.JS_NewInt32(engine.context, 1));
    try set(&scope, bindings, receiver, .close_promise, c.pi_js_null());
    return c.JS_DupValue(engine.context, receiver);
}
fn boundClose(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = close(&scope, data[0], data[1]) catch |err| return @import("native_durable.zig").reject(engine, err);
    return c.JS_DupValue(engine.context, result);
}
fn changeRefs(scope: *Scope, bindings: c.JSValue, receiver: c.JSValue, increment: bool) !void {
    const old = try get(scope, bindings, receiver, .refs);
    const value = if (increment) try scope.own(try scope.engine.checked(c.JS_PiIncrement(scope.engine.context, old))) else decrement: {
        const numeric = try scope.own(try scope.engine.checked(c.JS_PiToNumeric(scope.engine.context, old)));
        const one = if (c.JS_IsBigInt(numeric)) try scope.own(try scope.engine.checked(c.JS_NewBigInt64(scope.engine.context, 1))) else c.JS_NewInt32(scope.engine.context, 1);
        break :decrement try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 1, numeric, one)));
    };
    try set(scope, bindings, receiver, .refs, value);
}
pub fn ref(scope: *Scope, bindings: c.JSValue, receiver: c.JSValue) !void {
    try changeRefs(scope, bindings, receiver, true);
}
pub fn unref(scope: *Scope, bindings: c.JSValue, receiver: c.JSValue) !void {
    try changeRefs(scope, bindings, receiver, false);
    if (scope.equal(try get(scope, bindings, receiver, .refs), c.JS_NewInt32(scope.engine.context, 0))) {
        try set(scope, bindings, receiver, .fd, c.JS_NewInt32(scope.engine.context, -1));
        const pending = try scope.invoke(try get(scope, bindings, receiver, .handle), "close", &.{});
        _ = try scope.call(try scope.get(bindings, "promise_then"), pending, &.{ try get(scope, bindings, receiver, .close_resolve), try get(scope, bindings, receiver, .close_reject) });
    }
}
fn deferredExecutor(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const args = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    set(&scope, data[0], data[1], .close_resolve, h.arg(args, 0)) catch |err| return @import("native_durable.zig").reject(engine, err);
    set(&scope, data[0], data[1], .close_reject, h.arg(args, 1)) catch |err| return @import("native_durable.zig").reject(engine, err);
    return c.pi_js_undefined();
}
fn cleanupValue(scope: *Scope, saved: c.JSValue) !void {
    const bindings = try scope.get(saved, "bindings");
    const receiver = try scope.get(saved, "self");
    try set(scope, bindings, receiver, .close_promise, c.pi_js_undefined());
    if (scope.truthy(try scope.get(saved, "deferred"))) {
        try set(scope, bindings, receiver, .close_reject, c.pi_js_undefined());
        try set(scope, bindings, receiver, .close_resolve, c.pi_js_undefined());
    }
}
fn cleanup(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    cleanupValue(&scope, data[0]) catch |err| return @import("native_durable.zig").reject(engine, err);
    return c.pi_js_undefined();
}
pub fn close(scope: *Scope, bindings: c.JSValue, receiver: c.JSValue) !c.JSValue {
    if (scope.equal(try get(scope, bindings, receiver, .fd), c.JS_NewInt32(scope.engine.context, -1))) return h.resolved(scope, c.pi_js_undefined());
    if (scope.truthy(try get(scope, bindings, receiver, .close_promise))) return get(scope, bindings, receiver, .close_promise);
    try changeRefs(scope, bindings, receiver, false);
    const deferred = !scope.equal(try get(scope, bindings, receiver, .refs), c.JS_NewInt32(scope.engine.context, 0));
    const pending = if (deferred) create: {
        var captures = [_]c.JSValue{ bindings, receiver };
        const executor = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, deferredExecutor, "", 2, 0, captures.len, &captures)));
        var args = [_]c.JSValue{executor};
        break :create try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(bindings, "promise_constructor"), args.len, &args)));
    } else create: {
        try set(scope, bindings, receiver, .fd, c.JS_NewInt32(scope.engine.context, -1));
        break :create try scope.invoke(try get(scope, bindings, receiver, .handle), "close", &.{});
    };
    const saved = try scope.object();
    try scope.put(saved, "bindings", bindings);
    try scope.put(saved, "self", receiver);
    try scope.put(saved, "deferred", c.pi_js_bool(scope.engine.context, @intFromBool(deferred)));
    var captures = [_]c.JSValue{saved};
    const callback = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, cleanup, "", 0, 0, captures.len, &captures)));
    const final = try @import("native_safe_promise.zig").finallyValue(scope, try scope.get(bindings, "safeFileHandlePromises"), pending, callback);
    try set(scope, bindings, receiver, .close_promise, final);
    _ = try scope.invoke(receiver, "emit", &.{try scope.text("close")});
    return final;
}
pub fn getAsyncId(scope: *Scope, bindings: c.JSValue, receiver: c.JSValue) !c.JSValue {
    return scope.invoke(try get(scope, bindings, receiver, .handle), "getAsyncId", &.{});
}
pub fn transfer(scope: *Scope, bindings: c.JSValue, receiver: c.JSValue) !c.JSValue {
    const busy = scope.truthy(try get(scope, bindings, receiver, .close_promise)) or
        scope.truthy(try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 6, try get(scope, bindings, receiver, .refs), c.JS_NewInt32(scope.engine.context, 1)))));
    if (busy) return h.throw(scope, try scope.own(try @import("dom_exception.zig").create(scope.engine, "Cannot transfer FileHandle while in use", "DataCloneError")));
    const handle = try get(scope, bindings, receiver, .handle);
    try set(scope, bindings, receiver, .fd, c.JS_NewInt32(scope.engine.context, -1));
    try set(scope, bindings, receiver, .close_reason, try scope.text("The FileHandle has been transferred"));
    try set(scope, bindings, receiver, .handle, c.pi_js_null());
    try set(scope, bindings, receiver, .refs, c.JS_NewInt32(scope.engine.context, 0));
    const data = try scope.object();
    try scope.put(data, "handle", handle);
    const result = try scope.object();
    try scope.put(result, "data", data);
    try scope.put(result, "deserializeInfo", try scope.text("internal/fs/promises:FileHandle"));
    return result;
}
pub fn transferList(scope: *Scope, bindings: c.JSValue, receiver: c.JSValue) !c.JSValue {
    const result = try scope.array();
    try scope.index(result, 0, try get(scope, bindings, receiver, .handle));
    return result;
}
pub fn deserialize(scope: *Scope, bindings: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !void {
    const handle = try scope.get(h.arg(args, 0), "handle");
    try set(scope, bindings, receiver, .handle, handle);
    try set(scope, bindings, receiver, .fd, try scope.get(handle, "fd"));
}
fn disposed(engine: *js.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!void {
    try @import("native_agent_async.zig").settle(engine, owner, rejected, if (rejected) value else c.pi_js_undefined());
}
pub fn asyncDispose(scope: *Scope, bindings: c.JSValue, receiver: c.JSValue) !c.JSValue {
    _ = bindings;
    const pending = try @import("native_agent_async.zig").create(scope.engine, receiver);
    defer scope.engine.freeValue(pending.owner);
    var transferred = false;
    errdefer if (!transferred) scope.engine.freeValue(pending.promise);
    beginDispose(scope, pending.owner, receiver) catch |err| try @import("native_agent_async.zig").rejectError(scope.engine, pending.owner, err);
    transferred = true;
    return scope.own(pending.promise);
}
fn beginDispose(scope: *Scope, owner: c.JSValue, receiver: c.JSValue) !void {
    try @import("native_agent_async.zig").wait(disposed, scope.engine, owner, try scope.invoke(receiver, "close", &.{}), 0);
}

fn assertion(scope: *Scope) !c.JSValue {
    // Node imports internal/assert here, whose error is deliberately different
    // from the public assert module's AssertionError object and own fields.
    const message = "handle must be an instance of FileHandle\nThis is caused by either a bug in Node.js or incorrect usage of Node.js internals.\nPlease open an issue with this stack trace at https://github.com/nodejs/node/issues\n";
    const error_value = try scope.own(try js.builtin(scope.engine, "Error", &.{try scope.text(message)}));
    try scope.put(error_value, "code", try scope.text("ERR_INTERNAL_ASSERTION"));
    return error_value;
}
fn completedCall(engine: *js.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    _ = try invokeSymbol(&scope, try scope.get(owner, "bindings"), try scope.get(owner, "agent"), .unref_method);
    try @import("native_agent_async.zig").settle(engine, owner, rejected, value);
}
fn invokeOperation(scope: *Scope, owner: c.JSValue, bindings: c.JSValue, receiver: c.JSValue, operation: c.JSValue, args: []const c.JSValue) !void {
    _ = try invokeSymbol(scope, bindings, receiver, .ref_method);
    var arguments: std.ArrayList(c.JSValue) = .empty;
    defer arguments.deinit(scope.engine.gpa);
    try arguments.append(scope.engine.gpa, receiver);
    try arguments.appendSlice(scope.engine.gpa, args);
    const pending = try scope.call(operation, c.pi_js_undefined(), arguments.items);
    // Actual await uses the realm's intrinsic PromiseResolve and direct promise
    // reactions. Captured .then would introduce observable species accesses.
    try @import("native_agent_async.zig").wait(completedCall, scope.engine, owner, pending, 0);
}
fn beginCall(scope: *Scope, owner: c.JSValue, bindings: c.JSValue, receiver: c.JSValue, operation: c.JSValue, args: []const c.JSValue, name: []const u8) !void {
    if (c.JS_IsUndefined(try get(scope, bindings, receiver, .refs))) return h.throw(scope, try assertion(scope));
    if (scope.equal(try scope.get(receiver, "fd"), c.JS_NewInt32(scope.engine.context, -1))) {
        const reason = try get(scope, bindings, receiver, .close_reason);
        const error_value = try scope.own(try js.builtin(scope.engine, "Error", &.{if (h.nullish(reason)) try scope.text("file closed") else reason}));
        try scope.put(error_value, "code", try scope.text("EBADF"));
        try scope.put(error_value, "syscall", try scope.text(name));
        return h.throw(scope, error_value);
    }
    try scope.put(owner, "bindings", bindings);
    invokeOperation(scope, owner, bindings, receiver, operation, args) catch |err| {
        // A synchronous ref/operation/admission failure still enters finally.
        // Retain its original object before a mutable unref can run guest code.
        const reason = @import("native_agent_async.zig").reason(scope.engine, err);
        defer scope.engine.freeValue(reason);
        _ = try invokeSymbol(scope, bindings, receiver, .unref_method);
        return @import("native_agent_async.zig").settle(scope.engine, owner, true, reason);
    };
}
/// The actual fsCall envelope for complete method frontends. No public class is
/// installed by this module. Operation functions must represent the original
/// async method body and receive (FileHandle, ...arguments).
pub fn call(scope: *Scope, bindings: c.JSValue, receiver: c.JSValue, operation: c.JSValue, args: []const c.JSValue, name: []const u8) !c.JSValue {
    const pending = try @import("native_agent_async.zig").create(scope.engine, receiver);
    defer scope.engine.freeValue(pending.owner);
    var transferred = false;
    errdefer if (!transferred) scope.engine.freeValue(pending.promise);
    beginCall(scope, pending.owner, bindings, receiver, operation, args, name) catch |err| try @import("native_agent_async.zig").rejectError(scope.engine, pending.owner, err);
    transferred = true;
    return scope.own(pending.promise);
}
