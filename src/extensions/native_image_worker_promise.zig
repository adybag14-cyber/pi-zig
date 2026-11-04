//! Private owner-thread promise settlement for an owned image worker VM.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const worker = @import("native_image_vm_worker.zig");
const timers = @import("timers.zig");
const pending = @import("native_pending_owner.zig");
const sdk = @import("native_sdk.zig");
const State = struct {
    allocator: std.mem.Allocator,
    task: *worker.Worker,
    resolve: c.JSValue,
    reject: c.JSValue,
    settled: bool = false,
};
fn state(value: c.JSValue) *State {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
}
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const owner: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    owner.task.deinit();
    c.JS_FreeValueRT(runtime, owner.resolve);
    c.JS_FreeValueRT(runtime, owner.reject);
    owner.allocator.destroy(owner);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, callback: ?*const c.JS_MarkFunc) callconv(.c) void {
    const owner: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, owner.resolve, callback);
    c.JS_MarkValue(runtime, owner.reject, callback);
}
fn failureValue(engine: *js.Engine, owner: *State) !c.JSValue {
    // Worker-local VM exceptions cross only as serialized failure DATA.
    // A genuine host allocator failure is the sole cross-worker OOM producer.
    if (owner.task.failure) |cause| if (cause == error.OutOfMemory)
        try pending.catchFailure(engine, cause);
    const result = try engine.checked(c.JS_NewError(engine.context));
    errdefer engine.freeValue(result);
    try js.define(engine, result, "message", try engine.checked(c.JS_NewStringLen(engine.context, if (owner.task.message) |message| message.ptr else "Image worker failed", if (owner.task.message) |message| message.len else "Image worker failed".len)));
    return result;
}
fn poll(context: ?*c.JSContext, handle: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var frame = pending.Frame.init(engine);
    frame.enter() catch return frame.finishCallback(c.pi_js_exception());
    const result = pollOwned(engine, handle, data) catch |err| sdk.fail(engine, err);
    return frame.finishCallback(result);
}
fn pollOwned(engine: *js.Engine, handle: c.JSValue, data: [*c]c.JSValue) !c.JSValue {
    const owner = state(data[0]);
    if (owner.settled) return c.pi_js_undefined();
    if (!owner.task.isDone()) return c.pi_js_undefined();
    try timers.cancelHandle(engine, handle);
    owner.task.join();
    var rejected = owner.task.failure != null;
    const result = if (rejected) try failureValue(engine, owner)
        else owner.task.result(engine) catch |err| blk: {
            try pending.catchFailure(engine, err);
            rejected = true;
            if (!c.JS_HasException(engine.context)) _ = sdk.fail(engine, err);
            try pending.checkFatal(engine);
            if (!c.JS_HasException(engine.context)) return error.ImageResultFailureWithoutPendingReason;
            break :blk c.JS_GetException(engine.context);
        };
    defer engine.freeValue(result);
    owner.settled = true;
    const ignored = try js.call(engine, if (rejected) owner.reject else owner.resolve, c.pi_js_undefined(), &.{result});
    engine.freeValue(ignored);
    return c.pi_js_undefined();
}
fn schedule(engine: *js.Engine, object: c.JSValue) !void {
    var data = [_]c.JSValue{object};
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, poll, "image worker completion", 0, 0, 1, &data));
    defer engine.freeValue(callback);
    const handle = try timers.scheduleInterval(engine, callback, 1);
    engine.freeValue(handle);
}
/// Takes ownership of task on success. A failed installation leaves task with
/// the caller, so no worker can be orphaned by a VM allocation failure.
pub fn create(engine: *js.Engine, task: *worker.Worker) !c.JSValue {
    var functions: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    errdefer engine.freeValue(promise);
    errdefer for (functions) |function| engine.freeValue(function);
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Native image worker promise owner", .finalizer = finalize, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const owner = try engine.gpa.create(State);
    errdefer engine.gpa.destroy(owner);
    const object = try engine.checked(c.JS_NewObjectClass(engine.context, @intCast(class)));
    owner.* = .{ .allocator = engine.gpa, .task = task, .resolve = functions[0], .reject = functions[1] };
    if (c.JS_SetOpaque(object, owner) < 0) {
        engine.freeValue(object);
        return error.OutOfMemory;
    }
    // Once object owns its state, errors must detach it before freeing the
    // object so the caller still owns task and the function references.
    schedule(engine, object) catch |err| {
        _ = c.JS_SetOpaque(object, null);
        engine.freeValue(object);
        return err;
    };
    engine.freeValue(object);
    return promise;
}
