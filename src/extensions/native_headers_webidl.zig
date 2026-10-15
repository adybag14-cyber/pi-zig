//! Actual Node24/Undici7.21 Headers WebIDL conversion order. No host JS body.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const c = em.c;

pub fn typeError(scope: *Scope, message: c.JSValue, code: ?[]const u8) anyerror!noreturn {
    var args = [_]c.JSValue{message};
    const value = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.global("TypeError"), args.len, &args)));
    if (code) |text| try scope.put(value, "code", try scope.text(text));
    _ = try scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, value)));
    unreachable;
}
pub fn arity(scope: *Scope, received: usize, minimum: usize, prefix: []const u8) !void {
    if (received >= minimum) return;
    const bytes = try std.fmt.allocPrint(scope.engine.gpa, "{s}: {d} argument{s} required, but{s} {d} found.", .{ prefix, minimum, if (minimum == 1) "" else "s", if (received == 0) "" else " only", received });
    defer scope.engine.gpa.free(bytes);
    try typeError(scope, try scope.text(bytes), null);
}
pub fn string(scope: *Scope, value: c.JSValue) !c.JSValue {
    return scope.call(try scope.global("String"), c.pi_js_undefined(), &.{value});
}
pub fn stringify(scope: *Scope, value: c.JSValue) !c.JSValue {
    if (c.JS_IsSymbol(value)) return scope.concat(try scope.concat(try scope.text("Symbol("), try scope.get(value, "description")), try scope.text(")"));
    if (c.JS_IsString(value)) return scope.concat(try scope.concat(try scope.text("\""), value), try scope.text("\""));
    if (c.JS_IsBigInt(value)) return scope.concat(try string(scope, value), try scope.text("n"));
    if (c.JS_IsObject(value)) {
        const inspected = try @import("node_event_inspect.zig").inspect(scope.engine, value, 2);
        defer scope.engine.gpa.free(inspected);
        return scope.text(inspected);
    }
    return string(scope, value);
}
pub fn byteString(scope: *Scope, value: c.JSValue, prefix: []const u8, argument: c.JSValue) !c.JSValue {
    if (c.JS_IsSymbol(value)) try typeError(scope, try scope.concat(try scope.concat(try scope.text(prefix), try scope.text(": ")), try scope.concat(argument, try scope.text(" is a symbol, which cannot be converted to a ByteString."))), null);
    const output = try string(scope, value);
    const length = try count(scope, output);
    for (0..length) |offset| {
        const position = number(scope, offset);
        const code = try scope.invoke(output, "charCodeAt", &.{position});
        const larger = try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 6, code, c.JS_NewInt32(scope.engine.context, 255))));
        if (scope.truthy(larger)) {
            var message = try scope.concat(try scope.text("Cannot convert argument to a ByteString because the character at index "), position);
            message = try scope.concat(message, try scope.text(" has a value of "));
            message = try scope.concat(message, try scope.invoke(output, "charCodeAt", &.{position}));
            try typeError(scope, try scope.concat(message, try scope.text(" which is greater than 255.")), null);
        }
    }
    return output;
}
pub fn number(scope: *Scope, value: usize) c.JSValue {
    return c.JS_NewFloat64(scope.engine.context, @floatFromInt(value));
}
pub fn count(scope: *Scope, value: c.JSValue) !usize {
    var length: u32 = 0;
    if (c.JS_ToUint32(scope.engine.context, &length, try scope.get(value, "length")) < 0) return js.capture(scope.engine);
    return length;
}
pub fn index(scope: *Scope, value: c.JSValue, position: usize) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, value, @intCast(position))));
}
pub fn iteratorSymbol(scope: *Scope) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetIteratorSymbol(scope.engine.context)));
}
fn labeled(scope: *Scope, argument: c.JSValue, position: usize) !c.JSValue {
    return scope.concat(try scope.concat(try scope.concat(argument, try scope.text("[")), number(scope, position)), try scope.text("]"));
}
/// Source deliberately does not IteratorClose on conversion errors here.
pub fn sequence(scope: *Scope, value: c.JSValue, outer: bool, prefix: []const u8, argument: c.JSValue, provided: c.JSValue) anyerror!c.JSValue {
    if (!c.JS_IsObject(value)) {
        const detail = try scope.concat(try scope.concat(try scope.concat(argument, try scope.text(" (")), try stringify(scope, value)), try scope.text(") is not iterable."));
        try typeError(scope, try scope.concat(try scope.concat(try scope.text(prefix), try scope.text(": ")), detail), null);
    }
    const method = if (c.JS_IsFunction(scope.engine.context, provided))
        try scope.call(provided, c.pi_js_undefined(), &.{})
    else selected: {
        const iterator = try scope.own(try js.getKey(scope.engine, value, try iteratorSymbol(scope)));
        if (c.JS_IsNull(iterator) or c.JS_IsUndefined(iterator)) break :selected c.pi_js_undefined();
        break :selected try scope.call(iterator, value, &.{});
    };
    if (c.JS_IsNull(method)) try typeError(scope, try scope.text("Cannot read properties of null (reading 'next')"), null);
    if (c.JS_IsUndefined(method) or !c.JS_IsFunction(scope.engine.context, try scope.get(method, "next"))) try typeError(scope, try scope.concat(try scope.concat(try scope.concat(try scope.text(prefix), try scope.text(": ")), argument), try scope.text(" is not iterable.")), null);
    const result = try scope.array();
    var position: usize = 0;
    while (true) {
        const step = try scope.invoke(method, "next", &.{});
        if (c.JS_IsNull(step) or c.JS_IsUndefined(step)) try typeError(scope, try scope.text(if (c.JS_IsNull(step)) "Cannot destructure property 'done' of 'method.next(...)' as it is null." else "Cannot destructure property 'done' of 'method.next(...)' as it is undefined."), null);
        const done = try scope.get(step, "done");
        const item = try scope.get(step, "value");
        if (scope.truthy(done)) break;
        // Resolve push before recursive conversion, exactly like seq.push(...).
        const push = try scope.get(result, "push");
        const label = try labeled(scope, argument, position);
        const converted = if (outer) try sequence(scope, item, false, prefix, label, c.pi_js_undefined()) else try byteString(scope, item, prefix, label);
        _ = try scope.call(push, result, &.{converted});
        position += 1;
    }
    return result;
}
pub fn record(scope: *Scope, value: c.JSValue, prefix: []const u8, argument: c.JSValue) !c.JSValue {
    const result = try scope.object();
    const proxy = c.JS_IsProxy(value);
    const keys = if (proxy)
        try scope.invoke(try scope.global("Reflect"), "ownKeys", &.{value})
    else collected: {
        const object = try scope.global("Object");
        const names = try scope.invoke(object, "getOwnPropertyNames", &.{value});
        const symbols = try scope.invoke(object, "getOwnPropertySymbols", &.{value});
        const combined = try scope.array();
        // Source spreads both arrays in this order; the normal arrays retain
        // exact own-key order, including nonenumerable keys and symbols.
        for (0..try count(scope, names)) |position| try scope.index(combined, @intCast(position), try index(scope, names, position));
        const offset = try count(scope, names);
        for (0..try count(scope, symbols)) |position| try scope.index(combined, @intCast(offset + position), try index(scope, symbols, position));
        break :collected combined;
    };
    for (0..try count(scope, keys)) |position| {
        const key = try index(scope, keys, position);
        if (proxy) {
            const descriptor = try scope.invoke(try scope.global("Reflect"), "getOwnPropertyDescriptor", &.{ value, key });
            if (c.JS_IsUndefined(descriptor) or !scope.truthy(try scope.get(descriptor, "enumerable"))) continue;
        }
        const key_name = if (proxy) c.pi_js_undefined() else try stringify(scope, key);
        const key_argument = if (proxy) argument else try scope.concat(try scope.concat(try scope.concat(try scope.text("Key "), key_name), try scope.text(" in ")), argument);
        const typed_key = try byteString(scope, key, prefix, key_argument);
        const raw_value = try scope.own(try js.getKey(scope.engine, value, key));
        const value_argument = if (proxy) argument else try scope.concat(try scope.concat(try scope.concat(argument, try scope.text("[")), key_name), try scope.text("]"));
        const typed_value = try byteString(scope, raw_value, prefix, value_argument);
        // Ordinary record assignment intentionally preserves Source __proto__
        // setter semantics rather than replacing it with own-property define.
        try js.setKey(scope.engine, result, typed_key, typed_value);
    }
    return result;
}
