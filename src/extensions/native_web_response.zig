//! Actual Node24 bundled Undici7.21 Response facade. Body algorithms and the
//! genuine native ReadableStream graph are shared with Request, never replaced
//! by object records or a duck-typed stream. Private state owns every JS edge.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const web = @import("native_headers_webidl.zig");
const idl = @import("native_web_idl.zig");
const headers = @import("native_headers.zig");
const body = @import("native_web_body.zig");
const c = em.c;
const cache_key = "\x00native-web-Response";
const Root = struct {
    engine: *em.Engine,
    class: c.JSClassID = 0,
    constructor: c.JSValue,
    prototype: c.JSValue,
    object_prototype: c.JSValue,
    interfaces: idl.Interfaces,
};
const State = struct {
    engine: *em.Engine,
    owner: c.JSValue,
    headers: c.JSValue,
    status_text: c.JSValue,
    url: c.JSValue,
    payload: ?body.Body = null,
    status: u16 = 200,
    network_error: bool = false,
    basic: bool = false,
    redirected: bool = false,
    guard: headers.Guard = .response,
};
const Kind = enum(c_int) { type, url, redirected, status, ok, statusText, headers, body, bodyUsed, clone, inspect, blob, arrayBuffer, text, json, formData, bytes, static_error, static_json, static_redirect };
fn rootOf(owner: c.JSValue) *Root {
    return @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)).?));
}
fn freeRoot(runtime: ?*c.JSRuntime, owner: c.JSValue) callconv(.c) void {
    const root: *Root = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    c.JS_FreeValueRT(runtime, root.constructor);
    c.JS_FreeValueRT(runtime, root.prototype);
    c.JS_FreeValueRT(runtime, root.object_prototype);
    inline for (std.meta.fields(idl.Interfaces)) |field| c.JS_FreeValueRT(runtime, @field(root.interfaces, field.name));
    root.engine.gpa.destroy(root);
}
fn markRoot(runtime: ?*c.JSRuntime, owner: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const root: *Root = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    c.JS_MarkValue(runtime, root.constructor, marker);
    c.JS_MarkValue(runtime, root.prototype, marker);
    c.JS_MarkValue(runtime, root.object_prototype, marker);
    inline for (std.meta.fields(idl.Interfaces)) |field| c.JS_MarkValue(runtime, @field(root.interfaces, field.name), marker);
}
fn freeState(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for ([_]c.JSValue{ state.owner, state.headers, state.status_text, state.url }) |edge| c.JS_FreeValueRT(runtime, edge);
    if (state.payload) |payload| inline for (std.meta.fields(body.Body)) |field| c.JS_FreeValueRT(runtime, @field(payload, field.name));
    state.engine.gpa.destroy(state);
}
fn markState(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for ([_]c.JSValue{ state.owner, state.headers, state.status_text, state.url }) |edge| c.JS_MarkValue(runtime, edge, marker);
    if (state.payload) |payload| inline for (std.meta.fields(body.Body)) |field| c.JS_MarkValue(runtime, @field(payload, field.name), marker);
}
fn classId(engine: *em.Engine, name: [*:0]const u8, finalizer: *const c.JSClassFinalizer, marker: *const c.JSClassGCMark) !c.JSClassID {
    var id: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &id);
    const definition: c.JSClassDef = .{ .class_name = name, .finalizer = finalizer, .gc_mark = marker };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    return id;
}
fn privateState(scope: *Scope, owner: c.JSValue, receiver: c.JSValue, headers_field: bool) !*State {
    const root = rootOf(owner);
    if (!scope.truthy(try scope.call(root.interfaces.has_instance, root.constructor, &.{receiver}))) try web.typeError(scope, try scope.text("Illegal invocation"), "ERR_INVALID_THIS");
    if (c.JS_GetOpaque(receiver, root.class)) |opaque_state| return @ptrCast(@alignCast(opaque_state));
    try web.typeError(scope, try scope.text(if (headers_field) "Cannot read private member #headers from an object whose class did not declare it" else "Cannot read private member #state from an object whose class did not declare it"), null);
}
fn internalState(owner: c.JSValue, receiver: c.JSValue) *State {
    return @ptrCast(@alignCast(c.JS_GetOpaque(receiver, rootOf(owner).class).?));
}
fn ownBody(engine: *em.Engine, input: body.Body) body.Body {
    var result = input;
    inline for (std.meta.fields(body.Body)) |field| @field(result, field.name) = c.JS_DupValue(engine.context, @field(input, field.name));
    return result;
}
fn fresh(scope: *Scope, owner: c.JSValue, prototype: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const value = try scope.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, prototype, rootOf(owner).class)));
    const state = try engine.gpa.create(State);
    state.* = .{ .engine = engine, .owner = c.JS_DupValue(engine.context, owner), .headers = c.pi_js_undefined(), .status_text = c.pi_js_undefined(), .url = c.pi_js_undefined() };
    _ = c.JS_SetOpaque(value, state);
    state.headers = try headers.fromRecord(engine, try scope.object());
    try headers.setGuard(engine, state.headers, .response);
    state.status_text = c.JS_DupValue(engine.context, try scope.text(""));
    state.url = c.JS_DupValue(engine.context, try scope.text(""));
    return value;
}
fn rangeError(scope: *Scope, message: c.JSValue) anyerror!noreturn {
    const error_value = try scope.own(try js.builtin(scope.engine, "RangeError", &.{message}));
    _ = try scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, error_value)));
    unreachable;
}
fn initialize(scope: *Scope, state: *State, init: c.JSValue, payload: ?body.Body) !void {
    var status: i32 = 0;
    const status_value = try scope.get(init, "status");
    if (c.JS_ToInt32(scope.engine.context, &status, status_value) < 0) return js.capture(scope.engine);
    if (status < 200 or status > 599) try rangeError(scope, try scope.text("init[\"status\"] must be in the range of 200 to 599, inclusive."));
    const status_text = try scope.get(init, "statusText");
    const units = try @import("native_utf16.zig").unitsAlloc(scope.engine, status_text);
    defer scope.engine.gpa.free(units);
    for (units) |unit| if (!(unit == 9 or (unit >= 32 and unit <= 126) or (unit >= 128 and unit <= 255))) try web.typeError(scope, try scope.text("Invalid statusText"), null);
    state.status = @intCast(status);
    scope.engine.freeValue(state.status_text);
    state.status_text = c.JS_DupValue(scope.engine.context, status_text);
    const header_init = try scope.get(init, "headers");
    if (!c.JS_IsNull(header_init) and !c.JS_IsUndefined(header_init)) {
        const filled = try scope.own(try headers.fromRecord(scope.engine, header_init));
        try headers.setGuard(scope.engine, filled, .response);
        scope.engine.freeValue(state.headers);
        state.headers = c.JS_DupValue(scope.engine.context, filled);
    }
    if (payload) |extracted| {
        if (status == 204 or status == 205 or status == 304) try web.typeError(scope, try scope.concat(try scope.text("Response constructor: Invalid response status code "), status_value), null);
        state.payload = ownBody(scope.engine, extracted);
        if (!c.JS_IsNull(extracted.content_type) and !c.JS_IsUndefined(extracted.content_type) and !scope.truthy(try scope.invoke(state.headers, "has", &.{try scope.text("content-type")}))) _ = try scope.invoke(state.headers, "append", &.{ try scope.text("content-type"), extracted.content_type });
    }
}
fn create(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) anyerror!c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = captures[0];
    const root = rootOf(owner);
    // Ordinary class allocation resolves newTarget.prototype before running
    // the constructor's BodyInit/ResponseInit conversions.
    const prototype = try scope.get(target, "prototype");
    const input = if (args.len == 0 or c.JS_IsUndefined(args[0])) c.pi_js_null() else args[0];
    const converted = if (c.JS_IsNull(input)) input else try idl.bodyInit(&scope, root.interfaces, input, "Response", try scope.text("body"));
    const init = try idl.responseInit(&scope, if (args.len > 1) args[1] else c.pi_js_undefined());
    const result = try fresh(&scope, owner, if (c.JS_IsObject(prototype)) prototype else root.object_prototype);
    const extracted: ?body.Body = if (c.JS_IsNull(converted)) null else try body.extract(&scope, &root.interfaces, converted, false);
    try initialize(&scope, internalState(owner, result), init, extracted);
    return c.JS_DupValue(engine.context, result);
}
fn reject(scope: *Scope, failure: anyerror) !c.JSValue {
    const engine = scope.engine;
    if (failure == error.OutOfMemory) return failure;
    if (failure != error.JavaScriptException) return failure;
    _ = engine.throwCaptured();
    const reason = try scope.own(c.JS_GetException(engine.context));
    var caps: [2]c.JSValue = undefined;
    const promise = try scope.own(try engine.checked(c.JS_NewPromiseCapability(engine.context, &caps)));
    defer for (caps) |cap| engine.freeValue(cap);
    _ = try scope.call(caps[1], c.pi_js_undefined(), &.{reason});
    return promise;
}
fn clone(scope: *Scope, owner: c.JSValue, receiver: c.JSValue, state: *State) !c.JSValue {
    if (try body.unusable(scope, state.payload)) try web.typeError(scope, try scope.text("Response.clone: Body has already been consumed."), null);
    const result = try fresh(scope, owner, rootOf(owner).prototype);
    const copy = try privateState(scope, owner, result, false);
    const copied_headers = try scope.own(try headers.fromRecord(scope.engine, state.headers));
    try headers.setGuard(scope.engine, copied_headers, state.guard);
    const cloned = if (state.payload) |payload| try body.clone(scope, payload) else null;
    scope.engine.freeValue(copy.headers);
    copy.headers = c.JS_DupValue(scope.engine.context, copied_headers);
    copy.status = state.status;
    copy.network_error = state.network_error;
    copy.basic = state.basic;
    copy.redirected = state.redirected;
    copy.guard = state.guard;
    scope.engine.freeValue(copy.status_text);
    copy.status_text = c.JS_DupValue(scope.engine.context, state.status_text);
    scope.engine.freeValue(copy.url);
    copy.url = c.JS_DupValue(scope.engine.context, state.url);
    if (cloned) |split| {
        copy.payload = ownBody(scope.engine, split.copy);
        scope.engine.freeValue(state.payload.?.stream);
        state.payload.?.stream = c.JS_DupValue(scope.engine.context, split.original_stream);
        if (scope.truthy(state.url)) {
            try body.registerResponse(scope.engine, receiver, state.payload.?.stream);
            try body.registerResponse(scope.engine, result, copy.payload.?.stream);
        }
    }
    return result;
}
fn isConsumer(kind: Kind) bool {
    return switch (kind) {
        .blob, .arrayBuffer, .text, .json, .formData, .bytes => true,
        else => false,
    };
}
fn operation(scope: *Scope, owner: c.JSValue, receiver: c.JSValue, args: []const c.JSValue, kind: Kind) !c.JSValue {
    const engine = scope.engine;
    if (kind == .static_error or kind == .static_json or kind == .static_redirect) return staticOperation(scope, owner, args, kind);
    const state = privateState(scope, owner, receiver, kind == .headers) catch |err| return if (isConsumer(kind)) reject(scope, err) else err;
    return switch (kind) {
        .type => scope.text(if (state.network_error) "error" else if (state.basic) "basic" else "default"),
        .url => state.url,
        .redirected => c.JS_NewBool(engine.context, state.redirected),
        .status => c.JS_NewInt32(engine.context, state.status),
        .ok => c.JS_NewBool(engine.context, state.status >= 200 and state.status <= 299),
        .statusText => state.status_text,
        .headers => state.headers,
        .body => if (state.payload) |payload| payload.stream else c.pi_js_null(),
        .bodyUsed => c.JS_NewBool(engine.context, if (state.payload) |payload| try body.disturbed(scope, payload.stream) else false),
        .clone => clone(scope, owner, receiver, state),
        .blob, .arrayBuffer, .text, .json, .formData, .bytes => scope.own(try body.consume(engine, state.payload, switch (kind) {
            .blob => .blob,
            .arrayBuffer => .array_buffer,
            .text => .text,
            .json => .json,
            .formData => .form_data,
            .bytes => .bytes,
            else => unreachable,
        }, try scope.invoke(state.headers, "get", &.{try scope.text("content-type")}))),
        .inspect => inspect(scope, receiver, args),
        else => unreachable,
    };
}
fn inspect(scope: *Scope, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const properties = try scope.object();
    inline for (.{ "status", "statusText", "headers", "body", "bodyUsed", "ok", "redirected", "type", "url" }) |name| try scope.set(properties, name, try scope.get(receiver, name));
    const formatted = try @import("node_event_inspect.zig").inspect(scope.engine, properties, if (args.len > 0) depth: {
        var depth: i32 = 2;
        if (c.JS_ToInt32(scope.engine.context, &depth, args[0]) < 0) return js.capture(scope.engine);
        break :depth depth;
    } else 2);
    defer scope.engine.gpa.free(formatted);
    return scope.concat(try scope.text("Response "), try scope.text(formatted));
}
fn staticOperation(scope: *Scope, owner: c.JSValue, args: []const c.JSValue, kind: Kind) !c.JSValue {
    const root = rootOf(owner);
    if (kind == .static_json) {
        try web.arity(scope, args.len, 1, "Response.json");
        const init = if (args.len > 1 and c.JS_IsNull(args[1])) args[1] else try idl.responseInit(scope, if (args.len > 1) args[1] else c.pi_js_undefined());
        const serialized = try scope.invoke(try scope.global("JSON"), "stringify", &.{args[0]});
        if (c.JS_IsUndefined(serialized)) try web.typeError(scope, try scope.text("Value is not JSON serializable"), null);
        var extracted = try body.extract(scope, &root.interfaces, serialized, false);
        extracted.content_type = try scope.text("application/json");
        const result = try fresh(scope, owner, root.prototype);
        try initialize(scope, try privateState(scope, owner, result, false), init, extracted);
        return result;
    }
    if (kind == .static_redirect) {
        try web.arity(scope, args.len, 1, "Response.redirect");
        const input = try idl.usvString(scope, args[0]);
        const converted = try idl.unsignedShort(scope, if (args.len < 2 or c.JS_IsUndefined(args[1])) c.JS_NewInt32(scope.engine.context, 302) else args[1]);
        const parsed_owned = js.builtin(scope.engine, "URL", &.{input}) catch |err| {
            if (err != error.JavaScriptException) return err;
            _ = scope.engine.throwCaptured();
            const cause = try scope.own(c.JS_GetException(scope.engine.context));
            const options = try scope.object();
            try scope.set(options, "cause", cause);
            const failure = try scope.own(try js.builtin(scope.engine, "TypeError", &.{ try scope.concat(try scope.text("Failed to parse URL from "), input), options }));
            _ = try scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, failure)));
            unreachable;
        };
        const parsed = try scope.own(parsed_owned);
        var status: i32 = 0;
        if (c.JS_ToInt32(scope.engine.context, &status, converted) < 0) return js.capture(scope.engine);
        if (status != 301 and status != 302 and status != 303 and status != 307 and status != 308) try rangeError(scope, try scope.concat(try scope.text("Invalid status code "), converted));
        const result = try fresh(scope, owner, root.prototype);
        const state = try privateState(scope, owner, result, false);
        state.status = @intCast(status);
        _ = try scope.invoke(state.headers, "append", &.{ try scope.text("location"), try scope.get(parsed, "href") });
        state.guard = .immutable;
        try headers.setGuard(scope.engine, state.headers, .immutable);
        return result;
    }
    const result = try fresh(scope, owner, root.prototype);
    const state = try privateState(scope, owner, result, false);
    state.status = 0;
    state.network_error = true;
    state.guard = .immutable;
    try headers.setGuard(scope.engine, state.headers, .immutable);
    return result;
}
fn callback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = operation(&scope, captures[0], receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic)) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
        return c.JS_ThrowInternalError(context, "Native Response: %s", @as([*:0]const u8, @errorName(err)));
    };
    return c.JS_DupValue(context, result);
}
fn function(scope: *Scope, owner: c.JSValue, name: [*:0]const u8, length: c_int, kind: Kind) !c.JSValue {
    var captures = [_]c.JSValue{owner};
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callback, name, length, @intFromEnum(kind), 1, &captures)));
}
fn getter(scope: *Scope, owner: c.JSValue, name: [*:0]const u8, display: [*:0]const u8, kind: Kind) !void {
    const atom = c.JS_NewAtom(scope.engine.context, name);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DefinePropertyGetSet(scope.engine.context, rootOf(owner).prototype, atom, c.JS_DupValue(scope.engine.context, try function(scope, owner, display, 0, kind)), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(scope.engine);
}
fn symbolProperty(scope: *Scope, object: c.JSValue, symbol: c.JSValue, value: c.JSValue, flags: c_int) !void {
    const atom = try js.atom(scope.engine, symbol);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DefinePropertyValue(scope.engine.context, object, atom, c.JS_DupValue(scope.engine.context, value), flags) < 0) return js.capture(scope.engine);
}
/// Body's genuine stream graph must already be installed. Every constructor in
/// interfaces is an actual captured interface, retained here for brand checks.
pub fn install(engine: *em.Engine, interfaces: idl.Interfaces) !void {
    if (engine.native_module_values.contains(cache_key)) return;
    try body.require(engine);
    try headers.install(engine);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.own(try engine.checked(c.JS_NewObjectClass(engine.context, try classId(engine, "Native Response Owner", freeRoot, markRoot))));
    const root = try engine.gpa.create(Root);
    root.* = .{ .engine = engine, .constructor = c.pi_js_undefined(), .prototype = c.pi_js_undefined(), .object_prototype = c.pi_js_undefined(), .interfaces = interfaces };
    inline for (std.meta.fields(idl.Interfaces)) |field| @field(root.interfaces, field.name) = c.JS_DupValue(engine.context, @field(interfaces, field.name));
    _ = c.JS_SetOpaque(owner, root);
    root.class = try classId(engine, "Response", freeState, markState);
    root.prototype = try js.object(engine);
    root.object_prototype = try js.get(engine, try scope.global("Object"), "prototype");
    // Bundled Undici declares `class _Response` and then names the exported
    // function Response. The lexical class name remains observable when called
    // without new, independently of the public function's name descriptor.
    root.constructor = try @import("native_class.zig").constructor(engine, "_Response", 0, root.prototype, create, &.{owner});
    if (c.JS_DefinePropertyValueStr(engine.context, root.constructor, "name", c.JS_DupValue(engine.context, try scope.text("Response")), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    inline for (.{ .{ "type", "get type", Kind.type }, .{ "url", "get url", Kind.url }, .{ "redirected", "get redirected", Kind.redirected }, .{ "status", "get status", Kind.status }, .{ "ok", "get ok", Kind.ok }, .{ "statusText", "get statusText", Kind.statusText }, .{ "headers", "get headers", Kind.headers }, .{ "body", "get body", Kind.body }, .{ "bodyUsed", "get bodyUsed", Kind.bodyUsed } }) |spec| try getter(&scope, owner, spec[0], spec[1], spec[2]);
    try scope.set(root.prototype, "clone", try function(&scope, owner, "clone", 0, .clone));
    const symbols = try scope.global("Symbol");
    try symbolProperty(&scope, root.prototype, try scope.invoke(symbols, "for", &.{try scope.text("nodejs.util.inspect.custom")}), try function(&scope, owner, "[nodejs.util.inspect.custom]", 2, .inspect), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    inline for (.{ .{ "blob", Kind.blob }, .{ "arrayBuffer", Kind.arrayBuffer }, .{ "text", Kind.text }, .{ "json", Kind.json }, .{ "formData", Kind.formData }, .{ "bytes", Kind.bytes } }) |spec| try scope.set(root.prototype, spec[0], try function(&scope, owner, spec[0], 0, spec[1]));
    try symbolProperty(&scope, root.prototype, try scope.get(symbols, "toStringTag"), try scope.text("Response"), c.JS_PROP_CONFIGURABLE);
    inline for (.{ .{ "error", 0, Kind.static_error }, .{ "json", 1, Kind.static_json }, .{ "redirect", 1, Kind.static_redirect } }) |spec| try scope.set(root.constructor, spec[0], try function(&scope, owner, spec[0], spec[1], spec[2]));
    try engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    if (c.JS_DefinePropertyValueStr(engine.context, global, "Response", c.JS_DupValue(engine.context, root.constructor), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    engine.native_module_values.putAssumeCapacity(cache_key, c.JS_DupValue(engine.context, owner));
}
pub fn isResponse(engine: *em.Engine, value: c.JSValue) bool {
    const owner = engine.native_module_values.get(cache_key) orelse return false;
    return c.JS_GetOpaque(value, rootOf(owner).class) != null;
}
pub const Transport = struct { body: c.JSValue, status: u16, status_text: c.JSValue, headers: c.JSValue, url: c.JSValue, redirected: bool = false };
/// Borrowed input edges; returns an owned genuine Response with immutable
/// headers. An actual async byte iterable is extracted by the shared Body graph.
pub fn fromTransport(engine: *em.Engine, input: Transport) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const owner = engine.native_module_values.get(cache_key) orelse return error.NativeWebResponseUnavailable;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const root = rootOf(owner);
    // Source's network path uses makeResponse/fromInnerResponse, bypassing the
    // public constructor's ResponseInit conversion and 200..599 restriction.
    const result = try fresh(&scope, owner, root.prototype);
    const state = internalState(owner, result);
    state.status = input.status;
    state.basic = true;
    engine.freeValue(state.status_text);
    state.status_text = c.JS_DupValue(engine.context, input.status_text);
    const filled = try scope.own(try headers.fromRecord(engine, input.headers));
    engine.freeValue(state.headers);
    state.headers = c.JS_DupValue(engine.context, filled);
    if (!c.JS_IsNull(input.body) and !c.JS_IsUndefined(input.body)) {
        const converted = try idl.bodyInit(&scope, root.interfaces, input.body, "Response", try scope.text("body"));
        state.payload = ownBody(engine, try body.extract(&scope, &root.interfaces, converted, false));
    }
    const parsed = try scope.own(try js.builtin(engine, "URL", &.{input.url}));
    try scope.set(parsed, "hash", try scope.text(""));
    const url = try scope.get(parsed, "href");
    engine.freeValue(state.url);
    state.url = c.JS_DupValue(engine.context, url);
    state.redirected = input.redirected;
    state.guard = .immutable;
    try headers.setGuard(engine, state.headers, .immutable);
    if (state.payload) |payload| try body.registerResponse(engine, result, payload.stream);
    return c.JS_DupValue(engine.context, result);
}
