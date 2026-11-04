// Copyright 2018 the V8 project authors. BSD; retained V8-LICENSE.
//! The selected Node24.13 explicit microtask checkpoint on the actual C job queue.
//! Completion callbacks are native function/data pairs. The real message-report
//! operation is required from the embedding; it is never process.emit or guest
//! code substituted for the VM's ordinary failed-microtask reporting operation.
const std = @import("std");
const em = @import("engine.zig");
const ChargedAllocator = @import("native_env_charged_allocator.zig").ChargedAllocator;
const c = em.c;

pub const Callback = struct {
    run: *const fn (*em.Engine, ?*anyopaque) void,
    data: ?*anyopaque,
    fn eql(self: Callback, other: Callback) bool {
        return self.run == other.run and self.data == other.data;
    }
};
pub const Operations = struct {
    /// The genuine Runtime_ReportMessageFromMicrotask/MessageHandler operation.
    /// Entry has an ordinary actual pending reason on this runtime. It reports
    /// and clears that reason, preserving a newly selected native abrupt event.
    /// The failed job's continuation remains current until the checkpoint ends.
    report_message_from_microtask: *const fn (*em.Engine, ?*c.JSContext) anyerror!void,
};

pub const Queue = struct {
    memory_owner: *anyopaque,
    charged: ChargedAllocator,
    owner_thread: std.Thread.Id,
    engine: ?*em.Engine,
    operations: Operations,
    callbacks: std.ArrayList(Callback) = .empty,
    callbacks_cow: ?std.ArrayList(Callback) = null,
    running: bool = false,
    running_completed: bool = false,
    scope_depth: usize = 0,
    suppressions: usize = 0,

    /// The bootstrap creates exactly one selected explicit queue for its actual
    /// Engine/runtime, then closes it before that VM is destroyed. Callback data
    /// is borrowed native storage; registering a callback does not own a JS root.
    pub fn create(engine: *em.Engine, operations: Operations) !*Queue {
        const memory_owner = engine.native_memory_owner;
        c.pi_js_retain_memory_owner(memory_owner);
        errdefer c.pi_js_release_memory_owner(memory_owner);
        if (c.pi_js_native_memory_reserve(memory_owner, @sizeOf(Queue)) == 0)
            return error.OutOfMemory;
        errdefer c.pi_js_native_memory_release(memory_owner, @sizeOf(Queue));
        const self = try std.heap.c_allocator.create(Queue);
        self.* = .{
            .memory_owner = memory_owner,
            .charged = ChargedAllocator.init(engine),
            .owner_thread = std.Thread.getCurrentId(),
            .engine = engine,
            .operations = operations,
        };
        return self;
    }
    fn assertOwner(self: *const Queue) void {
        std.debug.assert(self.owner_thread == std.Thread.getCurrentId());
    }
    fn requireEngine(self: *Queue) !*em.Engine {
        self.assertOwner();
        return self.engine orelse error.NativeMicrotaskQueueClosed;
    }
    pub fn shouldPerformCheckpoint(self: *const Queue) bool {
        self.assertOwner();
        return self.engine != null and !self.running and
            self.scope_depth == 0 and self.suppressions == 0;
    }
    /// These are the actual native scope/suppression counters. The selected
    /// Node policy is explicit: decrementing a scope does not run a checkpoint.
    pub fn enterScope(self: *Queue) !void {
        _ = try self.requireEngine();
        self.scope_depth += 1;
    }
    pub fn leaveScope(self: *Queue) void {
        self.assertOwner();
        std.debug.assert(self.scope_depth != 0);
        self.scope_depth -= 1;
    }
    pub fn suppress(self: *Queue) !void {
        _ = try self.requireEngine();
        self.suppressions += 1;
    }
    pub fn unsuppress(self: *Queue) void {
        self.assertOwner();
        std.debug.assert(self.suppressions != 0);
        self.suppressions -= 1;
    }
    fn mutableCallbacks(self: *Queue) !*std.ArrayList(Callback) {
        _ = try self.requireEngine();
        if (!self.running_completed) return &self.callbacks;
        // Source creates the COW vector BEFORE duplicate/member lookup, even
        // for adding an existing pair or removing an absent one.
        if (self.callbacks_cow == null) {
            var next: std.ArrayList(Callback) = .empty;
            errdefer next.deinit(self.charged.allocator());
            try next.appendSlice(self.charged.allocator(), self.callbacks.items);
            self.callbacks_cow = next;
        }
        return &self.callbacks_cow.?;
    }
    pub fn addCompletedCallback(self: *Queue, callback: Callback) !void {
        const values = try self.mutableCallbacks();
        for (values.items) |existing| if (existing.eql(callback)) return;
        try values.append(self.charged.allocator(), callback);
    }
    pub fn removeCompletedCallback(self: *Queue, callback: Callback) !void {
        const values = try self.mutableCallbacks();
        for (values.items, 0..) |existing, index| {
            if (!existing.eql(callback)) continue;
            _ = values.orderedRemove(index);
            return;
        }
    }
    fn onCompleted(self: *Queue, engine: *em.Engine) void {
        std.debug.assert(self.running and !self.running_completed);
        self.running_completed = true;
        // Every pair in the ORIGINAL vector runs. Mutations affect the next
        // checkpoint. Keep the actual selected exception published throughout;
        // no Completion/Boundary escrow may surround this native iteration.
        for (self.callbacks.items) |callback| callback.run(engine, callback.data);
        self.running_completed = false;
        if (self.callbacks_cow) |replacement| {
            self.callbacks.deinit(self.charged.allocator());
            self.callbacks = replacement;
            self.callbacks_cow = null;
        }
    }
    fn acknowledgeCancelledUnwind(engine: *em.Engine, entry_observed: bool) void {
        // Only the genuine stopped TryRunMicrotasks boundary acknowledges a
        // cancelled native unwind. An active published event must stay visible.
        if (c.JS_PiIsExecutionTerminating(engine.runtime) or
            !c.JS_HasException(engine.context)) return;
        var generic_fatal: bool = false;
        const reason = c.JS_PiGetExceptionWithFatal(engine.context, &generic_fatal);
        if (c.JS_PiIsExecutionTermination(reason)) {
            engine.acknowledgeCancelledMicrotaskUnwind(reason, entry_observed);
        } else {
            // A later ordinary/generic event is an actual surviving owner.
            // Republish immediately, with no allocation or callback in between.
            _ = c.JS_PiThrowNativePending(engine.context, reason, generic_fatal);
        }
    }
    fn runMicrotasks(self: *Queue, engine: *em.Engine) !isize {
        std.debug.assert(!self.running);
        self.running = true;
        defer self.running = false;
        self.suppressions += 1;
        defer self.suppressions -= 1;
        if (!c.JS_IsJobPending(engine.runtime)) {
            // Empty checkpoints still invoke completed callbacks and leave the
            // actual outer continuation untouched.
            self.onCompleted(engine);
            return 0;
        }
        // Only a real canceled job may restore this entry history. Older
        // outer unwind remains; later cleanup/completion events record anew.
        const entry_observed = engine.nativeTerminationObserved();
        const outer = c.JS_PiGetContinuationPreservedEmbedderData(engine.runtime);
        c.JS_PiSetContinuationPreservedEmbedderData(engine.runtime, c.pi_js_undefined());
        var processed: isize = 0;
        var failed: ?anyerror = null;
        var native_unwind = false;
        while (c.JS_IsJobPending(engine.runtime)) {
            var context: ?*c.JSContext = null;
            const status = c.JS_ExecutePendingJob(engine.runtime, &context);
            if (status == c.JS_PI_JOB_TERMINATED) {
                native_unwind = true;
                break;
            }
            if (status == 0) break;
            if (status < 0) {
                const active_context = context orelse engine.context;
                if (!c.JS_HasException(active_context)) {
                    failed = error.MissingActualMicrotaskException;
                    break;
                }
                // Inspect the PROVEN actual pending event, then immediately
                // republish the same owner into the empty runtime slot. There
                // is no allocation, free, guest entry or callback between.
                var fatal: bool = false;
                const reason = c.JS_PiGetExceptionWithFatal(active_context, &fatal);
                const private = c.JS_PiIsExecutionTermination(reason);
                _ = c.JS_PiThrowNativePending(active_context, reason, fatal);
                if (private) {
                    native_unwind = true;
                    break;
                }
                if (fatal) {
                    // Preserve the observed generic classification in the
                    // genuine enclosing native invocation before callbacks.
                    _ = engine.nativeCallbackResult(c.pi_js_exception());
                    break;
                }
                processed += 1;
                self.operations.report_message_from_microtask(engine, active_context) catch |err| {
                    if (err == error.OutOfMemory) _ = engine.throwNativeOutOfMemoryFatal();
                    failed = err;
                    break;
                };
                if (c.JS_PiIsExecutionTerminating(engine.runtime)) {
                    native_unwind = true;
                    break;
                }
                if (c.JS_HasException(active_context)) {
                    failed = error.ActualMicrotaskReportLeftPending;
                    break;
                }
                continue;
            }
            std.debug.assert(status == 1);
            processed += 1;
        }
        if (native_unwind) acknowledgeCancelledUnwind(engine, entry_observed);
        // Source restores the caller's continuation BEFORE queue termination
        // cleanup, deferred native Promise AFTER, or completion callbacks.
        c.JS_PiSetContinuationPreservedEmbedderData(engine.runtime, outer);
        c.JS_FreeValueRT(engine.runtime, outer);
        var terminated = false;
        if (native_unwind or c.JS_PiIsExecutionTerminating(engine.runtime)) {
            terminated = c.JS_PiFinishTerminatedMicrotasks(engine.runtime) == 1;
            // Finish0 after a real Cancel retires only held aborted-job owners.
            // It neither clears the live queue nor invents a deferred AFTER.
        }
        if (native_unwind or terminated) acknowledgeCancelledUnwind(engine, entry_observed);
        self.onCompleted(engine);
        if (failed) |err| return err;
        return if (terminated) -1 else processed;
    }
    fn performBody(self: *Queue, engine: *em.Engine) !void {
        const outcome = self.runMicrotasks(engine);
        // PerformCheckpointInternal clears kept objects after RunMicrotasks,
        // including its termination branch and callbacks. Preserve the actual
        // runtime event through this native retirement as well.
        c.JS_ClearKeptObjects(engine.runtime);
        _ = try outcome;
        if (c.JS_PiIsExecutionTerminating(engine.runtime))
            return error.ExecutionTerminated;
        if (c.JS_HasException(engine.context))
            return error.JavaScriptException;
    }
    pub fn performCheckpoint(self: *Queue) !void {
        const engine = try self.requireEngine();
        if (!self.shouldPerformCheckpoint()) return;
        var invocation: em.Engine.NativeInvocation = .{};
        engine.enterNativeInvocation(&invocation);
        const outcome: anyerror!void = self.performBody(engine);
        // Native callbacks and kept-object cleanup are complete. Reduce only
        // actual owners here: an empty successful checkpoint must not poll a
        // request-only termination through a fresh generic entry boundary.
        const result = engine.leaveNativeInvocation(&invocation, c.pi_js_undefined());
        if (invocation.terminated) return error.ExecutionTerminated;
        if (c.JS_IsException(result)) {
            // The last stable owner is gone. Leave the actual value/class pair
            // published; checked() would convert a primitive fatal into DATA.
            if (outcome) |_| {} else |err| {
                if (err == error.ExecutionTerminated or err == error.OutOfMemory)
                    return err;
            }
            return error.JavaScriptException;
        }
        engine.freeValue(result);
        try outcome;
    }
    pub fn close(self: *Queue) !void {
        self.assertOwner();
        if (self.engine == null) return;
        if (self.running or self.running_completed or self.scope_depth != 0 or self.suppressions != 0)
            return error.NativeMicrotaskQueueHasLiveScope;
        std.debug.assert(self.callbacks_cow == null);
        self.engine = null;
        self.callbacks.deinit(self.charged.allocator());
        self.callbacks = .empty;
    }
    pub fn destroy(self: *Queue) void {
        self.assertOwner();
        std.debug.assert(self.engine == null and !self.running and
            !self.running_completed and self.callbacks_cow == null and
            self.callbacks.items.len == 0 and self.scope_depth == 0 and
            self.suppressions == 0);
        const memory_owner = self.memory_owner;
        self.charged.deinit();
        std.heap.c_allocator.destroy(self);
        c.pi_js_native_memory_release(memory_owner, @sizeOf(Queue));
        c.pi_js_release_memory_owner(memory_owner);
    }
};


