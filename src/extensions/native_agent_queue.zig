//! Original Agent PendingMessageQueue bodies over ordinary mutable receivers.
//! Private construction is shared by the real Agent constructor; no queue data
//! is serialized and no guest property receives native ownership privileges.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;

const Method = enum(c_int) { enqueue, hasItems, peek, drain, clear };

pub fn constructor(engine: *em.Engine) !c.JSValue {
    const prototype = try sdk.object(engine);
    defer engine.freeValue(prototype);
    const function = try engine.checked(c.JS_NewCFunction2(engine.context, construct, "PendingMessageQueue", 1, c.JS_CFUNC_constructor, 0));
    errdefer engine.freeValue(function);
    if (c.JS_SetConstructor(engine.context, function, prototype) < 0) return js.capture(engine);
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const callback = try engine.checked(c.pi_js_function_magic(engine.context, method, field.name, if (field.value == @intFromEnum(Method.enqueue)) 1 else 0, field.value));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, callback, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
    return function;
}

fn construct(context: ?*c.JSContext, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return create(engine, target, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}

pub fn create(engine: *em.Engine, target: c.JSValue, mode: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.get(target, "prototype");
    const queue = try scope.own(try engine.checked(if (c.JS_IsObject(prototype)) c.JS_NewObjectProto(engine.context, prototype) else c.JS_NewObject(engine.context)));
    try scope.put(queue, "messages", try scope.array());
    try scope.put(queue, "mode", mode);
    return c.JS_DupValue(engine.context, queue);
}

fn method(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return apply(engine, receiver, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}

fn apply(engine: *em.Engine, receiver: c.JSValue, operation: Method, argument: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (operation) {
        .enqueue => {
            _ = try scope.invoke(try scope.get(receiver, "messages"), "push", &.{argument});
        },
        .hasItems => return c.pi_js_bool(engine.context, @intFromBool(try scope.positive(try scope.get(try scope.get(receiver, "messages"), "length")))),
        .peek => {
            if (scope.equal(try scope.get(receiver, "mode"), try scope.text("all"))) return c.JS_DupValue(engine.context, try scope.invoke(try scope.get(receiver, "messages"), "slice", &.{}));
            const messages = try scope.get(receiver, "messages");
            const first = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, messages, 0)));
            const result = try scope.array();
            if (scope.truthy(first)) try scope.index(result, 0, first);
            return c.JS_DupValue(engine.context, result);
        },
        .drain => {
            const drained = try scope.invoke(receiver, "peek", &.{});
            const messages = try scope.get(receiver, "messages");
            const slice = try scope.get(messages, "slice");
            const length = try scope.get(drained, "length");
            try scope.set(receiver, "messages", try scope.call(slice, messages, &.{length}));
            return c.JS_DupValue(engine.context, drained);
        },
        .clear => try scope.set(receiver, "messages", try scope.array()),
    }
    return c.pi_js_undefined();
}
