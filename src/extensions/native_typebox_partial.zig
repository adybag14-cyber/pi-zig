//! Actual PartialAction/FromType and Enum exports sharing real native Memory.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const core = @import("native_typebox_schema_core.zig");
const memory = @import("native_typebox_memory.zig");
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
pub fn create(engine: *v.em.Engine, shared_graph: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const exports = try scope.object();
    const functions = @import("native_node_function.zig");
    try scope.put(exports, "Partial", try scope.own(try functions.create(engine, "Partial", 1, invokePartial, &.{shared_graph})));
    try scope.put(exports, "Enum", try scope.own(try functions.create(engine, "Enum", 2, invokeEnum, &.{shared_graph})));
    return engine.valueNamespace(exports);
}
/// Called only on the owner's mutable Type export builder before namespace seal.
/// This helper does not mutate any global/shared TypeBox namespace on its own.
pub fn install(engine: *v.em.Engine, type_builder: c.JSValue, shared_graph: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const exports = try scope.own(try create(engine, shared_graph));
    inline for (.{ "Partial", "Enum" }) |name| try scope.put(type_builder, name, try scope.get(exports, name));
}
fn invokePartial(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const options = if (c.JS_IsUndefined(arg(args, 1))) try scope.object() else args[1];
    return c.JS_DupValue(engine.context, try partial(&scope, roots[0], arg(args, 0), options));
}
fn invokeEnum(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(engine.context, try core.enumeration(&scope, roots[0], arg(args, 0), arg(args, 1)));
}
pub fn partial(scope: *Scope, graph: c.JSValue, value: c.JSValue, options: c.JSValue) anyerror!c.JSValue {
    if (try core.kind(scope, value, "Ref")) return core.deferred(scope, graph, "Partial", try core.list(scope, &.{value}), options);
    return memory.invoke(scope, graph, "Update", &.{ try fromType(scope, graph, value), try scope.object(), options });
}
fn propertyReduce(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const copy = try scope.own(try v.js.spread(engine, args[0]));
    const key = args[1];
    const atom = c.JS_ValueToAtom(engine.context, key);
    if (atom == c.JS_ATOM_NULL) return v.js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    const value = try scope.own(try v.js.getKey(engine, roots[1], key));
    const optional = try core.changeModifier(&scope, roots[0], value, "~optional", true);
    if (c.JS_DefinePropertyValue(engine.context, copy, atom, c.JS_DupValue(engine.context, optional), c.JS_PROP_C_W_E) < 0) return v.js.capture(engine);
    return c.JS_DupValue(engine.context, copy);
}
fn unionMap(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.JS_DupValue(engine.context, try fromType(&scope, roots[0], arg(args, 0)));
}
fn cyclicTarget(scope: *Scope, graph: c.JSValue, definitions: c.JSValue, reference: c.JSValue) anyerror!c.JSValue {
    if (!try v.js.hasKey(scope.engine, definitions, reference)) return core.never(scope, graph);
    if (try core.kind(scope, try scope.own(try v.js.getKey(scope.engine, definitions, reference)), "Ref")) return cyclicTarget(scope, graph, definitions, try scope.get(try scope.own(try v.js.getKey(scope.engine, definitions, reference)), "$ref"));
    return scope.own(try v.js.getKey(scope.engine, definitions, reference));
}
pub fn fromType(scope: *Scope, graph: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    if (try core.kind(scope, value, "Cyclic")) {
        const definitions = try scope.get(value, "$defs");
        const reference = try scope.get(value, "$ref");
        const target = try cyclicTarget(scope, graph, definitions, reference);
        const mapped = try fromType(scope, graph, target);
        const fields = try scope.object();
        const atom = c.JS_ValueToAtom(scope.engine.context, reference);
        if (atom == c.JS_ATOM_NULL) return v.js.capture(scope.engine);
        defer c.JS_FreeAtom(scope.engine.context, atom);
        if (c.JS_DefinePropertyValue(scope.engine.context, fields, atom, c.JS_DupValue(scope.engine.context, mapped), c.JS_PROP_C_W_E) < 0) return v.js.capture(scope.engine);
        return core.cyclic(scope, graph, try memory.invoke(scope, graph, "Assign", &.{ definitions, fields }), reference);
    }
    if (try core.kind(scope, value, "Dependent")) return fromType(scope, graph, try @import("native_typebox_partial_evaluate.zig").dependent(scope, graph, try scope.get(value, "if"), try scope.get(value, "then"), try scope.get(value, "else")));
    if (try core.kind(scope, value, "Intersect")) return fromType(scope, graph, try @import("native_typebox_partial_evaluate.zig").intersection(scope, graph, try scope.get(value, "allOf")));
    if (try core.kind(scope, value, "Union")) {
        const values = try scope.get(value, "anyOf");
        const callback = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 1, unionMap, &.{graph}));
        return core.unionType(scope, graph, try scope.invoke(values, "map", &.{callback}));
    }
    if (try core.kind(scope, value, "Object")) {
        const properties = try scope.get(value, "properties");
        const keys = try scope.invoke(try scope.global("Object"), "getOwnPropertyNames", &.{properties});
        const callback = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 2, propertyReduce, &.{ graph, properties }));
        const mapped = try scope.invoke(keys, "reduce", &.{ callback, try scope.object() });
        return core.object(scope, graph, mapped, try scope.object());
    }
    return core.object(scope, graph, try scope.object(), try scope.object());
}