test "native microtask checkpoint final pop preserves actual primitive fatal policy" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const Observer = struct {
        calls: usize = 0,
        observed_pending: bool = false,
        observed_uncatchable: bool = false,
        fn report(_: *em.Engine, _: ?*c.JSContext) anyerror!void {
            return error.UnexpectedEmptyCheckpointReport;
        }
        fn completed(host: *em.Engine, raw: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            self.observed_pending = c.JS_HasException(host.context);
            self.observed_uncatchable = c.JS_PiIsPendingUncatchable(host.context);
        }
    };
    const queue = try Queue.create(engine, .{ .report_message_from_microtask = Observer.report });
    defer queue.destroy();
    defer queue.close() catch unreachable;
    var observer: Observer = .{};
    try queue.addCompletedCallback(.{ .run = Observer.completed, .data = &observer });
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));

    c.JS_SetMemoryLimit(engine.runtime, 1);
    const allocation_result = c.JS_NewObject(engine.context);
    c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
    defer engine.freeValue(allocation_result);
    try std.testing.expect(c.JS_IsException(allocation_result));
    try std.testing.expectError(error.JavaScriptException, queue.performCheckpoint());
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 1), observer.calls);
    try std.testing.expect(observer.observed_pending and observer.observed_uncatchable);
    try std.testing.expect(c.JS_HasException(engine.context));
    var generic_fatal: bool = false;
    const fatal = c.JS_PiGetExceptionWithFatal(engine.context, &generic_fatal);
    defer engine.freeValue(fatal);
    try std.testing.expect(generic_fatal and c.JS_IsNull(fatal));
    try std.testing.expect(!c.JS_IsUncatchableError(fatal));

    // Identical primitive DATA with ordinary source provenance stays ordinary.
    // Empty checkpoints still invoke their native completed callback vector.
    observer = .{};
    _ = c.JS_PiThrowExceptionData(engine.context, c.pi_js_null());
    try std.testing.expectError(error.JavaScriptException, queue.performCheckpoint());
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 1), observer.calls);
    try std.testing.expect(observer.observed_pending and !observer.observed_uncatchable);
    try std.testing.expect(c.JS_HasException(engine.context));
    generic_fatal = true;
    const ordinary = c.JS_PiGetExceptionWithFatal(engine.context, &generic_fatal);
    defer engine.freeValue(ordinary);
    try std.testing.expect(!generic_fatal and c.JS_IsNull(ordinary));
}

