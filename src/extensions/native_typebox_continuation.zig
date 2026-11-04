//! Private synchronous heap activations for explicitly planned TypeBox closures.
//! No guest source, AST, promises, jobs, threshold changes, or alternate VM.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
pub const Scope = @import("native_models_stream_scope.zig").Scope;

pub const Plan = struct {
    source_callback: *const fn (*js.Engine, c.JSValue, []const c.JSValue, []const c.JSValue) anyerror!c.JSValue,
    slots: usize,
    entry: usize,
    steps: []const *const fn (*Activation) anyerror!Action,
};
pub const Provenance = struct {
    state: *anyopaque,
    callback: usize,
    class: c.JSClassID,
    roots: []const c.JSValue,
    arrow: bool,
};
const Registration = struct { provenance: Provenance, plan: *const Plan };
const Runtime = struct {
    entries: std.AutoHashMapUnmanaged(usize, Registration) = .empty,
    request: ?*Request = null,
    machine: ?*Machine = null,
    owner_thread: std.Thread.Id,
};
const Request = struct {
    machine: *Machine,
    function: c.JSValue,
    registration: Registration,
    receiver: c.JSValue,
    args: []const c.JSValue,
    consumed: bool = false,
    prepared: ?*Activation = null,
};
pub const Call = struct {
    function: c.JSValue,
    receiver: c.JSValue,
    args: []const c.JSValue,
    result: usize,
    next: usize,
    construct: bool = false,
};
pub const Action = union(enum) {
    next: usize,
    call: Call,
    returned: c.JSValue, // borrowed from the still-live activation Scope
    thrown: c.JSValue, // borrowed; ordinary guest throws preserve identity
    enter_finally: struct { handler: usize, next: usize },
    leave_try: usize,
    finish_finally,
};
const Reason = struct {
    value: c.JSValue,
    fatal: bool, // Cached class from an actual owned pending event.
    terminal_abort: bool = false, // Historical host/private unwind, not a class.
    fn isNative(self: Reason) bool { return c.JS_PiIsExecutionTermination(self.value); }
    fn isFatal(self: Reason, engine: *js.Engine) bool {
        return if (self.isNative())
            c.JS_PiNativePendingPriority(engine.runtime, self.value) > 0
        else self.fatal;
    }
    fn skipsGuest(self: Reason) bool {
        // Cancellation may allow ordinary cleanup to replace the private event,
        // but it cannot resume the already-aborted TypeBox activation.
        return self.terminal_abort or self.fatal or self.isNative();
    }
};
fn rememberProducer(engine: *js.Engine, reason: Reason) void {
    // Only takePending supplies this paired, owned actual event.
    const private = c.JS_PiIsExecutionTermination(reason.value);
    if (private and engine.nativeTerminationObserved()) return;
    if (!private and !reason.isFatal(engine)) return;
    const invocation = engine.native_fatal_invocation orelse return;
    @import("std").debug.assert(invocation.active);
    if (!private) if (invocation.first) |first| {
        if (!c.JS_PiIsExecutionTermination(first) or
            c.JS_PiNativePendingPriority(engine.runtime, first) > 0) return;
    };
    // Retain a proven actual producer before another root can run cleanup.
    // Even a canceled private token records history in every active owner.
    _ = c.JS_PiThrowNativePending(engine.context,
        c.JS_DupValue(engine.context, reason.value), reason.fatal);
    engine.releaseNativeValue(c.pi_js_undefined());
    var duplicate_fatal: bool = false;
    const duplicate = c.JS_PiGetExceptionWithFatal(engine.context, &duplicate_fatal);
    // Retire only the paired duplicate we published. Keep a different
    // normalization winner pending for the caller's existing drain.
    if (duplicate_fatal == reason.fatal and c.JS_IsStrictEqual(engine.context, duplicate, reason.value))
        engine.freeValue(duplicate)
    else
        _ = c.JS_PiThrowNativePending(engine.context, duplicate, duplicate_fatal);
}
const Completion = union(enum) {
    @"resume": usize,
    returned: c.JSValue, // owned, moved before Scope.own
    thrown: Reason, // owned
};
pub const Activation = struct {
    scope: Scope,
    plan: *const Plan,
    values: []c.JSValue,
    roots: []const c.JSValue,
    args: []const c.JSValue,
    receiver: c.JSValue,
    env: c.JSValue,
    pc: usize,
    parent: ?*Activation,
    parent_result: usize,
    logical_suppression: bool,
    // The selected source has one non-nested try/finally. Admission rejects
    // nesting before generation; this is an invariant check, not a JS limit.
    finally_handler: ?usize,
    pending: ?Completion,

    pub fn engine(self: *Activation) *js.Engine { return self.scope.engine; }
};

