//! Native Node24 WHATWG writable streams. Authority: internal/webstreams/
//! writablestream and util from the pinned 0CD86676 builtin-source artifact.
//! Every queue, writer promise and sink algorithm belongs to the VM owner thread.
const std = @import("std");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const async_value = @import("native_agent_async.zig");
const c = js.c;
const Engine = js.Engine;
const Status = enum { writable, erroring, errored, closed };
const Stage = enum(c_int) { start, write, close, abort };
const Group = enum(c_int) { stream, writer, controller };
const Method = enum(c_int) { locked, streamAbort, streamClose, getWriter, closed, desiredSize, ready, writerAbort, writerClose, releaseLock, write, signal, errorValue };
const Capability = struct {
    promise: c.JSValue,
    resolve: c.JSValue,
    reject: c.JSValue,
    fn create(e: *Engine) !Capability {
        var functions: [2]c.JSValue = undefined;
        const promise = try e.checked(c.JS_NewPromiseCapability(e.context, &functions));
        return .{ .promise = promise, .resolve = functions[0], .reject = functions[1] };
    }
    fn deinit(self: Capability, runtime: ?*c.JSRuntime) void {
        c.JS_FreeValueRT(runtime, self.promise);
        c.JS_FreeValueRT(runtime, self.resolve);
        c.JS_FreeValueRT(runtime, self.reject);
    }
    fn mark(self: Capability, runtime: ?*c.JSRuntime, visit: ?*const c.JS_MarkFunc) void {
        c.JS_MarkValue(runtime, self.promise, visit);
        c.JS_MarkValue(runtime, self.resolve, visit);
        c.JS_MarkValue(runtime, self.reject, visit);
    }
    fn settle(self: Capability, e: *Engine, rejected: bool, value: c.JSValue) !void {
        var args = [_]c.JSValue{value};
        const ignored = try e.checked(c.JS_Call(e.context, if (rejected) self.reject else self.resolve, c.pi_js_undefined(), 1, &args));
        e.freeValue(ignored);
    }
};
const Chunk = struct { value: c.JSValue, size: f64 };
const Abort = struct { capability: Capability, reason: c.JSValue, was_erroring: bool };
const State = struct {
    engine: *Engine,
    bindings: c.JSValue,
    sink: c.JSValue,
    write_algorithm: c.JSValue,
    close_algorithm: c.JSValue,
    abort_algorithm: c.JSValue,
    size_algorithm: c.JSValue,
    controller: c.JSValue,
    signal: c.JSValue,
    writer: c.JSValue,
    stored_error: c.JSValue,
    closed: Capability,
    status: Status = .writable,
    started: bool = false,
    backpressure: bool = false,
    high_water_mark: f64,
    queue_total_size: f64 = 0,
    chunks: std.ArrayList(Chunk) = .empty,
    requests: std.ArrayList(Capability) = .empty,
    in_flight_write: ?Capability = null,
    close_request: ?Capability = null,
    in_flight_close: ?Capability = null,
    pending_abort: ?Abort = null,
    in_flight_abort: ?Abort = null,
};
const Writer = struct { engine: *Engine, stream: c.JSValue, ready: Capability, closed: Capability };
const Controller = struct { engine: *Engine, stream: c.JSValue };
fn streamState(value: c.JSValue) *State {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
}
fn writerState(value: c.JSValue) *Writer {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
}
fn streamFinalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const raw = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return;
    const self: *State = @ptrCast(@alignCast(raw));
    inline for (.{ "bindings", "sink", "write_algorithm", "close_algorithm", "abort_algorithm", "size_algorithm", "controller", "signal", "writer", "stored_error" }) |field| c.JS_FreeValueRT(runtime, @field(self, field));
    self.closed.deinit(runtime);
    for (self.chunks.items) |chunk| c.JS_FreeValueRT(runtime, chunk.value);
    for (self.requests.items) |pending| pending.deinit(runtime);
    if (self.in_flight_write) |pending| pending.deinit(runtime);
    if (self.close_request) |pending| pending.deinit(runtime);
    if (self.in_flight_close) |pending| pending.deinit(runtime);
    inline for (.{ "pending_abort", "in_flight_abort" }) |field| if (@field(self, field)) |pending| {
        pending.capability.deinit(runtime);
        c.JS_FreeValueRT(runtime, pending.reason);
    };
    self.chunks.deinit(self.engine.gpa);
    self.requests.deinit(self.engine.gpa);
    self.engine.gpa.destroy(self);
}
fn streamMark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const raw = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return;
    const self: *State = @ptrCast(@alignCast(raw));
    inline for (.{ "bindings", "sink", "write_algorithm", "close_algorithm", "abort_algorithm", "size_algorithm", "controller", "signal", "writer", "stored_error" }) |field| c.JS_MarkValue(runtime, @field(self, field), visit);
    self.closed.mark(runtime, visit);
    for (self.chunks.items) |chunk| c.JS_MarkValue(runtime, chunk.value, visit);
    for (self.requests.items) |pending| pending.mark(runtime, visit);
    if (self.in_flight_write) |pending| pending.mark(runtime, visit);
    if (self.close_request) |pending| pending.mark(runtime, visit);
    if (self.in_flight_close) |pending| pending.mark(runtime, visit);
    inline for (.{ "pending_abort", "in_flight_abort" }) |field| if (@field(self, field)) |pending| {
        pending.capability.mark(runtime, visit);
        c.JS_MarkValue(runtime, pending.reason, visit);
    };
}
fn writerFinalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const raw = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return;
    const self: *Writer = @ptrCast(@alignCast(raw));
    c.JS_FreeValueRT(runtime, self.stream);
    self.ready.deinit(runtime);
    self.closed.deinit(runtime);
    self.engine.gpa.destroy(self);
}
fn writerMark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const raw = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return;
    const self: *Writer = @ptrCast(@alignCast(raw));
    c.JS_MarkValue(runtime, self.stream, visit);
    self.ready.mark(runtime, visit);
    self.closed.mark(runtime, visit);
}
fn controllerFinalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const self: *Controller = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, self.stream);
    self.engine.gpa.destroy(self);
}
fn controllerMark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *Controller = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, self.stream, visit);
}
fn retained(e: *Engine) !c.JSValue {
    return e.native_writable_stream_bindings orelse error.NativeWritableStreamUnavailable;
}
fn classId(e: *Engine, group: Group) !c.JSClassID {
    const value = try js.get(e, try retained(e), switch (group) {
        .stream => "streamClass",
        .writer => "writerClass",
        .controller => "controllerClass",
    });
    defer e.freeValue(value);
    var id: u32 = 0;
    if (c.JS_ToUint32(e.context, &id, value) < 0) return js.capture(e);
    return id;
}
fn groupName(group: Group) [:0]const u8 {
    return switch (group) {
        .stream => "WritableStream",
        .writer => "WritableStreamDefaultWriter",
        .controller => "WritableStreamDefaultController",
    };
}
fn coded(e: *Engine, kind: [*:0]const u8, code: []const u8, message: []const u8) anyerror {
    const text = try @import("native_sdk.zig").text(e, message);
    defer e.freeValue(text);
    const constructor = try js.get(e, try retained(e), kind);
    defer e.freeValue(constructor);
    var args = [_]c.JSValue{text};
    const reason = try e.checked(c.JS_CallConstructor(e.context, constructor, 1, &args));
    var transferred = false;
    errdefer if (!transferred) e.freeValue(reason);
    const code_value = try @import("native_sdk.zig").text(e, code);
    if (c.JS_DefinePropertyValueStr(e.context, reason, "code", code_value, c.JS_PROP_C_W_E) < 0) return js.capture(e);
    transferred = true;
    _ = c.JS_Throw(e.context, reason);
    return js.capture(e);
}
fn invalidThis(e: *Engine, group: Group) anyerror {
    const message = try std.fmt.allocPrint(e.gpa, "Value of \"this\" must be of type {s}", .{groupName(group)});
    defer e.gpa.free(message);
    return coded(e, "TypeError", "ERR_INVALID_THIS", message);
}
fn stateError(e: *Engine, comptime message: []const u8) anyerror {
    return coded(e, "TypeError", "ERR_INVALID_STATE", "Invalid state: " ++ message);
}
fn invalidArgument(e: *Engine, name: []const u8, expected: []const u8, value: c.JSValue, instance: bool) anyerror {
    const received = try @import("node_events.zig").description(e, value);
    defer e.gpa.free(received);
    const message = try std.fmt.allocPrint(e.gpa, "The \"{s}\" {s} must be {s} {s}. Received {s}", .{ name, if (std.mem.indexOfScalar(u8, name, '.') != null) "property" else "argument", if (instance) "an instance of" else "of type", expected, received });
    defer e.gpa.free(message);
    return coded(e, "TypeError", "ERR_INVALID_ARG_TYPE", message);
}
fn invalidValue(e: *Engine, name: []const u8, value: c.JSValue) anyerror {
    const inspected = try @import("node_event_inspect.zig").inspect(e, value, 2);
    defer e.gpa.free(inspected);
    const message = try std.fmt.allocPrint(e.gpa, "The {s} '{s}' is invalid. Received {s}{s}", .{ if (std.mem.indexOfScalar(u8, name, '.') != null) "property" else "argument", name, inspected[0..@min(inspected.len, 128)], if (inspected.len > 128) "..." else "" });
    defer e.gpa.free(message);
    return coded(e, "RangeError", "ERR_INVALID_ARG_VALUE", message);
}
fn pendingReject(e: *Engine, reason: c.JSValue) !c.JSValue {
    return e.checked(c.JS_NewSettledPromise(e.context, true, reason));
}
fn resolved(e: *Engine) !c.JSValue {
    return e.checked(c.JS_NewSettledPromise(e.context, false, c.pi_js_undefined()));
}
fn replace(e: *Engine, slot: *c.JSValue, value: c.JSValue) void {
    e.freeValue(slot.*);
    slot.* = c.JS_DupValue(e.context, value);
}
fn clearAlgorithms(self: *State) void {
    inline for (.{ "write_algorithm", "close_algorithm", "abort_algorithm", "size_algorithm" }) |field| replace(self.engine, &@field(self, field), c.pi_js_undefined());
    // Node's sink is captured by the bound algorithms, not retained separately
    // once those algorithms are cleared. Do not keep a closed sink alive.
    replace(self.engine, &self.sink, c.pi_js_undefined());
}
fn clearChunks(self: *State) void {
    for (self.chunks.items) |chunk| self.engine.freeValue(chunk.value);
    self.chunks.clearRetainingCapacity();
    self.queue_total_size = 0;
}
fn rejectCapability(e: *Engine, capability: *Capability, reason: c.JSValue) !void {
    if (c.JS_PromiseState(e.context, capability.promise) != c.JS_PROMISE_PENDING) {
        const fresh = try Capability.create(e);
        capability.deinit(e.runtime);
        capability.* = fresh;
    }
    try capability.settle(e, true, reason);
    c.JS_PromiseMarkAsHandled(e.context, capability.promise);
}
fn closeQueued(self: *State) bool {
    return self.close_request != null or self.in_flight_close != null;
}
fn updateBackpressure(self: *State, value: bool) !void {
    if (!c.JS_IsUndefined(self.writer) and self.backpressure != value) {
        const writer = writerState(self.writer);
        if (value) {
            const fresh = try Capability.create(self.engine);
            writer.ready.deinit(self.engine.runtime);
            writer.ready = fresh;
        } else try writer.ready.settle(self.engine, false, c.pi_js_undefined());
    }
    self.backpressure = value;
}
fn rejectCloseAndClosed(self: *State) !void {
    if (self.close_request) |pending| {
        try pending.settle(self.engine, true, self.stored_error);
        pending.deinit(self.engine.runtime);
        self.close_request = null;
    }
    c.JS_PromiseMarkAsHandled(self.engine.context, self.closed.promise);
    try self.closed.settle(self.engine, true, self.stored_error);
    if (!c.JS_IsUndefined(self.writer)) {
        const writer = writerState(self.writer);
        c.JS_PromiseMarkAsHandled(self.engine.context, writer.closed.promise);
        try writer.closed.settle(self.engine, true, self.stored_error);
    }
}
fn promiseCallback(self: *State, function: c.JSValue, args: []const c.JSValue) !c.JSValue {
    // A sink callback can synchronously controller.error(), clearing the last
    // algorithm edge, or run GC. Retain the actual executing callable itself.
    const function_root = c.JS_DupValue(self.engine.context, function);
    defer self.engine.freeValue(function_root);
    const receiver_root = c.JS_DupValue(self.engine.context, self.sink);
    defer self.engine.freeValue(receiver_root);
    const result = if (c.JS_IsUndefined(function)) c.pi_js_undefined() else js.call(self.engine, function_root, receiver_root, args) catch |err| {
        const reason = async_value.reason(self.engine, err);
        defer self.engine.freeValue(reason);
        return pendingReject(self.engine, reason);
    };
    defer self.engine.freeValue(result);
    // Node's invokePromiseCallback is async even when the sink returns a Promise.
    return @import("native_durable.zig").resolvedPromise(self.engine, result);
}
fn waitAlgorithm(e: *Engine, stream: c.JSValue, value: c.JSValue, stage: Stage) !void {
    const promise = try e.checked(c.JS_PiPromiseResolve(e.context, value));
    defer e.freeValue(promise);
    var roots = [_]c.JSValue{stream};
    const yes = try e.checked(c.JS_NewCFunctionData2(e.context, continuation, "", 1, @intFromEnum(stage) * 2, 1, &roots));
    defer e.freeValue(yes);
    const no = try e.checked(c.JS_NewCFunctionData2(e.context, continuation, "", 1, @intFromEnum(stage) * 2 + 1, 1, &roots));
    defer e.freeValue(no);
    const ignored = try e.checked(c.JS_PromiseThen(e.context, promise, yes, no));
    e.freeValue(ignored);
}
fn finishErroring(stream: c.JSValue, self: *State) !void {
    self.status = .errored;
    clearChunks(self);
    while (self.requests.items.len > 0) {
        const pending = self.requests.orderedRemove(0);
        defer pending.deinit(self.engine.runtime);
        try pending.settle(self.engine, true, self.stored_error);
    }
    if (self.pending_abort) |pending| {
        self.pending_abort = null;
        if (pending.was_erroring) {
            defer pending.capability.deinit(self.engine.runtime);
            defer self.engine.freeValue(pending.reason);
            try pending.capability.settle(self.engine, true, self.stored_error);
            return rejectCloseAndClosed(self);
        }
        self.in_flight_abort = pending;
        const returned = try promiseCallback(self, self.abort_algorithm, &.{pending.reason});
        defer self.engine.freeValue(returned);
        clearAlgorithms(self);
        return waitAlgorithm(self.engine, stream, returned, .abort);
    }
    return rejectCloseAndClosed(self);
}
fn startErroring(stream: c.JSValue, self: *State, reason: c.JSValue) !void {
    if (self.status != .writable) return;
    self.status = .erroring;
    replace(self.engine, &self.stored_error, reason);
    if (!c.JS_IsUndefined(self.writer)) try rejectCapability(self.engine, &writerState(self.writer).ready, reason);
    if (self.in_flight_write == null and self.in_flight_close == null and self.started) try finishErroring(stream, self);
}
fn dealRejection(stream: c.JSValue, self: *State, reason: c.JSValue) !void {
    if (self.status == .writable) return startErroring(stream, self, reason);
    if (self.status == .erroring) return finishErroring(stream, self);
}
fn advance(stream: c.JSValue, self: *State) !void {
    if (!self.started or self.in_flight_write != null or self.in_flight_close != null) return;
    if (self.status == .erroring) return finishErroring(stream, self);
    if (self.status != .writable) return;
    if (self.chunks.items.len > 0) {
        self.in_flight_write = self.requests.orderedRemove(0);
        const returned = try promiseCallback(self, self.write_algorithm, &.{ self.chunks.items[0].value, self.controller });
        defer self.engine.freeValue(returned);
        return waitAlgorithm(self.engine, stream, returned, .write);
    }
    if (self.close_request) |pending| {
        self.in_flight_close = pending;
        self.close_request = null;
        const returned = try promiseCallback(self, self.close_algorithm, &.{});
        defer self.engine.freeValue(returned);
        clearAlgorithms(self);
        return waitAlgorithm(self.engine, stream, returned, .close);
    }
}
fn continueAlgorithm(stream: c.JSValue, self: *State, result: c.JSValue, rejected: bool, stage: Stage) !void {
    const e = self.engine;
    switch (stage) {
        .start => {
            self.started = true;
            if (rejected) return dealRejection(stream, self, result);
            return advance(stream, self);
        },
        .write => {
            const pending = self.in_flight_write orelse return;
            self.in_flight_write = null;
            defer pending.deinit(e.runtime);
            try pending.settle(e, rejected, if (rejected) result else c.pi_js_undefined());
            if (rejected) {
                if (self.status == .writable) clearAlgorithms(self);
                return dealRejection(stream, self, result);
            }
            const chunk = self.chunks.orderedRemove(0);
            e.freeValue(chunk.value);
            self.queue_total_size = @max(0, self.queue_total_size - chunk.size);
            if (!closeQueued(self) and self.status == .writable) try updateBackpressure(self, self.high_water_mark - self.queue_total_size <= 0);
            return advance(stream, self);
        },
        .close => {
            const pending = self.in_flight_close orelse return;
            self.in_flight_close = null;
            defer pending.deinit(e.runtime);
            try pending.settle(e, rejected, if (rejected) result else c.pi_js_undefined());
            if (rejected) {
                if (self.pending_abort) |abort| {
                    self.pending_abort = null;
                    defer abort.capability.deinit(e.runtime);
                    defer e.freeValue(abort.reason);
                    try abort.capability.settle(e, true, result);
                }
                return dealRejection(stream, self, result);
            }
            if (self.status == .erroring) {
                replace(e, &self.stored_error, c.pi_js_undefined());
                if (self.pending_abort) |abort| {
                    self.pending_abort = null;
                    defer abort.capability.deinit(e.runtime);
                    defer e.freeValue(abort.reason);
                    try abort.capability.settle(e, false, c.pi_js_undefined());
                }
            }
            self.status = .closed;
            if (!c.JS_IsUndefined(self.writer)) try writerState(self.writer).closed.settle(e, false, c.pi_js_undefined());
            try self.closed.settle(e, false, c.pi_js_undefined());
        },
        .abort => {
            const pending = self.in_flight_abort orelse return;
            self.in_flight_abort = null;
            defer pending.capability.deinit(e.runtime);
            defer e.freeValue(pending.reason);
            try pending.capability.settle(e, rejected, if (rejected) result else c.pi_js_undefined());
            try rejectCloseAndClosed(self);
        },
    }
}
/// Retirement also works after permanent host allocator failure. It uses only
/// retained VM values and existing promise resolving functions, never Scope.own.
fn failAll(self: *State, reason: c.JSValue) void {
    const e = self.engine;
    self.status = .errored;
    replace(e, &self.stored_error, reason);
    clearAlgorithms(self);
    clearChunks(self);
    for (self.requests.items) |pending| {
        pending.settle(e, true, reason) catch {};
        pending.deinit(e.runtime);
    }
    self.requests.clearRetainingCapacity();
    inline for (.{ "in_flight_write", "in_flight_close", "close_request" }) |field| if (@field(self, field)) |pending| {
        @field(self, field) = null;
        pending.settle(e, true, reason) catch {};
        pending.deinit(e.runtime);
    };
    inline for (.{ "pending_abort", "in_flight_abort" }) |field| if (@field(self, field)) |pending| {
        @field(self, field) = null;
        pending.capability.settle(e, true, reason) catch {};
        pending.capability.deinit(e.runtime);
        e.freeValue(pending.reason);
    };
    self.closed.settle(e, true, reason) catch {};
    c.JS_PromiseMarkAsHandled(e.context, self.closed.promise);
    if (!c.JS_IsUndefined(self.writer)) {
        const writer = writerState(self.writer);
        writer.ready.settle(e, true, reason) catch {};
        writer.closed.settle(e, true, reason) catch {};
        c.JS_PromiseMarkAsHandled(e.context, writer.ready.promise);
        c.JS_PromiseMarkAsHandled(e.context, writer.closed.promise);
    }
}
fn continuation(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const self = streamState(roots[0]);
    continueAlgorithm(roots[0], self, if (argc > 0) argv[0] else c.pi_js_undefined(), @mod(magic, 2) != 0, @enumFromInt(@divTrunc(magic, 2))) catch |err| {
        const reason = async_value.reason(self.engine, err);
        defer self.engine.freeValue(reason);
        failAll(self, reason);
    };
    _ = context;
    return c.pi_js_undefined();
}
pub fn isWritableStream(e: *Engine, value: c.JSValue) !bool {
    if (e.native_writable_stream_bindings == null or !c.JS_IsObject(value)) return false;
    return c.JS_GetOpaque(value, try classId(e, .stream)) != null;
}
pub fn isWritableStreamLocked(e: *Engine, value: c.JSValue) !bool {
    if (!try isWritableStream(e, value)) return invalidThis(e, .stream);
    return !c.JS_IsUndefined(streamState(value).writer);
}
/// Node's kIsWritable state predicate, distinct from the class brand predicate.
pub fn isWritableNative(e: *Engine, value: c.JSValue) !bool {
    if (!try isWritableStream(e, value)) return invalidThis(e, .stream);
    return streamState(value).status == .writable;
}
pub fn isClosedNative(e: *Engine, value: c.JSValue) !bool {
    if (!try isWritableStream(e, value)) return invalidThis(e, .stream);
    return streamState(value).status == .closed;
}
pub fn closeQueuedOrInFlightNative(e: *Engine, value: c.JSValue) !bool {
    if (!try isWritableStream(e, value)) return invalidThis(e, .stream);
    return closeQueued(streamState(value));
}
pub fn isErrored(e: *Engine, value: c.JSValue) !bool {
    if (!try isWritableStream(e, value)) return invalidThis(e, .stream);
    return streamState(value).status == .errored;
}
pub fn isErroringNative(e: *Engine, value: c.JSValue) !bool {
    if (!try isWritableStream(e, value)) return invalidThis(e, .stream);
    return streamState(value).status == .erroring;
}
pub fn isErroringOrErroredNative(e: *Engine, value: c.JSValue) !bool {
    if (!try isWritableStream(e, value)) return invalidThis(e, .stream);
    const status = streamState(value).status;
    return status == .erroring or status == .errored;
}
pub fn streamStoredErrorNative(e: *Engine, value: c.JSValue) !c.JSValue {
    if (!try isWritableStream(e, value)) return invalidThis(e, .stream);
    return c.JS_DupValue(e.context, streamState(value).stored_error);
}
fn nativeWriter(e: *Engine, value: c.JSValue) !*Writer {
    const raw = c.JS_GetOpaque(value, try classId(e, .writer)) orelse return invalidThis(e, .writer);
    return @ptrCast(@alignCast(raw));
}
fn boundStream(e: *Engine, writer: *Writer) !c.JSValue {
    if (c.JS_IsUndefined(writer.stream)) return stateError(e, "Writer is not bound to a WritableStream");
    return writer.stream;
}
pub fn acquireWriterNative(e: *Engine, stream: c.JSValue) !c.JSValue {
    if (!try isWritableStream(e, stream)) return invalidArgument(e, "stream", "WritableStream", stream, true);
    const self = streamState(stream);
    if (!c.JS_IsUndefined(self.writer)) return stateError(e, "WritableStream is locked");
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const object = try s.own(try e.checked(c.JS_NewObjectProtoClass(e.context, try s.get(try retained(e), "writerPrototype"), try classId(e, .writer))));
    const ready = try Capability.create(e);
    var attached = false;
    errdefer if (!attached) ready.deinit(e.runtime);
    const closed = try Capability.create(e);
    errdefer if (!attached) closed.deinit(e.runtime);
    const writer = try e.gpa.create(Writer);
    writer.* = .{ .engine = e, .stream = c.JS_DupValue(e.context, stream), .ready = ready, .closed = closed };
    _ = c.JS_SetOpaque(object, writer);
    attached = true;
    replace(e, &self.writer, object);
    switch (self.status) {
        .writable => if (closeQueued(self) or !self.backpressure) try writer.ready.settle(e, false, c.pi_js_undefined()),
        .erroring => {
            try writer.ready.settle(e, true, self.stored_error);
            c.JS_PromiseMarkAsHandled(e.context, writer.ready.promise);
        },
        .closed => {
            try writer.ready.settle(e, false, c.pi_js_undefined());
            try writer.closed.settle(e, false, c.pi_js_undefined());
        },
        .errored => {
            try writer.ready.settle(e, true, self.stored_error);
            try writer.closed.settle(e, true, self.stored_error);
            c.JS_PromiseMarkAsHandled(e.context, writer.ready.promise);
            c.JS_PromiseMarkAsHandled(e.context, writer.closed.promise);
        },
    }
    return c.JS_DupValue(e.context, object);
}
pub fn writerReadyNative(e: *Engine, value: c.JSValue) !c.JSValue {
    return c.JS_DupValue(e.context, (try nativeWriter(e, value)).ready.promise);
}
pub fn writerClosedNative(e: *Engine, value: c.JSValue) !c.JSValue {
    return c.JS_DupValue(e.context, (try nativeWriter(e, value)).closed.promise);
}
pub fn writerDesiredSizeNative(e: *Engine, value: c.JSValue) !c.JSValue {
    const stream = try boundStream(e, try nativeWriter(e, value));
    const self = streamState(stream);
    return switch (self.status) {
        .erroring, .errored => c.pi_js_null(),
        .closed => c.JS_NewInt32(e.context, 0),
        .writable => c.JS_NewFloat64(e.context, self.high_water_mark - self.queue_total_size),
    };
}
pub fn releaseWriterNative(e: *Engine, value: c.JSValue) !void {
    const writer = try nativeWriter(e, value);
    if (c.JS_IsUndefined(writer.stream)) return;
    const self = streamState(writer.stream);
    // Node shares the lazy released error across writers in one module instance.
    var reason = try js.get(e, try retained(e), "releasedError");
    defer e.freeValue(reason);
    if (c.JS_IsUndefined(reason)) {
        const err = stateError(e, "Writer has been released");
        e.freeValue(reason);
        reason = async_value.reason(e, err);
        try @import("native_sdk.zig").put(e, try retained(e), "releasedError", c.JS_DupValue(e.context, reason));
    }
    try rejectCapability(e, &writer.ready, reason);
    try rejectCapability(e, &writer.closed, reason);
    replace(e, &self.writer, c.pi_js_undefined());
    replace(e, &writer.stream, c.pi_js_undefined());
}
pub fn controllerErrorNative(e: *Engine, controller: c.JSValue, reason: c.JSValue) !void {
    const raw = c.JS_GetOpaque(controller, try classId(e, .controller)) orelse return invalidThis(e, .controller);
    const value: *Controller = @ptrCast(@alignCast(raw));
    const self = streamState(value.stream);
    if (self.status != .writable) return;
    clearAlgorithms(self);
    try startErroring(value.stream, self, reason);
}
pub fn controllerErrorIfNeededNative(e: *Engine, controller: c.JSValue, reason: c.JSValue) !void {
    return controllerErrorNative(e, controller, reason);
}
pub fn writerWriteNative(e: *Engine, value: c.JSValue, chunk: c.JSValue) !c.JSValue {
    const writer = try nativeWriter(e, value);
    const stream = try boundStream(e, writer);
    // A size callback may synchronously release/reacquire the writer or error
    // the controller. Hold the original stream and inspect the lock afterward.
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    _ = try s.own(c.JS_DupValue(e.context, value));
    _ = try s.own(c.JS_DupValue(e.context, stream));
    const self = streamState(stream);
    const size_algorithm = try s.own(c.JS_DupValue(e.context, self.size_algorithm));
    const raw_size = if (c.JS_IsUndefined(size_algorithm)) c.JS_NewInt32(e.context, 1) else s.call(size_algorithm, c.pi_js_undefined(), &.{chunk}) catch |err| blk: {
        const reason = try s.own(async_value.reason(e, err));
        try controllerErrorNative(e, self.controller, reason);
        break :blk c.JS_NewInt32(e.context, 1);
    };
    if (!c.JS_IsStrictEqual(e.context, stream, writer.stream)) return stateError(e, "Mismatched WritableStreams");
    if (self.status == .errored) return pendingReject(e, self.stored_error);
    if (closeQueued(self) or self.status == .closed) return stateError(e, "WritableStream is closed");
    if (self.status == .erroring) return pendingReject(e, self.stored_error);
    const pending = try Capability.create(e);
    var appended = false;
    errdefer if (!appended) pending.deinit(e.runtime);
    try self.requests.append(e.gpa, pending);
    appended = true;
    const returned = c.JS_DupValue(e.context, pending.promise);
    errdefer e.freeValue(returned);
    var size: f64 = undefined;
    const size_error: ?anyerror = if (c.JS_ToFloat64(e.context, &size, raw_size) < 0) js.capture(e) else if (!std.math.isFinite(size) or size < 0) invalidValue(e, "size", c.JS_NewFloat64(e.context, size)) else null;
    if (size_error) |err| {
        const reason = try s.own(async_value.reason(e, err));
        try controllerErrorNative(e, self.controller, reason);
        return returned;
    }
    const owned_chunk = c.JS_DupValue(e.context, chunk);
    self.chunks.append(e.gpa, .{ .value = owned_chunk, .size = size }) catch |err| {
        e.freeValue(owned_chunk);
        const reason = async_value.reason(e, err);
        defer e.freeValue(reason);
        failAll(self, reason);
        return returned;
    };
    self.queue_total_size += size;
    if (!closeQueued(self) and self.status == .writable) try updateBackpressure(self, self.high_water_mark - self.queue_total_size <= 0);
    try advance(stream, self);
    return returned;
}
fn closeStream(e: *Engine, stream: c.JSValue) !c.JSValue {
    const self = streamState(stream);
    if (self.status == .closed or self.status == .errored) return stateError(e, "WritableStream is closed");
    const pending = try Capability.create(e);
    self.close_request = pending;
    const returned = c.JS_DupValue(e.context, pending.promise);
    errdefer e.freeValue(returned);
    if (!c.JS_IsUndefined(self.writer) and self.backpressure and self.status == .writable) try writerState(self.writer).ready.settle(e, false, c.pi_js_undefined());
    try advance(stream, self);
    return returned;
}
pub fn writerCloseNative(e: *Engine, value: c.JSValue) !c.JSValue {
    const stream = try boundStream(e, try nativeWriter(e, value));
    if (closeQueued(streamState(stream))) return stateError(e, "Failure to close WritableStream");
    return closeStream(e, stream);
}
pub fn closeWithErrorPropagationNative(e: *Engine, value: c.JSValue) !c.JSValue {
    const stream = try boundStream(e, try nativeWriter(e, value));
    const self = streamState(stream);
    if (closeQueued(self) or self.status == .closed) return resolved(e);
    if (self.status == .errored) return pendingReject(e, self.stored_error);
    return closeStream(e, stream);
}
fn abortStream(e: *Engine, stream: c.JSValue, reason: c.JSValue) !c.JSValue {
    const self = streamState(stream);
    if (self.status == .closed or self.status == .errored) return resolved(e);
    const already_erroring = self.status == .erroring;
    try @import("abort_signal.zig").abort(e, self.signal, reason);
    if (self.pending_abort) |pending| return c.JS_DupValue(e.context, pending.capability.promise);
    const pending = try Capability.create(e);
    self.pending_abort = .{ .capability = pending, .reason = c.JS_DupValue(e.context, if (already_erroring) c.pi_js_undefined() else reason), .was_erroring = already_erroring };
    const returned = c.JS_DupValue(e.context, pending.promise);
    errdefer e.freeValue(returned);
    if (!already_erroring) try startErroring(stream, self, reason);
    return returned;
}
pub fn writerAbortNative(e: *Engine, value: c.JSValue, reason: c.JSValue) !c.JSValue {
    return abortStream(e, try boundStream(e, try nativeWriter(e, value)), reason);
}
fn makeStream(e: *Engine, sink_input: c.JSValue, strategy_input: c.JSValue, prototype: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const sink = if (c.JS_IsUndefined(sink_input)) try s.object() else sink_input;
    const strategy = if (c.JS_IsUndefined(strategy_input)) try s.object() else strategy_input;
    if (!c.JS_IsObject(sink)) return invalidArgument(e, "sink", "object", sink, false);
    if (!c.JS_IsObject(strategy) and !c.JS_IsNull(strategy)) return invalidArgument(e, "strategy", "object", strategy, false);
    const sink_type = try s.get(sink, "type");
    if (!c.JS_IsUndefined(sink_type)) return invalidValue(e, "type", sink_type);
    const size = if (c.JS_IsNull(strategy)) c.pi_js_undefined() else try s.get(strategy, "size");
    if (!c.JS_IsUndefined(size) and !c.JS_IsFunction(e.context, size)) return invalidArgument(e, "strategy.size", "function", size, false);
    const hwm_value = if (c.JS_IsNull(strategy)) c.pi_js_undefined() else try s.get(strategy, "highWaterMark");
    var hwm: f64 = 1;
    if (!c.JS_IsUndefined(hwm_value) and c.JS_ToFloat64(e.context, &hwm, hwm_value) < 0) return js.capture(e);
    if (std.math.isNan(hwm) or hwm < 0) return invalidValue(e, "strategy.highWaterMark", c.JS_NewFloat64(e.context, hwm));
    const bindings = try retained(e);
    const object = try s.own(try e.checked(c.JS_NewObjectProtoClass(e.context, prototype, try classId(e, .stream))));
    const controller = try s.own(try e.checked(c.JS_NewObjectProtoClass(e.context, try s.get(bindings, "controllerPrototype"), try classId(e, .controller))));
    const start = try s.get(sink, "start");
    const write = try s.get(sink, "write");
    const close = try s.get(sink, "close");
    const abort = try s.get(sink, "abort");
    if (s.truthy(start) and !c.JS_IsFunction(e.context, start)) {
        _ = c.JS_ThrowTypeError(e.context, "Bind must be called on a function");
        return js.capture(e);
    }
    inline for (.{ .{ "sink.write", write }, .{ "sink.close", close }, .{ "sink.abort", abort } }) |entry| if (s.truthy(entry[1]) and !c.JS_IsFunction(e.context, entry[1])) return invalidArgument(e, entry[0], "function", entry[1], false);
    const signal = try s.own(try @import("abort_signal.zig").create(e));
    const closed = try Capability.create(e);
    var attached = false;
    errdefer if (!attached) closed.deinit(e.runtime);
    const self = try e.gpa.create(State);
    self.* = .{ .engine = e, .bindings = c.JS_DupValue(e.context, bindings), .sink = c.JS_DupValue(e.context, if (s.truthy(write) or s.truthy(close) or s.truthy(abort)) sink else c.pi_js_undefined()), .write_algorithm = c.JS_DupValue(e.context, if (s.truthy(write)) write else c.pi_js_undefined()), .close_algorithm = c.JS_DupValue(e.context, if (s.truthy(close)) close else c.pi_js_undefined()), .abort_algorithm = c.JS_DupValue(e.context, if (s.truthy(abort)) abort else c.pi_js_undefined()), .size_algorithm = c.JS_DupValue(e.context, size), .controller = c.JS_DupValue(e.context, controller), .signal = c.JS_DupValue(e.context, signal), .writer = c.pi_js_undefined(), .stored_error = c.pi_js_undefined(), .closed = closed, .high_water_mark = hwm };
    _ = c.JS_SetOpaque(object, self);
    attached = true;
    const owned_controller = try e.gpa.create(Controller);
    owned_controller.* = .{ .engine = e, .stream = c.JS_DupValue(e.context, object) };
    _ = c.JS_SetOpaque(controller, owned_controller);
    try updateBackpressure(self, hwm <= 0);
    const started = if (s.truthy(start)) try s.call(start, sink, &.{controller}) else c.pi_js_undefined();
    const start_promise = try s.own(try @import("native_durable.zig").resolvedPromise(e, started));
    try waitAlgorithm(e, object, start_promise, .start);
    return c.JS_DupValue(e.context, object);
}
pub fn createNative(e: *Engine, sink: c.JSValue, strategy: c.JSValue) !c.JSValue {
    try install(e);
    const prototype = try js.get(e, try retained(e), "streamPrototype");
    defer e.freeValue(prototype);
    return makeStream(e, sink, strategy, prototype);
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn constructStream(e: *Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const prototype = try js.get(e, target, "prototype");
    defer e.freeValue(prototype);
    const fallback = if (c.JS_IsObject(prototype)) c.pi_js_undefined() else try js.get(e, try retained(e), "streamPrototype");
    defer e.freeValue(fallback);
    return makeStream(e, argument(args, 0), argument(args, 1), if (c.JS_IsObject(prototype)) prototype else fallback);
}
fn constructWriter(e: *Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const prototype = try js.get(e, target, "prototype");
    defer e.freeValue(prototype);
    const writer = try acquireWriterNative(e, argument(args, 0));
    errdefer e.freeValue(writer);
    if (c.JS_IsObject(prototype) and c.JS_SetPrototype(e.context, writer, prototype) < 0) return js.capture(e);
    return writer;
}
fn illegalConstructor(e: *Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return coded(e, "TypeError", "ERR_ILLEGAL_CONSTRUCTOR", "Illegal constructor");
}
fn operate(e: *Engine, receiver: c.JSValue, group: Group, method: Method, args: []const c.JSValue) !c.JSValue {
    switch (group) {
        .stream => {
            if (!try isWritableStream(e, receiver)) return invalidThis(e, .stream);
            const self = streamState(receiver);
            switch (method) {
                .locked => return c.pi_js_bool(e.context, @intFromBool(!c.JS_IsUndefined(self.writer))),
                .getWriter => return acquireWriterNative(e, receiver),
                .streamAbort, .streamClose => {
                    if (!c.JS_IsUndefined(self.writer)) return stateError(e, "WritableStream is locked");
                    if (method == .streamAbort) return abortStream(e, receiver, argument(args, 0));
                    if (closeQueued(self)) return stateError(e, "Failure closing WritableStream");
                    return closeStream(e, receiver);
                },
                else => unreachable,
            }
        },
        .writer => switch (method) {
            .closed => return writerClosedNative(e, receiver),
            .ready => return writerReadyNative(e, receiver),
            .desiredSize => return writerDesiredSizeNative(e, receiver),
            .writerAbort => return writerAbortNative(e, receiver, argument(args, 0)),
            .writerClose => return writerCloseNative(e, receiver),
            .releaseLock => {
                try releaseWriterNative(e, receiver);
                return c.pi_js_undefined();
            },
            .write => return writerWriteNative(e, receiver, argument(args, 0)),
            else => unreachable,
        },
        .controller => {
            const raw = c.JS_GetOpaque(receiver, try classId(e, .controller)) orelse return invalidThis(e, .controller);
            const owner: *Controller = @ptrCast(@alignCast(raw));
            if (method == .signal) return c.JS_DupValue(e.context, streamState(owner.stream).signal);
            try controllerErrorNative(e, receiver, argument(args, 0));
            return c.pi_js_undefined();
        },
    }
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const e = Engine.fromContext(context.?);
    const group: Group = @enumFromInt(@divTrunc(magic, 100));
    const method: Method = @enumFromInt(@mod(magic, 100));
    return operate(e, receiver, group, method, if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| {
        return switch (method) {
            .streamAbort, .streamClose, .closed, .ready, .writerAbort, .writerClose, .write => @import("native_durable.zig").rejectedPromise(e, err),
            else => @import("native_sdk.zig").fail(e, err),
        };
    };
}
fn defineMethod(s: *Scope, prototype: c.JSValue, group: Group, name: [:0]const u8, method: Method, getter: bool) !void {
    const function_name = if (getter) try std.fmt.allocPrintSentinel(s.engine.gpa, "get {s}", .{name}, 0) else null;
    defer if (function_name) |allocated| s.engine.gpa.free(allocated);
    const function = try s.own(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, dispatch, if (function_name) |allocated| allocated.ptr else name.ptr, 0, @intFromEnum(group) * 100 + @intFromEnum(method), 0, null)));
    if (!getter) {
        if (c.JS_DefinePropertyValueStr(s.engine.context, prototype, name.ptr, c.JS_DupValue(s.engine.context, function), c.JS_PROP_C_W_E) < 0) return js.capture(s.engine);
        return;
    }
    const atom = c.JS_NewAtom(s.engine.context, name.ptr);
    defer c.JS_FreeAtom(s.engine.context, atom);
    if (c.JS_DefinePropertyGetSet(s.engine.context, prototype, atom, c.JS_DupValue(s.engine.context, function), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(s.engine);
}
/// Constructors are exported for composition without reading mutable globals.
pub fn exports(e: *Engine) !c.JSValue {
    try install(e);
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const result = try s.object();
    inline for (.{ "WritableStream", "WritableStreamDefaultWriter", "WritableStreamDefaultController" }) |name| try s.put(result, name, try s.get(try retained(e), name));
    return c.JS_DupValue(e.context, result);
}
pub fn install(e: *Engine) !void {
    if (e.native_writable_stream_bindings != null) return;
    // Node's writable module requires its real AbortController dependency.
    // Engine.init is intentionally smaller than the complete web API graph.
    if (e.abort_signal_class == 0) try @import("abort_signal.zig").install(e);
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const bindings = try s.object();
    inline for (.{ "TypeError", "RangeError" }) |name| try s.put(bindings, name, try s.global(name));
    // Root the installation before any constructor can reenter native helpers.
    e.native_writable_stream_bindings = c.JS_DupValue(e.context, bindings);
    errdefer {
        e.freeValue(e.native_writable_stream_bindings.?);
        e.native_writable_stream_bindings = null;
    }
    const global = try s.own(c.JS_GetGlobalObject(e.context));
    const symbol = try s.get(try s.global("Symbol"), "toStringTag");
    const tag = c.JS_ValueToAtom(e.context, symbol);
    defer c.JS_FreeAtom(e.context, tag);
    inline for ([_]Group{ .stream, .writer, .controller }) |group| {
        var id: c.JSClassID = 0;
        _ = c.JS_NewClassID(e.runtime, &id);
        const definition: c.JSClassDef = .{ .class_name = groupName(group).ptr, .finalizer = switch (group) {
            .stream => streamFinalize,
            .writer => writerFinalize,
            .controller => controllerFinalize,
        }, .gc_mark = switch (group) {
            .stream => streamMark,
            .writer => writerMark,
            .controller => controllerMark,
        } };
        if (c.JS_NewClass(e.runtime, id, &definition) < 0) return error.OutOfMemory;
        try s.put(bindings, switch (group) {
            .stream => "streamClass",
            .writer => "writerClass",
            .controller => "controllerClass",
        }, c.JS_NewUint32(e.context, id));
        const prototype = try s.object();
        try s.put(bindings, switch (group) {
            .stream => "streamPrototype",
            .writer => "writerPrototype",
            .controller => "controllerPrototype",
        }, prototype);
        const constructor = try s.own(try @import("native_class.zig").constructor(e, groupName(group), if (group == .writer) 1 else 0, prototype, switch (group) {
            .stream => constructStream,
            .writer => constructWriter,
            .controller => illegalConstructor,
        }, &.{}));
        try s.put(bindings, groupName(group), constructor);
        if (c.JS_DefinePropertyValueStr(e.context, global, groupName(group).ptr, c.JS_DupValue(e.context, constructor), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(e);
        if (group == .stream) {
            try defineMethod(&s, prototype, group, "locked", .locked, true);
            try defineMethod(&s, prototype, group, "abort", .streamAbort, false);
            try defineMethod(&s, prototype, group, "close", .streamClose, false);
            try defineMethod(&s, prototype, group, "getWriter", .getWriter, false);
        } else if (group == .writer) {
            try defineMethod(&s, prototype, group, "closed", .closed, true);
            try defineMethod(&s, prototype, group, "desiredSize", .desiredSize, true);
            try defineMethod(&s, prototype, group, "ready", .ready, true);
            try defineMethod(&s, prototype, group, "abort", .writerAbort, false);
            try defineMethod(&s, prototype, group, "close", .writerClose, false);
            try defineMethod(&s, prototype, group, "releaseLock", .releaseLock, false);
            try defineMethod(&s, prototype, group, "write", .write, false);
        } else {
            try defineMethod(&s, prototype, group, "signal", .signal, true);
            try defineMethod(&s, prototype, group, "error", .errorValue, false);
        }
        if (c.JS_DefinePropertyValue(e.context, prototype, tag, c.JS_DupValue(e.context, try s.text(groupName(group))), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(e);
    }
}
