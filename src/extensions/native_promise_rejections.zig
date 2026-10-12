//! Owner-thread promise bookkeeping. The tracker calls observe only: no JS
//! invocation, getter, coercion or diagnostic. Dispatch occurs at a complete
//! checkpoint, before the next timer/input turn, using original raw values.
const std = @import("std");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const scopes = @import("native_async_scope.zig");

pub const Rejection = struct {
    promise: c.JSValue,
    reason: c.JSValue,
    scope: c.JSValue,
    uid: f64,
    pub fn deinit(self: Rejection, context: *c.JSContext) void {
        c.JS_FreeValue(context, self.promise);
        c.JS_FreeValue(context, self.reason);
        c.JS_FreeValue(context, self.scope);
    }
};
pub const Handled = struct {
    promise: c.JSValue,
    uid: f64,
    pub fn deinit(self: Handled, context: *c.JSContext) void {
        c.JS_FreeValue(context, self.promise);
    }
};
const Entry = struct { value: Rejection, ready: bool = false };
pub const Queue = struct {
    engine: *engine_mod.Engine,
    gpa: std.mem.Allocator,
    entries: std.ArrayList(Entry) = .empty,
    handled: std.ArrayList(c.JSValue) = .empty,
    // Genuine private ephemeron storage. Already reported promises must not be
    // kept alive by host bookkeeping. Only their uid is needed for late handling.
    reported: c.JSValue,
    weak_get: c.JSValue,
    weak_set: c.JSValue,
    weak_delete: c.JSValue,
    last_uid: f64 = 0,
    allocation_failed: bool = false,

    pub fn init(engine: *engine_mod.Engine, gpa: std.mem.Allocator) !Queue {
        const context = engine.context;
        const global = c.JS_GetGlobalObject(context);
        defer engine.freeValue(global);
        const constructor = try engine.checked(c.JS_GetPropertyStr(context, global, "WeakMap"));
        defer engine.freeValue(constructor);
        const prototype = try engine.checked(c.JS_GetPropertyStr(context, constructor, "prototype"));
        defer engine.freeValue(prototype);
        const get = try engine.checked(c.JS_GetPropertyStr(context, prototype, "get"));
        errdefer engine.freeValue(get);
        const set = try engine.checked(c.JS_GetPropertyStr(context, prototype, "set"));
        errdefer engine.freeValue(set);
        const delete = try engine.checked(c.JS_GetPropertyStr(context, prototype, "delete"));
        errdefer engine.freeValue(delete);
        const reported = try engine.checked(c.JS_CallConstructor(context, constructor, 0, null));
        return .{ .engine = engine, .gpa = gpa, .reported = reported, .weak_get = get, .weak_set = set, .weak_delete = delete };
    }
    pub fn deinit(self: *Queue) void {
        const engine = self.engine;
        for (self.entries.items) |entry| entry.value.deinit(engine.context);
        for (self.handled.items) |promise| engine.freeValue(promise);
        self.entries.deinit(self.gpa);
        self.handled.deinit(self.gpa);
        engine.freeValue(self.reported);
        engine.freeValue(self.weak_get);
        engine.freeValue(self.weak_set);
        engine.freeValue(self.weak_delete);
    }
    /// C rejection callback entry. The complete checkpoint snapshot is fixed:
    /// catching a queued sibling from a prior rejection's listener does not
    /// cancel its scheduled report and does not invent rejectionHandled.
    pub fn observe(self: *Queue, promise: c.JSValue, reason: c.JSValue, is_handled: bool) void {
        const engine = self.engine;
        for (self.entries.items, 0..) |entry, index| {
            if (!c.JS_IsStrictEqual(engine.context, entry.value.promise, promise)) continue;
            if (is_handled and !entry.ready) {
                const removed = self.entries.orderedRemove(index);
                removed.value.deinit(engine.context);
            }
            return;
        }
        if (is_handled) {
            self.handled.ensureUnusedCapacity(self.gpa, 1) catch {
                self.allocation_failed = true;
                return;
            };
            self.handled.appendAssumeCapacity(c.JS_DupValue(engine.context, promise));
            return;
        }
        self.entries.ensureUnusedCapacity(self.gpa, 1) catch {
            self.allocation_failed = true;
            return;
        };
        self.last_uid += 1;
        self.entries.appendAssumeCapacity(.{ .value = .{
            .promise = c.JS_DupValue(engine.context, promise),
            .reason = c.JS_DupValue(engine.context, reason),
            .scope = scopes.capture(engine),
            .uid = self.last_uid,
        } });
    }
    /// Called only after JS jobs and nextTicks fully drain, outside an active
    /// native invocation. A partial runReadyJobs batch is never a checkpoint.
    pub fn checkpoint(self: *Queue) void {
        for (self.entries.items) |*entry| entry.ready = true;
    }
    /// Transfers raw roots to the dispatcher. It must call noteReported before
    /// invoking guest process.emit, then restore the captured execution scope.
    pub fn take(self: *Queue) !?Rejection {
        if (self.allocation_failed) return error.OutOfMemory;
        for (self.entries.items, 0..) |entry, index| {
            if (entry.ready) return self.entries.orderedRemove(index).value;
        }
        return null;
    }
    /// No guest operation: captured genuine WeakMap intrinsic, private genuine
    /// receiver, genuine Promise key and numeric value. Never used by observe.
    pub fn noteReported(self: *Queue, rejection: Rejection) !void {
        var args = [_]c.JSValue{ rejection.promise, c.JS_NewFloat64(self.engine.context, rejection.uid) };
        const result = try self.engine.checked(c.JS_Call(self.engine.context, self.weak_set, self.reported, args.len, &args));
        self.engine.freeValue(result);
    }
    /// Dispatch these before the next pending-unhandled snapshot, after queued
    /// promise reactions have run. Caller performs dynamic process.emit and
    /// original Node warning fallback; the tracker never invokes either.
    pub fn takeHandled(self: *Queue) !?Handled {
        if (self.allocation_failed) return error.OutOfMemory;
        while (self.handled.items.len != 0) {
            const promise = self.handled.orderedRemove(0);
            errdefer self.engine.freeValue(promise);
            var args = [_]c.JSValue{promise};
            const uid_value = try self.engine.checked(c.JS_Call(self.engine.context, self.weak_get, self.reported, args.len, &args));
            defer self.engine.freeValue(uid_value);
            if (c.JS_IsUndefined(uid_value)) {
                self.engine.freeValue(promise);
                continue;
            }
            var uid: f64 = undefined;
            if (c.JS_ToFloat64(self.engine.context, &uid, uid_value) < 0) return error.JavaScriptException;
            const deleted = try self.engine.checked(c.JS_Call(self.engine.context, self.weak_delete, self.reported, args.len, &args));
            self.engine.freeValue(deleted);
            return .{ .promise = promise, .uid = uid };
        }
        return null;
    }
};
