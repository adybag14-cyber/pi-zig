//! Native port of pinned Node24 V8 Object::GetMethod and its side-effect-free
//! PropertyNotFunction diagnostic arguments (objects.cc/js-objects.cc).
//! Data-property lookup stops at accessors/proxies without executing guest code.
const a = @import("native_tui_alt_frame.zig");
const c = a.c;
const js = a.js;
const Frame = a.Frame;
const utf16 = @import("native_utf16.zig");

pub fn typeError(f: *Frame, message: c.JSValue) !void {
    const constructor = try f.get(f.bindings, "typeError");
    const value = try f.construct(constructor, &.{message});
    _ = try f.engine.checked(c.JS_Throw(f.engine.context, c.JS_DupValue(f.engine.context, value)));
    unreachable;
}
// These C APIs inspect only QuickJS proxy metadata. The checked implementation
// can throw here only when the proxy is revoked; it never calls a guest trap.
fn proxyTarget(f: *Frame, value: c.JSValue) !?c.JSValue {
    const target = c.JS_GetProxyTarget(f.engine.context, value);
    if (c.JS_IsException(target)) {
        f.engine.freeValue(c.JS_GetException(f.engine.context));
        return null;
    }
    return try f.own(target);
}
pub fn checkGet(f: *Frame, value: c.JSValue) !void {
    if (c.JS_IsProxy(value) and try proxyTarget(f, value) == null)
        try typeError(f, try f.text("Cannot perform 'get' on a proxy that has been revoked"));
}
pub fn get(f: *Frame, value: c.JSValue, name: [*:0]const u8) !c.JSValue {
    try checkGet(f, value);
    return f.get(value, name);
}
pub fn getKey(f: *Frame, value: c.JSValue, key: c.JSValue) !c.JSValue {
    try checkGet(f, value);
    return f.own(try js.getKey(f.engine, value, key));
}
fn dataProperty(f: *Frame, value: c.JSValue, key: c.JSValue) !c.JSValue {
    const atom = try js.atom(f.engine, key);
    defer c.JS_FreeAtom(f.engine.context, atom);
    var current = value;
    while (c.JS_IsObject(current)) {
        // V8 GetDataProperty refuses proxy/accessor traversal, including a
        // proxy in an ordinary object's prototype chain.
        if (c.JS_IsProxy(current)) return c.pi_js_undefined();
        var descriptor: c.JSPropertyDescriptor = undefined;
        const present = c.JS_GetOwnProperty(f.engine.context, &descriptor, current, atom);
        if (present < 0) return js.capture(f.engine);
        if (present != 0) {
            defer f.engine.freeValue(descriptor.value);
            defer f.engine.freeValue(descriptor.getter);
            defer f.engine.freeValue(descriptor.setter);
            if (descriptor.flags & c.JS_PROP_GETSET != 0) return c.pi_js_undefined();
            return f.own(c.JS_DupValue(f.engine.context, descriptor.value));
        }
        current = try f.own(try f.engine.checked(c.JS_GetPrototype(f.engine.context, current)));
    }
    return c.pi_js_undefined();
}
fn data(f: *Frame, value: c.JSValue, key: []const u8) !c.JSValue {
    return dataProperty(f, value, try f.text(key));
}
fn same(f: *Frame, left: c.JSValue, right: c.JSValue) bool {
    return c.JS_IsStrictEqual(f.engine.context, left, right);
}
fn intrinsicString(f: *Frame, key: [*:0]const u8, value: c.JSValue) !c.JSValue {
    return f.call(try f.get(f.bindings, key), value, &.{});
}
pub fn noSideEffectsString(f: *Frame, input: c.JSValue) anyerror!c.JSValue {
    var value = input;
    while (c.JS_IsProxy(value)) value = try proxyTarget(f, value) orelse return f.text("null");
    if (!c.JS_IsObject(value) and !c.JS_IsSymbol(value))
        return f.own(try f.engine.checked(c.JS_ToString(f.engine.context, value)));
    if (c.JS_IsSymbol(value)) {
        const text = try intrinsicString(f, "symbolToString", value);
        const units = try utf16.unitsAlloc(f.engine, text);
        defer f.engine.gpa.free(units);
        // Symbol( + description + ). V8 truncates only descriptions >128 units.
        if (units.len <= 136) return text;
        return f.concat(&.{ try f.own(try utf16.string(f.engine, units[0..63])), try f.text("...<omitted>..."), try f.own(try utf16.string(f.engine, units[units.len - 57 ..])) });
    }
    if (c.JS_IsFunction(f.engine.context, value)) {
        const text = try intrinsicString(f, "functionToString", value);
        const units = try utf16.unitsAlloc(f.engine, text);
        defer f.engine.gpa.free(units);
        if (units.len <= 128) return text;
        return f.concat(&.{ try f.own(try utf16.string(f.engine, units[0..111])), try f.text("...<omitted>..."), try f.own(try utf16.string(f.engine, units[units.len - 2 ..])) });
    }
    const to_string = try data(f, value, "toString");
    if (c.JS_IsError(value) or same(f, to_string, try f.get(f.bindings, "errorToString"))) {
        const raw_name = try data(f, value, "name");
        const raw_message = try data(f, value, "message");
        const name = if (c.JS_IsString(raw_name)) raw_name else try f.text("");
        const message = if (c.JS_IsString(raw_message)) raw_message else try f.text("");
        if (try f.is(name, "")) return message;
        if (try f.is(message, "")) return name;
        return f.concat(&.{ name, try f.text(": "), message });
    }
    if (same(f, to_string, try f.get(f.bindings, "objectToString"))) {
        const constructor = try data(f, value, "constructor");
        if (c.JS_IsFunction(f.engine.context, constructor)) {
            const name = try data(f, constructor, "name");
            if (c.JS_IsString(name) and !try f.is(name, "")) return f.concat(&.{ try f.text("#<"), name, try f.text(">") });
        }
    }
    const raw_tag = try dataProperty(f, value, try f.get(f.bindings, "tagSymbol"));
    var tag = raw_tag;
    if (!c.JS_IsString(tag)) {
        const atom = c.JS_GetClassName(f.engine.runtime, c.JS_GetClassID(value));
        if (atom == c.JS_ATOM_NULL) return f.text("[object Unknown]");
        defer c.JS_FreeAtom(f.engine.context, atom);
        tag = try f.own(try f.engine.checked(c.JS_AtomToString(f.engine.context, atom)));
    }
    return f.concat(&.{ try f.text("[object "), tag, try f.text("]") });
}
pub fn propertyNotFunction(f: *Frame, value: c.JSValue, key: c.JSValue, receiver: c.JSValue) !void {
    try typeError(f, try f.concat(&.{ try f.text("'"), try noSideEffectsString(f, value), try f.text("' returned for property '"), try noSideEffectsString(f, key), try f.text("' of object '"), try noSideEffectsString(f, receiver), try f.text("' is not a function") }));
}
