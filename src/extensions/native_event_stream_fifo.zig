//! Actual EventStream FifoQueue over its observable ordinary JS fields.
//! Source ae7b16d; no opaque substitute for incoming/outgoing or live methods.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const sdk = @import("native_sdk.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const c = em.c;
const Method = enum(c_int) { length, enqueue, dequeue };
fn hasIncoming(engine: *em.Engine, receiver: c.JSValue) !bool {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return scope.positive(try scope.get(try scope.get(receiver, "incoming"), "length"));
}
fn method(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return dispatch(engine, receiver, @enumFromInt(magic), if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn dispatch(engine: *em.Engine, receiver: c.JSValue, operation: Method, value: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (operation) {
        .length => {
            const incoming = try scope.get(try scope.get(receiver, "incoming"), "length");
            const outgoing = try scope.get(try scope.get(receiver, "outgoing"), "length");
            return engine.checked(c.JS_PiBinaryOperator(engine.context, 0, incoming, outgoing));
        },
        .enqueue => {
            _ = try scope.invoke(try scope.get(receiver, "incoming"), "push", &.{value});
            return c.pi_js_undefined();
        },
        .dequeue => {
            if (scope.equal(try scope.get(try scope.get(receiver, "outgoing"), "length"), c.JS_NewInt32(engine.context, 0))) {
                while (try hasIncoming(engine, receiver)) {
                    var row: Scope = .{ .engine = engine };
                    defer row.deinit();
                    // Source evaluates the outgoing push member before the
                    // incoming pop argument, and reloads both live fields.
                    const outgoing = try row.get(receiver, "outgoing");
                    const push = try row.get(outgoing, "push");
                    const item = try row.invoke(try row.get(receiver, "incoming"), "pop", &.{});
                    _ = try row.call(push, outgoing, &.{item});
                }
            }
            return js.invoke(engine, try scope.get(receiver, "outgoing"), "pop", &.{});
        },
    }
}
fn construct(engine: *em.Engine, target: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.own(try @import("native_class.zig").object(engine, target));
    try scope.put(result, "incoming", try scope.array());
    try scope.put(result, "outgoing", try scope.array());
    return c.JS_DupValue(engine.context, result);
}
pub fn constructor(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.object();
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    const atom = c.JS_NewAtom(engine.context, "length");
    if (atom == c.JS_ATOM_NULL) return js.capture(engine);
    defer c.JS_FreeAtom(engine.context, atom);
    const getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, method, "get length", 0, @intFromEnum(Method.length), 0, null));
    if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    inline for (.{ Method.enqueue, Method.dequeue }) |operation| {
        const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, method, @tagName(operation), if (operation == .enqueue) 1 else 0, @intFromEnum(operation), 0, null)));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, @tagName(operation), c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    return @import("native_class.zig").constructor(engine, "FifoQueue", 0, prototype, construct, &.{});
}
pub fn create(engine: *em.Engine, queue_constructor: c.JSValue) !c.JSValue {
    return engine.checked(c.JS_CallConstructor(engine.context, queue_constructor, 0, null));
}
