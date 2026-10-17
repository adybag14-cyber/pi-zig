//! Local genuine construct-only Node error classes. No shared class/Engine
//! rewrite; native callable roots charged/traced and fresh errors propagated.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const f = @import("native_node_module_callable.zig");
const h = @import("native_node_tty_values.zig");
pub const Construct = *const fn (*v.em.Engine, c.JSValue, c.JSValue, []const c.JSValue, []const c.JSValue) anyerror!c.JSValue;
const State = struct { engine: *v.em.Engine, name: [*:0]const u8, construct: Construct, roots: []c.JSValue, charge: usize };
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for (self.roots) |root| c.JS_FreeValueRT(runtime, root);
    const engine = self.engine; const charge = self.charge;
    engine.gpa.free(self.roots); engine.gpa.destroy(self);
    c.pi_js_native_memory_release(engine.native_memory_owner, charge);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visitor: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for (self.roots) |root| c.JS_MarkValue(runtime, root, visitor);
}
fn call(_: ?*c.JSContext, function: c.JSValue, new_target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)).?));
    const engine = self.engine;
    const generation = engine.native_allocation_generation;
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    h.pending(engine) catch |err| return f.failure(engine, err, generation);
    if (flags & c.JS_CALL_FLAG_CONSTRUCTOR == 0) return c.JS_ThrowTypeError(engine.context, "Class constructor %s cannot be invoked without 'new'", self.name);
    const value = self.construct(engine, function, new_target, if (argc > 0) argv[0..@intCast(argc)] else &.{}, self.roots) catch |err| return f.failure(engine, err, generation);
    return h.success(engine, value) catch |err| f.failure(engine, err, generation);
}
fn define(engine: *v.em.Engine, target: c.JSValue, name: [*:0]const u8, value: c.JSValue, flags: c_int) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, target, name, c.JS_DupValue(engine.context, value), flags | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
}
pub fn create(engine: *v.em.Engine, name: [*:0]const u8, length: c_int, prototype: c.JSValue, base: c.JSValue, construct: Construct, roots: []const c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try h.pending(engine);
    const bytes = std.math.mul(usize, roots.len, @sizeOf(c.JSValue)) catch return error.OutOfMemory;
    const charge = std.math.add(usize, @sizeOf(State), bytes) catch return error.OutOfMemory;
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, charge) == 0) return error.OutOfMemory;
    var attached = false;
    errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, charge);
    const state = try engine.gpa.create(State); errdefer if (!attached) engine.gpa.destroy(state);
    const retained = try engine.gpa.alloc(c.JSValue, roots.len); errdefer if (!attached) engine.gpa.free(retained);
    var id: c.JSClassID = 0;
    if (c.JS_NewClassID(engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Native Node Error Class", .call = call, .finalizer = finalize, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    // Genuine intrinsic FunctionProto, not live global Function.prototype.
    const function_prototype = try engine.checked(c.JS_GetFunctionProto(engine.context)); defer engine.freeValue(function_prototype);
    const function = try engine.checked(c.JS_NewObjectProtoClass(engine.context, function_prototype, id)); errdefer engine.freeValue(function);
    for (roots, retained) |root, *slot| slot.* = c.JS_DupValue(engine.context, root);
    state.* = .{ .engine = engine, .name = name, .construct = construct, .roots = retained, .charge = charge };
    _ = c.JS_SetOpaque(function, state); attached = true;
    _ = c.JS_SetConstructorBit(engine.context, function, true);
    if (c.JS_SetPrototype(engine.context, function, base) < 0) return v.js.capture(engine);
    const text = try engine.checked(c.JS_NewString(engine.context, name)); defer engine.freeValue(text);
    try define(engine, function, "name", text, c.JS_PROP_CONFIGURABLE);
    try define(engine, function, "length", c.JS_NewInt32(engine.context, length), c.JS_PROP_CONFIGURABLE);
    try define(engine, function, "prototype", prototype, 0);
    try define(engine, prototype, "constructor", function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    return function;
}
/// Source super() resolves the DECLARED class's current [[Prototype]], while
/// passing the actual derived new.target through to the genuine base class.
pub fn superConstruct(s: *v.Scope, lexical_class: c.JSValue, new_target: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const base = try s.own(try h.success(s.engine, try s.engine.checked(c.JS_GetPrototype(s.engine.context, lexical_class))));
    return s.own(try h.success(s.engine, try s.engine.checked(c.JS_CallConstructor2(s.engine.context, base, new_target, @intCast(args.len), @constCast(args.ptr)))));
}
