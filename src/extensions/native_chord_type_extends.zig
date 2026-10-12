//! Actual TypeBox Extends/Compare dependency, separate from Chord schema fits.
const v = @import("native_chord_type_values.zig");
const Scope = v.Scope;
const js = v.js;
const c = v.c;
fn result(s: *Scope, label: []const u8, inferred: ?c.JSValue) !c.JSValue {
    const fields = try s.record();
    if (inferred) |value| try js.define(s.engine, fields, "inferred", s.result(value));
    return s.result(try v.create(s, label, fields, c.pi_js_undefined()));
}
pub fn trueLike(s: *Scope, value: c.JSValue) !bool {
    return try v.kind(s, value, "ExtendsUnion") or try v.kind(s, value, "ExtendsTrue");
}
fn yes(s: *Scope, inferred: c.JSValue) !c.JSValue {
    return result(s, "ExtendsTrue", inferred);
}
fn no(s: *Scope) !c.JSValue {
    return result(s, "ExtendsFalse", null);
}
fn schema(s: *Scope, label: []const u8, args: []const c.JSValue) !c.JSValue {
    return v.constructor(s, label, args);
}
fn right(inferred: c.JSValue, left: c.JSValue, operand: c.JSValue, s: *Scope) anyerror!c.JSValue {
    if (try v.kind(s, operand, "Any")) return yes(s, inferred);
    if (try v.kind(s, operand, "Dependent")) return error.NativeTypeBoxDependentInferenceRequired;
    if (try v.kind(s, operand, "Enum")) {
        const evaluated = try s.keep(try @import("native_chord_type_evaluate.zig").enumeration(s.engine, try s.get(operand, "enum")));
        return leftward(s.engine, inferred, left, evaluated);
    }
    if (try v.kind(s, operand, "Infer")) return error.NativeTypeBoxInferenceRequired;
    if (try v.kind(s, operand, "Intersect")) return sequence(s, inferred, left, try s.get(operand, "allOf"), true);
    if (try v.kind(s, operand, "TemplateLiteral")) {
        const evaluated = try s.keep(try @import("native_chord_type_evaluate.zig").template(s.engine, try s.get(operand, "pattern")));
        return leftward(s.engine, inferred, left, evaluated);
    }
    if (try v.kind(s, operand, "Union")) return sequence(s, inferred, left, try s.get(operand, "anyOf"), false);
    if (try v.kind(s, operand, "Unknown")) return yes(s, inferred);
    return no(s);
}
fn sequence(s: *Scope, inferred: c.JSValue, left: c.JSValue, alternatives: c.JSValue, all: bool) anyerror!c.JSValue {
    var state = inferred;
    const count = try v.length(s, alternatives);
    for (0..count) |index| {
        const checked = try s.keep(try leftward(s.engine, state, left, try s.at(alternatives, index)));
        if (try trueLike(s, checked)) {
            state = try s.get(checked, "inferred");
            if (!all) return yes(s, state);
        } else if (all) return no(s);
    }
    return if (all) yes(s, state) else no(s);
}
fn properties(s: *Scope, inferred: c.JSValue, left: c.JSValue, right_properties: c.JSValue) anyerror!c.JSValue {
    const compared = try s.record();
    const keys = try v.names(s, right_properties);
    const count = try v.length(s, keys);
    var valid = true;
    for (0..count) |index| {
        const key = try s.at(keys, index);
        const rhs = try s.key(right_properties, key);
        var checked: c.JSValue = undefined;
        if (try js.hasKey(s.engine, left, key)) {
            const lhs = try s.key(left, key);
            if (try v.kind(s, rhs, "Infer")) return error.NativeTypeBoxInferenceRequired;
            checked = try s.keep(try leftward(s.engine, try s.record(), lhs, rhs));
            if (try trueLike(s, checked)) {
                const permissive = !try v.modifier(s, lhs, "~optional") or try v.modifier(s, rhs, "~optional");
                checked = try s.keep(if (permissive) try yes(s, try s.get(checked, "inferred")) else try no(s));
            }
        } else if (try v.modifier(s, rhs, "~optional")) {
            if (try v.kind(s, rhs, "Infer")) return error.NativeTypeBoxInferenceRequired;
            checked = try s.keep(try yes(s, inferred));
        } else checked = try s.keep(try no(s));
        try js.setKey(s.engine, compared, key, checked);
    }
    // Source evaluates every property before testing the aggregate result.
    const values = try s.builtin("Object", "values", &.{compared});
    const value_count = try v.length(s, values);
    for (0..value_count) |index| if (!try trueLike(s, try s.at(values, index))) {
        valid = false;
        break;
    };
    if (!valid) return no(s);
    const extracted = try s.record();
    const names = try v.names(s, compared);
    const name_count = try v.length(s, names);
    for (0..name_count) |index| try js.spreadInto(s.engine, extracted, try s.get(try s.key(compared, try s.at(names, index)), "inferred"));
    const merged = try s.record();
    try js.spreadInto(s.engine, merged, inferred);
    try js.spreadInto(s.engine, merged, extracted);
    return yes(s, merged);
}
fn objectToRecord(s: *Scope, inferred: c.JSValue, properties_left: c.JSValue, operand: c.JSValue) anyerror!c.JSValue {
    _ = try s.at(try v.names(s, try s.get(operand, "patternProperties")), 0);
    const item = try v.recordValue(s, operand);
    const keys = try v.names(s, properties_left);
    const count = try v.length(s, keys);
    const merged = try s.record();
    try js.spreadInto(s.engine, merged, inferred);
    for (0..count) |index| {
        const checked = try s.keep(try leftward(s.engine, try s.record(), try s.key(properties_left, try s.at(keys, index)), item));
        if (!try trueLike(s, checked)) return no(s);
        const additions = try s.get(checked, "inferred");
        const names = try v.names(s, additions);
        const name_count = try v.length(s, names);
        for (0..name_count) |name_index| {
            const key = try s.at(names, name_index);
            const next = try s.key(additions, key);
            if (try js.hasKey(s.engine, merged, key)) {
                const previous = try s.key(merged, key);
                const choices = if (try v.kind(s, previous, "Union")) try s.keep(try @import("native_iterator_spread.zig").snapshot(s.engine, try s.get(previous, "anyOf"))) else try v.list(s, &.{previous});
                try js.push(s.engine, choices, next);
                try js.setKey(s.engine, merged, key, try schema(s, "Union", &.{choices}));
            } else try js.setKey(s.engine, merged, key, next);
        }
    }
    return yes(s, merged);
}
fn tuple(s: *Scope, inferred: c.JSValue, elements: c.JSValue, operand: c.JSValue) anyerror!c.JSValue {
    const left = try s.keep(try @import("native_chord_type_instantiate.zig").elements(s.engine, inferred, elements));
    if (try v.kind(s, operand, "Tuple")) {
        const right_elements = try s.keep(try @import("native_chord_type_instantiate.zig").elements(s.engine, inferred, try s.get(operand, "items")));
        const count = try v.length(s, left);
        if (count != try v.length(s, right_elements)) return no(s);
        var state = inferred;
        for (0..count) |index| {
            const rhs = try s.at(right_elements, index);
            if (try v.kind(s, rhs, "Rest") or try v.kind(s, rhs, "Infer")) return error.NativeTypeBoxInferenceRequired;
            const checked = try s.keep(try leftward(s.engine, state, try s.at(left, index), rhs));
            if (!try trueLike(s, checked)) return no(s);
            state = try s.get(checked, "inferred");
        }
        return yes(s, state);
    }
    if (try v.kind(s, operand, "Array")) {
        const item = try s.get(operand, "items");
        if (try v.kind(s, item, "Infer")) return error.NativeTypeBoxInferenceRequired;
        var state = inferred;
        const count = try v.length(s, left);
        for (0..count) |index| {
            const checked = try s.keep(try leftward(s.engine, state, try s.at(left, index), item));
            if (!try trueLike(s, checked)) return no(s);
            state = try s.get(checked, "inferred");
        }
        return yes(s, state);
    }
    return right(inferred, try schema(s, "Tuple", &.{left}), operand, s);
}
pub fn leftward(engine: *js.Engine, inferred: c.JSValue, left: c.JSValue, operand: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (try v.kind(&s, left, "Any")) {
        if (try v.kind(&s, operand, "Infer")) return right(inferred, left, operand, &s);
        if (try v.kind(&s, operand, "Any") or try v.kind(&s, operand, "Unknown")) return yes(&s, inferred);
        return result(&s, "ExtendsUnion", inferred);
    }
    if (try v.kind(&s, left, "Array")) {
        const item = try s.get(left, "items");
        if (try v.kind(&s, operand, "Array")) {
            const immutable_left = try v.modifier(&s, left, "~immutable");
            const immutable_right = try v.modifier(&s, operand, "~immutable");
            if (immutable_left and !immutable_right) return no(&s);
            return leftward(engine, inferred, item, try s.get(operand, "items"));
        }
        return right(inferred, left, operand, &s);
    }
    inline for (.{ "BigInt", "Boolean" }) |name| if (try v.kind(&s, left, name)) return if (try v.kind(&s, operand, name)) yes(&s, inferred) else right(inferred, left, operand, &s);
    if (try v.kind(&s, left, "Constructor") or try v.kind(&s, left, "Function")) return error.NativeTypeBoxFunctionInferenceRequired;
    if (try v.kind(&s, left, "Dependent")) return error.NativeTypeBoxDependentInferenceRequired;
    if (try v.kind(&s, left, "Enum")) return leftward(engine, inferred, try s.keep(try @import("native_chord_type_evaluate.zig").enumeration(engine, try s.get(left, "enum"))), operand);
    if (try v.kind(&s, left, "Integer")) return if (try v.kind(&s, operand, "Integer") or try v.kind(&s, operand, "Number")) yes(&s, inferred) else right(inferred, left, operand, &s);
    if (try v.kind(&s, left, "Intersect")) return leftward(engine, inferred, try s.keep(try @import("native_chord_type_evaluate.zig").intersection(engine, try s.get(left, "allOf"))), operand);
    if (try v.kind(&s, left, "Literal")) {
        const value = try s.get(left, "const");
        if (try v.kind(&s, operand, "Literal")) return if (c.JS_IsStrictEqual(engine.context, value, try s.get(operand, "const"))) yes(&s, inferred) else no(&s);
        const name: []const u8 = if (c.JS_IsBigInt(value)) "BigInt" else if (c.JS_IsBool(value)) "Boolean" else if (c.JS_IsNumber(value)) "Number" else if (c.JS_IsString(value)) "String" else return error.NativeTypeBoxUnreachableLiteral;
        if (try v.kind(&s, operand, name)) return yes(&s, inferred);
        return right(inferred, try schema(&s, "Literal", &.{value}), operand, &s);
    }
    if (try v.kind(&s, left, "Never")) return if (try v.kind(&s, operand, "Infer")) right(inferred, left, operand, &s) else yes(&s, inferred);
    inline for (.{ "Null", "Number" }) |name| if (try v.kind(&s, left, name)) return if (try v.kind(&s, operand, name)) yes(&s, inferred) else right(inferred, left, operand, &s);
    if (try v.kind(&s, left, "Object")) {
        const fields = try s.get(left, "properties");
        if (try v.kind(&s, operand, "Record")) return objectToRecord(&s, inferred, fields, operand);
        if (try v.kind(&s, operand, "Object")) return properties(&s, inferred, fields, try s.get(operand, "properties"));
        return right(inferred, try schema(&s, "Object", &.{fields}), operand, &s);
    }
    if (try v.kind(&s, left, "Record")) {
        _ = try s.at(try v.names(&s, try s.get(left, "patternProperties")), 0);
        const item = try v.recordValue(&s, left);
        if (try v.kind(&s, operand, "Record")) return leftward(engine, inferred, item, try v.recordValue(&s, operand));
        if (try v.kind(&s, operand, "Object")) return if (try v.length(&s, try v.names(&s, try s.get(operand, "properties"))) == 0) yes(&s, inferred) else no(&s);
        if (try v.kind(&s, operand, "Any") or try v.kind(&s, operand, "Unknown")) return yes(&s, inferred);
        return no(&s);
    }
    inline for (.{ "String", "Symbol" }) |name| if (try v.kind(&s, left, name)) return if (try v.kind(&s, operand, name)) yes(&s, inferred) else right(inferred, left, operand, &s);
    if (try v.kind(&s, left, "TemplateLiteral")) return leftward(engine, inferred, try s.keep(try @import("native_chord_type_evaluate.zig").template(engine, try s.get(left, "pattern"))), operand);
    if (try v.kind(&s, left, "Tuple")) return tuple(&s, inferred, try s.get(left, "items"), operand);
    if (try v.kind(&s, left, "Undefined")) return if (try v.kind(&s, operand, "Void") or try v.kind(&s, operand, "Undefined")) yes(&s, inferred) else right(inferred, left, operand, &s);
    if (try v.kind(&s, left, "Union")) {
        if (try v.kind(&s, operand, "Infer")) return error.NativeTypeBoxInferenceRequired;
        const choices = try s.get(left, "anyOf");
        const others = if (try v.kind(&s, operand, "Union")) try s.get(operand, "anyOf") else try v.list(&s, &.{operand});
        var state = inferred;
        const count = try v.length(&s, choices);
        for (0..count) |index| {
            const checked = try s.keep(try sequence(&s, state, try s.at(choices, index), others, false));
            if (!try trueLike(&s, checked)) return no(&s);
            state = try s.get(checked, "inferred");
        }
        return yes(&s, state);
    }
    if (try v.kind(&s, left, "Unknown")) {
        if (try v.kind(&s, operand, "Infer")) return right(inferred, left, operand, &s);
        return if (try v.kind(&s, operand, "Any") or try v.kind(&s, operand, "Unknown")) yes(&s, inferred) else no(&s);
    }
    if (try v.kind(&s, left, "Void")) return if (try v.kind(&s, operand, "Void")) yes(&s, inferred) else right(inferred, left, operand, &s);
    return no(&s);
}
fn canonical(s: *Scope, value: c.JSValue) !c.JSValue {
    if (try v.kind(s, value, "Cyclic")) return error.NativeTypeBoxCyclicExtendsRequired;
    if (try v.modifier(s, value, "~unsafe")) return schema(s, "Unknown", &.{});
    return value;
}
pub fn compare(engine: *js.Engine, left: c.JSValue, right_value: c.JSValue) anyerror!u2 {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const first = try s.keep(try leftward(engine, try s.record(), try canonical(&s, left), try canonical(&s, right_value)));
    const second = try s.keep(try leftward(engine, try s.record(), try canonical(&s, right_value), try canonical(&s, left)));
    if (try trueLike(&s, first) and try trueLike(&s, second)) return 0;
    if (try trueLike(&s, first) and try v.kind(&s, second, "ExtendsFalse")) return 2;
    if (try v.kind(&s, first, "ExtendsFalse") and try trueLike(&s, second)) return 3;
    return 1;
}
