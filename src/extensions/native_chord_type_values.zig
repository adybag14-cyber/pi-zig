//! Concrete TypeBox schema-value operations for the native evaluator.
//! Private until settings/metrics and the complete action graph are wired.
const scoped = @import("native_chord_values.zig");
pub const Scope = scoped.Scope;
pub const js = scoped.js;
pub const c = js.c;
pub fn object(s: *Scope, value: c.JSValue) bool {
    return c.JS_IsObject(value) and !c.JS_IsFunction(s.engine.context, value);
}
pub fn kind(s: *Scope, value: c.JSValue, name: []const u8) !bool {
    return object(s, value) and try s.has(value, "~kind") and try s.equal(try s.get(value, "~kind"), name);
}
pub fn modifier(s: *Scope, value: c.JSValue, name: []const u8) !bool {
    return object(s, value) and try s.has(value, name);
}
pub fn length(s: *Scope, value: c.JSValue) !u32 {
    var result: u32 = undefined;
    if (c.JS_ToUint32(s.engine.context, &result, try s.get(value, "length")) < 0) return js.capture(s.engine);
    return result;
}
pub fn names(s: *Scope, value: c.JSValue) !c.JSValue {
    return s.builtin("Object", "getOwnPropertyNames", &.{value});
}
pub fn create(s: *Scope, label: []const u8, fields: c.JSValue, options: c.JSValue) !c.JSValue {
    const value = try s.record();
    try js.spreadInto(s.engine, value, fields);
    try js.spreadInto(s.engine, value, options);
    if (c.JS_DefinePropertyValueStr(s.engine.context, value, "~kind", s.result(try s.text(label)), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(s.engine);
    return value;
}
pub fn update(s: *Scope, value: c.JSValue, hidden: c.JSValue, enumerable: c.JSValue) anyerror!c.JSValue {
    const result = try s.keep(try @import("native_chord_clone.zig").clone(s.engine, value));
    inline for (.{ false, true }) |visible| {
        const fields = if (visible) enumerable else hidden;
        const keys = try s.keys(fields);
        const count = try length(s, keys);
        for (0..count) |index| {
            const key = try s.at(keys, index);
            const atom = try js.atom(s.engine, key);
            defer c.JS_FreeAtom(s.engine.context, atom);
            if (c.JS_DefinePropertyValue(s.engine.context, result, atom, s.result(try s.key(fields, key)), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE | if (visible) @as(c_int, c.JS_PROP_ENUMERABLE) else 0) < 0) return js.capture(s.engine);
        }
    }
    return result;
}
pub fn discard(s: *Scope, value: c.JSValue, omitted: []const []const u8) anyerror!c.JSValue {
    const result = try s.record();
    const keys = try names(s, value);
    const count = try length(s, keys);
    outer: for (0..count) |index| {
        const key = try s.at(keys, index);
        for (omitted) |name| if (try s.equal(key, name)) continue :outer;
        const descriptor = try s.builtin("Object", "getOwnPropertyDescriptor", &.{ value, key });
        const copy = try s.keep(try @import("native_chord_clone.zig").clone(s.engine, try s.get(descriptor, "value")));
        try js.setKey(s.engine, descriptor, try s.text("value"), copy);
        _ = try s.builtin("Object", "defineProperty", &.{ result, key, descriptor });
    }
    return result;
}
pub fn changeModifier(s: *Scope, value: c.JSValue, name: []const u8, add: bool) anyerror!c.JSValue {
    const empty = try s.record();
    const changed = if (add) blk: {
        const hidden = try s.record();
        try js.setKey(s.engine, hidden, try s.text(name), c.pi_js_bool(s.engine.context, 1));
        break :blk try update(s, value, hidden, empty);
    } else try discard(s, value, &.{name});
    return update(s, changed, empty, empty);
}
pub fn constructor(s: *Scope, name: []const u8, args: []const c.JSValue) anyerror!c.JSValue {
    if (@import("std").mem.eql(u8, name, "TemplateLiteral")) {
        const fields = try s.record();
        try js.define(s.engine, fields, "type", s.result(try s.text("string")));
        try js.define(s.engine, fields, "pattern", s.result(args[0]));
        return create(s, name, fields, c.pi_js_undefined());
    }
    if (@import("std").mem.eql(u8, name, "Record") and try kind(s, args[0], "TemplateLiteral")) {
        const pattern = try s.get(args[0], "pattern");
        if (try @import("native_typebox_pattern.zig").patternKind(s.engine, pattern) == .finite) {
            const literals = try s.keep((try @import("native_typebox_pattern.zig").literals(s.engine, pattern)).?);
            const choices = try s.list();
            const count = try length(s, literals);
            for (0..count) |index| try js.push(s.engine, choices, try constructor(s, "Literal", &.{try s.at(literals, index)}));
            return constructor(s, "Record", &.{ try constructor(s, "Union", &.{choices}), args[1], if (args.len > 2) args[2] else c.pi_js_undefined() });
        }
        const patterns = try s.record();
        try js.setKey(s.engine, patterns, pattern, args[1]);
        const fields = try s.record();
        try js.define(s.engine, fields, "type", s.result(try s.text("object")));
        try js.define(s.engine, fields, "patternProperties", s.result(patterns));
        const record = try create(s, "Record", fields, c.pi_js_undefined());
        return update(s, record, try s.record(), if (args.len > 2 and !c.JS_IsUndefined(args[2])) args[2] else try s.record());
    }
    if (@import("std").mem.eql(u8, name, "Never")) {
        const fields = try s.record();
        try js.define(s.engine, fields, "not", s.result(try s.record()));
        return create(s, name, fields, if (args.len > 0) args[0] else c.pi_js_undefined());
    }
    if (@import("std").mem.eql(u8, name, "Undefined") or @import("std").mem.eql(u8, name, "Void") or @import("std").mem.eql(u8, name, "BigInt") or @import("std").mem.eql(u8, name, "Symbol")) {
        const fields = try s.record();
        try js.define(s.engine, fields, "type", s.result(try s.text(if (@import("std").mem.eql(u8, name, "Undefined")) "undefined" else if (@import("std").mem.eql(u8, name, "Void")) "void" else if (@import("std").mem.eql(u8, name, "BigInt")) "bigint" else "symbol")));
        return create(s, name, fields, if (args.len > 0) args[0] else c.pi_js_undefined());
    }
    if (@import("std").mem.eql(u8, name, "Tuple")) {
        const fields = try s.record();
        try js.define(s.engine, fields, "type", s.result(try s.text("array")));
        try js.define(s.engine, fields, "additionalItems", c.pi_js_bool(s.engine.context, 0));
        try js.define(s.engine, fields, "items", s.result(args[0]));
        try js.define(s.engine, fields, "minItems", s.result(try s.get(args[0], "length")));
        return create(s, name, fields, if (args.len > 1) args[1] else c.pi_js_undefined());
    }
    if (@import("std").mem.eql(u8, name, "Ref")) {
        const fields = try s.record();
        try js.define(s.engine, fields, "$ref", s.result(args[0]));
        return create(s, name, fields, if (args.len > 1) args[1] else c.pi_js_undefined());
    }
    if (@import("std").mem.eql(u8, name, "Readonly") or @import("std").mem.eql(u8, name, "Immutable")) return changeModifier(s, args[0], if (@import("std").mem.eql(u8, name, "Readonly")) "~readonly" else "~immutable", true);
    const types = try s.keep(try @import("typebox.zig").create(s.engine));
    const method = try s.key(types, try s.text(name));
    return s.keep(try js.call(s.engine, method, types, args));
}
pub fn list(s: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try s.list();
    for (values, 0..) |value, index| if (c.JS_DefinePropertyValueUint32(s.engine.context, result, @intCast(index), s.result(value), c.JS_PROP_C_W_E) < 0) return js.capture(s.engine);
    return result;
}
pub fn recordValue(s: *Scope, schema: c.JSValue) !c.JSValue {
    const properties = try s.get(schema, "patternProperties");
    return s.key(properties, try s.at(try names(s, try s.get(schema, "patternProperties")), 0));
}