test "native microtask canceled job acknowledgement preserves earlier owner history" {
    const Owner = @import("native_pending_owner.zig");
    const Helpers = struct {
        fn report(_: *em.Engine, _: ?*c.JSContext) anyerror!void {
            return error.UnexpectedCancelledJobReport;
        }
        fn cancelledJob(context: ?*c.JSContext, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
            const host = em.Engine.fromContext(context.?);
            c.JS_PiRequestExecutionTermination(host.runtime);
            if (c.JS_PiCheckExecutionTermination(host.context) >= 0)
                return c.JS_ThrowInternalError(host.context, "Missing actual private job event");
            _ = host.nativeCallbackResult(c.pi_js_exception());
            var generic_fatal: bool = false;
            const reason = c.JS_PiGetExceptionWithFatal(host.context, &generic_fatal);
            if (!c.JS_PiIsExecutionTermination(reason) or generic_fatal) {
                host.releaseNativeValue(reason);
                return c.JS_ThrowInternalError(host.context, "Invalid actual private job event");
            }
            // Cancel the same published event while retaining its genuine
            // owned token for the stopped-job acknowledgement boundary.
            _ = c.JS_PiThrowNativePending(host.context, c.JS_DupValue(host.context, reason), false);
            c.JS_PiCancelExecutionTermination(host.runtime);
            return c.JS_PiThrowNativePending(host.context, reason, false);
        }
    };
    for ([_]bool{ false, true }) |prior_history| {
        const engine = try em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        const queue = try Queue.create(engine, .{ .report_message_from_microtask = Helpers.report });
        defer {
            queue.close() catch unreachable;
            queue.destroy();
        }
        var outer = Owner.Frame.init(engine);
        try outer.enter();
        defer if (outer.invocation.active) { _ = outer.finishCallback(c.pi_js_undefined()); };
        if (prior_history) {
            c.JS_PiRequestExecutionTermination(engine.runtime);
            try std.testing.expect(c.JS_PiCheckExecutionTermination(engine.context) < 0);
            _ = engine.nativeCallbackResult(c.pi_js_exception());
            c.JS_PiCancelExecutionTermination(engine.runtime);
            try std.testing.expect(engine.nativeTerminationObserved());
            try std.testing.expect(!c.JS_HasException(engine.context));
        }
        try std.testing.expectEqual(@as(c_int, 0), c.JS_EnqueueJob(engine.context, Helpers.cancelledJob, 0, null));
        const outcome = queue.performCheckpoint();
        try std.testing.expectEqual(prior_history, engine.nativeTerminationObserved());
        try std.testing.expect(!c.JS_HasException(engine.context));
        try std.testing.expect(!c.JS_PiIsExecutionTerminating(engine.runtime));
        const completed = outer.finishVoid(outcome);
        if (prior_history) try std.testing.expectError(error.ExecutionTerminated, completed)
        else try completed;
        try std.testing.expect(engine.native_fatal_invocation == null);
        try std.testing.expect(!engine.nativeTerminationObserved());
    }
}
