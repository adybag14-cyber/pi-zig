//! Native Zig construction of extension JSON-schema values.
const std = @import("std");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const sdk = @import("native_values.zig");

const Kind = enum(c_int) { Any, Unknown, String, Number, Integer, Boolean, Null, Literal, Array, Union, Intersect, Optional, Object, Record };
pub fn install(engine: *engine_mod.Engine) !void {
    try @import("native_schema_formats.zig").install(engine);
    if (engine.native_module_names.contains("typebox")) return;
    const types = try create(engine);
    defer engine.freeValue(types);
    const namespace = try engine.valueNamespace(types);
    defer engine.freeValue(namespace);
    const exports = try sdk.object(engine);
    defer engine.freeValue(exports);
    if (!copyProperties(engine.context, exports, types, false)) return error.JavaScriptException;
    try sdk.put(engine, exports, "Type", c.JS_DupValue(engine.context, namespace));
    try sdk.put(engine, exports, "default", c.JS_DupValue(engine.context, namespace));
    try engine.registerValueModule("typebox", exports);
    if (!engine.native_module_names.contains("@sinclair/typebox")) try engine.registerValueModule("@sinclair/typebox", exports);
}

pub fn create(engine: *engine_mod.Engine) !c.JSValue {
    const object = try engine.checked(c.JS_NewObject(engine.context));
    errdefer engine.freeValue(object);
    inline for (std.meta.fields(Kind)) |field| {
        const name: [:0]const u8 = field.name;
        const function = try engine.checked(c.pi_js_function_magic(engine.context, construct, if (field.value == @intFromEnum(Kind.Object)) "_Object_" else if (field.value == @intFromEnum(Kind.Array)) "_Array_" else name.ptr, if (field.value == @intFromEnum(Kind.Array) or field.value == @intFromEnum(Kind.Literal) or field.value == @intFromEnum(Kind.Record)) 2 else 1, @intCast(field.value)));
        if (c.JS_DefinePropertyValueStr(engine.context, object, name.ptr, function, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    return object;
}

fn put(context: ?*c.JSContext, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) bool {
    return c.JS_DefinePropertyValueStr(context, target, name, value, c.JS_PROP_C_W_E) >= 0;
}

fn copyProperties(context: ?*c.JSContext, target: c.JSValue, source: c.JSValue, skip_optional: bool) bool {
    if (!c.JS_IsObject(source)) return true;
    var properties: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(context, &properties, &count, source, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK | c.JS_GPN_ENUM_ONLY) < 0) return false;
    defer c.JS_FreePropertyEnum(context, properties, count);
    for (0..count) |index| {
        const name = c.JS_AtomToCString(context, properties[index].atom);
        if (name == null) return false;
        defer c.JS_FreeCString(context, name);
        if (skip_optional and std.mem.eql(u8, std.mem.span(name), "__piOptional")) continue;
        const value = c.JS_GetProperty(context, source, properties[index].atom);
        if (c.JS_IsException(value)) return false;
        if (c.JS_DefinePropertyValue(context, target, properties[index].atom, value, c.JS_PROP_C_W_E) < 0) return false;
    }
    return true;
}

fn construct(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const kind: Kind = @enumFromInt(magic);
    const first = if (argc > 0) argv[0] else c.pi_js_undefined();
    const result = c.JS_NewObject(context);
    if (c.JS_IsException(result)) return result;
    var successful = true;
    const type_name: ?[*:0]const u8 = switch (kind) {
        .String => "string",
        .Number => "number",
        .Integer => "integer",
        .Boolean => "boolean",
        .Null => "null",
        .Array => "array",
        .Object, .Record => "object",
        else => null,
    };
    if (type_name) |name| successful = put(context, result, "type", c.JS_NewString(context, name));
    switch (kind) {
        .Any, .Unknown, .String, .Number, .Integer, .Boolean, .Null => {
            successful = successful and copyProperties(context, result, first, false);
        },
        .Literal => {
            const name: [*:0]const u8 = if (c.JS_IsNull(first)) "null" else if (c.JS_IsBool(first)) "boolean" else if (c.JS_IsNumber(first)) "number" else "string";
            successful = successful and put(context, result, "type", c.JS_NewString(context, name));
            successful = successful and put(context, result, "const", c.JS_DupValue(context, first));
            if (argc > 1) successful = successful and copyProperties(context, result, argv[1], false);
        },
        .Array => {
            successful = successful and put(context, result, "items", c.JS_DupValue(context, first));
            if (argc > 1) successful = successful and copyProperties(context, result, argv[1], false);
        },
        .Union, .Intersect => {
            successful = successful and put(context, result, if (kind == .Union) "anyOf" else "allOf", c.JS_DupValue(context, first));
            if (argc > 1) successful = successful and copyProperties(context, result, argv[1], false);
        },
        .Optional => {
            const engine = engine_mod.Engine.fromContext(context.?);
            var active: std.ArrayList(c.JSValue) = .empty;
            defer active.deinit(engine.gpa);
            const copied = cloneMemory(engine, first, &active) catch |err| {
                c.JS_FreeValue(context, result);
                if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
                return engine.throwCaptured();
            };
            defer engine.freeValue(copied);
            successful = successful and copySchemaProperties(context, result, copied);
            successful = successful and c.JS_DefinePropertyValueStr(context, result, "~optional", c.pi_js_bool(context, 1), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) >= 0;
        },
        .Record => {
            const engine = engine_mod.Engine.fromContext(context.?);
            c.JS_FreeValue(context, result);
            return record(engine, first, if (argc > 1) argv[1] else c.pi_js_undefined(), if (argc > 2) argv[2] else c.pi_js_undefined()) catch |err| {
                if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
                return engine.throwCaptured();
            };
        },
        .Object => {
            const properties = c.JS_DupValue(context, first);
            defer c.JS_FreeValue(context, properties);
            const required = c.JS_NewArray(context);
            defer c.JS_FreeValue(context, required);
            if (c.JS_IsException(properties) or c.JS_IsException(required)) successful = false;
            var names: [*c]c.JSPropertyEnum = null;
            var count: u32 = 0;
            var required_count: u32 = 0;
            if (!c.JS_IsObject(first) or c.JS_GetOwnPropertyNames(context, &names, &count, first, c.JS_GPN_STRING_MASK) < 0) successful = false;
            defer if (names != null) c.JS_FreePropertyEnum(context, names, count);
            for (0..count) |index| {
                if (!successful) break;
                const schema = c.JS_GetProperty(context, first, names[index].atom);
                defer c.JS_FreeValue(context, schema);
                if (c.JS_IsException(schema)) {
                    successful = false;
                    break;
                }
                const optional_atom = c.JS_NewAtom(context, "~optional");
                defer c.JS_FreeAtom(context, optional_atom);
                const optional = if (c.JS_IsObject(schema)) c.JS_HasProperty(context, schema, optional_atom) else 0;
                if (optional < 0) {
                    successful = false;
                    break;
                }
                if (optional == 0) {
                    const name = c.JS_AtomToString(context, names[index].atom);
                    successful = successful and c.JS_SetPropertyUint32(context, required, required_count, name) >= 0;
                    required_count += 1;
                }
            }
            if (required_count > 0) successful = successful and put(context, result, "required", c.JS_DupValue(context, required));
            successful = successful and put(context, result, "properties", c.JS_DupValue(context, properties));
            if (argc > 1) successful = successful and copyProperties(context, result, argv[1], false);
        },
    }
    if (kind != .Optional) successful = successful and c.JS_DefinePropertyValueStr(context, result, "~kind", c.JS_NewString(context, @tagName(kind)), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) >= 0;
    if (!successful) {
        c.JS_FreeValue(context, result);
        if (c.JS_HasException(context)) return c.JS_Throw(context, c.JS_GetException(context));
        return c.JS_ThrowTypeError(context, "Native schema construction failed");
    }
    return result;
}
fn record(engine: *engine_mod.Engine, key: c.JSValue, value: c.JSValue, options: c.JSValue) !c.JSValue {
    const properties = try sdk.object(engine);
    defer engine.freeValue(properties);
    var pattern: ?c.JSValue = null;
    var labels: std.ArrayList(c.JSValue) = .empty;
    defer {
        for (labels.items) |label| engine.freeValue(label);
        labels.deinit(engine.gpa);
    }
    try recordKeys(engine, key, properties, value, &pattern, &labels, false);
    const base = try sdk.object(engine);
    defer engine.freeValue(base);
    try sdk.put(engine, base, "type", try engine.checked(c.JS_NewString(engine.context, "object")));
    if (pattern) |expression_value| {
        const expression = try engine.toString(expression_value);
        defer engine.gpa.free(expression);
        const patterns = try sdk.object(engine);
        defer engine.freeValue(patterns);
        const atom = c.JS_NewAtomLen(engine.context, expression.ptr, expression.len);
        defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DefinePropertyValue(engine.context, patterns, atom, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        try sdk.put(engine, base, "patternProperties", c.JS_DupValue(engine.context, patterns));
    } else {
        const required = try sdk.array(engine);
        defer engine.freeValue(required);
        var names: [*c]c.JSPropertyEnum = null;
        var count: u32 = 0;
        if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, properties, c.JS_GPN_STRING_MASK) < 0) return error.JavaScriptException;
        defer c.JS_FreePropertyEnum(engine.context, names, count);
        const optional_atom = c.JS_NewAtom(engine.context, "~optional");
        defer c.JS_FreeAtom(engine.context, optional_atom);
        const optional = if (c.JS_IsObject(value)) c.JS_HasProperty(engine.context, value, optional_atom) else 0;
        if (optional < 0) return error.JavaScriptException;
        if (optional == 0 and count != 0) {
            for (0..count) |index| if (c.JS_SetPropertyUint32(engine.context, required, @intCast(index), try engine.checked(c.JS_AtomToString(engine.context, names[index].atom))) < 0) return error.JavaScriptException;
            try sdk.put(engine, base, "required", c.JS_DupValue(engine.context, required));
        }
        try sdk.put(engine, base, "properties", c.JS_DupValue(engine.context, properties));
    }
    if (c.JS_DefinePropertyValueStr(engine.context, base, "~kind", c.JS_NewString(engine.context, if (pattern == null) "Object" else "Record"), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    var active: std.ArrayList(c.JSValue) = .empty;
    defer active.deinit(engine.gpa);
    const result = try cloneMemory(engine, base, &active);
    errdefer engine.freeValue(result);
    if (!copyProperties(engine.context, result, options, false)) return error.JavaScriptException;
    return result;
}
fn recordPattern(engine: *engine_mod.Engine, pattern: *?c.JSValue, labels: *std.ArrayList(c.JSValue), text: []const u8) !void {
    const label = try engine.checked(c.JS_NewStringLen(engine.context, text.ptr, text.len));
    errdefer engine.freeValue(label);
    try labels.append(engine.gpa, label);
    pattern.* = label;
}
fn recordKeys(engine: *engine_mod.Engine, key: c.JSValue, properties: c.JSValue, value: c.JSValue, pattern: *?c.JSValue, labels: *std.ArrayList(c.JSValue), in_union: bool) anyerror!void {
    if (!c.JS_IsObject(key)) return;
    const kind = try sdk.get(engine, key, "~kind");
    defer engine.freeValue(kind);
    if (!c.JS_IsString(kind)) return;
    const name = try engine.toString(kind);
    defer engine.gpa.free(name);
    if (std.mem.eql(u8, name, "Any") or std.mem.eql(u8, name, "String") or std.mem.eql(u8, name, "Number") or std.mem.eql(u8, name, "Integer")) {
        if (in_union and std.mem.eql(u8, name, "Any")) return;
        if (in_union or std.mem.eql(u8, name, "Any")) {
            try recordPattern(engine, pattern, labels, "^.*$");
        } else if (std.mem.eql(u8, name, "String")) {
            const raw = try sdk.get(engine, key, "pattern");
            defer engine.freeValue(raw);
            if (c.JS_IsString(raw) or c.JS_IsObject(raw)) {
                const text = try engine.toString(raw);
                defer engine.gpa.free(text);
                try recordPattern(engine, pattern, labels, text);
            } else try recordPattern(engine, pattern, labels, "^.*$");
        } else try recordPattern(engine, pattern, labels, if (std.mem.eql(u8, name, "Integer")) "^-?(?:0|[1-9][0-9]*)$" else "^-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?$");
        return;
    }
    if (std.mem.eql(u8, name, "Union")) {
        const choices = try sdk.get(engine, key, "anyOf");
        defer engine.freeValue(choices);
        for (0..try sdk.length(engine, choices)) |index| {
            const choice = try engine.checked(c.JS_GetPropertyUint32(engine.context, choices, @intCast(index)));
            defer engine.freeValue(choice);
            try recordKeys(engine, choice, properties, value, pattern, labels, true);
        }
        return;
    }
    if (std.mem.eql(u8, name, "Intersect") and !in_union) {
        const choices = try intersectKeys(engine, key);
        defer {
            for (choices.items) |choice| engine.freeValue(choice);
            var owned_choices = choices;
            owned_choices.deinit(engine.gpa);
        }
        for (choices.items) |choice| try recordKeys(engine, choice, properties, value, pattern, labels, choices.items.len > 1);
        return;
    }
    if (std.mem.eql(u8, name, "Boolean") and !in_union) {
        try sdk.put(engine, properties, "true", c.JS_DupValue(engine.context, value));
        try sdk.put(engine, properties, "false", c.JS_DupValue(engine.context, value));
    } else if (std.mem.eql(u8, name, "Literal")) {
        const literal = try sdk.get(engine, key, "const");
        defer engine.freeValue(literal);
        if (in_union and !c.JS_IsString(literal) and !c.JS_IsNumber(literal)) return;
        const label = try engine.toString(literal);
        defer engine.gpa.free(label);
        const atom = c.JS_NewAtomLen(engine.context, label.ptr, label.len);
        defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DefinePropertyValue(engine.context, properties, atom, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
}
fn keyKind(engine: *engine_mod.Engine, key: c.JSValue) ![]u8 {
    if (!c.JS_IsObject(key)) return engine.gpa.dupe(u8, "Unknown");
    const kind = try sdk.get(engine, key, "~kind");
    defer engine.freeValue(kind);
    return if (c.JS_IsString(kind)) engine.toString(kind) else engine.gpa.dupe(u8, "Unknown");
}
fn ownKey(engine: *engine_mod.Engine, list: *std.ArrayList(c.JSValue), key: c.JSValue) !void {
    const owned = c.JS_DupValue(engine.context, key);
    errdefer engine.freeValue(owned);
    try list.append(engine.gpa, owned);
}
fn keyChoices(engine: *engine_mod.Engine, key: c.JSValue, list: *std.ArrayList(c.JSValue)) anyerror!void {
    const kind = try keyKind(engine, key);
    defer engine.gpa.free(kind);
    if (std.mem.eql(u8, kind, "Union")) {
        const values = try sdk.get(engine, key, "anyOf");
        defer engine.freeValue(values);
        for (0..try sdk.length(engine, values)) |index| {
            const child = try engine.checked(c.JS_GetPropertyUint32(engine.context, values, @intCast(index)));
            defer engine.freeValue(child);
            try keyChoices(engine, child, list);
        }
    } else if (std.mem.eql(u8, kind, "Intersect")) {
        var nested = try intersectKeys(engine, key);
        defer {
            for (nested.items) |child| engine.freeValue(child);
            nested.deinit(engine.gpa);
        }
        for (nested.items) |child| try ownKey(engine, list, child);
    } else try ownKey(engine, list, key);
}
fn insideKey(engine: *engine_mod.Engine, left: c.JSValue, right: c.JSValue) !bool {
    const lhs = try keyKind(engine, left);
    defer engine.gpa.free(lhs);
    const rhs = try keyKind(engine, right);
    defer engine.gpa.free(rhs);
    if (std.mem.eql(u8, rhs, "Any") or std.mem.eql(u8, rhs, "Unknown") or std.mem.eql(u8, lhs, "Never")) return true;
    if (std.mem.eql(u8, lhs, "Literal")) {
        const literal = try sdk.get(engine, left, "const");
        defer engine.freeValue(literal);
        if (std.mem.eql(u8, rhs, "Literal")) {
            const other = try sdk.get(engine, right, "const");
            defer engine.freeValue(other);
            return c.JS_IsStrictEqual(engine.context, literal, other);
        }
        return (std.mem.eql(u8, rhs, "String") and c.JS_IsString(literal)) or (std.mem.eql(u8, rhs, "Number") and c.JS_IsNumber(literal)) or (std.mem.eql(u8, rhs, "Boolean") and c.JS_IsBool(literal));
    }
    if (std.mem.eql(u8, lhs, "Array") and std.mem.eql(u8, rhs, "Array")) {
        const l = try sdk.get(engine, left, "items");
        defer engine.freeValue(l);
        const r = try sdk.get(engine, right, "items");
        defer engine.freeValue(r);
        return insideKey(engine, l, r);
    }
    if (std.mem.eql(u8, lhs, "Record") and std.mem.eql(u8, rhs, "Record")) {
        const l = try firstRecordValue(engine, left);
        defer engine.freeValue(l);
        const r = try firstRecordValue(engine, right);
        defer engine.freeValue(r);
        return insideKey(engine, l, r);
    }
    return std.mem.eql(u8, lhs, rhs) or (std.mem.eql(u8, lhs, "Integer") and std.mem.eql(u8, rhs, "Number"));
}
fn narrowKey(engine: *engine_mod.Engine, left: c.JSValue, right: c.JSValue) !c.JSValue {
    const lhs = try keyKind(engine, left);
    defer engine.gpa.free(lhs);
    const rhs = try keyKind(engine, right);
    defer engine.gpa.free(rhs);
    if (std.mem.eql(u8, lhs, "Never") or std.mem.eql(u8, lhs, "Any")) return c.JS_DupValue(engine.context, left);
    if (std.mem.eql(u8, lhs, "Unknown")) return c.JS_DupValue(engine.context, right);
    if (std.mem.eql(u8, rhs, "Never") or std.mem.eql(u8, rhs, "Any")) return c.JS_DupValue(engine.context, right);
    if (std.mem.eql(u8, rhs, "Unknown")) return c.JS_DupValue(engine.context, left);
    const l_composite = std.mem.eql(u8, lhs, "Object") or std.mem.eql(u8, lhs, "Tuple");
    const r_composite = std.mem.eql(u8, rhs, "Object") or std.mem.eql(u8, rhs, "Tuple");
    if (l_composite and r_composite) return composite(engine, left, right);
    if (l_composite) return c.JS_DupValue(engine.context, left);
    if (r_composite) return c.JS_DupValue(engine.context, right);
    const l_inside = try insideKey(engine, left, right);
    const r_inside = try insideKey(engine, right, left);
    if (r_inside) return c.JS_DupValue(engine.context, right);
    if (l_inside) return c.JS_DupValue(engine.context, left);
    const never = try sdk.object(engine);
    errdefer engine.freeValue(never);
    if (c.JS_DefinePropertyValueStr(engine.context, never, "~kind", c.JS_NewString(engine.context, "Never"), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    return never;
}
fn firstRecordValue(engine: *engine_mod.Engine, schema: c.JSValue) !c.JSValue {
    const patterns = try sdk.get(engine, schema, "patternProperties");
    defer engine.freeValue(patterns);
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, patterns, c.JS_GPN_STRING_MASK) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    return if (count == 0) c.pi_js_undefined() else engine.checked(c.JS_GetProperty(engine.context, patterns, names[0].atom));
}
fn compositeProperties(engine: *engine_mod.Engine, schema: c.JSValue) !c.JSValue {
    const kind = try keyKind(engine, schema);
    defer engine.gpa.free(kind);
    if (std.mem.eql(u8, kind, "Object")) return sdk.get(engine, schema, "properties");
    const properties = try sdk.object(engine);
    errdefer engine.freeValue(properties);
    if (std.mem.eql(u8, kind, "Tuple")) {
        const items = try sdk.get(engine, schema, "items");
        defer engine.freeValue(items);
        for (0..try sdk.length(engine, items)) |index| if (c.JS_SetPropertyUint32(engine.context, properties, @intCast(index), try engine.checked(c.JS_GetPropertyUint32(engine.context, items, @intCast(index)))) < 0) return error.JavaScriptException;
    }
    return properties;
}
fn modifier(engine: *engine_mod.Engine, schema: c.JSValue, name: [:0]const u8) !bool {
    if (!c.JS_IsObject(schema) or c.JS_IsFunction(engine.context, schema)) return false;
    const atom = c.JS_NewAtom(engine.context, name);
    defer c.JS_FreeAtom(engine.context, atom);
    const present = c.JS_HasProperty(engine.context, schema, atom);
    if (present < 0) return error.JavaScriptException;
    return present > 0;
}
fn objectSchema(engine: *engine_mod.Engine, properties: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "type", try engine.checked(c.JS_NewString(engine.context, "object")));
    const required = try sdk.array(engine);
    defer engine.freeValue(required);
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    var next: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, properties, c.JS_GPN_STRING_MASK) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for (0..count) |index| {
        const property = try engine.checked(c.JS_GetProperty(engine.context, properties, names[index].atom));
        defer engine.freeValue(property);
        if (!try modifier(engine, property, "~optional")) {
            if (c.JS_SetPropertyUint32(engine.context, required, next, try engine.checked(c.JS_AtomToString(engine.context, names[index].atom))) < 0) return error.JavaScriptException;
            next += 1;
        }
    }
    if (next != 0) try sdk.put(engine, result, "required", c.JS_DupValue(engine.context, required));
    try sdk.put(engine, result, "properties", c.JS_DupValue(engine.context, properties));
    if (c.JS_DefinePropertyValueStr(engine.context, result, "~kind", c.JS_NewString(engine.context, "Object"), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    return result;
}
fn composite(engine: *engine_mod.Engine, left: c.JSValue, right: c.JSValue) anyerror!c.JSValue {
    const lhs = try compositeProperties(engine, left);
    defer engine.freeValue(lhs);
    const rhs = try compositeProperties(engine, right);
    defer engine.freeValue(rhs);
    const properties = try sdk.object(engine);
    defer engine.freeValue(properties);
    for ([_]c.JSValue{ lhs, rhs }) |source| {
        var names: [*c]c.JSPropertyEnum = null;
        var count: u32 = 0;
        if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, source, c.JS_GPN_STRING_MASK) < 0) return error.JavaScriptException;
        defer c.JS_FreePropertyEnum(engine.context, names, count);
        for (0..count) |index| {
            const atom = names[index].atom;
            const exists = c.JS_HasProperty(engine.context, properties, atom);
            if (exists < 0) return error.JavaScriptException;
            if (exists > 0) continue;
            const l = c.JS_HasProperty(engine.context, lhs, atom);
            if (l < 0) return error.JavaScriptException;
            const r = c.JS_HasProperty(engine.context, rhs, atom);
            if (r < 0) return error.JavaScriptException;
            if (l > 0 and r > 0) {
                const first = try engine.checked(c.JS_GetProperty(engine.context, lhs, atom));
                defer engine.freeValue(first);
                const second = try engine.checked(c.JS_GetProperty(engine.context, rhs, atom));
                defer engine.freeValue(second);
                const intersection = try sdk.object(engine);
                defer engine.freeValue(intersection);
                const items = try sdk.array(engine);
                defer engine.freeValue(items);
                if (c.JS_SetPropertyUint32(engine.context, items, 0, c.JS_DupValue(engine.context, first)) < 0 or c.JS_SetPropertyUint32(engine.context, items, 1, c.JS_DupValue(engine.context, second)) < 0) return error.JavaScriptException;
                try sdk.put(engine, intersection, "allOf", c.JS_DupValue(engine.context, items));
                if (c.JS_DefinePropertyValueStr(engine.context, intersection, "~kind", c.JS_NewString(engine.context, "Intersect"), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
                const evaluated = try evaluateIntersection(engine, intersection);
                defer engine.freeValue(evaluated);
                const copied = try sdk.object(engine);
                var copied_consumed = false;
                errdefer if (!copied_consumed) engine.freeValue(copied);
                var child_names: [*c]c.JSPropertyEnum = null;
                var child_count: u32 = 0;
                if (c.JS_GetOwnPropertyNames(engine.context, &child_names, &child_count, evaluated, c.JS_GPN_STRING_MASK) < 0) return error.JavaScriptException;
                defer c.JS_FreePropertyEnum(engine.context, child_names, child_count);
                for (0..child_count) |child_index| {
                    const label = c.JS_AtomToCString(engine.context, child_names[child_index].atom) orelse return error.OutOfMemory;
                    defer c.JS_FreeCString(engine.context, label);
                    if (std.mem.eql(u8, std.mem.span(label), "~optional") or std.mem.eql(u8, std.mem.span(label), "~readonly")) continue;
                    var descriptor: c.JSPropertyDescriptor = undefined;
                    if (c.JS_GetOwnProperty(engine.context, &descriptor, evaluated, child_names[child_index].atom) < 0) return error.JavaScriptException;
                    defer engine.freeValue(descriptor.value);
                    defer engine.freeValue(descriptor.getter);
                    defer engine.freeValue(descriptor.setter);
                    if (c.JS_DefinePropertyValue(engine.context, copied, child_names[child_index].atom, c.JS_DupValue(engine.context, descriptor.value), descriptor.flags) < 0) return error.JavaScriptException;
                }
                inline for (.{ "~optional", "~readonly" }) |name| if (try modifier(engine, first, name) and try modifier(engine, second, name)) {
                    if (c.JS_DefinePropertyValueStr(engine.context, copied, name, c.pi_js_bool(engine.context, 1), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
                };
                copied_consumed = true;
                if (c.JS_DefinePropertyValue(engine.context, properties, atom, copied, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
            } else if (c.JS_DefinePropertyValue(engine.context, properties, atom, try engine.checked(c.JS_GetProperty(engine.context, if (l > 0) lhs else rhs, atom)), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        }
    }
    return objectSchema(engine, properties);
}
pub fn evaluateIntersection(engine: *engine_mod.Engine, schema: c.JSValue) !c.JSValue {
    var choices = try intersectKeys(engine, schema);
    defer {
        for (choices.items) |choice| engine.freeValue(choice);
        choices.deinit(engine.gpa);
    }
    if (choices.items.len == 1) return c.JS_DupValue(engine.context, choices.items[0]);
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    if (choices.items.len == 0) {
        try sdk.put(engine, result, "not", try sdk.object(engine));
        if (c.JS_DefinePropertyValueStr(engine.context, result, "~kind", c.JS_NewString(engine.context, "Never"), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    } else {
        const items = try sdk.array(engine);
        defer engine.freeValue(items);
        for (choices.items, 0..) |choice, index| if (c.JS_SetPropertyUint32(engine.context, items, @intCast(index), c.JS_DupValue(engine.context, choice)) < 0) return error.JavaScriptException;
        try sdk.put(engine, result, "anyOf", c.JS_DupValue(engine.context, items));
        if (c.JS_DefinePropertyValueStr(engine.context, result, "~kind", c.JS_NewString(engine.context, "Union"), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    }
    return result;
}
fn intersectKeys(engine: *engine_mod.Engine, key: c.JSValue) anyerror!std.ArrayList(c.JSValue) {
    var result: std.ArrayList(c.JSValue) = .empty;
    errdefer {
        for (result.items) |child| engine.freeValue(child);
        result.deinit(engine.gpa);
    }
    const operands = try sdk.get(engine, key, "allOf");
    defer engine.freeValue(operands);
    for (0..try sdk.length(engine, operands)) |index| {
        const operand = try engine.checked(c.JS_GetPropertyUint32(engine.context, operands, @intCast(index)));
        defer engine.freeValue(operand);
        var choices: std.ArrayList(c.JSValue) = .empty;
        defer {
            for (choices.items) |choice| engine.freeValue(choice);
            choices.deinit(engine.gpa);
        }
        try keyChoices(engine, operand, &choices);
        if (index == 0) {
            for (choices.items) |choice| try ownKey(engine, &result, choice);
        } else {
            var next: std.ArrayList(c.JSValue) = .empty;
            errdefer {
                for (next.items) |child| engine.freeValue(child);
                next.deinit(engine.gpa);
            }
            for (result.items) |left| for (choices.items) |right| {
                const narrowed = try narrowKey(engine, left, right);
                next.append(engine.gpa, narrowed) catch |err| {
                    engine.freeValue(narrowed);
                    return err;
                };
            };
            for (result.items) |child| engine.freeValue(child);
            result.deinit(engine.gpa);
            result = next;
        }
    }
    var broadened: std.ArrayList(c.JSValue) = .empty;
    errdefer {
        for (broadened.items) |child| engine.freeValue(child);
        broadened.deinit(engine.gpa);
    }
    for (result.items) |candidate| {
        const kind = try keyKind(engine, candidate);
        defer engine.gpa.free(kind);
        if (std.mem.eql(u8, kind, "Never")) continue;
        if (std.mem.eql(u8, kind, "Any") or std.mem.eql(u8, kind, "Unknown")) {
            for (broadened.items) |prior| engine.freeValue(prior);
            broadened.clearRetainingCapacity();
            try ownKey(engine, &broadened, candidate);
            break;
        }
        var contained = false;
        if (!std.mem.eql(u8, kind, "Object")) for (broadened.items) |prior| if (try insideKey(engine, candidate, prior)) {
            contained = true;
            break;
        };
        if (contained) continue;
        var prior_index = broadened.items.len;
        while (prior_index > 0) {
            prior_index -= 1;
            if (try insideKey(engine, broadened.items[prior_index], candidate)) engine.freeValue(broadened.orderedRemove(prior_index));
        }
        try ownKey(engine, &broadened, candidate);
    }
    for (result.items) |child| engine.freeValue(child);
    result.deinit(engine.gpa);
    return broadened;
}
fn copySchemaProperties(context: ?*c.JSContext, target: c.JSValue, source: c.JSValue) bool {
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(context, &names, &count, source, c.JS_GPN_STRING_MASK) < 0) return false;
    defer c.JS_FreePropertyEnum(context, names, count);
    for (0..count) |index| {
        var descriptor: c.JSPropertyDescriptor = undefined;
        if (c.JS_GetOwnProperty(context, &descriptor, source, names[index].atom) < 0) return false;
        defer c.JS_FreeValue(context, descriptor.value);
        defer c.JS_FreeValue(context, descriptor.getter);
        defer c.JS_FreeValue(context, descriptor.setter);
        if (c.JS_DefineProperty(context, target, names[index].atom, descriptor.value, descriptor.getter, descriptor.setter, descriptor.flags | c.JS_PROP_HAS_VALUE | c.JS_PROP_HAS_CONFIGURABLE | c.JS_PROP_HAS_WRITABLE | c.JS_PROP_HAS_ENUMERABLE) < 0) return false;
    }
    return true;
}
fn cloneMemory(engine: *engine_mod.Engine, value: c.JSValue, active: *std.ArrayList(c.JSValue)) anyerror!c.JSValue {
    if (!c.JS_IsObject(value) or c.JS_IsFunction(engine.context, value)) return c.JS_DupValue(engine.context, value);
    for (active.items) |parent| if (c.JS_IsStrictEqual(engine.context, parent, value)) return engine.checked(c.JS_ThrowRangeError(engine.context, "Maximum call stack size exceeded"));
    try active.append(engine.gpa, value);
    defer _ = active.pop();
    if (c.JS_GetTypedArrayType(value) >= 0) return sdk.invoke(engine, value, "slice", &.{});
    if (c.JS_IsArray(value)) {
        const result = try sdk.array(engine);
        errdefer engine.freeValue(result);
        const count = try sdk.length(engine, value);
        try sdk.put(engine, result, "length", c.JS_NewInt64(engine.context, @intCast(count)));
        for (0..count) |index| {
            const key = c.JS_NewAtomUInt32(engine.context, @intCast(index));
            defer c.JS_FreeAtom(engine.context, key);
            const present = c.JS_HasProperty(engine.context, value, key);
            if (present < 0) return error.JavaScriptException;
            if (present == 0) continue;
            const child = try engine.checked(c.JS_GetPropertyUint32(engine.context, value, @intCast(index)));
            defer engine.freeValue(child);
            if (c.JS_SetPropertyUint32(engine.context, result, @intCast(index), try cloneMemory(engine, child, active)) < 0) return error.JavaScriptException;
        }
        return result;
    }
    const class_atom = c.JS_GetClassName(engine.runtime, c.JS_GetClassID(value));
    defer c.JS_FreeAtom(engine.context, class_atom);
    const class_value = try engine.checked(c.JS_AtomToString(engine.context, class_atom));
    defer engine.freeValue(class_value);
    const name = try engine.toString(class_value);
    defer engine.gpa.free(name);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    if (std.mem.eql(u8, name, "RegExp")) {
        const constructor = try sdk.get(engine, global, "RegExp");
        defer engine.freeValue(constructor);
        const source = try sdk.get(engine, value, "source");
        defer engine.freeValue(source);
        const flags = try sdk.get(engine, value, "flags");
        defer engine.freeValue(flags);
        var args = [_]c.JSValue{ source, flags };
        return engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args));
    }
    if (std.mem.eql(u8, name, "Map") or std.mem.eql(u8, name, "Set")) {
        const iterator = try sdk.invoke(engine, value, if (std.mem.eql(u8, name, "Map")) "entries" else "values", &.{});
        defer engine.freeValue(iterator);
        const array = try sdk.get(engine, global, "Array");
        defer engine.freeValue(array);
        const items = try sdk.invoke(engine, array, "from", &.{iterator});
        defer engine.freeValue(items);
        const cloned = try cloneMemory(engine, items, active);
        defer engine.freeValue(cloned);
        const constructor_name = try engine.gpa.dupeZ(u8, name);
        defer engine.gpa.free(constructor_name);
        const constructor = try sdk.get(engine, global, constructor_name);
        defer engine.freeValue(constructor);
        var args = [_]c.JSValue{cloned};
        return engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &args));
    }
    const prototype = try engine.checked(c.JS_GetPrototype(engine.context, value));
    defer engine.freeValue(prototype);
    if (!c.JS_IsNull(prototype)) {
        const constructor = try sdk.get(engine, prototype, "constructor");
        defer engine.freeValue(constructor);
        if (c.JS_IsFunction(engine.context, constructor)) {
            const class_name = try sdk.get(engine, constructor, "name");
            defer engine.freeValue(class_name);
            const label = try engine.toString(class_name);
            defer engine.gpa.free(label);
            if (!std.mem.eql(u8, label, "Object")) return c.JS_DupValue(engine.context, value);
        }
    }
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    const kind = c.JS_NewAtom(engine.context, "~kind");
    defer c.JS_FreeAtom(engine.context, kind);
    const unsafe = c.JS_NewAtom(engine.context, "~unsafe");
    defer c.JS_FreeAtom(engine.context, unsafe);
    const is_schema = c.JS_HasProperty(engine.context, value, kind) != 0 or c.JS_HasProperty(engine.context, value, unsafe) != 0;
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, value, c.JS_GPN_STRING_MASK | if (is_schema) @as(c_int, 0) else c.JS_GPN_SYMBOL_MASK) < 0) return error.JavaScriptException;
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for (0..count) |index| {
        const key = try engine.checked(c.JS_AtomToString(engine.context, names[index].atom));
        defer engine.freeValue(key);
        if (c.JS_IsString(key)) {
            const text = try engine.toString(key);
            defer engine.gpa.free(text);
            if (std.mem.eql(u8, text, "__proto__") or std.mem.eql(u8, text, "constructor") or std.mem.eql(u8, text, "prototype")) continue;
        }
        var descriptor: c.JSPropertyDescriptor = undefined;
        if (c.JS_GetOwnProperty(engine.context, &descriptor, value, names[index].atom) < 0) return error.JavaScriptException;
        defer engine.freeValue(descriptor.value);
        defer engine.freeValue(descriptor.getter);
        defer engine.freeValue(descriptor.setter);
        const child = if (is_schema) c.JS_DupValue(engine.context, descriptor.value) else try engine.checked(c.JS_GetProperty(engine.context, value, names[index].atom));
        defer engine.freeValue(child);
        const flags = if (is_schema) descriptor.flags else c.JS_PROP_C_W_E;
        if (c.JS_DefinePropertyValue(engine.context, result, names[index].atom, try cloneMemory(engine, child, active), flags) < 0) return error.JavaScriptException;
    }
    return result;
}

test "native schema binding isolates throwing property getters without leaking engine values" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const types = try create(engine);
    defer engine.freeValue(types);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try std.testing.expect(put(engine.context, global, "Type", c.JS_DupValue(engine.context, types)));
    try std.testing.expectError(error.JavaScriptException, engine.eval("Type.Object({get broken() { throw new Error('getter failed'); }})", "schema-getter.js", c.JS_EVAL_TYPE_GLOBAL));
    engine.beginInvocation();
    const healthy = try engine.eval("Type.String({minLength: 1})", "schema-healthy.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(healthy);
    const encoded = try engine.stringify(healthy);
    defer std.testing.allocator.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "minLength") != null);
}

test "extension imports native Type schemas and optional fields" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const types = try create(engine);
    defer engine.freeValue(types);
    const exports = c.JS_NewObject(engine.context);
    defer engine.freeValue(exports);
    try std.testing.expect(put(engine.context, exports, "Type", c.JS_DupValue(engine.context, types)));
    try engine.registerValueModule("typebox", exports);
    const namespace = try engine.evalModule("import { Type } from 'typebox'; export const schema = Type.Object({text: Type.String(), count: Type.Optional(Type.Integer({minimum: 0}))}, {additionalProperties: false});", "schema-extension.js");
    defer engine.freeValue(namespace);
    const schema = c.JS_GetPropertyStr(engine.context, namespace, "schema");
    defer engine.freeValue(schema);
    const encoded = try engine.stringify(schema);
    defer std.testing.allocator.free(encoded);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, encoded, .{});
    defer parsed.deinit();
    const object = parsed.value.object;
    try std.testing.expectEqualStrings("object", object.get("type").?.string);
    try std.testing.expectEqual(@as(usize, 1), object.get("required").?.array.items.len);
    try std.testing.expectEqualStrings("text", object.get("required").?.array.items[0].string);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "__piOptional") == null);
}

test "native TypeBox metadata descriptors optional deep clones property identities symbols and getter errors match original" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const types = try create(engine);
    defer engine.freeValue(types);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try std.testing.expect(put(engine.context, global, "Type", c.JS_DupValue(engine.context, types)));
    errdefer std.debug.print("TypeBox metadata VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\const Type=globalThis.Type;
        \\const number=Type.Number({minimum:0}),child=Type.String(),optional=Type.Optional(Type.Object({child})),properties={number,optional},object=Type.Object(properties),symbol=Symbol('annotation'),reference={same:true},annotated=Type.String({[symbol]:reference}),date=new Date(0),map=new Map([['key',{n:1}]]),complex=Type.Optional(Type.String({date,map})),reason={original:true};let getter;
        \\try{Type.String({get description(){throw reason}})}catch(error){getter=error===reason}
        \\const values=[Type.Any(),Type.Unknown(),Type.String(),Type.Number(),Type.Integer(),Type.Boolean(),Type.Null(),Type.Literal('x'),Type.Array(number),Type.Union([number,child]),Type.Intersect([Type.Object({}),Type.Object({})]),object,optional],metadata=values.map(value=>{const descriptor=Object.getOwnPropertyDescriptor(value,'~kind');return{kind:value['~kind'],enumerable:descriptor.enumerable,writable:descriptor.writable,configurable:descriptor.configurable,keys:Object.keys(value)}}),modifier=Object.getOwnPropertyDescriptor(optional,'~optional');globalThis.result=JSON.stringify({metadata,modifier:{value:modifier.value,enumerable:modifier.enumerable,writable:modifier.writable,configurable:modifier.configurable},identity:{properties:object.properties===properties,number:object.properties.number===number,optional:object.properties.optional===optional,deep:optional.properties.child!==child,date:complex.date===date,map:complex.map!==map,mapValue:complex.map.get('key')!==map.get('key')},required:object.required,symbol:annotated[symbol]===reference&&Object.getOwnPropertySymbols(annotated)[0]===symbol,hidden:!JSON.stringify(object).includes('~kind')&&!JSON.stringify(object).includes('~optional'),getter});
        \\
        \\
    , "native-typebox-metadata-source");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-typebox-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"metadata\":[{\"kind\":\"Any\",\"enumerable\":false,\"writable\":true,\"configurable\":true,\"keys\":[]},{\"kind\":\"Unknown\",\"enumerable\":false,\"writable\":true,\"configurable\":true,\"keys\":[]},{\"kind\":\"String\",\"enumerable\":false,\"writable\":true,\"configurable\":true,\"keys\":[\"type\"]},{\"kind\":\"Number\",\"enumerable\":false,\"writable\":true,\"configurable\":true,\"keys\":[\"type\"]},{\"kind\":\"Integer\",\"enumerable\":false,\"writable\":true,\"configurable\":true,\"keys\":[\"type\"]},{\"kind\":\"Boolean\",\"enumerable\":false,\"writable\":true,\"configurable\":true,\"keys\":[\"type\"]},{\"kind\":\"Null\",\"enumerable\":false,\"writable\":true,\"configurable\":true,\"keys\":[\"type\"]},{\"kind\":\"Literal\",\"enumerable\":false,\"writable\":true,\"configurable\":true,\"keys\":[\"type\",\"const\"]},{\"kind\":\"Array\",\"enumerable\":false,\"writable\":true,\"configurable\":true,\"keys\":[\"type\",\"items\"]},{\"kind\":\"Union\",\"enumerable\":false,\"writable\":true,\"configurable\":true,\"keys\":[\"anyOf\"]},{\"kind\":\"Intersect\",\"enumerable\":false,\"writable\":true,\"configurable\":true,\"keys\":[\"allOf\"]},{\"kind\":\"Object\",\"enumerable\":false,\"writable\":true,\"configurable\":true,\"keys\":[\"type\",\"required\",\"properties\"]},{\"kind\":\"Object\",\"enumerable\":false,\"writable\":true,\"configurable\":true,\"keys\":[\"type\",\"required\",\"properties\"]}],\"modifier\":{\"value\":true,\"enumerable\":false,\"writable\":true,\"configurable\":true},\"identity\":{\"properties\":true,\"number\":true,\"optional\":true,\"deep\":true,\"date\":true,\"map\":true,\"mapValue\":true},\"required\":[\"number\"],\"symbol\":true,\"hidden\":true,\"getter\":true}", text);
}

test "native TypeBox Record key patterns finite unions and distributed primitive intersections match original" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const types = try create(engine);
    defer engine.freeValue(types);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try std.testing.expect(put(engine.context, global, "Type", c.JS_DupValue(engine.context, types)));
    errdefer std.debug.print("TypeBox Record VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\const Type=globalThis.Type;
        \\const value=Type.Object({n:Type.Number()}),cases=[['string',Type.String()],['pattern',Type.String({pattern:'^x_'})],['number',Type.Number()],['integer',Type.Integer()],['boolean',Type.Boolean()],['literal',Type.Literal('x')],['literals',Type.Union([Type.Literal('a'),Type.Literal('b')])],['wide-union',Type.Union([Type.String({pattern:'^x'}),Type.Literal('a')])],['any-union',Type.Union([Type.Any(),Type.Literal('a')])],['unknown',Type.Unknown()],['intersection',Type.Intersect([Type.Union([Type.Literal('a'),Type.Literal('b')]),Type.Union([Type.Literal('b'),Type.Literal('c')])])],['intersection-string',Type.Intersect([Type.String({minLength:5}),Type.Literal('x')])],['intersection-number',Type.Intersect([Type.Integer(),Type.Number()])]];
        \\globalThis.result=JSON.stringify(cases.map(([name,key])=>{const schema=Type.Record(key,value);return{name,kind:schema['~kind'],schema,detached:(Object.values(schema.patternProperties??schema.properties)[0]??{})!==value}}));
        \\
    , "native-typebox-record-source");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-typebox-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("[{\"name\":\"string\",\"kind\":\"Record\",\"schema\":{\"type\":\"object\",\"patternProperties\":{\"^.*$\":{\"type\":\"object\",\"required\":[\"n\"],\"properties\":{\"n\":{\"type\":\"number\"}}}}},\"detached\":true},{\"name\":\"pattern\",\"kind\":\"Record\",\"schema\":{\"type\":\"object\",\"patternProperties\":{\"^x_\":{\"type\":\"object\",\"required\":[\"n\"],\"properties\":{\"n\":{\"type\":\"number\"}}}}},\"detached\":true},{\"name\":\"number\",\"kind\":\"Record\",\"schema\":{\"type\":\"object\",\"patternProperties\":{\"^-?(?:0|[1-9][0-9]*)(?:\\\\.[0-9]+)?$\":{\"type\":\"object\",\"required\":[\"n\"],\"properties\":{\"n\":{\"type\":\"number\"}}}}},\"detached\":true},{\"name\":\"integer\",\"kind\":\"Record\",\"schema\":{\"type\":\"object\",\"patternProperties\":{\"^-?(?:0|[1-9][0-9]*)$\":{\"type\":\"object\",\"required\":[\"n\"],\"properties\":{\"n\":{\"type\":\"number\"}}}}},\"detached\":true},{\"name\":\"boolean\",\"kind\":\"Object\",\"schema\":{\"type\":\"object\",\"required\":[\"true\",\"false\"],\"properties\":{\"true\":{\"type\":\"object\",\"required\":[\"n\"],\"properties\":{\"n\":{\"type\":\"number\"}}},\"false\":{\"type\":\"object\",\"required\":[\"n\"],\"properties\":{\"n\":{\"type\":\"number\"}}}}},\"detached\":true},{\"name\":\"literal\",\"kind\":\"Object\",\"schema\":{\"type\":\"object\",\"required\":[\"x\"],\"properties\":{\"x\":{\"type\":\"object\",\"required\":[\"n\"],\"properties\":{\"n\":{\"type\":\"number\"}}}}},\"detached\":true},{\"name\":\"literals\",\"kind\":\"Object\",\"schema\":{\"type\":\"object\",\"required\":[\"a\",\"b\"],\"properties\":{\"a\":{\"type\":\"object\",\"required\":[\"n\"],\"properties\":{\"n\":{\"type\":\"number\"}}},\"b\":{\"type\":\"object\",\"required\":[\"n\"],\"properties\":{\"n\":{\"type\":\"number\"}}}}},\"detached\":true},{\"name\":\"wide-union\",\"kind\":\"Record\",\"schema\":{\"type\":\"object\",\"patternProperties\":{\"^.*$\":{\"type\":\"object\",\"required\":[\"n\"],\"properties\":{\"n\":{\"type\":\"number\"}}}}},\"detached\":true},{\"name\":\"any-union\",\"kind\":\"Object\",\"schema\":{\"type\":\"object\",\"required\":[\"a\"],\"properties\":{\"a\":{\"type\":\"object\",\"required\":[\"n\"],\"properties\":{\"n\":{\"type\":\"number\"}}}}},\"detached\":true},{\"name\":\"unknown\",\"kind\":\"Object\",\"schema\":{\"type\":\"object\",\"properties\":{}},\"detached\":true},{\"name\":\"intersection\",\"kind\":\"Object\",\"schema\":{\"type\":\"object\",\"required\":[\"b\"],\"properties\":{\"b\":{\"type\":\"object\",\"required\":[\"n\"],\"properties\":{\"n\":{\"type\":\"number\"}}}}},\"detached\":true},{\"name\":\"intersection-string\",\"kind\":\"Object\",\"schema\":{\"type\":\"object\",\"required\":[\"x\"],\"properties\":{\"x\":{\"type\":\"object\",\"required\":[\"n\"],\"properties\":{\"n\":{\"type\":\"number\"}}}}},\"detached\":true},{\"name\":\"intersection-number\",\"kind\":\"Record\",\"schema\":{\"type\":\"object\",\"patternProperties\":{\"^-?(?:0|[1-9][0-9]*)$\":{\"type\":\"object\",\"required\":[\"n\"],\"properties\":{\"n\":{\"type\":\"number\"}}}}},\"detached\":true}]", text);
}
fn recordAllocationExercise(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    const fixture = try engine.eval("({keys:[{'~kind':'String',type:'string',pattern:'^x_'},{'~kind':'Union',anyOf:[{'~kind':'Literal',type:'string',const:'a'},{'~kind':'Literal',type:'string',const:'b'}]},{'~kind':'Intersect',allOf:[{'~kind':'Union',anyOf:[{'~kind':'Literal',type:'string',const:'a'},{'~kind':'Literal',type:'string',const:'b'}]},{'~kind':'Union',anyOf:[{'~kind':'Literal',type:'string',const:'b'},{'~kind':'Literal',type:'string',const:'c'}]}]}],value:{'~kind':'Object',type:'object',required:['n'],properties:{n:{'~kind':'Number',type:'number'}}}})", "record-allocation-input", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(fixture);
    const keys = try sdk.get(engine, fixture, "keys");
    defer engine.freeValue(keys);
    const value = try sdk.get(engine, fixture, "value");
    defer engine.freeValue(value);
    for (0..try sdk.length(engine, keys)) |index| {
        const key = try engine.checked(c.JS_GetPropertyUint32(engine.context, keys, @intCast(index)));
        defer engine.freeValue(key);
        const output = try record(engine, key, value, c.pi_js_undefined());
        engine.freeValue(output);
    }
}
test "native TypeBox Record patterns unions intersection ownership unwind every GPA allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, recordAllocationExercise, .{});
}

