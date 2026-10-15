//! Native stream composition. Source-only: byte core is qualified separately;
//! the complete public default/reader/prototype/pipe graph still needs gates.
const std = @import("std");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const core = @import("native_readable_byte_stream.zig");
const async_value = @import("native_agent_async.zig");
const c = js.c;
const Operation = enum(c_int) { pullBytes, pullIterator, cancelSource, teePull, teeCancel1, teeCancel2, getReader, cancel, locked, tee };
const Stage = enum(c_int) { iteratorNext, eof, iteratorReturn, teeRead, teeCancelled };
fn bindings(engine: *js.Engine) !c.JSValue {
    return engine.native_readable_stream_bindings orelse error.NativeWebReadableStreamUnavailable;
}
fn nullish(value: c.JSValue) bool {
    return c.JS_IsUndefined(value) or c.JS_IsNull(value);
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn flagged(scope: *Scope, data: c.JSValue, key: [*:0]const u8) !bool {
    return scope.truthy(try scope.get(data, key));
}
fn flag(scope: *Scope, data: c.JSValue, key: [*:0]const u8) !void {
    try scope.put(data, key, c.pi_js_bool(scope.engine.context, 1));
}
fn callback(scope: *Scope, data: c.JSValue, name: [*:0]const u8, operation: Operation, length: c_int) !c.JSValue {
    var roots = [_]c.JSValue{data};
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, dispatch, name, length, @intFromEnum(operation), roots.len, &roots)));
}
fn create(scope: *Scope, retained: c.JSValue, source: c.JSValue) !c.JSValue {
    var args = [_]c.JSValue{source};
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(retained, "fileHandleReadableStream"), args.len, &args)));
}
fn copyBytes(scope: *Scope, input: c.JSValue) !c.JSValue {
    var offset: usize = undefined;
    var length: usize = undefined;
    var width: usize = undefined;
    const backing = try scope.own(try scope.engine.checked(c.JS_PiGetArrayBufferViewBuffer(scope.engine.context, input, &offset, &length, &width)));
    var total: usize = undefined;
    const bytes = c.JS_GetArrayBuffer(scope.engine.context, &total, backing);
    if (bytes == null and total != 0) return js.capture(scope.engine);
    if (offset > total or length > total - offset) return error.NativeStreamChunkBounds;
    const copied = try scope.own(try scope.engine.checked(c.JS_NewArrayBufferCopy(scope.engine.context, if (length == 0) null else bytes + offset, length)));
    var args = [_]c.JSValue{copied};
    return scope.own(try scope.engine.checked(c.JS_NewTypedArray(scope.engine.context, args.len, &args, c.JS_TYPED_ARRAY_UINT8)));
}
fn sourceStart(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, branch: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    scope.put(roots[0], if (branch == 1) "controller1" else if (branch == 2) "controller2" else "controller", if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| return @import("native_durable.zig").reject(engine, err);
    return c.pi_js_undefined();
}
fn startFunction(scope: *Scope, data: c.JSValue, branch: c_int) !c.JSValue {
    var roots = [_]c.JSValue{data};
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, sourceStart, "start", 1, branch, roots.len, &roots)));
}
fn byteSource(scope: *Scope, data: c.JSValue, pull: Operation, cancel: Operation, branch: c_int) !c.JSValue {
    const source = try scope.object();
    if (branch == 0 or try flagged(scope, data, "byteSource")) try scope.put(source, "type", try scope.text("bytes"));
    try scope.put(source, "start", try startFunction(scope, data, branch));
    try scope.put(source, "pull", try callback(scope, data, "pull", pull, 1));
    try scope.put(source, "cancel", try callback(scope, data, "cancel", cancel, 1));
    return source;
}
fn finish(scope: *Scope, data: c.JSValue, owner: c.JSValue) !void {
    try core.closeController(scope, try bindings(scope.engine), try scope.get(data, "controller"));
    // A real later microtask responds to any retained BYOB descriptor. Closing
    // itself already settles default reads and the reader.closed promise.
    try async_value.wait(continued, scope.engine, owner, c.pi_js_undefined(), @intFromEnum(Stage.eof));
}
fn next(scope: *Scope, data: c.JSValue, owner: c.JSValue) !void {
    const pending = try scope.call(try scope.get(data, "next"), try scope.get(data, "iterator"), &.{});
    try async_value.wait(continued, scope.engine, owner, pending, @intFromEnum(Stage.iteratorNext));
}
fn continueValue(scope: *Scope, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: Stage) !void {
    const data = try scope.get(owner, "agent");
    if (stage == .teeRead or stage == .teeCancelled) return teeContinued(scope, data, owner, value, rejected, stage);
    if (rejected) return async_value.settle(scope.engine, owner, true, value);
    if (stage == .eof) {
        try core.respondZeroNative(scope, try bindings(scope.engine), try scope.get(data, "controller"));
        return async_value.settle(scope.engine, owner, false, c.pi_js_undefined());
    }
    if (stage == .iteratorReturn) {
        if (!c.JS_IsObject(value)) return error.NativeAsyncIteratorReturnNotObject;
        return async_value.settle(scope.engine, owner, false, c.pi_js_undefined());
    }
    if (try flagged(scope, data, "cancelled")) return async_value.settle(scope.engine, owner, false, c.pi_js_undefined());
    if (!c.JS_IsObject(value)) return error.NativeAsyncIteratorResultNotObject;
    if (scope.truthy(try scope.get(value, "done"))) {
        try flag(scope, data, "done");
        return finish(scope, data, owner);
    }
    const copied = try copyBytes(scope, try scope.get(value, "value"));
    var offset: usize = undefined;
    var length: usize = undefined;
    var width: usize = undefined;
    _ = try scope.own(try scope.engine.checked(c.JS_PiGetArrayBufferViewBuffer(scope.engine.context, copied, &offset, &length, &width)));
    if (length == 0) return next(scope, data, owner);
    try core.enqueueNative(scope, try bindings(scope.engine), try scope.get(data, "controller"), copied);
    try async_value.settle(scope.engine, owner, false, c.pi_js_undefined());
}
fn continued(engine: *js.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    continueValue(&scope, owner, value, rejected, @enumFromInt(raw)) catch |err| {
        if (@as(Stage, @enumFromInt(raw)) == .teeRead) {
            const reason = async_value.reason(engine, err);
            defer engine.freeValue(reason);
            try teeError(&scope, try scope.get(owner, "agent"), reason);
        }
        try async_value.rejectError(engine, owner, err);
    };
}
fn begin(scope: *Scope, data: c.JSValue, owner: c.JSValue, args: []const c.JSValue, operation: Operation) !void {
    if (operation == .cancelSource) {
        try flag(scope, data, "cancelled");
        const iterator = try scope.get(data, "iterator");
        if (nullish(iterator)) return async_value.settle(scope.engine, owner, false, c.pi_js_undefined());
        const return_method = try scope.get(iterator, "return");
        if (nullish(return_method)) return async_value.settle(scope.engine, owner, false, c.pi_js_undefined());
        const pending = try scope.call(return_method, iterator, &.{argument(args, 0)});
        return async_value.wait(continued, scope.engine, owner, pending, @intFromEnum(Stage.iteratorReturn));
    }
    if (try flagged(scope, data, "cancelled")) return async_value.settle(scope.engine, owner, false, c.pi_js_undefined());
    if (try flagged(scope, data, "done")) return finish(scope, data, owner);
    if (operation == .pullIterator) return next(scope, data, owner);
    const copied = try copyBytes(scope, try scope.get(data, "bytes"));
    var offset: usize = undefined;
    var length: usize = undefined;
    var width: usize = undefined;
    _ = try scope.own(try scope.engine.checked(c.JS_PiGetArrayBufferViewBuffer(scope.engine.context, copied, &offset, &length, &width)));
    try flag(scope, data, "done");
    if (length == 0) return finish(scope, data, owner);
    try core.enqueueNative(scope, try bindings(scope.engine), try scope.get(data, "controller"), copied);
    try async_value.settle(scope.engine, owner, false, c.pi_js_undefined());
}
fn asynchronous(scope: *Scope, data: c.JSValue, args: []const c.JSValue, operation: Operation) !c.JSValue {
    const pending = try async_value.create(scope.engine, data);
    defer scope.engine.freeValue(pending.owner);
    var offered = false;
    errdefer if (!offered) scope.engine.freeValue(pending.promise);
    begin(scope, data, pending.owner, args, operation) catch |err| try async_value.rejectError(scope.engine, pending.owner, err);
    offered = true;
    return scope.own(pending.promise);
}
fn teeError(scope: *Scope, data: c.JSValue, reason: c.JSValue) !void {
    if (try flagged(scope, data, "closed")) return;
    try flag(scope, data, "closed");
    if (!try flagged(scope, data, "cancelled1")) try core.errorNative(scope, try bindings(scope.engine), try scope.get(data, "controller1"), reason);
    if (!try flagged(scope, data, "cancelled2")) try core.errorNative(scope, try bindings(scope.engine), try scope.get(data, "controller2"), reason);
    try async_value.settle(scope.engine, try scope.get(data, "cancelOwner"), false, c.pi_js_undefined());
}
fn teeRead(scope: *Scope, data: c.JSValue) !void {
    if (try flagged(scope, data, "closed")) return;
    if (try flagged(scope, data, "reading")) return flag(scope, data, "readAgain");
    try flag(scope, data, "reading");
    const pending = try async_value.create(scope.engine, data);
    defer scope.engine.freeValue(pending.owner);
    defer scope.engine.freeValue(pending.promise);
    c.JS_PromiseMarkAsHandled(scope.engine.context, pending.promise);
    const reading = try core.readNative(scope, try bindings(scope.engine), try scope.get(data, "reader"), &.{});
    try async_value.wait(continued, scope.engine, pending.owner, reading, @intFromEnum(Stage.teeRead));
}
fn teeContinued(scope: *Scope, data: c.JSValue, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: Stage) !void {
    if (stage == .teeCancelled) {
        try async_value.settle(scope.engine, try scope.get(data, "cancelOwner"), rejected, if (rejected) value else c.pi_js_undefined());
        return async_value.settle(scope.engine, owner, false, c.pi_js_undefined());
    }
    try scope.put(data, "reading", c.pi_js_bool(scope.engine.context, 0));
    if (rejected) {
        try teeError(scope, data, value);
        return async_value.settle(scope.engine, owner, false, c.pi_js_undefined());
    }
    if (try flagged(scope, data, "closed")) return async_value.settle(scope.engine, owner, false, c.pi_js_undefined());
    if (scope.truthy(try scope.get(value, "done"))) {
        try flag(scope, data, "closed");
        inline for (.{ .{ "cancelled1", "controller1" }, .{ "cancelled2", "controller2" } }) |entry| if (!try flagged(scope, data, entry[0])) {
            const controller = try scope.get(data, entry[1]);
            try core.closeController(scope, try bindings(scope.engine), controller);
            if (try flagged(scope, data, "byteSource")) try core.respondZeroNative(scope, try bindings(scope.engine), controller);
        };
        try async_value.settle(scope.engine, try scope.get(data, "cancelOwner"), false, c.pi_js_undefined());
    } else {
        const chunk = try scope.get(value, "value");
        const first = !try flagged(scope, data, "cancelled1");
        const second = !try flagged(scope, data, "cancelled2");
        // Clone before either enqueue transfers the original backing store.
        const copied = if (first and second and try flagged(scope, data, "byteSource")) try copyBytes(scope, chunk) else chunk;
        if (first) try core.enqueueNative(scope, try bindings(scope.engine), try scope.get(data, "controller1"), chunk);
        if (second) try core.enqueueNative(scope, try bindings(scope.engine), try scope.get(data, "controller2"), copied);
        if (try flagged(scope, data, "readAgain")) {
            try scope.put(data, "readAgain", c.pi_js_bool(scope.engine.context, 0));
            try teeRead(scope, data);
        }
    }
    try async_value.settle(scope.engine, owner, false, c.pi_js_undefined());
}
fn teeClosed(engine: *js.Engine, owner: c.JSValue, reason: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) try teeError(&scope, try scope.get(owner, "agent"), reason);
    try async_value.settle(engine, owner, false, c.pi_js_undefined());
}
pub fn tee(engine: *js.Engine, stream_value: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const retained = try bindings(engine);
    const reader_value = try core.getReaderNative(&scope, retained, stream_value, c.pi_js_undefined());
    const data = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try scope.put(data, "byteSource", c.pi_js_bool(engine.context, @intFromBool(try core.byteStreamNative(&scope, retained, stream_value))));
    try scope.put(data, "reader", reader_value);
    try scope.put(data, "stream", stream_value);
    const cancel_pending = try async_value.create(engine, data);
    defer engine.freeValue(cancel_pending.owner);
    defer engine.freeValue(cancel_pending.promise);
    try scope.put(data, "cancelOwner", cancel_pending.owner);
    try scope.put(data, "cancelPromise", cancel_pending.promise);
    c.JS_PromiseMarkAsHandled(engine.context, cancel_pending.promise);
    const first = try create(&scope, retained, try byteSource(&scope, data, .teePull, .teeCancel1, 1));
    const second = try create(&scope, retained, try byteSource(&scope, data, .teePull, .teeCancel2, 2));
    const observer = try async_value.create(engine, data);
    defer engine.freeValue(observer.owner);
    defer engine.freeValue(observer.promise);
    c.JS_PromiseMarkAsHandled(engine.context, observer.promise);
    try async_value.wait(teeClosed, engine, observer.owner, try core.closedNative(&scope, retained, reader_value), 0);
    const result = try scope.array();
    try scope.index(result, 0, first);
    try scope.index(result, 1, second);
    return c.JS_DupValue(engine.context, result);
}
fn cancelTee(scope: *Scope, data: c.JSValue, reason: c.JSValue, second: bool) !c.JSValue {
    try flag(scope, data, if (second) "cancelled2" else "cancelled1");
    try scope.put(data, if (second) "reason2" else "reason1", reason);
    if (try flagged(scope, data, "cancelled1") and try flagged(scope, data, "cancelled2") and !try flagged(scope, data, "closed")) {
        try flag(scope, data, "closed");
        const reasons = try scope.array();
        try scope.index(reasons, 0, try scope.get(data, "reason1"));
        try scope.index(reasons, 1, try scope.get(data, "reason2"));
        const pending = try async_value.create(scope.engine, data);
        defer scope.engine.freeValue(pending.owner);
        defer scope.engine.freeValue(pending.promise);
        c.JS_PromiseMarkAsHandled(scope.engine.context, pending.promise);
        const cancelled = try core.cancelNative(scope, try bindings(scope.engine), try scope.get(data, "stream"), reasons);
        try async_value.wait(continued, scope.engine, pending.owner, cancelled, @intFromEnum(Stage.teeCancelled));
    }
    return scope.get(data, "cancelPromise");
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const operation: Operation = @enumFromInt(raw);
    const args = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    const returned = dispatchValue(&scope, receiver, roots[0], args, operation) catch |err| {
        if (operation == .getReader or operation == .locked or operation == .tee) return @import("native_durable.zig").reject(engine, err);
        return @import("native_durable.zig").rejectedPromise(engine, err);
    };
    return c.JS_DupValue(context, returned);
}
fn dispatchValue(scope: *Scope, receiver: c.JSValue, data: c.JSValue, args: []const c.JSValue, operation: Operation) !c.JSValue {
    switch (operation) {
        .getReader => return core.getReaderNative(scope, data, receiver, argument(args, 0)),
        .locked => return c.pi_js_bool(scope.engine.context, @intFromBool(try core.lockedNative(scope, data, receiver))),
        .cancel => {
            if (try core.lockedNative(scope, data, receiver)) return @import("node_events.zig").codedError(scope.engine, "TypeError", "ERR_INVALID_STATE", "Invalid state: ReadableStream is locked");
            return core.cancelNative(scope, data, receiver, argument(args, 0));
        },
        .tee => return scope.own(try tee(scope.engine, receiver)),
        .teePull => {
            try teeRead(scope, data);
            return scope.own(try @import("native_durable.zig").resolvedPromise(scope.engine, c.pi_js_undefined()));
        },
        .teeCancel1, .teeCancel2 => return cancelTee(scope, data, argument(args, 0), operation == .teeCancel2),
        else => return asynchronous(scope, data, args, operation),
    }
}
pub fn install(engine: *js.Engine) !void {
    if (engine.native_readable_stream_bindings != null) return;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const retained = try scope.object();
    try core.prepare(&scope, retained);
    try core.preparePublicGraph(&scope, retained);
    const constructor = try scope.get(retained, "fileHandleReadableStream");
    const prototype = try scope.get(constructor, "prototype");
    inline for (.{ .{ "getReader", Operation.getReader }, .{ "cancel", Operation.cancel }, .{ "tee", Operation.tee } }) |entry| {
        const function = try callback(&scope, retained, entry[0], entry[1], 0);
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, entry[0], c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(engine);
    }
    const locked = try callback(&scope, retained, "get locked", .locked, 0);
    const atom = c.JS_NewAtom(engine.context, "locked");
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, c.JS_DupValue(engine.context, locked), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(engine);
    const tag = c.JS_ValueToAtom(engine.context, try scope.get(try scope.global("Symbol"), "toStringTag"));
    defer c.JS_FreeAtom(engine.context, tag);
    if (c.JS_DefinePropertyValue(engine.context, prototype, tag, c.JS_DupValue(engine.context, try scope.text("ReadableStream")), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "ReadableStream", constructor);
    engine.native_readable_stream_bindings = c.JS_DupValue(engine.context, retained);
}
pub fn fromBytes(engine: *js.Engine, copied_bytes: c.JSValue) !c.JSValue {
    try install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const data = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try scope.put(data, "bytes", copied_bytes);
    return c.JS_DupValue(engine.context, try create(&scope, try bindings(engine), try byteSource(&scope, data, .pullBytes, .cancelSource, 0)));
}
pub fn fromAsyncIterator(engine: *js.Engine, supplied: c.JSValue) !c.JSValue {
    try install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const symbol = try scope.get(try scope.global("Symbol"), "asyncIterator");
    const method = try scope.own(try js.getKey(engine, supplied, symbol));
    const iterator = if (nullish(method)) supplied else try scope.call(method, supplied, &.{});
    const next_method = try scope.get(iterator, "next");
    if (!c.JS_IsFunction(engine.context, next_method)) return error.NativeAsyncIteratorNextRequired;
    const data = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try scope.put(data, "iterator", iterator);
    try scope.put(data, "next", next_method);
    return c.JS_DupValue(engine.context, try create(&scope, try bindings(engine), try byteSource(&scope, data, .pullIterator, .cancelSource, 0)));
}
pub fn isReadableStream(engine: *js.Engine, value: c.JSValue) !bool {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return if (engine.native_readable_stream_bindings) |retained| core.isReadableStream(&scope, retained, value) else false;
}
pub fn isDisturbed(engine: *js.Engine, value: c.JSValue) !bool {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return if (engine.native_readable_stream_bindings) |retained| core.isDisturbed(&scope, retained, value) else false;
}
pub fn isErrored(engine: *js.Engine, value: c.JSValue) !bool {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return if (engine.native_readable_stream_bindings) |retained| core.isErrored(&scope, retained, value) else false;
}
pub fn closeController(engine: *js.Engine, controller: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try core.closeController(&scope, try bindings(engine), controller);
}
