//! Native execution primitives for statically lowered TypeBox declarations.
//! No source parser, JavaScript evaluator, dynamic source or checker body runs.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
pub const Scope = v.Scope;
pub const c = v.c;
pub const Engine = v.em.Engine;
pub const Callback = @import("native_node_function.zig").Callback;
pub fn environment(scope: *Scope, parent: c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, parent)));
}
pub fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
pub fn bind(scope: *Scope, env: c.JSValue, name: [:0]const u8, value: c.JSValue) !void {
    try scope.put(env, name, value);
}
/// Module lexical declarations exist before evaluation but cannot be read
/// until their original initializer executes. The marker is private to the
/// native lexical environment and is inherited by captured function frames.
pub fn declare(scope: *Scope, env: c.JSValue, name: [:0]const u8) !void {
    var marker = try scope.get(env, "@typebox_uninitialized");
    if (!c.JS_IsObject(marker)) {
        marker = try scope.object();
        try scope.put(env, "@typebox_uninitialized", marker);
    }
    try scope.put(env, name, marker);
}
pub fn get(scope: *Scope, env: c.JSValue, name: [:0]const u8) !c.JSValue {
    if (try v.js.hasKey(scope.engine, env, try scope.text(name))) {
        const value = try scope.get(env, name);
        const marker = try scope.get(env, "@typebox_uninitialized");
        if (c.JS_IsObject(marker) and scope.equal(value, marker)) {
            const start = if (std.mem.indexOfScalar(u8, name, '_')) |index| index + 1 else 0;
            const original = try scope.engine.gpa.dupeZ(u8, name[start..]);
            defer scope.engine.gpa.free(original);
            _ = c.JS_ThrowReferenceError(scope.engine.context, "Cannot access '%s' before initialization", original.ptr);
            return v.js.capture(scope.engine);
        }
        return value;
    }
    return scope.global(name);
}
fn ownKey(scope: *Scope, object: c.JSValue, atom_key: c.JSAtom) !bool {
    var descriptor: c.JSPropertyDescriptor = undefined;
    const found = c.JS_GetOwnProperty(scope.engine.context, &descriptor, object, atom_key);
    if (found < 0) return v.js.capture(scope.engine);
    if (found != 0) {
        scope.engine.freeValue(descriptor.value);
        scope.engine.freeValue(descriptor.getter);
        scope.engine.freeValue(descriptor.setter);
    }
    return found != 0;
}
pub fn assign(scope: *Scope, env: c.JSValue, name: [:0]const u8, value: c.JSValue) !void {
    const atom = try v.js.atom(scope.engine, try scope.text(name));
    defer c.JS_FreeAtom(scope.engine.context, atom);
    var current = env;
    while (c.JS_IsObject(current)) {
        if (try ownKey(scope, current, atom)) {
            // Assignment cannot initialize an existing lexical TDZ binding.
            // Only the original declaration's bind operation initializes it.
            _ = try get(scope, current, name);
            if (c.JS_SetProperty(scope.engine.context, current, atom, c.JS_DupValue(scope.engine.context, value)) < 0) return v.js.capture(scope.engine);
            return;
        }
        current = try scope.own(try scope.engine.checked(c.JS_GetPrototype(scope.engine.context, current)));
    }
    return v.js.typeError(scope.engine, "Unbound compiled TypeBox lexical assignment");
}
pub fn key(scope: *Scope, object: c.JSValue, property_key: c.JSValue) !c.JSValue {
    return scope.own(try v.js.getKey(scope.engine, object, property_key));
}
pub fn propertyKey(scope: *Scope, value: c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_ToPropertyKey(scope.engine.context, value)));
}
pub fn property(scope: *Scope, object: c.JSValue, property_key: c.JSValue, value: c.JSValue) !void {
    const atom = try v.js.atom(scope.engine, property_key);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DefinePropertyValue(scope.engine.context, object, atom, c.JS_DupValue(scope.engine.context, value), c.JS_PROP_C_W_E) < 0) return v.js.capture(scope.engine);
}
pub fn set(scope: *Scope, object: c.JSValue, property_key: c.JSValue, value: c.JSValue) !void {
    try v.js.setKey(scope.engine, object, property_key, value);
}
pub fn function(scope: *Scope, name: [:0]const u8, length: c_int, callback: Callback, env: c.JSValue, receiver: c.JSValue, arrow: bool) !c.JSValue {
    const roots = [_]c.JSValue{ env, receiver };
    return scope.own(if (arrow)
        try @import("native_node_function.zig").createArrow(scope.engine, name, length, callback, &roots)
    else
        try @import("native_node_function.zig").create(scope.engine, name, length, callback, &roots));
}
pub const Continuation = @import("native_typebox_continuation.zig");
pub fn plannedFunction(scope: *Scope, name: [:0]const u8, length: c_int, callback: Callback, env: c.JSValue, receiver: c.JSValue, arrow: bool, plan: *const Continuation.Plan) !c.JSValue {
    const roots = [_]c.JSValue{ env, receiver };
    return scope.own(try @import("native_node_function.zig").createPlanned(scope.engine, name, length, callback, &roots, arrow, plan));
}
pub fn rest(scope: *Scope, args: []const c.JSValue, start: usize) !c.JSValue {
    const result = try scope.array();
    if (start < args.len) for (args[start..], 0..) |value, index| try scope.index(result, @intCast(index), value);
    return result;
}
pub fn append(scope: *Scope, array: c.JSValue, value: c.JSValue) !void {
    try scope.index(array, try v.length(scope, array), value);
}
pub fn spreadArray(scope: *Scope, array: c.JSValue, value: c.JSValue) !void {
    var cursor = try v.iterator(scope, value);
    defer cursor.deinit();
    errdefer cursor.closePreserving();
    while (try cursor.next()) |item| {
        defer scope.engine.freeValue(item);
        try append(scope, array, item);
    }
}
pub fn spreadObject(scope: *Scope, object: c.JSValue, value: c.JSValue) !void {
    try v.js.spreadInto(scope.engine, object, value);
}
pub fn invoke(scope: *Scope, callable: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_Call(scope.engine.context, callable, receiver, @intCast(args.len), @constCast(args.ptr))));
}
pub fn invokeSpread(scope: *Scope, callable: c.JSValue, receiver: c.JSValue, array: c.JSValue) !c.JSValue {
    const count = try v.length(scope, array);
    const args = try scope.engine.gpa.alloc(c.JSValue, count);
    defer scope.engine.gpa.free(args);
    for (args, 0..) |*slot, index| slot.* = try v.at(scope, array, @intCast(index));
    return invoke(scope, callable, receiver, args);
}
pub fn construct(scope: *Scope, callable: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, callable, @intCast(args.len), @constCast(args.ptr))));
}
pub fn regexp(scope: *Scope, pattern: []const u8, flags: []const u8) !c.JSValue {
    return construct(scope, scope.engine.intrinsic_regexp_constructor, &.{ try scope.text(pattern), try scope.text(flags) });
}
pub fn binary(scope: *Scope, operation: []const u8, left: c.JSValue, right: c.JSValue) !c.JSValue {
    inline for (.{ .{ "+", 0 }, .{ "-", 1 }, .{ "*", 2 }, .{ "/", 3 }, .{ "<", 4 }, .{ "<=", 5 }, .{ ">", 6 }, .{ ">=", 7 }, .{ "%", 8 }, .{ "**", 9 }, .{ "&", 10 }, .{ "|", 11 }, .{ "<<", 12 }, .{ ">>", 13 } }) |entry| {
        if (std.mem.eql(u8, operation, entry[0])) return scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, entry[1], left, right)));
    }
    if (std.mem.eql(u8, operation, "===")) return c.pi_js_bool(scope.engine.context, @intFromBool(c.JS_IsStrictEqual(scope.engine.context, left, right)));
    if (std.mem.eql(u8, operation, "!==")) return c.pi_js_bool(scope.engine.context, @intFromBool(!c.JS_IsStrictEqual(scope.engine.context, left, right)));
    if (std.mem.eql(u8, operation, "in")) return c.pi_js_bool(scope.engine.context, @intFromBool(try v.js.hasKey(scope.engine, right, left)));
    if (std.mem.eql(u8, operation, "instanceof")) {
        const result = c.JS_IsInstanceOf(scope.engine.context, left, right);
        if (result < 0) return v.js.capture(scope.engine);
        return c.pi_js_bool(scope.engine.context, @intFromBool(result != 0));
    }
    return error.InvalidCompiledTypeBoxBinaryOperation;
}
pub fn unary(scope: *Scope, operation: []const u8, value: c.JSValue) !c.JSValue {
    if (std.mem.eql(u8, operation, "!")) return c.pi_js_bool(scope.engine.context, @intFromBool(!scope.truthy(value)));
    if (std.mem.eql(u8, operation, "typeof")) return scope.text(if (c.JS_IsUndefined(value)) "undefined" else if (c.JS_IsNull(value)) "object" else if (c.JS_IsBool(value)) "boolean" else if (c.JS_IsNumber(value)) "number" else if (c.JS_IsBigInt(value)) "bigint" else if (c.JS_IsString(value)) "string" else if (c.JS_IsSymbol(value)) "symbol" else if (c.JS_IsFunction(scope.engine.context, value)) "function" else "object");
    return error.InvalidCompiledTypeBoxUnaryOperation;
}
pub fn update(scope: *Scope, value: c.JSValue, increment: bool) !c.JSValue {
    return scope.own(try scope.engine.checked(if (increment) c.JS_PiIncrement(scope.engine.context, value) else c.JS_PiDecrement(scope.engine.context, value)));
}
pub fn throwValue(scope: *Scope, value: c.JSValue) anyerror {
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, value))) catch |err| return err;
    unreachable;
}
pub fn defaulted(value: c.JSValue) bool {
    return c.JS_IsUndefined(value);
}
pub fn nullish(value: c.JSValue) bool {
    return c.JS_IsUndefined(value) or c.JS_IsNull(value);
}
pub fn iterator(scope: *Scope, value: c.JSValue) !v.js.Iterator {
    return v.iterator(scope, value);
}
pub fn iteratorValue(scope: *Scope, value: *v.js.Iterator) !c.JSValue {
    return if (value.closed) c.pi_js_undefined() else scope.own((try value.next()) orelse c.pi_js_undefined());
}
pub fn iteratorRest(scope: *Scope, value: *v.js.Iterator) !c.JSValue {
    const result = try scope.array();
    while (!value.closed) {
        const item = (try value.next()) orelse break;
        defer scope.engine.freeValue(item);
        try append(scope, result, item);
    }
    return result;
}
pub fn evaluation(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var operation: u32 = undefined;
    if (c.JS_ToUint32(engine.context, &operation, roots[1]) < 0) return v.js.capture(engine);
    const algebra = @import("native_typebox_partial_evaluate.zig");
    const graph = roots[0];
    const result = switch (operation) {
        0 => try algebra.template(&scope, graph, argument(args, 0)),
        1 => try algebra.enumeration(&scope, graph, argument(args, 0), if (defaulted(argument(args, 1))) try scope.array() else argument(args, 1)),
        2 => try algebra.intersection(&scope, graph, argument(args, 0)),
        3 => try algebra.evaluate(&scope, graph, argument(args, 0)),
        4 => try algebra.unionValue(&scope, graph, argument(args, 0)),
        5 => try algebra.dependent(&scope, graph, argument(args, 0), argument(args, 1), argument(args, 2)),
        6 => try algebra.fastUnion(&scope, graph, argument(args, 0)),
        else => return error.InvalidCompiledTypeBoxEvaluationBinding,
    };
    return c.JS_DupValue(engine.context, result);
}
pub fn evaluationBinding(scope: *Scope, graph: c.JSValue, name: [:0]const u8, operation: u32, length: c_int) !c.JSValue {
    return scope.own(try @import("native_node_function.zig").create(scope.engine, name, length, evaluation, &.{ graph, c.JS_NewUint32(scope.engine.context, operation) }));
}