fn runtime(engine: *js.Engine) !*Runtime {
    if (engine.native_typebox_continuation) |opaque_runtime| {
        const live: *Runtime = @ptrCast(@alignCast(opaque_runtime));
        if (live.owner_thread != std.Thread.getCurrentId()) return error.TypeBoxContinuationForeignThread;
        return live;
    }
    const live = try engine.gpa.create(Runtime);
    live.* = .{ .owner_thread = std.Thread.getCurrentId() };
    engine.native_typebox_continuation = live;
    return live;
}
fn existingRuntime(engine: *js.Engine) ?*Runtime {
    return if (engine.native_typebox_continuation) |ptr| @ptrCast(@alignCast(ptr)) else null;
}
fn identity(value: c.JSValue) ?usize {
    // pi_js_object_identity itself has no tag check.
    if (!c.JS_IsObject(value)) return null;
    return @intFromPtr(c.pi_js_object_identity(value) orelse return null);
}
fn same(left: Provenance, right: Provenance) bool {
    return left.state == right.state and left.callback == right.callback and
        left.class == right.class and left.roots.ptr == right.roots.ptr and
        left.roots.len == right.roots.len and left.arrow == right.arrow;
}
fn lookup(engine: *js.Engine, live: *Runtime, function: c.JSValue) ?Registration {
    _ = engine;
    const key = identity(function) orelse return null;
    const found = live.entries.get(key) orelse return null;
    // Check class before opaque lookup. Neither property access nor a guest
    // equality operation participates in scheduling authority.
    if (c.JS_GetClassID(function) != found.provenance.class) return null;
    if (c.JS_GetOpaque(function, found.provenance.class) != found.provenance.state) return null;
    return found;
}
pub fn register(engine: *js.Engine, function: c.JSValue, provenance: Provenance, plan: *const Plan) !void {
    const live = try runtime(engine);
    if (plan.steps.len == 0 or plan.entry >= plan.steps.len or @intFromPtr(plan.source_callback) != provenance.callback) return error.TypeBoxContinuationDescriptor;
    const key = identity(function) orelse return error.TypeBoxContinuationDescriptor;
    if (c.JS_GetClassID(function) != provenance.class or c.JS_GetOpaque(function, provenance.class) != provenance.state) return error.TypeBoxContinuationDescriptor;
    const entry = try live.entries.getOrPut(engine.gpa, key);
    if (entry.found_existing) return error.TypeBoxContinuationDuplicate;
    entry.value_ptr.* = .{ .provenance = provenance, .plan = plan };
}
/// Called by the actual function finalizer before State storage is released.
/// The map owns no guest values and removal never allocates.
pub fn unregister(engine: *js.Engine, function: c.JSValue, state: *anyopaque) void {
    const live = existingRuntime(engine) orelse return;
    const key = identity(function) orelse return;
    if (live.entries.get(key)) |found| {
        std.debug.assert(found.provenance.state == state);
        _ = live.entries.remove(key);
    }
}
/// Must run AFTER JS_FreeRuntime, including Engine.init's error unwind.
pub fn deinitAfterRuntime(engine: *js.Engine) void {
    const live = existingRuntime(engine) orelse return;
    std.debug.assert(live.request == null and live.machine == null);
    std.debug.assert(live.entries.count() == 0);
    live.entries.deinit(engine.gpa);
    engine.native_typebox_continuation = null;
    engine.gpa.destroy(live);
}

