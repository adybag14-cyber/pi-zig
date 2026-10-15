//! Source-authored Request/Response WebIDL conversion; unqualified Body phase.
//! Actual interface constructors and the captured intrinsic HasInstance are
//! supplied by the owning native Web graph, never by plain-object substitutes.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const web = @import("native_headers_webidl.zig");
const headers = @import("native_headers.zig");
const c = em.c;
pub const Interfaces = struct {
    has_instance: c.JSValue,
    readable: c.JSValue,
    blob: c.JSValue,
    form_data: c.JSValue,
    url_params: c.JSValue,
    abort_signal: c.JSValue,
    request: c.JSValue,
    pub fn is(self: Interfaces, scope: *Scope, constructor: c.JSValue, value: c.JSValue) !bool {
        return scope.truthy(try scope.call(self.has_instance, constructor, &.{value}));
    }
};
fn binary(scope: *Scope, operation: c_int, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, operation, left, right)));
}
pub fn domString(scope: *Scope, value: c.JSValue, prefix: []const u8, argument: c.JSValue) !c.JSValue {
    if (c.JS_IsSymbol(value)) {
        const message = try scope.concat(try scope.concat(try scope.text(prefix), try scope.text(": ")), argument);
        try web.typeError(scope, try scope.concat(message, try scope.text(" is a symbol, which cannot be converted to a DOMString.")), null);
    }
    return web.string(scope, value);
}
pub fn usvString(scope: *Scope, value: c.JSValue) !c.JSValue {
    // Template string coercion rejects Symbol; String(Symbol) would accept it.
    const text = if (c.JS_IsString(value)) value else try scope.stringify(value);
    return scope.invoke(text, "toWellFormed", &.{});
}
pub fn unsignedShort(scope: *Scope, value: c.JSValue) !c.JSValue {
    const math = try scope.global("Math");
    // Source evaluates the bound even in the unflagged conversion path.
    _ = try binary(scope, 1, try scope.invoke(math, "pow", &.{ c.JS_NewInt32(scope.engine.context, 2), c.JS_NewInt32(scope.engine.context, 16) }), c.JS_NewInt32(scope.engine.context, 1));
    var x = try scope.call(try scope.global("Number"), c.pi_js_undefined(), &.{value});
    const zero = c.JS_NewInt32(scope.engine.context, 0);
    if (scope.equal(x, zero)) x = zero;
    const number = try scope.global("Number");
    if (scope.truthy(try scope.invoke(number, "isNaN", &.{x})) or
        (scope.equal(x, zero) and scope.truthy(try scope.invoke(try scope.global("Object"), "is", &.{ zero, x }))) or
        scope.equal(x, try scope.get(number, "POSITIVE_INFINITY")) or scope.equal(x, try scope.get(number, "NEGATIVE_INFINITY"))) return zero;
    const absolute = try scope.invoke(math, "abs", &.{x});
    const integer = try scope.invoke(math, "floor", &.{absolute});
    x = if (scope.truthy(try binary(scope, 4, x, zero))) try binary(scope, 2, c.JS_NewInt32(scope.engine.context, -1), integer) else integer;
    // Actual Undici unflagged unsigned conversion retains negative remainder.
    return binary(scope, 8, x, try scope.invoke(math, "pow", &.{ c.JS_NewInt32(scope.engine.context, 2), c.JS_NewInt32(scope.engine.context, 16) }));
}
fn dictionary(scope: *Scope, init: c.JSValue) !void {
    if (!c.JS_IsNull(init) and !c.JS_IsUndefined(init) and !c.JS_IsObject(init)) {
        const detail = try scope.concat(try scope.concat(try scope.text("undefined: Expected "), try scope.stringify(init)), try scope.text(" to be one of: Null, Undefined, Object."));
        try web.typeError(scope, detail, null);
    }
}
fn member(scope: *Scope, init: c.JSValue, key: [*:0]const u8) !c.JSValue {
    return if (c.JS_IsNull(init) or c.JS_IsUndefined(init)) c.pi_js_undefined() else scope.get(init, key);
}
pub fn responseInit(scope: *Scope, init: c.JSValue) !c.JSValue {
    try dictionary(scope, init);
    const result = try scope.object();
    const status = try member(scope, init, "status");
    try scope.set(result, "status", try unsignedShort(scope, if (c.JS_IsUndefined(status)) c.JS_NewInt32(scope.engine.context, 200) else status));
    const status_text = try member(scope, init, "statusText");
    try scope.set(result, "statusText", try web.byteString(scope, if (c.JS_IsUndefined(status_text)) try scope.text("") else status_text, "undefined", try scope.text("undefined.statusText")));
    const header_init = try member(scope, init, "headers");
    if (!c.JS_IsUndefined(header_init)) try scope.set(result, "headers", try headers.convertInit(scope, header_init, "undefined", try scope.text("undefined.headers")));
    return result;
}
fn bufferSource(scope: *Scope, value: c.JSValue) !bool {
    if (c.JS_IsArrayBuffer(value)) return true;
    if (!scope.truthy(try scope.invoke(try scope.global("ArrayBuffer"), "isView", &.{value}))) return false;
    return c.JS_IsArrayBuffer(try scope.get(value, "buffer"));
}
pub fn bodyInit(scope: *Scope, interfaces: Interfaces, value: c.JSValue, prefix: []const u8, argument: c.JSValue) !c.JSValue {
    if (try interfaces.is(scope, interfaces.readable, value)) return value;
    if (!c.JS_IsNull(value) and !c.JS_IsUndefined(value)) {
        const async_iterator = try scope.own(try scope.engine.checked(c.JS_GetAsyncIteratorSymbol(scope.engine.context)));
        if (scope.truthy(try scope.own(try js.getKey(scope.engine, value, async_iterator)))) return value;
    }
    if (c.JS_IsString(value)) return usvString(scope, value);
    if (try interfaces.is(scope, interfaces.blob, value)) return value;
    if (try bufferSource(scope, value)) return value;
    if (try interfaces.is(scope, interfaces.form_data, value)) return value;
    if (try interfaces.is(scope, interfaces.url_params, value)) return value;
    return domString(scope, value, prefix, argument);
}
pub fn requestInfo(scope: *Scope, interfaces: Interfaces, value: c.JSValue) !c.JSValue {
    if (c.JS_IsString(value)) return usvString(scope, value);
    if (try interfaces.is(scope, interfaces.request, value)) return value;
    return usvString(scope, value);
}
const Converter = enum { byte_string, headers_init, body, usv_string, dom_string, boolean, signal, any };
const Field = struct { key: [*:0]const u8, converter: Converter, allowed: ?[]const []const u8 = null, default: ?[]const u8 = null };
const fields = [_]Field{
    .{ .key = "method", .converter = .byte_string },
    .{ .key = "headers", .converter = .headers_init },
    .{ .key = "body", .converter = .body },
    .{ .key = "referrer", .converter = .usv_string },
    .{ .key = "referrerPolicy", .converter = .dom_string, .allowed = &.{ "", "no-referrer", "no-referrer-when-downgrade", "same-origin", "origin", "strict-origin", "origin-when-cross-origin", "strict-origin-when-cross-origin", "unsafe-url" } },
    .{ .key = "mode", .converter = .dom_string, .allowed = &.{ "navigate", "same-origin", "no-cors", "cors" } },
    .{ .key = "credentials", .converter = .dom_string, .allowed = &.{ "omit", "same-origin", "include" } },
    .{ .key = "cache", .converter = .dom_string, .allowed = &.{ "default", "no-store", "reload", "no-cache", "force-cache", "only-if-cached" } },
    .{ .key = "redirect", .converter = .dom_string, .allowed = &.{ "follow", "manual", "error" } },
    .{ .key = "integrity", .converter = .dom_string },
    .{ .key = "keepalive", .converter = .boolean },
    .{ .key = "signal", .converter = .signal },
    .{ .key = "window", .converter = .any },
    .{ .key = "duplex", .converter = .dom_string, .allowed = &.{"half"} },
    .{ .key = "dispatcher", .converter = .any },
    .{ .key = "priority", .converter = .dom_string, .allowed = &.{ "high", "low", "auto" }, .default = "auto" },
};
pub fn requestInit(scope: *Scope, interfaces: Interfaces, init: c.JSValue) !c.JSValue {
    try dictionary(scope, init);
    const result = try scope.object();
    for (fields) |field| {
        var value = try member(scope, init, field.key);
        if (c.JS_IsUndefined(value)) {
            if (field.default) |default| value = try scope.text(default) else continue;
        }
        const argument = try scope.concat(try scope.text("undefined."), try scope.text(std.mem.span(field.key)));
        value = switch (field.converter) {
            .byte_string => try web.byteString(scope, value, "undefined", argument),
            .headers_init => try headers.convertInit(scope, value, "undefined", argument),
            .body => if (c.JS_IsNull(value)) value else try bodyInit(scope, interfaces, value, "undefined", argument),
            .usv_string => try usvString(scope, value),
            .dom_string => try domString(scope, value, "undefined", argument),
            .boolean => try scope.call(try scope.global("Boolean"), c.pi_js_undefined(), &.{value}),
            .signal => converted: {
                if (c.JS_IsNull(value)) break :converted value;
                if (!try interfaces.is(scope, interfaces.abort_signal, value)) {
                    const message = try scope.concat(try scope.text("RequestInit: Expected signal (\""), try web.stringify(scope, value));
                    try web.typeError(scope, try scope.concat(message, try scope.text("\") to be an instance of AbortSignal.")), null);
                }
                break :converted value;
            },
            .any => value,
        };
        if (field.allowed) |allowed| {
            var accepted = false;
            for (allowed) |option| if (scope.equal(value, try scope.text(option))) {
                accepted = true;
                break;
            };
            if (!accepted) {
                var message = try scope.concat(try scope.text("undefined: "), value);
                message = try scope.concat(message, try scope.text(" is not an accepted type. Expected one of "));
                for (allowed, 0..) |option, position| {
                    if (position > 0) message = try scope.concat(message, try scope.text(", "));
                    message = try scope.concat(message, try scope.text(option));
                }
                try web.typeError(scope, try scope.concat(message, try scope.text(".")), null);
            }
        }
        try scope.set(result, field.key, value);
    }
    return result;
}
const std = @import("std");
