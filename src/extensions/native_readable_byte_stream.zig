//! Private native byte-stream/controller implementation. Source-only until the
//! genuine stream and FileHandle probes qualify its lifecycle and ownership.
const std = @import("std");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const async_value = @import("native_agent_async.zig");
const h = @import("native_stream_helpers.zig");
const c = js.c;
const Status = enum { readable, closed, errored };
const ReaderKind = enum { default, byob, none };
const Method = enum(c_int) { getReader, locked, cancel, readerRead, readerCancel, releaseLock, readerClosed, enqueue, close, errorValue, desiredSize, byobRequest, requestView, respond, respondWithNewView, privateCancel };
const Await = enum(c_int) { start, pull, cancel };
const Chunk = struct {
    backing: c.JSValue,
    offset: usize,
    length: usize,
};
const ValueChunk = struct { value: c.JSValue, size: f64 };
const Into = struct {
    owner: c.JSValue,
    backing: c.JSValue,
    offset: usize,
    capacity: usize,
    backing_length: usize = 0,
    filled: usize = 0,
    minimum: usize,
    width: usize,
    array_type: c_int,
    kind: ReaderKind,
    read_settled: bool = false,
};
const State = struct {
    engine: *js.Engine,
    bindings: c.JSValue,
    source: c.JSValue,
    pull: c.JSValue,
    cancel: c.JSValue,
    controller: c.JSValue,
    reader: c.JSValue,
    request: c.JSValue,
    request_view: c.JSValue,
    stored_error: c.JSValue,
    size_algorithm: c.JSValue,
    byte_source: bool = true,
    status: Status = .readable,
    started: bool = false,
    pulling: bool = false,
    pull_again: bool = false,
    close_requested: bool = false,
    disturbed: bool = false,
    auto_allocate: usize = 0,
    high_water_mark: f64 = 0,
    queue_bytes: usize = 0,
    queue: std.ArrayList(Chunk) = .empty,
    value_queue: std.ArrayList(ValueChunk) = .empty,
    queue_total_size: f64 = 0,
    pending: std.ArrayList(Into) = .empty,
};
const Reader = struct {
    engine: *js.Engine,
    stream: c.JSValue,
    kind: ReaderKind,
    released: bool = false,
    closed: async_value.Pending,
};
const Controller = struct {
    engine: *js.Engine,
    stream_value: c.JSValue,
};
fn controllerFinalize(runtime: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
    const self: *Controller = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    c.JS_FreeValueRT(runtime, self.stream_value);
    self.engine.gpa.destroy(self);
}
fn controllerMark(runtime: ?*c.JSRuntime, object: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *Controller = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    c.JS_MarkValue(runtime, self.stream_value, visit);
}
fn stream(value: c.JSValue) *State {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
}
fn reader(value: c.JSValue) *Reader {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
}
fn releaseInto(engine: *js.Engine, into: Into) void {
    engine.freeValue(into.owner);
    engine.freeValue(into.backing);
}
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    inline for (.{ "bindings", "source", "pull", "cancel", "controller", "reader", "request", "request_view", "stored_error", "size_algorithm" }) |name| c.JS_FreeValueRT(runtime, @field(self, name));
    for (self.queue.items) |chunk| c.JS_FreeValueRT(runtime, chunk.backing);
    for (self.value_queue.items) |chunk| c.JS_FreeValueRT(runtime, chunk.value);
    for (self.pending.items) |into| releaseInto(self.engine, into);
    self.queue.deinit(self.engine.gpa);
    self.value_queue.deinit(self.engine.gpa);
    self.pending.deinit(self.engine.gpa);
    self.engine.gpa.destroy(self);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    inline for (.{ "bindings", "source", "pull", "cancel", "controller", "reader", "request", "request_view", "stored_error", "size_algorithm" }) |name| c.JS_MarkValue(runtime, @field(self, name), visit);
    for (self.queue.items) |chunk| c.JS_MarkValue(runtime, chunk.backing, visit);
    for (self.value_queue.items) |chunk| c.JS_MarkValue(runtime, chunk.value, visit);
    for (self.pending.items) |into| {
        c.JS_MarkValue(runtime, into.owner, visit);
        c.JS_MarkValue(runtime, into.backing, visit);
    }
}
fn readerFinalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const self: *Reader = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, self.stream);
    c.JS_FreeValueRT(runtime, self.closed.owner);
    c.JS_FreeValueRT(runtime, self.closed.promise);
    self.engine.gpa.destroy(self);
}
fn readerMark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *Reader = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, self.stream, visit);
    c.JS_MarkValue(runtime, self.closed.owner, visit);
    c.JS_MarkValue(runtime, self.closed.promise, visit);
}
fn typeError(scope: *Scope, message: [*:0]const u8) anyerror {
    _ = c.JS_ThrowTypeError(scope.engine.context, "%s", message);
    return js.capture(scope.engine);
}
fn codedTypeError(scope: *Scope, code: []const u8, message: []const u8) anyerror {
    return @import("node_events.zig").codedError(scope.engine, "TypeError", code, message);
}
fn integer(scope: *Scope, value: c.JSValue, positive: bool) !usize {
    var number: f64 = undefined;
    if (c.JS_ToFloat64(scope.engine.context, &number, value) < 0) return js.capture(scope.engine);
    if (!std.math.isFinite(number) or @trunc(number) != number or number < @as(f64, if (positive) 1 else 0) or number > 9007199254740991) return typeError(scope, "Invalid byte stream count");
    return std.math.cast(usize, @as(u64, @intFromFloat(number))) orelse error.InvalidNativeByteStreamCount;
}
fn numberValue(scope: *Scope, number: usize) c.JSValue {
    return c.JS_NewFloat64(scope.engine.context, @floatFromInt(number));
}
fn transferred(scope: *Scope, self: *State, backing: c.JSValue) !c.JSValue {
    return scope.call(try scope.get(self.bindings, "byteStreamTransfer"), backing, &.{});
}
fn view(scope: *Scope, backing: c.JSValue, offset: usize, length: usize, array_type: c_int, width: usize) !c.JSValue {
    var args = [_]c.JSValue{ backing, numberValue(scope, offset), numberValue(scope, length / width) };
    if (array_type >= 0) return scope.own(try scope.engine.checked(c.JS_NewTypedArray(scope.engine.context, args.len, &args, @intCast(array_type))));
    return scope.own(try js.builtin(scope.engine, "DataView", &args));
}
fn result(scope: *Scope, item: c.JSValue, finished: bool) !c.JSValue {
    const object = try scope.object();
    try scope.put(object, "value", item);
    try scope.put(object, "done", c.pi_js_bool(scope.engine.context, @intFromBool(finished)));
    return object;
}
fn invalidate(self: *State) void {
    self.engine.freeValue(self.request);
    self.engine.freeValue(self.request_view);
    self.request = c.pi_js_undefined();
    self.request_view = c.pi_js_undefined();
}
fn clearQueue(self: *State) void {
    for (self.queue.items) |chunk| self.engine.freeValue(chunk.backing);
    self.queue.clearRetainingCapacity();
    self.queue_bytes = 0;
    for (self.value_queue.items) |chunk| self.engine.freeValue(chunk.value);
    self.value_queue.clearRetainingCapacity();
    self.queue_total_size = 0;
}
fn queuedSize(self: *State) f64 {
    return if (self.byte_source) @floatFromInt(self.queue_bytes) else self.queue_total_size;
}
fn settleClosed(scope: *Scope, self: *State, failed: bool, reason: c.JSValue) !void {
    if (!c.JS_IsUndefined(self.reader)) try async_value.settle(scope.engine, reader(self.reader).closed.owner, failed, reason);
}
fn queueChunk(scope: *Scope, self: *State, backing: c.JSValue, offset: usize, length: usize, front: bool) !void {
    const total = try std.math.add(usize, self.queue_bytes, length);
    const retained = c.JS_DupValue(scope.engine.context, backing);
    errdefer scope.engine.freeValue(retained);
    const chunk: Chunk = .{ .backing = retained, .offset = offset, .length = length };
    if (front) try self.queue.insert(scope.engine.gpa, 0, chunk) else try self.queue.append(scope.engine.gpa, chunk);
    self.queue_bytes = total;
}
fn queueClone(scope: *Scope, self: *State, backing: c.JSValue, offset: usize, length: usize) !void {
    if (length == 0) return;
    const end = try std.math.add(usize, offset, length);
    const cloned = try scope.call(try scope.get(self.bindings, "byteStreamSlice"), backing, &.{ numberValue(scope, offset), numberValue(scope, end) });
    try queueChunk(scope, self, cloned, 0, length, true);
}
fn commit(scope: *Scope, self: *State, finished: bool) !void {
    const into = self.pending.items[0];
    if (into.kind == .none) {
        if (!finished) try queueClone(scope, self, into.backing, into.offset, into.filled);
        releaseInto(scope.engine, self.pending.orderedRemove(0));
        invalidate(self);
        return;
    }
    if (!into.read_settled) {
        const returned = if (into.kind == .default and finished) c.pi_js_undefined() else try view(scope, into.backing, into.offset, into.filled, into.array_type, into.width);
        const packet = try result(scope, returned, finished);
        try async_value.settle(scope.engine, into.owner, false, packet);
    }
    releaseInto(scope.engine, self.pending.orderedRemove(0));
    invalidate(self);
}
fn closeNow(scope: *Scope, self: *State) !void {
    if (self.pending.items.len != 0 and self.pending.items[0].filled % self.pending.items[0].width != 0) {
        const reason = try scope.own(try js.builtin(scope.engine, "TypeError", &.{try scope.text("Invalid state: Partial read")}));
        try scope.put(reason, "code", try scope.text("ERR_INVALID_STATE"));
        try errored(scope, self, reason);
        return h.throw(scope, reason);
    }
    self.status = .closed;
    try settleClosed(scope, self, false, c.pi_js_undefined());
    // Default read requests close immediately. Its auto-allocated pull-into
    // descriptor can remain live until the source's later respond(0); delaying
    // the read until that response changes FileHandle autoClose ordering.
    for (self.pending.items) |*into| if (into.kind == .default and !into.read_settled) {
        try async_value.settle(scope.engine, into.owner, false, try result(scope, c.pi_js_undefined(), true));
        into.read_settled = true;
    };
    // Pull-into descriptors remain until respond(0), even if the BYOB request
    // object has not yet been materialized by its lazy getter. Plain default
    // read requests without auto-allocation have no such descriptor to retain.
    while (self.pending.items.len != 0 and self.pending.items[0].capacity == 0) try commit(scope, self, true);
}
fn errored(scope: *Scope, self: *State, reason: c.JSValue) !void {
    if (self.status != .readable) return;
    self.status = .errored;
    scope.engine.freeValue(self.stored_error);
    self.stored_error = c.JS_DupValue(scope.engine.context, reason);
    invalidate(self);
    clearQueue(self);
    while (self.pending.items.len != 0) {
        const into = self.pending.orderedRemove(0);
        defer releaseInto(scope.engine, into);
        if (into.kind != .none) try async_value.settle(scope.engine, into.owner, true, reason);
    }
    try settleClosed(scope, self, true, reason);
}
fn algorithm(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const item = if (argc > 0) argv[0] else c.pi_js_undefined();
    const rejected = @mod(raw, 2) != 0;
    const stage: Await = @enumFromInt(@divTrunc(raw, 2));
    const self = stream(roots[0]);
    algorithmStep(&scope, roots[0], self, roots[1], item, rejected, stage) catch |err| {
        const reason = async_value.reason(engine, err);
        defer engine.freeValue(reason);
        errored(&scope, self, reason) catch |failure| return @import("native_durable.zig").reject(engine, failure);
    };
    return c.pi_js_undefined();
}
fn awaitAlgorithm(scope: *Scope, object: c.JSValue, pending: c.JSValue, owner: c.JSValue, stage: Await) !void {
    const awaited = try scope.own(try scope.engine.checked(c.JS_PiPromiseResolve(scope.engine.context, pending)));
    var roots = [_]c.JSValue{ object, owner };
    const fulfilled = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, algorithm, "", 1, @intFromEnum(stage) * 2, roots.len, &roots)));
    const rejected = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, algorithm, "", 1, @intFromEnum(stage) * 2 + 1, roots.len, &roots)));
    _ = try scope.own(try scope.engine.checked(c.JS_PromiseThen(scope.engine.context, awaited, fulfilled, rejected)));
}
fn algorithmStep(scope: *Scope, object: c.JSValue, self: *State, owner: c.JSValue, item: c.JSValue, rejected: bool, stage: Await) !void {
    if (stage == .cancel) return async_value.settle(scope.engine, owner, rejected, if (rejected) item else c.pi_js_undefined());
    if (stage == .pull) self.pulling = false;
    if (rejected) return errored(scope, self, item);
    if (stage == .start) self.started = true;
    const again = self.pull_again;
    self.pull_again = false;
    if (stage == .start or again) try pull(scope, object, self);
}
fn pull(scope: *Scope, object: c.JSValue, self: *State) !void {
    if (!self.started or self.status != .readable or self.close_requested or (self.pending.items.len == 0 and self.high_water_mark <= queuedSize(self))) return;
    if (self.pulling) {
        self.pull_again = true;
        return;
    }
    self.pulling = true;
    const pending = if (c.JS_IsUndefined(self.pull)) c.pi_js_undefined() else scope.call(self.pull, self.source, &.{self.controller}) catch |err| {
        self.pulling = false;
        const reason = async_value.reason(scope.engine, err);
        defer scope.engine.freeValue(reason);
        return errored(scope, self, reason);
    };
    awaitAlgorithm(scope, object, pending, c.pi_js_undefined(), .pull) catch |err| {
        self.pulling = false;
        const reason = async_value.reason(scope.engine, err);
        defer scope.engine.freeValue(reason);
        return errored(scope, self, reason);
    };
}
fn copyQueue(scope: *Scope, self: *State) !void {
    if (!self.byte_source) {
        while (self.pending.items.len != 0 and self.value_queue.items.len != 0) {
            const into = self.pending.items[0];
            if (into.kind == .none) {
                releaseInto(scope.engine, self.pending.orderedRemove(0));
                continue;
            }
            const chunk = self.value_queue.items[0];
            try async_value.settle(scope.engine, into.owner, false, try result(scope, chunk.value, false));
            releaseInto(scope.engine, self.pending.orderedRemove(0));
            self.queue_total_size = @max(0, self.queue_total_size - chunk.size);
            scope.engine.freeValue(self.value_queue.orderedRemove(0).value);
        }
        if (self.close_requested and self.value_queue.items.len == 0 and self.status == .readable) try closeNow(scope, self);
        return;
    }
    while (self.pending.items.len != 0 and self.queue.items.len != 0) {
        const into = &self.pending.items[0];
        const chunk = &self.queue.items[0];
        if (into.kind == .none and into.capacity == 0) {
            releaseInto(scope.engine, self.pending.orderedRemove(0));
            continue;
        }
        if (into.kind == .default) {
            const returned = try view(scope, chunk.backing, chunk.offset, chunk.length, c.JS_TYPED_ARRAY_UINT8, 1);
            try async_value.settle(scope.engine, into.owner, false, try result(scope, returned, false));
            const removed = self.pending.orderedRemove(0);
            releaseInto(scope.engine, removed);
            self.queue_bytes -= chunk.length;
            scope.engine.freeValue(self.queue.orderedRemove(0).backing);
            continue;
        }
        const available = @min(into.capacity - into.filled, self.queue_bytes);
        const maximum = into.filled + available;
        const aligned = maximum - maximum % into.width;
        const planned = if (aligned >= into.minimum) aligned - into.filled else available;
        const count = @min(planned, chunk.length);
        var source_length: usize = undefined;
        var destination_length: usize = undefined;
        const source_data = c.JS_GetArrayBuffer(scope.engine.context, &source_length, chunk.backing);
        const destination = c.JS_GetArrayBuffer(scope.engine.context, &destination_length, into.backing);
        if (source_data == null or destination == null or chunk.offset > source_length or count > source_length - chunk.offset or into.offset + into.filled > destination_length or count > destination_length - into.offset - into.filled) return error.InvalidNativeByteStreamStorage;
        @memcpy(destination[into.offset + into.filled ..][0..count], source_data[chunk.offset..][0..count]);
        into.filled += count;
        chunk.offset += count;
        chunk.length -= count;
        self.queue_bytes -= count;
        if (chunk.length == 0) scope.engine.freeValue(self.queue.orderedRemove(0).backing);
        if (into.filled >= into.minimum and into.filled % into.width == 0) try commit(scope, self, false);
    }
    if (self.close_requested and self.queue_bytes == 0 and self.status == .readable) try closeNow(scope, self);
}
fn handled(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn closedPromise(scope: *Scope, object: c.JSValue) !async_value.Pending {
    const pending = try async_value.create(scope.engine, object);
    errdefer {
        scope.engine.freeValue(pending.owner);
        scope.engine.freeValue(pending.promise);
    }
    const ignore = try scope.own(try scope.engine.checked(c.JS_NewCFunction(scope.engine.context, handled, "", 1)));
    _ = try scope.own(try scope.engine.checked(c.JS_PromiseThen(scope.engine.context, pending.promise, c.pi_js_undefined(), ignore)));
    return pending;
}
fn function(scope: *Scope, object: c.JSValue, name: [*:0]const u8, method: Method, roots: []c.JSValue, getter: bool) !void {
    const callback = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, dispatch, name, if (getter) 0 else 1, @intFromEnum(method), @intCast(roots.len), roots.ptr)));
    if (!getter) return scope.put(object, name, callback);
    const atom = c.JS_NewAtom(scope.engine.context, name);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DefinePropertyGetSet(scope.engine.context, object, atom, c.JS_DupValue(scope.engine.context, callback), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(scope.engine);
}
fn publicBindings(engine: *js.Engine, bindings: c.JSValue) bool {
    return if (engine.native_readable_stream_bindings) |retained| c.JS_IsStrictEqual(engine.context, retained, bindings) else false;
}
fn classId(scope: *Scope, bindings: c.JSValue, name: [*:0]const u8) !c.JSClassID {
    var id: u32 = undefined;
    if (c.JS_ToUint32(scope.engine.context, &id, try scope.get(bindings, name)) < 0) return js.capture(scope.engine);
    return id;
}
/// Private consumers capture the same bindings as the constructor. These
/// checks inspect only the native class/state and do not invoke guest getters.
pub fn isReadableStream(scope: *Scope, bindings: c.JSValue, object: c.JSValue) !bool {
    return c.JS_GetOpaque(object, try classId(scope, bindings, "byteStreamClass")) != null;
}
pub fn isDisturbed(scope: *Scope, bindings: c.JSValue, object: c.JSValue) !bool {
    const raw = c.JS_GetOpaque(object, try classId(scope, bindings, "byteStreamClass")) orelse return false;
    return @as(*State, @ptrCast(@alignCast(raw))).disturbed;
}
pub fn isErrored(scope: *Scope, bindings: c.JSValue, object: c.JSValue) !bool {
    const raw = c.JS_GetOpaque(object, try classId(scope, bindings, "byteStreamClass")) orelse return false;
    return @as(*State, @ptrCast(@alignCast(raw))).status == .errored;
}
/// Captured internal controller close, as used by BodyMixin's queued close.
/// Public controller.close still performs its observable receiver/state checks.
pub fn closeController(scope: *Scope, bindings: c.JSValue, object: c.JSValue) !void {
    const raw = c.JS_GetOpaque(object, try classId(scope, bindings, "byteControllerClass")) orelse return error.NativeByteStreamControllerRequired;
    const retained: *Controller = @ptrCast(@alignCast(raw));
    const self = stream(retained.stream_value);
    if (self.close_requested or self.status != .readable) return;
    if ((self.byte_source and self.queue_bytes != 0) or (!self.byte_source and self.value_queue.items.len != 0)) {
        self.close_requested = true;
        return;
    }
    try closeNow(scope, self);
}
fn nativeState(scope: *Scope, bindings: c.JSValue, object: c.JSValue) !*State {
    const raw = c.JS_GetOpaque(object, try classId(scope, bindings, "byteStreamClass")) orelse return codedTypeError(scope, "ERR_INVALID_THIS", "Value of \"this\" must be of type ReadableStream");
    return @ptrCast(@alignCast(raw));
}
fn nativeReader(scope: *Scope, bindings: c.JSValue, object: c.JSValue) !*Reader {
    const raw = c.JS_GetOpaque(object, try classId(scope, bindings, "byteReaderClass")) orelse return error.NativeReadableReaderRequired;
    return @ptrCast(@alignCast(raw));
}
pub fn lockedNative(scope: *Scope, bindings: c.JSValue, object: c.JSValue) !bool {
    return !c.JS_IsUndefined((try nativeState(scope, bindings, object)).reader);
}
pub fn byteStreamNative(scope: *Scope, bindings: c.JSValue, object: c.JSValue) !bool {
    return (try nativeState(scope, bindings, object)).byte_source;
}
pub fn getReaderNative(scope: *Scope, bindings: c.JSValue, object: c.JSValue, options: c.JSValue) !c.JSValue {
    return getReader(scope, object, try nativeState(scope, bindings, object), options);
}
pub fn readNative(scope: *Scope, bindings: c.JSValue, object: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const owned = try nativeReader(scope, bindings, object);
    return read(scope, owned.stream, try nativeState(scope, bindings, owned.stream), owned, args);
}
pub fn closedNative(scope: *Scope, bindings: c.JSValue, object: c.JSValue) !c.JSValue {
    return (try nativeReader(scope, bindings, object)).closed.promise;
}
pub fn releaseReaderNative(scope: *Scope, bindings: c.JSValue, object: c.JSValue) !void {
    const owned = try nativeReader(scope, bindings, object);
    var roots = [_]c.JSValue{ owned.stream, object };
    _ = try operate(scope, object, &roots, .releaseLock, &.{});
}
pub fn byobViewNative(scope: *Scope, bindings: c.JSValue, controller: c.JSValue) !c.JSValue {
    const object = (try controllerNative(scope, bindings, controller)).stream_value;
    const self = try nativeState(scope, bindings, object);
    if (!self.byte_source) return c.pi_js_null();
    _ = try getRequest(scope, object, self);
    return if (c.JS_IsUndefined(self.request)) c.pi_js_null() else self.request_view;
}
pub fn respondWithNewViewNative(scope: *Scope, bindings: c.JSValue, controller: c.JSValue, chunk: c.JSValue) !void {
    const object = (try controllerNative(scope, bindings, controller)).stream_value;
    const self = try nativeState(scope, bindings, object);
    const request = try getRequest(scope, object, self);
    var roots = [_]c.JSValue{ object, c.pi_js_undefined() };
    _ = try operate(scope, request, &roots, .respondWithNewView, &.{chunk});
}
pub fn cancelNative(scope: *Scope, bindings: c.JSValue, object: c.JSValue, reason: c.JSValue) !c.JSValue {
    return cancel(scope, object, try nativeState(scope, bindings, object), reason);
}
fn controllerNative(scope: *Scope, bindings: c.JSValue, object: c.JSValue) !*Controller {
    const raw = c.JS_GetOpaque(object, try classId(scope, bindings, "byteControllerClass")) orelse return error.NativeByteStreamControllerRequired;
    return @ptrCast(@alignCast(raw));
}
pub fn enqueueNative(scope: *Scope, bindings: c.JSValue, controller: c.JSValue, chunk: c.JSValue) !void {
    var roots = [_]c.JSValue{ (try controllerNative(scope, bindings, controller)).stream_value, c.pi_js_undefined() };
    _ = try operate(scope, controller, &roots, .enqueue, &.{chunk});
}
pub fn errorNative(scope: *Scope, bindings: c.JSValue, controller: c.JSValue, reason: c.JSValue) !void {
    var roots = [_]c.JSValue{ (try controllerNative(scope, bindings, controller)).stream_value, c.pi_js_undefined() };
    _ = try operate(scope, controller, &roots, .errorValue, &.{reason});
}
fn failureClass(engine: *js.Engine, bindings: c.JSValue, key: [*:0]const u8) !c.JSClassID {
    // Failure retirement cannot append temporary roots to a host-allocated
    // Scope. These private binding properties contain only native class IDs.
    const value = try js.get(engine, bindings, key);
    defer engine.freeValue(value);
    var class: u32 = undefined;
    if (c.JS_ToUint32(engine.context, &class, value) < 0) return js.capture(engine);
    return class;
}
pub fn errorStreamAfterHostFailure(engine: *js.Engine, bindings: c.JSValue, object: c.JSValue, reason: c.JSValue) !void {
    const raw = c.JS_GetOpaque(object, try failureClass(engine, bindings, "byteStreamClass")) orelse return error.NativeReadableStreamRequired;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    // errored releases queues and rejects actual pending reads/closed using
    // direct JS capabilities. It does not create Scope-owned temporary roots.
    try errored(&scope, @ptrCast(@alignCast(raw)), reason);
}
pub fn errorControllerAfterHostFailure(engine: *js.Engine, bindings: c.JSValue, controller: c.JSValue, reason: c.JSValue) !void {
    const raw = c.JS_GetOpaque(controller, try failureClass(engine, bindings, "byteControllerClass")) orelse return error.NativeReadableControllerRequired;
    const owned: *Controller = @ptrCast(@alignCast(raw));
    try errorStreamAfterHostFailure(engine, bindings, owned.stream_value, reason);
}
pub fn respondZeroNative(scope: *Scope, bindings: c.JSValue, controller: c.JSValue) !void {
    const self = try nativeState(scope, bindings, (try controllerNative(scope, bindings, controller)).stream_value);
    if (self.status == .closed and self.pending.items.len != 0) try respond(scope, self, 0);
}
fn getReader(scope: *Scope, object: c.JSValue, self: *State, options: c.JSValue) !c.JSValue {
    const mode = try h.optional(scope, options, "mode");
    const kind: ReaderKind = if (c.JS_IsUndefined(mode)) .default else if (scope.equal(mode, try scope.text("byob"))) .byob else return typeError(scope, "Invalid reader mode");
    if (kind == .byob and !self.byte_source) return typeError(scope, "ReadableStream does not support BYOB readers");
    if (!c.JS_IsUndefined(self.reader)) return typeError(scope, "ReadableStream is locked");
    const shared = publicBindings(scope.engine, self.bindings);
    const reader_class = try classId(scope, self.bindings, "byteReaderClass");
    const result_object = try scope.own(try scope.engine.checked(if (shared) c.JS_NewObjectProtoClass(scope.engine.context, try scope.get(self.bindings, if (kind == .byob) "byobReaderPrototype" else "defaultReaderPrototype"), reader_class) else c.JS_NewObjectClass(scope.engine.context, reader_class)));
    const closed_pending = try closedPromise(scope, object);
    var attached = false;
    errdefer if (!attached) {
        scope.engine.freeValue(closed_pending.owner);
        scope.engine.freeValue(closed_pending.promise);
    };
    const owned = try scope.engine.gpa.create(Reader);
    owned.* = .{ .engine = scope.engine, .stream = c.JS_DupValue(scope.engine.context, object), .kind = kind, .closed = closed_pending };
    _ = c.JS_SetOpaque(result_object, owned);
    attached = true;
    var roots = [_]c.JSValue{ object, result_object };
    if (!shared) inline for (.{ .{ "read", Method.readerRead }, .{ "cancel", Method.readerCancel }, .{ "releaseLock", Method.releaseLock }, .{ "closed", Method.readerClosed } }) |entry| try function(scope, result_object, entry[0], entry[1], &roots, entry[1] == .readerClosed);
    self.reader = c.JS_DupValue(scope.engine.context, result_object);
    if (self.status == .closed) try async_value.settle(scope.engine, owned.closed.owner, false, c.pi_js_undefined());
    if (self.status == .errored) try async_value.settle(scope.engine, owned.closed.owner, true, self.stored_error);
    return result_object;
}
fn read(scope: *Scope, object: c.JSValue, self: *State, owned: *Reader, args: []const c.JSValue) !c.JSValue {
    if (owned.released) return typeError(scope, "Reader has been released");
    const pending = try async_value.create(scope.engine, object);
    defer scope.engine.freeValue(pending.owner);
    var offered = false;
    errdefer if (!offered) scope.engine.freeValue(pending.promise);
    self.disturbed = true;
    if (self.status == .errored) {
        try async_value.settle(scope.engine, pending.owner, true, self.stored_error);
        offered = true;
        return scope.own(pending.promise);
    }
    var into: Into = .{ .owner = c.JS_DupValue(scope.engine.context, pending.owner), .backing = c.pi_js_undefined(), .offset = 0, .capacity = self.auto_allocate, .minimum = 1, .width = 1, .array_type = c.JS_TYPED_ARRAY_UINT8, .kind = owned.kind };
    var admitted = false;
    errdefer if (!admitted) releaseInto(scope.engine, into);
    if (owned.kind == .byob) {
        var offset: usize = undefined;
        var length: usize = undefined;
        var width: usize = undefined;
        const original = try scope.own(try scope.engine.checked(c.JS_PiGetArrayBufferViewBuffer(scope.engine.context, h.arg(args, 0), &offset, &length, &width)));
        if (length == 0) return codedTypeError(scope, "ERR_INVALID_STATE", "Invalid state: View or Viewed ArrayBuffer is zero-length or detached");
        const minimum_value = try h.optional(scope, h.arg(args, 1), "min");
        const minimum = if (c.JS_IsUndefined(minimum_value)) 1 else try integer(scope, minimum_value, true);
        if (minimum > length / width) return typeError(scope, "BYOB minimum exceeds view capacity");
        into.offset = offset;
        into.capacity = length;
        into.minimum = minimum * width;
        into.width = width;
        into.array_type = c.JS_GetTypedArrayType(h.arg(args, 0));
        _ = c.JS_GetArrayBuffer(scope.engine.context, &into.backing_length, original);
        into.backing = c.JS_DupValue(scope.engine.context, try transferred(scope, self, original));
    } else if (self.auto_allocate != 0) {
        into.backing_length = self.auto_allocate;
        into.backing = try js.builtin(scope.engine, "ArrayBuffer", &.{numberValue(scope, self.auto_allocate)});
    }
    try self.pending.append(scope.engine.gpa, into);
    admitted = true;
    if (self.status == .closed) {
        try commit(scope, self, true);
    } else {
        try copyQueue(scope, self);
        try pull(scope, object, self);
    }
    offered = true;
    return scope.own(pending.promise);
}
fn getRequest(scope: *Scope, object: c.JSValue, self: *State) !c.JSValue {
    if (!c.JS_IsUndefined(self.request)) return self.request;
    if (self.pending.items.len == 0 or self.pending.items[0].capacity == 0) return c.pi_js_null();
    invalidate(self);
    const into = self.pending.items[0];
    self.request_view = c.JS_DupValue(scope.engine.context, try view(scope, into.backing, into.offset + into.filled, into.capacity - into.filled, c.JS_TYPED_ARRAY_UINT8, 1));
    const shared = publicBindings(scope.engine, self.bindings);
    const request = if (shared) try scope.own(try scope.engine.checked(c.JS_NewObjectProtoClass(scope.engine.context, try scope.get(self.bindings, "byobRequestPrototype"), try classId(scope, self.bindings, "byteRequestClass")))) else try scope.object();
    if (shared) {
        const owned = try scope.engine.gpa.create(Controller);
        owned.* = .{ .engine = scope.engine, .stream_value = c.JS_DupValue(scope.engine.context, object) };
        _ = c.JS_SetOpaque(request, owned);
    }
    var roots = [_]c.JSValue{ object, c.pi_js_undefined() };
    if (!shared) inline for (.{ .{ "view", Method.requestView }, .{ "respond", Method.respond }, .{ "respondWithNewView", Method.respondWithNewView } }) |entry| try function(scope, request, entry[0], entry[1], &roots, entry[1] == .requestView);
    self.request = c.JS_DupValue(scope.engine.context, request);
    return request;
}
fn respond(scope: *Scope, self: *State, count: usize) !void {
    if (self.pending.items.len == 0) return typeError(scope, "BYOB request is invalidated");
    const into = &self.pending.items[0];
    if (self.status == .readable and count == 0) return codedTypeError(scope, "ERR_INVALID_ARG_VALUE", "The argument 'bytesWritten' is invalid. Received 0");
    if (count > into.capacity - into.filled or (self.status == .closed and count != 0)) return typeError(scope, "Invalid BYOB response count");
    const next = try transferred(scope, self, into.backing);
    scope.engine.freeValue(into.backing);
    into.backing = c.JS_DupValue(scope.engine.context, next);
    invalidate(self);
    into.filled += count;
    if (self.status == .closed) {
        if (into.filled % into.width != 0) return typeError(scope, "Partial BYOB element at end of stream");
        while (self.pending.items.len != 0) try commit(scope, self, true);
    } else if (into.kind == .none) {
        try commit(scope, self, false);
    } else if (into.filled >= into.minimum) {
        const remainder = into.filled % into.width;
        if (remainder != 0) {
            try queueClone(scope, self, into.backing, into.offset + into.filled - remainder, remainder);
            into.filled -= remainder;
        }
        try commit(scope, self, false);
    }
    try copyQueue(scope, self);
}
fn cancel(scope: *Scope, object: c.JSValue, self: *State, reason: c.JSValue) !c.JSValue {
    self.disturbed = true;
    if (self.status == .closed) return h.resolved(scope, c.pi_js_undefined());
    if (self.status == .errored) return h.throw(scope, self.stored_error);
    invalidate(self);
    clearQueue(self);
    while (self.pending.items.len != 0) {
        const into = self.pending.orderedRemove(0);
        defer releaseInto(scope.engine, into);
        // Cancellation closes read-into requests with undefined; an EOF
        // respond(0) instead returns an empty view of the requested type.
        if (into.kind != .none and !into.read_settled) try async_value.settle(scope.engine, into.owner, false, try result(scope, c.pi_js_undefined(), true));
    }
    try closeNow(scope, self);
    const pending = try async_value.create(scope.engine, object);
    defer scope.engine.freeValue(pending.owner);
    var offered = false;
    errdefer if (!offered) scope.engine.freeValue(pending.promise);
    const returned = if (c.JS_IsUndefined(self.cancel)) c.pi_js_undefined() else try scope.call(self.cancel, self.source, &.{reason});
    try awaitAlgorithm(scope, object, returned, pending.owner, .cancel);
    offered = true;
    return scope.own(pending.promise);
}
fn enqueueValue(scope: *Scope, self: *State, chunk: c.JSValue) !void {
    while (self.pending.items.len != 0 and self.pending.items[0].kind == .none) releaseInto(scope.engine, self.pending.orderedRemove(0));
    if (self.pending.items.len != 0) {
        const into = self.pending.items[0];
        try async_value.settle(scope.engine, into.owner, false, try result(scope, chunk, false));
        releaseInto(scope.engine, self.pending.orderedRemove(0));
        return;
    }
    const size_value = if (c.JS_IsUndefined(self.size_algorithm)) c.JS_NewInt32(scope.engine.context, 1) else try scope.call(self.size_algorithm, c.pi_js_undefined(), &.{chunk});
    var size: f64 = undefined;
    if (c.JS_ToFloat64(scope.engine.context, &size, size_value) < 0) return js.capture(scope.engine);
    if (!std.math.isFinite(size) or size < 0) {
        const text = try @import("node_events.zig").description(scope.engine, size_value);
        defer scope.engine.gpa.free(text);
        const message = try std.fmt.allocPrint(scope.engine.gpa, "The argument 'size' is invalid. Received {s}", .{text});
        defer scope.engine.gpa.free(message);
        return @import("node_events.zig").codedError(scope.engine, "RangeError", "ERR_INVALID_ARG_VALUE", message);
    }
    const retained = c.JS_DupValue(scope.engine.context, chunk);
    errdefer scope.engine.freeValue(retained);
    try self.value_queue.append(scope.engine.gpa, .{ .value = retained, .size = size });
    self.queue_total_size += size;
}
fn operate(scope: *Scope, receiver: c.JSValue, roots: [*c]c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    const object = roots[0];
    const self = stream(object);
    const first = h.arg(args, 0);
    switch (method) {
        .readerRead, .readerCancel, .releaseLock, .readerClosed => {
            if (!scope.equal(receiver, roots[1])) return typeError(scope, "Invalid ReadableStream reader receiver");
            const owned = reader(roots[1]);
            if (method == .readerClosed) return owned.closed.promise;
            if (method == .readerRead) return read(scope, object, self, owned, args);
            if (method == .readerCancel) {
                if (owned.released) return typeError(scope, "Reader has been released");
                return cancel(scope, object, self, first);
            }
            if (owned.released) return c.pi_js_undefined();
            const reason = try scope.own(try js.builtin(scope.engine, "TypeError", &.{try scope.text("Invalid state: Releasing reader")}));
            try scope.put(reason, "code", try scope.text("ERR_INVALID_STATE"));
            // The Source controller retains its current BYOB request and the
            // leading pull-into buffer after reader release. A replacement
            // reader can consume bytes later written through that request.
            for (self.pending.items, 0..) |*into, index| {
                if (into.kind == .none) continue;
                try async_value.settle(scope.engine, into.owner, true, reason);
                scope.engine.freeValue(into.owner);
                into.owner = c.pi_js_undefined();
                into.kind = .none;
                if (index != 0) scope.engine.freeValue(into.backing);
            }
            if (self.pending.items.len > 1) self.pending.shrinkRetainingCapacity(1);
            if (!self.byte_source and self.pending.items.len != 0) releaseInto(scope.engine, self.pending.orderedRemove(0));
            if (self.status != .readable) {
                const replacement = try closedPromise(scope, object);
                scope.engine.freeValue(owned.closed.owner);
                scope.engine.freeValue(owned.closed.promise);
                owned.closed = replacement;
            }
            try async_value.settle(scope.engine, owned.closed.owner, true, reason);
            owned.released = true;
            scope.engine.freeValue(self.reader);
            self.reader = c.pi_js_undefined();
            return c.pi_js_undefined();
        },
        .requestView => return if (scope.equal(receiver, self.request)) self.request_view else c.pi_js_null(),
        .respond, .respondWithNewView => {
            if (!scope.equal(receiver, self.request)) return typeError(scope, "BYOB request is invalidated");
            var count: usize = undefined;
            if (method == .respond) {
                count = try integer(scope, first, false);
            } else {
                var offset: usize = undefined;
                var length: usize = undefined;
                var width: usize = undefined;
                const backing = try scope.own(try scope.engine.checked(c.JS_PiGetArrayBufferViewBuffer(scope.engine.context, first, &offset, &length, &width)));
                const into = self.pending.items[0];
                var new_length: usize = undefined;
                _ = c.JS_GetArrayBuffer(scope.engine.context, &new_length, backing);
                // The original destination may have been transferred into an
                // upstream BYOB reader. Validate against the retained original
                // full backing length, rather than its now-detached storage.
                if (offset != into.offset + into.filled or length > into.capacity - into.filled or into.backing_length != new_length) return typeError(scope, "Invalid replacement BYOB view");
                scope.engine.freeValue(self.pending.items[0].backing);
                self.pending.items[0].backing = c.JS_DupValue(scope.engine.context, backing);
                count = length;
            }
            try respond(scope, self, count);
            try pull(scope, object, self);
            return c.pi_js_undefined();
        },
        .enqueue, .close, .errorValue, .desiredSize, .byobRequest => {
            if (!scope.equal(receiver, self.controller)) return typeError(scope, "Invalid byte stream controller receiver");
            if (method == .byobRequest) return getRequest(scope, object, self);
            if (method == .desiredSize) return if (self.status == .errored) c.pi_js_null() else c.JS_NewFloat64(scope.engine.context, if (self.status == .closed) 0 else self.high_water_mark - queuedSize(self));
            if (method == .errorValue) {
                try errored(scope, self, first);
                return c.pi_js_undefined();
            }
            if (self.status != .readable or self.close_requested) return typeError(scope, "ReadableStream controller is already closed");
            if (method == .close) {
                self.close_requested = true;
                if ((self.byte_source and self.queue_bytes == 0) or (!self.byte_source and self.value_queue.items.len == 0)) try closeNow(scope, self);
                return c.pi_js_undefined();
            }
            if (!self.byte_source) {
                enqueueValue(scope, self, first) catch |err| {
                    const reason = async_value.reason(scope.engine, err);
                    defer scope.engine.freeValue(reason);
                    try errored(scope, self, reason);
                    return h.throw(scope, reason);
                };
                try pull(scope, object, self);
                return c.pi_js_undefined();
            }
            var offset: usize = undefined;
            var length: usize = undefined;
            var width: usize = undefined;
            const original = try scope.own(try scope.engine.checked(c.JS_PiGetArrayBufferViewBuffer(scope.engine.context, first, &offset, &length, &width)));
            if (length == 0) return typeError(scope, "Byte stream chunks must be nonempty");
            const backing = try transferred(scope, self, original);
            if (self.pending.items.len != 0 and self.pending.items[0].capacity != 0) {
                const destination = try transferred(scope, self, self.pending.items[0].backing);
                scope.engine.freeValue(self.pending.items[0].backing);
                self.pending.items[0].backing = c.JS_DupValue(scope.engine.context, destination);
                invalidate(self);
                if (self.pending.items[0].kind == .none) try commit(scope, self, false);
            }
            try queueChunk(scope, self, backing, offset, length, false);
            try copyQueue(scope, self);
            try pull(scope, object, self);
            return c.pi_js_undefined();
        },
        .privateCancel => return cancel(scope, object, self, first),
        else => {
            if (!scope.equal(receiver, object)) return typeError(scope, "Invalid ReadableStream receiver");
            if (method == .locked) return c.pi_js_bool(scope.engine.context, @intFromBool(!c.JS_IsUndefined(self.reader)));
            if (method == .getReader) return getReader(scope, object, self, first);
            if (!c.JS_IsUndefined(self.reader)) return typeError(scope, "ReadableStream is locked");
            return cancel(scope, object, self, first);
        },
    }
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const method: Method = @enumFromInt(raw);
    const returned = operate(&scope, receiver, roots, method, if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| {
        if (method == .readerRead or method == .readerCancel or method == .cancel or method == .privateCancel) return @import("native_durable.zig").rejectedPromise(engine, err);
        return @import("native_durable.zig").reject(engine, err);
    };
    return c.JS_DupValue(engine.context, returned);
}
fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, constants: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bindings = constants[0];
    const public_binding = publicBindings(engine, bindings);
    const provided = h.arg(args, 0);
    const source = if (c.JS_IsUndefined(provided)) try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()))) else provided;
    if (!c.JS_IsObject(source)) return typeError(&scope, "The source must be an object");
    const strategy = h.arg(args, 1);
    if (!h.nullish(strategy) and !c.JS_IsObject(strategy)) return typeError(&scope, "The strategy must be an object");
    // Source requires strategy getters before the underlying source's type.
    const size_value = try h.optional(&scope, strategy, "size");
    const high_value = try h.optional(&scope, strategy, "highWaterMark");
    const type_value = try scope.get(source, "type");
    const byte_source = scope.equal(try scope.stringify(type_value), try scope.text("bytes"));
    if (!byte_source and (!public_binding or !c.JS_IsUndefined(type_value))) return typeError(&scope, "Invalid readable stream source type");
    if (byte_source and !c.JS_IsUndefined(size_value)) return typeError(&scope, "Byte streams do not accept a size algorithm");
    if (!byte_source and !c.JS_IsUndefined(size_value) and !c.JS_IsFunction(engine.context, size_value)) return typeError(&scope, "The strategy size algorithm must be callable");
    var high: f64 = if (byte_source) 0 else 1;
    if (!c.JS_IsUndefined(high_value) and c.JS_ToFloat64(engine.context, &high, high_value) < 0) return js.capture(engine);
    if (std.math.isNan(high) or high < 0) return typeError(&scope, "Invalid stream highWaterMark");
    const auto_value = if (byte_source) try scope.get(source, "autoAllocateChunkSize") else c.pi_js_undefined();
    const auto_allocate = if (c.JS_IsUndefined(auto_value)) 0 else try integer(&scope, auto_value, true);
    const prototype = try scope.get(target, "prototype");
    const object = try scope.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, prototype, try classId(&scope, bindings, "byteStreamClass"))));
    const self = try engine.gpa.create(State);
    self.* = .{ .engine = engine, .bindings = c.JS_DupValue(engine.context, bindings), .source = c.JS_DupValue(engine.context, source), .pull = c.pi_js_undefined(), .cancel = c.pi_js_undefined(), .controller = c.pi_js_undefined(), .reader = c.pi_js_undefined(), .request = c.pi_js_undefined(), .request_view = c.pi_js_undefined(), .stored_error = c.pi_js_undefined(), .size_algorithm = c.JS_DupValue(engine.context, size_value), .byte_source = byte_source, .auto_allocate = auto_allocate, .high_water_mark = high };
    _ = c.JS_SetOpaque(object, self);
    const controller_class = try classId(&scope, bindings, "byteControllerClass");
    const controller = try scope.own(try engine.checked(if (public_binding) c.JS_NewObjectProtoClass(engine.context, try scope.get(bindings, if (byte_source) "byteControllerPrototype" else "defaultControllerPrototype"), controller_class) else c.JS_NewObjectClass(engine.context, controller_class)));
    const controller_owner = try engine.gpa.create(Controller);
    controller_owner.* = .{ .engine = engine, .stream_value = c.JS_DupValue(engine.context, object) };
    _ = c.JS_SetOpaque(controller, controller_owner);
    self.controller = c.JS_DupValue(engine.context, controller);
    const start = try scope.get(source, "start");
    const pull_value = try scope.get(source, "pull");
    const cancel_value = try scope.get(source, "cancel");
    self.pull = c.JS_DupValue(engine.context, if (scope.truthy(pull_value)) pull_value else c.pi_js_undefined());
    self.cancel = c.JS_DupValue(engine.context, if (scope.truthy(cancel_value)) cancel_value else c.pi_js_undefined());
    if ((!c.JS_IsUndefined(self.pull) and !c.JS_IsFunction(engine.context, self.pull)) or (!c.JS_IsUndefined(self.cancel) and !c.JS_IsFunction(engine.context, self.cancel))) return typeError(&scope, "Byte source algorithms must be callable");
    var roots = [_]c.JSValue{ object, c.pi_js_undefined() };
    if (!public_binding) inline for (.{ .{ "getReader", Method.getReader }, .{ "cancel", Method.cancel }, .{ "locked", Method.locked } }) |entry| try function(&scope, object, entry[0], entry[1], &roots, entry[1] == .locked);
    inline for (.{ .{ "enqueue", Method.enqueue }, .{ "close", Method.close }, .{ "error", Method.errorValue }, .{ "desiredSize", Method.desiredSize }, .{ "byobRequest", Method.byobRequest } }) |entry| {
        if (!public_binding and (byte_source or entry[1] != .byobRequest)) try function(&scope, controller, entry[0], entry[1], &roots, entry[1] == .desiredSize or entry[1] == .byobRequest);
    }
    const pending = if (!scope.truthy(start)) c.pi_js_undefined() else try scope.call(start, source, &.{controller});
    try awaitAlgorithm(&scope, object, pending, c.pi_js_undefined(), .start);
    return c.JS_DupValue(engine.context, object);
}
fn privateCancel(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    if (argc < 1) return c.JS_ThrowTypeError(context, "Missing native stream");
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const class = classId(&scope, roots[0], "byteStreamClass") catch |err| return @import("native_durable.zig").reject(engine, err);
    const raw = c.JS_GetOpaque2(context, argv[0], class) orelse return c.JS_Throw(context, c.JS_GetException(context));
    const self: *State = @ptrCast(@alignCast(raw));
    const returned = cancel(&scope, argv[0], self, if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| return @import("native_durable.zig").rejectedPromise(engine, err);
    return c.JS_DupValue(context, returned);
}
const PublicGroup = enum(c_int) { defaultReader, byobReader, defaultController, byteController, request };
fn publicName(group: PublicGroup) [:0]const u8 {
    return switch (group) {
        .defaultReader => "ReadableStreamDefaultReader",
        .byobReader => "ReadableStreamBYOBReader",
        .defaultController => "ReadableStreamDefaultController",
        .byteController => "ReadableByteStreamController",
        .request => "ReadableStreamBYOBRequest",
    };
}
fn invalidPublicReceiver(scope: *Scope, group: PublicGroup) anyerror {
    const message = std.fmt.allocPrint(scope.engine.gpa, "Value of \"this\" must be of type {s}", .{publicName(group)}) catch return error.OutOfMemory;
    defer scope.engine.gpa.free(message);
    return codedTypeError(scope, "ERR_INVALID_THIS", message);
}
fn publicOperate(scope: *Scope, receiver: c.JSValue, bindings: c.JSValue, group: PublicGroup, method: Method, args: []const c.JSValue) !c.JSValue {
    const class = try classId(scope, bindings, switch (group) {
        .defaultReader, .byobReader => "byteReaderClass",
        .defaultController, .byteController => "byteControllerClass",
        .request => "byteRequestClass",
    });
    const raw = c.JS_GetOpaque(receiver, class) orelse return invalidPublicReceiver(scope, group);
    const object = switch (group) {
        .defaultReader, .byobReader => blk: {
            const owned: *Reader = @ptrCast(@alignCast(raw));
            if ((owned.kind == .byob) != (group == .byobReader)) return invalidPublicReceiver(scope, group);
            break :blk owned.stream;
        },
        else => @as(*Controller, @ptrCast(@alignCast(raw))).stream_value,
    };
    if (group == .defaultController or group == .byteController) {
        if ((try nativeState(scope, bindings, object)).byte_source != (group == .byteController)) return invalidPublicReceiver(scope, group);
    }
    var roots = [_]c.JSValue{ object, receiver };
    return operate(scope, receiver, &roots, method, args);
}
fn publicDispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const method: Method = @enumFromInt(@mod(raw, 100));
    const group: PublicGroup = @enumFromInt(@divTrunc(raw, 100));
    const returned = publicOperate(&scope, receiver, roots[0], group, method, if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| {
        if (method == .readerRead or method == .readerCancel or method == .readerClosed) return @import("native_durable.zig").rejectedPromise(engine, err);
        return @import("native_durable.zig").reject(engine, err);
    };
    return c.JS_DupValue(context, returned);
}
fn publicFunction(scope: *Scope, bindings: c.JSValue, prototype: c.JSValue, group: PublicGroup, name: [:0]const u8, method: Method, length: c_int, getter: bool) !void {
    var roots = [_]c.JSValue{bindings};
    const function_name = if (getter) try std.fmt.allocPrintSentinel(scope.engine.gpa, "get {s}", .{name}, 0) else null;
    defer if (function_name) |allocated| scope.engine.gpa.free(allocated);
    const callback = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, publicDispatch, if (function_name) |allocated| allocated.ptr else name.ptr, length, @intFromEnum(group) * 100 + @intFromEnum(method), roots.len, &roots)));
    if (!getter) {
        if (c.JS_DefinePropertyValueStr(scope.engine.context, prototype, name.ptr, c.JS_DupValue(scope.engine.context, callback), c.JS_PROP_C_W_E) < 0) return js.capture(scope.engine);
        return;
    }
    const atom = c.JS_NewAtom(scope.engine.context, name.ptr);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DefinePropertyGetSet(scope.engine.context, prototype, atom, c.JS_DupValue(scope.engine.context, callback), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(scope.engine);
}
fn constructReader(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, constants: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.get(target, "prototype");
    const stream_value = h.arg(args, 0);
    if (!try isReadableStream(&scope, constants[0], stream_value)) return codedTypeError(&scope, "ERR_INVALID_ARG_TYPE", "The \"stream\" argument must be an instance of ReadableStream");
    const options = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    if (scope.truthy(constants[1])) try scope.put(options, "mode", try scope.text("byob"));
    const object = try getReaderNative(&scope, constants[0], stream_value, options);
    if (c.JS_IsObject(prototype) and c.JS_SetPrototype(engine.context, object, prototype) < 0) return js.capture(engine);
    return c.JS_DupValue(engine.context, object);
}
fn illegalConstruct(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return @import("node_events.zig").codedError(engine, "TypeError", "ERR_ILLEGAL_CONSTRUCTOR", "Illegal constructor");
}
/// Install shared public prototypes over real private state. Private FileHandle
/// bindings retain their already-qualified instance methods and ownership.
pub fn preparePublicGraph(scope: *Scope, bindings: c.JSValue) !void {
    var request_class: c.JSClassID = 0;
    _ = c.JS_NewClassID(scope.engine.runtime, &request_class);
    const definition: c.JSClassDef = .{ .class_name = "ReadableStreamBYOBRequest", .finalizer = controllerFinalize, .gc_mark = controllerMark };
    if (c.JS_NewClass(scope.engine.runtime, request_class, &definition) < 0) return error.OutOfMemory;
    try scope.put(bindings, "byteRequestClass", c.JS_NewUint32(scope.engine.context, request_class));
    const global = try scope.own(c.JS_GetGlobalObject(scope.engine.context));
    const tag = c.JS_ValueToAtom(scope.engine.context, try scope.get(try scope.global("Symbol"), "toStringTag"));
    defer c.JS_FreeAtom(scope.engine.context, tag);
    inline for ([_]PublicGroup{ .defaultReader, .byobReader, .defaultController, .byteController, .request }) |group| {
        const prototype = try scope.object();
        const key = switch (group) {
            .defaultReader => "defaultReaderPrototype",
            .byobReader => "byobReaderPrototype",
            .defaultController => "defaultControllerPrototype",
            .byteController => "byteControllerPrototype",
            .request => "byobRequestPrototype",
        };
        try scope.put(bindings, key, prototype);
        const is_reader = group == .defaultReader or group == .byobReader;
        const constructor = try scope.own(try @import("native_class.zig").constructor(scope.engine, publicName(group), if (is_reader) 1 else 0, prototype, if (is_reader) constructReader else illegalConstruct, &.{ bindings, c.pi_js_bool(scope.engine.context, @intFromBool(group == .byobReader)) }));
        try scope.put(global, publicName(group).ptr, constructor);
        if (c.JS_DefinePropertyValue(scope.engine.context, prototype, tag, c.JS_DupValue(scope.engine.context, try scope.text(publicName(group))), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(scope.engine);
        if (is_reader) {
            try publicFunction(scope, bindings, prototype, group, "read", .readerRead, if (group == .byobReader) 1 else 0, false);
            try publicFunction(scope, bindings, prototype, group, "releaseLock", .releaseLock, 0, false);
            try publicFunction(scope, bindings, prototype, group, "closed", .readerClosed, 0, true);
            try publicFunction(scope, bindings, prototype, group, "cancel", .readerCancel, 0, false);
        } else if (group == .request) {
            try publicFunction(scope, bindings, prototype, group, "view", .requestView, 0, true);
            try publicFunction(scope, bindings, prototype, group, "respond", .respond, 1, false);
            try publicFunction(scope, bindings, prototype, group, "respondWithNewView", .respondWithNewView, 1, false);
        } else {
            if (group == .byteController) try publicFunction(scope, bindings, prototype, group, "byobRequest", .byobRequest, 0, true);
            try publicFunction(scope, bindings, prototype, group, "desiredSize", .desiredSize, 0, true);
            try publicFunction(scope, bindings, prototype, group, "close", .close, 0, false);
            try publicFunction(scope, bindings, prototype, group, "enqueue", .enqueue, if (group == .byteController) 1 else 0, false);
            try publicFunction(scope, bindings, prototype, group, "error", .errorValue, 0, false);
        }
    }
}
/// Private FileHandle integration only. No global or node:stream export is
/// installed until the complete stream graph and real Source cases qualify.
pub fn prepare(scope: *Scope, bindings: c.JSValue) !void {
    if (c.JS_IsFunction(scope.engine.context, try scope.get(bindings, "fileHandleReadableStream")) and c.JS_IsFunction(scope.engine.context, try scope.get(bindings, "fileHandleReadableStreamCancel"))) return;
    var stream_class: c.JSClassID = 0;
    var reader_class: c.JSClassID = 0;
    var controller_class: c.JSClassID = 0;
    if (scope.engine.native_readable_stream_classes) |classes| {
        stream_class = classes[0];
        reader_class = classes[1];
        controller_class = classes[2];
    } else {
        _ = c.JS_NewClassID(scope.engine.runtime, &stream_class);
        _ = c.JS_NewClassID(scope.engine.runtime, &reader_class);
        _ = c.JS_NewClassID(scope.engine.runtime, &controller_class);
        const definition: c.JSClassDef = .{ .class_name = "ReadableStream", .finalizer = finalize, .gc_mark = mark };
        const reader_definition: c.JSClassDef = .{ .class_name = "ReadableStreamReader", .finalizer = readerFinalize, .gc_mark = readerMark };
        const controller_definition: c.JSClassDef = .{ .class_name = "ReadableByteStreamController", .finalizer = controllerFinalize, .gc_mark = controllerMark };
        if (c.JS_NewClass(scope.engine.runtime, stream_class, &definition) < 0 or c.JS_NewClass(scope.engine.runtime, reader_class, &reader_definition) < 0 or c.JS_NewClass(scope.engine.runtime, controller_class, &controller_definition) < 0) return error.OutOfMemory;
        scope.engine.native_readable_stream_classes = .{ stream_class, reader_class, controller_class };
    }
    try scope.put(bindings, "byteStreamClass", c.JS_NewUint32(scope.engine.context, stream_class));
    try scope.put(bindings, "byteReaderClass", c.JS_NewUint32(scope.engine.context, reader_class));
    try scope.put(bindings, "byteControllerClass", c.JS_NewUint32(scope.engine.context, controller_class));
    const original = try scope.get(try scope.global("ArrayBuffer"), "prototype");
    try scope.put(bindings, "byteStreamTransfer", try scope.get(original, "transfer"));
    try scope.put(bindings, "byteStreamSlice", try scope.get(original, "slice"));
    const prototype = try scope.object();
    const constructor = try scope.own(try @import("native_class.zig").constructor(scope.engine, "ReadableStream", 0, prototype, construct, &.{bindings}));
    try scope.put(bindings, "fileHandleReadableStream", constructor);
    var roots = [_]c.JSValue{bindings};
    try scope.put(bindings, "fileHandleReadableStreamCancel", try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, privateCancel, "readableStreamCancel", 1, 0, roots.len, &roots))));
}
