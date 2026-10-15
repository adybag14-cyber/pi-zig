//! Actual native Body extraction/consumption seam. Standard streams belong to
//! Env; byte collection belongs to the shared collector. No substitute stream.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const idl = @import("native_web_idl.zig");
const flow = @import("native_agent_async.zig");
const collector = @import("native_body_collect.zig");
const web = @import("native_headers_webidl.zig");
const form = @import("native_web_form_data.zig");
const mime_parser = @import("native_web_mime.zig");
const multipart = @import("native_web_multipart.zig");
const c = em.c;
const cache_key = "\x00native-web-Body";
pub const Streams = struct {
    bindings: c.JSValue,
    constructor: c.JSValue,
    is_disturbed: *const fn (*Scope, c.JSValue, c.JSValue) anyerror!bool,
    is_errored: *const fn (*Scope, c.JSValue, c.JSValue) anyerror!bool,
    close_controller: *const fn (*Scope, c.JSValue, c.JSValue) anyerror!void,
};
/// Fields returned by extract/clone belong to the caller's Scope. Facades must
/// duplicate/mark committed state and release their previous owned fields.
pub const Body = struct { stream: c.JSValue, source: c.JSValue, length: c.JSValue, content_type: c.JSValue };
pub const Clone = struct { original_stream: c.JSValue, copy: Body };
pub const Mode = enum(c_int) { bytes, array_buffer, text, json, blob, form_data };
const Root = struct { engine: *em.Engine, streams: Streams, encoder: c.JSValue, response_registry: c.JSValue };
fn rootOf(owner: c.JSValue) *Root {
    return @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)).?));
}
fn freeRoot(runtime: ?*c.JSRuntime, owner: c.JSValue) callconv(.c) void {
    const root: *Root = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    for ([_]c.JSValue{ root.streams.bindings, root.streams.constructor, root.encoder, root.response_registry }) |value| c.JS_FreeValueRT(runtime, value);
    root.engine.gpa.destroy(root);
}
fn markRoot(runtime: ?*c.JSRuntime, owner: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const root: *Root = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    for ([_]c.JSValue{ root.streams.bindings, root.streams.constructor, root.encoder, root.response_registry }) |value| c.JS_MarkValue(runtime, value, visit);
}
fn ownerOf(engine: *em.Engine) !c.JSValue {
    return engine.native_module_values.get(cache_key) orelse error.NativeWebReadableStreamUnavailable;
}
pub fn require(engine: *em.Engine) !void {
    _ = try ownerOf(engine);
}
pub fn install(engine: *em.Engine, streams: Streams) !void {
    if (engine.native_module_values.contains(cache_key)) return;
    if (!c.JS_IsFunction(engine.context, streams.constructor) or !c.JS_IsConstructor(engine.context, streams.constructor)) return error.NativeWebReadableStreamUnavailable;
    if (engine.text_encoder_class == 0) try @import("text_encoding.zig").install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Native Web Body Bindings", .finalizer = freeRoot, .gc_mark = markRoot };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const owner = try scope.own(try engine.checked(c.JS_NewObjectClass(engine.context, class)));
    const constructor = try scope.global("TextEncoder");
    const encoder = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null));
    var attached = false;
    errdefer if (!attached) engine.freeValue(encoder);
    const root = try engine.gpa.create(Root);
    root.* = .{ .engine = engine, .streams = streams, .encoder = encoder, .response_registry = c.pi_js_undefined() };
    root.streams.bindings = c.JS_DupValue(engine.context, streams.bindings);
    root.streams.constructor = c.JS_DupValue(engine.context, streams.constructor);
    _ = c.JS_SetOpaque(owner, root);
    attached = true;
    const cleanup = try scope.own(try @import("native_node_function.zig").createArrow(engine, "", 1, responseCollected, &.{owner}));
    var registry_args = [_]c.JSValue{cleanup};
    root.response_registry = try engine.checked(c.JS_CallConstructor(engine.context, try scope.global("FinalizationRegistry"), 1, &registry_args));
    try engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1);
    engine.native_module_values.putAssumeCapacity(cache_key, c.JS_DupValue(engine.context, owner));
}
pub fn disturbed(scope: *Scope, stream: c.JSValue) !bool {
    const root = rootOf(try ownerOf(scope.engine));
    return root.streams.is_disturbed(scope, root.streams.bindings, stream);
}
pub fn errored(scope: *Scope, stream: c.JSValue) !bool {
    const root = rootOf(try ownerOf(scope.engine));
    return root.streams.is_errored(scope, root.streams.bindings, stream);
}
pub fn streamConstructor(scope: *Scope) !c.JSValue {
    return scope.own(c.JS_DupValue(scope.engine.context, rootOf(try ownerOf(scope.engine)).streams.constructor));
}
pub fn closeController(scope: *Scope, controller: c.JSValue) !void {
    try require(scope.engine);
    scope.engine.native_exception_diagnostics_suppressed += 1;
    defer scope.engine.native_exception_diagnostics_suppressed -= 1;
    sourceClose(scope, controller) catch |err| {
        if (err != error.JavaScriptException) return err;
        const reason = try scope.own(c.JS_DupValue(scope.engine.context, scope.engine.captured_exception orelse return err));
        const message = try scope.get(reason, "message");
        const already_closed = scope.truthy(try scope.invoke(message, "includes", &.{try scope.text("Controller is already closed")})) or scope.truthy(try scope.invoke(message, "includes", &.{try scope.text("ReadableStream is already closed")}));
        if (!already_closed) return err;
        if (scope.engine.captured_exception) |captured| {
            scope.engine.captured_exception = null;
            scope.engine.freeValue(captured);
        }
    };
}
fn sourceClose(scope: *Scope, controller: c.JSValue) !void {
    _ = try scope.invoke(controller, "close", &.{});
    const request = try scope.get(controller, "byobRequest");
    if (!c.JS_IsNull(request) and !c.JS_IsUndefined(request)) _ = try scope.invoke(request, "respond", &.{c.JS_NewInt32(scope.engine.context, 0)});
}
fn responseCollected(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) anyerror!c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (args.len == 0) return c.pi_js_undefined();
    const stream = try scope.invoke(args[0], "deref", &.{});
    if (scope.truthy(stream) and !scope.truthy(try scope.get(stream, "locked"))) {
        const root = rootOf(captures[0]);
        if (!try root.streams.is_disturbed(&scope, root.streams.bindings, stream) and !try root.streams.is_errored(&scope, root.streams.bindings, stream)) {
            const canceled = try scope.invoke(stream, "cancel", &.{try scope.text("Response object has been garbage collected")});
            const ignore = try scope.own(try @import("native_node_function.zig").createArrow(engine, "noop", 0, idle, &.{}));
            _ = try scope.invoke(canceled, "catch", &.{ignore});
        }
    }
    return c.pi_js_undefined();
}
/// Actual bundled streamRegistry: only network/URL-present facade paths call
/// this. Weak registration retains neither the Response nor its stream target.
pub fn registerResponse(engine: *em.Engine, response: c.JSValue, stream: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const root = rootOf(try ownerOf(engine));
    var args = [_]c.JSValue{stream};
    const weak = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, try scope.global("WeakRef"), 1, &args)));
    _ = try scope.invoke(root.response_registry, "register", &.{ response, weak });
}
pub fn unusable(scope: *Scope, body: ?Body) !bool {
    const value = body orelse return false;
    return scope.truthy(try scope.get(value.stream, "locked")) or try disturbed(scope, value.stream);
}
fn fail(engine: *em.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
    return c.JS_ThrowInternalError(engine.context, "Native Web Body: %s", @as([*:0]const u8, @errorName(err)));
}
fn start(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.set(captures[0], "controller", if (args.len > 0) args[0] else c.pi_js_undefined());
    return c.pi_js_undefined();
}
// These deliberately empty methods are the actual extractBody underlying
// source methods from bundled Undici; the byte stream owns queue/backpressure.
fn idle(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
    return c.pi_js_undefined();
}
fn closeJob(context: ?*c.JSContext, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    _ = captures[0];
    closeController(&scope, captures[1]) catch |err| return fail(engine, err);
    return c.pi_js_undefined();
}
fn byteStream(scope: *Scope) !struct { stream: c.JSValue, controller: c.JSValue } {
    const owner = try ownerOf(scope.engine);
    const root = rootOf(owner);
    const holder = try scope.object();
    const source = try scope.object();
    try scope.set(source, "pull", try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "pull", 0, idle, &.{})));
    try scope.set(source, "start", try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "start", 1, start, &.{holder})));
    try scope.set(source, "cancel", try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "cancel", 0, idle, &.{})));
    try scope.set(source, "type", try scope.text("bytes"));
    var args = [_]c.JSValue{source};
    const stream = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, root.streams.constructor, 1, &args)));
    const controller = try scope.get(holder, "controller");
    if (!c.JS_IsObject(controller)) return error.NativeWebStreamStartUnavailable;
    return .{ .stream = stream, .controller = controller };
}
fn copiedBytes(scope: *Scope, input: c.JSValue) !c.JSValue {
    const view = c.JS_IsDataView(input) or c.JS_GetTypedArrayType(input) >= 0;
    const buffer = if (view) try scope.get(input, "buffer") else input;
    const offset = if (view) try scope.get(input, "byteOffset") else c.JS_NewInt32(scope.engine.context, 0);
    const length = try scope.get(input, "byteLength");
    if (scope.truthy(try scope.get(buffer, "detached"))) return scope.own(try js.builtin(scope.engine, "Uint8Array", &.{c.JS_NewInt32(scope.engine.context, 0)}));
    const bytes = try scope.own(try js.builtin(scope.engine, "Uint8Array", &.{length}));
    const source = try scope.own(try js.builtin(scope.engine, "Uint8Array", &.{ buffer, offset, length }));
    _ = try scope.invoke(bytes, "set", &.{source});
    return bytes;
}
pub fn extract(scope: *Scope, interfaces: *const idl.Interfaces, converted: c.JSValue, keepalive: bool) !Body {
    scope.engine.native_exception_diagnostics_suppressed += 1;
    defer scope.engine.native_exception_diagnostics_suppressed -= 1;
    const owner = try ownerOf(scope.engine);
    const root = rootOf(owner);
    var source = c.pi_js_null();
    var length = c.pi_js_null();
    var content_type = c.pi_js_null();
    var multipart_parts: ?c.JSValue = null;
    const readable = try interfaces.is(scope, interfaces.readable, converted);
    const is_blob = !readable and try interfaces.is(scope, interfaces.blob, converted);
    var controller = c.pi_js_undefined();
    var stream = if (readable) converted else if (is_blob) try scope.invoke(converted, "stream", &.{}) else built: {
        const pair = try byteStream(scope);
        controller = pair.controller;
        break :built pair.stream;
    };
    if (c.JS_IsString(converted)) {
        source = converted;
        content_type = try scope.text("text/plain;charset=UTF-8");
    } else if (try interfaces.is(scope, interfaces.url_params, converted)) {
        source = try scope.invoke(converted, "toString", &.{});
        content_type = try scope.text("application/x-www-form-urlencoded;charset=UTF-8");
    } else if (c.JS_IsArrayBuffer(converted) or c.JS_IsDataView(converted) or c.JS_GetTypedArrayType(converted) >= 0) {
        source = try copiedBytes(scope, converted);
    } else if (try interfaces.is(scope, interfaces.form_data, converted)) {
        const encoded = try multipart.encode(scope, converted, root.encoder);
        source = converted;
        length = encoded.length;
        content_type = encoded.content_type;
        multipart_parts = encoded.parts;
    } else if (is_blob) {
        source = converted;
        length = try scope.get(converted, "size");
        const mime = try scope.get(converted, "type");
        if (scope.truthy(mime)) content_type = mime;
    } else {
        const symbol = try scope.own(try scope.engine.checked(c.JS_GetAsyncIteratorSymbol(scope.engine.context)));
        const iterator = try scope.own(try js.getKey(scope.engine, converted, symbol));
        if (c.JS_IsFunction(scope.engine.context, iterator)) {
            if (keepalive) try web.typeError(scope, try scope.text("keepalive"), null);
            if (try disturbed(scope, converted) or scope.truthy(try scope.get(converted, "locked"))) try web.typeError(scope, try scope.text("Response body object should not be disturbed or locked"), null);
            if (!readable) stream = try scope.own(try @import("native_web_iterable_source.zig").fromIterable(scope.engine, converted));
        } else if (!readable) return error.NativeWebBodyInitUnconverted;
    }
    if (c.JS_IsString(source) or c.JS_GetTypedArrayType(source) == c.JS_TYPED_ARRAY_UINT8) {
        const bytes = if (c.JS_IsString(source)) try scope.invoke(root.encoder, "encode", &.{source}) else source;
        length = try scope.get(bytes, "length");
        if (scope.truthy(length) and !try root.streams.is_errored(scope, root.streams.bindings, stream)) {
            const copy = try scope.own(try js.builtin(scope.engine, "Uint8Array", &.{bytes}));
            _ = try scope.invoke(controller, "enqueue", &.{copy});
        }
        var captures = [_]c.JSValue{ owner, controller };
        if (c.JS_EnqueueJob(scope.engine.context, closeJob, captures.len, &captures) < 0) return js.capture(scope.engine);
    } else if (multipart_parts) |parts| try multipart.start(scope, parts, stream, controller);
    return .{ .stream = try scope.own(c.JS_DupValue(scope.engine.context, stream)), .source = try scope.own(c.JS_DupValue(scope.engine.context, source)), .length = try scope.own(c.JS_DupValue(scope.engine.context, length)), .content_type = try scope.own(c.JS_DupValue(scope.engine.context, content_type)) };
}
pub fn clone(scope: *Scope, body: Body) !Clone {
    const pair = try scope.invoke(body.stream, "tee", &.{});
    return .{ .original_stream = try web.index(scope, pair, 0), .copy = .{ .stream = try web.index(scope, pair, 1), .source = try scope.own(c.JS_DupValue(scope.engine.context, body.source)), .length = try scope.own(c.JS_DupValue(scope.engine.context, body.length)), .content_type = try scope.own(c.JS_DupValue(scope.engine.context, body.content_type)) } };
}
fn convert(scope: *Scope, bytes: c.JSValue, mode: Mode, mime: c.JSValue) !c.JSValue {
    if (mode == .bytes or mode == .array_buffer) {
        const copied = try scope.own(try js.builtin(scope.engine, "Uint8Array", &.{bytes}));
        return if (mode == .bytes) copied else scope.get(copied, "buffer");
    }
    if (mode == .text) return bytes;
    if (mode == .json) return scope.invoke(try scope.global("JSON"), "parse", &.{bytes});
    var size: usize = 0;
    const raw = c.JS_GetUint8Array(scope.engine.context, &size, bytes);
    if (raw == null and c.JS_HasException(scope.engine.context)) return js.capture(scope.engine);
    if (mode == .blob) {
        const mime_type = if (try mime_parser.extract(scope, mime)) |record| try mime_parser.serialize(scope, record) else try scope.text("");
        const parts = try scope.array();
        try scope.index(parts, 0, bytes);
        const options = try scope.object();
        try scope.set(options, "type", mime_type);
        return scope.own(try js.builtin(scope.engine, "Blob", &.{ parts, options }));
    }
    const parsed_mime = try mime_parser.extract(scope, mime);
    const essence = if (parsed_mime) |record| try scope.get(record, "essence") else c.pi_js_null();
    if (scope.equal(essence, try scope.text("application/x-www-form-urlencoded"))) {
        const decoded = try @import("binary_encoding.zig").decode(scope.engine.gpa, if (size == 0) &.{} else raw[0..size], .utf8);
        defer scope.engine.gpa.free(decoded);
        var pairs = try @import("url_search_params.zig").parse(scope.engine.gpa, decoded);
        defer @import("url_search_params.zig").freePairs(scope.engine.gpa, &pairs);
        const result = try scope.own(try form.create(scope.engine));
        for (pairs.items) |pair| try form.appendEntry(scope, result, try scope.text(pair.name), try scope.text(pair.value));
        return result;
    }
    if (scope.equal(essence, try scope.text("multipart/form-data"))) return multipart.parse(scope, if (size == 0) &.{} else raw[0..size], parsed_mime.?);
    try web.typeError(scope, try scope.text("Content-Type was not one of \"multipart/form-data\" or \"application/x-www-form-urlencoded\"."), null);
}
fn complete(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) return flow.settle(engine, owner, true, value);
    var mode: i32 = 0;
    if (c.JS_ToInt32(engine.context, &mode, try scope.get(owner, "mode")) < 0) return js.capture(engine);
    const result = convert(&scope, value, @enumFromInt(mode), try scope.get(owner, "mime")) catch |err| return flow.rejectError(engine, owner, err);
    try flow.settle(engine, owner, false, result);
}
pub fn consume(engine: *em.Engine, body: ?Body, mode: Mode, mime: c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    try scope.put(pending.owner, "mode", c.JS_NewInt32(engine.context, @intFromEnum(mode)));
    try scope.put(pending.owner, "mime", mime);
    if (try unusable(&scope, body)) {
        const failure = try scope.own(try js.builtin(engine, "TypeError", &.{try scope.text("Body is unusable: Body has already been read")}));
        try flow.settle(engine, pending.owner, true, failure);
        return pending.promise;
    }
    if (body) |present| {
        const reader = scope.invoke(present.stream, "getReader", &.{}) catch |err| {
            try flow.rejectError(engine, pending.owner, err);
            return pending.promise;
        };
        const collected = scope.own(collector.collect(engine, reader, .{ .mode = switch (mode) {
            .text, .json => .text,
            else => .bytes,
        } }) catch |err| {
            try flow.rejectError(engine, pending.owner, err);
            return pending.promise;
        }) catch |err| {
            try flow.rejectError(engine, pending.owner, err);
            return pending.promise;
        };
        try flow.wait(complete, engine, pending.owner, collected, 0);
    } else {
        const empty = switch (mode) {
            .text, .json => try scope.text(""),
            else => try scope.own(try engine.checked(c.JS_NewUint8ArrayCopy(engine.context, null, 0))),
        };
        const result = convert(&scope, empty, mode, mime) catch |err| {
            try flow.rejectError(engine, pending.owner, err);
            return pending.promise;
        };
        try flow.settle(engine, pending.owner, false, result);
    }
    return pending.promise;
}
