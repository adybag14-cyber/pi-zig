//! Actual native TypeBox structural instantiation and deferred action routing.
//! Unported actions fail explicitly; this graph is not publicly activated.
const v = @import("native_chord_type_values.zig");
const Scope = v.Scope;
const js = v.js;
const c = v.c;
fn typeValue(s: *Scope, name: []const u8, args: []const c.JSValue) !c.JSValue {
    return v.constructor(s, name, args);
}
pub fn deferred(s: *Scope, name: []const u8, parameters: c.JSValue, options: c.JSValue) !c.JSValue {
    const fields = try s.record();
    try js.define(s.engine, fields, "type", s.result(try s.text("deferred")));
    try js.define(s.engine, fields, "action", s.result(try s.text(name)));
    try js.define(s.engine, fields, "parameters", s.result(parameters));
    try js.define(s.engine, fields, "options", s.result(options));
    return v.create(s, "Deferred", fields, c.pi_js_undefined());
}
fn mapped(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const value = if (argc > 0) argv[0] else c.pi_js_undefined();
    return (if (operation == 0) visit(engine, data[0], data[1], value) else partial(engine, value, operation == 1)) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn map(s: *Scope, context: c.JSValue, visited: c.JSValue, values: c.JSValue, operation: c_int) !c.JSValue {
    var captures = [_]c.JSValue{ context, visited };
    const callback = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, mapped, "", 1, operation, 2, &captures)));
    return s.keep(try js.invoke(s.engine, values, "map", &.{callback}));
}
fn properties(s: *Scope, context: c.JSValue, visited: c.JSValue, values: c.JSValue) anyerror!c.JSValue {
    const result = try s.record();
    const names = try v.names(s, values);
    const count = try v.length(s, names);
    for (0..count) |index| {
        const key = try s.at(names, index);
        const value = try s.keep(try visit(s.engine, context, visited, try s.key(values, key)));
        const atom = try js.atom(s.engine, key);
        defer c.JS_FreeAtom(s.engine.context, atom);
        if (c.JS_DefinePropertyValue(s.engine.context, result, atom, s.result(value), c.JS_PROP_C_W_E) < 0) return js.capture(s.engine);
    }
    return result;
}
fn spreadRest(s: *Scope, values: c.JSValue, target: c.JSValue) anyerror!void {
    const count = try v.length(s, values);
    for (0..count) |index| {
        const value = try s.at(values, index);
        if (try v.kind(s, value, "Rest")) {
            const inner = try s.get(value, "items");
            if (try v.kind(s, inner, "Tuple")) {
                try spreadRest(s, try s.get(inner, "items"), target);
                continue;
            }
            if (!try v.kind(s, inner, "Infer") and !try v.kind(s, inner, "Ref")) {
                try js.push(s.engine, target, try typeValue(s, "Never", &.{}));
                continue;
            }
        }
        try js.push(s.engine, target, value);
    }
}
pub fn elements(engine: *js.Engine, context: c.JSValue, types: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const instantiated = try map(&s, context, try s.list(), types, 0);
    const result = try s.list();
    try spreadRest(&s, instantiated, result);
    return s.result(result);
}
fn partial(engine: *js.Engine, value: c.JSValue, optional: bool) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (try v.kind(&s, value, "Cyclic") or try v.kind(&s, value, "Dependent")) return error.NativeTypeBoxComputedModifierRequired;
    if (try v.kind(&s, value, "Intersect") or try v.kind(&s, value, "Union")) {
        const intersection = try v.kind(&s, value, "Intersect");
        const values = try s.get(value, if (intersection) "allOf" else "anyOf");
        const result = try map(&s, c.pi_js_undefined(), c.pi_js_undefined(), values, if (optional) 1 else 2);
        return s.result(try typeValue(&s, if (intersection) "Intersect" else "Union", &.{result}));
    }
    const result = try s.record();
    if (try v.kind(&s, value, "Object")) {
        const values = try s.get(value, "properties");
        const names = try v.names(&s, values);
        const count = try v.length(&s, names);
        for (0..count) |index| {
            const key = try s.at(names, index);
            const item = try v.changeModifier(&s, try s.key(values, key), "~optional", optional);
            const atom = try js.atom(engine, key);
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DefinePropertyValue(engine.context, result, atom, s.result(item), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
        }
    }
    return s.result(try typeValue(&s, "Object", &.{result}));
}
fn indexKeys(s: *Scope, value: c.JSValue, output: c.JSValue) anyerror!void {
    if (try v.kind(s, value, "Literal")) {
        const text = try s.keep(try s.engine.checked(c.JS_ToString(s.engine.context, try s.get(value, "const"))));
        try js.push(s.engine, output, text);
    } else if (try v.kind(s, value, "Union")) {
        const alternatives = try s.get(value, "anyOf");
        const count = try v.length(s, alternatives);
        for (0..count) |index| try indexKeys(s, try s.at(alternatives, index), output);
    } else return error.NativeTypeBoxComputedIndexerRequired;
}
fn pick(s: *Scope, value: c.JSValue, indexer: c.JSValue) anyerror!c.JSValue {
    if (!try v.kind(s, value, "Object")) return error.NativeTypeBoxCollapseToObjectRequired;
    const keys = try s.list();
    try indexKeys(s, indexer, keys);
    const values = try s.get(value, "properties");
    const names = try v.names(s, values);
    const result = try s.record();
    const count = try v.length(s, names);
    for (0..count) |index| {
        const key = try s.at(names, index);
        if (c.JS_ToBool(s.engine.context, try s.keep(try js.invoke(s.engine, keys, "includes", &.{key}))) == 0) continue;
        const atom = try js.atom(s.engine, key);
        defer c.JS_FreeAtom(s.engine.context, atom);
        if (c.JS_DefinePropertyValue(s.engine.context, result, atom, s.result(try s.key(values, key)), c.JS_PROP_C_W_E) < 0) return js.capture(s.engine);
    }
    return typeValue(s, "Object", &.{result});
}
fn deferredAction(s: *Scope, context: c.JSValue, visited: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    const action = try s.get(value, "action");
    const parameters = try s.get(value, "parameters");
    const options = try s.get(value, "options");
    inline for (.{ .{ "AddImmutable", "~immutable", true }, .{ "RemoveImmutable", "~immutable", false }, .{ "AddReadonly", "~readonly", true }, .{ "RemoveReadonly", "~readonly", false }, .{ "AddOptional", "~optional", true }, .{ "RemoveOptional", "~optional", false } }) |operation| {
        if (try s.equal(action, operation[0])) {
            const item = try s.keep(try visit(s.engine, context, visited, try s.at(parameters, 0)));
            return v.update(s, try v.changeModifier(s, item, operation[1], operation[2]), try s.record(), options);
        }
    }
    if (try s.equal(action, "Evaluate")) {
        const item = try s.keep(try visit(s.engine, context, visited, try s.at(parameters, 0)));
        const evaluated = try s.keep(try @import("native_chord_type_evaluate.zig").evaluate(s.engine, item));
        return v.update(s, evaluated, try s.record(), options);
    }
    if (try s.equal(action, "With")) {
        const item = try s.keep(try visit(s.engine, context, visited, try s.at(parameters, 0)));
        const fields = try s.keep(try visit(s.engine, context, visited, try s.at(parameters, 1)));
        return v.update(s, item, try s.record(), fields);
    }
    if (try s.equal(action, "Partial") or try s.equal(action, "Required")) {
        const optional = try s.equal(action, "Partial");
        const item = try s.keep(try visit(s.engine, context, visited, try s.at(parameters, 0)));
        if (try v.kind(s, item, "Ref")) return deferred(s, if (optional) "Partial" else "Required", try v.list(s, &.{item}), options);
        return v.update(s, try s.keep(try partial(s.engine, item, optional)), try s.record(), options);
    }
    if (try s.equal(action, "Pick") or try s.equal(action, "Record")) {
        const record = try s.equal(action, "Record");
        const first = try s.keep(try visit(s.engine, context, visited, try s.at(parameters, 0)));
        const second = try s.keep(try visit(s.engine, context, visited, try s.at(parameters, 1)));
        if (try v.kind(s, first, "Ref") or (!record and try v.kind(s, second, "Ref"))) return deferred(s, if (record) "Record" else "Pick", try v.list(s, &.{ first, second }), options);
        const result = if (record) try typeValue(s, "Record", &.{ first, second }) else try pick(s, first, second);
        return v.update(s, result, try s.record(), options);
    }
    return error.NativeTypeBoxDeferredActionRequired;
}
fn withModifiers(s: *Scope, original: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    var result = value;
    inline for (.{ "~optional", "~readonly", "~immutable" }) |name| if (try v.modifier(s, original, name)) {
        result = try v.changeModifier(s, result, name, true);
    };
    return result;
}
fn visit(engine: *js.Engine, context: c.JSValue, visited: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (try v.kind(&s, value, "Deferred")) return s.result(try deferredAction(&s, context, visited, value));
    var result = value;
    if (try v.kind(&s, value, "Ref")) {
        const name = try s.get(value, "$ref");
        const previous = try s.keep(try js.invoke(engine, visited, "includes", &.{name}));
        if (c.JS_ToBool(engine.context, previous) == 0 and try js.hasKey(engine, context, name)) {
            const next = try s.keep(try @import("native_iterator_spread.zig").snapshot(engine, visited));
            try js.push(engine, next, name);
            result = try s.keep(try visit(engine, context, next, try s.key(context, name)));
        }
    } else if (try v.kind(&s, value, "Array")) {
        const item = try s.keep(try visit(engine, context, visited, try s.get(value, "items")));
        result = try typeValue(&s, "Array", &.{ item, try v.discard(&s, value, &.{ "~kind", "type", "items" }) });
    } else if (try v.kind(&s, value, "Call") or try v.kind(&s, value, "Constructor") or try v.kind(&s, value, "Function") or try v.kind(&s, value, "Dependent")) {
        return error.NativeTypeBoxComputedStructuralActionRequired;
    } else if (try v.kind(&s, value, "Intersect")) {
        const types = try map(&s, context, visited, try s.get(value, "allOf"), 0);
        result = try typeValue(&s, "Intersect", &.{ types, try v.discard(&s, value, &.{ "~kind", "allOf" }) });
    } else if (try v.kind(&s, value, "Object")) {
        const fields = try properties(&s, context, visited, try s.get(value, "properties"));
        result = try typeValue(&s, "Object", &.{ fields, try v.discard(&s, value, &.{ "~kind", "type", "properties", "required" }) });
    } else if (try v.kind(&s, value, "Record")) {
        const pattern = try s.at(try v.names(&s, try s.get(value, "patternProperties")), 0);
        const item = try s.keep(try visit(engine, context, visited, try v.recordValue(&s, value)));
        const patterns = try s.record();
        try js.setKey(engine, patterns, pattern, item);
        const fields = try s.record();
        try js.define(engine, fields, "type", s.result(try s.text("object")));
        try js.define(engine, fields, "patternProperties", s.result(patterns));
        result = try v.create(&s, "Record", fields, c.pi_js_undefined());
    } else if (try v.kind(&s, value, "Rest")) {
        const fields = try s.record();
        try js.define(engine, fields, "type", s.result(try s.text("rest")));
        try js.define(engine, fields, "items", try visit(engine, context, visited, try s.get(value, "items")));
        result = try v.create(&s, "Rest", fields, c.pi_js_undefined());
    } else if (try v.kind(&s, value, "Tuple")) {
        const values = try map(&s, context, visited, try s.get(value, "items"), 0);
        const spread = try s.list();
        try spreadRest(&s, values, spread);
        result = try typeValue(&s, "Tuple", &.{ spread, try v.discard(&s, value, &.{ "~kind", "type", "items", "minItems", "additionalItems" }) });
    } else if (try v.kind(&s, value, "Union")) {
        result = try typeValue(&s, "Union", &.{ try map(&s, context, visited, try s.get(value, "anyOf"), 0), try v.discard(&s, value, &.{ "~kind", "anyOf" }) });
    }
    return s.result(try withModifiers(&s, value, result));
}
pub fn instantiate(engine: *js.Engine, context: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return visit(engine, context, try s.list(), value);
}
