//! Source EvaluateIntersect/Dependent algebra sharing actual Memory and Extends.
//! The Extends binding must come from the actual shared Type operator graph;
//! incomplete Chord comparison helpers are deliberately not substituted.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const core = @import("native_typebox_schema_core.zig");
const memory = @import("native_typebox_memory.zig");
fn empty(scope: *Scope, array: c.JSValue) !bool {
    return scope.equal(try scope.get(array, "length"), c.JS_NewInt32(scope.engine.context, 0));
}
fn head(scope: *Scope, array: c.JSValue) !c.JSValue {
    return v.at(scope, array, 0);
}
fn tail(scope: *Scope, array: c.JSValue) !c.JSValue {
    return scope.invoke(array, "slice", &.{c.JS_NewInt32(scope.engine.context, 1)});
}
fn append(scope: *Scope, values: c.JSValue, value: c.JSValue) !c.JSValue {
    const copy = try scope.own(try @import("native_iterator_spread.zig").snapshot(scope.engine, values));
    try scope.index(copy, try v.length(scope, copy), value);
    return copy;
}
fn concatenate(scope: *Scope, left: c.JSValue, right: c.JSValue) !c.JSValue {
    const copy = try scope.own(try @import("native_iterator_spread.zig").snapshot(scope.engine, left));
    var iterator = try v.iterator(scope, right);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |value| {
        defer scope.engine.freeValue(value);
        try scope.index(copy, try v.length(scope, copy), value);
    }
    return copy;
}
fn extendsResult(scope: *Scope, graph: c.JSValue, left: c.JSValue, right: c.JSValue) !c.JSValue {
    const types = try scope.get(graph, "Type");
    const function = try scope.get(types, "Extends");
    if (!c.JS_IsFunction(scope.engine.context, function)) return error.MissingActualTypeBoxExtends;
    return scope.call(function, types, &.{ try scope.object(), left, right });
}
fn trueLike(scope: *Scope, result: c.JSValue) !bool {
    return try core.kind(scope, result, "ExtendsUnion") or try core.kind(scope, result, "ExtendsTrue");
}
fn compare(scope: *Scope, graph: c.JSValue, left: c.JSValue, right: c.JSValue) !u2 {
    const first = try extendsResult(scope, graph, left, right);
    const second = try extendsResult(scope, graph, right, left);
    if (try trueLike(scope, first) and try trueLike(scope, second)) return 0;
    if (try trueLike(scope, first) and try core.kind(scope, second, "ExtendsFalse")) return 2;
    if (try core.kind(scope, first, "ExtendsFalse") and try trueLike(scope, second)) return 3;
    return 1;
}
fn tupleProperty(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    const atom = c.JS_ValueToAtom(engine.context, args[2]);
    if (atom == c.JS_ATOM_NULL) return v.js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyValue(engine.context, result, atom, c.JS_DupValue(engine.context, args[1]), c.JS_PROP_C_W_E) < 0) return v.js.capture(engine);
    try v.js.spreadInto(engine, result, args[0]);
    return c.JS_DupValue(engine.context, result);
}
fn properties(scope: *Scope, value: c.JSValue) !c.JSValue {
    if (try core.kind(scope, value, "Object")) return scope.get(value, "properties");
    if (try core.kind(scope, value, "Tuple")) {
        const items = try scope.get(value, "items");
        const callback = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 3, tupleProperty, &.{}));
        return scope.invoke(items, "reduceRight", &.{ callback, try scope.object() });
    }
    return scope.object();
}
fn compositeProperty(scope: *Scope, graph: c.JSValue, left: c.JSValue, right: c.JSValue) anyerror!c.JSValue {
    const readonly = try core.modifier(scope, left, "~readonly") and try core.modifier(scope, right, "~readonly");
    const optional = try core.modifier(scope, left, "~optional") and try core.modifier(scope, right, "~optional");
    const evaluated = try intersection(scope, graph, try core.list(scope, &.{ left, right }));
    const without_optional = try core.changeModifier(scope, graph, evaluated, "~optional", false);
    var value = try core.changeModifier(scope, graph, without_optional, "~readonly", false);
    if (optional) value = try core.changeModifier(scope, graph, value, "~optional", true);
    if (readonly) value = try core.changeModifier(scope, graph, value, "~readonly", true);
    return value;
}
fn compositeReduce(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const key = args[1];
    const copy = try scope.own(try v.js.spread(engine, args[0]));
    const atom = c.JS_ValueToAtom(engine.context, key);
    if (atom == c.JS_ATOM_NULL) return v.js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    const left = roots[1];
    const right = roots[2];
    const value = if (try v.js.hasKey(engine, left, key)) (if (try v.js.hasKey(engine, right, key)) try compositeProperty(&scope, roots[0], try scope.own(try v.js.getKey(engine, left, key)), try scope.own(try v.js.getKey(engine, right, key))) else try scope.own(try v.js.getKey(engine, left, key))) else if (try v.js.hasKey(engine, right, key)) try scope.own(try v.js.getKey(engine, right, key)) else try core.never(&scope, roots[0]);
    if (c.JS_DefinePropertyValue(engine.context, copy, atom, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E) < 0) return v.js.capture(engine);
    return c.JS_DupValue(engine.context, copy);
}
fn composite(scope: *Scope, graph: c.JSValue, left: c.JSValue, right: c.JSValue) !c.JSValue {
    const lhs = try properties(scope, left);
    const rhs = try properties(scope, right);
    const all = try concatenate(scope, try scope.invoke(try scope.global("Object"), "getOwnPropertyNames", &.{lhs}), try scope.invoke(try scope.global("Object"), "getOwnPropertyNames", &.{rhs}));
    var args = [_]c.JSValue{all};
    const keys = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.global("Set"), args.len, &args)));
    const values = try scope.own(try @import("native_iterator_spread.zig").snapshot(scope.engine, keys));
    const callback = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 2, compositeReduce, &.{ graph, lhs, rhs }));
    return core.object(scope, graph, try scope.invoke(values, "reduce", &.{ callback, try scope.object() }), try scope.object());
}
fn narrow(scope: *Scope, graph: c.JSValue, left: c.JSValue, right: c.JSValue) anyerror!c.JSValue {
    if (try core.kind(scope, left, "Never") or try core.kind(scope, left, "Any")) return left;
    if (try core.kind(scope, left, "Unknown")) return right;
    if (try core.kind(scope, right, "Never") or try core.kind(scope, right, "Any")) return right;
    if (try core.kind(scope, right, "Unknown")) return left;
    const lhs = try core.kind(scope, left, "Object") or try core.kind(scope, left, "Tuple");
    const rhs = try core.kind(scope, right, "Object") or try core.kind(scope, right, "Tuple");
    if (lhs and rhs) return composite(scope, graph, left, right);
    if (lhs) return left;
    if (rhs) return right;
    return switch (try compare(scope, graph, left, right)) {
        2 => left,
        3, 0 => right,
        else => core.never(scope, graph),
    };
}
fn distributeOperation(scope: *Scope, graph: c.JSValue, left: c.JSValue, right: c.JSValue) anyerror!c.JSValue {
    const lhs = try evaluate(scope, graph, left);
    const rhs = try evaluate(scope, graph, right);
    return if (try core.kind(scope, lhs, "Union") or try core.kind(scope, rhs, "Union")) intersection(scope, graph, try core.list(scope, &.{ lhs, rhs })) else narrow(scope, graph, lhs, rhs);
}
fn distributeType(scope: *Scope, graph: c.JSValue, value: c.JSValue, values: c.JSValue, result: c.JSValue) anyerror!c.JSValue {
    if (try empty(scope, values)) return if (try empty(scope, result)) core.list(scope, &.{value}) else result;
    const left = try head(scope, values);
    const right = try tail(scope, values);
    return distributeType(scope, graph, value, right, try append(scope, result, try distributeOperation(scope, graph, left, value)));
}
fn distributeUnion(scope: *Scope, graph: c.JSValue, values: c.JSValue, distribution: c.JSValue, result: c.JSValue) anyerror!c.JSValue {
    if (try empty(scope, values)) return result;
    const left = try head(scope, values);
    const right = try tail(scope, values);
    return distributeUnion(scope, graph, right, distribution, try concatenate(scope, result, try distribute(scope, graph, try core.list(scope, &.{left}), distribution)));
}
fn distribute(scope: *Scope, graph: c.JSValue, values: c.JSValue, result: c.JSValue) anyerror!c.JSValue {
    if (try empty(scope, values)) return result;
    const left = try head(scope, values);
    const right = try tail(scope, values);
    return distribute(scope, graph, right, if (try core.kind(scope, left, "Union")) try distributeUnion(scope, graph, try scope.get(left, "anyOf"), result, try scope.array()) else try distributeType(scope, graph, left, result, try scope.array()));
}
fn flatten(scope: *Scope, values: c.JSValue, result: c.JSValue) anyerror!c.JSValue {
    if (try empty(scope, values)) return result;
    const left = try head(scope, values);
    const right = try tail(scope, values);
    const flat = if (try core.kind(scope, left, "Union")) try flatten(scope, try scope.get(left, "anyOf"), try scope.array()) else try core.list(scope, &.{left});
    return flatten(scope, right, try concatenate(scope, result, flat));
}
fn broadenFilter(scope: *Scope, graph: c.JSValue, value: c.JSValue, values: c.JSValue, result: c.JSValue, all: c.JSValue) anyerror!c.JSValue {
    if (try empty(scope, values)) return append(scope, result, value);
    const left = try head(scope, values);
    const right = try tail(scope, values);
    return switch (try compare(scope, graph, value, left)) {
        2, 0 => all,
        1 => broadenFilter(scope, graph, value, right, try append(scope, result, left), all),
        else => broadenFilter(scope, graph, value, right, result, all),
    };
}
fn broadenTypes(scope: *Scope, graph: c.JSValue, values: c.JSValue, result: c.JSValue) anyerror!c.JSValue {
    if (try empty(scope, values)) return result;
    const left = try head(scope, values);
    const right = try tail(scope, values);
    const value = try evaluate(scope, graph, left);
    if (try core.kind(scope, value, "Any") or try core.kind(scope, value, "Unknown")) return core.list(scope, &.{value});
    if (try core.kind(scope, value, "Never")) return broadenTypes(scope, graph, right, result);
    if (try core.kind(scope, value, "Object")) return broadenTypes(scope, graph, right, try append(scope, result, value));
    return broadenTypes(scope, graph, right, try broadenFilter(scope, graph, value, result, try scope.array(), result));
}
pub fn unionValue(scope: *Scope, graph: c.JSValue, values: c.JSValue) anyerror!c.JSValue {
    const broad = try flatten(scope, try broadenTypes(scope, graph, values, try scope.array()), try scope.array());
    return fastUnion(scope, graph, broad);
}
pub fn fastUnion(scope: *Scope, graph: c.JSValue, values: c.JSValue) anyerror!c.JSValue {
    const length = try scope.get(values, "length");
    if (scope.equal(length, c.JS_NewInt32(scope.engine.context, 1))) return head(scope, values);
    if (scope.equal(try scope.get(values, "length"), c.JS_NewInt32(scope.engine.context, 0))) return core.never(scope, graph);
    return core.unionType(scope, graph, values);
}
pub fn intersection(scope: *Scope, graph: c.JSValue, values: c.JSValue) anyerror!c.JSValue {
    const distribution = try distribute(scope, graph, values, try scope.array());
    const broadened = try flatten(scope, try broadenTypes(scope, graph, distribution, try scope.array()), try scope.array());
    return unionValue(scope, graph, broadened);
}
fn exclude(scope: *Scope, graph: c.JSValue, left: c.JSValue, right: c.JSValue) anyerror!c.JSValue {
    const value = try evaluate(scope, graph, left);
    var values = if (try core.kind(scope, value, "Union")) try scope.get(value, "anyOf") else try core.list(scope, &.{value});
    var result = try scope.array();
    while (!try empty(scope, values)) {
        const first = try head(scope, values);
        values = try tail(scope, values);
        if (!try trueLike(scope, try extendsResult(scope, graph, first, right))) result = try append(scope, result, first);
    }
    return unionValue(scope, graph, result);
}
pub fn dependent(scope: *Scope, graph: c.JSValue, if_value: c.JSValue, then_value: c.JSValue, else_value: c.JSValue) anyerror!c.JSValue {
    const intersected = try intersection(scope, graph, try core.list(scope, &.{ if_value, then_value }));
    const excluded = try exclude(scope, graph, else_value, if_value);
    return unionValue(scope, graph, try core.list(scope, &.{ intersected, excluded }));
}
pub fn enumeration(scope: *Scope, graph: c.JSValue, values: c.JSValue, result: c.JSValue) anyerror!c.JSValue {
    if (try empty(scope, values)) return unionValue(scope, graph, result);
    const first = try head(scope, values);
    const rest = try tail(scope, values);
    return enumeration(scope, graph, rest, try append(scope, result, try core.literal(scope, graph, first)));
}
pub fn template(scope: *Scope, graph: c.JSValue, pattern: c.JSValue) anyerror!c.JSValue {
    const decoder = try scope.get(try scope.get(graph, "Type"), "TemplateLiteralDecode");
    if (!c.JS_IsFunction(scope.engine.context, decoder)) return error.MissingActualTypeBoxTemplateLiteralDecode;
    return evaluate(scope, graph, try scope.call(decoder, c.pi_js_undefined(), &.{pattern}));
}
pub fn evaluate(scope: *Scope, graph: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    if (try core.kind(scope, value, "Dependent")) return dependent(scope, graph, try scope.get(value, "if"), try scope.get(value, "then"), try scope.get(value, "else"));
    if (try core.kind(scope, value, "Enum")) return enumeration(scope, graph, try scope.get(value, "enum"), try scope.array());
    if (try core.kind(scope, value, "Intersect")) return intersection(scope, graph, try scope.get(value, "allOf"));
    if (try core.kind(scope, value, "TemplateLiteral")) {
        return template(scope, graph, try scope.get(value, "pattern"));
    }
    if (try core.kind(scope, value, "Union")) return unionValue(scope, graph, try scope.get(value, "anyOf"));
    return value;
}
