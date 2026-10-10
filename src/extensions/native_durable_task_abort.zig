//! Public task abort admits one real mark, then joins only the observed run.
//! Private native marks retain actual invocations; no routing token is exposed.
const std = @import("std");
const em = @import("engine.zig");
const durable = @import("native_durable.zig");
const sdk = @import("native_sdk.zig");
const tasks = @import("native_durable_tasks.zig");
const scheduling = @import("../durable/scheduler.zig");
const session = @import("../durable/session.zig");
const json = @import("../durable/backend/json.zig");
const c = em.c;
const Engine = em.Engine;
test {
    _ = @import("native_durable_task_abort_test.zig");
}
const Mark = struct {
    engine: *Engine,
    queue: *Queue,
    terminal: bool = false,
    run: ?scheduling.Runtime = null,
    waiter: ?*Waiter = null,
    fn releaseRun(self: *Mark) void {
        const run = self.run orelse return;
        self.run = null;
        for (self.queue.marks.items, 0..) |mark, index| if (mark == self) {
            _ = self.queue.marks.orderedRemove(index);
            break;
        };
        run.release();
    }
};
const Waiter = struct {
    next: ?*Waiter = null,
    mark: *Mark,
    value: c.JSValue,
    resolve: c.JSValue,
    reject: c.JSValue,
    fn destroy(self: *Waiter, engine: *Engine) void {
        engine.freeValue(self.value);
        engine.freeValue(self.resolve);
        engine.freeValue(self.reject);
        engine.gpa.destroy(self);
    }
};
pub const Queue = struct {
    class_id: c.JSClassID = 0,
    marks: std.ArrayList(*Mark) = .empty,
    first: ?*Waiter = null,
    last: ?*Waiter = null,
    fn unlink(self: *Queue, wanted: *Waiter) void {
        var previous: ?*Waiter = null;
        var current = self.first;
        while (current) |slot| {
            if (slot == wanted) {
                if (previous) |prior| prior.next = slot.next else self.first = slot.next;
                if (self.last == slot) self.last = previous;
                slot.next = null;
                return;
            }
            previous = slot;
            current = slot.next;
        }
    }
    pub fn deinit(self: *Queue, engine: *Engine) void {
        while (self.first) |slot| {
            self.unlink(slot);
            slot.mark.waiter = null;
            slot.mark.releaseRun();
            slot.destroy(engine);
        }
        while (self.marks.items.len > 0) self.marks.items[self.marks.items.len - 1].releaseRun();
        self.marks.deinit(engine.gpa);
    }
    fn makeMark(self: *Queue, engine: *Engine) !c.JSValue {
        if (self.class_id == 0) {
            var class_id: c.JSClassID = 0;
            _ = c.JS_NewClassID(engine.runtime, &class_id);
            const definition: c.JSClassDef = .{ .class_name = "NativeTaskAbortMark", .finalizer = finalizeMark };
            if (c.JS_NewClass(engine.runtime, class_id, &definition) < 0) return error.JavaScriptException;
            self.class_id = class_id;
        }
        try self.marks.ensureUnusedCapacity(engine.gpa, 1);
        const mark = try engine.gpa.create(Mark);
        errdefer engine.gpa.destroy(mark);
        const value = try engine.checked(c.JS_NewObjectClass(engine.context, self.class_id));
        mark.* = .{ .engine = engine, .queue = self };
        _ = c.JS_SetOpaque(value, mark);
        return value;
    }
    pub fn pump(self: *Queue, manager: *tasks.Manager) !bool {
        const engine = manager.engine;
        const native = try durable.state(engine, manager.session);
        var worked = false;
        var current = self.first;
        while (current) |slot| {
            const next = slot.next;
            const finished = if (slot.mark.run) |run| run.isFinished() else true;
            if (!finished and native.failure_reason == null) {
                current = next;
                continue;
            }
            // Remove all borrowed list state before invoking a promise callback.
            const result = if (finished) try sdk.text(engine, "marked") else try @import("native_durable_errors.zig").sessionFailed(engine, native.failure_reason.?);
            defer engine.freeValue(result);
            self.unlink(slot);
            slot.mark.waiter = null;
            defer slot.destroy(engine);
            if (finished) try tasks.Manager.deliver(manager);
            var args = [_]c.JSValue{result};
            const returned = try engine.checked(c.JS_Call(engine.context, if (finished) slot.resolve else slot.reject, c.pi_js_undefined(), 1, &args));
            engine.freeValue(returned);
            worked = true;
            current = self.first;
        }
        return worked;
    }
};
fn finalizeMark(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const raw = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return;
    const mark: *Mark = @ptrCast(@alignCast(raw));
    std.debug.assert(mark.waiter == null);
    mark.releaseRun();
    mark.engine.gpa.destroy(mark);
}
pub fn abortTask(manager: *tasks.Manager, id: u64, context: c.JSValue) !c.JSValue {
    return abortTaskWithRestart(manager, id, context, false);
}
fn abortTaskWithRestart(manager: *tasks.Manager, id: u64, context: c.JSValue, keep_restart: bool) !c.JSValue {
    const engine = manager.engine;
    var captures = [_]c.JSValue{ manager.session, c.JS_NewInt64(engine.context, @intCast(id)), context, c.pi_js_bool(engine.context, @intFromBool(keep_restart)), c.pi_js_undefined() };
    const callback = try engine.checked(c.JS_NewCFunctionData(engine.context, queued, 0, 0, captures.len, &captures));
    defer engine.freeValue(callback);
    const pending = try durable.enqueue(engine, manager.session, callback);
    defer engine.freeValue(pending);
    var after_data = [_]c.JSValue{ manager.session, context };
    const after = try engine.checked(c.JS_NewCFunctionData(engine.context, marked, 1, 0, after_data.len, &after_data));
    defer engine.freeValue(after);
    return sdk.invoke(engine, pending, "then", &.{after});
}
/// Source first accepts a read-only job, validates direct ownership, and only
/// then queues the abort mark. A terminal child's read ignores cancellation.
pub fn abortOwnedRead(manager: *tasks.Manager, owner_id: u64, id: u64, context: c.JSValue) !c.JSValue {
    const engine = manager.engine;
    var data = [_]c.JSValue{ manager.session, c.JS_NewInt64(engine.context, @intCast(id)), context, c.JS_NewInt64(engine.context, @intCast(owner_id)) };
    const callback = try engine.checked(c.JS_NewCFunctionData(engine.context, ownedRead, 0, 0, data.len, &data));
    defer engine.freeValue(callback);
    const pending = try durable.enqueueRead(engine, manager.session, callback, context);
    defer engine.freeValue(pending);
    const after = try engine.checked(c.JS_NewCFunctionData(engine.context, afterOwnedRead, 1, 0, data.len, &data));
    defer engine.freeValue(after);
    return sdk.invoke(engine, pending, "then", &.{after});
}
fn ownedRead(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return ownedReadValue(engine, data) catch |err| durable.reject(engine, err);
}
fn ownedReadValue(engine: *Engine, data: [*c]c.JSValue) !c.JSValue {
    const manager = try tasks.getManager(engine, data[0]);
    const id = try durable.number(engine, data[1]);
    const owner = try durable.number(engine, data[3]);
    var record = try manager.lease.value.storage.readTableRecord(engine.gpa, .task, id);
    defer if (record) |*value| value.deinit();
    const owned = if (record) |value| if (json.get(value.value, "owner")) |parent| try json.asInteger(parent) == owner else false else false;
    if (!owned) {
        const message = try std.fmt.allocPrint(engine.gpa, "Task {d} is not owned by task {d}", .{ id, owner });
        defer engine.gpa.free(message);
        try @import("native_durable_errors.zig").throwMessage(engine, message);
        return error.JavaScriptException;
    }
    const terminal = try @import("../durable/task_state.zig").status(record.?.value) == .terminal;
    return c.pi_js_bool(engine.context, @intFromBool(terminal));
}
fn afterOwnedRead(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    if (argc > 0 and c.JS_ToBool(context, argv[0]) != 0) return c.pi_js_bool(context, 1);
    return markOwnedAfterRead(engine, data) catch |err| durable.reject(engine, err);
}
fn markOwnedAfterRead(engine: *Engine, data: [*c]c.JSValue) !c.JSValue {
    const manager = try tasks.getManager(engine, data[0]);
    const pending = try abortTaskWithRestart(manager, try durable.number(engine, data[1]), data[2], true);
    defer engine.freeValue(pending);
    const done = try engine.checked(c.JS_NewCFunction(engine.context, ownedMarked, "owned-task-marked", 0));
    defer engine.freeValue(done);
    return sdk.invoke(engine, pending, "then", &.{done});
}
fn ownedMarked(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_bool(context, 0);
}
fn queued(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return queuedOwned(engine, captures[0..5]) catch |err| durable.reject(engine, err);
}
pub fn retry(engine: *Engine, captures: []const c.JSValue) c.JSValue {
    return queuedOwned(engine, captures) catch |err| durable.reject(engine, err);
}
fn queuedOwned(engine: *Engine, captures: []const c.JSValue) !c.JSValue {
    const manager = try tasks.getManager(engine, captures[0]);
    const native = try durable.state(engine, captures[0]);
    try durable.assertVMHealthy(native);
    try durable.checkCancellation(engine, captures[2]);
    const value = try manager.task_aborts.makeMark(engine);
    errdefer engine.freeValue(value);
    const mark: *Mark = @ptrCast(@alignCast(c.JS_GetOpaque(value, manager.task_aborts.class_id).?));
    const Call = struct {
        manager: *tasks.Manager,
        id: u64,
        keep_restart: bool,
        result: ?scheduling.Scheduler.TaskAbortMark = null,
        fn clock(raw: ?*anyopaque) !i64 {
            const manager_pointer: *tasks.Manager = @ptrCast(@alignCast(raw.?));
            try manager_pointer.updateClock();
            return if (manager_pointer.custom_clock) manager_pointer.clock_value.load(.acquire) else std.Io.Clock.real.now(manager_pointer.lease.value.io).toMilliseconds();
        }
        fn apply(raw: ?*anyopaque, tx: *session.Transaction, _: @import("../durable/types.zig").Context) !json.Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            tx.task_clock = clock;
            tx.task_clock_context = self.manager;
            self.result = try self.manager.scheduler.abortTaskOnLine(tx, self.id, self.keep_restart);
            return .null;
        }
    };
    var call: Call = .{ .manager = manager, .id = try durable.number(engine, captures[1]), .keep_restart = c.JS_ToBool(engine.context, captures[3]) != 0 };
    defer if (call.result) |*result| result.deinit();
    const scope = @import("native_durable_storage.zig").withContext(native, captures[2]);
    defer scope.restore();
    const previous_publication_context = native.publication_context;
    native.publication_context = captures[2];
    defer native.publication_context = previous_publication_context;
    var admitted = (manager.lease.value.tryCommit(Call.apply, &call, .{}, .{}) catch |err| {
        if (err == error.UnknownTask) {
            const message = try std.fmt.allocPrint(engine.gpa, "Task {d} does not exist", .{call.id});
            defer engine.gpa.free(message);
            try @import("native_durable_errors.zig").throwMessage(engine, message);
            return error.JavaScriptException;
        }
        return err;
    }) orelse {
        const pending = try @import("native_durable_storage.zig").deferTaskAbort(engine, captures);
        engine.freeValue(value);
        return pending;
    };
    admitted.deinit();
    mark.terminal = call.result.?.terminal;
    mark.run = call.result.?.run;
    call.result.?.run = null;
    if (mark.run != null) manager.task_aborts.marks.appendAssumeCapacity(mark);
    try tasks.Manager.deliver(manager);
    return value;
}
fn marked(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return markedOwned(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), data) catch |err| durable.reject(engine, err);
}
fn markedOwned(engine: *Engine, value: c.JSValue, data: [*c]c.JSValue) !c.JSValue {
    const manager = try tasks.getManager(engine, data[0]);
    const raw = c.JS_GetOpaque(value, manager.task_aborts.class_id) orelse return error.InvalidTaskAbortMark;
    const mark: *Mark = @ptrCast(@alignCast(raw));
    if (mark.terminal or mark.run == null) return sdk.text(engine, if (mark.terminal) "terminal" else "marked");
    errdefer mark.releaseRun();
    const slot = try engine.gpa.create(Waiter);
    errdefer engine.gpa.destroy(slot);
    var functions: [2]c.JSValue = undefined;
    const pending = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    defer engine.freeValue(pending);
    slot.* = .{ .mark = mark, .value = c.JS_DupValue(engine.context, value), .resolve = functions[0], .reject = functions[1] };
    const queue = &manager.task_aborts;
    if (queue.last) |previous| previous.next = slot else queue.first = slot;
    queue.last = slot;
    mark.waiter = slot;
    errdefer {
        queue.unlink(slot);
        mark.waiter = null;
        engine.freeValue(slot.value);
        for (functions) |function| engine.freeValue(function);
    }
    const observed_promise = try @import("native_durable_context.zig").awaitWithContext(engine, pending, data[1]);
    defer engine.freeValue(observed_promise);
    var cleanup_data = [_]c.JSValue{value};
    const fulfilled = try engine.checked(c.JS_NewCFunctionData(engine.context, observed, 1, 0, cleanup_data.len, &cleanup_data));
    defer engine.freeValue(fulfilled);
    const rejected = try engine.checked(c.JS_NewCFunctionData(engine.context, observed, 1, 1, cleanup_data.len, &cleanup_data));
    defer engine.freeValue(rejected);
    return sdk.invoke(engine, observed_promise, "then", &.{ fulfilled, rejected });
}
fn observed(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, rejected: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const raw = c.JS_GetOpaque(data[0], c.JS_GetClassID(data[0])) orelse return durable.reject(engine, error.InvalidTaskAbortMark);
    const mark: *Mark = @ptrCast(@alignCast(raw));
    if (mark.waiter) |slot| {
        mark.queue.unlink(slot);
        mark.waiter = null;
        slot.destroy(engine);
    }
    mark.releaseRun();
    const value = if (argc > 0) argv[0] else c.pi_js_undefined();
    return if (rejected != 0) c.JS_Throw(context, c.JS_DupValue(context, value)) else c.JS_DupValue(context, value);
}
