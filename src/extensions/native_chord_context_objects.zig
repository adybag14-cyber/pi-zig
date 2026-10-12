//! Chord2 Context classes with native private storage and ordinary prototypes.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const Engine = js.Engine;
const Kind = enum(c_int) { empty, value };
const State = struct { engine: *Engine, kind: Kind, parent: c.JSValue, key: c.JSValue, value: c.JSValue, name: c.JSValue };
fn finalizer(runtime: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    inline for (.{ "parent", "key", "value", "name" }) |field| c.JS_FreeValueRT(runtime, @field(state, field));
    state.engine.gpa.destroy(state);
}
fn mark(runtime: ?*c.JSRuntime, object: c.JSValue, visitor: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    inline for (.{ "parent", "key", "value", "name" }) |field| c.JS_MarkValue(runtime, @field(state, field), visitor);
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn construct(engine: *Engine, target: c.JSValue, args: []const c.JSValue, data: []const c.JSValue) !c.JSValue {
    var class_id: u32 = undefined;
    if (c.JS_ToUint32(engine.context, &class_id, data[0]) < 0) return js.capture(engine);
    const kind: Kind = if (c.JS_ToBool(engine.context, data[1]) != 0) .value else .empty;
    var prototype = try js.get(engine, target, "prototype");
    defer engine.freeValue(prototype);
    if (!c.JS_IsObject(prototype)) {
        const sample = try js.object(engine);
        defer engine.freeValue(sample);
        const fallback = try engine.checked(c.JS_GetPrototype(engine.context, sample));
        engine.freeValue(prototype);
        prototype = fallback;
    }
    const object = try engine.checked(c.JS_NewObjectProtoClass(engine.context, prototype, class_id));
    errdefer engine.freeValue(object);
    const state = try engine.gpa.create(State);
    state.* = .{ .engine = engine, .kind = kind, .parent = c.JS_DupValue(engine.context, if (kind == .value) arg(args, 0) else c.pi_js_undefined()), .key = c.JS_DupValue(engine.context, if (kind == .value) arg(args, 1) else c.pi_js_undefined()), .value = c.JS_DupValue(engine.context, if (kind == .value) arg(args, 2) else c.pi_js_undefined()), .name = c.JS_DupValue(engine.context, if (kind == .empty) arg(args, 0) else c.pi_js_undefined()) };
    _ = c.JS_SetOpaque(object, state);
    return object;
}
fn constructBase(engine: *Engine, target: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return @import("native_class.zig").object(engine, target);
}
fn method(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return invoke(engine, receiver, if (argc > 0) argv[0] else c.pi_js_undefined(), operation, data) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn invoke(engine: *Engine, receiver: c.JSValue, key: c.JSValue, operation: c_int, data: [*c]c.JSValue) !c.JSValue {
    // EmptyContext.value does not access a private field and accepts any this.
    if (operation == 0) return c.pi_js_undefined();
    if (operation == 4) return js.invoke(engine, receiver, "value", &.{data[0]});
    var class_id: u32 = undefined;
    if (c.JS_ToUint32(engine.context, &class_id, data[0]) < 0) return js.capture(engine);
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque2(engine.context, receiver, class_id) orelse return js.capture(engine)));
    if (operation == 1) return c.JS_DupValue(engine.context, state.name);
    if (operation == 2) {
        const requested = try js.get(engine, key, "token");
        defer engine.freeValue(requested);
        const stored = try js.get(engine, state.key, "token");
        defer engine.freeValue(stored);
        if (c.JS_IsStrictEqual(engine.context, requested, stored)) return c.JS_DupValue(engine.context, state.value);
        return js.invoke(engine, state.parent, "value", &.{key});
    }
    const parent = try engine.toString(state.parent);
    defer engine.gpa.free(parent);
    const token = try js.get(engine, state.key, "token");
    defer engine.freeValue(token);
    const description = try js.get(engine, token, "description");
    defer engine.freeValue(description);
    const label = if (c.JS_IsNull(description) or c.JS_IsUndefined(description)) try engine.gpa.dupe(u8, "anonymous") else try engine.toString(description);
    defer engine.gpa.free(label);
    const text = try std.fmt.allocPrint(engine.gpa, "{s}.WithValue({s})", .{ parent, label });
    defer engine.gpa.free(text);
    return engine.checked(c.JS_NewStringLen(engine.context, text.ptr, text.len));
}
fn defineMethod(engine: *Engine, prototype: c.JSValue, name: [*:0]const u8, length: c_int, operation: c_int, capture: c.JSValue) !void {
    var data = [_]c.JSValue{capture};
    const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, method, name, length, operation, 1, &data));
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, name, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
}
fn derivedClass(engine: *Engine, base: c.JSValue, name: [:0]const u8, kind: Kind) !c.JSValue {
    var class_id: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class_id);
    const definition: c.JSClassDef = .{ .class_name = name.ptr, .finalizer = finalizer, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, class_id, &definition) < 0) return error.OutOfMemory;
    const base_prototype = try js.get(engine, base, "prototype");
    defer engine.freeValue(base_prototype);
    const prototype = try engine.checked(c.JS_NewObjectProto(engine.context, base_prototype));
    defer engine.freeValue(prototype);
    const identifier = c.JS_NewUint32(engine.context, class_id);
    const constructor = try @import("native_class.zig").constructor(engine, name, if (kind == .empty) 1 else 3, prototype, construct, &.{ identifier, c.pi_js_bool(engine.context, @intFromBool(kind == .value)) });
    errdefer engine.freeValue(constructor);
    if (c.JS_SetPrototype(engine.context, constructor, base) < 0) return js.capture(engine);
    try defineMethod(engine, prototype, "value", 1, if (kind == .empty) 0 else 2, identifier);
    try defineMethod(engine, prototype, "toString", 0, if (kind == .empty) 1 else 3, identifier);
    return constructor;
}
/// Private per-module bindings, retained only through exported native functions.
pub fn bindings(engine: *Engine, abort_key: c.JSValue) !c.JSValue {
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    const prototype = try js.object(engine);
    defer engine.freeValue(prototype);
    const base = try @import("native_class.zig").constructor(engine, "BaseContext", 0, prototype, constructBase, &.{});
    defer engine.freeValue(base);
    var data = [_]c.JSValue{abort_key};
    const getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, method, "get abortSignal", 0, 4, 1, &data));
    defer engine.freeValue(getter);
    const atom = c.JS_NewAtom(engine.context, "abortSignal");
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, c.JS_DupValue(engine.context, getter), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    try js.define(engine, result, "EmptyContext", try derivedClass(engine, base, "EmptyContext", .empty));
    try js.define(engine, result, "ContextValue", try derivedClass(engine, base, "ContextValue", .value));
    try js.define(engine, result, "abortKey", c.JS_DupValue(engine.context, abort_key));
    return result;
}
pub fn create(engine: *Engine, bindings_value: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const constructor = try js.get(engine, bindings_value, name);
    defer engine.freeValue(constructor);
    const generation = engine.native_allocation_generation;
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, @intCast(args.len), @constCast(args.ptr))) catch |err| return engine.nativeAllocationError(err, generation);
}
