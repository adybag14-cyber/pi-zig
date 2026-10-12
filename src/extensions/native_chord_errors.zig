//! Chord2 error identities used by native Host ownership and resource lifecycle.
const std = @import("std");
const js = @import("native_js_values.zig");
const values = @import("native_values.zig");
const c = js.c;
const Engine = js.Engine;
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn optional(engine: *Engine, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (c.JS_IsNull(object) or c.JS_IsUndefined(object)) c.pi_js_undefined() else js.get(engine, object, name);
}
fn equal(engine: *Engine, value: c.JSValue, text: []const u8) !bool {
    const string = try engine.checked(c.JS_NewStringLen(engine.context, text.ptr, text.len));
    defer engine.freeValue(string);
    return c.JS_IsStrictEqual(engine.context, value, string);
}
fn construct(engine: *Engine, target: c.JSValue, args: []const c.JSValue, data: []const c.JSValue) !c.JSValue {
    const code = try engine.toString(arg(args, 0));
    defer engine.gpa.free(code);
    const reason = try optional(engine, arg(args, 2), "reason");
    defer engine.freeValue(reason);
    const suffix = if (c.JS_ToBool(engine.context, reason) > 0) blk: {
        const repeated = try optional(engine, arg(args, 2), "reason");
        defer engine.freeValue(repeated);
        const text = try engine.toString(repeated);
        defer engine.gpa.free(text);
        break :blk try std.fmt.allocPrint(engine.gpa, "/{s}", .{text});
    } else try engine.gpa.dupe(u8, "");
    defer engine.gpa.free(suffix);
    const message = try engine.toString(arg(args, 1));
    defer engine.gpa.free(message);
    const text = try std.fmt.allocPrint(engine.gpa, "{s}{s}: {s}", .{ code, suffix, message });
    defer engine.gpa.free(text);
    const formatted = try engine.checked(c.JS_NewStringLen(engine.context, text.ptr, text.len));
    defer engine.freeValue(formatted);
    const options = try js.object(engine);
    defer engine.freeValue(options);
    try js.define(engine, options, "cause", try optional(engine, arg(args, 2), "cause"));
    var base_args = [_]c.JSValue{ formatted, options };
    const object = try engine.checked(c.JS_CallConstructor2(engine.context, data[0], target, 2, &base_args));
    errdefer engine.freeValue(object);
    inline for (.{ "code", "reason", "retryable", "details" }) |name| try js.define(engine, object, name, c.pi_js_undefined());
    try values.put(engine, object, "name", try engine.checked(c.JS_NewString(engine.context, "ChordError")));
    try values.put(engine, object, "code", c.JS_DupValue(engine.context, arg(args, 0)));
    try values.put(engine, object, "reason", try optional(engine, arg(args, 2), "reason"));
    try values.put(engine, object, "retryable", c.pi_js_bool(engine.context, @intFromBool(try equal(engine, arg(args, 0), "superseded") or try equal(engine, arg(args, 0), "upgrade_conflict"))));
    try values.put(engine, object, "details", try optional(engine, arg(args, 2), "details"));
    return object;
}
pub fn create(engine: *Engine, constructor: c.JSValue, code: []const u8, message: []const u8, options: c.JSValue) !c.JSValue {
    const code_value = try engine.checked(c.JS_NewStringLen(engine.context, code.ptr, code.len));
    defer engine.freeValue(code_value);
    const message_value = try engine.checked(c.JS_NewStringLen(engine.context, message.ptr, message.len));
    defer engine.freeValue(message_value);
    var args = [_]c.JSValue{ code_value, message_value, options };
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, 3, &args));
}
fn helper(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return invoke(engine, if (argc > 0) argv[0..@intCast(argc)] else &.{}, operation, data[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn invoke(engine: *Engine, args: []const c.JSValue, operation: c_int, constructor: c.JSValue) !c.JSValue {
    if (operation == 0 or operation == 3) {
        const instance = c.JS_IsInstanceOf(engine.context, arg(args, 0), constructor);
        if (instance < 0) return js.capture(engine);
        if (operation == 0) {
            if (instance == 0) return c.pi_js_bool(engine.context, 0);
            if (c.JS_IsUndefined(arg(args, 1))) return c.pi_js_bool(engine.context, 1);
            const code = try js.get(engine, arg(args, 0), "code");
            defer engine.freeValue(code);
            return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, code, arg(args, 1))));
        }
        if (instance != 0) return c.JS_DupValue(engine.context, arg(args, 0));
        const label = try engine.toString(arg(args, 1));
        defer engine.gpa.free(label);
        const base_error = try js.global(engine, "Error");
        defer engine.freeValue(base_error);
        const is_error = c.JS_IsInstanceOf(engine.context, arg(args, 0), base_error);
        if (is_error < 0) return js.capture(engine);
        const description = if (is_error > 0) try js.get(engine, arg(args, 0), "message") else blk: {
            const string = try js.global(engine, "String");
            defer engine.freeValue(string);
            break :blk try js.call(engine, string, c.pi_js_undefined(), &.{arg(args, 0)});
        };
        defer engine.freeValue(description);
        const detail = try engine.toString(description);
        defer engine.gpa.free(detail);
        const text = try std.fmt.allocPrint(engine.gpa, "{s}: {s}", .{ label, detail });
        defer engine.gpa.free(text);
        const options = try js.object(engine);
        defer engine.freeValue(options);
        try js.define(engine, options, "cause", c.JS_DupValue(engine.context, arg(args, 0)));
        return create(engine, constructor, "unavailable", text, options);
    }
    const options = try js.object(engine);
    defer engine.freeValue(options);
    var arguments = [_]c.JSValue{ c.pi_js_undefined(), c.pi_js_undefined(), options };
    if (operation == 1) {
        arguments[2] = c.pi_js_undefined();
        arguments[0] = try engine.checked(c.JS_NewString(engine.context, "forbidden"));
        arguments[1] = if (c.JS_IsUndefined(arg(args, 0))) try engine.checked(c.JS_NewString(engine.context, "forbidden")) else c.JS_DupValue(engine.context, arg(args, 0));
    } else {
        arguments[0] = try engine.checked(c.JS_NewString(engine.context, "invalid"));
        arguments[1] = c.JS_DupValue(engine.context, arg(args, 1));
        try js.define(engine, options, "reason", c.JS_DupValue(engine.context, arg(args, 0)));
        try js.define(engine, options, "details", c.JS_DupValue(engine.context, arg(args, 2)));
    }
    defer engine.freeValue(arguments[0]);
    defer engine.freeValue(arguments[1]);
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, arguments.len, &arguments));
}
/// Return concrete error exports without activating the incomplete Chord package.
pub fn exports(engine: *Engine) !c.JSValue {
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    const base = try js.global(engine, "Error");
    defer engine.freeValue(base);
    const base_prototype = try js.get(engine, base, "prototype");
    defer engine.freeValue(base_prototype);
    const prototype = try engine.checked(c.JS_NewObjectProto(engine.context, base_prototype));
    defer engine.freeValue(prototype);
    const constructor = try @import("native_class.zig").constructor(engine, "ChordError", 3, prototype, construct, &.{base});
    defer engine.freeValue(constructor);
    if (c.JS_SetPrototype(engine.context, constructor, base) < 0) return js.capture(engine);
    try js.define(engine, result, "ChordError", c.JS_DupValue(engine.context, constructor));
    inline for (.{ .{ "isChordError", 2 }, .{ "forbidden", 0 }, .{ "invalid", 3 }, .{ "asChordError", 2 } }, 0..) |entry, operation| {
        var data = [_]c.JSValue{constructor};
        try js.define(engine, result, entry[0], try engine.checked(c.JS_NewCFunctionData2(engine.context, helper, entry[0], entry[1], @intCast(operation), 1, &data)));
    }
    return result;
}
