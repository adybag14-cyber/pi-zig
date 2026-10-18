//! Local genuine construct-only Node error classes. No shared class/Engine
//! rewrite; native callable roots charged/traced and fresh errors propagated.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const f = @import("native_node_module_callable.zig");
const Scope = @import("native_node_operation_scope.zig").Scope;
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
    var s = Scope.init(self.engine);
    return s.finish(invoke(&s, self, function, new_target, if (argc > 0) argv[0..@intCast(argc)] else &.{}, flags)) catch |err| f.failure(self.engine, err, 0);
}
fn invoke(s: *Scope, self: *State, function: c.JSValue, target: c.JSValue, args: []const c.JSValue, flags: c_int) !c.JSValue {
    try s.pending();
    try s.engine.checkNativeEntry();
    if (flags & c.JS_CALL_FLAG_CONSTRUCTOR == 0) {
        const generation = try s.beforeAllocation();
        return s.checkedAllocation(c.JS_ThrowTypeError(s.engine.context, "Class constructor %s cannot be invoked without 'new'", self.name), generation);
    }
    var result = try self.construct(s.engine, function, target, args, self.roots);
    s.pending() catch |err| { s.boundary.release(&result); return err; };
    if (c.JS_IsException(result)) return error.MissingActualNodeClassCallbackReason;
    return result;
}
pub fn create(engine: *v.em.Engine, name: [*:0]const u8, length: c_int, prototype: c.JSValue, base: c.JSValue, construct: Construct, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    return s.finish(createBody(&s, name, length, prototype, base, construct, roots));
}
fn createBody(s: *Scope, name: [*:0]const u8, length: c_int, prototype: c.JSValue, base: c.JSValue, construct: Construct, roots: []const c.JSValue) !c.JSValue {
    const engine = s.engine;
    try s.pending();
    var id: c.JSClassID = 0;
    if (c.JS_NewClassID(engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Native Node Error Class", .call = call, .finalizer = finalize, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    // Intrinsic FunctionProto plus a direct native allocation. No global
    // Function getter and no guest-capable generation interval.
    const function_prototype = try s.checked(c.JS_GetFunctionProto(engine.context));
    const generation = try s.beforeAllocation();
    const function = try s.checkedAllocation(c.JS_NewObjectProtoClass(engine.context, function_prototype, id), generation);
    const bytes = std.math.mul(usize, roots.len, @sizeOf(c.JSValue)) catch return error.OutOfMemory;
    const charge = std.math.add(usize, @sizeOf(State), bytes) catch return error.OutOfMemory;
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, charge) == 0) return error.OutOfMemory;
    var attached = false;
    errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, charge);
    const self = try engine.gpa.create(State);
    errdefer if (!attached) engine.gpa.destroy(self);
    const retained = try engine.gpa.alloc(c.JSValue, roots.len);
    errdefer if (!attached) engine.gpa.free(retained);
    for (roots, retained) |root, *slot| slot.* = c.JS_DupValue(engine.context, root);
    self.* = .{ .engine = engine, .name = name, .construct = construct, .roots = retained, .charge = charge };
    _ = c.JS_SetOpaque(function, self);
    attached = true;
    _ = c.JS_SetConstructorBit(engine.context, function, true);
    try s.pending();
    const status = c.JS_SetPrototype(engine.context, function, base);
    try s.pending();
    if (status < 0) return error.MissingActualNodeClassPrototypeReason;
    try s.define(function, "name", try s.text(std.mem.span(name)), c.JS_PROP_CONFIGURABLE);
    try s.define(function, "length", c.JS_NewInt32(engine.context, length), c.JS_PROP_CONFIGURABLE);
    try s.define(function, "prototype", prototype, 0);
    try s.define(prototype, "constructor", function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    return c.JS_DupValue(engine.context, function);
}
/// Source super() resolves the DECLARED class's current [[Prototype]], while
/// passing the actual derived new.target through to the genuine base class.
pub fn superConstruct(s: *v.Scope, lexical_class: c.JSValue, new_target: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var stage = Scope.init(s.engine);
    const result = try stage.finish(superBody(&stage, lexical_class, new_target, args));
    return @import("native_sdk_owned_completion.zig").ownRoot(s, result);
}
fn superBody(s: *Scope, lexical_class: c.JSValue, new_target: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const base = try s.prototype(lexical_class);
    try s.pending();
    const result = try s.checked(c.JS_CallConstructor2(s.engine.context, base, new_target, @intCast(args.len), @constCast(args.ptr)));
    return c.JS_DupValue(s.engine.context, result);
}

/// Source super(...rest) keeps the resolved lexical superclass through spread
/// evaluation, then uses the VM's real argument-list constructor operation.
pub fn superConstructSpread(s: *v.Scope, lexical_class: c.JSValue, new_target: c.JSValue, rest: c.JSValue) !c.JSValue {
    var stage = Scope.init(s.engine);
    const result = try stage.finish(superSpreadBody(&stage, lexical_class, new_target, rest));
    return @import("native_sdk_owned_completion.zig").ownRoot(s, result);
}
fn superSpreadBody(s: *Scope, lexical_class: c.JSValue, new_target: c.JSValue, rest: c.JSValue) !c.JSValue {
    const base = try s.prototype(lexical_class);
    const generation = try s.beforeAllocation();
    const arguments = try s.checkedAllocation(c.JS_NewArray(s.engine.context), generation);
    var position: u32 = 0;
    try s.pending();
    const appended = c.JS_PiArrayAppend(s.engine.context, arguments, &position, rest);
    try s.pending();
    if (appended < 0) return error.MissingActualNodeSuperSpreadReason;
    try s.pending();
    const result = try s.checked(c.JS_PiCallConstructorArray(s.engine.context, base, new_target, arguments));
    return c.JS_DupValue(s.engine.context, result);
}
