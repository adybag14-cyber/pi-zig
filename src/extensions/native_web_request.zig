//! Native Request facade over the shared genuine Headers/Body/stream graph.
//! Source-only continuation: TransformStream transfer remains an explicit seam.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const web = @import("native_headers_webidl.zig");
const idl = @import("native_web_idl.zig");
const headers = @import("native_headers.zig");
const body = @import("native_web_body.zig");
const platform = @import("native_web_platform.zig");
const c = em.c;
const key = "\x00native-web-Request";
/// The shared Transform owner supplies the captured actual constructor graph.
/// Callback returns an owned genuine identity TransformStream; no tee adapter.
pub const TransferProvider = struct { owner: c.JSValue, create: *const fn (*em.Engine, c.JSValue) anyerror!c.JSValue };
const Root = struct {
    engine: *em.Engine,
    class: c.JSClassID = 0,
    constructor: c.JSValue,
    prototype: c.JSValue,
    url_constructor: c.JSValue,
    controller_constructor: c.JSValue,
    registry: c.JSValue,
    dependent_controllers: c.JSValue,
    abort_symbol: c.JSValue,
    interfaces: idl.Interfaces,
    patch_warning: bool = false,
    transfer: ?TransferProvider = null,
};
const State = struct { engine: *em.Engine, owner: c.JSValue, metadata: c.JSValue, headers: c.JSValue, signal: c.JSValue, dispatcher: c.JSValue, payload: ?body.Body = null, guard: headers.Guard = .request };
const Kind = enum(c_int) { method, url, headers, destination, referrer, referrerPolicy, mode, credentials, cache, redirect, integrity, keepalive, isReloadNavigation, isHistoryNavigation, signal, body, bodyUsed, duplex, clone, inspect, blob, arrayBuffer, text, json, formData, bytes };
fn rootOf(owner: c.JSValue) *Root {
    return @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)).?));
}
fn freeRoot(runtime: ?*c.JSRuntime, owner: c.JSValue) callconv(.c) void {
    const root: *Root = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    for ([_]c.JSValue{ root.constructor, root.prototype, root.url_constructor, root.controller_constructor, root.registry, root.dependent_controllers, root.abort_symbol }) |value| c.JS_FreeValueRT(runtime, value);
    inline for (std.meta.fields(idl.Interfaces)) |field| c.JS_FreeValueRT(runtime, @field(root.interfaces, field.name));
    if (root.transfer) |provider| c.JS_FreeValueRT(runtime, provider.owner);
    root.engine.gpa.destroy(root);
}
fn markRoot(runtime: ?*c.JSRuntime, owner: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const root: *Root = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    for ([_]c.JSValue{ root.constructor, root.prototype, root.url_constructor, root.controller_constructor, root.registry, root.dependent_controllers, root.abort_symbol }) |value| c.JS_MarkValue(runtime, value, marker);
    inline for (std.meta.fields(idl.Interfaces)) |field| c.JS_MarkValue(runtime, @field(root.interfaces, field.name), marker);
    if (root.transfer) |provider| c.JS_MarkValue(runtime, provider.owner, marker);
}
fn freeState(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for ([_]c.JSValue{ state.owner, state.metadata, state.headers, state.signal, state.dispatcher }) |edge| c.JS_FreeValueRT(runtime, edge);
    if (state.payload) |payload| inline for (std.meta.fields(body.Body)) |field| c.JS_FreeValueRT(runtime, @field(payload, field.name));
    state.engine.gpa.destroy(state);
}
fn markState(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for ([_]c.JSValue{ state.owner, state.metadata, state.headers, state.signal, state.dispatcher }) |edge| c.JS_MarkValue(runtime, edge, marker);
    if (state.payload) |payload| inline for (std.meta.fields(body.Body)) |field| c.JS_MarkValue(runtime, @field(payload, field.name), marker);
}
fn classId(engine: *em.Engine, name: [*:0]const u8, finalizer: *const c.JSClassFinalizer, marker: *const c.JSClassGCMark) !c.JSClassID {
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = name, .finalizer = finalizer, .gc_mark = marker };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    return class;
}
fn stateOf(scope: *Scope, owner: c.JSValue, value: c.JSValue) !*State {
    const root = rootOf(owner);
    if (!scope.truthy(try scope.call(root.interfaces.has_instance, root.constructor, &.{value}))) try web.typeError(scope, try scope.text("Illegal invocation"), "ERR_INVALID_THIS");
    return internal(scope, owner, value);
}
fn getterState(scope: *Scope, owner: c.JSValue, value: c.JSValue, kind: Kind) !*State {
    const root = rootOf(owner);
    if (!scope.truthy(try scope.call(root.interfaces.has_instance, root.constructor, &.{value}))) try web.typeError(scope, try scope.text("Illegal invocation"), "ERR_INVALID_THIS");
    if (c.JS_GetOpaque(value, root.class)) |pointer| return @ptrCast(@alignCast(pointer));
    const field = if (kind == .headers) "#headers" else if (kind == .signal) "#signal" else "#state";
    try web.typeError(scope, try scope.concat(try scope.concat(try scope.text("Cannot read private member "), try scope.text(field)), try scope.text(" from an object whose class did not declare it")), null);
}
fn internal(scope: *Scope, owner: c.JSValue, value: c.JSValue) !*State {
    if (c.JS_GetOpaque(value, rootOf(owner).class)) |pointer| return @ptrCast(@alignCast(pointer));
    try web.typeError(scope, try scope.text("Cannot read private member #state from an object whose class did not declare it"), null);
}
fn replace(engine: *em.Engine, old: *c.JSValue, next: c.JSValue) void {
    const owned = c.JS_DupValue(engine.context, next);
    engine.freeValue(old.*);
    old.* = owned;
}
fn ownBody(engine: *em.Engine, input: body.Body) body.Body {
    var output = input;
    inline for (std.meta.fields(body.Body)) |field| @field(output, field.name) = c.JS_DupValue(engine.context, @field(input, field.name));
    return output;
}
fn copyMetadata(scope: *Scope, target: c.JSValue, source: c.JSValue) !void {
    // makeRequest copies private fields directly; mutable Object.assign is not
    // an extra observable hook in the bundled Request implementation.
    inline for (.{ "url", "method", "mode", "credentials", "cache", "redirect", "referrer", "referrerPolicy", "integrity", "destination", "keepalive", "isReloadNavigation", "isHistoryNavigation" }) |field| try scope.set(target, field, try scope.get(source, field));
}
fn fresh(scope: *Scope, owner: c.JSValue, prototype: c.JSValue) !c.JSValue {
    const value = try scope.own(try scope.engine.checked(c.JS_NewObjectProtoClass(scope.engine.context, prototype, rootOf(owner).class)));
    const state = try scope.engine.gpa.create(State);
    state.* = .{ .engine = scope.engine, .owner = c.JS_DupValue(scope.engine.context, owner), .metadata = c.pi_js_undefined(), .headers = c.pi_js_undefined(), .signal = c.pi_js_undefined(), .dispatcher = c.pi_js_undefined() };
    _ = c.JS_SetOpaque(value, state);
    state.metadata = try js.object(scope.engine);
    state.headers = try headers.fromRecord(scope.engine, try scope.object());
    try headers.setGuard(scope.engine, state.headers, .request);
    inline for (.{ .{ "method", "GET" }, .{ "mode", "cors" }, .{ "credentials", "same-origin" }, .{ "cache", "default" }, .{ "redirect", "follow" }, .{ "referrer", "about:client" }, .{ "referrerPolicy", "" }, .{ "integrity", "" }, .{ "destination", "" } }) |field| try scope.set(state.metadata, field[0], try scope.text(field[1]));
    inline for (.{ "keepalive", "isReloadNavigation", "isHistoryNavigation" }) |field| try scope.set(state.metadata, field, c.JS_NewBool(scope.engine.context, false));
    return value;
}
fn registryCleanup(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (args.len != 0) _ = try scope.invoke(try scope.get(args[0], "signal"), "removeEventListener", &.{ try scope.text("abort"), try scope.get(args[0], "abort") });
    return c.pi_js_undefined();
}
fn abortFollow(engine: *em.Engine, receiver: c.JSValue, _: []const c.JSValue, captures: []const c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const ac = try scope.invoke(captures[1], "deref", &.{});
    if (c.JS_IsUndefined(ac)) return c.pi_js_undefined();
    const callback = try scope.get(captures[2], "abort");
    const root = rootOf(captures[0]);
    _ = try scope.invoke(root.registry, "unregister", &.{callback});
    _ = try scope.invoke(receiver, "removeEventListener", &.{ try scope.text("abort"), callback });
    const reason = try scope.get(receiver, "reason");
    _ = try scope.invoke(ac, "abort", &.{reason});
    const signal = try scope.get(ac, "signal");
    const dependents = try scope.invoke(root.dependent_controllers, "get", &.{signal});
    if (!c.JS_IsUndefined(dependents)) {
        const iterator = try scope.invoke(dependents, "values", &.{});
        while (true) {
            const row = try scope.invoke(iterator, "next", &.{});
            if (scope.truthy(try scope.get(row, "done"))) break;
            const controller = try scope.invoke(try scope.get(row, "value"), "deref", &.{});
            if (!c.JS_IsUndefined(controller)) _ = try scope.invoke(controller, "abort", &.{reason});
        }
        _ = try scope.invoke(dependents, "clear", &.{});
        _ = try scope.invoke(root.dependent_controllers, "delete", &.{signal});
    }
    return c.pi_js_undefined();
}
fn buildAbort(scope: *Scope, owner: c.JSValue, weak: c.JSValue) !c.JSValue {
    const holder = try scope.object();
    const callback = try scope.own(try @import("native_node_function.zig").create(scope.engine, "abort", 0, abortFollow, &.{ owner, weak, holder }));
    try scope.set(holder, "abort", callback);
    return callback;
}
fn signalFor(scope: *Scope, owner: c.JSValue, request: c.JSValue, parent: c.JSValue, cloned: bool) !c.JSValue {
    const root = rootOf(owner);
    const ac = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, root.controller_constructor, 0, null)));
    const signal = try scope.get(ac, "signal");
    if (!c.JS_IsNull(parent) and !c.JS_IsUndefined(parent)) {
        if (scope.truthy(try scope.get(parent, "aborted"))) _ = try scope.invoke(ac, "abort", &.{try scope.get(parent, "reason")}) else {
            var args = [_]c.JSValue{ac};
            const weak = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.global("WeakRef"), 1, &args)));
            const callback = try buildAbort(scope, owner, weak);
            if (cloned) {
                var list = try scope.invoke(root.dependent_controllers, "get", &.{parent});
                if (c.JS_IsUndefined(list)) {
                    list = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.global("Set"), 0, null)));
                    _ = try scope.invoke(root.dependent_controllers, "set", &.{ parent, list });
                }
                _ = try scope.invoke(list, "add", &.{weak});
                _ = try scope.invoke(signal, "addEventListener", &.{ try scope.text("abort"), callback });
            } else {
                const atom = try js.atom(scope.engine, root.abort_symbol);
                defer c.JS_FreeAtom(scope.engine.context, atom);
                if (c.JS_DefinePropertyValue(scope.engine.context, request, atom, c.JS_DupValue(scope.engine.context, ac), c.JS_PROP_C_W_E) < 0) return js.capture(scope.engine);
                _ = try scope.invoke(parent, "addEventListener", &.{ try scope.text("abort"), callback });
                const held = try scope.object();
                try scope.set(held, "signal", parent);
                try scope.set(held, "abort", callback);
                _ = try scope.invoke(root.registry, "register", &.{ ac, held, callback });
            }
        }
    }
    return signal;
}
fn cloneSignal(scope: *Scope, owner: c.JSValue, receiver: c.JSValue) !c.JSValue {
    const root = rootOf(owner);
    const ac = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, root.controller_constructor, 0, null)));
    // Source reads this.signal afresh after allocating the controller, including
    // repeated reads for reason and WeakMap key when a guest shadows the getter.
    if (scope.truthy(try scope.get(try scope.get(receiver, "signal"), "aborted"))) {
        _ = try scope.invoke(ac, "abort", &.{try scope.get(try scope.get(receiver, "signal"), "reason")});
    } else {
        var list = try scope.invoke(root.dependent_controllers, "get", &.{try scope.get(receiver, "signal")});
        if (c.JS_IsUndefined(list)) {
            list = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.global("Set"), 0, null)));
            _ = try scope.invoke(root.dependent_controllers, "set", &.{ try scope.get(receiver, "signal"), list });
        }
        var args = [_]c.JSValue{ac};
        const weak = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.global("WeakRef"), 1, &args)));
        _ = try scope.invoke(list, "add", &.{weak});
        _ = try scope.invoke(try scope.get(ac, "signal"), "addEventListener", &.{ try scope.text("abort"), try buildAbort(scope, owner, weak) });
    }
    return scope.get(ac, "signal");
}
fn parseUrl(scope: *Scope, owner: c.JSValue, value: c.JSValue, referrer: bool) !c.JSValue {
    var args = [_]c.JSValue{value};
    return scope.own(scope.engine.checked(c.JS_CallConstructor(scope.engine.context, rootOf(owner).url_constructor, 1, &args)) catch |err| {
        if (err != error.JavaScriptException) return err;
        const cause = try scope.own(c.JS_DupValue(scope.engine.context, scope.engine.captured_exception orelse return err));
        const options = try scope.object();
        try scope.set(options, "cause", cause);
        const message = if (referrer) try scope.concat(try scope.concat(try scope.text("Referrer \""), value), try scope.text("\" is not a valid URL.")) else try scope.concat(try scope.text("Failed to parse URL from "), value);
        const failure = try scope.own(try js.builtin(scope.engine, "TypeError", &.{ message, options }));
        _ = try scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, failure)));
        unreachable;
    });
}
fn method(scope: *Scope, value: c.JSValue) !c.JSValue {
    const units = try @import("native_utf16.zig").unitsAlloc(scope.engine, value);
    defer scope.engine.gpa.free(units);
    var valid = units.len != 0;
    for (units) |unit| if (!((unit >= 'a' and unit <= 'z') or (unit >= 'A' and unit <= 'Z') or (unit >= '0' and unit <= '9') or switch (unit) {
        '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_', '`', '|', '~' => true,
        else => false,
    })) {
        valid = false;
        break;
    };
    if (!valid) try web.typeError(scope, try scope.concat(try scope.concat(try scope.text("'"), value), try scope.text("' is not a valid HTTP method.")), null);
    const upper = try scope.invoke(value, "toUpperCase", &.{});
    inline for (.{ "CONNECT", "TRACE", "TRACK" }) |forbidden| if (scope.equal(upper, try scope.text(forbidden))) try web.typeError(scope, try scope.concat(try scope.concat(try scope.text("'"), value), try scope.text("' HTTP method is unsupported.")), null);
    inline for (.{ "DELETE", "GET", "HEAD", "OPTIONS", "POST", "PUT" }) |known| if (scope.equal(upper, try scope.text(known))) return upper;
    return value;
}
fn create(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = captures[0];
    const root = rootOf(owner);
    const prototype = try scope.get(target, "prototype");
    try web.arity(&scope, args.len, 1, "Request constructor");
    const input = try idl.requestInfo(&scope, root.interfaces, args[0]);
    const init = try idl.requestInit(&scope, root.interfaces, if (args.len > 1) args[1] else c.pi_js_undefined());
    const result = try fresh(&scope, owner, if (c.JS_IsObject(prototype)) prototype else try scope.get(try scope.global("Object"), "prototype"));
    const state = try internal(&scope, owner, result);
    var input_state: ?*State = null;
    var parent_signal = c.pi_js_null();
    if (c.JS_IsString(input)) {
        const parsed = try parseUrl(&scope, owner, input, false);
        if (scope.truthy(try scope.get(parsed, "username")) or scope.truthy(try scope.get(parsed, "password"))) try web.typeError(&scope, try scope.concat(try scope.text("Request cannot be constructed from a URL that includes credentials: "), input), null);
        try scope.set(state.metadata, "url", try scope.get(parsed, "href"));
        replace(engine, &state.dispatcher, try scope.get(init, "dispatcher"));
    } else {
        const original = try internal(&scope, owner, input);
        input_state = original;
        parent_signal = original.signal;
        try copyMetadata(&scope, state.metadata, original.metadata);
        const explicit_dispatcher = try scope.get(init, "dispatcher");
        replace(engine, &state.dispatcher, if (scope.truthy(explicit_dispatcher)) explicit_dispatcher else original.dispatcher);
        const copied = try scope.own(try headers.fromRecord(engine, original.headers));
        replace(engine, &state.headers, copied);
    }
    const window = try scope.get(init, "window");
    if (!c.JS_IsNull(window) and !c.JS_IsUndefined(window)) try web.typeError(&scope, try scope.text("'window' option 'client' must be null"), null);
    // RequestInit's priority default means initHasKey is always true.
    try scope.set(state.metadata, "referrer", try scope.text("about:client"));
    try scope.set(state.metadata, "referrerPolicy", try scope.text(""));
    const referrer = try scope.get(init, "referrer");
    if (!c.JS_IsUndefined(referrer)) {
        var selected = referrer;
        if (!scope.equal(referrer, try scope.text(""))) {
            const parsed = try parseUrl(&scope, owner, referrer, true);
            selected = if (scope.equal(try scope.get(parsed, "protocol"), try scope.text("about:")) and scope.equal(try scope.get(parsed, "hostname"), try scope.text("client"))) try scope.text("about:client") else try scope.get(parsed, "href");
        }
        try scope.set(state.metadata, "referrer", selected);
    }
    inline for (.{ "referrerPolicy", "mode", "credentials", "cache", "redirect", "integrity", "keepalive" }) |field| {
        const value = try scope.get(init, field);
        if (!c.JS_IsUndefined(value)) try scope.set(state.metadata, field, value);
    }
    if (scope.equal(try scope.get(state.metadata, "mode"), try scope.text("navigate"))) try web.typeError(&scope, try scope.text("Request constructor: invalid request mode navigate."), null);
    if (scope.equal(try scope.get(state.metadata, "cache"), try scope.text("only-if-cached")) and !scope.equal(try scope.get(state.metadata, "mode"), try scope.text("same-origin"))) try web.typeError(&scope, try scope.text("'only-if-cached' can be set only with 'same-origin' mode"), null);
    const supplied_method = try scope.get(init, "method");
    if (!c.JS_IsUndefined(supplied_method)) try scope.set(state.metadata, "method", try method(&scope, supplied_method));
    const actual_method = try scope.get(state.metadata, "method");
    if (!root.patch_warning and scope.equal(actual_method, try scope.text("patch"))) {
        const options = try scope.object();
        try scope.set(options, "code", try scope.text("UNDICI-FETCH-patch"));
        _ = try scope.invoke(try scope.global("process"), "emitWarning", &.{ try scope.text("Using `patch` is highly likely to result in a `405 Method Not Allowed`. `PATCH` is much more likely to succeed."), options });
        root.patch_warning = true;
    }
    const explicit_signal = try scope.get(init, "signal");
    if (!c.JS_IsUndefined(explicit_signal)) parent_signal = explicit_signal;
    replace(engine, &state.signal, try signalFor(&scope, owner, result, parent_signal, false));
    if (scope.equal(try scope.get(state.metadata, "mode"), try scope.text("no-cors"))) {
        if (!scope.equal(actual_method, try scope.text("GET")) and !scope.equal(actual_method, try scope.text("HEAD")) and !scope.equal(actual_method, try scope.text("POST"))) try web.typeError(&scope, try scope.concat(try scope.concat(try scope.text("'"), actual_method), try scope.text(" is unsupported in no-cors mode.")), null);
        state.guard = .request_no_cors;
    }
    const header_init = try scope.get(init, "headers");
    if (!c.JS_IsUndefined(header_init)) replace(engine, &state.headers, try scope.own(try headers.fromRecord(engine, header_init)));
    try headers.setGuard(engine, state.headers, state.guard);
    const input_body: ?body.Body = if (input_state) |original| original.payload else null;
    const init_body = try scope.get(init, "body");
    const has_init_body = !c.JS_IsNull(init_body) and !c.JS_IsUndefined(init_body);
    if ((has_init_body or input_body != null) and (scope.equal(actual_method, try scope.text("GET")) or scope.equal(actual_method, try scope.text("HEAD")))) try web.typeError(&scope, try scope.text("Request with GET/HEAD method cannot have body."), null);
    const extracted: ?body.Body = if (has_init_body) try body.extract(&scope, &root.interfaces, init_body, scope.truthy(try scope.get(state.metadata, "keepalive"))) else input_body;
    if (extracted) |payload| {
        if (has_init_body and scope.truthy(payload.content_type) and !scope.truthy(try scope.invoke(state.headers, "has", &.{try scope.text("content-type")}))) _ = try scope.invoke(state.headers, "append", &.{ try scope.text("content-type"), payload.content_type });
        if (c.JS_IsNull(payload.source)) {
            const duplex = try scope.get(init, "duplex");
            if (has_init_body and (c.JS_IsNull(duplex) or c.JS_IsUndefined(duplex))) try web.typeError(&scope, try scope.text("RequestInit: duplex option is required when sending a body."), null);
            const mode = try scope.get(state.metadata, "mode");
            if (!scope.equal(mode, try scope.text("same-origin")) and !scope.equal(mode, try scope.text("cors"))) try web.typeError(&scope, try scope.text("If request is made from ReadableStream, mode should be \"same-origin\" or \"cors\""), null);
        }
        if (!has_init_body) {
            if (try body.unusable(&scope, input_body)) try web.typeError(&scope, try scope.text("Cannot construct a Request with a Request object that has already been used."), null);
            const provider = root.transfer orelse return error.NativeWebTransformStreamUnavailable;
            const identity = try scope.own(try provider.create(engine, provider.owner));
            var transferred = payload;
            transferred.stream = try scope.invoke(payload.stream, "pipeThrough", &.{identity});
            state.payload = ownBody(engine, transferred);
        } else {
            state.payload = ownBody(engine, payload);
        }
    }
    return c.JS_DupValue(engine.context, result);
}
fn clone(scope: *Scope, owner: c.JSValue, state: *State, receiver: c.JSValue) !c.JSValue {
    if (try body.unusable(scope, state.payload)) try web.typeError(scope, try scope.text("unusable"), null);
    const result = try fresh(scope, owner, rootOf(owner).prototype);
    const copy = try internal(scope, owner, result);
    try copyMetadata(scope, copy.metadata, state.metadata);
    replace(scope.engine, &copy.headers, try scope.own(try headers.fromRecord(scope.engine, state.headers)));
    copy.guard = state.guard;
    try headers.setGuard(scope.engine, copy.headers, copy.guard);
    replace(scope.engine, &copy.dispatcher, state.dispatcher);
    if (state.payload) |payload| {
        const split = try body.clone(scope, payload);
        copy.payload = ownBody(scope.engine, split.copy);
        replace(scope.engine, &state.payload.?.stream, split.original_stream);
    }
    replace(scope.engine, &copy.signal, try cloneSignal(scope, owner, receiver));
    return result;
}
fn consumer(kind: Kind) bool {
    return switch (kind) {
        .blob, .arrayBuffer, .text, .json, .formData, .bytes => true,
        else => false,
    };
}
fn rejected(scope: *Scope, failure: anyerror) !c.JSValue {
    if (failure != error.JavaScriptException) return failure;
    _ = scope.engine.throwCaptured();
    const reason = try scope.own(c.JS_GetException(scope.engine.context));
    var caps: [2]c.JSValue = undefined;
    const promise = try scope.own(try scope.engine.checked(c.JS_NewPromiseCapability(scope.engine.context, &caps)));
    defer for (caps) |cap| scope.engine.freeValue(cap);
    _ = try scope.call(caps[1], c.pi_js_undefined(), &.{reason});
    return promise;
}
fn operation(scope: *Scope, owner: c.JSValue, receiver: c.JSValue, args: []const c.JSValue, kind: Kind) !c.JSValue {
    const state = getterState(scope, owner, receiver, kind) catch |err| return if (consumer(kind)) rejected(scope, err) else err;
    return switch (kind) {
        .headers => state.headers,
        .signal => state.signal,
        .body => if (state.payload) |payload| payload.stream else c.pi_js_null(),
        .bodyUsed => c.JS_NewBool(scope.engine.context, if (state.payload) |payload| try body.disturbed(scope, payload.stream) else false),
        .duplex => scope.text("half"),
        .clone => clone(scope, owner, state, receiver),
        .inspect => inspect(scope, receiver, args),
        .blob, .arrayBuffer, .text, .json, .formData, .bytes => scope.own(try body.consume(scope.engine, state.payload, switch (kind) {
            .blob => .blob,
            .arrayBuffer => .array_buffer,
            .text => .text,
            .json => .json,
            .formData => .form_data,
            .bytes => .bytes,
            else => unreachable,
        }, try scope.invoke(state.headers, "get", &.{try scope.text("content-type")}))),
        else => scope.get(state.metadata, @tagName(kind)),
    };
}
fn inspect(scope: *Scope, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const options = if (args.len > 1) args[1] else c.pi_js_undefined();
    if (c.JS_IsNull(try scope.get(options, "depth"))) try scope.set(options, "depth", c.JS_NewInt32(scope.engine.context, 2));
    const colors = try scope.get(options, "colors");
    if (c.JS_IsNull(colors) or c.JS_IsUndefined(colors)) try scope.set(options, "colors", c.JS_NewBool(scope.engine.context, true));
    const properties = try scope.object();
    inline for (.{ "method", "url", "headers", "destination", "referrer", "referrerPolicy", "mode", "credentials", "cache", "redirect", "integrity", "keepalive", "isReloadNavigation", "isHistoryNavigation", "signal" }) |field| try scope.set(properties, field, try scope.get(receiver, field));
    var depth: i32 = 2;
    const configured_depth = try scope.get(options, "depth");
    if (!c.JS_IsUndefined(configured_depth) and c.JS_ToInt32(scope.engine.context, &depth, configured_depth) < 0) return js.capture(scope.engine);
    const output = try @import("node_event_inspect.zig").inspect(scope.engine, properties, depth);
    defer scope.engine.gpa.free(output);
    return scope.concat(try scope.text("Request "), try scope.text(output));
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = operation(&scope, captures[0], receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(raw)) catch |err| return @import("native_sdk.zig").fail(engine, err);
    return c.JS_DupValue(context, result);
}
fn function(scope: *Scope, owner: c.JSValue, name: [*:0]const u8, kind: Kind) !c.JSValue {
    var captures = [_]c.JSValue{owner};
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, dispatch, name, if (kind == .inspect) 2 else 0, @intFromEnum(kind), 1, &captures)));
}
fn getter(scope: *Scope, owner: c.JSValue, comptime name: [:0]const u8, kind: Kind) !void {
    const atom = c.JS_NewAtom(scope.engine.context, name);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DefinePropertyGetSet(scope.engine.context, rootOf(owner).prototype, atom, c.JS_DupValue(scope.engine.context, try function(scope, owner, "get " ++ name, kind)), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(scope.engine);
}
pub fn install(engine: *em.Engine) !void {
    if (engine.native_module_values.contains(key)) return;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const interfaces = try platform.prepare(&scope);
    const owner = try scope.own(try engine.checked(c.JS_NewObjectClass(engine.context, try classId(engine, "Native Request Owner", freeRoot, markRoot))));
    const root = try engine.gpa.create(Root);
    root.* = .{ .engine = engine, .constructor = c.pi_js_undefined(), .prototype = c.pi_js_undefined(), .url_constructor = c.pi_js_undefined(), .controller_constructor = c.pi_js_undefined(), .registry = c.pi_js_undefined(), .dependent_controllers = c.pi_js_undefined(), .abort_symbol = c.pi_js_undefined(), .interfaces = interfaces };
    inline for (std.meta.fields(idl.Interfaces)) |field| @field(root.interfaces, field.name) = c.JS_DupValue(engine.context, @field(interfaces, field.name));
    _ = c.JS_SetOpaque(owner, root);
    root.class = try classId(engine, "Request", freeState, markState);
    root.prototype = try js.object(engine);
    root.url_constructor = try js.global(engine, "URL");
    root.controller_constructor = try js.global(engine, "AbortController");
    root.dependent_controllers = try engine.checked(c.JS_CallConstructor(engine.context, try scope.global("WeakMap"), 0, null));
    root.abort_symbol = c.JS_DupValue(engine.context, try scope.call(try scope.global("Symbol"), c.pi_js_undefined(), &.{try scope.text("abortController")}));
    const cleanup = try scope.own(try @import("native_node_function.zig").createArrow(engine, "", 1, registryCleanup, &.{}));
    var registry_args = [_]c.JSValue{cleanup};
    root.registry = try engine.checked(c.JS_CallConstructor(engine.context, try scope.global("FinalizationRegistry"), 1, &registry_args));
    root.constructor = try @import("native_class.zig").constructor(engine, "_Request", 1, root.prototype, create, &.{owner});
    if (c.JS_DefinePropertyValueStr(engine.context, root.constructor, "name", c.JS_DupValue(engine.context, try scope.text("Request")), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    replace(engine, &root.interfaces.request, root.constructor);
    inline for (.{ Kind.method, Kind.url, Kind.headers, Kind.destination, Kind.referrer, Kind.referrerPolicy, Kind.mode, Kind.credentials, Kind.cache, Kind.redirect, Kind.integrity, Kind.keepalive, Kind.isReloadNavigation, Kind.isHistoryNavigation, Kind.signal, Kind.body, Kind.bodyUsed, Kind.duplex }) |kind| try getter(&scope, owner, @tagName(kind), kind);
    try scope.set(root.prototype, "clone", try function(&scope, owner, "clone", .clone));
    const inspect_symbol = try scope.call(try scope.get(try scope.global("Symbol"), "for"), c.pi_js_undefined(), &.{try scope.text("nodejs.util.inspect.custom")});
    const inspect_atom = try js.atom(engine, inspect_symbol);
    defer c.JS_FreeAtom(engine.context, inspect_atom);
    if (c.JS_DefinePropertyValue(engine.context, root.prototype, inspect_atom, c.JS_DupValue(engine.context, try function(&scope, owner, "[nodejs.util.inspect.custom]", .inspect)), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    inline for (.{ Kind.blob, Kind.arrayBuffer, Kind.text, Kind.json, Kind.formData, Kind.bytes }) |kind| try scope.set(root.prototype, @tagName(kind), try function(&scope, owner, @tagName(kind), kind));
    // Bundled Object.defineProperties creates this enumerable undefined value.
    if (c.JS_DefinePropertyValueStr(engine.context, root.prototype, "attribute", c.pi_js_undefined(), c.JS_PROP_ENUMERABLE) < 0) return js.capture(engine);
    const tag = try js.atom(engine, try scope.get(try scope.global("Symbol"), "toStringTag"));
    defer c.JS_FreeAtom(engine.context, tag);
    if (c.JS_DefinePropertyValue(engine.context, root.prototype, tag, c.JS_DupValue(engine.context, try scope.text("Request")), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    try engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1);
    try platform.setRequest(engine, root.constructor);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    if (c.JS_DefinePropertyValueStr(engine.context, global, "Request", c.JS_DupValue(engine.context, root.constructor), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    engine.native_module_values.putAssumeCapacity(key, c.JS_DupValue(engine.context, owner));
}
pub fn isRequest(engine: *em.Engine, value: c.JSValue) bool {
    const owner = engine.native_module_values.get(key) orelse return false;
    return c.JS_GetOpaque(value, rootOf(owner).class) != null;
}
/// Bind only after the actual shared Transform constructor and Env pipe graph
/// exist. The native owner edge is duplicated/marked until Engine teardown.
pub fn bindTransfer(engine: *em.Engine, provider: TransferProvider) !void {
    const owner = engine.native_module_values.get(key) orelse return error.NativeWebRequestUnavailable;
    const root = rootOf(owner);
    const retained = c.JS_DupValue(engine.context, provider.owner);
    if (root.transfer) |old| engine.freeValue(old.owner);
    root.transfer = .{ .owner = retained, .create = provider.create };
}
/// Internal fetch handoff borrows the actual privately owned Request state.
pub const View = struct { url: c.JSValue, method: c.JSValue, headers: c.JSValue, signal: c.JSValue, dispatcher: c.JSValue, payload: ?body.Body };
pub fn view(scope: *Scope, request: c.JSValue) !View {
    const owner = scope.engine.native_module_values.get(key) orelse return error.NativeWebRequestUnavailable;
    const state = try stateOf(scope, owner, request);
    return .{ .url = try scope.get(state.metadata, "url"), .method = try scope.get(state.metadata, "method"), .headers = state.headers, .signal = state.signal, .dispatcher = state.dispatcher, .payload = state.payload };
}
