//! Durable LineScanner's private state, backed by the native streaming scan algorithm.
const std = @import("std");
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const scan = @import("../durable/line_scan.zig");
const c = js.c;
const State = struct { engine: *js.Engine, scanner: scan.LineScanner };
fn finalize(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    self.engine.gpa.destroy(self);
}
fn invalid(engine: *js.Engine) anyerror {
    _ = c.JS_ThrowRangeError(engine.context, "Invalid line range");
    return js.capture(engine);
}
fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, constants: []const c.JSValue) !c.JSValue {
    var scope: h.Scope = .{ .engine = engine };
    defer scope.deinit();
    const start = h.arg(args, 0);
    const end = h.arg(args, 1);
    if (!try h.validInteger(&scope, start, false)) return invalid(engine);
    var start_number: f64 = undefined;
    if (c.JS_ToFloat64(engine.context, &start_number, start) < 0) return js.capture(engine);
    const actual_end = if (c.JS_IsUndefined(end)) c.JS_NewFloat64(engine.context, std.math.inf(f64)) else end;
    if (!scope.truthy(try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 6, actual_end, start))))) return invalid(engine);
    const infinity = scope.equal(actual_end, c.JS_NewFloat64(engine.context, std.math.inf(f64)));
    if (!infinity and !try h.validInteger(&scope, actual_end, false)) return invalid(engine);
    var end_number: f64 = undefined;
    if (!infinity and c.JS_ToFloat64(engine.context, &end_number, actual_end) < 0) return js.capture(engine);
    var class_id: u32 = undefined;
    if (c.JS_ToUint32(engine.context, &class_id, constants[0]) < 0) return js.capture(engine);
    const value = try scope.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, try scope.get(target, "prototype"), class_id)));
    const scanner = try scan.LineScanner.init(.{ .startLine = @intFromFloat(start_number), .endLine = if (infinity) null else @intFromFloat(end_number) });
    const state = try engine.gpa.create(State);
    state.* = .{ .engine = engine, .scanner = scanner };
    _ = c.JS_SetOpaque(value, state);
    return c.JS_DupValue(engine.context, value);
}
fn invoke(engine: *js.Engine, receiver: c.JSValue, args: []const c.JSValue, class_value: c.JSValue, method: c_int) !c.JSValue {
    var class_id: u32 = undefined;
    if (c.JS_ToUint32(engine.context, &class_id, class_value) < 0) return js.capture(engine);
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque2(engine.context, receiver, class_id) orelse return js.capture(engine)));
    if (method == 0) {
        var offset: usize = undefined;
        var length: usize = undefined;
        var element: usize = undefined;
        const backing = try engine.checked(c.JS_GetTypedArrayBuffer(engine.context, h.arg(args, 0), &offset, &length, &element));
        defer engine.freeValue(backing);
        var backing_length: usize = undefined;
        const bytes = c.JS_GetArrayBuffer(engine.context, &backing_length, backing);
        if (bytes == null or offset > backing_length or length > backing_length - offset) return error.InvalidTypedArray;
        try state.scanner.push(bytes[offset..][0..length]);
        return c.pi_js_undefined();
    }
    var scope: h.Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try state.scanner.finish();
    const object = try scope.object();
    inline for (std.meta.fields(scan.LineScan)) |field| try scope.put(object, field.name, c.JS_NewFloat64(engine.context, @floatFromInt(@field(result, field.name))));
    return c.JS_DupValue(engine.context, object);
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, method: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, data[0], method) catch |err| @import("native_durable.zig").reject(engine, err);
}
pub fn create(engine: *js.Engine) !c.JSValue {
    var id: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &id);
    const definition: c.JSClassDef = .{ .class_name = "LineScanner", .finalizer = finalize };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    var scope: h.Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.object();
    const class_value = c.JS_NewUint32(engine.context, id);
    const constructor = try scope.own(try @import("native_class.zig").constructor(engine, "LineScanner", 1, prototype, construct, &.{class_value}));
    var data = [_]c.JSValue{class_value};
    inline for (.{ .{ "push", 1, 0 }, .{ "finish", 0, 1 } }) |method| {
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, method[0], method[1], method[2], 1, &data));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, method[0], function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    return c.JS_DupValue(engine.context, constructor);
}
