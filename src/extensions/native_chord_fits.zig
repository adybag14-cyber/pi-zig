//! Chord's conservative structural contract compatibility, not tool coercion.
const std = @import("std");
const scope_module = @import("native_chord_values.zig");
const Scope = scope_module.Scope;
const js = scope_module.js;
const c = js.c;
const Engine = js.Engine;
const canonical = @import("native_chord_canonical.zig");
const constraints = [_][]const u8{ "minLength", "maxLength", "pattern", "format", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf", "minItems", "maxItems", "uniqueItems", "minProperties", "maxProperties" };
const annotations = [_][]const u8{ "title", "description", "default", "examples", "$id", "$schema", "$comment", "readOnly", "writeOnly", "deprecated" };
fn oneOf(key: []const u8, choices: []const []const u8) bool {
    for (choices) |choice| if (std.mem.eql(u8, key, choice)) return true;
    return false;
}
fn length(s: *Scope, value: c.JSValue) !usize {
    const size = try s.get(value, "length");
    var result: u32 = undefined;
    if (c.JS_ToUint32(s.engine.context, &result, size) < 0) return js.capture(s.engine);
    return result;
}
pub fn asSchema(s: *Scope, value: c.JSValue) !c.JSValue {
    if (!c.JS_IsNull(value) and c.JS_IsObject(value) and !c.JS_IsFunction(s.engine.context, value)) return value;
    const result = try s.record();
    if (c.JS_IsStrictEqual(s.engine.context, value, c.pi_js_bool(s.engine.context, 0))) try js.define(s.engine, result, "not", s.result(try s.record()));
    return result;
}
fn withoutAnnotations(s: *Scope, value: c.JSValue) !c.JSValue {
    const schema = try asSchema(s, value);
    const entries = try s.entries(schema);
    const result = try s.record();
    for (0..try length(s, entries)) |index| {
        const entry = try s.at(entries, index);
        const key = try s.at(entry, 0);
        const name = try s.engine.toString(key);
        defer s.engine.gpa.free(name);
        if (oneOf(name, &annotations)) continue;
        const atom = try js.atom(s.engine, key);
        defer c.JS_FreeAtom(s.engine.context, atom);
        if (c.JS_DefinePropertyValue(s.engine.context, result, atom, s.result(try s.at(entry, 1)), c.JS_PROP_C_W_E) < 0) return js.capture(s.engine);
    }
    return result;
}
fn types(s: *Scope, schema: c.JSValue) !c.JSValue {
    const value = try s.get(schema, "type");
    if (c.JS_IsString(value)) {
        const result = try s.list();
        if (c.JS_SetPropertyUint32(s.engine.context, result, 0, s.result(value)) < 0) return js.capture(s.engine);
        return result;
    }
    return if (c.JS_IsArray(value)) value else c.pi_js_undefined();
}
fn includes(s: *Scope, values: c.JSValue, value: c.JSValue) !bool {
    const result = try s.keep(try js.invoke(s.engine, values, "includes", &.{value}));
    return c.JS_ToBool(s.engine.context, result) > 0;
}
fn present(s: *Scope, array: c.JSValue, index: usize) !bool {
    return js.hasKey(s.engine, array, c.JS_NewUint32(s.engine.context, @intCast(index)));
}
pub fn fits(engine: *Engine, sub_input: c.JSValue, sup_input: c.JSValue) anyerror!bool {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const sub = try withoutAnnotations(&s, sub_input);
    const sup = try withoutAnnotations(&s, sup_input);
    const sup_keys = try s.keys(sup);
    if (try length(&s, sup_keys) == 0) return true;
    if (try canonical.deepEqual(engine, sub, sup)) return true;
    for (0..try length(&s, sup_keys)) |index| {
        const key = try engine.toString(try s.at(sup_keys, index));
        defer engine.gpa.free(key);
        if (!oneOf(key, &constraints) and !oneOf(key, &.{ "type", "properties", "required", "additionalProperties", "patternProperties", "items", "additionalItems", "const", "enum", "anyOf", "parameters", "returnType" })) return false;
    }
    const additional = try s.get(sup, "additionalProperties");
    if (!c.JS_IsUndefined(additional) and !c.JS_IsBool(additional)) return false;
    const sub_union = try s.get(sub, "anyOf");
    if (c.JS_IsArray(sub_union)) {
        for (0..try length(&s, sub_union)) |index| if (try present(&s, sub_union, index) and !try fits(engine, try s.at(sub_union, index), sup)) return false;
        return true;
    }
    const sup_union = try s.get(sup, "anyOf");
    if (c.JS_IsArray(sup_union)) {
        for (0..try length(&s, sup_union)) |index| if (try present(&s, sup_union, index) and try fits(engine, sub, try s.at(sup_union, index))) return true;
        return false;
    }
    if (try s.has(sup, "const")) return try s.has(sub, "const") and try canonical.deepEqual(engine, try s.get(sub, "const"), try s.get(sup, "const"));
    const allowed = try s.get(sup, "enum");
    if (c.JS_IsArray(allowed)) {
        var values = try s.get(sub, "enum");
        if (try s.has(sub, "const")) {
            values = try s.list();
            if (c.JS_SetPropertyUint32(engine.context, values, 0, s.result(try s.get(sub, "const"))) < 0) return js.capture(engine);
        } else if (!c.JS_IsArray(values)) return false;
        for (0..try length(&s, values)) |index| {
            if (!try present(&s, values, index)) continue;
            var matched = false;
            for (0..try length(&s, allowed)) |at| if (try present(&s, allowed, at) and try canonical.deepEqual(engine, try s.at(values, index), try s.at(allowed, at))) {
                matched = true;
                break;
            };
            if (!matched) return false;
        }
        return true;
    }
    for (constraints) |key| if (try s.has(sup, key) and !try canonical.deepEqual(engine, try s.key(sub, try s.text(key)), try s.key(sup, try s.text(key)))) return false;
    const sup_types = try types(&s, sup);
    const sub_types = try types(&s, sub);
    if (c.JS_IsUndefined(sup_types) or c.JS_IsUndefined(sub_types)) return false;
    for (0..try length(&s, sub_types)) |index| {
        if (!try present(&s, sub_types, index)) continue;
        const kind = try s.at(sub_types, index);
        if (!try includes(&s, sup_types, kind) and !(try s.equal(kind, "integer") and try includes(&s, sup_types, try s.text("number")))) return false;
    }
    if (try s.has(sub, "const") or c.JS_IsArray(try s.get(sub, "enum"))) return true;
    if (try includes(&s, sub_types, try s.text("object")) and !try objectFits(engine, sub, sup)) return false;
    if (try includes(&s, sub_types, try s.text("array")) and !try arrayFits(engine, sub, sup)) return false;
    if (try includes(&s, sub_types, try s.text("function"))) return functionFits(engine, sub, sup);
    return true;
}
fn objectFits(engine: *Engine, sub: c.JSValue, sup: c.JSValue) anyerror!bool {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const sub_properties = try asSchema(&s, try s.get(sub, "properties"));
    const sup_properties = try asSchema(&s, try s.get(sup, "properties"));
    const sub_required_raw = try s.get(sub, "required");
    const sup_required_raw = try s.get(sup, "required");
    const sub_required = if (c.JS_IsNull(sub_required_raw) or c.JS_IsUndefined(sub_required_raw)) try s.list() else sub_required_raw;
    const sup_required = if (c.JS_IsNull(sup_required_raw) or c.JS_IsUndefined(sup_required_raw)) try s.list() else sup_required_raw;
    for (0..try length(&s, sup_required)) |index| if (!try includes(&s, sub_required, try s.at(sup_required, index))) return false;
    const sup_keys = try s.keys(sup_properties);
    const sub_additional = try s.get(sub, "additionalProperties");
    for (0..try length(&s, sup_keys)) |index| {
        const key = try s.at(sup_keys, index);
        const property = try s.key(sup_properties, key);
        if (try js.hasKey(engine, sub_properties, key)) {
            if (!try fits(engine, try s.key(sub_properties, key), property)) return false;
        } else if ((c.JS_IsNull(sub_additional) or (c.JS_IsObject(sub_additional) and !c.JS_IsFunction(engine.context, sub_additional))) and !try fits(engine, sub_additional, property)) return false;
    }
    const sub_keys = try s.keys(sub_properties);
    if (c.JS_IsStrictEqual(engine.context, try s.get(sup, "additionalProperties"), c.pi_js_bool(engine.context, 0))) {
        if (!c.JS_IsStrictEqual(engine.context, sub_additional, c.pi_js_bool(engine.context, 0))) return false;
        for (0..try length(&s, sub_keys)) |index| if (!try js.hasKey(engine, sup_properties, try s.at(sub_keys, index))) return false;
    }
    const sup_patterns = try asSchema(&s, try s.get(sup, "patternProperties"));
    const patterns = try s.keys(sup_patterns);
    if (try length(&s, patterns) == 0) return true;
    const sub_patterns = try asSchema(&s, try s.get(sub, "patternProperties"));
    const sub_pattern_keys = try s.keys(sub_patterns);
    const has_patterns = try length(&s, sub_pattern_keys) != 0;
    if (!c.JS_IsStrictEqual(engine.context, sub_additional, c.pi_js_bool(engine.context, 0)) and !has_patterns) return false;
    const regexp = try s.keep(try js.global(engine, "RegExp"));
    for (0..try length(&s, patterns)) |index| {
        const pattern = try s.at(patterns, index);
        const property = try s.key(sup_patterns, pattern);
        const matcher = try s.keep(try @import("native_schema_regexp.zig").construct(engine, regexp, pattern, try s.text("u")));
        for (0..try length(&s, sub_keys)) |at| {
            const key = try s.at(sub_keys, at);
            if (try js.hasKey(engine, sup_properties, key)) continue;
            const matched = try s.keep(try js.invoke(engine, matcher, "test", &.{key}));
            if (c.JS_ToBool(engine.context, matched) > 0 and !try fits(engine, try s.key(sub_properties, key), property)) return false;
        }
        if (has_patterns and (!try js.hasKey(engine, sub_patterns, pattern) or !try fits(engine, try s.key(sub_patterns, pattern), property))) return false;
    }
    for (0..try length(&s, sub_pattern_keys)) |index| if (!try js.hasKey(engine, sup_patterns, try s.at(sub_pattern_keys, index))) return false;
    return true;
}
fn arrayFits(engine: *Engine, sub: c.JSValue, sup: c.JSValue) anyerror!bool {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const sub_items = try s.get(sub, "items");
    const sup_items = try s.get(sup, "items");
    if (c.JS_IsArray(sup_items)) {
        if (!c.JS_IsArray(sub_items) or try length(&s, sub_items) != try length(&s, sup_items)) return false;
        for (0..try length(&s, sub_items)) |index| if (try present(&s, sub_items, index) and !try fits(engine, try s.at(sub_items, index), try s.at(sup_items, index))) return false;
        return true;
    }
    if (c.JS_IsArray(sub_items)) {
        for (0..try length(&s, sub_items)) |index| if (try present(&s, sub_items, index) and !try fits(engine, try s.at(sub_items, index), sup_items)) return false;
        return true;
    }
    return fits(engine, sub_items, sup_items);
}
fn functionFits(engine: *Engine, sub: c.JSValue, sup: c.JSValue) anyerror!bool {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const sub_raw = try s.get(sub, "parameters");
    const sup_raw = try s.get(sup, "parameters");
    const sub_parameters = if (c.JS_IsNull(sub_raw) or c.JS_IsUndefined(sub_raw)) try s.list() else sub_raw;
    const sup_parameters = if (c.JS_IsNull(sup_raw) or c.JS_IsUndefined(sup_raw)) try s.list() else sup_raw;
    if (try length(&s, sub_parameters) > try length(&s, sup_parameters)) return false;
    for (0..try length(&s, sub_parameters)) |index| if (try present(&s, sub_parameters, index) and !try fits(engine, try s.at(sup_parameters, index), try s.at(sub_parameters, index))) return false;
    return fits(engine, try s.get(sub, "returnType"), try s.get(sup, "returnType"));
}
