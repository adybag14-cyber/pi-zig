//! Owner-only asynchronous GuardedStorage. Raw values, including cursors and
//! backend errors, stay rooted in this VM; native workers never receive them.
const std = @import("std");
const engine_mod = @import("engine.zig");
const durable = @import("native_durable.zig");
const sdk = @import("native_sdk.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub const Pending = struct { promise: c.JSValue, public: c.JSValue, next: ?*Pending = null };

pub fn object(engine: *Engine, session: c.JSValue) !c.JSValue {
    const value = try engine.checked(c.JS_NewObjectClass(engine.context, engine.native_durable_class));
    errdefer engine.freeValue(value);
    const self = try engine.gpa.create(durable.State);
    errdefer engine.gpa.destroy(self);
    self.* = .{ .engine = engine, .kind = .guarded_storage, .memory = undefined, .parent = c.JS_DupValue(engine.context, session), .tail = c.pi_js_undefined() };
    errdefer engine.freeValue(self.parent);
    inline for (std.meta.fields(durable.Method)[0..16]) |field| {
        try sdk.put(engine, value, field.name, try engine.checked(c.pi_js_function_magic(engine.context, method, field.name, 1, @intCast(field.value))));
    }
    _ = c.JS_SetOpaque(value, self);
    return value;
}

fn method(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const self = durable.state(engine, receiver) catch |err| return durable.rejectedPromise(engine, err);
    if (self.kind != .guarded_storage) return durable.rejectedPromise(engine, error.InvalidDurableReceiver);
    const op: durable.Method = @enumFromInt(magic);
    const args = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    return (if (op == .close) close(self, args) else call(self, receiver, op, args)) catch |err| durable.rejectedPromise(engine, err);
}

fn readContext(op: durable.Method, args: []const c.JSValue) c.JSValue {
    const index: usize = switch (op) {
        .mintId, .commit => return c.pi_js_undefined(),
        .entry => if (args.len >= 3 and !c.JS_IsUndefined(args[2])) 2 else 1,
        .scanConversations, .scanEntries, .scanTasks, .scanSubmissions, .scanDocuments => 3,
        .findLatestHeadMarker, .submissionByRequest, .findDocument, .document => 2,
        else => 1,
    };
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn forwardedArguments(op: durable.Method, args: []const c.JSValue, output: *[4]c.JSValue) []const c.JSValue {
    const count: usize = switch (op) {
        .mintId => 0,
        .entry => if (args.len >= 3 and !c.JS_IsUndefined(args[2])) 3 else 2,
        .scanConversations, .scanEntries, .scanTasks, .scanSubmissions, .scanDocuments => 4,
        .findLatestHeadMarker, .submissionByRequest, .findDocument, .document => 3,
        else => 2,
    };
    for (output[0..count], 0..) |*value, index| value.* = if (index < args.len) args[index] else c.pi_js_undefined();
    return output[0..count];
}

fn call(self: *durable.State, receiver: c.JSValue, op: durable.Method, args: []const c.JSValue) !c.JSValue {
    const engine = self.engine;
    const native = try durable.state(engine, self.parent);
    try durable.assertVMHealthy(native);
    if (self.storage_closed or native.session.?.storage.closing.load(.acquire)) return sdk.sourceError(engine, "Session is closed");
    // Reserve all host-owned tracking before entering an arbitrary backend.
    const node = try engine.gpa.create(Pending);
    var admitted = false;
    errdefer if (!admitted) engine.gpa.destroy(node);
    var functions: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    errdefer engine.freeValue(promise);
    defer for (functions) |function| engine.freeValue(function);
    var captures = [_]c.JSValue{ receiver, readContext(op, args), functions[0], functions[1], promise };
    const fulfilled = try engine.checked(c.JS_NewCFunctionData(engine.context, settled, 1, 0, captures.len, &captures));
    defer engine.freeValue(fulfilled);
    const rejected = try engine.checked(c.JS_NewCFunctionData(engine.context, settled, 1, 1, captures.len, &captures));
    defer engine.freeValue(rejected);
    var raw_functions: [2]c.JSValue = undefined;
    const raw_call = try engine.checked(c.JS_NewPromiseCapability(engine.context, &raw_functions));
    defer engine.freeValue(raw_call);
    defer for (raw_functions) |function| engine.freeValue(function);
    const observed = try engine.checked(c.JS_PromiseThen(engine.context, raw_call, fulfilled, rejected));
    defer engine.freeValue(observed);
    // A synchronous backend throw is converted to the same asynchronous path.
    var synchronous_error = false;
    var forwarded: [4]c.JSValue = undefined;
    const returned = sdk.invoke(engine, native.parent, @tagName(op), forwardedArguments(op, args, &forwarded)) catch |err| blk: {
        _ = durable.reject(engine, err);
        synchronous_error = true;
        break :blk c.JS_GetException(engine.context);
    };
    defer engine.freeValue(returned);
    // Promise reactions cannot run until this native callback returns. The
    // backend is invoked before admission, matching Source's async wrapper:
    // a reentrant close from inside that invocation sees the earlier calls.
    // An intrusive node was reserved before invocation, so a reentrant call
    // cannot consume an array capacity reservation or force a late allocation.
    node.* = .{ .promise = c.JS_DupValue(engine.context, raw_call), .public = c.JS_DupValue(engine.context, promise), .next = self.guarded_calls };
    self.guarded_calls = node;
    admitted = true;
    _ = native.session.?.storage.underway.fetchAdd(1, .acq_rel);
    _ = try resolve(engine, raw_functions[if (synchronous_error) 1 else 0], returned);
    return promise;
}

fn settled(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, rejected: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const self = durable.state(engine, data[0]) catch |err| return durable.reject(engine, err);
    const native = durable.state(engine, self.parent) catch |err| return durable.reject(engine, err);
    const value = if (argc > 0) argv[0] else c.pi_js_undefined();
    // Remove the admission regardless of guest failure formatting or report
    // callbacks. The reserved native close drain observes the same counter.
    defer {
        var previous: ?*Pending = null;
        var item = self.guarded_calls;
        while (item) |pending| {
            if (c.JS_IsStrictEqual(engine.context, pending.public, data[4])) {
                if (previous) |before| before.next = pending.next else self.guarded_calls = pending.next;
                engine.freeValue(pending.promise);
                engine.freeValue(pending.public);
                engine.gpa.destroy(pending);
                break;
            }
            previous = pending;
            item = pending.next;
        }
        _ = native.session.?.storage.underway.fetchSub(1, .acq_rel);
        native.session.?.io.futexWake(u32, &native.session.?.storage.underway.raw, std.math.maxInt(u32));
    }
    return complete(native, data[1], rejected != 0, value, data[2], data[3]) catch |err| blk: {
        _ = durable.reject(engine, err);
        const reason = c.JS_GetException(engine.context);
        defer engine.freeValue(reason);
        break :blk resolve(engine, data[3], reason) catch |settle_error| durable.reject(engine, settle_error);
    };
}

fn complete(native: *durable.State, read: c.JSValue, rejected: bool, value: c.JSValue, fulfill: c.JSValue, reject: c.JSValue) !c.JSValue {
    const engine = native.engine;
    try durable.assertVMHealthy(native);
    if (rejected) {
        var exempt = false;
        if (!c.JS_IsUndefined(read)) {
            exempt = try @import("native_durable_errors.zig").isRequestError(engine, value);
            if (!exempt) {
                // Source reads abortSignal?.aborted, rather than invoking the
                // context's cancellation method or replacing the raw reason.
                const signal = try sdk.get(engine, read, "abortSignal");
                defer engine.freeValue(signal);
                if (!c.JS_IsUndefined(signal) and !c.JS_IsNull(signal)) {
                    const aborted = try sdk.get(engine, signal, "aborted");
                    defer engine.freeValue(aborted);
                    exempt = c.JS_IsStrictEqual(engine.context, aborted, c.pi_js_bool(engine.context, 1));
                }
            }
        }
        if (!exempt) durable.captureStorageFailure(native, native.session_lease.?.adapter.?.session_value, value);
    }
    return resolve(engine, if (rejected) reject else fulfill, value);
}

fn resolve(engine: *Engine, function: c.JSValue, value: c.JSValue) !c.JSValue {
    var args = [_]c.JSValue{value};
    const ignored = try engine.checked(c.JS_Call(engine.context, function, c.pi_js_undefined(), 1, &args));
    engine.freeValue(ignored);
    return c.pi_js_undefined();
}

fn ignore(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn adopt(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_DupValue(context, data[0]);
}
fn closeRaw(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const native = durable.state(engine, data[0]) catch |err| return durable.reject(engine, err);
    // Public GuardedStorage.close always reaches the original backend and does
    // not itself fail the Session. Session.close owns its separate close latch.
    return sdk.invoke(engine, native.parent, "close", &.{data[1]}) catch |err| durable.reject(engine, err);
}
fn close(self: *durable.State, args: []const c.JSValue) !c.JSValue {
    const engine = self.engine;
    self.storage_closed = true;
    const cleanup_context = if (args.len > 0) args[0] else c.pi_js_undefined();
    var captures = [_]c.JSValue{ self.parent, cleanup_context };
    const finish = try engine.checked(c.JS_NewCFunctionData(engine.context, closeRaw, 1, 0, captures.len, &captures));
    defer engine.freeValue(finish);
    const ignored = try engine.checked(c.JS_NewCFunction(engine.context, ignore, "guarded-storage-close-settled", 0));
    defer engine.freeValue(ignored);
    var barrier = try durable.resolvedPromise(engine, c.pi_js_undefined());
    defer engine.freeValue(barrier);
    // All calls already run concurrently. Chaining normalized observations
    // waits for the snapshot without reading the guest's Promise intrinsics.
    var current = self.guarded_calls;
    while (current) |pending| : (current = pending.next) {
        const normalized = try engine.checked(c.JS_PromiseThen(engine.context, pending.promise, ignored, ignored));
        defer engine.freeValue(normalized);
        var data = [_]c.JSValue{normalized};
        const next_call = try engine.checked(c.JS_NewCFunctionData(engine.context, adopt, 1, 0, data.len, &data));
        defer engine.freeValue(next_call);
        const next = try engine.checked(c.JS_PromiseThen(engine.context, barrier, next_call, c.pi_js_undefined()));
        engine.freeValue(barrier);
        barrier = next;
    }
    return engine.checked(c.JS_PromiseThen(engine.context, barrier, finish, c.pi_js_undefined()));
}
