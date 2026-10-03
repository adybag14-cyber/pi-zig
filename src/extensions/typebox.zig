//! Native Zig construction of extension JSON-schema values.
const std = @import("std");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;

const Kind = enum(c_int) { Any, Unknown, String, Number, Integer, Boolean, Null, Literal, Array, Union, Intersect, Optional, Object, Record };

pub fn create(engine: *engine_mod.Engine) !c.JSValue {
    const object = try engine.checked(c.JS_NewObject(engine.context));
    errdefer engine.freeValue(object);
    inline for (std.meta.fields(Kind)) |field| {
        const name: [:0]const u8 = field.name;
        const function = try engine.checked(c.pi_js_function_magic(engine.context, construct, name.ptr, 1, @intCast(field.value)));
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
    if (c.JS_GetOwnPropertyNames(context, &properties, &count, source, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return false;
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
            successful = successful and put(context, result, "const", c.JS_DupValue(context, first));
            const name: [*:0]const u8 = if (c.JS_IsNull(first)) "null" else if (c.JS_IsBool(first)) "boolean" else if (c.JS_IsNumber(first)) "number" else "string";
            successful = successful and put(context, result, "type", c.JS_NewString(context, name));
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
            successful = successful and copyProperties(context, result, first, false);
            successful = successful and put(context, result, "__piOptional", c.pi_js_bool(context, 1));
        },
        .Record => {
            successful = successful and put(context, result, "additionalProperties", if (argc > 1) c.JS_DupValue(context, argv[1]) else c.pi_js_undefined());
            if (argc > 2) successful = successful and copyProperties(context, result, argv[2], false);
        },
        .Object => {
            const properties = c.JS_NewObject(context);
            defer c.JS_FreeValue(context, properties);
            const required = c.JS_NewArray(context);
            defer c.JS_FreeValue(context, required);
            if (c.JS_IsException(properties) or c.JS_IsException(required)) successful = false;
            var names: [*c]c.JSPropertyEnum = null;
            var count: u32 = 0;
            var required_count: u32 = 0;
            if (c.JS_IsObject(first) and c.JS_GetOwnPropertyNames(context, &names, &count, first, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) successful = false;
            defer if (names != null) c.JS_FreePropertyEnum(context, names, count);
            for (0..count) |index| {
                if (!successful) break;
                const schema = c.JS_GetProperty(context, first, names[index].atom);
                defer c.JS_FreeValue(context, schema);
                if (c.JS_IsException(schema)) {
                    successful = false;
                    break;
                }
                const cleaned = c.JS_NewObject(context);
                defer c.JS_FreeValue(context, cleaned);
                successful = successful and copyProperties(context, cleaned, schema, true);
                successful = successful and c.JS_DefinePropertyValue(context, properties, names[index].atom, c.JS_DupValue(context, cleaned), c.JS_PROP_C_W_E) >= 0;
                const optional = c.JS_GetPropertyStr(context, schema, "__piOptional");
                defer c.JS_FreeValue(context, optional);
                if (c.JS_IsException(optional)) {
                    successful = false;
                    break;
                }
                if (c.JS_ToBool(context, optional) != 1) {
                    const name = c.JS_AtomToString(context, names[index].atom);
                    successful = successful and c.JS_SetPropertyUint32(context, required, required_count, name) >= 0;
                    required_count += 1;
                }
            }
            successful = successful and put(context, result, "properties", c.JS_DupValue(context, properties));
            if (required_count > 0) successful = successful and put(context, result, "required", c.JS_DupValue(context, required));
            if (argc > 1) successful = successful and copyProperties(context, result, argv[1], false);
        },
    }
    if (!successful) {
        c.JS_FreeValue(context, result);
        return c.JS_ThrowTypeError(context, "Native schema construction failed");
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
