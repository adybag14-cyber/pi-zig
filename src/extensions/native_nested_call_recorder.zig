//! NestedCallRecorder's actual bounded record, usage, and snapshot algorithms.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const math = @import("native_image_arithmetic.zig");
const c = em.c;
const Method = enum(c_int) { start, finish, addUsage, snapshot, totalUsage, copy, finished };
pub fn constructor(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.object();
    const encoder = try scope.own(try js.builtin(engine, "TextEncoder", &.{}));
    inline for (.{ Method.start, Method.finish, Method.addUsage, Method.snapshot }) |method| {
        var roots = [_]c.JSValue{encoder};
        const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, @tagName(method), if (method == .finish) 3 else if (method == .snapshot) 0 else 1, @intFromEnum(method), roots.len, &roots)));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, @tagName(method), c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
    const getter = try engine.checked(c.pi_js_function_magic(engine.context, getterCallback, "get totalUsage", 0, 0));
    const atom = c.JS_NewAtom(engine.context, "totalUsage");
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    return @import("native_class.zig").constructor(engine, "NestedCallRecorder", 0, prototype, construct, &.{});
}
fn construct(engine: *em.Engine, target: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.own(try @import("native_class.zig").object(engine, target));
    try scope.put(result, "calls", try scope.array());
    try scope.put(result, "startedAt", try scope.own(try js.builtin(engine, "Map", &.{})));
    try scope.put(result, "complete", c.pi_js_bool(engine.context, 1));
    try scope.put(result, "argumentBytes", c.JS_NewInt32(engine.context, 0));
    try scope.put(result, "usage", c.pi_js_undefined());
    return c.JS_DupValue(engine.context, result);
}
fn argument(argc: c_int, argv: [*c]c.JSValue, index: usize) c.JSValue {
    return if (index < @as(usize, @intCast(@max(0, argc)))) argv[index] else c.pi_js_undefined();
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return apply(engine, receiver, @enumFromInt(magic), argument(argc, argv, 0), argument(argc, argv, 1), argument(argc, argv, 2), roots[0]) catch |err| sdk.fail(engine, err);
}
fn getterCallback(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return sdk.get(engine, receiver, "usage") catch |err| sdk.fail(engine, err);
}
fn now(scope: *Scope) !c.JSValue {
    return scope.invoke(try scope.global("performance"), "now", &.{});
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return callbackBody(engine, @enumFromInt(magic), argument(argc, argv, 0)) catch |err| sdk.fail(engine, err);
}
fn callbackBody(engine: *em.Engine, method: Method, value: c.JSValue) !c.JSValue {
    if (method == .copy) return js.spread(engine, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.pi_js_bool(engine.context, @intFromBool(!scope.equal(try scope.get(value, "status"), try scope.text("unfinished"))));
}
fn apply(engine: *em.Engine, receiver: c.JSValue, method: Method, first: c.JSValue, second: c.JSValue, third: c.JSValue, encoder: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (method) {
        .start => {
            if (try math.compare(engine, .greater_equal, try scope.get(try scope.get(receiver, "calls"), "length"), c.JS_NewInt32(engine.context, 256))) {
                try scope.set(receiver, "complete", c.pi_js_bool(engine.context, 0));
                return c.pi_js_undefined();
            }
            const record = try scope.object();
            try scope.put(record, "id", try scope.get(first, "id"));
            try scope.put(record, "name", try scope.get(first, "name"));
            try scope.put(record, "status", try scope.text("unfinished"));
            const json_class = try scope.global("JSON");
            const stringify = try scope.get(json_class, "stringify");
            var args = try scope.get(first, "arguments");
            if (temp.nullish(args)) args = try scope.object();
            const json = try scope.call(stringify, json_class, &.{args});
            const bytes = try scope.get(try scope.invoke(encoder, "encode", &.{json}), "length");
            if (try math.compare(engine, .greater, bytes, c.JS_NewInt32(engine.context, 8192)) or try math.compare(engine, .greater, try scope.concat(try scope.get(receiver, "argumentBytes"), bytes), c.JS_NewInt32(engine.context, 32768))) {
                try scope.put(record, "argumentsBytes", bytes);
                try scope.set(receiver, "complete", c.pi_js_bool(engine.context, 0));
            } else {
                try scope.put(record, "arguments", try scope.invoke(try scope.global("JSON"), "parse", &.{json}));
                try scope.set(receiver, "argumentBytes", try scope.concat(try scope.get(receiver, "argumentBytes"), bytes));
            }
            _ = try scope.invoke(try scope.get(receiver, "calls"), "push", &.{record});
            const started = try scope.get(receiver, "startedAt");
            const set = try scope.get(started, "set");
            _ = try scope.call(set, started, &.{ record, try now(&scope) });
            return c.JS_DupValue(engine.context, record);
        },
        .finish => {
            if (!scope.truthy(first)) return c.pi_js_undefined();
            try scope.set(first, "status", try scope.text(if (scope.truthy(second)) "error" else "ok"));
            const round_class = try scope.global("Math");
            const round = try scope.get(round_class, "round");
            const end = try now(&scope);
            var began = try scope.invoke(try scope.get(receiver, "startedAt"), "get", &.{first});
            if (temp.nullish(began)) began = try now(&scope);
            try scope.set(first, "durationMs", try scope.call(round, round_class, &.{try scope.own(try math.binary(engine, .subtract, end, began))}));
            _ = try scope.invoke(try scope.get(receiver, "startedAt"), "delete", &.{first});
            if (scope.truthy(second) and scope.truthy(third)) try scope.set(first, "error", try scope.invoke(third, "slice", &.{ c.JS_NewInt32(engine.context, 0), c.JS_NewInt32(engine.context, 500) }));
            return c.pi_js_undefined();
        },
        .addUsage => {
            const previous = try scope.get(receiver, "usage");
            try scope.set(receiver, "usage", if (scope.truthy(previous)) try scope.own(try @import("native_sdk_session_hooks.zig").combineUsage(engine, try scope.get(receiver, "usage"), first)) else first);
            return c.pi_js_undefined();
        },
        .snapshot => {
            if (scope.equal(try scope.get(try scope.get(receiver, "calls"), "length"), c.JS_NewInt32(engine.context, 0)) and scope.truthy(try scope.get(receiver, "complete"))) return c.pi_js_undefined();
            const calls = try scope.invoke(try scope.get(receiver, "calls"), "map", &.{try scope.own(try engine.checked(c.pi_js_function_magic(engine.context, callback, "", 1, @intFromEnum(Method.copy))))});
            const result = try scope.object();
            try scope.put(result, "calls", calls);
            var complete = try scope.get(receiver, "complete");
            if (scope.truthy(complete)) complete = try scope.invoke(calls, "every", &.{try scope.own(try engine.checked(c.pi_js_function_magic(engine.context, callback, "", 1, @intFromEnum(Method.finished))))});
            try scope.put(result, "complete", complete);
            return c.JS_DupValue(engine.context, result);
        },
        else => unreachable,
    }
}
