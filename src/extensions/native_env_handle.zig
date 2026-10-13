//! Source private Handle objects. Reader calls still dispatch through their ordinary methods.
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const Scope = h.Scope;
const c = js.c;
const Method = enum(c_int) { request, pread, close };
const Stage = enum(c_int) { pread, close };
fn next(engine: *js.Engine, _: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (@as(Stage, @enumFromInt(raw)) == .close) return c.pi_js_undefined();
    if (rejected) return h.throw(&scope, value);
    return c.JS_DupValue(engine.context, try scope.get(value, "payload"));
}
fn invoke(engine: *js.Engine, receiver: c.JSValue, args: []const c.JSValue, bindings: c.JSValue, operation: Method) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (operation == .request) {
        const json = if (c.JS_IsUndefined(h.arg(args, 1))) try scope.object() else h.arg(args, 1);
        const opts = if (c.JS_IsUndefined(h.arg(args, 2))) try scope.object() else h.arg(args, 2);
        const body = try scope.own(try js.spread(engine, json));
        try scope.put(body, "handle", try scope.get(receiver, "id"));
        const options = try scope.own(try js.spread(engine, opts));
        try scope.put(options, "session", try scope.get(receiver, "session"));
        const connection = try scope.get(try scope.get(receiver, "env"), "connection");
        return c.JS_DupValue(engine.context, try scope.invoke(connection, "request", &.{ h.arg(args, 0), body, options }));
    }
    const captures = try scope.object();
    try scope.put(captures, "bindings", bindings);
    const pending = if (operation == .pread) prepared: {
        const json = try scope.object();
        if (!c.JS_IsUndefined(h.arg(args, 0))) try scope.put(json, "offset", h.arg(args, 0));
        try scope.put(json, "length", h.arg(args, 1));
        break :prepared try scope.invoke(receiver, "request", &.{ try scope.text("pread"), json });
    } else try scope.invoke(receiver, "request", &.{try scope.text("close")});
    return c.JS_DupValue(engine.context, try h.wait(next, &scope, captures, pending, if (operation == .pread) Stage.pread else Stage.close));
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const method: Method = @enumFromInt(raw);
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, data[0], method) catch |err| if (method == .request) @import("native_durable.zig").reject(engine, err) else @import("native_durable.zig").rejectedPromise(engine, err);
}
fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const object = try scope.own(try @import("native_class.zig").object(engine, target));
    inline for (.{ "env", "id", "session", "path" }) |key| try scope.put(object, key, c.pi_js_undefined());
    inline for (.{ "env", "id", "session", "path" }, 0..) |key, index| try scope.set(object, key, h.arg(args, index));
    return c.JS_DupValue(engine.context, object);
}
pub fn create(scope: *Scope, bindings: c.JSValue) !c.JSValue {
    const prototype = try scope.object();
    const constructor = try @import("native_class.zig").constructor(scope.engine, "Handle", 4, prototype, construct, &.{});
    _ = try scope.own(constructor);
    var constants = [_]c.JSValue{bindings};
    inline for (.{ .{ "request", Method.request, 1 }, .{ "pread", Method.pread, 2 }, .{ "close", Method.close, 0 } }) |method| {
        const function = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, dispatch, method[0], method[2], @intFromEnum(method[1]), 1, &constants)));
        if (method[1] != .request) {
            const async_prototype = try scope.own(try scope.engine.checked(c.JS_GetAsyncFunctionPrototype(scope.engine.context)));
            if (c.JS_SetPrototype(scope.engine.context, function, async_prototype) < 0) return js.capture(scope.engine);
        }
        if (c.JS_DefinePropertyValueStr(scope.engine.context, prototype, method[0], c.JS_DupValue(scope.engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(scope.engine);
    }
    return constructor;
}
