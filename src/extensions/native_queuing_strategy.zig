//! The actual Node24 queuing-strategy classes. No substitute stream queues.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const c = em.c;
const key = "pi-native:queuing-strategies";
const State = struct { engine: *em.Engine, high_water_mark: f64, size: c.JSValue };
const Op = enum(c_int) { high_water_mark, size, byte_size, count_size };
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, self.size);
    self.engine.gpa.destroy(self);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, self.size, visit);
}
fn classId(engine: *em.Engine, owner: c.JSValue) !c.JSClassID {
    const value = try js.get(engine, owner, "class");
    defer engine.freeValue(value);
    var result: u32 = 0;
    if (c.JS_ToUint32(engine.context, &result, value) < 0) return js.capture(engine);
    return result;
}
fn throwTypeError(scope: *Scope, owner: c.JSValue, message: []const u8, code: []const u8) anyerror {
    var args = [_]c.JSValue{try scope.text(message)};
    const exception = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(owner, "TypeError"), args.len, &args)));
    try scope.put(exception, "code", try scope.text(code));
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, exception))) catch |err| return err;
    unreachable;
}
fn construct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const init = if (args.len == 0) c.pi_js_undefined() else args[0];
    if (!c.JS_IsObject(init) or c.JS_IsArray(init) or c.JS_IsFunction(engine.context, init)) {
        const received = try @import("native_transform_stream.zig").receivedDescription(engine, init);
        defer engine.gpa.free(received);
        const message = try std.fmt.allocPrint(engine.gpa, "The \"init\" argument must be of type object. Received {s}", .{received});
        defer engine.gpa.free(message);
        return throwTypeError(&scope, roots[0], message, "ERR_INVALID_ARG_TYPE");
    }
    const first = try scope.get(init, "highWaterMark");
    if (c.JS_IsUndefined(first)) {
        return throwTypeError(&scope, roots[0], "The \"init.highWaterMark\" option is required", "ERR_MISSING_OPTION");
    }
    // Node intentionally reads this getter twice and applies unary plus, which
    // rejects BigInt and Symbol and delays range validation until stream use.
    const raw = try scope.get(init, "highWaterMark");
    var number: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &number, raw) < 0) return js.capture(engine);
    const prototype = try scope.get(target, "prototype");
    const fallback = try scope.get(roots[0], "prototype");
    const object = try scope.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, if (c.JS_IsObject(prototype)) prototype else fallback, try classId(engine, roots[0]))));
    const size = try scope.get(roots[0], "size");
    const self = try engine.gpa.create(State);
    self.* = .{ .engine = engine, .high_water_mark = number, .size = c.JS_DupValue(engine.context, size) };
    _ = c.JS_SetOpaque(object, self);
    return c.JS_DupValue(engine.context, object);
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return invoke(engine, receiver, if (argc == 0) &.{} else argv[0..@intCast(argc)], @enumFromInt(magic), roots[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn invoke(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, op: Op, owner: c.JSValue) !c.JSValue {
    if (op == .count_size) return c.JS_NewInt32(engine.context, 1);
    if (op == .byte_size) return js.get(engine, if (args.len == 0) c.pi_js_undefined() else args[0], "byteLength");
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(receiver, try classId(engine, owner)) orelse return js.typeError(engine, "Cannot read private member from an object whose class did not declare it")));
    return if (op == .high_water_mark) c.JS_NewFloat64(engine.context, self.high_water_mark) else c.JS_DupValue(engine.context, self.size);
}
fn callback(scope: *Scope, owner: c.JSValue, op: Op, name: [*:0]const u8, length: c_int) !c.JSValue {
    var roots = [_]c.JSValue{owner};
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, dispatch, name, length, @intFromEnum(op), roots.len, &roots)));
}
pub fn exports(engine: *em.Engine) !c.JSValue {
    try install(engine);
    return c.JS_DupValue(engine.context, engine.native_module_values.get(key).?);
}
pub fn install(engine: *em.Engine) !void {
    if (engine.native_module_values.contains(key)) return;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    inline for (.{ "ByteLengthQueuingStrategy", "CountQueuingStrategy" }, .{ Op.byte_size, Op.count_size }, .{ 1, 0 }) |name, size_op, size_length| {
        var id: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &id);
        const definition: c.JSClassDef = .{ .class_name = name, .finalizer = finalize, .gc_mark = mark };
        if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
        const owner = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
        const prototype = try scope.object();
        try scope.put(owner, "class", c.JS_NewUint32(engine.context, id));
        try scope.put(owner, "prototype", prototype);
        try scope.put(owner, "TypeError", try scope.global("TypeError"));
        try scope.put(owner, "size", try callback(&scope, owner, size_op, "size", size_length));
        const constructor = try scope.own(try @import("native_class.zig").constructor(engine, name, 1, prototype, construct, &.{owner}));
        inline for (.{ "highWaterMark", "size" }, .{ Op.high_water_mark, Op.size }) |property, op| {
            const atom = c.JS_NewAtom(engine.context, property);
            if (atom == c.JS_ATOM_NULL) return js.capture(engine);
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, c.JS_DupValue(engine.context, try callback(&scope, owner, op, "get " ++ property, 0)), c.pi_js_undefined(), c.JS_PROP_ENUMERABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
        }
        const tag = try js.atom(engine, try scope.get(try scope.global("Symbol"), "toStringTag"));
        defer c.JS_FreeAtom(engine.context, tag);
        if (c.JS_DefinePropertyValue(engine.context, prototype, tag, c.JS_DupValue(engine.context, try scope.text(name)), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
        try scope.put(result, name, constructor);
        if (c.JS_DefinePropertyValueStr(engine.context, global, name, c.JS_DupValue(engine.context, constructor), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    try engine.registerValueModule(key, result);
}
