//! Owner-pumped scheduler mutations. Busy native Session lines are retried;
//! a VM owner never waits for a worker which may be awaiting a VM callback.
const std = @import("std");
const engine_mod = @import("engine.zig");
const durable = @import("native_durable.zig");
const sdk = @import("native_sdk.zig");
const tasks = @import("native_durable_tasks.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;
const Kind = enum { abort, conversation };
const Request = struct { kind: Kind, accepted: bool, conversation: u64, background: bool, context: c.JSValue, resolve: c.JSValue, reject: c.JSValue };
pub const Queue = struct {
    items: std.ArrayList(Request) = .empty,
    fn release(engine: *Engine, request: Request) void {
        engine.freeValue(request.context);
        engine.freeValue(request.resolve);
        engine.freeValue(request.reject);
    }
    pub fn deinit(self: *Queue, engine: *Engine) void {
        for (self.items.items) |request| release(engine, request);
        self.items.deinit(engine.gpa);
    }
    pub fn close(self: *Queue, engine: *Engine, reason: c.JSValue) !void {
        var index: usize = 0;
        while (index < self.items.items.len) {
            // A Session job accepted before close keeps its place on the line.
            // Its mark/read finishes before the queued backend-close job.
            if (self.items.items[index].accepted) {
                index += 1;
                continue;
            }
            const request = self.items.orderedRemove(index);
            defer release(engine, request);
            var arguments = [_]c.JSValue{reason};
            const ignored = try engine.checked(c.JS_Call(engine.context, request.reject, c.pi_js_undefined(), 1, &arguments));
            engine.freeValue(ignored);
        }
    }
    fn admit(self: *Queue, manager: *tasks.Manager, conversation: u64, background: bool, context: c.JSValue) !c.JSValue {
        return self.admitKind(manager, .abort, false, conversation, background, context);
    }
    fn admitAccepted(self: *Queue, manager: *tasks.Manager, conversation: u64, background: bool, context: c.JSValue) !c.JSValue {
        return self.admitKind(manager, .abort, true, conversation, background, context);
    }
    pub fn admitConversation(self: *Queue, manager: *tasks.Manager, conversation: u64, context: c.JSValue) !c.JSValue {
        return self.admitKind(manager, .conversation, false, conversation, false, context);
    }
    pub fn admitConversationAccepted(self: *Queue, manager: *tasks.Manager, conversation: u64, context: c.JSValue) !c.JSValue {
        return self.admitKind(manager, .conversation, true, conversation, false, context);
    }
    fn admitKind(self: *Queue, manager: *tasks.Manager, kind: Kind, accepted: bool, conversation: u64, background: bool, context: c.JSValue) !c.JSValue {
        const engine = manager.engine;
        if (kind == .abort) try durable.checkCancellation(engine, context);
        if (manager.closed and !accepted) return engine.checked(c.JS_Throw(engine.context, try tasks.schedulerClosedError(manager)));
        var functions: [2]c.JSValue = undefined;
        const pending = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
        errdefer {
            engine.freeValue(pending);
            for (functions) |function| engine.freeValue(function);
        }
        try self.items.ensureUnusedCapacity(engine.gpa, 1);
        self.items.appendAssumeCapacity(.{ .kind = kind, .accepted = accepted, .conversation = conversation, .background = background, .context = c.JS_DupValue(engine.context, context), .resolve = functions[0], .reject = functions[1] });
        return pending;
    }
    pub fn pump(self: *Queue, manager: *tasks.Manager) !bool {
        const engine = manager.engine;
        if (self.items.items.len == 0) return false;
        // Mutations preserve admission order. A busy first request stays first.
        const request = self.items.items[0];
        const value = mark(manager, request) catch |err| {
            _ = durable.reject(engine, err);
            const reason = c.JS_GetException(engine.context);
            defer engine.freeValue(reason);
            const retired = self.items.orderedRemove(0);
            defer release(engine, retired);
            var arguments = [_]c.JSValue{reason};
            const ignored = try engine.checked(c.JS_Call(engine.context, request.reject, c.pi_js_undefined(), 1, &arguments));
            engine.freeValue(ignored);
            return true;
        } orelse return false;
        defer engine.freeValue(value);
        const retired = self.items.orderedRemove(0);
        defer release(engine, retired);
        var arguments = [_]c.JSValue{value};
        const ignored = try engine.checked(c.JS_Call(engine.context, request.resolve, c.pi_js_undefined(), 1, &arguments));
        engine.freeValue(ignored);
        return true;
    }
    fn mark(manager: *tasks.Manager, request: Request) !?c.JSValue {
        const engine = manager.engine;
        if (manager.closed and !request.accepted) return try engine.checked(c.JS_Throw(engine.context, try tasks.schedulerClosedError(manager)));
        const native = try durable.state(engine, manager.session);
        if (native.failure_reason) |cause| return try engine.checked(c.JS_Throw(engine.context, try @import("native_durable_errors.zig").sessionFailed(engine, cause)));
        if (request.kind == .conversation) {
            const Read = struct {
                fn apply(raw: ?*anyopaque, tx: *@import("../durable/session.zig").Transaction, _: @import("../durable/types.zig").Context) !@import("../durable/backend/json.zig").Value {
                    const id: *u64 = @ptrCast(@alignCast(raw.?));
                    return .{ .bool = try tx.readRecord(.conversation, id.*) != null };
                }
            };
            var id = request.conversation;
            var result = (try manager.lease.value.tryCommit(Read.apply, &id, .{}, .{})) orelse return null;
            defer result.deinit();
            return c.pi_js_bool(engine.context, @intFromBool(result.value.value.bool));
        }
        try durable.checkCancellation(engine, request.context);
        const reached = (try manager.scheduler.tryAbortConversation(engine.gpa, request.conversation, request.background, .{})) orelse return null;
        defer engine.gpa.free(reached);
        const result = try sdk.array(engine);
        errdefer engine.freeValue(result);
        for (reached) |id| try sdk.append(engine, result, c.JS_NewInt64(engine.context, @intCast(id)));
        return result;
    }
};
/// Only mark admission participates in the Session queue. Settlement waits run
/// afterwards so the tasks being joined can still commit on that same line.
pub fn abortConversation(manager: *tasks.Manager, conversation: u64, background: bool, context: c.JSValue) !c.JSValue {
    const engine = manager.engine;
    const id = c.JS_NewInt64(engine.context, @intCast(conversation));
    var captures = [_]c.JSValue{ manager.session, id, c.pi_js_bool(engine.context, @intFromBool(background)), context };
    const run = try engine.checked(c.JS_NewCFunctionData(engine.context, queued, 0, 0, captures.len, &captures));
    defer engine.freeValue(run);
    const pending = try durable.enqueue(engine, manager.session, run);
    defer engine.freeValue(pending);
    const marked = try engine.checked(c.JS_NewCFunctionData(engine.context, afterMarked, 1, 0, captures.len, &captures));
    defer engine.freeValue(marked);
    return sdk.invoke(engine, pending, "then", &.{marked});
}
fn queued(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const manager = tasks.getManager(engine, data[0]) catch |err| return durable.reject(engine, err);
    const id = durable.number(engine, data[1]) catch |err| return durable.reject(engine, err);
    return manager.abort_controls.admitAccepted(manager, id, c.JS_ToBool(context, data[2]) != 0, data[3]) catch |err| durable.reject(engine, err);
}
fn afterMarked(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return afterMarkedOwned(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), data) catch |err| durable.reject(engine, err);
}
fn afterMarkedOwned(engine: *Engine, reached: c.JSValue, data: [*c]c.JSValue) !c.JSValue {
    const manager = try tasks.getManager(engine, data[0]);
    if (c.JS_ToBool(engine.context, data[2]) == 0) return tasks.wait(manager, null, try durable.number(engine, data[1]), data[3]);
    const waits = try sdk.array(engine);
    defer engine.freeValue(waits);
    for (0..try sdk.length(engine, reached)) |index| {
        const id = try engine.checked(c.JS_GetPropertyUint32(engine.context, reached, @intCast(index)));
        defer engine.freeValue(id);
        try sdk.append(engine, waits, try tasks.wait(manager, try durable.number(engine, id), null, data[3]));
    }
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try sdk.get(engine, global, "Promise");
    defer engine.freeValue(constructor);
    const all = try sdk.invoke(engine, constructor, "all", &.{waits});
    defer engine.freeValue(all);
    const idle = try engine.checked(c.JS_NewCFunctionData(engine.context, afterTasks, 0, 0, 4, data));
    defer engine.freeValue(idle);
    return sdk.invoke(engine, all, "then", &.{idle});
}
fn afterTasks(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const manager = tasks.getManager(engine, data[0]) catch |err| return durable.reject(engine, err);
    const conversation = durable.number(engine, data[1]) catch |err| return durable.reject(engine, err);
    return tasks.wait(manager, null, conversation, data[3]) catch |err| durable.reject(engine, err);
}
fn allocationExercise(gpa: std.mem.Allocator, held_worker: bool) !void {
    const engine = try Engine.init(gpa, .{ .host_await_timeout_ms = 3000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const storage = try durable.memoryObject(engine);
    defer engine.freeValue(storage);
    const session_value = try durable.sessionObject(engine, storage);
    defer engine.freeValue(session_value);
    const builtins = try sdk.array(engine);
    defer engine.freeValue(builtins);
    const registry = try @import("native_durable_registry.zig").create(engine, builtins);
    defer engine.freeValue(registry);
    const options = try sdk.object(engine);
    defer engine.freeValue(options);
    try sdk.put(engine, options, "registry", c.JS_DupValue(engine.context, registry));
    try tasks.attach(engine, session_value, options, c.pi_js_undefined());
    const manager = try tasks.getManager(engine, session_value);
    const Barrier = struct {
        session: *@import("../durable/session.zig").Session,
        entered: std.atomic.Value(bool) = .init(false),
        release: std.atomic.Value(bool) = .init(false),
        failure: ?anyerror = null,
        fn root(_: ?*anyopaque, tx: *@import("../durable/session.zig").Transaction, _: @import("../durable/types.zig").Context) !@import("../durable/backend/json.zig").Value {
            return tx.createRootConversation();
        }
        fn hold(raw: ?*anyopaque, _: *@import("../durable/session.zig").Transaction, _: @import("../durable/types.zig").Context) !@import("../durable/backend/json.zig").Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.entered.store(true, .release);
            while (!self.release.load(.acquire)) std.atomic.spinLoopHint();
            return .null;
        }
        fn run(self: *@This()) void {
            var result = self.session.commit(hold, self, .{}, .{}) catch |err| {
                self.failure = err;
                self.entered.store(true, .release);
                return;
            };
            result.deinit();
        }
    };
    var root = try manager.lease.value.commit(Barrier.root, null, .{}, .{});
    root.deinit();
    var barrier: Barrier = .{ .session = &manager.lease.value };
    var worker: ?std.Thread = null;
    defer if (worker) |thread| {
        barrier.release.store(true, .release);
        thread.join();
    };
    if (held_worker) {
        worker = try std.Thread.spawn(.{}, Barrier.run, .{&barrier});
        while (!barrier.entered.load(.acquire)) std.atomic.spinLoopHint();
        if (barrier.failure) |failure| return failure;
    }
    const context = try sdk.object(engine);
    defer engine.freeValue(context);
    const pending = try manager.abort_controls.admit(manager, 1, false, context);
    defer engine.freeValue(pending);
    if (held_worker) {
        try std.testing.expect(!try manager.abort_controls.pump(manager));
        try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, pending));
        barrier.release.store(true, .release);
        worker.?.join();
        worker = null;
        if (barrier.failure) |failure| return failure;
    }
    const generation = engine.native_allocation_generation;
    try std.testing.expect(try manager.abort_controls.pump(manager));
    const settled = engine.awaitValue(pending) catch |err| return engine.nativeAllocationError(err, generation);
    defer engine.freeValue(settled);
    try std.testing.expectEqual(@as(usize, 0), try sdk.length(engine, settled));
    const reason = try sdk.object(engine);
    defer engine.freeValue(reason);
    const signal = try @import("abort_signal.zig").create(engine);
    defer engine.freeValue(signal);
    try sdk.put(engine, context, "abortSignal", c.JS_DupValue(engine.context, signal));
    const canceled = try manager.abort_controls.admit(manager, 1, false, context);
    defer engine.freeValue(canceled);
    try @import("abort_signal.zig").abort(engine, signal, reason);
    try std.testing.expect(try manager.abort_controls.pump(manager));
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, canceled));
    const original = c.JS_PromiseResult(engine.context, canceled);
    defer engine.freeValue(original);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, original));
    const closing = try manager.abort_controls.admitConversation(manager, 1, context);
    defer engine.freeValue(closing);
    manager.close();
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, closing));
    try std.testing.expectEqual(@as(usize, 0), manager.abort_controls.items.items.len);
}
test "native durable VM scheduler controls do not block a held worker line and preserve cancellation before mark and close admission" {
    try allocationExercise(std.testing.allocator, true);
}
test "native durable VM scheduler control queue promises and requests unwind every host allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationExercise, .{false});
}
