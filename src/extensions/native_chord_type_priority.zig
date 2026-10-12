//! Actual Value.Clean schema preprocessing, enabled by default upstream.
const v = @import("native_chord_type_values.zig");
const Scope = v.Scope;
const js = v.js;
const c = v.c;
fn typeValue(s: *Scope, name: []const u8, args: []const c.JSValue) !c.JSValue {
    return v.constructor(s, name, args);
}
fn mapCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return sort(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn map(s: *Scope, values: c.JSValue) !c.JSValue {
    const callback = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, mapCallback, "", 1, 0, 0, null)));
    return s.keep(try js.invoke(s.engine, values, "map", &.{callback}));
}
fn properties(s: *Scope, value: c.JSValue) anyerror!c.JSValue {
    const result = try s.record();
    const names = try v.names(s, value);
    const count = try v.length(s, names);
    for (0..count) |index| {
        const key = try s.at(names, index);
        try js.setKey(s.engine, result, key, try s.keep(try sort(s.engine, try s.key(value, key))));
    }
    return result;
}
pub fn recordKey(s: *Scope, value: c.JSValue) anyerror!c.JSValue {
    const pattern = try s.at(try v.names(s, try s.get(value, "patternProperties")), 0);
    if (try s.equal(pattern, "^.*$")) return typeValue(s, "String", &.{});
    if (try s.equal(pattern, "^-?(?:0|[1-9][0-9]*)$")) return typeValue(s, "Integer", &.{});
    if (try s.equal(pattern, "^-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?$")) return typeValue(s, "Number", &.{});
    const literals = try @import("native_typebox_pattern.zig").literals(s.engine, pattern);
    if (literals) |values| {
        _ = try s.keep(values);
        const count = try v.length(s, values);
        if (count == 1) return typeValue(s, "Literal", &.{try s.at(values, 0)});
        const types = try s.list();
        for (0..count) |index| try js.push(s.engine, types, try typeValue(s, "Literal", &.{try s.at(values, index)}));
        return typeValue(s, "Union", &.{types});
    }
    return switch (try @import("native_typebox_pattern.zig").patternKind(s.engine, pattern)) {
        .invalid => typeValue(s, "String", &.{}),
        .infinite => typeValue(s, "TemplateLiteral", &.{pattern}),
        .finite => unreachable,
    };
}
pub fn sort(engine: *js.Engine, value: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    var next = value;
    if (try v.kind(&s, value, "Array")) {
        const item = try s.keep(try sort(engine, try s.get(value, "items")));
        next = try typeValue(&s, "Array", &.{ item, try v.discard(&s, value, &.{ "~kind", "type", "items" }) });
    } else if (try v.kind(&s, value, "Intersect")) {
        next = try typeValue(&s, "Intersect", &.{try map(&s, try s.get(value, "allOf"))});
    } else if (try v.kind(&s, value, "Union")) {
        const prioritized = try s.keep(try @import("native_chord_type_evaluate.zig").priority(engine, try s.get(value, "anyOf")));
        next = try typeValue(&s, "Union", &.{try map(&s, prioritized)});
    } else if (try v.kind(&s, value, "Object")) {
        next = try typeValue(&s, "Object", &.{try properties(&s, try s.get(value, "properties"))});
    } else if (try v.kind(&s, value, "Record")) {
        const key = try recordKey(&s, value);
        const item = try s.keep(try sort(engine, try v.recordValue(&s, value)));
        next = try typeValue(&s, "Record", &.{ key, item });
    } else if (try v.kind(&s, value, "Tuple")) {
        next = try typeValue(&s, "Tuple", &.{try map(&s, try s.get(value, "items"))});
    }
    const names = try v.names(&s, value);
    const count = try v.length(&s, names);
    for (0..count) |index| {
        const key = try s.at(names, index);
        if (try js.hasKey(engine, next, key)) continue;
        try js.setKey(engine, next, key, try s.key(value, key));
    }
    return s.result(next);
}
