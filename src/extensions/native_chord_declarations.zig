//! Actual branded Chord declaration and facet/registry token constructors.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
const Method = enum(c_int) { cell, resource, listener, derivation, declKind, defineFacet, defineRegistry };
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return invoke(engine, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(operation), data[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn invoke(engine: *h.Engine, args: []const c.JSValue, method: Method, bindings: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const symbol = try s.get(bindings, "declSymbol");
    if (method == .declKind) {
        const value = h.arg(args, 0);
        return if (c.JS_IsObject(value) and !c.JS_IsFunction(engine.context, value)) js.getKey(engine, value, symbol) else c.pi_js_undefined();
    }
    const result = try s.record();
    if (method == .defineFacet or method == .defineRegistry) {
        const options = if (c.JS_IsUndefined(h.arg(args, 1))) try s.record() else args[1];
        try h.field(&s, result, if (method == .defineFacet) "setup" else "name", h.arg(args, 0));
        const option = try s.get(options, if (method == .defineFacet) "uses" else "conflict");
        try h.field(&s, result, if (method == .defineFacet) "uses" else "conflict", if (method == .defineRegistry and h.nullish(option)) try s.text("error") else option);
        return s.result(result);
    }
    try js.setKey(engine, result, symbol, try s.text(@tagName(method)));
    switch (method) {
        .cell => {
            try h.field(&s, result, "schema", h.arg(args, 0));
            try h.field(&s, result, "initial", h.arg(args, 1));
        },
        .resource => try h.field(&s, result, "spec", h.arg(args, 0)),
        .listener => {
            try h.field(&s, result, "source", h.arg(args, 0));
            try h.field(&s, result, "select", if (args.len == 2) c.pi_js_undefined() else h.arg(args, 1));
            try h.field(&s, result, "fn", h.arg(args, if (args.len == 2) 1 else 2));
        },
        .derivation => {
            try h.field(&s, result, "sources", h.arg(args, 0));
            try h.field(&s, result, "fn", h.arg(args, 1));
        },
        else => unreachable,
    }
    return s.result(result);
}
pub fn exports(engine: *h.Engine, bindings: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const symbol_constructor = try s.keep(try js.global(engine, "Symbol"));
    const symbol = try s.keep(try js.call(engine, symbol_constructor, c.pi_js_undefined(), &.{try s.text("chord.decl")}));
    try h.field(&s, bindings, "declSymbol", symbol);
    const result = try s.record();
    inline for (.{ .{ "cell", 2, Method.cell }, .{ "resource", 1, Method.resource }, .{ "listener", 1, Method.listener }, .{ "derivation", 2, Method.derivation }, .{ "declKind", 1, Method.declKind }, .{ "defineFacet", 1, Method.defineFacet }, .{ "defineRegistry", 1, Method.defineRegistry } }) |item| {
        var captures = [_]c.JSValue{bindings};
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, item[0], item[1], @intFromEnum(item[2]), 1, &captures));
        if (item[2] == .listener) {
            // The overload implementation is an ordinary function; its rest
            // parameter leaves length1 and construction follows Node behavior.
            engine.freeValue(function);
            try js.define(engine, result, item[0], try @import("native_node_function.zig").create(engine, item[0], 1, listener, &.{bindings}));
        } else try js.define(engine, result, item[0], function);
    }
    return s.result(result);
}
fn listener(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    return invoke(engine, args, .listener, values[0]);
}