fn prepare(engine: *js.Engine, registration: Registration, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !*Activation {
    // Only native allocations and non-fallible refcount increments before ack.
    // In particular environment creation, defaults and parameter bindings are
    // the first generated Step, after the real VM call has returned.
    const frame = try engine.gpa.create(Activation);
    errdefer engine.gpa.destroy(frame);
    const slots = try engine.gpa.alloc(c.JSValue, registration.plan.slots);
    for (slots) |*slot| slot.* = c.pi_js_undefined();
    frame.scope.engine = engine;
    frame.scope.inline_count = 0;
    frame.scope.values = .empty;
    frame.scope.inline_values[0] = c.JS_DupValue(engine.context, function);
    frame.scope.inline_values[1] = c.JS_DupValue(engine.context, receiver);
    frame.scope.inline_count = 2;
    frame.plan = registration.plan;
    frame.values = slots;
    frame.roots = registration.provenance.roots;
    frame.args = args;
    frame.receiver = if (registration.provenance.arrow) c.pi_js_undefined() else receiver;
    frame.env = c.pi_js_undefined();
    frame.pc = registration.plan.entry;
    frame.parent = null;
    frame.parent_result = 0;
    frame.logical_suppression = false;
    frame.finally_handler = null;
    frame.pending = null;
    return frame;
}
fn completionPayload(completion: Completion) ?c.JSValue {
    return switch (completion) {
        .@"resume" => null,
        .returned => |value| value,
        .thrown => |reason| reason.value,
    };
}
fn releaseValue(engine: *js.Engine, completion: *Completion, value: c.JSValue) void {
    completion.* = mergeCleanup(engine, completion.*, null);
    const generation = engine.native_allocation_generation;
    engine.freeValue(value);
    completion.* = mergeCleanup(engine, completion.*, generation);
}
fn releaseOrdinaryCompletion(engine: *js.Engine, completion: *Completion, retired: Completion) void {
    // A saved Source finally completion is ordinary: terminal outcomes are
    // never installed in Activation.pending by complete().
    if (retired == .thrown) std.debug.assert(!retired.thrown.skipsGuest());
    if (completionPayload(retired)) |value| releaseValue(engine, completion, value);
}
fn destroy(frame: *Activation, completion: *Completion) void {
    const engine = frame.engine();
    if (frame.pending) |pending| {
        frame.pending = null;
        releaseOrdinaryCompletion(engine, completion, pending);
    }
    // Preserve original root order and take an actual event after EACH free.
    // A generation interval belongs only to that release, never a guest step.
    for (frame.scope.inline_values[0..frame.scope.inline_count]) |value|
        releaseValue(engine, completion, value);
    for (frame.scope.values.items) |value|
        releaseValue(engine, completion, value);
    frame.scope.values.deinit(engine.gpa);
    engine.gpa.free(frame.values);
    completion.* = mergeCleanup(engine, completion.*, null);
    if (frame.logical_suppression) {
        std.debug.assert(engine.native_exception_diagnostics_suppressed > 0);
        engine.native_exception_diagnostics_suppressed -= 1;
    }
    engine.gpa.destroy(frame);
    completion.* = mergeCleanup(engine, completion.*, null);
}

/// Return a private ack only for the currently armed exact ordinary call.
/// Null means the existing NativeNode invocation proceeds normally.
pub fn intercept(engine: *js.Engine, function: c.JSValue, provenance: Provenance, target: c.JSValue, args: []const c.JSValue, constructing: bool) !?c.JSValue {
    const live = existingRuntime(engine) orelse return null;
    if (live.owner_thread != std.Thread.getCurrentId()) return error.TypeBoxContinuationForeignThread;
    const request = live.request orelse return null;
    if (request.machine.engine != engine or request.machine.runtime != live or live.machine != request.machine) return error.TypeBoxContinuationProvenance;
    const found = lookup(engine, live, function) orelse return null;
    if (constructing or identity(function) != identity(request.function) or !same(found.provenance, provenance) or
        !same(found.provenance, request.registration.provenance) or found.plan != request.registration.plan or
        !c.JS_IsSameValue(engine.context, target, request.receiver) or
        args.len != request.args.len or (args.len != 0 and args.ptr != request.args.ptr)) return error.TypeBoxContinuationHandshake;
    // Consume before preparation; no allocator/finalizer can consume it twice.
    live.request = null;
    request.consumed = true;
    request.prepared = try prepare(engine, found, function, request.receiver, request.args);
    return c.pi_js_undefined();
}

/// Private invokeBody hook receives the actual callable object, not a name or
/// callback-pointer search. Constructor receiver/result rules stay in Node.
pub fn invokeBody(engine: *js.Engine, function: c.JSValue, provenance: Provenance, receiver: c.JSValue, args: []const c.JSValue) !?c.JSValue {
    const live = existingRuntime(engine) orelse return null;
    if (live.owner_thread != std.Thread.getCurrentId()) return error.TypeBoxContinuationForeignThread;
    const registration = lookup(engine, live, function) orelse return null;
    if (!same(registration.provenance, provenance)) return error.TypeBoxContinuationProvenance;
    var machine: Machine = .{ .engine = engine, .runtime = live, .top = null };
    const previous_machine = live.machine;
    live.machine = &machine;
    defer live.machine = previous_machine;
    machine.top = try prepare(engine, registration, function, receiver, args);
    return machine.run() catch |err| {
        var completion: Completion = .{ .thrown = failureReason(engine, err) };
        while (machine.top) |frame| {
            machine.top = frame.parent;
            destroy(frame, &completion);
        }
        const captured = captureOwned(engine, completion.thrown);
        _ = publishReason(engine, captured);
        return reasonError(captured);
    };
}

fn takePending(engine: *js.Engine, release_generation: ?u64) ?Reason {
    if (!c.JS_HasException(engine.context)) return null;
    var fatal: bool = false;
    const value = c.JS_PiGetExceptionWithFatal(engine.context, &fatal);
    if (!c.JS_PiIsExecutionTermination(value)) if (release_generation) |generation| {
        const tag = c.pi_js_native_allocation_error_generation(value);
        const distance = tag -% generation;
        if (tag != 0 and distance != 0 and distance <= engine.native_allocation_generation -% generation) {
            fatal = true;
            c.JS_SetUncatchableError(engine.context, value);
        }
    };
    const reason: Reason = .{ .value = value, .fatal = fatal,
        .terminal_abort = c.JS_PiIsExecutionTermination(value) };
    rememberProducer(engine, reason);
    return reason;
}
fn retainBeforeCleanup(engine: *js.Engine, retained: Reason, incoming: Reason) bool {
    if (retained.isNative() or incoming.isNative()) {
        return !c.JS_PiNativePendingReplaceClassified(engine.runtime,
            retained.value, retained.fatal, incoming.value, incoming.fatal);
    }
    // Retain this interpreter's original policy: later ordinary cleanup
    // replaces ordinary completion, while the first generic fatal survives.
    return retained.fatal;
}
fn publishReason(engine: *js.Engine, reason: Reason) c.JSValue {
    return c.JS_PiThrowNativePending(engine.context, reason.value, reason.fatal);
}
fn reasonError(reason: Reason) anyerror {
    return if (reason.terminal_abort or reason.isNative())
        error.ExecutionTerminated else error.JavaScriptException;
}
fn mergeCleanup(engine: *js.Engine, initial: Completion, release_generation: ?u64) Completion {
    return mergeWithPolicy(engine, initial, release_generation, false);
}
fn mergeWithPolicy(engine: *js.Engine, initial: Completion, release_generation: ?u64, preserve_ordinary: bool) Completion {
    return mergeWithHistoryPolicy(engine, initial, release_generation, preserve_ordinary, false);
}
fn mergeWithHistoryPolicy(engine: *js.Engine, initial: Completion, release_generation: ?u64, preserve_ordinary: bool, allow_history_only: bool) Completion {
    var completion = initial;
    var generation = release_generation;
    while (true) {
        // The actual outer Node invocation can retain a primitive fatal even
        // after checked() captured its value. Do not repeatedly introduce the
        // same retained fatal while retiring its duplicates.
        const owns_fatal = switch (completion) {
            .thrown => |reason| reason.isFatal(engine),
            else => false,
        };
        if (!owns_fatal) _ = engine.nativeCallbackResult(c.pi_js_undefined());
        const observed_abort = engine.nativeTerminationObserved();
        if (completion == .thrown and observed_abort) completion.thrown.terminal_abort = true;
        var next = takePending(engine, generation);
        if (next == null and observed_abort and completion != .thrown and !allow_history_only) {
            // The actual enclosing owner saw a private unwind before this
            // local take. Never continue a returned Action without its reason.
            _ = c.JS_ThrowInternalError(engine.context, "TypeBox continuation terminated without a pending reason");
            next = takePending(engine, null).?;
        }
        var incoming = next orelse return completion;
        incoming.terminal_abort = incoming.terminal_abort or observed_abort;
        const retained = switch (completion) {
            .thrown => |reason| if (preserve_ordinary)
                !c.JS_PiNativePendingReplaceClassified(engine.runtime,
                    reason.value, reason.fatal, incoming.value, incoming.fatal)
            else retainBeforeCleanup(engine, reason, incoming),
            else => false,
        };
        const history = incoming.terminal_abort or
            (completion == .thrown and completion.thrown.terminal_abort);
        const discarded: ?c.JSValue = if (retained) chosen: {
            completion.thrown.terminal_abort = history;
            break :chosen incoming.value;
        } else replaced: {
            const prior = completionPayload(completion);
            var selected = incoming;
            selected.terminal_abort = history;
            completion = .{ .thrown = selected };
            break :replaced prior;
        };
        generation = null;
        if (discarded) |value| {
            // Selection and historical-abort transfer precede destruction.
            generation = engine.native_allocation_generation;
            engine.freeValue(value);
        }
    }
}
fn failureReason(engine: *js.Engine, err: anyerror) Reason {
    // A non-JS host producer first retires ordinary pending owners. Its
    // internal empty state may carry history without creating a fake reason.
    const defer_host_reason = err != error.JavaScriptException and err != error.ExecutionTerminated;
    var completion = mergeWithHistoryPolicy(engine, .{ .@"resume" = 0 }, null, false, defer_host_reason);
    var history = err == error.ExecutionTerminated or engine.nativeTerminationObserved();
    if (completion == .thrown) history = history or completion.thrown.terminal_abort;
    if (err == error.JavaScriptException or err == error.ExecutionTerminated) {
        if (completion == .thrown) {
            completion.thrown.terminal_abort = completion.thrown.terminal_abort or history;
            return completion.thrown;
        }
    } else {
        // Preserve the original host-failure order: retire ordinary pending
        // values before producing the host error. The first actual fatal wins.
        while (completion == .thrown) {
            const prior = completion.thrown;
            history = history or prior.terminal_abort;
            if (prior.isFatal(engine)) {
                completion.thrown.terminal_abort = history;
                return completion.thrown;
            }
            completion = mergeWithHistoryPolicy(engine, .{ .@"resume" = 0 }, null, false, true);
            const generation = engine.native_allocation_generation;
            engine.freeValue(prior.value);
            completion = mergeWithHistoryPolicy(engine, completion, generation, false, true);
            history = history or engine.nativeTerminationObserved();
        }
    }
    if (err == error.OutOfMemory) {
        // A real typed allocation failure is its own producer, including when
        // Scope.own's retirement previously published an ordinary event.
        _ = engine.throwNativeOutOfMemoryFatal();
    } else if (err == error.JavaScriptException) {
        if (engine.captured_exception) |data| {
            _ = c.JS_PiThrowExceptionData(engine.context, c.JS_DupValue(engine.context, data));
        } else {
            _ = c.JS_ThrowInternalError(engine.context, "TypeBox continuation missing exception");
        }
    } else if (err == error.ExecutionTerminated) {
        // Preserve real host history without manufacturing a private token.
        _ = c.JS_ThrowInternalError(engine.context, "TypeBox continuation terminated without a pending reason");
    } else {
        _ = c.JS_ThrowInternalError(engine.context, "TypeBox continuation: %s", @as([*:0]const u8, @errorName(err)));
    }
    completion = mergeCleanup(engine, completion, null);
    std.debug.assert(completion == .thrown);
    completion.thrown.terminal_abort = completion.thrown.terminal_abort or history;
    return completion.thrown;
}
fn captureThrown(engine: *js.Engine, value: c.JSValue) Reason {
    // Source THROW creates a new ordinary event; a flagged diagnostic is not
    // fatal authority, and forbidden private-token DATA uses the shared guard.
    _ = c.JS_PiThrowExceptionData(engine.context, c.JS_DupValue(engine.context, value));
    return captureOwned(engine, failureReason(engine, error.JavaScriptException));
}
/// Consumes and returns an actual owned reason. The enclosing Node callback
/// suppresses diagnostics, so ordinary capture needs no guest formatting.
/// Retire the old diagnostic roots under this reducer instead of reclassifying
/// a duplicated reason through checked(), which cannot carry host abort history.
fn captureOwned(engine: *js.Engine, initial: Reason) Reason {
    var completion = mergeCleanup(engine, .{ .thrown = initial }, null);
    if (completion.thrown.skipsGuest()) return completion.thrown;
    std.debug.assert(engine.native_exception_diagnostics_suppressed != 0);
    while (engine.captured_exception != null or engine.last_error != null) {
        if (engine.captured_exception) |previous| {
            engine.captured_exception = null;
            // Engine.captureValue retained an earlier ordinary operation while
            // retiring diagnostics. Preserve that narrower policy here.
            completion = mergeWithPolicy(engine, completion, null, true);
            const generation = engine.native_allocation_generation;
            engine.freeValue(previous);
            completion = mergeWithPolicy(engine, completion, generation, true);
        } else if (engine.last_error) |message| {
            engine.last_error = null;
            engine.gpa.free(message);
            completion = mergeWithPolicy(engine, completion, null, true);
        }
    }
    if (!completion.thrown.skipsGuest())
        engine.captured_exception = c.JS_DupValue(engine.context, completion.thrown.value);
    return completion.thrown;
}
/// Called while the real Node invocation is still linked. Preserve actual
/// cached classification; only diagnostic fallback creates ordinary DATA.
pub fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    return publishReason(engine, failureReason(engine, err));
}
pub fn isPlanned(engine: *js.Engine, function: c.JSValue) bool {
    const live = existingRuntime(engine) orelse return false;
    if (live.owner_thread != std.Thread.getCurrentId()) return false;
    return lookup(engine, live, function) != null;
}

