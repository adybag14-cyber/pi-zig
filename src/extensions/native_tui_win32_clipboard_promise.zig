//! Private owner-thread clipboard queue. Public timers cannot reach this lane.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const Worker = @import("native_tui_win32_clipboard_worker.zig").Worker;
const Scope = @import("native_node_operation_scope.zig").Scope;
const async_scope = @import("native_async_scope.zig");
const vm_value = @import("native_tui_win32_value.zig");
const private_owner = "#pi-native-tui-win32-clipboard-owner";
pub const maximum_active_workers: usize = 4;
const Node = struct {
    next: ?*Node = null,
    task: *Worker,
    resolve: c.JSValue,
    reject: c.JSValue,
    scope: c.JSValue,
};
const Owner = struct {
    engine: *js.Engine,
    first: ?*Node = null,
    last: ?*Node = null,
    active: usize = 0,
    pumping: bool = false,
    closing: bool = false,
    delivering: bool = false,
    failed: bool = false,
};
fn allocationFailure(engine: *js.Engine) anyerror {
    // A real host/budget failure publishes its event while all current roots
    // and the owning invocation are still live, before any deferred cleanup.
    _ = engine.throwNativeOutOfMemoryFatal();
    return error.OutOfMemory;
}
fn ownerObjectBody(stage: *Scope, id: c.JSClassID) !c.JSValue {
    const generation = try stage.beforeAllocation();
    return c.JS_DupValue(stage.engine.context,
        try stage.checkedAllocation(c.JS_NewObjectClass(stage.engine.context, @intCast(id)), generation));
}
fn ownerObject(engine: *js.Engine, id: c.JSClassID) !c.JSValue {
    var stage = Scope.init(engine);
    return stage.finish(ownerObjectBody(&stage, id));
}
fn capabilityBody(stage: *Scope, functions: *[2]c.JSValue) !c.JSValue {
    // Promise initialization can call guest hooks. Its actual invocation
    // boundary preserves native producers; no allocation tag/counter span may
    // classify a reason returned through that hook.
    try stage.pending();
    return c.JS_DupValue(stage.engine.context,
        try stage.checked(c.JS_NewPromiseCapability(stage.engine.context, functions)));
}
fn capability(engine: *js.Engine, functions: *[2]c.JSValue) !c.JSValue {
    var stage = Scope.init(engine);
    return stage.finish(capabilityBody(&stage, functions));
}
fn ownerValue(value: c.JSValue) *Owner {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
}
fn existing(engine: *js.Engine) ?*Owner {
    return if (engine.native_module_values.get(private_owner)) |value| ownerValue(value) else null;
}
fn releaseNode(runtime: ?*c.JSRuntime, owner: *Owner, node: *Node) void {
    // C destroy joins its private handle before any copied job bytes retire.
    node.task.deinit();
    c.JS_FreeValueRT(runtime, node.resolve);
    c.JS_FreeValueRT(runtime, node.reject);
    c.JS_FreeValueRT(runtime, node.scope);
    owner.engine.gpa.destroy(node);
    c.pi_js_native_memory_release(owner.engine.native_memory_owner, @sizeOf(Node));
}
fn retire(runtime: ?*c.JSRuntime, owner: *Owner) void {
    owner.closing = true;
    const first = owner.first;
    owner.first = null;
    owner.last = null;
    owner.active = 0;
    var cursor = first;
    while (cursor) |node| {
        cursor = node.next;
        releaseNode(runtime, owner, node);
    }
}
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const owner: *Owner = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    retire(runtime, owner);
    const engine = owner.engine;
    engine.gpa.destroy(owner);
    c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Owner));
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const owner: *Owner = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    var cursor = owner.first;
    while (cursor) |node| {
        c.JS_MarkValue(runtime, node.resolve, marker);
        c.JS_MarkValue(runtime, node.reject, marker);
        c.JS_MarkValue(runtime, node.scope, marker);
        cursor = node.next;
    }
}
fn getOwner(engine: *js.Engine) !*Owner {
    if (existing(engine)) |owner| {
        if (owner.failed) return error.NativeClipboardCompletionFailed;
        if (owner.closing) return error.NativeClipboardOwnerRetired;
        return owner;
    }
    if (engine.native_io == null) return error.NativeClipboardQueueUnavailable;
    if (engine.native_tui_platform_pump != null or engine.native_tui_platform_pending != null or engine.native_tui_platform_deinit != null)
        return error.NativeClipboardOwnerAlreadyInstalled;
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(Owner)) == 0) return allocationFailure(engine);
    var attached = false;
    errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Owner));
    const owner = engine.gpa.create(Owner) catch |err| return if (err == error.OutOfMemory) allocationFailure(engine) else err;
    errdefer if (!attached) engine.gpa.destroy(owner);
    var id: c.JSClassID = 0;
    if (c.JS_NewClassID(engine.runtime, &id) == 0) return allocationFailure(engine);
    const definition: c.JSClassDef = .{
        .class_name = "Native Win32 clipboard queue",
        .finalizer = finalize,
        .gc_mark = mark,
    };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return allocationFailure(engine);
    const object = try ownerObject(engine, id);
    errdefer engine.freeValue(object);
    owner.* = .{ .engine = engine };
    if (c.JS_SetOpaque(object, owner) < 0) return error.InvalidNativeClipboardOwner;
    attached = true;
    engine.native_module_values.put(engine.gpa, private_owner, object) catch |err|
        return if (err == error.OutOfMemory) allocationFailure(engine) else err;
    engine.native_tui_platform_pump = pump;
    engine.native_tui_platform_pending = hasPending;
    engine.native_tui_platform_deinit = cleanup;
    return owner;
}
pub fn hasFailed(engine: *js.Engine) bool {
    return if (existing(engine)) |owner| owner.failed else false;
}
pub fn hasPending(engine: *js.Engine) bool {
    const owner = existing(engine) orelse return false;
    // A failed delivery remains visible to every actual owner loop until the
    // engine retires. Idle completion must not return success on an empty queue.
    return owner.failed or (!owner.closing and owner.first != null);
}
fn cleanup(engine: *js.Engine) void {
    if (existing(engine)) |owner| retire(engine.runtime, owner);
    engine.native_tui_platform_pump = null;
    engine.native_tui_platform_pending = null;
    engine.native_tui_platform_deinit = null;
}
pub fn errorValue(engine: *js.Engine, message: [*:0]const u8) !c.JSValue {
    var stage = Scope.init(engine);
    return stage.finish(errorBody(&stage, message));
}
fn errorBody(stage: *Scope, message: [*:0]const u8) !c.JSValue {
    // Error creation invokes the runtime's guest stack hooks, which can also
    // mutate the Error. Neither this call nor its subsequent definition is a
    // non-guest allocation span. Only the literal text constructor below is.
    try stage.pending();
    const result = try stage.checked(c.JS_NewError(stage.engine.context));
    const text = try vm_value.text(stage, std.mem.span(message));
    try stage.define(result, "message", text, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE);
    return c.JS_DupValue(stage.engine.context, result);
}
pub fn throwMessage(engine: *js.Engine, message: [*:0]const u8) anyerror {
    const reason = errorValue(engine, message) catch |err| return err;
    _ = engine.checked(c.JS_Throw(engine.context, reason)) catch |err| return err;
    unreachable;
}
fn remove(owner: *Owner, previous: ?*Node, node: *Node) void {
    if (previous) |before| before.next = node.next else owner.first = node.next;
    if (owner.last == node) owner.last = previous;
    node.next = null;
}
fn settle(stage: *Scope, owner: *Owner, node: *Node, queue_failure: bool) !c.JSValue {
    owner.delivering = true;
    defer releaseNode(owner.engine.runtime, owner, node);
    node.task.join();
    if (node.task.allocationFailed()) return allocationFailure(owner.engine);
    const active_scope = async_scope.enter(owner.engine, node.scope);
    defer active_scope.restore();
    const message: ?[*:0]const u8 = if (queue_failure) "Could not queue clipboard operation" else node.task.message();
    var rejecting = message != null;
    const produced = if (message) |text| try errorValue(owner.engine, text) else
        node.task.result(owner.engine) catch |err| converted: {
            if (err == error.OutOfMemory) return allocationFailure(owner.engine);
            if (err == error.ExecutionTerminated) return err;
            // The original N-API completion rejects any ordinary value-creation
            // failure with this message. Do not strand the original deferred.
            // A genuine pending native producer is surfaced before discarding
            // the ordinary conversion diagnostic; DATA alone is never fatal.
            try stage.pending();
            if (owner.engine.captured_exception) |reason| {
                owner.engine.captured_exception = null;
                var owned = reason;
                stage.boundary.release(&owned);
            }
            try stage.pending();
            rejecting = true;
            break :converted try errorValue(owner.engine, "Could not create clipboard value");
        };
    const result = try stage.own(produced);
    // Resolving may run then getters or Promise hooks. There is deliberately no
    // allocator-counter span around this guest-capable operation.
    _ = try stage.call(if (rejecting) node.reject else node.resolve, c.pi_js_undefined(), &.{result});
    return c.pi_js_bool(owner.engine.context, 1);
}
fn pumpBody(stage: *Scope, owner: *Owner) !c.JSValue {
    try stage.pending();
    var previous: ?*Node = null;
    var cursor = owner.first;
    // Settle one completed callback per pump, then allow the engine's normal
    // microtask checkpoint. The queue is private and all links are owner-only.
    while (cursor) |node| {
        if (node.task.isDone()) {
            remove(owner, previous, node);
            std.debug.assert(owner.active > 0);
            owner.active -= 1;
            return settle(stage, owner, node, false);
        }
        previous = node;
        cursor = node.next;
    }
    var started = false;
    previous = null;
    cursor = owner.first;
    while (cursor) |node| {
        if (!node.task.started and owner.active < maximum_active_workers) {
            node.task.start() catch |err| {
                remove(owner, previous, node);
                owner.delivering = true;
                if (err == error.OutOfMemory) {
                    const failure = allocationFailure(owner.engine);
                    releaseNode(owner.engine.runtime, owner, node);
                    return failure;
                }
                return settle(stage, owner, node, true);
            };
            owner.active += 1;
            started = true;
        }
        previous = node;
        cursor = node.next;
        if (owner.active == maximum_active_workers) break;
    }
    return c.pi_js_bool(owner.engine.context, @intFromBool(started));
}
fn pump(engine: *js.Engine) !bool {
    const owner = existing(engine) orelse return false;
    if (owner.failed) return error.NativeClipboardCompletionFailed;
    if (owner.closing or owner.pumping or owner.first == null) return false;
    owner.pumping = true;
    defer owner.pumping = false;
    var stage = Scope.init(engine);
    var returned = [_]c.JSValue{c.pi_js_undefined()};
    var host_error: ?anyerror = null;
    if (pumpBody(&stage, owner)) |result| returned[0] = result else |err| host_error = err;
    // Select the actual completion and retire local roots while the invocation
    // stays linked. Remaining queue roots may run finalizers too.
    stage.boundary.retire(host_error, &stage.values, &returned);
    if (owner.delivering and stage.boundary.failed(host_error)) {
        owner.failed = true;
        retire(engine.runtime, owner);
    }
    stage.boundary.finishRetired(host_error, &returned) catch |err| {
        const delivering = owner.delivering;
        owner.delivering = false;
        if (!delivering) return err;
        owner.failed = true;
        owner.closing = true;
        // A failure discovered only at final materialization leaves any
        // remaining queue linked/rooted for terminal Engine cleanup. Never
        // release it after the invocation popped or allow owner reuse.
        return error.NativeClipboardCompletionFailed;
    };
    owner.delivering = false;
    defer engine.freeValue(returned[0]);
    return c.JS_ToBool(engine.context, returned[0]) != 0;
}
/// Consumes task on every exit. Promise roots and queue admission precede the
/// initial start. At most four jobs own an OS thread; the others remain queued
/// as aggregate-charged native records, with no public timer identifier.
pub fn create(engine: *js.Engine, task: *Worker) !c.JSValue {
    var queued = false;
    errdefer if (!queued) task.deinit();
    const owner = try getOwner(engine);
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(Node)) == 0) return allocationFailure(engine);
    errdefer if (!queued) c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Node));
    const node = engine.gpa.create(Node) catch |err| return if (err == error.OutOfMemory) allocationFailure(engine) else err;
    errdefer if (!queued) engine.gpa.destroy(node);
    // The raw API may create both resolving functions before an init hook
    // leaves an exception. Own partial outputs even when capability fails.
    var functions = [_]c.JSValue{ c.pi_js_undefined(), c.pi_js_undefined() };
    errdefer if (!queued) for (functions) |function| engine.freeValue(function);
    const promise = try capability(engine, &functions);
    errdefer engine.freeValue(promise);
    const scope = async_scope.capture(engine);
    errdefer if (!queued) engine.freeValue(scope);
    node.* = .{ .task = task, .resolve = functions[0], .reject = functions[1], .scope = scope };
    // An earlier queued request keeps FIFO start precedence even if a
    // Promise reaction submits more work between completion-pump turns.
    var waiting = owner.first;
    while (waiting) |item| {
        if (!item.task.started) break;
        waiting = item.next;
    }
    if (owner.active < maximum_active_workers and waiting == null) {
        task.start() catch |err| {
            if (err == error.OutOfMemory) return allocationFailure(engine);
            return throwMessage(engine, "Could not queue clipboard operation");
        };
        owner.active += 1;
    }
    if (owner.last) |last| last.next = node else owner.first = node;
    owner.last = node;
    queued = true;
    return promise;
}
