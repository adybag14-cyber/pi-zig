//! Actual Chord ResourceImpl/ResourceFacade lifecycle, without partial Host activation.
const std = @import("std");
const js = @import("native_js_values.zig");
const values = @import("native_values.zig");
const durable = @import("native_durable.zig");
const host_values = @import("native_chord_host_values.zig");
const errors = @import("native_chord_errors.zig");
const Engine = js.Engine;
const c = js.c;
const State = struct { engine: *Engine, value: c.JSValue, resource: c.JSValue, host: c.JSValue };
const Method = enum(c_int) { value, exclusive, open, close, markUnavailable, facadeKey, facadeValue, adopt };
fn finalizer(runtime: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
    const owner: *State = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    inline for (.{ "value", "resource", "host" }) |name| c.JS_FreeValueRT(runtime, @field(owner, name));
    owner.engine.gpa.destroy(owner);
}
fn mark(runtime: ?*c.JSRuntime, object: c.JSValue, visitor: ?*const c.JS_MarkFunc) callconv(.c) void {
    const owner: *State = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
    inline for (.{ "value", "resource", "host" }) |name| c.JS_MarkValue(runtime, @field(owner, name), visitor);
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn state(engine: *Engine, object: c.JSValue, bindings: c.JSValue, facade: bool) !*State {
    const identifier = try js.get(engine, bindings, if (facade) "facadeId" else "resourceId");
    defer engine.freeValue(identifier);
    var class_id: u32 = undefined;
    if (c.JS_ToUint32(engine.context, &class_id, identifier) < 0) return js.capture(engine);
    return @ptrCast(@alignCast(c.JS_GetOpaque2(engine.context, object, class_id) orelse return js.capture(engine)));
}
fn equals(engine: *Engine, value: c.JSValue, text: []const u8) !bool {
    const string = try engine.checked(c.JS_NewStringLen(engine.context, text.ptr, text.len));
    defer engine.freeValue(string);
    return c.JS_IsStrictEqual(engine.context, value, string);
}
fn setState(engine: *Engine, object: c.JSValue, name: []const u8) !void {
    try values.put(engine, object, "state", try engine.checked(c.JS_NewStringLen(engine.context, name.ptr, name.len)));
}
fn failure(engine: *Engine, bindings: c.JSValue, object: c.JSValue, code: []const u8, suffix: []const u8) !c.JSValue {
    const key = try js.get(engine, object, "key");
    defer engine.freeValue(key);
    const label = try engine.toString(key);
    defer engine.gpa.free(label);
    const message = try std.fmt.allocPrint(engine.gpa, "resource {s}{s}", .{ label, suffix });
    defer engine.gpa.free(message);
    const constructor = try js.get(engine, bindings, "ChordError");
    defer engine.freeValue(constructor);
    const reason = try errors.create(engine, constructor, code, message, c.pi_js_undefined());
    return engine.checked(c.JS_Throw(engine.context, reason));
}
fn callback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const method: Method = @enumFromInt(operation);
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, method, data[0]) catch |err| {
        return if (method == .open or method == .close) durable.rejectedPromise(engine, err) else durable.reject(engine, err);
    };
}
fn optionalClose(engine: *Engine, receiver: c.JSValue, value: c.JSValue) !c.JSValue {
    const spec = try js.get(engine, receiver, "spec");
    defer engine.freeValue(spec);
    const function = try js.get(engine, spec, "close");
    defer engine.freeValue(function);
    if (c.JS_IsNull(function) or c.JS_IsUndefined(function)) return c.pi_js_undefined();
    return js.call(engine, function, spec, &.{value});
}
fn chain(engine: *Engine, _: c.JSValue, work: c.JSValue, awaited: c.JSValue, stage: c_int) !c.JSValue {
    return host_values.wait(resumeResource, engine, work, awaited, stage);
}
fn job(engine: *Engine, receiver: c.JSValue, bindings: c.JSValue, signal: c.JSValue, order: c.JSValue) !c.JSValue {
    const work = try js.object(engine);
    errdefer engine.freeValue(work);
    try js.define(engine, work, "resource", c.JS_DupValue(engine.context, receiver));
    try js.define(engine, work, "bindings", c.JS_DupValue(engine.context, bindings));
    try js.define(engine, work, "signal", c.JS_DupValue(engine.context, signal));
    try js.define(engine, work, "order", c.JS_DupValue(engine.context, order));
    return work;
}
fn invoke(engine: *Engine, receiver: c.JSValue, args: []const c.JSValue, method: Method, bindings: c.JSValue) anyerror!c.JSValue {
    if (method == .adopt) {
        if (c.JS_SetPropertyStr(engine.context, receiver, "spec", c.JS_DupValue(engine.context, arg(args, 0))) < 0) return js.capture(engine);
        return c.pi_js_undefined();
    }
    if (method == .exclusive) {
        const spec = try js.get(engine, receiver, "spec");
        defer engine.freeValue(spec);
        const exclusive = try js.get(engine, spec, "exclusive");
        defer engine.freeValue(exclusive);
        return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, exclusive, c.pi_js_bool(engine.context, 1))));
    }
    if (method == .facadeKey or method == .facadeValue) {
        const self = try state(engine, receiver, bindings, true);
        if (method == .facadeKey) return js.get(engine, self.resource, "key");
        const factory = try js.get(engine, self.host, "inFactory");
        defer engine.freeValue(factory);
        var count: f64 = undefined;
        if (c.JS_ToFloat64(engine.context, &count, factory) < 0) return js.capture(engine);
        if (count > 0) return failure(engine, bindings, receiver, "not_ready", " (inside a factory) is not ready");
        return js.get(engine, self.resource, "value");
    }
    if (method == .markUnavailable) {
        try setState(engine, receiver, "unavailable");
        const self = try state(engine, receiver, bindings, false);
        engine.freeValue(self.value);
        self.value = c.pi_js_undefined();
        return c.pi_js_undefined();
    }
    const current = try js.get(engine, receiver, "state");
    defer engine.freeValue(current);
    if (method == .value) {
        if (try equals(engine, current, "unavailable")) return failure(engine, bindings, receiver, "unavailable", " could not be restored");
        if (!try equals(engine, current, "open")) return failure(engine, bindings, receiver, "not_ready", " is not ready");
        return c.JS_DupValue(engine.context, (try state(engine, receiver, bindings, false)).value);
    }
    if (!try equals(engine, current, if (method == .open) "closed" else "open")) return durable.resolvedPromise(engine, c.pi_js_undefined());
    const work = try job(engine, receiver, bindings, if (method == .open) arg(args, 0) else c.pi_js_undefined(), arg(args, if (method == .open) 1 else 0));
    defer engine.freeValue(work);
    if (method == .open) {
        try setState(engine, receiver, "opening");
        const opened = openValue(engine, receiver, arg(args, 0)) catch |err| {
            try setState(engine, receiver, "closed");
            return err;
        };
        defer engine.freeValue(opened);
        return chain(engine, bindings, work, opened, 0);
    }
    try setState(engine, receiver, "closed");
    const index = try js.invoke(engine, arg(args, 0), "indexOf", &.{receiver});
    defer engine.freeValue(index);
    if (!c.JS_IsStrictEqual(engine.context, index, c.JS_NewInt32(engine.context, -1))) {
        const removed = try js.invoke(engine, arg(args, 0), "splice", &.{ index, c.JS_NewInt32(engine.context, 1) });
        engine.freeValue(removed);
    }
    const self = try state(engine, receiver, bindings, false);
    const value = self.value;
    self.value = c.pi_js_undefined();
    defer engine.freeValue(value);
    const closed = try optionalClose(engine, receiver, value);
    defer engine.freeValue(closed);
    return chain(engine, bindings, work, closed, 2);
}
fn openValue(engine: *Engine, receiver: c.JSValue, signal: c.JSValue) !c.JSValue {
    const spec = try js.get(engine, receiver, "spec");
    defer engine.freeValue(spec);
    const options = try js.object(engine);
    defer engine.freeValue(options);
    try js.define(engine, options, "signal", c.JS_DupValue(engine.context, signal));
    return js.invoke(engine, spec, "open", &.{options});
}
fn resumeResource(engine: *Engine, work: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) anyerror!c.JSValue {
    const receiver = try js.get(engine, work, "resource");
    defer engine.freeValue(receiver);
    const bindings = try js.get(engine, work, "bindings");
    defer engine.freeValue(bindings);
    if (rejected) {
        if (stage == 0) try setState(engine, receiver, "closed");
        return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    }
    if (stage == 2) return c.pi_js_undefined();
    if (stage == 1) return failure(engine, bindings, receiver, "aborted", " opened after abort");
    const signal = try js.get(engine, work, "signal");
    defer engine.freeValue(signal);
    const aborted = try js.get(engine, signal, "aborted");
    defer engine.freeValue(aborted);
    if (c.JS_ToBool(engine.context, aborted) > 0) {
        try setState(engine, receiver, "closed");
        const closed = try optionalClose(engine, receiver, value);
        defer engine.freeValue(closed);
        return chain(engine, bindings, work, closed, 1);
    }
    const self = try state(engine, receiver, bindings, false);
    engine.freeValue(self.value);
    self.value = c.JS_DupValue(engine.context, value);
    try setState(engine, receiver, "open");
    const order = try js.get(engine, work, "order");
    defer engine.freeValue(order);
    const ignored = try js.invoke(engine, order, "push", &.{receiver});
    engine.freeValue(ignored);
    return c.pi_js_undefined();
}
fn construct(engine: *Engine, target: c.JSValue, args: []const c.JSValue, data: []const c.JSValue) !c.JSValue {
    const facade = c.JS_ToBool(engine.context, data[1]) > 0;
    const identifier = try js.get(engine, data[0], if (facade) "facadeId" else "resourceId");
    defer engine.freeValue(identifier);
    var class_id: u32 = undefined;
    if (c.JS_ToUint32(engine.context, &class_id, identifier) < 0) return js.capture(engine);
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
    const self = try engine.gpa.create(State);
    self.* = .{ .engine = engine, .value = c.pi_js_undefined(), .resource = c.JS_DupValue(engine.context, if (facade) arg(args, 0) else c.pi_js_undefined()), .host = c.JS_DupValue(engine.context, if (facade) arg(args, 1) else c.pi_js_undefined()) };
    _ = c.JS_SetOpaque(object, self);
    if (!facade) {
        inline for (.{ "key", "spec", "deps" }, 0..) |name, index| try js.define(engine, object, name, c.JS_DupValue(engine.context, arg(args, index)));
        try js.define(engine, object, "state", try engine.checked(c.JS_NewString(engine.context, "closed")));
    }
    return object;
}
fn define(engine: *Engine, prototype: c.JSValue, bindings: c.JSValue, name: [*:0]const u8, method: Method, length: c_int, getter: bool) !void {
    var data = [_]c.JSValue{bindings};
    const function_name = if (getter) try std.fmt.allocPrintSentinel(engine.gpa, "get {s}", .{name}, 0) else try engine.gpa.dupeZ(u8, std.mem.span(name));
    defer engine.gpa.free(function_name);
    const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, function_name.ptr, length, @intFromEnum(method), 1, &data));
    defer engine.freeValue(function);
    if (method == .open or method == .close) {
        const async_prototype = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
        defer engine.freeValue(async_prototype);
        if (c.JS_SetPrototype(engine.context, function, async_prototype) < 0) return js.capture(engine);
    }
    if (getter) {
        const atom = c.JS_NewAtom(engine.context, name);
        defer c.JS_FreeAtom(engine.context, atom);
        if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, c.JS_DupValue(engine.context, function), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    } else if (c.JS_DefinePropertyValueStr(engine.context, prototype, name, c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
pub const Classes = struct {
    exports: c.JSValue,
    bindings: c.JSValue,
    pub fn deinit(self: *Classes, engine: *Engine) void {
        engine.freeValue(self.exports);
        engine.freeValue(self.bindings);
    }
};
/// Host owns the same concrete classes and their private facade identity map.
pub fn classes(engine: *Engine) !Classes {
    const result = try errors.exports(engine);
    errdefer engine.freeValue(result);
    const bindings = try js.object(engine);
    errdefer engine.freeValue(bindings);
    try js.define(engine, bindings, "ChordError", try js.get(engine, result, "ChordError"));
    inline for (.{ "ResourceImpl", "ResourceFacade" }, 0..) |name, index| {
        var class_id: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &class_id);
        const definition: c.JSClassDef = .{ .class_name = name, .finalizer = finalizer, .gc_mark = mark };
        if (c.JS_NewClass(engine.runtime, class_id, &definition) < 0) return error.OutOfMemory;
        try js.define(engine, bindings, if (index == 0) "resourceId" else "facadeId", c.JS_NewUint32(engine.context, class_id));
        const prototype = try js.object(engine);
        defer engine.freeValue(prototype);
        const constructor = try @import("native_class.zig").constructor(engine, name, if (index == 0) 3 else 2, prototype, construct, &.{ bindings, c.pi_js_bool(engine.context, @intCast(index)) });
        defer engine.freeValue(constructor);
        if (index == 0) {
            try define(engine, prototype, bindings, "value", .value, 0, true);
            try define(engine, prototype, bindings, "exclusive", .exclusive, 0, true);
            try define(engine, prototype, bindings, "open", .open, 2, false);
            try define(engine, prototype, bindings, "close", .close, 1, false);
            try define(engine, prototype, bindings, "markUnavailable", .markUnavailable, 0, false);
            try define(engine, prototype, bindings, "adopt", .adopt, 1, false);
        } else {
            try define(engine, prototype, bindings, "key", .facadeKey, 0, true);
            try define(engine, prototype, bindings, "value", .facadeValue, 0, true);
        }
        try js.define(engine, result, name, c.JS_DupValue(engine.context, constructor));
    }
    return .{ .exports = result, .bindings = bindings };
}
pub fn resourceOf(engine: *Engine, value: c.JSValue, bindings: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(value) or c.JS_IsFunction(engine.context, value)) return c.pi_js_undefined();
    const resource_identifier = try js.get(engine, bindings, "resourceId");
    defer engine.freeValue(resource_identifier);
    var resource_id: u32 = undefined;
    if (c.JS_ToUint32(engine.context, &resource_id, resource_identifier) < 0) return js.capture(engine);
    if (c.JS_GetOpaque(value, resource_id) != null) return c.JS_DupValue(engine.context, value);
    const identifier = try js.get(engine, bindings, "facadeId");
    defer engine.freeValue(identifier);
    var class_id: u32 = undefined;
    if (c.JS_ToUint32(engine.context, &class_id, identifier) < 0) return js.capture(engine);
    const owned: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, class_id) orelse return c.pi_js_undefined()));
    return c.JS_DupValue(engine.context, owned.resource);
}
pub fn exports(engine: *Engine) !c.JSValue {
    const created = try classes(engine);
    engine.freeValue(created.bindings);
    return created.exports;
}
