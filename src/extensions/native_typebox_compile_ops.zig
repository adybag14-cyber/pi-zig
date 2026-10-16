//! VM operations used by directly authored TypeBox 1.3.27 algorithm bodies.
//! Lexical cells are private null-prototype VM objects, traced by function captures.
const std = @import("std");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = js.c;
const Engine = js.Engine;
pub fn boolean(s: *Scope, value: bool) c.JSValue {
    return c.pi_js_bool(s.engine.context, @intFromBool(value));
}
pub fn frame(s: *Scope, parent: c.JSValue) !c.JSValue {
    const result = try s.own(try s.engine.checked(c.JS_NewObjectProto(s.engine.context, c.pi_js_null())));
    try s.put(result, "@parent", parent);
    return result;
}
pub fn lookup(s: *Scope, initial: c.JSValue, key: [*:0]const u8) !c.JSValue {
    const atom = c.JS_NewAtom(s.engine.context, key);
    if (atom == c.JS_ATOM_NULL) return js.capture(s.engine);
    defer c.JS_FreeAtom(s.engine.context, atom);
    var current = initial;
    while (c.JS_IsObject(current)) {
        const present = c.JS_HasProperty(s.engine.context, current, atom);
        if (present < 0) return js.capture(s.engine);
        if (present != 0) return s.get(current, key);
        current = try s.get(current, "@parent");
    }
    return c.pi_js_undefined();
}
pub fn assign(s: *Scope, initial: c.JSValue, key: [*:0]const u8, value: c.JSValue) !void {
    const atom = c.JS_NewAtom(s.engine.context, key);
    if (atom == c.JS_ATOM_NULL) return js.capture(s.engine);
    defer c.JS_FreeAtom(s.engine.context, atom);
    var current = initial;
    while (c.JS_IsObject(current)) {
        const present = c.JS_HasProperty(s.engine.context, current, atom);
        if (present < 0) return js.capture(s.engine);
        if (present != 0) {
            try s.set(current, key, value);
            return;
        }
        current = try s.get(current, "@parent");
    }
    try s.put(initial, key, value);
}
pub fn importValue(s: *Scope, graph: c.JSValue, module: [*:0]const u8, name: [*:0]const u8) !c.JSValue {
    const modules = try s.get(graph, "modules");
    const namespace = try s.get(modules, module);
    if (std.mem.eql(u8, std.mem.span(name), "*")) return namespace;
    return s.get(namespace, name);
}
pub fn defineKey(s: *Scope, target: c.JSValue, key: c.JSValue, value: c.JSValue) !void {
    const atom = try js.atom(s.engine, key);
    defer c.JS_FreeAtom(s.engine.context, atom);
    if (c.JS_DefinePropertyValue(s.engine.context, target, atom, c.JS_DupValue(s.engine.context, value), c.JS_PROP_C_W_E) < 0) return js.capture(s.engine);
}
pub fn propertyKey(s: *Scope, key: c.JSValue) !c.JSValue {
    const atom = try js.atom(s.engine, key);
    defer c.JS_FreeAtom(s.engine.context, atom);
    return s.own(try s.engine.checked(c.JS_AtomToValue(s.engine.context, atom)));
}
pub fn deleteKey(s: *Scope, target: c.JSValue, key: c.JSValue) !c.JSValue {
    const atom = try js.atom(s.engine, key);
    defer c.JS_FreeAtom(s.engine.context, atom);
    const result = c.JS_DeleteProperty(s.engine.context, target, atom, c.JS_PROP_THROW);
    if (result < 0) return js.capture(s.engine);
    return boolean(s, result != 0);
}
pub fn append(s: *Scope, target: c.JSValue, value: c.JSValue) !void {
    const length = try s.get(target, "length");
    var index: u32 = 0;
    if (c.JS_ToUint32(s.engine.context, &index, length) < 0) return js.capture(s.engine);
    try s.index(target, index, value);
}
pub fn arrayHole(s: *Scope, target: c.JSValue) !void {
    const length = try s.get(target, "length");
    const next = try s.own(try s.engine.checked(c.JS_PiIncrement(s.engine.context, length)));
    try s.set(target, "length", next);
}
pub fn iterator(e: *Engine, value: c.JSValue) !js.Iterator {
    const symbol = try e.checked(c.JS_GetIteratorSymbol(e.context));
    defer e.freeValue(symbol);
    return js.Iterator.init(e, value, symbol);
}
pub fn spreadArray(s: *Scope, target: c.JSValue, value: c.JSValue) !void {
    var iter = try iterator(s.engine, value);
    defer iter.deinit();
    errdefer iter.closePreserving();
    while (try iter.next()) |item| {
        defer s.engine.freeValue(item);
        try append(s, target, item);
    }
}
pub fn rest(s: *Scope, args: []const c.JSValue, start: usize) !c.JSValue {
    const array = try s.array();
    for (args[@min(start, args.len)..]) |item| try append(s, array, item);
    return array;
}
pub fn construct(s: *Scope, function: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, function, @intCast(args.len), @constCast(args.ptr))));
}
pub fn callSpread(s: *Scope, function: c.JSValue, receiver: c.JSValue, array: c.JSValue) !c.JSValue {
    const length = try s.get(array, "length");
    var count: u32 = 0;
    if (c.JS_ToUint32(s.engine.context, &count, length) < 0) return js.capture(s.engine);
    const args = try s.engine.gpa.alloc(c.JSValue, count);
    defer s.engine.gpa.free(args);
    for (args, 0..) |*item, i| item.* = try s.own(try s.engine.checked(c.JS_GetPropertyUint32(s.engine.context, array, @intCast(i))));
    return s.call(function, receiver, args);
}
pub fn arrow(s: *Scope, name: [*:0]const u8, length: c_int, callback: c.JSCFunctionData, roots: []const c.JSValue) !c.JSValue {
    return s.own(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, name, length, 0, @intCast(roots.len), @constCast(roots.ptr))));
}
pub fn instanceOf(s: *Scope, left: c.JSValue, right: c.JSValue) !c.JSValue {
    const result = c.JS_IsInstanceOf(s.engine.context, left, right);
    if (result < 0) return js.capture(s.engine);
    return boolean(s, result != 0);
}
pub fn toNumber(s: *Scope, value: c.JSValue) !c.JSValue {
    return s.own(try s.engine.checked(c.JS_ToNumber(s.engine.context, value)));
}
pub fn typeOf(s: *Scope, value: c.JSValue) !c.JSValue {
    const name: []const u8 = if (c.JS_IsUndefined(value)) "undefined" else if (c.JS_IsNull(value)) "object" else if (c.JS_IsBool(value)) "boolean" else if (c.JS_IsNumber(value)) "number" else if (c.JS_IsBigInt(value)) "bigint" else if (c.JS_IsString(value)) "string" else if (c.JS_IsSymbol(value)) "symbol" else if (c.JS_IsFunction(s.engine.context, value)) "function" else "object";
    return s.text(name);
}
pub fn negate(s: *Scope, value: c.JSValue) !c.JSValue {
    const numeric = try s.own(try s.engine.checked(c.JS_PiToNumeric(s.engine.context, value)));
    const multiplier = if (c.JS_IsBigInt(numeric)) try s.own(try s.engine.checked(c.JS_NewBigInt64(s.engine.context, -1))) else c.JS_NewInt32(s.engine.context, -1);
    return s.own(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, 2, numeric, multiplier)));
}
pub fn constructWithTarget(s: *Scope, super: c.JSValue, target: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return s.own(try s.engine.checked(c.JS_CallConstructor2(s.engine.context, super, target, @intCast(args.len), @constCast(args.ptr))));
}
pub fn derivedPrototype(s: *Scope, super: c.JSValue) !c.JSValue {
    const prototype = try s.get(super, "prototype");
    return s.own(try s.engine.checked(c.JS_NewObjectProto(s.engine.context, prototype)));
}
pub fn setPrototype(s: *Scope, target: c.JSValue, prototype: c.JSValue) !void {
    if (c.JS_SetPrototype(s.engine.context, target, prototype) < 0) return js.capture(s.engine);
}
pub fn method(s: *Scope, target: c.JSValue, name: [*:0]const u8, function: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(s.engine.context, target, name, c.JS_DupValue(s.engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(s.engine);
}
