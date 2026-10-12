//! Native TypeBox Evaluate distribution/composite/broaden algebra.
const v = @import("native_chord_type_values.zig");
const Scope = v.Scope;
const js = v.js;
const c = v.c;
const relations = @import("native_chord_type_extends.zig");
fn typeValue(s: *Scope, name: []const u8, args: []const c.JSValue) !c.JSValue {
    return v.constructor(s, name, args);
}
fn append(s: *Scope, target: c.JSValue, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueUint32(s.engine.context, target, try v.length(s, target), s.result(value), c.JS_PROP_C_W_E) < 0) return js.capture(s.engine);
}
fn appendAll(s: *Scope, target: c.JSValue, values: c.JSValue) !void {
    const count = try v.length(s, values);
    for (0..count) |index| try append(s, target, try s.at(values, index));
}
fn propertyMap(s: *Scope, value: c.JSValue) anyerror!c.JSValue {
    if (try v.kind(s, value, "Object")) return s.get(value, "properties");
    if (try v.kind(s, value, "Tuple")) {
        const items = try s.get(value, "items");
        const fields = try s.record();
        const count = try v.length(s, items);
        for (0..count) |index| if (c.JS_DefinePropertyValueUint32(s.engine.context, fields, @intCast(index), s.result(try s.at(items, index)), c.JS_PROP_C_W_E) < 0) return js.capture(s.engine);
        return fields;
    }
    return s.record();
}
fn compositeProperty(s: *Scope, left: c.JSValue, right: c.JSValue) anyerror!c.JSValue {
    const readonly = try v.modifier(s, left, "~readonly") and try v.modifier(s, right, "~readonly");
    const optional = try v.modifier(s, left, "~optional") and try v.modifier(s, right, "~optional");
    const evaluated = try s.keep(try intersection(s.engine, try v.list(s, &.{ left, right })));
    const without_optional = try v.changeModifier(s, evaluated, "~optional", false);
    var property = try v.changeModifier(s, without_optional, "~readonly", false);
    if (optional) property = try v.changeModifier(s, property, "~optional", true);
    if (readonly) property = try v.changeModifier(s, property, "~readonly", true);
    return property;
}
fn composite(s: *Scope, left: c.JSValue, right: c.JSValue) anyerror!c.JSValue {
    const lhs = try propertyMap(s, left);
    const rhs = try propertyMap(s, right);
    const keys = try v.names(s, lhs);
    const additional = try v.names(s, rhs);
    const count = try v.length(s, additional);
    for (0..count) |index| {
        const key = try s.at(additional, index);
        const included = try s.keep(try js.invoke(s.engine, keys, "includes", &.{key}));
        if (c.JS_ToBool(s.engine.context, included) == 0) try append(s, keys, key);
    }
    const result = try s.record();
    const size = try v.length(s, keys);
    for (0..size) |index| {
        const key = try s.at(keys, index);
        const in_left = try js.hasKey(s.engine, lhs, key);
        const in_right = try js.hasKey(s.engine, rhs, key);
        const property = if (in_left) (if (in_right) try compositeProperty(s, try s.key(lhs, key), try s.key(rhs, key)) else try s.key(lhs, key)) else if (in_right) try s.key(rhs, key) else try typeValue(s, "Never", &.{});
        try js.setKey(s.engine, result, key, property);
    }
    return typeValue(s, "Object", &.{result});
}
pub fn narrow(engine: *js.Engine, left: c.JSValue, right: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (try v.kind(&s, left, "Never") or try v.kind(&s, left, "Any")) return s.result(left);
    if (try v.kind(&s, left, "Unknown")) return s.result(right);
    if (try v.kind(&s, right, "Never") or try v.kind(&s, right, "Any")) return s.result(right);
    if (try v.kind(&s, right, "Unknown")) return s.result(left);
    const can_left = try v.kind(&s, left, "Object") or try v.kind(&s, left, "Tuple");
    const can_right = try v.kind(&s, right, "Object") or try v.kind(&s, right, "Tuple");
    if (can_left and can_right) return s.result(try composite(&s, left, right));
    if (can_left) return s.result(left);
    if (can_right) return s.result(right);
    return switch (try relations.compare(engine, left, right)) {
        2 => s.result(left),
        0, 3 => s.result(right),
        else => s.result(try typeValue(&s, "Never", &.{})),
    };
}
fn flatten(s: *Scope, types: c.JSValue, target: c.JSValue) anyerror!void {
    const count = try v.length(s, types);
    for (0..count) |index| {
        const value = try s.at(types, index);
        if (try v.kind(s, value, "Union")) try flatten(s, try s.get(value, "anyOf"), target) else try append(s, target, value);
    }
}
fn broaden(s: *Scope, types: c.JSValue) anyerror!c.JSValue {
    var result = try s.list();
    const count = try v.length(s, types);
    for (0..count) |index| {
        const value = try s.keep(try evaluate(s.engine, try s.at(types, index)));
        if (try v.kind(s, value, "Any") or try v.kind(s, value, "Unknown")) {
            result = try v.list(s, &.{value});
            break;
        }
        if (try v.kind(s, value, "Never")) continue;
        if (try v.kind(s, value, "Object")) {
            try append(s, result, value);
            continue;
        }
        const original = result;
        const next = try s.list();
        const size = try v.length(s, result);
        var contained = false;
        for (0..size) |position| {
            const existing = try s.at(result, position);
            const relation = try relations.compare(s.engine, value, existing);
            if (relation == 2 or relation == 0) {
                contained = true;
                break;
            }
            if (relation == 1) try append(s, next, existing);
        }
        if (contained) {
            result = original;
        } else {
            try append(s, next, value);
            result = next;
        }
    }
    const flattened = try s.list();
    try flatten(s, result, flattened);
    return flattened;
}
fn unionFast(s: *Scope, types: c.JSValue) anyerror!c.JSValue {
    const count = try v.length(s, types);
    if (count == 1) return s.at(types, 0);
    if (count == 0) return typeValue(s, "Never", &.{});
    return typeValue(s, "Union", &.{types});
}
pub fn unionValue(engine: *js.Engine, types: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return s.result(try unionFast(&s, try broaden(&s, types)));
}
fn operation(s: *Scope, left: c.JSValue, right: c.JSValue) anyerror!c.JSValue {
    const lhs = try s.keep(try evaluate(s.engine, left));
    const rhs = try s.keep(try evaluate(s.engine, right));
    return if (try v.kind(s, lhs, "Union") or try v.kind(s, rhs, "Union")) intersection(s.engine, try v.list(s, &.{ lhs, rhs })) else narrow(s.engine, lhs, rhs);
}
fn distribute(s: *Scope, types: c.JSValue, previous: c.JSValue) anyerror!c.JSValue {
    var result = previous;
    const count = try v.length(s, types);
    for (0..count) |index| {
        const value = try s.at(types, index);
        if (try v.kind(s, value, "Union")) {
            const alternatives = try s.get(value, "anyOf");
            const next = try s.list();
            const alternative_count = try v.length(s, alternatives);
            for (0..alternative_count) |position| try appendAll(s, next, try distribute(s, try v.list(s, &.{try s.at(alternatives, position)}), result));
            result = next;
        } else {
            const next = try s.list();
            const size = try v.length(s, result);
            for (0..size) |position| try append(s, next, try s.keep(try operation(s, try s.at(result, position), value)));
            if (size == 0) try append(s, next, value);
            result = next;
        }
    }
    return result;
}
pub fn intersection(engine: *js.Engine, types: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const distributed = try distribute(&s, types, try s.list());
    const broad = try broaden(&s, distributed);
    return unionValue(engine, broad);
}
pub fn enumeration(engine: *js.Engine, values: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const types = try s.list();
    const count = try v.length(&s, values);
    for (0..count) |index| try append(&s, types, try typeValue(&s, "Literal", &.{try s.at(values, index)}));
    return unionValue(engine, types);
}
pub fn template(engine: *js.Engine, pattern: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const literals = try @import("native_typebox_pattern.zig").literals(engine, pattern);
    if (literals) |values| {
        _ = try s.keep(values);
        return enumeration(engine, values);
    }
    return s.result(try typeValue(&s, "String", &.{}));
}
pub fn evaluate(engine: *js.Engine, value: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (try v.kind(&s, value, "Dependent")) return error.NativeTypeBoxDependentEvaluateRequired;
    if (try v.kind(&s, value, "Enum")) return enumeration(engine, try s.get(value, "enum"));
    if (try v.kind(&s, value, "Intersect")) return intersection(engine, try s.get(value, "allOf"));
    if (try v.kind(&s, value, "TemplateLiteral")) return template(engine, try s.get(value, "pattern"));
    if (try v.kind(&s, value, "Union")) return unionValue(engine, try s.get(value, "anyOf"));
    return s.result(value);
}
pub fn priority(engine: *js.Engine, types: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    var sorted = try s.list();
    const count = try v.length(&s, types);
    for (0..count) |index| {
        const value = try s.at(types, index);
        const next = try s.list();
        var inserted = false;
        const size = try v.length(&s, sorted);
        for (0..size) |position| {
            const existing = try s.at(sorted, position);
            if (!inserted) {
                const relation = try relations.compare(engine, value, existing);
                if (relation != 3 and relation != 1) {
                    try append(&s, next, value);
                    inserted = true;
                }
            }
            try append(&s, next, existing);
        }
        if (!inserted) try append(&s, next, value);
        sorted = next;
    }
    return s.result(sorted);
}
