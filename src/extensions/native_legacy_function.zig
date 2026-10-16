//! Isolated SOURCE-ONLY CJS legacy-function class draft.
//! Actual caller/arguments-shape corpus, GC/failure/VM-heap gates remain pending.
//! Existing strict native_node_function and public VM behavior stay unchanged.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const Engine = js.Engine;
pub const Callback = @import("native_node_function.zig").Callback;
const Frame = struct {
    engine: *Engine,
    function: c.JSValue,
    arguments: []c.JSValue,
    caller: c.JSValue,
    identity: usize,
    previous_same: ?*Frame,
};
threadlocal var logical_frame: ?*Frame = null;
const State = struct {
    engine: *Engine,
    callback: Callback,
    values: []c.JSValue,
    properties: c.JSValue,
    arguments_atom: c.JSAtom,
    caller_atom: c.JSAtom,
    active: ?*Frame = null,
};
fn state(value: c.JSValue) *State {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
}
fn fail(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
    return c.JS_ThrowTypeError(engine.context, "Native legacy function: %s", @as([*:0]const u8, @errorName(err)));
}
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const owned: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    std.debug.assert(owned.active == null);
    c.JS_FreeValueRT(runtime, owned.properties);
    c.JS_FreeAtomRT(runtime, owned.arguments_atom);
    c.JS_FreeAtomRT(runtime, owned.caller_atom);
    for (owned.values) |item| c.JS_FreeValueRT(runtime, item);
    owned.engine.gpa.free(owned.values);
    owned.engine.gpa.destroy(owned);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const owned: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, owned.properties, marker);
    for (owned.values) |item| c.JS_MarkValue(runtime, item, marker);
    var active = owned.active;
    while (active) |frame| : (active = frame.previous_same) {
        c.JS_MarkValue(runtime, frame.function, marker);
        c.JS_MarkValue(runtime, frame.caller, marker);
        for (frame.arguments) |argument| c.JS_MarkValue(runtime, argument, marker);
    }
}
fn names(context: ?*c.JSContext, table: [*c][*c]c.JSPropertyEnum, length: [*c]u32, value: c.JSValue) callconv(.c) c_int {
    return c.JS_GetOwnPropertyNames(context, table, length, state(value).properties, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK);
}
fn descriptor(context: ?*c.JSContext, output: [*c]c.JSPropertyDescriptor, value: c.JSValue, atom: c.JSAtom) callconv(.c) c_int {
    const owned = state(value);
    const found = c.JS_GetOwnProperty(context, output, owned.properties, atom);
    if (found != 1 or output == null) return found;
    if (atom != owned.arguments_atom and atom != owned.caller_atom) return found;
    owned.engine.freeValue(output.*.value);
    output.*.value = if (owned.active) |active| if (atom == owned.caller_atom)
        c.JS_DupValue(context, active.caller)
    else
        owned.engine.checked(c.JS_PiUnmappedArguments(context, @intCast(active.arguments.len), active.arguments.ptr)) catch |err| {
            _ = fail(owned.engine, err);
            output.*.value = c.pi_js_undefined();
            return -1;
        } else c.pi_js_null();
    return found;
}
fn define(context: ?*c.JSContext, value: c.JSValue, atom: c.JSAtom, field: c.JSValue, getter: c.JSValue, setter: c.JSValue, flags: c_int) callconv(.c) c_int {
    const owned = state(value);
    const properties = owned.properties;
    if (owned.active != null and (atom == owned.arguments_atom or atom == owned.caller_atom)) {
        // Use the VM's ordinary descriptor validator with the live virtual
        // value. Never write a caller/Arguments snapshot into the inactive table.
        const temporary = c.JS_NewObjectProto(context, c.pi_js_null());
        if (c.JS_IsException(temporary)) return -1;
        defer owned.engine.freeValue(temporary);
        var current: c.JSPropertyDescriptor = undefined;
        if (descriptor(context, &current, value, atom) != 1) return -1;
        defer owned.engine.freeValue(current.getter);
        defer owned.engine.freeValue(current.setter);
        if (c.JS_DefinePropertyValue(context, temporary, atom, current.value, current.flags) < 0) return -1;
        return c.JS_DefineProperty(context, temporary, atom, field, getter, setter, flags);
    }
    const extensible = c.JS_IsExtensible(context, value);
    if (extensible < 0) return -1;
    if (extensible == 0) {
        const present = c.JS_GetOwnProperty(context, null, properties, atom);
        if (present < 0) return -1;
        if (present == 0) {
            if (flags & c.JS_PROP_THROW != 0) {
                _ = c.JS_ThrowTypeError(context, "Cannot define property on a non-extensible native legacy function");
                return -1;
            }
            return 0;
        }
    }
    // The ordinary table enforces the actual writable/configurable descriptors.
    return c.JS_DefineProperty(context, properties, atom, field, getter, setter, flags);
}
fn remove(context: ?*c.JSContext, value: c.JSValue, atom: c.JSAtom) callconv(.c) c_int {
    return c.JS_DeleteProperty(context, state(value).properties, atom, 0);
}
const exotic: c.JSClassExoticMethods = .{ .get_own_property = descriptor, .get_own_property_names = names, .define_own_property = define, .delete_property = remove };
fn call(_: ?*c.JSContext, function: c.JSValue, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const owned = state(function);
    return invoke(owned, function, target, if (argc > 0) argv[0..@intCast(argc)] else &.{}, flags & c.JS_CALL_FLAG_CONSTRUCTOR != 0) catch |err| fail(owned.engine, err);
}
fn invoke(owned: *State, function: c.JSValue, target: c.JSValue, args: []const c.JSValue, constructing: bool) !c.JSValue {
    const engine = owned.engine;
    const arguments = try engine.gpa.alloc(c.JSValue, args.len);
    defer engine.gpa.free(arguments);
    for (arguments, args) |*slot, argument| slot.* = c.JS_DupValue(engine.context, argument);
    defer for (arguments) |argument| engine.freeValue(argument);
    const retained_function = c.JS_DupValue(engine.context, function);
    defer engine.freeValue(retained_function);
    // Ordinary construction resolves newTarget.prototype before entering the
    // callee. An already active outer invocation stays visible during lookup.
    const receiver = if (constructing)
        try @import("native_class.zig").object(engine, target)
    else if (c.JS_IsNull(target) or c.JS_IsUndefined(target))
        c.JS_GetGlobalObject(engine.context)
    else
        try engine.checked(c.JS_ToObject(engine.context, target));
    defer engine.freeValue(receiver);
    var identity: usize = 0;
    var caller = try engine.checked(c.JS_PiObserveCallFrame(engine.context, &identity));
    if (logical_frame) |previous| {
        if (previous.engine == engine and previous.identity == identity) {
            engine.freeValue(caller);
            caller = c.JS_DupValue(engine.context, previous.function);
        }
    }
    defer engine.freeValue(caller);
    var frame: Frame = .{ .engine = engine, .function = c.JS_DupValue(engine.context, function), .arguments = arguments, .caller = caller, .identity = identity, .previous_same = owned.active };
    defer engine.freeValue(frame.function);
    const previous_logical = logical_frame;
    const previous_same = owned.active;
    logical_frame = &frame;
    owned.active = &frame;
    defer {
        owned.active = previous_same;
        logical_frame = previous_logical;
    }
    const returned = try owned.callback(engine, receiver, args, owned.values);
    if (!constructing or c.JS_IsObject(returned)) return returned;
    engine.freeValue(returned);
    return c.JS_DupValue(engine.context, receiver);
}
pub fn create(engine: *Engine, name: [*:0]const u8, length: c_int, body: Callback, values: []const c.JSValue) !c.JSValue {
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Native CJS Legacy Function", .call = call, .finalizer = finalizer, .gc_mark = mark, .exotic = @constCast(&exotic) };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const prototype = try engine.checked(c.JS_GetFunctionProto(engine.context));
    defer engine.freeValue(prototype);
    const function = try engine.checked(c.JS_NewObjectProtoClass(engine.context, prototype, class));
    var attached = false;
    errdefer engine.freeValue(function);
    const properties = try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()));
    errdefer if (!attached) engine.freeValue(properties);
    const arguments_atom = c.JS_NewAtom(engine.context, "arguments");
    if (arguments_atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    errdefer if (!attached) c.JS_FreeAtom(engine.context, arguments_atom);
    const caller_atom = c.JS_NewAtom(engine.context, "caller");
    if (caller_atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    errdefer if (!attached) c.JS_FreeAtom(engine.context, caller_atom);
    const captured = try engine.gpa.alloc(c.JSValue, values.len);
    errdefer if (!attached) engine.gpa.free(captured);
    const owned = try engine.gpa.create(State);
    for (captured, values) |*slot, value| slot.* = c.JS_DupValue(engine.context, value);
    owned.* = .{ .engine = engine, .callback = body, .values = captured, .properties = properties, .arguments_atom = arguments_atom, .caller_atom = caller_atom };
    _ = c.JS_SetOpaque(function, owned);
    attached = true;
    _ = c.JS_SetConstructorBit(engine.context, function, true);
    if (c.JS_DefinePropertyValueStr(engine.context, properties, "length", c.JS_NewInt32(engine.context, length), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, properties, "name", try engine.checked(c.JS_NewString(engine.context, name)), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValue(engine.context, properties, arguments_atom, c.pi_js_null(), 0) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValue(engine.context, properties, caller_atom, c.pi_js_null(), 0) < 0) return js.capture(engine);
    const instance_prototype = try js.object(engine);
    defer engine.freeValue(instance_prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, instance_prototype, "constructor", c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, properties, "prototype", c.JS_DupValue(engine.context, instance_prototype), c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    return function;
}
