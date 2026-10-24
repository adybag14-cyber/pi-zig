// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual loader.js circular exports and its shared warning prototype.
//! The canonical Module supplies its private parent/symbol and real process.
//! k_evaluated is the actual internalBinding('module_wrap') value, never inferred.
const a = @import("native_node_argument_values.zig");
const c = a.c;
const Scope = a.Scope;
const modules = @import("native_node_module_constructor.zig");
const functions = @import("native_node_module_callable.zig");
const registration = @import("native_node_string_error_registration.zig");
const Frame = a.frames.Frame(enum { required_esm, message, parent });
const Root = enum(usize) {
    module, required_symbol, evaluated, proxy, object_prototype,
    get_prototype, set_prototype, cycle_error,
};
fn root(roots: []const c.JSValue, comptime selected: Root) c.JSValue {
    return roots[@intFromEnum(selected)];
}
fn adoptPrepared(s: *Scope, prepared: @import("native_node_argument_bootstrap.zig").Prepared) !void {
    var values = [_]c.JSValue{
        prepared.internal_inspect, prepared.assert_function,
        prepared.arguments.invalid_arg_type, prepared.arguments.hidden_invalid_arg_type,
        prepared.arguments.invalid_arg_value, prepared.arguments.internal_assertion,
        prepared.arguments.validate_string,
    };
    for (&values, 0..) |*slot, position| {
        const incoming = slot.*;
        slot.* = c.pi_js_undefined();
        _ = s.own(incoming) catch |err| {
            for (values[position + 1 ..]) |*remaining| s.boundary.release(remaining);
            return err;
        };
    }
}
fn cycleError(s: *Scope) !c.JSValue {
    const prepared = try @import("native_node_argument_bootstrap.zig").prepare(s.engine);
    try adoptPrepared(s, prepared);
    const core = try s.own(a.duplicate(s.engine, try @import("native_node_stream.zig").owner(s.engine)));
    const system = try s.own(a.duplicate(s.engine, try @import("native_node_system_errors.zig").registry(s.engine)));
    const errors = @import("native_node_argument_errors.zig");
    return registration.register(s, try s.get(core, "Error"), "ERR_REQUIRE_CYCLE_MODULE", "%s",
        try s.get(system, "marker"), prepared.assert_function,
        try s.own(try errors.reflectApply(s.engine)), prepared.internal_inspect,
        try s.own(try errors.arrayUnshift(s.engine)));
}
/// One actual loader module creates this graph before user modules run. No
/// public node:module, substitute Module, ESM status or require cache is made.
pub fn create(engine: *a.v.em.Engine, module: c.JSValue, k_evaluated: c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    return a.expression(engine, createBody, .{ module, k_evaluated });
}
fn createBody(s: *Scope, module: c.JSValue, k_evaluated: c.JSValue) !c.JSValue {
    try s.pending();
    if (!c.JS_IsNumber(k_evaluated)) return error.ActualModuleWrapEvaluatedStatusRequired;
    // This validates the genuine, already-created constructor; mutable
    // Module.Module and properties of a replacement constructor are not used.
    const lexical = try s.own(try modules.loaderEnvironment(s.engine, module));
    const process = try s.get(lexical, "process");
    const required = try s.own(try modules.loaderKey(s.engine, module, .required_module));
    // These are the exact primordial imports captured by the same canonical
    // Module before guest execution, even if this leaf is linked later.
    const object_prototype = try s.get(lexical, "circularObjectPrototype");
    const string = try s.get(lexical, "circularString");
    const has_own = try s.get(lexical, "circularHasOwnProperty");
    const get_descriptor = try s.get(lexical, "circularGetOwnPropertyDescriptor");
    const get_prototype = try s.get(lexical, "circularGetPrototypeOf");
    const set_prototype = try s.get(lexical, "circularSetPrototypeOf");
    const error_constructor = try cycleError(s);
    // Source new Proxy({}, { __proto__: null, get, getOwnPropertyDescriptor }).
    const target = try s.object();
    const handler = try s.objectProto(c.pi_js_null());
    try s.put(handler, "get", try s.own(try functions.create(s.engine, "get", 2, false,
        getTrap, &.{ process, string })));
    try s.put(handler, "getOwnPropertyDescriptor", try s.own(try functions.create(s.engine,
        "getOwnPropertyDescriptor", 2, false, descriptorTrap, &.{ process, string, has_own, get_descriptor })));
    const generation = try s.beforeAllocation();
    const proxy = try s.checkedAllocation(c.JS_NewProxy(s.engine.context, target, handler), generation);
    const get_exports = try s.own(try functions.create(s.engine, "getExportsForCircularRequire", 1, true,
        getExports, &.{ module, required, k_evaluated, proxy, object_prototype,
            get_prototype, set_prototype, error_constructor }));
    const result = try s.objectProto(c.pi_js_null());
    try s.put(result, "getExportsForCircularRequire", get_exports);
    try s.put(result, "CircularRequirePrototypeWarningProxy", proxy);
    return a.duplicate(s.engine, result);
}
fn warn(s: *Scope, process: c.JSValue, string: c.JSValue, property: c.JSValue) !void {
    // Member callee is read before String(prop), exactly as the Source call.
    const emit = try s.get(process, "emitWarning");
    const name = try s.call(string, c.pi_js_undefined(), &.{property});
    var message = try a.add(s, try s.text("Accessing non-existent property '"), name);
    message = try a.add(s, message, try s.text("' of module exports inside circular dependency"));
    _ = try s.call(emit, process, &.{message});
}
fn getTrap(engine: *a.v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, getTrapBody, .{ a.arg(args, 0), a.arg(args, 1), roots });
}
fn getTrapBody(s: *Scope, target: c.JSValue, property: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    if (try s.hasKey(target, property) or s.equal(property, try s.text("__esModule")))
        return a.duplicate(s.engine, try s.getKey(target, property));
    try warn(s, roots[0], roots[1], property);
    return c.pi_js_undefined();
}
fn descriptorTrap(engine: *a.v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, descriptorTrapBody, .{ a.arg(args, 0), a.arg(args, 1), roots });
}
fn descriptorTrapBody(s: *Scope, target: c.JSValue, property: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    if (s.truthy(try s.call(roots[2], target, &.{property})) or s.equal(property, try s.text("__esModule")))
        return a.duplicate(s.engine, try s.call(roots[3], c.pi_js_undefined(), &.{ target, property }));
    try warn(s, roots[0], roots[1], property);
    return c.pi_js_undefined();
}
fn requiredModule(s: *Scope, module: c.JSValue, key: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.getKey(module, key));
}
fn unevaluated(s: *Scope, required: c.JSValue, evaluated: c.JSValue) !c.JSValue {
    return a.boolean(s, !s.equal(try s.call(try s.get(required, "getStatus"), required, &.{}), evaluated));
}
fn cycleMessage(s: *Scope, module: c.JSValue) !c.JSValue {
    var message = try a.add(s, try s.text("Cannot require() ES Module "),
        try s.own(try a.fieldText(s.engine, module, "id")));
    message = try a.add(s, message, try s.text(" in a cycle."));
    return a.duplicate(s.engine, message);
}
fn parentMessage(s: *Scope, message: c.JSValue, parent: c.JSValue) !c.JSValue {
    var value = try a.add(s, message, try s.text(" (from "));
    value = try a.add(s, value, try s.own(try a.fieldText(s.engine, parent, "filename")));
    return a.duplicate(s.engine, try a.add(s, value, try s.text(")")));
}
fn nonProxy(s: *Scope, module: c.JSValue) !c.JSValue {
    return a.boolean(s, !c.JS_IsProxy(try s.get(module, "exports")));
}
fn plainExports(s: *Scope, module: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.boolean(s, s.equal(try s.call(root(roots, .get_prototype), c.pi_js_undefined(),
        &.{try s.get(module, "exports")}), root(roots, .object_prototype)));
}
fn notEsModule(s: *Scope, module: c.JSValue) !c.JSValue {
    return a.boolean(s, !s.truthy(try s.get(try s.get(module, "exports"), "__esModule")));
}
fn setWarningPrototype(s: *Scope, module: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    _ = try s.call(root(roots, .set_prototype), c.pi_js_undefined(),
        &.{ try s.get(module, "exports"), root(roots, .proxy) });
    return c.pi_js_undefined();
}
fn getExports(engine: *a.v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = Frame.create(&s.values) catch |err| return s.finish(err);
    return a.finishFrame(&s, frame, getExportsBody(&s, frame, a.arg(args, 0), roots));
}
fn getExportsBody(s: *Scope, frame: *Frame, module: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try frame.take(.required_esm, a.expression(s.engine, requiredModule, .{ module, root(roots, .required_symbol) }));
    if (s.truthy(frame.get(.required_esm)) and
        try a.condition(s.engine, unevaluated, .{ frame.get(.required_esm), root(roots, .evaluated) }))
    {
        try frame.take(.message, a.expression(s.engine, cycleMessage, .{module}));
        try frame.take(.parent, modules.lastParent(s.engine, root(roots, .module), module));
        if (s.truthy(frame.get(.parent)))
            try frame.take(.message, a.expression(s.engine, parentMessage, .{ frame.get(.message), frame.get(.parent) }));
        const reason = try s.construct(root(roots, .cycle_error), &.{frame.get(.message)});
        return a.raise(s, reason);
    }
    // Preserve every separate Source module.exports Get (six on the plain
    // object path). A getter may replace it between these expressions.
    if (try a.condition(s.engine, a.fieldTruthy, .{ module, @as([*:0]const u8, "exports") }) and
        try a.condition(s.engine, nonProxy, .{module}) and
        try a.condition(s.engine, plainExports, .{ module, roots }) and
        try a.condition(s.engine, notEsModule, .{module}))
    {
        _ = try a.expression(s.engine, setWarningPrototype, .{ module, roots });
    }
    return a.field(s.engine, module, "exports");
}
