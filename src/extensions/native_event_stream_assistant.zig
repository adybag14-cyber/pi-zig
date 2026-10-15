//! Source AssistantMessageEventStream over the actual live-field base class.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const arithmetic = @import("native_image_arithmetic.zig");
const native = @import("native_node_function.zig");
const core = @import("native_event_stream_core.zig");
const c = em.c;
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
fn isComplete(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const event = argument(args, 0);
    return c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.get(event, "type"), try scope.text("done")) or scope.equal(try scope.get(event, "type"), try scope.text("error"))));
}
fn extractResult(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const event = argument(args, 0);
    if (scope.equal(try scope.get(event, "type"), try scope.text("done"))) return js.get(engine, event, "message");
    if (scope.equal(try scope.get(event, "type"), try scope.text("error"))) return js.get(engine, event, "error");
    const failure = try scope.own(try js.builtin(engine, "Error", &.{try scope.text("Unexpected event type for final result")}));
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, failure)));
}
fn construct(engine: *em.Engine, target: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = roots[0];
    const self_constructor = try scope.get(owner, "constructor");
    const parent = try scope.own(try engine.checked(c.JS_GetPrototype(engine.context, self_constructor)));
    var args = [_]c.JSValue{ try scope.own(try native.createArrow(engine, "", 1, isComplete, &.{})), try scope.own(try native.createArrow(engine, "", 1, extractResult, &.{})) };
    const instance = try scope.own(try engine.checked(c.JS_CallConstructor2(engine.context, parent, target, args.len, &args)));
    const wall = try scope.invoke(try scope.global("Date"), "now", &.{});
    const monotonic = try scope.invoke(try scope.global("performance"), "now", &.{});
    const clocks = try scope.object();
    try scope.put(clocks, "wall", wall);
    try scope.put(clocks, "monotonic", monotonic);
    _ = try scope.call(try scope.get(owner, "set"), try scope.get(owner, "clocks"), &.{ instance, clocks });
    return c.JS_DupValue(engine.context, instance);
}
fn privateClocks(scope: *Scope, owner: c.JSValue, receiver: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    // An intrinsic WeakMap stores the private brand/clocks without adding own
    // properties or retaining an otherwise unreachable stream instance.
    const clocks = try scope.call(try scope.get(owner, "get"), try scope.get(owner, "clocks"), &.{receiver});
    if (c.JS_IsUndefined(clocks)) return js.typeError(engine, "Receiver must be an instance of class AssistantMessageEventStream");
    return clocks;
}
fn time(scope: *Scope, clocks: c.JSValue, receiver: c.JSValue, message: c.JSValue) !void {
    const engine = scope.engine;
    if (scope.truthy(try scope.get(receiver, "done")) or !c.JS_IsUndefined(try scope.get(message, "durationMs"))) return;
    if (try arithmetic.compare(engine, .less, try scope.get(message, "timestamp"), try scope.get(clocks, "wall"))) return;
    // Preserve the actual nested member evaluation order observed by Source27.
    const maximum_owner = try scope.global("Math");
    const maximum = try scope.get(maximum_owner, "max");
    const round_owner = try scope.global("Math");
    const round = try scope.get(round_owner, "round");
    const now = try scope.invoke(try scope.global("performance"), "now", &.{});
    const elapsed = try scope.own(try arithmetic.binary(engine, .subtract, now, try scope.get(clocks, "monotonic")));
    const rounded = try scope.call(round, round_owner, &.{elapsed});
    const duration = try scope.call(maximum, maximum_owner, &.{ c.JS_NewInt32(engine.context, 0), rounded });
    try scope.set(message, "durationMs", duration);
}
fn superCall(scope: *Scope, owner: c.JSValue, receiver: c.JSValue, name: []const u8, value: c.JSValue) !c.JSValue {
    const parent = try scope.own(try scope.engine.checked(c.JS_GetPrototype(scope.engine.context, try scope.get(owner, "prototype"))));
    // Captured intrinsic Reflect.get implements super's separate receiver,
    // including an inherited getter's this binding and live parent mutation.
    const function = try scope.call(try scope.get(owner, "reflectGet"), try scope.get(owner, "reflect"), &.{ parent, try scope.text(name), receiver });
    return js.call(scope.engine, function, receiver, &.{value});
}
fn push(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const event = argument(args, 0);
    if (scope.equal(try scope.get(event, "type"), try scope.text("done"))) {
        const clocks = try privateClocks(&scope, roots[0], receiver);
        try time(&scope, clocks, receiver, try scope.get(event, "message"));
    } else if (scope.equal(try scope.get(event, "type"), try scope.text("error"))) {
        const clocks = try privateClocks(&scope, roots[0], receiver);
        try time(&scope, clocks, receiver, try scope.get(event, "error"));
    }
    return superCall(&scope, roots[0], receiver, "push", event);
}
fn end(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = argument(args, 0);
    if (!c.JS_IsUndefined(result)) try time(&scope, try privateClocks(&scope, roots[0], receiver), receiver, result);
    return superCall(&scope, roots[0], receiver, "end", result);
}
fn factory(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return engine.checked(c.JS_CallConstructor(engine.context, roots[0], 0, null));
}
pub fn create(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const base = try scope.own(try core.constructor(engine));
    const base_prototype = try scope.get(base, "prototype");
    const prototype = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, base_prototype)));
    const owner = try scope.object();
    try scope.put(owner, "prototype", prototype);
    const clocks = try scope.own(try js.builtin(engine, "WeakMap", &.{}));
    try scope.put(owner, "clocks", clocks);
    try scope.put(owner, "get", try scope.get(clocks, "get"));
    try scope.put(owner, "set", try scope.get(clocks, "set"));
    const reflect = try scope.global("Reflect");
    try scope.put(owner, "reflect", reflect);
    try scope.put(owner, "reflectGet", try scope.get(reflect, "get"));
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    const push_method = try native.createMethod(engine, "push", 1, push, &.{owner});
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "push", push_method, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    const end_method = try native.createMethod(engine, "end", 1, end, &.{owner});
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "end", end_method, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    const assistant = try scope.own(try @import("native_class.zig").constructor(engine, "AssistantMessageEventStream", 0, prototype, construct, &.{owner}));
    if (c.JS_SetPrototype(engine.context, assistant, base) < 0) return js.capture(engine);
    try scope.put(owner, "constructor", assistant);
    const namespace = try scope.object();
    try scope.put(namespace, "EventStream", base);
    try scope.put(namespace, "AssistantMessageEventStream", assistant);
    try scope.put(namespace, "createAssistantMessageEventStream", try scope.own(try native.create(engine, "createAssistantMessageEventStream", 0, factory, &.{assistant})));
    return c.JS_DupValue(engine.context, namespace);
}
