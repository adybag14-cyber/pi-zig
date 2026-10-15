//! Memory-backed actual constructor operations used by Partial evaluation.
const v = @import("native_ai_provider_values.zig");
pub const Scope = v.Scope;
pub const c = v.c;
const memory = @import("native_typebox_memory.zig");
pub fn kind(scope: *Scope, value: c.JSValue, name: []const u8) !bool {
    return c.JS_IsObject(value) and !c.JS_IsFunction(scope.engine.context, value) and try v.js.hasKey(scope.engine, value, try scope.text("~kind")) and try v.eq(scope, try scope.get(value, "~kind"), name);
}
pub fn modifier(scope: *Scope, value: c.JSValue, name: []const u8) !bool {
    return c.JS_IsObject(value) and !c.JS_IsFunction(scope.engine.context, value) and try v.js.hasKey(scope.engine, value, try scope.text(name));
}
pub fn list(scope: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try scope.array();
    for (values, 0..) |value, index| try scope.index(result, @intCast(index), value);
    return result;
}
pub fn make(scope: *Scope, graph: c.JSValue, name: []const u8, fields: c.JSValue, options: c.JSValue) !c.JSValue {
    const hidden = try scope.object();
    try scope.put(hidden, "~kind", try scope.text(name));
    return memory.invoke(scope, graph, "Create", &.{ hidden, fields, options });
}
pub fn changeModifier(scope: *Scope, graph: c.JSValue, value: c.JSValue, name: []const u8, add: bool) !c.JSValue {
    const changed = if (add) added: {
        const hidden = try scope.object();
        const atom = c.JS_ValueToAtom(scope.engine.context, try scope.text(name));
        if (atom == c.JS_ATOM_NULL) return v.js.capture(scope.engine);
        defer c.JS_FreeAtom(scope.engine.context, atom);
        if (c.JS_DefinePropertyValue(scope.engine.context, hidden, atom, c.pi_js_bool(scope.engine.context, 1), c.JS_PROP_C_W_E) < 0) return v.js.capture(scope.engine);
        break :added try memory.invoke(scope, graph, "Update", &.{ value, hidden, try scope.object() });
    } else try memory.invoke(scope, graph, "Discard", &.{ value, try list(scope, &.{try scope.text(name)}) });
    return memory.invoke(scope, graph, "Update", &.{ changed, try scope.object(), try scope.object() });
}
fn requiredKey(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const key = if (args.len != 0) args[0] else c.pi_js_undefined();
    const value = try scope.own(try v.js.getKey(engine, roots[0], key));
    return c.pi_js_bool(engine.context, @intFromBool(!try modifier(&scope, value, "~optional")));
}
pub fn object(scope: *Scope, graph: c.JSValue, properties: c.JSValue, options: c.JSValue) !c.JSValue {
    const keys = try scope.invoke(try scope.global("Object"), "getOwnPropertyNames", &.{properties});
    const callback = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 1, requiredKey, &.{properties}));
    const required = try scope.invoke(keys, "filter", &.{callback});
    const fields = try scope.object();
    try scope.put(fields, "type", try scope.text("object"));
    if (scope.truthy(try scope.get(required, "length"))) try scope.put(fields, "required", required);
    try scope.put(fields, "properties", properties);
    return make(scope, graph, "Object", fields, options);
}
pub fn unionType(scope: *Scope, graph: c.JSValue, values: c.JSValue) !c.JSValue {
    const fields = try scope.object();
    try scope.put(fields, "anyOf", values);
    return make(scope, graph, "Union", fields, try scope.object());
}
pub fn never(scope: *Scope, graph: c.JSValue) !c.JSValue {
    const fields = try scope.object();
    try scope.put(fields, "not", try scope.object());
    return make(scope, graph, "Never", fields, c.pi_js_undefined());
}
pub fn deferred(scope: *Scope, graph: c.JSValue, action: []const u8, parameters: c.JSValue, options: c.JSValue) !c.JSValue {
    const fields = try scope.object();
    try scope.put(fields, "type", try scope.text("deferred"));
    try scope.put(fields, "action", try scope.text(action));
    try scope.put(fields, "parameters", parameters);
    try scope.put(fields, "options", options);
    return make(scope, graph, "Deferred", fields, try scope.object());
}
pub fn literal(scope: *Scope, graph: c.JSValue, value: c.JSValue) !c.JSValue {
    const name: []const u8 = if (c.JS_IsBigInt(value)) "bigint" else if (c.JS_IsBool(value)) "boolean" else if (scope.truthy(try scope.invoke(try scope.global("Number"), "isFinite", &.{value}))) "number" else if (c.JS_IsString(value)) "string" else {
        const invalid = try scope.own(try @import("native_typebox_errors.zig").literalConstructor(scope.engine));
        return scope.engine.checked(c.JS_Throw(scope.engine.context, try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, invalid, 1, @constCast(&[_]c.JSValue{value})))));
    };
    const fields = try scope.object();
    try scope.put(fields, "type", try scope.text(name));
    try scope.put(fields, "const", value);
    return make(scope, graph, "Literal", fields, c.pi_js_undefined());
}
fn cyclicDefinition(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = args[0];
    const key = args[1];
    const fields = try scope.object();
    try scope.put(fields, "$id", key);
    const schema = try scope.own(try v.js.getKey(engine, roots[1], key));
    const updated = try memory.invoke(&scope, roots[0], "Update", &.{ schema, try scope.object(), fields });
    const copy = try scope.own(try v.js.spread(engine, result));
    const atom = c.JS_ValueToAtom(engine.context, key);
    if (atom == c.JS_ATOM_NULL) return v.js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyValue(engine.context, copy, atom, c.JS_DupValue(engine.context, updated), c.JS_PROP_C_W_E) < 0) return v.js.capture(engine);
    return c.JS_DupValue(engine.context, copy);
}
pub fn cyclic(scope: *Scope, graph: c.JSValue, definitions: c.JSValue, reference: c.JSValue) !c.JSValue {
    const keys = try scope.invoke(try scope.global("Object"), "getOwnPropertyNames", &.{definitions});
    const callback = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 2, cyclicDefinition, &.{ graph, definitions }));
    const mapped = try scope.invoke(keys, "reduce", &.{ callback, try scope.object() });
    const fields = try scope.object();
    try scope.put(fields, "$defs", mapped);
    try scope.put(fields, "$ref", reference);
    return make(scope, graph, "Cyclic", fields, c.pi_js_undefined());
}
fn enumKey(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return v.js.call(engine, try scope.global("isNaN"), c.pi_js_undefined(), &.{if (args.len != 0) args[0] else c.pi_js_undefined()});
}
fn enumValue(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const copy = try scope.own(try @import("native_iterator_spread.zig").snapshot(engine, args[0]));
    const value = try scope.own(try v.js.getKey(engine, roots[0], args[1]));
    try scope.index(copy, try v.length(&scope, copy), value);
    return c.JS_DupValue(engine.context, copy);
}
pub fn enumeration(scope: *Scope, graph: c.JSValue, value: c.JSValue, options: c.JSValue) !c.JSValue {
    const values = if (c.JS_IsObject(value) and !c.JS_IsFunction(scope.engine.context, value) and !try v.array(scope, value)) mapped: {
        const keys = try scope.invoke(try scope.global("Object"), "getOwnPropertyNames", &.{value});
        const filter = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 1, enumKey, &.{}));
        const reduce = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 2, enumValue, &.{value}));
        break :mapped try scope.invoke(try scope.invoke(keys, "filter", &.{filter}), "reduce", &.{ reduce, try scope.array() });
    } else value;
    const fields = try scope.object();
    try scope.put(fields, "enum", values);
    return make(scope, graph, "Enum", fields, options);
}
