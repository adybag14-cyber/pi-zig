//! Private actual TypeBox Default/Clean workers. Not a public normalize API.
//! Intersect routes through the real native Instantiate/Evaluate engine.
//! Its remaining unported actions fail explicitly; full activation is gated.
const scoped = @import("native_chord_values.zig");
const Scope = scoped.Scope;
const js = scoped.js;
const c = js.c;
const Engine = js.Engine;
pub const Mode = enum { defaults, clean };
fn object(value: c.JSValue, engine: *Engine) bool {
    return c.JS_IsObject(value) and !c.JS_IsFunction(engine.context, value);
}
fn kind(s: *Scope, schema: c.JSValue, name: []const u8) !bool {
    return object(schema, s.engine) and try s.has(schema, "~kind") and try s.equal(try s.get(schema, "~kind"), name);
}
fn array(s: *Scope, value: c.JSValue) !bool {
    return c.JS_ToBool(s.engine.context, try s.builtin("Array", "isArray", &.{value})) != 0;
}
fn length(s: *Scope, value: c.JSValue) !u32 {
    var result: u32 = undefined;
    if (c.JS_ToUint32(s.engine.context, &result, try s.get(value, "length")) < 0) return js.capture(s.engine);
    return result;
}
fn keys(s: *Scope, value: c.JSValue) !c.JSValue {
    return s.builtin("Object", "getOwnPropertyNames", &.{value});
}
fn has(s: *Scope, value: c.JSValue, key: c.JSValue) !bool {
    if (try s.equal(key, "__proto__") or try s.equal(key, "constructor") or try s.equal(key, "prototype")) {
        const owner = try s.keep(try js.global(s.engine, "Object"));
        const prototype = try s.get(owner, "prototype");
        const function = try s.get(prototype, "hasOwnProperty");
        const result = try s.keep(try js.invoke(s.engine, function, "call", &.{ value, key }));
        return c.JS_ToBool(s.engine.context, result) != 0;
    }
    return js.hasKey(s.engine, value, key);
}
fn boolean(value: c.JSValue) bool {
    return c.JS_IsBool(value);
}
fn check(s: *Scope, context: c.JSValue, schema: c.JSValue, value: c.JSValue) !bool {
    return @import("native_tool_validation.zig").checkWithContext(s.engine, context, schema, value);
}
fn remove(s: *Scope, value: c.JSValue, key: c.JSValue) !void {
    const atom = try js.atom(s.engine, key);
    defer c.JS_FreeAtom(s.engine.context, atom);
    if (c.JS_DeleteProperty(s.engine.context, value, atom, c.JS_PROP_THROW) < 0) return js.capture(s.engine);
}
fn fromDefault(s: *Scope, schema: c.JSValue, value: c.JSValue) !c.JSValue {
    if (!c.JS_IsUndefined(value)) return s.result(value);
    if (c.JS_IsFunction(s.engine.context, try s.get(schema, "default"))) return js.invoke(s.engine, schema, "default", &.{});
    return @import("native_chord_clone.zig").clone(s.engine, try s.get(schema, "default"));
}
fn mapped(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return cleanItem(engine, data[0], data[1], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn cleanItem(engine: *Engine, context: c.JSValue, schema: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return visit(engine, .clean, context, try s.get(schema, "items"), value);
}
fn fromArray(s: *Scope, mode: Mode, context: c.JSValue, schema: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    if (!try array(s, value)) return s.result(value);
    if (mode == .clean) {
        var captures = [_]c.JSValue{ context, schema };
        const callback = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, mapped, "", 1, 0, 2, &captures)));
        return js.invoke(s.engine, value, "map", &.{callback});
    }
    var index: u32 = 0;
    while (index < try length(s, value)) : (index += 1) {
        const item = try s.keep(try visit(s.engine, mode, context, try s.get(schema, "items"), try s.at(value, index)));
        if (c.JS_SetPropertyUint32(s.engine.context, value, index, s.result(item)) < 0) return js.capture(s.engine);
    }
    return s.result(value);
}
fn fromTuple(s: *Scope, mode: Mode, context: c.JSValue, schema: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    if (!try array(s, value)) return s.result(value);
    if (mode == .defaults) {
        const items = try s.get(schema, "items");
        const max_value = try s.builtin("Math", "max", &.{ try s.get(try s.get(schema, "items"), "length"), try s.get(value, "length") });
        var max: f64 = undefined;
        if (c.JS_ToFloat64(s.engine.context, &max, max_value) < 0) return js.capture(s.engine);
        var index: u32 = 0;
        while (@as(f64, @floatFromInt(index)) < max) : (index += 1) {
            if (index >= try length(s, items)) continue;
            const item = try s.keep(try visit(s.engine, mode, context, try s.at(items, index), try s.at(value, index)));
            if (c.JS_SetPropertyUint32(s.engine.context, value, index, s.result(item)) < 0) return js.capture(s.engine);
        }
    } else {
        const min_value = try s.builtin("Math", "min", &.{ try s.get(value, "length"), try s.get(try s.get(schema, "items"), "length") });
        var count: u32 = undefined;
        if (c.JS_ToUint32(s.engine.context, &count, min_value) < 0) return js.capture(s.engine);
        for (0..count) |index| {
            const item = try s.keep(try visit(s.engine, mode, context, try s.at(try s.get(schema, "items"), index), try s.at(value, index)));
            if (c.JS_SetPropertyUint32(s.engine.context, value, @intCast(index), s.result(item)) < 0) return js.capture(s.engine);
        }
        if (try length(s, value) > count) return js.invoke(s.engine, value, "slice", &.{ c.JS_NewInt32(s.engine.context, 0), c.JS_NewUint32(s.engine.context, count) });
    }
    return s.result(value);
}
fn additional(s: *Scope, schema: c.JSValue) !c.JSValue {
    return if (try s.has(schema, "additionalProperties")) try s.get(schema, "additionalProperties") else c.pi_js_undefined();
}
fn fromObject(s: *Scope, mode: Mode, context: c.JSValue, schema: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    if (!object(value, s.engine) or (mode == .clean and try array(s, value))) return s.result(value);
    if (mode == .defaults) {
        const known = try keys(s, try s.get(schema, "properties"));
        const count = try length(s, known);
        for (0..count) |index| {
            const key = try s.at(known, index);
            const item = try s.keep(try visit(s.engine, mode, context, try s.key(try s.get(schema, "properties"), key), try s.key(value, key)));
            const optional = if (c.JS_IsUndefined(item)) blk: {
                const property = try s.key(try s.get(schema, "properties"), key);
                break :blk object(property, s.engine) and try s.has(property, "~optional");
            } else false;
            if (c.JS_IsUndefined(item) and (optional or !try s.has(try s.key(try s.get(schema, "properties"), key), "default"))) continue;
            try js.setKey(s.engine, value, key, item);
        }
        if (!try s.has(schema, "additionalProperties") or boolean(try s.get(schema, "additionalProperties"))) return s.result(value);
        const names = try keys(s, value);
        const name_count = try length(s, names);
        for (0..name_count) |index| {
            const key = try s.at(names, index);
            const included = try s.keep(try js.invoke(s.engine, known, "includes", &.{key}));
            if (c.JS_ToBool(s.engine.context, included) != 0) continue;
            const item = try s.keep(try visit(s.engine, mode, context, try s.get(schema, "additionalProperties"), try s.key(value, key)));
            try js.setKey(s.engine, value, key, item);
        }
    } else {
        const extra = try additional(s, schema);
        const names = try keys(s, value);
        const count = try length(s, names);
        for (0..count) |index| {
            const key = try s.at(names, index);
            if (try has(s, try s.get(schema, "properties"), key)) {
                const item = try s.keep(try visit(s.engine, mode, context, try s.key(try s.get(schema, "properties"), key), try s.key(value, key)));
                try js.setKey(s.engine, value, key, item);
                continue;
            }
            const keep = (boolean(extra) and c.JS_ToBool(s.engine.context, extra) != 0) or (object(extra, s.engine) and try check(s, context, extra, try s.key(value, key)));
            if (keep) {
                const item = try s.keep(try visit(s.engine, mode, context, extra, try s.key(value, key)));
                try js.setKey(s.engine, value, key, item);
            } else try remove(s, value, key);
        }
    }
    return s.result(value);
}
fn recordPattern(s: *Scope, schema: c.JSValue) !c.JSValue {
    return s.at(try keys(s, try s.get(schema, "patternProperties")), 0);
}
fn fromRecord(s: *Scope, mode: Mode, context: c.JSValue, schema: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    if (!object(value, s.engine)) return s.result(value);
    const extra = if (mode == .clean) try additional(s, schema) else c.pi_js_undefined();
    const constructor = try s.keep(try js.global(s.engine, "RegExp"));
    const expression = try s.keep(try @import("native_schema_regexp.zig").construct(s.engine, constructor, try recordPattern(s, schema), null));
    const property = try s.key(try s.get(schema, "patternProperties"), try recordPattern(s, schema));
    const names = try keys(s, value);
    const count = try length(s, names);
    for (0..count) |index| {
        const key = try s.at(names, index);
        const matched = c.JS_ToBool(s.engine.context, try s.keep(try js.invoke(s.engine, expression, "test", &.{key}))) != 0;
        if (mode == .defaults) {
            if (!matched or !try s.has(property, "default")) continue;
        } else if (!matched) {
            const keep = (boolean(extra) and c.JS_ToBool(s.engine.context, extra) != 0) or (object(extra, s.engine) and try check(s, context, extra, try s.key(value, key)));
            if (keep) {
                const item = try s.keep(try visit(s.engine, mode, context, extra, try s.key(value, key)));
                try js.setKey(s.engine, value, key, item);
            } else try remove(s, value, key);
            continue;
        }
        const item = try s.keep(try visit(s.engine, mode, context, property, try s.key(value, key)));
        try js.setKey(s.engine, value, key, item);
    }
    if (mode == .defaults and try s.has(schema, "additionalProperties")) {
        const additional_names = try keys(s, value);
        const additional_count = try length(s, additional_names);
        for (0..additional_count) |index| {
            const key = try s.at(additional_names, index);
            if (c.JS_ToBool(s.engine.context, try s.keep(try js.invoke(s.engine, expression, "test", &.{key}))) != 0) continue;
            const item = try s.keep(try visit(s.engine, mode, context, try s.get(schema, "additionalProperties"), try s.key(value, key)));
            try js.setKey(s.engine, value, key, item);
        }
    }
    return s.result(value);
}
fn fromUnion(s: *Scope, mode: Mode, context: c.JSValue, schema: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    const alternatives = try s.get(schema, "anyOf");
    const symbol = try s.keep(try s.engine.checked(c.JS_GetIteratorSymbol(s.engine.context)));
    var iterator = try js.Iterator.init(s.engine, alternatives, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |inner| {
        defer s.engine.freeValue(inner);
        const copy = try s.keep(try @import("native_chord_clone.zig").clone(s.engine, value));
        const candidate = try s.keep(try visit(s.engine, mode, context, inner, copy));
        if (try check(s, context, inner, candidate)) {
            try iterator.close();
            return s.result(candidate);
        }
    }
    return s.result(value);
}
fn fromRef(s: *Scope, mode: Mode, context: c.JSValue, schema: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    if (try has(s, context, try s.get(schema, "$ref"))) return visit(s.engine, mode, context, try s.key(context, try s.get(schema, "$ref")), value);
    return s.result(value);
}
fn fromCyclic(s: *Scope, mode: Mode, context: c.JSValue, schema: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    const definitions = try s.record();
    try js.spreadInto(s.engine, definitions, context);
    try js.spreadInto(s.engine, definitions, try s.get(schema, "$defs"));
    const ref = try s.record();
    try js.define(s.engine, ref, "$ref", s.result(try s.get(schema, "$ref")));
    if (c.JS_DefinePropertyValueStr(s.engine.context, ref, "~kind", s.result(try s.text("Ref")), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(s.engine);
    return visit(s.engine, mode, definitions, ref, value);
}
pub fn visit(engine: *Engine, mode: Mode, context: c.JSValue, schema: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const input = if (mode == .defaults and try s.has(schema, "default")) try s.keep(try fromDefault(&s, schema, value)) else value;
    if (try kind(&s, schema, "Array")) return fromArray(&s, mode, context, schema, input);
    if (try kind(&s, schema, "Cyclic")) return fromCyclic(&s, mode, context, schema, input);
    if (try kind(&s, schema, "Intersect")) {
        const options = try s.record();
        if (mode == .clean and try s.has(schema, "unevaluatedProperties")) try js.define(engine, options, "additionalProperties", s.result(try s.get(schema, "unevaluatedProperties")));
        const instantiated = try s.keep(try @import("native_chord_type_instantiate.zig").instantiate(engine, context, schema));
        const evaluated = try s.keep(try @import("native_chord_type_evaluate.zig").evaluate(engine, instantiated));
        const target = if (mode == .clean and try kind(&s, evaluated, "Object")) try @import("native_chord_type_values.zig").update(&s, evaluated, try s.record(), options) else evaluated;
        return visit(engine, mode, context, target, input);
    }
    if (try kind(&s, schema, "Object")) return fromObject(&s, mode, context, schema, input);
    if (try kind(&s, schema, "Record")) return fromRecord(&s, mode, context, schema, input);
    if (try kind(&s, schema, "Ref")) return fromRef(&s, mode, context, schema, input);
    if (try kind(&s, schema, "Tuple")) return fromTuple(&s, mode, context, schema, input);
    if (try kind(&s, schema, "Union")) return fromUnion(&s, mode, context, schema, input);
    return s.result(input);
}