const Machine = struct {
    engine: *js.Engine,
    runtime: *Runtime,
    top: ?*Activation,

    fn run(self: *Machine) !c.JSValue {
        while (self.top) |frame| {
            const entry = mergeCleanup(self.engine, .{ .@"resume" = 0 }, null);
            if (entry == .thrown) {
                if (try self.complete(entry)) |returned| return returned;
                continue;
            }
            const action = self.step(frame) catch |err| {
                if (try self.complete(.{ .thrown = failureReason(self.engine, err) })) |returned| return returned;
                continue;
            };
            // A callback may have captured the actual event before returning
            // an Action. Its payload is borrowed from the still-live frame.
            const observed = mergeCleanup(self.engine, .{ .@"resume" = 0 }, null);
            if (observed == .thrown) {
                if (try self.complete(observed)) |returned| return returned;
                continue;
            }
            switch (action) {
                .next => |pc| frame.pc = pc,
                .call => |call_operation| self.call(frame, call_operation) catch |err| {
                    if (try self.complete(.{ .thrown = failureReason(self.engine, err) })) |returned| return returned;
                },
                .returned => |borrowed| {
                    if (try self.complete(.{ .returned = c.JS_DupValue(self.engine.context, borrowed) })) |returned| return returned;
                },
                .thrown => |borrowed| {
                    if (try self.complete(.{ .thrown = captureThrown(self.engine, borrowed) })) |returned| return returned;
                },
                .enter_finally => |entry_finally| {
                    if (frame.finally_handler != null or frame.pending != null) return error.TypeBoxContinuationNestedFinally;
                    frame.finally_handler = entry_finally.handler;
                    frame.pc = entry_finally.next;
                },
                .leave_try => |pc| {
                    if (try self.complete(.{ .@"resume" = pc })) |returned| return returned;
                },
                .finish_finally => {
                    const saved = frame.pending orelse return error.TypeBoxContinuationFinally;
                    frame.pending = null; // move; complete owns the value now
                    if (try self.complete(saved)) |returned| return returned;
                },
            }
        }
        return error.TypeBoxContinuationEmpty;
    }
    noinline fn step(_: *Machine, frame: *Activation) !Action {
        if (frame.pc >= frame.plan.steps.len) return error.TypeBoxContinuationPC;
        return frame.plan.steps[frame.pc](frame);
    }
    fn call(self: *Machine, frame: *Activation, operation: Call) !void {
        if (operation.result >= frame.values.len or operation.next >= frame.plan.steps.len) return error.TypeBoxContinuationOperand;
        const eligible = if (!operation.construct) lookup(self.engine, self.runtime, operation.function) else null;
        var request: Request = undefined;
        const previous = self.runtime.request;
        if (eligible) |registered| {
            request = .{ .machine = self, .function = operation.function, .registration = registered, .receiver = operation.receiver, .args = operation.args };
            self.runtime.request = &request;
        }
        // The existing VM still performs polls and its real dispatch. No guest
        // work takes place between an ack return and the next dispatch step.
        const returned = if (operation.construct)
            c.JS_CallConstructor(self.engine.context, operation.function, @intCast(operation.args.len), @constCast(operation.args.ptr))
        else
            c.JS_Call(self.engine.context, operation.function, operation.receiver, @intCast(operation.args.len), @constCast(operation.args.ptr));
        self.runtime.request = previous; // disarm on EVERY return, incl predispatch failure
        _ = self.engine.nativeCallbackResult(c.pi_js_undefined());
        if (c.JS_IsException(returned) or c.JS_HasException(self.engine.context)) {
            // Own/clear the actual pending reason BEFORE freeing a successful
            // value or an uncommitted child; finalizers cannot replace it.
            const original = takePending(self.engine, null) orelse failureReason(self.engine, error.JavaScriptException);
            var completion: Completion = .{ .thrown = original };
            if (!c.JS_IsException(returned))
                releaseValue(self.engine, &completion, returned);
            if (eligible != null) if (request.prepared) |child| destroy(child, &completion);
            const captured = captureOwned(self.engine, completion.thrown);
            _ = publishReason(self.engine, captured);
            return reasonError(captured);
        }
        if (eligible != null) {
            const child = request.prepared;
            if (!request.consumed or child == null or !c.JS_IsUndefined(returned)) {
                var cleanup: Completion = .{ .@"resume" = 0 };
                releaseValue(self.engine, &cleanup, returned);
                if (child) |prepared| destroy(prepared, &cleanup);
                try self.cleanupFailure(cleanup);
                return error.TypeBoxContinuationHandshake;
            }
            // The acknowledged value is the non-owning undefined immediate.
            self.engine.freeValue(returned);
            if (self.engine.native_exception_diagnostics_suppressed == std.math.maxInt(usize)) {
                var cleanup: Completion = .{ .@"resume" = 0 };
                destroy(child.?, &cleanup);
                try self.cleanupFailure(cleanup);
                return error.TypeBoxContinuationSuppression;
            }
            self.engine.native_exception_diagnostics_suppressed += 1;
            child.?.logical_suppression = true;
            child.?.parent = frame;
            child.?.parent_result = operation.result;
            frame.pc = operation.next;
            self.top = child;
            return;
        }
        frame.pc = operation.next;
        frame.values[operation.result] = try frame.scope.own(returned);
    }
    fn cleanupFailure(self: *Machine, completion: Completion) !void {
        switch (completion) {
            .@"resume" => {},
            .returned => unreachable,
            .thrown => |reason| {
                const captured = captureOwned(self.engine, reason);
                _ = publishReason(self.engine, captured);
                return reasonError(captured);
            },
        }
    }
    /// Consumes completion on every path. Ordinary completion runs the real
    /// Source finally. Actual fatal or historical private abort skips guest
    /// work; native frame teardown always runs in the original root order.
    fn complete(self: *Machine, initial: Completion) !?c.JSValue {
        var completion = initial;
        while (self.top) |frame| {
            if (frame.pending) |previous| {
                frame.pending = null;
                releaseOrdinaryCompletion(self.engine, &completion, previous);
            }
            completion = mergeCleanup(self.engine, completion, null);
            const skips_guest = switch (completion) { .thrown => |reason| reason.skipsGuest(), else => false };
            if (!skips_guest) if (frame.finally_handler) |handler| {
                frame.finally_handler = null;
                frame.pending = completion;
                frame.pc = handler;
                return null;
            };
            if (completion == .@"resume") {
                frame.pc = completion.@"resume";
                return null;
            }
            const parent = frame.parent;
            const result_slot = frame.parent_result;
            self.top = parent;
            destroy(frame, &completion);
            switch (completion) {
                .returned => |owned| {
                    if (parent) |caller| {
                        // Scope.own consumes even on append failure. Clear the
                        // completion BEFORE calling it; failure cannot retry/free.
                        completion = .{ .@"resume" = 0 };
                        caller.values[result_slot] = caller.scope.own(owned) catch |err| {
                            completion = .{ .thrown = failureReason(self.engine, err) };
                            continue;
                        };
                        return null;
                    }
                    return owned;
                },
                .thrown => |reason| {
                    if (parent == null) {
                        _ = publishReason(self.engine, reason);
                        return reasonError(reason);
                    }
                },
                .@"resume" => unreachable,
            }
        }
        // A malformed completion must not discard an already-owned event.
        if (completion == .thrown) {
            const captured = captureOwned(self.engine, completion.thrown);
            _ = publishReason(self.engine, captured);
            return reasonError(captured);
        }
        var cleanup: Completion = .{ .@"resume" = 0 };
        if (completionPayload(completion)) |value| releaseValue(self.engine, &cleanup, value);
        try self.cleanupFailure(cleanup);
        return error.TypeBoxContinuationEmpty;
    }
};
