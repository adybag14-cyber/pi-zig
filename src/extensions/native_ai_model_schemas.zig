//! Native execution of the exact pinned model/compat constructor declarations.
//! The static Zig operation graph invokes actual supplied Type factories;
//! it retains schema aliases, optional metadata and observable evaluation order.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const program = @import("native_ai_model_schema_program.zig");
const Context = struct { types: c.JSValue, globals: c.JSValue, locals: c.JSValue };
fn privateObject(scope: *Scope) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, c.pi_js_null())));
}
pub fn create(engine: *v.em.Engine, actual_type: c.JSValue) !c.JSValue {
    return build(engine, actual_type, false);
}
/// Separate actual Source module namespaces, sharing ModelCostSchema identity.
pub fn createGraph(engine: *v.em.Engine, actual_type: c.JSValue) !c.JSValue {
    return build(engine, actual_type, true);
}
fn build(engine: *v.em.Engine, actual_type: c.JSValue, separate: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const globals = try privateObject(&scope);
    const exports = try scope.object();
    const model_exports = try scope.object();
    const compat_exports = try scope.object();
    const context: Context = .{ .types = actual_type, .globals = globals, .locals = c.pi_js_undefined() };
    for (program.declarations) |declaration| {
        const value = try evaluate(&scope, context, declaration.node);
        try scope.put(globals, declaration.name, value);
        if (declaration.exported) {
            try scope.put(exports, declaration.name, value);
            try scope.put(if (declaration.module == .model) model_exports else compat_exports, declaration.name, value);
        }
    }
    if (separate) {
        const graph = try scope.object();
        try scope.put(graph, "model", try scope.own(try engine.valueNamespace(model_exports)));
        try scope.put(graph, "compat", try scope.own(try engine.valueNamespace(compat_exports)));
        return c.JS_DupValue(engine.context, graph);
    }
    return engine.valueNamespace(exports);
}
fn reference(scope: *Scope, context: Context, name: []const u8) !c.JSValue {
    const key = try scope.text(name);
    const object = if (!v.nullish(context.locals) and try v.js.hasKey(scope.engine, context.locals, key)) context.locals else context.globals;
    if (!try v.js.hasKey(scope.engine, object, key)) return error.MissingActualNativeSchemaReference;
    return scope.own(try v.js.getKey(scope.engine, object, key));
}
fn append(scope: *Scope, array: c.JSValue, value: c.JSValue) !void {
    return scope.index(array, try v.length(scope, array), value);
}
fn evaluate(scope: *Scope, context: Context, id: program.Id) anyerror!c.JSValue {
    switch (program.nodes[id]) {
        .string => |text| return scope.text(text),
        .number => |number| return c.JS_NewFloat64(scope.engine.context, number),
        .boolean => |boolean| return c.pi_js_bool(scope.engine.context, @intFromBool(boolean)),
        .undef => return c.pi_js_undefined(),
        .reference => |name| return reference(scope, context, name),
        .array => |elements| {
            const array = try scope.array();
            for (elements) |element| {
                const value = try evaluate(scope, context, element.value);
                if (!element.spread) {
                    try append(scope, array, value);
                    continue;
                }
                var iterator = try v.iterator(scope, value);
                defer iterator.deinit();
                errdefer iterator.closePreserving();
                while (try iterator.next()) |item| {
                    defer scope.engine.freeValue(item);
                    try append(scope, array, item);
                }
            }
            return array;
        },
        .object => |fields| {
            const object = try scope.object();
            for (fields) |field| {
                const value = try evaluate(scope, context, field.value);
                if (field.spread) {
                    try v.js.spreadInto(scope.engine, object, value);
                    continue;
                }
                const key = try scope.text(field.key);
                const atom = c.JS_ValueToAtom(scope.engine.context, key);
                if (atom == c.JS_ATOM_NULL) return v.js.capture(scope.engine);
                defer c.JS_FreeAtom(scope.engine.context, atom);
                if (c.JS_DefinePropertyValue(scope.engine.context, object, atom, c.JS_DupValue(scope.engine.context, value), c.JS_PROP_C_W_E) < 0) return v.js.capture(scope.engine);
            }
            return object;
        },
        .call => |call| {
            // Source resolves Type.method before evaluating any argument.
            const function = try scope.get(context.types, call.name);
            if (call.args.len > 4) return error.NativeSchemaConstructorArity;
            var args: [4]c.JSValue = undefined;
            for (call.args, 0..) |argument, index| args[index] = try evaluate(scope, context, argument);
            return scope.call(function, context.types, args[0..call.args.len]);
        },
        .helper => |call| {
            for (program.helpers) |helper| {
                if (!std.mem.eql(u8, helper.name, call.name)) continue;
                const locals = try privateObject(scope);
                const value = if (call.args.len != 0) try evaluate(scope, context, call.args[0]) else c.pi_js_undefined();
                try scope.put(locals, helper.parameter, value);
                return evaluate(scope, .{ .types = context.types, .globals = context.globals, .locals = locals }, helper.node);
            }
            return error.MissingActualNativeSchemaHelper;
        },
        .template => |parts| {
            var text = try scope.text("");
            for (parts) |part| text = try scope.concat(text, try scope.stringify(try evaluate(scope, context, part)));
            return text;
        },
        .merge_provider => return mergeProvider(scope, context),
    }
}
fn schemaProperties(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return v.js.get(engine, if (args.len != 0) args[0] else c.pi_js_undefined(), "properties");
}
fn mergeProvider(scope: *Scope, context: Context) !c.JSValue {
    const by_api = try reference(scope, context, "CompatSchemasByApi");
    const groups = try scope.invoke(try scope.invoke(try scope.global("Object"), "values", &.{by_api}), "map", &.{try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 1, schemaProperties, &.{}))});
    const overrides = try reference(scope, context, "ProviderCompatPropertyOverrides");
    const merged = try scope.object();
    const duplicates = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.global("Set"), 0, null)));
    var group_iterator = try v.iterator(scope, groups);
    defer group_iterator.deinit();
    errdefer group_iterator.closePreserving();
    while (try group_iterator.next()) |properties| {
        defer scope.engine.freeValue(properties);
        var entries = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{properties}));
        defer entries.deinit();
        errdefer entries.closePreserving();
        while (try entries.next()) |entry| {
            defer scope.engine.freeValue(entry);
            var pair = try v.iterator(scope, entry);
            defer pair.deinit();
            errdefer pair.closePreserving();
            const name = try scope.own((try pair.next()) orelse c.pi_js_undefined());
            const schema = try scope.own((try pair.next()) orelse c.pi_js_undefined());
            try pair.close();
            if (!c.JS_IsUndefined(try scope.own(try v.js.getKey(scope.engine, merged, name)))) {
                _ = try scope.invoke(duplicates, "add", &.{name});
                if (!try v.js.hasKey(scope.engine, overrides, name)) return v.errorText(scope, try scope.concat(try scope.text("Duplicate compatibility schema property requires an override: "), try scope.stringify(name)));
            }
            try v.js.setKey(scope.engine, merged, name, schema);
        }
    }
    var names = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "keys", &.{overrides}));
    defer names.deinit();
    errdefer names.closePreserving();
    while (try names.next()) |name| {
        defer scope.engine.freeValue(name);
        if (!scope.truthy(try scope.invoke(duplicates, "has", &.{name}))) return v.errorText(scope, try scope.concat(try scope.text("Compatibility schema override does not resolve a duplicate property: "), try scope.stringify(name)));
    }
    const result = try scope.own(try v.js.spread(scope.engine, merged));
    try v.js.spreadInto(scope.engine, result, overrides);
    return result;
}
