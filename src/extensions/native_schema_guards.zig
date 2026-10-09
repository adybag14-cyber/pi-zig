//! Pinned TypeBox schema-keyword admission. Invalid keyword shapes are ignored
//! by the original compiler; nested schema dictionaries validate their entire
//! enumerable value set before any constraint is applied.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub fn assertRoot(engine: *Engine, value: c.JSValue) !void {
    if (c.JS_IsBool(value) or c.JS_IsObject(value)) return;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const string = try vm.get(engine, global, "String");
    defer engine.freeValue(string);
    var args = [_]c.JSValue{value};
    const rendered = try engine.checked(c.JS_Call(engine.context, string, c.pi_js_undefined(), 1, &args));
    defer engine.freeValue(rendered);
    const label = try engine.toString(rendered);
    defer engine.gpa.free(label);
    const terminated = try engine.gpa.dupeZ(u8, label);
    defer engine.gpa.free(terminated);
    _ = try engine.checked(c.JS_ThrowTypeError(engine.context, "Cannot use 'in' operator to search for 'type' in %s", terminated.ptr));
    unreachable;
}
pub fn schema(value: c.JSValue) bool {
    return c.JS_IsBool(value) or (c.JS_IsObject(value) and !c.JS_IsArray(value));
}
fn schemaFor(engine: *Engine, value: c.JSValue) bool {
    return schema(value) and !c.JS_IsFunction(engine.context, value);
}
fn array(engine: *Engine, value: c.JSValue, strings: bool) !bool {
    if (!c.JS_IsArray(value)) return false;
    for (0..try vm.length(engine, value)) |index| {
        const atom = c.JS_NewAtomUInt32(engine.context, @intCast(index));
        defer c.JS_FreeAtom(engine.context, atom);
        const present = c.JS_HasProperty(engine.context, value, atom);
        if (present < 0) return error.JavaScriptException;
        if (present == 0) continue;
        const item = try engine.checked(c.JS_GetPropertyUint32(engine.context, value, @intCast(index)));
        defer engine.freeValue(item);
        if (strings) {
            if (!c.JS_IsString(item)) return false;
        } else if (!schemaFor(engine, item)) return false;
    }
    return true;
}
fn dictionary(engine: *Engine, value: c.JSValue, mode: enum { schemas, strings, mixed }) !bool {
    if (!c.JS_IsObject(value) or c.JS_IsFunction(engine.context, value)) return false;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const object = try vm.get(engine, global, "Object");
    defer engine.freeValue(object);
    const values = try vm.invoke(engine, object, "values", &.{value});
    defer engine.freeValue(values);
    for (0..try vm.length(engine, values)) |index| {
        const item = try engine.checked(c.JS_GetPropertyUint32(engine.context, values, @intCast(index)));
        defer engine.freeValue(item);
        const entry_valid = switch (mode) {
            .schemas => schemaFor(engine, item),
            .strings => try array(engine, item, true),
            .mixed => schemaFor(engine, item) or try array(engine, item, true),
        };
        if (!entry_valid) return false;
    }
    return true;
}
pub fn pattern(engine: *Engine, value: c.JSValue) !bool {
    if (c.JS_IsString(value)) return true;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try vm.get(engine, global, "RegExp");
    defer engine.freeValue(constructor);
    const result = c.JS_IsInstanceOf(engine.context, value, constructor);
    if (result < 0) {
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
        unreachable;
    }
    return result != 0;
}
pub fn compilePattern(engine: *Engine, value: c.JSValue) !c.JSValue {
    if (!c.JS_IsString(value)) return c.JS_DupValue(engine.context, value);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try vm.get(engine, global, "RegExp");
    defer engine.freeValue(constructor);
    const flags = try engine.checked(c.JS_NewString(engine.context, "u"));
    defer engine.freeValue(flags);
    return @import("native_schema_regexp.zig").construct(engine, constructor, value, flags);
}
pub fn valid(engine: *Engine, key: []const u8, value: c.JSValue) !bool {
    if (std.mem.eql(u8, key, "~refine")) {
        if (!c.JS_IsArray(value)) return false;
        for (0..try vm.length(engine, value)) |index| {
            const atom = c.JS_NewAtomUInt32(engine.context, @intCast(index));
            defer c.JS_FreeAtom(engine.context, atom);
            const present = c.JS_HasProperty(engine.context, value, atom);
            if (present < 0) return error.JavaScriptException;
            if (present == 0) continue;
            const entry = try engine.checked(c.JS_GetPropertyUint32(engine.context, value, @intCast(index)));
            defer engine.freeValue(entry);
            if (!c.JS_IsObject(entry) or c.JS_IsFunction(engine.context, entry)) return false;
            for ([_][:0]const u8{ "check", "error" }) |name| {
                const key_atom = c.JS_NewAtom(engine.context, name.ptr);
                defer c.JS_FreeAtom(engine.context, key_atom);
                const found = c.JS_HasProperty(engine.context, entry, key_atom);
                if (found < 0) return error.JavaScriptException;
                if (found == 0) return false;
                const callback = try vm.get(engine, entry, name);
                defer engine.freeValue(callback);
                if (!c.JS_IsFunction(engine.context, callback)) return false;
            }
        }
        return true;
    }
    for ([_][]const u8{ "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf", "minItems", "maxItems", "minContains", "maxContains", "minLength", "maxLength", "minProperties", "maxProperties" }) |name| if (std.mem.eql(u8, key, name)) {
        if (c.JS_IsBigInt(value)) return std.mem.eql(u8, key, "minimum") or std.mem.eql(u8, key, "maximum") or std.mem.eql(u8, key, "exclusiveMinimum") or std.mem.eql(u8, key, "exclusiveMaximum") or std.mem.eql(u8, key, "multipleOf");
        if (!c.JS_IsNumber(value)) return false;
        var number: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &number, value) < 0) return error.JavaScriptException;
        return std.math.isFinite(number);
    };
    if (std.mem.eql(u8, key, "type")) return c.JS_IsString(value) or try array(engine, value, true);
    if (std.mem.eql(u8, key, "required")) return array(engine, value, true);
    if (std.mem.eql(u8, key, "enum")) return c.JS_IsArray(value);
    if (std.mem.eql(u8, key, "uniqueItems")) return c.JS_IsBool(value);
    if (std.mem.eql(u8, key, "format")) return c.JS_IsString(value);
    if (std.mem.eql(u8, key, "pattern")) return pattern(engine, value);
    for ([_][]const u8{ "additionalItems", "additionalProperties", "contains", "if", "then", "else", "not", "propertyNames", "unevaluatedItems", "unevaluatedProperties" }) |name| if (std.mem.eql(u8, key, name)) return schemaFor(engine, value);
    for ([_][]const u8{ "allOf", "anyOf", "oneOf", "prefixItems" }) |name| if (std.mem.eql(u8, key, name)) return array(engine, value, false);
    if (std.mem.eql(u8, key, "items")) return schemaFor(engine, value) or try array(engine, value, false);
    for ([_][]const u8{ "properties", "patternProperties", "dependentSchemas" }) |name| if (std.mem.eql(u8, key, name)) return dictionary(engine, value, .schemas);
    if (std.mem.eql(u8, key, "dependentRequired")) return dictionary(engine, value, .strings);
    if (std.mem.eql(u8, key, "dependencies")) return dictionary(engine, value, .mixed);
    return true;
}
pub fn read(engine: *Engine, object: c.JSValue, key: [:0]const u8) !c.JSValue {
    const value = try vm.get(engine, object, key);
    errdefer engine.freeValue(value);
    if (c.JS_IsUndefined(value)) return value;
    if (try valid(engine, key, value)) return value;
    engine.freeValue(value);
    return c.pi_js_undefined();
}