test "native TypeBox installed named constructors default Type and Format are readonly real namespaces with source function metadata" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try install(engine);
    try install(engine);
    errdefer std.debug.print("TypeBox module shape VM failure: {s}\n", .{engine.last_error orelse "no VM diagnostic"});
    const output = try engine.evalModule(
        \\import TypeDefault,{Type,Object as ObjectFactory,String as StringFactory} from 'typebox';
        \\import FormatDefault,{Format,IsEmail} from 'typebox/format';
        \\const names=['Any','Unknown','String','Number','Integer','Boolean','Null','Literal','Array','Union','Intersect','Optional','Object','Record'];let typeReadonly,formatReadonly;try{Type.Object=()=>null}catch(error){typeReadonly=error instanceof TypeError}try{Format.Test=()=>false}catch(error){formatReadonly=error instanceof TypeError}const descriptor=Object.getOwnPropertyDescriptor(Type,'Object');globalThis.result=JSON.stringify({type:TypeDefault===Type&&Type.Object===ObjectFactory&&Type.String===StringFactory,format:FormatDefault===Format&&Format.IsEmail===IsEmail,typeReadonly,formatReadonly,tag:Object.prototype.toString.call(Type),prototype:Object.getPrototypeOf(Type)===null,extensible:Object.isExtensible(Type),descriptor:{writable:descriptor.writable,enumerable:descriptor.enumerable,configurable:descriptor.configurable},functions:names.map(key=>({key,name:Type[key].name,length:Type[key].length})),schema:Type.Object({value:Type.String()}),email:Format.Test('email','x@example.com')});
        \\
    , "native-typebox-module-shape-source");
    defer engine.freeValue(output);
    const result = try engine.eval("globalThis.result", "native-typebox-result", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    const text = try engine.toString(result);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("{\"type\":true,\"format\":true,\"typeReadonly\":true,\"formatReadonly\":true,\"tag\":\"[object Module]\",\"prototype\":true,\"extensible\":false,\"descriptor\":{\"writable\":true,\"enumerable\":true,\"configurable\":false},\"functions\":[{\"key\":\"Any\",\"name\":\"Any\",\"length\":1},{\"key\":\"Unknown\",\"name\":\"Unknown\",\"length\":1},{\"key\":\"String\",\"name\":\"String\",\"length\":1},{\"key\":\"Number\",\"name\":\"Number\",\"length\":1},{\"key\":\"Integer\",\"name\":\"Integer\",\"length\":1},{\"key\":\"Boolean\",\"name\":\"Boolean\",\"length\":1},{\"key\":\"Null\",\"name\":\"Null\",\"length\":1},{\"key\":\"Literal\",\"name\":\"Literal\",\"length\":2},{\"key\":\"Array\",\"name\":\"_Array_\",\"length\":2},{\"key\":\"Union\",\"name\":\"Union\",\"length\":1},{\"key\":\"Intersect\",\"name\":\"Intersect\",\"length\":1},{\"key\":\"Optional\",\"name\":\"Optional\",\"length\":1},{\"key\":\"Object\",\"name\":\"_Object_\",\"length\":1},{\"key\":\"Record\",\"name\":\"Record\",\"length\":2}],\"schema\":{\"type\":\"object\",\"required\":[\"value\"],\"properties\":{\"value\":{\"type\":\"string\"}}},\"email\":true}", text);
}
